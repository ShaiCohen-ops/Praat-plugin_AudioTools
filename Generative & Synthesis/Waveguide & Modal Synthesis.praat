# ============================================================
# Praat AudioTools - Waveguide_Modal_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Fixed synthesis + visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Physical Modeling Synthesis using modal and filtered excitation
#   techniques. Simulates the physics of real instruments:
#   strings, pipes, bars, membranes, bells, and more.
#
# Changelog v0.2:
#   - Fixed waveguide synthesis (now uses modal approach)
#   - All sounds now start at t=0
#   - Added melody demo mode
#   - Added visualization
# ============================================================

form Physical Modeling Synthesis
    comment === Demo Mode ===
    boolean Melody_demo 0
    comment (If checked, plays a test melody with selected model)
    
    comment === Instrument Model ===
    optionmenu Model_type: 1
        option Bowed String
        option Blown Pipe
        option Struck Bar
        option Plucked Membrane
        option Blown Bottle
        option Scraped Surface
        option Hammered String
        option Reed Pipe
        option Brass Lip
        option Vocal Tract
        option Struck Bell
        option Bowed Glass
        option Friction Drum
        option Breath Noise
        option Modal Resonator
    
    comment === Physical Parameters ===
    positive Duration_s 3.0
    positive Frequency_Hz 220
    real Excitation_strength_(0-1) 0.7
    real Damping_(0.9-0.999) 0.995
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

sampling_frequency = 44100

# Decay rate from damping (higher damping = slower decay)
decayRate = (1 - damping) * 100

# === Info ===
writeInfoLine: "=== Physical Modeling Synthesis ==="
appendInfoLine: "Model: ", model_type$
appendInfoLine: "Frequency: ", frequency_Hz, " Hz"
appendInfoLine: "Damping: ", damping, " (decay rate: ", fixed$(decayRate, 2), ")"
appendInfoLine: ""

# === Main Logic ===
if melody_demo
    appendInfoLine: "Generating melody demo..."
    
    # Test melody: C4, E4, G4, C5, G4, E4, C4, G3 (arpeggio)
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
    
    # Combine
    selectObject: id1, id2, id3, id4, id5, id6, id7, id8
    Concatenate
    sound = selected("Sound")
    Rename: "physical_" + model_type$ + "_melody"
    
    removeObject: id1, id2, id3, id4, id5, id6, id7, id8
    
    selectObject: sound
else
    # Single note
    @makeSynth: frequency_Hz, duration_s
    sound = selected("Sound")
    Rename: "physical_" + model_type$
endif

# === Apply Envelope ===
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
    trem_rate = 5 + chaos * 15
    trem_depth = 0.3 + chaos * 0.5
    Formula: "self * (1 - trem_depth + trem_depth*sin(2*pi*trem_rate*x))"
elsif envelope = 7
    attack_time = 0.3 + chaos * 0.5
    Formula: "self * if x < attack_time then x/attack_time else 1 fi"
elsif envelope = 8
    totalDur = Get total duration
    attack = 0.01
    decay = 0.1 + chaos * 0.2
    sustain = 0.5 + chaos * 0.3
    release = 0.3
    decay_end = attack + decay
    release_start = totalDur - release
    Formula: "self * if x < attack then x/attack elsif x < decay_end then 1-(1-sustain)*((x-attack)/decay) elsif x < release_start then sustain else sustain*(1-(x-release_start)/release) fi"
elsif envelope = 9
    stutter_rate = 10 + chaos * 30
    Formula: "self * if floor(x*stutter_rate) mod 2 = 0 then 1 else 0 fi"
elsif envelope = 10
    burst_density = 5 + chaos * 20
    Formula: "self * if randomUniform(0,1) < burst_density*0.05 then exp(-(x-floor(x*burst_density)/burst_density)*50) else 0 fi"
endif

selectObject: sound
Scale peak: 0.95

# === Visualization ===
if draw_visualization
    @drawVisualization
endif

# === Play ===
if play_result
    selectObject: sound
    Play
endif

