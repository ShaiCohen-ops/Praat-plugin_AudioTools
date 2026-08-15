# ============================================================
# Praat AudioTools - Waveguide_Modal_Synthesis.praat
# Author: Shai Cohen
# Version: 1.1.1 reviewed
#
# Waveguide methods:
#   Fractional-delay feedback loop with a two-sample loss filter.
#   Delay compensation keeps the fundamental close to the target pitch.
#
# Modal methods:
#   Sum of damped sinusoidal modes using physically motivated ratio sets.
#   Each mode: A_m * sin(2*pi*f_m*t) * exp(-d_m*t)
#
# Visualization:
#   excitation/model -> delay or modal bank -> measured spectral peaks -> output
# ============================================================

form Waveguide and Modal Synthesis v1.1.1
    comment === Instrument Model ===
    optionmenu Method: 4
        option Waveguide: Plucked String
        option Waveguide: Breath-driven Loop
        option Modal: Bell-like Inharmonic
        option Modal: Plucked String
        option Modal: Struck Bar
        option Modal: Circular Membrane
    boolean Melody_demo 0

    comment === Musical Controls ===
    positive Frequency_Hz 220
    positive Duration_s 2.0
    real Damping_(0.9-0.9999) 0.998
    optionmenu Envelope: 1
        option No Envelope
        option Percussive
        option Slow Decay
        option Smooth Gate
        option Reverse Ramp
        option Tremolo
        option Swell
        option ADSR
        option Smooth Stutter
        option Random Bursts

    comment === Output ===
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

sample_rate_Hz = 44100
envelope_amount = 0.30
output_peak = 0.95
random_seed = 0

if edit_details
    beginPause: "Waveguide and Modal Synthesis - details"
        positive: "Sample rate (Hz)", sample_rate_Hz
        real: "Envelope amount (0..1)", envelope_amount
        positive: "Output peak", output_peak
        integer: "Random seed (0=random)", random_seed
    endPause: "OK", 1
endif

# ---------------- Validation ----------------
if damping < 0.9 or damping > 0.9999
    exitScript: "Damping must be between 0.9 and 0.9999."
endif
if envelope_amount < 0 or envelope_amount > 1
    exitScript: "Envelope amount must be between 0 and 1."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in (0, 1]."
endif
if sample_rate_Hz < 8000
    exitScript: "Sample rate is too low for this synthesis model."
endif

if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
endif

# ---------------- Model names and modal templates ----------------
if method = 1
    method_name$ = "WG_PluckedString"
    method_label$ = "Waveguide: Plucked String"
elsif method = 2
    method_name$ = "WG_BreathLoop"
    method_label$ = "Waveguide: Breath-driven Loop"
elsif method = 3
    method_name$ = "Modal_Bell"
    method_label$ = "Modal: Bell-like Inharmonic"
elsif method = 4
    method_name$ = "Modal_PluckedString"
    method_label$ = "Modal: Plucked String"
elsif method = 5
    method_name$ = "Modal_StruckBar"
    method_label$ = "Modal: Struck Bar"
elsif method = 6
    method_name$ = "Modal_Membrane"
    method_label$ = "Modal: Circular Membrane"
endif

num_modes = 0
max_mode_ratio = 1
if method = 3
    num_modes = 6
    mode_ratios# = { 1.000, 2.143, 3.413, 4.090, 5.190, 6.250 }
    mode_amps# = { 1.000, 0.700, 0.500, 0.300, 0.150, 0.080 }
    mode_decays# = { 0.500, 3.000, 6.000, 10.000, 15.000, 20.000 }
    max_mode_ratio = 6.250
elsif method = 4
    num_modes = 8
    mode_ratios# = { 1.000, 2.001, 3.004, 4.010, 5.020, 6.035, 7.055, 8.080 }
    mode_amps# = { 1.000, 0.500, 0.333, 0.250, 0.200, 0.167, 0.143, 0.125 }
    mode_decays# = { 0.300, 0.800, 1.500, 2.500, 4.000, 6.000, 8.500, 12.000 }
    max_mode_ratio = 8.080
elsif method = 5
    num_modes = 5
    mode_ratios# = { 1.000, 2.756, 5.404, 8.933, 13.344 }
    mode_amps# = { 1.000, 0.600, 0.350, 0.200, 0.100 }
    mode_decays# = { 0.400, 2.000, 5.000, 10.000, 18.000 }
    max_mode_ratio = 13.344
elsif method = 6
    num_modes = 5
    mode_ratios# = { 1.000, 1.593, 2.135, 2.296, 2.917 }
    mode_amps# = { 1.000, 0.700, 0.500, 0.400, 0.300 }
    mode_decays# = { 0.200, 0.800, 1.800, 3.000, 5.000 }
    max_mode_ratio = 2.917
endif

max_fundamental = frequency_Hz
if melody_demo
    max_fundamental = 523.25
endif
nyquist = sample_rate_Hz / 2
if method >= 3 and max_fundamental * max_mode_ratio >= 0.95 * nyquist
    exitScript: "Highest modal frequency exceeds 95% of Nyquist. Lower Frequency or raise Sample rate."
endif
if method <= 2 and sample_rate_Hz / max_fundamental < 4
    exitScript: "Waveguide period is too short at this sample rate. Lower Frequency or raise Sample rate."
endif

writeInfoLine: "=== Waveguide and Modal Synthesis v1.1.1 ==="
appendInfoLine: "Model: ", method_label$
appendInfoLine: "Sample rate: ", sample_rate_Hz, " Hz"
appendInfoLine: "Damping: ", fixed$(damping, 5)
appendInfoLine: "Envelope: ", envelope$
if random_seed > 0
    appendInfoLine: "Seed: ", random_seed
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
    representative_frequency = 261.63
    representative_duration = 0.4
else
    appendInfoLine: "Generating single note..."
    @makeSynth: frequency_Hz, duration_s
    sound = selected("Sound")
    Rename: method_name$ + "_" + fixed$(frequency_Hz, 0) + "Hz"
    representative_frequency = frequency_Hz
    representative_duration = duration_s
endif

# One normalization stage only: preserves relative note and channel dynamics.
selectObject: sound
peak_before = Get absolute extremum: 0, 0, "Sinc70"
if peak_before > 0
    Scale peak: output_peak
endif
output_peak_measured = Get absolute extremum: 0, 0, "Sinc70"
output_rms = Get root-mean-square: 0, 0

if draw_visualization
    @drawVisualization
endif

if play_result
    selectObject: sound
    Play
endif

selectObject: sound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Peak: ", fixed$(output_peak_measured, 4), " | RMS: ", fixed$(output_rms, 4)


# ==============================================================================
# Procedure: makeSynth
# ==============================================================================
procedure makeSynth: .freq, .dur

    if method <= 2
        # Fractional-delay Karplus-Strong style loop.
        # The two-sample average contributes about 0.5 sample phase delay,
        # so the explicit delay line targets sr/f - 0.5 samples.
        .sr = sample_rate_Hz
        .delay_target = .sr / .freq
        .line_delay = .delay_target - 0.5
        .delay_int = floor(.line_delay)
        .frac = .line_delay - .delay_int
        .ntotal = round(.dur * .sr)
        .seed_len = .delay_int + 2

        .sound = Create Sound from formula: "waveguide", 1, 0, .dur, .sr, "0"

        # Windowed random initial state avoids a hard onset at note boundaries.
        for .i from 1 to min(.seed_len, .ntotal)
            if .seed_len > 1
                .u = (.i - 1) / (.seed_len - 1)
            else
                .u = 0
            endif
            .win = sin(pi * .u) ^ 2
            Set value at sample number: 1, .i, randomUniform(-1, 1) * .win
        endfor

        # Combined fractional delay + two-point loss filter:
        # 0.5 * [(1-frac)y[n-N] + y[n-N-1] + frac*y[n-N-2]]
        for .i from .delay_int + 3 to .ntotal
            .a = Get value at sample number: 1, .i - .delay_int
            .b = Get value at sample number: 1, .i - .delay_int - 1
            .c = Get value at sample number: 1, .i - .delay_int - 2
            .loop = 0.5 * ((1 - .frac) * .a + .b + .frac * .c)
            .drive = 0
            if method = 2
                # Small continuous breath excitation drives the resonant loop.
                .drive = 0.02 * randomUniform(-1, 1)
            endif
            Set value at sample number: 1, .i, damping * .loop + .drive
        endfor

    else
        .sr = sample_rate_Hz
        .base_decay = (1 - damping) * 500
        .sound = Create Sound from formula: "modal", 1, 0, .dur, .sr, "0"

        for .m from 1 to num_modes
            .mfreq = .freq * mode_ratios#[.m]
            .mamp = mode_amps#[.m]
            .mdecay = mode_decays#[.m] * .base_decay
            selectObject: .sound
            Formula: "self + " + fixed$(.mamp, 6)
            ... + " * sin(2*pi*" + fixed$(.mfreq, 6) + "*x)"
            ... + " * exp(-" + fixed$(.mdecay, 8) + "*x)"
        endfor
    endif

    @applyEnvelope: .sound, .dur

    # Short raised-cosine note boundary tapers prevent clicks without changing
    # the main decay mechanism. They scale automatically for very short notes.
    selectObject: .sound
    .fade = min(0.003, .dur / 5)
    if .fade > 0
        Formula: "self * if x < " + fixed$(.fade, 8)
        ... + " then 0.5-0.5*cos(pi*x/" + fixed$(.fade, 8) + ") else 1 fi"
        .fade_start = .dur - .fade
        Formula: "self * if x > " + fixed$(.fade_start, 8)
        ... + " then 0.5-0.5*cos(pi*(" + fixed$(.dur, 8) + "-x)/" + fixed$(.fade, 8) + ") else 1 fi"
    endif
