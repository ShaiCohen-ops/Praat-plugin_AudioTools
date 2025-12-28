# ============================================================
# Praat AudioTools - Harmonic Resonance Boost.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
#
# Description:
#   Boosts frequencies at harmonic intervals of a fundamental
#   while attenuating non-harmonic content. Creates resonant,
#   tuned comb-filter effects. Different L/R bandwidths create
#   stereo width.
#
# Usage:
#   Select a Sound object in Praat and run this script.
# ============================================================

form Harmonic Resonance Boost
    optionmenu Preset: 1
        option Custom
        option Sub Drone (50 Hz - deep rumble)
        option Industrial Hum (60 Hz - aggressive)
        option Laser Comb (200 Hz - razor sharp)
        option Alien Voice (333 Hz - otherworldly)
        option Metallic Ring (666 Hz - harsh)
        option Glass Bells (1200 Hz - delicate)
        option Celestial Pad (528 Hz - ethereal)
        option Swarm (77 Hz - buzzing)
    comment === Harmonic Parameters ===
    positive fundamental_frequency 440
    comment (base frequency for harmonic series)
    positive harmonic_bandwidth 50
    comment (width around each harmonic in Hz)
    positive harmonic_boost 1.5
    comment (gain multiplier for harmonics)
    comment === Non-Harmonic Attenuation ===
    positive mid_freq_cutoff 6000
    positive low_mid_attenuation 0.6
    positive high_freq_attenuation 0.4
    comment === Stereo ===
    boolean create_stereo 1
    positive stereo_bandwidth_offset 15
    comment (Hz difference between L/R for width)
    comment === Output ===
    positive scale_peak 0.90
    boolean play_after_processing 1
endform

# Apply presets
if preset = 2
    # Sub Drone - deep rumbling bass harmonics
    fundamental_frequency = 50
    harmonic_bandwidth = 20
    harmonic_boost = 4.0
    mid_freq_cutoff = 3000
    low_mid_attenuation = 0.15
    high_freq_attenuation = 0.05
    stereo_bandwidth_offset = 8
    preset_name$ = "SubDrone"
elsif preset = 3
    # Industrial Hum - 60Hz power line frequency
    fundamental_frequency = 60
    harmonic_bandwidth = 15
    harmonic_boost = 5.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.1
    high_freq_attenuation = 0.02
    stereo_bandwidth_offset = 5
    preset_name$ = "Industrial"
elsif preset = 4
    # Laser Comb - super narrow, robotic
    fundamental_frequency = 200
    harmonic_bandwidth = 8
    harmonic_boost = 6.0
    mid_freq_cutoff = 8000
    low_mid_attenuation = 0.05
    high_freq_attenuation = 0.02
    stereo_bandwidth_offset = 3
    preset_name$ = "Laser"
elsif preset = 5
    # Alien Voice - eerie, hollow
    fundamental_frequency = 333
    harmonic_bandwidth = 40
    harmonic_boost = 3.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.08
    high_freq_attenuation = 0.03
    stereo_bandwidth_offset = 20
    preset_name$ = "Alien"
elsif preset = 6
    # Metallic Ring - harsh, clangy
    fundamental_frequency = 666
    harmonic_bandwidth = 25
    harmonic_boost = 5.5
    mid_freq_cutoff = 6000
    low_mid_attenuation = 0.06
    high_freq_attenuation = 0.04
    stereo_bandwidth_offset = 12
    preset_name$ = "Metallic"
elsif preset = 7
    # Glass Bells - high, delicate, shimmery
    fundamental_frequency = 1200
    harmonic_bandwidth = 35
    harmonic_boost = 3.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.2
    high_freq_attenuation = 0.15
    stereo_bandwidth_offset = 25
    preset_name$ = "Glass"
elsif preset = 8
    # Celestial Pad - 528Hz "miracle frequency", wide and dreamy
    fundamental_frequency = 528
    harmonic_bandwidth = 80
    harmonic_boost = 2.0
    mid_freq_cutoff = 7000
    low_mid_attenuation = 0.25
    high_freq_attenuation = 0.15
    stereo_bandwidth_offset = 40
    preset_name$ = "Celestial"
elsif preset = 9
    # Swarm - low buzzing insect-like
    fundamental_frequency = 77
    harmonic_bandwidth = 12
    harmonic_boost = 4.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.12
    high_freq_attenuation = 0.06
    stereo_bandwidth_offset = 6
    preset_name$ = "Swarm"
