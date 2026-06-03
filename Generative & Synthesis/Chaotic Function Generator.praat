# ============================================================
# Praat AudioTools - Chaotic Function Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Corrected
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic function generator with two categories:
#   1. Singular functions: Mathematical functions with singularities
#   2. Iterated maps: Properly iterated chaotic dynamical systems
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.2:
#   - Fixed iterated maps (now properly chaotic)
#   - Fixed x normalization (0→1)
#   - Fixed Praat syntax (fi not endif)
#   - Added output clamping
#   - Added presets
#   - Added spatial modes
#   - Added visualization
# ============================================================

form Chaotic Function Generator
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Singularity
        option Dense Oscillation
        option Logistic Chaos
        option Lorenz-like
        option Tent Map Texture
    
    comment === Basic Settings ===
    positive Duration_s 1.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 200
    
    comment === Function Type ===
    optionmenu Function_type 1
        option sin(1/x)
        option sin((1/x)*(1/(1-x)))
        option Multi-sine: 2sin(3/x)+3cos(5/x)+...
        option sin(3/x)*sin(5/(1-x))
        option sin(1/x) + 2*sin(1/(1-x))
        option tan(1/x)*cos(1/(1-x))
        option sin(1/x²)*cos(1/(1-x)²)
        option exp(-1/x²)*sin(50x)
        option sin(1/x)*cos(1/x²)
        option sin(1/(x(1-x)))
        option sin(ln(x))*cos(ln(1-x))
        option --- Iterated Maps ---
        option Logistic Map (r=3.9)
        option Logistic Map (r=3.7)
        option Tent Map
        option Henon Map
        option Custom Formula
    
    comment === Iterated Map Settings ===
    positive Control_rate_Hz 1000
    real Chaos_parameter 3.9
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Wide
        option Rotating
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
    
    comment === Custom ===
    text Custom_formula sin(1/x)
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Gentle Singularity
    duration_s = 2.0
    base_frequency_Hz = 150
    function_type = 1
    spatial_mode = 1
    preset_name$ = "GentleSingularity"
elsif preset = 3
    # Dense Oscillation
    duration_s = 1.5
    base_frequency_Hz = 100
    function_type = 3
    spatial_mode = 2
    preset_name$ = "DenseOscillation"
elsif preset = 4
    # Logistic Chaos
    duration_s = 3.0
    base_frequency_Hz = 200
    function_type = 13
    control_rate_Hz = 500
    chaos_parameter = 3.95
    spatial_mode = 3
    preset_name$ = "LogisticChaos"
elsif preset = 5
    # Lorenz-like
    duration_s = 4.0
    base_frequency_Hz = 150
    function_type = 16
    control_rate_Hz = 800
    spatial_mode = 3
    preset_name$ = "Lorenzlike"
elsif preset = 6
    # Tent Map Texture
    duration_s = 2.0
    base_frequency_Hz = 300
    function_type = 15
    control_rate_Hz = 600
    spatial_mode = 2
    preset_name$ = "TentMapTexture"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi
eps = 1e-4

# === Info ===
writeInfoLine: "=== Chaotic Function Generator ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Function: ", function_type$
appendInfoLine: ""

# === Check if iterated map ===
isIteratedMap = 0
if function_type >= 13 and function_type <= 16
    isIteratedMap = 1
endif

# === Generate sound ===
if isIteratedMap = 0
    # === Singular Functions ===
    appendInfoLine: "Generating singular function..."
    
    # Build formula with normalized x (0→1)
    # Praat's x goes 0→duration, so normalize: xn = x/duration
    
    if function_type = 1
        # sin(1/x)
        formula$ = "sin(1/((x/duration_s)+eps))"
    elsif function_type = 2
        # sin((1/x)*(1/(1-x)))
        formula$ = "sin((1/((x/duration_s)+eps))*(1/((1-(x/duration_s))+eps)))"
    elsif function_type = 3
        # Multi-sine
        formula$ = "(2*sin(3/((x/duration_s)+eps)))+(3*cos(5/((x/duration_s)+eps)))+(4*sin(6/((x/duration_s)+eps)))+(cos(3/((x/duration_s)+eps)))"
    elsif function_type = 4
        # sin(3/x)*sin(5/(1-x))
        formula$ = "sin(3/((x/duration_s)+eps))*sin(5/((1-(x/duration_s))+eps))"
    elsif function_type = 5
        # sin(1/x) + 2*sin(1/(1-x))
        formula$ = "sin(1/((x/duration_s)+eps))+(2*sin(1/((1-(x/duration_s))+eps)))"
    elsif function_type = 6
        # tan(1/x)*cos(1/(1-x)) - clamp tan to avoid huge values
        formula$ = "max(-1, min(1, tan(1/((x/duration_s)+eps))))*cos(1/((1-(x/duration_s))+eps))"
    elsif function_type = 7
        # sin(1/x²)*cos(1/(1-x)²)
        formula$ = "sin(1/(((x/duration_s)+eps)^2))*cos(1/(((1-(x/duration_s))+eps)^2))"
    elsif function_type = 8
        # exp(-1/x²)*sin(50x)
        formula$ = "exp(-1/(((x/duration_s)+eps)^2))*sin(50*twoPi*x/duration_s)"
    elsif function_type = 9
        # sin(1/x)*cos(1/x²)
        formula$ = "sin(1/((x/duration_s)+eps))*cos(1/(((x/duration_s)+eps)^2))"
    elsif function_type = 10
        # sin(1/(x(1-x)))
        formula$ = "sin(1/(((x/duration_s)+eps)*((1-(x/duration_s))+eps)))"
    elsif function_type = 11
        # sin(ln(x))*cos(ln(1-x))
        formula$ = "sin(ln((x/duration_s)+0.01))*cos(ln((1-(x/duration_s))+0.01))"
    elsif function_type = 12
        # Separator - use sin(1/x)
        formula$ = "sin(1/((x/duration_s)+eps))"
    elsif function_type = 17
        # Custom
        formula$ = custom_formula$
    else
        formula$ = "sin(1/((x/duration_s)+eps))"
    endif
    
    outputSound = Create Sound from formula: "chaos_" + uid$, 1, 0, duration_s, sample_rate_Hz, formula$

