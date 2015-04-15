##############################################################
# Build configuration file
#
# Run run.bat or run.sh to run the build
#
##############################################################

# Build command syntax:
# build <os> <arch> <project_name> <basekit> <list_of_packages>
# where basekit may be: base-tcl-<ver> or base-tk-<ver> or base-tcl-thread-<ver> or base-tk-thread-<ver>


# Examples

# Prepare library project samplelib. Version number not relevant
# One library project may contain multiple tcl packages with different names
# Artifacts are placed in lib/generic and are ready to use by other projects
#prepare-lib samplelib 0.0.0

# Build project sample for linux-ix86 with basekit base-tcl-8.6.3.1 and packages tls-1.6.4 autoproxy-1.5.3
#build linux ix86 sample base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3}

# Run project sample as starpack - recommended since it tests end-to-end
#launch sample

# Run project sample not as starpack but from unwrapped vfs
# Project must be built for this platform first!
#run sample


prepare-lib sklib 0.0.0

build linux ix86 sku base-tk-8.6.3.1 {sklib-0.0.0 Tkhtml-3.0 tls-1.6.4}

build linux ix86 skd base-tcl-8.6.3.1 {sklib-0.0.0 Expect-5.45.3 cmdline-1.5}


puts "Building deb/rpm dist package"
if {$::tcl_platform(platform) eq "unix"} { 
    set distdir dist/linux-ix86
    file delete -force $distdir
    file mkdir $distdir
    file mkdir $distdir/usr/local/sbin
    file copy build/skd/linux-ix86/skd.bin $distdir/usr/local/sbin/skd
    file copy skd/etc $distdir
    file mkdir $distdir/usr/local/bin
    file copy build/sku/linux-ix86/sku.bin $distdir/usr/local/bin/sku
    cd $distdir
    exec fpm -s dir -t deb -n skapp -v 0.4.0 usr etc
    exec fpm -s dir -t rpm -n skapp -v 0.4.0 usr etc
    cd ../..
} 


launch sku
#exec ./build/sku/linux-ix86/sku.bin


