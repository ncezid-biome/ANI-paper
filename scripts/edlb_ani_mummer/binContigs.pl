#!/usr/bin/env perl
# Authors: Lee Katz and Lori Gladney
# Original script by Lori Gladney
# Objective: Run MUMmer dnadiff script between two genomes

use strict;
use warnings;
use File::Temp qw/ tempfile tempdir /;
use File::Basename qw/fileparse basename dirname/;
use Getopt::Long qw/GetOptions/;
use Data::Dumper;
use List::Util qw/shuffle/;

use Bio::SeqIO;

use threads;
use Thread::Queue;

local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n";}

exit main();

sub main{
  my $settings={};
  GetOptions($settings,qw(tempdir verbose only-first=i numcpus=i min|min-ani=i)) or die $!;
  $$settings{tempdir}||=tempdir("ani-m-bin.XXXXXX", CLEANUP => 1, TMPDIR=>1);
  $$settings{min}||=95;
  $$settings{numcpus}||=1;
  $$settings{'only-first'}||=0;

  die usage() if(!@ARGV);

  # place all contigs into separate files
  logmsg "Splitting all contigs into $$settings{tempdir}";
  my $contigCount=0;
  my @contigFile=();
  for my $fasta(@ARGV){
    my $in=Bio::SeqIO->new(-file=>$fasta);
    while(my $seq=$in->next_seq){
      $contigCount++;
      my $outfile="$$settings{tempdir}/$contigCount.fasta";
      push(@contigFile,$outfile);

      my $out=Bio::SeqIO->new(-file=>">$outfile");
      $out->write_seq($seq);
      $out->close;
    }
  }
  
  # Set up pairwise combinations
  my @combination;
  for(my $i=0;$i<$contigCount;$i++){
    if($$settings{'only-first'} && $i >= $$settings{'only-first'}){
      logmsg "DEBUG: only looking at $i references";
      last;
    }
    for(my $j=0;$j<$contigCount;$j++){
      next if($i==$j);
      push(@combination,[$contigFile[$i],$contigFile[$j]]);
    }
    logmsg "Reference contig $i: $contigFile[$i]" if($$settings{verbose});
  }

  # Randomize @combination so that you decrease the 
  # likelihood of the same files being read
  # at the same time by multithreading.
  @combination=shuffle(@combination);

  # enqueue the all vs all combinations
  my $Q=Thread::Queue->new(@combination);
  $Q->enqueue(undef) for(1..$$settings{numcpus});

  logmsg "Running ANI with $$settings{numcpus} threads";
  my @thr;
  for(my $i=0;$i<$$settings{numcpus};$i++){
    $thr[$i]=threads->new(\&aniWorker,$Q,$settings);
  }

  my %ani;
  for(@thr){
    my $tid=$_->tid;
    my $tmp=$_->join;

    # Properly combine 2d hash
    while(my($ref,$queryHash)=each(%$tmp)){
      while(my($query,$ani)=each($queryHash)){
        $ani{$ref}{$query}=$ani;
      }
    }
  }

  # Print results
  while(my($ref,$queryHash)=each(%ani)){
    print $ref;
    while(my($query,$ani)=each($queryHash)){
      print "\t$query" if($ani > $$settings{min});
    }
    print "\n";
  }

  return 0;
}

sub aniWorker{
  my($Q,$settings)=@_;

  my %ani;
  while(defined(my $param=$Q->dequeue)){
    my($ref,$query)=@$param;

    # get the identifier for this contig
    my $refId=Bio::SeqIO->new(-file=>$ref)->next_seq->id;
    my $queryId=Bio::SeqIO->new(-file=>$query)->next_seq->id;

    # Sometimes ani fails.
    # I'm guessing it might be due to disk IO and multithreading?
    my $aniReport="";
    my $numTries=0;
    do{
      $numTries++;
      logmsg "$refId / $queryId ($numTries)" if($$settings{verbose});
      $aniReport = `ani-m.pl --stdev --alignment-length $ref $query 2>/dev/null`;
    } while($? > 0 && $numTries < 100);
    if($?){
      logmsg "ERROR between $refId and $queryId after $numTries tries";
      exit $?;
    }
    chomp($aniReport);

    my(undef,undef,$ani, $stdev, $percentAligned)=split(/\t/, $aniReport);
    # If the result's ani varies so much across the contig,
    # then ignore the result.
    if($stdev > 15){
      logmsg "WARNING: large standard deviation ($stdev) between these two contigs: $refId $queryId\n  Discarding the result.";
      $ani=0;
    }
    # If the two contigs do not align very well,
    # then ignore the result.
    $ani=0 if($percentAligned < 70);

    $ani{$refId}{$queryId}=$ani;
  }

  return \%ani;
}

sub usage{
  "$0: bin contigs by ANI. All contigs from all files are
  concatenated into the same analysis internally.

  Usage: $0 file.fasta [file2.fasta...]
  --numcpus    1
  --min        95    Percentage cutoff for binning
  --only-first 0     If nonzero, uses only the first X
                     contigs as references for ANI.
  --verbose          Print every comparison being performed
  "
}

