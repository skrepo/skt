package provide img 0.0.0

package require anigif

namespace eval ::img {
    namespace export *
    namespace ensemble create
}


proc ::img::memoize {} {
    set cmd [info level -1]
    if {[info level] > 2 && [lindex [info level -2] 0] eq "memoize"} return
    if {![info exists ::Memo($cmd)]} {set ::Memo($cmd) [eval $cmd]}
    return -code return $::Memo($cmd)
}


# Convert image pointer to image root name
# Example:   flag/pl  ->  <scriptroot>/images/flag/pl
proc ::img::root {imgptr} {
    memoize
    return [file join [file dir [info script]] images $imgptr]
}


# Return .png or .gif for given imgptr (image pointer)
# e.g. flag/pl is a pointer to images/flag/pl.png or images/flag/pl.gif 
# depending on which one is present
proc ::img::ext {imgptr} {
    memoize
    set imgpath [::img::root $imgptr]
    foreach ext {.png .gif} {
        if {[file exists ${imgpath}${ext}]} {
           return $ext
       }
    }
    puts stderr "ERROR: ::img::ext could not find image for $imgptr ($imgpath)"
    # if image not found return .png
    return .png
}

proc ::img::path {imgptr} {
    memoize
    return [::img::root $imgptr][::img::ext $imgptr]
}


# Create image object in the context of the caller and return its name
# e.g. ::img::load flag/pl will look for images/flag/pl.png or images/flag/pl.gif 
# and will load image under the name flag_pl and return that name
proc ::img::load {imgptr} {
    memoize
    set imgobj [string map {/ _} $imgptr]
    #TODO check if replacing / with \ is necessary on windows
    uplevel [list image create photo $imgobj -file [::img::path $imgptr]]
    return $imgobj
}

proc ::img::place {imgptr lbl} {
    anigif::stop $lbl
    if {[::img::ext $imgptr] eq ".gif"} {
        anigif::anigif [::img::path $imgptr] $lbl
    } else {
        $lbl configure -image [::img::load $imgptr]
    }
}

