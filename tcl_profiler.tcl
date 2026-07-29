#=================================================================
# TIME PROFILER
# by [Barney Blankenship] (based on work by [George Peter Staplin])
# edited for use with CI by [Jesse W Sandberg]
# 
# Insert this snippet above the function definitions you want
# to have profiled.
#
# TO INITIALIZE OR CLEAR/RESET THE PROFILER...
# global TimeProfilerMode
# if { [info exists TimeProfilerMode] } {
#      global ProfilerArray
#      array unset ProfilerArray
# }
#
# TO PRODUCE THE OUTPUT...
# global TimeProfilerMode
# if { $TimeProfilerMode } {
#      TimeProfilerDump description filename
# }
# (description: text string shown at the top of the output)
#
# PROFILING DATA COLLECTION
# (This describes what is included in the output)
# Provides total elapsed time in milliseconds between reset and dump.
# Provides function call statistics...
# for each function defined after this snippet, provide...
#   Number of times called
#   Average milliseconds per call
#   Maximum milliseconds call time
#   Minimum milliseconds call time
#   Total milliseconds used
#   Ratio of above to total elapsed time (XX.XXX percent)
# In addition, the function call statistics are sorted
# in descending values of Ratio (above).
#
# Note that nested functions and functions that use
# recursion are provided for and timed properly.
#
# TO DISABLE PROFILING WITHOUT REMOVING THE PROFILER
# Set "TimeProfilerMode" to 0 below...
#=================================================================
global TimeProfilerMode
if { ![info exists TimeProfilerMode] } {
    set TimeProfilerMode 0
}