# === Final Selection ===
selectObject: sound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: makeSynth - Generate one note
# ==============================================================================
procedure makeSynth: .freq, .dur
    
    .decayRate = (1 - damping) * 100
    
    if model_type = 1
        # === Bowed String ===
        .bow_pressure = 0.3 + excitation_strength * 0.5
        .f$ = fixed$(.freq, 2)
        .bp$ = fixed$(.bow_pressure, 3)
        .dr$ = fixed$(.decayRate * 0.3, 3)
        .sound = Create Sound from formula: "BowedString", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (sin(2*pi*" + .f$ + "*x) + 0.5*sin(4*pi*" + .f$ + "*x) + 0.3*sin(6*pi*" + .f$ + "*x)) * (1 + " + .bp$ + "*sin(20*x)) * exp(-" + .dr$ + "*x)"
        
    elsif model_type = 2
        # === Blown Pipe ===
        .breath_pressure = excitation_strength
        .temp = Create Sound from formula: "BlownPipe", 1, 0, .dur, sampling_frequency,
        ... ".breath_pressure * randomGauss(0, 0.5) * (1 + 0.5*sin(2*pi*" + fixed$(.freq, 2) + "*x))"
        Filter (pass Hann band): .freq*0.8, .freq*1.2, 50
        .sound = selected("Sound")
        removeObject: .temp
        selectObject: .sound
        Formula: "self * exp(-" + fixed$(.decayRate*0.2, 3) + "*x)"
        
    elsif model_type = 3
        # === Struck Bar (inharmonic) ===
        .f1 = .freq
        .f2 = .freq * 2.756
        .f3 = .freq * 5.404
        .f4 = .freq * 8.933
        .dr$ = fixed$(.decayRate, 3)
        .sound = Create Sound from formula: "StruckBar", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * exp(-" + .dr$ + "*x) * (sin(2*pi*" + fixed$(.f1, 2) + "*x) + 0.7*sin(2*pi*" + fixed$(.f2, 2) + "*x)*exp(-x*3) + 0.4*sin(2*pi*" + fixed$(.f3, 2) + "*x)*exp(-x*6) + 0.2*sin(2*pi*" + fixed$(.f4, 2) + "*x)*exp(-x*10))"
        
    elsif model_type = 4
        # === Plucked Membrane ===
        .f1 = .freq
        .f2 = .freq * 1.593
        .f3 = .freq * 2.135
        .f4 = .freq * 2.295
        .f5 = .freq * 2.917
        .dr$ = fixed$(.decayRate, 3)
        .sound = Create Sound from formula: "PluckedMembrane", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * exp(-" + .dr$ + "*x) * (sin(2*pi*" + fixed$(.f1, 2) + "*x) + 0.5*sin(2*pi*" + fixed$(.f2, 2) + "*x) + 0.3*sin(2*pi*" + fixed$(.f3, 2) + "*x) + 0.25*sin(2*pi*" + fixed$(.f4, 2) + "*x) + 0.15*sin(2*pi*" + fixed$(.f5, 2) + "*x))"
        
    elsif model_type = 5
        # === Blown Bottle ===
        .temp = Create Sound from formula: "BlownBottle", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (0.3*randomGauss(0, 1) + 0.7*sin(2*pi*" + fixed$(.freq, 2) + "*x)) * (1 + 0.2*sin(x*3))"
        Filter (pass Hann band): .freq*0.5, .freq*1.5, 100
        .sound = selected("Sound")
        removeObject: .temp
        selectObject: .sound
        Formula: "self * exp(-" + fixed$(.decayRate*0.15, 3) + "*x)"
        
    elsif model_type = 6
        # === Scraped Surface ===
        .sound = Create Sound from formula: "ScrapedSurface", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * sin(2*pi*" + fixed$(.freq, 2) + "*x) * (0.5 + 0.5*randomUniform(0,1)) * if randomUniform(0,1) < 0.7 then 1 else 0.3 fi"
        
    elsif model_type = 7
        # === Hammered String ===
        .hammer_stiffness = 1 - excitation_strength * 0.5
        .attackTime = 0.002 + .hammer_stiffness * 0.008
        .at$ = fixed$(.attackTime, 5)
        .dr$ = fixed$(.decayRate * 0.5, 3)
        .sound = Create Sound from formula: "HammeredString", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (if x < " + .at$ + " then x/" + .at$ + " else exp(-" + .dr$ + "*(x-" + .at$ + ")) fi) * (sin(2*pi*" + fixed$(.freq, 2) + "*x) + 0.5*sin(4*pi*" + fixed$(.freq, 2) + "*x) + 0.25*sin(6*pi*" + fixed$(.freq, 2) + "*x) + 0.12*sin(8*pi*" + fixed$(.freq, 2) + "*x))"
        
    elsif model_type = 8
        # === Reed Pipe ===
        .reed_stiffness = 0.5 + chaos * 0.3
        .dr$ = fixed$(.decayRate * 0.2, 3)
        .sound = Create Sound from formula: "ReedPipe", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (sin(2*pi*" + fixed$(.freq, 2) + "*x) + 0.33*sin(6*pi*" + fixed$(.freq, 2) + "*x) + 0.2*sin(10*pi*" + fixed$(.freq, 2) + "*x)) * (1 + 0.1*randomGauss(0, " + fixed$(.reed_stiffness, 3) + ")) * exp(-" + .dr$ + "*x)"
        
    elsif model_type = 9
        # === Brass Lip ===
        .lip_tension = 0.3 + excitation_strength * 0.5
        .lt$ = fixed$(.lip_tension, 3)
        .dr$ = fixed$(.decayRate * 0.3, 3)
        .sound = Create Sound from formula: "BrassLip", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (sin(2*pi*" + fixed$(.freq, 2) + "*x) + 0.7*sin(4*pi*" + fixed$(.freq, 2) + "*x) + 0.5*sin(6*pi*" + fixed$(.freq, 2) + "*x) + 0.3*sin(8*pi*" + fixed$(.freq, 2) + "*x)) * (1 + " + .lt$ + "*sin(150*x)) * exp(-" + .dr$ + "*x)"
        
    elsif model_type = 10
        # === Vocal Tract ===
        .formant1 = .freq * 2.5
        .formant2 = .freq * 4 + chaos * 200
        .temp1 = Create Sound from formula: "VocalTract", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * (sin(2*pi*" + fixed$(.freq, 2) + "*x) + 0.5*sin(4*pi*" + fixed$(.freq, 2) + "*x) + 0.3*sin(6*pi*" + fixed$(.freq, 2) + "*x))"
        Filter (pass Hann band): .formant1 - 100, .formant1 + 100, 100
        .temp2 = selected("Sound")
        Formula: "self * 1.5"
        Filter (pass Hann band): .formant2 - 150, .formant2 + 150, 100
        .sound = selected("Sound")
        removeObject: .temp1, .temp2
        selectObject: .sound
        Formula: "self * exp(-" + fixed$(.decayRate*0.2, 3) + "*x)"
        
    elsif model_type = 11
        # === Struck Bell ===
        .f1 = .freq
        .f2 = .freq * 2.14
        .f3 = .freq * 3.41
        .f4 = .freq * 4.09
        .f5 = .freq * 5.19
        .dr$ = fixed$(.decayRate * 0.7, 3)
        .sound = Create Sound from formula: "StruckBell", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * exp(-" + .dr$ + "*x) * (sin(2*pi*" + fixed$(.f1, 2) + "*x) + 0.6*sin(2*pi*" + fixed$(.f2, 2) + "*x)*exp(-x*2) + 0.4*sin(2*pi*" + fixed$(.f3, 2) + "*x)*exp(-x*3) + 0.2*sin(2*pi*" + fixed$(.f4, 2) + "*x)*exp(-x*5) + 0.1*sin(2*pi*" + fixed$(.f5, 2) + "*x)*exp(-x*8))"
        
    elsif model_type = 12
        # === Bowed Glass ===
        .bow_velocity = 0.2 + excitation_strength * 0.5
        .bv$ = fixed$(.bow_velocity, 3)
        .dr$ = fixed$(.decayRate * 0.3, 3)
        .sound = Create Sound from formula: "BowedGlass", 1, 0, .dur, sampling_frequency,
        ... "excitation_strength * sin(2*pi*" + fixed$(.freq, 2) + "*x) * (1 + " + .bv$ + "*sin(15*x + chaos*sin(3*x))) * exp(-" + .dr$ + "*x)"
        
    elsif model_type = 13
        # === Friction Drum ===
        .friction = excitation_strength
        .fr$ = fixed$(.friction, 3)
        .sound = Create Sound from formula: "FrictionDrum", 1, 0, .dur, sampling_frequency,
        ... .fr$ + " * sin(2*pi*" + fixed$(.freq, 2) + "*(1 + 0.2*sin(5*x))*x) * (1 + 0.5*randomGauss(0, chaos)) * exp(-" + fixed$(.decayRate*0.3, 3) + "*x)"
        
    elsif model_type = 14
        # === Breath Noise ===
        .turbulence = excitation_strength
        .temp = Create Sound from formula: "BreathNoise", 1, 0, .dur, sampling_frequency,
        ... ".turbulence * randomGauss(0, 1) * (1 + 0.3*sin(2*pi*" + fixed$(.freq, 2) + "*x)) * (1 + chaos*sin(x*10))"
        Filter (pass Hann band): .freq*0.5, .freq*2, .freq*0.3
        .sound = selected("Sound")
        removeObject: .temp
        
    elsif model_type = 15
        # === Modal Resonator ===
        .num_modes = 5
        .sound = Create Sound from formula: "ModalResonator", 1, 0, .dur, sampling_frequency, "0"
        for .i from 1 to .num_modes
            .mode_freq = .freq * (1 + (.i-1) * (1 + chaos * 0.5))
            .mode_decay = .decayRate + (.i-1) * 5
            .mode_amp = excitation_strength / .i
            .mf$ = fixed$(.mode_freq, 2)
            .md$ = fixed$(.mode_decay, 2)
            .ma$ = fixed$(.mode_amp, 4)
            selectObject: .sound
            Formula: "self + " + .ma$ + " * sin(2*pi*" + .mf$ + "*x) * exp(-" + .md$ + "*x)"
        endfor
    endif
    
    # Short fade in/out to avoid clicks
    selectObject: .sound
    .totalDur = Get total duration
    Formula: "self * if x < 0.005 then x/0.005 else 1 fi"
    Formula: "self * if x > .totalDur - 0.01 then (.totalDur - x)/0.01 else 1 fi"
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
        Text: 0.5, "centre", 0.6, "half", "Physical Modeling: " + model_type$ + " (Melody Demo)"
    else
        Text: 0.5, "centre", 0.6, "half", "Physical Modeling: " + model_type$
    endif
    Font size: 9
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.2, "half", "F=" + fixed$(frequency_Hz, 1) + " Hz | Damping=" + fixed$(damping, 3) + " | Excitation=" + fixed$(excitation_strength, 2)
    
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
    
    # === Spectrum (first 0.5s or full if shorter) ===
    Select outer viewport: 0, 7, 3.0, 4.8
    Select inner viewport: 0.6, 6.6, 3.1, 4.7
    
    selectObject: sound
    .specEnd = min(0.5, .totalDur)
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
    
    # Draw modal frequencies if applicable
    if model_type = 3 or model_type = 4 or model_type = 11
        Colour: "{1, 1, 0.5}"
        Dotted line
        
        if model_type = 3
            # Bar modes
            .modes# = {1, 2.756, 5.404, 8.933}
        elsif model_type = 4
            # Membrane modes
            .modes# = {1, 1.593, 2.135, 2.295, 2.917}
        elsif model_type = 11
            # Bell modes
            .modes# = {1, 2.14, 3.41, 4.09, 5.19}
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
    if model_type = 3 or model_type = 4 or model_type = 11
        Select outer viewport: 0, 7, 7.3, 7.6
        Font size: 8
        Colour: "{0.4, 0.4, 0.4}"
        if model_type = 3
            Text: 0.5, "centre", 0.5, "half", "Bar modes: 1 : 2.756 : 5.404 : 8.933 (yellow lines)"
        elsif model_type = 4
            Text: 0.5, "centre", 0.5, "half", "Membrane modes: 1 : 1.593 : 2.135 : 2.295 : 2.917 (yellow lines)"
        elsif model_type = 11
            Text: 0.5, "centre", 0.5, "half", "Bell modes: 1 : 2.14 : 3.41 : 4.09 : 5.19 (yellow lines)"
        endif
    endif
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc