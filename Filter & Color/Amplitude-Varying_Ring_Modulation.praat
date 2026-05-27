# ============================================================
# Praat AudioTools - Amplitude-Varying_Ring_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2025) - Fixed frequency-curve/endFreq to match audio (removed spurious *exponent)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ring modulation with frequency sweep and amplitude tremolo.
#   The carrier frequency accelerates over time (chirp), while
#   the modulation depth pulsates creating complex timbral motion.
#
# Changelog v0.3:
#   - Fixed preset comparison (number not string)
#   - Fixed Formula variable interpolation
#   - Fixed inline if in appendInfoLine
#   - Added preset name to output
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Amplitude-Varying Ring Modulation v0.3
    comment Ring modulation with frequency chirp and amplitude tremolo.
    optionmenu Preset: 1
        option Manual
        option Subtle Modulation
        option Extreme Sweep
        option Fast Pulsing
        option Metallic
        option Alien Voice
        option Underwater Transmission
    comment === Carrier parameters ===
    positive Carrier_frequency 250
    positive Sweep_exponent 2
    comment === Amplitude modulation ===
    positive Amplitude_rate 3
    real Amplitude_center 0.5
    real Amplitude_depth 0.5
    comment === Output options ===
    positive Scale_peak 0.99
    boolean Play_after_processing 1
    boolean Draw_modulation 1
endform

# ============================================================
# Apply preset values (fixed: use number not string)
# ============================================================
if preset = 2
    # Subtle Modulation
    carrier_frequency = 100
    sweep_exponent = 1.5
    amplitude_rate = 1
    amplitude_center = 0.7
    amplitude_depth = 0.3
    presetName$ = "Subtle"
elsif preset = 3
    # Extreme Sweep
    carrier_frequency = 500
    sweep_exponent = 3
    amplitude_rate = 5
    amplitude_center = 0.5
    amplitude_depth = 0.5
    presetName$ = "ExtremeSweep"
elsif preset = 4
    # Fast Pulsing
    carrier_frequency = 200
    sweep_exponent = 2
    amplitude_rate = 10
    amplitude_center = 0.6
    amplitude_depth = 0.4
    presetName$ = "FastPulse"
elsif preset = 5
    # Metallic
    carrier_frequency = 440
    sweep_exponent = 1
    amplitude_rate = 7
    amplitude_center = 0.8
    amplitude_depth = 0.2
    presetName$ = "Metallic"
elsif preset = 6
    # Alien Voice
    carrier_frequency = 150
    sweep_exponent = 2.5
    amplitude_rate = 4
    amplitude_center = 0.5
    amplitude_depth = 0.5
    presetName$ = "AlienVoice"
elsif preset = 7
    # Underwater Transmission
    carrier_frequency = 80
    sweep_exponent = 1.2
    amplitude_rate = 0.5
    amplitude_center = 0.6
    amplitude_depth = 0.4
    presetName$ = "Underwater"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Amplitude-Varying Ring Modulation v0.3 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", originalName$
appendInfoLine: ""

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Validate amplitude bounds
ampMin = amplitude_center - amplitude_depth
ampMax = amplitude_center + amplitude_depth

if ampMin < 0
    amplitude_depth = amplitude_center
    ampMin = 0
    ampMax = amplitude_center + amplitude_depth
endif

if ampMax > 1
    ampMax = 1
endif

# Calculate frequency range
if sweep_exponent = 1
    startFreq = carrier_frequency
    endFreq = carrier_frequency
else
    startFreq = 0
    endFreq = carrier_frequency * duration^(sweep_exponent - 1)
endif

if endFreq > nyquist
    endFreq = nyquist
endif

appendInfoLine: "Carrier: ", carrier_frequency, " Hz"
appendInfoLine: "Sweep exponent: ", sweep_exponent
appendInfoLine: "Freq range: ", fixed$(startFreq, 0), " -> ", fixed$(endFreq, 0), " Hz"
appendInfoLine: "Amplitude rate: ", amplitude_rate, " Hz"
appendInfoLine: "Amplitude range: ", fixed$(ampMin, 2), " - ", fixed$(ampMax, 2)
appendInfoLine: ""

