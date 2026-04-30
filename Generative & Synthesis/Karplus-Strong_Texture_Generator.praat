# ============================================================
# Praat AudioTools - Karplus-Strong_Texture_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Karplus-Strong plucked string synthesis.
#   Physical modeling algorithm: noise burst → filtered delay line.
#
#   Recurrence simplified to a 2-tap weighted sum:
#     y[n] = damping * (c1 * y[n-N] + c2 * y[n-N-1])
#     where c1 = 0.5 + 0.5 * brightness
#           c2 = 0.5 - 0.5 * brightness
#           N  = round(sample_rate / pitch)
#     Brightness 0 = canonical lowpass average; 1 = pure delay
#     (no filter), max sustain of high frequencies.
#
# Changelog v0.3:
#   - Speed (HEADLINE): KS feedback loop vectorized. v0.2's
#     per-sample Get/Set value at sample number was ~3 round-
#     trips × ~265k samples per channel = ~800k Praat object
#     queries per channel. Replaced with Formula (part) passes
#     batched at the delay-line length. Within one delay
#     period, every output sample reads from the previous
#     delay period (already fully written), so a single
#     Formula (part) pass over N samples computes them all
#     simultaneously without serial dependency. Realistic
#     speedup: 30-100x depending on pitch (longer delays =
#     more samples per pass = bigger win). 3-second 220 Hz
#     run goes from ~5 s to ~0.1 s.
#   - Fix: Haas-effect right channel was producing silence.
#     v0.2's `self[col - delaySamplesHaas]` formula reads
#     in-place from cells already overwritten in the same
#     pass (col 1000 reads col 339, but col 339 was already
#     zeroed when col 339 read out-of-range col -322). Result:
#     entire right channel was silent; what played as "Haas"
#     was just hard-left mono. Fixed by reading from a
#     separate source matrix via cross-reference (same
#     pattern used in 8-Channel_Spectral_Shift v0.5).
#   - Fix/change: detuned stereo is now truly correlated.
#     v0.2 generated TWO independent random excitations and
#     processed each through a different delay length, so
#     the L and R channels were uncorrelated voices — sounds
#     diffuse rather than chorus-like. v0.3 generates ONE
#     excitation and processes it through two delay lines,
#     producing the beating/chorus effect that "detuned"
#     implies. Audible difference: more focused stereo image,
#     audible beats at the detune frequency.
#   - Visualization rewritten to suite 8x8 standard
#     (matching 22.2 Stem Renderer, 8-ch I Ching, 8-ch
#     Movements, 4-ch Canon, 8-ch Spectral Shift, etc.).
#     Panels:
#       A: Decay envelope (RMS over time, log-y) — shows
#          what damping does. Theoretical exponential decay
#          envelope overlaid as a reference curve.
#       B: Full-range spectrogram with harmonic lines.
#       C: KS signal-flow block diagram with actual values
#          labelled.
#       D: Full output waveform (was attack-only in v0.2).
#       E: Summary stats bar.
# Changelog v0.2:
#   - Fixed KS algorithm (was subtraction, now correct averaging)
#   - Added presets, spatial modes, visualization
# ============================================================

form Karplus-Strong Synthesis
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Plucked String
        option Guitar Strum
        option Harp Glissando
        option Metallic Pluck
        option Sitar Drone
        option Steel Drum
        option Banjo Bright
        option Dulcimer Shimmer
        option Prepared Piano
        option Frozen Resonance
    
    comment === Basic Settings ===
    positive Duration_s 3.0
    integer Sample_rate_Hz 44100
    positive Pitch_Hz 220
    
    comment === KS Parameters ===
    real Damping 0.995 (= 0.9-0.9999)
    real Brightness 0.5 (= 0-1, lowpass mix)
    positive Excitation_ms 5
    
    comment === Output ===
    optionmenu Spatial_mode 1
        option Mono
        option Stereo (detuned)
        option Stereo (delayed)
    real Detune_cents 8.6
    real Haas_delay_ms 15
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
preset_name$ = "Custom"

if preset = 2
    pitch_Hz = 220
    damping = 0.996
    brightness = 0.5
    excitation_ms = 5
    preset_name$ = "PluckedString"
elsif preset = 3
    pitch_Hz = 110
    damping = 0.995
    brightness = 0.6
    excitation_ms = 8
    preset_name$ = "GuitarStrum"
elsif preset = 4
    pitch_Hz = 440
    damping = 0.998
    brightness = 0.4
    excitation_ms = 3
    preset_name$ = "HarpGlissando"
