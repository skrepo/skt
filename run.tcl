
proc platforminfo {} {
    puts "Script name: $::argv0"
    puts "Arguments:\n[join $::argv \n]"
    puts "Current directory: [pwd]"
    puts "This is Tcl version $::tcl_version , patchlevel $::tcl_patchLevel"
    puts "[info nameofexecutable] is [info tclversion] patch [info patchlevel]"
    puts "Directory(s) where package require will search:"
    puts "$::auto_path"
    puts "tcl_libPath = $::tcl_libPath"  ;# May want to skip this one
    puts "tcl_library = $::tcl_library"
    puts "info library = [info library]"
    puts "Shared libraries are expected to use the extension [info sharedlibextension]"
    puts "platform information:"
    parray ::tcl_platform
}


platforminfo

proc platform_path {} {
    # assume ix86 - hopefully only 32-bit builds needed
    switch -glob $::tcl_platform(os) {
        Linux {return lib/linux-ix86}
        Windows* {return lib/win32-ix86}
        default {error "Unrecognized platform"}
    }
}

lappend auto_path [platform_path]
lappend auto_path lib/generic

# test package/module
package require aes

# run sample project without building
#source sample/main.tcl

# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir
proc copy-pkg {os arch pkgname ver proj} {
  # copy regular packages to build dir
  # recognize base-tcl packages and place them properly
  # delete if another package version present
}

proc prepare-pkg {os arch pkgname ver} {
}

proc fetch-pkg {os arch pkgname ver} {

}



#https://github.com/skrepo/activestate/blob/master/teacup/base-tk-thread/application-base-tk-thread-8.6.4.0.298892-linux-glibc2.3-ix86

# convert pkg-name-1.2.3 into "pkg-name 1.2.3"
proc split-pkg-ver {pkgver} {
  set dashpos [string last - $pkgver]
  if {$dashpos > 0} {
    return [string replace $pkgver $dashpos $dashpos " "]
  } else {
    error "Wrong package name: $pkgver. It should be pkgname-1.2.3"
  }
}

proc build {os arch proj {packages {}}} {
  set bld [file join build $proj $os-$arch]
  file delete -force $bld
  file mkdir $bld
  foreach pkgver $packages {
    copy-pkg $os $arch {*}[split-pkg-ver $pkgver] $proj

  }


}


build linux ix86 another {base-tcl-8.6.3.1 tls-1.6.4}
build win32 ix86 another {base-tcl-8.6.3.1 tls-1.6.4}


