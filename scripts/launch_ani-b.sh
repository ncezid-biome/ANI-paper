#!/bin/bash

# Launches speed test for ANI-b
set -e

if [ "$3" == "" ]; then
  echo "Runs an all vs all speed test and captures the time into the first parameter"
  echo "Usage: $(basename $0) speedtest.txt file1.fasta file2.fasta..."
  exit 1
fi

# Test prereq
module purge
module load ruby/2.4.1
module load ncbi-blast+/2.2.30
echo "Testing prereq software";
which ruby
which ani.rb
which blastn

out=$1; shift;
if [ -e "$out" ]; then
  echo "ERROR: $out already exists!";
  exit 1;
fi;

tmpdir=$(mktemp --tmpdir='.' --directory ANI-B.XXXXXX)

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

qsub -q all.q -N ANI-b -o $tmpdir/log -j y -V -cwd -t 1-$(cat $CTRL_FILE | wc -l) \
  -v "CTRL_FILE=$CTRL_FILE" -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  set -e

  ref=$(sed -n ${SGE_TASK_ID}p $CTRL_FILE | cut -f 1)
  query=$(sed -n ${SGE_TASK_ID}p $CTRL_FILE | cut -f 2)

  /usr/bin/time -f 'SECONDS\t%e' \
    ani.rb --seq1 $ref --seq2 $query --threads 1

END_OF_SCRIPT

touch $out

qsub -hold_jid ANI-b -o $out -e $out.err -V -cwd -q all.q -N ANI-b-reduce \
  -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  grep -h SECONDS $tmpdir/log/*.o* | cut -f 2 | sort -n

END_OF_SCRIPT



