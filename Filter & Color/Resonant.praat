# ============================================================
# Praat AudioTools - Resonant.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Resonant delay feedback effect - creates echoes, reverb-like
#   textures, comb filtering, and metallic resonances through
#   iterative IIR comb filtering.
#
#   ALGORITHM NOTE:
#   Each "iteration" applies a single-pass IIR comb filter:
#     y[n] = x[n] + fb * y[n - D]
#   via Praat's in-place Formula:
#     self + fb * self[col - D]
#   where self[col-D] reads the OUTPUT value at the delayed
#   position (already computed in this pass). The loop applies
#   this filter N times in series, creating a cascade. The
#   single-pass impulse response is an exponentially-decaying
#   echo train at multiples of D samples; the cascade response
#   is the convolution of N such trains.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v1.2:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v1.1
#     for the same form parameters and same RNG state. Same
#     iterative IIR comb filter, same 11 presets with same values,
#     same wet-signal pre-normalization, same dry/wet mixing,
#     same final Scale peak.
#   - Modernized object reference syntax in the dry/wet mix
#     Formula: `Object_<id>(x)` -> `object(<id>, x)`. Both are
#     valid Praat; the new form is documented in current Praat
#     manuals while the old form is legacy. Cosmetic only.
#   - NEW: Show_spectrum form toggle (default OFF). v1.1 always
#     computed two `To Spectrum` calls (original + result) for
#     the visualization, even though those are short for finite
#     sounds. Default OFF keeps the wallclock minimal; turn ON
#     to see the spectrum overlay (now in Panel D when enabled).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle (preset, iterations,
#         feedback %, delay ms, dry/wet)
#       Panel A (left, headline): single-pass IIR comb impulse
#         response — REPLACES v1.1's misleading per-iteration
#         decay bar chart. v1.1 drew `feedback^i` at iteration i,
#         implying iteration i creates one echo at that amplitude.
#         The actual single-pass IIR produces an infinite
#         decaying echo train at multiples of D samples;
#         iterations cascade these trains. v1.2 shows the
#         physically-correct single-pass impulse response.
#       Panel B (right, headline): parameter report + algorithm
#         explanation in plain text
#       Panel C: zoom overlay (first 200 ms, gray = original,
#         blue = processed)
#       Panel D: result waveform (full file) OR result+original
#         spectrum overlay (when Show_spectrum = ON)
#       Panel E: light-grey summary stats bar (suite standard,
#         preserving v1.1's already-correct light-grey style at
#         the suite-standard viewport position)
#   - Dropped 3 decorative `comment === ... ===` form separators
#     and 3 inline parenthetical `comment (...)` clarifications
#     to keep the form compact (lesson from the rest of the
#     suite). The hint text is preserved by virtue of clear
#     field names.
# Changelog v1.1:
#   - Fixed zero output, restored original presets
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

form Resonant Effect v1.2
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
    positive Iterations 20
    real Feedback_amount 0.5
    positive Max_delay_samples 1000
    positive Scale_peak 0.99
    real Dry_wet_mix 0.7
    boolean Show_spectrum 0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS (Original values from v1.1, unchanged)
# ============================================================

if preset = 2
    # Light Echo (5 repeats)
    iterations = 5
    feedback_amount = 0.5
    max_delay_samples = 1000
    dry_wet_mix = 0.7
    presetName$ = "LightEcho"
elsif preset = 3
    # Medium Reverb (10 repeats)
    iterations = 10
    feedback_amount = 0.5
    max_delay_samples = 1500
    dry_wet_mix = 0.7
    presetName$ = "MediumReverb"
elsif preset = 4
    # Dense Space (20 repeats)
    iterations = 20
    feedback_amount = 0.5
    max_delay_samples = 2000
    dry_wet_mix = 0.7
    presetName$ = "DenseSpace"
elsif preset = 5
    # Extreme Chaos (30 repeats)
    iterations = 30
    feedback_amount = 0.6
    max_delay_samples = 2500
    dry_wet_mix = 0.7
    presetName$ = "ExtremeChaos"
elsif preset = 6
    # Subtle Texture (3 repeats)
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
writeInfoLine: "=== Resonant Effect v1.2 ==="
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
# PROCESS (Original algorithm — unchanged)
# ============================================================

appendInfoLine: "Processing..."

# Create working copy for wet signal
selectObject: soundID
wetID = Copy: "wet_processing"

# Generate single random delay
delay = randomInteger(1, max_delay_samples)
delay$ = string$(delay)
fb$ = string$(feedback_amount)

appendInfoLine: "Using delay: ", delay, " samples (", fixed$(delay / sampleRate * 1000, 2), " ms)"

# Convert delay to ms for visualization
delayMs = delay / sampleRate * 1000

# Apply iterative IIR comb filter (recursive in-place Formula).
# Each iteration: y[n] = x[n] + fb * y[n - D]
# (self[col-D] reads the OUTPUT already written this pass)
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
# v1.2 modernization: object(id, x) instead of Object_<id>(x).
# Both are valid Praat; the new form is documented in current manuals.
Formula: dryAmt$ + " * self + " + wetAmt$ + " * object(" + wetId$ + ", x)"

# Final scale
Scale peak: scale_peak

# Capture stats for visualization
selectObject: resultID
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    Black
    Plain line
    
    # ----------------------------------------------------------
    # Compute spectra ONLY if user opted in
    # ----------------------------------------------------------
    if show_spectrum
        selectObject: soundID
        origSpecID = To Spectrum: "yes"
        selectObject: resultID
        resSpecID = To Spectrum: "yes"
    endif
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##RESONANT EFFECT##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  " + string$(iterations) + " iter"
        ... + "  |  fb " + fixed$(feedback_amount * 100, 0) + "%"
        ... + "  |  delay " + fixed$(delayMs, 1) + " ms"
        ... + "  |  " + fixed$(dry_wet_mix * 100, 0) + "% wet"
    
    # ----------------------------------------------------------
    # PANEL A: SINGLE-PASS IIR COMB IMPULSE RESPONSE  (left, headline)
    # Shows the actual filter behaviour: an exponentially-decaying
    # echo train at multiples of D samples. REPLACES v1.1's
    # misleading per-iteration `feedback^i` bar chart, which
    # implied iteration i creates one echo of that amplitude.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Decide how many echoes to display (cap at 20 or when amp < 0.005)
    nEchoesDisplay = 20
    if feedback_amount > 0.01
        # Solve feedback^k < 0.005  ->  k > log(0.005) / log(feedback)
        kCutoff = ln(0.005) / ln(feedback_amount)
        if kCutoff < nEchoesDisplay
            nEchoesDisplay = ceiling(kCutoff)
        endif
    endif
    if nEchoesDisplay < 5
        nEchoesDisplay = 5
    endif
    
    # x-axis: time in ms, from 0 to nEchoesDisplay * delayMs (with margin)
    xAxisMax = (nEchoesDisplay + 0.5) * delayMs
    if xAxisMax < 10
        xAxisMax = 10
    endif
    
    Axes: 0, xAxisMax, 0, 1.15
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, xAxisMax, 0, 1.15
    
    # Reference grid
    Colour: "{0.88, 0.88, 0.92}"
    Line width: 1
    Dotted line
    Draw line: 0, 0.25, xAxisMax, 0.25
    Draw line: 0, 0.50, xAxisMax, 0.50
    Draw line: 0, 0.75, xAxisMax, 0.75
    Draw line: 0, 1.00, xAxisMax, 1.00
    Solid line
    
    # Initial impulse at t=0
    Colour: "{0.20, 0.45, 0.75}"
    Line width: 2.5
    Draw line: 0, 0, 0, 1.0
    
    # Echo train at k*delayMs with amplitude feedback^k
    Colour: "{0.85, 0.30, 0.30}"
    Line width: 2
    for k from 1 to nEchoesDisplay
        xt = k * delayMs
        if xt <= xAxisMax
            amp = feedback_amount ^ k
            if amp >= 0.005
                Draw line: xt, 0, xt, amp
                # Small filled circle on top
                Paint circle (mm): "{0.85, 0.30, 0.30}", xt, amp, 0.6
            endif
        endif
    endfor
    Line width: 1
    
    # Decay envelope curve (smooth exponential)
    Colour: "{0.55, 0.35, 0.75}"
    Line width: 1.5
    Dotted line
    envSteps = 60
    envPrevX = 0
    envPrevY = 1.0
    for es from 1 to envSteps
        envX = es / envSteps * xAxisMax
        # amp(t) = feedback^(t/delay)
        envY = feedback_amount ^ (envX / delayMs)
        Draw line: envPrevX, envPrevY, envX, envY
        envPrevX = envX
        envPrevY = envY
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (ms)"
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Filter:"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.86, "half", "y[n] = x[n] + fb \\.c y[n - D]"
    Text: 0.10, "left", 0.80, "half", "(applied " + string$(iterations) + " times in cascade)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.70, "half", "Comb parameters:"
    
    Font size: 11
    Colour: "{0.20, 0.50, 0.80}"
    Text: 0.10, "left", 0.62, "half", "Iter:     " + string$(iterations)
    Text: 0.10, "left", 0.55, "half", "Fb:       " + fixed$(feedback_amount * 100, 0) + "%"
    Text: 0.10, "left", 0.48, "half", "Delay:    " + string$(delay) + " samp"
    Text: 0.10, "left", 0.41, "half", "          (" + fixed$(delayMs, 1) + " ms)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.31, "half", "Mix:"
    
    Font size: 10
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.23, "half", "Dry:  " + fixed$(dryAmount * 100, 0) + "%"
    Text: 0.10, "left", 0.16, "half", "Wet:  " + fixed$(wetAmount * 100, 0) + "%"
    
    Font size: 7
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.07, "half", "Wet normalized to 0.99 before mix"
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Single-pass impulse response (one IIR comb cycle)"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 200 ms)
    # Gray = original, blue = processed.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.2
    if zoomDur > duration
        zoomDur = duration
    endif
    if zoomDur > finalDur
        zoomDur = finalDur
    endif
    
    selectObject: soundID
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: resultID
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
    selectObject: soundID
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Processed on top
    selectObject: resultID
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, blue = processed)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT WAVEFORM (FULL FILE) or SPECTRUM OVERLAY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    if show_spectrum
        # Spectrum overlay: original gray, processed blue
        Axes: 0, 5000, 0, 80
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 5000, 0, 80
        
        Colour: "{0.88, 0.88, 0.92}"
        Line width: 1
        Dotted line
        Draw line: 0, 20, 5000, 20
        Draw line: 0, 40, 5000, 40
        Draw line: 0, 60, 5000, 60
        Solid line
        
        selectObject: origSpecID
        Colour: "{0.70, 0.70, 0.70}"
        Line width: 1
        Draw: 0, 5000, 0, 80, "no"
        
        selectObject: resSpecID
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1.5
        Draw: 0, 5000, 0, 80, "no"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Spectrum overlay  (gray = original, blue = processed, 0-5 kHz)"
        Text left: "yes", "dB"
        Text bottom: "yes", "Frequency (Hz)"
    else
        # Result waveform (full file)
        selectObject: resultID
        out_peak_v = Get absolute extremum: 0, 0, "None"
        if out_peak_v < 0.001
            out_peak_v = 0.001
        endif
        out_amp = out_peak_v * 1.15
        
        Axes: 0, finalDur, -out_amp, out_amp
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -out_amp, out_amp
        Colour: "{0.82, 0.82, 0.82}"
        Draw line: 0, 0, finalDur, 0
        
        selectObject: resultID
        Colour: "{0.20, 0.50, 0.80}"
        Line width: 1
        Draw: 0, finalDur, -out_amp, out_amp, "no", "Curve"
        
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Processed waveform (full file)"
        Text left: "yes", "Amp"
        Text bottom: "yes", "Time (s)"
    endif
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if show_spectrum
        specStr$ = "shown"
    else
        specStr$ = "off"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + soundName$
        ... + "  |  Iter: " + string$(iterations)
        ... + "  |  Fb: " + fixed$(feedback_amount * 100, 0) + "%"
        ... + "  |  Delay: " + string$(delay) + " samp (" + fixed$(delayMs, 1) + " ms)"
        ... + "  |  Mix: " + fixed$(dryAmount * 100, 0) + "%/" + fixed$(wetAmount * 100, 0) + "% (dry/wet)"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Filter: y[n] = x[n] + fb \\.c y[n-D]   x " + string$(iterations) + " cascade"
        ... + "  |  In: " + fixed$(duration, 2) + " s"
        ... + "  |  Out: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
        ... + "  |  SR: " + string$(round(sampleRate)) + " Hz"
        ... + "  |  Spec: " + specStr$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    # Cleanup spectra if computed
    if show_spectrum
        removeObject: origSpecID, resSpecID
    endif
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

selectObject: resultID
