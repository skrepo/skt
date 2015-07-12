package require skutil

namespace eval ::model {

    namespace export *
    namespace ensemble create
    
    # skd-sku client socket, also indicates if sku client connected
    variable skd_sock ""
    # OpenVPN config as double-dashed one-line string
    variable ovpn_config ""

    # pid also determines openvpn status: started, stopped
    # TODO make retrieving OpenVPN pid more robust: ovpn mgmt pid command
    # > pid
    # > SUCCESS: pid=3422
    variable ovpn_pid ""
    # current openvpn status: connected, disconnected
    # TODO
    # > state
    # > 1436650174,CONNECTED,SUCCESS,10.13.0.26,78.129.174.84
    # > END
    variable ovpn_connstatus disconnected
    # DNS pushed from the server
    variable ovpn_dnsip ""


    # mgmt port
    variable mgmt_port 0
    # TUN/TAP read bytes
    variable mgmt_vread 0
    # TUN/TAP write bytes
    variable mgmt_vwrite 0
    # TCP/UDP read bytes
    variable mgmt_rread 0
    # TCP/UDP write bytes
    variable mgmt_rwrite 0
    # connection state from mgmt console: AUTH,GET_CONFIG,ASSIGN_IP,CONNECTED
    variable mgmt_connstatus ""
    # virtual IP
    variable mgmt_vip ""
    # real IP
    variable mgmt_rip ""
}


proc ::model::reset-ovpn-state {} {
    set ::model::mgmt_port 0
    set ::model::mgmt_vread 0
    set ::model::mgmt_vwrite 0
    set ::model::mgmt_rread 0
    set ::model::mgmt_rwrite 0
    set ::model::mgmt_connstatus ""
    set ::model::mgmt_vip ""
    set ::model::mgmt_rip ""
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


# TODO model2dict

