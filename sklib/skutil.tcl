package provide skutil 0.0.0

#TODO test it on Windows with \r\n
proc strip-blank-lines {s} {
    set s [string trim $s]
    set s [regsub -all {\s*\n(\s*\n)+} $s "\n"]
    set s [regsub -all {^(\s*\n)+} $s ""]
    set s [regsub -all {(\s*\n)+$} $s ""]
    return $s
}


# Keep application state in global nested dictionary called ::state
# If the last argument is a list, the list should be key value pairs 
# to set in ::state under the path described by previous arguments
# If the last argument is a word, return value in ::state under the path
# described by all arguments
proc state {args} {
    # all-but-last args describe the path in nested dictionary
    set path [lrange $args 0 end-1]
    # last arg is key-value list
    set kv [lindex $args end]
    # remove comments and before-comment semicolons
    regsub -all {;*#[^\n]*\n} $kv "\n" kv

    # variable, command and backslash substitution
    # upleveled - must be done in caller context

    set kv [strip-blank-lines $kv]
    if {[llength $kv] == 1} {
        # now we know that kv is a single key
        set kv [uplevel [list subst $kv]]
        return [dict get $::state {*}$path $kv]
    }

    # key-value list
    set kvl {}
    foreach u [split $kv "\n"] {
        # first single word always the key, separate substitution
        lappend kvl [uplevel [list subst [lindex $u 0]]]
        # the rest of line (may be multiword) is the value, separate substitution
        lappend kvl [uplevel [list subst [join [lrange $u 1 end]]]]
    }

    if {[llength $kvl] % 2 == 1} {
        error "Missing value for key '[lindex $kvl end]' in state definition"
    }
    foreach {k v} $kvl {
        dict set ::state {*}$path $k $v
    }
    return $::state
}

proc parse-ip {s} {
    if {[regexp {^\d+\.\d+\.\d+\.\d+$} $s]
        && [scan $s %d.%d.%d.%d a b c d] == 4
        && 0 <= $a && $a <= 255 && 0 <= $b && $b <= 255
        && 0 <= $c && $c <= 255 && 0 <= $d && $d <= 255} {
        return [list $a $b $c $d]
    } else {
        return {}
    }
}

proc is-valid-ip {s} {
    set parsed [parse-ip $s]
    return [expr {$parsed ne ""}]
}


proc slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

proc spit {path content} {
    set fd [open $path w]
    puts $fd $content
    close $fd
}


proc is-tk-loaded {} {
    catch {package require Tk} out
    return [regexp {^[0-9.]+$} $out]
}


proc create-pidfile {path} {
    # propagate error if it occurs
    set path [file normalize $path]
    log create-pidfile $path
    set fd [open $path w]
    puts $fd [pid]
    close $fd
}

proc delete-pidfile {path} {
    # propagate error if it occurs
    file delete $path
}

# log with timestamp to stdout
proc log {args} {
    # swallow exception
    catch {puts [join [list [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"] {*}$args]]}
} 


# log variable names and values
proc dbg {args} {
    foreach varname $args {
        upvar $varname var
        log variable $varname: $var
    }
}


