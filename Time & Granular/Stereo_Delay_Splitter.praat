# ============================================================
# Praat AudioTools - Stereo_Delay_Splitter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Delay Splitter - per channel, applies an FIR high-pass comb
#   (y[n] = x[n+D] - x[n], zero at DC) with different delays on L and R
#   to create stereo width / spectral separation.
#   Delay_mode selects how D is set:
#     Divisor      - D = totalSamples/divisor (fraction of file). Notch
#                    spacing is only divisor/duration Hz, so perceptually
#                    broadband decorrelation/widening, not tonal comb, and
#                    the forward read leaves the last 1/divisor dry.
#     Milliseconds - fixed short delays for audible tonal comb filtering.
#     Tempo-synced - delays set as note values (1/2..1/32, incl. dotted)
#                    at Manual_bpm; D = beats * (60/bpm) * sampleRate.
#
# Changelog v0.5:
#   - Added Wet_dry mix (0 = dry, 1 = fully wet). Each channel is mixed
#     against its pre-processing dry copy. Default 1.0 reproduces v0.4.
#
# Changelog v0.4:
#   - Added Tempo-synced delay mode: per-channel note values at a manual
#     BPM (1/2, 1/4, 1/4., 1/8, 1/8., 1/16, 1/16., 1/32). Delay_mode is
#     now a 3-way selector (Divisor / Milliseconds / Tempo-synced),
#     replacing the Use_ms_delay boolean.
#   - Info warns if a delay >= file length (that pass leaves the channel dry).
#
# Changelog v0.3:
#   - Added optional millisecond-delay mode (Use_ms_delay, off by default)
#     for true audible comb filtering; divisor mode unchanged when off.
#   - Delays clamped to >=1 sample (a 0-sample delay would null the channel).
#   - Viz fix: spectra are now computed on a mono fold (To Spectrum is
#     mono-only; result is always stereo, so the panel crashed every run).
#   - Viz fix: divisor/delay info text was placed in inherited spectrum
#     axes (clamped off-panel); now drawn in normalized axes.
#   - Description corrected to describe the actual effect.
# ============================================================

form Stereo Delay Splitter
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Default (L:2,4 | R:8,10)
        option Narrow Stereo (L:3,5 | R:6,8)
        option Wide Stereo (L:2,6 | R:12,18)
        option Alt Divisors (L:2,3 | R:9,15)
        option Custom
    
    comment === Left Channel Divisors ===
    positive Divisor_L1 2
    positive Divisor_L2 4
    
    comment === Right Channel Divisors ===
    positive Divisor_R1 8
    positive Divisor_R2 10
    
    comment === Delay Mode ===
    optionmenu Delay_mode 1
        option Divisor (fraction of file)
        option Milliseconds
        option Tempo-synced (BPM)
    
    comment === Millisecond Delays (Milliseconds mode) ===
    positive Delay_L1_ms 3
    positive Delay_L2_ms 5
    positive Delay_R1_ms 7
    positive Delay_R2_ms 11
    
    comment === Tempo (Tempo-synced mode) ===
    positive Manual_bpm 120
    optionmenu Note_L1 4
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_L2 6
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_R1 2
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    optionmenu Note_R2 5
        option 1/2
        option 1/4
        option 1/4 dotted
        option 1/8
        option 1/8 dotted
        option 1/16
        option 1/16 dotted
        option 1/32
    
    comment === Mix ===
    real Wet_dry 1.0
    
    comment === Output ===
    positive Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 1
    # Default
    divisor_L1 = 2
    divisor_L2 = 4
    divisor_R1 = 8
    divisor_R2 = 10
elsif preset = 2
    # Narrow Stereo
    divisor_L1 = 3
    divisor_L2 = 5
    divisor_R1 = 6
    divisor_R2 = 8
elsif preset = 3
    # Wide Stereo
    divisor_L1 = 2
    divisor_L2 = 6
    divisor_R1 = 12
    divisor_R2 = 18
elsif preset = 4
    # Alt Divisors
    divisor_L1 = 2
    divisor_L2 = 3
    divisor_R1 = 9
    divisor_R2 = 15
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
duration = Get total duration
totalSamples = Get number of samples
numChannels = Get number of channels

