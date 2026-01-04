# ============================================================
# Praat AudioTools - Brightness_Sorted_Grains.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Brightness Sorted Grains - extracts grains from audio and
#   sorts them by spectral centroid (brightness) before
#   concatenation. Creates spectral sweep effects from dark
#   to bright or bright to dark.
#
# Changelog v0.2:
#   - Fixed mono conversion bug
#   - Added presets
#   - Added visualization
#   - Improved sorting display
#   - Renamed for clarity
# ============================================================

form Brightness Sorted Grains
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Gentle Sweep (few grains)
        option Dense Cloud (many grains)
        option Micro Grains (short, fast)
        option Long Drones (slow evolution)
        option Extreme Sort (strong exaggeration)
    
    comment === Grain Size ===
    positive Grain_size_ms 150
    positive Grain_size_variation_ms 50
    optionmenu Grain_size_mode 1
        option Fixed
        option Random
    
    comment === Density ===
    positive Grain_overlap 0.3
    positive Density_factor 1.5
    
    comment === Processing ===
    positive Pitch_scatter 0.2
    boolean Reverse_grains 0
    optionmenu Window_type 2
        option Rectangular
        option Triangular
        option Parabolic
    
    comment === Sorting ===
    boolean Sort_grains 1
    optionmenu Sort_direction 1
        option Dark to bright
        option Bright to dark
    positive Gap_between_grains_ms 50
    
    comment === Spectral Exaggeration ===
    boolean Exaggerate_spectral 1
    optionmenu Exaggeration_intensity 2
        option Subtle
        option Moderate
        option Strong
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
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
elsif exaggeration_intensity = 2
    spectral_boost = 1.5
else
    spectral_boost = 2.0
endif

# === Info ===
writeInfoLine: "=== Brightness Sorted Grains ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Target grains: ", num_grains
appendInfoLine: "Grain size: ", grain_size_ms, " ms"
if grain_size_mode = 2
    appendInfoLine: "Size variation: ±", grain_size_variation_ms, " ms"
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
        
        # Pitch scatter
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
    
    if sort_direction = 1
        appendInfoLine: "Sorted: dark → bright"
    else
        appendInfoLine: "Sorted: bright → dark"
    endif
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
    Copy: sound_name$ + "_brightness_sorted"
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

# === Visualization ===
if draw_visualization and grainCount > 0
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    if sort_direction = 1
        sortLabel$ = "Dark → Bright"
    else
        sortLabel$ = "Bright → Dark"
    endif
    Text: 0.5, "centre", 0.5, "half", "Brightness Sorted: " + sound_name$ + " (" + sortLabel$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.8
    Select inner viewport: 0.6, 7.6, 0.7, 1.7
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.9, 3.1
    Select inner viewport: 0.6, 7.6, 2.0, 3.0
    selectObject: result
    Colour: "{0.4, 0.6, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Sorted"
    Text bottom: "yes", "Time (s)"
    
    # Brightness distribution (sorted order)
    Select outer viewport: 0, 8, 3.3, 4.8
    Select inner viewport: 0.6, 7.6, 3.5, 4.7
    
    # Find brightness range for scaling
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
    
    Axes: 0, grainCount, 0, maxB * 1.1
    
    # Draw brightness bars
    for i to grainCount
        brightness = grainBrightness#[i]
        
        # Color gradient: dark (blue) to bright (yellow)
        normalizedB = (brightness - minB) / (maxB - minB)
        r = normalizedB
        g = normalizedB * 0.8
        b = 1 - normalizedB
        barColor$ = "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        
        Paint rectangle: barColor$, i - 0.8, i - 0.2, 0, brightness
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Brightness (Hz)"
    Text bottom: "yes", "Grain # (sorted order)"
    
    # Draw trend line
    Colour: "{0.8, 0.2, 0.2}"
    Line width: 2
    for i from 2 to grainCount
        Draw line: i - 1 - 0.5, grainBrightness#[i - 1], i - 0.5, grainBrightness#[i]
    endfor
    Line width: 1
    
    # Spectrogram comparison
    Select outer viewport: 0, 4, 5.0, 6.3
    Select inner viewport: 0.6, 3.8, 5.2, 6.2
    selectObject: original
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"
    
    Select outer viewport: 4, 8, 5.0, 6.3
    Select inner viewport: 4.4, 7.6, 5.2, 6.2
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Sorted (note spectral sweep)"
    
    # Stats
    Select outer viewport: 0, 8, 6.4, 6.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Grains: " + string$(grainCount) + " | Brightness: " + fixed$(minB, 0) + "-" + fixed$(maxB, 0) + " Hz | Duration: " + fixed$(output_duration, 2) + "s | Gap: " + string$(gap_between_grains_ms) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
if grainCount > 0
    selectObject: result
    
    appendInfoLine: ""
    appendInfoLine: "=== Done ==="
    appendInfoLine: "Created: ", sound_name$ + "_brightness_sorted"
    appendInfoLine: "Grains: ", grainCount
    appendInfoLine: "Brightness range: ", fixed$(minBrightness, 0), "-", fixed$(maxBrightness, 0), " Hz"
    appendInfoLine: "Duration: ", fixed$(output_duration, 2), " s"
    
    # === Play ===
    if play_result
        Play
    endif
    
    selectObject: result
else
    appendInfoLine: ""
    appendInfoLine: "No grains could be created with current parameters"
endif

# === Final Info ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Grains: ", grainCount
appendInfoLine: "Brightness range: ", fixed$(minBrightness, 0), "-", fixed$(maxBrightness, 0), " Hz"
appendInfoLine: "Duration: ", fixed$(output_duration, 2), " s"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result