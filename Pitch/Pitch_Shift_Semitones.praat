# ============================================================
# Praat AudioTools - Pitch_Shift_Semitones.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Shift (Semitones) - shifts pitch by specified semitones
#   while preserving duration using PSOLA resynthesis. Includes
#   presets for common musical intervals.
#
# Changelog v0.4.3: the semantic colour of v0.4.2 was keyed only on the sign of
#   semitones and applied at three sites, so the stock form defaults (Custom,
#   0 semitones) resolved every branch to neutral grey and the page came out
#   entirely grey. Direction now drives the subtitle, both panel captions, the
#   shifted spectrogram frame, the travelled span of the interval ruler, its
#   ticks, arrow and marker, and the summary state line. 0 semitones is now an
#   explicit IDENTITY state with its own label and colour rather than a silent
#   fallthrough. Also: originalName$ is escaped before it reaches Picture text
#   (the underscore was being read as subscript markup); the summary box is
#   drawn after re-selecting the inner viewport, so it no longer comes out
#   oversized; both waveform panels now share one explicit symmetric amplitude
#   range instead of autoscaling independently; the interval ruler gained
#   numbered marks; Text FAR flags corrected on panels that draw no marks;
#   summary text replaced with the actual run parameters. DSP/analysis unchanged.
# Changelog v0.4.2: semantic library colour pass - original/reference neutral grey, upward shift blue, downward shift warm red; DSP/analysis unchanged.
# Changelog v0.4.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.4: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.4:
#   - True identity path for 0 semitones (no PSOLA/resample/normalization).
#   - Preserves the original channel count by processing each channel
#     independently with the same shift.
#   - Uses the actual time domain for DurationTier points (xmin/xmax safe).
#   - Wider adaptive pitch-analysis range with sampling-rate safety checks.
#   - Validates custom shifts / temporary sample rates before processing.
#   - Peak protection is attenuation-only; quiet outputs are never boosted.
#   - Visualization style/layout preserved; interval axis is dynamic and
#     spectrogram ceiling respects the source Nyquist region.
#
# Changelog v0.2:
#   - Added input check
#   - Modern syntax throughout
#   - Added interval presets
#   - Added visualization
#   - Object ID-based cleanup
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
fs = Get sampling frequency
source_xmin = Get start time
source_xmax = Get end time
duration = source_xmax - source_xmin
n_channels = Get number of channels

# === Form ===
form Pitch Shift (Semitones) v0.4.3
    comment Select a Sound object first
    
    comment === Interval Preset ===
    optionmenu Preset 1
        option Custom (use value below)
        option Minor 2nd (+1)
        option Major 2nd (+2)
        option Minor 3rd (+3)
        option Major 3rd (+4)
        option Perfect 4th (+5)
        option Tritone (+6)
        option Perfect 5th (+7)
        option Minor 6th (+8)
        option Major 6th (+9)
        option Minor 7th (+10)
        option Major 7th (+11)
        option Octave Up (+12)
        option Octave Down (-12)
        option Perfect 5th Down (-7)
        option Major 3rd Down (-4)
    
    comment === Custom Value ===
    real Semitones 0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    semitones = 1
    intervalName$ = "m2"
elsif preset = 3
    semitones = 2
    intervalName$ = "M2"
elsif preset = 4
    semitones = 3
    intervalName$ = "m3"
elsif preset = 5
    semitones = 4
    intervalName$ = "M3"
elsif preset = 6
    semitones = 5
    intervalName$ = "P4"
elsif preset = 7
    semitones = 6
    intervalName$ = "TT"
elsif preset = 8
    semitones = 7
    intervalName$ = "P5"
elsif preset = 9
    semitones = 8
    intervalName$ = "m6"
elsif preset = 10
    semitones = 9
    intervalName$ = "M6"
elsif preset = 11
    semitones = 10
    intervalName$ = "m7"
elsif preset = 12
    semitones = 11
    intervalName$ = "M7"
elsif preset = 13
    semitones = 12
    intervalName$ = "8ve+"
elsif preset = 14
    semitones = -12
    intervalName$ = "8ve-"
elsif preset = 15
    semitones = -7
    intervalName$ = "P5-"
elsif preset = 16
    semitones = -4
    intervalName$ = "M3-"
else
    if semitones >= 0
        intervalName$ = "+" + string$(semitones)
    else
        intervalName$ = string$(semitones)
    endif
endif

# === Validation ===
if duration <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if semitones < -48 or semitones > 48
    exitScript: "Custom Semitones must be between -48 and +48."
endif

# === Info ===
writeInfoLine: "=== Pitch Shift v0.4.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", n_channels, " ch)"
appendInfoLine: "Shift: ", semitones, " semitones (", intervalName$, ")"
appendInfoLine: ""

# === Calculate Ratios ===
note_ratio = 2 ^ (semitones / 12)
newfs = fs * note_ratio

if newfs < 1000 or newfs > 384000
    exitScript: "This shift would require a temporary sampling frequency of " +
        ... string$(round(newfs)) + " Hz. Use a smaller shift."