# === Get Preset Name ===
if preset = 1
    presetName$ = "Default"
elsif preset = 2
    presetName$ = "Narrow"
elsif preset = 3
    presetName$ = "Wide"
elsif preset = 4
    presetName$ = "Alt"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Stereo Delay Splitter ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Left divisors: ", divisor_L1, ", ", divisor_L2
appendInfoLine: "Right divisors: ", divisor_R1, ", ", divisor_R2
appendInfoLine: ""

# === Prepare Source ===
if numChannels = 1
    selectObject: original
    Copy: "left_tmp"
    selectObject: original
    Copy: "right_tmp"
    selectObject: "Sound left_tmp", "Sound right_tmp"
    Combine to stereo
    sourceSound = selected("Sound")
    # Clean up the temporary mono copies
    removeObject: "Sound left_tmp", "Sound right_tmp"
    appendInfoLine: "Converted mono to stereo for processing"
else
    selectObject: original
    Copy: "stereo_temp"
    sourceSound = selected("Sound")
endif

# === Calculate Delays ===
if delay_mode = 2
    # Milliseconds
    delayL1 = round(delay_L1_ms / 1000 * sampleRate)
    delayL2 = round(delay_L2_ms / 1000 * sampleRate)
    delayR1 = round(delay_R1_ms / 1000 * sampleRate)
    delayR2 = round(delay_R2_ms / 1000 * sampleRate)