# ============================================================
# Procedure: Draw modulation visualization
# ============================================================
procedure drawModulation
    Erase all
    
    # Smart tick intervals
    if duration > 10
        timeTickInterval = 2
    elsif duration > 5
        timeTickInterval = 1
    elsif duration > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif
    
    # ========================================================
    # PANEL 1: Carrier frequency over time (top)
    # ========================================================
    Select outer viewport: 0, 6, 0, 3
    Select inner viewport: 0.8, 5.8, 0.5, 2.6
    
    maxFreqDisplay = endFreq * 1.1
    if maxFreqDisplay < carrier_frequency * 2
        maxFreqDisplay = carrier_frequency * 2
    endif
    if maxFreqDisplay > nyquist
        maxFreqDisplay = nyquist
    endif
    
    if maxFreqDisplay > 5000
        freqTickInterval = 1000
    elsif maxFreqDisplay > 2000
        freqTickInterval = 500
    elsif maxFreqDisplay > 500
        freqTickInterval = 100
    else
        freqTickInterval = 50
    endif
    
    Axes: 0, duration, 0, maxFreqDisplay
    
    # Draw instantaneous frequency curve
    Colour: "{0.2, 0.4, 0.8}"
    Line width: 2
    
    numDrawPoints = 200
    for iPoint from 1 to numDrawPoints - 1
        t1 = (iPoint - 1) * duration / numDrawPoints
        t2 = iPoint * duration / numDrawPoints
        
        if t1 < 0.001
            t1 = 0.001
        endif
        
        if sweep_exponent = 1
            freq1 = carrier_frequency
            freq2 = carrier_frequency
        else
            freq1 = carrier_frequency * t1^(sweep_exponent - 1)
            freq2 = carrier_frequency * t2^(sweep_exponent - 1)
        endif
        
        if freq1 > maxFreqDisplay
            freq1 = maxFreqDisplay
        endif
        if freq2 > maxFreqDisplay
            freq2 = maxFreqDisplay
        endif
        
        Draw line: t1, freq1, t2, freq2
    endfor
    
    # Draw Nyquist reference
    if nyquist < maxFreqDisplay * 1.2
        Colour: "{0.8, 0.2, 0.2}"
        Dotted line
        Draw line: 0, nyquist, duration, nyquist
        Text: duration * 0.02, "Left", nyquist * 0.95, "Half", "Nyquist"
        Solid line
    endif
    
    Line width: 1
    Colour: "Black"
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "Carrier Frequency - " + originalName$ + " [" + presetName$ + "]"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, freqTickInterval, "yes", "yes", "no"
    
    # ========================================================
    # PANEL 2: Amplitude envelope over time (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.8, 5.8, 3.5, 5.6
    
    Axes: 0, duration, 0, 1.1
    
    # Draw amplitude bounds
    Paint rectangle: "{0.92, 0.95, 1}", 0, duration, ampMin, ampMax
    
    # Draw center line
    Colour: "{0.6, 0.6, 0.6}"
    Dotted line
    Draw line: 0, amplitude_center, duration, amplitude_center
    Solid line
    
    # Draw amplitude envelope
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    
    for iPoint from 1 to numDrawPoints - 1
        t1 = (iPoint - 1) * duration / numDrawPoints
        t2 = iPoint * duration / numDrawPoints
        
        amp1 = amplitude_center + amplitude_depth * sin(2 * pi * amplitude_rate * t1)
        amp2 = amplitude_center + amplitude_depth * sin(2 * pi * amplitude_rate * t2)
        
        if amp1 < 0
            amp1 = 0
        endif
        if amp2 < 0
            amp2 = 0
        endif
        if amp1 > 1
            amp1 = 1
        endif
        if amp2 > 1
            amp2 = 1
        endif
        
        Draw line: t1, amp1, t2, amp2
    endfor
    
    Line width: 1
    Colour: "Black"
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    Text top: "no", "Modulation Envelope (rate: " + fixed$(amplitude_rate, 1) + " Hz)"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 0.25, "yes", "yes", "no"
endproc

# ============================================================
# Procedure: Apply ring modulation to a sound
# ============================================================
procedure applyRingMod: .inputSound
    selectObject: .inputSound
    
    # Build formula with modern syntax (no old-style interpolation)
    carrier$ = string$(carrier_frequency)
    exponent$ = string$(sweep_exponent)
    ampCenter$ = string$(amplitude_center)
    ampDepth$ = string$(amplitude_depth)
    ampRate$ = string$(amplitude_rate)
    
    Formula: "self * sin(2 * pi * " + carrier$ + " * x^" + exponent$ + " / " + exponent$ + ") * (" + ampCenter$ + " + " + ampDepth$ + " * sin(2 * pi * " + ampRate$ + " * x))"
endproc

# ============================================================
# Draw visualization (before processing)
# ============================================================
if draw_modulation
    @drawModulation
endif

# ============================================================
# Main processing: Handle mono or stereo
# ============================================================
appendInfoLine: "Processing..."

if numChannels = 1
    selectObject: sound
    processed = Copy: originalName$ + "_ringmod_" + presetName$
    @applyRingMod: processed
    
    selectObject: processed
    Scale peak: scale_peak
    finalOutput = processed

else
    selectObject: sound
    Extract one channel: 1
    left = selected("Sound")
    Rename: "left_temp"
    @applyRingMod: left
    
    selectObject: sound
    Extract one channel: 2
    right = selected("Sound")
    Rename: "right_temp"
    @applyRingMod: right
    
    selectObject: left
    plusObject: right
    Combine to stereo
    finalOutput = selected("Sound")
    Rename: originalName$ + "_ringmod_" + presetName$
    
    Scale peak: scale_peak
    
    removeObject: left, right
endif

# ============================================================
# Output
# ============================================================
selectObject: sound
plusObject: finalOutput

appendInfoLine: "Done!"
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")

# Stereo info (fixed: no inline if)
if numChannels > 1
    appendInfoLine: "Channels: ", numChannels, " (true stereo)"
else
    appendInfoLine: "Channels: ", numChannels
endif

if draw_modulation
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif

if play_after_processing
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput