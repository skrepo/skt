# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

set builddate [clock format [clock seconds] -gmt 1]
array set github_repos {}

proc ex {args} {
    return [exec -- {*}$args >&@ stdout]
}

# only for text files, assumes utf-8 encoding
proc slurp {path} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set data [read $fd]
    close $fd
    return $data
}

proc spit {path content} {
    set fd [open $path w]
    puts -nonewline $fd $content
    close $fd
}

proc generalize-arch {arch} {
    switch -glob $arch {
        i?86 {return ix86}
        x86_64 {return x86_64}
        default {error "Unrecognized CPU architecture"}
    }
}

proc this-arch {} {
    return [generalize-arch $::tcl_platform(machine)]
}

proc this-os {} {
    switch -glob $::tcl_platform(os) {
        Linux {return linux}
        Windows* {return win32}
        default {error "Unrecognized OS"}
    }
}

# these libraries are only to provide tls support for the build script
lappend auto_path [file join lib [this-os]-[this-arch]]
lappend auto_path [file join lib generic]

package require http
package require vfs::zip
package require tls
package require i18n
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


proc install-fpm {} {
    if {[catch {exec fpm --version}] == 1} {
        puts "Installing fpm"
        ex sudo apt-get update --fix-missing
        ex sudo apt-get -fy install git ruby-dev gcc rpm
        #ex sudo apt-get -fy install rubygems
        #ex sudo apt-get -fy install rubygems-integration
        ex sudo gem install fpm
    } else {
        puts "fpm already present"
    }
}

# also in sklib
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
      return [list "package-$pkgname-$ver-tcl.tm" "package-$pkgname-$ver-[oscompiler $os]-$arch.zip" "package-$pkgname-$ver-tcl.zip" "$pkgname-$ver.zip"]
    }
  }
}




#TODO support url redirect (Location header)
# also in skutil
proc wget {url filepath} {
  set fo [open $filepath w]
  set tok [http::geturl $url -channel $fo]
  close $fo
  set retcode [http::ncode $tok]
  if {$retcode != 200} {
      file delete $filepath
  }
  http::cleanup $tok
  return $retcode
}

proc github-repo {repo github_user} {
    global github_repos
    set github_repos($repo) $github_user
}

proc fetch-github {pkgname ver} {
    global github_repos
    if {![info exists github_repos($pkgname)]} {
        return 0
    }
    set github_user $github_repos($pkgname)
    # The original link is: https://github.com/$github_user/$pkgname/archive/$ver
    # but it gets redirected to:
    set url https://codeload.github.com/$github_user/$pkgname/zip/$ver

    puts -nonewline "Trying to download $url...     "
    flush stdout
    if {[wget $url [file join downloads $pkgname-$ver.zip]] == 200} {
      puts "DONE"
      return 1
    } else {
      puts "FAIL"
      return 0
    }
}


# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir


# first prepare-pkg and copy from lib to build
proc copy-pkg {os arch pkgname ver proj} {
  prepare-pkg $os $arch $pkgname $ver
  set libdir [file join build $proj $os-$arch $proj.vfs lib]
  #puts "Copying package $pkgname-$ver to $libdir"
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
    #puts "Already prepared: $target_path_depend"
    return
  }
  if {[file exists $target_path_indep]} {
    #puts "Already prepared: $target_path_indep"
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
        package-*-tcl.zip {
          file mkdir $target_path_indep
          unzip $cand_path $target_path_indep
          return
        }
        package-*.zip {
          file mkdir $target_path_depend
          unzip $cand_path $target_path_depend
          return
        }
        *.zip {
          unzip $cand_path [file join lib generic]
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
  if {[fetch-github $pkgname $ver]} {
      # Successfully fetched the package from an individual github repo so return
      return
  }

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
    if {[wget $url [file join downloads $cand]] == 200} {
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
# ignore files matching glob pattern $ignore
proc copy-merge {from to {ignore ""}} {
    file mkdir $to
    foreach f [glob [file join $from *]] {
        set tail [file tail $f]
        if {![string match $ignore $tail]} {
            if {[file isdirectory $f]} {
                set new_to [file join $to $tail]
                file mkdir $new_to
                copy-merge $f $new_to
            } else {
                file copy -force $f $to
            }
        }
    }
}


proc build {os arch_exact proj base {packages {}}} {
    set arch [generalize-arch $arch_exact]
    puts "\nStarting build ($os $arch $proj $base $packages)"
    if {![file isdirectory $proj]} {
      puts "Could not find project dir $proj"
      return
    }
    set bld [file join build $proj $os-$arch]
    puts "Cleaning build dir $bld"
    file delete -force $bld
    file mkdir [file join $bld $proj.vfs lib]
    # we don't copy base-tcl/tk to build folder. Having it in lib is enough - hence prepare-pkg
    prepare-pkg $os $arch {*}[split-last-dash $base]
    foreach pkgver $packages {
        copy-pkg $os $arch {*}[split-last-dash $pkgver] $proj
    }
    set vfs [file join $bld $proj.vfs]
    puts "Copying project source files to VFS dir: $vfs"
  
    copy-merge $proj $vfs exclude
    set cmd [list [info nameofexecutable] sdx.kit wrap [file join $bld $proj[suffix_exec $os]] -vfs [file join $bld $proj.vfs] -runtime [file join lib $os-$arch $base]]
    puts "Building starpack $proj"
    puts $cmd
    ex {*}$cmd
}

proc run {proj} {
    ex [info nameofexecutable] [file join build $proj [this-os]-[this-arch] $proj.vfs main.tcl]
}


proc prepare-lib {pkgname ver} {
    set dest [file join lib generic $pkgname-$ver]
    file delete -force $dest
    file mkdir $dest
    copy-merge $pkgname $dest
    pkg_mkIndex $dest
}

proc doc {path} {
    package require doctools
    ::doctools::new mydtp -format html
    set path [file normalize $path]
    set dest [file join [file dir $path] [file root [file tail $path]].html]
    spit $dest [mydtp format [slurp $path]]
}



#platforminfo

source build.tcl


