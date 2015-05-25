if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}


#package require skutil
#set tok [http::geturl https://news.ycombinator.com/]
#Since url redirect not supported yet, use direct url
#wget https://github.com/skrepo/activestate/raw/master/teacup/tls/package-tls-0.0.0.2010.08.18.09.08.25-source.zip tls-source.zip
#wget https://raw.githubusercontent.com/skrepo/activestate/master/teacup/tls/package-tls-0.0.0.2010.08.18.09.08.25-source.zip tls-source.zip
#wget https://sk/favicon.ico favicon.ico

package require i18n

if {[catch {i18n load pl} out err]} {
    puts "ERROR caught: $out"
}

set nrOfFruits 3
set fruit apple

puts [_ "We need {0} {1} to feed the children" $nrOfFruits $fruit] ;# _d789097c30b6a705


# give more examples
puts "First: [_ "This is my example"]  Second: [_ "With {0} message in one line" 1]"  ;# _afff6937b45e6bea _36fbc2379cb3b1e4

puts "Third: [_ "uu uu" arg1 arg2][_ "bi bi bi" param1 param2][_ "cicicici cicici"]"  ;# _17788f47d34b7db8 _4e3a1066125da9e2 _245044b4b04cba100


#i18n code2msg ~/seckiss/skt/sample/main.tcl


i18n msg2code  ~/seckiss/skt/sample/main.tcl


exit




package require inicfg

set d [inicfg::load my.ini]

#puts $d
#puts "pretty printed dict:"
#puts [inicfg dict-pretty $d]

dict set d add1 dodane
dict set d PORT add2 ddddoodda
dict set d PORT FIRST add3 duuuddd
dict unset d HOST insection

set r [inicfg save other.ini $d]
set r [inicfg save my.ini $d]

puts "REPORT:"
puts "$r"
exit



package require skutil

puts "topdir: $starkit::topdir"
set fname [file join $starkit::topdir main.tcl]

set data [slurp $fname]
puts "data: $data"

exit


proc beat {} {
    puts -nonewline .
    flush stdout
    after 300 beat
}

after 300 beat





proc background-error {msg err} {
    puts "$msg [dict get $err -errorinfo]"
}

interp bgerror "" background-error


package require https
https wget https://www.securitykiss.com/favicon.ico favicon.ico

puts [https curl https://www.securitykiss.com/geo-ip.php]
set tok [https curl https://www.securitykiss.com/geo-ip.php -command ::https::curl-callback]
puts [https curl https://91.227.221.115/geo-ip.php -expected-hostname www.securitykiss.com]

set tok [https wget https://www.securitykiss.com/favicon.ico favicon.ico -command ::https::wget-callback]
puts [https curl https://91.227.221.115/geo-ip.php -expected-hostname www.securitykiss.com]
#https curl https://sk/geo-ip.php

# wrong cert website 
puts [https curl https://tv.eurosport.pl -expected-hostname a248.e.akamai.net]


puts "Entering event loop"
vwait forever
exit


#
#         Consider using wrap template to curry function calls for subtask/sequence in EDP
#



package require asyncdns

proc dns-resolve {token} {
    upvar 0 $token state
    puts "parray state:"
    parray state
    puts "resolved ip: $state(ip)"
    asyncdns cleanup $token
}

set token [asyncdns resolve -command dns-resolve securitykiss.com]


puts "Entering event loop"
vwait forever

