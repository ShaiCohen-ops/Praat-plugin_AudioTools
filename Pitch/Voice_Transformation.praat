# ============================================================
# Praat AudioTools - Voice_Transformation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Voice Transformation - combines pitch shifting, duration
#   stretching, formant shifting, and bandpass filtering.
#   Includes presets for common voice effects like chipmunk,
#   robot, telephone, and radio voice.
#
# Changelog v0.5.1: compact Summary typography/spacing; collision-safe gap after bottom-axis labels; DSP/analysis unchanged.
# Changelog v0.5: visualization standardization only - unified typography, summary/full-page Picture framing; DSP/analysis unchanged.
# Changelog v0.5:
#   - Corrected Change gender pitch-range factor: formant shifting now uses
#     pitch-range factor 1.0 instead of 0 (which monotonized the pitch contour).
#   - Full xmin/xmax-safe DurationTier and PitchTier handling.
#   - Mono is used for shared pitch analysis only; processing preserves the
#     exact original channel count.
#   - Added parameter validation for pitch range, filter band, duration,
#     formant ratio, semitone shift, time step and sampling frequency.
#   - Adaptive spectrogram ceiling respects Nyquist.
#   - No-pitch material still receives duration/formant/filter processing;
#     requested pitch shifting is skipped cleanly if no voiced pitch exists.
#   - Removed forced Scale intensity; peak protection is attenuation-only.
#   - Visualization layout/style preserved; title/stats axes and time-domain
#     coordinates corrected.
#
# Changelog v0.2:
#   - Renamed from "globally change pitch and duration"
#   - Modern syntax throughout
#   - Added visualization
#   - Fixed object cleanup
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

userSound = selected("Sound")
origName$ = selected$("Sound")

# v0.4 keeps the selected Sound untouched. A mono analysis reference is
# created later only when needed; audio processing is performed per channel.

# === Form ===
form Voice Transformation v0.5.1
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Vocal Harmonics
        option Reduce Breathiness
        option Deeper Voice
        option Higher Voice
        option Chipmunk Effect
        option Robot Voice
        option Telephone Effect
        option Radio Voice
    
    comment === Pitch Analysis ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    positive Time_step 0.01
    
    comment === Frequency Range ===
    positive Freq_cutoff_low 120
    positive Freq_cutoff_high 3500
    
    comment === Transformations ===
    real Pitch_shift_semitones 0
    real Formant_shift_ratio 1.0
    real Duration_factor 1.0
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Vocal harmonics
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 100
    freq_cutoff_high = 4000
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Vocal"
elsif preset = 3
    # Reduce breathiness
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 200
    freq_cutoff_high = 3000
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Clean"
elsif preset = 4
    # Deeper voice
    pitch_floor = 50
    pitch_ceiling = 400
    freq_cutoff_low = 80
    freq_cutoff_high = 4000
    pitch_shift_semitones = -4
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Deeper"
elsif preset = 5
    # Higher voice
    pitch_floor = 100
    pitch_ceiling = 800
    freq_cutoff_low = 150
    freq_cutoff_high = 5000
    pitch_shift_semitones = 5
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Higher"
elsif preset = 6
    # Chipmunk effect
    pitch_floor = 150
    pitch_ceiling = 1000
    freq_cutoff_low = 200
    freq_cutoff_high = 8000
    pitch_shift_semitones = 7
    formant_shift_ratio = 1.4
    duration_factor = 0.85
    presetName$ = "Chipmunk"
elsif preset = 7
    # Robot voice
    pitch_floor = 50
    pitch_ceiling = 300
    freq_cutoff_low = 100
    freq_cutoff_high = 2500
    pitch_shift_semitones = -6
    formant_shift_ratio = 0.9
    duration_factor = 1.05
    presetName$ = "Robot"
elsif preset = 8
    # Telephone effect
    pitch_floor = 75
    pitch_ceiling = 500
    freq_cutoff_low = 300
    freq_cutoff_high = 3400
    pitch_shift_semitones = 0
    formant_shift_ratio = 1.0
    duration_factor = 1.0
    presetName$ = "Telephone"
elsif preset = 9
    # Radio voice
    pitch_floor = 60
    pitch_ceiling = 400
    freq_cutoff_low = 80
    freq_cutoff_high = 8000
    pitch_shift_semitones = -2
    formant_shift_ratio = 0.95
    duration_factor = 0.98
    presetName$ = "Radio"
else
    presetName$ = "Custom"
endif

# === Source metadata ===
selectObject: userSound
xmin = Get start time
xmax = Get end time
dur = xmax - xmin
fs = Get sampling frequency
nChannels = Get number of channels

# === Validation ===
if dur <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if fs < 1000
    exitScript: "Sampling frequency is too low for safe voice processing."
endif
if pitch_floor <= 0 or pitch_ceiling <= pitch_floor
    exitScript: "Pitch_floor / Pitch_ceiling are invalid."
endif
if pitch_ceiling >= 0.45 * fs
    exitScript: "Pitch_ceiling must be below 45% of the source sampling frequency."
endif
if time_step <= 0 or time_step > 0.1
    exitScript: "Time_step must be greater than 0 and no more than 0.1 s."
endif
if freq_cutoff_low < 0 or freq_cutoff_high <= freq_cutoff_low
    exitScript: "Frequency filter limits are invalid."
endif
if freq_cutoff_high >= 0.49 * fs
    exitScript: "Freq_cutoff_high must be below 49% of the source sampling frequency."
endif
if pitch_shift_semitones < -48 or pitch_shift_semitones > 48
    exitScript: "Pitch_shift_semitones must be between -48 and +48."
endif
if formant_shift_ratio <= 0 or formant_shift_ratio > 4
    exitScript: "Formant_shift_ratio must be greater than 0 and no more than 4."
endif
if duration_factor <= 0 or duration_factor > 4
    exitScript: "Duration_factor must be greater than 0 and no more than 4."
endif

# === Info ===
writeInfoLine: "=== Voice Transformation v0.5.1 ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(dur, 2), " s, ", nChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Pitch shift: ", pitch_shift_semitones, " semitones"
appendInfoLine: "Formant shift: ", formant_shift_ratio, "x"
appendInfoLine: "Duration: ", duration_factor, "x"
appendInfoLine: "Band: ", freq_cutoff_low, "-", freq_cutoff_high, " Hz"
appendInfoLine: ""

# === Shared mono analysis reference ===
selectObject: userSound
if nChannels > 1
    analysisMono = Convert to mono
else
    analysisMono = Copy: origName$ + "_analysis"
endif

analysisManip = 0
sourcePitchTier = 0
shiftedPitchTier = 0
durationTier = 0
pitchAvailable = 0
pitchSafetyCount = 0
peakSafetyApplied = 0

# Analyze pitch only if a pitch shift is requested.
if pitch_shift_semitones <> 0
    selectObject: analysisMono
    analysisManip = To Manipulation: time_step, pitch_floor, pitch_ceiling

    selectObject: analysisManip
    sourcePitchTier = Extract pitch tier

    selectObject: sourcePitchTier
    nPitchPoints = Get number of points

    if nPitchPoints > 0
        pitchAvailable = 1

        Create PitchTier: "voice_shifted_pitch", xmin, xmax
        shiftedPitchTier = selected("PitchTier")

        pitchRatio = 2 ^ (pitch_shift_semitones / 12)
        synthFloor = 20
        synthCeil = 0.45 * fs

        for p from 1 to nPitchPoints
            selectObject: sourcePitchTier
            pointTime = Get time from index: p
            pointPitch = Get value at index: p

            newPitch = pointPitch * pitchRatio
            if newPitch < synthFloor
                newPitch = synthFloor
                pitchSafetyCount += 1
            elsif newPitch > synthCeil
                newPitch = synthCeil
                pitchSafetyCount += 1
            endif

            selectObject: shiftedPitchTier
            Add point: pointTime, newPitch
        endfor

        if pitchSafetyCount > 0
            appendInfoLine: "Pitch safety limits applied: ", pitchSafetyCount, " point(s)"
        endif
    else
        appendInfoLine: "No voiced pitch detected: requested pitch shift will be skipped."
    endif
endif

# Shared constant duration tier in the TRUE source time domain.
if duration_factor <> 1
    Create DurationTier: "voice_duration", xmin, xmax
    durationTier = selected("DurationTier")
    Add point: xmin, duration_factor
    Add point: xmax, duration_factor
endif

# === Per-channel processing ===
appendInfoLine: "Processing ", nChannels, " channel(s)..."
channelResults# = zero#(nChannels)

for ch from 1 to nChannels
    selectObject: userSound
    if nChannels = 1
        channelWork = Copy: "VT_ch1"
    else
        channelWork = Extract one channel: ch
        Rename: "VT_ch" + string$(ch)
    endif

    selectObject: channelWork
    manipulation = To Manipulation: time_step, pitch_floor, pitch_ceiling

    if pitch_shift_semitones <> 0 and pitchAvailable
        selectObject: manipulation
        plusObject: shiftedPitchTier
        Replace pitch tier
    endif

    if duration_factor <> 1
        selectObject: manipulation
        plusObject: durationTier
        Replace duration tier
    endif

    selectObject: manipulation
    channelStage = Get resynthesis (overlap-add)
    removeObject: manipulation, channelWork

    # Formant stage.
    if formant_shift_ratio <> 1
        appendInfoLine: "  Channel ", ch, ": formant shift ", formant_shift_ratio, "x"
        selectObject: channelStage

        # Change gender:
        # formant ratio, new pitch median=0 (preserve median),
        # pitch range factor=1.0 (preserve contour range),
        # duration factor=1.0 (duration already handled above).
        formantShifted = Change gender: pitch_floor, pitch_ceiling,
            ... formant_shift_ratio, 0, 1.0, 1.0

        removeObject: channelStage
        channelStage = formantShifted
    endif

    # Band-pass filter.
    selectObject: channelStage
    filteredChannel = Filter (pass Hann band): freq_cutoff_low, freq_cutoff_high, 100
    removeObject: channelStage

    Rename: "VT_result_ch" + string$(ch)
    channelResults#[ch] = selected("Sound")
endfor

# === Rebuild original channel count ===
if nChannels = 1
    result = channelResults#[1]
else
    selectObject: channelResults#[1]
    resultXmin = Get start time
    resultXmax = Get end time
    resultFs = Get sampling frequency

    Create Sound from formula: "VT_result_build", nChannels,
        ... resultXmin, resultXmax, resultFs, "0"
    result = selected("Sound")

    for ch from 1 to nChannels
        selectObject: result
        Formula (part): resultXmin, resultXmax, ch, ch,
            ... "object[" + string$(channelResults#[ch]) + ", 1, col]"
        removeObject: channelResults#[ch]
    endfor
endif

# === Finalize ===
selectObject: result
Rename: origName$ + "_" + presetName$

resultPeak = Get absolute extremum: 0, 0, "None"
if resultPeak > 0.95
    Scale peak: 0.95
    peakSafetyApplied = 1
endif

newDur = Get total duration

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Voice Transformation v0.5.1: " + origName$ + " -> " + presetName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: userSound
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Transformed"
    Text bottom: "yes", "Time (s)"
    
    # Spectrogram comparison
    Select outer viewport: 0, 4, 3.3, 4.8
    Select inner viewport: 0.6, 3.8, 3.5, 4.7
    specCeil = min(5000, 0.49 * fs)

    selectObject: analysisMono
    To Spectrogram: 0.03, specCeil, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    # Draw filter band
    Colour: "{0.8, 0.4, 0.4}"
    Dotted line
    Draw line: xmin, freq_cutoff_low, xmax, freq_cutoff_low
    Draw line: xmin, freq_cutoff_high, xmax, freq_cutoff_high
    Solid line
    
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"
    Text left: "yes", "Hz"
    
    Select outer viewport: 4, 8, 3.3, 4.8
    Select inner viewport: 4.4, 7.6, 3.5, 4.7
    selectObject: result
    if nChannels > 1
        resultVizMono = Convert to mono
    else
        resultVizMono = Copy: "VT_result_viz"
    endif

    selectObject: resultVizMono
    To Spectrogram: 0.03, specCeil, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, resultVizMono
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Transformed"
    
    # Transformation summary
    Select outer viewport: 0, 8, 5.0, 5.8
    Select inner viewport: 0.6, 7.6, 5.1, 5.7
    
    Axes: 0, 4, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 4, 0, 1
    
    # Pitch shift bar
    if pitch_shift_semitones <> 0
        if pitch_shift_semitones > 0
            Paint rectangle: "{0.5, 0.7, 0.5}", 0.1, 0.9, 0.1, 0.9
        else
            Paint rectangle: "{0.7, 0.5, 0.5}", 0.1, 0.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 0.1, 0.9, 0.1, 0.9
    endif
    
    # Formant bar
    if formant_shift_ratio <> 1.0
        if formant_shift_ratio > 1.0
            Paint rectangle: "{0.5, 0.5, 0.7}", 1.1, 1.9, 0.1, 0.9
        else
            Paint rectangle: "{0.7, 0.5, 0.7}", 1.1, 1.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 1.1, 1.9, 0.1, 0.9
    endif
    
    # Duration bar
    if duration_factor <> 1.0
        if duration_factor > 1.0
            Paint rectangle: "{0.7, 0.6, 0.5}", 2.1, 2.9, 0.1, 0.9
        else
            Paint rectangle: "{0.5, 0.6, 0.7}", 2.1, 2.9, 0.1, 0.9
        endif
    else
        Paint rectangle: "{0.7, 0.7, 0.7}", 2.1, 2.9, 0.1, 0.9
    endif
    
    # Filter bar
    Paint rectangle: "{0.6, 0.6, 0.5}", 3.1, 3.9, 0.1, 0.9
    
    # Labels
    Colour: "Black"
    Font size: 6
    Text: 0.5, "centre", 0.5, "half", string$(pitch_shift_semitones) + "st"
    Text: 1.5, "centre", 0.5, "half", fixed$(formant_shift_ratio, 2) + "x"
    Text: 2.5, "centre", 0.5, "half", fixed$(duration_factor, 2) + "x"
    Text: 3.5, "centre", 0.5, "half", string$(freq_cutoff_low) + "-" + string$(freq_cutoff_high)
    
    Text: 0.5, "centre", -0.3, "half", "Pitch"
    Text: 1.5, "centre", -0.3, "half", "Formant"
    Text: 2.5, "centre", -0.3, "half", "Duration"
    Text: 3.5, "centre", -0.3, "half", "Band"
    
    Colour: "Black"
    Draw inner box
    
    # Stats
    Select outer viewport: 0, 8, 5.9, 6.2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Duration: " + fixed$(dur, 2) + "s -> " + fixed$(newDur, 2) + "s | Preset: " + presetName$
    
    Font size: 10
    Colour: "Black"

    # ----------------------------------------------------------
    # Summary strip
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.32, 6.88
    Select inner viewport: 0.60, 7.70, 6.32 + 0.04, 6.88 - 0.04
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    Text: 0.02, "left", 0.45, "half", "Voice pitch/formant mapping • transformed output • diagnostics"
    Text: 0.02, "left", 0.20, "half", "Voice Transformation • run parameters are reported in the Info window"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    pageHeight = 6.98
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Cleanup ===
if durationTier <> 0
    removeObject: durationTier
endif
if shiftedPitchTier <> 0
    removeObject: shiftedPitchTier
endif
if sourcePitchTier <> 0
    removeObject: sourcePitchTier
endif
if analysisManip <> 0
    removeObject: analysisManip
endif
removeObject: analysisMono

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(dur, 2), " s -> ", fixed$(newDur, 2), " s"
appendInfoLine: "Channels preserved: ", nChannels
appendInfoLine: "Peak safety applied: ", peakSafetyApplied

# === Play ===
if play_result
    Play
endif

selectObject: result
