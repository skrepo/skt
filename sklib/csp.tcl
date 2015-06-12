package provide csp 0.0.0

namespace eval csp {
    # channel as a list/queue for buffered channel or
    # venue container for rendez-vous channel (non-buffered size 0 channel)
    variable Channel
    array set Channel {}
    # channel capacity (buffer size)
    variable ChannelCap
    array set ChannelCap {}
    variable ChannelCloseMark
    array set ChannelCloseMark {}
    variable Routine
    array set Routine {}
    # counters to produce unique Routine and Channel names
    variable RCount 0
    variable CCount 0

    # Channel proc template
    variable CTemplate {
        proc %CHANNEL% {operator val} {
            CheckOperator $operator
            CheckClosed %CHANNEL%
            while {![CSendReady %CHANNEL%]} {
                CheckClosed %CHANNEL%
                Wait$operator
            }
            CAppend %CHANNEL% $val
            after idle {after 0 ::csp::goupdate}
            # post-send extra logic for rendez-vous channels
            if {![CBuffered %CHANNEL%]} {
                # wait again for container empty (once receiver collected the value)
                while {![CEmpty %CHANNEL%]} {
                    CheckClosed %CHANNEL%
                    Wait$operator
                }
            }
        }
    }

    namespace export go channel select timer ticker range <- <-!
    namespace ensemble create
}

proc ::csp::Wait<- {} {
    yield
}

proc ::csp::Wait<-! {} {
    vwait ::csp::resume
}

proc ::csp::IsOperator {op} {
    return [expr {$op in {<- <-!}}]
}

proc ::csp::CheckOperator {op} {
    if {![IsOperator $op]} {
        error "Unrecognized operator $op. Should be <- or <-!"
    }
    if {[info coroutine] eq ""} {
        if {$op eq "<-"} {
            error "<- can only be used in a coroutine"
        }
    } else {
        if {$op eq "<-!"} {
            error "<-! should not be used in a coroutine"
        }
    }
}

# throw error if channel is closed
proc ::csp::CheckClosed {ch} {
    if {[CClosed $ch]} {
        error "Cannot send to the closed channel %CHANNEL%"
    }
}

# throw error if incorrect channel name
proc ::csp::CheckName {ch} {
    if {![regexp {::csp::Channel_\d+} $ch]} {
        error "Wrong channel name: $ch"
    }
}

proc ::csp::CSendReady {ch} {
    if {[CClosed $ch]} {
        return 0
    }
    if {[CBuffered $ch]} {
        return [expr {! [CFull $ch]}]
    } else {
        return [CEmpty $ch]
    }
}

proc ::csp::CReceiveReady {ch} {
    CheckName $ch 
    # if channel command no longer exists
    if {[info procs $ch] eq ""} {
        return 0
    }
    return [expr {![CEmpty $ch]}]
}



# 1. channel ch ?cap? 
# Create channel (with internal name) and place that name in given var
# the default buffer size (capacity) is zero which means rendez-vous channel
# 2. channel ch close
# Close the channel named by ch
# 3. channel ch purge
# Close the channel and release resources (further references to the channel will throw error)
proc ::csp::channel {chVars {cap 0}} {
    variable Channel
    variable ChannelCap
    variable ChannelCloseMark
    variable CTemplate
    lmap chVar $chVars {
        upvar $chVar ch
        if {$cap eq "close"} {
            set ChannelCloseMark($ch) 1
            channel ch purge
            after idle {after 0 ::csp::goupdate}
        } elseif {$cap eq "purge"} {
            CheckName $ch
            # if channel command still exists
            if {[info procs $ch] ne ""} {
                unset Channel($ch)
                unset ChannelCap($ch)
                unset ChannelCloseMark($ch)
                rename $ch ""
            }
        } else {
            set ch [NewChannel]
            # initialize channel as a list or do nothing if exists
            set Channel($ch) {}
            set ChannelCap($ch) $cap
            set ChannelCloseMark($ch) 0
            namespace eval ::csp [string map [list %CHANNEL% $ch] $CTemplate]
        }
        set ch
    }
}

# A channel is considered closed if no longer exists (but its name is correct) 
# or if it was marked as closed
proc ::csp::CClosed {ch} {
    CheckName $ch
    # if channel command no longer exists
    if {[info procs $ch] eq ""} {
        return 1
    }
    variable ChannelCloseMark
    return $ChannelCloseMark($ch)
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
    CheckName $ch
    # if channel command no longer exists
    if {[info procs $ch] eq ""} {
        return 1
    }
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
# args should be proc name and arguments
proc ::csp::go {args} {
    variable Routine
    # args contain the routine name with arguments
    set rname [::csp::NewRoutine]
    coroutine $rname {*}$args
    set Routine($rname) 1
    after idle {after 0 ::csp::goupdate}
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
            catch {unset Routine($r)}
        } else {
            # cannot run the already running coroutine - catch error when it happens
            #puts stderr "CURRENT COROUTINE: [info coroutine]"
            #puts stderr "r: $r"
            # this may regularly throw 'coroutine "::csp::Routine_N" is already running'
            after idle [list after 0 catch $r]
            #if {[catch {$r} out err]} 
                #puts stderr "OUT: $out, ERR: $err"
            
        }
    }
    # it is enough to resume only once - see vwait experiments in vwait1.tcl
    set ::csp::resume 1
}


proc ::csp::CReceive {ch} {
    variable Channel
    set elem [lindex $Channel($ch) 0]
    set Channel($ch) [lreplace $Channel($ch) 0 0]
    return $elem
}

proc ::csp::ReceiveWith {ch operator} {
    CheckOperator $operator
    # check if ch contains elements, if so return element, yield otherwise
    while {![CReceiveReady $ch]} {
        # if closed and empty channel break the upper loop
        if {[CClosed $ch]} {
            channel ch purge
            return -code break
        }
        Wait$operator
    }
    set elem [CReceive $ch]
    after idle {after 0 ::csp::goupdate}
    return $elem
}

# Can be only used from coroutine
# Uses yield for wait
proc ::csp::<- {ch} {
    return [ReceiveWith $ch <-]
}

# Can be used from non-coroutine
# Uses vwait for wait => nested event loops
# It means that not ready channel in nested vwait 
# may block an upstream channel that become ready
# Use with care. Avoid if you can.
proc ::csp::<-! {ch} {
    return [ReceiveWith $ch <-!]
}


proc ::csp::select {a} {
    set ready_count 0
    while {$ready_count == 0} {
        # (op ch body) triples ready for send/receive
        set triples {}
        set default 0
        set defaultbody {}
        set operator {}
        foreach {op ch body} $a {
            if {[IsOperator $ch]} {
                lassign [list $op $ch] ch op
                set channel [uplevel subst $ch]
                if {$op ni $operator} {
                    lappend operator $op
                }
                if {[CSendReady $channel]} {
                    lappend triples s $channel $body
                }
            } elseif {[IsOperator $op]} {
                set channel [uplevel subst $ch]
                if {$op ni $operator} {
                    lappend operator $op
                }
                if {[CReceiveReady $channel]} {
                    lappend triples r $channel $body
                }
            } elseif {$op eq "default"} {
                set default 1
                set defaultbody $ch
            } else {
                error "Wrong select arguments: $op $ch"
            }
        }
        if {[llength $operator] == 0} {
            error "<- or <-! operator required in select"
        }
        if {[llength $operator] > 1} {
            error "<- and <-! should not be mixed in a single select"
        }
        CheckOperator $operator
        set ready_count [expr {[llength $triples] / 3}]
        if {$ready_count == 0} {
            if {$default == 0} {
                Wait$operator
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
     
    lassign $triple op ch body
    return [uplevel $body]
}

proc ::csp::timer_routine {ch} {
    $ch <- [clock seconds]
}

proc ::csp::timer {chName ms} {
    upvar $chName ch
    csp::channel ch 0
    after $ms csp::go timer_routine $ch
    return $ch
}

proc ::csp::ticker_routine {ch ms} {
    $ch <- [clock seconds]
    after $ms csp::go ticker_routine $ch $ms
}

proc ::csp::ticker {chName ms} {
    upvar $chName ch
    csp::channel ch 0
    after $ms csp::go ticker_routine $ch $ms
    return $ch
}

# receive from channel until closed
proc ::csp::range {varName ch body} {
    uplevel [subst {
        while 1 {
            set $varName \[<- $ch\]
            $body
        }
    }]
}
