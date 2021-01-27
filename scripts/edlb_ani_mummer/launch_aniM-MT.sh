#!/bin/bash -l
#$ -pe smp 1
#$ -q all.q
#$ -cwd -V -j y
#$ -N aniM

# Usage: ani-m.pl <reference> <query>
OUT=$1
REF=$2
shift; shift;
#QUERY=$(echo "$@" | tr ' ' '\n');
QUERY="$@"
script=$(basename $0)

NSLOTS=${NSLOTS:=4}

if [ "$QUERY" == "" ]; then
  echo "USAGE: $script out.tsv ref.fasta *.fasta"
  echo "  *.fasta: all the query fasta files to match against ref.fasta"
  exit 1;
fi

module purge
module load ncbi-blast+/2.2.30
module load MUMmer/3.23

mkdir -p /scratch/$USER
tmpdir=$(mktemp -p /scratch/$USER -d aniM.XXXXXX)
trap ' { rm -rf $tmpdir; } ' EXIT

cp -nv $QUERY $tmpdir/

# Do the ANI
ANISCRIPT="$HOME/src/edlb_ani_mummer/ani-m.pl"
$ANISCRIPT $REF $tmpdir/* --symmetric > $OUT

