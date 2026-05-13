# ============================================================
# Praat AudioTools - Brightness_Sorted_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brightness Sorted Grains - extracts grains from audio and
#   sorts them by spectral centroid (brightness) before
#   concatenation. Creates spectral sweep effects from dark
#   to bright or bright to dark.
#
# Algorithmic notes:
#   - Grain extraction: random source-time selection, Extract part
#     with chosen window shape.
#   - Brightness measurement: spectral centroid (centre of gravity
#     of Spectrum object, exponent 2).
#   - Spectral exaggeration: bright grains get high-freq boost,
#     dark grains get low-freq boost. Reinforces the natural
#     brightness contrast for stronger spectral sweep effect.
#   - "Pitch scatter" parameter is mislabeled in v0.2. The actual
#     Formula `if x > 0 then self * shift_factor else self fi`
#     applies a UNIFORM gain across all positive-frequency bins,
#     which is amplitude scatter, not pitch shift. Per-grain
#     loudness varies; pitch does not. v0.3 keeps the existing
#     audio behavior (form field name preserved for backward
#     compatibility with saved settings); the misnomer is flagged
#     in Panel B's parameter report. If you want it renamed in
#     a future v0.4, ask.
#   - Sort: bubble sort O(N^2), fine for max 500 grains.
#   - Concatenation: iterative pairwise Concatenate, also O(N^2).
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - CRITICAL FIX: Removed duplicate `=== Done ===` block at
#     end of script. v0.2 had two final-report sections (lines
#     572-606 in the original) — for grainCount > 0 the script
#     printed stats and called Play TWICE; for grainCount = 0
#     the second block referenced undefined variables and
#     would error. v0.3 has a single, conditional final report.
#   - Audio output is bit-identical to v0.2 for the same form
#     parameters AND same Praat RNG state — except Play runs
#     once instead of twice.
#   - Form syntax modernized: 5 `optionmenu X:` with colons
#     (Preset, Grain_size_mode, Window_type, Sort_direction,
#     Exaggeration_intensity).
#   - Dropped 8 decorative form lines (6 `comment === ... ===`
#     section dividers, 1 instructional, 1 inline parenthetical).
#     Form went from ~22 effective rows to 14.
#   - NEW: Show_spectrograms boolean form toggle (default OFF).
#     v0.2 always computed two `To Spectrogram` calls. Default
#     OFF skips them; ON puts side-by-side spectrograms in
#     Panel D (replacing the waveform comparison).
#   - Output filename now includes preset name suffix:
#     `<name>_brightness_sorted_<presetName>` (e.g.
#     `_brightness_sorted_DenseCloud`). v0.2 was just
#     `<name>_brightness_sorted`.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x6.7 with title + 2 waveforms + brightness bars + 2
#     spectrograms + stats line):
#       Title bar + metadata subtitle (preset, grain count,
#         brightness range, sort direction, gap, exaggeration)
#       Panel A (left, headline): brightness distribution —
#         PRESERVED v0.2 design (bars with dark blue -> bright
#         yellow gradient + red trend line)
#       Panel B (right, headline): parameter report — algorithm
#         explanation, settings, sort direction, exaggeration
#         intensity, gain-scatter clarification
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         blue = sorted, SHARED y-axis)
#       Panel D: full waveform comparison (gray = original,
#         blue = sorted, SHARED y-axis) OR side-by-side
#         spectrograms (when Show_spectrograms = ON)
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed mono conversion bug
#   - Added presets
#   - Added visualization
#   - Improved sorting display
#   - Renamed for clarity
# ============================================================

