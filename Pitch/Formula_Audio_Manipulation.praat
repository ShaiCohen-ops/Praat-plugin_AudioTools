# ============================================================
# Praat AudioTools - Formula_Audio_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formula Audio Manipulation - multi-layer modulation combining
#   complex amplitude modulation (with irrational ratio harmonics),
#   pitch modulation via PSOLA, and ring modulation. Creates
#   evolving textures from subtle to chaotic.
#
# Changelog v0.3:
#   - Mono-safe: source is folded to mono before processing (the
#     [] formula refs and To Manipulation/To Pitch are mono-only);
#     stereo input no longer errors. The Original viz panels show
#     the folded mono source.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed formula interpolation
#   - Added visualization
#   - Modern syntax
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sampling_rate = Get sampling frequency

# === Form ===
form Formula Audio Manipulation
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (configure below)
        option Gentle Modulation
        option Complex Textures
        option Chaotic Systems
        option Rhythmic Pulsing
        option Harmonic Richness
        option Extreme Modulation
        option Subtle Evolution
    
    comment === Amplitude Modulation ===
    real Base_frequency 0.8
    real Modulation_depth 0.85
    integer Complexity_level 3
    comment (1=simple, 2=layered, 3=chaotic)
    
    comment === Pitch Modulation ===
    boolean Apply_pitch_modulation 1
    real Pitch_mod_rate 0.5
    real Pitch_mod_depth 0.4
    
    comment === Ring Modulation ===
    boolean Apply_ring_modulation 1
    real Ring_mod_frequency 120
    real Ring_mod_depth 0.6
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Gentle Modulation
    base_frequency = 0.3
    modulation_depth = 0.4
    complexity_level = 2
    apply_pitch_modulation = 1
    pitch_mod_rate = 0.2
    pitch_mod_depth = 0.2
    apply_ring_modulation = 0
elsif preset = 3
    # Complex Textures
    base_frequency = 1.2
    modulation_depth = 0.7
    complexity_level = 3
    apply_pitch_modulation = 1
    pitch_mod_rate = 0.8
    pitch_mod_depth = 0.3
    apply_ring_modulation = 1
    ring_mod_frequency = 80
    ring_mod_depth = 0.4
elsif preset = 4
    # Chaotic Systems
    base_frequency = 2.5
    modulation_depth = 0.9
    complexity_level = 3
    apply_pitch_modulation = 1
    pitch_mod_rate = 1.5
    pitch_mod_depth = 0.6
    apply_ring_modulation = 1
    ring_mod_frequency = 200
    ring_mod_depth = 0.8
elsif preset = 5
    # Rhythmic Pulsing
    base_frequency = 4.0
    modulation_depth = 0.6
    complexity_level = 2
    apply_pitch_modulation = 0
    apply_ring_modulation = 1
    ring_mod_frequency = 60
    ring_mod_depth = 0.7
elsif preset = 6
    # Harmonic Richness
    base_frequency = 0.5
    modulation_depth = 0.5
    complexity_level = 3
    apply_pitch_modulation = 1
    pitch_mod_rate = 0.3
    pitch_mod_depth = 0.4
    apply_ring_modulation = 1
    ring_mod_frequency = 150
    ring_mod_depth = 0.3
elsif preset = 7
    # Extreme Modulation
    base_frequency = 3.0
    modulation_depth = 1.0
    complexity_level = 3
    apply_pitch_modulation = 1
    pitch_mod_rate = 2.0
    pitch_mod_depth = 0.8
    apply_ring_modulation = 1
    ring_mod_frequency = 300
    ring_mod_depth = 0.9
elsif preset = 8
    # Subtle Evolution
    base_frequency = 0.2
    modulation_depth = 0.3
    complexity_level = 1
    apply_pitch_modulation = 1
    pitch_mod_rate = 0.1
    pitch_mod_depth = 0.15
    apply_ring_modulation = 0
endif

