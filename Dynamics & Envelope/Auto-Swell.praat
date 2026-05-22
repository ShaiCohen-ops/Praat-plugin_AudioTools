# ============================================================
# Praat AudioTools - Auto-Swell.praat  
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stereo Amplitude Modulator / Dynamic Tremolo
#   Applies periodic or envelope-shaped amplitude modulations
#   with flexible stereo modes for spatial movement.
#
# Changelog v1.1:
#   - Fixed Info window: was 13 consecutive writeInfoLine calls
#     (each clears the window), which wiped the header/parameters;
#     now one writeInfoLine + appendInfoLine
#   - Fixed preset reporting: shape/stereo strings are derived from
#     the numeric settings (form $-strings are not updated by
#     presets, so non-Custom presets printed the wrong labels)
#   - Fixed triangle phase_start: was inverted (start-at-minimum
#     began at maximum); all three starts now correct. phase_start
#     applies to the smooth oscillators (sine, triangle); the
#     asymmetric/gate shapes start at their natural phase
#   - Fixed visualization: set Axes before Text on the title and
#     parameters captions (placement inherited the prior panel's
#     axes); title centered on the full 0-8 canvas
#
# Changelog v1.0:
#   - Added presets for common use cases
#   - Added visualization of modulation envelopes
#   - Fixed cleanup issues (orphan objects)
#   - Modernized procedure calls (@ syntax)
#   - Added info output with statistics
#   - Added phase_start option (sine)
#   - Play is now optional
# ============================================================

form Stereo Amplitude Modulator v1.1
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Tremolo (slow sine)
        option Fast Tremolo (quick sine)
        option Rhythmic Chop (pulse gate)
        option Stereo Ping-Pong (opposite phases)
        option Polyrhythmic Drift (different rates)
        option Textural Contrast (different shapes)
        option Single Swell (rise-fall arc)
    
    comment === Swell Shape ===
    optionmenu Swell_shape 1
        option Sine wave (smooth)
        option Triangle wave (linear)
        option Sawtooth (rise, instant drop)
        option Reverse sawtooth (instant rise, fall)
        option Square wave (hard gate)
        option Exponential rise
        option Exponential fall
        option S-curve (ease in-out)
        option Double peak (two swells per cycle)
        option Random walk (organic)
        option Pulse gate (rhythmic)
        option Rise-fall envelope (single arc)
    
    comment === Timing ===
    positive Swell_rate_Hz 0.5
    positive Depth_percent 80
    
    comment === Stereo Mode ===
    optionmenu Stereo_mode 2
        option Mono (same both channels)
        option Phase offset (L/R out of phase)
        option Different rates (polyrhythmic)
        option Different shapes (contrasting)
    
    positive Phase_offset_degrees 90
    positive Right_rate_multiplier 1.5
    
    optionmenu Right_swell_shape 2
        option Sine wave
        option Triangle wave
        option Sawtooth
        option Reverse sawtooth
        option Square wave
        option Exponential rise
        option Exponential fall
        option S-curve
        option Double peak
        option Random walk
        option Pulse gate
        option Rise-fall envelope
    
    comment === Advanced ===
    optionmenu Phase_start 1
        option Start at minimum (fade in)
        option Start at maximum (fade out)
        option Start at middle (half amplitude)
    
    positive Pulse_width_percent 50
    positive Random_smoothness 10
    
    comment === Output ===
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalSound = selected("Sound")
soundName$ = selected$("Sound")

selectObject: originalSound
dur = Get total duration
sr = Get sampling frequency
nChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Gentle Tremolo
    swell_shape = 1
    swell_rate_Hz = 0.3
    depth_percent = 50
    stereo_mode = 1
    presetName$ = "GentleTremolo"
elsif preset = 3
    # Fast Tremolo
    swell_shape = 1
    swell_rate_Hz = 6
    depth_percent = 70
    stereo_mode = 1
    presetName$ = "FastTremolo"
elsif preset = 4
    # Rhythmic Chop
    swell_shape = 11
    swell_rate_Hz = 4
    depth_percent = 100
    pulse_width_percent = 50
    stereo_mode = 1
    presetName$ = "RhythmicChop"
elsif preset = 5
    # Stereo Ping-Pong
    swell_shape = 1
    swell_rate_Hz = 0.5
    depth_percent = 90
    stereo_mode = 2
    phase_offset_degrees = 180
    presetName$ = "PingPong"
elsif preset = 6
    # Polyrhythmic Drift
    swell_shape = 1
    swell_rate_Hz = 0.4
    depth_percent = 70
    stereo_mode = 3
    right_rate_multiplier = 1.618
    presetName$ = "Polyrhythmic"
elsif preset = 7
    # Textural Contrast
    swell_shape = 2
    swell_rate_Hz = 0.5
    depth_percent = 80
    stereo_mode = 4
    right_swell_shape = 6
    presetName$ = "TexturalContrast"
elsif preset = 8
    # Single Swell
    swell_shape = 12
    depth_percent = 95
    stereo_mode = 1
    presetName$ = "SingleSwell"
else
    presetName$ = "Custom"
endif

# === Convert Parameters ===
depth = depth_percent / 100
swellPeriod = 1 / swell_rate_Hz
pulseWidth = pulse_width_percent / 100
phaseOffsetRad = phase_offset_degrees * pi / 180

# === Get Shape & Stereo Names (derived from numeric settings) ===
if swell_shape = 1
    shapeName$ = "Sine"
elsif swell_shape = 2
    shapeName$ = "Triangle"
elsif swell_shape = 3
    shapeName$ = "Sawtooth"
elsif swell_shape = 4
    shapeName$ = "RevSawtooth"
elsif swell_shape = 5
    shapeName$ = "Square"
elsif swell_shape = 6
    shapeName$ = "ExpRise"
elsif swell_shape = 7
    shapeName$ = "ExpFall"
elsif swell_shape = 8
    shapeName$ = "S-curve"
elsif swell_shape = 9
    shapeName$ = "DoublePeak"
elsif swell_shape = 10
    shapeName$ = "RandomWalk"
elsif swell_shape = 11
    shapeName$ = "PulseGate"
else
    shapeName$ = "RiseFall"
endif

if stereo_mode = 1
    stereoName$ = "Mono (identical L/R)"
elsif stereo_mode = 2
    stereoName$ = "Phase offset (" + fixed$(phase_offset_degrees, 0) + " deg)"
elsif stereo_mode = 3
    stereoName$ = "Different rates (R x" + fixed$(right_rate_multiplier, 2) + ")"
else
    stereoName$ = "Different shapes"
endif

