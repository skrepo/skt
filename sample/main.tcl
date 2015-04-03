lappend auto_path lib/linux-ix86


package require http
package require tls

http::register https 443 [list tls::socket]


#TODO support url redirect (Location header)
proc wget {url filepath} {
  set fo [open $filepath w]
  set tok [http::geturl $url -channel $fo]
  close $fo
  foreach {name value} [http::meta $tok] {
    puts "$name: $value"
  }
  http::cleanup $tok
}

#set tok [http::geturl https://news.ycombinator.com/]

#Since url redirect not supported yet, use direct url
#wget https://github.com/skrepo/activestate/raw/master/teacup/tls/package-tls-0.0.0.2010.08.18.09.08.25-source.zip tls-source.zip

wget https://raw.githubusercontent.com/skrepo/activestate/master/teacup/tls/package-tls-0.0.0.2010.08.18.09.08.25-source.zip tls-source.zip




