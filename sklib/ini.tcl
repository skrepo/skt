package provide ini 0.0.0

# ini config parser. Supports hierarchical sections
# ini load $path - return dict
# ini save $path $config - save $config dict


# for simplicity assume that disk I/O is immediate so provide only blocking command version
# -nocache option for load

namespace eval ::ini {
    namespace export load save
    namespace ensemble create
}

proc ::ini::slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

proc ::ini::spit {path content} {
    set fd [open $path w]
    puts -nonewline $fd $content
    close $fd
}

proc ::ini::ignored {line} {
    if {$line eq "" || [string index $line 0] == ";" || [string index $line 0] == "#"} {
        return 1
    } else {
        return 0
    }
}

proc ::ini::load {path} {
    set data [slurp $path]
    set lines [split $data \n]
    set lines [lmap line $lines {string trim $line}]
    set lines [lmap line $lines {
        if {[ignored $line]} {
            continue
        } else {
            set line
        }
    }]
    set res ""
    # start with default section
    set section ""
    foreach line $lines {
        switch -regexp -matchvar v $line {
            {^\[(.*)\]$} {
                set section [lindex $v 1]
            }
            {^([^=]*)=(.*)$} {
                set name [lindex $v 1]
                set value [lindex $v 2]
                dict set res {*}[split $section .] $name $value
            }
            default {
                error "Unexpected '$line'"
            }
        }
    }
    return $res
}

proc ::ini::save {path config} {
    set data [slurp $path]
    set lines [lmap line [split $data "\n"] {string trim $line}]
    
    spit $path $data

}


######################### 
## dict format dict 
# 
# convert dictionary value dict into string 
# hereby insert newlines and spaces to make 
# a nicely formatted ascii output 
# The output is a valid dict and can be read/used 
# just like the original dict 
############################# 

proc isdict {v} { 
   string match "value is a dict *" [::tcl::unsupported::representation $v] 
} 

## helper function - do the real work recursively 
# use accumulator for indentation 
proc dict-pretty {dict {indent ""} {indentstring "    "}} {
   # unpack this dimension 
   dict for {key value} $dict { 
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

