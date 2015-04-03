package require http
package require tls

set tls::debug 3
http::register https 443 [list tls::socket]

set tok [http::geturl https://news.ycombinator.com/]

puts [http::data $tok]
