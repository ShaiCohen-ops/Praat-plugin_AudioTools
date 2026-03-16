# ============================================================
# Praat AudioTools - Sound_Duplicator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Duplicates a selected Sound N times, assembles the copies
#   into a single longer Sound with crossfades at every join,
#   and applies a shaping envelope across the full output.
#
#   Envelope types:
#     Linear      -- straight rise and fall
#     Cosine      -- smooth curved fade in/out
#     Triangle    -- rise to peak then continuous linear fall
#     Gentle arch -- cosine rise, flat sustain, cosine fall
#
#   Performance note:
#     Assembly is incremental: one copy in RAM at a time.
#     Envelope is a single vectorised Formula: call.
#     No sample-by-sample loops.
#
# Changelog:
#   1.1 (2026) -- rewritten for speed
#   1.0 (2026) -- initial release
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

srcSound = selected("Sound")
srcName$ = selected$("Sound")

# === Form ===
form Sound Duplicator
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Stutter
        option Echo Decay
        option Swell
        option Tight Loop
        option Pulse Burst
        option Long Fade
    comment === Duplication ===
    positive Number_of_repetitions 4
    comment === Crossfade ===
    positive Crossfade_duration_ms 50
    comment === Overall Envelope ===
    optionmenu Envelope_type: 1
        option Linear
        option Cosine
        option Triangle
        option Gentle arch
    real Fade_in_percent 10
    real Fade_out_percent 15
    real Peak_level_percent 100
    comment === Output ===
    boolean Draw_visualization 1
    boolean Normalize_output 1
    boolean Play_result 1
endform

# === Apply presets ===
if preset = 2
    number_of_repetitions = 8
    crossfade_duration_ms  = 10
    envelope_type          = 1
    fade_in_percent        = 0
    fade_out_percent       = 0
    peak_level_percent     = 100
elsif preset = 3
    number_of_repetitions = 5
    crossfade_duration_ms  = 80
    envelope_type          = 1
    fade_in_percent        = 0
    fade_out_percent       = 60
    peak_level_percent     = 100
elsif preset = 4
    number_of_repetitions = 4
    crossfade_duration_ms  = 120
    envelope_type          = 2
    fade_in_percent        = 25
    fade_out_percent       = 25
    peak_level_percent     = 100
elsif preset = 5
    number_of_repetitions = 6
    crossfade_duration_ms  = 200
    envelope_type          = 1
    fade_in_percent        = 0
    fade_out_percent       = 0
    peak_level_percent     = 100
elsif preset = 6
    number_of_repetitions = 8
    crossfade_duration_ms  = 20
    envelope_type          = 3
    fade_in_percent        = 10
    fade_out_percent       = 10
    peak_level_percent     = 100
elsif preset = 7
    number_of_repetitions = 3
    crossfade_duration_ms  = 150
    envelope_type          = 4
    fade_in_percent        = 30
    fade_out_percent       = 30
    peak_level_percent     = 100
endif

# === Read source properties ===
selectObject: srcSound
srcDur      = Get total duration
srcSR       = Get sampling frequency
srcChannels = Get number of channels

# === Validate settings ===
if number_of_repetitions < 1
    number_of_repetitions = 1
endif
n = number_of_repetitions

if crossfade_duration_ms < 0
    crossfade_duration_ms = 0
endif
xfSec = crossfade_duration_ms / 1000.0
if xfSec > srcDur * 0.90
    xfSec = srcDur * 0.90
    crossfade_duration_ms = xfSec * 1000.0
endif
if xfSec < 0.001
    xfSec = 0.001
endif

if fade_in_percent < 0
    fade_in_percent = 0
endif
if fade_in_percent > 100
    fade_in_percent = 100
endif
if fade_out_percent < 0
    fade_out_percent = 0
endif
if fade_out_percent > 100
    fade_out_percent = 100
endif
if fade_in_percent + fade_out_percent > 100
    fade_out_percent = 100 - fade_in_percent
endif
if peak_level_percent <= 0
    peak_level_percent = 100
endif
peakAmp = peak_level_percent / 100.0

# === Envelope string ===
if envelope_type = 1
    envStr$ = "Linear"
elsif envelope_type = 2
    envStr$ = "Cosine"
elsif envelope_type = 3
    envStr$ = "Triangle"
else
    envStr$ = "GentleArch"
endif

# === Calculate output duration ===
totalDur    = n * srcDur - (n - 1) * xfSec
fiSec       = totalDur * fade_in_percent  / 100.0
foSec       = totalDur * fade_out_percent / 100.0
foStart     = totalDur - foSec
sustainDur  = totalDur - fiSec - foSec
if sustainDur < 0
    sustainDur = 0
endif

