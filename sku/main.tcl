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
    unix relinquish-root
    redirect-stdout

    # watch out - cmdline is buggy. For example you cannot define help option, it conflicts with the implicit one
    set options {
            {cli                "Run command line interface (CLI) instead of GUI"}
            {generate-keys      "Generate private key and certificate signing request"}
            {add-launcher       "Add desktop launcher for current user"}
            {remove-launcher    "Remove desktop launcher"}
            {id                 "Show client id from the certificate"}
            {version            "Print version"}
            {locale    en       "Run particular language version"}
        }
    set usage ": sku \[options]\noptions:"
    if {[catch {array set params [::cmdline::getoptions ::argv $options $usage]}] == 1} {
        log [cmdline::usage $options $usage]
        exit 1
    }
    log Params:
    parray params


    if {[catch {i18n load en [file join [file dir [info script]] messages.txt]} out err]} {
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

    set ::model::Running_binary_fingerprint [sha1sum [this-binary]]

    #TODO log to stderr?
    if {$params(generate-keys)} {
        main-generate-keys
        main-exit
    }
    if {$params(add-launcher)} {
        puts stderr [log Adding Desktop Launcher]
        unix add-launcher sku
        main-exit
    }
    if {$params(remove-launcher)} {
        puts stderr [log Removing Desktop Launcher]
        unix remove-launcher sku
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

    #skd-connect 7777
    #model print
    in-ui main
    skd-monitor
    plan-monitor
    conn-status-display
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
    puts stderr [log Generating RSA keys]
    set privkey [file join $::model::KEYSDIR client.key]
    if {[file exists $privkey]} {
        puts stderr [log RSA key $privkey already exists]
    } else {
        if {![generate-rsa $privkey]} {
            puts stderr [log Could not generate RSA keys]
            return 0
        }
    }
    set csr [file join $::model::KEYSDIR client.csr]
    if {[file exists $csr]} {
        puts stderr [log CSR $csr already exists]
    } else {
        set cn [generate-cn]
        if {![generate-csr $privkey $csr $cn]} {
            puts stderr [log Could not generate Certificate Signing Request]
            return 0
        }
    }

    set crt [file join $::model::KEYSDIR client.crt]

    if {[file exists $crt]} {
        puts stderr [log CRT $crt already exists]
    } else {
        # POST csr and save cert
        for {set i 0} {$i<[llength $::model::Vigos]} {incr i} {
            if {[catch {open $csr r} fd err] == 1} {
                log "Failed to open $csr for reading"
                log $err
            }
            set vigo [get-next-vigo "" $i]
            log Trying vigo $vigo
            #TODO expected-hostname should not be needed - ensure that vigo provides proper certificate with IP common name
            if {[catch {https curl https://$vigo:10443/sign-cert -timeout 8000 -method POST -type text/plain -querychannel $fd -expected-hostname www.securitykiss.com} crtdata err] == 1} {
                log $vigo FAILED
                log $err
                close $fd
            } else {
                log $vigo OK
                puts stderr [log Received the signed certificate]
                log crtdata: $crtdata
                spit $crt $crtdata
                close $fd
                return 1
            }
        }
    }
    puts stderr [log Could not receive the signed certificate]
    return 0
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
    # TODO sku may be started before all Tk deps are installed, so run in CLI first and check for Tk a few times with delay
    package require Tk 
    wm title . "SecurityKISS Tunnel"
    wm iconphoto . -default [img load 16/logo] [img load 24/logo] [img load 32/logo] [img load 64/logo]
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

    frame-toolbar .c

    tabset-providers

    frame-ipinfo .c
    #hsep .c 5
    frame-status .c
    hsep .c 15
    frame-buttons .c
    hsep .c 5

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

    # TODO use config.ovpn and other config files from welcome message or by a separate call
    set ::conf [::ovconf::parse /home/sk/seckiss/skt/config.ovpn]
    go check-for-updates ""
    go get-welcome

}

proc check-for-updates {uframe} {
    try {
        set platform [this-os]-[this-arch]
        channel {chout cherr} 1
        vigo-curl $chout $cherr /check-for-updates/$platform
        select {
            <- $chout {
                set data [<- $chout]
                if {[is-dot-ver $data]} { 
                    set ::model::Latest_version $data
                } else {
                    set ::model::Latest_version 0
                }
                puts stderr "Check for updates: $data"
            }
            <- $cherr {
                set ::model::Latest_version 0
                set err [<- $cherr]
                puts stderr "Check failed: $err"
            }
        }
        checkforupdates-refresh $uframe 0
        $chout close
        $cherr close
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}

# select current slist from welcome as a function of welcome message and current plan/time
# tstamp - current time given as argument to get multiple values in specific moment
proc current-slist {tstamp} {
    set welcome [dict-pop $::model::Providers [current-provider] welcome {}]
    set planname [dict-pop [current-plan $tstamp] name {}]
    return [dict-pop $welcome serverLists $planname {}]
}


# select current plan as a function of welcome message and current time
# tstamp - current time given as argument to get multiple values in specific moment
proc current-plan {tstamp} {
    set welcome [dict-pop $::model::Providers [current-provider] welcome {}]
    if {$welcome eq ""} {
        return ""
    }
    set plans [dict-pop $welcome activePlans {}]
    if {$plans eq ""} {
        return ""
    }
    set sorted_plans [lsort -command [list plan-comparator $tstamp] $plans]
    set current [lindex $sorted_plans 0]
    return $current
}


proc period-elapsed {plan tstamp} {
    return [expr {$tstamp - [period-start $plan $tstamp]}]
}

proc period-length {plan tstamp} {
    return [expr {[period-end $plan $tstamp] - [period-start $plan $tstamp]}]
}


proc period-end {plan tstamp} {
    set period [dict-pop $plan period day]
    set period_start [period-start $plan $tstamp]
    return [clock add $period_start 1 $period]
}

proc period-start {plan tstamp} {
    set period [dict-pop $plan period day]
    if {$period eq "day"} {
        set periodsecs 86400
    } elseif {$period eq "month"} {
        # average number of seconds in a month
        set periodsecs 2629800
    } else {
        # just in case set default to day
        set periodsecs 86400
    }
    set plan_start [plan-start $plan]
    set secs [expr {$tstamp - $plan_start}]
    # estimated number of periods
    set est [expr {$secs / $periodsecs - 2}]
    for {set i $est} {$i<$est+5} {incr i} {
        set start [clock add $plan_start $i $period]
        set end [clock add $plan_start [expr {$i+1}] $period]
        if {$start <= $tstamp && $tstamp < $end} {
            return $start
        }
    }
    error "Could not determine period-start for plan $plan and tstamp $tstamp"
}


proc plan-start {plan} {
    return [dict-pop $plan start [model now]]
}


proc plan-end {plan} {
    set period [dict-pop $plan period day]
    set plan_start [plan-start $plan]
    set nop [dict-pop $plan nop 0]
    return [clock add $plan_start $nop $period]
}



# tstamp - current time given as argument to get multiple values in specific moment
proc plan-is-active {tstamp plan} {
    set start [plan-start $plan]
    return [expr {$start < $tstamp && $tstamp < [plan-end $plan]}]
}

# sort activePlans:
# - active first
# - month first over day period
# - traffic limit descending
# - empty last
# tstamp - current time given as argument to get multiple values in specific moment
proc plan-comparator {tstamp a b} {
    if {$a eq ""} { return -1 }
    if {$b eq ""} { return 1 }
    set active_diff [expr {[plan-is-active $tstamp $b] - [plan-is-active $tstamp $a]}]
    if {$active_diff != 0} {
        return $active_diff
    }
    # use direct string compare - lexicographically day sorts before month
    set period_diff [string compare [dict-pop $b period day] [dict-pop $a period day]]
    if {$period_diff != 0} {
        return $period_diff
    }
    return [expr {[dict-pop $b limit 0] - [dict-pop $a limit 0]}] 
}

 

# sample welcome message:
# ip 127.0.0.1
# now 1436792064
# latestSkt 1.4.4
# serverLists
# {
#     GREEN {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}}}
#     JADEITE {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}} {id 2 ccode FR country France city Paris ip 176.31.32.106 ovses {{proto udp port 123} {proto tcp port 443}}} {id 3 ccode UK country {United Kingdom} city London ip 78.129.174.84 ovses {{proto udp port 5353} {proto tcp port 443}}}}
# 
# }
# activePlans {{name JADEITE period month limit 50000000000 start 1431090862 used 12345678901 nop 3} {name GREEN period day limit 300000000 start 1431040000 used 15000000 nop 99999}}
proc get-welcome {} {
    try {
        set platform [this-os]-[this-arch]
        channel {chout cherr} 1
        vigo-curl $chout $cherr /welcome/[build-version]/$platform/$::model::Cn
        select {
            <- $chout {
                set data [<- $chout]
                log Welcome message received:\n$data
                puts stderr "welcome: $data"
                set welcome [json::json2dict $data]
                # save entire welcome message
                dict set ::model::Providers securitykiss welcome $welcome
                model now [dict-pop $welcome now 0]
                # TODO not really for currently selected provider
                model slist [current-provider] [current-slist [model now]]
                set ::model::Gui_externalip [dict-pop $welcome ip ???]
                usage-meter-update [model now]
            }
            <- $cherr {
                set err [<- $cherr]
                tk_messageBox -message "Could not receive Welcome message" -type ok
                log get-welcome failed with error: $err
            }
        }
        $chout close
        $cherr close
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}


proc vigo-curl {chout cherr urlpath} {
    go vigo-hosts $chout $cherr -hosts $::model::Vigos -hindex $::model::vigo_lastok -urlpath $urlpath -proto https -port 10443 -expected_hostname www.securitykiss.com
}


proc vigo-wget {chout cherr urlpath filepath} {
    go vigo-hosts $chout $cherr -hosts $::model::Vigos -hindex $::model::vigo_lastok -urlpath $urlpath -proto https -port 10443 -expected_hostname www.securitykiss.com -filepath $filepath
# -indiv_timeout 60000
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


# Extract new OpenVPN connstatus from SKD stat report
# update the model and refresh display if status changed
proc conn-status-update {stat} {
    set newstatus [conn-status-reported $stat]
    if {$newstatus ne $::model::Connstatus} {
        set ::model::Connstatus $newstatus
        conn-status-display
    }
}


# Extract new OpenVPN connstatus from SKD stat report
proc conn-status-reported {stat} {
    if {$stat eq ""} {
        set connstatus unknown
    } elseif {[dict get $stat ovpn_pid] == 0} {
        set connstatus disconnected
    } elseif {[dict get $stat mgmt_connstatus] eq "CONNECTED"} {
        set connstatus connected
    } else {
        set connstatus connecting
    }
    return $connstatus
}


proc conn-status-display {} {
    set status $::model::Connstatus
    img place 32/status/$status .c.stat.imagestatus

    set ip [dict-pop $::model::Current_sitem ip {}]
    set city [dict-pop $::model::Current_sitem city ?]
    set ccode [dict-pop $::model::Current_sitem ccode ?]
    set flag EMPTY

    switch $status {
        unknown {
            lassign {normal disabled disabled} state1 state2 state3
            set msg [_ "Unknown"] ;# _a297104e26a168e6
            set ::model::Gui_externalip ""
        }
        disconnected {
            lassign {normal normal disabled} state1 state2 state3
            set msg [_ "Disconnected"] ;# _afd638922a7655ae
            set ::model::Gui_externalip ""
            after 1000 [list go get-welcome]
        }
        connecting {
            lassign {disabled disabled normal} state1 state2 state3
            set msg [_ "Connecting to {0}, {1}" $city $ccode] ;# _a9e00a1f366a7a19
        }
        connected {
            lassign {disabled disabled normal} state1 state2 state3
            set msg [_ "Connected to {0}, {1}" $city $ccode] ;# _540ebc2e02c2c88e
            # TODO make it more robust - for now we assume external ip after get connected. Check externally.
            set ::model::Gui_externalip $ip
            if {$ccode ni {"" ?}} {
                set flag $ccode
            }
        }
    }
    
    img place 64/flag/$flag .c.stat.flag

    tabset-state $state1
    .c.bs.connect configure -state $state2
    .c.bs.disconnect configure -state $state3

    .c.stat.status configure -text $msg
}

proc usage-meter-update-blank {} {
    set um .c.nb.[current-provider].um
    set ::model::Gui_planline [_ "Plan ?"]
    set ::model::Gui_usedlabel [_ "Used"]
    set ::model::Gui_elapsedlabel [_ "Elapsed"]
    set ::model::Gui_usedsummary ""
    set ::model::Gui_elapsedsummary ""
    $um.usedbar.fill configure -width 0
    $um.elapsedbar.fill configure -width 0
}


proc usage-meter-update {tstamp} {
    try {
        set um .c.nb.[current-provider].um
        set plan [current-plan $tstamp]
        if {$plan eq ""} {
            usage-meter-update-blank
            return
        }
        set planname [dict-pop $plan name ?]
        set plan_start [plan-start $plan]
        set plan_end [plan-end $plan]
        set until [format-date $plan_end]
        set period [dict-pop $plan period day]
        if {$period eq "month"} {
            set ::model::Gui_usedlabel [_ "This month used"]
            set ::model::Gui_elapsedlabel [_ "This month elapsed"]
            set ::model::Gui_planline [_ "Plan {0} valid until {1}" $planname $until]
        } elseif {$period eq "day"} {
            set ::model::Gui_usedlabel [_ "This day used"]
            set ::model::Gui_elapsedlabel [_ "This day elapsed"]
            set ::model::Gui_planline [_ "Plan {0}" $planname]
        } else {
            usage-meter-update-blank
            return
        }
        
        set used [dict-pop $plan used 0]
        set limit [dict-pop $plan limit 0]
        if {$limit <= 0} {
            usage-meter-update-blank
            return
        }
        if {$used > $limit} {
            set used $limit
        }
        if {$used < 0} {
            usage-meter-update-blank
            return
        }
        set ::model::Gui_usedsummary "[format-mega $used] / [format-mega $limit 1]"
        set period_start [period-start $plan $tstamp]
        set period_end [period-end $plan $tstamp]
        #puts stderr "plan_start: [clock format $plan_start]"
        #puts stderr "period_start: [clock format $period_start]"
        #puts stderr "period_end: [clock format $period_end]"
        set period_elapsed [period-elapsed $plan $tstamp]
        set period_length [period-length $plan $tstamp]
        if {$period_elapsed <= 0} {
            usage-meter-update-blank
            return
        }
        if {$period_length <= 0} {
            usage-meter-update-blank
            return
        }
        if {$period_elapsed > $period_length} {
            set period_elapsed $period_length
        }
        set ::model::Gui_elapsedsummary "[format-interval $period_elapsed] / [format-interval $period_length 1]"
    
        ##################################
        # update bars
    
        set barw $::model::layout_barw
        set wu [expr {$barw * $used / $limit}]
        if {$wu < 0} {
        }
        $um.usedbar.fill configure -width $wu
        set we [expr {$barw * $period_elapsed / $period_length}]
        $um.elapsedbar.fill configure -width $we
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}



# convert big number to the suffixed (K/M/G/T) representation 
# with max 3 significant digits plus optional dot
# trim - trim the decimal part if zero
proc format-mega {n {trim 0}} {
    # number length
    set l [string length $n]
    # 3 digits to display
    set d [string range $n 0 2]
    if {$l > 12} {
        set suffix T
    } elseif {$l > 9} {
        set suffix G
    } elseif {$l > 6} {
        set suffix M
    } elseif {$l > 3} {
        set suffix K
    } else {
        set suffix ""
    }
    # position of the dot
    set p [expr {$l % 3}]
    if {$suffix ne "" && $p > 0} {
        set d [string-insert $d $p .]
        if {$trim} {
            while {[string index $d end] eq "0"} {
                set d [string range $d 0 end-1]
            }
            if {[string index $d end] eq "."} {
                set d [string range $d 0 end-1]
            }
        }
    }
    return $d$suffix
}


# trim - trim the minor unit
proc format-interval {sec {trim 0}} {
    set min [expr {$sec/60}]
    # if more than 24 hour
    if {$min > 1440} {
        set days [expr {$min/1440}]
        set hours [expr {($min-$days*1440)/60}]
        if {$trim} {
            return "${days}d"
        } else {
            return "${days}d ${hours}h"
        }
    } else {
        set hours [expr {$min/60}]
        set minutes [expr {$min-($hours*60)}]
        if {$trim} {
            return "${hours}h"
        } else {
            return "${hours}h ${minutes}m"
        }
    }
}

proc format-date {sec} {
    return [clock format $sec -format "%Y-%m-%d"]
}




# create usage meter in parent p
proc frame-usage-meter {p} {
    set bg1 $::model::layout_bg1
    set bg3 $::model::layout_bg3
    set fgused $::model::layout_fgused
    set fgelapsed $::model::layout_fgelapsed
    set um [frame $p.um -background $bg1]
    ttk::label $um.plan -textvariable ::model::Gui_planline -background $bg1
    ttk::label $um.usedlabel -textvariable ::model::Gui_usedlabel -background $bg1 -width 15
    set barw $::model::layout_barw
    set barh $::model::layout_barh
    frame $um.usedbar -background $bg3 -width $barw -height $barh
    frame $um.usedbar.fill -background $fgused -width 0 -height $barh
    place $um.usedbar.fill -x 0 -y 0
    grid columnconfigure $um.usedbar 0 -weight 1
    #ttk::label $um.usedsummary -text "12.4 GB / 50 GB" -background $bg1
    ttk::label $um.usedsummary -textvariable ::model::Gui_usedsummary -background $bg1 -width 15
    ttk::label $um.elapsedlabel -textvariable ::model::Gui_elapsedlabel -background $bg1 -width 15
    frame $um.elapsedbar -background $bg3 -width $barw -height $barh
    frame $um.elapsedbar.fill -background $fgelapsed -width 0 -height $barh
    place $um.elapsedbar.fill -x 0 -y 0
    #ttk::label $um.elapsedsummary -text "3 days 14 hours / 31 days" -background $bg1
    ttk::label $um.elapsedsummary -textvariable ::model::Gui_elapsedsummary -background $bg1 -width 15
    grid $um.plan -column 0 -row 0 -columnspan 3 -padx 5 -pady 5 -sticky w
    grid $um.usedlabel $p.um.usedbar $p.um.usedsummary -row 1 -padx 5 -pady 5 -sticky w
    grid $um.elapsedlabel $p.um.elapsedbar $p.um.elapsedsummary -row 2 -padx 5 -pady 5 -sticky w
    grid $um -padx 10 -sticky news
    return $um
}


proc frame-toolbar {p} {
    set tb [frame $p.tb -borderwidth 0 -relief raised]
    #ttk::button $tb.feedback
    #img place 16/feedback  $tb.feedback 
    #grid $tb.feedback -column 0 -row 0 -sticky w
    label $tb.appealimg
    img place 16/bang $tb.appealimg
    label $tb.appeal1 -text "Help improve this program. Provide your"
    hyperlink $tb.appeal2 -command [list launchBrowser "https://securitykiss.com/locate/"] -text "feedback."
    label $tb.appeal3 -text "We listen."

    button $tb.options -relief flat -command OptionsClicked
    img place 24/options  $tb.options
    grid $tb.appealimg -column 0 -row 0 -sticky w
    grid $tb.appeal1 -column 1 -row 0 -sticky w
    grid $tb.appeal2 -column 2 -row 0 -sticky w
    grid $tb.appeal3 -column 3 -row 0 -sticky w
    grid $tb.options -column 4 -row 0 -sticky e
    grid $tb -padx 5 -sticky news
    grid columnconfigure $tb $tb.options -weight 1
    return $tb
}



# create ip info panel in parent p
proc frame-ipinfo {p} {
    set bg2 $::model::layout_bg2
    set inf [frame $p.inf -background $bg2]
    ttk::label $inf.externaliplabel -text [_ "External IP:"] -background $bg2
    ttk::label $inf.externalip -textvariable ::model::Gui_externalip -background $bg2
    hyperlink $inf.geocheck -image [img load 16/external] -background $bg2 -command [list launchBrowser "https://securitykiss.com/locate/"]
    grid $inf.externaliplabel -column 0 -row 2 -padx 10 -pady 5 -sticky w
    grid $inf.externalip -column 1 -row 2 -padx 0 -pady 5 -sticky e
    grid $inf.geocheck -column 2 -row 2 -padx 5 -pady 5 -sticky w
    grid columnconfigure $inf $inf.externalip -minsize 120
    grid $inf -padx 10 -sticky news
    return $inf
}

proc frame-status {p} {
    set bg2 $::model::layout_bg2
    set stat [frame $p.stat -background $bg2]
    label $stat.imagestatus -background $bg2

    ttk::label $stat.status -text "" -background $bg2
    ttk::label $stat.flag -background $bg2
    img place 64/flag/EMPTY $stat.flag
    grid $stat.imagestatus -row 5 -column 0 -padx 10 -pady 5
    grid $stat.status -row 5 -column 1 -padx 10 -pady 5 -sticky w
    grid $stat.flag -row 5 -column 2 -padx 10 -pady 5 -sticky e
    grid columnconfigure $stat $stat.status -weight 1
    grid $stat -padx 10 -sticky news
    return $stat
}

proc frame-buttons {p} {
    set bs [frame $p.bs]
    button $bs.connect -font [dynafont -size 12] -compound left -image [img load 24/connect] -text [_ "Connect"] -command ClickConnect ;# _2eaf8d491417924c
    button $bs.disconnect -font [dynafont -size 12] -compound left -image [img load 24/disconnect] -text [_ "Disconnect"] -command ClickDisconnect ;# _87fff3af45753920
    button $bs.slist -font [dynafont -size 12] -compound left -image [img load 24/servers] -text [_ "Servers"] -command ServerListClicked ;# _bf9c42ec59d68714
    grid $bs.connect -row 0 -column 0 -padx 10 -sticky w
    grid $bs.disconnect -row 0 -column 1 -padx 10 -sticky w
    grid $bs.slist -row 0 -column 2 -padx 10 -sticky e
    grid columnconfigure $bs $bs.slist -weight 1
    grid $bs -sticky news
    focus $bs.slist
    return $bs
}

proc dynafont {args} {
    memoize
    set name font[join $args]
    if {$name ni [font names]} {
        font create $name {*}[font actual TkDefaultFont]
        font configure $name {*}$args
    }
    return $name
}


proc tabset-providers {} {
    set parent .c
    set nb [ttk::notebook $parent.nb]
    ttk::notebook::enableTraversal $nb
    bind $nb <<NotebookTabChanged>> {usage-meter-update [model now]}
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

proc CheckForUpdatesClicked {uframe} {
    try {
        set about .options_dialog.nb.about
        $about.checkforupdates configure -state disabled
        checkforupdates-status $uframe 16/connecting "Checking for updates"
        go check-for-updates $uframe
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}

proc checkforupdates-status {uframe img msg} {
    try {
        $uframe.status configure -text "  $msg"
        img place $img $uframe.status
    } on error {e1 e2} {
        log "$e1 $e2"
    }
} 


# Three possible outcomes: 
# -The program is up to date
# -New version XXX available
# -No updates found (connection problem) 
# uframe - it is passed to update the correct widget
# quiet - display message only if we already know that the program out of date
proc checkforupdates-refresh {uframe quiet} {
    try {
        if {![winfo exists $uframe]} {
            return
        }
        set latest $::model::Latest_version
        if {$quiet} {
            if {$latest ne "0" && [is-dot-ver $latest]} {
                if {[int-ver $latest] > [int-ver [build-version]]} {
                    checkforupdates-status $uframe 16/attention "New version $latest is available"
                    grid $uframe.button
                    return
                }
            }
            checkforupdates-status $uframe 16/empty ""
            return
        } else {
            if {$latest ne "0" && [is-dot-ver $latest]} {
                if {[int-ver $latest] > [int-ver [build-version]]} {
                    checkforupdates-status $uframe 16/attention "New version $latest is available"
                    grid $uframe.button
                } else {
                    checkforupdates-status $uframe 16/tick "The program is up to date"
                }
            } else {
                checkforupdates-status $uframe 16/question "No updates found"
            }
        }
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}


proc UpdateNowClicked {uframe} {
    try {
        set about .options_dialog.nb.about
        $uframe.button configure -state disabled

        set version $::model::Latest_version
        if {[int-ver $version] <= [int-ver [build-version]]} {
            return
        }

        set dir [file join $::model::UPGRADEDIR $version]
        file mkdir $dir
        set platform [this-os]-[this-arch]
        set files {sku.bin.sig skd.bin.sig sku.bin skd.bin}
        # csp channel for collecting info about downloaded files
        channel collector
        if {![files-exist $files]} {
            checkforupdates-status $uframe 16/downloading "Downloading..."
            foreach f $files {
                set filepath [file join $dir $f]
                go download-latest-skt $collector /latest-skt/$version/$platform/$f $filepath
            }
            # given timeout is per item
            go wait-for-items $collector [llength $files] 60000 [list upgrade-downloaded $dir $uframe]
        } else {
            upgrade-downloaded $dir $uframe ok
        }
    } on error {e1 e2} {
        log "$e1 $e2"
    }
}

# SKD only to verify signature and replace binaries and restart itself
# SKU prepares upgrade dir, initializes upgrade and restarts itself
proc upgrade-downloaded {dir uframe status} {
    log upgrade-downloaded $status
    if {$status eq "ok"} { 
        checkforupdates-status $uframe 16/updating "Updating..."
        # give 5 seconds to restart itself, otherwise report update failed
        after 5000 [list checkforupdates-status $uframe 16/warning "Update failed"]
        puts stderr "PREPARE UPGRADE from $dir"
        skd-write "upgrade $dir"
        puts stderr "UPGRADING from $dir"
    } else {
        checkforupdates-status $uframe 16/error "Problem with the download"
    }
           
}

# csp coroutine to collect messages from collector channel
# if $n items received within individual $timeouts
# then call "$command ok". Otherwise "$command timeout"
proc wait-for-items {collector n timeout command} {
    try {
        for {set i 0} {$i < $n} {incr i} {
            timer t $timeout
            select {
                <- $collector {
                    set item [<- $collector]
                    log "wait-for-items collected item=$item for n=$n timeout=$timeout command=$command"
                }
                <- $t {
                    log "wait-for-items timed out for n=$n timeout=$timeout command=$command"
                    <- $t
                    {*}$command timeout
                    return
                }
            }
        }
        log "wait-for-items completed successfully for n=$n timeout=$timeout command=$command"
        {*}$command ok
        return
    } on error {e1 e2} {
        log "$e1 $e2"
    } finally {
        catch {
            $collector close
        }
    }
}



proc download-latest-skt {collector url filepath} {
    try {
        channel {chout cherr} 1
        vigo-wget $chout $cherr $url $filepath
        log "download-latest-skt started $url $filepath"
        select {
            <- $chout {
                set data [<- $chout]
                $collector <- $filepath
                puts stderr "download-latest-skt $url $filepath OK"
            }
            <- $cherr {
                set err [<- $cherr]
                puts stderr "download-latest-skt $url $filepath ERROR: $err"
            }
        }
    } on error {e1 e2} {
        log "$e1 $e2"
    } finally {
        catch {
            $chout close
            $cherr close
        }
    }
}

proc OptionsClicked {} {
    set w .options_dialog
    catch { destroy $w }
    toplevel $w ;#-width 400 -height 400


    set nb [ttk::notebook $w.nb]
    frame $nb.about
    label $nb.about.buildver1 -text "Program version:"
    label $nb.about.buildver2 -text [build-version]
    label $nb.about.builddate1 -text "Build date:"
    label $nb.about.builddate2 -text [build-date]

    # this widget needs to have unique id which is passed through button events to status update label
    set update_id [rand-big]
    set uframe $nb.about.updateframe$update_id

    button $nb.about.checkforupdates -text "Check for updates" -command [list CheckForUpdatesClicked $uframe]

    frame $uframe
    label $uframe.status -compound left
    button $uframe.button -text "Update now" -command [list UpdateNowClicked $uframe]



    grid $nb.about.buildver1 -row 2 -column 0 -sticky w -padx 10 -pady 5
    grid $nb.about.buildver2 -row 2 -column 1 -sticky w -padx 10 -pady 5
    grid $nb.about.builddate1 -row 4 -column 0 -sticky w -padx 10 -pady 5
    grid $nb.about.builddate2 -row 4 -column 1 -sticky w -padx 10 -pady 5
    grid $nb.about.checkforupdates -column 1 -sticky e -padx 10 -pady 5
    grid $uframe -columnspan 2 -sticky news -padx 10 -pady 5
    grid $uframe.status -row 0 -column 0 -sticky w
    grid $uframe.button -row 0 -column 1 -sticky e -padx {40 0}
    grid columnconfigure $nb.about 0 -weight 1 -minsize 200
    grid columnconfigure $uframe 0 -weight 1
    grid rowconfigure $uframe 0 -weight 1 -minsize 40
    grid remove $uframe.button
    frame $nb.settings
    ttk::notebook::enableTraversal $nb
    $nb add $nb.about -text About -padding 20
    $nb add $nb.settings -text Settings
    grid $nb -sticky news -padx 10 -pady 10 

    set wb $w.buttons
    frame $wb
    button $wb.cancel -text Cancel -width 10 -command [list set ::Modal.Result cancel]
    button $wb.ok -text OK -width 10 -command [list set ::Modal.Result ok]
    grid $wb -sticky news
    grid $wb.cancel -row 5 -column 0 -padx {30 0} -pady 5 -sticky w
    grid $wb.ok -row 5 -column 1 -padx {0 30} -pady 5 -sticky e
    grid columnconfigure $wb 0 -weight 1
    grid rowconfigure $wb 0 -weight 1
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 0 -weight 1

    bind $w <Escape> [list set ::Modal.Result cancel]
    bind $w <Control-w> [list set ::Modal.Result cancel]
    bind $w <Control-q> [list set ::Modal.Result cancel]
    wm title $w "Options"
    
    # update status based on previous values of Latest_version - in quiet mode - display only if program out of date
    checkforupdates-refresh $uframe 1

    set modal [ShowModal $w]
    if {$modal eq "ok"} {
        puts stderr "Options ok"
    }
    destroy $w
}


#TODO sorting by country and favorites
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
        $wt insert {} end -id $id -image [img load 24/flag/$ccode] -values [list $country $city $ip]
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
    #model print
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
    #wm attributes $win -topmost 1
    #wm attributes $win -type dialog
    raise $win
    focus $win
    grab $win
    tkwait variable ::Modal.Result
    grab release $win
    if {$options(-destroy)} {destroy $win}
    return ${::Modal.Result}
}





# tablelist vs TkTable vs treectrl vs treeview vs BWidget::Tree

proc vigo-hosts {tryout tryerr args} {
    try {
        fromargs {-urlpath -indiv_timeout -hosts -hindex -proto -port -expected_hostname -filepath} \
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
                if {$filepath ne ""} {
                    https wget $url $filepath {*}$opts -command [-> chhttp]
                } else {
                    https curl $url {*}$opts -command [-> chhttp]
                }
                set tok [<- $chhttp]
                upvar #0 $tok state
                set ncode [http::ncode $tok]
                set status [http::status $tok]
                if {$status eq "ok" && $ncode == 200} {
                    set data [http::data $tok]
                    set ::model::vigo_lastok $host_index
                    log "vigo-hosts $url success. data: $data"
                    $tryout <- $data
                    return
                } else {
                    log "vigo-hosts $url failed with status: [http::status $tok], error: [http::error $tok]"
                    if {$filepath ne ""} {
                        file delete $filepath
                    }
                }
            } on error {e1 e2} { 
                log "$e1 $e2"
            } finally {
                catch {
                    http::cleanup $tok
                    $chhttp close
                    set fd $state(-channel)
                    close $fd
                }
            }
        }
        $tryerr <- "All hosts failed error"
    } on error {e1 e2} {
        log "$e1 $e2"
    } finally {
    }
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


proc plan-monitor {} {
    #puts stderr "########################1"
    #puts stderr [dict-pretty [dict-pop $::model::Providers [current-provider] welcome {}]]
    #puts stderr "########################2"
    set now [model now]
    #puts stderr "current-plan: [current-plan $now]"
    set slist [current-slist $now]
    #puts stderr "current-slist: $slist"
    model slist [current-provider] $slist
    usage-meter-update $now
    after 5000 plan-monitor
}

proc skd-monitor {} {
    set ms [clock milliseconds]
    if {$ms - $::model::Skd_beat > 3000} {
        log "Heartbeat not received within last 3 seconds. Restarting connection."
        set ::model::Connstatus unknown
        conn-status-display
        skd-close
        skd-connect 7777
    }
    after 1000 skd-monitor
}


proc skd-connect {port} {
    #TODO handle error
    if {[catch {set sock [socket 127.0.0.1 $port]} out err] == 1} {
        skd-close
        return
    }
    set ::model::Skd_sock $sock
    chan configure $sock -blocking 0 -buffering line
    chan event $sock readable skd-read
}


proc skd-write {msg} {
    if {[catch {puts $::model::Skd_sock $msg} out err] == 1} {
        log "skd-write problem writing $msg to $::model::Skd_sock"
        skd-close
    }
}

proc skd-close {} {
    catch {close $::model::Skd_sock}
}


proc skd-read {} {
    set sock $::model::Skd_sock
    if {[gets $sock line] < 0} {
        if {[eof $sock]} {
            log "skd-read_sock EOF. Connection terminated"
            skd-close
        }
        return
    }
    switch -regexp -matchvar tokens $line {
        {^ctrl: (.*)$} {
            switch -regexp -matchvar details [lindex $tokens 1] {
                {^Config loaded} {
                    skd-write start
                }
                {^version (\S+) (.*)$} {
                    set skd_version [lindex $details 1]
                    puts stderr "SKD VERSION: $skd_version"
                    puts stderr "SKU VERSION: [build-version]"
                    # sku to restart itself if skd already upgraded and not too often
                    if {[int-ver $skd_version] > [int-ver [build-version]]} {
                        set sha [sha1sum [this-binary]]
                        # just restart itself from the new binary - skd should have replaced it
                        # restart only if different binaries
                        if {$sha ne $::model::Running_binary_fingerprint} {
                            model save
                            execl [this-binary]
                        }
                    }
                }
            }
        }
        {^ovpn: (.*)$} {
            set ::status [lindex $tokens 1]
            switch -regexp -matchvar details [lindex $tokens 1] {
                {^Initialization Sequence Completed} {
                    #conn-status-display connected
                }
            }
        }
        {^stat: (.*)$} {
            set stat [dict create {*}[lindex $tokens 1]]
            set ::model::Skd_beat [clock milliseconds]
            set ovpn_config [dict-pop $stat ovpn_config {}]
            set ::model::Current_sitem [lindex [ovconf get $ovpn_config --meta] 0]
            conn-status-update $stat
            #TODO heartbeat timeout
            #connstatus update trigger

        }
    }
    log SKD>> $line
}


proc get-client-no {crtpath} {
    set crt [slurp $crtpath]
    regexp {CN=(client\d{8})} $crt _ cn
    return $cn
}


proc ClickConnect {} {
    # we artificially enforce Connstatus and update display 
    # in order to immediately disable button to prevent double-click
    # The Connstatus may be corrected by SKD reports
    set ::model::Connstatus connecting
    # temporary set Current_sitem - it will be overwritten by meta info
    # received back from SKD
    set ::model::Current_sitem [model selected-sitem [current-provider]]

    set localconf $::conf
    conn-status-display
    set ip [dict get $::model::Current_sitem ip]
    # TODO set ovs according to ovs preferences
    set ovs [lindex [dict get $::model::Current_sitem ovses] 0]
    set proto [dict get $ovs proto]
    set port [dict get $ovs port]
    append localconf " --proto $proto --remote $ip $port --meta $::model::Current_sitem "
    skd-write "config $localconf"
}

proc ClickDisconnect {} {
    # we artificially enforce Connstatus and update display 
    # in order to immediately disable button to prevent double-click
    # The Connstatus may be corrected by SKD reports
    set ::model::Connstatus disconnected
    conn-status-display

    skd-write stop
}


proc build-version {} {
    memoize
    return [string trim [slurp [file join [file dir [info script]] buildver.txt]]]
}

proc build-date {} {
    memoize
    return [string trim [slurp [file join [file dir [info script]] builddate.txt]]]
}



main

vwait ::until_exit