# === Get Preset Name ===
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "Gentle"
elsif preset = 3
    presetName$ = "Complex"
elsif preset = 4
    presetName$ = "Chaotic"
elsif preset = 5
    presetName$ = "Rhythmic"
elsif preset = 6
    presetName$ = "Harmonic"
elsif preset = 7
    presetName$ = "Extreme"
else
    presetName$ = "Subtle"
endif

# === Info ===
writeInfoLine: "=== Formula Audio Manipulation ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "AM: base=", fixed$(base_frequency, 2), " Hz, depth=", fixed$(modulation_depth, 2), ", complexity=", complexity_level
if apply_pitch_modulation
    appendInfoLine: "Pitch mod: rate=", fixed$(pitch_mod_rate, 2), " Hz, depth=", fixed$(pitch_mod_depth, 2)
endif
if apply_ring_modulation
    appendInfoLine: "Ring mod: freq=", ring_mod_frequency, " Hz, depth=", fixed$(ring_mod_depth, 2)
endif
appendInfoLine: ""

# ===================================================================
# BUILD AMPLITUDE MODULATION ENVELOPE
# ===================================================================

appendInfoLine: "Building AM envelope (complexity ", complexity_level, ")..."

# Use variables in formula (modern syntax)
bf = base_frequency
md = modulation_depth

if complexity_level = 1
    # Simple modulated envelope
    Create Sound from formula: "am_envelope", 1, 0, duration, sampling_rate,
        ... ~ 0.5 + 0.5 * sin(2*pi*bf*x * (1 + md*0.6*sin(2*pi*2*x)))
    
elsif complexity_level = 2
    # Multiple competing oscillators (golden ratio, e)
    Create Sound from formula: "am_envelope", 1, 0, duration, sampling_rate,
        ... ~ 0.5 + 0.5 * (
        ... sin(2*pi*bf*x * (1 + 0.4*sin(2*pi*1.5*x))) +
        ... 0.6*sin(2*pi*bf*1.618*x * (1 + 0.5*sin(2*pi*2.8*x))) +
        ... 0.4*sin(2*pi*bf*2.718*x * (1 + 0.6*sin(2*pi*0.9*x)))
        ... ) / 2.0
    
else
    # Complex chaotic system with nested modulation
    Create Sound from formula: "am_envelope", 1, 0, duration, sampling_rate,
        ... ~ 0.5 + 0.5 * (
        ... sin(2*pi*bf*x * (1 + md*0.7*sin(2*pi*1.4*x + 2.5*sin(2*pi*0.4*x)))) +
        ... 0.8*sin(2*pi*bf*1.618*x * (1 + md*0.6*sin(2*pi*2.5*x + 1.5*sin(2*pi*0.7*x)))) +
        ... 0.5*sin(2*pi*bf*2.414*x * (1 + md*0.8*sin(2*pi*1.1*x + 2.0*sin(2*pi*0.3*x))))
        ... ) / 2.3
endif

am_envelope = selected("Sound")

# ===================================================================
# APPLY AMPLITUDE MODULATION
# ===================================================================

appendInfoLine: "Applying AM..."

# Fold to mono (the [] formula refs and To Manipulation/To Pitch are mono-only)
selectObject: original
numChan = Get number of channels
if numChan > 1
    src = Convert to mono
    appendInfoLine: "  (stereo input folded to mono)"
else
    src = Copy: sound_name$ + "_srcmono"
endif
selectObject: src
Copy: sound_name$ + "_modulated"
sound_mod = selected("Sound")

Formula: ~ self * Sound_am_envelope[]

# ===================================================================
# PITCH MODULATION (optional)
# ===================================================================

if apply_pitch_modulation
    appendInfoLine: "Applying pitch modulation..."
    
    selectObject: sound_mod
    manipulation = To Manipulation: 0.005, 75, 600
    
    # Get base pitch
    selectObject: sound_mod
    To Pitch: 0.005, 75, 600
    pitch_obj = selected("Pitch")
    f0_base = Get quantile: 0, 0, 0.5, "Hertz"
    
    if f0_base = undefined
        f0_base = 150
    endif
    
    removeObject: pitch_obj
    
    # Create modulated pitch tier with dense points
    Create PitchTier: "pitch_mod", 0, duration
    pitchtier_new = selected("PitchTier")
    
    n_points = round(duration * 100)
    if n_points < 200
        n_points = 200
    endif
    if n_points > 2000
        n_points = 2000
    endif
    
    pmr = pitch_mod_rate
    pmd = pitch_mod_depth
    
    for i from 0 to n_points - 1
        t = i * duration / n_points
        
        # Complex pitch modulation with multiple layers
        mod1 = sin(2*pi*pmr*t)
        mod2 = 0.5 * sin(2*pi*pmr*1.7*t + 0.5)
        mod3 = 0.3 * sin(2*pi*pmr*0.6*t + 1.2)
        
        mod_factor = 1 + pmd * (mod1 + mod2 + mod3) / 1.8
        f0 = f0_base * mod_factor
        
        # Clamp to range
        if f0 < 75
            f0 = 75
        elsif f0 > 600
            f0 = 600
        endif
        
        selectObject: pitchtier_new
        Add point: t, f0
    endfor
    
    # Replace pitch tier
    selectObject: manipulation, pitchtier_new
    Replace pitch tier
    
    # Resynthesize
    selectObject: manipulation
    sound_repitched = Get resynthesis (overlap-add)
    Rename: sound_name$ + "_pitch_mod"
    
    # Clean up
    removeObject: sound_mod, manipulation, pitchtier_new
    sound_mod = sound_repitched
endif

# ===================================================================
# RING MODULATION (optional)
# ===================================================================

if apply_ring_modulation
    appendInfoLine: "Applying ring modulation..."
    
    rmf = ring_mod_frequency
    rmd = ring_mod_depth
    
    # Create carrier signal
    Create Sound from formula: "carrier", 1, 0, duration, sampling_rate,
        ... ~ sin(2*pi*rmf*x)
    carrier = selected("Sound")
    
    # Apply ring modulation
    selectObject: sound_mod
    Formula: ~ self * (1 - rmd + rmd * Sound_carrier[])
    
    removeObject: carrier
endif

# ===================================================================
# FINAL PROCESSING
# ===================================================================

selectObject: sound_mod
Rename: sound_name$ + "_formula_" + presetName$
Scale peak: 0.95
result = selected("Sound")

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Formula Audio Manipulation: " + sound_name$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: src
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # AM envelope
    Select outer viewport: 0, 8, 1.7, 2.7
    Select inner viewport: 0.6, 7.6, 1.8, 2.6
    selectObject: am_envelope
    Colour: "{0.8, 0.6, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "AM Env"
    
    # Result waveform
    Select outer viewport: 0, 8, 2.8, 3.8
    Select inner viewport: 0.6, 7.6, 2.9, 3.7
    selectObject: result
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Spectrogram comparison
    Select outer viewport: 0, 4, 4.0, 5.4
    Select inner viewport: 0.6, 3.8, 4.2, 5.3
    selectObject: src
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"
    
    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.4, 7.6, 4.2, 5.3
    selectObject: result
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Processed"
    
    # Processing chain
    Select outer viewport: 0, 8, 5.5, 5.8
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    
    chainText$ = "AM(" + fixed$(base_frequency, 1) + "Hz)"
    if apply_pitch_modulation
        chainText$ = chainText$ + " → Pitch(" + fixed$(pitch_mod_rate, 1) + "Hz)"
    endif
    if apply_ring_modulation
        chainText$ = chainText$ + " → Ring(" + string$(ring_mod_frequency) + "Hz)"
    endif
    
    Text: 0.5, "centre", 0.5, "half", "Chain: " + chainText$ + " | Complexity: " + string$(complexity_level)
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
removeObject: am_envelope
removeObject: src

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result