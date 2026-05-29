# ============================================================
# Praat AudioTools - Convolve_Bursts_Taps.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025) - Real pulse shaping
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bursts & Taps Convolution - creates impulse response with
#   sparse discrete taps (distinct echoes) plus clustered
#   burst patterns (Gaussian-distributed impulse clouds).
#
#   Pulse shaping:
#     Pulse_amplitude  - burst-cloud level relative to the sparse taps
#     Pulse_width_s    - grain length (only active when Pulse_tone_Hz > 0)
#     Pulse_tone_Hz    - 0 = broadband clicks; > 0 = Hann-windowed tone
#                        grains at this carrier frequency
#
# Changelog v0.3:
#   - Replaced the To Sound (pulse train) IR with explicit pulse shaping.
#     The old Pulse_amplitude/width/period fed the pulse-train adaptation
#     factor / adaptation time / interpolation depth, so width did nothing
#     and amplitude was normalized away. Now: Pulse_amplitude sets the
#     burst/tap balance, and Pulse_tone_Hz turns impulses into tonal grains
#     of Pulse_width_s. Pulse_tone_Hz = 0 reproduces the original clicks.
# ============================================================

form Bursts and Taps Convolution
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Subtle Bursts
        option Medium Bursts
        option Heavy Bursts
        option Extreme Bursts
    
    comment === Duration ===
    positive IR_duration_s 1.8
    
    comment === Sparse Taps (discrete echoes) ===
    positive Tap_1_time_s 0.15
    positive Tap_2_time_s 1.20
    
    comment === Burst Clusters ===
    natural Number_of_bursts 3
    natural Points_per_burst 10
    positive Burst_stddev_s 0.035
    comment (Gaussian spread of each cluster)
    positive Burst_margin_s 0.3
    comment (minimum distance from edges)
    
    comment === Pulse Shaping ===
    positive Pulse_amplitude 1.0
    comment (burst-cloud level relative to the sparse taps)
    positive Pulse_width_s 0.02
    comment (grain length; only used when Pulse_tone_Hz > 0)
    real Pulse_tone_Hz 0
    comment (0 = broadband clicks, >0 = tonal grains at this carrier Hz)
    
    comment === Mix ===
    real Wet_dry_percent 60
    comment (0 = dry only, 100 = wet only)
    
    comment === Output ===
    boolean Keep_IR 0
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
# --- FIX: Get channel count ---
numChans = Get number of channels
sr = Get sampling frequency

# === Apply Presets ===
if preset = 2
    # Subtle Bursts
    iR_duration_s = 1.5
    tap_1_time_s = 0.12
    tap_2_time_s = 1.0
    number_of_bursts = 2
    points_per_burst = 6
    burst_stddev_s = 0.025
    burst_margin_s = 0.25
    pulse_width_s = 0.018
    pulse_tone_Hz = 0
    presetName$ = "Subtle"
elsif preset = 3
    # Medium Bursts
    iR_duration_s = 1.8
    tap_1_time_s = 0.15
    tap_2_time_s = 1.20
    number_of_bursts = 3
    points_per_burst = 10
    burst_stddev_s = 0.035
    burst_margin_s = 0.3
    pulse_width_s = 0.02
    pulse_tone_Hz = 0
    presetName$ = "Medium"
elsif preset = 4
    # Heavy Bursts
    iR_duration_s = 2.5
    tap_1_time_s = 0.18
    tap_2_time_s = 1.80
    number_of_bursts = 5
    points_per_burst = 15
    burst_stddev_s = 0.050
    burst_margin_s = 0.35
    pulse_width_s = 0.025
    pulse_tone_Hz = 0
    presetName$ = "Heavy"
elsif preset = 5
    # Extreme Bursts
    iR_duration_s = 3.5
    tap_1_time_s = 0.20
    tap_2_time_s = 2.80
    number_of_bursts = 8
    points_per_burst = 25
    burst_stddev_s = 0.080
    burst_margin_s = 0.4
    pulse_width_s = 0.03
    pulse_tone_Hz = 0
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

# Store burst centers for visualization
for b from 1 to number_of_bursts
    burstCenter[b] = randomUniform(burst_margin_s, iR_duration_s - burst_margin_s)
endfor

# === Info ===
writeInfoLine: "=== Bursts & Taps Convolution ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Channels: ", numChans
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Sparse taps: ", fixed$(tap_1_time_s, 2), "s, ", fixed$(tap_2_time_s, 2), "s"
appendInfoLine: "Bursts: ", number_of_bursts, " x ", points_per_burst, " points"
appendInfoLine: "Burst spread (stddev): ", fixed$(burst_stddev_s, 3), " s"
appendInfoLine: "IR duration: ", fixed$(iR_duration_s, 1), " s"
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""
appendInfoLine: "Burst centers:"
for b from 1 to number_of_bursts
    appendInfoLine: "  Burst ", b, ": ", fixed$(burstCenter[b], 3), " s"
endfor
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# === BUILD IMPULSE TIMES (taps + Gaussian bursts) ===
appendInfoLine: "  Creating point pattern..."

# Sparse taps -> their own train (reference level)
Create empty PointProcess: "pp_taps", 0, iR_duration_s
ppTaps = selected("PointProcess")
Add point: tap_1_time_s
Add point: tap_2_time_s

# Burst clusters -> separate train (scaled by Pulse_amplitude relative to taps)
Create empty PointProcess: "pp_bursts", 0, iR_duration_s
ppBursts = selected("PointProcess")
totalPoints = 2
burstPoints = 0
for b from 1 to number_of_bursts
    center = burstCenter[b]
    for i from 1 to points_per_burst
        t = center + randomGauss(0, burst_stddev_s)
        if t > 0 and t < iR_duration_s
            selectObject: ppBursts
            Add point: t
            totalPoints = totalPoints + 1
            burstPoints = burstPoints + 1
        endif
    endfor
endfor

appendInfoLine: "  Total impulse points: ", totalPoints

# === CONVERT POINTS TO IMPULSE TRAINS ===
appendInfoLine: "  Building impulse trains..."

selectObject: ppTaps
To Sound (pulse train): sr, 1.0, 0.001, 2000
impTaps = selected("Sound")
Scale peak: 1.0

if burstPoints > 0
    selectObject: ppBursts
    To Sound (pulse train): sr, 1.0, 0.001, 2000
    impBursts = selected("Sound")
    Scale peak: 1.0
endif

removeObject: ppTaps, ppBursts

# === SHAPE EACH IMPULSE ===
# tone = 0 -> broadband single-sample clicks (original character)
# tone > 0 -> each impulse becomes a Hann-windowed tone grain of width seconds
if pulse_tone_Hz > 0
    appendInfoLine: "  Shaping pulses into tone grains..."
    kernelDur = pulse_width_s
    kc = kernelDur / 2
    tone$ = string$(pulse_tone_Hz)
    kc$ = string$(kc)
    kdur$ = string$(kernelDur)
    Create Sound from formula: "pulse_kernel", 1, 0, kernelDur, sr, "(0.5 - 0.5 * cos(2*pi*x/" + kdur$ + ")) * cos(2*pi*" + tone$ + "*(x - " + kc$ + "))"
    kernel = selected("Sound")

    selectObject: impTaps, kernel
    Convolve: "sum", "zero"
    convTaps = selected("Sound")
    Extract part: kc, kc + iR_duration_s, "rectangular", 1, "no"
    irTaps = selected("Sound")
    removeObject: convTaps, impTaps

    if burstPoints > 0
        selectObject: impBursts, kernel
        Convolve: "sum", "zero"
        convBursts = selected("Sound")
        Extract part: kc, kc + iR_duration_s, "rectangular", 1, "no"
        irBursts = selected("Sound")
        removeObject: convBursts, impBursts
    endif
    removeObject: kernel
else
    irTaps = impTaps
    if burstPoints > 0
        irBursts = impBursts
    endif
endif

# === COMBINE TAPS + (Pulse_amplitude-scaled) BURSTS ===
selectObject: irTaps
if burstPoints > 0
    amp$ = string$(pulse_amplitude)
    irBursts$ = string$(irBursts)
    Formula: "self + " + amp$ + " * object[" + irBursts$ + "]"
    removeObject: irBursts
endif
Scale peak: 0.9
Rename: "ir_" + presetName$
irSound = selected("Sound")

# === CONVOLVE ===
appendInfoLine: "  Convolving..."

selectObject: original, irSound
Convolve: "sum", "zero"
wetSound = selected("Sound")

