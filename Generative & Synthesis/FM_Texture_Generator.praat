# ============================================================
# Praat AudioTools -  DX7 FM Synthesis Generator
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   FM (Frequency Modulation) Synthesis texture generator.
#   Classic Chowning/DX7-style FM sounds with various timbres.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis Toolkit
#   for Experimental Composition.
#
# Changelog v0.3:
#   - Visualization aligned to AudioTools house style: title in its own band,
#     grey summary panel, larger fonts, full-precision RGB, black spectrogram
#     marks (were white -> invisible on the margin).
#   - Replaced the non-ASCII en-dash.
# ============================================================


form DX7 FM Synthesis Generator (v6.0)
    comment === Demo Mode ===
    boolean Melody_demo 0
    comment (If checked, plays a test melody with selected preset)
    
    comment === Preset ===
    optionmenu Preset 1
        option Electric Piano (DX7 Epiano 1)
        option Slap Bass (Solid/Lately)
        option Tubular Bells
        option Hammond Organ
        option Warm Pad
        option Custom (Test Tone)

    comment === Timbre Controls ===
    positive Base_Frequency 110.0
    comment (Scales Modulation Index - Turn up for "Bite")
    positive Brightness 1.0
    comment (Scales Decay Times - Lower = tighter, Higher = lush)
    positive Decay_Scale 1.0

    comment === Amplitude Envelope ===
    optionmenu Envelope 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Gate
        option Reverse
        option Tremolo
        option Swell
        option ADSR
        option Stutter
        option Random Bursts

    comment === Output ===
    positive Duration 2.0
    positive Master_Volume 0.8
    boolean Show_Visualization 1
    boolean Play_Result 1
    
    comment === Advanced ===
    boolean Show_Advanced_Settings 0
endform

sampling_frequency = 44100

# === DEFAULT ADVANCED PARAMETERS ===
# Operator 1
op1_freq = 1.0
op1_level = 1.0
op1_envelope$ = "sus"

# Operator 2
op2_freq = 1.0
op2_level = 1.0
op2_envelope$ = "decay"

# Operator 3
op3_freq = 1.0
op3_level = 0.0
op3_envelope$ = "snap"

# Operator 4
op4_freq = 1.0
op4_level = 0.0
op4_envelope$ = "decay"

# Operator 5
op5_freq = 1.0
op5_level = 0.0
op5_envelope$ = "snap"

# Operator 6
op6_freq = 1.0
op6_level = 0.0
op6_envelope$ = "sus"
op6_feedback = 0.0

# Algorithm (1=Parallel, 2=Series, 3=Dual)
algorithm = 1

# Envelope times
snap_decay_time = 0.1
tone_decay_time = 0.8

