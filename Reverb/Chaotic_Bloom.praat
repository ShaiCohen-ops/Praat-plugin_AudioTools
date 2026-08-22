# ============================================================
# Praat AudioTools - Chaotic_Bloom.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5.1 (2026)
# v0.5.1 (2026): Shared left panel-label rails and user-approved Summary geometry; DSP/analysis unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaotic Bloom - stochastic diffusion reverb using Poisson
#   processes. Creates organic, evolving reverb tails by
#   convolving input with randomly-distributed impulse clouds.
#   Envelope includes exponential decay with chirping shimmer.
#   Stereo mode uses decorrelated L/R impulse patterns with
#   sinusoidal panning for spatial movement.
#
# Algorithmic notes:
#   - IR generation: Poisson point process -> pulse train ->
#     envelope (sin^2 fade x exponential decay x chirp shimmer).
#   - The shimmer chirp `sin(2*pi*x*200*(x-xmin)/(xmax-xmin))`
#     has phase = 2*pi*200*t^2/T, so its instantaneous
#     frequency sweeps from 0 Hz at t=0 to 400 Hz at t=T=6s
#     (left channel; right channel uses 180 -> 360 Hz). This
#     is a fixed character of the IR.
#   - Stereo "pan crossfade": each channel time-modulates a
#     crossfade between dry and convolved signals at an
#     independent LFO rate (2 Hz left, 1.8 Hz right). Creates
#     spatial wandering.
#   - Two-stage mix: pan-crossfade output is then mixed with
#     original dry via wet_dry_percent. Both mix levels remain
#     user-controllable.
#   - RNG (Poisson) is unseeded; same Praat session = same IR.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline
#   Analysis-Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.4:
#   - Public form and output naming are unchanged.
#   - Private zero-based work copy fixes non-zero source xmin.
#   - Fixed 3+ channel input: silent tail now matches the source
#     channel count; non-stereo multichannel sources retain all channels.
#   - Clarified actual Praat semantics of Pulse_amplitude / Pulse_width /
#     Pulse_period: pulse-train adaptation factor, adaptation time, and
#     sinc interpolation depth respectively.
#   - Pulse_period is converted internally to an integer interpolation
#     depth, as required by the pulse-train synthesis parameter.
#   - Explicit row/column cross-object reads preserve channel routing
#     in the shared-IR multichannel path.
#   - Safe peak normalization skips digital silence.
#   - Visualization uses the zero-based source and reports multichannel
#     shared-IR mode accurately.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters AND same Praat RNG state.
#     Same Poisson IR generation, same chirp envelope math
#     (0->400 Hz left, 0->360 Hz right), same stereo crossfade
#     architecture (2 Hz left, 1.8 Hz right), same two-stage
#     mix (pan crossfade then wet/dry), same Scale peak.
#     All 4 presets (+ Custom) preserved with same values.
#   - Form syntax modernized: `optionmenu Preset:` with colon.
#   - Dropped 8 decorative form lines (6 `comment === ... ===`
#     section dividers, 1 instructional, 2 inline parenthetical
#     hints). Form went from ~14 effective rows to 10.
#   - Visualization rewritten to suite 8x8 standard (v0.2 was
#     8x3.8 with title + 2 stacked waveforms + IR+parameters
#     side-by-side):
#       Title bar + metadata subtitle (preset, density, tail,
#         pulse width, conv mix, wet/dry %)
#       Panel A (left, headline): IR waveform (first 3 s of
#         the 6 s IR) — PRESERVED v0.2's signature visual,
#         showing the chirp-modulated Poisson cloud
#       Panel B (right, headline): parameter report — algorithm
#         explanation (Poisson + chirp envelope + pan crossfade),
#         parameters, stereo crossfade rates (when stereo)
#       Panel C: zoom overlay (first 500 ms, gray = original,
#         purple = processed) — shows the bloom emerging
#       Panel D: full waveform comparison (gray = original,
#         purple = processed, SHARED y-axis) — fixes v0.2's
#         independent auto-scaling
#       Panel E: light-grey summary stats bar (suite standard)
# Changelog v0.2:
#   - Fixed selection syntax (object IDs)
#   - Fixed name-based references
#   - Added wet/dry mix control
#   - Added visualization
#   - Added info output
# ============================================================

form Chaotic Bloom v0.5.1
    optionmenu Preset: 1
        option Default (balanced)
        option Dense Bloom
        option Sparse Bloom
        option Wide Stereo Shimmer
        option Custom (use settings below)
    positive Tail_duration_s 2.0
    positive Poisson_density 3000
    positive Pulse_amplitude 1.0
    positive Pulse_width 0.04
    positive Pulse_period 2500
    positive Convolution_mix 0.4
    real Wet_dry_percent 50
    positive Scale_peak 0.85
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

# Private zero-based work copy; never shift the caller's original Sound.
selectObject: original
workSource = Copy: "chaotic_bloom_work"
selectObject: workSource
workStart = Get start time
if workStart <> 0
    Shift times by: -workStart
endif

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    tail_duration_s = 2.0
    poisson_density = 3000
    pulse_amplitude = 1.0
    pulse_width = 0.04
    pulse_period = 2500
    convolution_mix = 0.4
    presetName$ = "Default"
elsif preset = 2
    # Dense Bloom
    tail_duration_s = 3.0
    poisson_density = 4500
    pulse_amplitude = 1.1
    pulse_width = 0.05
    pulse_period = 2200
    convolution_mix = 0.5
    presetName$ = "DenseBloom"
elsif preset = 3
    # Sparse Bloom
    tail_duration_s = 1.5
    poisson_density = 1800
    pulse_amplitude = 0.9
    pulse_width = 0.03
    pulse_period = 2800
    convolution_mix = 0.3
    presetName$ = "SparseBloom"
elsif preset = 4
    # Wide Stereo Shimmer
    tail_duration_s = 2.5
    poisson_density = 3200
    pulse_amplitude = 1.0
    pulse_width = 0.035
    pulse_period = 2600
    convolution_mix = 0.35
    presetName$ = "WideStereo"
else
    presetName$ = "Custom"
endif

# PointProcess: To Sound (pulse train) interprets the public Pulse_* fields as:
#   Pulse_amplitude -> adaptation factor
#   Pulse_width     -> adaptation time (s)
#   Pulse_period    -> sinc interpolation depth (samples)
# Keep the public names unchanged for caller compatibility.
pulseInterpolationDepth = round(pulse_period)
if pulseInterpolationDepth < 1
    pulseInterpolationDepth = 1
endif
rightInterpolationDepth = round(pulseInterpolationDepth * 1.04)
if rightInterpolationDepth < 1
    rightInterpolationDepth = 1
endif

# Clamp wet/dry
if wet_dry_percent < 0
    wet_dry_percent = 0
elsif wet_dry_percent > 100
    wet_dry_percent = 100
endif

wet_level = wet_dry_percent / 100
dry_level = 1 - wet_level

# === Info ===
writeInfoLine: "=== Chaotic Bloom v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(originalDur, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Poisson density: ", poisson_density, " impulses/s"
appendInfoLine: "Tail duration: ", tail_duration_s, " s"
appendInfoLine: "Pulse-train adaptation factor: ", pulse_amplitude
appendInfoLine: "Pulse-train adaptation time: ", pulse_width, " s"
appendInfoLine: "Pulse-train interpolation depth: ", pulseInterpolationDepth, " samples"
appendInfoLine: "Convolution mix: ", convolution_mix
appendInfoLine: "Wet/Dry: ", wet_dry_percent, "%"
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

# IR duration (longer than tail for Poisson to fill)
irDuration = 6

# Create extended sound with tail
totalDur = originalDur + tail_duration_s

Create Sound from formula: "silent_tail", numChannels, 0, tail_duration_s, sr, "0"
silentTail = selected("Sound")

