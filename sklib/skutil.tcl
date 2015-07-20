package provide skutil 0.0.0


#TODO test it on Windows with \r\n
proc strip-blank-lines {s} {
    set s [string trim $s]
    set s [regsub -all {\s*\n(\s*\n)+} $s "\n"]
    set s [regsub -all {^(\s*\n)+} $s ""]
    set s [regsub -all {(\s*\n)+$} $s ""]
    return $s
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


proc is-tk-loaded {} {
    catch {package require Tk} out
    return [regexp {^[0-9.]+$} $out]
}

proc pidof {name} {
    if {[catch {exec pidof -s $name} out err]} {
        return ""
    } else {
        return $out
    }
}

proc ofpid {pid} {
    if {[catch {set name [exec ps --no-headers --pid $pid -o comm]} out err]} {
        return ""
    } else {
        return $out
    }
}


# return error message on error, empty string otherwise
proc create-pidfile {path} {
    set path [file normalize $path]
    if {[file exists $path]} {
        if {[file isfile $path]} {
            # Some heuristics to give meaningful error message
            set pid [string trim [slurp $path]]
            if {$pid ne ""} {
                puts stderr "pid=$pid, thispid=[pid]"
                if {$pid == [pid]} {
                    # restarting with the same pid - upgrade/execl scenario - do nothing and return success
                    log "Pidfile is matching current process. Restart/upgrade detected. Pidfile not created this time."
                    return ""
                }   
                set process [ofpid $pid]
                if {$process eq ""} {
                    log "No process for PID $pid so the creator probably abruptly ended. Proceeding to create-pidfile."
                    catch {exec pkill [file tail $path]}
                    #proceed to create pid file
                } else {
                    set root [file root [file tail $path]]
                    if {[string match *$root* $process]} {
                        return "Program is already running with PID $pid. Pidfile not created this time."
                    } else {
                        return "$path points to existing process $process. Is program already running? Pidfile not created this time."
                    }
                }
            } else {
                log "$path exists but is empty. Previous program run did not close correctly. Proceeding to create-pidfile."
                catch {exec pkill [file tail $path]}
                #proceed to create pid file
            }
        } else {
            return "$path exists but is not a file. Please delete it and start again. Pidfile not created this time."
        }
    }
    if {[catch {
        mk-head-dir $path
        set fd [open $path w]
        puts -nonewline $fd [pid]
        close $fd
    } out err]} {
        log $out
        log $err
        return "Could not create $path. Check logs for details."
    }
    log Created pidfile $path
    return ""
}

proc delete-pidfile {path} {
    if {[catch {file delete $path} out err]} {
        log $out
        log $err
        return "There was a problem with deleting $path. Check logs for details."
    } else {
        return ""
    }
}

# log with timestamp to stdout and return stringified args (for further logging/printing)
proc log {args} {
    # swallow exception
    catch {puts [join [list [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"] {*}$args]]}
    return [join $args]
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
    # -ignorestderr - Stops the exec command from treating the output of messages to the pipeline's standard error channel as an error case.
    if {[catch {exec -ignorestderr {*}$cmd} out err]} {
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
    #TODO adjust paths like the one below
    # public key must be in /etc/skd/keys/skt_public.pem
    set cmd [list openssl dgst -sha1 -verify $pubkey -signature $filepath.sig $filepath]
    log verify-signature: $cmd
    # -ignorestderr - Stops the exec command from treating the output of messages to the pipeline's standard error channel as an error case.
    if {[catch {exec -ignorestderr {*}$cmd} out err]} {
        # openssl returns error exit code both on Verification Failure and on No such file or directory
        log $cmd returned: $out
        log $err
        return 0
    }
    log $cmd returned: $out
    return [string equal "Verfied OK" $out]
}


# Generate RSA private key
# ruturn 1 on success, 0 otherwise
proc generate-rsa {filepath} {
    set cmd [list openssl genrsa -out $filepath 2048]
    log generate-rsa $filepath
    if {![mk-head-dir $filepath]} {
        return 0
    }
    # -ignorestderr - Stops the exec command from treating the output of messages to the pipeline's standard error channel as an error case.
    if {[catch {exec -ignorestderr {*}$cmd} out err]} {
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
    # -ignorestderr - Stops the exec command from treating the output of messages to the pipeline's standard error channel as an error case.
    if {[catch {exec -ignorestderr {*}$cmd} out err]} {
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


# Preserve the value of local variable between calls of the proc
# by mapping local varName to global array value
proc static {varName {initialValue ""}} {
    if {[info level] < 2} {
        error "Must be called from inside proc"
    }
    set callerProc [lindex [info level -1] 0]
    if {![info exists ::Static($callerProc,$varName)]} {
        set ::Static($callerProc,$varName) $initialValue
    }
    uplevel [list upvar #0 ::Static($callerProc,$varName) $varName]
}


proc unzip {zipfile {destdir .}} {
    package require vfs::zip
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

# return random 0 <= x < $n
proc rand-int {n} {
    return [expr {round(rand()*$n)}]
}

proc rand-byte {} {
    return [rand-int 256]
}

proc rand-byte-hex {} {
    return [format %02x [rand-byte]]
}

# return 9-digit random integer
proc rand-big {} {
    return [expr {100000000 + [rand-int 900000000]}]
}

# return list of numbers from 0 to n-1
proc seq {n} {
    set res {}
    for {set i 0} {$i < $n} {incr i} {
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
            if {[llength $allowed] > 0 && ($flag ni $allowed)} {
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


# Parse argument list to get value of the named argument
# For example:
#   namedarg {10 -arg2 20 -arg3 30 40 -arg5 50 60} -arg3
# should return 30
# For non-existing argument name return $default or empty string if not given
# It's a simpler alternative to parseopts
proc namedarg {arglist name {default ""}} {
    if {[llength $arglist] % 2 == 1} {
        set arglist [lrange $arglist 0 end-1]
    }
    array set arr $arglist
    if {[info exists arr($name)]} {
        return $arr($name)
    } else {
        return $default
    }
}

proc arg {name {default ""}} {
    upvar args a
    return [namedarg $a $name $default]
}

# return arg list with only selected named args
# take any number of arg names
proc args= {args} {
    upvar args a
    set result {}
    foreach name $args {
        lappend result $name [namedarg $a $name]
    }
    return $result
} 


# return modified args with added/overwritten name-value pairs:
# args+ name1 value1 name2 value2 ...
# takes any number of name-value pairs 
proc args+ {args} {
    upvar args arglist
    if {[llength $arglist] % 2 == 1} {
        set odd [lindex $arglist end]
        set arglist [lrange $arglist 0 end-1]
    }
    array set arr $arglist
    foreach {name value} $args {
        list set arr($name) $value
    }
    if {[info exists odd]} {
        return [concat [array get arr] $odd]
    } else {
        return [array get arr]
    }
}

# takes any number of names
proc args- {args} {
    upvar args arglist
    if {[llength $arglist] % 2 == 1} {
        set odd [lindex $arglist end]
        set arglist [lrange $arglist 0 end-1]
    }
    array set arr $arglist
    foreach {name} $args {
        list array unset arr $name
    }
    if {[info exists odd]} {
        return [concat [array get arr] $odd]
    } else {
        return [array get arr]
    }
}


proc fromargs {names {defaults {}}} {
    upvar args a
    foreach {name default} [lzip $names $defaults] {
        if {![string match -* $name]} {
            error "fromargs argument name '$name' must start with dash"
        }
        uplevel [list set [string range $name 1 end] [namedarg $a $name $default]]
    }
}


proc test1 {args} {
    fromargs -aa
    fromargs {-bb -cc}
    fromargs {-dd -ee -ff} {8888 9999}
    puts "$aa $bb $cc $dd $ee $ff"
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

# List comparator - order independent (set like but with duplicates)
proc leqi {a b} {expr {[lsort $a] eq [lsort $b]}}

# List comparator - literally. lrange makes a list canonical
proc leq {a b} {expr {[lrange $a 0 end] eq [lrange $b 0 end]}}

# List difference - duplicates matter and are preserved
proc ldiff {a b} {
    set res {}
    foreach ael $a {
        set idx [lsearch -exact $b $ael]
        if {$idx < 0} {
            lappend res $ael
        } else {
            set b [lreplace $b $idx $idx]
        }
    }
    return $res
}

# Return list without duplicates while preserving order
proc lunique {a} {
    set res {}
    foreach ael $a {
        set idx [lsearch -exact $res $ael]
        if {$idx < 0} {
            lappend res $ael
        }
    }
    return $res
}


# Return list intersection while preserving order of a
# Duplicates matter and are preserved
proc lintersection {a b} {
    set res {}
    foreach ael $a {
        set idx [lsearch -exact $b $ael]
        if {$idx >= 0} {
            lappend res $ael
            set b [lreplace $b $idx $idx]
        }
    }
}

# Count non-empty elements of the list
proc lcount {a} {
    set c 0
    foreach e $a {
        if {$e ne ""} {
            incr c
        }
    }
    return $c
}

# Combine lists so that the elements alternate (a0 b0 a1 b1 a2 b2 ...)
# Useful for iterating 2 lists in sync:
# foreach {aval bval} [lzip $a $b] {...}
proc lzip {a b} {
    set result {}
    set len [expr {max([llength $a],[llength $b])}]
    for {set i 0} {$i<$len} {incr i} {
        lappend result [lindex $a $i] [lindex $b $i]
    }
    return $result
}





proc touch {file} {
    if {[file exists $file]} {
        file mtime $file [clock seconds]
    } else {
        set fh [open $file w]
        catch {close $fh}
    }
}

# Get value from nested dict or return default value if key does not exist
# dict-pop dictValue k1 [k2 k3 ...] defaultValue
proc dict-pop {d args} {
    if {[llength $args] < 2} {
        error "Missing arguments to dict-pop. Actual: dict-pop dict $args. Expected: dict-pop dict k1 \[k2 k3 ...\] defaultValue"
    }
    set default [lindex $args end]
    set keys [lrange $args 0 end-1]
    if {[dict exists $d {*}$keys]} {
        return [dict get $d {*}$keys]
    } else {
        return $default
    }
}
        
# If key exists in nested dict, return its value
# Otherwise set it to defaultValue and return defaultValue
# dict-put dictVar k1 [k2 k3 ...] defaultValue
proc dict-put {dictVar args} {
    upvar $dictVar d
    if {[llength $args] < 2} {
        error "Missing arguments to dict-put. Actual: dict-put $dictVar $args. Expected: dict-put $dictVar k1 \[k2 k3 ...\] defaultValue"
    }
    set default [lindex $args end]
    set keys [lrange $args 0 end-1]
    if {[dict exists $d {*}$keys]} {
        return [dict get $d {*}$keys]
    } else {
        dict set d {*}$keys $default
        return $default
    }
}


######################### 
# convert dictionary value dict into string 
# hereby insert newlines and spaces to make 
# a nicely formatted ascii output 
# The output is a valid dict and can be read/used 
# just like the original dict 
############################# 
# copy of this proc is also in inicfg.tcl
proc dict-pretty {d {indent ""} {indentstring "    "}} {
    set result ""
    # unpack this dimension 
    dict for {key value} $d { 
       if {[isdict $value]} { 
          append result "$indent[list $key]\n$indent\{\n" 
          append result "[dict-pretty $value "$indentstring$indent" $indentstring]\n" 
          append result "$indent\}\n" 
       } else { 
          append result "$indent[list $key] [list $value]\n" 
       }
    }
    return $result 
}


proc isdict {v} { 
   string match "value is a dict *" [::tcl::unsupported::representation $v] 
} 



proc string-insert {s pos insertion} {
    append insertion [string index $s $pos]
    string replace $s $pos $pos $insertion
}


proc hyperlink {name args} {
    if { "UnderlineFont" ni [ font names ] } {
        font create UnderlineFont {*}[ font actual TkDefaultFont ]
        font configure UnderlineFont -underline true
    }
    if { [ dict exists $args -command ] } {
        set command [ dict get $args -command ]
        dict unset args -command
    }
    # note - this forcibly overrides foreground and font options
    label $name {*}$args -foreground blue -cursor hand1
    bind $name <Enter> {%W configure -font UnderlineFont}
    bind $name <Leave> {%W configure -font TkDefaultFont}
    if { [ info exists command ] } {
        bind $name <Button-1> $command
    }
    return $name
}


proc launchBrowser {url} {
    try {
        if {$::tcl_platform(platform) eq "windows"} {
            set command [list {*}[auto_execok start] {}]
            # Windows shell would start a new command after &, so shell escape it with ^
            set url [string map {& ^&} $url]
        } elseif {$::tcl_platform(os) eq "Darwin"} {
            # It *is* generally a mistake to use $tcl_platform(os) to select functionality,
            # particularly in comparison to $tcl_platform(platform).  For now, let's just
            # regard it as a stylistic variation subject to debate.
            set command [list open]
        } else {
            set command [list xdg-open]
        }
        exec {*}$command $url &
    } on error {e1 e2} {
        log $e1 $e2
        log ERROR: could not launchBrowser: $url
    }
}

# Convert version string like "11.22.0333.4" to large integer for further comparison
# Empty string parses to 0 without error
proc int-ver {v} {
    set result ""
    foreach i {0 1 2 3} {
        append result [format "%04s" [lindex [split $v .] $i]]
    }
    return [string trimleft $result 0]
}

# return true for version format: 0, 1, 12, 123, 1234, 1.2, 1.23, 1.23.45, 11.22.33.44 etc
proc is-dot-ver {v} {
    return [regexp {^\d{1,4}(\.\d{1,4}){0,3}$} $v]
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
