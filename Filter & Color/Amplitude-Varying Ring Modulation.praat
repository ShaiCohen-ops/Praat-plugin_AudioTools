# ============================================================
# Praat AudioTools - Amplitude-Varying Ring Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ring modulation with frequency sweep and amplitude tremolo.
#   The carrier frequency accelerates over time (chirp), while
#   the modulation depth pulsates creating complex timbral motion.
#
# Technical approach:
#   - Ring modulation: signal × sin(carrier)
#   - Frequency chirp: carrier frequency accelerates via x^exponent
#   - Amplitude tremolo: modulation depth oscillates sinusoidally
#   - True stereo processing preserves spatial image
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit
#   for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Amplitude-Varying Ring Modulation
    comment Ring modulation with frequency chirp and amplitude tremolo.
    optionmenu Preset: 1
        option Default
        option Subtle Modulation
        option Extreme Sweep
        option Fast Pulsing
        option Metallic
        option Alien Voice
        option Underwater Transmission
    comment === Carrier parameters ===
    positive carrier_frequency 250
    comment (base carrier frequency in Hz)
    positive sweep_exponent 2
    comment (frequency acceleration: 1=linear, 2=quadratic, 3=cubic)
    comment === Amplitude modulation ===
    positive amplitude_rate 3
    comment (tremolo rate in Hz)
    real amplitude_center 0.5
    comment (center of amplitude oscillation, 0-1)
    real amplitude_depth 0.5
    comment (amplitude oscillates ± this amount around center)
    comment === Output options ===
    positive scale_peak 0.99
    boolean play_after_processing 1
    boolean draw_modulation 1
endform

# ============================================================
# Apply preset values
# ============================================================
if preset$ = "Subtle Modulation"
    carrier_frequency = 100
    sweep_exponent = 1.5
    amplitude_rate = 1
    amplitude_center = 0.7
    amplitude_depth = 0.3
elif preset$ = "Extreme Sweep"
    carrier_frequency = 500
    sweep_exponent = 3
    amplitude_rate = 5
    amplitude_center = 0.5
    amplitude_depth = 0.5
elif preset$ = "Fast Pulsing"
    carrier_frequency = 200
    sweep_exponent = 2
    amplitude_rate = 10
    amplitude_center = 0.6
    amplitude_depth = 0.4
elif preset$ = "Metallic"
    carrier_frequency = 440
    sweep_exponent = 1
    amplitude_rate = 7
    amplitude_center = 0.8
    amplitude_depth = 0.2
elif preset$ = "Alien Voice"
    carrier_frequency = 150
    sweep_exponent = 2.5
    amplitude_rate = 4
    amplitude_center = 0.5
    amplitude_depth = 0.5
elif preset$ = "Underwater Transmission"
    carrier_frequency = 80
    sweep_exponent = 1.2
    amplitude_rate = 0.5
    amplitude_center = 0.6
    amplitude_depth = 0.4
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Validate amplitude bounds
ampMin = amplitude_center - amplitude_depth
ampMax = amplitude_center + amplitude_depth

if ampMin < 0
    # Clamp to avoid phase inversion (optional - could allow it)
    amplitude_depth = amplitude_center
    ampMin = 0
    ampMax = amplitude_center + amplitude_depth
endif

if ampMax > 1
    # Normalize if exceeding 1
    ampMax = 1
endif

# Calculate frequency range (approximate - depends on duration)
# The instantaneous frequency at time t is: carrier * exponent * t^(exponent-1)
# At t=0: freq ≈ carrier (for exponent=1) or 0 (for exponent>1)
# At t=duration: freq = carrier * exponent * duration^(exponent-1)
if sweep_exponent = 1
    startFreq = carrier_frequency
    endFreq = carrier_frequency
else
    startFreq = 0
    endFreq = carrier_frequency * sweep_exponent * duration^(sweep_exponent - 1)
endif

# Warn if end frequency exceeds Nyquist
if endFreq > nyquist
    endFreq = nyquist
    # Could add warning here
endif

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
    
    # Determine frequency axis range
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
        
        # Avoid t=0 for exponent > 1
        if t1 < 0.001
            t1 = 0.001
        endif
        
        # Instantaneous frequency = d/dt [carrier * t^exponent / exponent]
        #                         = carrier * t^(exponent-1)
        # But for display, we show the "effective" frequency
        if sweep_exponent = 1
            freq1 = carrier_frequency
            freq2 = carrier_frequency
        else
            freq1 = carrier_frequency * sweep_exponent * t1^(sweep_exponent - 1)
            freq2 = carrier_frequency * sweep_exponent * t2^(sweep_exponent - 1)
        endif
        
        # Clamp to display range
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
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    Text top: "no", "##Carrier Frequency## - " + originalName$
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, freqTickInterval, "yes", "yes", "no"
    
    # ========================================================
    # PANEL 2: Amplitude envelope over time (bottom)
    # ========================================================
    Select outer viewport: 0, 6, 3, 6
    Select inner viewport: 0.8, 5.8, 3.5, 5.6
    
    Axes: 0, duration, 0, 1.1
    
    # Draw amplitude bounds
    Colour: "{0.9, 0.9, 0.9}"
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
        
        # Clamp
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
    Black
    
    Draw inner box
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"
    Text top: "no", "##Modulation Envelope## (rate: " + fixed$(amplitude_rate, 1) + " Hz)"
    
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 0.25, "yes", "yes", "no"
endproc

# ============================================================
# Procedure: Apply ring modulation to a sound
# ============================================================
procedure applyRingMod: .inputSound
    selectObject: .inputSound
    
    # Apply the ring modulation formula
    Formula: "self * sin(2 * pi * 'carrier_frequency' * x^'sweep_exponent' / 'sweep_exponent') * ('amplitude_center' + 'amplitude_depth' * sin(2 * pi * 'amplitude_rate' * x))"
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
if numChannels = 1
    # Mono processing
    selectObject: sound
    processed = Copy: originalName$ + "_ringmod"
    @applyRingMod: processed
    
    selectObject: processed
    Scale peak: scale_peak
    finalOutput = processed

else
    # True stereo processing
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
    
    # Combine back to stereo
    selectObject: left, right
    Combine to stereo
    finalOutput = selected("Sound")
    Rename: originalName$ + "_ringmod"
    
    Scale peak: scale_peak
    
    # Cleanup
    removeObject: left, right
endif

# ============================================================
# Select final output
# ============================================================
selectObject: finalOutput

# ============================================================
# Play if requested
# ============================================================
if play_after_processing
    Play
endif

# ============================================================
# Report completion
# ============================================================
writeInfoLine: "Amplitude-Varying Ring Modulation completed."
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Output: ", originalName$, "_ringmod"
appendInfoLine: "Channels: ", numChannels, if numChannels > 1 then " (true stereo)" else "" fi
appendInfoLine: "Duration: ", fixed$(duration, 3), " s"
appendInfoLine: ""
appendInfoLine: "Carrier: ", fixed$(carrier_frequency, 1), " Hz"
appendInfoLine: "Sweep exponent: ", fixed$(sweep_exponent, 2)
appendInfoLine: "Frequency range: ", fixed$(startFreq, 0), " -> ", fixed$(endFreq, 0), " Hz"
appendInfoLine: ""
appendInfoLine: "Amplitude rate: ", fixed$(amplitude_rate, 1), " Hz"
appendInfoLine: "Amplitude range: ", fixed$(ampMin, 2), " - ", fixed$(ampMax, 2)
if draw_modulation
    appendInfoLine: ""
    appendInfoLine: "Visualization in Picture window."
endif