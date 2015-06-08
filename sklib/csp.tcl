package provide csp 0.0.0

namespace eval csp {
    # channel as a list/queue for buffered channel or
    # venue container for rendez-vous channel (non-buffered size 0 channel)
    variable Channel
    array set Channel {}
    # channel capacity (buffer size)
    variable ChannelCap
    array set ChannelCap {}
    variable Routine
    array set Routine {}
    # counters to produce unique Routine and Channel names
    variable RCount 0
    variable CCount 0

    # Channel proc template
    variable CTemplate {
        proc %CHANNEL% {operator val} {
            if {$operator ne "<-"} {
                error "Unrecognized operator $operator. Should be <-"
            }
            while {![CSendReady %CHANNEL%]} {
                uplevel yield
            }
            CAppend %CHANNEL% $val
            after idle ::csp::goupdate
            # post-send extra logic for rendez-vous channels
            if {![CBuffered %CHANNEL%]} {
                # wait again for container empty (receiver collected value)
                while {![CEmpty %CHANNEL%]} {
                    uplevel yield
                }
            }
        }
    }

    namespace export go channel select timer ticker <-
    namespace ensemble create
}

proc ::csp::CSendReady {ch} {
    if {[CBuffered $ch]} {
        return [expr {! [CFull $ch]}]
    } else {
        return [CEmpty $ch]
    }
}


# create channel (with internal name) and place that name in given var
# the default buffer size (capacity) is zero which means rendez-vous channel
proc ::csp::channel {varName {cap 0}} {
    variable Channel
    variable ChannelCap
    variable CTemplate
    upvar $varName var    
    set var [NewChannel]
    # initialize channel as a list or do nothing if exists
    set Channel($var) {}
    set ChannelCap($var) $cap
    namespace eval ::csp [string map [list %CHANNEL% $var] $CTemplate]
    return $var
}

# uconditionally append to the channel - internal only
proc ::csp::CAppend {ch val} {
    variable Channel
    lappend Channel($ch) $val
    #puts "Channel($ch) after CAppend: $Channel($ch)"
    return
}

proc ::csp::CBuffered {ch} {
    variable ChannelCap
    return [expr {$ChannelCap($ch) != 0}]
}

proc ::csp::CEmpty {ch} {
    variable Channel
    return [expr {[llength $Channel($ch)] == 0}]
}


proc ::csp::CFull {ch} {
    variable Channel
    variable ChannelCap
    set clen [llength $Channel($ch)]
    return [expr {$clen >= $ChannelCap($ch)}]
}

# return contents of the channel
proc ::csp::CGet {ch} {
    variable Channel
    return $Channel($ch)
}



# generate new routine name
proc ::csp::NewRoutine {} {
    variable RCount
    incr RCount
    return ::csp::Routine_$RCount
}

proc ::csp::NewChannel {} {
    variable CCount
    incr CCount
    return ::csp::Channel_$CCount
}



# invoke proc in a routine
proc ::csp::go {args} {
    variable Routine
    # args contain the routine name with arguments
    set rname [::csp::NewRoutine]
    coroutine $rname {*}$args
    set Routine($rname) 1
    after idle ::csp::goupdate
    return $rname
}

# TODO every routine should save in Routine array if it did anything last time when called
# if it was idle set 0 in the array
# if all idle don't schedule next goupdate
proc ::csp::goupdate {} {
    variable Routine
    foreach r [array names Routine] {
        if {[info commands $r] eq ""} {
            # coroutine must have ended so remove it from the array
            unset Routine($r)
        } else {
            $r
        }
    }
}


proc ::csp::CReceive {ch} {
    variable Channel
    set elem [lindex $Channel($ch) 0]
    set Channel($ch) [lreplace $Channel($ch) 0 0]
    return $elem
}

proc ::csp::<- {ch} {
    # check if ch contains elements, return element or yield empty
    while {[CEmpty $ch]} {
        uplevel yield
    }
    set elem [CReceive $ch]
    after idle ::csp::goupdate
    return $elem
}


proc ::csp::select {a} {
    set ready_count 0
    while {$ready_count == 0} {
        # (dir ch body) triples ready for send/receive
        set triples {}
        set default 0
        set defaultbody ""
        foreach {dir ch body} $a {
            if {$ch eq "<-"} {
                lassign [list $dir $ch] ch dir
                set channel [uplevel subst $ch]
                if {[CSendReady $channel]} {
                    lappend triples s $channel $body
                }
            } elseif {$dir eq "<-"} {
                set channel [uplevel subst $ch]
                if {![CEmpty $channel]} {
                    lappend triples r $channel $body
                }
            } elseif {$dir eq "default"} {
                set default 1
                set defaultbody $ch
            } else {
                error "Wrong select arguments: $dir $ch"
            }
        }
        set ready_count [expr {[llength $triples] / 3}]
        if {$ready_count == 0} {
            if {$default == 0} {
                uplevel yield
            } else {
                return [uplevel $defaultbody]
            }
        }
    }

    if {$ready_count == 1} {
        set triple $triples
    } else {
        set random [expr {round(floor(rand()*$ready_count))}]
        set triple [lrange $triples [expr {$random * 3}] [expr {$random * 3 + 2}]]
    }
     
    lassign $triple dir ch body
    return [uplevel $body]
}



proc ::csp::timer_routine {ch} {
    $ch <- [clock seconds]
}

proc ::csp::timer {varName ms} {
    upvar $varName ch
    csp::channel ch 0
    after $ms csp::go timer_routine $ch
    return $ch
}

proc ::csp::ticker_routine {ch ms} {
    $ch <- [clock seconds]
    after $ms csp::go ticker_routine $ch $ms
}

proc ::csp::ticker {varName ms} {
    upvar $varName ch
    csp::channel ch 0
    after $ms csp::go ticker_routine $ch $ms
    return $ch
}