# === SHOW ADVANCED SETTINGS (If Checked) ===
if show_Advanced_Settings
    beginPause: "Advanced DX7 Parameters"
        comment: "Algorithm:"
        optionmenu: "Algorithm", algorithm
            option: "Parallel (All ops to output)"
            option: "Series (6->5->4->3->2->1)"
            option: "Dual Stack (5->4 + 2->1)"
        
        comment: "Operator 1 (Carrier):"
        positive: "Op1 freq", op1_freq
        real: "Op1 level", op1_level
        optionmenu: "Op1 envelope", 1
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Operator 2:"
        positive: "Op2 freq", op2_freq
        real: "Op2 level", op2_level
        optionmenu: "Op2 envelope", 2
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Operator 3:"
        positive: "Op3 freq", op3_freq
        real: "Op3 level", op3_level
        optionmenu: "Op3 envelope", 1
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Operator 4:"
        positive: "Op4 freq", op4_freq
        real: "Op4 level", op4_level
        optionmenu: "Op4 envelope", 2
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Operator 5:"
        positive: "Op5 freq", op5_freq
        real: "Op5 level", op5_level
        optionmenu: "Op5 envelope", 1
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Operator 6 (Feedback):"
        positive: "Op6 freq", op6_freq
        real: "Op6 level", op6_level
        real: "Op6 feedback", op6_feedback
        optionmenu: "Op6 envelope", 3
            option: "snap"
            option: "decay"
            option: "sus"
            option: "slow"
        
        comment: "Envelope Timing:"
        positive: "Snap decay time", snap_decay_time
        positive: "Tone decay time", tone_decay_time
    clicked = endPause: "Cancel", "OK", 2, 1
    if clicked = 1
        exitScript: "Cancelled."
    endif
    
    # Map envelope selections to strings
    if op1_envelope = 1
        op1_envelope$ = "snap"
    elsif op1_envelope = 2
        op1_envelope$ = "decay"
    elsif op1_envelope = 3
        op1_envelope$ = "sus"
    elsif op1_envelope = 4
        op1_envelope$ = "slow"
    endif
    
    if op2_envelope = 1
        op2_envelope$ = "snap"
    elsif op2_envelope = 2
        op2_envelope$ = "decay"
    elsif op2_envelope = 3
        op2_envelope$ = "sus"
    elsif op2_envelope = 4
        op2_envelope$ = "slow"
    endif
    
    if op3_envelope = 1
        op3_envelope$ = "snap"
    elsif op3_envelope = 2
        op3_envelope$ = "decay"
    elsif op3_envelope = 3
        op3_envelope$ = "sus"
    elsif op3_envelope = 4
        op3_envelope$ = "slow"
    endif
    
    if op4_envelope = 1
        op4_envelope$ = "snap"
    elsif op4_envelope = 2
        op4_envelope$ = "decay"
    elsif op4_envelope = 3
        op4_envelope$ = "sus"
    elsif op4_envelope = 4
        op4_envelope$ = "slow"
    endif
    
    if op5_envelope = 1
        op5_envelope$ = "snap"
    elsif op5_envelope = 2
        op5_envelope$ = "decay"
    elsif op5_envelope = 3
        op5_envelope$ = "sus"
    elsif op5_envelope = 4
        op5_envelope$ = "slow"
    endif
    
    if op6_envelope = 1
        op6_envelope$ = "snap"
    elsif op6_envelope = 2
        op6_envelope$ = "decay"
    elsif op6_envelope = 3
        op6_envelope$ = "sus"
    elsif op6_envelope = 4
        op6_envelope$ = "slow"
    endif
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== DX7 FM Synthesis Generator ==="
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Base Frequency: ", base_Frequency, " Hz"
appendInfoLine: "Brightness: ", brightness
appendInfoLine: "Decay Scale: ", decay_Scale
if melody_demo
    appendInfoLine: "Mode: MELODY DEMO"
else
    appendInfoLine: "Mode: Single Note"
endif
appendInfoLine: ""

# ============================================================
# MAIN LOGIC
# ============================================================

if melody_demo
    appendInfoLine: "Generating melody demo (C-E-G-C-G-E-C-G arpeggio)..."
    
    # Test melody: C4, E4, G4, C5, G4, E4, C4, G3
    @makeFMNote: 261.63, 0.4
    id1 = selected("Sound")
    
    @makeFMNote: 329.63, 0.4
    id2 = selected("Sound")
    
    @makeFMNote: 392.00, 0.4
    id3 = selected("Sound")
    
    @makeFMNote: 523.25, 0.6
    id4 = selected("Sound")
    
    @makeFMNote: 392.00, 0.4
    id5 = selected("Sound")
    
    @makeFMNote: 329.63, 0.4
    id6 = selected("Sound")
    
    @makeFMNote: 261.63, 0.4
    id7 = selected("Sound")
    
    @makeFMNote: 196.00, 0.8
    id8 = selected("Sound")
    
    # Combine
    selectObject: id1, id2, id3, id4, id5, id6, id7, id8
    Concatenate
    sound = selected("Sound")
    Rename: "DX7_" + preset$ + "_melody"
    
    removeObject: id1, id2, id3, id4, id5, id6, id7, id8
    
    selectObject: sound
else
    # Single note
    @makeFMNote: base_Frequency, duration
    sound = selected("Sound")
    Rename: "DX7_" + preset$
endif

# ============================================================
# APPLY AMPLITUDE ENVELOPE
# ============================================================
selectObject: sound
totalDur = Get total duration

if envelope = 2
    # Percussive
    Formula: "self * exp(-x*5)"
elsif envelope = 3
    # Slow Fade
    Formula: "self * exp(-x*0.3)"
elsif envelope = 4
    # Gate
    gate_period = 0.1 + (brightness - 1) * 0.1
    if gate_period < 0.05
        gate_period = 0.1
    endif
    Formula: "self * if sin(2*pi*x/" + string$(gate_period) + ") > 0 then 1 else 0 fi"
