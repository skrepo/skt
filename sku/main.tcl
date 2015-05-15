#
# sku.tcl
#
# This should be the preamble to every application
# It makes it possible to run as starpack or as a sourced script
if {![catch {package require starkit}]} {
  #this is to initialize starkit variables
  starkit::startup
}

package require ovconf
package require tls
#package require http
package require cmdline
package require unix
package require linuxdeps
#http::register https 443 [list tls::socket]
# skutil must be last required package in order to overwrite the log proc from Tclx
package require skutil
package require https
package require anigif
package require json

set ::LOGFILE ~/.sku/sku.log

proc fatal {msg err} {
    log $err
    in-ui error $msg
    main-exit
}

proc background-error {msg err} {
    fatal $msg [dict get $err -errorinfo]
}

interp bgerror "" background-error
#after 4000 {error "This is my bg error"}


namespace eval tolog {
    variable fh
    proc initialize {args} {
        variable fh
        # if for some reason cannot log to file, log to stderr
        if {[catch {mk-head-dir $::LOGFILE} out err] == 1 || [catch {set fh [open $::LOGFILE w]} out err] == 1} {
            set fh stderr
            puts stderr $err
        }
        info procs
    }
    proc finalize {args} {
        variable fh
        catch {close $fh}
    }
    proc clear {args} {}
    proc flush {handle} {
        variable fh
        if {[catch {::flush $fh} out err] == 1} {
            set fh stderr
            puts stderr $err
        }
    }
    proc write {handle data} {
        variable fh
        # again, downgrade to logging to stderr if problems with writing to file
        if {[catch {puts -nonewline $fh $data} out err] == 1} {
            set fh stderr
            puts stderr $err
        }
        flush $fh
    }
    namespace export *
    namespace ensemble create
}



proc redirect-stdout {} {
    chan push stdout tolog
}



# Parse command line options and launch proper task
# It may set global variables
proc main {} {
    set user [unix relinquish-root]
    redirect-stdout
    dbg user
    

    state sku {
        # SKD connection socket 
        skd_sock ""
        # User Interface (gui or cli)
        ui ""
        # Start retries
        start_retries 0
        # Embedded bootstrap vigo list
        vigos ""
        # temporary
        slist ""
    }


    # watch out - cmdline is buggy. For example you cannot define help option, it conflicts with the implicit one
    set options {
            {cli            "Run command line interface (CLI) instead of GUI"}
            {generate-keys  "Generate private key and certificate signing request"}
            {id             "Show client id from the certificate"}
            {version        "Print version"}
            {p              "Print anything"}
            {ra             "Print anything"}
        }
    set usage ": sku \[options]\noptions:"
    if {[catch {array set params [::cmdline::getoptions ::argv $options $usage]}] == 1} {
        log [cmdline::usage $options $usage]
        exit 1
    }
    log Params:
    parray params

    # embedded bootstrap vigo list
    set lst [slurp [file join $starkit::topdir bootstrap_ips.lst]]
    set vigos ""
    foreach v $lst {
        set v [string trim $v]
        if {[is-valid-ip $v]} {
            lappend vigos $v
        }
    }
    state sku {vigos $vigos}
    puts "vigos: $vigos"
    #TODO use vigos to get current time - why do we need it before welcome?.
    #TODO isn't certificate signing start date a problem in case of vigos in different timezones? Consider signing with golang crypto libraries
    
    # Copy cadir because it  must be accessible from outside of starkit
    # Overwrites certs on every run
    set cadir [file normalize ~/.sku/certs]
    copy-merge [file join $::starkit::topdir certs] $cadir
    https init -cadir $cadir
 

    if {$params(id)} {
        main-id
        main-exit
    }

    if {$params(generate-keys)} {
        main-generate-keys
        main-exit
    }
    if {$params(version)} {
        main-version
        main-exit
    }

    if {$params(cli) || ![unix is-x-running]} {
        state sku {ui cli}
    } else {
        state sku {ui gui}
    }

    if {[catch {create-pidfile ~/.sku/sku.pid} out err] == 1} {
        fatal "Could not create ~/.sku/sku.pid file" $err
    }
    skd-connect 7777
    after idle main-start
}

proc main-id {} {
    if {[catch {cn-from-cert [file normalize ~/.sku/keys/client.crt]} cn err] == 1} {
        puts stderr "Could not retrieve client id"
        log $err
    } else {
        #TODO after logging redesign it should go to stdout
        puts stderr $cn
    }
}

proc main-exit {} {
    if {[catch {delete-pidfile ~/.sku/sku.pid} out err] == 1} {
        # don't use fatal here to avoid endless loop
        puts stderr "Could not delete ~/.sku/sku.pid file"
        puts stderr $err
    }
    set ::until_exit 1
    #TODO Disconnect and clean up
    catch {close [state sku skd_sock]}
    catch {destroy .}
    exit
}


# it may be called many times by events retrying to start after lib install
proc main-start {} {

    set retries [state sku start_retries]
    state sku {start_retries [incr retries]}
    log start_retries: [state sku start_retries]
    # give up after a number of retries
    if {$retries > 5} {
        in-ui error "Could not main-start after a number of retries"
        return
    }

    # Ignore result of openvpn install - it may be handled later, when GUI is running
    check-openvpn-deps

    if {[state sku ui] eq "gui"} {
        log Running check-tk-deps
        # if no missing libs start UI
        if {![check-tk-deps]} {
            in-ui main
        }
    }
}

# Combine $fun and $ui to run proper procedure in gui or cli
proc in-ui {fun args} {
    set ui [state sku ui]
    [join [list $fun $ui] -] {*}$args
}


proc error-gui {msg} {
    # if Tk not functional downgrade displaying errors to cli
    if {[is-tk-loaded]} {
        # hide toplevel window. Use wm deiconify to restore later
        catch {wm withdraw .}
        log $msg
        tk_messageBox -title "SKU error" -type ok -icon error -message ERROR -detail "$msg\n\nPlease check ~/.sku/sku.log for details"
    } else {
        error-cli $msg
    }
}

proc error-cli {msg} {
    log $msg
    puts stderr $msg
}


# Check if openvpn is installed. 
# If not send pkg-install request to SKD
# Return 1 if request sent, 0 otherwise
proc check-openvpn-deps {} {
    if {![linuxdeps is-openvpn-installed]} {
        skd-write "pkg-install openvpn"
        return 1
    } else {
        return 0
    }
}

# Check if there is a missing lib that Tk depends on
# If so send lib-install request to SKD
# Return 1 if request sent, 0 otherwise
proc check-tk-deps {} {
    set missing_lib [linuxdeps tk-missing-lib]
    if {[llength $missing_lib] != 0} {
        skd-write "lib-install $missing_lib"
        return 1
    } else {
        # hide toplevel window. Use wm deiconify to restore later
        wm withdraw .
        return 0
    }
}


# This is blocking procedure to be run from command line
# ruturn 1 on success, 0 otherwise
# Print to stderr for user-visible messages. Use log for detailed info written to log file
proc main-generate-keys {} {
    log Generating RSA keys
    set privkey [file normalize ~/.sku/keys/client_private.pem]
    if {[file exists $privkey]} {
        log RSA key $privkey already exists
    } else {
        if {![generate-rsa $privkey]} {
            return 0
        }
    }
    set csr [file normalize ~/.sku/keys/client.csr]
    if {[file exists $csr]} {
        log CSR $csr already exists
    } else {
        set cn [generate-cn]
        if {![generate-csr $privkey $csr $cn]} {
            return 0
        }
    }


    # POST csr and save cert
    for {set i 0} {$i<[llength [state sku vigos]]} {incr i} {
        if {[catch {open $csr r} fd err] == 1} {
            log "Failed to open $csr for reading"
            log $err
        }
        set vigo [get-next-vigo "" $i]
        puts -nonewline stderr "Trying vigo $vigo...\t"
        #TODO expected-hostname should not be needed - ensure that vigo provides proper certificate with IP common name
        if {[catch {https curl https://$vigo:10443/sign-cert -timeout 8000 -method POST -type text/plain -querychannel $fd -expected-hostname www.securitykiss.com} crtdata err] == 1} {
            puts stderr FAILED
            log $err
            close $fd
        } else {
            puts stderr OK
            puts stderr "Received the signed certificate"
            log crtdata: $crtdata
            spit [file normalize ~/.sku/keys/client.crt] $crtdata
            close $fd
            break
        }
    }
    return 1
}


#TODO generate from HD UUID/dbus machine-id and add sha256 for checksum/proof of work
proc generate-cn {} {
    return [join [lmap i [seq 8] {rand-byte-hex}] ""]
}

proc main-version {} {
    log SKU Version:
    #TODO
}

proc main-cli {} {
    log Running CLI
    #TODO
}

# height should be odd value
proc hsep {parent height} {
    set height [expr {($height-1)/2}]
    static counter 0
    incr counter
    frame $parent.sep$counter ;#-background yellow
    grid $parent.sep$counter -padx 10 -pady $height -sticky news
}


proc main-gui {} {
    log Running GUI

    package require Tk 
    package require Tkhtml

    wm deiconify .
    wm protocol . WM_DELETE_WINDOW {
        #TODO improve the message
        main-exit
        if {[tk_messageBox -message "Quit?" -type yesno] eq "yes"} {
            main-exit
        }
    }

    set clientNo [get-client-no OpenVPN/config/client.crt]

    #TODO remove caching
    if 0 {
    set url "https://www.securitykiss.com/sk/app/display.php?c=$clientNo&v=0.3.0"
    set welcome [https curl $url -expected-hostname www.securitykiss.com]
    spit display.htm $welcome
    } else {
        set welcome [slurp display.htm]
    }
    
    #TODO remove caching
    if 0 {
    set url "https://www.securitykiss.com/sk/app/usage.php?c=$clientNo"
    set usage [https curl $url -expected-hostname www.securitykiss.com]
    spit usage.htm $usage
    } else {
        set usage [slurp usage.htm]
    }
    set serverlist [get-server-list $welcome]
    set ::serverdesc [lindex $serverlist 0]
    set ::status "Not connected"
    
    set config [get-ovpn-config $welcome]
    spit config.ovpn $config
 
if 0 {    
    ttk::label .p1 -text $clientNo
    grid .p1 -pady 5
    html .p2 -shrink 1
    .p2 parse -final $usage
    grid .p2
    frame .p3
    ttk::button .p3.connect -text Connect -command ClickConnect
    ttk::button .p3.disconnect -text Disconnect -command ClickDisconnect
    ttk::combobox .p3.combo -width 35 -textvariable ::serverdesc
    .p3.combo configure -values $serverlist
    .p3.combo state readonly
    grid .p3.connect .p3.disconnect .p3.combo -padx 10 -pady 10
    grid .p3
    ttk::label .p4 -textvariable ::status
    grid .p4 -sticky w -padx 5 -pady 5
} else {

    set bg1 white
    set bg2 grey95
    set bg3 "light grey"

    frame .c
    grid .c -sticky news
    grid columnconfigure . .c -weight 1
    grid rowconfigure . .c -weight 1

    hsep .c 15

    frame .c.p1 -background $bg1
    
    ttk::label .c.p1.plan -text "Plan JADEITE valid until 2015 Sep 14" -background $bg1
    ttk::label .c.p1.usedlabel -text "This month used" -background $bg1
    frame .c.p1.usedbar -background $bg3 -width 300 -height 8
    frame .c.p1.usedbar.fill -background red -width 120 -height 8
    place .c.p1.usedbar.fill -x 0 -y 0
    grid columnconfigure .c.p1.usedbar 0 -weight 1
    ttk::label .c.p1.usedsummary -text "12.4 GB / 50 GB" -background $bg1
    ttk::label .c.p1.elapsedlabel -text "This month elapsed" -background $bg1
    frame .c.p1.elapsedbar -background $bg3 -width 300 -height 8
    frame .c.p1.elapsedbar.fill -background blue -width 180 -height 8
    place .c.p1.elapsedbar.fill -x 0 -y 0
    ttk::label .c.p1.elapsedsummary -text "3 days 14 hours / 31 days" -background $bg1
    grid .c.p1.plan -column 0 -row 0 -columnspan 3 -padx 5 -pady 5 -sticky w
    grid .c.p1.usedlabel .c.p1.usedbar .c.p1.usedsummary -row 1 -padx 5 -pady 5 -sticky w
    grid .c.p1.elapsedlabel .c.p1.elapsedbar .c.p1.elapsedsummary -row 2 -padx 5 -pady 5 -sticky w
    grid .c.p1 -padx 10 -sticky news


    hsep .c 5

    frame .c.p7 -background $bg2
    ttk::label .c.p7.externalip -text "External IP: 123.123.123.123" -background $bg2
    ttk::label .c.p7.geocheck -text "Geo check" -background $bg2
    grid .c.p7.externalip -column 0 -row 2 -padx 10 -pady 5 -sticky w
    grid .c.p7.geocheck -column 1 -row 2 -padx 10 -pady 5 -sticky w
    grid .c.p7 -padx 10 -sticky news
    

    #hsep .c 5




    frame .c.p5 -background $bg2
    label .c.p5.imagestatus -background $bg2
    place-image status/disconnected.png .c.p5.imagestatus
    after 2000 [list place-image status/connecting.gif .c.p5.imagestatus]
    after 4000 [list place-image status/connected.png .c.p5.imagestatus]
    ttk::label .c.p5.status -text "Connected to ..." -background $bg2
    load-image flag/64/PL.png
    ttk::label .c.p5.flag -image flag_64_PL -background $bg2
    grid .c.p5.imagestatus -row 5 -column 0 -padx 10 -pady 5
    grid .c.p5.status -row 5 -column 1 -padx 10 -pady 5 -sticky w
    grid .c.p5.flag -row 5 -column 2 -padx 10 -pady 5 -sticky e
    grid columnconfigure .c.p5 .c.p5.status -weight 1
    grid .c.p5 -padx 10 -sticky news

    hsep .c 15


    frame .c.p3 ;#-background yellow
    ttk::button .c.p3.connect -text Connect -command ClickConnect
    ttk::button .c.p3.disconnect -text Disconnect -command ClickDisconnect
    ttk::button .c.p3.slist -text Servers -command ServerListClicked
    grid .c.p3.connect .c.p3.disconnect .c.p3.slist -padx 10
    grid columnconfigure .c.p3 .c.p3.slist -weight 1
    grid .c.p3 -sticky news
    focus .c.p3.slist

    # If the tag is the name of a class of widgets, such as Button, the binding applies to all widgets in that class;
    bind Button <Return> InvokeFocusedWithEnter
    bind TButton <Return> InvokeFocusedWithEnter
    #TODO coordinate with shutdown hook and provide warning/confirmation request
    bind . <Control-w> main-exit
    bind . <Control-q> main-exit

    hsep .c 15


    grid columnconfigure .c 0 -weight 1
    # this will allocate spare space to the first row in container .c
    grid rowconfigure .c 0 -weight 1
    #instead of [wm minsize . 200 200]
    setDialogMinsize .
    # sizegrip - bottom-right corner for resize
    grid [ttk::sizegrip .grip] -sticky se
    
    #source [file join $::starkit::topdir dialog.tcl]    

}
    set ::conf [::ovconf::parse config.ovpn]
    after idle ReceiveWelcome
}

proc InvokeFocusedWithEnter {} {
    set focused [focus] ;# or [focus -displayof .]
    if {$focused eq ""} {
        return
    }
    set type [winfo class $focused]
    switch -glob $type {
        *Button {
            # this matches both Button and TButton
            $focused invoke
        }
        Treeview {
            puts stderr "selected: [$focused selection]"
        }
    }
}


proc setDialogMinsize {window} {
   # this update will ensure that winfo will return the correct sizes
   update
   # get the current width and height
   set winWidth [winfo width $window]
   set winHeight [expr {[winfo height $window] + 10}]
   # set it as the minimum size
   wm minsize $window $winWidth $winHeight
}

proc ServerListClicked {} {
    set slist [state sku slist]
    set ssel 2
    #TODO validate ssel is in slist, otherwise select first one
    #TODO sorting by country
    set newsel [slistDialog $slist $ssel]
    puts stderr "New selected server: $newsel"
}


# Return new sitem id if selection made or empty string if canceled
proc slistDialog {slist ssel} {
    set w .slist_dialog
    catch { destroy $w }
    toplevel $w
    puts stderr $slist
    set wt $w.tree

    ttk::treeview $wt -columns "country city ip" -selectmode browse
    
    $wt heading #0 -text F
    $wt heading 0 -text Country
    $wt heading 1 -text City
    $wt heading 2 -text IP
    $wt column #0 -width 50 -anchor nw -stretch 0
    $wt column 0 -width 140 -anchor w
    $wt column 1 -width 140 -anchor w
    $wt column 2 -width 140 -anchor w
    
    foreach sitem $slist {
        set id [dict get $sitem id]
        set ccode [dict get $sitem ccode]
        set country [dict get $sitem country]
        set city [dict get $sitem city]
        set ip [dict get $sitem ip]
        load-image flag/24/$ccode.png
        $wt insert {} end -id $id -image flag_24_$ccode -values [list $country $city $ip]
    }
    $wt selection set $ssel
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1
    grid $wt -sticky news

    set wb $w.buttons
    frame $wb
    # width may be in pixels or in chars depending on presence of the image
    button $wb.cancel -text Cancel -width 10 -command [list set ::Modal.Result cancel]
    button $wb.ok -text OK -width 10 -command [list set ::Modal.Result ok]
    grid $wb -sticky news
    grid $wb.cancel -row 5 -column 0 -padx {30 0} -pady 5 -sticky w
    grid $wb.ok -row 5 -column 1 -padx {0 30} -pady 5 -sticky e
    grid columnconfigure $wb 0 -weight 1
    grid columnconfigure $wb 1 -weight 1

    bind Treeview <Return> [list set ::Modal.Result ok]
    bind Treeview <Double-Button-1> [list set ::Modal.Result ok]
    bind $w <Escape> [list set ::Modal.Result cancel]
    bind $w <Control-w> [list set ::Modal.Result cancel]
    bind $w <Control-q> [list set ::Modal.Result cancel]


    focus $wt
    $wt focus $ssel
    set modal [ShowModal $w]
    puts stderr "modal: $modal"
    set newsel ""
    if {$modal eq "ok"} {
        set newsel [$wt selection]
    }
    destroy $w
    return $newsel
}



#-----------------------------------------------------------------------------
# ShowModal win ?-onclose script? ?-destroy bool?
#
# Displays $win as a modal dialog. 
#
# If -destroy is true then $win is destroyed when the dialog is closed. 
# Otherwise the caller must do it. 
#
# If an -onclose script is provided, it is executed if the user terminates the 
# dialog through the window manager (such as clicking on the [X] button on the 
# window decoration), and the result of that script is returned. The default 
# script does nothing and returns an empty string. 
#
# Otherwise, the dialog terminates when the global ::Modal.Result is set to a 
# value. 
#
# This proc doesn't play nice if you try to have more than one modal dialog 
# active at a time. (Don't do that anyway!)
#
# Examples:
#   -onclose {return cancel}    -->    ShowModal returns the word 'cancel'
#   -onclose {list 1 2 3}       -->    ShowModal returns the list {1 2 3}
#   -onclose {set ::x zap!}     -->    (variations on a theme)
#
proc ShowModal {win args} {
    set ::Modal.Result {}
    array set options [list -onclose {} -destroy 0 {*}$args]
    wm transient $win .
    wm protocol $win WM_DELETE_WINDOW [list catch $options(-onclose) ::Modal.Result]
    set x [expr {([winfo width  .] - [winfo reqwidth  $win]) / 2 + [winfo rootx .]}]
    set y [expr {([winfo height .] - [winfo reqheight $win]) / 2 + [winfo rooty .]}]
    wm geometry $win +$x+$y
    raise $win
    focus $win
    grab $win
    tkwait variable ::Modal.Result
    grab release $win
    if {$options(-destroy)} {destroy $win}
    return ${::Modal.Result}
}





# tablelist vs TkTable vs treectrl vs treeview vs BWidget::Tree


# e.g. load-image flag/pl.png - it should load image under the name flag_pl and return that name
proc load-image {path} {
    set imgobj [string map {/ _} [file rootname $path]]
    #TODO check if replacing / with \ is necessary on windows
    uplevel [list image create photo $imgobj -file [file join $::starkit::topdir images $path]]
    return $imgobj
}

proc place-image {path lbl} {
    if {[file extension $path] eq ".gif"} {
        anigif::stop $lbl
        anigif::anigif [file join $::starkit::topdir images $path] $lbl
    } else {
        anigif::stop $lbl
        set imgobj [load-image $path]
        $lbl configure -image $imgobj
    }
}
    

proc ReceiveWelcome {{tok ""}} {
    static attempts 0
    static vigo_lastok
    # Unfortunately http is catching callback errors and they don't propagate to our background-error, so we need to catch them all here and log
    if {[catch {
        if {$tok eq ""} {
            # reset retry counter when called initially (without the token that comes from http callback)
            set attempts 0
        } else {
            if {$tok ne "error"} {
                set ncode [http::ncode $tok]
                set status [http::status $tok]
                set data [http::data $tok]
                upvar #0 $tok state
                set url $state(url)
                if {$status eq "ok" && $ncode == 200} {
                    #TODO save welcome in config
                    #tk_messageBox -message "Welcome received: $data" -type ok
                    log Welcome message received:\n$data
                    puts stderr "welcome: $data"
    
                    set d [json::json2dict $data]
                    puts stderr "dict: $d"
                    puts stderr ""
                    set slist [dict get $d server-lists JADEITE]
                    state sku {slist $slist}
    
                    array set parsed [https parseurl $url]
                    set vigo_lastok $parsed(host)
                    http::cleanup $tok
                    return
                }
            }
            log Request for token $tok failed
            incr attempts
            http::cleanup $tok
        }
     
        # We are here only if welcome request did not succeed yet
        # Try again if max retries not exceeded
        if {$attempts < [llength [state sku vigos]]} {
            set vigo [get-next-vigo $vigo_lastok $attempts]
            set cn [cn-from-cert [file normalize ~/.sku/keys/client.crt]]
            # although scheduled for non-blocking async it may still throw error here when network is unreachable
            if {[catch {https curl https://$vigo:10443/welcome?cn=$cn -timeout 8000 -expected-hostname www.securitykiss.com -command ReceiveWelcome} out err] == 1} {
                log $err
                after idle {ReceiveWelcome error}
            }
        } else {
            # ReceiveWelcome failed for all vigos
            #TODO use cached config
            tk_messageBox -message "Could not receive Welcome message" -type ok
            return
        }
    } out err] == 1} {
        # catch was returning 2 in spite of no error (-code 0) - that's why the check == 1 above. Probably bug in Tcl
        error $err
    }
}

# get next vigo to try based on the attempt number relative the last succeeded vigo
proc get-next-vigo {vigo_lastok attempt} {
    #if connected use vigo internal IP regardless of attempt
    #else use vigo list
    set i [lsearch -exact [state sku vigos] $vigo_lastok]
    if {$i == -1} {
        set i 0
    }
    set next [expr {($i + $attempt) % [llength [state sku vigos]]}]
    set vigo [lindex [state sku vigos] $next]
    return $vigo
}


proc skd-connect {port} {
    #TODO handle error
    if {[catch {set sock [socket 127.0.0.1 $port]} out err] == 1} {
        skd-close $err
    }
    state sku {skd_sock $sock}
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable skd-read
}


proc skd-write {msg} {
    if {[catch {puts [state sku skd_sock] $msg} out err] == 1} {
        skd-close $err
    }
}

proc skd-close {err} {
    catch {close [state sku skd_sock]}
    fatal "Could not communicate with SKD. Please check if skd service is running and check logs in /var/log/skd.log" $err
}


#TODO detect disconnecting from SKD - sock monitoring?
proc skd-read {} {
    set sock [state sku skd_sock]
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            skd-close "skd_sock EOF. Connection terminated"
        }
        return
    }
    switch -regexp -matchvar tokens $line {
        {^ctrl: (.*)$} {
            switch -regexp -matchvar details [lindex $tokens 1] {
                {^Welcome to SKD} {
                    if {$::tcl_platform(platform) eq "windows"} {
                        #set conf [::ovconf::parse {c:\temp\Warsaw_195_162_24_220_tcp_443.ovpn}]
                        #set conf [::ovconf::parse {c:\temp\securitykiss_winopenvpn_client00000001\openvpn.conf}]
                        #set conf [::ovconf::parse config.ovpn]
                    } else {
                        #set conf [::ovconf::parse /home/sk/openvpn/Lodz_193_107_90_205_tcp_443.ovpn]
                        #set conf [::ovconf::parse /home/sk/openvpn/securitykiss_winopenvpn_client00000001/openvpn.conf]
                        #set conf [::ovconf::parse config.ovpn]
                    }
                    #skd-write "config $conf"
                }
                {^Config loaded} {
                    skd-write start
                }
                {^pkg-install ended with result} {
                    after idle main-start
                }

            }
        }
        {^ovpn: (.*)$} {
            set ::status [lindex $tokens 0]
        }
        {^pkg: (.*)$} {
            #TODO can we parse pkg-mgr output to see success/failure? Aren't messages i18ned?


        }

    }
    log SKD>> $line
}

# Extract server list from welcome message
# Return multi-line string with each line representing a server like:
# LosAngeles 23.19.26.250 UDP 123
proc get-server-list {s} {
    set res {}
    set lines [split $s \n]
    foreach l $lines {
        if {[string first "<!-- " $l] != 0} {
            continue
        }
        set l [join [lrange $l 1 end-1]]
        if {[string first "#remote" $l] == 0} {
            set tokens [split $l ,]
            set serv [join [lindex $tokens 2] ""]
            append serv " "
            append serv [join [lrange $tokens 3 4]]
            append serv " "
            append serv [lindex [lindex $tokens 5] 1]
            lappend res $serv
        }
    }
    return $res
}

proc get-ovpn-config {s} {
    set res {}
    set lines [split $s \n]
    foreach l $lines {
        if {[string first "<!-- " $l] != 0} {
            continue
        }
        set l [join [lrange $l 1 end-1]]
        if {[string first "#" $l] == 0} {
            continue
        }
        if {[string first "SecurityKISS" $l] == 0} {
            continue
        }
        if {[string first "proto" $l] == 0} {
            continue
        }
        if {[string first "remote" $l] == 0} {
            continue
        }
        lappend res $l
    }
    return [join $res \n]
}

proc get-client-no {crtpath} {
    set crt [slurp $crtpath]
    regexp {CN=(client\d{8})} $crt _ cn
    return $cn
}

    


#proc curl {url data_var} {
#    upvar $data_var data
#    set tok [http::geturl $url]
#    set ncode [http::ncode $tok]
#    set data [http::data $tok]
#    http::cleanup $tok
#    return $ncode
#}
 

proc ClickConnect {} {
    set localconf $::conf
    set ip [lindex $::serverdesc 1]
    set proto [lindex $::serverdesc 2]
    set port [lindex $::serverdesc 3]
    append localconf "--proto $proto --remote $ip $port"
    skd-write "config $localconf"
}

proc ClickDisconnect {} {
    skd-write stop
}

proc check-for-upgrades {} {
    # TODO check and save latest version with signature
}


# SKD only to verify signature and run executable
# the rest in SKU
proc upgrade {} {
    # check latest version and checksum
    # compare to current version
    # check if downloaded
    # download if necessary / wget
}


main

vwait ::until_exit
