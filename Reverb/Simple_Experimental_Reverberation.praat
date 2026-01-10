# ============================================================
# Praat AudioTools - Simple_Experimental_Reverberation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Smooth Cosmic Reverb - modulated reverb effect with
#   sinusoidal delay variation and time-varying amplitude
#   modulation. Delays follow: start + range×(k/n) + depth×sin(k).
#   Each echo has different tremolo patterns. HF enhancement
#   decays over time. Creates ethereal, "cosmic" swimming reverb.
#
# Changelog v0.2:
#   - Added input check
#   - Fixed selection and formula syntax
#   - Added wet/dry mix control
#   - Added visualization
# ============================================================

form Smooth Cosmic Reverb
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Cosmic
        option Medium Cosmic
        option Heavy Cosmic
        option Extreme Cosmic
    
    comment === Main Parameters ===
    positive Tail_duration_s 2.0
    natural Number_of_delays 45
    positive Base_amplitude 0.22
    positive Decay_factor 0.96
    
    comment === Delay Range ===
    positive Delay_start_s 0.08
    positive Delay_range_s 0.5
    positive Delay_mod_depth_s 0.08
    
    comment === Modulation ===
    positive Amp_mod_depth 0.2
    positive Mod_freq_factor 0.5
    
    comment === HF Enhancement ===
    positive HF_enhancement 0.08
    positive HF_decay_rate 4.0
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    positive Fadeout_duration_s 1.2
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
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Cosmic
    tail_duration_s = 1.5
    number_of_delays = 25
    base_amplitude = 0.15
    decay_factor = 0.97
    delay_start_s = 0.05
    delay_range_s = 0.3
    delay_mod_depth_s = 0.05
    amp_mod_depth = 0.15
    mod_freq_factor = 0.4
    hF_enhancement = 0.05
    hF_decay_rate = 3.0
    fadeout_duration_s = 1.0
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Cosmic
    tail_duration_s = 2.0
    number_of_delays = 45
    base_amplitude = 0.22
    decay_factor = 0.96
    delay_start_s = 0.08
    delay_range_s = 0.5
    delay_mod_depth_s = 0.08
    amp_mod_depth = 0.2
    mod_freq_factor = 0.5
    hF_enhancement = 0.08
    hF_decay_rate = 4.0
    fadeout_duration_s = 1.2
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Cosmic
    tail_duration_s = 3.0
    number_of_delays = 70
    base_amplitude = 0.28
    decay_factor = 0.95
    delay_start_s = 0.1
    delay_range_s = 0.75
    delay_mod_depth_s = 0.12
    amp_mod_depth = 0.3
    mod_freq_factor = 0.65
    hF_enhancement = 0.12
    hF_decay_rate = 5.0
    fadeout_duration_s = 1.8
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Cosmic
    tail_duration_s = 4.5
    number_of_delays = 100
    base_amplitude = 0.35
    decay_factor = 0.94
    delay_start_s = 0.12
    delay_range_s = 1.2
    delay_mod_depth_s = 0.18
    amp_mod_depth = 0.4
    mod_freq_factor = 0.8
    hF_enhancement = 0.15
    hF_decay_rate = 6.0
    fadeout_duration_s = 2.5
    presetName$ = "Extreme"
else
    presetName$ = "Custom"
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# Pre-calculate delays for visualization
for k from 1 to min(number_of_delays, 100)
    echoDelay[k] = delay_start_s + delay_range_s * (k / number_of_delays) + delay_mod_depth_s * sin(k * 0.6)
    echoAmp[k] = base_amplitude * (decay_factor ^ k) * (0.8 + amp_mod_depth * sin(k * mod_freq_factor))
endfor

# Sample period
samplePeriod = 1 / sr

# === Info ===
writeInfoLine: "=== Smooth Cosmic Reverb ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Delays: ", number_of_delays
appendInfoLine: "Delay range: ", delay_start_s * 1000, " - ", (delay_start_s + delay_range_s) * 1000, " ms"
appendInfoLine: "Delay modulation: ±", delay_mod_depth_s * 1000, " ms"
appendInfoLine: "Amplitude modulation: ", amp_mod_depth
appendInfoLine: "HF enhancement: ", hF_enhancement, " (decay rate ", hF_decay_rate, ")"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

totalDur = originalDur + tail_duration_s

# Create silent tail
if numChannels = 2
    Create Sound from formula: "silent_tail", 2, 0, tail_duration_s, sr, "0"
else
    Create Sound from formula: "silent_tail", 1, 0, tail_duration_s, sr, "0"
endif
silentTail = selected("Sound")

# Concatenate
selectObject: original, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

origDur_str$ = string$(originalDur)
sp_str$ = string$(samplePeriod)
hf_str$ = string$(hF_enhancement)
hfRate_str$ = string$(hF_decay_rate)

