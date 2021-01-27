#!/usr/bin/env perl  
#Lori Gladney 01-27-2015 version 3 
# Edited by Lee Katz
#Objective: Run MUMmer dnadiff script between two genomes 

use strict;
use warnings; 
use File::Temp qw/ tempfile tempdir /;
use File::Basename qw/fileparse basename dirname/;
use Getopt::Long;
use Data::Dumper;
use List::Util qw/max sum/;

local $0=basename $0;
sub logmsg{print STDERR "$0: @_\n";}
exit(main());

sub main{
  my $settings={};
  GetOptions($settings,qw(help symmetric|symmetrical)) or die $!;
  die usage() if($$settings{help});

  my $reference= shift(@ARGV) or die "Cannot locate the reference sequence\n". usage();
  my @query= @ARGV or die "Cannot locate the query sequence\n".usage();

  # Print the header
  my @header=qw(reference query ANI stdev percentAligned);
  print join("\t",@header)."\n";

  for my $query(@query){
    my $ani    = ani($reference,$query,$settings);

    # Print the output with tabs
    print join("\t",map{$$ani{$_}} @header)."\n";

    # Warnings
    if($$ani{percentAligned} < 70){
      logmsg "Warning: percent aligned is less than 70% between $reference and $query";
    }

    # Symmetrical analyses follow after this
    if(!$$settings{symmetric}){
      next;
    }
    my $revAni = ani($query,$reference,$settings);
    my $covDifference = abs($$ani{percentAligned} - $$revAni{percentAligned});
    if($covDifference > 5){
      logmsg "Warning: there is a coverage difference ($covDifference%) when $reference and $query are swapped";
    }
    
    # Print the output with tabs
    print join("\t",map{$$revAni{$_}} @header)."\n";
  }
    
  return 0;
}



sub ani{
  my($reference,$query,$settings)=@_;

  my $tempdir = tempdir("ani-m.XXXXXX", CLEANUP => 1, TMPDIR=>1); 

  my $refname=basename($reference);
  my $queryname=basename($query);

  my $prefix="$tempdir/".$refname."_".$queryname;

  #Make system call to run the dnadiff script and output any STDERR/STDOUT to dev/null
  system ("dnadiff $reference $query -p $prefix 2>/dev/null");
  if($?){
    die "Error: Problem with dnadiff: $!\n  dnadiff $reference $query -p $prefix\n";
  }

  my($ani,$percentAligned);

  #Loop through each line in the report, pulling out lines that match AvgIdentity. 
  my $report="$prefix.report";
  open(my $reportFh, $report) or die "Cannot read dnadiff report file $report: $!";
  while(<$reportFh>){
    chomp;
    my @F=split(/\s+/,$_);
      
    if (/^AvgIdentity/) {
      $ani=$F[1];
    }
      
    if (/^AlignedBases/) {
      $percentAligned=$F[1];
      if($percentAligned=~/(\d+\.\d+)%/){
        $percentAligned=$1;
      }
    }
  }   
  close $reportFh;

  # The percent identity
  my $coords="$prefix.1coords";
  my $totalLength;
  my @idy;
  open(my $coordsFh, $coords) or die "ERROR: could not read coordinates file $coords: $!";
  while(<$coordsFh>){
    chomp;
    my($s1,$e1,$s2,$e2,$len1,$len2,$idy,$lenR,$lenQ,$covR,$covQ,@contig)=split /\t/;
    push(@idy,$idy);
    $totalLength+= $len1;
  }
  close $coordsFh;
  my $avgIdentity=0;
  my $stdevIdentity=0;
  if(scalar(@idy)){
    $avgIdentity=sum(@idy)/scalar(@idy);
    $stdevIdentity=sprintf("%0.2f",stdev(\@idy));
  }

  return{
    reference      => $refname,
    query          => $queryname,
    ANI            => $ani,
    stdev          => $stdevIdentity,
    percentAligned => $percentAligned,
  };
}



# Reducing dependencies by defining stdev here
sub stdev{
  my($data) = @_;
  if(@$data == 1){
    return 0;
  }
  my $average = sum(@$data)/scalar(@$data);
  my $sqtotal = 0;
  foreach(@$data) {
    $sqtotal += ($average-$_) ** 2;
  }
  my $std = ($sqtotal / (@$data-1)) ** 0.5;
  return $std;
}

sub usage{
  "This script calculates the average nucleotide identity (ANI).
  If multiple queries are given, they will all be compared to
  the reference genome.
  Usage: $0 reference.fasta query.fasta [query2.fasta...]
  --symmetric      When given, the reference and query will be
                   swapped in a second calculated ANI value.
  "
}


