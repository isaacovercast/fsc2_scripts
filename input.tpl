//Number of population samples (demes)
2
//Population effective sizes (number of genes)
NPOP0
NPOP1
//Sample sizes
7 0
14 0
//Growth rates : negative growth implies population expansion
0
0
//Number of migration matrices : 0 implies no migration between demes
2
//Migration matrix 0
0 MIG1
MIG2 0
//Migration matrix 1
0 0
0 0
//historical event: time, source, sink, migrants, new size, growth rate, migr. matrix
3 historical event
TIME2 0 0 0 RESIZE1 0 1
TIME3 1 1 0 RESIZE2 0 1
TIME1 1 0 1 1 0 1
//Number of independent loci [chromosome]
1 0
//Per chromosome: Number of linkage blocks
1
//per Block: data type, num loci, rec. rate and mut rate + optional parameters
FREQ 1 0.00000 2.5e-8 OUTEXP
