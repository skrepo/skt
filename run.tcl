
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

linux ix86
win32 ix86

# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build_* dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir
proc copy-pkg {os arch name ver build_dir clean_other_ver} {
  #add version, download and make the package ready to use
  # delete if another package version present
}

proc prepare-pkg {os arch name ver} {
}

proc fetch-pkg {os arch name ver} {

}


set pkgname(base-tk-thread-linux-ix86) application-base-tk-thread-8.6.4.0.298892-linux-glibc2.3-ix86

https://github.com/skrepo/activestate/blob/master/teacup/base-tk-thread/application-base-tk-thread-8.6.4.0.298892-linux-glibc2.3-ix86




proc build {os arch proj {packages {}}} {
  set bld build_$proj
  file delete -force $bld
  file mkdir $bld
  #::puts [info nameofexecutable]
  ::file copy ./lib/linux/ix86/application-base-tcl-8.6.3.1.298685-linux-glibc2.3-ix86 $bld
  #exec cp [info nameofexecutable] $bld


}


build linux ix86 another {base-tcl-8.6.3.1 tls-1.6.4}
build win32 ix86 another {base-tcl-8.6.3.1 tls-1.6.4}


