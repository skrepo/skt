#!/bin/sh

proc=`uname -p`

if [ "$proc"="x86_64" ]; then
    ./lib/linux-x86_64/base-tcl-8.6.3.1 bootstrap.tcl "$@"
else
    ./lib/linux-ix86/base-tcl-8.6.3.1 bootstrap.tcl "$@"
fi