endif

appendInfoLine: "Pitch ratio: ", fixed$(note_ratio, 4)
appendInfoLine: "Temp sample rate: ", round(newfs), " Hz"

baseManipMin = 40
baseManipMax = min(1200, 0.45 * fs)
manipMin = baseManipMin * note_ratio
manipMax = baseManipMax * note_ratio

if manipMin < 20
    manipMin = 20
endif
nyqSafe = 0.45 * newfs
if manipMax > nyqSafe
    manipMax = nyqSafe
endif

if manipMax <= manipMin
    exitScript: "The requested shift leaves no safe pitch-analysis range."
endif

appendInfoLine: "Manipulation range: ", round(manipMin), "-", round(manipMax), " Hz"
appendInfoLine: ""

safetyApplied = 0

# === Exact identity for zero shift ===
if abs(semitones) < 0.0000001
    selectObject: original
    result = Copy: originalName$ + "_" + intervalName$
    appendInfoLine: "0 semitones: exact identity copy (processing bypassed)."

else
    appendInfoLine: "Processing ", n_channels, " channel(s)..."
    channelResults# = zero#(n_channels)

    for ch from 1 to n_channels
        selectObject: original
        if n_channels = 1
            channelSource = Copy: "PSS_ch1"
        else
            channelSource = Extract one channel: ch
            Rename: "PSS_ch" + string$(ch)
        endif

        selectObject: channelSource
        Override sampling frequency: newfs
        shifted_xmin = Get start time
        shifted_xmax = Get end time

        manipulation = To Manipulation: 0.01, manipMin, manipMax

        selectObject: manipulation
        durationTier = Extract duration tier

        selectObject: durationTier
        Add point: shifted_xmin, note_ratio
        if shifted_xmax > shifted_xmin
            Add point: shifted_xmax, note_ratio
        endif

        selectObject: manipulation
        plusObject: durationTier
        Replace duration tier

        selectObject: manipulation
        resynthSound = Get resynthesis (overlap-add)

        selectObject: resynthSound
        channelResult = Resample: fs, 50
        Rename: "PSS_result_ch" + string$(ch)
        channelResults#[ch] = channelResult

        removeObject: durationTier, manipulation, channelSource, resynthSound
    endfor

    Create Sound from formula: "PSS_result_build", n_channels,
        ... source_xmin, source_xmax, fs, "0"
    result = selected("Sound")

    for ch from 1 to n_channels
        selectObject: result
        Formula (part): source_xmin, source_xmax, ch, ch,
            ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
        removeObject: channelResults#[ch]
    endfor

    selectObject: result
    Rename: originalName$ + "_" + intervalName$

    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak > 0.95
        Scale peak: 0.95
        safetyApplied = 1
    endif
endif

# === Visualization ===
if draw_visualization
    # ------------------------------------------------------------
    # Semantic palette. Every coloured element on the page derives
    # from these three strings, so direction reads at a glance
    # instead of living only on the shifted waveform.
    # ------------------------------------------------------------
    if semitones > 0
        accent$ = "{0.20, 0.45, 0.82}"
        accentSoft$ = "{0.80, 0.87, 0.96}"
        dirLabel$ = "UP"
    elsif semitones < 0
        accent$ = "{0.82, 0.22, 0.18}"
        accentSoft$ = "{0.97, 0.86, 0.84}"
        dirLabel$ = "DOWN"
    else
        # 0 semitones is an explicit state, not an absence of one.
        accent$ = "{0.42, 0.42, 0.58}"
        accentSoft$ = "{0.90, 0.90, 0.93}"
        dirLabel$ = "IDENTITY"
    endif
    neutral$ = "{0.50, 0.50, 0.55}"

    safeName$ = replace$(originalName$, "_", "\_ ", 0)

    if semitones = 0
        shiftedLabel$ = "Output (identity copy)"
        stateLine$ = "IDENTITY - 0 semitones, PSOLA bypassed. Both panels show the same signal."
    else
        shiftedLabel$ = "Shifted (" + intervalName$ + ")"
        stateLine$ = dirLabel$ + " " + fixed$(semitones, 2) + " st (" + intervalName$ +
            ... ") | ratio " + fixed$(note_ratio, 4) + " | temp rate " + string$(round(newfs)) +
            ... " Hz | analysis " + string$(round(manipMin)) + "-" + string$(round(manipMax)) + " Hz"
    endif
    if safetyApplied
        peakLine$ = "Peak safety applied: output attenuated to 0.95."
    else
        peakLine$ = "Peak safety not needed; output level untouched."
    endif

    # Shared symmetric amplitude range so the two waveform panels are
    # actually comparable (Draw: 0,0,0,0 autoscales each on its own).
    selectObject: original
    ampO = Get absolute extremum: 0, 0, "None"
    selectObject: result
    ampR = Get absolute extremum: 0, 0, "None"
    wavAmp = max(0.001, max(ampO, ampR) * 1.15)

    Erase all
    pageHeight = 6.85
    Select outer viewport: 0, 8, 0, pageHeight

    # ------------------------------------------------------------
    # Title strip. Axes maps to the INNER viewport, so a text strip
    # must set the inner viewport or the two lines collapse.
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Pitch Shift (Semitones) v0.4.3##"
    Font size: 7
    Colour: accent$
    Text: 0.5, "centre", 0.22, "half", safeName$ + " -> " + intervalName$ + " (" + fixed$(semitones, 2) + " st)"

    # ------------------------------------------------------------
    # Original waveform
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 0.60, 1.90
    Select inner viewport: 0.60, 7.70, 0.70, 1.80
    selectObject: original
    Colour: neutral$
    Draw: 0, 0, -wavAmp, wavAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Colour: neutral$
    Text top: "no", "Original"

    # ------------------------------------------------------------
    # Shifted waveform
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 2.00, 3.30
    Select inner viewport: 0.60, 7.70, 2.10, 3.20
    selectObject: result
    Colour: accent$
    Draw: 0, 0, -wavAmp, wavAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Colour: accent$
    Text top: "no", shiftedLabel$
    Colour: "Black"
    Text bottom: "no", "Time (s) - both panels share the range +/-" + fixed$(wavAmp, 3)

    # ------------------------------------------------------------
    # Spectrogram comparison. Praat paints a Spectrogram in greyscale
    # and takes no colour argument, so direction can only be carried
    # by the frame and the caption here.
    # ------------------------------------------------------------
    specMax = min(5000, 0.45 * fs)

    Select outer viewport: 0, 4, 3.45, 5.05
    Select inner viewport: 0.60, 3.75, 3.55, 4.95
    selectObject: original
    To Spectrogram: 0.03, specMax, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    # Draw inner box ALWAYS paints black and ignores Colour (confirmed
    # 6.4.06), so a semantic frame has to be a Draw rectangle.
    Select inner viewport: 0.60, 3.75, 3.55, 4.95
    Axes: 0, 1, 0, 1
    Colour: neutral$
    Line width: 1
    Draw rectangle: 0, 1, 0, 1
    Font size: 6
    Colour: neutral$
    Text top: "no", "Original"
    Colour: "Black"
    Text left: "no", "Hz"

    Select outer viewport: 4, 8, 3.45, 5.05
    Select inner viewport: 4.45, 7.70, 3.55, 4.95
    selectObject: result
    To Spectrogram: 0.03, specMax, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Select inner viewport: 4.45, 7.70, 3.55, 4.95
    Axes: 0, 1, 0, 1
    Colour: accent$
    Line width: 2
    Draw rectangle: 0, 1, 0, 1
    Line width: 1
    Font size: 6
    Colour: accent$
    Text top: "no", shiftedLabel$

    # ------------------------------------------------------------
    # Interval ruler
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 5.15, 5.95
    Select inner viewport: 0.60, 7.70, 5.25, 5.62

    axisMin = min(-12, floor(semitones) - 2)
    axisMax = max(12, ceiling(semitones) + 2)
    Axes: axisMin, axisMax, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", axisMin, axisMax, 0, 1

    # Travelled span filled in the direction colour.
    if semitones <> 0
        Paint rectangle: accentSoft$, min(0, semitones), max(0, semitones), 0.08, 0.92
    endif

    # Semitone markers: ticks inside the travelled span take the accent.
    for st from ceiling(axisMin) to floor(axisMax)
        if st = 0
            Colour: "{0.30, 0.30, 0.40}"
            Line width: 2
        elsif semitones > 0 and st > 0 and st <= semitones
            Colour: accent$
            Line width: 1
        elsif semitones < 0 and st < 0 and st >= semitones
            Colour: accent$
            Line width: 1
        else
            Colour: "{0.80, 0.80, 0.80}"
            Line width: 1
        endif
        Draw line: st, 0.12, st, 0.88
    endfor
    Line width: 1

    if semitones <> 0
        Colour: accent$
        Draw arrow: 0, 0.5, semitones * 0.88, 0.5
    endif
    Paint circle (mm): accent$, semitones, 0.5, 3

    Select inner viewport: 0.60, 7.70, 5.25, 5.62
    Axes: axisMin, axisMax, 0, 1
    Colour: "Black"
    Draw inner box
    Marks bottom every: 1, 3, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Semitones"

    # ------------------------------------------------------------
    # Summary strip
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 5.95, 6.75
    Select inner viewport: 0.60, 7.70, 6.00, 6.68
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: accent$
    Text: 0.02, "left", 0.52, "half", stateLine$
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.02, "left", 0.22, "half", safeName$ + " | " + fixed$(duration, 2) + " s | " +
        ... string$(n_channels) + " ch | " + string$(round(fs)) + " Hz | " + peakLine$

    # Re-select before the box: Text leaves the drawing frame on the
    # OUTER viewport, which is why the old Draw rectangle came out
    # larger than the grey fill it was meant to outline.
    Select inner viewport: 0.60, 7.70, 6.00, 6.68
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    # Restore the complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Channels preserved: ", n_channels
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