else
    preset_name$ = "Custom"
endif

# Input validation
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original_sound = selected("Sound")
original_name$ = selected$("Sound")
selectObject: original_sound
n_channels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency

writeInfoLine: "=== Harmonic Resonance Boost ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Fundamental: ", fundamental_frequency, " Hz"
appendInfoLine: "Bandwidth: ", harmonic_bandwidth, " Hz"
appendInfoLine: "Boost: ", harmonic_boost, "x"
appendInfoLine: "Attenuation (low/high): ", low_mid_attenuation, " / ", high_freq_attenuation
if create_stereo
    appendInfoLine: "Stereo offset: ", stereo_bandwidth_offset, " Hz"
endif
appendInfoLine: ""

# Convert to mono
selectObject: original_sound
if n_channels > 1
    sound = Convert to mono
else
    sound = Copy: "mono_temp"
endif

# Build formula strings
fundStr$ = fixed$(fundamental_frequency, 2)
boostStr$ = fixed$(harmonic_boost, 4)
lowAttStr$ = fixed$(low_mid_attenuation, 4)
highAttStr$ = fixed$(high_freq_attenuation, 4)
midCutStr$ = fixed$(mid_freq_cutoff, 2)

# ===== PROCESS LEFT CHANNEL =====
appendInfoLine: "Processing left channel..."

bwL$ = fixed$(harmonic_bandwidth, 2)

selectObject: sound
spectrum_L = To Spectrum: "yes"

selectObject: spectrum_L
matrix_L = To Matrix
Rename: "matL"

# Harmonic detection formula:
# Distance to nearest harmonic = abs(x - round(x/f)*f)
# If distance < bandwidth: boost, else: attenuate

selectObject: matrix_L
Formula: "if abs(x - round(x / " + fundStr$ + ") * " + fundStr$ + ") < " + bwL$ + " then self * " + boostStr$ + " else if x < " + midCutStr$ + " then self * " + lowAttStr$ + " else self * " + highAttStr$ + " fi fi"

selectObject: matrix_L
spectrum_L_mod = To Spectrum
Rename: "specL"

selectObject: spectrum_L_mod
result_L = To Sound

# Trim to original duration
selectObject: result_L
durL = Get total duration
if durL > duration
    trimL = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: result_L
    result_L = trimL
endif

appendInfoLine: "  Done"

# ===== PROCESS RIGHT CHANNEL (if stereo) =====
if create_stereo
    appendInfoLine: "Processing right channel..."
    
    bwR$ = fixed$(harmonic_bandwidth + stereo_bandwidth_offset, 2)
    
    selectObject: sound
    spectrum_R = To Spectrum: "yes"
    
    selectObject: spectrum_R
    matrix_R = To Matrix
    Rename: "matR"
    
    selectObject: matrix_R
    Formula: "if abs(x - round(x / " + fundStr$ + ") * " + fundStr$ + ") < " + bwR$ + " then self * " + boostStr$ + " else if x < " + midCutStr$ + " then self * " + lowAttStr$ + " else self * " + highAttStr$ + " fi fi"
    
    selectObject: matrix_R
    spectrum_R_mod = To Spectrum
    Rename: "specR"
    
    selectObject: spectrum_R_mod
    result_R = To Sound
    
    # Trim to original duration
    selectObject: result_R
    durR = Get total duration
    if durR > duration
        trimR = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: result_R
        result_R = trimR
    endif
    
    appendInfoLine: "  Done"
    
    # Combine to stereo
    appendInfoLine: "Creating stereo..."
    selectObject: result_L
    plusObject: result_R
    final_result = Combine to stereo
    
    removeObject: spectrum_R, matrix_R, spectrum_R_mod, result_L, result_R
else
    final_result = result_L
endif

# Finalize
selectObject: final_result
if create_stereo
    Rename: original_name$ + "_harmonic_" + preset_name$
else
    Rename: original_name$ + "_harmonic_" + preset_name$ + "_mono"
endif
Scale peak: scale_peak

# Cleanup
removeObject: sound, spectrum_L, matrix_L, spectrum_L_mod

appendInfoLine: ""
appendInfoLine: "Complete!"
appendInfoLine: "Harmonics: ", fundStr$, ", ", fixed$(fundamental_frequency * 2, 0), ", ", fixed$(fundamental_frequency * 3, 0), ", ", fixed$(fundamental_frequency * 4, 0), "... Hz"

selectObject: final_result
if play_after_processing
    Play
endif