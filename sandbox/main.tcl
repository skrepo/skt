package require csp
package require tls
package require https
package require http
package require skutil
namespace import csp::*

proc http_handler {httpout httperr tok} {
    # need to catch error in case the handler triggers after the channels were closed
    catch {
        set ncode [http::ncode $tok]
        set status [http::status $tok]
        if {$status eq "ok" && $ncode == 200} {
            $httpout <- $tok
        } else {
            $httperr <- $tok
        }
    }
}

#proc curl-hosts {tryout tryerr hosts hindex urlpath indiv_timeout proto port expected_hostname} {
proc curl-hosts {tryout tryerr args} {
    fromargs {-urlpath -indiv_timeout -hosts -hindex -proto -port -expected_hostname} \
             {/ 5000 {} 0 https}
    if {$proto ne "http" && $proto ne "https"} {
        error "Wrong proto: $proto"
    }
    if {$port eq ""} {
        if {$proto eq "http"} {
            set port 80
        } elseif {$proto eq "https"} {
            set port 443
        }
    }
    set opts {}
    if {$indiv_timeout ne ""} {
        lappend opts -timeout $indiv_timeout
    }
    if {$expected_hostname ne ""} {
        lappend opts -expected-hostname $expected_hostname
    }

    channel httpout
    channel httperr
    set hlen [llength $hosts]
    foreach i [seq $hlen] {
        set host [lindex $hosts [expr {($hindex+$i) % $hlen}]]
        if {[catch {https curl $proto://$host:${port}${urlpath} {*}$opts -command [list http_handler $httpout $httperr]} out err]} {
            log $err
            continue
        }
        puts "waiting for $host"
        select {
            <- $httpout {
                set token [<- $httpout]
                set data [http::data $token]
                http::cleanup $token
                puts "curl-hosts ok data: $data"
                $tryout <- $data
                channel httpout close
                channel httperr close
                return
            }
            <- $httperr {
                set token [<- $httperr]
                puts "curl-hosts failed with status: [http::status $token] error: [http::error $token]"
                http::cleanup $token
                #TODO logerr
            }
        }
    }
    $tryerr <- "All hosts failed error"
    channel httpout close
    channel httperr close
}

channel tryout
channel tryerr
set hosts {8.8.8.8 8.8.4.4 91.227.221.115}
#set hosts {8.8.8.8 8.8.4.4}
#hosts start index
set hindex 3
set urlpath /test.html
set indiv_timeout 3000
set proto https
set port 443
set expected_hostname www.securitykiss.com

go curl-hosts $tryout $tryerr -hosts $hosts -hindex $hindex -urlpath $urlpath -indiv_timeout $indiv_timeout -proto $proto -port $port -expected_hostname $expected_hostname

select {
    <- $tryout {
        set data [<- $tryout]
        puts "curl-hosts success data: $data"
    }
    <- $tryerr {
        set err [<- $tryerr]
        puts "curl-hosts failed with error: $err"
    }
}

channel tryout close
channel tryerr close

puts Finished










if 0 {
channel c1

puts "c1=$c1"

ticker t1 1000
timer t2 3000
timer t3 4000

proc myrout {t} {
    puts "myrout"
    while 1 {
        puts [<- $t]
    }
}

proc selrout {t1 t2} {
    puts "selrout"
    while 1 {
        select {
            <- $t1 {
                puts "select t1: [<- $t1]"
            }
            <- $t2 {
                puts "select t2: [<- $t2]"
            }
        }
    }
}

proc receiver {c} {
    puts "receiver started"
    while 1 {
        puts "receiver: [<- $c]"
    }
    puts "receiver ended"
}


#go myrout $t1
#go selrout $t1 $t2
puts "main"

#while 1 { puts "ticker: [<- $t1]" }

$t1 <- blabla
$t1 <- uuu
$t1 <- tttt

<- $t3


channel c1 10

$c1 <- 11
$c1 <- 22
channel c1 close

#go receiver $c1


range v $c1 {
    puts "bing: $v"
}

#vwait forever
}


if 0 {

package require linuxdeps
package require skutil
package require Tclx
package require unix

proc signal-handler {} {
    puts "SIGNAL caught"
    #Do cleanup
    exit 0
}
 
signal trap {SIGTERM SIGINT SIGQUIT} signal-handler

puts "is X running: [unix is-x-running]"


puts "id user: [id user]"
puts "id group: [id group]"
exec touch file1111
puts "HOME: $env(HOME)"
puts "dropped root: [unix relinquish-root]"
puts "id user: [id user]"
puts "id group: [id group]"
exec touch file2222
puts "HOME: $env(HOME)"
vwait forever

puts "BEFORE linuxdeps"
linuxdeps tk-install
puts "AFTER linuxdeps"
}
