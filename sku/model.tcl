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
    
    variable INIFILE [file normalize ~/.sku/sku.ini]
    variable LOGFILE [file normalize ~/.sku/sku.log]
    variable PROVIDERDIR [file normalize ~/.sku/provider]
    variable KEYSDIR [file join $::model::PROVIDERDIR securitykiss ovpnconf default]


    ######################################## 
    # General globals
    ######################################## 

    # currently selected provider tab
    variable current_provider securitykiss

    # SKD connection socket 
    variable Skd_sock ""

    # User Interface (gui or cli)
    variable Ui ""

    # OpenVPN connection status
    variable Conn_status disconnected


    # other providers dict
    variable Providers [dict create securitykiss {
        tabname SecurityKISS
        slist {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}} {id 2 ccode FR country France city Paris ip 176.31.32.106 ovses {{proto udp port 123} {proto tcp port 443}}} {id 3 ccode UK country {United Kingdom} city Newcastle ip 31.24.33.221 ovses {{proto udp port 5353} {proto tcp port 443}}}}
        selected_sitem_id {}
    }]

    # sample slist
    # {{id 1 ccode DE country Germany city Darmstadt ip 46.165.221.230 ovses {{proto udp port 123} {proto tcp port 443}}} {id 2 ccode FR country France city Paris ip 176.31.32.106 ovses {{proto udp port 123} {proto tcp port 443}}} {id 3 ccode UK country {United Kingdom} city Newcastle ip 31.24.33.221 ovses {{proto udp port 5353} {proto tcp port 443}}}}
 
    variable provider_list {securitykiss}

    variable Current_sitem {}

    variable layout_bg1 white
    variable layout_bg2 grey95
    variable layout_bg3 "light grey"
    variable layout_x 300
    variable layout_y 300
    variable layout_w 0
    variable layout_h 0


    ######################################## 
    # securitykiss specific
    ######################################## 

    # client id
    variable Cn ""
    
    # Embedded bootstrap vigo list
    variable Vigos {}

    variable vigo_lastok 0

    # temporary slist
    variable slist {}
}

# Display all model variables to stderr
proc ::model::print {} {
    puts stderr "MODEL:"
    foreach v [info vars ::model::*] {
        puts stderr "$v=[set $v]"
    }
    puts stderr ""
}

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
    set d [dict create]
    foreach key [::model::vars] {
        dict set d $key [set ::model::$key]
    }
    # save property if starts with lowercase
    set smd [dict filter $d key \[a-z\]*]
    inicfg save $inifile $smd
}

proc ::model::dict2ini {d inifile} {
    # save property if starts with lowercase
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

    puts stderr "READ CONFIG:"
    ::model::print
    #puts stderr "[inicfg dict-pretty $::Config]"
}

proc ::model::save {} {
    # save main ini
    ::model::model2ini $::model::INIFILE
    # save provider inis
    dict for {p d} $::model::Providers {
        set inifile [file join $::model::PROVIDERDIR $p config.ini]
        ::model::dict2ini $d $inifile
    }
}


proc ::model::slist {provider args} {
    if {[llength $args] == 0} {
        return [dict-pop $::model::Providers $provider slist {}]
    } elseif {[llength $args] == 1} {
        set slist [lindex $args 0]
        dict set ::model::Providers $provider slist $slist
    }
}


# ... so there is no guarantee that what you put in is what you get out
# If only $provider argument given return selected sitem dict or empty dict/string if no provider. If selected was not present return random from the slist
#
# With additional argument:
# selected-sitem $provider ?sitem_id?
# selected-sitem $provider ?sitem?
# saves selected sitem id. Given sitem may be empty
proc ::model::selected-sitem {provider args} {
    if {[llength $args] == 0} {
        set slist [::model::slist $provider]
        set ssid [dict-pop $::model::Providers $provider selected_sitem_id {}]
        if {$ssid eq "" || [::model::sitem-by-id $provider $ssid] eq ""} {
            # pick random sitem
            set sitem [lindex $slist [rand-int [llength $slist]]]
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


