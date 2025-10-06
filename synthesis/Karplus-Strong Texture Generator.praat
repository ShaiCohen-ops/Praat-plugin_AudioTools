# ============================================================
# Praat AudioTools - Karplus-Strong Texture Generator.praat
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

form Karplus-Strong Texture Generator
    choice Texture_type: 1
        button Plucked String
        button Guitar Strum
        button Harp Glissando
        button Metallic Pluck
        button Prepared Piano
        button Sitar Drone
        button Koto Cascade
        button Banjo Roll
        button Dulcimer Shimmer
        button Steel Drum
        button Granular Pluck
        button Reversed Decay
        button Bitcrushed String
        button Frozen Resonance
        button Chaos Feedback
    positive Duration_(s) 3.0
    positive Pitch_center_(Hz) 220
    real Damping_(0.9-0.999) 0.995
    real Chaos_(0-1) 0.3
    choice Process: 1
        button Clean
        button Spectral Mirror
        button Harmonic Enhancer
        button Spectral Knots
        button Frequency Fold
        button Ring Shift
        button Spectral Blur
endform

sampling_frequency = 44100
delay_samples = round(sampling_frequency / pitch_center)

if texture_type = 1
    sound = Create Sound from formula: "Pluck", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) else self - damping*self[col - delay_samples] fi"
    
elsif texture_type = 2
    sound = Create Sound from formula: "Strum", 1, 0, duration, sampling_frequency,
    ... "if col <= 100 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*(1+0.01*(col mod 3)))] fi"
    
elsif texture_type = 3
    sound = Create Sound from formula: "Glissando", 1, 0, duration, sampling_frequency,
    ... "if col <= 50 then randomGauss(0,1) else self - damping*self[col - round(delay_samples/(1+x*chaos*0.5))] fi"
    
elsif texture_type = 4
    sound = Create Sound from formula: "Metallic", 1, 0, duration, sampling_frequency,
    ... "if col <= 20 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*0.99)] fi"
    
elsif texture_type = 5
    sound = Create Sound from formula: "PreparedPiano", 1, 0, duration, sampling_frequency,
    ... "if col <= 80 then randomGauss(0,1) * sin(col*0.5) else self - damping*self[col - delay_samples] fi"
    
elsif texture_type = 6
    sound = Create Sound from formula: "Sitar", 1, 0, duration, sampling_frequency,
    ... "if col <= 200 then randomGauss(0,0.8) else self - damping*self[col - delay_samples] + 0.2*self[col - round(delay_samples/2)] fi"
    
elsif texture_type = 7
    sound = Create Sound from formula: "Koto", 1, 0, duration, sampling_frequency,
    ... "if col <= 30 then randomGauss(0,1) * exp(-col/10) else self - damping*self[col - round(delay_samples*(2^(floor(x*3)/12)))] fi"
    
elsif texture_type = 8
    sound = Create Sound from formula: "Banjo", 1, 0, duration, sampling_frequency,
    ... "if col <= 15 then randomGauss(0,1) else self - 0.5*self[col - delay_samples] fi"
    
elsif texture_type = 9
    sound = Create Sound from formula: "Dulcimer", 1, 0, duration, sampling_frequency,
    ... "if col <= 60 then randomGauss(0,1) else self - damping*self[col - round(delay_samples*(1+0.3*sin(x*20)))] fi"
    
elsif texture_type = 10
    sound = Create Sound from formula: "SteelDrum", 1, 0, duration, sampling_frequency,
    ... "if col <= 40 then randomGauss(0,1)*sin(col*0.3) else self - damping*(self[col - delay_samples] + 0.3*self[col - round(delay_samples/2.76)]) fi"
    
elsif texture_type = 11
    sound = Create Sound from formula: "GranularPluck", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) * abs(sin(col*chaos*0.1)) else self - damping*self[col - delay_samples] fi"
    
elsif texture_type = 12
    sound = Create Sound from formula: "ReversedDecay", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) else self - (damping + x*chaos*0.01)*self[col - delay_samples] fi"
    
elsif texture_type = 13
    sound = Create Sound from formula: "Bitcrushed", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then floor(randomGauss(0,1)*8)/8 else floor(self*16)/16 - damping*self[col - delay_samples] fi"
    
elsif texture_type = 14
    sound = Create Sound from formula: "FrozenResonance", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) else self - damping*self[col - delay_samples] * (1+chaos*sin(x*100)) fi"
    
elsif texture_type = 15
    sound = Create Sound from formula: "ChaosFeedback", 1, 0, duration, sampling_frequency,
    ... "if col <= delay_samples then randomGauss(0,1) else self - damping*self[col - round(delay_samples*(1+chaos*randomGauss(0,0.1)))] fi"
endif

selectObject: sound

if process = 2
    sampling_rate = Get sampling frequency
    To Spectrum: "yes"
    nyquist = sampling_rate / 2
    Formula: "if col < nyquist/2 then self + self[nyquist-col] else self fi"
    To Sound
    sound = selected("Sound")
    
elsif process = 3
    To Spectrum: "yes"
    Formula: "self + 0.3 * self[col*2] + 0.1 * self[col*3]"
    To Sound
    sound = selected("Sound")
    
elsif process = 4
    sampling_rate = Get sampling frequency
    To Spectrum: "yes"
    Formula: "if col < 100 then self else self[abs(col - 2*round(col/1000)*1000)] * (sin(col/300) + cos(col/150))^2 fi"
    To Sound
    sound = selected("Sound")
    
elsif process = 5
    To Spectrum: "yes"
    Formula: "self[abs((col * (1 + chaos)) mod 1000)]"
    To Sound
    sound = selected("Sound")
    
elsif process = 6
    To Spectrum: "yes"
    Formula: "self * cos(2*pi*pitch_center*chaos*0.1*col)"
    To Sound
    sound = selected("Sound")
    
elsif process = 7
    To Spectrum: "yes"
    blur_amount = round(10 + chaos * 40)
    Formula: "self + 0.5*(self[col-blur_amount] + self[col+blur_amount])"
    To Sound
    sound = selected("Sound")
endif

selectObject: sound
Scale peak: 0.95
Play