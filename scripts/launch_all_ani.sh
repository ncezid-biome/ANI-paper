#!/bin/bash

# Launches speed test for ANI-m, ANI-b, and FastANI
set -e

if [ "$3" == "" ]; then
  echo "Runs an all vs all speed test and captures the time into the first parameter"
  echo "Usage: $(basename $0) speedtest.txt file1.fasta file2.fasta..."
  exit 1
fi

# Test prereq: ani-m
export PATH=$PATH:$(dirname $(realpath $0))
echo "Testing prereq software";
module purge
module load MUMmer
module unload perl
module load perl/5.16.1-MT
which ani-m.pl
which nucmer
which perl
perl -Mthreads -e 1
# ani-b
module purge
#module load ruby/2.4.1
export PATH=$HOME/bin/ruby-2.4.5/bin:$PATH
module load ncbi-blast+/2.2.30
which ruby
which ani.rb
which blastn
# FastANI
module purge
which fastANI

out=$1; shift;
if [ -e "$out" ]; then
  echo "ERROR: $out already exists!";
  exit 1;
fi;

tmpdir=$(mktemp --tmpdir='.' --directory ANI-ALL.XXXXXX)
echo "TEMPDIR is $tmpdir";


CTRL_FILE="$tmpdir/fasta.txt"
echo "$@" | tr ' ' '\n' | xargs -P 1 -n 1 realpath > $CTRL_FILE

mkdir -p $tmpdir/log

qsub -q all.q -N ANI-all -o $tmpdir/log -j y -V -cwd -t 1-$(cat $CTRL_FILE | wc -l) \
  -v "CTRL_FILE=$CTRL_FILE" -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  ref=$(sed -n ${SGE_TASK_ID}p $CTRL_FILE | cut -f 1)
  query_counter=0
  for query in $(cat $CTRL_FILE); do 

    tmpsubdir=$(mktemp --tmpdir=$tmpdir --directory ani-all.XXXXXX)
    trap "rm -rf $tmpsubdir;" EXIT
    touch $tmpsubdir/ani.tsv
    touch $tmpsubdir/time.tsv

    ## ANI-M
    module purge
    module load MUMmer
    module unload perl
    module load perl/5.16.1-MT
    echo "Testing prereq software";
    which ani-m.pl
    which nucmer
    which perl
    perl -Mthreads -e 1

    # The script needs to be a query vs list of references
    refTsv="$tmpsubdir/ref.ani-m.tsv"
    echo -e "File\n$ref" > $refTsv

    cp -v $ref $query $tmpsubdir

    echo -e "Method\tpercent-aligned\tANI" >> $tmpsubdir/ani.tsv
    echo -e "Method\tSECONDS" >> $tmpsubdir/time.tsv
    echo "ANI-M";
    echo -ne "ANI-M\t" >> $tmpsubdir/ani.tsv
    /usr/bin/time -o $tmpsubdir/time.tsv --append -f 'ANI-M\t%e' \
      ani-m-bionumerics.pl --query $query --references $refTsv --nThreads 1 |\
      tail -n +2 | cut -f 3,4 >> $tmpsubdir/ani.tsv 

    # For right now, do not do any coverage check
    if [ 1 -lt 0 ]; then
      echo "EXITING IF THIS BLOCK IS EXECUTED"; exit 1;
      # If the percent aligned is less than 70% with ANI-M, 
      # discard the results.  We don't care.
      coverage=$(cut -f 2 $tmpsubdir/ani.tsv | tail -n 1);
      if [[ "$coverage" = "." || "$coverage" = "" ]]; then
        echo "Coverage was not reported. Discarding";
        rm -rf $tmpsubdir
        continue;
      fi;
      if (( $(echo "$coverage < 70" | bc -l) )); then
        echo "Coverage was $coverage, < 70%. Discarding";
        rm -rf $tmpsubdir
        continue;
      fi;
    fi
    

    ## ANI-B
    module purge
    #module load ruby/2.4.1
    module load ncbi-blast+/2.2.30
    echo "Testing prereq software";
    which ruby
    which ani.rb
    which blastn
    echo "ANI-B";
    echo -ne "ANI-B\t.\t" >> $tmpsubdir/ani.tsv
    /usr/bin/time -o $tmpsubdir/time.tsv --append -f 'ANI-B\t%e' \
      ani.rb --auto --seq1 $ref --seq2 $query --threads 1 >> $tmpsubdir/ani-b.tsv
    anib=$(cat $tmpsubdir/ani-b.tsv);

    if [ ! "$anib" ]; then
      anib="0";
    fi
    echo "$anib" >> $tmpsubdir/ani.tsv

    ## FastANI
    module purge
    which fastANI
    echo "FastANI"
    echo -ne "FastANI\t" >> $tmpsubdir/ani.tsv
    /usr/bin/time -o $tmpsubdir/time.tsv --append -f 'FastANI\t%e' \
      fastANI -q $query -r $ref -o $tmpsubdir/fastANI.tsv
    percent_aligned=$(echo "$(cut -d ' ' -f 4 $tmpsubdir/fastANI.tsv) / $(cut -d ' ' -f 5 $tmpsubdir/fastANI.tsv)" | bc -l)
    ani=$(cut -d ' ' -f 3 $tmpsubdir/fastANI.tsv)

    if [ "$ani" == "" ]; then
      ani="0";
    fi
    if [ "$percent_aligned" == "" ]; then
      percent_aligned=".";
    fi

    echo -e "$percent_aligned\t$ani" >> $tmpsubdir/ani.tsv

    mv -v $tmpsubdir/ani.tsv $tmpdir/ani.$SGE_TASK_ID.$query_counter.tsv
    mv -v $tmpsubdir/time.tsv $tmpdir/time.$SGE_TASK_ID.$query_counter.tsv
    rm -rfv $tmpsubdir

    query_counter=$(($query_counter + 1))
  done

END_OF_SCRIPT

touch $out

qsub -S /bin/bash -hold_jid ANI-all -o $out -e $out.err -V -cwd -q all.q -N ANI-all-reduce-times \
  -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  # Table output
  echo -e "ANI-M\tANI-B\tFastANI"

  grep -h ANI-M   $tmpdir/time.*.tsv  | cut -f 2 > $tmpdir/col1.speeds.txt
  grep -h ANI-B   $tmpdir/time.*.tsv  | cut -f 2 > $tmpdir/col2.speeds.txt
  grep -h FastANI $tmpdir/time.*.tsv  | cut -f 2 > $tmpdir/col3.speeds.txt

  paste $tmpdir/col1.speeds.txt $tmpdir/col2.speeds.txt $tmpdir/col3.speeds.txt

END_OF_SCRIPT

qsub -S /bin/bash -hold_jid ANI-all -o $out.ani.tsv -e $out.ani.err -V -cwd -q all.q -N ANI-all-reduce-anis \
  -v "tmpdir=$tmpdir" <<- "END_OF_SCRIPT"
  #!/bin/bash

  # Table output
  echo -e "ANI-M\tANI-B\tFastANI"

  grep -h ANI-M   $tmpdir/ani.*.tsv  | cut -f 3 > $tmpdir/col1.ani.txt
  grep -h ANI-B   $tmpdir/ani.*.tsv  | cut -f 3 > $tmpdir/col2.ani.txt
  grep -h FastANI $tmpdir/ani.*.tsv  | cut -f 3 > $tmpdir/col3.ani.txt

  paste $tmpdir/col1.ani.txt $tmpdir/col2.ani.txt $tmpdir/col3.ani.txt

END_OF_SCRIPT


echo "Times will be found in $out"
echo "ANI values will be found in $out.ani.tsv"