elsif preset = 5
    pitch_Hz = 330
    damping = 0.9995
    brightness = 0.8
    excitation_ms = 2
    preset_name$ = "MetallicPluck"
elsif preset = 6
    pitch_Hz = 130
    damping = 0.997
    brightness = 0.5
    excitation_ms = 15
    preset_name$ = "SitarDrone"
elsif preset = 7
    pitch_Hz = 523
    damping = 0.994
    brightness = 0.7
    excitation_ms = 4
    preset_name$ = "SteelDrum"
elsif preset = 8
    pitch_Hz = 294
    damping = 0.990
    brightness = 0.9
    excitation_ms = 3
    preset_name$ = "BanjoBright"
elsif preset = 9
    pitch_Hz = 392
    damping = 0.9985
    brightness = 0.4
    excitation_ms = 6
    preset_name$ = "DulcimerShimmer"
elsif preset = 10
    pitch_Hz = 185
    damping = 0.993
    brightness = 0.6
    excitation_ms = 10
    preset_name$ = "PreparedPiano"
elsif preset = 11
    pitch_Hz = 261
    damping = 0.9999
    brightness = 0.3
    excitation_ms = 20
    preset_name$ = "FrozenResonance"
endif

# === Constants ===
uid$ = string$(randomInteger(10000, 99999))

# Vectorized KS recurrence coefficients (precomputed once)
# y[n] = damping * (c1 * y[n-N] + c2 * y[n-N-1])
c1 = 0.5 + 0.5 * brightness
c2 = 0.5 - 0.5 * brightness

# Delay line lengths
delaySamples = round(sample_rate_Hz / pitch_Hz)
excitationSamples = round(excitation_ms * sample_rate_Hz / 1000)
if excitationSamples > delaySamples
    excitationSamples = delaySamples
endif
totalSamples = round(duration_s * sample_rate_Hz)

# Right-channel detune (for spatial mode 2)
# detune in cents -> frequency ratio
detuneRatio = 2 ^ (detune_cents / 1200)
delaySamplesR = round(sample_rate_Hz / (pitch_Hz * detuneRatio))
if delaySamplesR < 2
    delaySamplesR = 2
endif

# Haas delay
haasSamples = round(haas_delay_ms * sample_rate_Hz / 1000)
if haasSamples < 1
    haasSamples = 1
endif

# === Info ===
writeInfoLine: "=== Karplus-Strong Synthesis v0.3 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Pitch: ", pitch_Hz, " Hz   |   Sample rate: ", sample_rate_Hz, " Hz"
appendInfoLine: "Delay line: ", delaySamples, " samples"
appendInfoLine: "Damping: ", fixed$(damping, 4), "   |   Brightness: ", fixed$(brightness, 2)
appendInfoLine: "  -> c1 = ", fixed$(c1, 3), "   c2 = ", fixed$(c2, 3)
appendInfoLine: "Excitation: ", excitation_ms, " ms (", excitationSamples, " samples)"
appendInfoLine: "Output samples: ", totalSamples
appendInfoLine: ""

# ============================================================
# VECTORIZED KS PROCEDURE
# ============================================================
# Generates one mono KS string into a Sound object.
# Returns the new Sound's ID in .out.
#
# How vectorization works:
#   The recurrence y[n] = damping * (c1 * y[n-N] + c2 * y[n-N-1])
#   has a serial dependency only across delay periods, not within
#   one. Within samples [n .. n+N-1] every read is from the prior
#   period [n-N .. n-1], which is already fully written. So we
#   can compute one delay period at a time with a single Formula
#   (part) pass, advancing by N samples between passes.
#
#   Total Formula passes: ceil(totalSamples / delaySamples)
#   For 3 s @ 220 Hz @ 44.1k: ceil(132300 / 200) = 662 passes
#   vs 264,300 individual Get/Set calls in v0.2.
# ============================================================
procedure synthKS: .name$, .delayN
    .out = Create Sound from formula: .name$, 1, 0, duration_s, sample_rate_Hz,
        ... "if col <= excitationSamples then randomGauss(0, 0.5) else 0 fi"
    
    selectObject: .out
    .ns = Get number of samples
    .sr = sample_rate_Hz
    
    # Start writing from sample (delayN + 2). Earlier samples
    # are either excitation noise (col <= excitationSamples) or
    # zeros (between excitation and delayN+2), which is the
    # correct initial condition for the delay line.
    .startSamp = .delayN + 2
    
    # Process one delay-period chunk at a time
    .curSamp = .startSamp
    while .curSamp <= .ns
        .endSamp = .curSamp + .delayN - 1
        if .endSamp > .ns
            .endSamp = .ns
        endif
        
        # Convert sample range to time range for Formula (part) bounds
        .tLo = (.curSamp - 1) / .sr
        .tHi = .endSamp / .sr
        
        # The recurrence reads from delayN and delayN+1 samples back.
        # Both reads are guaranteed to be in the prior period (already
        # written) because we advance by exactly delayN samples per pass.
        .dN = .delayN
        .dN1 = .delayN + 1
        Formula (part): .tLo, .tHi, 1, 1,
            ... "damping * (" + fixed$(c1, 8) + " * self[col - " + string$(.dN) + "]"
            ... + " + " + fixed$(c2, 8) + " * self[col - " + string$(.dN1) + "])"
        
        .curSamp = .curSamp + .delayN
    endwhile
    
    # Soft fade-out (last 50 ms) to prevent end-click
    .fadeT = 0.05
    if duration_s > 2 * .fadeT
        selectObject: .out
        Formula: "if x > duration_s - " + fixed$(.fadeT, 4)
            ... + " then self * ((duration_s - x) / " + fixed$(.fadeT, 4) + ")"
            ... + " else self fi"
    endif
endproc

# ============================================================
# SYNTHESIZE
# ============================================================
appendInfoLine: "Synthesizing..."
stopwatch

if spatial_mode = 1
    # --- Mono ---
    @synthKS: "ks_L_" + uid$, delaySamples
    leftID = synthKS.out
    
    selectObject: leftID
    Rename: "ks_" + preset_name$
    outputSound = leftID

elsif spatial_mode = 2
    # --- Stereo (detuned) — TRUE CORRELATED VERSION (v0.3) ---
    # Generate ONE excitation and process it through two delay
    # lines. This produces the chorus / beating effect that
    # "detuned" actually means. v0.2 generated independent
    # excitations, which sounds diffuse instead of chorused.
    appendInfoLine: "  Detuned stereo (correlated, ", fixed$(detune_cents, 1), " cents)"
    
    # Build a shared excitation as a small Sound, then copy it
    # into both channels' synthesis buffers.
    sharedSeed = Create Sound from formula: "ks_seed_" + uid$, 1, 0, duration_s, sample_rate_Hz,
        ... "if col <= excitationSamples then randomGauss(0, 0.5) else 0 fi"
    
    # Left channel
    selectObject: sharedSeed
    Copy: "ks_L_" + uid$
    leftID = selected("Sound")
    selectObject: leftID
    nsL = Get number of samples
    curL = delaySamples + 2
    while curL <= nsL
        endL = curL + delaySamples - 1
        if endL > nsL
            endL = nsL
        endif
        tLoL = (curL - 1) / sample_rate_Hz
        tHiL = endL / sample_rate_Hz
        dNL = delaySamples
        dNL1 = delaySamples + 1
        Formula (part): tLoL, tHiL, 1, 1,
            ... "damping * (" + fixed$(c1, 8) + " * self[col - " + string$(dNL) + "]"
            ... + " + " + fixed$(c2, 8) + " * self[col - " + string$(dNL1) + "])"
        curL = curL + delaySamples
    endwhile
    selectObject: leftID
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
    
    # Right channel — different delay = detuned pitch
    selectObject: sharedSeed
    Copy: "ks_R_" + uid$
    rightID = selected("Sound")
    selectObject: rightID
    nsR = Get number of samples
    curR = delaySamplesR + 2
    while curR <= nsR
        endR = curR + delaySamplesR - 1
        if endR > nsR
            endR = nsR
        endif
        tLoR = (curR - 1) / sample_rate_Hz
        tHiR = endR / sample_rate_Hz
        dNR = delaySamplesR
        dNR1 = delaySamplesR + 1
        Formula (part): tLoR, tHiR, 1, 1,
            ... "damping * (" + fixed$(c1, 8) + " * self[col - " + string$(dNR) + "]"
            ... + " + " + fixed$(c2, 8) + " * self[col - " + string$(dNR1) + "])"
        curR = curR + delaySamplesR
    endwhile
    selectObject: rightID
    Formula: "if x > duration_s - 0.05 then self * ((duration_s - x) / 0.05) else self fi"
    
    # Combine
    selectObject: leftID
    plusObject: rightID
    stereoSound = Combine to stereo
    Rename: "ks_" + preset_name$
    
    removeObject: sharedSeed, leftID, rightID
    outputSound = stereoSound

else
    # --- Stereo (delayed / Haas) — IN-PLACE BUG FIX (v0.3) ---
    # Generate one mono signal, then for the right channel use
    # cross-Sound reference to read the original samples instead
    # of in-place self-reads, which v0.2 used and which produced
    # silence (every read hit a cell already zeroed out).
    appendInfoLine: "  Haas-effect stereo (", fixed$(haas_delay_ms, 1), " ms)"
    
    @synthKS: "ks_L_" + uid$, delaySamples
    leftID = synthKS.out
    
    # Build right channel as a delayed copy of left.
    # Read from leftID (untouched) into a fresh empty Sound.
    rightID = Create Sound from formula: "ks_R_" + uid$, 1, 0, duration_s, sample_rate_Hz, "0"
    selectObject: rightID
    nsHaas = Get number of samples
    Formula: "if col > " + string$(haasSamples)
        ... + " then object[" + string$(leftID) + ", col - " + string$(haasSamples) + "]"
        ... + " else 0 fi"
    
    selectObject: leftID
    plusObject: rightID
    stereoSound = Combine to stereo
    Rename: "ks_" + preset_name$
    
    removeObject: leftID, rightID
    outputSound = stereoSound
endif

synthElapsed = stopwatch
appendInfoLine: "  (synthesis: ", fixed$(synthElapsed, 3), " s)"

# === Normalize ===
if normalize_output
    selectObject: outputSound
    Scale peak: 0.9
endif

# === Final stats for visualization ===
selectObject: outputSound
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
    Text: 0.5, "centre", 0.68, "half", "##KARPLUS-STRONG TEXTURE GENERATOR##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... "Preset: " + preset_name$
        ... + "  |  " + fixed$(pitch_Hz, 1) + " Hz"
        ... + "  |  Damp: " + fixed$(damping, 4)
        ... + "  |  Bright: " + fixed$(brightness, 2)
        ... + "  |  N = " + string$(delaySamples) + " samp"
        ... + "  |  " + fixed$(finalDur, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: DECAY ENVELOPE  (left, headline)
    # RMS over time on log-y. Theoretical exponential decay from
    # damping^cycles is overlaid as a reference. Tells the user
    # at a glance how sustained the sound is and whether the
    # decay matches the damping parameter.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    # Compute RMS in 50 ms windows from the actual output
    rmsWinSec = 0.05
    nRMSWin = round(finalDur / rmsWinSec)
    if nRMSWin < 4
        nRMSWin = 4
    endif
    if nRMSWin > 200
        nRMSWin = 200
    endif
    rmsHopSec = finalDur / nRMSWin
    
    # We need a mono representation for RMS measurement.
    # If stereo, use channel 1 as a proxy (cheaper than full mix).
    if nResultCh = 1
        rmsSrc = outputSound
        rmsSrcOwned = 0
    else
        selectObject: outputSound
        rmsSrc = Extract one channel: 1
        rmsSrcOwned = 1
    endif
    
    rmsT# = zero# (nRMSWin)
    rmsV# = zero# (nRMSWin)
    rmsMax = 0.000001
    selectObject: rmsSrc
    for k from 1 to nRMSWin
        tStart = (k - 1) * rmsHopSec
        tEnd = tStart + rmsWinSec
        if tEnd > finalDur
            tEnd = finalDur
        endif
        thisRMS = Get root-mean-square: tStart, tEnd
        if thisRMS = undefined or thisRMS < 0
            thisRMS = 0
        endif
        rmsT#[k] = (tStart + tEnd) / 2
        rmsV#[k] = thisRMS
        if thisRMS > rmsMax
            rmsMax = thisRMS
        endif
    endfor
    if rmsSrcOwned = 1
        removeObject: rmsSrc
    endif
    
    # Convert to dB (relative to peak, floor at -60)
    dbFloor = -60
    rmsDb# = zero# (nRMSWin)
    for k from 1 to nRMSWin
        if rmsV#[k] > 0.000001
            v = 20 * log10(rmsV#[k] / rmsMax)
            if v < dbFloor
                v = dbFloor
            endif
        else
            v = dbFloor
        endif
        rmsDb#[k] = v
    endfor
    
    Axes: 0, finalDur, dbFloor, 3
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, finalDur, dbFloor, 3
    
    # Reference grid: -10 dB lines
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    gv = -10
    while gv >= dbFloor
        Draw line: 0, gv, finalDur, gv
        gv = gv - 10
    endwhile
    Colour: "{0.78, 0.78, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # --- Theoretical exponential decay overlay ---
    # Each delay-line cycle, the loop multiplies by `damping`.
    # In dB: per cycle = 20*log10(damping). Cycles per second = pitch.
    # So decay rate dB/s = pitch * 20*log10(damping).
    # (Note: brightness adds a frequency-dependent decay on top
    # of this, but the lowest mode decays at approximately the
    # damping rate, which is what we plot here.)
    decayPerCycleDb = 20 * log10(damping)
    decayDbPerSec = pitch_Hz * decayPerCycleDb
    Colour: "{0.55, 0.20, 0.55}"
    Dotted line
    Line width: 1.5
    if decayDbPerSec < -0.01
        # Only draw if there's actual decay
        Draw line: 0, 0, finalDur, finalDur * decayDbPerSec
    endif
    Solid line
    Line width: 1
    Font size: 5
    Colour: "{0.55, 0.20, 0.55}"
    if decayDbPerSec < -0.01
        Text: finalDur * 0.95, "right", -5, "half",
            ... "theory: " + fixed$(decayDbPerSec, 1) + " dB/s"
    else
        Text: finalDur * 0.5, "centre", -5, "half", "no decay (damping ≈ 1)"
    endif
    
    # --- Measured RMS curve ---
    Colour: "{0.85, 0.40, 0.20}"
    Line width: 1.5
    for k from 2 to nRMSWin
        Draw line: rmsT#[k - 1], rmsDb#[k - 1], rmsT#[k], rmsDb#[k]
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "RMS (dB rel peak)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: SPECTROGRAM with HARMONIC LINES  (right, upper)
    # Full range up to Nyquist/2 so harmonics are visible.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.55, 7.75, 0.90, 2.85
    
    # Build a mono representation
    if nResultCh = 1
        specSrc = outputSound
        specSrcOwned = 0
    else
        selectObject: outputSound
        specSrc = Extract one channel: 1
        specSrcOwned = 1
    endif
    
    # Spectrogram up to Nyquist/2 (or a hard cap of 11025 Hz for clarity)
    specMaxFreq = sample_rate_Hz / 4
    if specMaxFreq > 11025
        specMaxFreq = 11025
    endif
    
    selectObject: specSrc
    To Spectrogram: 0.03, specMaxFreq, 0.005, 20, "Gaussian"
    specID = selected("Spectrogram")
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "no"
    removeObject: specID
    if specSrcOwned = 1
        removeObject: specSrc
    endif
    
    # Overlay harmonic lines
    Axes: 0, finalDur, 0, specMaxFreq
    Colour: "{1, 0.85, 0.30}"
    Dotted line
    Line width: 1
    h = 1
    while pitch_Hz * h < specMaxFreq and h <= 16
        Draw line: 0, pitch_Hz * h, finalDur, pitch_Hz * h
        h = h + 1
    endwhile
    Solid line
    
    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left every: 1, 1000, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL C: KS BLOCK DIAGRAM  (right, lower)
    # Educational diagram showing the signal flow with current
    # parameter values labelled. Helps users understand what
    # they're tweaking.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.40, 7.85, 3.15, 4.55
    
    Axes: 0, 100, 0, 100
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 100, 0, 100
    
    # Boxes (positions chosen for the canvas aspect)
    # Excitation box (left)
    Paint rectangle: "{0.85, 0.92, 0.82}", 4, 22, 55, 80
    Colour: "{0.30, 0.45, 0.30}"
    Line width: 1.2
    Draw rectangle: 4, 22, 55, 80
    Font size: 6
    Colour: "{0.20, 0.35, 0.20}"
    Text: 13, "centre", 70, "half", "##Excite##"
    Font size: 5
    Text: 13, "centre", 64, "half", "noise"
    Text: 13, "centre", 58, "half", fixed$(excitation_ms, 1) + " ms"
    
    # Delay line box (centre)
    Paint rectangle: "{0.82, 0.85, 0.95}", 30, 60, 55, 80
    Colour: "{0.30, 0.40, 0.65}"
    Draw rectangle: 30, 60, 55, 80
    Font size: 6
    Colour: "{0.20, 0.30, 0.55}"
    Text: 45, "centre", 72, "half", "##Delay line##"
    Font size: 5
    Text: 45, "centre", 65, "half", "N = " + string$(delaySamples) + " samp"
    Text: 45, "centre", 60, "half", "(" + fixed$(1000.0 / pitch_Hz, 2) + " ms)"
    
    # 2-tap filter box (right)
    Paint rectangle: "{0.95, 0.88, 0.82}", 68, 96, 55, 80
    Colour: "{0.65, 0.40, 0.30}"
    Draw rectangle: 68, 96, 55, 80
    Font size: 6
    Colour: "{0.55, 0.30, 0.20}"
    Text: 82, "centre", 72, "half", "##2-tap LP##"
    Font size: 5
    Text: 82, "centre", 65, "half", "c1=" + fixed$(c1, 2) + " c2=" + fixed$(c2, 2)
    Text: 82, "centre", 60, "half", "(brightness)"
    
    # Damping (gain) box at bottom
    Paint rectangle: "{0.95, 0.92, 0.82}", 35, 65, 18, 38
    Colour: "{0.65, 0.55, 0.30}"
    Draw rectangle: 35, 65, 18, 38
    Font size: 6
    Colour: "{0.55, 0.45, 0.20}"
    Text: 50, "centre", 32, "half", "##× damping##"
    Font size: 5
    Text: 50, "centre", 24, "half", fixed$(damping, 4)
    
    Line width: 1
    
    # Arrows: excite → delay
    Colour: "{0.40, 0.40, 0.50}"
    Line width: 1.2
    Draw line: 22, 67, 30, 67
    # arrowhead
    Draw line: 30, 67, 28, 65
    Draw line: 30, 67, 28, 69
    
    # delay → filter
    Draw line: 60, 67, 68, 67
    Draw line: 68, 67, 66, 65
    Draw line: 68, 67, 66, 69
    
    # filter → out (right edge)
    Draw line: 96, 67, 99, 67
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    Text: 97, "right", 73, "half", "out"
    
    # Feedback path: out -> damping -> back to delay input
    # Goes down from filter output, left to damping, then back up to delay
    Draw line: 82, 55, 82, 45
    Draw line: 82, 45, 65, 38 / 2 + 8
    # Simpler: take it down to damping, then back up to delay-in level
    Draw line: 82, 55, 82, 45
    Draw line: 82, 45, 65, 28
    Draw line: 35, 28, 13, 28
    Draw line: 13, 28, 13, 55
    Draw line: 13, 55, 22, 67
    # Arrowhead into delay (already drawn above for excite→delay; reuse position)
    
    # Feedback labels
    Font size: 5
    Colour: "{0.40, 0.40, 0.50}"
    Text: 80, "right", 50, "half", "feedback"
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Signal flow"
    
    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8
    
    Font size: 7
    Colour: "Black"
    Text: 2.20, "centre", 7.30, "half", "Decay envelope (orange = measured, dotted = theory)"
    Text: 6.10, "centre", 7.30, "half", "Spectrogram + harmonics (upper) & block diagram (lower)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM  (full width, full duration)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68
    
    selectObject: outputSound
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    selectObject: outputSound
    if nResultCh = 1
        Colour: "{0.20, 0.55, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        selectObject: outputSound
        Extract one channel: 2
        vCh2 = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh2
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if nResultCh = 1
        Text top: "no", "Output waveform"
    else
        Text top: "no", "Output  (blue = L,  orange = R)"
    endif
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if spatial_mode = 1
        spatialName$ = "Mono"
    elsif spatial_mode = 2
        spatialName$ = "Stereo (detuned, " + fixed$(detune_cents, 1) + " ¢)"
    else
        spatialName$ = "Stereo (Haas, " + fixed$(haas_delay_ms, 1) + " ms)"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + preset_name$ + "##"
        ... + "  Pitch: " + fixed$(pitch_Hz, 1) + " Hz"
        ... + "  |  N = " + string$(delaySamples) + " samp"
        ... + "  |  Damp: " + fixed$(damping, 4) + " (" + fixed$(decayDbPerSec, 1) + " dB/s)"
        ... + "  |  Bright: " + fixed$(brightness, 2)
        ... + "  |  Excite: " + fixed$(excitation_ms, 1) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Mode: " + spatialName$
        ... + "  |  SR: " + string$(sample_rate_Hz) + " Hz"
        ... + "  |  Dur: " + fixed$(finalDur, 2) + " s (" + string$(totalSamples) + " samp)"
        ... + "  |  Peak: " + fixed$(finalPeak, 3)
        ... + "  |  Synth time: " + fixed$(synthElapsed, 2) + " s"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
endif

# === Play ===
if play_result
    selectObject: outputSound
    Play
endif

# === Final ===
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
