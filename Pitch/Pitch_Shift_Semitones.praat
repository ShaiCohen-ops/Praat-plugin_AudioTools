# ============================================================
# Praat AudioTools - Pitch_Shift_Semitones.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch Shift (Semitones) - shifts pitch by specified semitones
#   while preserving duration using PSOLA resynthesis. Includes
#   presets for common musical intervals.
#
# Changelog v0.3:
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
form Pitch Shift (Semitones) v0.3
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
writeInfoLine: "=== Pitch Shift v0.3 ==="
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
    Erase all
    
    # --- Title ---
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Pitch Shift (Semitones)##"
    
    # --- Subtitle ---
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", originalName$ + " -> " + intervalName$ + " (" + string$(semitones) + " st)"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.9
    Select inner viewport: 0.6, 7.6, 0.7, 1.8
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.0, 3.3
    Select inner viewport: 0.6, 7.6, 2.1, 3.2
    selectObject: result
    if semitones > 0
        Colour: "{0.5, 0.6, 0.8}"
    elsif semitones < 0
        Colour: "{0.8, 0.6, 0.5}"
    else
        Colour: "{0.6, 0.6, 0.6}"
    endif
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Shifted"
    Text bottom: "yes", "Time (s)"
    
    # Spectrogram comparison
    specMax = min(5000, 0.45 * fs)
    Select outer viewport: 0, 4, 3.5, 5.0
    Select inner viewport: 0.6, 3.8, 3.7, 4.9
    selectObject: original
    To Spectrogram: 0.03, specMax, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"
    Text left: "yes", "Hz"
    
    Select outer viewport: 4, 8, 3.5, 5.0
    Select inner viewport: 4.4, 7.6, 3.7, 4.9
    selectObject: result
    To Spectrogram: 0.03, specMax, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Shifted (" + intervalName$ + ")"
    
    # Interval diagram
    Select outer viewport: 0, 8, 5.2, 5.8
    Select inner viewport: 0.6, 7.6, 5.3, 5.7
    
    axisMin = min(-12, floor(semitones) - 2)
    axisMax = max(12, ceiling(semitones) + 2)
    Axes: axisMin, axisMax, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", axisMin, axisMax, 0, 1

    # Draw semitone markers
    for st from ceiling(axisMin) to floor(axisMax)
        if st = 0
            Colour: "{0.3, 0.3, 0.3}"
            Line width: 2
        else
            Colour: "{0.7, 0.7, 0.7}"
            Line width: 1
        endif
        Draw line: st, 0.1, st, 0.9
    endfor
    Line width: 1
    
    # Highlight current shift
    if semitones > 0
        circleColor$ = "{0.5, 0.6, 0.8}"
    elsif semitones < 0
        circleColor$ = "{0.8, 0.6, 0.5}"
    else
        circleColor$ = "{0.5, 0.5, 0.5}"
    endif
    Paint circle (mm): circleColor$, semitones, 0.5, 3
    
    # Arrow from 0 to target
    if semitones <> 0
        Colour: circleColor$
        Draw arrow: 0, 0.5, semitones * 0.9, 0.5
    endif
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Semitones"
    
    Font size: 10
    Colour: "Black"
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