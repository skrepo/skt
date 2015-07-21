##############################################################
# Build configuration file
#
# Run run.bat or run.sh to run the build
#
##############################################################

# Build command syntax:
# build <os> <arch> <project_name> <basekit> <list_of_packages>
# where basekit may be: base-tcl-<ver> or base-tk-<ver> or base-tcl-thread-<ver> or base-tk-thread-<ver>
#


# Examples

# Prepare library project samplelib. Version number not relevant
# One library project may contain multiple tcl packages with different names
# Artifacts are placed in lib/generic and are ready to use by other projects
#prepare-lib samplelib 0.0.0

# Build project sample for linux-ix86 with basekit base-tcl-8.6.3.1 and packages tls-1.6.4 autoproxy-1.5.3
#build linux ix86 sample base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3}

# Run project sample as starpack - recommended since it tests end-to-end
#ex ./build/sample/linux-ix86/sample.bin

# Run project sample not as starpack but from unwrapped vfs
# Project must be built for this platform first!
#run sample

proc copy-flags {countries {sizes {16 24 64}}} {
    set from [file normalize ../images/flag/shiny]
    set to [file normalize ./sku/images]
    foreach size $sizes {
        file mkdir [file join $to $size flag]
        foreach c $countries {
            file copy -force [file join $from $size $c.png] [file join $to $size flag]
        }
    }
}


proc build-sku {os arch} {
    spit sku/builddate.txt $::builddate
    copy-flags {PL GB UK DE FR US}
    github-repo csp securitykiss-com  ;#https://github.com/securitykiss-com/csp/archive/0.1.0.zip
    #build $os $arch sku base-tk-8.6.3.1 {sklib-0.0.0 Tkhtml-3.0 tls-1.6.4 Tclx-8.4 cmdline-1.5 anigif-1.3 json-1.3.3 snit-2.3.2 doctools-1.4.19 textutil::expander-1.3.1 csp-0.1.0}
    build $os $arch sku base-tk-8.6.3.1 {sklib-0.0.0 tls-1.6.4 Tclx-8.4 cmdline-1.5 anigif-1.3 json-1.3.3 csp-0.1.0}

    # this is necessary to prevent "cp: cannot create regular file ‘/usr/local/sbin/sku.bin’: Text file busy"
    if {[file exists /usr/local/bin/sku.bin]} {
        ex sudo mv /usr/local/bin/sku.bin /usr/local/bin/sku-prev.bin
    }
    ex sudo cp build/sku/linux-x86_64/sku.bin /usr/local/bin/sku.bin
}

proc build-skd {os arch} {
    spit skd/builddate.txt $::builddate
    # use the sku version as skd version
    spit skd/buildver.txt [slurp sku/buildver.txt]
    build $os $arch skd base-tk-8.6.3.1 {sklib-0.0.0 Tclx-8.4}
    #ex sudo service skd stop

    # this is necessary to prevent "cp: cannot create regular file ‘/usr/local/sbin/skd.bin’: Text file busy"
    # do the same when auto-upgrading inside SKD
    if {[file exists /usr/local/sbin/skd.bin]} {
        ex sudo mv /usr/local/sbin/skd.bin /usr/local/sbin/skd-prev.bin
    }
    ex sudo cp build/skd/linux-x86_64/skd.bin /usr/local/sbin/skd.bin

    ex sudo cp skd/exclude/etc/init.d/skd /etc/init.d/skd
    #ex sudo service skd restart
}

proc build-deb-rpm {arch_exact} {
    set arch [generalize-arch $arch_exact]
    puts "Building deb/rpm dist package"
    install-fpm
    if {$::tcl_platform(platform) eq "unix"} { 
        set distdir dist/linux-$arch
        file delete -force $distdir
        file mkdir $distdir
        file mkdir $distdir/usr/local/sbin
        file copy build/skd/linux-$arch/skd.bin $distdir/usr/local/sbin/skd.bin
        file copy skd/exclude/etc $distdir
        file mkdir $distdir/usr/local/bin
        file copy build/sku/linux-$arch/sku.bin $distdir/usr/local/bin/sku.bin
        file copy sku/exclude/sku $distdir/usr/local/bin/sku
        cd $distdir
        set fpmopts "-a $arch_exact -s dir -n skapp -v 0.4.0 --before-install ../../skd/exclude/skd.preinst --after-install ../../skd/exclude/skd.postinst --before-remove ../../skd/exclude/skd.prerm --after-remove ../../skd/exclude/skd.postrm usr etc"
        ex fpm -t deb {*}$fpmopts
        ex fpm -t rpm --rpm-autoreqprov {*}$fpmopts
        cd ../..
    } 
}

proc build-total {} {
    foreach arch_exact {x86_64} {
        build-sku linux $arch_exact
        build-skd linux $arch_exact
        build-deb-rpm $arch_exact
    }
    puts "Install from dpkg"
    ex sudo dpkg -i ./dist/linux-x86_64/skapp_0.4.0_amd64.deb
    #ex ./build/sku/linux-ix86/sku.bin
}

proc release {} {
    #TODO extract buildver.txt and use for release
    #TODO /home/sk/seckiss/distskt
}

proc test {} {
    package require tcltest
    tcltest::configure -testdir [file normalize ./sklib]
    tcltest::runAllTests
}


prepare-lib sklib 0.0.0


#build linux x86_64 sandbox base-tk-8.6.3.1 {sklib-0.0.0 Tclx-8.4}
#build linux x86_64 sandbox base-tk-8.6.3.1 {sklib-0.0.0 tls-1.6.4}
#ex ./build/sandbox/linux-x86_64/sandbox.bin

#build-total
#
#package require i18n
#i18n code2msg ./sku/main.tcl {es pl} ./sku/messages.txt 

build-sku linux x86_64
build-skd linux x86_64
#build-deb-rpm x86_64


#build linux ix86 sample base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3 sklib-0.0.0 Tclx-8.4}
#ex ./build/sample/linux-ix86/sample.bin

#doc ./lib/generic/csp-0.1.0/csp.man
#ex xdg-open ./lib/generic/csp-0.1.0/csp.html

exit

#puts "Running with sudo"
#ex sudo ./build/sandbox/linux-x86_64/sandbox.bin
#puts "Running without"
#ex ./build/sandbox/linux-x86_64/sandbox.bin
