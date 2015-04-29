package provide https 0.0.0

package require http
package require tls
http::register https 443 [list tls::socket] ;# -require 1] ;# -command tls-callback]

# log with timestamp to stdout
proc log {args} {
    # swallow exception
    catch {puts [join [list [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"] {*}$args]]}
}

# this is a modified version of the default [info body tls::callback]
proc tls-callback {option args} {
    variable debug
    log tls-callback input: $option $args
    switch -- $option {
        "error" {
            lassign $args chan msg
            log 0 "TLS/$chan: error: $msg"
        }
        "verify"  {
            lassign $args chan depth cert rc err
            array set c $cert
            if {$rc != "1"} {
                log 1 "TLS/$chan: verify/$depth: Bad Cert: $err (rc = $rc)"
            } else {
                log 2 "TLS/$chan: verify/$depth: $c(subject)"
            }
            if {$debug > 0} {
                return 1; # FORCE OK
            } else {
                return $rc
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
            log 2 "TLS/$chan: $major/$minor: $state"
        }
        default {
            return -code error "bad option \"$option\": must be one of error, info, or verify"
        }
    }
}


#TODO support url redirect (Location header)
proc wget {url filepath} {
    set fo [open $filepath w]
    set tok [http::geturl $url -channel $fo]
    close $fo
    upvar #0 $tok state
    puts "tok state:"
    parray state
    #puts "tls status:"
    #parray [tls::status $state(sock)]
    set retcode [http::ncode $tok]
    if {$retcode != 200} {
        file delete $filepath
    }
    http::cleanup $tok
    return $retcode
}