# === Info ===
clearinfo
writeInfoLine:  "=== Sound Duplicator v1.1 ==="
appendInfoLine: "Source:          ", srcName$
appendInfoLine: "Source duration: ", fixed$(srcDur, 4), " s"
appendInfoLine: "Sample rate:     ", srcSR, " Hz"
appendInfoLine: "Channels:        ", srcChannels
appendInfoLine: "Repetitions:     ", n
appendInfoLine: "Crossfade:       ", fixed$(crossfade_duration_ms, 1), " ms"
appendInfoLine: "Output duration: ", fixed$(totalDur, 4), " s"
appendInfoLine: "Envelope:        ", envStr$
appendInfoLine: "Fade in:         ", fixed$(fade_in_percent, 1), " %  (", fixed$(fiSec, 3), " s)"
appendInfoLine: "Fade out:        ", fixed$(fade_out_percent, 1), " %  (", fixed$(foSec, 3), " s)"
appendInfoLine: "Peak level:      ", fixed$(peak_level_percent, 1), " %"
appendInfoLine: ""

# === Build duplicated sound ===
# Incremental assembly: keep only 2 sounds in RAM at a time.
# Each iteration: grow result by one copy then free the copy.
# Avoids allocating all N copies simultaneously.
appendInfoLine: "[1/3] Building ", n, " copies (incremental)..."

selectObject: srcSound
resultSound = Copy: "dup_tmp"

for rep from 2 to n
    selectObject: srcSound
    nextCopy = Copy: "dup_next"
    oldResult = resultSound
    selectObject: oldResult
    plusObject: nextCopy
    Concatenate with overlap: xfSec
    resultSound = selected("Sound")
    removeObject: oldResult, nextCopy
    appendInfo: "."
endfor

appendInfoLine: ""
appendInfoLine: "  Done.  Crossfade: ", fixed$(xfSec * 1000, 1), " ms"

# === Apply overall envelope via single Formula: call ===
# x is time in seconds from start of the output sound.
# All parameters are interpolated into the formula string.
appendInfoLine: "[2/3] Applying ", envStr$, " envelope..."

selectObject: resultSound

if envelope_type = 1
    Formula: "self * 'peakAmp' * (if x < 'fiSec' and 'fiSec' > 0 then x / 'fiSec' else (if x > 'foStart' and 'foSec' > 0 then ('totalDur' - x) / 'foSec' else 1 fi) fi)"

elsif envelope_type = 2
    Formula: "self * 'peakAmp' * (if x < 'fiSec' and 'fiSec' > 0 then 0.5 - 0.5 * cos(pi * x / 'fiSec') else (if x > 'foStart' and 'foSec' > 0 then 0.5 - 0.5 * cos(pi * ('totalDur' - x) / 'foSec') else 1 fi) fi)"

elsif envelope_type = 3
    # Triangle: linear rise over fiSec, then continuous linear fall
    # from peak at fiSec all the way to zero at totalDur.
    # No separate fadeout zone -- the fall IS the fadeout.
    fallDur = totalDur - fiSec
    if fallDur < 0.001
        fallDur = 0.001
    endif
    Formula: "self * 'peakAmp' * (if x < 'fiSec' and 'fiSec' > 0 then x / 'fiSec' else (if 'fallDur' > 0 then max(0, 1 - (x - 'fiSec') / 'fallDur') else 1 fi) fi)"

else
    # Gentle arch: smooth hill peaking at the midpoint, zero at both ends.
    # Uses 0.5 - 0.5*cos(2*pi*x/T) which equals sin^2(pi*x/T) but avoids
    # Praat operator precedence issues with the ^ exponent.
    Formula: "self * 'peakAmp' * (0.5 - 0.5 * cos(2 * pi * x / 'totalDur'))"
endif

appendInfoLine: "  Done."

# === Finalize ===
appendInfoLine: "[3/3] Finalizing..."

xfLabel$ = string$(round(crossfade_duration_ms))
outName$ = srcName$ + "_dup" + string$(n) + "_xf" + xfLabel$ + "_" + envStr$

selectObject: resultSound
Rename: outName$

if normalize_output = 1
    Scale peak: 0.99
    appendInfoLine: "  Normalized to 0.99 peak."
endif

selectObject: resultSound
finalDur = Get total duration

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:          ", outName$
appendInfoLine: "Duration:        ", fixed$(finalDur, 4), " s"
appendInfoLine: "Repetitions:     ", n
appendInfoLine: "Crossfade:       ", fixed$(crossfade_duration_ms, 1), " ms"
appendInfoLine: "Envelope:        ", envStr$
appendInfoLine: "Normalized:      ", normalize_output

# === Visualization ===
if draw_visualization = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 7.5

    # ---- Title ----
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.62, "half", "##Sound Duplicator##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -1.15, "half",
        ... srcName$ + "  x" + string$(n)
        ... + "  |  xfade: " + fixed$(crossfade_duration_ms, 1) + " ms"
        ... + "  |  env: " + envStr$
        ... + "  |  out: " + fixed$(finalDur, 2) + " s"

    # ---- Source waveform ----
    Select outer viewport: 0, 8, 0.55, 1.80
    Select inner viewport: 0.6, 7.7, 0.62, 1.73
    selectObject: srcSound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Source"
    Text top: "no", fixed$(srcDur, 3) + " s  (" + string$(srcChannels) + "ch)"

    # ---- Output waveform ----
    Select outer viewport: 0, 8, 1.85, 3.10
    Select inner viewport: 0.6, 7.7, 1.92, 3.03
    selectObject: resultSound
    Colour: "{0.18, 0.52, 0.72}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    # Crossfade boundary markers
    Colour: "{0.80, 0.35, 0.15}"
    Line width: 3
    selectObject: resultSound
    mn = Get minimum: 0, 0, "None"
    mx = Get maximum: 0, 0, "None"
    if mx - mn < 0.001
        mx =  0.5
        mn = -0.5
    endif
    Axes: 0, finalDur, mn, mx
    for rep from 1 to n - 1
        xBound = rep * srcDur - rep * xfSec
        Draw line: xBound, mn, xBound, mx
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    Text top: "no", string$(n) + " copies  |  orange lines = crossfade boundaries"

    # ---- Envelope curve ----
    Select outer viewport: 0, 8, 3.18, 4.18
    Select inner viewport: 0.6, 7.7, 3.25, 4.11
    Axes: 0, finalDur, -0.05, 1.15
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, finalDur, -0.05, 1.15

    # Create a tiny 100 Hz Sound whose samples encode the envelope shape.
    # Drawing it with Draw: is a single C-level call -- no Praat loop.
    envSR  = 500
    fallDurViz = finalDur - fiSec
    if fallDurViz < 0.001
        fallDurViz = 0.001
    endif
    envSnd = Create Sound from formula: "env_curve", 1, 0, finalDur, envSR,
        ... "(if 'envelope_type' = 4 then "
        ... +   "0.5 - 0.5 * cos(2 * pi * x / 'finalDur') "
        ... + "else (if 'envelope_type' = 3 then "
        ... +   "(if x < 'fiSec' and 'fiSec' > 0 then x / 'fiSec' "
        ... +   "else max(0, 1 - (x - 'fiSec') / 'fallDurViz') fi) "
        ... + "else (if x < 'fiSec' and 'fiSec' > 0 then "
        ... +   "(if 'envelope_type' = 2 "
        ... +     "then 0.5 - 0.5 * cos(pi * x / 'fiSec') "
        ... +     "else x / 'fiSec' fi) "
        ... +   "else (if x > 'foStart' and 'foSec' > 0 then "
        ... +     "(if 'envelope_type' = 2 "
        ... +       "then 0.5 - 0.5 * cos(pi * ('finalDur' - x) / 'foSec') "
        ... +       "else ('finalDur' - x) / 'foSec' fi) "
        ... +   "else 1 fi) fi) fi) fi) * 'peakAmp'"

    selectObject: envSnd
    Colour: "{0.18, 0.52, 0.72}"
    Line width: 2
    Draw: 0, 0, -0.05, 1.15 * peakAmp, "no", "Curve"
    removeObject: envSnd

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    Text top: "no", envStr$ + " envelope  |  peak: " + fixed$(peak_level_percent, 0) + "%  |  in: " + fixed$(fade_in_percent, 0) + "%  out: " + fixed$(fade_out_percent, 0) + "%"

    # ---- Summary panel ----
    Select outer viewport: 0, 8, 4.25, 5.35
    Select inner viewport: 0.6, 7.7, 4.32, 5.28
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.93, 0.93, 0.93}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.87, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.65, "half",
        ... "Source: " + srcName$
        ... + "  |  " + fixed$(srcDur, 3) + " s"
        ... + "  |  " + string$(srcChannels) + " ch"
        ... + "  |  " + string$(srcSR) + " Hz"
    Text: 0.02, "left", 0.44, "half",
        ... "Copies: " + string$(n)
        ... + "  |  Crossfade: " + fixed$(crossfade_duration_ms, 1) + " ms"
        ... + "  |  Output: " + fixed$(finalDur, 3) + " s"
    Text: 0.02, "left", 0.23, "half",
        ... "Envelope: " + envStr$
        ... + "  |  Fade in: " + fixed$(fade_in_percent, 0) + "%"
        ... + "  |  Fade out: " + fixed$(fade_out_percent, 0) + "%"
        ... + "  |  Peak: " + fixed$(peak_level_percent, 0) + "%"
        ... + "  |  Norm: " + string$(normalize_output)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

selectObject: resultSound

if play_result = 1
    Play
endif