# workSource is older than silentTail, so object-list order is dry then tail.
selectObject: workSource, silentTail
Concatenate
extendedSound = selected("Sound")
removeObject: silentTail

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
    
    # === LEFT CHANNEL IR ===
    appendInfoLine: "  Creating left IR..."
    Create Poisson process: "chaos_L", 0, irDuration, poisson_density
    poissonL = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulseInterpolationDepth
    irSoundL = selected("Sound")
    
    # Apply envelope: sin² fade × exponential decay × shimmer
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))
    
    # Convolve left
    selectObject: leftChannel, irSoundL
    Convolve: "sum", "zero"
    convL = selected("Sound")
    
    mix_str$ = string$(convolution_mix)
    Formula: "self * " + mix_str$
    
    # === RIGHT CHANNEL IR (different parameters for decorrelation) ===
    appendInfoLine: "  Creating right IR..."
    Create Poisson process: "chaos_R", 0, irDuration, poisson_density * 1.07
    poissonR = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width * 0.875, rightInterpolationDepth
    irSoundR = selected("Sound")
    
    # Slightly different envelope for decorrelation
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 75^(-(x-xmin)/(xmax-xmin)) * (1 + 0.75*sin(2*pi*x*180*(x-xmin)/(xmax-xmin)))
    
    # Convolve right
    selectObject: rightChannel, irSoundR
    Convolve: "sum", "zero"
    convR = selected("Sound")
    
    mix_r_str$ = string$(convolution_mix * 0.95)
    Formula: "self * " + mix_r_str$
    
    # === PANNING MODULATION ===
    appendInfoLine: "  Applying stereo panning..."
    
    # Left channel panning
    selectObject: leftChannel
    Copy: "L_panned"
    lPanned = selected("Sound")
    Formula: ~ self * (0.5 + 0.5*sin(2*pi*(x-xmin)*2))
    
    selectObject: convL
    Copy: "convL_panned"
    convLPanned = selected("Sound")
    Formula: ~ self * (0.5 - 0.5*sin(2*pi*(x-xmin)*2))
    
    # Right channel panning
    selectObject: rightChannel
    Copy: "R_panned"
    rPanned = selected("Sound")
    Formula: ~ self * (0.5 - 0.5*sin(2*pi*(x-xmin)*1.8))
    
    selectObject: convR
    Copy: "convR_panned"
    convRPanned = selected("Sound")
    Formula: ~ self * (0.5 + 0.5*sin(2*pi*(x-xmin)*1.8))
    
    # === MIX FINAL LEFT ===
    lPanned_str$ = string$(lPanned)
    convLPanned_str$ = string$(convLPanned)
    
    selectObject: lPanned
    Formula: "self + object[" + convLPanned_str$ + "]"
    finalLeft = lPanned
    
    # === MIX FINAL RIGHT ===
    rPanned_str$ = string$(rPanned)
    convRPanned_str$ = string$(convRPanned)
    
    selectObject: rPanned
    Formula: "self + object[" + convRPanned_str$ + "]"
    finalRight = rPanned
    
    # === APPLY WET/DRY ===
    if dry_level > 0
        wet_str$ = string$(wet_level)
        dry_str$ = string$(dry_level)
        left_str$ = string$(leftChannel)
        right_str$ = string$(rightChannel)
        
        selectObject: finalLeft
        Formula: "self * " + wet_str$ + " + object[" + left_str$ + "] * " + dry_str$
        
        selectObject: finalRight
        Formula: "self * " + wet_str$ + " + object[" + right_str$ + "] * " + dry_str$
    endif
    
    # === COMBINE TO STEREO ===
    selectObject: finalLeft, finalRight
    Combine to stereo
    result = selected("Sound")
    selectObject: result
    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0
        Scale peak: scale_peak
    endif
    Rename: originalName$ + "_bloom_" + presetName$
    
    # Store IR for visualization
    irForViz = irSoundL
    
    # Cleanup
    removeObject: poissonL, poissonR
    removeObject: irSoundR
    removeObject: leftChannel, rightChannel
    removeObject: convL, convR
    removeObject: convLPanned, convRPanned
    removeObject: finalLeft, finalRight
    removeObject: extendedSound

else
    # === MONO / MULTICHANNEL SHARED-IR PROCESSING ===
    if numChannels = 1
        appendInfoLine: "  Processing mono..."
    else
        appendInfoLine: "  Processing ", numChannels, "-channel shared-IR mode..."
    endif
    
    # Create IR
    Create Poisson process: "chaos_mono", 0, irDuration, poisson_density
    poissonMono = selected("PointProcess")
    
    To Sound (pulse train): sr, pulse_amplitude, pulse_width, pulseInterpolationDepth
    irSound = selected("Sound")
    
    # Apply envelope
    Formula: ~ self * (sin(pi*(x-xmin)/(xmax-xmin))^2) * 80^(-(x-xmin)/(xmax-xmin)) * (1 + 0.8*sin(2*pi*x*200*(x-xmin)/(xmax-xmin)))
    
    # Convolve
    selectObject: extendedSound, irSound
    Convolve: "sum", "zero"
    convMono = selected("Sound")
    
    mix_str$ = string$(convolution_mix)
    Formula: "self * " + mix_str$
    
    # Mix with dry
    ext_str$ = string$(extendedSound)
    conv_str$ = string$(convMono)
    
    selectObject: extendedSound
    Copy: "result_temp"
    resultTemp = selected("Sound")
    
    wet_str$ = string$(wet_level)
    dry_str$ = string$(dry_level)
    
    Formula: "self * " + dry_str$ + " + object[" + conv_str$ + ", row, col] * " + wet_str$

    resultPeak = Get absolute extremum: 0, 0, "None"
    if resultPeak > 0
        Scale peak: scale_peak
    endif
    Rename: originalName$ + "_bloom_" + presetName$
    result = selected("Sound")
    
    # Store IR for visualization
    irForViz = irSound
    
    # Cleanup
    removeObject: poissonMono, convMono, extendedSound
