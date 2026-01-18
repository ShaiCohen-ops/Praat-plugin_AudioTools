# ============================================================
# Praat AudioTools - Resonant.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2025) - Fixed zero output, restored original presets
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Resonant delay feedback effect - creates echoes, reverb-like
#   textures, comb filtering, and metallic resonances through
#   iterative delayed feedback.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Resonant Effect v1.1
    optionmenu Preset: 1
        option Custom
        option Light Echo (5 repeats)
        option Medium Reverb (10 repeats)
        option Dense Space (20 repeats)
        option Extreme Chaos (30 repeats)
        option Subtle Texture (3 repeats)
        option Comb Filter (Metallic)
        option Flanger-like
        option Slapback
        option Cathedral
        option Small Room
        option Tape Echo
    comment === Delay Parameters ===
    positive Iterations 20
    comment (Number of feedback iterations)
    real Feedback_amount 0.5
    comment (Feedback gain 0-0.9 range)
    positive Max_delay_samples 1000
    comment (Maximum random delay in samples)
    comment === Output ===
    positive Scale_peak 0.99
    real Dry_wet_mix 0.7
    comment (0 = dry only, 1 = wet only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS (Original values restored)
# ============================================================

if preset = 2
    # Light Echo (5 repeats) - ORIGINAL
    iterations = 5
    feedback_amount = 0.5
    max_delay_samples = 1000
    dry_wet_mix = 0.7
    presetName$ = "LightEcho"
elsif preset = 3
    # Medium Reverb (10 repeats) - ORIGINAL
    iterations = 10
    feedback_amount = 0.5
    max_delay_samples = 1500
    dry_wet_mix = 0.7
    presetName$ = "MediumReverb"
elsif preset = 4
    # Dense Space (20 repeats) - ORIGINAL
    iterations = 20
    feedback_amount = 0.5
    max_delay_samples = 2000
    dry_wet_mix = 0.7
    presetName$ = "DenseSpace"
elsif preset = 5
    # Extreme Chaos (30 repeats) - ORIGINAL
    iterations = 30
    feedback_amount = 0.6
    max_delay_samples = 2500
    dry_wet_mix = 0.7
    presetName$ = "ExtremeChaos"
elsif preset = 6
    # Subtle Texture (3 repeats) - ORIGINAL
    iterations = 3
    feedback_amount = 0.4
    max_delay_samples = 800
    dry_wet_mix = 0.7
    presetName$ = "SubtleTexture"
elsif preset = 7
    # Comb Filter (Metallic)
    iterations = 20
    feedback_amount = 0.6
    max_delay_samples = 50
    dry_wet_mix = 0.6
    presetName$ = "CombFilter"
elsif preset = 8
    # Flanger-like
    iterations = 10
    feedback_amount = 0.5
    max_delay_samples = 30
    dry_wet_mix = 0.5
    presetName$ = "Flanger"
elsif preset = 9
    # Slapback
    iterations = 3
    feedback_amount = 0.4
    max_delay_samples = 2000
    dry_wet_mix = 0.5
    presetName$ = "Slapback"
elsif preset = 10
    # Cathedral
    iterations = 25
    feedback_amount = 0.55
    max_delay_samples = 3000
    dry_wet_mix = 0.7
    presetName$ = "Cathedral"
elsif preset = 11
    # Small Room
    iterations = 8
    feedback_amount = 0.45
    max_delay_samples = 500
    dry_wet_mix = 0.5
    presetName$ = "SmallRoom"
elsif preset = 12
    # Tape Echo
    iterations = 5
    feedback_amount = 0.5
    max_delay_samples = 3000
    dry_wet_mix = 0.5
    presetName$ = "TapeEcho"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================

selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
numSamples = Get number of samples
numChannels = Get number of channels

# Clamp feedback to safe range
if feedback_amount > 0.9
    feedback_amount = 0.9
endif
if feedback_amount < 0
    feedback_amount = 0
endif

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif

# Convert delay samples to ms for display
maxDelayMs = max_delay_samples / sampleRate * 1000

clearinfo
writeInfoLine: "=== Resonant Effect v1.1 ==="
appendInfoLine: "Input: ", soundName$
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: "Sample rate: ", sampleRate, " Hz"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Iterations: ", iterations
appendInfoLine: "Feedback: ", fixed$(feedback_amount * 100, 0), "%"
appendInfoLine: "Max delay: ", max_delay_samples, " samples (", fixed$(maxDelayMs, 1), " ms)"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: ""

# ============================================================
# PROCESS (Original algorithm)
# ============================================================

appendInfoLine: "Processing..."

# Create working copy for wet signal
selectObject: soundID
wetID = Copy: "wet_processing"

# Generate single random delay (like original)
delay = randomInteger(1, max_delay_samples)
delay$ = string$(delay)
fb$ = string$(feedback_amount)

appendInfoLine: "Using delay: ", delay, " samples (", fixed$(delay / sampleRate * 1000, 2), " ms)"

# Apply iterative feedback (original algorithm)
for i from 1 to iterations
    selectObject: wetID
    Formula: "self + " + fb$ + " * self[col - " + delay$ + "]"
endfor

# Scale wet signal to prevent clipping before mix
selectObject: wetID
wetMax = Get maximum: 0, 0, "Sinc70"
wetMin = Get minimum: 0, 0, "Sinc70"
wetPeak = max(abs(wetMax), abs(wetMin))

if wetPeak > 0.01
    # Normalize wet signal
    Scale peak: 0.99
else
    appendInfoLine: "WARNING: Wet signal is very quiet"
endif

# Create final mix
selectObject: soundID
resultID = Copy: soundName$ + "_" + presetName$

# Mix dry and wet
dryAmount = 1 - dry_wet_mix
wetAmount = dry_wet_mix
dryAmt$ = string$(dryAmount)
wetAmt$ = string$(wetAmount)
wetId$ = string$(wetID)

selectObject: resultID
Formula: dryAmt$ + " * self + " + wetAmt$ + " * Object_" + wetId$ + "(x)"

# Final scale
Scale peak: scale_peak

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Resonant Effect: " + soundName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 8, 0.6, 2.2
    Select inner viewport: 0.6, 7.6, 0.75, 2.05
    
    selectObject: soundID
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 9
    Text top: "no", "Original"
    Text left: "yes", "Amp"
    
    # Processed waveform
    Select outer viewport: 0, 8, 2.3, 3.9
    Select inner viewport: 0.6, 7.6, 2.45, 3.75
    
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Processed (" + presetName$ + ")"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # Impulse response visualization (feedback decay)
    Select outer viewport: 0, 4, 4.1, 5.8
    Select inner viewport: 0.6, 3.6, 4.3, 5.6
    
    Axes: 0, iterations + 1, 0, 1.1
    
    # Draw feedback decay curve
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 2
    
    for i from 1 to iterations
        # Amplitude at iteration i = feedback^i
        amp = feedback_amount ^ i
        
        # Draw bar
        Paint rectangle: "{0.8, 0.4, 0.4}", i - 0.35, i + 0.35, 0, amp
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Echo amplitude decay"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Iteration"
    
    # Spectrum comparison
    Select outer viewport: 4, 8, 4.1, 5.8
    Select inner viewport: 4.6, 7.6, 4.3, 5.6
    
    selectObject: soundID
    origSpecID = To Spectrum: "yes"
    
    selectObject: resultID
    resSpecID = To Spectrum: "yes"
    
    selectObject: origSpecID
    Colour: "{0.7, 0.7, 0.7}"
    Line width: 1
    Draw: 0, 5000, 0, 80, "no"
    
    selectObject: resSpecID
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 2
    Draw: 0, 5000, 0, 80, "no"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Spectrum (gray=orig, blue=processed)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"
    
    removeObject: origSpecID, resSpecID
    
    # Info panel
    Select outer viewport: 0, 8, 5.9, 6.3
    Select inner viewport: 0.5, 7.7, 5.95, 6.25
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.01, "left", 0.5, "half", "Iterations: " + string$(iterations)
    Text: 0.18, "left", 0.5, "half", "Feedback: " + fixed$(feedback_amount * 100, 0) + "%"
    Text: 0.38, "left", 0.5, "half", "Delay: " + string$(delay) + " samp (" + fixed$(delay / sampleRate * 1000, 1) + " ms)"
    Text: 0.68, "left", 0.5, "half", "Mix: " + fixed$(dryAmount * 100, 0) + "% dry / " + fixed$(wetAmount * 100, 0) + "% wet"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================

removeObject: wetID

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Created: ", soundName$, "_", presetName$

if play_result
    selectObject: resultID
    Play
endif

selectObject: soundID

