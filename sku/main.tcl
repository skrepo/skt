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
package require anigif
package require json
package require inicfg
package require i18n
package require csp
namespace import csp::*

#puts stderr "existing select: [info body select]"

puts stderr "select: [namespace origin select]"

# skutil must be last required package in order to overwrite the log proc from Tclx
package require skutil


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


# When adding/removing provider, just create/delete folder in ~/.sku/provider
# and call this proc - it will take care of updating Config and Config_$provider
proc update-provider-list {} {
    # providers by config
    set cproviders [dict-pop $::Config providers {}]
    # providers by filesystem
    set fproviders [lmap d [glob -directory $::PROVIDERDIR -nocomplain -type d *] {file tail $d}]

    # sanitize directory names
    foreach p $fproviders {
        if {![regexp {^[\w\d_]+$} $p]} {
            fatal "Provider directory name should be alphanumeric string in $::PROVIDERDIR"
        }
    }

    # all this shuffling below in order to preserve providers order as per Config
    set providers [lunique [concat [lintersection $cproviders $fproviders] $fproviders]]
    
    # Provider list must be kept in main Config to preserve order
    dict set ::Config providers $providers

    foreach p $providers {
        set inifile [file join $::PROVIDERDIR $p config.ini]
        touch $inifile
        set ::Config_$p [inicfg load $inifile]
        dict-put ::Config_$p tabname $p
    }
}

proc update-default-properties {} {
    dict-put ::Config layout bg1 white
    dict-put ::Config layout bg2 grey95
    dict-put ::Config layout bg3 "light grey"
}

proc read-vigos {} {
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
}


proc read-config {} {
    if {[catch {
        touch $::INIFILE
        set ::Config [inicfg load $::INIFILE]
        # provider list from Config but compare against dir
        # update the provider list in Config
        update-provider-list
        update-default-properties
    } out err]} {
        puts stderr $out
        log $out
        log $err
        main-exit
    }

    puts stderr "READ CONFIG:"
    puts stderr "[inicfg dict-pretty $::Config]"

}

