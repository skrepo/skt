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



package require https

proc background-error {msg err} {
    puts "$msg [dict get $err -errorinfo]"
}

interp bgerror "" background-error


#https wget https://www.securitykiss.com/favicon.ico favicon.ico

#puts [https curl https://www.securitykiss.com/geo-ip.php]

#set tok [https curl-async https://www.securitykiss.com/geo-ip.php]


set tok [https wget-async https://www.securitykiss.com/favicon.ico favicon.ico]
#set tok [https wget-async https://91.227.221.115/favicon.ico favicon.ico]
#set tok [https wget-async https://sk/favicon.ico favicon.ico]

# wrong cert website 
#set tok [https curl-async https://tv.eurosport.com]

puts "Entering event loop"
vwait forever
