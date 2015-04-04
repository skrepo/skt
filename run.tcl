
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
package require http
package require tls
package require vfs::zip
http::register https 443 [list tls::socket]

# run sample project without building
# NOTE: package versions are not respected!!!
#source sample/main.tcl

proc unzip {zipfile {destdir .}} {
  set mntfile [vfs::zip::Mount $zipfile $zipfile]
  foreach f [glob $zipfile/*] {
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

proc osext {os} {
  if {$os eq "linux"} {
    return $os-glibc2.3
  } else {
    return $os
  }
}

proc get-fetchnames {os arch pkgname ver} {
  switch -glob $pkgname {
    base-* {
      set res "application-$pkgname-$ver-[osext $os]-$arch"
      if {$os eq "win32"} {
        set res $res.exe
      }
      return $res
    }
    default {
      return [list "package-$pkgname-$ver-tcl.tm" "package-$pkgname-$ver-[osext $os]-$arch.zip"]
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
  #puts "http::status: [http::status $tok]"
  #puts "http::code: [http::code $tok]"
  #puts "http::ncode: [http::ncode $tok]"
  #foreach {name value} [http::meta $tok] {
  #  puts "$name: $value"
  #}
  http::cleanup $tok
  return
}





proc copy-base {os arch pkgname ver proj} {
  prepare-pkg $os $arch $pkgname $ver
  file copy -force [file join lib $os-$arch $pkgname-$ver] [file join build $proj $os-$arch]
}

# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir
proc copy-pkg {os arch pkgname ver proj} {
  prepare-pkg $os $arch $pkgname $ver
  if {\
    [catch {file copy -force [file join lib $os-$arch $pkgname-$ver] [file join build $proj $os-$arch]}] &&\
    [catch {file copy -force [file join lib generic $pkgname-$ver]   [file join build $proj $os-$arch]}]} {
      #if both copy attempts failed raise error
      error "Could not find $pkgname-$ver neither in lib/$os-$arch nor lib/generic"
  }
}


proc prepare-pkg {os arch pkgname ver} {
  set target_path_depend [file join lib $os-$arch $pkgname-$ver]
  set target_path_indep [file join lib generic $pkgname-$ver]
  # nothing to do if pkg exists in lib dir, it may be file or dir
  if {[file exists $target_path_depend] || [file exists $target_path_indep]} {
    return
  }
  fetch-pkg $os $arch $pkgname $ver
  set candidates [get-fetchnames $os $arch $pkgname $ver]
  foreach cand $candidates {
    set cand_path [file join downloads $cand]
    if {[file isfile $cand_path]} {
      switch -glob $cand {
        application-* {
          #TODO check if we can use base-tcl without exe extension for starpacks on Windows
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
  error
}
 


proc fetch-pkg {os arch pkgname ver} {
  set candidates [get-fetchnames $os $arch $pkgname $ver]
  # return if at least one candidate exists in downloads
  foreach cand $candidates {
    if {[file isfile [file join downloads $cand]]} {
      return
    }
  }
  set repourl https://raw.githubusercontent.com/skrepo/activestate/master/teacup/$pkgname
  foreach cand $candidates {
    set url $repourl/$cand
    #puts "Trying url: $url"
    # return on first successful download
    if {[wget $url [file join downloads $cand]] eq ""} {
      return
    }
  }
  error "Could not fetch package $pkgname-$ver for $os-$arch"
}





proc build {os arch proj base {packages {}}} {
  set bld [file join build $proj $os-$arch]
  file delete -force $bld
  file mkdir $bld
  file mkdir downloads
  copy-base $os $arch {*}[split-last-dash $base] $proj
  foreach pkgver $packages {
    copy-pkg $os $arch {*}[split-last-dash $pkgver] $proj
  }


}


build linux ix86 another base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3 Thread-2.7.2}
build win32 ix86 another base-tcl-8.6.3.1 {tls-1.6.4 autoproxy-1.5.3 Thread-2.7.2}

#build linux ix86 another base-tcl-8.6.3.1 {tls-1.6.4}
#build win32 ix86 another base-tcl-8.6.3.1 {tls-1.6.4}


