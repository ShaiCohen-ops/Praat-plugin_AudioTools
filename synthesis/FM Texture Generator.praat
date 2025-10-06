# ============================================================
# Praat AudioTools - FM Texture Generator.praat
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

form FM Texture Generator
    choice Texture_type: 1
        button Classic FM Bell
        button Brass Stack
        button Electric Piano
        button Organ Cluster
        button Glass Harmonica
        button Metallic Sweep
        button Vocal Formant
        button Alien Choir
        button Wobble Bass
        button Digital Noise
        button Sidebanded Drone
        button Harmonic Bells
        button Chaotic FM
        button Inharmonic Stack
        button Feedback Scream
    positive Duration_(s) 3.0
    positive Carrier_freq_(Hz) 440
    positive Modulator_ratio 2.0
    positive Modulation_index_(0-20) 5.0
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
mod_freq = carrier_freq * modulator_ratio

if texture_type = 1
    sound = Create Sound from formula: "FMBell", 1, 0, duration, sampling_frequency,
    ... "0.5 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x)) * exp(-x*2)"
    
elsif texture_type = 2
    sound = Create Sound from formula: "Brass", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*(1+x*0.5)*sin(2*pi*mod_freq*x)) * (1-exp(-x*10))*exp(-x*0.5)"
    
elsif texture_type = 3
    sound = Create Sound from formula: "EPiano", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*exp(-x*3)*sin(2*pi*mod_freq*x)) * exp(-x*1.5)"
    
elsif texture_type = 4
    sound = Create Sound from formula: "Organ", 1, 0, duration, sampling_frequency,
    ... "0.3 * (sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x)) + 0.5*sin(2*pi*carrier_freq*2*x) + 0.3*sin(2*pi*carrier_freq*3*x))"
    
elsif texture_type = 5
    sound = Create Sound from formula: "GlassHarmonica", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x + modulation_index*0.5*sin(2*pi*mod_freq*2*x))) * exp(-x*1)"
    
elsif texture_type = 6
    sound = Create Sound from formula: "MetallicSweep", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + (modulation_index+x*chaos*10)*sin(2*pi*mod_freq*(1+x*chaos)*x)) * exp(-x*0.5)"
    
elsif texture_type = 7
    sound = Create Sound from formula: "VocalFormant", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x) + 2*sin(2*pi*carrier_freq*3*x))"
    
elsif texture_type = 8
    sound = Create Sound from formula: "AlienChoir", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x + chaos*sin(2*pi*0.5*x))) * (1+0.3*sin(2*pi*3*x))"
    
elsif texture_type = 9
    sound = Create Sound from formula: "WobbleBass", 1, 0, duration, sampling_frequency,
    ... "0.5 * sin(2*pi*carrier_freq*x + modulation_index*(1+chaos*sin(2*pi*5*x))*sin(2*pi*mod_freq*x))"
    
elsif texture_type = 10
    sound = Create Sound from formula: "DigitalNoise", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*20*sin(2*pi*mod_freq*x)) * (1+chaos*randomGauss(0,0.3))"
    
elsif texture_type = 11
    sound = Create Sound from formula: "SidebandedDrone", 1, 0, duration, sampling_frequency,
    ... "0.3 * (sin(2*pi*(carrier_freq+mod_freq*modulation_index)*x) + sin(2*pi*(carrier_freq-mod_freq*modulation_index)*x))"
    
elsif texture_type = 12
    sound = Create Sound from formula: "HarmonicBells", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*1.414*x)) * exp(-x*2) + 0.2*sin(2*pi*carrier_freq*2.76*x)*exp(-x*3)"
    
elsif texture_type = 13
    sound = Create Sound from formula: "ChaoticFM", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*(1+chaos*randomGauss(0,0.2))*x))"
    
elsif texture_type = 14
    sound = Create Sound from formula: "InharmonicStack", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*1.618*x)) * exp(-x*1.5)"
    
elsif texture_type = 15
    sound = Create Sound from formula: "FeedbackScream", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*carrier_freq*x + modulation_index*sin(2*pi*mod_freq*x + modulation_index*sin(2*pi*mod_freq*x))) * (1+0.5*sin(2*pi*1*x))"
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