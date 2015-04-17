package require linuxdeps
package require skutil
package require Tclx
package require unix




puts "id user: [id user]"
puts "id group: [id group]"
exec touch file1111
puts "RRRRRR: [unix relinquish-root]"
puts "id user: [id user]"
puts "id group: [id group]"
exec touch file2222
exit

puts "BEFORE linuxdeps"
linuxdeps install
puts "AFTER linuxdeps"
