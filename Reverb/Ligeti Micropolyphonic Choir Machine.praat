# ============================================================
# Praat AudioTools - Ligeti_Micropolyphonic_Choir_Machine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ligeti Micropolyphonic Choir Machine - creates dense,
#   slowly-evolving textures inspired by György Ligeti's
#   micropolyphonic technique (Lux Aeterna, Atmosphères).
#   Multiple voices with slight pitch/timing variations
#   create "clouds" of overlapping near-unisons. Different
#   structural modes offer various texture behaviors.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed formula syntax (Formula... → Formula:)
#   - Fixed variable scope issues
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Ligeti Micropolyphonic Choir
    comment Select a Sound object first
    
    comment === Behavioral Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Static Spectral Fog (Gaussian Mass)
        option Fracturing Mass (Gradual Detuning)
        option Stereo Torsion (L=Pure, R=Detuned)
        option Bimodal Web (High/Low Split)
        option Breathing Field (Uniform Cloud)
    
    comment === Voice Parameters ===
    positive Number_of_voices 60
    positive Time_offset_range_s 0.8
    positive Duration_variation 0.05
    positive Max_pitch_cents 15.0
    
    comment === Output ===
    boolean Stereo_spread 1
    positive Attack_fade_ms 30
    positive Voice_gain 1.0
    
    comment === Mix ===
    real Wet_dry_percent 80
    comment (0 = dry only, 100 = wet only)
    
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
originalName$ = selected$("Sound")

selectObject: original
originalDur = Get total duration
sr = Get sampling frequency
originalChannels = Get number of channels

# === Setup Defaults ===
structure$ = "uniform"
dist_shape$ = "flat"
time_range = 0.5
pitch_max = 15
dur_var = 0.05
n_voices = 50
gain = 1.0
fade = 25
use_stereo = stereo_spread

# === Apply Presets ===
if preset = 2
    # STATIC SPECTRAL FOG
    structure$ = "uniform"
    dist_shape$ = "gaussian"
    n_voices = 60
    time_range = 0.5
    pitch_max = 8
    dur_var = 0.02
    gain = 0.8
    fade = 50
    presetName$ = "Fog"

elsif preset = 3
    # FRACTURING MASS
    structure$ = "arc_fracture"
    dist_shape$ = "flat"
    n_voices = 60
    time_range = 1.0
    pitch_max = 35
    dur_var = 0.08
    gain = 0.7
    fade = 30
    presetName$ = "Fracture"

elsif preset = 4
    # STEREO TORSION
    structure$ = "asymmetry"
    dist_shape$ = "flat"
    n_voices = 50
    time_range = 0.6
    pitch_max = 25
    dur_var = 0.05
    gain = 0.9
    fade = 20
    use_stereo = 1
    presetName$ = "Torsion"

elsif preset = 5
    # BIMODAL WEB
    structure$ = "bimodal"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 0.8
    pitch_max = 20
    dur_var = 0.1
    gain = 0.85
    fade = 15
    presetName$ = "Bimodal"

elsif preset = 6
    # BREATHING FIELD
    structure$ = "uniform"
    dist_shape$ = "flat"
    n_voices = 40
    time_range = 1.2
    pitch_max = 12
    dur_var = 0.08
    gain = 0.8
    fade = 40
    presetName$ = "Breathing"

else
    # CUSTOM
    n_voices = number_of_voices
    time_range = time_offset_range_s
    pitch_max = max_pitch_cents
    dur_var = duration_variation
    gain = voice_gain
    fade = attack_fade_ms
    presetName$ = "Custom"
endif

if n_voices < 2
    exitScript: "Need at least 2 voices."
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Output channels
if use_stereo = 1
    outChannels = 2
else
    outChannels = originalChannels
endif

# === Info ===
writeInfoLine: "=== Ligeti Micropolyphonic Choir ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Structure: ", structure$
appendInfoLine: "Distribution: ", dist_shape$
appendInfoLine: "Voices: ", n_voices
appendInfoLine: "Time range: ±", fixed$(time_range, 2), " s"
appendInfoLine: "Pitch range: ±", pitch_max, " cents"
appendInfoLine: "Duration var: ±", fixed$(dur_var * 100, 1), "%"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# Store voice data for visualization
for v from 1 to n_voices
    voicePitch[v] = 0
    voiceOffset[v] = 0
    voicePan[v] = 0
endfor

# === Create Output Buffer ===
output_dur = originalDur + time_range + 0.5

Create Sound from formula: "choir_output", outChannels, 0, output_dur, sr, "0"
output = selected("Sound")

# ============================================================
# VOICE GENERATION LOOP
# ============================================================

appendInfoLine: "Generating ", n_voices, " voices..."

