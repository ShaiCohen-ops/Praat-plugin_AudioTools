# ============================================================
# Praat AudioTools - Poisson_Point_Process_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stochastic grain synthesis using Poisson point processes.
#   Events occur at random times with exponentially distributed
#   inter-arrival intervals - a mathematically rigorous approach
#   to statistical texture synthesis (cf. Xenakis).
#
#   Each event triggers a short windowed grain with randomized
#   frequency and duration. Independent L/R processes create
#   spatial depth.
#
# Usage:
#   Run this script and select a preset or customize parameters.
#
# Changelog v0.3:
#   - Chunked synthesis (prevents formula explosion), added viz
#
# Changelog v0.4:
#   - Fixed stereo-width crossfeed: the in-place self[1,col]/self[2,col] mix was
#     row-major asymmetric (the right channel read the already-blended left).
#     Now reads both channels from an unmodified copy -> symmetric crossfeed.
#   - Rebuilt the visualization in the AudioTools house style (8-inch canvas,
#     title band, event timeline + spectrogram, grey summary, larger fonts).
#   - Replaced non-ASCII characters (em-dash, plus-minus).
# ============================================================

form Poisson Point Process Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Sparse Ambience
        option Dense Texture
        option Rhythmic Pulse
        option Wide Stereo Field
        option Ascending Shimmer
        option Granular Cloud
        option Metallic Rain
    
    comment === Global ===
    positive Duration_s 10.0
    integer Sample_rate_Hz 44100
    
    comment === Event Rate (events per second) ===
    positive Left_event_rate 8.0
    positive Right_event_rate 8.0
    
    comment === Frequency (Hz) ===
    positive Left_base_freq_Hz 120
    positive Left_freq_spread_Hz 200
    positive Right_base_freq_Hz 120
    positive Right_freq_spread_Hz 200
    
    comment === Grain Duration (s) ===
    positive Left_grain_dur_s 0.1
    positive Left_grain_spread_s 0.05
    positive Right_grain_dur_s 0.1
    positive Right_grain_spread_s 0.05
    
    comment === Amplitude ===
    positive Left_amplitude 0.6
    positive Right_amplitude 0.6
    real Stereo_width 1.0 (= 0=mono, 1=full stereo)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Sparse Ambience
    left_event_rate = 3.0
    right_event_rate = 2.5
    left_base_freq_Hz = 80
    right_base_freq_Hz = 100
    left_freq_spread_Hz = 150
    right_freq_spread_Hz = 180
    left_grain_dur_s = 0.15
    right_grain_dur_s = 0.18
    left_grain_spread_s = 0.08
    right_grain_spread_s = 0.09
    left_amplitude = 0.5
    right_amplitude = 0.5
    stereo_width = 1.0
    preset_name$ = "SparseAmbience"
    
elsif preset = 3
    # Dense Texture
    left_event_rate = 25.0
    right_event_rate = 22.0
    left_base_freq_Hz = 200
    right_base_freq_Hz = 220
    left_freq_spread_Hz = 400
    right_freq_spread_Hz = 380
    left_grain_dur_s = 0.05
    right_grain_dur_s = 0.06
    left_grain_spread_s = 0.02
    right_grain_spread_s = 0.025
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 0.8
    preset_name$ = "DenseTexture"
    
elsif preset = 4
    # Rhythmic Pulse
    left_event_rate = 12.0
    right_event_rate = 12.0
    left_base_freq_Hz = 100
    right_base_freq_Hz = 105
    left_freq_spread_Hz = 50
    right_freq_spread_Hz = 55
    left_grain_dur_s = 0.08
    right_grain_dur_s = 0.08
    left_grain_spread_s = 0.01
    right_grain_spread_s = 0.01
    left_amplitude = 0.7
    right_amplitude = 0.7
    stereo_width = 0.3
    preset_name$ = "RhythmicPulse"
    
elsif preset = 5
    # Wide Stereo Field
    left_event_rate = 10.0
    right_event_rate = 10.0
    left_base_freq_Hz = 150
    right_base_freq_Hz = 450
    left_freq_spread_Hz = 100
    right_freq_spread_Hz = 300
    left_grain_dur_s = 0.12
    right_grain_dur_s = 0.09
    left_grain_spread_s = 0.05
    right_grain_spread_s = 0.04
    left_amplitude = 0.6
    right_amplitude = 0.6
    stereo_width = 1.0
    preset_name$ = "WideStereo"
    
elsif preset = 6
    # Ascending Shimmer
    left_event_rate = 18.0
    right_event_rate = 16.0
    left_base_freq_Hz = 300
    right_base_freq_Hz = 600
    left_freq_spread_Hz = 500
    right_freq_spread_Hz = 800
    left_grain_dur_s = 0.04
    right_grain_dur_s = 0.03
    left_grain_spread_s = 0.01
    right_grain_spread_s = 0.01
    left_amplitude = 0.45
    right_amplitude = 0.45
    stereo_width = 0.9
    preset_name$ = "AscendingShimmer"
    
elsif preset = 7
    # Granular Cloud
    left_event_rate = 35.0
    right_event_rate = 32.0
    left_base_freq_Hz = 400
    right_base_freq_Hz = 380
    left_freq_spread_Hz = 600
    right_freq_spread_Hz = 620
    left_grain_dur_s = 0.03
    right_grain_dur_s = 0.035
    left_grain_spread_s = 0.015
    right_grain_spread_s = 0.018
    left_amplitude = 0.35
    right_amplitude = 0.35
    stereo_width = 0.85
    preset_name$ = "GranularCloud"
    
elsif preset = 8
    # Metallic Rain
    left_event_rate = 20.0
    right_event_rate = 18.0
    left_base_freq_Hz = 800
    right_base_freq_Hz = 1200
    left_freq_spread_Hz = 1000
    right_freq_spread_Hz = 1500
    left_grain_dur_s = 0.02
    right_grain_dur_s = 0.025
    left_grain_spread_s = 0.008
    right_grain_spread_s = 0.01
    left_amplitude = 0.4
    right_amplitude = 0.4
    stereo_width = 1.0
    preset_name$ = "MetallicRain"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
grainsPerChunk = 25

# === Info ===
writeInfoLine: "=== Poisson Point Process Synthesis ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Left: ", left_event_rate, " events/s, ", left_base_freq_Hz, "+/-", left_freq_spread_Hz/2, " Hz"
appendInfoLine: "Right: ", right_event_rate, " events/s, ", right_base_freq_Hz, "+/-", right_freq_spread_Hz/2, " Hz"
appendInfoLine: ""

# ============================================================
# LEFT CHANNEL
# ============================================================
appendInfoLine: "Processing LEFT channel..."

Create Poisson process: "poisson_L_" + uid$, 0, duration_s, left_event_rate
poissonLeft = selected("PointProcess")

nPointsLeft = Get number of points
appendInfoLine: "  Generated ", nPointsLeft, " Poisson events"

# Store grain parameters
for p to nPointsLeft
    selectObject: poissonLeft
    grainTimeL[p] = Get time from index: p
    grainFreqL[p] = left_base_freq_Hz + left_freq_spread_Hz * (randomUniform(0, 1) - 0.5)
    grainDurL[p] = left_grain_dur_s + left_grain_spread_s * (randomUniform(0, 1) - 0.5)
    grainDurL[p] = max(0.01, grainDurL[p])
    grainAmpL[p] = left_amplitude * (0.7 + 0.3 * randomUniform(0, 1))
    
    if grainTimeL[p] + grainDurL[p] > duration_s
        grainDurL[p] = duration_s - grainTimeL[p]
    endif
endfor

# Create left channel sound
leftSound = Create Sound from formula: "left_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Chunked synthesis
nChunksL = ceiling(nPointsLeft / grainsPerChunk)

for chunk to nChunksL
    startGrain = (chunk - 1) * grainsPerChunk + 1
    endGrain = min(chunk * grainsPerChunk, nPointsLeft)
    
    chunkFormula$ = ""
    
    for g from startGrain to endGrain
        if grainDurL[g] > 0.005
            t$ = fixed$(grainTimeL[g], 6)
            d$ = fixed$(grainDurL[g], 6)
            f$ = fixed$(grainFreqL[g], 2)
            a$ = fixed$(grainAmpL[g], 4)
            
            # Grain: amplitude * sine * Hann window
            grainTerm$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * x) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = grainTerm$
            else
                chunkFormula$ = chunkFormula$ + " + " + grainTerm$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: leftSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Left chunk ", chunk, "/", nChunksL
    endif
endfor

removeObject: poissonLeft

# ============================================================
# RIGHT CHANNEL
# ============================================================
appendInfoLine: ""
appendInfoLine: "Processing RIGHT channel..."

Create Poisson process: "poisson_R_" + uid$, 0, duration_s, right_event_rate
poissonRight = selected("PointProcess")

nPointsRight = Get number of points
appendInfoLine: "  Generated ", nPointsRight, " Poisson events"

# Store grain parameters
for p to nPointsRight
    selectObject: poissonRight
    grainTimeR[p] = Get time from index: p
    grainFreqR[p] = right_base_freq_Hz + right_freq_spread_Hz * (randomUniform(0, 1) - 0.5)
    grainDurR[p] = right_grain_dur_s + right_grain_spread_s * (randomUniform(0, 1) - 0.5)
    grainDurR[p] = max(0.01, grainDurR[p])
    grainAmpR[p] = right_amplitude * (0.7 + 0.3 * randomUniform(0, 1))
    
    if grainTimeR[p] + grainDurR[p] > duration_s
        grainDurR[p] = duration_s - grainTimeR[p]
    endif
