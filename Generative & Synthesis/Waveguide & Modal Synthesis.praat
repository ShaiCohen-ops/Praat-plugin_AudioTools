# ============================================================
# Praat AudioTools - Waveguide & Modal Synthesis.praat
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

form Physical Modeling Synthesis Generator
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
    positive Duration_(s) 3.0
    positive Frequency_(Hz) 220
    real Excitation_strength_(0-1) 0.7
    real Damping_(0.9-0.999) 0.995
    real Chaos_(0-1) 0.3
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
endform

sampling_frequency = 44100
delay_samples = round(sampling_frequency / frequency)

if model_type = 1
    bow_pressure = 0.3 + excitation_strength * 0.5
    sound = Create Sound from formula: "BowedString", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0, 0.3) else self - damping*self[col - delay_samples] * (1 + bow_pressure*sin(x*20)) fi"
    
elsif model_type = 2
    breath_pressure = excitation_strength
    sound = Create Sound from formula: "BlownPipe", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0, breath_pressure) * sin(x*100) else self - damping*self[col - delay_samples] + 0.1*randomGauss(0, breath_pressure) fi"
    Filter (pass Hann band): frequency*0.8, frequency*1.2, 50
    
elsif model_type = 3
    sound = Create Sound from formula: "StruckBar", 1, 0, duration, sampling_frequency,
    ... "if col <= 50 then excitation_strength * randomGauss(0, 1) else self - damping*(self[col - delay_samples] + 0.7*self[col - round(delay_samples*2.756)]) fi"
    
elsif model_type = 4
    sound = Create Sound from formula: "PluckedMembrane", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then excitation_strength * randomGauss(0, 1) else self - damping*(self[col - delay_samples] + 0.5*self[col - round(delay_samples*1.593)] + 0.3*self[col - round(delay_samples*2.135)]) fi"
    
elsif model_type = 5
    bottle_resonance = delay_samples * 0.8
    sound = Create Sound from formula: "BlownBottle", 1, 0, duration, sampling_frequency,
    ... "if col <= bottle_resonance then randomGauss(0, excitation_strength) * abs(sin(x*50)) else self - damping*self[col - round(bottle_resonance)] + 0.05*randomGauss(0, excitation_strength) fi"
    Filter (pass Hann band): frequency*0.5, frequency*1.5, 100
    
elsif model_type = 6
    sound = Create Sound from formula: "ScrapedSurface", 1, 0, duration, sampling_frequency,
    ... "if randomUniform(0,1) < excitation_strength*0.3 then randomGauss(0, 0.8) * sin(x*frequency*2*pi) else self - 0.7*self[col - round(delay_samples*0.5)] fi"
    
elsif model_type = 7
    hammer_stiffness = 1 - excitation_strength * 0.5
    sound = Create Sound from formula: "HammeredString", 1, 0, duration, sampling_frequency,
    ... "if col <= 30 then excitation_strength * randomGauss(0, 1) * exp(-col/10) else self - damping*self[col - delay_samples] - hammer_stiffness*0.1*(self[col-delay_samples] - self[col-delay_samples-1]) fi"
    
elsif model_type = 8
    reed_stiffness = 0.5 + chaos * 0.3
    sound = Create Sound from formula: "ReedPipe", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0, excitation_strength) * (1 - reed_stiffness*abs(sin(x*200))) else self - damping*self[col - delay_samples] * (1 + 0.2*sin(x*frequency*2*pi)) fi"
    
elsif model_type = 9
    lip_tension = 0.3 + excitation_strength * 0.5
    sound = Create Sound from formula: "BrassLip", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0, excitation_strength) else self - damping*self[col - delay_samples] * if abs(self) < lip_tension then 1 else 0.5 fi + 0.05*randomGauss(0, excitation_strength) fi"
    
elsif model_type = 10
    sound = Create Sound from formula: "VocalTract", 1, 0, duration, sampling_frequency,
    ... "if col <= 100 then randomGauss(0, excitation_strength) * abs(sin(x*frequency*2*pi)) else self - damping*self[col - delay_samples] fi"
    formant1 = frequency * 2.5
    formant2 = frequency * 4 + chaos * 200
    Filter (pass Hann band): formant1 - 100, formant1 + 100, 100
    Formula: "self * 1.5"
    Filter (pass Hann band): formant2 - 100, formant2 + 100, 100
    
elsif model_type = 11
    sound = Create Sound from formula: "StruckBell", 1, 0, duration, sampling_frequency,
    ... "if col <= 40 then excitation_strength * randomGauss(0, 1) else self - damping*(self[col - delay_samples] + 0.6*self[col - round(delay_samples*2.14)] + 0.4*self[col - round(delay_samples*3.41)] + 0.2*self[col - round(delay_samples*4.09)]) fi"
    
elsif model_type = 12
    bow_velocity = 0.2 + excitation_strength * 0.5
    sound = Create Sound from formula: "BowedGlass", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples*2 then randomGauss(0, 0.2) else self - (damping+0.003)*self[col - round(delay_samples*1.5)] * (1 + bow_velocity*sin(x*15+chaos*sin(x*3))) fi"
    
elsif model_type = 13
    friction = excitation_strength
    sound = Create Sound from formula: "FrictionDrum", 1, 0, duration, sampling_frequency,
    ... "if col mod round(100 - friction*80) = 0 then friction * randomGauss(0, 1) else self - damping*self[col - delay_samples] * (1 + 0.3*randomGauss(0, chaos)) fi"
    
elsif model_type = 14
    turbulence = excitation_strength
    sound = Create Sound from formula: "BreathNoise", 1, 0, duration, sampling_frequency,
    ... "turbulence * randomGauss(0, 1) * (1 + sin(2*pi*frequency*x)) * (1 + chaos*sin(x*10))"
    Filter (pass Hann band): frequency*0.5, frequency*2, frequency*0.3
    
elsif model_type = 15
    num_modes = 5
    sound = Create Sound from formula: "ModalResonator", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_modes
        mode_freq = frequency * (1 + (i-1) * (1 + chaos * 0.5))
        mode_decay = damping - (i-1) * 0.01
        mode_amp = excitation_strength / i
        selectObject: sound
        Formula: "self + mode_amp * sin(2*pi*mode_freq*x) * exp(-x*(1-mode_decay)*50)"
    endfor
    excitation = Create Sound from formula: "Excite", 1, 0, duration, sampling_frequency,
    ... "if x < 0.01 then excitation_strength * randomGauss(0, 1) else 0 fi"
    selectObject: sound
    plusObject: excitation
    Formula: "self + object[excitation]"
    selectObject: excitation
    Remove
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