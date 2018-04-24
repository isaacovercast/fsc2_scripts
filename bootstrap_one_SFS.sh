#!/bin/bash
# sh doesn't know about range expansion on linux {1..3}

# Works on linux. "Should" work on mac, but untested. Won't even
# pretend to work on windows at this point.
# 2/7/15 iao

# Inputs
# Takes 2 optional flags
# -n <int>	: number of parameter estimation iterations
# -t		: Run in 'test' mode, sets number of iterations and number of
#				simulations to reasonable values so it runs quick

# Output
# This script generates an 'out' directory in cwd. Inside this directory
# it creates a folder for each time it is invoked. The folder is the working
# directory, and it is timestamped so multiple runs won't step on each other.
# Inside the working directory it creates a directory for each parameter
# estimation iteration, and a bootstrap directory with number folders
# for each bootstrap replicate.
#
# The working directory contains a file called Results.txt which is
# a concatenation of all parameter estimation interations sorted by
# estimated likelihood value.

# Created 2.7.14 by Isaac Overcast
# Based heavily on work by Xander Xue

###################################################################

# Update the script for new versions of fsc. Right now this
# script will only want to run the most recent version, if it doesn't
# find it it'll go out and grab it.
CUR_FSC_VRS=25221

###################################################################
# A couple utility functions
###################################################################

# print usage information, try to be helpful
usage() {
    echo "Usage: run_fsc_boot [-n <num_iterations>] [-p <file_prefix>] [-t] [-m] [-d]"
    echo "	  -d : Use unfolded sfs (and the *jointDAF.obs file name)"
    echo "	  -m : Do --multiSFS. This requires the *_MSFS.obs file format"
	echo "    -n <num_iterations> : how many parameter estimation iterations to run"
	echo "    -t : Run in TEST mode. Set values small so it runs quick."
	echo "	  -p <prefix> : The prefix for the .tpl, .est, and .obs files. If you don't give it a value it assumes 'input'"
}

# Locate the fsc binary and set the $FSC_BIN variable.
# First test $PATH, then test cwd, then dl if you can't find it.
# Die on failure, pointless to continue if you can't
# get fsc to run.
getfsc(){
	# TODO: this part might not work right.
	FSC_BIN=`which fsc$CUR_FSC_VRS`
	if [ $? == 0 ];
	then
		#Found fsc executable in $PATH
		echo $FSC_BIN
	else
		# fsc binary not in PATH. Look in CWD."
		`./fsc$CUR_FSC_VRS &> /dev/null`
	
		if [ $? == 1 ];
		then
			echo "Found fsc in CWD"
			FSC_BIN="$PWD/fsc$CUR_FSC_VRS"
			echo $FSC_BIN
		else
			echo "Fetching fsc2 executable...."
	
			OS_fingerprint=`uname`
			FSC_DL=""
			if [ $OS_fingerprint == "Linux" ];
			then
				echo "OS=linux"
				`wget http://cmpg.unibe.ch/software/fastsimcoal2/downloads/fsc_linux64.zip &> /dev/null`
				FSC_DL=fsc_linux64
			else
				echo "OS=Mac"
				`curl http://cmpg.unibe.ch/software/fastsimcoal2/downloads/fsc_mac64.zip > fsc_mac64.zip`
				FSC_DL=fsc_mac64
			fi
			
			# Extract the fsc binary, change mode to allow execution, and clean up the .zip file
			unzip -p $FSC_DL.zip $FSC_DL/fsc$CUR_FSC_VRS > fsc$CUR_FSC_VRS
			chmod 777 fsc$CUR_FSC_VRS
			rm -f fsc_*64.zip
			FSC_BIN="$PWD/fsc$CUR_FSC_VRS"
		fi
	fi
	
	if [ -s $FSC_BIN ];
	then
		echo "FSC executable: $FSC_BIN"
	else
		echo "No FSC binary. Error DL'ing. Contact your system administrator."
		exit
	fi
}


###################################################################
# Enter the main section of run_fsc.sh
###################################################################


# Set default options to sensible values
ITERATIONS=1
NSIMULATIONS=100000
NUM_PARAM_SETS=100
BOOTSTRAPS=5

# Set this variable to empty string. If the -m flag is passed in
# then this gets set to '--multiSFS'
DO_MULTI=""

# Default observed file type is jointMAFpop1_0
OBSERVED_FILE_TYPE="_jointMAFpop1_0.obs"
# Flag for doing folded vs unfolded sfs
# default value is -m to do unfolded sfs
FSC_FOLDING_FLAG="-m"

# Define output file names
OUTTMP="Results.unsorted.txt"
OUTPUT_LIKELIHOODS="Results.txt"

MAKE_BOOTSTRAP_SFS=false
# Read in the number of iterations from the command line
# This allows for short runs w/ simple parameter tweaking in advance
# of full blown runs.
while getopts bdmn:p:t flag; do
  case $flag in
	b)
		echo "Make Bootstrap SFS file and exit"
		MAKE_BOOTSTRAP_SFS=true
		;;
	d)
      echo "Do unfolded sfs (requires *jointDAF.obs)"
	  FSC_FOLDING_FLAG="-d"
	  OBSERVED_FILE_TYPE="_jointDAFpop1_0.obs"
	  ;;
	m)
	  echo "Do --multiSFS (requires *_MSFS.sfs format)"
	  DO_MULTI="--multiSFS"
	  OBSERVED_FILE_TYPE="_MSFS.obs"
	  ;;
    n)
      echo "Doing Iterations: $OPTARG";
      ITERATIONS=$OPTARG;
      ;;
	p)
	  echo "Using prefix: $OPTARG";
	  PREFIX=$OPTARG
	  ;;
	t) 
	  echo "Doing TEST run. Set defaults so it'll run quick."
	  NSIMULATIONS=10
	  ITERATIONS=5
	  NUM_PARAM_SETS=1
	  BOOTSTRAPS=5
	  ;;
    ?)
      usage;
      exit;
      ;;
  esac
done


# We wrap the $PREFIX in braces for the observed file because otherwise
# the shell things the underscore is doing something funny. The braces
# escape the underscore.
TEMPLATE_FILE="$PREFIX.tpl"
PARAM_FILE="$PREFIX.est"
OBSERVED_FILE="${PREFIX}${OBSERVED_FILE_TYPE}"
BOOTSTRAP_FILE="$PREFIX.par"
BOOTSTRAP_SFS_FILE="bootstrap${OBSERVED_FILE_TYPE}"


# Generate a timestamp in number of seconds since the epoch
# and make an outdir for the results. This allows for multiple
# runs without stepping on previous output/results. The
# timestamp can be reformatted for easier reading, or different
# prefix can be appended depending on run options, but thats a V2 thing.
TIMESTAMP=`date +"%s"`
mkdir -p out/${PREFIX}-$TIMESTAMP
OUTDIR=out/${PREFIX}-$TIMESTAMP
FSCDIR=`pwd`

echo "Using files: $TEMPLATE_FILE, $PARAM_FILE, $OBSERVED_FILE, $BOOTSTRAP_FILE, $BOOTSTRAP_SFS_FILE"

if [ ! -f $TEMPLATE_FILE ]; then
	echo "$TEMPLATE_FILE doesn't exist"
	exit
fi
if [ ! -f $PARAM_FILE ]; then
	echo "$PARAM_FILE doesn't exist"
	exit
fi
if [ ! -f $OBSERVED_FILE ]; then
	echo "$OBSERVED_FILE doesn't exist"
	exit
fi
if [ ! -f $BOOTSTRAP_FILE ]; then
	echo "$BOOTSTRAP_FILE doesn't exist"
	exit
fi
if [ ! -f $BOOTSTRAP_SFS_FILE -a $MAKE_BOOTSTRAP_SFS = false ]; then
	echo "$BOOTSTRAP_SFS_FILE doesn't exist"
	echo "Run this script w/ the -b flag to generate it"
	exit
fi

# Locate the fsc binary and set the $FSC_BIN.
getfsc

echo "#########################################"
echo "Do Bootstrap Replicates"
echo "#########################################"
# In order to do the bootstrapping you need to take the .par file
# from the iteration with the highest likelihood and make a few slight
# modifications to it.

cp $BOOTSTRAP_FILE $OUTDIR
cp $TEMPLATE_FILE $OUTDIR
cp $PARAM_FILE $OUTDIR
cp $OBSERVED_FILE $OUTDIR

# Counting snps will be different depending on if we are using the joint
# or multi format. We need to know the total #snps because we need to update
# the .par file below.

if [ ! -z "$DO_MULTI" ]
then
	NSNPS=`cat $OBSERVED_FILE | awk 'NR==3' | tr " " "\n" | awk '{s+=$1}END{print s}'`
else
	NSNPS=`cat $OBSERVED_FILE | awk 'NR>=3' | tr "\t" "\n" | awk 'NR>1' | awk '{s+=$1}END{print s}'`
fi

echo "NSNPS=$NSNPS"
if [ -z $NSNPS ]
then
	echo "Failed to read total NSNPs from the observed file, bailing out."
	exit
fi

cd $OUTDIR

TMPFILE=.wat.txt
# Since now we are simulating snps under our model we need to change 
# the last line so it reads: 
# //per Block:data type, number of loci, per gen recomb and mut rates
# SNP 1 0 0 0

# Get the line number of the data type line and add 1 to it, since the line
# we want to fix is the one after it
DATATYPELINE=`grep -n "per Block:" $BOOTSTRAP_FILE | cut -d : -f 1`
DATATYPELINE=$(( $DATATYPELINE + 1 ))

# Have to use the temp file because 'sed -i' doesn't work on mac
sed ""$DATATYPELINE"s/.*/SNP 1 0 0 0/" $BOOTSTRAP_FILE > $TMPFILE
mv $TMPFILE $BOOTSTRAP_FILE

# Need to change this line to make '1' = the total number of SNPs in the dataset
# //Number of independent loci [chromosome]
# 1 0

# Get the line number of the description line and add 1 to it, since the line
# we want to fix is the one after it
SNPLINE=`grep -n "Number of independent loci" $BOOTSTRAP_FILE | cut -d : -f 1`
SNPLINE=$(( $SNPLINE + 1 ))

# Have to use the temp file because 'sed -i' doesn't work on mac
sed ""$SNPLINE"s/.*/"$NSNPS" 0/" $BOOTSTRAP_FILE > $TMPFILE
mv $TMPFILE $BOOTSTRAP_FILE

###############################################################################
# Do the bootstrap loops
###############################################################################
# For each bootstrap iteration we simulate a new SFS under the model using
# the parameter estimates from the most likely iteration above.
# Then we re-run parameter estimation using our initial model and using
# the simulated SFS as our observed data. After this is done we're
# going to compare our simulated results to the observed to see how well it fits.
# 
# Bootstrap iterations should be a flag as well, for now
# just do the same number of bootstraps as param estimation reps
if [ $MAKE_BOOTSTRAP_SFS = true ]; then
	echo $MAKE_BOOTSTRAP_SFS
	echo "Make the bootstrap sfs"
	mkdir boot_tmp
	i=boot_tmp
	cp $BOOTSTRAP_FILE $i/bootstrap.par
    	BOOTSTRAP_FILE="bootstrap.par"
	cp ${PREFIX}.tpl $i/bootstrap.tpl
	cp ${PREFIX}.est $i/bootstrap.est

	cd $i
    echo "$FSC_BIN -i $BOOTSTRAP_FILE -n 1 $FSC_FOLDING_FLAG -c 2 -I $DO_MULTI &> /dev/null"
	$FSC_BIN -i $BOOTSTRAP_FILE -n 1 $FSC_FOLDING_FLAG -c 2 -I $DO_MULTI &> /dev/null

	cp bootstrap/bootstrap${OBSERVED_FILE_TYPE} ../../..
	cd ..
	rm -rf boot_tmp
	exit
else
	# Do $BOOTSTRAPS # of replicates for each simulated sfs
	# removed -0
	for j in $(eval echo {1..$BOOTSTRAPS})
	do
		mkdir $j
		cd $j
		cp ../../../${PREFIX}.tpl ./bootstrap.tpl
		cp ../../../${PREFIX}.est ./bootstrap.est
		cp ../../../bootstrap${OBSERVED_FILE_TYPE} .
		
        echo "$FSC_BIN -t bootstrap.tpl -n $NSIMULATIONS -N $NSIMULATIONS $FSC_FOLDING_FLAG -e bootstrap.est -E $NUM_PARAM_SETS -M 0.01 -l 10 -L 20 -C 2 -c 2 $DO_MULTI >bootstrap.log"
		$FSC_BIN -t bootstrap.tpl -n $NSIMULATIONS -N $NSIMULATIONS $FSC_FOLDING_FLAG -e bootstrap.est -E $NUM_PARAM_SETS -M 0.01 -l 10 -L 20 -C 2 -c 2 $DO_MULTI >bootstrap.log

		# Done with this bootstrap parameter estimation. Go back up and do another.
		cd ..
	done
	# Done with all bootstraps for this simulated SFS. Go up and do another.
	cd ..
fi

exit
###############################################################################
# Do the post-processing in R
###############################################################################

echo "#########################################"
echo "Do post-processign in R"
echo "#########################################"

# Update the values in the external R script for making boxplots and histograms
# and junk.

RSCRIPT_NAME=${PREFIX}_postprocess.R
cd $FSCDIR/$OUTDIR
cp $FSCDIR/fsc_stats.R ./$RSCRIPT_NAME

# Temp file hacks is because mac doesn't like 'sed -i' :( There's probably a better way
# to do this.
echo "Setting input values for R script $OUTDIR/$RSCRIPT_NAME"
echo "Prefix = $PREFIX"
sed "s/vals_from_sh_prefix.*/vals_from_sh_prefix<-\""$PREFIX"\"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
echo "Outdir = $FSCDIR/$OUTDIR"
sed "s|vals_from_sh_outdir.*|vals_from_sh_outdir<-\""$FSCDIR/$OUTDIR"\"|" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
echo "Num iterations = $ITERATIONS"
sed "s/vals_from_sh_nreps.*/vals_from_sh_nreps<-"$ITERATIONS"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
echo "Num bootstraps = $BOOTSTRAPS"
sed "s/vals_from_sh_nboots.*/vals_from_sh_nboots<-"$BOOTSTRAPS"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
NPOP0=`cat $FSCDIR/$OBSERVED_FILE | awk 'NR==2' | awk '{print $2}'`
NPOP1=`cat $FSCDIR/$OBSERVED_FILE | awk 'NR==2' | awk '{print $3}'`
echo "Num pop 0 = $NPOP0"
sed "s/vals_from_sh_npop0.*/vals_from_sh_npop0<-"$NPOP0"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
echo "Num pop 1 = $NPOP1"
sed "s/vals_from_sh_npop1.*/vals_from_sh_npop1<-"$NPOP1"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME
echo "Best parameters iteration = $BEST_PARAMS_ITERATION"
sed "s/vals_from_sh_bestlhoodrep.*/vals_from_sh_bestlhoodrep<-"$BEST_PARAMS_ITERATION"/" $RSCRIPT_NAME > $TMPFILE
mv $TMPFILE $RSCRIPT_NAME

# Call the external R script to do stuff
#Rscript $RSCRIPT_NAME

echo "#########################################"
echo "Done. Output files are here: $OUTDIR"
echo "#########################################"

exit 1