elsif envelope = 5
    # Reverse
    Formula: "self * (x/" + string$(totalDur) + ")"
elsif envelope = 6
    # Tremolo
    trem_rate = 5 + brightness * 5
    trem_depth = 0.3 + (brightness - 1) * 0.2
    if trem_depth < 0.1
        trem_depth = 0.3
    endif
    Formula: "self * (1 - " + string$(trem_depth) + " + " + string$(trem_depth) + "*sin(2*pi*" + string$(trem_rate) + "*x))"
elsif envelope = 7
    # Swell
    attack_time = 0.3 + (decay_Scale - 1) * 0.2
    if attack_time < 0.1
        attack_time = 0.3
    endif
    Formula: "self * if x < " + string$(attack_time) + " then x/" + string$(attack_time) + " else 1 fi"
elsif envelope = 8
    # ADSR
    attack = 0.01
    decay = 0.1 + (decay_Scale - 1) * 0.1
    if decay < 0.05
        decay = 0.1
    endif
    sustain = 0.5 + brightness * 0.2
    if sustain < 0.3
        sustain = 0.5
    endif
    if sustain > 1.0
        sustain = 1.0
    endif
    release = 0.3
    decay_end = attack + decay
    release_start = totalDur - release
    if release_start < decay_end
        release_start = decay_end
    endif
    Formula: "self * if x < " + string$(attack) + " then x/" + string$(attack) + 
    ... " else if x < " + string$(decay_end) + " then 1-(1-" + string$(sustain) + ")*((x-" + string$(attack) + ")/" + string$(decay) + 
    ... ") else if x < " + string$(release_start) + " then " + string$(sustain) + 
    ... " else " + string$(sustain) + "*(1-(x-" + string$(release_start) + ")/" + string$(release) + ") fi fi fi"
elsif envelope = 9
    # Stutter
    stutter_rate = 10 + brightness * 10
    Formula: "self * if floor(x*" + string$(stutter_rate) + ") mod 2 = 0 then 1 else 0 fi"
elsif envelope = 10
    # Random Bursts
    burst_density = 5 + brightness * 10
    Formula: "self * if randomUniform(0,1) < " + string$(burst_density) + "*0.05 then exp(-(x-floor(x*" + string$(burst_density) + ")/" + string$(burst_density) + ")*50) else 0 fi"
endif

selectObject: sound
Scale peak: 0.95

# ============================================================
# VISUALIZATION
# ============================================================
if show_Visualization
    @drawVisualization
endif

# ============================================================
# PLAY
# ============================================================
if play_Result
    selectObject: sound
    Play
endif