endfor

# Create right channel sound
rightSound = Create Sound from formula: "right_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# Chunked synthesis
nChunksR = ceiling(nPointsRight / grainsPerChunk)

for chunk to nChunksR
    startGrain = (chunk - 1) * grainsPerChunk + 1
    endGrain = min(chunk * grainsPerChunk, nPointsRight)
    
    chunkFormula$ = ""
    
    for g from startGrain to endGrain
        if grainDurR[g] > 0.005
            t$ = fixed$(grainTimeR[g], 6)
            d$ = fixed$(grainDurR[g], 6)
            f$ = fixed$(grainFreqR[g], 2)
            a$ = fixed$(grainAmpR[g], 4)
            
            grainTerm$ = "if x >= " + t$ + " and x < " + t$ + " + " + d$ + " then " + a$ + " * sin(twoPi * " + f$ + " * x) * (1 - cos(twoPi * (x - " + t$ + ") / " + d$ + ")) / 2 else 0 fi"
            
            if chunkFormula$ = ""
                chunkFormula$ = grainTerm$
            else
                chunkFormula$ = chunkFormula$ + " + " + grainTerm$
            endif
        endif
    endfor
    
    if chunkFormula$ <> ""
        selectObject: rightSound
        Formula: "self + (" + chunkFormula$ + ")"
    endif
    
    if chunk mod 5 = 0
        appendInfoLine: "  Right chunk ", chunk, "/", nChunksR
    endif
endfor

removeObject: poissonRight

# ============================================================
# COMBINE TO STEREO
# ============================================================
appendInfoLine: ""
appendInfoLine: "Combining to stereo..."

selectObject: leftSound
plusObject: rightSound
outputSound = Combine to stereo
Rename: "poisson_" + preset_name$

removeObject: leftSound, rightSound

# Apply stereo width
if stereo_width < 1.0
    selectObject: outputSound
    Copy: "preWidth_" + uid$
    preWidth = selected("Sound")
    selectObject: outputSound
    widthMix = 1 - stereo_width
    # Symmetric crossfeed: read both channels from the unmodified copy.
    # In-place self[1,col]/self[2,col] is row-major, so the right channel would
    # read the already-blended left and over-mix (asymmetric L/R).
    Formula: "if row = 1 then self + " + fixed$(widthMix, 2) + " * object[preWidth, 2, col] else self + " + fixed$(widthMix, 2) + " * object[preWidth, 1, col] fi"
    removeObject: preWidth
endif

# === Fade In/Out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"

# === Normalize ===
selectObject: outputSound
Scale peak: 0.9

# === Visualization ===
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Total events: ", nPointsLeft + nPointsRight, " (L: ", nPointsLeft, ", R: ", nPointsRight, ")"
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Poisson Point Process: " + preset_name$

    # --- Panel 1: Event timeline (L blue bottom, R red top) ---
    Select outer viewport: 0, 8, 0.9, 2.5
    Select inner viewport: 0.75, 7.6, 1.05, 2.4
    Axes: 0, duration_s, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, duration_s, 0, 2

    for .p to nPointsLeft
        .t = grainTimeL[.p]
        .d = grainDurL[.p]
        .a = grainAmpL[.p] / left_amplitude
        Paint rectangle: "{0.20, 0.50, 0.80}", .t, .t + .d, 0, .a * 0.9
    endfor
    for .p to nPointsRight
        .t = grainTimeR[.p]
        .d = grainDurR[.p]
        .a = grainAmpR[.p] / right_amplitude
        Paint rectangle: "{0.80, 0.30, 0.20}", .t, .t + .d, 1, 1 + .a * 0.9
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "L          R"
    Text bottom: "yes", "Time (s)"

    # --- Panel 2: Spectrogram ---
    Select outer viewport: 0, 8, 2.7, 4.9
    Select inner viewport: 0.75, 7.6, 2.85, 4.8
    selectObject: outputSound
    Extract one channel: 1
    .monoSpec = selected("Sound")
    .maxFreq = max(left_base_freq_Hz + left_freq_spread_Hz, right_base_freq_Hz + right_freq_spread_Hz) * 1.5
    .maxFreq = max(2000, .maxFreq)
    selectObject: .monoSpec
    To Spectrogram: 0.02, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .monoSpec, .spec

    Select inner viewport: 0.75, 7.6, 2.85, 4.8
    Axes: 0, duration_s, 0, .maxFreq
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Font size: 10
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 5.0, 5.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "L: " + fixed$(left_event_rate, 1) + "/s @ " + fixed$(left_base_freq_Hz, 0) + " Hz | R: " + fixed$(right_event_rate, 1) + "/s @ " + fixed$(right_base_freq_Hz, 0) + " Hz | " + string$(nPointsLeft + nPointsRight) + " events | Blue=L, Red=R"
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc