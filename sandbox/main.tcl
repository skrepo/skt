package require csp
namespace import csp::*

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

#go myrout $t1
go selrout $t1 $t2
puts "main"

#while 1 { puts "ticker: [<- $t1]" }

$t1 <- blabla
$t1 <- uuu
$t1 <- tttt

<- $t3


#vwait forever



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
