
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
http::register https 443 [list tls::socket]

# run sample project without building
#source sample/main.tcl





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
      if {$os eq "windows"} {
        set res $res.exe
      }
    }
    default {
      #TODO now 2 possibilites zip or tm
    }
  }
  return $res
}




#TODO support url redirect (Location header)
proc wget {url filepath} {
  set fo [open $filepath w]
  set tok [http::geturl $url -channel $fo]
  close $fo
  foreach {name value} [http::meta $tok] {
    puts "$name: $value"
  }
  http::cleanup $tok
}




# Package presence is checked in the following order:
# 1. is pkg-ver in lib?          => copy to build dir
# 2. is pkg-ver in downloads?    => prepare, unpack to lib dir, delete other versions in lib dir
# 3. is pkg-ver in github?       => fetch to downloads dir
proc copy-pkg {os arch pkgname ver proj} {
  prepare-pkg $os $arch $pkgname $ver
  #TODO if build/$proj/$os-$arch is dir
  file copy -force [file join lib $os-$arch $pkgname-$ver] [file join build $proj $os-$arch]
  # copy regular packages to build dir
  # recognize base-tcl packages and place them properly
  # delete if another package version present
}

proc prepare-pkg {os arch pkgname ver} {
  
  fetch-pkg $os $arch $pkgname $ver
  switch -glob $pkgname {
    base-* {
      set fetchnames [get-fetchnames $os $arch $pkgname $ver]
      if {[llength $fetchnames] == 1} {
        #TODO check if we can use base-tcl without exe extension for starpacks on Windows
        file copy -force [file join downloads $fetchnames] [file join lib $os-$arch $pkgname-$ver]
      } else {
        error "should be only one fetchname"
      }

    }
    default {
    }
  }

}

proc fetch-pkg {os arch pkgname ver} {
  set fetchnames [get-fetchnames $os $arch $pkgname $ver]
  # return if at least one candidate exists in downloads
  foreach name $fetchnames {
    if {[file isfile [file join downloads $name]]} {
      return
    }
  }
  set repourl https://raw.githubusercontent.com/skrepo/activestate/master/teacup/$pkgname
  foreach name $fetchnames {
    set url $repourl/$name
    #TODO check wget status and return if downloaded
    wget $url [file join downloads $name]
  }
  #raise error if we got here
}





proc build {os arch proj {packages {}}} {
  set bld [file join build $proj $os-$arch]
  file delete -force $bld
  file mkdir $bld
  foreach pkgver $packages {
    copy-pkg $os $arch {*}[split-last-dash $pkgver] $proj
  }


}


build linux ix86 another {base-tcl-8.6.3.1}

#build linux ix86 another {base-tcl-8.6.3.1 tls-1.6.4}
#build win32 ix86 another {base-tcl-8.6.3.1 tls-1.6.4}


