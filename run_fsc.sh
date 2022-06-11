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
CUR_FSC_VRS=27

###################################################################
# A couple utility functions
###################################################################

# print usage information, try to be helpful
usage() {
    echo "Usage: run_fsc [-n <num_iterations>] [-p <file_prefix>] [-t] [-m] [-d]"
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
		# Found fsc executable in $PATH
		echo "Found fsc binary"
	else
		# fsc binary not in PATH. Look in CWD."
		`./fsc$CUR_FSC_VRS &> /dev/null`
	
		if [ $? == 1 ];
		then
			# Found fsc in CWD
			FSC_BIN="$PWD/fsc$CUR_FSC_VRS"
		else
			echo "Fetching fsc2 executable...."
	
			OS_fingerprint=`uname`
			FSC_DL=""
			if [ $OS_fingerprint == "Linux" ];
			then
				echo "OS=linux"
				`wget http://cmpg.unibe.ch/software/fastsimcoal2/downloads/fsc27_linux64.zip > fsc_linux64.zip`
				FSC_DL=fsc27_linux64
			else
				echo "OS=Mac"
				`curl http://cmpg.unibe.ch/software/fastsimcoal2/downloads/fsc27_mac64.zip > fsc_mac64.zip`
				FSC_DL=fsc27_mac64
			fi
			
			# Extract the fsc binary, change mode to allow execution, and clean up the .zip file
			unzip -p $FSC_DL.zip $FSC_DL/fsc$CUR_FSC_VRS* > fsc$CUR_FSC_VRS
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
ITERATIONS=100
NSIMULATIONS=100000
NUM_PARAM_SETS=100
BOOTSTRAPS=50

# Set this variable to empty string. If the -m flag is passed in
# then this gets set to '--multiSFS'
DO_MULTI=""

# Assume input prefix is 'input'
PREFIX="input"

# Default observed file type is jointMAFpop1_0
OBSERVED_FILE_TYPE="_jointMAFpop1_0.obs"
# Flag for doing folded vs unfolded sfs
# default value is -m to do unfolded sfs
FSC_FOLDING_FLAG="-m"

# Define output file names
OUTTMP="Results.unsorted.txt"
OUTPUT_LIKELIHOODS="Results.txt"

# Are we doing a test run?
TEST=0

# Read in the number of iterations from the command line
# This allows for short runs w/ simple parameter tweaking in advance
# of full blown runs.
while getopts dmn:p:t flag; do
  case $flag in
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
	  TEST=1
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
if [ $PREFIX != "input" ]; then
	TEMPLATE_FILE="$PREFIX.tpl"
	PARAM_FILE="$PREFIX.est"
	OBSERVED_FILE="${PREFIX}${OBSERVED_FILE_TYPE}"
else
	# Set template and parameter files in a sensible way
	TEMPLATE_FILE="input.tpl"
	PARAM_FILE="input.est"
	OBSERVED_FILE="input${OBSERVED_FILE_TYPE}"
fi


# Generate a timestamp in number of seconds since the epoch
# and make an outdir for the results. This allows for multiple
# runs without stepping on previous output/results. The
# timestamp can be reformatted for easier reading, or different
# prefix can be appended depending on run options, but thats a V2 thing.
TIMESTAMP=`date +"%s"`

OUTDIR=out/${PREFIX}-$TIMESTAMP
if [ "$TEST" -eq 1 ]; then
	OUTDIR=$OUTDIR-test
fi

mkdir -p $OUTDIR
FSCDIR=`pwd`


echo "Using files: $TEMPLATE_FILE, $PARAM_FILE, $OBSERVED_FILE"

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

# Locate the fsc binary and set the $FSC_BIN.
getfsc

echo "#########################################"
echo "Begin Parameter Estimation Replicates"
echo "#########################################"

# Touch the replicate output files
touch $OUTDIR/$OUTTMP $OUTDIR/$OUTPUT_LIKELIHOODS

# This is a little tricky because bash implements brace expansion
# before it does variable conversion, so variables inside brace
# ranges don't work without using `eval`.
for i in $(eval echo {1..$ITERATIONS})
do
	echo "Doing Iteration $i/$ITERATIONS"
	mkdir $OUTDIR/$i

	# FSC makes some stupid assumptions about where the observed file is
	# and it won't let you pass it in, so you just have to copy these files
	# over and over. Kinda stupid.
	cp $TEMPLATE_FILE $OUTDIR/$i
	cp $PARAM_FILE $OUTDIR/$i
	cp $OBSERVED_FILE $OUTDIR/$i

	cd $OUTDIR/$i
	$FSC_BIN -t $TEMPLATE_FILE -n 10000 -N $NSIMULATIONS $FSC_FOLDING_FLAG -e $PARAM_FILE -E $NUM_PARAM_SETS -M 0.01 -l 10 -L 40 -0 -c 0 $DO_MULTI >output.log

	# For ease of reading output, grab the header if its the first rep
	# Not sure if this is useful.
    if [ $i == 1 ];
	then
		echo "copy header"
		head -n 1 ./$PREFIX/${PREFIX}.bestlhoods > ../$OUTPUT_LIKELIHOODS
	fi

	echo -n "REP $i - " >> ../$OUTTMP
	tail -n 1 ./$PREFIX/${PREFIX}.bestlhoods >> ../$OUTTMP

	# Go back up to execdir and do the next iteration.
	cd ../../..
done

echo "#########################################"
echo "Parameter Estimation Results"
echo "#########################################"

# Sort results. Field 14 is Max Estimated Likelihood, sort low to high.
# Note, this doesn't handle duplicates intelligently.
# Doop likelihood values will result in the first one being duplicated
# in the results file.
# this is stupid. The field will change if you change the number of params
# so this should actually identify the right column in a smart way.
# Well we know the MaxEstLhood is the 2nd to last field so we do
# some goofy shell hacks, reverse the whole file, grap the 2nd field only
# reverse it again, cut off the header and sort by max likelihood.
# PARTY TIME!
LHOOD_COL=`cat $OUTDIR/$OUTTMP | rev | cut -f 2 | rev | grep -v MaxEstLhood | sort`

for i in $LHOOD_COL
do 
	echo $i
	grep -e "$i" $OUTDIR/$OUTTMP >> $OUTDIR/$OUTPUT_LIKELIHOODS
done

# find the rep with the best likelihood value
BEST_PARAMS_ITERATION=`head -n 2 $OUTDIR/$OUTPUT_LIKELIHOODS | tail -n 1 | cut -f 2 -d " "`
echo "Best parameter estimation iteration - $BEST_PARAMS_ITERATION"
cat "$OUTDIR/$BEST_PARAMS_ITERATION/${PREFIX}/${PREFIX}.bestlhoods"

# Clean up the unsorted results file
rm -f $OUTDIR/$OUTTMP
