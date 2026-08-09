# ============================================================
# Praat AudioTools - Formula_Audio_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Formula Audio Manipulation - multi-layer modulation combining
#   complex amplitude modulation, pitch modulation via PSOLA,
#   and ring modulation. Creates evolving textures from subtle
#   to chaotic while preserving the source channel count.
#
# Changelog v0.4:
#   - Preserves the original number of channels.
#   - Preserves the original Sound time domain (xmin/xmax).
#   - AM depth now has literal 0..1 meaning:
#       0 = no amplitude modulation, 1 = full envelope depth.
#   - Complexity 2 now responds correctly to Modulation_depth.
#   - Pitch modulation preserves the detected source F0 contour
#     instead of replacing it with a contour around one median F0.
#   - Pitch modulation is symmetric in musical interval space.
#   - If no usable pitch is detected, only the pitch stage is
#     skipped; AM and ring modulation still run.
#   - Pitch control rate is fixed at 100 Hz and includes endTime.
#   - Adds parameter validation and sampling-safe pitch limits.
#   - Ring modulation works directly on every source channel.
#   - Final peak handling is attenuation-only.
#   - Visualization uses mono analysis views only where required,
#     explicit normalized axes, and a Nyquist-safe spectrogram limit.
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
sound_name$ = selected$("Sound")

selectObject: original
startTime = Get start time
endTime = Get end time
duration = endTime - startTime
sampling_rate = Get sampling frequency
numChan = Get number of channels

# === Form ===
form Formula Audio Manipulation v0.4
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

# === Validate Parameters ===
if base_frequency < 0
    exitScript: "Base_frequency must be zero or greater."
endif
if modulation_depth < 0 or modulation_depth > 1
    exitScript: "Modulation_depth must be between 0 and 1."
endif
if complexity_level < 1 or complexity_level > 3
    exitScript: "Complexity_level must be 1, 2, or 3."
endif
if pitch_mod_rate < 0
    exitScript: "Pitch_mod_rate must be zero or greater."
endif
if pitch_mod_depth < 0 or pitch_mod_depth > 1
    exitScript: "Pitch_mod_depth must be between 0 and 1."
endif
if ring_mod_frequency < 0
    exitScript: "Ring_mod_frequency must be zero or greater."
endif
if ring_mod_frequency >= sampling_rate / 2
    exitScript: "Ring_mod_frequency must be below Nyquist (" + fixed$(sampling_rate / 2, 1) + " Hz)."
endif
if ring_mod_depth < 0 or ring_mod_depth > 1
    exitScript: "Ring_mod_depth must be between 0 and 1."
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
writeInfoLine: "=== Formula Audio Manipulation v0.4 ==="
appendInfoLine: "Source: ", sound_name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels preserved: ", numChan
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

# Build the envelope on the exact sample grid of the source.
selectObject: original
if numChan > 1
    am_envelope = Extract one channel: 1
else
    am_envelope = Copy: "am_envelope_source"
endif
selectObject: am_envelope
Rename: "am_envelope"

bf = base_frequency
md = modulation_depth
t0 = startTime

if complexity_level = 1
    # Simple nested oscillator. The outer 1-md + md*shape mapping means
    # md=0 gives a flat unity envelope.
    Formula: ~ 1 - md + md * (0.5 + 0.5 * sin(2*pi*bf*(x-t0) * (1 + md*0.6*sin(2*pi*2*(x-t0)))))

elsif complexity_level = 2
    # Multiple competing oscillators (golden ratio, e).
    Formula: ~ 1 - md + md * (0.5 + 0.5 * (
        ... sin(2*pi*bf*(x-t0) * (1 + 0.4*sin(2*pi*1.5*(x-t0)))) +
        ... 0.6*sin(2*pi*bf*1.618*(x-t0) * (1 + 0.5*sin(2*pi*2.8*(x-t0)))) +
        ... 0.4*sin(2*pi*bf*2.718*(x-t0) * (1 + 0.6*sin(2*pi*0.9*(x-t0))))
        ... ) / 2.0)

else
    # Complex nested modulation.
    Formula: ~ 1 - md + md * (0.5 + 0.5 * (
        ... sin(2*pi*bf*(x-t0) * (1 + md*0.7*sin(2*pi*1.4*(x-t0) + 2.5*sin(2*pi*0.4*(x-t0))))) +
        ... 0.8*sin(2*pi*bf*1.618*(x-t0) * (1 + md*0.6*sin(2*pi*2.5*(x-t0) + 1.5*sin(2*pi*0.7*(x-t0))))) +
        ... 0.5*sin(2*pi*bf*2.414*(x-t0) * (1 + md*0.8*sin(2*pi*1.1*(x-t0) + 2.0*sin(2*pi*0.3*(x-t0)))))
        ... ) / 2.3)