for voice from 1 to n_voices
    
    if voice mod 10 = 0
        appendInfoLine: "  Voice ", voice, " / ", n_voices
    endif
    
    selectObject: original
    Copy: "voice_temp"
    voiceCopy = selected("Sound")
    
    # Reset start time
    t_start = Get start time
    if t_start <> 0
        Shift times by: -t_start
    endif
    
    # === 1. CALCULATE PANNING ===
    pan_pos = randomUniform(-1, 1)
    voicePan[voice] = pan_pos
    
    # === 2. CALCULATE PITCH DEVIATION ===
    current_pitch_cents = 0
    
    if structure$ = "uniform"
        if dist_shape$ = "gaussian"
            r1 = randomUniform(-1, 1)
            r2 = randomUniform(-1, 1)
            current_pitch_cents = ((r1 + r2) / 2) * pitch_max
        else
            current_pitch_cents = randomUniform(-pitch_max, pitch_max)
        endif
        
    elsif structure$ = "arc_fracture"
        intensity = voice / n_voices
        current_range = pitch_max * intensity
        current_pitch_cents = randomUniform(-current_range, current_range)
        
    elsif structure$ = "asymmetry"
        tension = (pan_pos + 1) / 2
        current_range = pitch_max * tension
        current_pitch_cents = randomUniform(-current_range, current_range)
        
    elsif structure$ = "bimodal"
        if voice mod 2 = 0
            current_pitch_cents = randomUniform(5, pitch_max)
        else
            current_pitch_cents = randomUniform(-pitch_max, -5)
        endif
    endif
    
    voicePitch[voice] = current_pitch_cents
    
    # === 3. APPLY PITCH SHIFT ===
    pitch_ratio = 2 ^ (current_pitch_cents / 1200)
    
    if abs(current_pitch_cents) > 0.1
        selectObject: voiceCopy
        new_sr = sr * pitch_ratio
        Override sampling frequency: new_sr
        Resample: sr, 50
        temp = selected("Sound")
        removeObject: voiceCopy
        voiceCopy = temp
    endif
    
    # === 4. TIME STRETCH ===
    if dist_shape$ = "gaussian"
        raw_rand = (randomUniform(-1, 1) + randomUniform(-1, 1)) / 2
        dur_factor = 1 + (raw_rand * dur_var)
    else
        dur_factor = 1 + randomUniform(-dur_var, dur_var)
    endif
    
    total_stretch = dur_factor * pitch_ratio
    
    if abs(total_stretch - 1) > 0.001
        selectObject: voiceCopy
        v_ch = Get number of channels
        if v_ch = 1
            Lengthen (overlap-add): 75, 600, total_stretch
            s_str = selected("Sound")
        else
            Extract one channel: 1
            ch1 = selected("Sound")
            Lengthen (overlap-add): 75, 600, total_stretch
            s1 = selected("Sound")
            selectObject: voiceCopy
            Extract one channel: 2
            ch2 = selected("Sound")
            Lengthen (overlap-add): 75, 600, total_stretch
            s2 = selected("Sound")
            selectObject: s1, s2
            Combine to stereo
            s_str = selected("Sound")
            removeObject: ch1, ch2, s1, s2
        endif
        removeObject: voiceCopy
        voiceCopy = s_str
    endif
    
    # === 5. ENVELOPE (Attack/Release Fade) ===
    if fade > 0
        selectObject: voiceCopy
        fade_sec = fade / 1000
        fade_str$ = string$(fade_sec)
        Formula: "self * (if (x - xmin) < " + fade_str$ + " then (x - xmin)/" + fade_str$ + " else if (xmax - x) < " + fade_str$ + " then (xmax - x)/" + fade_str$ + " else 1 fi fi)"
    endif
    
    # === 6. GAIN ===
    selectObject: voiceCopy
    gain_per_voice = gain / sqrt(n_voices)
    gain_str$ = string$(gain_per_voice)
    Formula: "self * " + gain_str$
    
    # === 7. STEREO PANNING ===
    selectObject: voiceCopy
    curr_ch = Get number of channels
    
    if use_stereo = 1 and curr_ch = 1
        l_gain = sqrt((1 - pan_pos) / 2)
        r_gain = sqrt((1 + pan_pos) / 2)
        
        l_str$ = string$(l_gain)
        r_str$ = string$(r_gain)
        
        Copy: "L_temp"
        s_left = selected("Sound")
        Formula: "self * " + l_str$
        
        selectObject: voiceCopy
        Copy: "R_temp"
        s_right = selected("Sound")
        Formula: "self * " + r_str$
        
        selectObject: s_left, s_right
        Combine to stereo
        v_stereo = selected("Sound")
        removeObject: voiceCopy, s_left, s_right
        voiceCopy = v_stereo
    endif
    
    # === 8. TIME OFFSET ===
    selectObject: voiceCopy
    
    if dist_shape$ = "gaussian"
        r1 = randomUniform(-0.5, 0.5)
        r2 = randomUniform(-0.5, 0.5)
        offset = (r1 + r2) * time_range
    else
        offset = randomUniform(-time_range/2, time_range/2)
    endif
    
    voiceOffset[voice] = offset
    
    # Apply offset
    if offset < 0
        cut_dur = abs(offset)
        curr_dur = Get total duration
        if cut_dur < curr_dur
            Extract part: cut_dur, curr_dur, "rectangular", 1, "no"
            v_cut = selected("Sound")
            removeObject: voiceCopy
            voiceCopy = v_cut
        endif
    elsif offset > 0.001
        Create Sound from formula: "sil", outChannels, 0, offset, sr, "0"
        sil = selected("Sound")
        selectObject: sil, voiceCopy
        Concatenate
        cat = selected("Sound")
        removeObject: sil, voiceCopy
        voiceCopy = cat
    endif
    
    # === 9. PAD TO OUTPUT LENGTH ===
    selectObject: voiceCopy
    curr_dur = Get total duration
    rem_dur = output_dur - curr_dur
    
    if rem_dur > 0
        Create Sound from formula: "sil_end", outChannels, 0, rem_dur, sr, "0"
        sil_end = selected("Sound")
        selectObject: voiceCopy, sil_end
        Concatenate
        cat2 = selected("Sound")
        removeObject: sil_end, voiceCopy
        voiceCopy = cat2
    endif
    
    # Clamp to exact output duration
    selectObject: voiceCopy
    Extract part: 0, output_dur, "rectangular", 1, "no"
    ready = selected("Sound")
    removeObject: voiceCopy
    
    # === 10. MIX INTO OUTPUT ===
    ready_str$ = string$(ready)
    selectObject: output
    Formula: "self + object[" + ready_str$ + "]"
    removeObject: ready

