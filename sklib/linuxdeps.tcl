package provide linuxdeps 0.0.0

namespace eval ::linuxdeps {
    variable pkgmgr2cmd 
    dict set pkgmgr2cmd apt-get "apt-get -fy install" 
    dict set pkgmgr2cmd zypper "zypper --non-interactive install" 
    dict set pkgmgr2cmd yum "yum -y install"


    variable lib2pkg

    dict set lib2pkg apt-get    libXft.so.2             libxft2
    dict set lib2pkg apt-get    libX11.so.6             libx11-6	    
    dict set lib2pkg apt-get    libfreetype.so.6        libfreetype6	
    dict set lib2pkg apt-get    libfontconfig.so.1      libfontconfig1	
    dict set lib2pkg apt-get    libXrender.so.1         libxrender1	    
    dict set lib2pkg apt-get    libXss.so.1             libxss1		    
    dict set lib2pkg apt-get    libXext.so.6            libxext6	    
    dict set lib2pkg apt-get    libz.so.1               zlib1g		    
    dict set lib2pkg apt-get    libxcb.so.1             libxcb1		    
    dict set lib2pkg apt-get    libexpat.so.1           libexpat1	    
    dict set lib2pkg apt-get    libXau.so.6             libxau6		    
    dict set lib2pkg apt-get    libXdmcp.so.6           libxdmcp6	    


    dict set lib2pkg zypper     libXft.so.2             libXft2
    dict set lib2pkg zypper     libX11.so.6             libX11-6		
    dict set lib2pkg zypper     libfreetype.so.6        libfreetype6	
    dict set lib2pkg zypper     libfontconfig.so.1      fontconfig	
    dict set lib2pkg zypper     libXrender.so.1         libXrender1	
    dict set lib2pkg zypper     libXss.so.1             libXss1	
    dict set lib2pkg zypper     libXext.so.6            libXext6		
    dict set lib2pkg zypper     libz.so.1               libz1		
    dict set lib2pkg zypper     libxcb.so.1             libxcb1		
    dict set lib2pkg zypper     libexpat.so.1           libexpat1	
    dict set lib2pkg zypper     libXau.so.6             libXau6		
    dict set lib2pkg zypper     libXdmcp.so.6           libXdmcp6	


    dict set lib2pkg yum        libXft.so.2             libXft
    dict set lib2pkg yum        libX11.so.6             libX11
    dict set lib2pkg yum        libfreetype.so.6        freetype
    dict set lib2pkg yum        libfontconfig.so.1      fontconfig
    dict set lib2pkg yum        libXrender.so.1         libXrender
    dict set lib2pkg yum        libXss.so.1             libXScrnSaver
    dict set lib2pkg yum        libXext.so.6            libXext
    dict set lib2pkg yum        libz.so.1               zlib
    dict set lib2pkg yum        libxcb.so.1             libxcb
    dict set lib2pkg yum        libexpat.so.1           expat
    dict set lib2pkg yum        libXau.so.6             libXau
    dict set lib2pkg yum        libXdmcp.so.6           libXdmcp


    namespace export install
    namespace ensemble create
}


#In Debian: /etc/debian_version
#In Ubuntu: lsb_release -a or /etc/debian_version
#In Redhat: cat /etc/redhat-release
#In Fedora: cat /etc/fedora-release
#Read cat /proc/version

# Prefer feature detection over distro detection

proc ::linuxdeps::find-pkg-mgr {} {
    # detect in order: zypper, apt-get, yum (others: pacman, portage, urpmi, dnf, slapt-geti emerge)
    set candidates {zypper apt-get yum}
    foreach c $candidates {
      if {![catch {exec $c --version}]} {
        return $c
      }
    }
    return ""
}


proc ::linuxdeps::tk-missing-dep {} {
    if {[catch {package require Tk} out err]} {
        #puts "OUT: $out"
        #puts "ERR: $err"
        switch -regexp -matchvar tokens $out {
            {^can't find package (.*)} {
              #the entire Tk package is missing - propagate the error
              package require Tk
            }
            {^couldn't load file ".*": (.*): cannot open shared object file.*} {
              return [lindex $tokens 1]
            }
            default {
              package require Tk
            }
        }
        # When Tk package missing:
        #OUT: can't find package dksjfds
        #ERR: -code 1 -level 0 -errorstack {INNER {invokeStk1 package require dksjfds} CALL tk-missing-dep} -errorcode {TCL PACKAGE UNFOUND} -errorinfo {can't find package dksjfds
        #    while executing
        #"package require dksjfds"} -errorline 2
        
        # When OS library is missing:
        #OUT: couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
        #ERR: -code 1 -level 0 -errorstack {INNER {load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk} UP 2 CALL tk-missing-dep} -errorcode NONE -errorinfo {couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
        #    while executing
        #"load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk"
        #    ("package ifneeded Tk 8.6.3" script)
        #    invoked from within
        #"package require Tk"} -errorline 2
    } else {
        return ""
    }
}

proc ::linuxdeps::tk-install-lib {pkg_mgr lib} {
    variable pkgmgr2cmd
    variable lib2pkg

    set cmd [dict get $pkgmgr2cmd $pkg_mgr]
    # TODO handle libraries not found in lib2pkg
    set pkg [dict get $lib2pkg $pkg_mgr $lib]

    exec {*}$cmd $pkg >&@ stdout
}



proc ::linuxdeps::install {} {
    set pkg_mgr [find-pkg-mgr]
    puts $pkg_mgr
    set missing_lib [tk-missing-dep]
    puts $missing_lib
    if {[llength $missing_lib] != 0} {
        tk-install-lib $pkg_mgr $missing_lib
    }
}
