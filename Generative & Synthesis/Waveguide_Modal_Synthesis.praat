# ============================================================
# Praat AudioTools - Waveguide_Modal_Synthesis.praat
# Author: Shai Cohen  (genuine synthesis rewrite)
# Version: 1.0
#
# WAVEGUIDE (methods 1-2): Karplus-Strong sample-by-sample loop
#   new_sample = damping * average( sample[i-N], sample[i-N+1] )
#   N = sr/freq  (delay-line = one pitch period)
#   The two-sample average IS the low-pass loss filter at reflection.
#   ⚠ Sample loop is slow in Praat. Melody mode = 8 loops.
#     Keep duration ≤ 2 s for reasonable wait time.
#
# MODAL (methods 3-6): Physically derived mode ratios, per-mode decay
#   Each mode = A*sin(2π·f·t)*exp(−d·t)
#   This is the impulse response of a 2nd-order IIR resonator —
#   genuine modal synthesis for impulsively excited objects.
# ============================================================

form Waveguide and Modal Synthesis
    comment === Instrument Model ===
    optionmenu Method: 4
        option Waveguide: Plucked String
        option Waveguide: Blown Pipe
        option Modal: Struck Bell
        option Modal: Plucked String
        option Modal: Struck Bar
        option Modal: Membrane / Drum
    boolean Melody_demo 0
    comment (Melody plays a short arpeggio with the selected model)

    comment === Physical Parameters ===
    positive Frequency_Hz 220
    positive Duration_s 2.0
    real Damping_(0.9-0.9999) 0.998
    real Excitation_strength_(0-1) 0.8
    real Chaos_(0-1) 0.3

    comment === Amplitude Envelope ===
    optionmenu Envelope: 1
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
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# --- Short name used for Sound object naming ---
if method = 1
    method_name$ = "WG_PluckedString"
elsif method = 2
    method_name$ = "WG_BlownPipe"
elsif method = 3
    method_name$ = "Modal_Bell"
elsif method = 4
    method_name$ = "Modal_PluckedString"
elsif method = 5
    method_name$ = "Modal_StruckBar"
elsif method = 6
    method_name$ = "Modal_Membrane"
endif

# --- Long name for display ---
if method = 1
    method_label$ = "Waveguide: Plucked String"
elsif method = 2
    method_label$ = "Waveguide: Blown Pipe"
elsif method = 3
    method_label$ = "Modal: Struck Bell"
elsif method = 4
    method_label$ = "Modal: Plucked String"
elsif method = 5
    method_label$ = "Modal: Struck Bar"
elsif method = 6
    method_label$ = "Modal: Membrane / Drum"
endif

writeInfoLine:  "=== Waveguide & Modal Synthesis ==="
appendInfoLine: "Model:     ", method_label$
appendInfoLine: "Frequency: ", frequency_Hz, " Hz"
appendInfoLine: "Damping:   ", damping
if method <= 2 and melody_demo
    appendInfoLine: "(Waveguide melody = 8 sample loops — please wait)"
endif
appendInfoLine: ""

# ============================================================
# Main: melody or single note
# ============================================================
if melody_demo
    appendInfoLine: "Generating melody..."

    @makeSynth: 261.63, 0.4
    id1 = selected("Sound")
    @makeSynth: 329.63, 0.4
    id2 = selected("Sound")
    @makeSynth: 392.00, 0.4
    id3 = selected("Sound")
    @makeSynth: 523.25, 0.6
    id4 = selected("Sound")
    @makeSynth: 392.00, 0.4
    id5 = selected("Sound")
    @makeSynth: 329.63, 0.4
    id6 = selected("Sound")
    @makeSynth: 261.63, 0.4
    id7 = selected("Sound")
    @makeSynth: 196.00, 0.8
    id8 = selected("Sound")

    selectObject: id1, id2, id3, id4, id5, id6, id7, id8
    Concatenate
    sound = selected("Sound")
    Rename: method_name$ + "_melody"

    removeObject: id1, id2, id3, id4, id5, id6, id7, id8

    selectObject: sound
