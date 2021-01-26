#!/bin/bash

# Launches speed test for ANI-m
set -e

if [ "$3" == "" ]; then
  echo "Runs an all vs all speed test and captures the time into the first parameter"
  echo "Usage: $(basename $0) speedtest.txt file1.fasta file2.fasta..."
  exit 1
fi

# Test prereq
module load MUMmer
module unload perl
module load perl/5.16.1-MT
echo "Testing prereq software";
which ani-m.pl
which nucmer
which perl
perl -Mthreads -e 1

out=$1; shift;
if [ -e "$out" ]; then
  echo "ERROR: $out already exists!";
  exit 1;
fi;

tmpdir=$(mktemp --tmpdir='.' --directory ANI-M.XXXXXX)

# Place all absolute paths to fasta files into an array file.
# Need to display pairwise combinations, one per line.
CTRL_FILE="$tmpdir/fasta.txt"
for i in "$@"; do
  for j in "$@"; do 
    echo -n  $(realpath $i)
    echo -ne "\t"
    echo -n  $(realpath $j)
    echo
  done;
done > $CTRL_FILE

mkdir -p $tmpdir/log

qsub -q all.q -N ANI-m -o $tmpdir/log -j y -V -cwd -t 1-$(cat $CTRL_FILE | wc -l) \
  -v "CTRL_FILE=$CTRL_FILE" -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  set -e
  tmpsubdir=$(mktemp --tmpdir=$tmpdir --directory ani-m-bionumerics.XXXXXX)

  ref=$(sed -n ${SGE_TASK_ID}p $CTRL_FILE | cut -f 1)
  query=$(sed -n ${SGE_TASK_ID}p $CTRL_FILE | cut -f 2)

  # The script needs to be a query vs list of references
  refTsv="$tmpsubdir/ref.tsv"
  echo -e "File\n$ref" > $refTsv

  cp -v $ref $query $tmpsubdir

  /usr/bin/time -f 'SECONDS\t%e' \
    ani-m-bionumerics.pl --query $query --references $refTsv --nThreads 1

  rm -rf $tmpsubdir

END_OF_SCRIPT

touch $out

qsub -hold_jid ANI-m -o $out -e $out.err -V -cwd -q all.q -N ANI-m-reduce \
  -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  grep -h SECONDS $tmpdir/log/*.o* | cut -f 2 | sort -n

END_OF_SCRIPT



