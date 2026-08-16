# ============================================================
# Praat AudioTools - Bell_curve_envelope.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026) - Process-faithful visualization + branch closure
#
# Changelog v0.4:
#   - MUSICAL PRIORITY: preserves the v0.3 pristine-source dual-read colour
#     transform. The creative sample-index remapping remains nearest-neighbour;
#     it is part of the established sound rather than silently replaced by a
#     cleaner resampler.
#   - QUALITY FIX: when either read reaches the end of the source before the
#     output ends, that branch now closes over the user Edge fade interval
#     instead of disappearing at one sample. This removes an avoidable click
#     while changing only a few milliseconds around the internal read boundary.
#   - DOCUMENTATION: calls the operation what it is: two sample-index time
#     reads from the pristine source. For a stationary sinusoid the approximate
#     pitch mapping is f -> f/L and f -> H*f; this is not a frequency-domain
#     filter.
#   - VISUALIZATION: source-read geometry -> exact effective bell envelope ->
#     measured source/colour spectra -> measured before/after waveform. Each
#     panel states the law or measurement it is meant to demonstrate.
#   - FORM: kept direct because there are only a few meaningful controls.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creates a colour transform from TWO sample-index reads of the ORIGINAL
#   signal, then shapes that transform with a Gaussian bell envelope. The
#   exact discrete read law is approximately:
#       i_low  = round(col / L)
#       i_high = round(col * H)
#       y0[col] = x[i_low] - x[i_high]
#   with out-of-range reads omitted. For a stationary sinusoid this behaves
#   approximately as f -> f/L and f -> H*f. It is a time-read transform, not
#   a frequency-domain filter.
#
#   The v0.3 pristine-source behaviour is preserved. v0.4 only smooths an
#   internal branch ending when a fast read reaches the source end early (or
#   a custom slow factor < 1 does the same), preventing an avoidable click.
#   The final bell is exp(-((t-mu)/r)^2), where r = duration / Bell_width,
#   multiplied by the short raised-cosine edge closures.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Bell Curve Envelope v0.4
    optionmenu Preset: 1
        option Custom
        option Narrow Bell
        option Wide Bell
        option Low Freq Emphasis
        option High Freq Emphasis
        option Bright Grain
        option Dark Grain
        option Metallic Bell
        option Soft Resonance
    comment === Dual-read colour transform ===
    positive Low_freq_factor 1.1
    positive High_freq_factor 1.1
    comment (stationary tone: low read ~ f/L; high read ~ H*f)
    comment === Bell Envelope ===
    positive Bell_width 4
    comment (higher=narrower, lower=wider)
    real Bell_center 0.5
    comment (0=start, 0.5=middle, 1=end)
    positive Edge_fade_ms 5
    comment (raised-cosine fade closing the envelope edges)
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Narrow Bell
    bell_width = 6
    bell_center = 0.5
    low_freq_factor = 1.1
    high_freq_factor = 1.1
    presetName$ = "NarrowBell"
elsif preset = 3
    # Wide Bell
    bell_width = 2
    bell_center = 0.5
    low_freq_factor = 1.1
    high_freq_factor = 1.1
    presetName$ = "WideBell"
elsif preset = 4
    # Low Freq Emphasis
    bell_width = 4
    bell_center = 0.5
    low_freq_factor = 1.5
    high_freq_factor = 1.0
    presetName$ = "LowEmphasis"
elsif preset = 5
    # High Freq Emphasis
    bell_width = 4
    bell_center = 0.5
    low_freq_factor = 1.0
    high_freq_factor = 1.5
    presetName$ = "HighEmphasis"
elsif preset = 6
    # Bright Grain
    bell_width = 8
    bell_center = 0.5
    low_freq_factor = 1.0
    high_freq_factor = 1.3
    presetName$ = "BrightGrain"
elsif preset = 7
    # Dark Grain
    bell_width = 8
    bell_center = 0.5
    low_freq_factor = 1.3
    high_freq_factor = 1.0
    presetName$ = "DarkGrain"
elsif preset = 8
    # Metallic Bell
    bell_width = 5
    bell_center = 0.5
    low_freq_factor = 1.2
    high_freq_factor = 1.2
    presetName$ = "MetallicBell"
elsif preset = 9
    # Soft Resonance
    bell_width = 2.5
    bell_center = 0.5
    low_freq_factor = 1.05
    high_freq_factor = 1.05
    presetName$ = "SoftResonance"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: originalID
duration = Get total duration
sampleRate = Get sampling frequency

if bell_center < 0 or bell_center > 1
    exitScript: "Bell center must be between 0 and 1."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be > 0 and <= 1."
endif

# Calculate envelope parameters
centerTime = duration * bell_center
# legacy variable name: sigma is the e^-1 radius r, not PDF standard deviation
sigma = duration / bell_width
fade_s = edge_fade_ms / 1000
if fade_s > duration / 2
    fade_s = duration / 2
endif

clearinfo
writeInfoLine: "=== Bell Curve Envelope v0.4 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Low freq factor: ", low_freq_factor
appendInfoLine: "High freq factor: ", high_freq_factor
appendInfoLine: "Bell center: ", fixed$(bell_center * 100, 0), "%"
appendInfoLine: "Bell width: ", bell_width
appendInfoLine: "Edge fade: ", fixed$(fade_s * 1000, 1), " ms"
appendInfoLine: ""

# ============================================================
# PROCESS
# ============================================================

appendInfo: "Processing..."

selectObject: originalID
workingID = Copy: originalName$ + "_bell_" + presetName$

# Build formula strings
lowStr$ = fixed$(low_freq_factor, 8)
highStr$ = fixed$(high_freq_factor, 8)
centerStr$ = fixed$(bell_center, 8)
widthStr$ = fixed$(bell_width, 8)

# A read can reach the source end before the requested output duration:
#   low read  round(col/L) does so only when L < 1
#   high read round(col*H) does so only when H > 1
# Close ONLY that branch over the same short raised-cosine interval used at
# the file edges. This removes a one-sample disappearance without redesigning
# the established nearest-neighbour colour transform.
lowEnd = duration
if low_freq_factor < 1
    lowEnd = duration * low_freq_factor
endif
highEnd = duration
if high_freq_factor > 1
    highEnd = duration / high_freq_factor
endif
lowBranchFade = min(fade_s, lowEnd / 2)
highBranchFade = min(fade_s, highEnd / 2)

if lowEnd < duration - 0.5 / sampleRate
    lowEndStr$ = fixed$(lowEnd, 10)
    lowFadeStr$ = fixed$(lowBranchFade, 10)
    lowGate$ = "(if (x-xmin) < (" + lowEndStr$ + "-" + lowFadeStr$ + ") then 1 else if (x-xmin) <= " + lowEndStr$ + " then 0.5 + 0.5*cos(pi*((x-xmin)-(" + lowEndStr$ + "-" + lowFadeStr$ + "))/" + lowFadeStr$ + ") else 0 fi fi)"
else
    lowGate$ = "1"
endif

if highEnd < duration - 0.5 / sampleRate
    highEndStr$ = fixed$(highEnd, 10)
    highFadeStr$ = fixed$(highBranchFade, 10)
    highGate$ = "(if (x-xmin) < (" + highEndStr$ + "-" + highFadeStr$ + ") then 1 else if (x-xmin) <= " + highEndStr$ + " then 0.5 + 0.5*cos(pi*((x-xmin)-(" + highEndStr$ + "-" + highFadeStr$ + "))/" + highFadeStr$ + ") else 0 fi fi)"
else
    highGate$ = "1"
endif

# Dual pristine-source sample reads. The nearest-neighbour index law is kept
# deliberately: it is part of this small tool's colour and was already made
# explicit in v0.3 when the accidental in-place feedback smear was removed.
origStr$ = string$(originalID)
selectObject: workingID
Formula: "((if round(col / " + lowStr$ + ") >= 1 and round(col / " + lowStr$ + ") <= ncol then object[" + origStr$ + ", row, round(col / " + lowStr$ + ")] else 0 fi) * " + lowGate$ + ") - ((if round(col * " + highStr$ + ") >= 1 and round(col * " + highStr$ + ") <= ncol then object[" + origStr$ + ", row, round(col * " + highStr$ + ")] else 0 fi) * " + highGate$ + ")"

# Keep a visualization-only copy BEFORE the bell. It never enters the audio path.
if draw_visualization
    colourVizID = Copy: "bell_colour_stage"
endif

# Apply the bell law exactly as documented. Note that r=duration/Bell_width is
# an e^-1 radius, not the statistical sigma of a normalized Gaussian PDF.
selectObject: workingID
Formula: "self * exp(-((x - (xmin + (xmax - xmin) * " + centerStr$ + ")) / ((xmax - xmin) / " + widthStr$ + "))^2)"

# Close the FILE edges: the Gaussian itself never reaches exactly zero.
fadeStr$ = fixed$(fade_s, 8)
selectObject: workingID
Formula: "self * (if x - xmin < " + fadeStr$ + " then 0.5 - 0.5 * cos(pi * (x - xmin) / " + fadeStr$ + ") else 1 fi) * (if xmax - x < " + fadeStr$ + " then 0.5 - 0.5 * cos(pi * (xmax - x) / " + fadeStr$ + ") else 1 fi)"

# Scale only when there is something to scale (L=H=1 intentionally cancels).
selectObject: workingID
preScalePeak = Get absolute extremum: 0, 0, "None"
if preScalePeak > 1e-12
    Scale peak: scale_peak
endif

appendInfoLine: " done"

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing process visualization..."

    # Analysis objects. colourVizID is the dual-read transform BEFORE the bell.
    selectObject: originalID
    drySpecID = To Spectrum: "yes"
    selectObject: colourVizID
    colourSpecID = To Spectrum: "yes"

    # Measured source and output amplitudes on one common waveform scale.
    selectObject: originalID
    sourcePeak = Get absolute extremum: 0, 0, "None"
    sourceRms = Get root-mean-square: 0, 0
    selectObject: workingID
    outPeak = Get absolute extremum: 0, 0, "None"
    outRms = Get root-mean-square: 0, 0
    waveRange = 1.05 * max(sourcePeak, outPeak)
    if waveRange < 1e-6
        waveRange = 1
    endif

    # Strongest measured dry spectral region and strongest colour-stage region.
    vizFreqMax = min(sampleRate / 2, 16000)
    dryPeakDb = -1000
    dryPeakHz = 0
    colourPeakDb = -1000
    colourPeakHz = 0
    nProbe = 500
    for q from 1 to nProbe
        fLoP = vizFreqMax * (q - 1) / nProbe
        fHiP = vizFreqMax * q / nProbe
        selectObject: drySpecID
        dP = Get band density: fLoP, fHiP
        if dP <> undefined and dP > 0
            dDb = 10 * log10(dP)
            if dDb > dryPeakDb
                dryPeakDb = dDb
                dryPeakHz = (fLoP + fHiP) / 2
            endif
        endif
        selectObject: colourSpecID
        cP = Get band density: fLoP, fHiP
        if cP <> undefined and cP > 0
            cDb = 10 * log10(cP)
            if cDb > colourPeakDb
                colourPeakDb = cDb
                colourPeakHz = (fLoP + fHiP) / 2
            endif
        endif
    endfor

    predLowHz = dryPeakHz / low_freq_factor
    predHighHz = dryPeakHz * high_freq_factor

    procedure vizStep: .range, .target
        .raw = .range / .target
        .mag = 10 ^ floor(log10(max(1e-12, .raw)))
        .n = .raw / .mag
        if .n < 1.5
            .step = 1 * .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endproc

    Erase all

    # ---------------- Header ----------------
    Select outer viewport: 0, 8, 0, 0.40
    Select inner viewport: 0, 8, 0, 0.40
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", 0.60, "half", "Bell Curve Envelope: " + originalName$ + " [" + presetName$ + "]"

    Select outer viewport: 0, 8, 0.42, 0.72
    Select inner viewport: 0, 8, 0.42, 0.72
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.35, 0.35, 0.42}"
    Text: 0.5, "centre", 0.5, "half", "pristine source -> two sample-index reads -> subtraction -> Gaussian bell x edge closure -> output scale"

    # ---------------- A title ----------------
    Select outer viewport: 0, 8, 0.80, 1.00
    Select inner viewport: 0, 8, 0.80, 1.00
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  Dual-read geometry: output time -> source time"

    # ---------------- A data ----------------
    Select outer viewport: 0, 8, 1.02, 2.12
    Select inner viewport: 0.72, 7.72, 1.06, 2.02
    Axes: 0, duration, 0, duration
    Paint rectangle: "{0.975, 0.975, 0.978}", 0, duration, 0, duration

    # Identity reference.
    Dashed line
    Colour: "{0.72, 0.72, 0.74}"
    Draw line: 0, 0, duration, duration
    Solid line

    # Slow/low read: source time ~= output/L, valid until lowEnd.
    Colour: "{0.30, 0.52, 0.82}"
    Line width: 2
    nDraw = 180
    for q from 1 to nDraw
        t0 = lowEnd * (q - 1) / nDraw
        t1 = lowEnd * q / nDraw
        s0 = min(duration, t0 / low_freq_factor)
        s1 = min(duration, t1 / low_freq_factor)
        Draw line: t0, s0, t1, s1
    endfor

    # Fast/high read: source time ~= H*output, valid until highEnd.
    Colour: "{0.78, 0.38, 0.28}"
    Line width: 2
    for q from 1 to nDraw
        t0 = highEnd * (q - 1) / nDraw
        t1 = highEnd * q / nDraw
        s0 = min(duration, t0 * high_freq_factor)
        s1 = min(duration, t1 * high_freq_factor)
        Draw line: t0, s0, t1, s1
    endfor
    Line width: 1

    # Labels BEFORE any frame-disturbing drawing operations.
    Select inner viewport: 0.72, 7.72, 1.06, 2.02
    Axes: 0, duration, 0, duration
    Font size: 5
    Colour: "{0.30, 0.52, 0.82}"
    Text: 0.03*duration, "left", 0.92*duration, "half", "blue: i = round(col/L), stationary f -> f/L"
    Colour: "{0.78, 0.38, 0.28}"
    Text: 0.03*duration, "left", 0.82*duration, "half", "red: i = round(col*H), stationary f -> H*f"

    # Mark internal branch endings, if any.
    Dotted line
    if lowEnd < duration - 0.5/sampleRate
        Colour: "{0.30, 0.52, 0.82}"
        Draw line: lowEnd, 0, lowEnd, duration
    endif
    if highEnd < duration - 0.5/sampleRate
        Colour: "{0.78, 0.38, 0.28}"
        Draw line: highEnd, 0, highEnd, duration
    endif
    Solid line

    Select inner viewport: 0.72, 7.72, 1.06, 2.02
    Axes: 0, duration, 0, duration
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.72, 1.06, 2.02
    Axes: 0, duration, 0, duration
    Font size: 5
    @vizStep: duration, 6
    stepA = vizStep.step
    Marks bottom every: 1, stepA, "yes", "yes", "no"
    Marks left every: 1, stepA, "yes", "yes", "no"

    Select outer viewport: 0, 8, 2.12, 2.30
    Select inner viewport: 0, 8, 2.12, 2.30
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "axes are time in seconds | y0[col] = source[round(col/L)] - source[round(col*H)] | early branch endings close over " + fixed$(fade_s*1000,1) + " ms"

    # ---------------- B title ----------------
    Select outer viewport: 0, 8, 2.36, 2.56
    Select inner viewport: 0, 8, 2.36, 2.56
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  Effective bell envelope: Gaussian law plus edge closure"

    # ---------------- B data ----------------
    Select outer viewport: 0, 8, 2.58, 3.62
    Select inner viewport: 0.72, 7.72, 2.62, 3.52
    Axes: 0, duration, 0, 1.08
    Paint rectangle: "{0.975, 0.975, 0.978}", 0, duration, 0, 1.08

    # Raw Gaussian in grey; effective envelope in orange.
    radius = duration / bell_width
    Colour: "{0.66, 0.66, 0.70}"
    Line width: 1
    for q from 1 to 260
        t0 = duration * (q - 1) / 260
        t1 = duration * q / 260
        g0 = exp(-((t0-centerTime)/radius)^2)
        g1 = exp(-((t1-centerTime)/radius)^2)
        Draw line: t0, g0, t1, g1
    endfor
    Colour: "{0.88, 0.42, 0.20}"
    Line width: 2
    for q from 1 to 260
        t0 = duration * (q - 1) / 260
        t1 = duration * q / 260
        @effectiveEnv: t0
        e0 = effectiveEnv.v
        @effectiveEnv: t1
        e1 = effectiveEnv.v
        Draw line: t0, e0, t1, e1
    endfor
    Line width: 1

    Dotted line
    Colour: "{0.75, 0.25, 0.22}"
    Draw line: centerTime, 0, centerTime, 1.05
    Solid line

    Select inner viewport: 0.72, 7.72, 2.62, 3.52
    Axes: 0, duration, 0, 1.08
    Font size: 5
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02*duration, "left", 1.00, "half", "gray = Gaussian | orange = actual gain after edge fades"

    Select inner viewport: 0.72, 7.72, 2.62, 3.52
    Axes: 0, duration, 0, 1.08
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.72, 7.72, 2.62, 3.52
    Axes: 0, duration, 0, 1.08
    Font size: 5
    @vizStep: duration, 6
    Marks bottom every: 1, vizStep.step, "yes", "yes", "no"
    One mark left: 0, "yes", "yes", "no", "0"
    One mark left: 0.5, "yes", "yes", "no", "0.5"
    One mark left: 1, "yes", "yes", "no", "1"

    Select outer viewport: 0, 8, 3.62, 3.80
    Select inner viewport: 0, 8, 3.62, 3.80
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "time in seconds | g(t)=exp(-((t-mu)/r)^2), r=T/Bell_width=" + fixed$(radius,3) + " s | center=" + fixed$(centerTime,3) + " s"

    # ---------------- C title ----------------
    Select outer viewport: 0, 8, 3.86, 4.06
    Select inner viewport: 0, 8, 3.86, 4.06
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  Measured spectrum: pristine source vs dual-read colour stage"

    # ---------------- C data ----------------
    Select outer viewport: 0, 8, 4.08, 5.14
    Select inner viewport: 0.68, 7.72, 4.12, 5.04
    selectObject: drySpecID
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"
    selectObject: colourSpecID
    Colour: "{0.28, 0.50, 0.80}"
    Line width: 1
    Draw: 0, vizFreqMax, 0, 80, "no"

    Select inner viewport: 0.68, 7.72, 4.12, 5.04
    Axes: 0, vizFreqMax, 0, 80
    Font size: 5
    Colour: "{0.45, 0.45, 0.50}"
    Text: 0.02*vizFreqMax, "left", 75, "half", "gray dry | blue colour stage (before bell)"
    Colour: "{0.28, 0.50, 0.80}"
    Text: 0.98*vizFreqMax, "right", 75, "half", "strongest measured dry " + fixed$(dryPeakHz,0) + " Hz -> colour " + fixed$(colourPeakHz,0) + " Hz"

    Select inner viewport: 0.68, 7.72, 4.12, 5.04
    Axes: 0, vizFreqMax, 0, 80
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.68, 7.72, 4.12, 5.04
    Axes: 0, vizFreqMax, 0, 80
    Font size: 5
    Marks left every: 1, 20, "yes", "yes", "no"
    @vizStep: vizFreqMax, 8
    stepC = vizStep.step
    nC = floor(vizFreqMax / stepC)
    for q from 0 to nC
        fC = q * stepC
        if fC >= 1000
            labC$ = fixed$(fC/1000,1) + "k"
        else
            labC$ = fixed$(fC,0)
        endif
        One mark bottom: fC, "no", "yes", "no", labC$
    endfor

    Select outer viewport: 0, 8, 5.14, 5.32
    Select inner viewport: 0, 8, 5.14, 5.32
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    if predHighHz <= sampleRate/2
        predText$ = "stationary dry peak predicts low " + fixed$(predLowHz,0) + " Hz and high " + fixed$(predHighHz,0) + " Hz"
    else
        predText$ = "stationary dry peak predicts low " + fixed$(predLowHz,0) + " Hz; high target " + fixed$(predHighHz,0) + " Hz exceeds Nyquist (aliasing possible)"
    endif
    Text: 0.5, "centre", 0.5, "half", "frequency in Hz; level in dB | " + predText$

    # ---------------- D title ----------------
    Select outer viewport: 0, 8, 5.38, 5.58
    Select inner viewport: 0, 8, 5.38, 5.58
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "D  Measured waveform: source and final output on the same amplitude scale"

    # ---------------- D data ----------------
    Select outer viewport: 0, 8, 5.60, 6.56
    Select inner viewport: 0.68, 7.72, 5.64, 6.46
    selectObject: originalID
    Colour: "{0.68, 0.68, 0.70}"
    Line width: 1
    Draw: 0, 0, -waveRange, waveRange, "no", "Curve"
    selectObject: workingID
    Colour: "{0.24, 0.50, 0.80}"
    Line width: 1
    Draw: 0, 0, -waveRange, waveRange, "no", "Curve"

    Select inner viewport: 0.68, 7.72, 5.64, 6.46
    Axes: 0, duration, -waveRange, waveRange
    Font size: 5
    Colour: "{0.35, 0.35, 0.40}"
    Text: 0.02*duration, "left", 0.78*waveRange, "half", "gray source | blue output"

    Select inner viewport: 0.68, 7.72, 5.64, 6.46
    Axes: 0, duration, -waveRange, waveRange
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.68, 7.72, 5.64, 6.46
    Axes: 0, duration, -waveRange, waveRange
    Font size: 5
    @vizStep: duration, 7
    Marks bottom every: 1, vizStep.step, "yes", "yes", "no"
    @vizStep: waveRange, 2
    Marks left every: 1, vizStep.step, "yes", "yes", "no"

    Select outer viewport: 0, 8, 6.56, 6.74
    Select inner viewport: 0, 8, 6.56, 6.74
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.35, 0.35, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "time in seconds | source peak/RMS " + fixed$(sourcePeak,3) + "/" + fixed$(sourceRms,3) + " | output " + fixed$(outPeak,3) + "/" + fixed$(outRms,3)

    # ---------------- QC strip ----------------
    Select outer viewport: 0, 8, 6.82, 7.42
    Select inner viewport: 0.15, 7.85, 6.84, 7.38
    Axes: 0, 3, 0, 2
    Colour: "{0.965, 0.965, 0.97}"
    Paint rectangle: "{0.965, 0.965, 0.97}", 0, 3, 0, 2
    Colour: "{0.82, 0.82, 0.84}"
    Draw line: 1, 0, 1, 2
    Draw line: 2, 0, 2, 2
    Draw line: 0, 1, 3, 1
    Colour: "Black"
    Draw rectangle: 0, 3, 0, 2
    Font size: 6
    Text: 0.05, "left", 1.55, "half", "L read factor: " + fixed$(low_freq_factor,3)
    Text: 1.05, "left", 1.55, "half", "H read factor: " + fixed$(high_freq_factor,3)
    Text: 2.05, "left", 1.55, "half", "sample rate: " + fixed$(sampleRate,0) + " Hz"
    Text: 0.05, "left", 0.55, "half", "bell r: " + fixed$(radius,3) + " s | center " + fixed$(bell_center,2)
    Text: 1.05, "left", 0.55, "half", "branch ends: L " + fixed$(lowEnd,3) + " s | H " + fixed$(highEnd,3) + " s"
    Text: 2.05, "left", 0.55, "half", "edge " + fixed$(fade_s*1000,1) + " ms | peak " + fixed$(outPeak,3)

    removeObject: drySpecID, colourSpecID, colourVizID
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_bell_", presetName$

if play_result
    selectObject: workingID
    Play
endif

# ============================================================
# PROCEDURES
# ============================================================

# Effective gain at time .t (0-based): exp(-((t-mu)/r)^2) times the
# raised-cosine edge fades. Mirrors the audio formulas exactly.
procedure effectiveEnv: .t
    .v = exp(-((.t - centerTime) / sigma)^2)
    if .t < fade_s
        .v = .v * (0.5 - 0.5 * cos(pi * .t / fade_s))
    endif
    if duration - .t < fade_s
        .v = .v * (0.5 - 0.5 * cos(pi * (duration - .t) / fade_s))
    endif
endproc
