form Subtractive Synthesis Generator
    choice Oscillator: 1
        button Sawtooth
        button Square
        button Pulse
        button Triangle
        button White Noise
        button Pink Noise
        button Dual Saw
        button Detuned Pulse
        button Noise + Saw
        button Super Saw
    choice Filter_type: 1
        button No Filter
        button Low Pass Smooth
        button Low Pass Resonant
        button High Pass
        button Band Pass Narrow
        button Band Pass Wide
        button Notch
        button Comb Filter
        button Formant Vowel
        button Sweep Filter
    positive Duration_(s) 3.0
    positive Frequency_(Hz) 220
    positive Filter_freq_(Hz) 1000
    real Resonance_(0-1) 0.5
    real Chaos_(0-1) 0.3
    choice Envelope: 1
        button No Envelope
        button Percussive
        button Slow Fade
        button Gate
        button Reverse
        button Tremolo
        button Swell
        button ADSR
        button Stutter
        button Random Bursts
endform

sampling_frequency = 44100

if oscillator = 1
    sound = Create Sound from formula: "Sawtooth", 1, 0, duration, sampling_frequency,
    ... "0.5 * (2*(frequency*x - floor(frequency*x + 0.5)))"
    
elsif oscillator = 2
    sound = Create Sound from formula: "Square", 1, 0, duration, sampling_frequency,
    ... "0.5 * if sin(2*pi*frequency*x) > 0 then 1 else -1 fi"
    
elsif oscillator = 3
    pulse_width = 0.3 + chaos * 0.4
    sound = Create Sound from formula: "Pulse", 1, 0, duration, sampling_frequency,
    ... "0.5 * if (frequency*x - floor(frequency*x)) < pulse_width then 1 else -1 fi"
    
elsif oscillator = 4
    sound = Create Sound from formula: "Triangle", 1, 0, duration, sampling_frequency,
    ... "0.5 * (2/pi) * arcsin(sin(2*pi*frequency*x))"
    
elsif oscillator = 5
    sound = Create Sound from formula: "WhiteNoise", 1, 0, duration, sampling_frequency,
    ... "0.5 * randomGauss(0, 1)"
    
elsif oscillator = 6
    sound = Create Sound from formula: "PinkNoise", 1, 0, duration, sampling_frequency,
    ... "0.5 * randomGauss(0, 1)"
    Filter (de-emphasis): 50
    
elsif oscillator = 7
    detune = 5 + chaos * 10
    sound = Create Sound from formula: "DualSaw", 1, 0, duration, sampling_frequency,
    ... "0.3 * (2*(frequency*x - floor(frequency*x + 0.5)) + 2*((frequency+detune)*x - floor((frequency+detune)*x + 0.5)))"
    
elsif oscillator = 8
    detune = 3 + chaos * 8
    pulse_width = 0.3 + chaos * 0.3
    sound = Create Sound from formula: "DetunedPulse", 1, 0, duration, sampling_frequency,
    ... "0.3 * (if (frequency*x - floor(frequency*x)) < pulse_width then 1 else -1 fi + if ((frequency+detune)*x - floor((frequency+detune)*x)) < pulse_width then 1 else -1 fi)"
    
elsif oscillator = 9
    sound = Create Sound from formula: "NoiseSaw", 1, 0, duration, sampling_frequency,
    ... "0.3 * (2*(frequency*x - floor(frequency*x + 0.5)) + randomGauss(0, 0.3))"
    
elsif oscillator = 10
    sound = Create Sound from formula: "SuperSaw", 1, 0, duration, sampling_frequency,
    ... "0.2 * (2*(frequency*x - floor(frequency*x + 0.5)) + 2*((frequency*1.01)*x - floor((frequency*1.01)*x + 0.5)) + 2*((frequency*0.99)*x - floor((frequency*0.99)*x + 0.5)) + 2*((frequency*1.02)*x - floor((frequency*1.02)*x + 0.5)) + 2*((frequency*0.98)*x - floor((frequency*0.98)*x + 0.5)))"
endif

selectObject: sound

if filter_type = 2
    Filter (pass Hann band): 0, filter_freq, 100
    
elsif filter_type = 3
    q_factor = 10 + resonance * 90
    Filter (pass Hann band): 0, filter_freq, filter_freq/q_factor
    
elsif filter_type = 4
    Filter (stop Hann band): 0, filter_freq, 100
    
elsif filter_type = 5
    bandwidth = 50 + chaos * 50
    Filter (pass Hann band): filter_freq - bandwidth/2, filter_freq + bandwidth/2, bandwidth/2
    
elsif filter_type = 6
    bandwidth = 200 + chaos * 400
    Filter (pass Hann band): filter_freq - bandwidth/2, filter_freq + bandwidth/2, bandwidth
    
elsif filter_type = 7
    bandwidth = 50 + resonance * 100
    Filter (stop Hann band): filter_freq - bandwidth/2, filter_freq + bandwidth/2, bandwidth
    
elsif filter_type = 8
    comb_delay = 1 / (filter_freq + chaos * 100)
    feedback = 0.5 + resonance * 0.45
    Formula: "self + feedback * self[x - comb_delay]"
    
elsif filter_type = 9
    formant1 = 800
    formant2 = 1200 + chaos * 600
    formant3 = 2600
    Filter (pass Hann band): formant1 - 100, formant1 + 100, 150
    Formula: "self * 1.5"
    Filter (pass Hann band): formant2 - 100, formant2 + 100, 150
    Formula: "self * 1.5"
    Filter (pass Hann band): formant3 - 150, formant3 + 150, 200
    
elsif filter_type = 10
    start_freq = filter_freq * 0.5
    end_freq = filter_freq * 2
    Formula: "self * (0.3 + 0.7*sin(2*pi*(start_freq + (end_freq-start_freq)*x/duration)*0.001))"
endif

selectObject: sound

if envelope = 2
    Formula: "self * exp(-x*5)"
    
elsif envelope = 3
    Formula: "self * exp(-x*0.3)"
    
elsif envelope = 4
    gate_period = 0.1 + chaos * 0.3
    Formula: "self * if sin(2*pi*x/gate_period) > 0 then 1 else 0 fi"
    
elsif envelope = 5
    Formula: "self * (x/duration)"
    
elsif envelope = 6
    trem_rate = 5 + chaos * 15
    trem_depth = 0.3 + chaos * 0.5
    Formula: "self * (1 - trem_depth + trem_depth*sin(2*pi*trem_rate*x))"
    
elsif envelope = 7
    attack_time = 0.3 + chaos * 0.5
    Formula: "self * if x < attack_time then x/attack_time else 1 fi"
    
elsif envelope = 8
    attack = 0.01
    decay = 0.1 + chaos * 0.2
    sustain = 0.5 + chaos * 0.3
    release = 0.3
    decay_end = attack + decay
    release_start = duration - release
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
Play