# Trim to reasonable length
selectObject: wetSound
totalDur = originalDur + iR_duration_s
Extract part: 0, totalDur, "rectangular", 1, "no"
wetTrimmed = selected("Sound")
removeObject: wetSound

# === APPLY WET/DRY MIX ===
if dry_level > 0
    appendInfoLine: "  Mixing wet/dry..."
    
    # Extend dry signal to match wet length
    selectObject: original
    Copy: "dry_extended"
    dryExtended = selected("Sound")
    
    # Create silence for extension
    # --- FIX: Use numChans variable here ---
    Create Sound from formula: "silence_ext", numChans, 0, iR_duration_s, sr, "0"
    silenceExt = selected("Sound")
    
    selectObject: dryExtended, silenceExt
    Concatenate
    dryFull = selected("Sound")
    removeObject: silenceExt, dryExtended
    
    # Mix
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    dry_full_str$ = string$(dryFull)
    
    selectObject: wetTrimmed
    Formula: "self * " + wet_str$ + " + object[" + dry_full_str$ + "] * " + dry_str$
    
    removeObject: dryFull
endif

selectObject: wetTrimmed
Scale peak: 0.95
Rename: originalName$ + "_bursts_" + presetName$
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
    Text: 0.5, "centre", 0.5, "half", "Bursts & Taps: " + originalName$ + " (" + presetName$ + ")"
    
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
    Colour: "{0.6, 0.7, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Wet " + fixed$(wet_dry_percent, 0) + "%"
    Text bottom: "yes", "Time (s)"
    
    # IR structure diagram
    Select outer viewport: 0, 8, 2.5, 4.0
    Select inner viewport: 0.6, 7.6, 2.6, 3.9
    
    Axes: 0, iR_duration_s, 0, 1.2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, iR_duration_s, 0, 1.2
    
    # Draw sparse taps
    Colour: "{0.8, 0.4, 0.4}"
    Line width: 2
    Draw line: tap_1_time_s, 0, tap_1_time_s, 1.0
    Draw line: tap_2_time_s, 0, tap_2_time_s, 1.0
    Paint circle: "{0.8, 0.4, 0.4}", tap_1_time_s, 1.0, 0.015 * iR_duration_s
    Paint circle: "{0.8, 0.4, 0.4}", tap_2_time_s, 1.0, 0.015 * iR_duration_s
    Line width: 1
    
    # Draw burst clusters
    Colour: "{0.4, 0.6, 0.8}"
    for b from 1 to number_of_bursts
        center = burstCenter[b]
        
        # Draw Gaussian envelope hint
        Dotted line
        for i from -20 to 20
            x1 = center + (i - 1) * burst_stddev_s * 0.2
            x2 = center + i * burst_stddev_s * 0.2
            y1 = 0.7 * exp(-((i-1)*0.2)^2 / 2)
            y2 = 0.7 * exp(-(i*0.2)^2 / 2)
            if x1 >= 0 and x2 <= iR_duration_s
                Draw line: x1, y1, x2, y2
            endif
        endfor
        Solid line
        
        # Draw center marker
        Paint circle: "{0.3, 0.5, 0.7}", center, 0.7, 0.012 * iR_duration_s
        
        # Label
        Font size: 5
        Text: center, "centre", 0.85, "half", "B" + string$(b)
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "IR Structure"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Font size: 5
    Colour: "{0.8, 0.4, 0.4}"
    Text: iR_duration_s * 0.85, "centre", 1.1, "half", "Sparse taps"
    Colour: "{0.4, 0.6, 0.8}"
    Text: iR_duration_s * 0.85, "centre", 1.0, "half", "Burst clusters"
    
    # Parameters
    Select outer viewport: 0, 8, 4.1, 4.5
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Bursts: " + string$(number_of_bursts) + " x " + string$(points_per_burst) + " pts | Spread: " + fixed$(burst_stddev_s * 1000, 0) + "ms | Taps: " + fixed$(tap_1_time_s * 1000, 0) + "ms, " + fixed$(tap_2_time_s * 1000, 0) + "ms"
    
    Font size: 10
    Colour: "Black"
endif

# === Cleanup ===
if keep_IR
    selectObject: irSound
    Rename: "IR_bursts_" + presetName$
else
    removeObject: irSound
endif


# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
if keep_IR
    appendInfoLine: "IR kept: IR_bursts_", presetName$
endif

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result