endif

# ===================================================================
# APPLY AMPLITUDE MODULATION TO ALL CHANNELS
# ===================================================================

appendInfoLine: "Applying AM..."

selectObject: original
sound_mod = Copy: sound_name$ + "_modulated"

# Explicitly read row 1 of the mono envelope for every source channel.
Formula: "self * object['am_envelope:0', 1, col]"

# ===================================================================
# PITCH MODULATION (optional)
# ===================================================================

pitchApplied = 0
pitchSkipped = 0
limitedPitchPoints = 0

if apply_pitch_modulation
    appendInfoLine: "Applying pitch modulation..."

    # Analyse a mono reference from the AM-processed signal.
    selectObject: sound_mod
    if numChan > 1
        pitchAnalysisMono = Convert to mono
    else
        pitchAnalysisMono = Copy: sound_name$ + "_pitch_analysis"
    endif

    pitchFloor = 40
    pitchCeiling = min(1200, 0.45 * sampling_rate)
    if pitchCeiling <= pitchFloor
        removeObject: pitchAnalysisMono
        exitScript: "Sampling rate is too low for the pitch-analysis settings."
    endif

    selectObject: pitchAnalysisMono
    pitch_obj = To Pitch: 0.005, pitchFloor, pitchCeiling

    selectObject: pitch_obj
    medianF0 = Get quantile: 0, 0, 0.5, "Hertz"

    if medianF0 = undefined
        appendInfoLine: "  No usable pitch detected: pitch stage skipped."
        pitchSkipped = 1
        removeObject: pitch_obj, pitchAnalysisMono
    else
        appendInfoLine: "  Median detected F0: ", fixed$(medianF0, 1), " Hz"

        # Keep the old depth scale perceptually recognizable:
        # depth 0.4 had a +40% upper excursion; now the corresponding
        # musical interval is mirrored symmetrically downward.
        pmd = pitch_mod_depth
        pitchDepthSemitones = 12 * ln(1 + pmd) / ln(2)
        pmr = pitch_mod_rate

        Create PitchTier: "pitch_mod", startTime, endTime
        pitchtier_new = selected("PitchTier")

        controlStep = 0.01
        nSteps = ceiling(duration / controlStep)
        voicedPitchPoints = 0
        targetMinHz = 20
        targetMaxHz = 0.45 * sampling_rate

        for i from 0 to nSteps
            if i = nSteps
                t = endTime
            else
                t = min(endTime, startTime + i * controlStep)
            endif

            selectObject: pitch_obj
            sourceF0 = Get value at time: t, "Hertz", "Linear"

            if sourceF0 <> undefined and sourceF0 > 0
                trel = t - startTime

                # Layered modulation normalized approximately to -1..+1.
                mod1 = sin(2*pi*pmr*trel)
                mod2 = 0.5 * sin(2*pi*pmr*1.7*trel + 0.5)
                mod3 = 0.3 * sin(2*pi*pmr*0.6*trel + 1.2)
                modShape = (mod1 + mod2 + mod3) / 1.8

                semitoneShift = pitchDepthSemitones * modShape
                newF0 = sourceF0 * (2 ^ (semitoneShift / 12))

                if newF0 < targetMinHz
                    newF0 = targetMinHz
                    limitedPitchPoints += 1
                elsif newF0 > targetMaxHz
                    newF0 = targetMaxHz
                    limitedPitchPoints += 1
                endif

                selectObject: pitchtier_new
                Add point: t, newF0
                voicedPitchPoints += 1
            endif
        endfor

        if voicedPitchPoints = 0
            appendInfoLine: "  No usable pitch control points: pitch stage skipped."
            pitchSkipped = 1
            removeObject: pitchtier_new, pitch_obj, pitchAnalysisMono
        else
            appendInfoLine: "  Pitch control points: ", voicedPitchPoints
            if limitedPitchPoints > 0
                appendInfoLine: "  Sampling-safe pitch limits applied: ", limitedPitchPoints, " point(s)"
            endif

            # Zeroed output container with the exact original channel layout,
            # domain and sample grid.
            selectObject: sound_mod
            pitchedResult = Copy: sound_name$ + "_pitch_mod"
            Formula: ~ 0

            # Apply the same target contour independently to each channel.
            for ch from 1 to numChan
                selectObject: sound_mod
                if numChan = 1
                    channelWork = Copy: sound_name$ + "_pitch_ch1"
                else
                    channelWork = Extract one channel: ch
                    Rename: sound_name$ + "_pitch_ch" + string$(ch)
                endif

                selectObject: channelWork
                channelManip = To Manipulation: 0.005, pitchFloor, pitchCeiling

                selectObject: pitchtier_new
                plusObject: channelManip
                Replace pitch tier

                selectObject: channelManip
                channelRes = Get resynthesis (overlap-add)

                selectObject: pitchedResult
                Formula (part): startTime, endTime, ch, ch, "object['channelRes:0', 1, col]"

                removeObject: channelManip, channelWork, channelRes
            endfor

            removeObject: sound_mod, pitchtier_new, pitch_obj, pitchAnalysisMono
            sound_mod = pitchedResult
            pitchApplied = 1
        endif
    endif
endif

# ===================================================================
# RING MODULATION (optional)
# ===================================================================

if apply_ring_modulation
    appendInfoLine: "Applying ring modulation..."

    rmf = ring_mod_frequency
    rmd = ring_mod_depth
    t0 = startTime

    # Dry/wet ring modulation directly on every channel.
    # rmd=0 leaves the signal unchanged; rmd=1 is full bipolar ring modulation.
    selectObject: sound_mod
    Formula: ~ self * (1 - rmd + rmd * sin(2*pi*rmf*(x-t0)))
endif

# ===================================================================
# FINAL PROCESSING
# ===================================================================

selectObject: sound_mod
Rename: sound_name$ + "_formula_" + presetName$

finalPeak = Get absolute extremum: 0, 0, "None"
if finalPeak > 0.95
    Scale peak: 0.95
    safetyApplied = 1
else
    safetyApplied = 0
endif

result = selected("Sound")

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    # Create mono views only for analyses/plots that should not depend on
    # the source channel count.
    selectObject: original
    if numChan > 1
        vizOriginalMono = Convert to mono
    else
        vizOriginalMono = Copy: sound_name$ + "_viz_original"
    endif

    selectObject: result
    if numChan > 1
        vizResultMono = Convert to mono
    else
        vizResultMono = Copy: sound_name$ + "_viz_result"
    endif

    Erase all

    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Formula Audio Manipulation: " + sound_name$ + " (" + presetName$ + ")"

    # Original waveform (mono visualization view)
    Select outer viewport: 0, 8, 0.6, 1.6
    Select inner viewport: 0.6, 7.6, 0.7, 1.5
    selectObject: vizOriginalMono
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
    selectObject: vizResultMono
    Colour: "{0.5, 0.6, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"

    # Spectrogram comparison
    specCeiling = min(5000, 0.45 * sampling_rate)

    Select outer viewport: 0, 4, 4.0, 5.4
    Select inner viewport: 0.6, 3.8, 4.2, 5.3
    selectObject: vizOriginalMono
    origSpec = To Spectrogram: 0.03, specCeiling, 0.01, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Original"

    Select outer viewport: 4, 8, 4.0, 5.4
    Select inner viewport: 4.4, 7.6, 4.2, 5.3
    selectObject: vizResultMono
    resSpec = To Spectrogram: 0.03, specCeiling, 0.01, 20, "Gaussian"
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Processed"

    # Processing chain
    Select outer viewport: 0, 8, 5.5, 5.8
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"

    chainText$ = "AM(" + fixed$(base_frequency, 1) + "Hz)"
    if apply_pitch_modulation
        if pitchApplied
            chainText$ = chainText$ + " → Pitch(" + fixed$(pitch_mod_rate, 1) + "Hz)"
        else
            chainText$ = chainText$ + " → Pitch(skipped)"
        endif
    endif
    if apply_ring_modulation
        chainText$ = chainText$ + " → Ring(" + string$(ring_mod_frequency) + "Hz)"
    endif

    Text: 0.5, "centre", 0.5, "half", "Chain: " + chainText$ + " | Complexity: " + string$(complexity_level)

    Font size: 10
    Colour: "Black"

    removeObject: vizOriginalMono, vizResultMono
endif

# === Cleanup ===
removeObject: am_envelope

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Output channels: ", numChan
if apply_pitch_modulation
    if pitchApplied
        appendInfoLine: "Pitch stage: applied"
    else
        appendInfoLine: "Pitch stage: skipped (no usable pitch)"
    endif
endif
appendInfoLine: "Peak safety applied: ", safetyApplied

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
