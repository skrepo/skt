package provide inicfg 0.0.0

# *.ini config parser. Supports hierarchical sections
# inicfg load $path - return dict
# inicfg save $path $config - save $config dict

# Sample ini file
# first=1111111 aaaaaa
#
# second=22222222 bbbbbbb
#
# add1=dodane
#
# [HOST]
# #keyvalue
# third=33333 cccc ccc
#
# [PORT]
# forth=4444444 dddddd
#
# add2=ddddoodda
#
# [PORT.FIRST.SECOND]
# fifth=55555
#
# [PORT.FIRST]
# add3=duuuddd
#


# for simplicity assume that disk I/O is immediate so provide only blocking command version
# -nocache option for load

namespace eval ::inicfg {
    namespace export load save dict-pretty
    namespace ensemble create
}

proc ::inicfg::slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

proc ::inicfg::spit {path content} {
    set fd [open $path w]
    puts -nonewline $fd $content
    close $fd
}

# Load ini file and return as dictionary
# ini file may have bracketed sections
# section names may be multi-level with parts separated by dots
# what creates nested dictionary
proc ::inicfg::load {path} {
    set data [slurp $path]
    set lines [split $data \n]
    set lines [lmap line $lines {string trim $line}]
    set res [dict create]
    set sections {}
    # start with default section
    set section ""
    foreach line $lines {
        switch -regexp -matchvar v $line {
            {^$} {}
            {^[#;].*} {}
            {^\[(.*)\]$} {
                if {[lindex $v 1] in $sections} {
                    error "Error parsing $path. Multiple sections $line"
                }
                set section [lindex $v 1]
                lappend sections $section
            }
            {^([^=]*)=(.*)$} {
                set name [lindex $v 1]
                set value [lindex $v 2]
                dict set res {*}[split $section .] $name $value
            }
            default {
                error "Error parsing $path. Unexpected '$line'"
            }
        }
    }
    return $res
}

# Save config dict to file on path
# If file exists, all comments and blank lines are preserved
# Return saving report as plain text
proc ::inicfg::save {path config} {
    if {[file exists $path]} {
        set data [slurp $path]
    } else {
        set data ""
    }
    set lines [lmap line [split $data "\n"] {string trim $line}]
    set res {}
    set section ""
    set report ""
    # this is actually dict copy - for storing unprocessed props
    set left [dict replace $config]
    foreach line $lines {
        switch -regexp -matchvar v $line {
            {^$} {lappend res $line}
            {^[#;].*} {lappend res $line}
            {^\[(.*)\]$} {
                end-of-section $section left res report
                set section [lindex $v 1]
                lappend res $line
            }
            {^([^=]*)=(.*)$} {
                set name [lindex $v 1]
                set value [lindex $v 2]
                if {[dict exists $config {*}[split $section .] $name]} {
                    set cvalue [dict get $config {*}[split $section .] $name]
                    if {$value ne $cvalue} {
                        lappend report "Changed property $name in section \[$section\] to $cvalue. Previous value: $value"
                    }
                    lappend res "$name=$cvalue"
                } else {
                    lappend report "Removed property $name in section \[$section\]. Previous value: $value"
                    lappend res ""
                }
                # mark as processed by removing from the left dict
                dict unset left {*}[split $section .] $name
            }
            default {
                error "Unexpected '$line'"
            }
        }
    }

    end-of-section $section left res report

    # append the unprocessed (added to config)
    dict-dump-nonempty $left "" res report
    spit $path [join $res \n]
    return [join $report \n]
}


proc ::inicfg::end-of-section {section leftVar resVar reportVar} {
    upvar $leftVar left
    upvar $resVar res
    upvar $reportVar report
    set leaves [dict-leaves $left {*}[split $section .]]
    set keys [dict keys $leaves]
    foreach k $keys {
        set value [dict get $leaves $k]
        lappend res "$k=$value"
        lappend report "Added property $k with value $value in section \[$section\]"
        # mark as processed by removing from the left dict
        dict unset left {*}[split $section .] $k
    }
}


# traverse the unprocessed dict d and dump non-empty leaves to resVar
proc ::inicfg::dict-dump-nonempty {d section resVar reportVar} {
    upvar $resVar res
    upvar $reportVar report
    set leaves [dict-leaves $d]
    if {$leaves ne ""} {
        if {$section ne ""} {
            lappend res "\[$section\]"
            lappend report "Added section \[$section\]"
        }
        foreach {key value} $leaves {
            lappend res "$key=$value"
            lappend report "Added property $key with value $value in section \[$section\]"
        }
    }
    foreach {key value} [dict-nonleaves $d] {
        if {$section eq ""} {
            set newsection $key
        } else {
            set newsection $section.$key
        }
        dict-dump-nonempty $value $newsection res report
    }
}


proc ::inicfg::isdict {v} { 
   string match "value is a dict *" [::tcl::unsupported::representation $v] 
} 

######################### 
# convert dictionary value dict into string 
# hereby insert newlines and spaces to make 
# a nicely formatted ascii output 
# The output is a valid dict and can be read/used 
# just like the original dict 
############################# 
# copy of this proc is also in skutil.tcl
proc ::inicfg::dict-pretty {d {indent ""} {indentstring "    "}} {
   # unpack this dimension 
   dict for {key value} $d { 
      if {[isdict $value]} { 
         append result "$indent[list $key]\n$indent\{\n" 
         append result "[dict-pretty $value "$indentstring$indent" $indentstring]\n" 
         append result "$indent\}\n" 
      } else { 
         append result "$indent[list $key] [list $value]\n" 
      }
   }
   return $result 
}

# Get dict consisting of leaves only key-value pairs in the d's subtree specified by args (as path in nested dict)
proc ::inicfg::dict-leaves {d args} {
    set res [dict create]
    dict for {key value} [dict get $d {*}$args] {
        if {![isdict $value]} {
            dict set res $key $value
        }
    }
    return $res
}

proc ::inicfg::dict-nonleaves {d args} {
    set res [dict create]
    dict for {key value} [dict get $d {*}$args] {
        if {[isdict $value]} {
            dict set res $key $value
        }
    }
    return $res
}

# List difference - duplicates matter
proc ::inicfg::ldiff {a b} {
    set res {}
    foreach ael $a {
        set idx [lsearch -exact $b $ael]
        if {$idx < 0} {
            lappend res $ael
        } else {
            set b [lreplace $b $idx $idx]
        }
    }
    return $res
}


