package provide linuxdeps 0.0.0

namespace eval ::linuxdeps {
    variable pkgmgr2cmd 
    dict set pkgmgr2cmd apt-get "apt-get -fy install" 
    dict set pkgmgr2cmd zypper "zypper --non-interactive install" 
    dict set pkgmgr2cmd yum "yum -y install"


    variable lib2pkg

    # apt-file search libXss.so.1
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

    # zypper search --provides libXss.so.1
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

    # yum whatprovides libXss.so.1
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


    #TODO remove temporary testing hack
    #variable templib libz.so.1
    variable templib ""


    namespace export is-openvpn-installed find-pkg-mgr find-pkg-mgr-cmd lib-to-pkg tk-missing-lib
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


proc ::linuxdeps::find-pkg-mgr-cmd {} {
    variable pkgmgr2cmd
    set pkg_mgr [find-pkg-mgr]
    if {[llength $pkg_mgr] > 0} {
        return [dict get $pkgmgr2cmd $pkg_mgr]
    }
    return ""
}


# Try to load Tk and return missing dynamic library name 
# If Tk loaded OK or no X11 or no Tk at all return empty string
proc ::linuxdeps::tk-missing-lib {} {

    #TODO remove
    variable templib
    if {[llength $templib] > 0} {
        set temp $templib
        set templib ""
        return $temp
    }

    if {[catch {package require Tk} out err]} {
        #puts "OUT: $out"
        #puts "ERR: $err"
        switch -regexp -matchvar tokens $out {
            {^can't find package (.*)} {
                #the entire Tk package is missing
                return ""
            }
            {^couldn't load file ".*": (.*): cannot open shared object file.*} {
              return [lindex $tokens 1]
            }
            {^no display name and no $DISPLAY environment variable.*} {
                # no X11
                return ""
            }
            default {
              package require Tk
            }
        }
        # When Tk package missing:
        #OUT: can't find package dksjfds
        #ERR: -code 1 -level 0 -errorstack {INNER {invokeStk1 package require dksjfds} CALL tk-missing-lib} -errorcode {TCL PACKAGE UNFOUND} -errorinfo {can't find package dksjfds
        #    while executing
        #"package require dksjfds"} -errorline 2
        
        # When OS library is missing:
        #OUT: couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
        #ERR: -code 1 -level 0 -errorstack {INNER {load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk} UP 2 CALL tk-missing-lib} -errorcode NONE -errorinfo {couldn't load file "/tmp/tcl_CJ5xeo": libXss.so.1: cannot open shared object file: No such file or directory
        #    while executing
        #"load /home/sk/skt/build/sandbox/linux-ix86/sandbox.bin/lib/libtk8.6.so Tk"
        #    ("package ifneeded Tk 8.6.3" script)
        #    invoked from within
        #"package require Tk"} -errorline 2

        # When no X11 running:
        #root@ubuntu:~# tclsh
        #% package require Tk
        #no display name and no $DISPLAY environment variable
        #% catch {[package require Tk]} out err
        #1
        #% puts $out
        #no display name and no $DISPLAY environment variable
        #% puts $err
        #-code 1 -level 0 -errorstack {INNER {load /usr/lib/x86_64-linux-gnu/libtk8.6.so Tk}} -errorcode {TK NO_DISPLAY} -errorinfo {no display name and no $DISPLAY environment variable
        #    while executing
        #"load /usr/lib/x86_64-linux-gnu/libtk8.6.so Tk"
        #    ("package ifneeded Tk 8.6.1" script)
        #    invoked from within
        #"package require Tk"} -errorline 1
    } else {
        return ""
    }
}

proc ::linuxdeps::lib-to-pkg {lib} {
    variable pkgmgr2cmd
    variable lib2pkg
    set pkg_mgr [find-pkg-mgr]
    if {[llength $pkg_mgr] > 0} {
        if {[dict exists $lib2pkg $pkg_mgr $lib]} {
            set pkg [dict get $lib2pkg $pkg_mgr $lib]
            return $pkg
        }
    }
}
 


# @deprecated
proc ::linuxdeps::tk-install-lib {lib} {
    variable pkgmgr2cmd
    variable lib2pkg
    set pkg_mgr [find-pkg-mgr]
    # Best effort principle, no error if it could not find pkg_mgr or package
    if {[llength $pkg_mgr] > 0} {
        set cmd [dict get $pkgmgr2cmd $pkg_mgr]
        if {[dict exists $lib2pkg $pkg_mgr $lib]} {
            set pkg [dict get $lib2pkg $pkg_mgr $lib]
            exec {*}$cmd $pkg >&@ stdout
        } else {
            puts "Could not locate $lib"
        }
    } else {
        puts "Could not locate $lib"
    }
}



# @deprecated
proc ::linuxdeps::tk-install {} {
    set last_missing_lib ""
    for {set i 0} {$i<5} {incr i} {
        set missing_lib [tk-missing-lib]
        puts $missing_lib
        if {[llength $missing_lib] != 0 && $missing_lib ne $last_missing_lib} {
            tk-install-lib $missing_lib
            set last_missing_lib $missing_lib
        } else {
            break
        }
    }
}

proc ::linuxdeps::is-openvpn-installed {} {
    # Unfortunately openvpn always returns exit code 1
    catch {exec openvpn --version} out err
    # So check if openvpn output starts with "OpenVPN"
    return [expr {[string first OpenVPN $out] == 0}]
}
 

# Check if openvpn installed, install if needed
# No errors raised, best effort
# @deprecated
proc ::linuxdeps::openvpn-install {} {
    variable pkgmgr2cmd
    if {![is-openvpn-installed]} {
        set pkg_mgr [find-pkg-mgr]
        if {[llength $pkg_mgr] > 0} {
            set cmd [dict get $pkgmgr2cmd $pkg_mgr]
            exec {*}$cmd openvpn >&@ stdout
        } else {
            puts "Could not locate openvpn"
        }
    }
}


