# Global model of the application
# Part of it will be durable in ini config file(s)
namespace eval model {
    
    namespace export *
    namespace ensemble create

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
}

proc ::model::print {} {
    puts stderr "MODEL:"
    foreach v [info vars ::model::*] {
        puts stderr "$v=[set $v]"
    }
    puts stderr ""
}


