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


set tok [https wget https://www.securitykiss.com/favicon.ico favicon.ico -command ::https::wget-callback]
puts [https curl https://91.227.221.115/geo-ip.php -expected-hostname www.securitykiss.com]
#https curl https://sk/geo-ip.php

# wrong cert website 
puts [https curl https://tv.eurosport.pl -expected-hostname a248.e.akamai.net]


puts "Entering event loop"
vwait forever
exit


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