if numChannels = 2
    # === STEREO PROCESSING ===
    appendInfoLine: "  Processing stereo..."
    
    # Extract channels
    selectObject: extendedSound
    Extract one channel: 1
    leftChannel = selected("Sound")
    
    selectObject: extendedSound
    Extract one channel: 2
    rightChannel = selected("Sound")
    
    # Process left channel
    selectObject: leftChannel
    Copy: "cosmic_left"
    cosmicLeft = selected("Sound")
    
    for k from 1 to number_of_delays
        delay = delay_start_s + delay_range_s * (k / number_of_delays) + delay_mod_depth_s * sin(k * 0.6)
        amp_mod = base_amplitude * (decay_factor ^ k) * (0.8 + amp_mod_depth * sin(k * mod_freq_factor))
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp_mod)
        
        selectObject: cosmicLeft
        
        if k mod 8 = 0
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.2*sin(x*40))"
        elsif k mod 12 = 0
            amp_mod2 = amp_mod * 0.7
            amp2_str$ = string$(amp_mod2)
            Formula: "self + " + amp2_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.15*sin(x*80))"
        elsif k mod 6 = 0
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.7 + 0.3*sin(4*pi*x))"
        else
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.9 + 0.1*sin(x*60))"
        endif
        
        if k mod 15 = 0
            Scale peak: 0.98
        endif
    endfor
    
    # Time-based rolloff
    Formula: "self * (0.9 + 0.1*(1 - x/" + origDur_str$ + "))"
    Scale peak: 0.98
    
    # Process right channel (different parameters)
    selectObject: rightChannel
    Copy: "cosmic_right"
    cosmicRight = selected("Sound")
    
    # Slightly different params for right
    delay_start_R = delay_start_s * 1.125
    delay_range_R = delay_range_s * 0.96
    delay_mod_R = delay_mod_depth_s * 0.875
    base_amp_R = base_amplitude * 0.91
    decay_R = decay_factor - 0.01
    
    for k from 1 to number_of_delays
        delay = delay_start_R + delay_range_R * (k / number_of_delays) + delay_mod_R * cos(k * 0.7)
        amp_mod = base_amp_R * (decay_R ^ k) * (0.75 + 0.25 * cos(k * 0.6))
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp_mod)
        
        selectObject: cosmicRight
        
        if k mod 7 = 0
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.18*cos(x*35))"
        elsif k mod 11 = 0
            amp_mod2 = amp_mod * 0.75
            amp2_str$ = string$(amp_mod2)
            Formula: "self + " + amp2_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.12*sin(x*70))"
        elsif k mod 5 = 0
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.65 + 0.35*cos(3*pi*x))"
        else
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.85 + 0.15*cos(x*55))"
        endif
        
        if k mod 18 = 0
            Scale peak: 0.98
        endif
    endfor
    
    Formula: "self * (0.88 + 0.12*(1 - x/" + origDur_str$ + "))"
    Scale peak: 0.98
    
    # Apply HF enhancement with decay
    selectObject: cosmicLeft
    Formula: "self + " + hf_str$ + " * (self - self(x - " + sp_str$ + ")) * exp(-" + hfRate_str$ + "*x/" + origDur_str$ + ")"
    
    selectObject: cosmicRight
    Formula: "self + " + hf_str$ + " * (self - self(x - " + sp_str$ + ")) * exp(-" + hfRate_str$ + "*x/" + origDur_str$ + ")"
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: cosmicLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: cosmicRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: cosmicLeft
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.98
    
    selectObject: cosmicRight
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    Scale peak: 0.98
    
    # Combine
    selectObject: cosmicLeft, cosmicRight
    Combine to stereo
    result = selected("Sound")
    Rename: originalName$ + "_cosmic_" + presetName$
    
    # Cleanup
    removeObject: leftChannel, rightChannel, cosmicLeft, cosmicRight, extendedSound

else
    # === MONO PROCESSING ===
    appendInfoLine: "  Processing mono..."
    
    selectObject: extendedSound
    Copy: "cosmic_mono"
    cosmicMono = selected("Sound")
    
    for k from 1 to number_of_delays
        delay = delay_start_s + delay_range_s * (k / number_of_delays) + delay_mod_depth_s * sin(k * 0.6)
        amp_mod = base_amplitude * (decay_factor ^ k) * (0.8 + amp_mod_depth * sin(k * mod_freq_factor))
        
        delay_str$ = string$(delay)
        amp_str$ = string$(amp_mod)
        
        selectObject: cosmicMono
        
        if k mod 8 = 0
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.2*sin(x*40))"
        elsif k mod 10 = 0
            amp_mod2 = amp_mod * 0.7
            amp2_str$ = string$(amp_mod2)
            Formula: "self + " + amp2_str$ + " * self(x - " + delay_str$ + ") * (1 + 0.15*sin(x*80))"
        else
            Formula: "self + " + amp_str$ + " * self(x - " + delay_str$ + ") * (0.9 + 0.1*sin(x*60))"
        endif
        
        if k mod 15 = 0
            Scale peak: 0.98
        endif
    endfor
    
    # Time-based rolloff
    Formula: "self * (0.9 + 0.1*(1 - x/" + origDur_str$ + "))"
    
    # HF enhancement with decay
    Formula: "self + " + hf_str$ + " * (self - self(x - " + sp_str$ + ")) * exp(-" + hfRate_str$ + "*x/" + origDur_str$ + ")"
    
    Scale peak: 0.98
    
    # Apply wet/dry
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        ext_str$ = string$(extendedSound)
        
        selectObject: cosmicMono
        Formula: "self * " + wet_str$ + " + object[" + ext_str$ + "] * " + dry_str$
    endif
    
    # Apply fadeout
    fade_start = totalDur - fadeout_duration_s
    fade_str$ = string$(fadeout_duration_s)
    start_str$ = string$(fade_start)
    
    selectObject: cosmicMono
    Formula: "if x > " + start_str$ + " then self * (0.5 + 0.5 * cos(pi * (x - " + start_str$ + ") / " + fade_str$ + ")) else self fi"
    
    Scale peak: 0.98
    Rename: originalName$ + "_cosmic_" + presetName$
    result = cosmicMono
    
    removeObject: extendedSound
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Smooth Cosmic Reverb: " + originalName$ + " (" + presetName$ + ")"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 1.4
    Select inner viewport: 0.6, 7.6, 0.7, 1.3
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Dry"
    
    # Result waveform
    Select outer viewport: 0, 8, 1.5, 2.3
    Select inner viewport: 0.6, 7.6, 1.6, 2.2
    selectObject: result
    Colour: "{0.5, 0.5, 0.7}"
    Draw: 0, originalDur, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Cosmic " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # Modulated delay pattern
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    maxDelayMs = (delay_start_s + delay_range_s + delay_mod_depth_s) * 1000 * 1.1
    maxAmp = base_amplitude * 1.2
    
    Axes: 0, maxDelayMs, 0, maxAmp
    Paint rectangle: "{0.95, 0.95, 0.98}", 0, maxDelayMs, 0, maxAmp
    
    # Draw linear reference line
    Colour: "{0.85, 0.85, 0.85}"
    Dotted line
    Draw line: delay_start_s * 1000, maxAmp * 0.9, (delay_start_s + delay_range_s) * 1000, maxAmp * 0.1
    Solid line
    
    # Draw modulated delays
    numShow = min(number_of_delays, 100)
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        amp = echoAmp[k]
        
        # Color by tremolo type
        if k mod 8 = 0
            col$ = "{0.8, 0.4, 0.4}"
        elsif k mod 12 = 0
            col$ = "{0.4, 0.8, 0.4}"
        elsif k mod 6 = 0
            col$ = "{0.4, 0.4, 0.8}"
        else
            col$ = "{0.6, 0.6, 0.7}"
        endif
        
        Colour: col$
        Paint circle (mm): col$, delayMs, amp, 1.2
    endfor
    
    # Draw sine wave showing modulation pattern
    Colour: "{0.7, 0.5, 0.7}"
    Line width: 1.5
    prevX = delay_start_s * 1000
    prevY = maxAmp * 0.5
    for k from 1 to numShow
        delayMs = echoDelay[k] * 1000
        # Show the sinusoidal modulation offset
        linDelay = (delay_start_s + delay_range_s * (k / number_of_delays)) * 1000
        modOffset = delay_mod_depth_s * sin(k * 0.6) * 1000
        yPos = maxAmp * 0.5 + modOffset * maxAmp / maxDelayMs * 5
        Draw line: prevX, prevY, delayMs, yPos
        prevX = delayMs
        prevY = yPos
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Delay (ms) — sinusoidally modulated"
    
    # Legend
    Font size: 5
    Colour: "{0.8, 0.4, 0.4}"
    Text: maxDelayMs * 0.75, "left", maxAmp * 0.95, "half", "● Fast tremolo (mod 8)"
    Colour: "{0.4, 0.8, 0.4}"
    Text: maxDelayMs * 0.75, "left", maxAmp * 0.85, "half", "● Faster (mod 12)"
    Colour: "{0.4, 0.4, 0.8}"
    Text: maxDelayMs * 0.75, "left", maxAmp * 0.75, "half", "● Slow pulse (mod 6)"
    Colour: "{0.6, 0.6, 0.7}"
    Text: maxDelayMs * 0.75, "left", maxAmp * 0.65, "half", "● Subtle (other)"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Delays: " + string$(number_of_delays) + " | Range: " + fixed$(delay_start_s * 1000, 0) + "-" + fixed$((delay_start_s + delay_range_s) * 1000, 0) + "ms | Mod: ±" + fixed$(delay_mod_depth_s * 1000, 0) + "ms | HF: " + fixed$(hF_enhancement, 2)
    
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