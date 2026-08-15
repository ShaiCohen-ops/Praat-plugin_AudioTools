# ============================================================
# Praat AudioTools - Subtractive_Synthesis_Generator.praat v2.2
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# License: MIT License
#
# Subtractive synthesis with a band-limited oscillator source,
# time-varying recursive filters, resonance/Q control, amplitude
# envelopes, and process-oriented visualization.
#
# v2.2 review:
# - Filter envelope now controls cutoff continuously in time.
# - LP 12 / LP 24 use 2 / 4 cascaded one-pole IIR stages.
# - Resonance is separated from transition smoothing and implemented
#   as a Q-dependent band around the moving cutoff.
# - Discontinuous oscillators use polyBLEP band-limiting.
# - Amplitude envelopes start/end at zero to avoid clicks.
# - Removed ineffective Volume control (it was cancelled by Scale peak).
# - Main form shortened; technical controls moved to Edit details.
# - Visualization explains source -> control -> filter -> envelope -> output.
# ============================================================

form Subtractive Synthesis Generator v2.2
    optionmenu Preset: 1
        option Custom
        option Moog Bass
        option ARP Lead
        option TB-303 Acid
        option String Pad
        option Plucked Bass
        option Synth Brass

    boolean Bass_line_demo 0

    optionmenu Waveform: 1
        option Sawtooth
        option Square
        option Pulse
        option Triangle
        option Dual Saw
        option Super Saw
    positive Frequency_Hz 220

    optionmenu Filter_type: 3
        option No Filter
        option Low Pass 12dB
        option Low Pass 24dB
        option High Pass
        option Band Pass
        option Notch
    positive Cutoff_freq_Hz 1000
    real Resonance_(0-1) 0.3

    optionmenu Filter_envelope: 1
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

    positive Duration_s 3.0
    boolean Edit_details 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ------------------------------------------------------------
# Technical defaults / optional detail page
# ------------------------------------------------------------
sampling_frequency = 44100
pulse_width = 0.30
output_peak = 0.90

if edit_details
    beginPause: "Subtractive Synthesis v2.2 - Details"
        integer: "Sampling frequency (Hz)", sampling_frequency
        real: "Pulse width (0.1..0.9)", pulse_width
        real: "Output peak (0..1]", output_peak
    endPause: "Run", 1
endif

# ------------------------------------------------------------
# Presets
# ------------------------------------------------------------
presetName$ = "Custom"
if preset = 2
    waveform = 1
    frequency_Hz = 110
    filter_type = 3
    cutoff_freq_Hz = 600
    resonance = 0.60
    filter_envelope = 5
    envelope_amount = 0.80
    amplitude_envelope = 1
    presetName$ = "MoogBass"
elsif preset = 3
    waveform = 1
    frequency_Hz = 440
    filter_type = 2
    cutoff_freq_Hz = 2000
    resonance = 0.40
    filter_envelope = 2
    envelope_amount = 0.90
    amplitude_envelope = 2
    presetName$ = "ARPLead"
elsif preset = 4
    waveform = 1
    frequency_Hz = 220
    filter_type = 3
    cutoff_freq_Hz = 800
    resonance = 0.80
    filter_envelope = 4
    envelope_amount = 1.00
    amplitude_envelope = 4
    presetName$ = "TB303Acid"
elsif preset = 5
    waveform = 6
    frequency_Hz = 220
    filter_type = 2
    cutoff_freq_Hz = 1500
    resonance = 0.20
    filter_envelope = 1
    envelope_amount = 0.50
    amplitude_envelope = 3
    presetName$ = "StringPad"
elsif preset = 6
    waveform = 1
    frequency_Hz = 110
    filter_type = 3
    cutoff_freq_Hz = 1200
    resonance = 0.50
    filter_envelope = 2
    envelope_amount = 0.70
    amplitude_envelope = 4
    presetName$ = "PluckedBass"
elsif preset = 7
    waveform = 1
    frequency_Hz = 330
    filter_type = 2
    cutoff_freq_Hz = 2500
    resonance = 0.30
    filter_envelope = 3
    envelope_amount = 0.60
    amplitude_envelope = 3
    presetName$ = "SynthBrass"
endif

