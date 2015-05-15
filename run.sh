#!/bin/sh

proc=`uname -p`

if [ "$proc"="x86_64" ]; then
    cp ./lib/linux-x86_64/base-tcl-8.6.3.1 base-tcl
else
    cp ./lib/linux-ix86/base-tcl-8.6.3.1 base-tcl
fi

chmod +x base-tcl
./base-tcl bootstrap.tcl "$@"

