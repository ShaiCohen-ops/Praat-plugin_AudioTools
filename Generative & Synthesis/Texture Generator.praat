# ============================================================
# Praat AudioTools - Texture Generator.praat
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

form Texture Generator
    optionmenu Texture_type: 1
        option Granular Cloud
        option Filtered Noise
        option Harmonic Swarm
        option Chaotic Pulse
        option Resonant Bells
        option Metallic Shimmer
        option Ocean Waves
        option Wind Texture
        option Glitch Storm
        option Crystal Rain
        option Dark Drone
        option Alien Choir
        option Broken Radio
        option Time Stretch
        option Bubble Pop
        option Digital Decay
        option Frost Crackle
        option Space Whisper
        option Magnetic Field
        option Circuit Bend
    positive Duration_(s) 5.0
    positive Density_(1-100) 30
    positive Pitch_center_(Hz) 440
    positive Pitch_range_(Hz) 200
    real Chaos_(0-1) 0.5
    comment --- Fade options ---
    positive Fade_out_s 0.5
    choice Fade_curve: 1
        button Linear
        button Exponential (-60 dB)
endform

sampling_frequency = 44100

if texture_type = 1
    sound = Create Sound from formula: "Granular", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*(pitch_center + pitch_range*sin(chaos*100*x))*x) * exp(-10*abs(sin(density*pi*x)))"

elsif texture_type = 2
    sound = Create Sound from formula: "FilteredNoise", 1, 0, duration, sampling_frequency,
    ... "randomGauss(0,0.5) * sin(2*pi*pitch_center*x*0.01) * (1+chaos*sin(20*x))"
    Filter (pass Hann band): pitch_center - pitch_range, pitch_center + pitch_range, 100

elsif texture_type = 3
    sound = Create Sound from formula: "HarmonicSwarm", 1, 0, duration, sampling_frequency,
    ... "0.2 * (sin(2*pi*pitch_center*x) + 0.5*sin(4*pi*pitch_center*x + chaos*x) + 0.3*sin(6*pi*pitch_center*x - chaos*2*x))"
    Formula: "self * (1 + 0.3*sin(density*x))"

elsif texture_type = 4
    sound = Create Sound from formula: "ChaoticPulse", 1, 0, duration, sampling_frequency,
    ... "0.4 * if (sin(2*pi*pitch_center*x) > (1-chaos)) then randomGauss(0,1) else 0 fi * exp(-density*abs(sin(10*pi*x)))"

elsif texture_type = 5
    sound = Create Sound from formula: "ResonantBells", 1, 0, duration, sampling_frequency,
    ... "0.3 * (sin(2*pi*pitch_center*x) + 0.7*sin(2*pi*pitch_center*1.618*x)) * exp(-chaos*5*x) * (1+sin(density*x))"

elsif texture_type = 6
    sound = Create Sound from formula: "MetallicShimmer", 1, 0, duration, sampling_frequency,
    ... "0.2 * sin(2*pi*pitch_center*x*(1+chaos*randomGauss(0,0.1))) * abs(sin(density*pi*x))"
    Filter (pass Hann band): 2000, 8000, 1000

elsif texture_type = 7
    sound = Create Sound from formula: "OceanWaves", 1, 0, duration, sampling_frequency,
    ... "randomGauss(0,0.3) * (1+sin(0.5*x)) * (1+chaos*sin(density*0.1*x))"
    Filter (stop Hann band): 100, 300, 50
    Formula: "self * (1 + 0.5*sin(0.3*x))"

elsif texture_type = 8
    sound = Create Sound from formula: "WindTexture", 1, 0, duration, sampling_frequency,
    ... "randomGauss(0,0.4) * (1+chaos*sin(density*0.5*x)) * (0.5+0.5*sin(0.2*x))"
    Filter (pass Hann band): 500, 3000, 500

elsif texture_type = 9
    sound = Create Sound from formula: "GlitchStorm", 1, 0, duration, sampling_frequency,
    ... "0.4 * if abs(sin(density*pi*x)) > (1-chaos) then sin(2*pi*pitch_center*x*floor(x*100)) else 0 fi"

elsif texture_type = 10
    sound = Create Sound from formula: "CrystalRain", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*pitch_center*(1+floor(chaos*10*x))*x) * exp(-density*abs(sin(50*pi*x)))"
    Filter (pass Hann band): 1000, 6000, 800

elsif texture_type = 11
    sound = Create Sound from formula: "DarkDrone", 1, 0, duration, sampling_frequency,
    ... "0.4 * (sin(2*pi*pitch_center*x) + 0.3*sin(2*pi*pitch_center*0.99*x) + 0.2*sin(2*pi*pitch_center*1.01*x)) * (1+chaos*sin(0.1*x))"
    Filter (pass Hann band): 50, 400, 100

elsif texture_type = 12
    sound = Create Sound from formula: "AlienChoir", 1, 0, duration, sampling_frequency,
    ... "0.25 * (sin(2*pi*pitch_center*x) + sin(2*pi*pitch_center*1.5*x + chaos*sin(density*x)) + sin(2*pi*pitch_center*2.01*x))"
    Formula: "self * (0.7 + 0.3*sin(5*x))"

elsif texture_type = 13
    sound = Create Sound from formula: "BrokenRadio", 1, 0, duration, sampling_frequency,
    ... "randomGauss(0,0.3) * if sin(density*x) > 0 then 1+chaos*sin(pitch_center*x) else 0.1 fi"
    Filter (pass Hann band): 800, 2500, 400

elsif texture_type = 14
    sound = Create Sound from formula: "TimeStretch", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*pitch_center*x*x/(1+chaos)) * exp(-0.5*abs(sin(density*x)))"

elsif texture_type = 15
    sound = Create Sound from formula: "BubblePop", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*pitch_center*(1+pitch_range/pitch_center*exp(-density*x))*x) * if randomGauss(0,1) > (1-chaos) then exp(-20*x) else 0 fi"

elsif texture_type = 16
    sound = Create Sound from formula: "DigitalDecay", 1, 0, duration, sampling_frequency,
    ... "0.3 * sin(2*pi*pitch_center*x) * floor((1-x/duration)*density) / density * (1+chaos*randomGauss(0,0.2))"

elsif texture_type = 17
    sound = Create Sound from formula: "FrostCrackle", 1, 0, duration, sampling_frequency,
    ... "0.35 * randomGauss(0,1) * if abs(sin(density*10*pi*x)) > (1-chaos*0.5) then exp(-100*abs(sin(density*10*pi*x))) else 0 fi"
    Filter (pass Hann band): 3000, 10000, 1500

elsif texture_type = 18
    sound = Create Sound from formula: "SpaceWhisper", 1, 0, duration, sampling_frequency,
    ... "0.3 * randomGauss(0,1) * (1+sin(2*pi*pitch_center*0.01*x)) * (chaos + (1-chaos)*sin(density*0.1*x))"
    Filter (pass Hann band): 200, 1200, 300

elsif texture_type = 19
    sound = Create Sound from formula: "MagneticField", 1, 0, duration, sampling_frequency,
    ... "0.35 * sin(2*pi*pitch_center*x + chaos*10*sin(density*x)) * (1+0.5*sin(0.5*x))"
    Filter (pass Hann band): 100, 800, 200

elsif texture_type = 20
    sound = Create Sound from formula: "CircuitBend", 1, 0, duration, sampling_frequency,
    ... "0.4 * sin(2*pi*pitch_center*x) * if floor(density*x) mod 2 = 0 then 1+chaos*randomGauss(0,0.5) else -1 fi * exp(-abs(sin(x)))"
endif

# --- Apply fade-out over the last Fade_out_s seconds ---
selectObject: sound
if fade_out_s > 0
    if fade_curve = 1
        Formula: "self * (if x < xmax - min('fade_out_s', xmax - xmin) then 1 else max(0, (xmax - x) / min('fade_out_s', xmax - xmin)) fi)"
    elsif fade_curve = 2
        Formula: "self * (if x < xmax - min('fade_out_s', xmax - xmin) then 1 else exp(-6.90775527898 * (x - (xmax - min('fade_out_s', xmax - xmin))) / min('fade_out_s', xmax - xmin)) fi)"
    endif
endif

Scale peak: 0.95
Play

