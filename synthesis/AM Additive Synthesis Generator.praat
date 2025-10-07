# ============================================================
# Praat AudioTools - AM Additive Synthesis Generator.praat
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

form AM Additive Synthesis Generator
    choice texture_type: 1
        button Harmonic Series
        button Odd Harmonics
        button Even Harmonics
        button Inharmonic Cluster
        button Golden Bells
        button Octave Stack
        button Fifth Stack
        button Shepard Tone
        button Spectral Comb
        button Random Cloud
        button Detuned Unison
        button Harmonic Decay
        button Rising Partials
        button Filtered Spectrum
        button Chaotic Swarm
    positive duration 3.0
    positive fundamental 220
    positive num_partials 8
    real detune 0.1
    real chaos 0.3
    choice envelope: 1
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

if texture_type = 1
    sound = Create Sound from formula: "HarmonicSeries", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        amp = 1 / i
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(fundamental*i) + "*x)"
    endfor

elsif texture_type = 2
    sound = Create Sound from formula: "OddHarmonics", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        harmonic = 2*i - 1
        amp = 1 / harmonic
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(fundamental*harmonic) + "*x)"
    endfor

elsif texture_type = 3
    sound = Create Sound from formula: "EvenHarmonics", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        harmonic = 2*i
        amp = 1 / harmonic
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(fundamental*harmonic) + "*x)"
    endfor

elsif texture_type = 4
    sound = Create Sound from formula: "InharmonicCluster", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * (i + chaos * randomGauss(0, 0.5))
        amp = 1 / i
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 5
    sound = Create Sound from formula: "GoldenBells", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * (1.618 ^ (i-1))
        amp = 1 / (2 ^ (i-1))
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 6
    sound = Create Sound from formula: "OctaveStack", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * (2 ^ (i-1))
        amp = 1 / (2 ^ (i-1))
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 7
    sound = Create Sound from formula: "FifthStack", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * (1.5 ^ (i-1))
        amp = 1 / (1.5 ^ (i-1))
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 8
    sound = Create Sound from formula: "ShepardTone", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        base = fundamental * (2 ^ (i-1))
        octave_pos = (i-1) / num_partials
        amp = sin(pi * octave_pos)
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(base) + "*(1 + " + string$(chaos*0.1) + "*x)*x)"
    endfor

elsif texture_type = 9
    sound = Create Sound from formula: "SpectralComb", 1, 0, duration, sampling_frequency, "0"
    spacing = 2 + chaos * 3
    for i from 1 to num_partials
        freq = fundamental * (1 + spacing * (i-1))
        amp = 1 / (1 + i*0.2)
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 10
    sound = Create Sound from formula: "RandomCloud", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * randomUniform(0.5, 4)
        amp = randomUniform(0.3, 1) / num_partials
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 11
    sound = Create Sound from formula: "DetunedUnison", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        freq = fundamental * (1 + detune * (i - num_partials/2) / num_partials)
        amp = 1 / num_partials
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(freq) + "*x)"
    endfor

elsif texture_type = 12
    sound = Create Sound from formula: "HarmonicDecay", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        amp = 1 / i
        decay_rate = i * 0.5
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(fundamental*i) + "*x) * exp(-x*" + string$(decay_rate) + ")"
    endfor

elsif texture_type = 13
    sound = Create Sound from formula: "RisingPartials", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        base = fundamental * i
        amp = 1 / i
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(base) + "*(1 + " + string$(chaos*0.5) + "*x)*x)"
    endfor

elsif texture_type = 14
    sound = Create Sound from formula: "FilteredSpectrum", 1, 0, duration, sampling_frequency, "0"
    center = num_partials / 2
    for i from 1 to num_partials
        amp = (1 / i) * exp(-((i - center)^2) / (2 * (chaos * 5 + 1)^2))
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(fundamental*i) + "*x)"
    endfor

elsif texture_type = 15
    sound = Create Sound from formula: "ChaoticSwarm", 1, 0, duration, sampling_frequency, "0"
    for i from 1 to num_partials
        base = fundamental * i
        amp = 1 / (i + chaos * randomGauss(0, 2))
        selectObject: sound
        Formula: "self + " + string$(amp) + " * sin(2*pi*" + string$(base) + "*(1 + " + string$(chaos) + "*sin(" + string$(i*10) + "*x))*x)"
    endfor
endif

selectObject: sound

if envelope = 2
    Formula: "self * exp(-x*5)"

elsif envelope = 3
    Formula: "self * exp(-x*0.3)"

elsif envelope = 4
    gate_period = 0.1 + chaos * 0.3
    Formula: "self * if sin(2*pi*x/" + string$(gate_period) + ") > 0 then 1 else 0 fi"

elsif envelope = 5
    Formula: "self * (x/" + string$(duration) + ")"

elsif envelope = 6
    trem_rate = 5 + chaos * 15
    trem_depth = 0.3 + chaos * 0.5
    Formula: "self * (1 - " + string$(trem_depth) + " + " + string$(trem_depth) + "*sin(2*pi*" + string$(trem_rate) + "*x))"

elsif envelope = 7
    attack_time = 0.3 + chaos * 0.5
    Formula: "self * if x < " + string$(attack_time) + " then x/" + string$(attack_time) + " else 1 fi"

elsif envelope = 8
    attack = 0.01
    decay = 0.1 + chaos * 0.2
    sustain = 0.5 + chaos * 0.3
    release = 0.3
    decay_end = attack + decay
    release_start = duration - release
    Formula: "self * if x < " + string$(attack) + " then x/" + string$(attack) + " else if x < " + string$(decay_end) + " then 1-(1-" + string$(sustain) + ")*((x-" + string$(attack) + ")/" + string$(decay) + ") else if x < " + string$(release_start) + " then " + string$(sustain) + " else " + string$(sustain) + "*(1-(x-" + string$(release_start) + ")/" + string$(release) + ") fi fi fi"

elsif envelope = 9
    stutter_rate = 10 + chaos * 30
    Formula: "self * if floor(x*" + string$(stutter_rate) + ") mod 2 = 0 then 1 else 0 fi"

elsif envelope = 10
    burst_density = 5 + chaos * 20
    Formula: "self * if randomUniform(0,1) < " + string$(burst_density*0.05) + " then exp(-(x-floor(x*" + string$(burst_density) + ")/" + string$(burst_density) + ")*50) else 0 fi"
endif

selectObject: sound
Scale peak: 0.95
Play