if { $TimeProfilerMode } {
    proc TimeProfiler {args} {
        global ProfilerArray
        
        # Intialize the elapsed time counters if needed...
        if { ![info exists ProfilerArray(ElapsedClicks)] } {
            set ProfilerArray(ElapsedClicks) [expr double([clock clicks])]
            set ProfilerArray(Elapsedms) [expr double([clock clicks -milliseconds])]
        }
        
        set fun [lindex [lindex $args 0] 0]
        
        if { [lindex $args end] == "enter" } {
            # Initalize the count of functions if needed...
            if { ![info exists ProfilerArray(funcount)] } {
                set ProfilerArray(funcount) 0
            }
            
            # See if this function is here for the first time...
            for { set fi 0 } { $fi < $ProfilerArray(funcount) } { incr fi } {
                if { [string equal $ProfilerArray($fi) $fun] } {
                    break
                }
            }
            if { $fi == $ProfilerArray(funcount) } {
                # Yes, function first time visit, add...
                set ProfilerArray($fi) $fun
                set ProfilerArray(funcount) [expr $fi + 1]
            }
            
            # Intialize the "EnterStack" if needed...
            if { ![info exists ProfilerArray(ES0)] } {
                set esi 1
            } else {
                set esi [expr $ProfilerArray(ES0) + 1]
            }
            # Append a "enter clicks" and "enter function name index" to the EnterStack...
            set ProfilerArray(ES0) $esi
            set ProfilerArray(ES$esi) [clock clicks]
            # Note: the above is last thing done so timing start is closest to
            # function operation start as possible.
        } else {
            # Right away stop timing...
            set deltaclicks [clock clicks]
            
            # Do not bother if TimeProfilerDump wiped the ProfilerArray
            # just prior to this "leave"...
            if { [info exists ProfilerArray(ES0)] } {
                # Pull an "enter clicks" off the EnterStack...
                set esi $ProfilerArray(ES0)
                set deltaclicks [expr $deltaclicks - $ProfilerArray(ES$esi)]
                incr esi -1
                set ProfilerArray(ES0) $esi
                
                # Correct for recursion and nesting...
                if { $esi } {
                    # Add our elapsed clicks to the previous stacked values to compensate...
                    for { set fix $esi } { $fix > 0 } { incr fix -1 } {
                        set ProfilerArray(ES$fix) [expr $ProfilerArray(ES$fix) + $deltaclicks]
                    }
                }
                
                # Intialize the delta clicks array if needed...
                if { ![info exists ProfilerArray($fun,0)] } {
                    set cai 1
                } else {
                    set cai [expr $ProfilerArray($fun,0) + 1]
                }
                
                # Add another "delta clicks" reading...
                set ProfilerArray($fun,0) $cai
                set ProfilerArray($fun,$cai) $deltaclicks
            }
        }
    }

    proc TimeProfilerReset {} {
        global ProfilerArray
        array unset ProfilerArray
    }

    proc TimeProfilerGetStatistics {} {
        global ProfilerArray

        set PerfList {}

        if { ![info exists ProfilerArray(ElapsedClicks)] } {
            return [dict create elapsed_ms 0.0 functions $PerfList]
        }
        
        # Stop timing elapsed time and calculate conversion factor for clicks to ms...
        set EndClicks [expr {double([clock clicks]) - $ProfilerArray(ElapsedClicks)}]
        set Endms [expr {double([clock clicks -milliseconds]) - $ProfilerArray(Elapsedms)}]
        if {$EndClicks == 0.0} {
            set msPerClick 0.0
        } else {
            set msPerClick [expr {$Endms / $EndClicks}]
        }
        
        # Visit each function and generate the statistics for it...
        for {set fi 0} {$fi < $ProfilerArray(funcount)} {incr fi} {
            set fun $ProfilerArray($fi)

            if {![info exists ProfilerArray($fun,0)]} {
                continue
            }

            set max -1.0
            set min -1.0
            set ctotal 0.0

            for {set cai 1} {$cai <= $ProfilerArray($fun,0)} {incr cai} {
                set clicks $ProfilerArray($fun,$cai)

                set ctotal [expr {$ctotal + double($clicks)}]

                if {$max < 0 || $clicks > $max} {
                    set max $clicks
                }

                if {$min < 0 || $clicks < $min} {
                    set min $clicks
                }
            }

            set calls   $ProfilerArray($fun,0)
            set avgms   [expr {($ctotal / double($calls)) * $msPerClick}]
            set totalms [expr {$ctotal * $msPerClick}]
            if {$EndClicks == 0.0} {
                set ratio 0.0
            } else {
                set ratio [expr {100.0 * $ctotal / $EndClicks}]
            }
            set maxms   [expr {$max * $msPerClick}]
            set minms   [expr {$min * $msPerClick}]

            lappend PerfList [dict create \
                function $fun \
                calls $calls \
                avgms $avgms \
                maxms $maxms \
                minms $minms \
                totalms $totalms \
                ratio $ratio]
        }

        # Sort the profile data by Ratio...
        set PerfList [lsort -command TimeProfilerCompareRatio $PerfList]

        return [dict create elapsed_ms $Endms functions $PerfList]
    }

    proc TimeProfilerCompareRatio {left right} {
        set leftRatio [dict get $left ratio]
        set rightRatio [dict get $right ratio]

        if {$leftRatio < $rightRatio} {
            return 1
        }
        if {$leftRatio > $rightRatio} {
            return -1
        }
        return 0
    }

    proc TimeProfilerCSVField {value} {
        set escapedValue [string map [list "\"" "\"\""] $value]
        return "\"${escapedValue}\""
    }

    proc TimeProfilerDumpCSV {stats {description "Benchmark"} {filename "TimingDump"}} {
        set fd [open "${filename}.csv" w]

        puts $fd "description,elapsed_ms,function,calls,avg_ms,max_ms,min_ms,total_ms,ratio_percent"
        foreach entry [dict get $stats functions] {
            puts $fd [join [list \
                [TimeProfilerCSVField $description] \
                [format "%.3f" [dict get $stats elapsed_ms]] \
                [TimeProfilerCSVField [dict get $entry function]] \
                [dict get $entry calls] \
                [format "%.6f" [dict get $entry avgms]] \
                [format "%.6f" [dict get $entry maxms]] \
                [format "%.6f" [dict get $entry minms]] \
                [format "%.6f" [dict get $entry totalms]] \
                [format "%.6f" [dict get $entry ratio]]] ","]
        }

        close $fd
    }

    proc TimeProfilerDumpTxt {stats {description "Benchmark"} {filename "TimingDump"}} {
        set fd [open "${filename}.txt" w]
        puts $fd "\n===================================================================="
        puts $fd [format "     T I M I N G  D U M P  <%s>" $description]
        puts $fd [format "\n      Elapsed time: %.0f ms" [dict get $stats elapsed_ms]]
        puts $fd [format "\n      %s" [clock format [clock seconds]]]
        puts $fd "===================================================================="

        foreach entry [dict get $stats functions] {
            puts $fd [format ">>>>> FUNCTION: %s" [dict get $entry function]]
            puts $fd [format "       CALLS: %d" [dict get $entry calls]]
            puts $fd [format "    AVG TIME: %.3f ms" [dict get $entry avgms]]
            puts $fd [format "    MAX TIME: %.3f ms" [dict get $entry maxms]]
            puts $fd [format "    MIN TIME: %.3f ms" [dict get $entry minms]]
            puts $fd [format "  TOTAL TIME: %.3f ms" [dict get $entry totalms]]
            puts $fd [format "       RATIO: %.3f%c\n" [dict get $entry ratio] 37]
        }

        close $fd
    }

    proc TimeProfilerDump {{description "Benchmark"} {filename "TimingDump"}} {
        set stats [TimeProfilerGetStatistics]
        TimeProfilerDumpTxt $stats $description $filename
        TimeProfilerDumpCSV $stats $description $filename
        TimeProfilerReset
    }
    
    #=================================================================
    # Overload "proc" so that functions defined after
    # this point have added trace handlers for entry and exit.
    # [George Peter Staplin]
    #=================================================================
    rename proc _proc
    
    _proc proc {name arglist body} {
                                    #===================================        
                                    # Allow multiple namespace use [JMN]
                                    if { ![string match ::* $name] } {
                                        # Not already an 'absolute' namespace path,
                                        # qualify it so that traces can find it...
                                        set name [uplevel 1 namespace current]::[set name]
                                    }
                                    #===================================
                                    
                                    _proc $name $arglist $body
                                    trace add execution $name enter TimeProfiler
                                    trace add execution $name leave TimeProfiler
                                }
}