# ============================================================
# FINAL
# ============================================================
selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: makeFMNote - Generate one FM note
# ==============================================================================
procedure makeFMNote: .freq, .dur
    
    # Default values
    .algo = 1
    
    # Initialize Frequencies
    .f1 = 1.0
    .f2 = 1.0
    .f3 = 1.0
    .f4 = 1.0
    .f5 = 1.0
    .f6 = 1.0
    
    # Initialize Levels
    .l1 = 0.0
    .l2 = 0.0
    .l3 = 0.0
    .l4 = 0.0
    .l5 = 0.0
    .l6 = 0.0
    .fb = 0.0
    
    # Initialize Envelopes
    .e1$ = ""
    .e2$ = ""
    .e3$ = ""
    .e4$ = ""
    .e5$ = ""
    .e6$ = ""
    
    # Macros
    .b_fac = brightness
    .d_fac = decay_Scale
    
    # Safety clamp
    if .d_fac < 0.001
        .d_fac = 0.001
    endif
    if .b_fac < 0
        .b_fac = 0
    endif
    
    # === ENVELOPE GENERATION ===
    .raw_snap = snap_decay_time * .d_fac
    .snap_Decay = max(0.001, .raw_snap)
    .env_snap$ = "(if x < 0.002 then x/0.002 else exp(-(x-0.002)/" + string$(.snap_Decay) + ") fi)"
    
    .raw_decay = tone_decay_time * .d_fac
    .tone_Decay = max(0.001, .raw_decay)
    .env_decay$ = "(if x < 0.01 then x/0.01 else exp(-(x-0.01)/" + string$(.tone_Decay) + ") fi)"
    
    .env_sus$ = "(if x < 0.01 then x/0.01 else 0.1*exp(-(x-0.01)/0.5) + 0.9 fi)"
    .env_slow$ = "(if x < 0.5 then x/0.5 else 1 fi)"
    
    # === APPLY ADVANCED SETTINGS OR PRESET ===
    if show_Advanced_Settings
        # Use manual operator settings
        .algo = algorithm
        
        .f1 = op1_freq
        .l1 = op1_level
        if op1_envelope$ = "snap"
            .e1$ = .env_snap$
        elsif op1_envelope$ = "decay"
            .e1$ = .env_decay$
        elsif op1_envelope$ = "sus"
            .e1$ = .env_sus$
        elsif op1_envelope$ = "slow"
            .e1$ = .env_slow$
        endif
        
        .f2 = op2_freq
        .l2 = op2_level
        if op2_envelope$ = "snap"
            .e2$ = .env_snap$
        elsif op2_envelope$ = "decay"
            .e2$ = .env_decay$
        elsif op2_envelope$ = "sus"
            .e2$ = .env_sus$
        elsif op2_envelope$ = "slow"
            .e2$ = .env_slow$
        endif
        
        .f3 = op3_freq
        .l3 = op3_level
        if op3_envelope$ = "snap"
            .e3$ = .env_snap$
        elsif op3_envelope$ = "decay"
            .e3$ = .env_decay$
        elsif op3_envelope$ = "sus"
            .e3$ = .env_sus$
        elsif op3_envelope$ = "slow"
            .e3$ = .env_slow$
        endif
        
        .f4 = op4_freq
        .l4 = op4_level
        if op4_envelope$ = "snap"
            .e4$ = .env_snap$
        elsif op4_envelope$ = "decay"
            .e4$ = .env_decay$
        elsif op4_envelope$ = "sus"
            .e4$ = .env_sus$
        elsif op4_envelope$ = "slow"
            .e4$ = .env_slow$
        endif
        
        .f5 = op5_freq
        .l5 = op5_level
        if op5_envelope$ = "snap"
            .e5$ = .env_snap$
        elsif op5_envelope$ = "decay"
            .e5$ = .env_decay$
        elsif op5_envelope$ = "sus"
            .e5$ = .env_sus$
        elsif op5_envelope$ = "slow"
            .e5$ = .env_slow$
        endif
        
        .f6 = op6_freq
        .l6 = op6_level
        .fb = op6_feedback
        if op6_envelope$ = "snap"
            .e6$ = .env_snap$
        elsif op6_envelope$ = "decay"
            .e6$ = .env_decay$
        elsif op6_envelope$ = "sus"
            .e6$ = .env_sus$
        elsif op6_envelope$ = "slow"
            .e6$ = .env_slow$
        endif
        
    elsif preset = 1
        # Electric Piano
        .algo = 3
        .f5 = 14.0
        .l5 = 3.0 * .b_fac
        .e5$ = .env_snap$
        .f4 = 1.0
        .l4 = 0.7
        .e4$ = .env_decay$
        .f2 = 1.0
        .l2 = 1.0 * .b_fac
        .e2$ = .env_decay$
        .f1 = 1.0
        .l1 = 1.0
        .e1$ = .env_sus$
        
    elsif preset = 2
        # Slap Bass
        .algo = 2
        .f3 = 2.0
        .l3 = 2.5 * .b_fac
        .e3$ = .env_snap$
        .f2 = 1.0
        .l2 = 1.5 * .b_fac
        .e2$ = .env_decay$
        .f1 = 1.0
        .l1 = 1.0
        .e1$ = .env_decay$
        .f6 = 1.0
        .l6 = 1.0
        .fb = 2.5 * .b_fac
        .e6$ = .env_sus$
        
    elsif preset = 3
        # Tubular Bells
        .algo = 3
        .f5 = 3.5
        .l5 = 1.5 * .b_fac
        .e5$ = .env_sus$
        .f4 = 1.0
        .l4 = 1.0
        .e4$ = .env_sus$
        .f2 = 14.0
        .l2 = 1.0 * .b_fac
        .e2$ = .env_decay$
        .f1 = 1.0
        .l1 = 1.0
        .e1$ = .env_sus$
        
    elsif preset = 4
        # Hammond Organ
        .algo = 1
        .f1 = 0.5
        .l1 = 0.8
        .e1$ = .env_sus$
        .f2 = 1.0
        .l2 = 1.0
        .e2$ = .env_sus$
        .f3 = 2.0
        .l3 = 0.7
        .e3$ = .env_sus$
        .f4 = 3.0
        .l4 = 0.5 * .b_fac
        .e4$ = .env_sus$
        .f5 = 4.0
        .l5 = 0.3 * .b_fac
        .e5$ = .env_sus$
        .f6 = 8.0
        .l6 = 0.2 * .b_fac
        .e6$ = .env_sus$
        
    elsif preset = 5
        # Warm Pad
        .algo = 1
        .f1 = 1.00
        .l1 = 0.5
        .e1$ = .env_slow$
        .f2 = 1.01
        .l2 = 0.5
        .e2$ = .env_slow$
        .f3 = 2.00
        .l3 = 0.3 * .b_fac
        .e3$ = .env_slow$
        .f4 = 2.02
        .l4 = 0.3 * .b_fac
        .e4$ = .env_slow$
        
    elsif preset = 6
        # Custom Test Tone
        .algo = 2
        .f2 = 2.0
        .l2 = 2.0 * .b_fac
        .e2$ = .env_decay$
        .f1 = 1.0
        .l1 = 1.0
        .e1$ = .env_sus$
    endif
    
    # === SYNTHESIS ENGINE ===
    Create Sound from formula: "temp", 1, 0, .dur, sampling_frequency, "0"
    
    # Phase calculations
    .p6$ = "2*pi*" + string$(.f6*.freq) + "*x"
    .p5$ = "2*pi*" + string$(.f5*.freq) + "*x"
    .p4$ = "2*pi*" + string$(.f4*.freq) + "*x"
    .p3$ = "2*pi*" + string$(.f3*.freq) + "*x"
    .p2$ = "2*pi*" + string$(.f2*.freq) + "*x"
    .p1$ = "2*pi*" + string$(.f1*.freq) + "*x"
    
    # OP 6 (Feedback)
    if .l6 > 0
        if .e6$ = ""
            .e6$ = .env_snap$
        endif
        if .fb > 0
            .fb_safe = min(.fb, 7.0)
            .s6$ = string$(.l6) + "*" + .e6$ + "*sin(" + .p6$ + "+" + string$(.fb_safe) + "*sin(" + .p6$ + "))"
        else
            .s6$ = string$(.l6) + "*" + .e6$ + "*sin(" + .p6$ + ")"
        endif
    else
        .s6$ = "0"
    endif
    
    # Algorithm Routing
    if .algo = 1
        # Parallel
        if .l5 > 0 and .e5$ <> ""
            .s5$ = string$(.l5) + "*" + .e5$ + "*sin(" + .p5$ + ")"
        else
            .s5$ = "0"
        endif
        if .l4 > 0 and .e4$ <> ""
            .s4$ = string$(.l4) + "*" + .e4$ + "*sin(" + .p4$ + ")"
        else
            .s4$ = "0"
        endif
        if .l3 > 0 and .e3$ <> ""
            .s3$ = string$(.l3) + "*" + .e3$ + "*sin(" + .p3$ + ")"
        else
            .s3$ = "0"
        endif
        if .l2 > 0 and .e2$ <> ""
            .s2$ = string$(.l2) + "*" + .e2$ + "*sin(" + .p2$ + ")"
        else
            .s2$ = "0"
        endif
        if .l1 > 0 and .e1$ <> ""
            .s1$ = string$(.l1) + "*" + .e1$ + "*sin(" + .p1$ + ")"
        else
            .s1$ = "0"
        endif
        .final$ = .s1$ + "+" + .s2$ + "+" + .s3$ + "+" + .s4$ + "+" + .s5$ + "+" + .s6$
        
    elsif .algo = 2
        # Series Stack
        if .l5 > 0 and .e5$ <> ""
            .s5$ = string$(.l5) + "*" + .e5$ + "*sin(" + .p5$ + "+" + .s6$ + ")"
        else
            .s5$ = .s6$
        endif
        if .l4 > 0 and .e4$ <> ""
            .s4$ = string$(.l4) + "*" + .e4$ + "*sin(" + .p4$ + "+" + .s5$ + ")"
        else
            .s4$ = .s5$
        endif
        if .l3 > 0 and .e3$ <> ""
            .s3$ = string$(.l3) + "*" + .e3$ + "*sin(" + .p3$ + "+" + .s4$ + ")"
        else
            .s3$ = .s4$
        endif
        if .l2 > 0 and .e2$ <> ""
            .s2$ = string$(.l2) + "*" + .e2$ + "*sin(" + .p2$ + "+" + .s3$ + ")"
        else
            .s2$ = .s3$
        endif
        if .l1 > 0 and .e1$ <> ""
            .s1$ = string$(.l1) + "*" + .e1$ + "*sin(" + .p1$ + "+" + .s2$ + ")"
        else
            .s1$ = .s2$
        endif
        .final$ = .s1$
        
    elsif .algo = 3
        # Dual Stack
        if .l5 > 0 and .e5$ <> ""
            .s5$ = string$(.l5) + "*" + .e5$ + "*sin(" + .p5$ + ")"
        else
            .s5$ = "0"
        endif
        if .l4 > 0 and .e4$ <> ""
            .s4$ = string$(.l4) + "*" + .e4$ + "*sin(" + .p4$ + "+" + .s5$ + ")"
        else
            .s4$ = .s5$
        endif
        if .l2 > 0 and .e2$ <> ""
            .s2$ = string$(.l2) + "*" + .e2$ + "*sin(" + .p2$ + ")"
        else
            .s2$ = "0"
        endif
        if .l1 > 0 and .e1$ <> ""
            .s1$ = string$(.l1) + "*" + .e1$ + "*sin(" + .p1$ + "+" + .s2$ + ")"
        else
            .s1$ = .s2$
        endif
        .final$ = .s1$ + "+" + .s4$
    endif
    
    # Apply synthesis
    Formula: string$(master_Volume) + " * 0.4 * (" + .final$ + ")"
    
    # Validate
    .min_check = Get minimum: 0, 0, "None"
    .max_check = Get maximum: 0, 0, "None"
    if .min_check = undefined or .max_check = undefined
        Formula: "0"
        appendInfoLine: "WARNING: Invalid synthesis at freq=" + string$(.freq)
    endif
    
    # Fade in/out to prevent clicks
    .totalDur = Get total duration
    Formula: "self * if x < 0.005 then x/0.005 else 1 fi"
    Formula: "self * if x > " + string$(.totalDur) + " - 0.01 then (" + string$(.totalDur) + " - x)/0.01 else 1 fi"
    
    Scale peak: 0.9
    
    .sound = selected("Sound")
endproc

# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    Erase all

    # --- Title (own clear band) ---
    Select outer viewport: 0, 8, 0.1, 0.7
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    if melody_demo
        Text: 0.5, "centre", 0.5, "half", "DX7 FM: " + preset$ + " (Melody Demo)"
    else
        Text: 0.5, "centre", 0.5, "half", "DX7 FM Synthesis: " + preset$
    endif

    # --- Panel 1: Waveform ---
    Select outer viewport: 0, 8, 0.9, 2.6
    Select inner viewport: 0.75, 7.6, 1.05, 2.5
    selectObject: sound
    Colour: "{0.20, 0.40, 0.70}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 3, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    # --- Panel 2: Spectrum ---
    Select outer viewport: 0, 8, 2.8, 4.5
    Select inner viewport: 0.75, 7.6, 2.95, 4.4
    selectObject: sound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")
    Colour: "{0.60, 0.30, 0.50}"
    Draw: 0, 5000, 0, 0, "no"
    removeObject: .spectrum
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 1000, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    # --- Panel 3: Spectrogram ---
    Select outer viewport: 0, 8, 4.7, 6.7
    Select inner viewport: 0.75, 7.6, 4.85, 6.6
    selectObject: sound
    .maxFreq = min(5000, base_Frequency * 12)
    To Spectrogram: 0.03, .maxFreq, 0.01, 20, "Gaussian"
    .spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: .spectrogram

    Select inner viewport: 0.75, 7.6, 4.85, 6.6
    Axes: 0, .totalDur, 0, .maxFreq
    Colour: "Black"
    Draw inner box
    Font size: 9
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 10
    Text left: "yes", "Frequency (Hz)"
    Text bottom: "yes", "Time (s)"

    # --- Summary panel (grey) ---
    Select outer viewport: 0, 8, 6.8, 7.2
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half", "F=" + fixed$(base_Frequency, 1) + " Hz | Brightness=" + fixed$(brightness, 2) + " | Decay=" + fixed$(decay_Scale, 2) + " | Envelope=" + envelope$
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc