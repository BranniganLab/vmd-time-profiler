set userScript [file normalize [lindex $argv 0]]
set repetitions [lindex $argv 1]
set warmupRuns [lindex $argv 2]
set outputName [lindex $argv 3]

if {![string is integer -strict $repetitions] || $repetitions < 1} {
    puts stderr "repetitions must be a positive integer"
    exit 1
}

if {![string is integer -strict $warmupRuns] || $warmupRuns < 0} {
    puts stderr "warmup-runs must be a non-negative integer"
    exit 1
}

proc ReportProfilerError {outputName message} {
    set errorFile "${outputName}.error.txt"

    set channel [open $errorFile w]
    puts $channel $message
    close $channel

    puts stderr "TIME_PROFILER_ERROR: $message"
    quit
}

set TimeProfilerMode 1

set actionDirectory [file dirname [file normalize [info script]]]
set profilerFile [file join $actionDirectory tcl_profiler.tcl]

# The user script sources their software and defines RunBenchmark.
set sourceStatus [catch {
    source $userScript
} sourceMessage sourceOptions]

if {$sourceStatus != 0} {
    set details $sourceMessage

    if {[dict exists $sourceOptions -errorinfo]} {
        append details "\n" [dict get $sourceOptions -errorinfo]
    }

    ReportProfilerError $outputName \
        "Failed to source benchmark script:\n$details"
}

if {[llength [info commands ::RunBenchmark]] == 0} {
    ReportProfilerError $outputName \
        "The benchmark script '$userScript' does not define a global RunBenchmark procedure."
}

if {[llength [info commands RunBenchmark]] == 0} {
    puts stderr \
        "The benchmark script must define a procedure named RunBenchmark."
    exit 1
}

# Warm-up calls are discarded.
for {set run 0} {$run < $warmupRuns} {incr run} {
    RunBenchmark
}

TimeProfilerReset

set status [catch {
    for {set run 0} {$run < $repetitions} {incr run} {
        RunBenchmark
    }
} result options]

TimeProfilerDump [file tail $userScript] $outputName

if {$status != 0} {
    puts stderr "The benchmark failed:"
    puts stderr $result
    puts stderr [dict get $options -errorinfo]
    exit 1
}

quit