# ============================================================
# Praat AudioTools - Competing Modulators.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025) - Rewritten (fixed encoding + bugs)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multiple FM voices with competing modulator frequencies
#   create complex interference patterns and beating textures.
#
# Usage:
#   Run this script (no input sound required).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Competing Modulators
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Chaos
        option Metallic Clash
        option Organic Swarm
        option Digital Warble
        option Harmonic Battle
        option Alien Chorus
        option Glitchy Modulation
        option Rhythmic Conflict
        option Spectral War
        option Liquid Modulation
        option Crystal Resonance
        option Deep Interference
    
    comment === Basic Settings ===
    positive Duration_s 8.0
    integer Sample_rate_Hz 44100
    positive Base_frequency_Hz 120
    integer Number_of_voices 4
    
    comment === Modulation ===
    real Modulation_intensity 0.5
    real Modulator_spread 1.5
    real Beating_rate_Hz 2.0
    
    comment === Envelope ===
    optionmenu Envelope_type 1
        option No Envelope
        option Percussive
        option Slow Fade
        option Reverse
        option Tremolo
        option Swell
        option ADSR
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo Voices
        option Rotating Modulators
        option Wide Field
        option Ping Pong
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    # Gentle Chaos
    base_frequency_Hz = 100
    modulation_intensity = 0.3
    number_of_voices = 3
    modulator_spread = 1.2
    beating_rate_Hz = 1.5
    envelope_type = 6
    spatial_mode = 1
    preset_name$ = "GentleChaos"
elsif preset = 3
    # Metallic Clash
    base_frequency_Hz = 180
    modulation_intensity = 0.8
    number_of_voices = 5
    modulator_spread = 2.0
    beating_rate_Hz = 5.0
    envelope_type = 2
    spatial_mode = 4
    preset_name$ = "MetallicClash"
elsif preset = 4
    # Organic Swarm
    base_frequency_Hz = 80
    modulation_intensity = 0.4
    number_of_voices = 6
    modulator_spread = 1.1
    beating_rate_Hz = 0.5
    envelope_type = 5
    spatial_mode = 3
    preset_name$ = "OrganicSwarm"
elsif preset = 5
    # Digital Warble
    base_frequency_Hz = 200
    modulation_intensity = 0.7
    number_of_voices = 4
    modulator_spread = 1.8
    beating_rate_Hz = 8.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "DigitalWarble"
elsif preset = 6
    # Harmonic Battle
    base_frequency_Hz = 150
    modulation_intensity = 0.6
    number_of_voices = 4
    modulator_spread = 2.0
    beating_rate_Hz = 3.0
    envelope_type = 7
    spatial_mode = 2
    preset_name$ = "HarmonicBattle"
elsif preset = 7
    # Alien Chorus
    base_frequency_Hz = 140
    modulation_intensity = 0.9
    number_of_voices = 5
    modulator_spread = 1.618
    beating_rate_Hz = 4.0
    envelope_type = 5
    spatial_mode = 3
    preset_name$ = "AlienChorus"
elsif preset = 8
    # Glitchy Modulation
    base_frequency_Hz = 220
    modulation_intensity = 1.0
    number_of_voices = 3
    modulator_spread = 3.0
    beating_rate_Hz = 12.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "GlitchyModulation"
elsif preset = 9
    # Rhythmic Conflict
    base_frequency_Hz = 110
    modulation_intensity = 0.5
    number_of_voices = 4
    modulator_spread = 1.5
    beating_rate_Hz = 6.0
    envelope_type = 1
    spatial_mode = 5
    preset_name$ = "RhythmicConflict"
elsif preset = 10
    # Spectral War
    base_frequency_Hz = 160
    modulation_intensity = 0.8
    number_of_voices = 6
    modulator_spread = 2.5
    beating_rate_Hz = 7.0
    envelope_type = 3
    spatial_mode = 4
    preset_name$ = "SpectralWar"
elsif preset = 11
    # Liquid Modulation
    base_frequency_Hz = 70
    modulation_intensity = 0.4
    number_of_voices = 3
    modulator_spread = 1.3
    beating_rate_Hz = 0.3
    envelope_type = 6
    spatial_mode = 3
    preset_name$ = "LiquidModulation"
elsif preset = 12
    # Crystal Resonance
    base_frequency_Hz = 440
    modulation_intensity = 0.5
    number_of_voices = 5
    modulator_spread = 1.5
    beating_rate_Hz = 2.0
    envelope_type = 2
    spatial_mode = 2
    preset_name$ = "CrystalResonance"
elsif preset = 13
    # Deep Interference
    duration_s = 12
    base_frequency_Hz = 55
    modulation_intensity = 0.6
    number_of_voices = 4
    modulator_spread = 1.2
    beating_rate_Hz = 0.2
    envelope_type = 3
    spatial_mode = 3
    preset_name$ = "DeepInterference"
endif

# === Validation ===
if number_of_voices > 8
    number_of_voices = 8
endif
if number_of_voices < 2
    number_of_voices = 2
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))
twoPi = 2 * pi

# === Info ===
writeInfoLine: "=== Competing Modulators ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", duration_s, " s"
appendInfoLine: "Voices: ", number_of_voices
appendInfoLine: "Base frequency: ", base_frequency_Hz, " Hz"
appendInfoLine: "Modulation intensity: ", modulation_intensity
appendInfoLine: ""

# === Create output sound ===
outputSound = Create Sound from formula: "competing_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"

# === Generate competing modulator voices ===
appendInfoLine: "Generating ", number_of_voices, " competing voices..."

for voice to number_of_voices
    appendInfoLine: "  Voice ", voice, "..."
    
    # Each voice has a carrier and competing modulators
    carrierFreq = base_frequency_Hz * (1 + (voice - 1) * 0.1)
    
    # Primary modulator frequency (different for each voice)
    mod1Freq = beating_rate_Hz * voice
    mod1Index = modulation_intensity * 2
    
    # Secondary modulator (competing - slightly detuned)
    mod2Freq = mod1Freq * modulator_spread
    mod2Index = modulation_intensity * 1.5
    
    # Tertiary modulator (creates complex beating)
    mod3Freq = mod1Freq * (1 + 0.01 * voice)
    mod3Index = modulation_intensity * 0.8
    
    # Voice amplitude (decreasing for higher voices)
    voiceAmp = 0.7 / (number_of_voices * sqrt(voice))
    
    # Build FM formula with competing modulators
    # carrier × (1 + mod1 + mod2 + mod3)
    voiceSound = Create Sound from formula: "voice_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "voiceAmp * sin(twoPi * carrierFreq * x + mod1Index * sin(twoPi * mod1Freq * x) + mod2Index * sin(twoPi * mod2Freq * x) + mod3Index * sin(twoPi * mod3Freq * x))"
    
    # Add to output
    voiceName$ = selected$("Sound")
    selectObject: outputSound
    Formula: "self + Sound_'voiceName$'[]"
    
    removeObject: voiceSound
endfor

# === Apply Envelope ===
appendInfoLine: "Applying envelope..."
selectObject: outputSound

if envelope_type = 2
    # Percussive
    Formula: "self * exp(-x * 3)"
elsif envelope_type = 3
    # Slow Fade
    Formula: "self * exp(-x * 0.2)"
elsif envelope_type = 4
    # Reverse
    Formula: "self * (x / duration_s)"
elsif envelope_type = 5
    # Tremolo
    tremRate = 5 + modulation_intensity * 10
    Formula: "self * (0.6 + 0.4 * sin(twoPi * tremRate * x))"
elsif envelope_type = 6
    # Swell
    attackTime = duration_s * 0.3
    Formula: "self * min(1, x / attackTime)"
elsif envelope_type = 7
    # ADSR
    attack = 0.05
    decay = 0.2
    sustain = 0.6
    releaseStart = duration_s - 0.5
    
    Formula: "if x < attack then self * (x / attack) else self fi"
    Formula: "if x >= attack and x < attack + decay then self * (1 - (1 - sustain) * ((x - attack) / decay)) else self fi"
    Formula: "if x >= attack + decay and x < releaseStart then self * sustain else self fi"
    Formula: "if x >= releaseStart then self * sustain * (1 - (x - releaseStart) / (duration_s - releaseStart)) else self fi"
endif

# === Fade in/out ===
selectObject: outputSound
Formula: "if x < 0.02 then self * (x / 0.02) else self fi"
Formula: "if x > duration_s - 0.02 then self * ((duration_s - x) / 0.02) else self fi"

# === Spatial Processing ===
if spatial_mode = 2
    # Stereo Voices - alternate voices L/R
    appendInfoLine: "Creating stereo voices..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 3000, 100
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 150, 8000, 100
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "competing_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 3
    # Rotating Modulators
    appendInfoLine: "Creating rotating stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * cos(twoPi * 0.15 * x))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.5 + 0.5 * sin(twoPi * 0.15 * x))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "competing_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 4
    # Wide Field - extreme frequency separation
    appendInfoLine: "Creating wide field stereo..."
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Filter (pass Hann band): 0, 2000, 150
    leftFiltered = selected("Sound")
    removeObject: leftSound
    leftSound = leftFiltered
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Filter (pass Hann band): 300, 8000, 150
    rightFiltered = selected("Sound")
    removeObject: rightSound
    rightSound = rightFiltered
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "competing_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound

elsif spatial_mode = 5
    # Ping Pong - fast alternating
    appendInfoLine: "Creating ping pong stereo..."
    
    panRate = 2.5
    
    selectObject: outputSound
    Copy: "left_" + uid$
    leftSound = selected("Sound")
    Formula: "self * (0.3 + 0.7 * (0.5 + 0.5 * sin(twoPi * panRate * x)))"
    
    selectObject: outputSound
    Copy: "right_" + uid$
    rightSound = selected("Sound")
    Formula: "self * (0.3 + 0.7 * (0.5 + 0.5 * cos(twoPi * panRate * x)))"
    
    selectObject: leftSound
    plusObject: rightSound
    stereoSound = Combine to stereo
    Rename: "competing_" + preset_name$
    
    removeObject: outputSound, leftSound, rightSound
    outputSound = stereoSound
else
    selectObject: outputSound
    Rename: "competing_" + preset_name$
endif

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Visualization ===
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawSpectrogram
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final Selection ===
selectObject: outputSound

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ==============================================================================
# Procedure: drawSpectrogram
# ==============================================================================
procedure drawSpectrogram
    
    Erase all
    
    .leftMargin = 0.6
    .rightMargin = 6.5
    
    # === Title ===
    Select outer viewport: 0, 7, 0, 1.5
    Font size: 12
    Colour: "Black"
    Text top: "no", "Competing Modulators: " + preset_name$
    
    # === Spectrogram ===
    Select outer viewport: 0, 7, 0.6, 4.5
    Colour: "{0.85, 0.85, 0.85}"
    Draw inner box
    
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    
    if spatial_mode > 1
        selectObject: outputSound
        Extract one channel: 1
        .monoForSpec = selected("Sound")
    else
        selectObject: outputSound
        Copy: "temp_for_spec"
        .monoForSpec = selected("Sound")
    endif
    
    selectObject: .monoForSpec
    .maxFreqSpec = min(5000, base_frequency_Hz * 8)
    
    To Spectrogram: 0.03, .maxFreqSpec, 0.005, 20, "Gaussian"
    .spec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    
    removeObject: .monoForSpec, .spec
    
    # Axis labels
    Select inner viewport: .leftMargin, .rightMargin, 0.7, 4.4
    Axes: 0, duration_s, 0, .maxFreqSpec
    Colour: "White"
    Marks left: 5, "yes", "yes", "no"
    Marks bottom every: 1, 1, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Frequency (Hz)"
    
    # === Footer ===
    Select outer viewport: 0, 7, 6.4, 7
    Font size: 8
    Colour: "{0.4, 0.4, 0.4}"
    .paramText$ = "Base: " + fixed$(base_frequency_Hz, 0) + " Hz | Mod: " + fixed$(modulation_intensity, 2) + " | Spread: " + fixed$(modulator_spread, 2) + " | Voices: " + string$(number_of_voices)
    Text top: "no", .paramText$
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc