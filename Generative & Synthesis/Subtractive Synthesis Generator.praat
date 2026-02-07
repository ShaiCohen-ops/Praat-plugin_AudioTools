# ============================================================
# Praat AudioTools - Subtractive_Synthesis_Generator.praat v2.0
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.0 (2025) - Added comprehensive visualizations
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Classic subtractive synthesis: harmonically rich waveforms
#   sculpted by resonant filters and amplitude envelopes.
#   Emulates the architecture of analog synthesizers (Moog, ARP, etc.).
#
# Features:
#   - 6 oscillator waveforms (Saw, Square, Pulse, Triangle, Dual Saw, Super Saw)
#   - 5 filter types (LP 12dB, LP 24dB, HP, BP, Notch)
#   - 4 filter envelope modes
#   - 5 amplitude envelope shapes
#   - Comprehensive visualization showing synthesis stages
#   - Bass line demo mode
#
# Categories: Synthesis, Sound Generation, Subtractive Synthesis
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis 
#   Toolkit for Experimental Composition.
# ============================================================

form Subtractive Synthesis Generator v2.0
    comment === Preset ===
    optionmenu Preset: 1
        option Custom
        option Moog Bass
        option ARP Lead
        option TB-303 Acid
        option String Pad
        option Plucked Bass
        option Synth Brass
    
    comment === Demo Mode ===
    boolean Bass_line_demo 0
    comment (If checked, generates 4-note bass pattern)
    
    comment === Oscillator ===
    optionmenu Waveform: 1
        option Sawtooth
        option Square
        option Pulse
        option Triangle
        option Dual Saw
        option Super Saw
    positive Frequency_Hz 220
    real Pulse_width_(0.1-0.9) 0.3
    
    comment === Filter ===
    optionmenu Filter_type: 2
        option No Filter
        option Low Pass 12dB
        option Low Pass 24dB
        option High Pass
        option Band Pass
        option Notch
    positive Cutoff_freq_Hz 1000
    real Resonance_(0-1) 0.3
    
    comment === Filter Envelope ===
    optionmenu Filter_envelope: 2
        option No Envelope
        option Short Sweep
        option Long Sweep
        option Attack Emphasis
        option Decay Sweep
    real Envelope_amount_(0-1) 0.7
    
    comment === Amplitude Envelope ===
    optionmenu Amplitude_envelope: 2
        option Percussive
        option Sustained
        option Slow Attack
        option Pluck
        option Gate
    
    comment === Output ===
    positive Duration_s 3.0
    real Volume 0.8
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Moog Bass
    waveform = 1
    frequency_Hz = 110
    filter_type = 3
    cutoff_freq_Hz = 600
    resonance = 0.6
    filter_envelope = 5
    envelope_amount = 0.8
    amplitude_envelope = 1
    presetName$ = "MoogBass"
elsif preset = 3
    # ARP Lead
    waveform = 1
    frequency_Hz = 440
    filter_type = 2
    cutoff_freq_Hz = 2000
    resonance = 0.4
    filter_envelope = 2
    envelope_amount = 0.9
    amplitude_envelope = 2
    presetName$ = "ARPLead"
elsif preset = 4
    # TB-303 Acid
    waveform = 1
    frequency_Hz = 220
    filter_type = 3
    cutoff_freq_Hz = 800
    resonance = 0.8
    filter_envelope = 4
    envelope_amount = 1.0
    amplitude_envelope = 4
    presetName$ = "TB303Acid"
elsif preset = 5
    # String Pad
    waveform = 6
    frequency_Hz = 220
    filter_type = 2
    cutoff_freq_Hz = 1500
    resonance = 0.2
    filter_envelope = 1
    envelope_amount = 0.5
    amplitude_envelope = 3
    presetName$ = "StringPad"
elsif preset = 6
    # Plucked Bass
    waveform = 1
    frequency_Hz = 110
    filter_type = 3
    cutoff_freq_Hz = 1200
    resonance = 0.5
    filter_envelope = 2
    envelope_amount = 0.7
    amplitude_envelope = 4
    presetName$ = "PluckedBass"
elsif preset = 7
    # Synth Brass
    waveform = 1
    frequency_Hz = 330
    filter_type = 2
    cutoff_freq_Hz = 2500
    resonance = 0.3
    filter_envelope = 3
    envelope_amount = 0.6
    amplitude_envelope = 3
    presetName$ = "SynthBrass"
else
    presetName$ = "Custom"
endif

sampling_frequency = 44100
needViz = draw_visualization

# Flag for visualization
makeVizObjects = 0
if needViz = 1
    if bass_line_demo = 0
        makeVizObjects = 1
    endif
endif

# === Info ===
clearinfo
writeInfoLine: "=== Subtractive Synthesis Generator v2.0 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Waveform: ", waveform$
appendInfoLine: "Filter: ", filter_type$
appendInfoLine: "Cutoff: ", cutoff_freq_Hz, " Hz"
appendInfoLine: "Amp Envelope: ", amplitude_envelope$
appendInfoLine: ""

# === Main Logic ===
if bass_line_demo
    appendInfoLine: "Generating bass line demo..."
    
    # Generate 4 notes for a bass pattern (A2, A2, A3, G2)
    @makeSynth: 110, 0.25
    id1 = selected("Sound")
    
    @makeSynth: 110, 0.25
    id2 = selected("Sound")
    
    @makeSynth: 220, 0.25
    id3 = selected("Sound")
    
    @makeSynth: 196, 0.25
    id4 = selected("Sound")

    # Combine them
    selectObject: id1, id2, id3, id4
    Concatenate
    final_id = selected("Sound")
    Rename: "subtractive_bassline_" + presetName$
    
    # Cleanup individual notes
    removeObject: id1, id2, id3, id4
    
    selectObject: final_id
    resultSound = final_id
    
    # For visualization, make a single note version
    if needViz
        makeVizObjects = 1
        @makeSynth: 110, 1.0
        vizSound = selected("Sound")
    endif
else
    appendInfoLine: "Generating single note..."
    @makeSynth: frequency_Hz, duration_s
    Rename: "subtractive_" + waveform$ + "_" + presetName$
    resultSound = selected("Sound")
    
    if needViz
        vizSound = resultSound
    endif
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Visualization ===
if needViz
    appendInfoLine: "Drawing visualization..."
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: resultSound
    Play
endif

# === Final Selection ===
selectObject: resultSound

# ==============================================================================
# Procedure: makeSynth - The Synthesizer Engine
# ==============================================================================
procedure makeSynth: .freq, .dur
    
    # === 1. Generate Oscillator ===
    if waveform = 1
        # Sawtooth
        .id = Create Sound from formula: "Sawtooth", 1, 0, .dur, sampling_frequency,
        ... "0.9 * (2*(.freq*x - floor(.freq*x + 0.5)))"
    elsif waveform = 2
        # Square
        .id = Create Sound from formula: "Square", 1, 0, .dur, sampling_frequency,
        ... "0.9 * if sin(2*pi*.freq*x) > 0 then 1 else -1 fi"
    elsif waveform = 3
        # Pulse
        .id = Create Sound from formula: "Pulse", 1, 0, .dur, sampling_frequency,
        ... "0.9 * if (.freq*x - floor(.freq*x)) < pulse_width then 1 else -1 fi"
    elsif waveform = 4
        # Triangle
        .id = Create Sound from formula: "Triangle", 1, 0, .dur, sampling_frequency,
        ... "0.9 * (2/pi) * arcsin(sin(2*pi*.freq*x))"
    elsif waveform = 5
        # Dual Saw
        .detune = 7
        .id = Create Sound from formula: "DualSaw", 1, 0, .dur, sampling_frequency,
        ... "0.6 * (2*(.freq*x - floor(.freq*x + 0.5)) + 2*((.freq+.detune)*x - floor((.freq+.detune)*x + 0.5)))"
    elsif waveform = 6
        # Super Saw
        .id = Create Sound from formula: "SuperSaw", 1, 0, .dur, sampling_frequency,
        ... "0.4 * (2*(.freq*x - floor(.freq*x + 0.5)) + 2*((.freq*1.005)*x - floor((.freq*1.005)*x + 0.5)) + 2*((.freq*0.995)*x - floor((.freq*0.995)*x + 0.5)) + 2*((.freq*1.01)*x - floor((.freq*1.01)*x + 0.5)) + 2*((.freq*0.99)*x - floor((.freq*0.99)*x + 0.5)))"
    endif

    selectObject: .id
    
    # Store raw oscillator for visualization
    if makeVizObjects
        Copy: "raw_osc_viz"
        rawOscID = selected("Sound")
        selectObject: .id
    endif

    # === 2. Calculate Filter Cutoff with Envelope ===
    .mod_cutoff = cutoff_freq_Hz

    if filter_envelope > 1
        if filter_envelope = 2
            # Short sweep
            .mod_cutoff = cutoff_freq_Hz * (1 + envelope_amount * 2)
        elsif filter_envelope = 3
            # Long sweep
            .mod_cutoff = cutoff_freq_Hz * (1 + envelope_amount * 1.5)
        elsif filter_envelope = 4
            # Attack emphasis
            .mod_cutoff = cutoff_freq_Hz * (1 + envelope_amount * 3)
        elsif filter_envelope = 5
            # Decay sweep
            .mod_cutoff = cutoff_freq_Hz * (1 + envelope_amount * 2)
        endif
    endif

    # Nyquist safety
    if .mod_cutoff > sampling_frequency / 2
        .mod_cutoff = sampling_frequency / 2 - 100
    endif

    # === 3. Apply Filter ===
    selectObject: .id
    
    if filter_type > 1
        .source = .id

        if filter_type = 2
            # Low Pass 12dB
            .bw = 100 + resonance * 200
            Filter (pass Hann band): 0, .mod_cutoff, .bw
        elsif filter_type = 3
            # Low Pass 24dB (two passes)
            .bw = 50 + resonance * 100
            .pass1 = Filter (pass Hann band): 0, .mod_cutoff, .bw
            selectObject: .pass1
            Filter (pass Hann band): 0, .mod_cutoff, .bw * 1.2
            removeObject: .pass1
        elsif filter_type = 4
            # High Pass
            .bw = 100 + resonance * 200
            Filter (stop Hann band): 0, .mod_cutoff, .bw
        elsif filter_type = 5
            # Band Pass
            .bw = 50 + (1 - resonance) * 150
            Filter (pass Hann band): .mod_cutoff - .bw/2, .mod_cutoff + .bw/2, .bw
        elsif filter_type = 6
            # Notch
            .bw = 30 + resonance * 70
            Filter (stop Hann band): .mod_cutoff - .bw/2, .mod_cutoff + .bw/2, .bw
        endif

        .filtered = selected("Sound")
        removeObject: .source
        .id = .filtered
        
        # Store filtered sound for visualization
        if makeVizObjects
            selectObject: .id
            Copy: "filtered_viz"
            filteredID = selected("Sound")
            selectObject: .id
        endif
    else
        if makeVizObjects
            filteredID = 0
        endif
    endif

    # === 4. Apply Amplitude Envelope ===
    selectObject: .id

    if amplitude_envelope = 1
        # Percussive (fast decay)
        Formula: "self * exp(-x*8)"
    elsif amplitude_envelope = 2
        # Sustained (slow decay)
        Formula: "self * exp(-x*1.5)"
    elsif amplitude_envelope = 3
        # Slow Attack
        .atk = 0.5
        Formula: "self * if x < .atk then x/.atk else 1 fi"
    elsif amplitude_envelope = 4
        # Pluck (very fast decay)
        Formula: "self * exp(-x*20)"
    elsif amplitude_envelope = 5
        # Gate (sustain then quick release)
        .rel = 0.1
        Formula: "self * if x < (.dur - .rel) then 1 else (.dur - x)/.rel fi"
    endif

    # === 5. Volume and Normalize ===
    Formula: "self * volume"
    Scale peak: 0.9
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 10, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Subtractive Synthesis: " + waveform$ + " [" + presetName$ + "]"
    
    # === Raw Oscillator Waveform ===
    Select outer viewport: 0, 5, 0.6, 1.8
    Select inner viewport: 0.5, 4.7, 0.7, 1.7
    
    selectObject: rawOscID
    .showDur = min(0.05, duration_s)
    Colour: "{0.7, 0.4, 0.2}"
    Draw: 0, .showDur, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "1. Oscillator (" + waveform$ + ")"
    Text left: "yes", "Amp"
    
    # === Filtered Waveform ===
    if filter_type > 1
        if filteredID > 0
            Select outer viewport: 5, 10, 0.6, 1.8
            Select inner viewport: 5.5, 9.7, 0.7, 1.7
            
            selectObject: filteredID
            Colour: "{0.3, 0.5, 0.7}"
            Draw: 0, .showDur, 0, 0, "no", "Curve"
            
            Colour: "Black"
            Draw inner box
            Font size: 8
            Text top: "no", "2. After Filter (" + filter_type$ + ")"
            Text left: "yes", "Amp"
        endif
    endif
    
    # === Final Output Waveform ===
    Select outer viewport: 0, 10, 2.0, 3.2
    Select inner viewport: 0.5, 9.7, 2.1, 3.1
    
    selectObject: vizSound
    Colour: "{0.2, 0.6, 0.3}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "3. Final Output (with " + amplitude_envelope$ + " envelope)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # === Spectrum Comparison ===
    Select outer viewport: 0, 5, 3.4, 5.2
    Select inner viewport: 0.5, 4.7, 3.5, 5.1
    
    # Raw spectrum
    selectObject: rawOscID
    To Ltas: 100
    rawLtasID = selected("Ltas")
    
    maxFreqDisplay = min(8000, sampling_frequency / 2)
    
    Colour: "{0.9, 0.7, 0.6}"
    Draw: 0, maxFreqDisplay, 20, 80, "no", "Curve"
    
    # Filtered spectrum
    if filter_type > 1
        if filteredID > 0
            selectObject: filteredID
            To Ltas: 100
            filtLtasID = selected("Ltas")
            
            Colour: "{0.5, 0.7, 0.9}"
            Line width: 2
            Draw: 0, maxFreqDisplay, 20, 80, "no", "Curve"
            Line width: 1
            
            removeObject: filtLtasID
        endif
    endif
    
    # Mark cutoff frequency
    if filter_type > 1
        Colour: "{0.9, 0.3, 0.3}"
        Dashed line
        Draw line: cutoff_freq_Hz, 20, cutoff_freq_Hz, 80
        Solid line
    endif
    
    removeObject: rawLtasID
    
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Spectrum Analysis"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Legend
    Font size: 6
    Colour: "{0.9, 0.7, 0.6}"
    Text: maxFreqDisplay * 0.6, "left", 75, "half", "Raw"
    if filter_type > 1
        Colour: "{0.5, 0.7, 0.9}"
        Text: maxFreqDisplay * 0.6, "left", 70, "half", "Filtered"
        Colour: "{0.9, 0.3, 0.3}"
        Text: maxFreqDisplay * 0.6, "left", 65, "half", "Cutoff: " + string$(cutoff_freq_Hz) + " Hz"
    endif
    
    # === Amplitude Envelope Shape ===
    Select outer viewport: 5, 10, 3.4, 5.2
    Select inner viewport: 5.5, 9.7, 3.5, 5.1
    
    envDur = min(2, duration_s)
    Axes: 0, envDur, 0, 1.1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, envDur, 0, 1.1
    
    # Draw envelope curve
    Colour: "{0.6, 0.3, 0.6}"
    Line width: 2
    
    numPoints = 200
    step = envDur / numPoints
    
    prevX = 0
    prevY = 0
    
    for pt to numPoints
        x = pt * step
        
        if amplitude_envelope = 1
            # Percussive
            y = exp(-x*8)
        elsif amplitude_envelope = 2
            # Sustained
            y = exp(-x*1.5)
        elsif amplitude_envelope = 3
            # Slow Attack
            atk = 0.5
            y = if x < atk then x/atk else 1 fi
        elsif amplitude_envelope = 4
            # Pluck
            y = exp(-x*20)
        elsif amplitude_envelope = 5
            # Gate
            rel = 0.1
            y = if x < (envDur - rel) then 1 else (envDur - x)/rel fi
        endif
        
        if pt > 1
            Draw line: prevX, prevY, x, y
        endif
        
        prevX = x
        prevY = y
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Amplitude Envelope (" + amplitude_envelope$ + ")"
    Text left: "yes", "Level"
    Text bottom: "yes", "Time (s)"
    
    # === Parameters Summary ===
    Select outer viewport: 0, 10, 5.4, 6.0
    Select inner viewport: 0.5, 9.7, 5.5, 5.9
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.3, 0.3, 0.3}"
    
    paramText$ = "Freq: " + string$(frequency_Hz) + " Hz | Filter: " + filter_type$ + " @ " + string$(cutoff_freq_Hz) + " Hz"
    if filter_type > 1
        paramText$ = paramText$ + " | Res: " + fixed$(resonance, 2)
    endif
    if filter_envelope > 1
        paramText$ = paramText$ + " | Env: " + filter_envelope$ + " (" + fixed$(envelope_amount, 1) + ")"
    endif
    
    Text: 0.5, "centre", 0.5, "half", paramText$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    
    # Cleanup visualization objects
    removeObject: rawOscID
    if filter_type > 1
        if filteredID > 0
            removeObject: filteredID
        endif
    endif
endproc