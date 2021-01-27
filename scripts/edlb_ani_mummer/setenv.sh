#!/bin/sh

# Script called by the algorithm scripts, preparing the environment to run the algorithm in.

# Set some directories
export EXEDIR=$SYSDIR/executables
export BINDIR=$SYSDIR/bin
export LIBDIR=$SYSDIR/lib

export TOOLSDIR=$SYSDIR/tools
export TOOLS=$TOOLSDIR:$TOOLSDIR/spades/SPAdes-3.5.0-Linux/bin
# export TOOLS=$TOOLSDIR/velvet:$TOOLSDIR/ncbi:$TOOLSDIR/custom:$TOOLSDIR/blast

export LD_LIBRARY_PATH=$LIBDIR:$LIBDIR/node
export PATH=$PATH:$BINDIR:$TOOLS:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
