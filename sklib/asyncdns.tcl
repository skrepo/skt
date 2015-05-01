package provide asyncdns 0.0.0

package require cmd

# Asynchronous DNS resolver using ping command
# Awful as it sounds it is the most robust method when compared to alternatives:
# - Tclx's host_info addresses is synchronouns
# - dns package from tcllib - full of nasty dependencies, not maintained, simply does not work
# We need async DNS in a single threaded, event driven program
# Otherwise system DNS resolution may freeze the program

namespace eval ::asyncdns {
    variable uid
    if {![info exists uid]} {
        set uid 0
    }
    variable default_timeout 5000
    namespace export resolve cleanup
    namespace ensemble create
}

# Simple options (-flag value) parser. Every flag must have value
# Removes options from varName. Returns options array
# If non-empty the allowed list is to validate flag names against
proc ::asyncdns::parseopts {varName {allowed {}}} {
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


# resolve -timeout 3000 -command callback hostname
proc ::asyncdns::resolve {args} {
    variable uid
    variable default_timeout

    array set opts [parseopts args {-command -timeout}]
    if {[llength $args] != 1} {
        error "Wrong number of arguments. Expected hostname. Given: $args"
    }
    lassign $args hostname
    if {![regexp {[a-zA-Z0-9\-.]+} $hostname]} {
        error "Wrong format of hostname: $hostname"
    }

    # Initialize the state variable, an array. We'll return the name of this
    # array as the token for the transaction.
    set token [namespace current]::[incr uid]
    upvar 0 $token state
    ::asyncdns::reset $token

    if {![info exists opts(-timeout)]} {
        set opts(-timeout) $default_timeout
    }
    array set state [array get opts]
    set state(hostname) $hostname

    switch $::tcl_platform(platform) {
        unix {set pingcmd [list ping -c 1 -w 1 $hostname]}
        windows {set pingcmd [list ping -n 1 -w 1 $hostname]}
        default: {error "Unrecognized platform"}
    }

    set state(tstart) [clock milliseconds]
    cmd invoke $pingcmd {} [list ::asyncdns::PingRead $token] [list ::asyncdns::PingErrRead $token]
    if {$state(-timeout) > 0} {
	    set state(timer) [after $state(-timeout) [list ::asyncdns::finish $token timeout]]
    }
    if {![info exists state(-command)]} {
        ::asyncdns::wait $token
    }
    return $token
}

# should be called by library user
proc ::asyncdns::cleanup {token} {
    upvar 0 $token state
    if {[info exists state]} {
	    unset state
    }
}

proc ::asyncdns::wait {token} {
    upvar 0 $token state
    if {![is-finished $token]} {
	    # We must wait on the original variable name, not the upvar alias
	    vwait ${token}(status)
    }
    return $state(status)
}

proc ::asyncdns::reset {token} {
    upvar 0 $token state
    array set state {
        ip ""
        status ""
    }
}

proc ::asyncdns::is-finished {token} {
    upvar 0 $token state
    if {![info exists state] || ([info exists state(status)] && $state(status) ne "")} {
        return 1
    } else {
        return 0
    }
}
    

proc ::asyncdns::finish {token status} {
    upvar 0 $token state
    set state(status) $status
    set state(elapsed) [expr {[clock milliseconds]-$state(tstart)}]
    unset state(tstart)
    if {[info exists state(timer)]} {
	    after cancel $state(timer)
        unset state(timer)
    }
    if {[info exists state(-command)]} {
        {*}$state(-command) $token
    }
} 

proc ::asyncdns::PingErrRead {token line} {
    #puts "asyncdns::PingErrRead token $token: $line"
}

proc ::asyncdns::PingRead {token line} {
    if {[is-finished $token]} {
        return
    }
    upvar 0 $token state
    set pat [string map {. \\.} $state(hostname)]
    append pat {.*[^0-9](\d+\.\d+\.\d+\.\d+)[^0-9]}
    if {[regexp $pat $line _ ip]} {
        set state(ip) $ip
        ::asyncdns::finish $token ok
    }
}


