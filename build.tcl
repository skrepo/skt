##############################################################
# Build configuration file
#
# Run run.bat or run.sh to run the build
#
##############################################################

# Build command syntax:
# build <os> <arch> <project_name> <basekit> <list_of_packages>
# where basekit may be: base-tcl-<ver> or base-tk-<ver> or base-tcl-thread-<ver> or base-tk-thread-<ver>

# Example
# Build project sample for linux-ix86 with basekit base-tcl-8.6.3.1 and packages tls-1.6.4 autoproxy-1.5.3
# build linux ix86 sample base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3}
#

# Run project sample not as starpack but from unwrapped vfs
# Project must be built for this platform first!
# run sample

# Run project sample as starpack
# launch sample


# copy from common library
file copy -force [file join skcommon skutil.tcl] skd
file attributes [file join skd skutil.tcl] -permissions a-w

# copy from common library
file copy -force [file join skcommon skutil.tcl] sku
file attributes [file join sku skutil.tcl] -permissions a-w

build linux ix86 sku base-tcl-8.6.3.1 {}

build linux ix86 skd base-tcl-8.6.3.1 {}
run skd
