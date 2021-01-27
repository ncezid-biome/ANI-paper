#!/bin/bash -l
#$ -pe smp 1
#$ -q all.q
#$ -cwd -V -j y
#$ -N aniM

module load ncbi-blast+/2.2.30
module load MUMmer/3.23

# Usage: ani-m.pl <reference> <query>
OUT=$1
REF=$2
shift; shift;
QUERY="$@";
script=$(basename $0)

if [ "$QUERY" == "" ]; then
  echo "USAGE: $script out.tsv ref.fasta *.fasta"
  echo "  *.fasta: all the query fasta files to match against ref.fasta"
  exit 1;
fi

# Do the ANI
ANISCRIPT="/scicomp/groups/OID/NCEZID/DFWED/EDLB/share/projects/validation/ANIm/scripts/ani-m_LK.pl"
echo -e "REF\tQUERY\tANI" > $OUT
for i in $QUERY; do
  command="$ANISCRIPT $REF $i >> $OUT"
  eval $command
  if [ $? -gt 0 ]; then
    echo "ERROR WITH COMMAND"
    echo "  $command"
    exit 1;
  fi
done
