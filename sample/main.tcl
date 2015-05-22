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

set nrOfFruits 3
set fruit apple

puts [_ "We need {0} {1} to feed the children" $nrOfFruits $fruit] ;# _444cca97f3240434

 ;# _183f7a8e54b7c123

# give more examples
puts "First: [_ "This is yur    example"]  Second: [_ "With {0} message in one line" 1]" ;# _bc3e28b0754207bc  ;# _277fa14dce3ed4c8

puts "Third: [_ aa][_ bb][_ cccc]" ;# _aa3d6657129a20ec ;# _7b75a0dfb2c07a88 ;# _7c90362c64745aa9


i18n code2msg ~/seckiss/skt/sample/main.tcl

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

