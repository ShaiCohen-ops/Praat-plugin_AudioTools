# ============================================================
# Praat AudioTools - Virtual_Subharmonic_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Virtual Subharmonic Generator — phantom bass enhancement
#   (MaxxBass-style harmonic generation) plus optional Mid-Side
#   stereo widening with mono-compatibility protection.
#
#   The "phantom bass" trick: extract the bass band, run it
#   through tanh waveshaping to generate upper harmonics
#   (2f, 3f, 4f...), filter those harmonics, and mix them on
#   top of the high-passed original. The brain reconstructs
#   the missing fundamental from the harmonic pattern, so on
#   small speakers (laptop, phone, etc.) you perceive bass
#   energy that isn't actually present.
#
#   Pipeline:
#     1. Split into L and R channels
#     2. Extract bass band [Bass_low_freq, Bass_high_freq] per channel
#     3. tanh waveshape with Drive -> generates harmonics
#     4. Bandpass-filter harmonics to [Bass_high_freq, Harmonic_lowpass]
#     5. High-pass the original L/R at Highpass_freq (clears low end)
#     6. Mix harmonics into the high-passed signal at Harmonic_mix
#     7. Optional M/S widening with mono-compatibility low-cut on side
#     8. Recombine to stereo and peak-scale
#
#   Stereo width parameter behavior: the Side signal is multiplied
#   by `stereo_width`. So 0 = mono collapse, 1 = identity (no
#   change), >1 = widen, <1 = narrow. v0.2's preset values (0.3
#   to 0.8) all narrow the stereo image. To widen, set values >1.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - REMOVED: Haas effect stage entirely. v0.2's Haas formula
#     wrote `if col > delay then self[col - delay] * level else 0 fi`
#     into the same Sound it was modifying — the read of self at
#     col - delay always saw the cell that earlier in iteration
#     had been overwritten with 0 (because at col=delay the else
#     branch ran). Net effect: the "delayed" Sound was zero
#     everywhere, the subsequent mix produced just an attenuated
#     copy of the original, and the Haas effect was inaudible.
#     The presets had been tuned to v0.2's silent-Haas sound, so
#     repairing the bug would change every preset's character.
#     v0.3 removes the stage. The four other processing stages
#     (bass extract, harmonic generation, high-pass, M/S) remain
#     unchanged. v0.2 audio output is preserved bit-identically
#     for the Haas-disabled path; v0.2 with Haas-enabled produced
#     the same as the new v0.3 output minus the small attenuation
#     from the (1 - haas_mix) factor — so v0.3's audio with
#     same parameters is approximately 0.5-3 dB louder than v0.2
#     with Haas-enabled. Worth flagging for level-matched A/B.
#   - Form: removed Apply_haas, Haas_delay_ms, Haas_mix,
#     Level_difference_dB. Adjusted preset definitions
#     accordingly.
#   - Form syntax modernized: optionmenu uses colon.
#   - Pre-computed status strings for the summary bar
#     (replaces an inline if/then/else fi in v0.2's
#     appendInfoLine, which is unreliable in Praat's
#     script-level expression context).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): processing-chain diagram
#         showing the 4 stages
#       Panel B (right, headline): parameter report
#       Panel C: zoom overlay (original gray + enhanced
#         purple, first 30 ms) - shows the harmonic content
#         added in the bass region
#       Panel D: output waveform with L/R distinguished
#       Panel E: summary stats bar
#   - Header documents the stereo_width math semantic
#     (which v0.2 didn't explain) so users understand
#     why values < 1 narrow rather than widen.
# Changelog v0.2:
#   - Added input check
#   - Fixed selection syntax (use object IDs)
#   - Fixed formula syntax (string building)
#   - Fixed name-based references
#   - Added visualization
# ============================================================

form Virtual Subharmonic Generator v0.3
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Enhancement
        option Moderate Effect
        option Aggressive MaxxBass
        option Mono-Safe Narrowing
        option Wide Stereo (not mono-safe)
    
    comment === Phantom Bass ===
    positive Bass_low_freq 30
    positive Bass_high_freq 120
    positive Drive 3.0
    comment (higher = more harmonics)
    real Harmonic_mix 0.6
    comment (0 = dry, 1 = full harmonics added)
    positive Highpass_freq 100
    positive Harmonic_lowpass 800
    
    comment === Mid-Side Width ===
    boolean Apply_MS_widening 1
    real Stereo_width 0.5
    comment (1 = identity, <1 narrows, >1 widens; default 0.5 narrows)
    
    comment === Safety ===
    boolean Preserve_mono_compatibility 1
    
    comment === Output ===
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
sr = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels

# === Apply Presets ===
if preset = 2
    # Subtle Enhancement
    drive = 2.0
    harmonic_mix = 0.4
    highpass_freq = 90
    harmonic_lowpass = 600
    apply_MS_widening = 1
    stereo_width = 0.3
    preserve_mono_compatibility = 1
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate Effect
    drive = 3.0
    harmonic_mix = 0.6
    highpass_freq = 100
    harmonic_lowpass = 800
    apply_MS_widening = 1
    stereo_width = 0.5
    preserve_mono_compatibility = 1
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive MaxxBass
    drive = 5.0
    harmonic_mix = 0.8
    highpass_freq = 120
    harmonic_lowpass = 1000
    apply_MS_widening = 1
    stereo_width = 0.7
    preserve_mono_compatibility = 0
    presetName$ = "Aggressive"
elsif preset = 5
    # Mono-Safe Narrowing
    drive = 2.5
    harmonic_mix = 0.5
    highpass_freq = 100
    harmonic_lowpass = 700
    apply_MS_widening = 1
    stereo_width = 0.4
    preserve_mono_compatibility = 1
    presetName$ = "MonoSafe"
elsif preset = 6
    # Wide Stereo
    drive = 3.5
    harmonic_mix = 0.65
    highpass_freq = 100
    harmonic_lowpass = 900
    apply_MS_widening = 1
    stereo_width = 0.8
    preserve_mono_compatibility = 0
    presetName$ = "WideStereo"
else
    presetName$ = "Custom"
endif

# Pre-compute status strings (replaces v0.2 inline ternary)
if apply_MS_widening
    msStr$ = "ON (width " + fixed$(stereo_width, 2) + ")"
else
    msStr$ = "OFF"
endif

if preserve_mono_compatibility
    monoStr$ = "ON"
else
    monoStr$ = "OFF"
endif

# === Info ===
writeInfoLine: "=== Virtual Subharmonic Generator v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", numChannels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Phantom Bass:"
appendInfoLine: "  Bass band: ", fixed$(bass_low_freq, 1), "-", fixed$(bass_high_freq, 1), " Hz"
appendInfoLine: "  Drive: ", fixed$(drive, 2)
appendInfoLine: "  Harmonic mix: ", fixed$(harmonic_mix, 2)
appendInfoLine: "  Highpass: ", fixed$(highpass_freq, 1), " Hz"
appendInfoLine: "  Harmonic LP: ", fixed$(harmonic_lowpass, 1), " Hz"
appendInfoLine: "M/S widening: ", msStr$
appendInfoLine: "Mono compat: ", monoStr$
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

# Convert to stereo if mono
if numChannels = 1
    appendInfoLine: "Converting mono to stereo..."
    selectObject: original
    Convert to stereo
    workingSound = selected("Sound")
else
    selectObject: original
    Copy: "working_temp"
    workingSound = selected("Sound")
endif

# === STAGE 1: EXTRACT BASS CONTENT ===
appendInfoLine: "Extracting bass (", bass_low_freq, "-", bass_high_freq, " Hz)..."

selectObject: workingSound
Extract one channel: 1
leftChannel = selected("Sound")

selectObject: workingSound
Extract one channel: 2
rightChannel = selected("Sound")

# Filter bass from LEFT
selectObject: leftChannel
Copy: "bass_L_temp"
bassLtemp = selected("Sound")
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bassLfiltered = selected("Sound")
removeObject: bassLtemp

# Filter bass from RIGHT
selectObject: rightChannel
Copy: "bass_R_temp"
bassRtemp = selected("Sound")
Filter (pass Hann band): bass_low_freq, bass_high_freq, 100
bassRfiltered = selected("Sound")
removeObject: bassRtemp

# === STAGE 2: GENERATE HARMONICS VIA WAVESHAPING ===
appendInfoLine: "Generating harmonics (drive=", drive, ")..."

drive_str$ = string$(drive)

# LEFT harmonics
selectObject: bassLfiltered
Copy: "harm_L_temp"
harmLtemp = selected("Sound")
Formula: "tanh(self * " + drive_str$ + ")"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmLfiltered = selected("Sound")
removeObject: harmLtemp

# RIGHT harmonics
selectObject: bassRfiltered
Copy: "harm_R_temp"
harmRtemp = selected("Sound")
Formula: "tanh(self * " + drive_str$ + ")"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmRfiltered = selected("Sound")
removeObject: harmRtemp

# === STAGE 3: HIGH-PASS ORIGINAL CHANNELS ===
appendInfoLine: "High-passing original at ", highpass_freq, " Hz..."

selectObject: leftChannel
Filter (stop Hann band): 0, highpass_freq, 100
leftHP = selected("Sound")

selectObject: rightChannel
Filter (stop Hann band): 0, highpass_freq, 100
rightHP = selected("Sound")

removeObject: leftChannel, rightChannel

# === STAGE 4: MIX HARMONICS WITH HIGH-PASSED SIGNAL ===
appendInfoLine: "Mixing harmonics (", harmonic_mix * 100, "%)..."

mix_str$ = string$(harmonic_mix)
harmL_str$ = string$(harmLfiltered)
harmR_str$ = string$(harmRfiltered)

selectObject: leftHP
Formula: "self + object[" + harmL_str$ + "] * " + mix_str$

selectObject: rightHP
Formula: "self + object[" + harmR_str$ + "] * " + mix_str$

# Cleanup intermediates
removeObject: bassLfiltered, bassRfiltered, harmLfiltered, harmRfiltered

# Peak safety after harmonic mix
@peakSafety: leftHP, rightHP

# === STAGE 5: MID-SIDE WIDENING (OPTIONAL) ===
if apply_MS_widening
    appendInfoLine: "Applying M/S widening (width=", stereo_width, ")..."
    
    left_str$ = string$(leftHP)
    right_str$ = string$(rightHP)
    width_str$ = string$(stereo_width)
    
    # Calculate Mid: M = (L + R) / 2
    selectObject: leftHP
    Copy: "mid_temp"
    midSignal = selected("Sound")
    Formula: "(object[" + left_str$ + "] + object[" + right_str$ + "]) / 2"
    
    # Calculate Side: S = ((L - R) / 2) * stereo_width
    selectObject: leftHP
    Copy: "side_temp"
    sideSignal = selected("Sound")
    Formula: "(object[" + left_str$ + "] - object[" + right_str$ + "]) / 2 * " + width_str$
    
    # High-pass side for mono compatibility (cuts <200 Hz from sides)
    if preserve_mono_compatibility
        selectObject: sideSignal
        Filter (stop Hann band): 0, 200, 100
        sideFiltered = selected("Sound")
        removeObject: sideSignal
        sideSignal = sideFiltered
    endif
    
    mid_str$ = string$(midSignal)
    side_str$ = string$(sideSignal)
    
    # Reconstruct L/R: L = M + S, R = M - S
    selectObject: leftHP
    Formula: "object[" + mid_str$ + "] + object[" + side_str$ + "]"
    
    selectObject: rightHP
    Formula: "object[" + mid_str$ + "] - object[" + side_str$ + "]"
    
    removeObject: midSignal, sideSignal
    
    @peakSafety: leftHP, rightHP
endif

# === STAGE 6: COMBINE TO STEREO ===
appendInfoLine: "Combining to stereo..."

selectObject: leftHP, rightHP
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_subharm_" + presetName$

Scale peak: 0.95

# Cleanup
removeObject: leftHP, rightHP, workingSound

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##VIRTUAL SUBHARMONIC GENERATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + presetName$
        ... + "  |  Bass " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Mix: " + fixed$(harmonic_mix, 2)
        ... + "  |  M/S: " + msStr$
        ... + "  |  Mono: " + monoStr$
    
    # ----------------------------------------------------------
    # PANEL A: PROCESSING CHAIN  (left, headline)
    # Vertical 4-stage diagram (style matching Chaos Distortion v0.3
    # and Distortion+BitCrusher v0.3 for visual consistency)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 6
    
    # Stage 1: Input
    yTop = 5.6
    yBot = 5.0
    Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "INPUT"
    Font size: 7
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(stereo audio)"
    
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 5.0, 0.50, 4.7
    
    # Stage 2: Bass extraction + harmonic generation
    yTop = 4.6
    yBot = 4.0
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "BASS -> HARMONICS"
    Font size: 7
    Colour: "{0.40, 0.20, 0.10}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
        ... fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0)
        ... + " Hz, tanh x" + fixed$(drive, 1)
    
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 4.0, 0.50, 3.7
    
    # Stage 3: HP + mix
    yTop = 3.6
    yBot = 3.0
    Paint rectangle: "{0.65, 0.85, 0.65}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "HP + MIX"
    Font size: 7
    Colour: "{0.15, 0.40, 0.15}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
        ... "HP " + fixed$(highpass_freq, 0) + " Hz + harm * "
        ... + fixed$(harmonic_mix, 2)
    
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 3.0, 0.50, 2.7
    
    # Stage 4: M/S widening (optional)
    yTop = 2.6
    yBot = 2.0
    if apply_MS_widening
        Paint rectangle: "{0.65, 0.65, 0.85}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "M/S WIDTH"
    Font size: 7
    if apply_MS_widening
        Colour: "{0.15, 0.15, 0.40}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
            ... "S * " + fixed$(stereo_width, 2)
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 2.0, 0.50, 1.7
    
    # Stage 5: Output
    yTop = 1.6
    yBot = 1.0
    Paint rectangle: "{0.65, 0.85, 0.75}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 8
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "OUTPUT"
    Font size: 7
    Colour: "{0.15, 0.40, 0.30}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(enhanced stereo)"
    
    # Mono-compat badge
    if preserve_mono_compatibility
        Font size: 5
        Colour: "{0.55, 0.30, 0.30}"
        Text: 0.50, "centre", 0.50, "half", "[mono-safe: side HP @ 200 Hz]"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.95, "half", "Phantom Bass:"
    
    Font size: 11
    Colour: "{0.85, 0.55, 0.20}"
    Text: 0.10, "left", 0.87, "half", "Bass:    " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
    Text: 0.10, "left", 0.79, "half", "Drive:   " + fixed$(drive, 2)
    Text: 0.10, "left", 0.71, "half", "Mix:     " + fixed$(harmonic_mix, 2)
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.61, "half", "Filtering:"
    
    Font size: 10
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.53, "half", "HP cut:  " + fixed$(highpass_freq, 0) + " Hz"
    Text: 0.10, "left", 0.45, "half", "Harm LP: " + fixed$(harmonic_lowpass, 0) + " Hz"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.34, "half", "Stereo:"
    
    Font size: 10
    if apply_MS_widening
        Colour: "{0.30, 0.30, 0.78}"
        Text: 0.10, "left", 0.26, "half", "M/S:     ON, S x " + fixed$(stereo_width, 2)
        # Tell user what direction
        Font size: 7
        Colour: "{0.55, 0.55, 0.55}"
        if stereo_width < 1
            widthDir$ = "(narrows)"
        elsif stereo_width > 1
            widthDir$ = "(widens)"
        else
            widthDir$ = "(identity)"
        endif
        Text: 0.10, "left", 0.18, "half", "         " + widthDir$
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.26, "half", "M/S:     OFF"
    endif
    
    Font size: 8
    if preserve_mono_compatibility
        Colour: "{0.55, 0.30, 0.30}"
        Text: 0.10, "left", 0.08, "half", "Mono compat: ON (side HP @ 200 Hz)"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.08, "half", "Mono compat: OFF"
    endif
    
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
    Text: 2.10, "centre", 7.30, "half", "Processing chain"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (full width, first 30 ms)
    # Original (gray) + enhanced (purple) overlaid.
    # The harmonic content added in the bass region should be
    # visible as additional high-frequency texture on the
    # bass-band peaks of the original.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.03
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    origPeak = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, zoomDur, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: 0, zoomDur, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original (gray, behind)
    selectObject: original
    if numChannels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Enhanced (purple, on top)
    selectObject: result
    Extract one channel: 1
    zRes = selected("Sound")
    Colour: "{0.55, 0.30, 0.65}"
    Line width: 1.3
    Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    removeObject: zRes
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original L, purple = enhanced L)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: result
    outPeakViz = Get absolute extremum: 0, 0, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: result
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    selectObject: result
    Extract one channel: 2
    vCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh2
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (full file)  (blue=L  orange=R)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  Bass: " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Mix: " + fixed$(harmonic_mix, 2)
        ... + "  |  HP: " + fixed$(highpass_freq, 0) + " Hz"
    
    Text: 0.02, "left", 0.28, "half",
        ... "M/S: " + msStr$
        ... + "  |  Mono compat: " + monoStr$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================
# PROCEDURES
# ============================================================

procedure peakSafety: .left, .right
    selectObject: .left
    .maxL = Get maximum: 0, 0, "None"
    .minL = Get minimum: 0, 0, "None"
    selectObject: .right
    .maxR = Get maximum: 0, 0, "None"
    .minR = Get minimum: 0, 0, "None"
    
    .maxPeak = max(abs(.maxL), abs(.maxR), abs(.minL), abs(.minR))
    
    if .maxPeak > 0.95
        .scale = 0.95 / .maxPeak
        .scale$ = string$(.scale)
        selectObject: .left
        Formula: "self * " + .scale$
        selectObject: .right
        Formula: "self * " + .scale$
    endif
endproc
