#!/usr/bin/env perl
# Authors: Lee Katz and Lori Gladney
# Original script by Lori Gladney
# Objective: Run MUMmer dnadiff script between two genomes

use strict;
use warnings;
use File::Temp qw/ tempfile tempdir /;
use File::Basename qw/fileparse basename dirname/;
use File::Slurp qw/read_file write_file/;
#use File::Find qw/find/; # TODO use innate perl to find files instead
use Getopt::Long qw/GetOptions GetOptionsFromString GetOptionsFromArray/;
use Data::Dumper;
use POSIX qw/ceil/;
use threads;
use Cwd qw /abs_path/; # SV

my $currentdir=dirname(abs_path($0)); # SV
my $scriptInvocation=join(" ",$0,@ARGV);

if(-e $ENV{MODULESHOME}){
  use lib "$ENV{MODULESHOME}/init";

  # Load up any GNU modules as long as the module is present.
  eval "use perl qw/module/;";
  if(!$@){
    module("load MUMmer/3.23") or bnLog("WARNING: could not find GNU module MUMmer/3.23. Relying on you for the correct path to dnadiff instead.  You can also export DNADIFF to the location of dnadiff.");
  }
}

########################################################
# CONFIG for applied maths
########################################################

# If MUMmer is not found with the modules command,
# here is a default location for dnadiff.
# You can set it to empty string to let the environment dictate where it is loaded.
my $defaultDnadiff="";

# Required options for bionumerics scripts.
# See Getopt::Long for help with formatting
my @bnOptions=qw(query=s references=s nThreads|numcpus=i localdir=s resultsdir=s shareddir=s tempdir=s clientVersion=s);
my @otherOptions=qw(header! help! dnadiff=s);

# END config
#######################################
my @allOptions=(@otherOptions,@bnOptions);

# global vars
my($messages,$warnings,$lastMessage,$progress,$errors);
$0=basename $0;

exit(main());
sub main{
  my $settings={};

  # Make sure @ARGV is split out correctly.
  # This method however introduces intolerance for spaces in arguments.
  my @argv=();
  for(@ARGV){
    s/^\s+|\s+$//g; # trim
    next if(/^$/);  # ignore empty string
    push(@argv,split(/\s+/,$_));
  }
  @ARGV=@argv;

  # Parse all obvious arguments and remove them from ARGV in the process.
  GetOptions($settings,@allOptions) or die $!;
  die usage() if($$settings{help});

  # Find the location of dnadiff
  $$settings{dnadiff}||=$ENV{DNADIFF} || $defaultDnadiff || `which dnadiff`;
  chomp($$settings{dnadiff}); # in case it was brought in by `which`

  # Set up default options
  $$settings{localdir}||=tempdir("ani-m.local.XXXXXX", CLEANUP => 1, TMPDIR=>1);
  $$settings{nThreads}||=1;
  $$settings{resultsdir}||=tempdir("ani-m.results.XXXXXX", CLEANUP => 1, TMPDIR=>1);
  $$settings{shareddir}||=tempdir("ani-m.shared.XXXXXX", CLEANUP => 1, TMPDIR=>1);
  $$settings{tempdir}||=tempdir("ani-m.temp.XXXXXX", CLEANUP => 1, TMPDIR=>1);
  $$settings{header}//=1;
  $$settings{'alignment-length'}//=1;

  # Set up reporting, output files
  for my $dirname(qw(localdir resultsdir shareddir tempdir)){
    $$settings{$dirname}=~s/^'|'$//g; # remove single quotes that appear at the beginning/end for some reason
    mkdir($$settings{$dirname}) if(!-e $$settings{$dirname});
  }
  mkdir $_ for("$$settings{resultsdir}/results","$$settings{resultsdir}/results/raw","$$settings{resultsdir}/logs");

  # Output files for BN
  $messages="$$settings{resultsdir}/logs/messages.txt"; # log file
  $warnings="$$settings{resultsdir}/logs/warnings.txt";
  $lastMessage="$$settings{resultsdir}/logs/__message__.txt"; # a single message describing the current state
  $progress="$$settings{resultsdir}/logs/__progress__.txt";   # a percentage that I make up
  $errors="$$settings{resultsdir}/logs/error.txt";            # any error messages. Any text here will cause BN to kill this script
  # Create zero-byte files. Their existence gets checked in bnLog() in case they cannot be created here.
  write_file($_,"") for($messages, $warnings, $lastMessage,$progress,$errors);

  # Now that the log files are there, check for dnadiff
  bnLog("ERROR: Could not find `dnadiff`") if(!-e $$settings{dnadiff});
  bnLog("Found dnadiff at $$settings{dnadiff}");

  # Connecting BN options to the original ani-m options
  my $tempdir=$$settings{localdir};

  #Reading in fasta files (assemblies) from the command line into variables $reference and $query
  my $query = $$settings{query} || "";
  bnLog("ERROR: query file '$query' does not exist!\n".Dumper($settings)) if(!-e $query);
  
  #my $queryDir=dirname($query);
  #my $dirContents=`ls -alh $queryDir $$settings{localdir} 2>&1`;
  #bnLog("current dir: $currentdir");
  #bnLog("current dir content ---".`ls -alh $currentdir`."---");
  #bnLog("$queryDir and $$settings{localdir} contain \n$dirContents\n <==");

  # If the query is gzipped, then gunzip it.
  if($query=~/\.gz$/){
    my $b=basename($query,qw(.gz));
    my $newname="$tempdir/$b";
    bnLog("Uncompressing $query => $newname");
    system("gunzip -cv $query > $newname 2>> $messages");
    bnLog("ERROR: could not gunzip $query: $!") if $?;
    $query=$newname;
  }

  # Get any information from an info table
  $$settings{refInfo}=infoTable($$settings{references},$settings);

  # Load up a reference genome array
  my @reference  = keys(%{ $$settings{refInfo} });
  my $numReferenceGenomes=@reference;
  bnLog("ERROR: no reference sequences were given!\n".usage()) if(!$numReferenceGenomes);

  # Make an array of reference genomes, one for each thread.
  # Not using Thread::Queue anymore because it doesn't seem to partition
  # to the threads equally enough.
  my @queue;
  my $numPerThread=ceil($numReferenceGenomes/$$settings{nThreads});
  my $numDefinedQueues=0;
  for(0..$$settings{nThreads}-1){
    my $thisQueue=[splice(@reference,0,$numPerThread)];
    $queue[$_]=$thisQueue;
    $numDefinedQueues++ if(@$thisQueue);
  }
  push(@{$queue[0]},@reference) if(@reference); # just in case there is some reference genome remaining
  bnLog("Initializing multithreading. Number of reference genomes per thread: $numPerThread. Number of threads with reference genomes: $numDefinedQueues",3);


  # Begin a new thread for each nThread. Each thread waits on the queue.
  my @thread;
  for(my $i=0;$i<$numDefinedQueues; $i++){
    $thread[$i]=threads->new(\&aniWorker,$query,$queue[$i],$settings);
  }
  my $numThreads=@thread;

  # This will be the output that's printed
  my $table="";

  # print the header (?)
  if($$settings{header}){
    my @header=qw(query reference percent-aligned ANI genus species subspecies serotype);
    $table.=join("\t",@header)."\n";
  }

  # Gather the output from each thread
  for(my $i=0;$i<@thread;$i++){
    $table.=$thread[$i]->join;
    # Percentage is based on the number of threads finished.
    my $percent=int(($i+1)/$numDefinedQueues*100);
    $percent=5 if($percent<5);
    $percent=99 if($percent > 99); # can't be 100% until the script is done

    bnLog("Joined ".($i+1)." threads",$percent);
  }

  # print it all to file
  my $resultsfile="$$settings{resultsdir}/results/raw/out.tsv";
  open(OUT,">",$resultsfile) or bnLog("ERROR: could not open $resultsfile: $!");
  print OUT $table;
  close OUT;
  
  bnLog("Results file is located at $resultsfile");

  # Just so that I can see it too
  print $table;

  bnLog("Done with ANI vs $numReferenceGenomes reference genomes",100);
  
  return 0;
}

sub aniWorker{
  my($query,$inQueue,$settings)=@_;
  my $TID=threads->tid;

  my $aniTable="";
  my $i;
  #bnLog("TID$TID: I see ".scalar(@$inQueue)." genomes");
  for my $reference(@$inQueue){
    bnLog("Running $query vs $reference (thread$TID)");
    $aniTable.=runAni($reference,$query,$settings);
    $i++;
  }
  return $aniTable;
}

sub runAni{
  my($reference,$query,$settings)=@_;
  my $tempdir=$$settings{localdir};

  # Rename the filename to something easier
  my $refname=basename($reference);
  my $queryname=basename($query);

  my $prefix="$tempdir/".$refname."_".$queryname;

  #Make system call to run the dnadiff script and output any STDERR/STDOUT to dev/null
  my $dnadiffCmd="$$settings{dnadiff} $reference $query -p $prefix 1>>$messages 2>&1";
  system($dnadiffCmd);
  if($?){
    bnLog("Error: Problem with dnadiff between $refname and $queryname: $!\n  Command was $dnadiffCmd",100);
    return join("\t", basename($query), basename($reference), 0, 0, "\t", "\t", "\t", "\t");
  }

  #Objective: parse output from MUMmer script dnadiff e.g. out.report

  #Reading data from an input file
  #The filename containing the data
  my $filename= "$prefix.report";

  my($ani,$alignedbases,$alignedpercent);
  open (DNADIFF, $filename) or die "Cannot locate dnadiff 'out.report' file at $filename. Please make sure the file is in the current directory.\n";
  #Loop through each line in the report, pulling out lines that match AvgIdentity.
  while(<DNADIFF>){

    if (/^AvgIdentity/ && !$ani) {
      #Place the second column value [REF column] of the first line with AvgIdentity into $ani
      #This is the line from the 1:1 alignments
      $ani=(split(/\s+/,$_))[1];
    }

    if (/^AlignedBases/ && !$alignedbases) {
      #Place the second column value [Query column] of the first line with AlignedBases into $aligned
      my $aligned=(split(/\s+/,$_))[2];

      # match the length/percentage
      if($aligned=~/(\d+)\((.*)\%\)/){
        $alignedbases=$1;
        $alignedpercent=$2;
      } else {
        bnLog("Warning: could not parse $aligned properly",-1);
        ($alignedbases,$alignedpercent)=($aligned,$aligned);
      }
    }

  }
  close DNADIFF;

  #Extract relevant information from the species table
  my $refInfo=$$settings{refInfo}{$reference};
  my $genus=$$refInfo{genus} || "";
  my $species=$$refInfo{species} || "";
  my $subspecies=$$refInfo{subspecies} || "";
  my $serotype=$$refInfo{serotype} || "";

  # Put together the table row
  my @output=(basename($query), basename($reference), $alignedpercent, $ani, $genus, $species, $subspecies, $serotype);
  my $returnStr=join("\t", @output)."\n";

  return $returnStr;
}

sub infoTable{
  my($table,$settings)=@_;
  my $result={};
  return $result if(!$table);

  my $dir=dirname($$settings{references});

  bnLog("Reading info table $table",1);

  open(INFO,$table) or bnLog("ERROR: Could not open the info table $table: $!");
  # Read in the header as lowercase, to generate a hash later
  my $header=<INFO>; chomp($header); $header=lc($header);
  my @header=split(/\t/,$header);
  if(!grep {/file/} @header){
    bnLog("ERROR: could not find File in the header.");
  }
  while(<INFO>){
    chomp;
    my @F=split /\t/;
    $_=~s/^\s+|\s+$//g for(@F);

    # Load up a hash of information
    my %F;
    @F{@header}=@F;
    $F{file}="$dir/".basename($F{file});

    if(!-e $F{file}){
      bnLog("ERROR: could not find $F{file}");
    }

    ## Check the existence of the file
    #if(!-e $F{file}){
    #  my $findCommand="find -L reference * -maxdepth 2 -type f -name '$F{file}'";
    #  bnLog("Finding reference genome file with $findCommand");
    #  my $files=`$findCommand`;
    #  chomp($files);
    #  my @file=split(/\n/,$files);
    #  bnLog("ERROR: Could not find $F{file}!") if(!defined($file[0]) || !-e $file[0]);
    #
    #  $F{file}=$file[0];
    #}

    $$result{$F{file}}=\%F;
  }
  return $result;
}

# Write to the appropriate BN logfile.
# The logfiles are defined at the beginning of the
# script and are global variables.
# If percent is <0, then it will not be reported.
sub bnLog{
  my($msg,$percent)=@_;
  $msg=~s/^\s+|\s+$//g; # trim whitespace
  $msg.="\n";           # give it a newline

  $percent=-1 if(!defined($percent));

  # choose the right log file
  my $logfile=$messages;
  if($msg=~/^warn/i){
    $logfile=$warnings;
  }elsif($msg=~/^error/i){
    $logfile=$errors;
  }

  return if(!$logfile);
  die "ERROR! could not find logfile $logfile" if(!-e $logfile);

  # Write the logmsg and the percent done
  write_file($logfile,{append=>1},$msg);
  write_file($progress,{append=>0},$percent) if($percent>=0);

  # If this is a progress message, put that message in the right spot too
  if($msg=~/^(init|running|finished|starting|done|read)/i){
    write_file($lastMessage,{append=>0},$msg);
  }

  # If this is an error message, die
  if($logfile eq $errors){
    $msg.="\nScript was called as such: $scriptInvocation";
    die $msg;
  }

  # Have the print statement last in case the script already dies with the error.
  # Fix the format for the percentage too, keeping in mind that -1 means no progress indicated.
  if($percent<0){
    $percent="";
  } else {
    $percent="$percent% ";
  }
  print STDERR "$percent$msg";
}

sub usage{
  "This script outputs the reference genome, the query genome and the Average nucleotide identity. Multiple reference genomes are allowed; one thread per reference genome.
  Usage: $0 --query query.fasta --references species.tsv [--other options]
  --query               A fasta file to query with; can be gzipped.
  --references          A tsv file where the first column is the location to reference genomes and where the other columns yield metadata. The top row is a descriptive header describing each column.  Each fasta file must be in the same directory as this spreadsheet.

  --noheader            Do not display the header
  --dnadiff  $defaultDnadiff  Location of dnadiff.  Alternatively, you can have the environmental variable DNADIFF exported.

  --nThreads    1
  --localdir    /tmp    Temporary directory for this instance
  --resultsdir  /tmp    Directory to place results and log files
  --shareddir   /tmp    Directory where data are shared between executables
  --tempdir     /tmp    Scratch directory where data are shared between executables
  "
}
