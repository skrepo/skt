# Global model of the application
# Part of it will be durable in ini config file(s)
#
# Using the convention: lowercase variables are saveable in inicfg !!! Capitalized or starting with other character are transient !!!
#

package require inicfg
package require skutil

namespace eval ::model {
    
    namespace export *
    namespace ensemble create

    ######################################## 
    # Constants
    ########################################
    
    variable HOME [file normalize ~]
    variable CONFIGDIR [file join $HOME .sku]
    variable INIFILE [file join $CONFIGDIR sku.ini]
    variable LOGFILE [file join $CONFIGDIR sku.log]
    variable PROVIDERDIR [file join $CONFIGDIR provider]
    variable UPGRADEDIR [file join $CONFIGDIR upgrade]
    variable KEYSDIR [file join $PROVIDERDIR securitykiss ovpnconf default]


    ######################################## 
    # General globals
    ######################################## 

    # currently selected provider tab
    variable current_provider securitykiss

    # SKD connection socket 
    variable Skd_sock ""

    # last SKD stat heartbeat timestamp in millis
    variable Skd_beat 0

    # User Interface (gui or cli)
    variable Ui ""

    variable Running_binary_fingerprint ""

    # Time offset relative to the "now" received in welcome message
    variable now_offset 0

    # latest skd/sku version to upgrade from check-for-updates
    variable Latest_version 0

    # OpenVPN connection status 
    # Although the source of truth for connstatus is SKD stat reports
    # we keep local copy to know when to update display
    variable Connstatus unknown

    # Last line of log received from SKD/Openvpn server with ovpn prefix
    variable OvpnServerLog ""

    # other providers dict
    # entire welcome message is stored
    # while welcome contains multiple slists, we need to store current slist as well since it depends on current time (through active plan selection)
    variable Providers [dict create securitykiss {
        tabname SecurityKISS
        slist {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}} {id 2 ccode FR country France city Paris ip 176.31.32.106 ovses {{proto udp port 123} {proto tcp port 443}}} {id 3 ccode UK country {United Kingdom} city Newcastle ip 31.24.33.221 ovses {{proto udp port 5353} {proto tcp port 443}}}}
        selected_sitem_id {}
        welcome {}
    }]


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


    # sample slist
    # {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}} {id 2 ccode FR country France city Paris ip 176.31.32.106 ovses {{proto udp port 123} {proto tcp port 443}}} {id 3 ccode UK country {United Kingdom} city Newcastle ip 31.24.33.221 ovses {{proto udp port 5353} {proto tcp port 443}}}}
    # There is a single slist and selected_sitem_id (ssid) per provider
    # On Click Connect the current provider's selected_sitem is copied to Current_sitem which stores currently connecting/connected sitem
 
    variable Current_sitem {}

    variable provider_list {securitykiss}

    variable layout_bg1 white
    variable layout_bg2 grey95
    variable layout_bg3 "light grey"
    variable layout_fgused grey
    variable layout_fgelapsed grey
    variable layout_x 300
    variable layout_y 300
    variable layout_w 0
    variable layout_h 0
    variable layout_barw 350
    variable layout_barh 8

    variable Gui_planline "Plan"
    variable Gui_usedlabel "Used"
    variable Gui_usedsummary "?"
    variable Gui_elapsedlabel "Elapsed"
    variable Gui_elapsedsummary "?"
    variable Gui_externalip "?"


    ######################################## 
    # securitykiss specific
    ######################################## 

    # client id
    variable Cn ""
    
    # Embedded bootstrap vigo list
    variable Vigos {}

    variable vigo_lastok 0
}

# Display all model variables to stderr
proc ::model::print {} {
    puts stderr "MODEL:"
    foreach v [info vars ::model::*] {
        puts stderr "$v=[set $v]"
    }
    puts stderr ""
}

# get the list of ::model namespace variables
proc ::model::vars {} {
    lmap v [info vars ::model::*] {
        string range $v [string length ::model::] end
    }
}

# Update model provider_list based on filesystem provider folders 
# When adding/removing provider, just create/delete folder in ~/.sku/provider
# and call this proc - it will take care of updating the model
proc ::model::update-provider-list {} {
    # ensure there is at least one provider
    if {[llength $::model::provider_list] == 0} {
        lappend ::model::provider_list securitykiss
    }

    # providers by config/model
    set cproviders $::model::provider_list

    # providers by filesystem
    set fproviders [lmap d [glob -directory $::model::PROVIDERDIR -nocomplain -type d *] {file tail $d}]

    # sanitize directory names
    foreach p $fproviders {
        if {![regexp {^[\w\d_]+$} $p]} {
            fatal "Provider directory name should be alphanumeric string in $::model::PROVIDERDIR"
        }
    }

    # all this shuffling below in order to preserve providers order as saved previously, keep in model
    set ::model::provider_list [lunique [concat [lintersection $cproviders $fproviders] $fproviders]]
}


proc ::model::ini2model {inifile} {
    touch $inifile
    # smd - Saved Model Dictionary
    set smd [inicfg load $inifile]
    dict for {key value} $smd { 
        set ::model::$key $value
    }
}

