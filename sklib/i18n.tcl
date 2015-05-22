package provide i18n 0.0.0

# Terminology:
# tm - translatable message
# uid - randomly generated identifier in format _1234567890abcdef, uniquely identifies tm


proc _ {t args} {

    #TODO find localized t replacement
    #TODO Verify number of params against placeholders in t
    # convert params list into array
    set i 0
    array set arr {}
    foreach a $args {
        set arr({$i}) $a
        incr i
    }
    # replace tokens in t
    return [string map [array get arr] $t]
}




namespace eval i18n {
    variable LC [dict create]
    namespace export load code2msg msg2code cleanup orphans
    namespace ensemble create
}

# Load messages file and store as dictionary
proc ::i18n::load {locale {msgfile messages.txt}} {
    variable LC
    #TODO create dictionary mapping 'en' string to translated message
    #TODO ignore localization generated id tokens - they are only for static parsing and message identification
    
    #process line by line
    #find #L16hex token as a section start
    #save en="xxx" xxx as a key
    #ignore yy= where yy!=locale
    #save it="zzz" zzz as value
    #export the key=>value array in $LC

}


# Parse source code files, mark translatable lines with uid, create/update messages file.
# This assumes that developer added or updated translatable lines in source code and messages need to be updated.
proc ::i18n::code2msg {filespec {msgfile messages.txt}} {
    #TODO uncomment and pass to code-uid-update in order to solve ambiguities where possible
    set uid2tm_msg [msg-prescan $msgfile]
    #TODO for now filespec is assumed to be a single file - should be file/dir specification/filter
    set uid2tml_code [code-uid-update $filespec]
    puts "uid2tml_code: $uid2tml_code"

    # now process messages.txt line by line and update tm based on matching uid
    # then append tms for uids that were not matched
    set out {}
    touch $msgfile
    set msgs [slurp $msgfile]
    set lines [split $msgs \n]
    set uids {}
    set prevSaved 0
    # original line numbers
    set lno 0
    foreach line $lines {
        incr lno
        switch -regexp -matchvar token $line {
            {^\s*#\|\s*en=} {
                # automatic comment - saved previous tm
                set prevSaved 1
                lappend out $line
            }
            {^\s*#\s*(_[\da-f]{16})} {
                # automatic comment - uids which means new section
                set index 0
                set uids {}
                set prevSaved 0
                #TODO handle multiple uids in the future - this is preparation
                while {[regexp -start $index {.*?(_[\da-f]{16})} $line match sub]} {
                    lappend uids $sub
                    incr index [string length $match]
                }
                lappend out $line
            }
            {^\s*en=(.*)$} {
                # tm
                set msg [lindex $token 1]
                #TODO handle multiple uids in the future - it may be tricky to handle changes. For now take the first uid
                set uid [lindex $uids 0]
                if {[dict exists $uid2tml_code $uid]} {
                    set msg_code [lindex [dict get $uid2tml_code $uid] 0]
                    dict unset uid2tml_code $uid
                    if {$msg eq $msg_code} {
                        # tm has not changed
                        lappend out $line
                    } else {
                        #TODO update args description line above
                        if {!$prevSaved} {
                            lappend out "#| en=$msg"
                        }
                        lappend out "en=$msg_code"
                    }
                }
            }
            default {
                lappend out $line
            }
        }
    }
    
    # now append new sections (uid present in source code but missing in messages)
    dict for {uid tml} $uid2tml_code {
        lappend out ""
        lappend out "# $uid"
        set msg_code [lindex $tml 0]
        set params [params-list2dict [lrange $tml 1 end]]
        if {$params ne ""} {
            lappend out "#, [join $params " "]"
        }
        lappend out "en=$msg_code"
    }
    
    spit $msgfile [join $out \n]
}

# Parse source code file and create missing uid tokens in source file i.e. it may modify the source file
# Return dict mapping uid => (list of tm and its arguments)
proc ::i18n::code-uid-update {filename} {
    set uid2tml [dict create]
    set touched 0
    set out {}
    set code [slurp $filename]
    set lines [split $code \n]
    set lno 0
    foreach line $lines {
        incr lno
        set index 0
        # translatable messages
        set tm {}
        while {[regexp -start $index {.*?\[_\s+([^\]]+)\]} $line match sub]} {
            lappend tm $sub
            incr index [string length $match]
        }
        # uid tokens
        set ut {}
        while {[regexp -start $index {.*?(_[\da-f]{16})} $line match sub]} {
            lappend ut $sub
            incr index [string length $match]
        }
        set missing [expr {[llength $tm] - [llength $ut]}]
        if {$missing > 0} {
            #TODO if [llength $ut] > 0 here it's also ambiguity - resolve it wiser
            foreach i [seq $missing] {
                set uid [generate-uid]
                append line " ;# _$uid"
                lappend ut $uid
            }
            set touched 1
        } elseif {$missing < 0 && [llength $ut] > 1} {
            #TODO resolve ambiguity by looking at existing tokens in messages.txt
            error "i18n ambiguity: more uid tokens than messages"
        }
        foreach i [seq [llength $tm]] {
            dict set uid2tml [lindex $ut $i] [lindex $tm $i]
        }
        lappend out $line
    }
    # don't touch the source file if there were no changes
    if {$touched} {
        spit $filename [join $out \n]
    }
    return $uid2tml
}



proc ::i18n::msg-prescan {msgfile} {

}


# Parse messages file, compare its 'en' entries with translatable lines in source code. Update source code.
# This assumes that translator changed the original 'en' messages and source code needs to be updated.
proc ::i18n::msg2code {} {

}

# Delete previous '#|' messages from messages file
# Delete messages marked to remove from messages file
proc ::i18n::cleanup {} {

}

# Find messages from messages file that have no corresponding translatable line (by uid) in source code.
# Mark them to remove
proc ::i18n::orphans {} {

}

proc ::i18n::slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

proc ::i18n::spit {path content} {
    set fd [open $path w]
    puts -nonewline $fd $content
    close $fd
}


proc ::i18n::rand-byte {} {
    return [expr {round(rand()*256)}]
}

proc ::i18n::rand-byte-hex {} {
    return [format %02x [rand-byte]]
}

proc ::i18n::seq {n} {
    set res {}
    for {set i 0} {$i < $n} {incr i} {
        lappend res $i
    }
    return $res
}

proc ::i18n::generate-uid {} {
    return [join [lmap i [seq 8] {rand-byte-hex}] ""]
}


proc ::i18n::touch {file} {
    if {[file exists $file]} {
        file mtime $file [clock seconds]
    } else {
        set fh [open $file w]
        catch {close $fh}
    }
}

proc ::i18n::params-list2dict {params} {
    set d [dict create]
    set i 0
    foreach p $params {
        dict set d "{$i}" $p
        incr i
    }
    return $d
}