# Parse command line options and launch proper task
# It may set global variables
proc main {} {
    set user [unix relinquish-root]
    set ::INIFILE [file normalize ~/.sku/sku.ini]
    set ::LOGFILE [file normalize ~/.sku/sku.log]
    set ::PROVIDERDIR [file normalize ~/.sku/provider]
    set ::KEYSDIR [file join $::PROVIDERDIR securitykiss ovpnconf default]
    redirect-stdout

    state sku {
        # SKD connection socket 
        skd_sock ""
        # User Interface (gui or cli)
        ui ""
        # Start retries
        start_retries 0
        # Embedded bootstrap vigo list
        vigos ""
        #
        vigo_lastok 0
        # temporary
        slist ""
        # new client id
        cn ""
        # providers
        providers "securitykiss cyberghost"
    }




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


    if {[catch {i18n load pl [file join $starkit::topdir messages.txt]} out err]} {
        log $out
        log $err
    }

    if {$params(cli) || ![unix is-x-running]} {
        state sku {ui cli}
    } else {
        state sku {ui gui}
    }


    if {$params(version)} {
        main-version
        main-exit
    }

    if {$params(id)} {
        set cn [cn-from-cert [file join $::KEYSDIR client.crt]]
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


    read-config

    read-vigos

    puts stderr [build-date]
    puts stderr [build-version]

    if {$params(generate-keys)} {
        main-generate-keys
        main-exit
    }
    
    # Copy cadir because it  must be accessible from outside of starkit
    # Overwrites certs on every run
    set cadir [file normalize ~/.sku/certs]
    copy-merge [file join $::starkit::topdir certs] $cadir
    https init -cadir $cadir
 


    set cn [cn-from-cert [file join $::KEYSDIR client.crt]]
    state sku {cn $cn}
    if {$cn eq ""} {
        fatal "Could not retrieve client id. Try to reinstall the program." 
    }


    skd-connect 7777
    after idle main-start
}


proc main-exit {} {
    if {[info exists ::Config]} {
        if {[catch {log Config save report: \n[inicfg save $::INIFILE $::Config]} out err]} {
            log $out
            log $err
            puts stderr $out
        }
        foreach p [dict-pop $::Config providers {}] {
            set inifile [file join $::PROVIDERDIR $p config.ini]
            if {[catch {log Config_$p save report: \n[inicfg save $inifile [set ::Config_$p]]} out err]} {
                log $out
                log $err
                puts stderr $out
            }
        }
    }


    # ignore if problems occurred in deleting pidfile
    delete-pidfile ~/.sku/sku.pid
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
        tk_messageBox -title "SKU error" -type ok -icon error -message ERROR -detail "$msg\n\nPlease check $::LOGFILE for details"
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
    set privkey [file join $::KEYSDIR client.key]
    if {[file exists $privkey]} {
        log RSA key $privkey already exists
    } else {
        if {![generate-rsa $privkey]} {
            return 0
        }
    }
    set csr [file join $::KEYSDIR client.csr]
    if {[file exists $csr]} {
        log CSR $csr already exists
    } else {
        set cn [generate-cn]
        if {![generate-csr $privkey $csr $cn]} {
            return 0
        }
    }


    # POST csr and save cert
    puts stderr "vigos: [state sku vigos]"
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
            spit [file join $::KEYSDIR client.crt] $crtdata
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

    frame .c
    grid .c -sticky news
    grid columnconfigure . .c -weight 1
    grid rowconfigure . .c -weight 1


    set tabset [tabset-providers .c]




    # If the tag is the name of a class of widgets, such as Button, the binding applies to all widgets in that class;
    bind Button <Return> InvokeFocusedWithEnter
    bind TButton <Return> InvokeFocusedWithEnter
    #TODO coordinate with shutdown hook and provide warning/confirmation request
    bind . <Control-w> main-exit
    bind . <Control-q> main-exit
    wm title . "SecurityKISS Tunnel"

    grid columnconfigure .c 0 -weight 1
    # this will allocate spare space to the first row in container .c
    grid rowconfigure .c 0 -weight 1
    grid [ttk::sizegrip .grip] -sticky se
    setDialogSize .
    bind . <Configure> [list MovedResized %W %x %y %w %h]
    # sizegrip - bottom-right corner for resize
    

}
    set ::conf [::ovconf::parse config.ovpn]

    set cn [state sku cn]
    go check-for-updates
    go get-welcome $cn

}

proc check-for-updates {} {
    channel {chout cherr} 1
    vigo-curl $chout $cherr /check-for-updates
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
            set slist [dict get $d serverLists JADEITE]
            state sku {slist $slist}
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
    go curl-hosts $chout $cherr -hosts [state sku vigos] -hindex [state sku vigo_lastok] -urlpath $urlpath -proto https -port 10443 -expected_hostname www.securitykiss.com
}

proc MovedResized {window x y w h} {
    if {$window eq "."} {
        dict set ::Config layout x $x
        dict set ::Config layout y $y
        dict set ::Config layout width $w
        dict set ::Config layout height $h
        #puts stderr "$window\tx=$x\ty=$y\tw=$w\th=$h"
    }
}

# create usage meter in parent p
proc frame-usage-meter {p} {
    set bg1 [dict get $::Config layout bg1]
    set bg3 [dict get $::Config layout bg3]
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
    set bg2 [dict get $::Config layout bg2]
    set inf [frame $p.inf -background $bg2]
    ttk::label $inf.externalip -text "External IP: 123.123.123.123" -background $bg2
    ttk::label $inf.geocheck -text "Geo check" -background $bg2
    grid $inf.externalip -column 0 -row 2 -padx 10 -pady 5 -sticky w
    grid $inf.geocheck -column 1 -row 2 -padx 10 -pady 5 -sticky w
    grid $inf -padx 10 -sticky news
    return $inf
}

