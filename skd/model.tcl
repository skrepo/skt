package require skutil

namespace eval ::model {

    namespace export *
    namespace ensemble create
    
    variable Resolv_marker "# DO NOT MODIFY - SKD generated"


    # skd-sku client socket, also indicates if sku client connected
    variable Skd_sock ""
    # OpenVPN config as double-dashed one-line string
    variable ovpn_config ""

    # DNS pushed from the server
    variable ovpn_dnsip ""


    # mgmt port
    variable mgmt_port 42385


    ##################################
    # mgmt state command output

    # timestamp of last state command update in milliseconds
    variable Mgmt_state_tstamp 0
    # management console client socket
    variable Mgmt_sock ""
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

    ################################
    # OpenVPN process PID
    
    # openvpn process PID as per mgmt console
    variable Mgmt_pid 0
    # last pid update in milliseconds
    variable Mgmt_pid_tstamp 0

    # openvpn process PID when starting OpenVPN
    variable Start_pid 0

    # final openvpn process PID set by algorithm
    variable ovpn_pid 0

}


proc ::model::reset-ovpn-state {} {
    set ::model::Mgmt_state_tstamp 0
    set ::model::Mgmt_sock ""
    set ::model::mgmt_port 42385
    set ::model::mgmt_vread 0
    set ::model::mgmt_vwrite 0
    set ::model::mgmt_rread 0
    set ::model::mgmt_rwrite 0
    set ::model::mgmt_connstatus ""
    set ::model::mgmt_vip ""
    set ::model::mgmt_rip ""
    set ::model::ovpn_dnsip ""
    set ::model::Mgmt_pid 0
    set ::model::Mgmt_pid_tstamp 0
    set ::model::Start_pid 0
    set ::model::ovpn_pid 0
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


# return part of the model (fields staring with lowercase) as a dict
proc ::model::model2dict {} {
    # load entire model namespace to a dict
    set d [dict create]
    foreach key [::model::vars] {
        dict set d $key [set ::model::$key]
    }
    # filter fields starting with lowercase
    set d [dict filter $d key \[a-z\]*]
    return $d
}
