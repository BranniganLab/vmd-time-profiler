# VMD Tcl Time Profiler

`vmd-time-profiler` is a GitHub composite action for measuring the execution
time of Tcl procedures inside
[VMD (Visual Molecular Dynamics)](https://www.ks.uiuc.edu/Research/vmd/).

The action loads a user-supplied benchmark script, performs optional warm-up
runs, executes the benchmark repeatedly, and produces:

- a machine-readable CSV report; and
- a human-readable text report.

Procedures called by the benchmark are instrumented automatically. The user
does not need to copy the profiler into the repository being tested.

## Requirements

The action requires:

- a Linux GitHub Actions runner;
- VMD installed and available as the `vmd` command on `PATH`; and
- a Tcl benchmark script that defines a global procedure named
  `RunBenchmark`.

This action does not install VMD. Install VMD in an earlier workflow step or
use a separate VMD setup action.


## User-Supplied Benchmark script

The calling repository supplies one Tcl script. That script must:

1. source the Tcl software being tested;
2. perform any one-time, unmeasured setup; and
3. define a global procedure named `RunBenchmark`.

It must not call `RunBenchmark`, `quit`, or `exit`. The action controls
benchmark execution and VMD termination.

For example:

```tcl
# test_files/benchmark/run_benchmark.tcl

set cwd [file dirname [file normalize [info script]]]

source [file join $cwd <RELATIVE PATH TO CODE YOU WANT TO SOURCE>]

# One-time setup is not included in the measured runs.
mol new [file join $cwd <RELATIVE PATH TO PDB/GRO>]
mol addfile [file join $cwd <RELATIVE PATH TO XTC/DCD>] waitfor all

proc RunBenchmark {} {
    <THE COMMANDS YOU WANT TO PROFILE>
}
```

To access variables inside `RunBenchmark`, declare them and then call them
with `global`, as shown below:

```tcl
# test_files/benchmark/run_benchmark.tcl

set cwd [file dirname [file normalize [info script]]]

source [file join $cwd <RELATIVE PATH TO CODE YOU WANT TO SOURCE>]

# One-time setup is not included in the measured runs.
mol new [file join $cwd <RELATIVE PATH TO PDB/GRO>]
mol addfile [file join $cwd <RELATIVE PATH TO XTC/DCD>] waitfor all

set configPath [file join $cwd <RELATIVE PATH TO CONFIG FILE>]

proc RunBenchmark {} {
    global configPath
    <THE COMMANDS YOU WANT TO PROFILE> $configPath
}
```

### Repeated-run behavior

The action calls the same `RunBenchmark` procedure for every warm-up and
measured repetition. The procedure must therefore be safe to execute more than
once.

If a run modifies global variables, molecule data, selections, or output
files, `RunBenchmark` should reset that state or use independent output names.
Each repetition should perform an equivalent workload.

## Basic usage

The following workflow assumes that VMD has already been added to `PATH`:

```yaml
jobs:
  time-profile:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout repository
        uses: actions/checkout@v6

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y \
            build-essential \
            libx11-dev \
            libglu1-mesa-dev \
            libxi-dev \
            libxext-dev \
            libxmu-dev \
            libjpeg-dev \
            libpng-dev \
            tcl-dev \
            tk-dev \
            python3-dev \
            flex \
            bison \
            git

      - name: Set up VMD
        id: setup-vmd
        uses: BranniganLab/setup-vmd@ae464c279176585de8a94bd7c7bd11eee4da5783
        with:
          github-app-id: ${{ secrets.GH_APP_ID }}
          github-app-private-key: ${{ secrets.GH_APP_PRIVATE_KEY }}

      - name: Run time profiler
        id: profiler
        uses: BranniganLab/vmd-time-profiler@v2
        with:
          script: test_files/benchmark/run_benchmark.tcl
          repetitions: 10
          warmup-runs: 1

      - name: Upload timing reports
        uses: actions/upload-artifact@v6
        with:
          name: vmd-timing-results
          path: |
            ${{ steps.profiler.outputs.csv-file }}
            ${{ steps.profiler.outputs.txt-file }}
          if-no-files-found: error
```

After the workflow completes, the reports are available from the
**Artifacts** section of the workflow-run summary.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `script` | Yes | — | Path to the benchmark Tcl script, relative to `working-directory`, or an absolute path. |
| `working-directory` | No | `.` | Path to the software checkout, relative to `$GITHUB_WORKSPACE`, or an absolute path. |
| `repetitions` | No | `10` | Number of measured calls to `RunBenchmark`. Must be a positive integer. |
| `warmup-runs` | No | `1` | Number of unmeasured calls made before profiling is reset. Must be a non-negative integer. |
| `output` | No | `timing_results` | Output path without an extension. Relative paths are resolved beneath `$GITHUB_WORKSPACE`. |

## Outputs

| Output | Description |
| --- | --- |
| `csv-file` | Absolute path to the generated CSV report. |
| `txt-file` | Absolute path to the generated human-readable report. |

Action outputs are file paths only. They do not persist files after the job
ends. Use `actions/upload-artifact`, as shown above, to make the reports
downloadable.

## Timing reports

### CSV report

The CSV file contains one row for each Tcl procedure called during the measured
runs:

```text
description,elapsed_ms,function,calls,avg_ms,max_ms,min_ms,total_ms,ratio_percent
```

| Column | Meaning |
| --- | --- |
| `description` | Name of the benchmark script. |
| `elapsed_ms` | Total elapsed time across all measured repetitions. |
| `function` | Fully qualified Tcl procedure name. |
| `calls` | Total number of calls across all measured repetitions. |
| `avg_ms` | Mean duration of one call. |
| `max_ms` | Longest individual call. |
| `min_ms` | Shortest individual call. |
| `total_ms` | Cumulative time spent in the procedure. |
| `ratio_percent` | Percentage of total elapsed time spent in the procedure. |

### Text report

The text report contains the same procedure-level statistics in a format
intended for direct inspection.

### Exclusive timing

Procedure timings are exclusive. If `outer` calls `inner`, time attributed to
`inner` is removed from `outer`. This prevents the same execution time from
being counted for both procedures.

The profiler measures Tcl procedures defined after the profiler is loaded.
This includes procedures defined while the benchmark script sources the
software under test. Built-in VMD commands and compiled functions are reflected
in the time of the Tcl procedure that calls them, but they do not receive
independent rows unless they are wrapped by a Tcl procedure.

## Error handling

The driver validates:

- the profiler and benchmark paths;
- the repetition and warm-up counts;
- successful loading of the profiler;
- availability of the profiler commands;
- successful loading of the benchmark script;
- definition of `::RunBenchmark`;
- completion of warm-up and measured runs; and
- successful report generation.

When VMD encounters an error, the driver writes
`<output>.error.txt`. The composite action checks this file because VMD does not
reliably propagate Tcl failures through its process exit status.

Common errors include:

### `RunBenchmark` was not defined

Ensure the benchmark script contains:

```tcl
proc RunBenchmark {} {
    # Measured commands
}
```

### A global variable is unavailable

Declare top-level variables inside the procedure:

```tcl
set benchmarkConfig "test_files/config.tcl"

proc RunBenchmark {} {
    global benchmarkConfig
    run_analysis $benchmarkConfig
}
```

### A relative file cannot be found

Build paths relative to the benchmark script rather than assuming a particular
current directory:

```tcl
set benchmarkDirectory \
    [file dirname [file normalize [info script]]]
```

### VMD is unavailable

The action requires:

```bash
command -v vmd
```

to succeed. Install VMD or add its binary directory to `PATH` before invoking
the profiler.


## Attribution

The Tcl profiler is based on work by Barney Blankenship and George Peter
Staplin and was adapted for continuous-integration use by Jesse W. Sandberg.