# Keep labels synchronized with numeric menu values.
if waveform = 1
    waveform$ = "Sawtooth"
elsif waveform = 2
    waveform$ = "Square"
elsif waveform = 3
    waveform$ = "Pulse"
elsif waveform = 4
    waveform$ = "Triangle"
elsif waveform = 5
    waveform$ = "Dual Saw"
else
    waveform$ = "Super Saw"
endif

if filter_type = 1
    filter_type$ = "No Filter"
elsif filter_type = 2
    filter_type$ = "Low Pass 12dB"
elsif filter_type = 3
    filter_type$ = "Low Pass 24dB"
elsif filter_type = 4
    filter_type$ = "High Pass 12dB"
elsif filter_type = 5
    filter_type$ = "Band Pass"
else
    filter_type$ = "Notch"
endif

if filter_envelope = 1
    filter_envelope$ = "No Envelope"
elsif filter_envelope = 2
    filter_envelope$ = "Short Sweep"
elsif filter_envelope = 3
    filter_envelope$ = "Long Sweep"
elsif filter_envelope = 4
    filter_envelope$ = "Attack Emphasis"
else
    filter_envelope$ = "Decay Sweep"
endif

if amplitude_envelope = 1
    amplitude_envelope$ = "Percussive"
elsif amplitude_envelope = 2
    amplitude_envelope$ = "Sustained"
elsif amplitude_envelope = 3
    amplitude_envelope$ = "Slow Attack"
elsif amplitude_envelope = 4
    amplitude_envelope$ = "Pluck"
else
    amplitude_envelope$ = "Gate"
endif

# ------------------------------------------------------------
# Validation
# ------------------------------------------------------------
if sampling_frequency < 8000
    exitScript: "Sample rate must be at least 8000 Hz."
endif
if duration_s <= 0
    exitScript: "Duration must be positive."
endif
if duration_s * sampling_frequency < 16
    exitScript: "Duration is too short for the selected sample rate."
endif
if frequency_Hz <= 0
    exitScript: "Frequency must be positive."
endif
if cutoff_freq_Hz <= 0
    exitScript: "Cutoff frequency must be positive."
endif
if resonance < 0 or resonance > 1
    exitScript: "Resonance must be between 0 and 1."
endif
if envelope_amount < 0 or envelope_amount > 1
    exitScript: "Envelope amount must be between 0 and 1."
endif
if pulse_width < 0.1 or pulse_width > 0.9
    exitScript: "Pulse width must be between 0.1 and 0.9."
endif
if output_peak <= 0 or output_peak > 1
    exitScript: "Output peak must be in (0, 1]."
endif

nyquist = sampling_frequency / 2
max_filter_hz = 0.45 * sampling_frequency
max_osc_frequency = frequency_Hz
if waveform = 5
    max_osc_frequency = frequency_Hz + 7
elsif waveform = 6
    max_osc_frequency = frequency_Hz * 1.01
endif
if max_osc_frequency >= max_filter_hz
    exitScript: "Oscillator frequency is too high for the selected sample rate. Keep the highest oscillator below 45% of sample rate."
endif
displayQ = 0.7071068 + resonance*(10-0.7071068)
if filter_type = 3
    displayQ = 1.306563 + resonance*(10-1.306563)
endif

# ------------------------------------------------------------
# Info / run setup
# ------------------------------------------------------------
clearinfo
writeInfoLine: "=== Subtractive Synthesis Generator v2.2 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Source: ", waveform$, " @ ", frequency_Hz, " Hz"
appendInfoLine: "Filter: ", filter_type$, " | base cutoff ", cutoff_freq_Hz, " Hz | resonance ", fixed$(resonance, 2)
appendInfoLine: "Filter control: ", filter_envelope$, " | amount ", fixed$(envelope_amount, 2)
appendInfoLine: "Amplitude envelope: ", amplitude_envelope$
appendInfoLine: "Process: band-limited source -> moving IIR filter/Q -> amplitude envelope -> output scaling"

needViz = draw_visualization
makeVizObjects = 0
if needViz and bass_line_demo = 0
    makeVizObjects = 1
endif

