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
