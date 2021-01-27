#!/bin/bash
# Author: Lee Katz
# Test script: do all vs all ANI. Took me about 2.5 minutes to finish on the example data.

D=$(dirname $0);
time ls $D/*.fasta | xargs -I {} -P 32 -n 1 $D/../ani-m-bionumerics.pl {} example/*.fasta --nThreads 1
#time $D/../ani-m-bionumerics.pl {} example/*.fasta --nThreads 32
