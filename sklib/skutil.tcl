package provide skutil 0.0.0

package require vfs::zip

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
    puts -nonewline $fd $content
    close $fd
}


proc is-tk-loaded {} {
    catch {package require Tk} out
    return [regexp {^[0-9.]+$} $out]
}


proc create-pidfile {path} {
    # propagate error if it occurs
    set path [file normalize $path]
    mk-head-dir $path
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

# this is utility for the server side
# returns 1 on success, 0 otherwise
proc create-signature {privkey filepath} {
    set cmd [list openssl dgst -sha1 -sign $privkey $filepath > $filepath.sig]
    log create-signature: $cmd
    if {[catch {exec {*}$cmd} out err]} {
        # possible errors: No such file or directory, wrong passphrase
        log $cmd returned: $out
        log $err
        return 0
    } else {
        log created signature: $filepath.sig
        return 1
    }
}

# returns 1 if verification succeeded, 0 otherwise
#TODO provide Windows version
proc verify-signature {pubkey filepath} {
    # public key must be in /etc/skd/keys/skt_public.pem
    set cmd [list openssl dgst -sha1 -verify $pubkey -signature $filepath.sig $filepath]
    log verify-signature: $cmd
    if {[catch {exec {*}$cmd} out err]} {
        # openssl returns error exit code both on Verification Failure and on No such file or directory
        log $cmd returned: $out
        log $err
        return 0
    }
    log $cmd returned: $out
    return [expr {$out eq "Verified OK"}]
}


# Generate RSA private key
# ruturn 1 on success, 0 otherwise
proc generate-rsa {filepath} {
    set cmd [list openssl genrsa -out $filepath 2048]
    log generate-rsa $filepath
    if {![mk-head-dir $filepath]} {
        return 0
    }
    if {[catch {exec {*}$cmd} out err]} {
        log $cmd returned: $out
        log $err
        return 0
    }
    log $cmd returned: $out
    return 1
}

# Generate CSR file
# ruturn 1 on success, 0 otherwise
proc generate-csr {privkey csr cn} {
    set crt_subj "/C=AA/ST=Universe/L=Internet/O=SecurityKISS User/CN=$cn"
    set cmd [list openssl req -new -subj $crt_subj -key $privkey -out $csr]
    log generate-csr $csr
    if {![mk-head-dir $csr]} {
        return 0
    }
    if {[catch {exec {*}$cmd} out err]} {
        log $cmd returned: $out
        log $err
        return 0
    }
    log $cmd returned: $out
    return 1
}

# Extract common name from certificate
# Return cn on success, empty string otherwise
proc cn-from-cert {crtpath} {
    memoize
    log ca-from-cert $crtpath
    set cmd [list openssl x509 -noout -subject -in $crtpath]
    if {[catch {exec {*}$cmd} subject err]} {
        log $cmd returned: $out
        log $err
        return ""
    }
    if {[regexp {CN=([0-9a-f]{4,16})} $subject -> cn]} {
        log Extracted cn $cn from subject $subject
        return $cn
    } else {
        log Could not extract cn from subject $subject
        return ""
    }
    
}


proc memoize {} {
    set cmd [info level -1]
    if {[info level] > 2 && [lindex [info level -2] 0] eq "memoize"} return
    if {![info exists ::Memo($cmd)]} {set ::Memo($cmd) [eval $cmd]}
    return -code return $::Memo($cmd)
}

proc unzip {zipfile {destdir .}} {
    set mntfile [vfs::zip::Mount $zipfile $zipfile]
    foreach f [glob [file join $zipfile *]] {
      file copy $f $destdir
    }
    vfs::zip::Unmount $mntfile $zipfile
}

# Create directories containing the file specified by filepath
# Return 1 if directories create or exist
# Return 0 if created directory would overwrite an existing file
proc mk-head-dir {filepath} {
    set filepath [file normalize $filepath]
    set elems [file split $filepath]
    if {[catch {file mkdir [file join {*}[lrange $elems 0 end-1]]} out err]} {
        log $out
        log $err
        log Could not create directories for $filepath
        return 0
    } else {
        return 1
    }
}


proc rand-byte {} {
    return [expr {round(rand()*256)}]
}

proc rand-byte-hex {} {
    return [format %02x [rand-byte]]
}

proc seq {n} {
    set res {}
    for {set i 1} {$i <= $n} {incr i} {
        lappend res $i
    }
    return $res
}


# Simple options (-flag value) parser. Every flag must have value
# Removes options from varName. Returns options array
# If non-empty the allowed list is to validate flag names against
proc parseopts {varName {allowed {}}} {
    upvar $varName var
    array set options {}
    foreach {flag value} $var {
        if {[string match -* $flag]} {
            if {[llength $allowed] > 0 && [lsearch -exact $allowed $flag] == -1} {
                error "Unrecognized flag: $flag. Allowed: $allowed"
            }
            if {$value eq ""} {
                error "Missing value for flag $flag"
            }
            set options($flag) $value
            set var [lreplace $var 0 1]
        } else {
            break
        }
    }
    return [array get options]
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
                #puts "Copying $f"
                file copy -force $f $to
            }
        }
    }
}