# ------------------------------------------------------------
# Main rendering
# ------------------------------------------------------------
if bass_line_demo
    appendInfoLine: "Generating four-note bass pattern..."
    @makeSynth: 110, 0.25
    id1 = selected("Sound")
    @makeSynth: 110, 0.25
    id2 = selected("Sound")
    @makeSynth: 220, 0.25
    id3 = selected("Sound")
    @makeSynth: 196, 0.25
    id4 = selected("Sound")

    selectObject: id1, id2, id3, id4
    Concatenate
    resultSound = selected("Sound")
    Rename: "subtractive_bassline_" + presetName$
    removeObject: id1, id2, id3, id4

    if needViz
        makeVizObjects = 1
        @makeSynth: 110, 1.0
        vizSound = selected("Sound")
    endif
else
    appendInfoLine: "Generating single note..."
    @makeSynth: frequency_Hz, duration_s
    resultSound = selected("Sound")
    Rename: "subtractive_" + waveform$ + "_" + presetName$
    if needViz
        vizSound = resultSound
    endif
endif

selectObject: resultSound
finalPeak = Get absolute extremum: 0, 0, "None"
finalRms = Get root-mean-square: 0, 0
appendInfoLine: "Output peak: ", fixed$(finalPeak, 4), " | RMS: ", fixed$(finalRms, 4)

if needViz
    @drawVisualization
endif

if play_result
    selectObject: resultSound
    Play
endif
selectObject: resultSound

# ============================================================================
# Oscillator helpers
# ============================================================================
procedure makePolyBlepSaw: .freq, .dur, .phaseOffset, .name$
    .dt = .freq / sampling_frequency
    .id = Create Sound from formula: .name$, 1, 0, .dur, sampling_frequency,
    ... "2*(.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset)) - 1 - " +
    ... "if (.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset)) < .dt then " +
    ... "2*(.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset))/.dt - ((.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset))/.dt)^2 - 1 " +
    ... "else if (.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset)) > 1-.dt then " +
    ... "((.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset)-1)/.dt)^2 + 2*((.freq*x + .phaseOffset - floor(.freq*x + .phaseOffset)-1)/.dt) + 1 " +
    ... "else 0 fi fi"
endproc

procedure makeOscillator: .freq, .dur
    if waveform = 1
        @makePolyBlepSaw: .freq, .dur, 0, "oscSaw"
        .id = selected("Sound")
        Formula: "0.85 * self"
    elsif waveform = 2
        @makePolyBlepSaw: .freq, .dur, 0, "sqA"
        .a = selected("Sound")
        @makePolyBlepSaw: .freq, .dur, -0.5, "sqB"
        .b = selected("Sound")
        selectObject: .a
        Copy: "oscSquare"
        .id = selected("Sound")
        Formula: "0.85 * (-object[.a,col] + object[.b,col])"
        removeObject: .a, .b
    elsif waveform = 3
        @makePolyBlepSaw: .freq, .dur, 0, "pulseA"
        .a = selected("Sound")
        @makePolyBlepSaw: .freq, .dur, -pulse_width, "pulseB"
        .b = selected("Sound")
        selectObject: .a
        Copy: "oscPulse"
        .id = selected("Sound")
        Formula: "0.85 * (-object[.a,col] + object[.b,col] + (2*pulse_width-1))"
        removeObject: .a, .b
    elsif waveform = 4
        # Band-limited square integrated into a triangle.
        @makePolyBlepSaw: .freq, .dur, 0, "triA"
        .a = selected("Sound")
        @makePolyBlepSaw: .freq, .dur, -0.5, "triB"
        .b = selected("Sound")
        selectObject: .a
        Copy: "triSquare"
        .sq = selected("Sound")
        Formula: "-object[.a,col] + object[.b,col]"
        removeObject: .a, .b
        selectObject: .sq
        Copy: "oscTriangle"
        .id = selected("Sound")
        Formula: "if col = 1 then 0 else self[col-1] + object[.sq,col] * dx fi"
        .mean = Get mean: 0, 0, 0
        Formula: "self - .mean"
        .pk = Get absolute extremum: 0, 0, "None"
        if .pk > 0
            Formula: "0.85 * self / .pk"
        endif
        removeObject: .sq
    elsif waveform = 5
        @makePolyBlepSaw: .freq, .dur, 0, "dualA"
        .a = selected("Sound")
        @makePolyBlepSaw: .freq+7, .dur, 0, "dualB"
        .b = selected("Sound")
        selectObject: .a
        Copy: "oscDualSaw"
        .id = selected("Sound")
        Formula: "0.45 * (object[.a,col] + object[.b,col])"
        removeObject: .a, .b
    else
        @makePolyBlepSaw: .freq, .dur, 0, "super0"
        .s0 = selected("Sound")
        @makePolyBlepSaw: .freq*1.005, .dur, 0, "super1"
        .s1 = selected("Sound")
        @makePolyBlepSaw: .freq*0.995, .dur, 0, "super2"
        .s2 = selected("Sound")
        @makePolyBlepSaw: .freq*1.01, .dur, 0, "super3"
        .s3 = selected("Sound")
        @makePolyBlepSaw: .freq*0.99, .dur, 0, "super4"
        .s4 = selected("Sound")
        selectObject: .s0
        Copy: "oscSuperSaw"
        .id = selected("Sound")
        Formula: "0.18*(object[.s0,col]+object[.s1,col]+object[.s2,col]+object[.s3,col]+object[.s4,col])"
        removeObject: .s0, .s1, .s2, .s3, .s4
    endif
    selectObject: .id
endproc

# ============================================================================
# Control generators
# ============================================================================
procedure makeCutoffControl: .dur
    .id = Create Sound from formula: "cutoffControl", 1, 0, .dur, sampling_frequency, "cutoff_freq_Hz"
    selectObject: .id
    if filter_envelope = 2
        .sweep = max(0.02, 0.25*.dur)
        Formula: "cutoff_freq_Hz * (1 + 2*envelope_amount * if x < .sweep then 1-x/.sweep else 0 fi)"
    elsif filter_envelope = 3
        Formula: "cutoff_freq_Hz * (1 + 1.5*envelope_amount*(x/.dur))"
    elsif filter_envelope = 4
        .attackWindow = max(0.02, 0.20*.dur)
        Formula: "cutoff_freq_Hz * (1 + 3*envelope_amount * if x < .attackWindow then 4*(x/.attackWindow)*(1-x/.attackWindow) else 0 fi)"
    elsif filter_envelope = 5
        Formula: "cutoff_freq_Hz * (1 + 2*envelope_amount*(1-x/.dur))"
    endif
    Formula: "if self < 20 then 20 else if self > max_filter_hz then max_filter_hz else self fi fi"
endproc

procedure makeBiquadControls: .cutoffID
    selectObject: .cutoffID
    Copy: "filterCos"
    filterCosID = selected("Sound")
    Formula: "cos(2*pi*self/sampling_frequency)"
    selectObject: .cutoffID
    Copy: "filterSin"
    filterSinID = selected("Sound")
    Formula: "sin(2*pi*self/sampling_frequency)"
endproc

procedure makeAmplitudeControl: .dur
    .attackFast = min(0.008, 0.08*.dur)
    .releaseFast = min(0.020, 0.12*.dur)
    .releaseSlow = min(0.080, 0.20*.dur)
    if amplitude_envelope = 1
        .id = Create Sound from formula: "ampControl", 1, 0, .dur, sampling_frequency,
        ... "(if x < .attackFast then 0.5-0.5*cos(pi*x/.attackFast) else 1 fi) * exp(-8*x) * " +
        ... "(if x > .dur-.releaseFast then 0.5-0.5*cos(pi*(.dur-x)/.releaseFast) else 1 fi)"
    elsif amplitude_envelope = 2
        .id = Create Sound from formula: "ampControl", 1, 0, .dur, sampling_frequency,
        ... "(if x < .attackFast then 0.5-0.5*cos(pi*x/.attackFast) else 1 fi) * exp(-1.5*x) * " +
        ... "(if x > .dur-.releaseSlow then 0.5-0.5*cos(pi*(.dur-x)/.releaseSlow) else 1 fi)"
    elsif amplitude_envelope = 3
        .atk = min(0.5, 0.40*.dur)
        .id = Create Sound from formula: "ampControl", 1, 0, .dur, sampling_frequency,
        ... "(if x < .atk then 0.5-0.5*cos(pi*x/.atk) else 1 fi) * " +
        ... "(if x > .dur-.releaseSlow then 0.5-0.5*cos(pi*(.dur-x)/.releaseSlow) else 1 fi)"
    elsif amplitude_envelope = 4
        .attackPluck = min(0.003, 0.05*.dur)
        .id = Create Sound from formula: "ampControl", 1, 0, .dur, sampling_frequency,
        ... "(if x < .attackPluck then 0.5-0.5*cos(pi*x/.attackPluck) else 1 fi) * exp(-20*x) * " +
        ... "(if x > .dur-.releaseFast then 0.5-0.5*cos(pi*(.dur-x)/.releaseFast) else 1 fi)"
    else
        .releaseGate = min(0.10, 0.25*.dur)
        .id = Create Sound from formula: "ampControl", 1, 0, .dur, sampling_frequency,
        ... "(if x < .attackFast then 0.5-0.5*cos(pi*x/.attackFast) else 1 fi) * " +
        ... "(if x > .dur-.releaseGate then 0.5-0.5*cos(pi*(.dur-x)/.releaseGate) else 1 fi)"
    endif
endproc

# ============================================================================
# Time-varying RBJ-style biquad primitives. Formula evaluation is recursive
# in Praat, so self[col-1] / self[col-2] are already-filtered samples.
# ============================================================================
procedure biquadLowPass: .sourceID, .cosID, .sinID, .q, .name$
    selectObject: .sourceID
    Copy: .name$
    .out = selected("Sound")
    Formula: "(((1-object[.cosID,col])/2)*object[.sourceID,col] + (1-object[.cosID,col])*object[.sourceID,col-1] + ((1-object[.cosID,col])/2)*object[.sourceID,col-2] + 2*object[.cosID,col]*self[col-1] - (1-object[.sinID,col]/(2*.q))*self[col-2]) / (1+object[.sinID,col]/(2*.q))"
endproc

procedure biquadHighPass: .sourceID, .cosID, .sinID, .q, .name$
    selectObject: .sourceID
    Copy: .name$
    .out = selected("Sound")
    Formula: "(((1+object[.cosID,col])/2)*object[.sourceID,col] - (1+object[.cosID,col])*object[.sourceID,col-1] + ((1+object[.cosID,col])/2)*object[.sourceID,col-2] + 2*object[.cosID,col]*self[col-1] - (1-object[.sinID,col]/(2*.q))*self[col-2]) / (1+object[.sinID,col]/(2*.q))"
endproc

procedure biquadBandPass: .sourceID, .cosID, .sinID, .q, .name$
    selectObject: .sourceID
    Copy: .name$
    .out = selected("Sound")
    Formula: "((object[.sinID,col]/(2*.q))*object[.sourceID,col] - (object[.sinID,col]/(2*.q))*object[.sourceID,col-2] + 2*object[.cosID,col]*self[col-1] - (1-object[.sinID,col]/(2*.q))*self[col-2]) / (1+object[.sinID,col]/(2*.q))"
endproc

procedure biquadNotch: .sourceID, .cosID, .sinID, .q, .name$
    selectObject: .sourceID
    Copy: .name$
    .out = selected("Sound")
    Formula: "(object[.sourceID,col] - 2*object[.cosID,col]*object[.sourceID,col-1] + object[.sourceID,col-2] + 2*object[.cosID,col]*self[col-1] - (1-object[.sinID,col]/(2*.q))*self[col-2]) / (1+object[.sinID,col]/(2*.q))"
endproc

# ============================================================================
# Main synthesizer engine
# ============================================================================
procedure makeSynth: .freq, .dur
    # 1. Band-limited source
    @makeOscillator: .freq, .dur
    .source = selected("Sound")

    if makeVizObjects
        selectObject: .source
        Copy: "viz_source"
        rawOscID = selected("Sound")
    endif

    # 2. Explicit time-varying filter control
    @makeCutoffControl: .dur
    .cutoffID = selected("Sound")
    @makeBiquadControls: .cutoffID
    .cosID = filterCosID
    .sinID = filterSinID

    if makeVizObjects
        selectObject: .cutoffID
        Copy: "viz_cutoff"
        cutoffVizID = selected("Sound")
    endif

    # 3. Filter topology. Resonance maps to biquad Q rather than a
    # transition-band smoothing parameter.
    .q12 = 0.7071068 + resonance*(10-0.7071068)
    if filter_type = 1
        selectObject: .source
        Copy: "filterBypass"
        .filtered = selected("Sound")
    elsif filter_type = 2
        @biquadLowPass: .source, .cosID, .sinID, .q12, "lp12"
        .filtered = selected("Sound")
    elsif filter_type = 3
        # 4th-order Butterworth pair at resonance=0; second pair becomes
        # increasingly resonant as the control rises.
        .q1 = 0.5411961
        .q2 = 1.306563 + resonance*(10-1.306563)
        @biquadLowPass: .source, .cosID, .sinID, .q1, "lp24a"
        .stage1 = selected("Sound")
        @biquadLowPass: .stage1, .cosID, .sinID, .q2, "lp24b"
        .filtered = selected("Sound")
        removeObject: .stage1
    elsif filter_type = 4
        @biquadHighPass: .source, .cosID, .sinID, .q12, "hp12"
        .filtered = selected("Sound")
    elsif filter_type = 5
        @biquadBandPass: .source, .cosID, .sinID, .q12, "bandPass"
        .filtered = selected("Sound")
    else
        @biquadNotch: .source, .cosID, .sinID, .q12, "notch"
        .filtered = selected("Sound")
    endif

    if makeVizObjects
        selectObject: .filtered
        Copy: "viz_filtered"
        filteredID = selected("Sound")
    endif

    # 4. Amplitude control
    @makeAmplitudeControl: .dur
    .ampID = selected("Sound")
    if makeVizObjects
        selectObject: .ampID
        Copy: "viz_amp"
        ampVizID = selected("Sound")
    endif

    selectObject: .filtered
    Formula: "self * object[.ampID,col]"

    # 5. One final output scaling step
    .prePeak = Get absolute extremum: 0, 0, "None"
    if .prePeak > 0
        Scale peak: output_peak
    endif
    .result = selected("Sound")

    removeObject: .source, .cutoffID, .cosID, .sinID, .ampID
    selectObject: .result
endproc

# ============================================================================
# Visualization: mechanism first, output last
# ============================================================================
procedure drawVisualization
    Erase all

    # Header
    Select outer viewport: 0, 8, 0.05, 0.42
    Select inner viewport: 0.15, 7.85, 0.08, 0.38
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "Subtractive Synthesis - " + presetName$
    Font size: 8
    Text: 0.5, "centre", 0.20, "half", "band-limited oscillator  ->  moving recursive filter + Q  ->  amplitude envelope  ->  output"

    # ---------- A: source waveform ----------
    Select outer viewport: 0, 4, 0.55, 2.15
    Select inner viewport: 0.62, 3.75, 0.83, 1.93
    .showDur = min(0.04, duration_s)
    selectObject: rawOscID
    .rawPk = Get absolute extremum: 0, .showDur, "None"
    if .rawPk < 0.1
        .rawPk = 1
    endif
    Colour: "{0.60,0.35,0.15}"
    Draw: 0, .showDur, -.rawPk, .rawPk, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0, 4, 0.55, 2.15
    Select inner viewport: 0.20, 3.90, 0.58, 0.78
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "A. Source oscillator - " + waveform$ + " @ " + string$(frequency_Hz) + " Hz"

    # ---------- A2: source / filtered measured spectra ----------
    Select outer viewport: 4, 8, 0.55, 2.15
    Select inner viewport: 4.50, 7.72, 0.83, 1.93
    .maxF = min(8000, nyquist)
    selectObject: rawOscID
    To Ltas: 80
    .rawL = selected("Ltas")
    Colour: "{0.78,0.55,0.36}"
    Draw: 0, .maxF, 20, 90, "no", "Curve"
    selectObject: filteredID
    To Ltas: 80
    .filtL = selected("Ltas")
    Colour: "{0.20,0.45,0.72}"
    Line width: 1.5
    Draw: 0, .maxF, 20, 90, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Level (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Font size: 7
    Colour: "{0.78,0.55,0.36}"
    Text: .maxF*0.62, "left", 85, "half", "source"
    Colour: "{0.20,0.45,0.72}"
    Text: .maxF*0.62, "left", 79, "half", "after filter"
    removeObject: .rawL, .filtL
    Select outer viewport: 4, 8, 0.55, 2.15
    Select inner viewport: 4.15, 7.90, 0.58, 0.78
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Measured spectral sculpting"

    # ---------- B: moving cutoff / Q ----------
    Select outer viewport: 0, 4, 2.35, 4.05
    Select inner viewport: 0.62, 3.75, 2.65, 3.80
    selectObject: cutoffVizID
    .cMin = Get minimum: 0, 0, "None"
    .cMax = Get maximum: 0, 0, "None"
    if .cMax <= .cMin
        .cMin = max(0, .cMin*0.8)
        .cMax = .cMax*1.2 + 1
    else
        .pad = 0.08*(.cMax-.cMin)
        .cMin = max(0, .cMin-.pad)
        .cMax = .cMax+.pad
    endif
    Colour: "{0.15,0.50,0.70}"
    Draw: 0, 0, .cMin, .cMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Cutoff (Hz)"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0, 4, 2.35, 4.05
    Select inner viewport: 0.20, 3.90, 2.38, 2.58
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "B. Filter control - " + filter_envelope$ + " | Q=" + fixed$(displayQ, 2)

    # ---------- C: amplitude envelope ----------
    Select outer viewport: 4, 8, 2.35, 4.05
    Select inner viewport: 4.50, 7.72, 2.65, 3.80
    selectObject: ampVizID
    Colour: "{0.55,0.25,0.60}"
    Line width: 1.5
    Draw: 0, 0, 0, 1.05, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Gain"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 4, 8, 2.35, 4.05
    Select inner viewport: 4.15, 7.90, 2.38, 2.58
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "C. Amplitude control - " + amplitude_envelope$

    # ---------- D: final measured output ----------
    Select outer viewport: 0, 8, 4.25, 5.65
    Select inner viewport: 0.62, 7.72, 4.52, 5.42
    selectObject: vizSound
    Colour: "{0.18,0.55,0.30}"
    Draw: 0, 0, -1, 1, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Select outer viewport: 0, 8, 4.25, 5.65
    Select inner viewport: 0.20, 7.90, 4.28, 4.47
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "D. Measured output (verification)"

    # ---------- QC summary, 2 rows x 3 columns ----------
    selectObject: cutoffVizID
    .cutMin = Get minimum: 0, 0, "None"
    .cutMax = Get maximum: 0, 0, "None"
    selectObject: vizSound
    .pk = Get absolute extremum: 0, 0, "None"
    .rms = Get root-mean-square: 0, 0

    Select outer viewport: 0, 8, 5.80, 6.62
    Select inner viewport: 0.30, 7.70, 5.88, 6.53
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.94,0.94,0.94}", 0, 3, 0, 2
    Colour: "{0.25,0.25,0.25}"
    Draw rectangle: 0, 3, 0, 2
    Draw line: 1, 0, 1, 2
    Draw line: 2, 0, 2, 2
    Draw line: 0, 1, 3, 1
    Font size: 7
    Text: 0.5, "centre", 1.55, "half", "Source: polyBLEP " + waveform$
    Text: 1.5, "centre", 1.55, "half", "Cutoff: " + fixed$(.cutMin,0) + ".." + fixed$(.cutMax,0) + " Hz"
    Text: 2.5, "centre", 1.55, "half", "Filter: " + filter_type$
    Text: 0.5, "centre", 0.45, "half", "Q: " + fixed$(displayQ,2) + " | res " + fixed$(resonance,2)
    Text: 1.5, "centre", 0.45, "half", "Amp env: " + amplitude_envelope$
    Text: 2.5, "centre", 0.45, "half", "Peak " + fixed$(.pk,3) + " | RMS " + fixed$(.rms,3)

    # Cleanup visualization copies only. vizSound/result remains.
    removeObject: rawOscID, filteredID, cutoffVizID, ampVizID
    if bass_line_demo
        removeObject: vizSound
    endif
endproc