elsif delay_mode = 3
    # Tempo-synced: beats = multiple of the quarter-note (the beat)
    # note option -> beats: 1/2, 1/4, 1/4., 1/8, 1/8., 1/16, 1/16., 1/32
    beatsTable# = {2, 1, 1.5, 0.5, 0.75, 0.25, 0.375, 0.125}
    beat = 60 / manual_bpm
    delayL1 = round(beatsTable#[note_L1] * beat * sampleRate)
    delayL2 = round(beatsTable#[note_L2] * beat * sampleRate)
    delayR1 = round(beatsTable#[note_R1] * beat * sampleRate)
    delayR2 = round(beatsTable#[note_R2] * beat * sampleRate)
else
    # Divisor (fraction of file)
    delayL1 = round(totalSamples / divisor_L1)
    delayL2 = round(totalSamples / divisor_L2)
    delayR1 = round(totalSamples / divisor_R1)
    delayR2 = round(totalSamples / divisor_R2)
endif

# Clamp to >=1 sample (a 0-sample delay would null the channel)
if delayL1 < 1
    delayL1 = 1
endif
if delayL2 < 1
    delayL2 = 1
endif
if delayR1 < 1
    delayR1 = 1
endif
if delayR2 < 1
    delayR2 = 1
endif

if delay_mode = 2
    delayLabel$ = "L: " + fixed$(delay_L1_ms, 1) + ", " + fixed$(delay_L2_ms, 1) + " ms | R: " + fixed$(delay_R1_ms, 1) + ", " + fixed$(delay_R2_ms, 1) + " ms | FIR high-pass comb"
    appendInfoLine: "Delay mode: millisecond (comb filtering)"
elsif delay_mode = 3
    @noteName: note_L1
    nL1$ = noteName$
    @noteName: note_L2
    nL2$ = noteName$
    @noteName: note_R1
    nR1$ = noteName$
    @noteName: note_R2
    nR2$ = noteName$
    delayLabel$ = "Tempo " + string$(manual_bpm) + " BPM | L: " + nL1$ + ", " + nL2$ + " | R: " + nR1$ + ", " + nR2$ + " | FIR high-pass comb"
    appendInfoLine: "Delay mode: tempo-synced (", manual_bpm, " BPM)"
else
    delayLabel$ = "L: " + string$(divisor_L1) + ", " + string$(divisor_L2) + " | R: " + string$(divisor_R1) + ", " + string$(divisor_R2) + " (divisors) | dense comb -> decorrelation/widening"
    appendInfoLine: "Delay mode: divisor (fraction of file)"
endif

# Warn if any delay reaches the file length (that channel iteration is a no-op)
if delayL1 >= totalSamples or delayL2 >= totalSamples or delayR1 >= totalSamples or delayR2 >= totalSamples
    appendInfoLine: "WARNING: a delay >= file length; that pass leaves the channel dry"
endif

appendInfoLine: "Left delays: ", delayL1, ", ", delayL2, " samples"
appendInfoLine: "Right delays: ", delayR1, ", ", delayR2, " samples"

# Wet/dry clamp to [0,1]
if wet_dry < 0
    wet_dry = 0
endif
if wet_dry > 1
    wet_dry = 1
endif
appendInfoLine: "Wet/dry: ", fixed$(wet_dry, 2)
appendInfoLine: ""

# === Process Left Channel ===
selectObject: sourceSound
Extract one channel: 1
leftDry = selected("Sound")
Rename: "LeftDry"
Copy: "Left"
leftChannel = selected("Sound")

appendInfoLine: "Processing left channel..."

# Iteration 1
selectObject: leftChannel
Formula: ~ if col + delayL1 <= ncol then self[col + delayL1] - self else self fi

# Iteration 2
Formula: ~ if col + delayL2 <= ncol then self[col + delayL2] - self else self fi

# Wet/dry mix against the dry channel
selectObject: leftChannel
Formula: ~ self * wet_dry + object[leftDry, row, col] * (1 - wet_dry)

# === Process Right Channel ===
selectObject: sourceSound
Extract one channel: 2
rightDry = selected("Sound")
Rename: "RightDry"
Copy: "Right"
rightChannel = selected("Sound")

appendInfoLine: "Processing right channel..."

# Iteration 1
selectObject: rightChannel
Formula: ~ if col + delayR1 <= ncol then self[col + delayR1] - self else self fi

# Iteration 2
Formula: ~ if col + delayR2 <= ncol then self[col + delayR2] - self else self fi

# Wet/dry mix against the dry channel
selectObject: rightChannel
Formula: ~ self * wet_dry + object[rightDry, row, col] * (1 - wet_dry)

# === Combine to Stereo ===
selectObject: leftChannel, rightChannel
Combine to stereo
result = selected("Sound")
Rename: original_name$ + "_stereo_split"

Scale peak: scale_peak

# === Cleanup ===
removeObject: leftChannel, rightChannel, leftDry, rightDry, sourceSound

# === Visualization ===
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 1, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Stereo Delay Splitter: " + original_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform (stereo)
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Stereo Split"
    Text bottom: "yes", "Time (s)"
    
    # Original spectrum
    Select outer viewport: 0, 4, 3.7, 5.3
    Select inner viewport: 0.6, 3.8, 3.9, 5.2
    selectObject: original
    nch = Get number of channels
    if nch > 1
        specMono = Convert to mono
    else
        specMono = Copy: "specMono"
    endif
    To Spectrum: "yes"
    origSpec = selected("Spectrum")
    Draw: 0, 5000, 0, 80, "no"
    removeObject: origSpec, specMono
    Colour: "{0.8, 0.5, 0.6}"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Original spectrum (Hz)"
    
    # Result spectrum (shows comb filtering)
    Select outer viewport: 4, 8, 3.7, 5.3
    Select inner viewport: 4.4, 7.6, 3.9, 5.2
    selectObject: result
    resMono = Convert to mono
    To Spectrum: "yes"
    resSpec = selected("Spectrum")
    Draw: 0, 5000, 0, 80, "no"
    removeObject: resSpec, resMono
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "dB"
    Text bottom: "yes", "Split spectrum (Hz)"
    
    # Delay info
    Select outer viewport: 0, 8, 5.4, 5.7
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", delayLabel$
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result

procedure noteName: .opt
    if .opt = 1
        noteName$ = "1/2"
    elsif .opt = 2
        noteName$ = "1/4"
    elsif .opt = 3
        noteName$ = "1/4."
    elsif .opt = 4
        noteName$ = "1/8"
    elsif .opt = 5
        noteName$ = "1/8."
    elsif .opt = 6
        noteName$ = "1/16"
    elsif .opt = 7
        noteName$ = "1/16."
    else
        noteName$ = "1/32"
    endif
endproc