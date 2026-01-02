# ============================================================
# Praat AudioTools - Subtractive Synthesis Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sound synthesis or generative algorithm script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Subtractive Synthesis Generator
    # --- New Option ---
    boolean Bass_line_demo 0
    comment (If checked, Frequency and Duration below are ignored)
    # ------------------
    optionmenu Waveform: 1
        option Sawtooth
        option Square
        option Pulse
        option Triangle
        option Dual Saw
        option Super Saw
    positive Duration_(s) 3.0
    positive Frequency_(Hz) 220
    real Pulse_width_(0.1-0.9) 0.3
    optionmenu Filter_type: 2
        option No Filter
        option Low Pass 12dB
        option Low Pass 24dB
        option High Pass
        option Band Pass
        option Notch
    positive Cutoff_freq_(Hz) 1000
    real Resonance_(0-1) 0.3
    optionmenu Filter_envelope: 2
        option No Envelope
        option Short Sweep
        option Long Sweep
        option Attack Emphasis
        option Decay Sweep
    real Envelope_amount_(0-1) 0.7
    optionmenu Amplitude_envelope: 2
        option Percussive
        option Sustained
        option Slow Attack
        option Pluck
        option Gate
    real Volume 0.8
endform

sampling_frequency = 44100

# MAIN LOGIC
if bass_line_demo
    # Generate 4 notes for a bass pattern (A2, A2, A3, G2)
    # We call the procedure '@makeSynth' for each note
    
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
    
    # Cleanup individual notes
    removeObject: id1, id2, id3, id4
    
    selectObject: final_id
else
    # Standard single note generation
    @makeSynth: frequency, duration
endif

Play

# ---------------------------------------------------------
# PROCEDURE: The Synthesizer Engine
# ---------------------------------------------------------
procedure makeSynth: .freq, .dur
    # 1. GENERATE OSCILLATOR
    if waveform = 1
        .id = Create Sound from formula: "Sawtooth", 1, 0, .dur, sampling_frequency,
        ... "0.9 * (2*(.freq*x - floor(.freq*x + 0.5)))"
    elsif waveform = 2
        .id = Create Sound from formula: "Square", 1, 0, .dur, sampling_frequency,
        ... "0.9 * if sin(2*pi*.freq*x) > 0 then 1 else -1 fi"
    elsif waveform = 3
        .id = Create Sound from formula: "Pulse", 1, 0, .dur, sampling_frequency,
        ... "0.9 * if (.freq*x - floor(.freq*x)) < pulse_width then 1 else -1 fi"
    elsif waveform = 4
        .id = Create Sound from formula: "Triangle", 1, 0, .dur, sampling_frequency,
        ... "0.9 * (2/pi) * arcsin(sin(2*pi*.freq*x))"
    elsif waveform = 5
        .detune = 7
        .id = Create Sound from formula: "DualSaw", 1, 0, .dur, sampling_frequency,
        ... "0.6 * (2*(.freq*x - floor(.freq*x + 0.5)) + 2*((.freq+.detune)*x - floor((.freq+.detune)*x + 0.5)))"
    elsif waveform = 6
        .id = Create Sound from formula: "SuperSaw", 1, 0, .dur, sampling_frequency,
        ... "0.4 * (2*(.freq*x - floor(.freq*x + 0.5)) + 2*((.freq*1.005)*x - floor((.freq*1.005)*x + 0.5)) + 2*((.freq*0.995)*x - floor((.freq*0.995)*x + 0.5)) + 2*((.freq*1.01)*x - floor((.freq*1.01)*x + 0.5)) + 2*((.freq*0.99)*x - floor((.freq*0.99)*x + 0.5)))"
    endif

    selectObject: .id

    # 2. CALCULATE FILTER CUTOFF
    .mod_cutoff = cutoff_freq

    if filter_envelope > 1
        if filter_envelope = 2
            .mod_cutoff = cutoff_freq * (1 + envelope_amount * 2)
        elsif filter_envelope = 3
            .mod_cutoff = cutoff_freq * (1 + envelope_amount * 1.5)
        elsif filter_envelope = 4
            .mod_cutoff = cutoff_freq * (1 + envelope_amount * 3)
        elsif filter_envelope = 5
            .mod_cutoff = cutoff_freq * (1 + envelope_amount * 2)
        endif
    endif

    # Nyquist safety
    if .mod_cutoff > sampling_frequency / 2
        .mod_cutoff = sampling_frequency / 2 - 100
    endif

    # 3. APPLY FILTER
    if filter_type > 1
        .source = .id
        selectObject: .source

        if filter_type = 2
            .bw = 100 + resonance * 200
            Filter (pass Hann band): 0, .mod_cutoff, .bw
        elsif filter_type = 3
            .bw = 50 + resonance * 100
            .pass1 = Filter (pass Hann band): 0, .mod_cutoff, .bw
            selectObject: .pass1
            Filter (pass Hann band): 0, .mod_cutoff, .bw * 1.2
            removeObject: .pass1
        elsif filter_type = 4
            .bw = 100 + resonance * 200
            Filter (stop Hann band): 0, .mod_cutoff, .bw
        elsif filter_type = 5
            .bw = 50 + (1 - resonance) * 150
            Filter (pass Hann band): .mod_cutoff - .bw/2, .mod_cutoff + .bw/2, .bw
        elsif filter_type = 6
            .bw = 30 + resonance * 70
            Filter (stop Hann band): .mod_cutoff - .bw/2, .mod_cutoff + .bw/2, .bw
        endif

        .filtered = selected("Sound")
        removeObject: .source
        .id = .filtered
    endif

    # 4. APPLY AMPLITUDE ENVELOPE
    selectObject: .id

    if amplitude_envelope = 1
        Formula: "self * exp(-x*8)"
    elsif amplitude_envelope = 2
        Formula: "self * exp(-x*1.5)"
    elsif amplitude_envelope = 3
        .atk = 0.5
        Formula: "self * if x < .atk then x/.atk else 1 fi"
    elsif amplitude_envelope = 4
        Formula: "self * exp(-x*20)"
    elsif amplitude_envelope = 5
        .rel = 0.1
        Formula: "self * if x < (.dur - .rel) then 1 else (.dur - x)/.rel fi"
    endif

    # 5. VOLUME
    Formula: "self * volume"
    Scale peak: 0.9
    
    # Leave the final sound selected for the main loop to pick up
endproc