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
# unix requires Tclx which litters global namespace. Need to clean up to avoid conflict with csp
rename ::select ""
package require linuxdeps
#http::register https 443 [list tls::socket]
package require https
package require json
package require i18n
package require csp
namespace import csp::*
package require Tk 
package require img
# skutil must be last required package in order to overwrite the log proc from Tclx
package require skutil

source [file join [file dir [info script]] model.tcl]


proc fatal {msg {err ""}} {
    log $msg
    log $err
    in-ui error $msg
    main-exit
}


proc background-error {msg err} {
    fatal $msg [dict get $err -errorinfo]
}

interp bgerror "" background-error
#after 4000 {error "This is my bg error"}

# Redirect stdout to a file $::model::LOGFILE
namespace eval tolog {
    variable fh
    proc initialize {args} {
        variable fh
        # if for some reason cannot log to file, log to stderr
        if {[catch {mk-head-dir $::model::LOGFILE} out err] == 1 || [catch {set fh [open $::model::LOGFILE w]} out err] == 1} {
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

    # watch out - cmdline is buggy. For example you cannot define help option, it conflicts with the implicit one
    set options {
            {cli            "Run command line interface (CLI) instead of GUI"}
            {generate-keys  "Generate private key and certificate signing request"}
            {id             "Show client id from the certificate"}
            {version        "Print version"}
            {locale    en   "Run particular language version"}
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


    if {[catch {i18n load pl [file join [file dir [info script]] messages.txt]} out err]} {
        log $out
        log $err
    }

    if {$params(cli) || ![unix is-x-running]} {
        set ::model::Ui cli
    } else {
        set ::model::Ui gui
    }


    if {$params(version)} {
        main-version
        main-exit
    }

    if {$params(id)} {
        set cn [cn-from-cert [file join $::model::KEYSDIR client.crt]]
        if {$cn eq ""} {
            error-cli "Could not retrieve client id. Try to reinstall the program." 
        } else {
            error-cli $cn
        }
        main-exit
    }


    set piderr [create-pidfile ~/.sku/sku.pid]
    if {$piderr ne ""} {
        fatal $piderr
    } 

    model load

    puts stderr [build-date]
    puts stderr [build-version]

    if {$params(generate-keys)} {
        main-generate-keys
        main-exit
    }
    
    # Copy cadir because it  must be accessible from outside of the starkit
    # Overwrites certs on every run
    set cadir [file normalize ~/.sku/certs]
    copy-merge [file join [file dir [info script]] certs] $cadir
    https init -cadir $cadir

    set cn [cn-from-cert [file join $::model::KEYSDIR client.crt]]
    set ::model::Cn $cn
    if {$cn eq ""} {
        fatal "Could not retrieve client id. Try to reinstall the program." 
    }

    skd-connect 7777
    model print
    in-ui main
    # first set connection status to disconnected...
    conn-status-update disconnected
    # ...and then update connection status from SKD
    skd-write status
}


proc main-exit {} {
    model save
    # ignore if problems occurred in deleting pidfile
    delete-pidfile ~/.sku/sku.pid
    set ::until_exit 1
    #TODO Disconnect and clean up
    catch {close [$::model::Skd_sock}
    catch {destroy .}
    exit
}


# Combine $fun and $ui to run proper procedure in gui or cli
proc in-ui {fun args} {
    [join [list $fun $::model::Ui] -] {*}$args
}


proc error-gui {msg} {
    # if Tk not functional downgrade displaying errors to cli
    if {[is-tk-loaded]} {
        # hide toplevel window. Use wm deiconify to restore later
        catch {wm withdraw .}
        log $msg
        tk_messageBox -title "SKU error" -type ok -icon error -message ERROR -detail "$msg\n\nPlease check $::model::LOGFILE for details"
    } else {
        error-cli $msg
    }
}

proc error-cli {msg} {
    log $msg
    puts stderr $msg
}


# This is blocking procedure to be run from command line
# ruturn 1 on success, 0 otherwise
# Print to stderr for user-visible messages. Use log for detailed info written to log file
proc main-generate-keys {} {
    log Generating RSA keys
    set privkey [file join $::model::KEYSDIR client.key]
    if {[file exists $privkey]} {
        log RSA key $privkey already exists
    } else {
        if {![generate-rsa $privkey]} {
            return 0
        }
    }
    set csr [file join $::model::KEYSDIR client.csr]
    if {[file exists $csr]} {
        log CSR $csr already exists
    } else {
        set cn [generate-cn]
        if {![generate-csr $privkey $csr $cn]} {
            return 0
        }
    }


    # POST csr and save cert
    for {set i 0} {$i<[llength $::model::Vigos]} {incr i} {
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
            spit [file join $::model::KEYSDIR client.crt] $crtdata
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
    wm title . "SecurityKISS Tunnel"
    wm deiconify .
    wm protocol . WM_DELETE_WINDOW {
        #TODO improve the message
        main-exit
        if {[tk_messageBox -message "Quit?" -type yesno] eq "yes"} {
            main-exit
        }
    }

    frame .c
    grid .c -sticky news
    grid columnconfigure . .c -weight 1
    grid rowconfigure . .c -weight 1

    tabset-providers

    # If the tag is the name of a class of widgets, such as Button, the binding applies to all widgets in that class;
    bind Button <Return> InvokeFocusedWithEnter
    bind TButton <Return> InvokeFocusedWithEnter
    #TODO coordinate with shutdown hook and provide warning/confirmation request
    bind . <Control-w> main-exit
    bind . <Control-q> main-exit

    grid [ttk::label .statusline -textvariable ::status]
    # sizegrip - bottom-right corner for resize
    grid [ttk::sizegrip .grip] -sticky se

    setDialogSize .
    grid columnconfigure .c 0 -weight 1
    # this will allocate spare space to the first row in container .c
    grid rowconfigure .c 0 -weight 1
    bind . <Configure> [list MovedResized %W %x %y %w %h]

    set ::conf [::ovconf::parse config.ovpn]
    go check-for-updates
    go get-welcome $::model::Cn

}

proc check-for-updates {} {
    channel {chout cherr} 1
    vigo-curl $chout $cherr /check-for-updates
    puts stderr "check-for-updates"
    select {
        <- $chout {
            set data [<- $chout]
            puts stderr "Check for updates: $data"
        }
        <- $cherr {
            set err [<- $cherr]
            puts stderr "Check failed: $err"
        }
    }
    $chout close
    $cherr close
}

proc get-welcome {cn} {
    channel {chout cherr} 1
    vigo-curl $chout $cherr /welcome?cn=$cn
    select {
        <- $chout {
            set data [<- $chout]
            log Welcome message received:\n$data
            puts stderr "welcome: $data"
            set d [json::json2dict $data]
            puts stderr "dict: $d"
            puts stderr ""
            ::model::slist securitykiss [dict get $d serverLists JADEITE]
            #set slist [dict get $d serverLists JADEITE]
            #set ::model::slist $slist
            tk_messageBox -message "Welcome message received" -type ok
        }
        <- $cherr {
            set err [<- $cherr]
            #TODO use cached config
            tk_messageBox -message "Could not receive Welcome message" -type ok
            log get-welcome failed with error: $err
        }
    }
    $chout close
    $cherr close
}


proc vigo-curl {chout cherr urlpath} {
    go curl-hosts $chout $cherr -hosts $::model::Vigos -hindex $::model::vigo_lastok -urlpath $urlpath -proto https -port 10443 -expected_hostname www.securitykiss.com
}

# save main window position and size changes in Config
proc MovedResized {window x y w h} {
    if {$window eq "."} {
        set ::model::layout_x $x
        set ::model::layout_y $y
        set ::model::layout_w $w
        set ::model::layout_h $h
        #puts stderr "$window\tx=$x\ty=$y\tw=$w\th=$h"
    }
    #puts stderr [current-tab-frame]
}

# state should be normal or disabled
proc tabset-state {state} {
    set all_tabs [.c.nb tabs]
    foreach tab $all_tabs {
        if {$tab eq [current-tab-frame]} {
            .c.nb tab $tab -state normal
        } else {
            .c.nb tab $tab -state $state
        }
    }
}





proc conn-status-update {status} {
    puts stderr "conn-status-update called: $status"
    set ::model::Conn_status $status
    img place status/$status [current-tab-frame].stat.imagestatus

    set state1 disabled
    set state2 normal
    set ip [dict-pop $::model::Current_sitem ip {}]

    switch $status {
        disconnected {
            # swap 2 variables
            lassign [list $state1 $state2] state2 state1 
            set msg [_ "Disconnected"] ;# _afd638922a7655ae
        }
        connecting {
            set msg [_ "Connecting to {0}" $ip] ;# _a9e00a1f366a7a19
        }
        connected {
            set msg [_ "Connected to {0}" $ip] ;# _540ebc2e02c2c88e
        }
    }

    if {$status ne "disconnected"} {
    }
    
    tabset-state $state1
    [current-tab-frame].bs.connect configure -state $state1
    [current-tab-frame].bs.disconnect configure -state $state2

    [current-tab-frame].stat.status configure -text $msg
}


# create usage meter in parent p
proc frame-usage-meter {p} {
    set bg1 $::model::layout_bg1
    set bg3 $::model::layout_bg3
    set um [frame $p.um -background $bg1]
    ttk::label $um.plan -text "Plan JADEITE valid until 2015 Sep 14" -background $bg1
    ttk::label $um.usedlabel -text "This month used" -background $bg1
    frame $um.usedbar -background $bg3 -width 300 -height 8
    frame $um.usedbar.fill -background red -width 120 -height 8
    place $um.usedbar.fill -x 0 -y 0
    grid columnconfigure $um.usedbar 0 -weight 1
    ttk::label $um.usedsummary -text "12.4 GB / 50 GB" -background $bg1
    ttk::label $um.elapsedlabel -text "This month elapsed" -background $bg1
    frame $um.elapsedbar -background $bg3 -width 300 -height 8
    frame $um.elapsedbar.fill -background blue -width 180 -height 8
    place $um.elapsedbar.fill -x 0 -y 0
    ttk::label $um.elapsedsummary -text "3 days 14 hours / 31 days" -background $bg1
    grid $um.plan -column 0 -row 0 -columnspan 3 -padx 5 -pady 5 -sticky w
    grid $um.usedlabel $p.um.usedbar $p.um.usedsummary -row 1 -padx 5 -pady 5 -sticky w
    grid $um.elapsedlabel $p.um.elapsedbar $p.um.elapsedsummary -row 2 -padx 5 -pady 5 -sticky w
    grid $um -padx 10 -sticky news
    return $um
}

# create ip info panel in parent p
proc frame-ipinfo {p} {
    set bg2 $::model::layout_bg2
    set inf [frame $p.inf -background $bg2]
    ttk::label $inf.externalip -text "External IP: 123.123.123.123" -background $bg2
    ttk::label $inf.geocheck -text "Geo check" -background $bg2
    grid $inf.externalip -column 0 -row 2 -padx 10 -pady 5 -sticky w
    grid $inf.geocheck -column 1 -row 2 -padx 10 -pady 5 -sticky w
    grid $inf -padx 10 -sticky news
    return $inf
}

proc frame-status {p} {
    set bg2 $::model::layout_bg2
    set stat [frame $p.stat -background $bg2]
    label $stat.imagestatus -background $bg2
    # TODO move to conn-status-update
    #place-image status/disconnected.png $stat.imagestatus

    ttk::label $stat.status -text "Connected to ..." -background $bg2
    ttk::label $stat.flag -image [img load flag/64/PL] -background $bg2
    grid $stat.imagestatus -row 5 -column 0 -padx 10 -pady 5
    grid $stat.status -row 5 -column 1 -padx 10 -pady 5 -sticky w
    grid $stat.flag -row 5 -column 2 -padx 10 -pady 5 -sticky e
    grid columnconfigure $stat $stat.status -weight 1
    grid $stat -padx 10 -sticky news
    return $stat
}

proc frame-buttons {p pname} {
    set bs [frame $p.bs]
    ttk::button $bs.connect -text [_ "Connect"] -command ClickConnect ;# _2eaf8d491417924c
    ttk::button $bs.disconnect -text [_ "Disconnect"] -command ClickDisconnect ;# _87fff3af45753920
    ttk::button $bs.slist -text [_ "Servers {0}" $pname] -command ServerListClicked ;# _bf9c42ec59d68714
    grid $bs.connect $bs.disconnect $bs.slist -padx 10
    grid columnconfigure $bs $bs.slist -weight 1
    grid $bs -sticky news
    focus $bs.slist
    return $bs
}


proc tabset-providers {} {
    set parent .c
    set nb [ttk::notebook $parent.nb]
    ttk::notebook::enableTraversal $nb
    foreach pname $::model::provider_list {
        set tab [frame-provider $nb $pname]
        set tabname [dict get $::model::Providers $pname tabname]
        $nb add $tab -text $tabname
    }
    grid $nb -sticky news -padx 10 -pady 10
    return $nb
}

# For example: .c.nb.securitykiss
proc current-tab-frame {} {
    return [.c.nb select]
}

# For example: securitykiss
proc current-provider {} {
    return [lindex [split [current-tab-frame] .] end]
}

# return provider frame window
proc frame-provider {p pname} {
    set f [ttk::frame $p.$pname]
    hsep $f 15
    frame-usage-meter $f
    hsep $f 5
    frame-ipinfo $f
    #hsep $f 5
    frame-status $f
    hsep $f 15
    frame-buttons $f $pname
    hsep $f 5
    return $f
}



proc InvokeFocusedWithEnter {} {
    set focused [focus]
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


proc setDialogSize {window} {
    #TODO check if layout in Config and if values make sense
    #TODO when layout in Config don't do updates from package manager
    # if layout not in Config we must determine size from package manager
    # this update will ensure that winfo will return the correct sizes
    update
    # get the current width and height as set by grid package manager
    set w [winfo width $window]
    set h [expr {[winfo height $window] + 10}]
    # set it as the minimum size
    wm minsize $window $w $h
    if {$::model::layout_w == 0} {
        set ::model::layout_w $w
    }
    if {$::model::layout_h == 0} {
        set ::model::layout_h $h
    }
    set cw $::model::layout_w
    set ch $::model::layout_h
    set cx $::model::layout_x
    set cy $::model::layout_y

    wm geometry $window ${cw}x${ch}+${cx}+${cy}
}



#TODO sorting by country
proc ServerListClicked {} {
    set slist [model slist [current-provider]]
    set ssitem [model selected-sitem [current-provider]]
    set ssid [dict get $ssitem id]


    set w .slist_dialog
    catch { destroy $w }
    toplevel $w
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
        img load flag/24/$ccode
        $wt insert {} end -id $id -image flag_24_$ccode -values [list $country $city $ip]
    }
    $wt selection set $ssid
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
    wm title $w "Select server"


    focus $wt
    $wt focus $ssid
    set modal [ShowModal $w]
    if {$modal eq "ok"} {
        model selected-sitem [current-provider] [$wt selection]
    }
    model print
    destroy $w

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

proc curl-hosts {tryout tryerr args} {
    fromargs {-urlpath -indiv_timeout -hosts -hindex -proto -port -expected_hostname} \
             {/ 5000 {} 0 https}
    if {$proto ne "http" && $proto ne "https"} {
        error "Wrong proto: $proto"
    }
    if {$port eq ""} {
        if {$proto eq "http"} {
            set port 80
        } elseif {$proto eq "https"} {
            set port 443
        }
    }
    set opts {}
    if {$indiv_timeout ne ""} {
        lappend opts -timeout $indiv_timeout
    }
    if {$expected_hostname ne ""} {
        lappend opts -expected-hostname $expected_hostname
    }

    set hlen [llength $hosts]
    foreach i [seq $hlen] {
        set host_index [expr {($hindex+$i) % $hlen}]
        # host_index is the index to start from when iterating hosts
        set host [lindex $hosts $host_index]
        set url $proto://$host:${port}${urlpath}
        # Need to catch error in case the handler triggers after the channel was closed (if using select with timer channel for timeouts)
        # or https curl throws error immediately
        try {
            https curl $url {*}$opts -command [-> chhttp]
            set tok [<- $chhttp]
            set ncode [http::ncode $tok]
            set status [http::status $tok]
            if {$status eq "ok" && $ncode == 200} {
                set data [http::data $tok]
                set ::model::vigo_lastok $host_index
                log "curl-hosts $url success. data: $data"
                $tryout <- $data
                return
            } else {
                log "curl-hosts $url failed with status: [http::status $tok], error: [http::error $tok]"
            }
        } on error {e1 e2} { 
            log $e1 $e2
        } finally {
            catch {
                http::cleanup $tok
                $chhttp close
            }
        }
    }
    $tryerr <- "All hosts failed error"
}


# get next host to try based on the attempt number relative the last succeeded host
proc get-next-host {hosts host_lastok attempt} {
    set i [lsearch -exact $hosts $host_lastok]
    if {$i == -1} {
        set i 0
    }
    set next [expr {($i + $attempt) % [llength $hosts]}]
    return [lindex $hosts $next]
}

# get next vigo to try based on the attempt number relative the last succeeded vigo
proc get-next-vigo {vigo_lastok attempt} {
    #TODO if connected use vigo internal IP regardless of attempt
    #else use vigo list
    return [get-next-host $::model::Vigos $vigo_lastok $attempt]
}


proc skd-connect {port} {
    #TODO handle error
    if {[catch {set sock [socket 127.0.0.1 $port]} out err] == 1} {
        skd-close $err
    }
    set ::model::Skd_sock $sock
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable skd-read
}


proc skd-write {msg} {
    if {[catch {puts $::model::Skd_sock $msg} out err] == 1} {
        skd-close $err
    }
}

proc skd-close {err} {
    catch {close $::model::Skd_sock}
    fatal "Could not communicate with SKD. Please check if skd service is running and check logs in /var/log/skd.log" $err
}


#TODO detect disconnecting from SKD - sock monitoring?
proc skd-read {} {
    set sock $::model::Skd_sock
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
                    # TODO display in SKU that connected to SKD, take care of updating this status
                }
                {^Config loaded} {
                    skd-write start
                }
                {^OpenVPN with pid .* started} {
                    conn-status-update connecting
                }
                {^OpenVPN with pid .* stopped} {
                    conn-status-update disconnected
                }
                {^OpenVPN already running with pid .*} {
                    conn-status-update connected
                }
                {^OpenVPN status (.*)$} {
                    conn-status-update [lindex $details 1]
                }
            }
        }
        {^ovpn: (.*)$} {
            set ::status [lindex $tokens 1]
            switch -regexp -matchvar details [lindex $tokens 1] {
                {^Initialization Sequence Completed} {
                    conn-status-update connected
                }
            }
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


proc ClickConnect {} {
    set localconf $::conf
    set ::model::Current_sitem [model selected-sitem [current-provider]]
    set ip [dict get $::model::Current_sitem ip]
    # TODO set ovs according to ovs preferences
    set ovs [lindex [dict get $::model::Current_sitem ovses] 0]
    set proto [dict get $ovs proto]
    set port [dict get $ovs port]
    append localconf "--proto $proto --remote $ip $port"
    skd-write "config $localconf"
}

proc ClickDisconnect {} {
    skd-write stop
}

# TODO check and save latest version with signature


proc build-version {} {
    memoize
    return [slurp [file join [file dir [info script]] buildver.txt]]
}

proc build-date {} {
    memoize
    return [slurp [file join [file dir [info script]] builddate.txt]]
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
