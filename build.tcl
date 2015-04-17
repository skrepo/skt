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
#exec ./build/sample/linux-ix86/sample.bin

# Run project sample not as starpack but from unwrapped vfs
# Project must be built for this platform first!
#run sample


proc install-fpm {} {
    exec -- apt-get update --fix-missing
    exec -- apt-get -fy install git ruby-dev gcc rpm
    exec -- gem install fpm
}

proc build-deb-rpm {arch_exact} {
    set arch [generalize-arch $arch_exact]
    puts "Building deb/rpm dist package"
    if {$::tcl_platform(platform) eq "unix"} { 
        set distdir dist/linux-$arch
        file delete -force $distdir
        file mkdir $distdir
        file mkdir $distdir/usr/local/sbin
        file copy build/skd/linux-$arch/skd.bin $distdir/usr/local/sbin/skd
        file copy skd/exclude/etc $distdir
        file mkdir $distdir/usr/local/bin
        file copy build/sku/linux-$arch/sku.bin $distdir/usr/local/bin/sku
        cd $distdir
        set fpmopts "-a $arch_exact -s dir -n skapp -v 0.4.0 --before-install ../../skd/exclude/skd.preinst --after-install ../../skd/exclude/skd.postinst --before-remove ../../skd/exclude/skd.prerm --after-remove ../../skd/exclude/skd.postrm usr etc"
        exec fpm -t deb {*}$fpmopts >&@ stdout
        exec fpm -t rpm --rpm-autoreqprov {*}$fpmopts >&@ stdout
        cd ../..
    } 
}

proc build-skd-sku {} {
    foreach arch_exact {i386 x86_64} {
        #build win32 $arch_exact sku base-tk-8.6.3.1 {tls-1.6.4}
        build linux $arch_exact sku base-tk-8.6.3.1 {sklib-0.0.0 Tkhtml-3.0 tls-1.6.4}
        build linux $arch_exact skd base-tcl-8.6.3.1 {sklib-0.0.0 Expect-5.45.3 cmdline-1.5}
        build-deb-rpm $arch_exact
    }
    puts "Install from dpkg"
    exec sudo dpkg -i ./dist/linux-x86_64/skapp_0.4.0_amd64.deb >&@ stdout
    exec ./build/sku/linux-ix86/sku.bin
}

prepare-lib sklib 0.0.0

#build-skd-sku

build linux x86_64 sandbox base-tk-8.6.3.1 {sklib-0.0.0}
exec ./build/sandbox/linux-x86_64/sandbox.bin
