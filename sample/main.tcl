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



#package require https

proc background-error {msg err} {
    puts "$msg [dict get $err -errorinfo]"
}

interp bgerror "" background-error


#https wget https://www.securitykiss.com/favicon.ico favicon.ico

#puts [https curl https://www.securitykiss.com/geo-ip.php]

#set tok [https curl-async https://www.securitykiss.com/geo-ip.php]


#set tok [https wget-async https://www.securitykiss.com/favicon.ico favicon.ico]
#set tok [https wget-async https://91.227.221.115/favicon.ico favicon.ico]
#set tok [https wget-async https://sk/favicon.ico favicon.ico]

# wrong cert website 
#set tok [https curl-async https://tv.eurosport.com]

#package require Tclx
#puts [host_info addresses google.com]
#exit

#package require dns

#proc dns-callback {tok} {
#    puts "dns::status: [dns::status $tok]"
#    puts "dns::address: [dns::address $tok]"
#    puts "dns::name: [dns::name $tok]"
#    dns::cleanup $tok
#}

#set tok [dns::resolve -protocol udp -command dns-callback -nameserver 8.8.8.8 www.tcl.tk ]
#set tok [dns::resolve -protocol udp -nameserver 8.8.8.8 securitykiss.com ]
#puts "wait: [dns::wait $tok]"
#puts "error: [dns::error $tok]"
#puts "dns::status: [dns::status $tok]"
#after 2000 dnsread

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