endfor

# === Apply Wet/Dry Mix ===
if dry_level > 0
    # Need to extend original to match output length
    selectObject: original
    Copy: "dry_extended"
    dryExt = selected("Sound")
    
    # Convert to stereo if needed
    if outChannels = 2 and originalChannels = 1
        Copy: "dry_R"
        dryR = selected("Sound")
        selectObject: dryExt, dryR
        Combine to stereo
        temp = selected("Sound")
        removeObject: dryExt, dryR
        dryExt = temp
    endif
    
    # Pad to output length
    selectObject: dryExt
    curr_dur = Get total duration
    if curr_dur < output_dur
        Create Sound from formula: "sil_dry", outChannels, 0, output_dur - curr_dur, sr, "0"
        sil_dry = selected("Sound")
        selectObject: dryExt, sil_dry
        Concatenate
        temp = selected("Sound")
        removeObject: sil_dry, dryExt
        dryExt = temp
    endif
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_id_str$ = string$(dryExt)
    
    selectObject: output
    Formula: "self * " + wet_str$ + " + object[" + dry_id_str$ + "] * " + dry_str$
    
    removeObject: dryExt
endif

# === Normalize ===
selectObject: output
if normalize_output = 1
    Scale peak: 0.95
endif

Rename: originalName$ + "_ligeti_" + presetName$
result = selected("Sound")

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Ligeti Micropolyphonic Choir: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.3
    Select inner viewport: 0.6, 7.6, 0.7, 1.2
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.4, 2.1
    Select inner viewport: 0.6, 7.6, 1.5, 2.0
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Choir"
    Text bottom: "yes", "Time (s)"
    
    # Voice distribution: Pitch vs Time Offset
    Select outer viewport: 0, 4, 2.3, 3.8
    Select inner viewport: 0.6, 3.8, 2.4, 3.7
    
    Axes: -time_range, time_range, -pitch_max * 1.2, pitch_max * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -time_range, time_range, -pitch_max * 1.2, pitch_max * 1.2
    
    # Draw voice points
    for v from 1 to n_voices
        # Color by pan position
        r = 0.5 + voicePan[v] * 0.3
        g = 0.5
        b = 0.5 - voicePan[v] * 0.3
        
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Paint circle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", voiceOffset[v], voicePitch[v], time_range * 0.03
    endfor
    
    # Center lines
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, -pitch_max * 1.2, 0, pitch_max * 1.2
    Draw line: -time_range, 0, time_range, 0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch (cents)"
    Text bottom: "yes", "Time offset (s)"
    
    # Voice distribution: Pan vs Pitch
    Select outer viewport: 4, 8, 2.3, 3.8
    Select inner viewport: 4.4, 7.6, 2.4, 3.7
    
    Axes: -1.2, 1.2, -pitch_max * 1.2, pitch_max * 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", -1.2, 1.2, -pitch_max * 1.2, pitch_max * 1.2
    
    # Draw voice points
    for v from 1 to n_voices
        r = 0.5 + voicePan[v] * 0.3
        g = 0.5
        b = 0.5 - voicePan[v] * 0.3
        
        Colour: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}"
        Paint circle: "{" + fixed$(r, 2) + ", " + fixed$(g, 2) + ", " + fixed$(b, 2) + "}", voicePan[v], voicePitch[v], 0.05
    endfor
    
    Colour: "{0.8, 0.8, 0.8}"
    Dotted line
    Draw line: 0, -pitch_max * 1.2, 0, pitch_max * 1.2
    Draw line: -1.2, 0, 1.2, 0
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pitch (cents)"
    Text bottom: "yes", "Pan (L←→R)"
    
    # Parameters
    Select outer viewport: 0, 8, 3.9, 4.3
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Voices: " + string$(n_voices) + " | Pitch: ±" + string$(pitch_max) + "¢ | Time: ±" + fixed$(time_range, 2) + "s | Mode: " + structure$
    
    Font size: 10
    Colour: "Black"
endif

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
