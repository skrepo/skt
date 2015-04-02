
proc platforminfo {} {
    puts "Script name: $::argv0"
    puts "Arguments:\n[join $::argv \n]"
    puts "Current directory: [pwd]"
    puts "This is Tcl version $::tcl_version , patchlevel $::tcl_patchLevel"
    puts "[info nameofexecutable] is [info tclversion] patch [info patchlevel]"
    puts "Directory(s) where package require will search:"
    puts "$::auto_path"
    puts "tcl_libPath = $::tcl_libPath"  ;# May want to skip this one
    puts "tcl_pkgPath = $::tcl_pkgPath"  ;# May want to skip this one
    puts "tcl_library = $::tcl_library"
    puts "info library = [info library]"
    puts "Shared libraries are expected to use the extension [info sharedlibextension]"
    puts "platform information:"
    parray ::tcl_platform
}


platforminfo

proc platform_path {} {
    # assume ix86 - hopefully only 32-bit builds needed
    switch $::tcl_platform(os) {
        Linux {return linux/ix86}
        Windows* {return win32/ix86}
        default {error "Unrecognized platform"}
    }
}

lappend auto_path [platform_path]
 
package require tls