endif

# Capture stats for visualization
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
resultNumCh = Get number of channels

# Compute actual chirp frequency endpoints (for the parameter report)
chirpEndL = 2 * 200
chirpEndR = 2 * 180

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all

    # Shared left panel-label rail.
    labelX = -0.035
    labelFont = 7

    Black
    Plain line
    
    # Mono copies of original and result for waveform display
    selectObject: workSource
    if numChannels > 1
        vizOrig = Convert to mono
    else
        vizOrig = Copy: "viz_orig"
    endif
    
    selectObject: result
    if resultNumCh > 1
        vizProc = Convert to mono
    else
        vizProc = Copy: "viz_proc"
    endif
    
    # Compute SHARED y-axis from BOTH dry and wet
    selectObject: vizOrig
    oPeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizProc
    pPeak = Get absolute extremum: 0, 0, "None"
    sharedPeak = oPeak
    if pPeak > sharedPeak
        sharedPeak = pPeak
    endif
    if sharedPeak < 0.001
        sharedPeak = 0.001
    endif
    sharedAmp = sharedPeak * 1.15
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##CHAOTIC BLOOM##" + " | v0.5.1"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  Poisson " + fixed$(poisson_density, 0) + "/s"
        ... + "  |  tail " + fixed$(tail_duration_s, 2) + " s"
        ... + "  |  pulse w " + fixed$(pulse_width, 3)
        ... + "  |  conv " + fixed$(convolution_mix, 2)
        ... + "  |  " + fixed$(wet_dry_percent, 0) + "% wet"
    
    # ----------------------------------------------------------
    # PANEL A: IR WAVEFORM  (left, headline)
    # First 3 s of the 6 s IR — PRESERVED v0.2's signature
    # visual showing chirp-modulated Poisson cloud.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    irDispDur = 3
    if irDispDur > irDuration
        irDispDur = irDuration
    endif
    
    selectObject: irForViz
    ir_peak = Get absolute extremum: 0, irDispDur, "None"
    if ir_peak < 0.001
        ir_peak = 0.001
    endif
    ir_amp = ir_peak * 1.15
    
    Axes: 0, irDispDur, -ir_amp, ir_amp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, irDispDur, -ir_amp, ir_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, irDispDur, 0
    
    selectObject: irForViz
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Draw: 0, irDispDur, -ir_amp, ir_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Select inner viewport: 0.20, 0.48, 0.95, 4.40
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "IR amp"
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    Axes: 0, irDispDur, -ir_amp, ir_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.94, "half", "Algorithm:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.88, "half", "Poisson process -> pulse train -> envelope:"
    Text: 0.10, "left", 0.83, "half", "  sin^2 fade \\.c exp decay \\.c chirp shimmer"
    Text: 0.10, "left", 0.78, "half", "then Convolve with input."
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.70, "half", "IR parameters:"
    
    Font size: 7
    Colour: "{0.55, 0.35, 0.78}"
    Text: 0.10, "left", 0.63, "half", "Density: " + fixed$(poisson_density, 0) + " imp/s"
    Text: 0.10, "left", 0.56, "half", "Pulse:   w " + fixed$(pulse_width, 3) + " | T " + fixed$(pulse_period, 0)
    Text: 0.10, "left", 0.49, "half", "Duration: " + fixed$(irDuration, 1) + " s (IR)"
    
    if numChannels = 2
        Font size: 7
        Colour: "{0.30, 0.55, 0.30}"
        Text: 0.10, "left", 0.42, "half", "L chirp: 0 -> " + fixed$(chirpEndL, 0) + " Hz over IR"
        Text: 0.10, "left", 0.37, "half", "R chirp: 0 -> " + fixed$(chirpEndR, 0) + " Hz over IR"
    else
        Font size: 7
        Colour: "{0.30, 0.55, 0.30}"
        Text: 0.10, "left", 0.42, "half", "Chirp: 0 -> " + fixed$(chirpEndL, 0) + " Hz over IR"
    endif
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.30, "half", "Mix:"
    
    Font size: 7
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.23, "half", "Conv mix: " + fixed$(convolution_mix, 2)
    Text: 0.10, "left", 0.16, "half", "Wet/Dry:  " + fixed$(wet_dry_percent, 0) + "% wet"
    Text: 0.10, "left", 0.09, "half", "Tail:     " + fixed$(tail_duration_s, 2) + " s"
    
    if numChannels = 2
        Font size: 7
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.05, "left", 0.02, "half", "Stereo pan crossfade: 2.0 Hz L, 1.8 Hz R"
    elsif numChannels = 1
        Font size: 7
        Colour: "{0.30, 0.55, 0.30}"
        Text: 0.05, "left", 0.02, "half", "Mono: no pan crossfade"
    else
        Font size: 7
        Colour: "{0.30, 0.55, 0.30}"
        Text: 0.05, "left", 0.02, "half", "Multichannel: shared IR, no pan crossfade"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0.60, 7.70, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Impulse response (first " + fixed$(irDispDur, 1) + " s of " + fixed$(irDuration, 1) + " s)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 500 ms)
    # Gray = original, purple = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    zoomDur = 0.5
    if zoomDur > originalDur
        zoomDur = originalDur
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    selectObject: vizOrig
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: vizProc
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Processed on top
    selectObject: vizProc
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, purple = processed)"
    Select inner viewport: 0.20, 0.48, 4.75, 5.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    Axes: 0, zoomDur, -z_amp, z_amp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: FULL WAVEFORM COMPARISON  (overlaid, SHARED y-axis)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -sharedAmp, sharedAmp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Mark the dry-vs-tail boundary
    if originalDur < finalDur
        Colour: "{0.85, 0.50, 0.20}"
        Line width: 1
        Dotted line
        Draw line: originalDur, -sharedAmp, originalDur, sharedAmp
        Solid line
        Font size: 6
        Text: originalDur, "left", sharedAmp * 0.85, "half", "  tail"
    endif
    
    # Original behind
    selectObject: vizOrig
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    # Processed on top
    selectObject: vizProc
    Colour: "{0.55, 0.35, 0.78}"
    Line width: 1
    Draw: 0, finalDur, -sharedAmp, sharedAmp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Full output (gray = original, purple = processed, shared y-axis)"
    Select inner viewport: 0.20, 0.48, 5.69, 6.48
    Axes: 0, 1, 0, 1
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", labelFont, "90", "Amp"
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    Axes: 0, finalDur, -sharedAmp, sharedAmp
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.70, 7.70
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if numChannels = 2
        stereoStr$ = "stereo pan crossfade (2.0/1.8 Hz)"
    elsif numChannels = 1
        stereoStr$ = "mono"
    else
        stereoStr$ = string$(numChannels) + "ch shared IR"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Font size: 7
    Colour: "Black"
    Font size: 7
    Text: 0.02, "left", 0.72, "half", "##Summary##"
    Font size: 6
    Text: 0.02, "left", 0.48, "half", 
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Poisson: " + fixed$(poisson_density, 0) + "/s"
        ... + "  |  Pulse train: adapt " + fixed$(pulse_amplitude, 2) + " | t " + fixed$(pulse_width, 3) + " | depth " + string$(pulseInterpolationDepth)
        ... + "  |  IR: " + fixed$(irDuration, 1) + " s"
        ... + "  |  Tail: " + fixed$(tail_duration_s, 2) + " s"
    
    Font size: 6
    Text: 0.02, "left", 0.24, "half", 
        ... "Conv mix: " + fixed$(convolution_mix, 2)
        ... + "  |  Wet/Dry: " + fixed$(wet_dry_percent, 0) + "\%  "
        ... + "  |  Mode: " + stereoStr$
        ... + "  |  In: " + fixed$(originalDur, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    
    Select inner viewport: 0.60, 7.70, 6.77, 7.63
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box

    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup viz objects
    removeObject: vizOrig, vizProc, irForViz

    # Restore full-page viewport before leaving visualization.
    Select outer viewport: 0, 8, 0, 7.80
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# If no visualization, still cleanup IR
if draw_visualization = 0
    removeObject: irForViz
endif

removeObject: workSource

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