else
    appendInfoLine: "Generating single note..."
    @makeSynth: frequency_Hz, duration_s
    sound = selected("Sound")
    Rename: method_name$ + "_" + fixed$(frequency_Hz, 0) + "Hz"
endif

# ============================================================
# Apply Envelope
# ============================================================
selectObject: sound

if envelope = 2
    Formula: "self * exp(-x*5)"

elsif envelope = 3
    Formula: "self * exp(-x*0.3)"

elsif envelope = 4
    gate_period = 0.1 + chaos * 0.3
    Formula: "self * if sin(2*pi*x/gate_period) > 0 then 1 else 0 fi"

elsif envelope = 5
    totalDur = Get total duration
    Formula: "self * (x/totalDur)"

elsif envelope = 6
    trem_rate  = 5   + chaos * 15
    trem_depth = 0.3 + chaos * 0.5
    Formula: "self * (1 - trem_depth + trem_depth*sin(2*pi*trem_rate*x))"

elsif envelope = 7
    attack_time = 0.3 + chaos * 0.5
    Formula: "self * if x < attack_time then x/attack_time else 1 fi"

elsif envelope = 8
    # ADSR — build formula string with literal values to avoid Praat
    # parser confusion with multi-elsif inside Formula strings.
    totalDur      = Get total duration
    attack        = 0.01
    decay         = 0.1 + chaos * 0.2
    sustain       = 0.5 + chaos * 0.3
    release       = 0.3
    decay_end     = attack + decay
    release_start = totalDur - release
    adsr$ =  "self * if x < "  + fixed$(attack, 6)
    adsr$ = adsr$ + " then x/" + fixed$(attack, 6)
    adsr$ = adsr$ + " elsif x < " + fixed$(decay_end, 6)
    adsr$ = adsr$ + " then 1-(1-" + fixed$(sustain, 6) + ")*((x-" + fixed$(attack, 6) + ")/" + fixed$(decay, 6) + ")"
    adsr$ = adsr$ + " elsif x < " + fixed$(release_start, 6)
    adsr$ = adsr$ + " then " + fixed$(sustain, 6)
    adsr$ = adsr$ + " else "  + fixed$(sustain, 6) + "*(1-(x-" + fixed$(release_start, 6) + ")/" + fixed$(release, 6) + ")"
    adsr$ = adsr$ + " fi"
    Formula: adsr$

elsif envelope = 9
    stutter_rate = 10 + chaos * 30
    Formula: "self * if floor(x*stutter_rate) mod 2 = 0 then 1 else 0 fi"

elsif envelope = 10
    burst_density = 5 + chaos * 20
    Formula: "self * if randomUniform(0,1) < burst_density*0.05 then exp(-(x-floor(x*burst_density)/burst_density)*50) else 0 fi"
endif

selectObject: sound
Scale peak: 0.95

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    @drawVisualization
endif

# ============================================================
# Play
# ============================================================
if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")


# ==============================================================================
# Procedure: makeSynth — generate one note at .freq Hz, .dur seconds
# ==============================================================================
procedure makeSynth: .freq, .dur

    if method <= 2
        # --------------------------------------------------------------
        # WAVEGUIDE SYNTHESIS  (Karplus-Strong)
        # --------------------------------------------------------------
        # 22050 Hz keeps loop iterations manageable (~22k per second)
        .sr     = 22050
        .period = round(.sr / .freq)
        .ntotal = round(.dur * .sr)

        .sound = Create Sound from formula: "waveguide", 1, 0, .dur, .sr, "0"

        if method = 1
            # Plucked string: one noise burst (length = one period)
            for .i from 1 to .period
                Set value at sample number: 1, .i,
                ... randomUniform(-1, 1) * excitation_strength
            endfor
        else
            # Blown pipe: sustained noise for ~8 periods,
            # simulating continuous breath pressure into the tube
            for .i from 1 to .ntotal
                if .i <= .period * 8
                    Set value at sample number: 1, .i,
                    ... randomUniform(-0.4, 0.4) * excitation_strength
                endif
            endfor
        endif

        # Waveguide feedback loop:
        #   new = damping * (y[i-N] + y[i-N+1]) / 2
        #   The two-sample average is a first-order low-pass filter,
        #   modelling energy loss at each string/tube reflection.
        for .i from .period + 1 to .ntotal
            .y1 = Get value at sample number: 1, .i - .period
            .y2 = Get value at sample number: 1, .i - .period + 1
            Set value at sample number: 1, .i, damping * (.y1 + .y2) * 0.5
        endfor

    else
        # --------------------------------------------------------------
        # MODAL SYNTHESIS
        # Each mode = A * sin(2π·f_m·t) * exp(−d_m·t)
        # = impulse response of a 2nd-order bandpass resonator
        # Modes are defined by real physical frequency ratios.
        # --------------------------------------------------------------
        .sr         = 44100
        # Maps damping slider to a useful decay range:
        #   0.9990 → ~0.5  (long ring)   0.9000 → ~50 (short ring)
        .base_decay = (1 - damping) * 500

        if method = 3
            # Struck Bell  (inharmonic: higher modes decay much faster)
            .num_modes    = 6
            .mode_ratios# = { 1.000,  2.143,  3.413,  4.090,  5.190,  6.250 }
            .mode_amps#   = { 1.000,  0.700,  0.500,  0.300,  0.150,  0.080 }
            .mode_decays# = { 0.500,  3.000,  6.000, 10.000, 15.000, 20.000 }

        elsif method = 4
            # Plucked String  (near-harmonic: slight stiffness inharmonicity)
            .num_modes    = 8
            .mode_ratios# = { 1.000,  2.001,  3.004,  4.010,  5.020,  6.035,  7.055,  8.080 }
            .mode_amps#   = { 1.000,  0.500,  0.333,  0.250,  0.200,  0.167,  0.143,  0.125 }
            .mode_decays# = { 0.300,  0.800,  1.500,  2.500,  4.000,  6.000,  8.500, 12.000 }

        elsif method = 5
            # Struck Bar  (Euler-Bernoulli beam: strongly inharmonic)
            .num_modes    = 5
            .mode_ratios# = {  1.000,  2.756,  5.404,  8.933, 13.344 }
            .mode_amps#   = {  1.000,  0.600,  0.350,  0.200,  0.100 }
            .mode_decays# = {  0.400,  2.000,  5.000, 10.000, 18.000 }

        elsif method = 6
            # Membrane / Drum  (Bessel function zeros J_0, J_1...)
            .num_modes    = 5
            .mode_ratios# = { 1.000,  1.593,  2.135,  2.296,  2.917 }
            .mode_amps#   = { 1.000,  0.700,  0.500,  0.400,  0.300 }
            .mode_decays# = { 0.200,  0.800,  1.800,  3.000,  5.000 }
        endif

        .sound = Create Sound from formula: "modal", 1, 0, .dur, .sr, "0"

        for .m from 1 to .num_modes
            .mfreq  = .freq * .mode_ratios# [.m]
            .mamp   = excitation_strength * .mode_amps# [.m]
            .mdecay = .mode_decays# [.m] * .base_decay

            selectObject: .sound
            Formula: "self + " + fixed$(.mamp,  6)
            ...     + " * sin(2*pi*" + fixed$(.mfreq,  3) + "*x)"
            ...     + " * exp(-"     + fixed$(.mdecay, 6) + "*x)"
        endfor
    endif

    # Click prevention: 5 ms fade-in, 10 ms fade-out
    selectObject: .sound
    .tdur = Get total duration
    Formula: "self * if x < 0.005 then x/0.005 else 1 fi"
    Formula: "self * if x > " + fixed$(.tdur - 0.01, 6)
    ...     + " then (" + fixed$(.tdur, 6) + "-x)/0.01 else 1 fi"
    Scale peak: 0.9

endproc


# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization

    selectObject: sound
    .totalDur = Get total duration

    Erase all

    # === Title ===
    Select outer viewport: 0, 7, 0.2, 0.8
    Font size: 14
    Colour: "Black"
    if melody_demo
        Text: 0.5, "centre", 0.6, "half",
        ... "Waveguide & Modal: " + method_label$ + "  (Melody Demo)"
    else
        Text: 0.5, "centre", 0.6, "half",
        ... "Waveguide & Modal: " + method_label$
    endif
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half",
    ... "F=" + fixed$(frequency_Hz, 1) + " Hz  |  Damping=" + fixed$(damping, 4)
    ...     + "  |  Excitation=" + fixed$(excitation_strength, 2)

    # === Waveform ===
    Select outer viewport: 0, 7, 1.0, 2.8
    Select inner viewport: 0.6, 6.6, 1.1, 2.7

    selectObject: sound
    Colour: "{0.2, 0.4, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    # === Spectrum ===
    Select outer viewport: 0, 7, 3.0, 4.8
    Select inner viewport: 0.6, 6.6, 3.1, 4.7

    selectObject: sound
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Colour: "{0.6, 0.3, 0.5}"
    Draw: 0, 5000, 0, 0, "no"

    Colour: "Black"
    Draw inner box
    Marks left: 3, "yes", "yes", "no"
    Marks bottom every: 1, 1000, "yes", "yes", "no"
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    removeObject: .spectrum

    # === Spectrogram ===
    Select outer viewport: 0, 7, 5.0, 7.2
    Select inner viewport: 0.6, 6.6, 5.1, 7.1

    selectObject: sound
    .maxFreq = min(5000, frequency_Hz * 12)
    To Spectrogram: 0.03, .maxFreq, 0.01, 20, "Gaussian"
    .spectrogram = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"

    removeObject: .spectrogram

    Select inner viewport: 0.6, 6.6, 5.1, 7.1
    Axes: 0, .totalDur, 0, .maxFreq

    # Draw modal frequency lines for inharmonic models
    if method = 3 or method = 5 or method = 6
        Colour: "{1, 1, 0.5}"
        Dotted line

        if method = 5
            .modes# = {1, 2.756, 5.404, 8.933}
        elsif method = 6
            .modes# = {1, 1.593, 2.135, 2.295, 2.917}
        elsif method = 3
            .modes# = {1, 2.143, 3.413, 4.090, 5.190}
        endif

        for .m to size(.modes#)
            .modeFreq = frequency_Hz * .modes#[.m]
            if .modeFreq < .maxFreq
                Draw line: 0, .modeFreq, .totalDur, .modeFreq
            endif
        endfor
        Solid line
    endif

    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
    Font size: 8
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"

    # === Legend for inharmonic models ===
    if method = 3 or method = 5 or method = 6
        Select outer viewport: 0, 7, 7.3, 7.6
        Font size: 8
        Colour: "{0.4, 0.4, 0.4}"
        if method = 5
            Text: 0.5, "centre", 0.5, "half",
            ... "Bar modes: 1 : 2.756 : 5.404 : 8.933 (yellow lines)"
        elsif method = 6
            Text: 0.5, "centre", 0.5, "half",
            ... "Membrane modes: 1 : 1.593 : 2.135 : 2.295 : 2.917 (yellow lines)"
        elsif method = 3
            Text: 0.5, "centre", 0.5, "half",
            ... "Bell modes: 1 : 2.143 : 3.413 : 4.090 : 5.190 (yellow lines)"
        endif
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1

endproc