form Brightness Sorted Grains v0.3
    optionmenu Preset: 1
        option Custom
        option Gentle Sweep (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, fast)
        option Long Drones (slow evolution)
        option Extreme Sort (strong exaggeration)
    positive Grain_size_ms 150
    positive Grain_size_variation_ms 50
    optionmenu Grain_size_mode: 1
        option Fixed
        option Random
    positive Grain_overlap 0.3
    positive Density_factor 1.5
    positive Pitch_scatter 0.2
    boolean Reverse_grains 0
    optionmenu Window_type: 2
        option Rectangular
        option Triangular
        option Parabolic
    boolean Sort_grains 1
    optionmenu Sort_direction: 1
        option Dark to bright
        option Bright to dark
    positive Gap_between_grains_ms 50
    boolean Exaggerate_spectral 1
    optionmenu Exaggeration_intensity: 2
        option Subtle
        option Moderate
        option Strong
    boolean Show_spectrograms 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
presetName$ = "Custom"

if preset = 2
    # Gentle Sweep
    grain_size_ms = 200
    grain_size_variation_ms = 30
    grain_size_mode = 1
    grain_overlap = 0.2
    density_factor = 0.8
    pitch_scatter = 0.1
    reverse_grains = 0
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 80
    exaggerate_spectral = 1
    exaggeration_intensity = 1
    presetName$ = "GentleSweep"
elsif preset = 3
    # Dense Cloud
    grain_size_ms = 100
    grain_size_variation_ms = 40
    grain_size_mode = 2
    grain_overlap = 0.5
    density_factor = 2.5
    pitch_scatter = 0.3
    reverse_grains = 1
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 20
    exaggerate_spectral = 1
    exaggeration_intensity = 2
    presetName$ = "DenseCloud"
elsif preset = 4
    # Micro Grains
    grain_size_ms = 50
    grain_size_variation_ms = 20
    grain_size_mode = 2
    grain_overlap = 0.4
    density_factor = 3.0
    pitch_scatter = 0.4
    reverse_grains = 0
    window_type = 3
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 10
    exaggerate_spectral = 0
    exaggeration_intensity = 2
    presetName$ = "MicroGrains"
elsif preset = 5
    # Long Drones
    grain_size_ms = 400
    grain_size_variation_ms = 100
    grain_size_mode = 2
    grain_overlap = 0.6
    density_factor = 0.5
    pitch_scatter = 0.05
    reverse_grains = 0
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 150
    exaggerate_spectral = 1
    exaggeration_intensity = 1
    presetName$ = "LongDrones"
elsif preset = 6
    # Extreme Sort
    grain_size_ms = 120
    grain_size_variation_ms = 50
    grain_size_mode = 2
    grain_overlap = 0.3
    density_factor = 2.0
    pitch_scatter = 0.5
    reverse_grains = 1
    window_type = 2
    sort_grains = 1
    sort_direction = 1
    gap_between_grains_ms = 40
    exaggerate_spectral = 1
    exaggeration_intensity = 3
    presetName$ = "ExtremeSort"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sample_rate = Get sampling frequency
num_channels = Get number of channels

# === Convert to Mono ===
selectObject: original
if num_channels > 1
    Convert to mono
    sound = selected("Sound")
else
    Copy: "mono_temp"
    sound = selected("Sound")
endif

# === Validate Parameters ===
if duration < grain_size_ms / 1000
    removeObject: sound
    exitScript: "Sound is shorter than grain size"
endif

if grain_size_mode = 2 and grain_size_variation_ms > grain_size_ms
    grain_size_variation_ms = grain_size_ms * 0.8
endif

# === Calculate Grain Parameters ===
base_grain_duration = grain_size_ms / 1000
hop_time = base_grain_duration * (1 - grain_overlap)
num_grains = round((duration / hop_time) * density_factor)

# Limit grain count for performance
if num_grains > 500
    num_grains = 500
endif

# === Get Window Shape ===
if window_type = 1
    window_shape$ = "rectangular"
elsif window_type = 2
    window_shape$ = "triangular"
else
    window_shape$ = "parabolic"
endif

# === Get Exaggeration Factor ===
if exaggeration_intensity = 1
    spectral_boost = 1.2
    exaggerationLabel$ = "Subtle"
elsif exaggeration_intensity = 2
    spectral_boost = 1.5
    exaggerationLabel$ = "Moderate"
else
    spectral_boost = 2.0
    exaggerationLabel$ = "Strong"
endif

if sort_direction = 1
    sortLabel$ = "Dark -> Bright"
else
    sortLabel$ = "Bright -> Dark"
endif

# === Info ===
writeInfoLine: "=== Brightness Sorted Grains v0.3 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Target grains: ", num_grains
appendInfoLine: "Grain size: ", grain_size_ms, " ms"
if grain_size_mode = 2
    appendInfoLine: "Size variation: +/- ", grain_size_variation_ms, " ms"
endif
appendInfoLine: ""

# === Arrays ===
grainIDs# = zero#(num_grains)
grainBrightness# = zero#(num_grains)
grainOriginalBrightness# = zero#(num_grains)
grainDurations# = zero#(num_grains)
grainCount = 0

# === Generate Grains ===
appendInfoLine: "Generating grains..."

for i from 1 to num_grains
    # Calculate grain duration
    if grain_size_mode = 1
        grain_duration = base_grain_duration
    else
        variation_seconds = (grain_size_variation_ms / 1000) * randomUniform(-1, 1)
        grain_duration = base_grain_duration + variation_seconds
        min_duration = base_grain_duration * 0.3
        max_duration = base_grain_duration * 2.0
        grain_duration = max(min_duration, min(max_duration, grain_duration))
    endif
    
    # Get source time
    max_start = duration - grain_duration
    if max_start > 0
        source_time = randomUniform(0, max_start)
        
        # Extract grain
        selectObject: sound
        Extract part: source_time, source_time + grain_duration, window_shape$, 1, "no"
        grain = selected("Sound")
        
        # Get spectral centroid (brightness)
        selectObject: grain
        To Spectrum: "yes"
        spectrum = selected("Spectrum")
        centroid = Get centre of gravity: 2
        brightness = centroid
        original_brightness = brightness
        removeObject: spectrum
        
        # Spectral exaggeration
        if exaggerate_spectral
            selectObject: grain
            To Spectrum: "yes"
            spectrum = selected("Spectrum")
            
            if brightness > 1000
                # Bright grains - emphasize high frequencies
                Formula: "if x > 1000 then self * spectral_boost else self fi"
                brightness = brightness * 1.3
            else
                # Dark grains - emphasize low frequencies
                Formula: "if x < 800 then self * spectral_boost else self fi"
                brightness = brightness * 0.7
            endif
            
            To Sound
            processed_grain = selected("Sound")
            removeObject: spectrum, grain
            grain = processed_grain
        endif
        
        # Pitch scatter (mislabeled — actually a gain scatter, see header)
        selectObject: grain
        if original_brightness > 1500
            grain_pitch_shift = randomGauss(0.5, pitch_scatter * 1.5)
        elsif original_brightness < 800
            grain_pitch_shift = randomGauss(-0.3, pitch_scatter * 0.8)
        else
            grain_pitch_shift = randomGauss(0, pitch_scatter)
        endif
        
        if abs(grain_pitch_shift) > 0.01
            selectObject: grain
            To Spectrum: "yes"
            spectrum_grain = selected("Spectrum")
            shift_factor = 2^(grain_pitch_shift / 12)
            Formula: "if x > 0 then self * shift_factor else self fi"
            To Sound
            shifted_grain = selected("Sound")
            removeObject: spectrum_grain, grain
            grain = shifted_grain
        endif
        
        # Random reverse
        selectObject: grain
        if reverse_grains and randomUniform(0, 1) > 0.7
            Reverse
            brightness = brightness * 0.9
        endif
        
        # Amplitude scaling based on brightness
        selectObject: grain
        if brightness > 1500
            Scale peak: 0.35
        elsif brightness < 800
            Scale peak: 0.25
        else
            Scale peak: 0.3
        endif
        
        # Store grain
        grainCount += 1
        grainIDs#[grainCount] = grain
        grainBrightness#[grainCount] = brightness
        grainOriginalBrightness#[grainCount] = original_brightness
        grainDurations#[grainCount] = grain_duration
    endif
endfor

appendInfoLine: "Created ", grainCount, " grains"

# === Sort Grains by Brightness ===
if sort_grains and grainCount > 1
    appendInfoLine: ""
    appendInfoLine: "Sorting by brightness..."
    
    # Bubble sort (simple, works fine for <500 grains)
    for i from 1 to grainCount
        for j from i + 1 to grainCount
            doSwap = 0
            if sort_direction = 1 and grainBrightness#[i] > grainBrightness#[j]
                doSwap = 1
            elsif sort_direction = 2 and grainBrightness#[i] < grainBrightness#[j]
                doSwap = 1
            endif
            
            if doSwap
                # Swap all arrays
                tempBrightness = grainBrightness#[i]
                grainBrightness#[i] = grainBrightness#[j]
                grainBrightness#[j] = tempBrightness
                
                tempOriginal = grainOriginalBrightness#[i]
                grainOriginalBrightness#[i] = grainOriginalBrightness#[j]
                grainOriginalBrightness#[j] = tempOriginal
                
                tempGrain = grainIDs#[i]
                grainIDs#[i] = grainIDs#[j]
                grainIDs#[j] = tempGrain
                
                tempDuration = grainDurations#[i]
                grainDurations#[i] = grainDurations#[j]
                grainDurations#[j] = tempDuration
            endif
        endfor
    endfor
    
    appendInfoLine: "Sorted: ", sortLabel$
endif

# === Create Silence for Gaps ===
gap_duration = gap_between_grains_ms / 1000
if gap_duration > 0
    silence = Create Sound from formula: "silence", 1, 0, gap_duration, sample_rate, "0"
endif

# === Concatenate Grains ===
if grainCount > 0
    appendInfoLine: ""
    appendInfoLine: "Concatenating..."
    
    # Start with first grain
    selectObject: grainIDs#[1]
    temp_sound = Copy: "temp_concat"
    
    for i from 2 to grainCount
        if grainIDs#[i] > 0
            if gap_duration > 0
                selectObject: temp_sound, silence
                Concatenate
                temp_with_gap = selected("Sound")
                selectObject: temp_with_gap, grainIDs#[i]
                Concatenate
                new_temp = selected("Sound")
                removeObject: temp_sound, temp_with_gap
                temp_sound = new_temp
            else
                selectObject: temp_sound, grainIDs#[i]
                Concatenate
                new_temp = selected("Sound")
                removeObject: temp_sound
                temp_sound = new_temp
            endif
        endif
    endfor
    
    selectObject: temp_sound
    Copy: sound_name$ + "_brightness_sorted_" + presetName$
    result = selected("Sound")
    removeObject: temp_sound
    
    # Cleanup
    if gap_duration > 0
        removeObject: silence
    endif
    
    for i from 1 to grainCount
        if grainIDs#[i] > 0
            removeObject: grainIDs#[i]
        endif
    endfor
    
    # Final scaling
    selectObject: result
    Scale peak: 0.9
    
    # Get stats
    selectObject: result
    output_duration = Get total duration
    
    minBrightness = grainBrightness#[1]
    maxBrightness = grainBrightness#[grainCount]
    if sort_direction = 2
        minBrightness = grainBrightness#[grainCount]
        maxBrightness = grainBrightness#[1]
    endif
endif

# Cleanup mono copy
removeObject: sound

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
if draw_visualization and grainCount > 0
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # Mono copy of original (result is already mono)
    selectObject: original
    if num_channels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    selectObject: result
    finalPeak = Get absolute extremum: 0, 0, "None"
    
    # Compute SHARED y-axis from BOTH original and result
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: result
    pPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if pPeak > sharedPeak
        sharedPeak = pPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # Find brightness range for Panel A
    minB = grainBrightness#[1]
    maxB = grainBrightness#[1]
    for i from 2 to grainCount
        if grainBrightness#[i] < minB
            minB = grainBrightness#[i]
        endif
        if grainBrightness#[i] > maxB
            maxB = grainBrightness#[i]
        endif
    endfor
    
    if maxB = minB
        maxB = minB + 1
    endif
    
    # Compute spectrograms only if user opted in
    if show_spectrograms
        selectObject: vizOrig
        origSpec = To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
        selectObject: result
        resSpec = To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BRIGHTNESS SORTED GRAINS##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... sound_name$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(grainCount) + " grains"
        ... + "  |  " + fixed$(minB, 0) + "-" + fixed$(maxB, 0) + " Hz"
        ... + "  |  " + sortLabel$
        ... + "  |  gap " + fixed$(gap_between_grains_ms, 0) + " ms"
    
    # ----------------------------------------------------------
    # PANEL A: BRIGHTNESS DISTRIBUTION  (left, headline)
    # PRESERVED v0.2 design: bars (dark blue -> bright yellow
    # gradient) + red trend line.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, grainCount + 0.5, 0, maxB * 1.1
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, grainCount + 0.5, 0, maxB * 1.1
    
    # Reference grid
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, maxB * 0.25, grainCount + 0.5, maxB * 0.25
    Draw line: 0, maxB * 0.50, grainCount + 0.5, maxB * 0.50
    Draw line: 0, maxB * 0.75, grainCount + 0.5, maxB * 0.75
    Solid line
    
    # Draw brightness bars
    for i from 1 to grainCount
        brightness = grainBrightness#[i]
        
        # Color gradient: dark (blue) to bright (yellow)
        normalizedB = (brightness - minB) / (maxB - minB)
        r = normalizedB
        g = normalizedB * 0.8
        b = 1 - normalizedB
        barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        Paint rectangle: barColor$, i - 0.4, i + 0.4, 0, brightness
    endfor
    
    # Draw trend line (red, on top of bars)
    Colour: "{0.85, 0.25, 0.25}"
    Line width: 2
    for i from 2 to grainCount
        Draw line: i - 1, grainBrightness#[i - 1], i, grainBrightness#[i]
    endfor
    Line width: 1
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Brightness (Hz)"
    Text bottom: "yes", "Grain # (sorted order)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "Algorithm:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.88, "half", "Extract grains -> spectral centroid ->"
    Text: 0.10, "left", 0.83, "half", "exaggerate -> sort -> concatenate."
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.75, "half", "Grains:"
    
    Font size: 9
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0.10, "left", 0.69, "half", "Size: " + fixed$(grain_size_ms, 0) + " ms"
    if grain_size_mode = 2
        Text: 0.10, "left", 0.63, "half", "Variation: +/- " + fixed$(grain_size_variation_ms, 0) + " ms (random)"
    else
        Text: 0.10, "left", 0.63, "half", "Variation: fixed"
    endif
    Text: 0.10, "left", 0.57, "half", "Overlap: " + fixed$(grain_overlap, 2) + " | Density: " + fixed$(density_factor, 2)
    Text: 0.10, "left", 0.51, "half", "Window: " + window_shape$
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.43, "half", "Sort + Exaggerate:"
    
    Font size: 9
    Colour: "{0.30, 0.55, 0.30}"
    if sort_grains
        Text: 0.10, "left", 0.37, "half", "Direction: " + sortLabel$
    else
        Text: 0.10, "left", 0.37, "half", "Sort: OFF (original order)"
    endif
    if exaggerate_spectral
        Text: 0.10, "left", 0.31, "half", "Exaggeration: " + exaggerationLabel$ + " (x" + fixed$(spectral_boost, 2) + ")"
    else
        Text: 0.10, "left", 0.31, "half", "Exaggeration: OFF"
    endif
    Text: 0.10, "left", 0.25, "half", "Gap: " + fixed$(gap_between_grains_ms, 0) + " ms"
    if reverse_grains
        Text: 0.10, "left", 0.19, "half", "Random reverse: 30% of grains"
    else
        Text: 0.10, "left", 0.19, "half", "Random reverse: OFF"
    endif
    
    # Pitch scatter clarification
    Font size: 7
    Colour: "{0.55, 0.30, 0.20}"
    Text: 0.05, "left", 0.10, "half", "Note: 'Pitch scatter' (" + fixed$(pitch_scatter, 2) + ") applies"
    Text: 0.05, "left", 0.05, "half", "uniform spectrum gain, not pitch shift"
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Brightness per grain (sorted order; bars + trend line)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, blue = sorted.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.5
    if zoomDur > duration
        zoomDur = duration
    endif
    if zoomDur > output_duration
        zoomDur = output_duration
    endif
    
    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Sorted on top
    selectObject: result
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = sorted)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: WAVEFORM COMPARISON or SPECTROGRAMS
    # ----------------------------------------------------------
    
    if show_spectrograms
        # Side-by-side spectrograms (original | sorted)
        
        # Original spectrogram (left half)
        Select outer viewport: 0, 4, 5.62, 6.55
        Select inner viewport: 0.55, 3.85, 5.69, 6.48
        
        selectObject: origSpec
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Original spectrogram"
        Text left: "yes", "Freq (Hz)"
        Text bottom: "yes", "Time (s)"
        
        # Sorted spectrogram (right half)
        Select outer viewport: 4, 8, 5.62, 6.55
        Select inner viewport: 4.10, 7.72, 5.69, 6.48
        
        selectObject: resSpec
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Sorted spectrogram (spectral sweep)"
        Text bottom: "yes", "Time (s)"
    else
        # Full waveform comparison (overlaid, SHARED y-axis)
        Select outer viewport: 0, 8, 5.62, 6.55
        Select inner viewport: 0.55, 7.72, 5.69, 6.48
        
        Axes: 0, output_duration, -sharedAmp, sharedAmp
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, output_duration, -sharedAmp, sharedAmp
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, output_duration, 0
        
        # Original behind (only as far as it goes)
        selectObject: vizOrig
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, output_duration, -sharedAmp, sharedAmp, "no", "Curve"
        
        # Sorted on top
        selectObject: result
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, output_duration, -sharedAmp, sharedAmp, "no", "Curve"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Full waveform  (gray = original, blue = sorted, shared y-axis)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrograms
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + sound_name$
        ... + "  |  Grains: " + string$(grainCount)
        ... + "  |  Brightness: " + fixed$(minBrightness, 0) + "-" + fixed$(maxBrightness, 0) + " Hz"
        ... + "  |  " + sortLabel$
        ... + "  |  Exaggerate: " + exaggerationLabel$
    
    Text: 0.02, "left", 0.28, "half",
        ... "Size: " + fixed$(grain_size_ms, 0) + " ms"
        ... + "  |  Overlap: " + fixed$(grain_overlap, 2)
        ... + "  |  Gap: " + fixed$(gap_between_grains_ms, 0) + " ms"
        ... + "  |  Window: " + window_shape$
        ... + "  |  In: " + fixed$(duration, 2) + " s"
        ... + "  |  Out: " + fixed$(output_duration, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  Spec: " + specStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig
    if show_spectrograms
        removeObject: origSpec, resSpec
    endif
endif

# ============================================================
# FINAL REPORT  (single block — fixes v0.2's duplicate)
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Done ==="

if grainCount > 0
    selectObject: result
    appendInfoLine: "Created: ", selected$("Sound")
    appendInfoLine: "Grains: ", grainCount
    appendInfoLine: "Brightness range: ", fixed$(minBrightness, 0), "-", fixed$(maxBrightness, 0), " Hz"
    appendInfoLine: "Duration: ", fixed$(output_duration, 2), " s"
    
    if play_result
        Play
    endif
    
    selectObject: result
else
    appendInfoLine: "No grains could be created with current parameters"
endif