# === Info Output (single writeInfoLine, then appendInfoLine) ===
writeInfoLine: "=============================================="
appendInfoLine: "  STEREO AMPLITUDE MODULATOR v1.1"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Input: ", soundName$, " (", fixed$(dur, 2), " s, ", nChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "=== Parameters ==="
appendInfoLine: "  Shape: ", swell_shape, " (", shapeName$, ")"
appendInfoLine: "  Rate: ", fixed$(swell_rate_Hz, 2), " Hz (period: ", fixed$(swellPeriod, 3), " s)"
appendInfoLine: "  Depth: ", fixed$(depth_percent, 0), "%"
appendInfoLine: "  Stereo mode: ", stereoName$
appendInfoLine: ""

# === Prepare Input ===
# Work with a copy to preserve original
selectObject: originalSound
workSound = Copy: "work"

# Convert to stereo if mono
selectObject: workSound
nCh = Get number of channels
if nCh = 1
    selectObject: workSound
    tmpStereo = Convert to stereo
    removeObject: workSound
    workSound = tmpStereo
endif

# Extract channels
selectObject: workSound
Extract one channel: 1
leftChannel = selected("Sound")
Rename: "left"

selectObject: workSound
Extract one channel: 2
rightChannel = selected("Sound")
Rename: "right"

# ============================================================
# PROCEDURE: Generate Modulation Envelope
# ============================================================

procedure generateModulation: .shape, .phaseStart, .rate, .pulseW, .smoothness, .phaseOffset, .duration, .sampleRate
    # Creates a modulation envelope sound [0, 1]
    
    # Calculate phase offset based on start position
    if .phaseStart = 1
        # Start at minimum
        .startOffset = -pi/2
    elsif .phaseStart = 2
        # Start at maximum  
        .startOffset = pi/2
    else
        # Start at middle
        .startOffset = 0
    endif
    
    Create Sound from formula: "mod", 1, 0, .duration, .sampleRate, "0"
    
    if .shape = 1
        # Sine wave
        Formula: ~ 0.5 + 0.5 * sin(2 * pi * .rate * x + .startOffset + .phaseOffset)
        
    elsif .shape = 2
        # Triangle wave  -  T(q) rises 0->1 over [0,.5], falls 1->0 over [.5,1]
        # phase_start picks the cycle start: min=q+0, max=q+0.5, middle=q+0.25
        if .phaseStart = 1
            .q = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        elsif .phaseStart = 2
            .q = "((x * .rate + .phaseOffset/(2*pi) + 0.5) mod 1)"
        else
            .q = "((x * .rate + .phaseOffset/(2*pi) + 0.25) mod 1)"
        endif
        Formula: ~ if '.q' < 0.5 then '.q' * 2 else 2 - '.q' * 2 fi
        
    elsif .shape = 3
        # Sawtooth (rise)
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ '.p'
        
    elsif .shape = 4
        # Reverse sawtooth (fall)
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ 1 - '.p'
        
    elsif .shape = 5
        # Square wave
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ if '.p' < 0.5 then 1 else 0 fi
        
    elsif .shape = 6
        # Exponential rise
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ 1 - exp(-5 * '.p')
        
    elsif .shape = 7
        # Exponential fall
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ exp(-5 * '.p')
        
    elsif .shape = 8
        # S-curve (ease in-out)
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ if '.p' < 0.5 then 2 * '.p' * '.p' else 1 - 2 * (1 - '.p') * (1 - '.p') fi
        
    elsif .shape = 9
        # Double peak
        Formula: ~ abs(sin(2 * pi * .rate * x + .phaseOffset))
        
    elsif .shape = 10
        # Random walk (smoothed noise)
        Formula: ~ randomGauss(0.5, 0.2)
        
        # Smooth with moving average
        .smoothSamples = round(.sampleRate / (.rate * .smoothness))
        if .smoothSamples < 2
            .smoothSamples = 2
        endif
        if .smoothSamples > 1000
            .smoothSamples = 1000
        endif
        
        # Multiple smoothing passes
        for .pass from 1 to 3
            Formula: ~ if col > .smoothSamples and col < ncol - .smoothSamples then (self[col - .smoothSamples] + self[col] + self[col + .smoothSamples]) / 3 else self fi
        endfor
        
        # Normalize to [0, 1]
        .minVal = Get minimum: 0, 0, "None"
        .maxVal = Get maximum: 0, 0, "None"
        .range = .maxVal - .minVal
        if .range < 0.001
            .range = 0.001
        endif
        Formula: ~ (self - .minVal) / .range
        
    elsif .shape = 11
        # Pulse gate
        .p = "((x * .rate + .phaseOffset/(2*pi)) mod 1)"
        Formula: ~ if '.p' < .pulseW then 1 else 0 fi
        
    elsif .shape = 12
        # Rise-fall envelope (single arc over duration)
        # Ignores rate - applies one swell over entire duration
        Formula: ~ if x < .duration/2 then (1 - exp(-5 * 2 * x / .duration)) else exp(-5 * 2 * (x - .duration/2) / .duration) fi
    endif
    
endproc

# ============================================================
# GENERATE MODULATION ENVELOPES
# ============================================================

appendInfoLine: "Generating modulation envelopes..."

# Left channel modulation
@generateModulation: swell_shape, phase_start, swell_rate_Hz, pulseWidth, random_smoothness, 0, dur, sr
leftMod = selected("Sound")
Rename: "mod_left"

# Right channel modulation (depends on stereo mode)
if stereo_mode = 1
    # Mono - same as left
    selectObject: leftMod
    rightMod = Copy: "mod_right"
    appendInfoLine: "  Stereo mode: Mono (identical L/R)"
    
elsif stereo_mode = 2
    # Phase offset
    @generateModulation: swell_shape, phase_start, swell_rate_Hz, pulseWidth, random_smoothness, phaseOffsetRad, dur, sr
    rightMod = selected("Sound")
    Rename: "mod_right"
    appendInfoLine: "  Stereo mode: Phase offset (", fixed$(phase_offset_degrees, 0), "°)"
    
elsif stereo_mode = 3
    # Different rates
    rightRate = swell_rate_Hz * right_rate_multiplier
    @generateModulation: swell_shape, phase_start, rightRate, pulseWidth, random_smoothness, 0, dur, sr
    rightMod = selected("Sound")
    Rename: "mod_right"
    appendInfoLine: "  Stereo mode: Different rates (L:", fixed$(swell_rate_Hz, 2), " R:", fixed$(rightRate, 2), " Hz)"
    
else
    # Different shapes
    @generateModulation: right_swell_shape, phase_start, swell_rate_Hz, pulseWidth, random_smoothness, 0, dur, sr
    rightMod = selected("Sound")
    Rename: "mod_right"
    appendInfoLine: "  Stereo mode: Different shapes"
endif

# Apply depth scaling: output = (1-depth) + depth * modulation
# This maps modulation [0,1] to amplitude [(1-depth), 1]
selectObject: leftMod
Formula: ~ (1 - depth) + depth * self

selectObject: rightMod
Formula: ~ (1 - depth) + depth * self

# ============================================================
# APPLY MODULATION TO AUDIO
# ============================================================

appendInfoLine: "Applying modulation..."

selectObject: leftChannel
Formula: ~ self * object[leftMod]

selectObject: rightChannel
Formula: ~ self * object[rightMod]

# ============================================================
# COMBINE TO STEREO OUTPUT
# ============================================================

selectObject: leftChannel, rightChannel
Combine to stereo
result = selected("Sound")
Rename: soundName$ + "_swell_" + shapeName$

if normalize_output
    selectObject: result
    Scale peak: 0.95
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Creating visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Stereo Amplitude Modulator## | " + soundName$ + " | " + presetName$
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.8, 7.6, 0.7, 1.4
    selectObject: originalSound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    
    # Left modulation envelope
    Select outer viewport: 0, 4, 1.6, 2.5
    Select inner viewport: 0.8, 3.8, 1.7, 2.4
    selectObject: leftMod
    Colour: "{0.3, 0.5, 0.8}"
    Draw: 0, 0, 0, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "L mod"
    
    # Right modulation envelope
    Select outer viewport: 4, 8, 1.6, 2.5
    Select inner viewport: 4.2, 7.6, 1.7, 2.4
    selectObject: rightMod
    Colour: "{0.8, 0.4, 0.3}"
    Draw: 0, 0, 0, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "R mod"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.6, 3.5
    Select inner viewport: 0.8, 7.6, 2.7, 3.4
    selectObject: result
    Colour: "{0.4, 0.6, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"
    
    # Parameters
    Select outer viewport: 0, 8, 3.6, 4.1
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.45}"
    Text: 0.5, "centre", 0.5, "half", "Shape: " + shapeName$ + " | Rate: " + fixed$(swell_rate_Hz, 2) + " Hz | Depth: " + fixed$(depth_percent, 0) + "% | Stereo: " + stereoName$
    
    Font size: 10
    Colour: "Black"
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: leftMod, rightMod, leftChannel, rightChannel, workSound

# ============================================================
# OUTPUT
# ============================================================

selectObject: result

appendInfoLine: ""
appendInfoLine: "=============================================="
appendInfoLine: "  COMPLETE"
appendInfoLine: "=============================================="
appendInfoLine: ""
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(dur, 2), " s"
appendInfoLine: ""

if play_result
    appendInfoLine: "Playing..."
    Play
endif

appendInfoLine: "Done!"

selectObject: result