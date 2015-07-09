# Global model of the application
# Part of it will be durable in ini config file(s)
namespace eval model {
    
    namespace export *
    namespace ensemble create

    variable INIFILE [file normalize ~/.sku/sku.ini]
    variable LOGFILE [file normalize ~/.sku/sku.log]
    variable PROVIDERDIR [file normalize ~/.sku/provider]
    variable KEYSDIR [file join $::model::PROVIDERDIR securitykiss ovpnconf default]

    # currently selected provider tab
    variable current_provider securitykiss

    # SKD connection socket 
    variable skd_sock ""

    # User Interface (gui or cli)
    variable ui ""

    # other providers dict
    variable providers [dict create]

    variable providers_list {}


    #
    # securitykiss specific
    #

    # client id
    variable cn ""
    
    # Embedded bootstrap vigo list
    variable vigos {}

    variable vigo_lastok 0

    # temporary slist
    variable slist {}
}

proc ::model::print {} {
    puts stderr "MODEL:"
    foreach v [info vars ::model::*] {
        puts stderr "$v=[set $v]"
    }
    puts stderr ""
}