else
    # === Iterated Chaotic Maps ===
    appendInfoLine: "Computing iterated map at control rate..."
    
    # Create control-rate modulation signal
    modSound = Create Sound from formula: "mod_" + uid$, 1, 0, duration_s, control_rate_Hz, "0"
    
    selectObject: modSound
    nControlPoints = Get number of samples
    timeStep = 1 / control_rate_Hz
    
    # Initialize map state
    if function_type = 13 or function_type = 14
        # Logistic map
        mapX = 0.1 + randomUniform(0, 0.1)
        if function_type = 13
            r = 3.9
        else
            r = 3.7
        endif
    elsif function_type = 15
        # Tent map
        mapX = randomUniform(0.1, 0.9)
    elsif function_type = 16
        # Henon map (simplified 1D projection)
        mapX = 0.1
        mapY = 0.1
        henonA = 1.4
        henonB = 0.3
    endif
    
    # Iterate and store
    for cp to nControlPoints
        # Iterate the map
        if function_type = 13 or function_type = 14
            # Logistic: x[n+1] = r * x[n] * (1 - x[n])
            mapX = r * mapX * (1 - mapX)
            modValue = mapX * 2 - 1
        elsif function_type = 15
            # Tent: x[n+1] = min(2x, 2(1-x))
            if mapX < 0.5
                mapX = 2 * mapX
            else
                mapX = 2 * (1 - mapX)
            endif
            modValue = mapX * 2 - 1
        elsif function_type = 16
            # Henon: x[n+1] = 1 - a*x² + y, y[n+1] = b*x
            newX = 1 - henonA * mapX * mapX + mapY
            newY = henonB * mapX
            mapX = newX
            mapY = newY
            # Bound check (Henon can escape)
            if abs(mapX) > 2
                mapX = randomUniform(-0.5, 0.5)
                mapY = randomUniform(-0.5, 0.5)
            endif
            modValue = mapX / 1.5
            if modValue > 1
                modValue = 1
            elsif modValue < -1
                modValue = -1
            endif
        endif
        
        selectObject: modSound
        Set value at sample number: 1, cp, modValue
    endfor
    
    # Resample to audio rate
    selectObject: modSound
    modAudio = Resample: sample_rate_Hz, 50
    modAudioName$ = selected$("Sound")
    
    # Use modulation for FM synthesis
    appendInfoLine: "Synthesizing audio..."
    outputSound = Create Sound from formula: "chaos_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "sin(twoPi * base_frequency_Hz * x * (1 + 0.5 * Sound_'modAudioName$'[]))"
    
    # Cleanup
    removeObject: modSound, modAudio
endif

# === Apply fade ===
selectObject: outputSound
Formula: "if x < 0.01 then self * (x / 0.01) else self fi"
Formula: "if x > duration_s - 0.01 then self * ((duration_s - x) / 0.01) else self fi"

# === Clamp to prevent clipping ===
selectObject: outputSound
Formula: "max(-1, min(1, self))"

# === Spatial Processing ===
if spatial_mode = 2
    appendInfoLine: "Creating stereo width..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "chaos_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
    
elsif spatial_mode = 3
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * cos(twoPi * 0.2 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.6 + 0.4 * sin(twoPi * 0.2 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "chaos_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "chaos_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
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
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 0.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Chaotic Function: " + preset_name$ + " (" + function_type$ + ")"
    
    # === Waveform ===
    Select outer viewport: 0, 7, 0.6, 2.5
    Colour: "{0.9, 0.9, 0.9}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.4
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoWave = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_wave"
        .monoWave = selected("Sound")
    endif
    
    selectObject: .monoWave
    Colour: "{0.2, 0.4, 0.8}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    
    removeObject: .monoWave
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 2.4
    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Amplitude"
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 2.6, 4.8
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 2.7, 4.7
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_spec"
        .monoSpec = selected("Sound")
    endif
    
    selectObject: .monoSpec
    .maxFreq = min(5000, base_frequency_Hz * 4)
    
    To Spectrogram: 0.02, .maxFreq, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoSpec, .spec
    
    Select inner viewport: .leftMargin, .rightMargin, 2.7, 4.7
    Axes: 0, duration_s, 0, .maxFreq
    Colour: "White"
    Marks left: 4, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 6.4, 7
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    if isIteratedMap
        .paramText$ = "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Control rate: " + string$(control_rate_Hz) + " Hz | Iterated map"
    else
        .paramText$ = "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Singular function"
    endif
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc