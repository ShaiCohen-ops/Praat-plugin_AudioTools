# ============================================================
# Praat AudioTools - Sound_Duplicator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Duplicates a selected Sound N times, assembles the copies
#   into a single longer Sound with crossfades at every join,
#   and applies a shaping envelope across the full output.
#
#   Envelope types:
#     Linear             -- straight rise, unity sustain, straight fall
#     Cosine             -- half-cosine rise, unity sustain, half-cosine fall
#     Triangle           -- rise to peak over Fade in, then one continuous
#                           linear fall to zero at the end of the file.
#                           Fade out is NOT used by this shape.
#     Arch (symmetric)   -- fixed sin^2 hill spanning the whole output,
#                           zero at both ends, instantaneous peak at the
#                           midpoint. Fade in / Fade out are NOT used.
#     Gentle arch        -- smootherstep rise, unity sustain, smootherstep
#                           fall, both governed by Fade in / Fade out.
#                           Flatter at the corners than Cosine.
#
#   Performance note:
#     Assembly is incremental: one copy in RAM at a time.
#     Envelope is a single vectorised Formula: call.
#     No sample-by-sample loops.
#
# Changelog:
#   1.2 (2026) -- Repetitions is now a natural number. It was `positive`,
#                 so 4.5 built four copies while the duration, the report
#                 and the ENVELOPE were computed from 4.5 - the envelope
#                 ran past the end of the audio and a linear fade-out
#                 stopped at about 0.72 instead of reaching zero. The
#                 envelope is now built from the assembled Sound's own
#                 measured duration, so it cannot disagree with the audio.
#              -- "Gentle arch" split in two. The old curve was a fixed
#                 symmetric sin^2 hill that ignored Fade in / Fade out
#                 entirely; it is preserved unchanged as "Arch (symmetric)"
#                 and honestly labelled. The new "Gentle arch" is what the
#                 description always promised: rise, flat sustain, fall,
#                 driven by the fade percentages. Preset "Long Fade" now
#                 selects it, so its 30%/30% finally do something.
#              -- Triangle reports "not used" for Fade out instead of
#                 displaying a value that never reaches the curve.
#              -- Normalization renamed Peak_normalize_output and turned
#                 OFF by default. It was on, so Peak_level_percent only
#                 described a stage that was then divided back out: a 50%
#                 peak request on a 0.5 source came out at 0.99.
#              -- Crossfade clamping fixed. The 1 ms floor was applied
#                 after the 0.9 x source clamp, so a 0.5 ms source got an
#                 overlap longer than itself and crashed Concatenate with
#                 overlap. The floor is now two samples, the ceiling is
#                 applied last, and both are reported.
#              -- Peak level no longer resets 0 to 100 silently; the field
#                 is `positive` and values above 100% are reported as
#                 amplification.
#              -- Output time domain shifted to start at 0 (with a single
#                 repetition the source's xmin used to survive and the
#                 envelope, which reckons from 0, was misaligned).
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
    natural Number_of_repetitions 4
    comment === Crossfade ===
    positive Crossfade_duration_ms 50
    comment === Overall Envelope ===
    optionmenu Envelope_type: 1
        option Linear
        option Cosine
        option Triangle (Fade out unused)
        option Arch (symmetric, fades unused)
        option Gentle arch (fades + sustain)
    real Fade_in_percent 10
    real Fade_out_percent 15
    positive Peak_level_percent 100
    comment (above 100% amplifies before any normalization)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Peak_normalize_output 0
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
    # v1.2: was 4 (the symmetric arch), which ignored these percentages.
    envelope_type          = 5
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
# Repetitions must be a whole number: the assembly loop can only run an
# integer number of times, so every derived quantity is computed from the
# rounded value and nothing downstream can disagree with the audio.
n = round(number_of_repetitions)
if n < 1
    n = 1
endif
number_of_repetitions = n

# Crossfade. Order matters: the floor is expressed in SAMPLES, and the
# upper clamp is applied LAST so that the overlap is always shorter than
# the source. v1.1 applied a fixed 1 ms floor after the 0.9 x source
# clamp, which on a 0.5 ms source produced an overlap longer than the
# material being overlapped.
if crossfade_duration_ms < 0
    crossfade_duration_ms = 0
endif
xfSec = crossfade_duration_ms / 1000.0
minOverlap = 2 / srcSR
maxOverlap = 0.90 * srcDur

if n > 1 and maxOverlap < minOverlap
    exitScript: "Source is too short to crossfade: " + fixed$(srcDur * 1000, 4) +
    ... " ms is under 3 samples at " + fixed$(srcSR, 0) + " Hz. Use a longer Sound, " +
    ... "or set Number_of_repetitions to 1."
endif

xfRequested_ms = crossfade_duration_ms
xfFloored = 0
xfCeilinged = 0
if xfSec < minOverlap
    xfSec = minOverlap
    xfFloored = 1
endif
if xfSec > maxOverlap
    xfSec = maxOverlap
    xfCeilinged = 1
endif
# Report the value that was actually used, not the one that was asked for.
crossfade_duration_ms = xfSec * 1000.0

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

# Peak level: the form type already rejects zero and negatives, so no
# silent reset to 100% here. Values above 100% are legal and amplify.
peakAmp = peak_level_percent / 100.0

# === Envelope string ===
if envelope_type = 1
    envStr$ = "Linear"
elsif envelope_type = 2
    envStr$ = "Cosine"
elsif envelope_type = 3
    envStr$ = "Triangle"
elsif envelope_type = 4
    envStr$ = "ArchSymmetric"
else
    envStr$ = "GentleArch"
endif

# Which fade fields this shape actually reads
usesFadeIn = 1
usesFadeOut = 1
if envelope_type = 3
    usesFadeOut = 0
elsif envelope_type = 4
    usesFadeIn = 0
    usesFadeOut = 0
endif

# === Predicted output duration (verified against the real one later) ===
predictedDur = n * srcDur - (n - 1) * xfSec

# === Info ===
clearinfo
writeInfoLine:  "=== Sound Duplicator v1.2 ==="
appendInfoLine: "Source:          ", srcName$
appendInfoLine: "Source duration: ", fixed$(srcDur, 4), " s"
appendInfoLine: "Sample rate:     ", srcSR, " Hz"
appendInfoLine: "Channels:        ", srcChannels
appendInfoLine: "Repetitions:     ", n
appendInfoLine: "Crossfade:       ", fixed$(crossfade_duration_ms, 3), " ms"
if xfFloored
    appendInfoLine: "                 (raised from ", fixed$(xfRequested_ms, 3),
    ... " ms to the 2-sample minimum)"
endif
if xfCeilinged
    appendInfoLine: "                 (lowered from ", fixed$(xfRequested_ms, 3),
    ... " ms to 90% of the source)"
endif
appendInfoLine: "Envelope:        ", envStr$
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

# Normalize the time domain. With a single repetition there is no
# concatenation, so a source with xmin <> 0 would otherwise keep its own
# start time while the envelope below reckons x from zero.
selectObject: resultSound
Shift times to: "start time", 0

# === Envelope parameters from the MEASURED duration ===
# Not from the predicted one: this is what kept the v1.1 envelope from
# ending with the audio.
selectObject: resultSound
totalDur = Get total duration

appendInfoLine: "  Done.  Crossfade: ", fixed$(xfSec * 1000, 3), " ms"
appendInfoLine: "  Output duration: ", fixed$(totalDur, 4), " s (predicted ",
... fixed$(predictedDur, 4), " s)"
if abs(totalDur - predictedDur) > 2 / srcSR
    appendInfoLine: "  WARNING: measured and predicted duration differ by more than two samples."
endif

fiSec   = totalDur * fade_in_percent  / 100.0
foSec   = totalDur * fade_out_percent / 100.0
foStart = totalDur - foSec
fallDur = totalDur - fiSec
if fallDur < 1e-9
    fallDur = 1e-9
endif
# Denominators are clamped away from zero so the formula is safe even if
# a branch is evaluated eagerly.
fiDen = max(fiSec, 1e-9)
foDen = max(foSec, 1e-9)

appendInfoLine: "Fade in:         ", fixed$(fade_in_percent, 1), " %  (", fixed$(fiSec, 3), " s)"
if usesFadeOut
    appendInfoLine: "Fade out:        ", fixed$(fade_out_percent, 1), " %  (", fixed$(foSec, 3), " s)"
else
    appendInfoLine: "Fade out:        not used by ", envStr$
endif
if envelope_type = 3
    appendInfoLine: "                 (Triangle falls continuously from the peak to the"
    appendInfoLine: "                  end of the file: ", fixed$(fallDur, 3), " s)"
endif
if envelope_type = 4
    appendInfoLine: "                 (Arch (symmetric) uses neither fade: it is a fixed hill"
    appendInfoLine: "                  over the whole output, peaking at the midpoint.)"
endif
appendInfoLine: "Peak level:      ", fixed$(peak_level_percent, 1), " %"
if peak_level_percent > 100
    appendInfoLine: "                 (above 100% - this amplifies and may clip)"
endif
appendInfoLine: ""

# === Build the envelope shape expression ===
# One string, used for BOTH the audio and the drawn curve, so the panel
# cannot drift away from what was applied.
fi$    = fixed$(fiSec, 9)
fo$    = fixed$(foSec, 9)
fs$    = fixed$(foStart, 9)
td$    = fixed$(totalDur, 9)
fiDen$ = fixed$(fiDen, 12)
foDen$ = fixed$(foDen, 12)
fall$  = fixed$(fallDur, 12)

if envelope_type = 1
    # Linear: straight rise, unity sustain, straight fall
    shape$ = "if x < " + fi$ + " and " + fi$ + " > 0 then x / " + fiDen$ +
    ... " else (if x > " + fs$ + " and " + fo$ + " > 0 then (" + td$ + " - x) / " + foDen$ +
    ... " else 1 fi) fi"

elsif envelope_type = 2
    # Cosine: half-cosine rise, unity sustain, half-cosine fall
    shape$ = "if x < " + fi$ + " and " + fi$ + " > 0 then 0.5 - 0.5 * cos(pi * x / " + fiDen$ +
    ... ") else (if x > " + fs$ + " and " + fo$ + " > 0 then 0.5 - 0.5 * cos(pi * (" + td$ +
    ... " - x) / " + foDen$ + ") else 1 fi) fi"

elsif envelope_type = 3
    # Triangle: linear rise over fiSec, then one continuous linear fall
    # from the peak all the way to zero at totalDur. There is no separate
    # fade-out zone - the fall IS the fade-out, which is why Fade out is
    # reported as unused rather than quietly ignored.
    shape$ = "if x < " + fi$ + " and " + fi$ + " > 0 then x / " + fiDen$ +
    ... " else max(0, 1 - (x - " + fi$ + ") / " + fall$ + ") fi"

elsif envelope_type = 4
    # Arch (symmetric): the v1.1 "Gentle arch" curve, unchanged. A fixed
    # sin^2 hill over the whole output - 50% rise, instantaneous peak,
    # 50% fall - written as 0.5 - 0.5*cos(2*pi*x/T) to avoid Praat
    # operator precedence issues with ^.
    shape$ = "0.5 - 0.5 * cos(2 * pi * x / " + td$ + ")"

else
    # Gentle arch: smootherstep rise, unity sustain, smootherstep fall,
    # both driven by the fade percentages. 6t^5 - 15t^4 + 10t^3 in Horner
    # form (no ^ operator); zero first AND second derivative at both ends,
    # so the corners are flatter than Cosine.
    tin$  = "(x / " + fiDen$ + ")"
    tout$ = "((" + td$ + " - x) / " + foDen$ + ")"
    sIn$  = tin$ + " * " + tin$ + " * " + tin$ + " * (" + tin$ + " * (6 * " + tin$ + " - 15) + 10)"
    sOut$ = tout$ + " * " + tout$ + " * " + tout$ + " * (" + tout$ + " * (6 * " + tout$ + " - 15) + 10)"
    shape$ = "if x < " + fi$ + " and " + fi$ + " > 0 then (" + sIn$ +
    ... ") else (if x > " + fs$ + " and " + fo$ + " > 0 then (" + sOut$ +
    ... ") else 1 fi) fi"
endif

envFormula$ = fixed$(peakAmp, 9) + " * (" + shape$ + ")"

# === Apply overall envelope via single Formula: call ===
appendInfoLine: "[2/3] Applying ", envStr$, " envelope..."

selectObject: resultSound
Formula: "self * (" + envFormula$ + ")"

appendInfoLine: "  Done."

# === Finalize ===
appendInfoLine: "[3/3] Finalizing..."

xfLabel$ = string$(round(crossfade_duration_ms))
outName$ = srcName$ + "_dup" + string$(n) + "_xf" + xfLabel$ + "_" + envStr$

selectObject: resultSound
Rename: outName$

prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if peak_normalize_output = 1
    if prePeak > 0
        Scale peak: 0.99
        normGain = 0.99 / prePeak
    endif
endif
selectObject: resultSound
outPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output:          ", outName$
appendInfoLine: "Duration:        ", fixed$(finalDur, 4), " s"
appendInfoLine: "Repetitions:     ", n
appendInfoLine: "Crossfade:       ", fixed$(crossfade_duration_ms, 3), " ms"
appendInfoLine: "Envelope:        ", envStr$
appendInfoLine: "Peak before normalization: ", fixed$(prePeak, 4)
if peak_normalize_output = 1
    appendInfoLine: "Normalization:   ON  (x", fixed$(normGain, 4), " -> ", fixed$(outPeak, 4), ")"
    appendInfoLine: "                 This is a constant gain over the whole file, so the"
    appendInfoLine: "                 absolute level set by Peak level (", fixed$(peak_level_percent, 0),
    ... "%) does not survive it."
else
    appendInfoLine: "Normalization:   off"
    if outPeak > 1
        appendInfoLine: "                 WARNING: peak exceeds 1.0 and will clip on playback or save."
    endif
endif

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

    envTop = 1.15 * peakAmp
    if peak_normalize_output = 1
        envTop = envTop * normGain
    endif
    Axes: 0, finalDur, -0.05, envTop
    Paint rectangle: "{0.96, 0.96, 0.98}", 0, finalDur, -0.05, envTop

    # Same expression string that was applied to the audio, sampled at
    # 500 Hz and drawn with one C-level call. If normalization ran, the
    # constant is folded in, so this panel is the total applied gain.
    envSR = 500
    if peak_normalize_output = 1 and normGain <> 1
        envDrawFormula$ = fixed$(normGain, 12) + " * (" + envFormula$ + ")"
    else
        envDrawFormula$ = envFormula$
    endif
    envSnd = Create Sound from formula: "env_curve", 1, 0, finalDur, envSR, envDrawFormula$

    selectObject: envSnd
    Colour: "{0.18, 0.52, 0.72}"
    Line width: 2
    Draw: 0, 0, -0.05, envTop, "no", "Curve"
    removeObject: envSnd

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    if usesFadeIn and usesFadeOut
        envCaption$ = envStr$ + " envelope  |  peak: " + fixed$(peak_level_percent, 0) +
        ... "%  |  in: " + fixed$(fade_in_percent, 0) + "%  out: " + fixed$(fade_out_percent, 0) + "%"
    elsif usesFadeIn
        envCaption$ = envStr$ + " envelope  |  peak: " + fixed$(peak_level_percent, 0) +
        ... "%  |  in: " + fixed$(fade_in_percent, 0) + "%  out: not used"
    else
        envCaption$ = envStr$ + " envelope  |  peak: " + fixed$(peak_level_percent, 0) +
        ... "%  |  fades not used by this shape"
    endif
    if peak_normalize_output = 1 and normGain <> 1
        envCaption$ = envCaption$ + "  |  x" + fixed$(normGain, 2) + " norm"
    endif
    Text top: "no", envCaption$

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
        ... + "  |  Crossfade: " + fixed$(crossfade_duration_ms, 2) + " ms"
        ... + "  |  Output: " + fixed$(finalDur, 3) + " s"
        ... + "  |  Peak: " + fixed$(outPeak, 3)
    if usesFadeOut
        fadeText$ = "  |  Fade in: " + fixed$(fade_in_percent, 0) + "%" +
        ... "  |  Fade out: " + fixed$(fade_out_percent, 0) + "%"
    elsif usesFadeIn
        fadeText$ = "  |  Fade in: " + fixed$(fade_in_percent, 0) + "%  |  Fade out: n/a"
    else
        fadeText$ = "  |  Fades: n/a"
    endif
    Text: 0.02, "left", 0.23, "half",
        ... "Envelope: " + envStr$
        ... + fadeText$
        ... + "  |  Peak level: " + fixed$(peak_level_percent, 0) + "%"
        ... + "  |  Norm: " + string$(peak_normalize_output)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

selectObject: resultSound

if play_result = 1
    Play
endif
