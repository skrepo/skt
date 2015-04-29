package provide https 0.0.0

package require http
package require tls
# TODO use your own cadir with sk CA
#http::register https 443 [list tls::socket -require 1 -command ::https::tls-callback -servername slakjdfls.com -cadir /etc/ssl/certs]
http::register https 443 [list https::socket -require 1 -command ::https::tls-callback -servername slakjdfls.com -cadir /etc/ssl/certs]

#TODO support url redirect (Location header)

# Believe or not but the original Tcl tls package does not validate certificate subject's Common Name CN against URL's domain name
# TLS is pointless without this validation because it enables trivial MITM attack




# Collection of http/tls utilities like wget or curl
# They work also for plain http
namespace eval ::https {
    variable default_timeout 5000
    variable sock2host
    namespace export curl curl-async wget wget-async socket
    namespace ensemble create
}


# log with timestamp to stdout
proc ::https::log {args} {
    # swallow exception
    catch {puts [join [list [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"] {*}$args]]}
}

proc ::https::debug-http {tok} {
    upvar #0 $tok state
    log debug-http $tok
    parray state
}

proc ::https::socket {args} {
    variable sock2host
    puts "https::socket args: $args"
    #Note that http::register appends options, host and port. E.g.: <given https::socket options> -async tv.eurosport.com 443
    set chan [tls::socket {*}$args]
    puts "https::socket created chan: $chan"
    dict set sock2host $chan [lindex $args end-1]
    puts "sock2host: $sock2host"
    return $chan
}



#
# this is a modified version of the default [info body tls::callback] with cert Common Name validation
proc ::https::tls-callback {option args} {
    variable sock2host
    log tls-callback: $option $args
    switch -- $option {
        "error" {
            lassign $args chan msg
            log "             " "TLS/$chan: error: $msg"
        }
        "verify"  {
            lassign $args chan depth cert rc err
            array set c $cert
            # Parse X.509 subject to extract CN
            set subject $c(subject)
            set props [split $subject ","]
            set props [lmap p $props {string trim $p}]
            set prop [lsearch -inline $props CN=*]
            if {![regexp {^CN=(.+)$} $prop _ cn]} {
                log ERROR: Wrong subject format in the certificate: $subject
                catch {dict unset sock2host $chan}
                return 0
            }
            # Return error early on bad/missing certs detected by OpenSSL
            if {$rc != 1} {
                log "ERROR: TLS/$chan: verify/$depth: Bad Cert: $err (rc = $rc)"
                catch {dict unset sock2host $chan}
                return $rc
            }
            log "             " "TLS/$chan: verify/$depth: $c(subject)"
            # Don't verify Common Name against url domain for root and intermediate certificates
            if {$depth != 0} {
                return 1
            }
            # Return error if chan name not saved before
            if {![dict exists $sock2host $chan]} {
                log ERROR: Missing hostname for channel $chan
                return 0
            }
            set host [dict get $sock2host $chan]
            if {$host eq $cn && $host ne ""} {
                log Hostname matched the Common Name: $host
                dict unset sock2host $chan
                return 1
            } else {
                log ERROR: Hostname: $host did not match the name in the certificate: $cn
                dict unset sock2host $chan
                return 0
            }
        }
        "info"  {
            lassign $args chan major minor state msg
            if {$msg != ""} {
                append state ": $msg"
            }
            # For tracing
            upvar #0 tls::$chan cb
            set cb($major) $minor
            log "             " "TLS/$chan: $major/$minor: $state"
        }
        default {
            return -code error "bad option \"$option\": must be one of error, info, or verify"
        }
    }
}





#http:: If the -command option is specified, then the HTTP operation is done in the background. ::http::geturl returns immediately after generating the HTTP request and the callback is invoked when the transaction completes. For this to work, the Tcl event loop must be active. In Tk applications this is always true. For pure-Tcl applications, the caller can use ::http::wait after calling ::http::geturl to start the event loop.

# Synchronous curl. Return url content
# All errors propagated upstream
proc ::https::curl {url {timeout ""}} {
    if {$timeout eq ""} {
        set timeout $::https::default_timeout
    }
    set tok [http::geturl $url -timeout $timeout]
    set retcode [http::ncode $tok]
    set status [http::status $tok]
    set data [http::data $tok]
    if {$status eq "ok" && $retcode == 200} {
        http::cleanup $tok
        return $data
    } else {
        debug-http $tok
        http::cleanup $tok
        error "ERROR in curl $url"
    }
}

# Networking errors propagated upstream
# Note that error from tls is not informative so normally need to check previous tls logs
# HTTP errors handled in callback
proc ::https::curl-async {url {timeout ""} {callback ::https::curl-callback}} {
    if {$timeout eq ""} {
        set timeout $::https::default_timeout
    }
    return [http::geturl $url -timeout $timeout -command $callback]
}

# this is a template for curl callback - use tok as request ID to match request-response
proc ::https::curl-callback {tok} {
    puts "curl-callback called with tok: $tok"
    set retcode [http::ncode $tok]
    set status [http::status $tok]
    set data [http::data $tok]
    http::cleanup $tok
    puts "curl-callback status: $status"
    puts "curl-callback retcode: $retcode"
    puts "curl-callback data: $data"
}


# Synchronous wget. Return HTTP response code. 
# Errors propagated upstream
proc ::https::wget {url filepath {timeout ""}} {
    if {$timeout eq ""} {
        set timeout $::https::default_timeout
    }
    set fo [open $filepath w]
    set tok [http::geturl $url -channel $fo -timeout $timeout]
    close $fo
    set status [http::status $tok]
    set retcode [http::ncode $tok]
    if {$status ne "ok"} {
        file delete $filepath
        debug-http $tok
        http::cleanup $tok
        error "ERROR in wget $url $filepath"
    }
    if {$retcode != 200} {
        file delete $filepath
    }
    http::cleanup $tok
    return $retcode
}

# Networking and file errors propagated upstream
# Note that error from tls is not informative so normally need to check previous tls logs
# HTTP errors handled in callback
proc ::https::wget-async {url filepath {timeout ""} {callback ::https::wget-callback}} {
    if {$timeout eq ""} {
        set timeout $::https::default_timeout
    }
    log "wget-async 1111"
    set fo [open $filepath w]
    if {[catch {set tok [http::geturl $url -channel $fo -timeout $timeout -command $callback]} out err]} {
        # before propagating error need to close file
        catch {close $fo}
        error $err
    }
    upvar #0 $tok state
    set state(filepath) $filepath
    return $tok
}


proc ::https::wget-callback {tok} {
    puts "wget-callback called with tok: $tok"
    upvar #0 $tok state
    set filechan $state(-channel)
    set filepath $state(filepath)
    set url $state(url)
    catch {close $filechan}
    set retcode [http::ncode $tok]
    set status [http::status $tok]
    puts "status: $status, retcode: $retcode"
    if {$status eq "ok" && $retcode == 200} {
        log wget-callback token $tok success
    } else {
        file delete $filepath
        log "wget-callback error: $url $filepath"
        debug-http $tok
    }
    http::cleanup $tok
}