proc ::model::model2ini {inifile} {
    # load entire model namespace to a dict
    set d [dict create]
    foreach key [::model::vars] {
        dict set d $key [set ::model::$key]
    }
    # save fields starting with lowercase
    set smd [dict filter $d key \[a-z\]*]
    inicfg save $inifile $smd
}

proc ::model::dict2ini {d inifile} {
    # save field if starts with lowercase
    set smd [dict filter $d key \[a-z\]*]
    inicfg save $inifile $smd
}

proc ::model::load-vigos {} {
    # embedded bootstrap vigo list
    set lst [slurp [file join [file dir [info script]] bootstrap_ips.lst]]
    set vigos ""
    foreach v $lst {
        set v [string trim $v]
        if {[is-valid-ip $v]} {
            lappend vigos $v
        }
    }
    set ::model::Vigos $vigos
    puts stderr "Vigos: $vigos"
    #TODO use vigos to get current time - why do we need it before welcome?.
    #TODO isn't certificate signing start date a problem in case of vigos in different timezones? Consider signing with golang crypto libraries
}



# Read saved part of the model as a dict
# and populate to model ns
proc ::model::load {} {
    if {[catch {
        ini2model $::model::INIFILE
        ::model::load-vigos

        # merge provider list from saved model provider folder structure
        update-provider-list

        foreach p $::model::provider_list {
            set inifile [file join $::model::PROVIDERDIR $p config.ini]
            touch $inifile
            dict set ::model::Providers $p [inicfg load $inifile]
            dict-put ::model::Providers $p tabname $p
        }
    } out err]} {
        puts stderr $out
        log $out
        log $err
        main-exit
    }

    #puts stderr "READ CONFIG:"
    #::model::print
    #puts stderr "[inicfg dict-pretty $::Config]"
}

# may throw errors
proc ::model::save {} {
    # save main ini
    ::model::model2ini $::model::INIFILE
    # save provider inis
    dict for {p d} $::model::Providers {
        set inifile [file join $::model::PROVIDERDIR $p config.ini]
        ::model::dict2ini $d $inifile
    }
}


######################################## 
# Slist and Sitem logic
######################################## 

# Examples:
# model slist $provider - get slist for $provider
# model slist $provider $slist - save $slist for $provider
proc ::model::slist {provider args} {
    if {[llength $args] == 0} {
        return [dict-pop $::model::Providers $provider slist {}]
    } elseif {[llength $args] == 1} {
        set slist [lindex $args 0]
        dict set ::model::Providers $provider slist $slist
    }
}

# Get or store selected sitem/site_id. Since slist is dynamic the selected sitem may get obsolete. 
# This function should prevent returning obsolete selected sitem by taking random in that case
# so there is no guarantee that what you put in is what you get out
#
# With additional argument:
# selected-sitem $provider - get selected sitem (dict) for provider or draw random from slist
# selected-sitem $provider ?sitem_id?
# selected-sitem $provider ?sitem?
# - saves selected sitem id. Given sitem may be empty
proc ::model::selected-sitem {provider args} {
    if {[llength $args] == 0} {
        set slist [::model::slist $provider]
        set ssid [dict-pop $::model::Providers $provider selected_sitem_id {}]
        if {$ssid eq "" || [::model::sitem-by-id $provider $ssid] eq ""} {
            # pick random sitem
            set rand [rand-int [llength $slist]]
            set sitem [lindex $slist $rand]
            # save its id in model
            dict set ::model::Providers $provider selected_sitem_id [dict get $sitem id]
            return $sitem
        } else {
            return [::model::sitem-by-id $provider $ssid]
        }
    } elseif {[llength $args] == 1} {
        set sitem [lindex $args 0]
        if {$sitem eq ""} {
            set sitem_id ""
        } elseif {[string is integer -strict $sitem]} {
            set sitem_id $sitem
        } else {
            set sitem_id [dict-pop $sitem id {}]
        }
        dict set ::model::Providers $provider selected_sitem_id $sitem_id
        return [::model::selected-sitem $provider]
    } else {
        log ERROR: wrong number of arguments in selected-sitem $provider $args
    }
}

# return sitem dict by id or empty if no such sitem
proc ::model::sitem-by-id {provider sitem_id} {
    foreach sitem [::model::slist $provider] {
        set id [dict get $sitem id]
        if {$id eq $sitem_id} {
            return $sitem
        }
    }
    return {}
}

# [model now]
# return offset-ed current time, it may use previously saved time offset 
# it should be server-originated UTC in seconds, if no offset use local time
# TODO remember to update display and time related derivatives 
# (for example current plan) after welcome message received
# in order to get the time with updated time offset
# TODO what to do if we get "now" from many welcome messages?
# [model now $now]
# use $now to calculate time offset that will be saved in the model
proc ::model::now {args} {
    if {[llength $args] == 0} {
        return [expr {[clock seconds] + $::model::now_offset}]
    } elseif {[llength $args] == 1} {
        set now [lindex $args 0]
        if {[string is integer -strict $now]} {
            set ::model::now_offset [expr {$now - [clock seconds]}]
        }
    } else {
        log ERROR: wrong number of arguments in ::model::now $args
    }
}





