# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

proc this-arch {} {
    switch -glob $::tcl_platform(machine) {
        i?86 {return ix86}
        x86_64 {return x86_64}
        default {error "Unrecognized CPU architecture"}
    }
}

proc this-os {} {
    switch -glob $::tcl_platform(os) {
        Linux {return linux}
        Windows* {return win32}
        default {error "Unrecognized OS"}
    }
}


# path to platform dependent libs in the lib dir - this is for the need of the build script - ix86 only!!! Should work on 64-bit as well
lappend auto_path [file join lib [this-os]-ix86]
# path to generic libs in the lib dir
lappend auto_path [file join lib generic]

package require http
package require vfs::zip
package require tls
http::register https 443 [list tls::socket]


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

proc unzip {zipfile {destdir .}} {
  set mntfile [vfs::zip::Mount $zipfile $zipfile]
  foreach f [glob [file join $zipfile *]] {
    file copy $f $destdir
  }
  vfs::zip::Unmount $mntfile $zipfile
}

# convert pkg-name-1.2.3 into "pkg-name 1.2.3" or
# convert linux-ix86 into "linux ix86"
proc split-last-dash {s} {
  set dashpos [string last - $s]
  if {$dashpos > 0} {
    return [string replace $s $dashpos $dashpos " "]
  } else {
    error "Wrong name to split: $s. It should contain at least one dash"
  }
}

proc oscompiler {os} {
  if {$os eq "linux"} {
    return $os-glibc2.3
  } else {
    return $os
  }
}


# based on the pkgname return candidate names of remote files (to be used in url)
proc get-fetchnames {os arch pkgname ver} {
  switch -glob $pkgname {
    base-* {
      set res "application-$pkgname-$ver-[oscompiler $os]-$arch"
      if {$os eq "win32"} {
        set res $res.exe
      }
      return $res
    }
    default {
      return [list "package-$pkgname-$ver-tcl.tm" "package-$pkgname-$ver-[oscompiler $os]-$arch.zip"]
    }
  }
}




#TODO support url redirect (Location header)
proc wget {url filepath} {
  set fo [open $filepath w]
  set tok [http::geturl $url -channel $fo]
  close $fo
  if {[http::ncode $tok] != 200} {
    file delete $filepath
    set retcode [http::code $tok]
    http::cleanup $tok
    return $retcode
  }
  http::cleanup $tok
  return
}





#proc copy-base {os arch pkgname ver proj} {
#  prepare-pkg $os $arch $pkgname $ver
#  file copy -force [file join lib $os-$arch $pkgname-$ver] [file join build $proj $os-$arch]
#}

# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir


# first prepare-pkg and copy from lib to build
proc copy-pkg {os arch pkgname ver proj} {
  prepare-pkg $os $arch $pkgname $ver
  set libdir [file join build $proj $os-$arch $proj.vfs lib]
  puts "Copying package $pkgname-$ver to $libdir"
  if {\
    [catch {file copy -force [file join lib $os-$arch $pkgname-$ver] $libdir}] &&\
    [catch {file copy -force [file join lib generic $pkgname-$ver]   $libdir}]} {
      #if both copy attempts failed raise error
      error "Could not find $pkgname-$ver neither in lib/$os-$arch nor lib/generic"
  }
}

proc prepare-pkg {os arch pkgname ver} {
  file mkdir [file join lib $os-$arch]
  set target_path_depend [file join lib $os-$arch $pkgname-$ver]
  set target_path_indep [file join lib generic $pkgname-$ver]
  # nothing to do if pkg exists in lib dir, it may be file or dir
  if {[file exists $target_path_depend]} {
    puts "Already prepared: $target_path_depend"
    return
  }
  if {[file exists $target_path_indep]} {
    puts "Already prepared: $target_path_indep"
    return
  }
  fetch-pkg $os $arch $pkgname $ver
  puts "Preparing package $pkgname-$ver to place in lib folder"
  set candidates [get-fetchnames $os $arch $pkgname $ver]
  foreach cand $candidates {
    set cand_path [file join downloads $cand]
    if {[file isfile $cand_path]} {
      switch -glob $cand {
        application-* {
          file copy -force $cand_path $target_path_depend
          return 
        }
        package-*.zip {
          file mkdir $target_path_depend
          unzip $cand_path $target_path_depend
          return
        }
        package-*-tcl.tm {
          file mkdir $target_path_indep
          file copy $cand_path [file join $target_path_indep $pkgname-$ver.tcl]
          pkg_mkIndex $target_path_indep
          return
        }
        default {}
      }
    }
  }
  error "Could not find existing file from candidates: $candidates"
}
 


proc fetch-pkg {os arch pkgname ver} {
  file mkdir downloads
  set candidates [get-fetchnames $os $arch $pkgname $ver]
  # return if at least one candidate exists in downloads
  foreach cand $candidates {
    if {[file isfile [file join downloads $cand]]} {
      puts "Already downloaded: $cand"
      return
    }
  }
  set repourl https://raw.githubusercontent.com/skrepo/activestate/master/teacup/$pkgname
  foreach cand $candidates {
    puts -nonewline "Trying to download $cand...     "
    flush stdout
    set url $repourl/$cand
    # return on first successful download
    if {[wget $url [file join downloads $cand]] eq ""} {
      puts "DONE"
      return
    } else {
      puts "FAIL"
    }
  }
  error "Could not fetch package $pkgname-$ver for $os-$arch"
}


proc suffix_exec {os} {
  array set os_suffix {
    linux .bin
    win32 .exe
  }
  return $os_suffix($os)
}

# recursively copy contents of the $from dir to the $to dir 
# while overwriting items in $to if necessary
proc copy-merge {from to} {
    foreach f [glob [file join $from *]] {
        if {[file isdirectory $f]} {
            set tail [lindex [file split $f] end]
            set new_to [file join $to $tail]
            file mkdir $new_to
            copy-merge $f $new_to
        } else {
            #puts "Copying $f"
            file copy -force $f $to
        }
    }
}


proc build {os arch proj base {packages {}}} {
  puts "\nStarting build ($os $arch $proj $base $packages)"
  if {![file isdirectory $proj]} {
    puts "Could not find project dir $proj"
    return
  }
  set bld [file join build $proj $os-$arch]
  puts "Cleaning build dir $bld"
  file delete -force $bld
  file mkdir [file join $bld $proj.vfs lib]
  # we don't copy base-tcl/tk to build folder, only in lib is enough - hence prepare-pkg
  prepare-pkg $os $arch {*}[split-last-dash $base]
  foreach pkgver $packages {
    copy-pkg $os $arch {*}[split-last-dash $pkgver] $proj
  }
  set vfs [file join $bld $proj.vfs]
  puts "Copying project source files to $vfs"

  copy-merge $proj $vfs
  set cmd [list [info nameofexecutable] sdx.kit wrap [file join $bld $proj[suffix_exec $os]] -vfs [file join $bld $proj.vfs] -runtime [file join lib $os-$arch $base]]
  puts "Building starpack $proj"
  puts $cmd
  exec {*}$cmd
}

proc run {proj} {
    exec [info nameofexecutable] [file join build $proj [this-os]-[this-arch] $proj.vfs main.tcl] >@stdout
}

proc launch {proj} {
    puts "Launching $proj"
    exec [file join build $proj [this-os]-[this-arch] $proj[suffix_exec [this-os]]] >@stdout
}

proc prepare-lib {pkgname ver} {
    set dest [file join lib generic $pkgname-$ver]
    file delete -force $dest
    file mkdir $dest
    copy-merge $pkgname $dest
    pkg_mkIndex $dest
}


#platforminfo

source build.tcl