proc frame-status {p} {
    set bg2 [dict get $::Config layout bg2]
    set stat [frame $p.stat -background $bg2]
    label $stat.imagestatus -background $bg2
    place-image status/disconnected.png $p.stat.imagestatus
    after 2000 [list place-image status/connecting.gif $stat.imagestatus]
    after 4000 [list place-image status/connected.png $stat.imagestatus]
    ttk::label $stat.status -text "Connected to ..." -background $bg2
    load-image flag/64/PL.png
    ttk::label $stat.flag -image flag_64_PL -background $bg2
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


proc tabset-providers {p} {
    set providers [dict get $::Config providers]
    set nop [llength $providers]
    #set nop 1

    if {$nop > 1} {
        set nb [ttk::notebook $p.nb]
        foreach pname $providers {
            set tab [frame-provider $nb $pname]
            set tabname [dict get [set ::Config_$pname] tabname]
            $nb add $tab -text $tabname
        }
        grid $nb -sticky news -padx 10 -pady 10
    } elseif {$nop == 1} {
        set nb [ttk::frame $p.single]
        set pname [lindex $providers 0]
        set tab [frame-provider $nb $pname]
        grid $tab -sticky news
        grid $nb -sticky news
    } else {
        fatal "No providers found"
    }
    return $nb
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
    set cw [dict-put ::Config layout width $w]
    set ch [dict-put ::Config layout height $h]
    set cx [dict-put ::Config layout x 300]
    set cy [dict-put ::Config layout y 300]

    wm geometry $window ${cw}x${ch}+${cx}+${cy}
}


proc get-selected-sitem {provider} {
    
}


proc ServerListClicked {} {
    set slist [state sku slist]
    set ssel 2
    #TODO validate ssel is in slist, otherwise select first one
    #TODO sorting by country
    set newsel [slistDialog $slist $ssel]
    #TODO in the meantime slist could have changed (by welcome msg). Build entire configuration info here from the old slist
    puts stderr "New selected server: $newsel"
}


# Return new sitem id if selection made or empty string if canceled
# This is really selecting entire configuration than the server IP
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
    wm title $w "Select server"


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


proc http_handler {httpout httperr tok} {
    # Need to catch error in case the handler triggers after the channels were closed
    # Also: unfortunately http package which may call this proc is catching callback errors 
    # and they don't propagate to our background-error, so we need to catch them all here and log
    if {[catch {
        set ncode [http::ncode $tok]
        set status [http::status $tok]
        if {$status eq "ok" && $ncode == 200} {
            $httpout <- $tok
        } else {
            $httperr <- $tok
        }
    } out err]} {
        log $err
    }
}

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
        # hindex is the index to start from when iterating hosts
        set host [lindex $hosts $host_index]
        set url $proto://$host:${port}${urlpath}
        channel {httpout httperr} 1
        if {[catch {https curl $url {*}$opts -command [list http_handler $httpout $httperr]} out err] == 0} {
            puts "waiting for $host"
            select {
                <- $httpout {
                    set token [<- $httpout]
                    set data [http::data $token]
                    http::cleanup $token
                    
                    state sku {vigo_lastok $host_index}
                    puts "curl-hosts $url success. data: $data"
                    $tryout <- $data
                    $httpout close
                    $httperr close
                    return
                }
                <- $httperr {
                    set token [<- $httperr]
                    log "curl-hosts $url failed with status: [http::status $token], error: [http::error $token]"
                    http::cleanup $token
                }
            }
        } else { 
            log $err
        }
        $httpout close
        $httperr close
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
    return [get-next-host [state sku vigos] $vigo_lastok $attempt]
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

# TODO check and save latest version with signature


proc build-version {} {
    memoize
    return [slurp [file join $starkit::topdir buildver.txt]]
}

proc build-date {} {
    memoize
    return [slurp [file join $starkit::topdir builddate.txt]]
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
