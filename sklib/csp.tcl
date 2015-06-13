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
        proc %CHANNEL% {operator {val ""}} {
            if {$operator eq "close"} {
                # delete channel command == channel closed
                rename %CHANNEL% "" 
                # let the CDrained purge the channel if empty
                CDrained %CHANNEL%
                SetResume
                return
            }
            CheckOperator $operator
            while {![CSendReady %CHANNEL%]} {
                CheckClosed %CHANNEL%
                Wait$operator
            }
            CAppend %CHANNEL% $val
            SetResume
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

    namespace export go channel select timer ticker range range! <- <-! -> ->>
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
        error "Cannot send to the closed channel $ch"
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
    return [expr {![CEmpty $ch]}]
}

# remove the channel completely
proc ::csp::CPurge {ch} {
    CheckName $ch
    catch {
        unset Channel($ch)
        unset ChannelCap($ch)
        rename $ch ""
        SetResume
    }
}


# channel chlist ?cap? 
# Create channel(s) (with internal name) and place that name in given var
# the default buffer size (capacity) is zero which means rendez-vous channel
proc ::csp::channel {chVars {cap 0}} {
    variable Channel
    variable ChannelCap
    variable CTemplate
    lmap chVar $chVars {
        upvar $chVar ch
        set ch [NewChannel]
        # initialize channel as a list or do nothing if exists
        set Channel($ch) {}
        set ChannelCap($ch) $cap
        namespace eval ::csp [string map [list %CHANNEL% $ch] $CTemplate]
    }
}

# A channel is considered closed if no longer exists (but its name is correct) 
proc ::csp::CClosed {ch} {
    CheckName $ch
    # if channel command no longer exists
    return [expr {[info procs $ch] eq ""}]
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
    CheckName $ch
    if {[info exists Channel($ch)]} {
        return [expr {[llength $Channel($ch)] == 0}]
    } else {
        return 1
    }
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
    SetResume
    return $rname
}

proc ::csp::SetResume {} {
    after idle {after 0 ::csp::Resume}
}

proc ::csp::Resume {} {
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
            catch $r
            #after idle [list after 0 catch $r]
            #if {[catch {$r} out err]} 
                #puts stderr "OUT: $out, ERR: $err"
            
        }
    }
    set ::csp::resume 1
}


proc ::csp::CReceive {ch} {
    variable Channel
    set elem [lindex $Channel($ch) 0]
    set Channel($ch) [lreplace $Channel($ch) 0 0]
    return $elem
}


proc ::csp::CDrained {ch} {
    CheckName $ch
    # drained = empty and closed
    set drained [expr {![CReceiveReady $ch] && [CClosed $ch]}]
    if {$drained} {
        # just in case purge every time
        CPurge $ch
        return 1
    } else {
        return 0
    }
}


proc ::csp::ReceiveWith {ch operator} {
    CheckOperator $operator
    # check if ch contains elements, if so return element, yield otherwise
    while {![CReceiveReady $ch]} {
        # trying to receive from empty and closed channel should clean up the channel and throw error
        if {[CDrained $ch]} {
            error "Cannot receive from a drained (empty and closed) channel $ch"
        }
        Wait$operator
    }
    set elem [CReceive $ch]
    SetResume
    return $elem
}

# Receive from channel, wait if channel not ready, throw error if channel is drained
# Can be only used from coroutine
# Uses yield for wait
proc ::csp::<- {ch} {
    return [ReceiveWith $ch <-]
}

# Receive from channel, wait if channel not ready, throw error if channel is drained
# Can be used from non-coroutine
# Uses vwait for wait => nested event loops
# It means that not ready channel in nested vwait 
# may block an upstream channel that become ready
# Use with care. Avoid if you can.
proc ::csp::<-! {ch} {
    return [ReceiveWith $ch <-!]
}


# Create a callback handler being a coroutine which when called
# will send callback arguments to the given channel
proc ::csp::-> {ch} {
    # this coroutine will not be registered in Routine array for unblocking calls
    # it should be called from the userland callback
    set routine [NewRoutine]
    coroutine $routine OneTimeSender $ch
    return $routine
}

proc ::csp::OneTimeSender {ch} {
    set cbargs [yield]
    if {![CClosed $ch]} {
        $ch <- $cbargs
    }
}

proc ::csp::->> {ch} {
    # this coroutine will not be registered in Routine array for unblocking calls
    # it should be called from the userland callback
    set routine [NewRoutine]
    coroutine $routine MultiSender $ch
    return $routine
}

proc ::csp::MultiSender {ch} {
    while {![CClosed $ch]} {
        set cbargs [yield]
        if {![CClosed $ch]} {
            $ch <- $cbargs
        }
    }
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

proc ::csp::timer {chName ms} {
    upvar $chName ch
    csp::channel ch
    after $ms [-> $ch] {[clock seconds]}
    return $ch
}

proc ::csp::TickerRoutine {ch ms} {
    if {![CClosed $ch]} {
        $ch <- [clock seconds]
        after $ms csp::go TickerRoutine $ch $ms
    }
}

proc ::csp::ticker {chName ms} {
    upvar $chName ch
    csp::channel ch 0
    after $ms csp::go TickerRoutine $ch $ms
    return $ch
}

# receive from channel until closed
proc ::csp::RangeWith {operator varName ch body} {
    CheckName $ch
    uplevel [subst -nocommands {
        while 1 {
            if {[catch {set $varName [$operator $ch]} out err]} {
                break
            }
            $body
        }
    }]
}

# receive from channel until closed in coroutine
proc ::csp::range {varName ch body} {
    if {[info coroutine] eq ""} {
        error "range can only be used in a coroutine"
    }
    RangeWith <- $varName $ch $body
}

# receive from channel until closed in main control flow
proc ::csp::range! {varName ch body} {
    if {[info coroutine] ne ""} {
        error "range! should not be used in a coroutine"
    }
    RangeWith <-! $varName $ch $body
}
