package require csp
namespace import csp::*

proc tryhosts {ch hosts urlpath proto port expected_hostname} {
    https curl $proto://$host:${port}${urlpath} -timeout $indiv_timeout -expected-hostname $expected_hostname \
        -command [concat curl-retry [args- -tok -attempts] -attempts $attempts -tok
}


channel chresp
set hosts {8.8.8.8 8.8.4.4 91.227.221.115}
set urlpath /test.html
set proto https
set port 443
set expected_hostname www.securitykiss.com

go tryhosts $chresp $hosts $urlpath $proto $port $expected_hostname


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
