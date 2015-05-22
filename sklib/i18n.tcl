package provide i18n 0.0.0


proc _ {t args} {

    #TODO find localized t replacement
    #TODO Verify number of args against placeholders in t
    # convert args list into array
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


# Parse source code files, mark translatable lines with UID, create/update messages file.
# This assumes that developer added or updated translatable lines in source code and messages need to be updated.
proc ::i18n::code2msg {filespec {msgfile messages.txt}} {
    puts ""
    #TODO for now filespec is assumed to be a single file - should be file/dir specification/filter
    

}

# Parse messages file, compare its 'en' entries with translatable lines in source code. Update source code.
# This assumes that translator changed the original 'en' messages and source code needs to be updated.
proc ::i18n::msg2code {} {

}

# Delete previous '#|' messages from messages file
# Delete messages marked to remove from messages file
proc ::i18n::cleanup {} {

}

# Find messages from messages file that have no corresponding translatable line (by UID) in source code.
# Mark them to remove
proc ::i18n::orphans {} {

}

