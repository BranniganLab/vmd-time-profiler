# Driver used by the VMD time-profiler GitHub Action.
#
# Expected arguments:
#   0: Absolute path to tcl_profiler.tcl
#   1: Absolute path to the user-supplied benchmark script
#   2: Number of measured repetitions
#   3: Number of unmeasured warm-up runs
#   4: Absolute output path without a file extension

proc ReportProfilerError {outputName message} {
    set errorFile "${outputName}.error.txt"

    if {[catch {
        set channel [open $errorFile w]
        puts $channel $message
        close $channel
    } writeMessage]} {
        puts stderr \
            "TIME_PROFILER_ERROR: Could not write '$errorFile': $writeMessage"
    }

    puts stderr "TIME_PROFILER_ERROR: $message"
    quit
}

proc FormatCaughtError {message options} {
    if {[dict exists $options -errorinfo]} {
        return "$message\n[dict get $options -errorinfo]"
    }
    return $message
}

if {[llength $argv] != 5} {
    puts stderr \
        "TIME_PROFILER_ERROR: Expected 5 arguments, received [llength $argv]."
    quit
}

set profilerFile [file normalize [lindex $argv 0]]
set userScript [file normalize [lindex $argv 1]]
set repetitions [lindex $argv 2]
set warmupRuns [lindex $argv 3]
set outputName [file normalize [lindex $argv 4]]

# Do not allow an error file from a previous invocation to affect this run.
file delete -force "${outputName}.error.txt"

if {![file isfile $profilerFile]} {
    ReportProfilerError $outputName \
        "Profiler file not found: $profilerFile"
}

if {![file isfile $userScript]} {
    ReportProfilerError $outputName \
        "Benchmark script not found: $userScript"
}

if {![string is integer -strict $repetitions] || $repetitions < 1} {
    ReportProfilerError $outputName \
        "repetitions must be a positive integer; received '$repetitions'."
}

if {![string is integer -strict $warmupRuns] || $warmupRuns < 0} {
    ReportProfilerError $outputName \
        "warmup-runs must be a non-negative integer; received '$warmupRuns'."
}

set ::TimeProfilerMode 1
set profilerStatus [catch {
    source $profilerFile
} profilerMessage profilerOptions]

if {$profilerStatus != 0} {
    ReportProfilerError $outputName \
        "Failed to source profiler:\n[FormatCaughtError \
            $profilerMessage $profilerOptions]"
}

foreach requiredCommand {
    ::TimeProfilerReset
    ::TimeProfilerDump
} {
    if {[llength [info commands $requiredCommand]] == 0} {
        ReportProfilerError $outputName \
            "The profiler did not define $requiredCommand."
    }
}

# The user script sources the software under test, performs one-time setup,
# and defines a global RunBenchmark procedure. It must not call quit or exit.
set sourceStatus [catch {
    source $userScript
} sourceMessage sourceOptions]

if {$sourceStatus != 0} {
    ReportProfilerError $outputName \
        "Failed to source benchmark script:\n[FormatCaughtError \
            $sourceMessage $sourceOptions]"
}

if {[llength [info commands ::RunBenchmark]] == 0} {
    ReportProfilerError $outputName \
        "The benchmark script '$userScript' did not define ::RunBenchmark."
}

# Warm-up runs are intentionally discarded.
set warmupStatus [catch {
    for {set run 0} {$run < $warmupRuns} {incr run} {
        ::RunBenchmark
    }
} warmupMessage warmupOptions]

if {$warmupStatus != 0} {
    ReportProfilerError $outputName \
        "A warm-up run failed:\n[FormatCaughtError \
            $warmupMessage $warmupOptions]"
}

::TimeProfilerReset

set benchmarkStatus [catch {
    for {set run 0} {$run < $repetitions} {incr run} {
        ::RunBenchmark
    }
} benchmarkMessage benchmarkOptions]

# Write partial profiling data when a measured run fails. This can help locate
# the procedure that failed, while the error file still makes the action fail.
set dumpStatus [catch {
    ::TimeProfilerDump [file tail $userScript] $outputName
} dumpMessage dumpOptions]

if {$benchmarkStatus != 0} {
    ReportProfilerError $outputName \
        "A measured benchmark run failed:\n[FormatCaughtError \
            $benchmarkMessage $benchmarkOptions]"
}

if {$dumpStatus != 0} {
    ReportProfilerError $outputName \
        "Failed to write profiler output:\n[FormatCaughtError \
            $dumpMessage $dumpOptions]"
}

quit
