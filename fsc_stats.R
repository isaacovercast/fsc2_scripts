# Post-process the fastsimcoal2 iterations and bootstrap replicates

# These are the values of the variables that change on a per execution
# basis. These values will be updated by the run_fsc.sh script, or
# if you want to just run it by hand then you can set them here yourself
# Defualts are dummy values, so they probably won't work for you
#
# Made these weird looking vars so I know they are only ever being set
# here once and then set transferred to the vars for use inside the script.
# Makes it easier to sed through and know you aren't munging any other 
# lines.
# prefix is the <prefix>.est, <prefix>.tpl file header.
# outdir should probably be full path rather than relative, just for safety.
vals_from_sh_prefix<-""
vals_from_sh_outdir<-""
vals_from_sh_nreps<-""
vals_from_sh_nboots<-""
vals_from_sh_npop0<-""
vals_from_sh_npop1<-""
vals_from_sh_bestlhoodrep<-""

# <TODO> Gotta figure out how to get the pop names in here so the plots will
# look good.
vals_from_sh_pop0name<-"pop0"
vals_from_sh_pop1name<-"pop1"

# Set the variables we'll actually use from the vals passed in from run_fsc.sh
prefix<-vals_from_sh_prefix
replicatedirectory<-vals_from_sh_outdir
nreps<-vals_from_sh_nreps
nboots<-vals_from_sh_nboots
npop0<-vals_from_sh_npop0
npop1<-vals_from_sh_npop1
popnames=c( vals_from_sh_pop0name, vals_from_sh_pop1name )
bestlhoodrep<-vals_from_sh_bestlhoodrep

# TEST all input vals to make sure they're good
if( prefix == "" ) { stop( paste( "Bad input parameter: prefix" ) ) }
if( replicatedirectory == "" ) { stop( paste( "Bad input parameter: outdir" ) ) }
if( nreps == "" ) { stop( paste( "Bad input parameter: nreps" ) ) }
if( nboots == "" ) { stop( paste( "Bad input parameter: nboots" ) ) }
if( npop0 == "" ) { stop( paste( "Bad input parameter: npop0" ) ) }
if( npop1 == "" ) { stop( paste( "Bad input parameter: npop1" ) ) }
if( bestlhoodrep == "" ) { stop( paste( "Bad input parameter: bestlhoodrep" ) ) }

replicate<-1:nreps
bootstraps<-1:nboots
data=NULL

plotdir<-paste( replicatedirectory, "replicateplots", sep='/')
dir.create( plotdir, showWarnings = FALSE ) 

bootplotdir<-paste( replicatedirectory, "bootstrapplots", sep='/')
dir.create( bootplotdir, showWarnings = FALSE )

###################################################
# Make boxplots and histograms for parameter values
###################################################

for(x in replicate){
  lhoodsfile<-paste( prefix, 'bestlhoods', sep='.')
  fname=paste(replicatedirectory, x, prefix, lhoodsfile,sep='/')
  if (file.exists(fname)) {
    readin=read.table(fname)
    matrixin=as.matrix(readin)
    header=matrixin[1,]
    secondline=matrixin[2,]
    numericline=as.numeric(secondline,ncol=length(secondline))
    data=rbind(data,numericline)
  }
}
if (is.null(data)) {
  stop( paste( "Can't read likelhood values in directory: ", replicatedirectory))
} else {
  means=NULL
  
  # make a directory for the output stats
  for(x in 1:length(header)){
    meantemp=mean(data[,x])
    means=c(means,meantemp)
    boxname=paste('box_plot_',header[x],'.pdf',sep='')
    {
      pdf(paste( plotdir, boxname, sep='/'))
      boxplot(data[,x],main=boxname)
      dev.off()
    }

    histname=paste('histogram_',header[x],'.pdf',sep='')
    {
      pdf(paste( plotdir, histname, sep='/'))
      hist(data[,x],main=histname)
      dev.off()
    }
  }

  # Write out the parameter estimates ordered by highest likelihood
  data=cbind(data,replicate)
  info=data[order(data[,length(header)-1],decreasing=T),]
  write.table(info, file=paste(plotdir, 'data.txt',sep='/'), row.names=F, col.names=c(header,'replicate_number'), sep='\t')
  write.table(means, file=paste(plotdir, 'means.txt',sep='/'), row.names=c(header),col.names=F)
}

###################################################
# Compare single pop SFS for observed vs expected
###################################################
# This is one form of the model fit, which compares the single population SFSs 
# between the observed and expected (as extrapolated from the optimized expected 
# joint SFS); last I checked (though this may be different for the 2 population 
# models), fsc2 didn't output the expected single population SFSs, so this first 
# R script is just to extrapolate it from the expected joint SFS;

# go grab the observed and the estimated SFS files from the replicate with the 
# highest likelihood and decompose it into individual AFS per population. The 
# file lives in: out/<timestamp>/<replicate#>/<prefix>/<prefix>_MSFS.txt
for( obsvsexp in c( "expected", "observed" ) ) {

  SFS=NULL
  population=NULL
  if( obsvsexp == "expected"){
    # Read the expected sfs from the best lhood iteration
    bestlhood_sfs_file<-paste( prefix, '_MSFS.txt', sep='' )
    print( paste( "Read expected sfs from: ", bestlhood_sfs_file, sep='' ) )
    SFS=read.table( paste( replicatedirectory, bestlhoodrep, prefix, bestlhood_sfs_file, 
                           sep='/'), fill=T)
    # Had to move this block inside the if/else because
    # the observed and expected sfs have different number of rows
    # and columns, oddly enough
    for(a in 0:npop0){
      for(b in 0:npop1){
        intermediate=cbind(a,b)
        population=rbind(population,intermediate)
      }
    }
  } else {
    # Just read the observed sfs from that same replicate
    observed_sfs_file<-paste( prefix, '_MSFS.obs', sep='' )
    print( paste( "Read observed sfs from: ", observed_sfs_file, sep='' ) )
    SFS=read.table( paste( replicatedirectory, bestlhoodrep, observed_sfs_file, 
                           sep="/" ), fill=T )    
    # Had to move this block inside the if/else because
    # the observed and expected sfs have different number of rows
    # and columns, oddly enough
    for(a in 0:(npop0) ) {
      for(b in 0:(npop1) ) {
        intermediate=cbind(a,b)
        population=rbind(population,intermediate)
      }
    }
  }
  
  if( is.null(SFS) ) { stop( paste( "Can't read sfs: ", obsvsexp, sep='' ) ) }
  
  SFS=SFS[3,]
  SFS=as.matrix(SFS)
  SFS=c(SFS)
  SFS=as.numeric(SFS)
  SFS=as.matrix(SFS,ncol=1)

  ###################################################
  # Decompose the expected sfs into individual sfs
  # for each population
  ###################################################
  # What's this doing? Fix this so it works more dynamically
  # set 'limit' based on some real value of the pops
  for(a in 1:2){
    if (a==1) {
      limit=npop0
    } else {
      limit=npop1
    }

    sider=population[,a]
    newSFS=cbind(sider,SFS)
    newSFS=newSFS[order(newSFS[,1]),]
    AFS=NULL
  
    for(b in 1:limit){
      value=NULL
      for(c in 1:nrow(newSFS)){
        if (newSFS[c,1]==b) {
          value=c(value,newSFS[c,2])
        }
      }
      AFS=cbind(AFS,sum(value))
    }
    AFS=AFS/sum(AFS[,1:ncol(AFS)-1])
    AFS=c(0,AFS[,1:ncol(AFS)-1],0)
    sfsfile=paste( popnames[a], obsvsexp, 'SFS', sep='.')
    write(AFS, file=paste( replicatedirectory, sfsfile, sep='/' ), sep='\t', ncolumns=length(AFS))
  }
}

for(a in 1:2){
  # print out a box plot of observed vs expected FS
  # This seems stupid, boxplots?
  obsfile=paste(popnames[a], '.observed.SFS',sep='')
  obs=read.table( paste( replicatedirectory, obsfile, sep='/' ) )
  obs=obs/sum(obs)
  expfile=paste(popnames[a],'.expected.SFS',sep='')
  exp=read.table( paste( replicatedirectory, expfile, sep='/' ) )
  {
    pdfname<-paste( popnames[a],'MarginalSFSFit.pdf',sep='-' )
    pdf( paste( replicatedirectory, pdfname ,sep='/' ) )
    boxplot(obs,ylim=c(0,1),names=0:(length(obs)-1),main=paste(popnames[a],'MarginalSFSFit',sep='-'))
    points(1:length(obs),exp,pch=4,col='red')
    dev.off()
  }
}

###################################################
# Analyse bootstrap replicates
###################################################

# creates boxplots, histograms, and smooth histograms for all of the parameters 
# across the bootstrapping, as well as a simple text data table; the CLR statistic, 
# another method used for model fitting, is included with this; all of the plots 
# include the original parameter estimate and the histograms include 95% confidence 
# intervals (including for the CLR statistic; if the observed is within the 95%, 
# then it's a good fit);

# For each bootstrap simulation iteration we run a series of parameter
# estimation iterations, so you have to go in and get the bestlhood
# from each iteration.
data=NULL
boots=NULL
for(x in replicate){
  for( boot in bootstraps ){
    # Bootstrap directories can get harry, they will look like this
    # ./<FSC_working_directory>/out/<timestamp>/bootstrap/<replicate>/<bootstrap_iteration>

    # get the best likelihood values for this bootstrap iteration
    fname=paste( replicatedirectory, 'bootstrap', x, boot, 'bootstrap', 'bootstrap.bestlhoods',sep='/')
    if (file.exists(fname)) {
      readin=read.table(fname)
      matrixin=as.matrix(readin)
      header=matrixin[1,]
      secondline=matrixin[2,]
      numericline=as.numeric(secondline,ncol=length(secondline))
      boots=rbind(boots, numericline )
    }
  }
  info=boots[order(boots[,length(header)-1],decreasing=T),]
  data=rbind(data, info[1,])
}

######## Doesn't work below here
# Or it "works" but the output is suspect still

estimates=read.table( paste( replicatedirectory, bestlhoodrep, prefix, 
                             paste(prefix, '.bestlhoods', sep=''), sep='/' ) )
estimates=as.matrix(estimates)
estimates=estimates[2,]
estimates=as.numeric(estimates)
addCLR=estimates[length(estimates)]-estimates[length(estimates)-1]
estimates=c(estimates,addCLR)
if (is.null(data)) {
  stop( "Data is null. Bailing out.")
} else {
  CLR=data[,ncol(data)]-data[,ncol(data)-1]
  data=cbind(data,CLR)
  header=c(header,'CLR')
  means=NULL
  pvalues=NULL
  approxobspvalue=NULL

  # Run through each parameter and make lots of different plots
  for(x in 1:length(header)){
    meantemp=mean(data[,x])
    means=cbind(means,meantemp)
    boxname=paste('box_plot_',header[x],'.pdf',sep='')
    {
      pdf(paste( bootplotdir ,boxname, sep='/'))
      boxplot(data[,x],main=boxname)
      points(1,estimates[x],pch=16,col='red')
      dev.off()
    }

    histname=paste('histogram_',header[x],'.pdf',sep='')
    {
      pdf(paste( bootplotdir, histname,sep='/'))
      hist(data[,x],main=histname)
      abline(v=estimates[x], col='red')
      dev.off()
    }

    intervals=quantile(data[,x], c(.025,.975))
    pvalues=cbind(pvalues,intervals)
    smooth=density(data[,x])
    smoothname=paste('smooth_histogram_',header[x],'.pdf',sep='')
    {
      pdf(paste( bootplotdir, smoothname, sep='/'))
      plot(smooth,main=smoothname)
      abline(v=estimates[x], col='red'); abline(v=intervals, lty=2)
      dev.off()
    }

    obsprob=mean(data[,x] < estimates[x])
    if (obsprob>0.5){
      obsprob=1-obsprob
    }

    obsprob=obsprob*2
    approxobspvalue=cbind(approxobspvalue,obsprob)
  }

  newdata=rbind(data,means,pvalues,approxobspvalue)
  write.table(newdata, file=paste(bootplotdir,'data.txt',sep='/'), row.names=c(1:length(replicate),'mean','lowCI','highCI','approx_obs_pvalue'), col.names=c(header), sep='\t')
}
