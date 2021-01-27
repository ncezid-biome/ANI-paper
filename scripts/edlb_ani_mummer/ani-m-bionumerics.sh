#!/bin/bash
#
# Launcher for executables where the underlying DRM is OpenGridEngine (or associated) #

# LK
#$ -cwd

export PATH=$PATH:/usr/local/bin:/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/sbin
source /etc/profile.d/modules.sh
module load perl/5.16.1-MT

export SYSDIR=/scicomp/home/gzu2/src/edlb_ani_mummer

#PERLSCRIPT=$SYSDIR/bin/ani-m-bionumerics/ani-m-bionumerics.pl
PERLSCRIPT=$SYSDIR/ani-m-bionumerics.pl
PERL=$(which perl)

NSLOTS=${NSLOTS:-32}; # LK


#*******************************************************************************
# You should not need to change anything below
#*******************************************************************************
. $SYSDIR/executables/setenv.sh

BINARY=$BINDIR/$MYNAME

echo "PERL is $PERL"; # LK
echo "Number of slots allocated: $NSLOTS"
if [[ -s $PE_HOSTFILE ]]; then
     echo "The hosts are: "
     /bin/cat $PE_HOSTFILE
fi

# Could check here that the hosts are all on the same machine # i.e. $PE_HOSTFILE should consist of a single line. CalculationEngine # executables cannot be run across machines

#*******************************************************************************
# Prepare the extra command line
#*******************************************************************************
cmdLineExtra=""
if [ ! -z "$NSLOTS" ]; then
     cmdLineExtra="$cmdLineExtra --nThreads=$NSLOTS"
fi

# Use a local directory on the computation node instead of doing temporary stuff on the network drive
if [ ! -z "$TMPDIR" ]; then
    cmdLineExtra="$cmdLineExtra --localdir=$TMPDIR"
fi

echo "Extra command line: $cmdLineExtra"

#*******************************************************************************
# Now run the algorithm
#*******************************************************************************

$PERL "$PERLSCRIPT" "$@" $cmdLineExtra
exitCode=$?

echo "Exit code: $exitCode"

# Examine the exit code. If non-zero and we do not have a custom error file: write something in the error file,
# this allows the engine to see that something went wrong (e.g. crash). Do only if there is no job error
# file. Ignore the presence of the DRM error file, it is not used to determine job error status.
errorFile="logs/error.txt"
drmErrorFile="errors.txt"

if [[ ( "$exitCode" != 0 ) && ( ! -s $errorFile ) ]]; then
   echo "Non-zero exitcode ($exitCode) detected: putting custom error string in $errorFile"
   echo "Algorithm exited with non-zero exit code $exitCode. " >> $errorFile

   # If the DRM error file exists: append that to the error file, might give a clue as to what went wrong
   if [[ -s $drmErrorFile ]]; then
       /bin/cat $drmErrorFile >> $errorFile
   fi
fi

exit $exitCode