endproc


# ==============================================================================
# Procedure: applyEnvelope
# ==============================================================================
procedure applyEnvelope: .sound_id, .dur
    selectObject: .sound_id

    if envelope = 2
        .rate = 3 + 8 * envelope_amount
        Formula: "self * exp(-" + fixed$(.rate, 6) + "*x)"

    elsif envelope = 3
        .rate = 0.15 + 0.8 * envelope_amount
        Formula: "self * exp(-" + fixed$(.rate, 6) + "*x)"

    elsif envelope = 4
        .gate_rate = 2 + 10 * envelope_amount
        .gate_duty = 0.65
        Formula: "self * if (x*" + fixed$(.gate_rate, 6) + "-floor(x*" + fixed$(.gate_rate, 6) + ")) < " + fixed$(.gate_duty, 6)
        ... + " then sin(pi*(x*" + fixed$(.gate_rate, 6) + "-floor(x*" + fixed$(.gate_rate, 6) + "))/" + fixed$(.gate_duty, 6) + ")^2 else 0 fi"

    elsif envelope = 5
        Formula: "self * (0.5 - 0.5*cos(pi*x/" + fixed$(.dur, 8) + "))"

    elsif envelope = 6
        .trem_rate = 4 + 12 * envelope_amount
        .trem_depth = 0.2 + 0.7 * envelope_amount
        Formula: "self * (1-0.5*" + fixed$(.trem_depth, 6)
        ... + "+0.5*" + fixed$(.trem_depth, 6) + "*sin(2*pi*" + fixed$(.trem_rate, 6) + "*x))"

    elsif envelope = 7
        Formula: "self * sin(pi*x/" + fixed$(.dur, 8) + ")^2"

    elsif envelope = 8
        .attack = min(0.03, .dur * 0.12)
        .release = min(0.20, .dur * 0.25)
        .decay = min(0.15, .dur * 0.20)
        .sustain = 0.45 + 0.40 * envelope_amount
        .decay_end = .attack + .decay
        .release_start = .dur - .release
        if .release_start < .decay_end
            .decay = max(0.001, (.dur - .attack - .release) * 0.5)
            .decay_end = .attack + .decay
            .release_start = .dur - .release
        endif
        .adsr$ = "self * if x < " + fixed$(.attack, 8)
        .adsr$ = .adsr$ + " then x/" + fixed$(.attack, 8)
        .adsr$ = .adsr$ + " else if x < " + fixed$(.decay_end, 8)
        .adsr$ = .adsr$ + " then 1-(1-" + fixed$(.sustain, 6) + ")*((x-" + fixed$(.attack, 8) + ")/" + fixed$(.decay, 8) + ")"
        .adsr$ = .adsr$ + " else if x < " + fixed$(.release_start, 8)
        .adsr$ = .adsr$ + " then " + fixed$(.sustain, 6)
        .adsr$ = .adsr$ + " else " + fixed$(.sustain, 6) + "*(" + fixed$(.dur, 8) + "-x)/" + fixed$(.release, 8)
        .adsr$ = .adsr$ + " fi fi fi"
        Formula: .adsr$

    elsif envelope = 9
        .stutter_rate = 6 + 24 * envelope_amount
        .duty = 0.55
        Formula: "self * if (x*" + fixed$(.stutter_rate, 6) + "-floor(x*" + fixed$(.stutter_rate, 6) + ")) < " + fixed$(.duty, 6)
        ... + " then sin(pi*(x*" + fixed$(.stutter_rate, 6) + "-floor(x*" + fixed$(.stutter_rate, 6) + "))/" + fixed$(.duty, 6) + ")^2 else 0 fi"

    elsif envelope = 10
        .density = 2 + 12 * envelope_amount
        .burst_width = min(0.18, max(0.03, 0.8 / .density))
        .env = Create Sound from formula: "burst_env", 1, 0, .dur, sample_rate_Hz, "0"
        .pp = Create Poisson process: "burst_pp", 0, .dur, .density
        .n = Get number of points
        for .k to .n
            .t = Get time from index: .k
            .amp = randomUniform(0.45, 1.0)
            .t1 = max(0, .t - .burst_width / 2)
            .t2 = min(.dur, .t + .burst_width / 2)
            .w = .t2 - .t1
            if .w > 0
                selectObject: .env
                Formula: "self + if x >= " + fixed$(.t1, 8) + " and x <= " + fixed$(.t2, 8)
                ... + " then " + fixed$(.amp, 6) + "*(0.5-0.5*cos(2*pi*(x-" + fixed$(.t1, 8) + ")/" + fixed$(.w, 8) + ")) else 0 fi"
            endif
            selectObject: .pp
        endfor
        removeObject: .pp
        selectObject: .sound_id
        Formula: "self * object[" + string$(.env) + "]"
        removeObject: .env
    endif
endproc


# ==============================================================================
# Procedure: drawVisualization
# ==============================================================================
procedure drawVisualization
    selectObject: sound
    .totalDur = Get total duration
    .repFreq = representative_frequency
    .repDur = representative_duration
    .nyq = sample_rate_Hz / 2

    # Extract the representative first note for measured spectral analysis.
    .analysis_end = min(.repDur, .totalDur)
    .analysis_note = Extract part: 0, .analysis_end, "rectangular", 1, "no"
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")
    .nbins = Get number of bins
    .df = Get frequency from bin number: 2

    # Peak and RMS already refer to full output.
    selectObject: sound
    .peak = Get absolute extremum: 0, 0, "Sinc70"
    .rms = Get root-mean-square: 0, 0

    Erase all

    # ----- Title strip -----
    Select outer viewport: 0, 8, 0.0, 0.55
    Select inner viewport: 0, 8, 0.0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "Waveguide and Modal Synthesis"
    Font size: 9
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5, "centre", 0.18, "half", method_label$

    # ----- Process strip -----
    Select outer viewport: 0, 8, 0.58, 1.0
    Select inner viewport: 0, 8, 0.58, 1.0
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.25,0.25,0.25}"
    if method <= 2
        Text: 0.5, "centre", 0.5, "half", "noise excitation -> fractional delay -> two-sample loss -> damping feedback -> envelope -> output"
    else
        Text: 0.5, "centre", 0.5, "half", "impulse-like excitation -> modal frequency bank -> per-mode decay -> envelope -> summed output"
    endif

    # ----- Panel A title -----
    Select outer viewport: 0.35, 4.0, 1.08, 1.38
    Select inner viewport: 0.35, 4.0, 1.08, 1.38
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    if method <= 2
        Text: 0.5, "centre", 0.5, "half", "A - Waveguide loop geometry"
    else
        Text: 0.5, "centre", 0.5, "half", "A - Modal decay score"
    endif

    if method <= 2
        # Diagram uses normalized coordinates, not data-world sound coordinates.
        Select inner viewport: 0.55, 3.85, 1.45, 3.65
        Axes: 0, 1, 0, 1
        Colour: "{0.96,0.96,0.96}"
        Paint rectangle: "{0.96,0.96,0.96}", 0, 1, 0, 1
        Colour: "Black"
        Draw inner box
        Font size: 8
        Text: 0.12, "centre", 0.70, "half", "noise"
        Text: 0.42, "centre", 0.70, "half", "delay"
        Text: 0.70, "centre", 0.70, "half", "loss LP"
        Text: 0.88, "centre", 0.70, "half", "gain"
        Draw arrow: 0.20, 0.70, 0.34, 0.70
        Draw arrow: 0.50, 0.70, 0.62, 0.70
        Draw arrow: 0.77, 0.70, 0.82, 0.70
        Draw arrow: 0.88, 0.60, 0.88, 0.34
        Draw arrow: 0.88, 0.34, 0.42, 0.34
        Font size: 7
        .targetDelay = sample_rate_Hz / .repFreq
        .lineDelay = .targetDelay - 0.5
        .delayInt = floor(.lineDelay)
        .frac = .lineDelay - .delayInt
        Text: 0.42, "centre", 0.52, "half", "D=" + fixed$(.targetDelay, 3) + " samples"
        Text: 0.42, "centre", 0.18, "half", "N=" + string$(.delayInt) + " + frac " + fixed$(.frac, 3)
        Text: 0.70, "centre", 0.52, "half", "0.5(1+z^-1)"
        Text: 0.88, "centre", 0.52, "half", fixed$(damping, 4)
    else
        Select inner viewport: 0.55, 3.85, 1.45, 3.65
        .fmin = .repFreq * 0.85
        .fmax = min(.nyq * 0.95, .repFreq * max_mode_ratio * 1.12)
        Axes: 0, .repDur, ln(.fmin), ln(.fmax)
        Colour: "{0.97,0.97,0.97}"
        Paint rectangle: "{0.97,0.97,0.97}", 0, .repDur, ln(.fmin), ln(.fmax)
        .baseDecay = (1 - damping) * 500
        for .m to num_modes
            .mf = .repFreq * mode_ratios#[.m]
            .md = mode_decays#[.m] * .baseDecay
            if .md > 0
                .t60 = ln(1000) / .md
            else
                .t60 = .repDur
            endif
            .lineEnd = min(.repDur, .t60)
            .lw = 1 + 2 * mode_amps#[.m]
            Line width: .lw
            Colour: "{0.20,0.40,0.70}"
            Draw line: 0, ln(.mf), .lineEnd, ln(.mf)
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text bottom: "yes", "Time (s)"
        Text left: "yes", "Mode frequency (log Hz)"
        # Sparse logarithmic frequency marks avoid label collisions.
        .fticks# = {50,100,200,500,1000,2000,5000,10000}
        for .i to size(.fticks#)
            .tf = .fticks#[.i]
            if .tf >= .fmin and .tf <= .fmax
                if .tf >= 1000
                    .lab$ = fixed$(.tf/1000, 0) + "k"
                else
                    .lab$ = fixed$(.tf, 0)
                endif
                One mark left: ln(.tf), "yes", "yes", "no", .lab$
            endif
        endfor
    endif

    # ----- Panel B title -----
    Select outer viewport: 4.05, 7.75, 1.08, 1.38
    Select inner viewport: 4.05, 7.75, 1.08, 1.38
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    if method <= 2
        Text: 0.5, "centre", 0.5, "half", "B - Predicted loop decay"
    else
        Text: 0.5, "centre", 0.5, "half", "B - Per-mode amplitude decay"
    endif

    Select inner viewport: 4.25, 7.55, 1.45, 3.65
    Axes: 0, .repDur, -60, 2
    Colour: "{0.97,0.97,0.97}"
    Paint rectangle: "{0.97,0.97,0.97}", 0, .repDur, -60, 2
    if method <= 2
        .targetDelay = sample_rate_Hz / .repFreq
        .w = 2 * pi * .repFreq / sample_rate_Hz
        .lineDelay = .targetDelay - 0.5
        .delayInt = floor(.lineDelay)
        .frac = .lineDelay - .delayInt
        .hre = 1 - .frac + .frac * cos(.w)
        .him = -.frac * sin(.w)
        .interpMag = sqrt(.hre*.hre + .him*.him)
        .loopGain = damping * abs(cos(.w/2)) * .interpMag
        if .loopGain > 0 and .loopGain < 1
            .t60Loop = (.targetDelay / sample_rate_Hz) * ln(0.001) / ln(.loopGain)
        else
            .t60Loop = .repDur
        endif
        Colour: "{0.65,0.30,0.25}"
        Line width: 2
        .steps = 100
        for .k from 1 to .steps - 1
            .t1 = (.k - 1) * .repDur / (.steps - 1)
            .t2 = .k * .repDur / (.steps - 1)
            if .t60Loop > 0
                .db1 = max(-60, -60 * .t1 / .t60Loop)
                .db2 = max(-60, -60 * .t2 / .t60Loop)
            else
                .db1 = -60
                .db2 = -60
            endif
            Draw line: .t1, .db1, .t2, .db2
        endfor
        Line width: 1
    else
        .baseDecay = (1 - damping) * 500
        for .m to num_modes
            .md = mode_decays#[.m] * .baseDecay
            .a0 = mode_amps#[.m]
            Colour: "{0.20,0.40,0.70}"
            .steps = 80
            for .k from 1 to .steps - 1
                .t1 = (.k - 1) * .repDur / (.steps - 1)
                .t2 = .k * .repDur / (.steps - 1)
                .a1 = .a0 * exp(-.md * .t1)
                .a2 = .a0 * exp(-.md * .t2)
                .db1 = max(-60, 20 * ln(max(.a1, 0.001)) / ln(10))
                .db2 = max(-60, 20 * ln(max(.a2, 0.001)) / ln(10))
                Draw line: .t1, .db1, .t2, .db2
            endfor
        endfor
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left every: 1, 20, "yes", "yes", "no"
    Text left: "yes", "Relative level (dB)"
    Text bottom: "yes", "Time (s)"

    # ----- Panel C title -----
    Select outer viewport: 0.35, 7.75, 3.82, 4.12
    Select inner viewport: 0.35, 7.75, 3.82, 4.12
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "C - Expected resonances vs measured spectrum"

    # Keep the spectral plot clear of its bottom tick labels and text strips.
    Select inner viewport: 0.65, 7.55, 4.18, 5.62
    if method <= 2
        .fminC = max(40, .repFreq * 0.7)
        .fmaxC = min(.nyq * 0.95, .repFreq * 9)
        .nExpected = 8
    else
        .fminC = max(40, .repFreq * 0.75)
        .fmaxC = min(.nyq * 0.95, .repFreq * max_mode_ratio * 1.15)
        .nExpected = num_modes
    endif
    Axes: ln(.fminC), ln(.fmaxC), 0, 1.05
    Colour: "{0.97,0.97,0.97}"
    Paint rectangle: "{0.97,0.97,0.97}", ln(.fminC), ln(.fmaxC), 0, 1.05

    # Measure magnitudes at expected modal/harmonic frequencies.
    .measured# = zero#(.nExpected)
    .maxMag = 0
    for .m to .nExpected
        if method <= 2
            .ef = .repFreq * .m
        else
            .ef = .repFreq * mode_ratios#[.m]
        endif
        .bin = round(.ef / .df) + 1
        .bin = min(.nbins, max(1, .bin))
        selectObject: .spectrum
        .re = Get real value in bin: .bin
        .im = Get imaginary value in bin: .bin
        .mag = sqrt(.re*.re + .im*.im)
        .measured#[.m] = .mag
        if .mag > .maxMag
            .maxMag = .mag
        endif
    endfor
    if .maxMag <= 0
        .maxMag = 1
    endif

    for .m to .nExpected
        if method <= 2
            .ef = .repFreq * .m
            .modelY = 1 / .m
        else
            .ef = .repFreq * mode_ratios#[.m]
            .modelY = mode_amps#[.m]
        endif
        if .ef >= .fminC and .ef <= .fmaxC
            .measY = .measured#[.m] / .maxMag
            Colour: "{0.65,0.30,0.25}"
            Line width: 2
            Draw line: ln(.ef), 0, ln(.ef), .measY
            Colour: "{0.15,0.35,0.70}"
            Line width: 1
            Draw circle: ln(.ef), min(1, .modelY), 0.025
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Normalized amplitude"
    # Numeric ticks stay attached to the data frame; the axis title gets its own strip below.
    .ticks# = {50,100,200,500,1000,2000,5000,10000}
    for .i to size(.ticks#)
        .tf = .ticks#[.i]
        if .tf >= .fminC and .tf <= .fmaxC
            if .tf >= 1000
                .lab$ = fixed$(.tf/1000, 0) + "k"
            else
                .lab$ = fixed$(.tf, 0)
            endif
            One mark bottom: ln(.tf), "yes", "yes", "no", .lab$
        endif
    endfor

    # Panel C axis-title strip.  Keep this separate from the data viewport so
    # Praat's tick labels can never collide with the axis title or legend.
    Select outer viewport: 1.2, 7.2, 5.84, 6.04
    Select inner viewport: 1.2, 7.2, 5.84, 6.04
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Frequency (log Hz)"

    # Panel C legend strip.
    Select outer viewport: 1.2, 7.2, 6.08, 6.30
    Select inner viewport: 1.2, 7.2, 6.08, 6.30
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.15,0.35,0.70}"
    Text: 0.29, "centre", 0.5, "half", "circle = model template"
    Colour: "{0.65,0.30,0.25}"
    Text: 0.72, "centre", 0.5, "half", "stem = measured spectrum"

    # ----- Panel D title -----
    Select outer viewport: 0.35, 7.75, 6.40, 6.66
    Select inner viewport: 0.35, 7.75, 6.40, 6.66
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "D - Measured output"

    Select inner viewport: 0.65, 7.55, 6.72, 8.08
    selectObject: sound
    Colour: "{0.20,0.40,0.70}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"

    # ----- QC strip: two rows x three columns -----
    .qcY1 = 8.34
    .qcY2 = 8.72
    .cellW = 8 / 3
    for .c from 1 to 3
        .x1 = (.c - 1) * .cellW
        .x2 = .c * .cellW
        Select outer viewport: .x1, .x2, .qcY1, .qcY2
        Select inner viewport: .x1, .x2, .qcY1, .qcY2
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "{0.25,0.25,0.25}"
        if .c = 1
            Text: 0.5, "centre", 0.5, "half", "Model: " + method_name$
        elsif .c = 2
            Text: 0.5, "centre", 0.5, "half", "F0=" + fixed$(.repFreq, 1) + " Hz | SR=" + fixed$(sample_rate_Hz, 0)
        else
            Text: 0.5, "centre", 0.5, "half", "Damping=" + fixed$(damping, 5) + " | Env=" + envelope$
        endif
    endfor

    for .c from 1 to 3
        .x1 = (.c - 1) * .cellW
        .x2 = .c * .cellW
        Select outer viewport: .x1, .x2, .qcY2, 9.10
        Select inner viewport: .x1, .x2, .qcY2, 9.10
        Axes: 0, 1, 0, 1
        Font size: 7
        Colour: "{0.25,0.25,0.25}"
        if .c = 1
            if method <= 2
                .targetDelay = sample_rate_Hz / .repFreq
                Text: 0.5, "centre", 0.5, "half", "Target period=" + fixed$(.targetDelay, 3) + " samples"
            else
                Text: 0.5, "centre", 0.5, "half", "Modes=" + string$(num_modes) + " | max ratio=" + fixed$(max_mode_ratio, 3)
            endif
        elsif .c = 2
            Text: 0.5, "centre", 0.5, "half", "Nyquist=" + fixed$(.nyq, 0) + " Hz"
        else
            Text: 0.5, "centre", 0.5, "half", "Peak=" + fixed$(.peak, 3) + " | RMS=" + fixed$(.rms, 3)
        endif
    endfor

    removeObject: .spectrum, .analysis_note
    selectObject: sound
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc
