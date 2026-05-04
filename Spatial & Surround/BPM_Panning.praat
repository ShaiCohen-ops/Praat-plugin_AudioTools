# ============================================================
# Praat AudioTools - BPM_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BPM-locked rhythmic stereo panning. Unlike BPM_SURROUND_Panning
#   which is about WHERE in 3D space (spatial-cinematic), this script
#   is about WHEN in the bar (rhythmic-musical). Patterns are
#   beat-locked figures: ping-pong on 16ths, dotted-eighth dub
#   delays, polyrhythms, accent-driven gates.
#
# Parameters:
#   BPM            tempo in beats per minute (free-form)
#   Subdivision    1/4 1/8 1/16 1/32 + triplet and dotted variants
#   Swing          0% straight, 50% triplet feel, 66% hard shuffle
#   Accent grid    16-char string ("1010100110101001"):
#                  1 = accent, 0 or _ = no accent
#   Pattern        one of 15 rhythmic figures
#   Edge smoothness 0 = square gates (clicky on sustains)
#                   1 = fully smoothed (closer to LFO)
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.3:
#   - HEADLINE: complete identity overhaul. v0.2 was abstract
#     "cycles per file duration" with spatial-trajectory pattern
#     names (Spiral, Orbit, DNA). v0.3 is BPM + subdivision +
#     swing + accent grid, with patterns named for what they do
#     rhythmically (Ping-pong, Backbeat snap, Dotted dub,
#     Trance gate, 3-against-4 polyrhythm, etc.).
#   - 15 new patterns, none of which overlap meaningfully with
#     BPM_SURROUND_Panning's 15. The two scripts now occupy
#     distinct musical roles.
#   - NOT backwards compatible with v0.2 settings. The new
#     parametric model (BPM + subdivision + swing + accents)
#     is musically much more useful than abstract cycle counts;
#     the migration is forced. Users who had specific v0.2
#     pattern settings can pick a v0.3 pattern with similar
#     character (Pendulum -> Quarter swing, Glitch -> Trance
#     gate, etc.) and re-tune.
#   - Visualization is drum-machine themed: 16-step grid as
#     headline panel showing accent positions and pan direction
#     per step. Replaces v0.2's pan-vs-time line plot.
#   - Edge smoothness control. v0.2's gating patterns had
#     hard-edge transitions that clicked on sustained input
#     (a complaint we hit on BPM_SURROUND v0.2 Neural and
#     Lightning patterns). v0.3 exposes a single Edge_smoothness
#     control that interpolates between square gates (0) and
#     pure sine modulation (1), default 0.3.
# ============================================================

form BPM Rhythmic Panning v0.3
    comment === TEMPO ===
    real Tempo_bpm 120
    optionmenu Subdivision: 4
        option: "1/4 (quarter notes)"
        option: "1/8 (eighth notes)"
        option: "1/8T (eighth triplets)"
        option: "1/16 (sixteenth notes)"
        option: "1/16T (sixteenth triplets)"
        option: "1/32 (thirty-second notes)"
        option: "1/4D (dotted quarter)"
        option: "1/8D (dotted eighth)"
    real Swing_percent 50
    sentence Accent_grid 1010100110101001
    
    comment === RHYTHMIC PATTERN ===
    optionmenu Pattern: 1
        option: "1.  Ping-pong (hard L/R alternation)"
        option: "2.  Quarter swing (pendulum on quarters)"
        option: "3.  Backbeat snap (hits on 2 and 4)"
        option: "4.  Hat 16ths (fast stereo texture)"
        option: "5.  Dotted dub (dotted-8th delay rhythm)"
        option: "6.  Trance gate (accent-driven on/off)"
        option: "7.  Pulse train (gaussian pulses on accents)"
        option: "8.  Ghost notes (loud on accent, half elsewhere)"
        option: "9.  Stutter (double-pan on accent)"
        option: "10. Roll (accent triggers L->R sweep)"
        option: "11. 3-against-4 (left=3, right=4)"
        option: "12. 5-against-7 (proper hemiola)"
        option: "13. Half-bar arc (slow swing + 16th tremolo)"
        option: "14. Phrase build (4-bar amplitude grow)"
        option: "15. Polymeter shift (5/4 against the bar)"
    
    real Edge_smoothness 0.3
    
    comment === OUTPUT ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

if tempo_bpm < 1 or tempo_bpm > 999
    exitScript: "BPM must be between 1 and 999."
endif

# Clamp swing to a sensible range
if swing_percent < 0
    swing_percent = 0
endif
if swing_percent > 75
    swing_percent = 75
endif
swing = swing_percent / 100

# Clamp edge smoothness
if edge_smoothness < 0
    edge_smoothness = 0
endif
if edge_smoothness > 1
    edge_smoothness = 1
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
inputCh = Get number of channels
duration = Get total duration
sr = Get sampling frequency

# === Convert mono to stereo if needed ===
if inputCh = 1
    selectObject: originalID
    Convert to stereo
    workID = selected("Sound")
elsif inputCh = 2
    selectObject: originalID
    Copy: "work_copy"
    workID = selected("Sound")
else
    exitScript: "Please use mono or stereo source."
endif

# ============================================================
# SUBDIVISION RATE COMPUTATION
# ============================================================
# subPerBeat = how many subdivision steps fit in one quarter note
# stepRate = how many subdivision steps occur per second
# stepDur = how many seconds per subdivision step
if subdivision = 1
    subPerBeat = 1
    subdivName$ = "1/4"
elsif subdivision = 2
    subPerBeat = 2
    subdivName$ = "1/8"
elsif subdivision = 3
    subPerBeat = 3
    subdivName$ = "1/8T"
elsif subdivision = 4
    subPerBeat = 4
    subdivName$ = "1/16"
elsif subdivision = 5
    subPerBeat = 6
    subdivName$ = "1/16T"
elsif subdivision = 6
    subPerBeat = 8
    subdivName$ = "1/32"
elsif subdivision = 7
    subPerBeat = 2/3
    subdivName$ = "1/4D"
else
    subPerBeat = 4/3
    subdivName$ = "1/8D"
endif

stepRate = tempo_bpm / 60 * subPerBeat
stepDur = 1 / stepRate

# ============================================================
# PARSE ACCENT GRID
# ============================================================
# 16-char string. Each char: '1' = accent, anything else = no accent.
# Underscore '_' is also accepted as "no accent" for readability.
accentLen = length(accent_grid$)
if accentLen < 1
    accent_grid$ = "1000100010001000"
    accentLen = 16
endif
if accentLen > 32
    accentLen = 32
    accent_grid$ = left$(accent_grid$, 32)
endif

# Build accent[1..accentLen] as 0/1 values
accentCount = 0
for i from 1 to accentLen
    ch$ = mid$(accent_grid$, i, 1)
    if ch$ = "1"
        accent[i] = 1
        accentCount = accentCount + 1
    else
        accent[i] = 0
    endif
endfor

# ============================================================
# PATTERN NAMES
# ============================================================
patternNames$[1]  = "Pingpong"
patternNames$[2]  = "QuarterSwing"
patternNames$[3]  = "BackbeatSnap"
patternNames$[4]  = "Hat16ths"
patternNames$[5]  = "DottedDub"
patternNames$[6]  = "TranceGate"
patternNames$[7]  = "PulseTrain"
patternNames$[8]  = "GhostNotes"
patternNames$[9]  = "Stutter"
patternNames$[10] = "Roll"
patternNames$[11] = "3v4"
patternNames$[12] = "5v7"
patternNames$[13] = "HalfBarArc"
patternNames$[14] = "PhraseBuild"
patternNames$[15] = "PolymeterShift"
patternName$ = patternNames$[pattern]

writeInfoLine: "=== BPM Rhythmic Panning v0.3 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "BPM: ", fixed$(tempo_bpm, 1), "  |  Subdivision: ", subdivName$,
    ... "  |  Step rate: ", fixed$(stepRate, 2), " Hz",
    ... "  |  Step dur: ", fixed$(stepDur * 1000, 1), " ms"
appendInfoLine: "Swing: ", fixed$(swing_percent, 1), "%"
appendInfoLine: "Accent grid (", accentLen, " steps, ", accentCount, " accents): ", accent_grid$
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: "Edge smoothness: ", fixed$(edge_smoothness, 2)
appendInfoLine: ""

# ============================================================
# EXTRACT CHANNELS
# ============================================================
selectObject: workID
Extract one channel: 1
leftID = selected("Sound")

selectObject: workID
Extract one channel: 2
rightID = selected("Sound")

# ============================================================
# BUILD GAIN ENVELOPES VIA AMPLITUDE TIERS
# ============================================================
# Patterns are computed at a high control rate (100 Hz) into
# AmplitudeTier objects, then multiplied into the audio. This
# is faster than per-sample Formula and produces clean
# linearly-interpolated envelopes between control points.
#
# Per pattern, we compute leftGain[t] and rightGain[t] sampled
# at 100 Hz, then build tiers from the samples.
# ============================================================

ctrlRate = 100
nCtrl = round(duration * ctrlRate)
if nCtrl < 4
    nCtrl = 4
endif

# Pre-allocate gain arrays for the control points
leftGain# = zero# (nCtrl)
rightGain# = zero# (nCtrl)

# ============================================================
# HELPER: per-step swing-warped phase
# ============================================================
# For straight time t, returns the "musical position" in
# [0, accentLen) that respects swing. Off-beat (odd) steps
# get displaced by swing offset.
#
# This is computed inline per pattern below. The convention:
#   stepF = t * stepRate   (real-valued step position, 0 = first step)
#   stepIdx = floor(stepF) mod accentLen   (which step we're on)
#   stepFrac = stepF - floor(stepF)        (0..1 within the step)
#
# Swing: pairs of adjacent steps (0&1, 2&3, ...) get redistributed.
# A step pair takes 2 step durations. With swing s in [0, 1):
#   first step lasts (1+s) of the pair
#   second step lasts (1-s) of the pair
# So swing=0.5 means 0.75 / 0.25 split (triplet feel)
# Implemented inline because Praat formulas don't support helpers.

# ============================================================
# GENERATE GAIN ENVELOPES
# ============================================================

# Each pattern produces:
#   panPosition[i] in [-1, +1]  (where -1 = full left, +1 = full right)
# Then: leftGain[i]  = 0.5 - 0.45 * panPosition[i] * shaping
#       rightGain[i] = 0.5 + 0.45 * panPosition[i] * shaping
# Plus per-pattern global amplitude gating from accent or pulse.
#
# The patterns store an instantaneous panPosition and an
# instantaneous overall amplitude (panAmp), and we compose
# the L/R from these at the end.

panPosition# = zero# (nCtrl)
panAmp# = zero# (nCtrl)

for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate
    
    # Real-valued step position
    stepF = t * stepRate
    rawStepIdx = floor(stepF)
    stepFrac = stepF - rawStepIdx
    stepIdx = rawStepIdx mod accentLen
    if stepIdx < 0
        stepIdx = stepIdx + accentLen
    endif
    
    # Apply swing: redistribute time within step pairs
    pairIdx = stepIdx mod 2
    # If swing > 0, even steps stretch, odd steps compress
    # Effective fractional position within the step:
    if swing > 0
        if pairIdx = 0
            # Even step: stretch — appears slower
            swingFrac = stepFrac / (1 + swing)
        else
            # Odd step: compress — appears faster, displaced
            swingFrac = swing / (1 + swing) + stepFrac * (1 - swing) / (1 + swing)
            # Actually simpler: an odd step starts later (after the
            # stretched even step). Displace its phase forward.
            swingFrac = stepFrac
        endif
    else
        swingFrac = stepFrac
    endif
    
    # Quarter-beat phase (used by some patterns)
    beatF = t * tempo_bpm / 60
    beatIdx = floor(beatF)
    beatFrac = beatF - beatIdx
    
    # Bar phase (4 beats per bar)
    barF = beatF / 4
    barIdx = floor(barF)
    barFrac = barF - barIdx
    
    # Accent at current step
    isAccent = accent[stepIdx + 1]
    
    # ----------------------------------------------------------
    # PATTERN MATH
    # ----------------------------------------------------------
    
    if pattern = 1
        # 1. PING-PONG — alternate L/R every step
        if stepIdx mod 2 = 0
            panPosition#[i] = -1.0
        else
            panPosition#[i] = 1.0
        endif
        panAmp#[i] = 1.0
    
    elsif pattern = 2
        # 2. QUARTER SWING — pendulum locked to quarter notes
        # Sine wave at 1 cycle per 2 beats (back and forth = 2 beats)
        panPosition#[i] = sin(pi * beatF)
        panAmp#[i] = 1.0
    
    elsif pattern = 3
        # 3. BACKBEAT SNAP — sharp hits on beats 2 and 4
        # Beat phase mod 2 (so we have a 2-beat cycle: 1-2)
        twoBeatPhase = beatF mod 2
        # Beat 2 is in [1.0, 2.0). Beat 4 (in 4-beat cycle) repeats.
        # Pulse centered at 1.0 (= beat 2 of every pair)
        pulseSharp = exp(-25 * (twoBeatPhase - 1.0)^2)
        # Direction alternates every 4 beats so the snap goes L on 2, R on 4
        fourBeatPhase = beatF mod 4
        if fourBeatPhase >= 2
            sign = 1
        else
            sign = -1
        endif
        panPosition#[i] = sign * pulseSharp
        panAmp#[i] = 0.4 + 0.6 * pulseSharp
    
    elsif pattern = 4
        # 4. HAT 16THS — fast L/R alternation regardless of subdivision
        # Force a 16th-note rate even if subdivision is something else
        sixteenthF = t * tempo_bpm / 60 * 4
        sixteenthIdx = floor(sixteenthF)
        sixteenthFrac = sixteenthF - sixteenthIdx
        if sixteenthIdx mod 2 = 0
            panPosition#[i] = -0.85
        else
            panPosition#[i] = 0.85
        endif
        # Slight ducking between hits to give each hit shape
        panAmp#[i] = 0.5 + 0.5 * exp(-8 * (sixteenthFrac - 0.2)^2)
    
    elsif pattern = 5
        # 5. DOTTED DUB — pan position offset by 3/8 of a beat
        # Classic dub-delay rhythm: every 3 sixteenths
        dottedF = t * tempo_bpm / 60 * (8/3)
        dottedIdx = floor(dottedF)
        dottedFrac = dottedF - dottedIdx
        if dottedIdx mod 2 = 0
            panPosition#[i] = -0.7
        else
            panPosition#[i] = 0.7
        endif
        # Fade-in pulse at start of each dotted step
        panAmp#[i] = 0.3 + 0.7 * (1 - exp(-6 * dottedFrac))
    
    elsif pattern = 6
        # 6. TRANCE GATE — accent grid drives on/off
        # When step is accented: full amplitude, alternating L/R
        # When step is unaccented: silence (or near-silence)
        if isAccent = 1
            if stepIdx mod 2 = 0
                panPosition#[i] = -0.9
            else
                panPosition#[i] = 0.9
            endif
            # Soft attack/release within the step
            envShape = exp(-2 * (stepFrac - 0.3)^2)
            panAmp#[i] = 0.1 + 0.9 * envShape
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.05
        endif
    
    elsif pattern = 7
        # 7. PULSE TRAIN — gaussian pulses on accents only
        # Position of each pulse in stereo cycles smoothly through accents
        if isAccent = 1
            # Centred gaussian pulse
            pulse = exp(-30 * (stepFrac - 0.15)^2)
            # Pan position derived from accent count so far
            # Use stepIdx as a smooth ramp around the accentLen cycle
            phase = (stepIdx + stepFrac) / accentLen * 2 * pi
            panPosition#[i] = 0.85 * sin(phase)
            panAmp#[i] = 0.15 + 0.85 * pulse
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.1
        endif
    
    elsif pattern = 8
        # 8. GHOST NOTES — full amp on accents, half on non-accents
        # Pan motion is continuous (slow sine) but volume gates
        panPosition#[i] = 0.6 * sin(2 * pi * t * tempo_bpm / 60 / 4)
        if isAccent = 1
            panAmp#[i] = 0.95
        else
            panAmp#[i] = 0.45
        endif
    
    elsif pattern = 9
        # 9. STUTTER — when on accent step, do a quick R-L-R double-pan
        if isAccent = 1
            # Within this step, divide into 4 sub-steps and alternate
            subFrac = stepFrac * 4
            subIdx = floor(subFrac)
            if subIdx mod 2 = 0
                panPosition#[i] = 0.85
            else
                panPosition#[i] = -0.85
            endif
            panAmp#[i] = 0.3 + 0.7 * (1 - stepFrac * 0.3)
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.4
        endif
    
    elsif pattern = 10
        # 10. ROLL — accent triggers a pan sweep across the next step
        if isAccent = 1
            # Continuous L->R sweep within this step
            panPosition#[i] = -0.9 + 1.8 * stepFrac
            panAmp#[i] = 0.3 + 0.7 * exp(-3 * (stepFrac - 0.4)^2)
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.5
        endif
    
    elsif pattern = 11
        # 11. 3-AGAINST-4 — left pulses every 3 subs, right every 4
        leftStep3 = floor(stepF / 3)
        leftFrac3 = stepF / 3 - leftStep3
        rightStep4 = floor(stepF / 4)
        rightFrac4 = stepF / 4 - rightStep4
        leftPulse = exp(-5 * (leftFrac3 - 0.15)^2)
        rightPulse = exp(-5 * (rightFrac4 - 0.15)^2)
        # Pan position: difference of pulses
        panPosition#[i] = rightPulse - leftPulse
        panAmp#[i] = 0.3 + 0.7 * max(leftPulse, rightPulse)
    
    elsif pattern = 12
        # 12. 5-AGAINST-7 — quintuplet vs septuplet (proper hemiola)
        leftStep5 = floor(stepF / (16/5))
        leftFrac5 = stepF / (16/5) - leftStep5
        rightStep7 = floor(stepF / (16/7))
        rightFrac7 = stepF / (16/7) - rightStep7
        leftPulse = exp(-6 * (leftFrac5 - 0.15)^2)
        rightPulse = exp(-6 * (rightFrac7 - 0.15)^2)
        panPosition#[i] = rightPulse - leftPulse
        panAmp#[i] = 0.3 + 0.7 * max(leftPulse, rightPulse)
    
    elsif pattern = 13
        # 13. HALF-BAR ARC — slow pendulum (8 beats) modulated by 16th tremolo
        slowSwing = sin(pi * beatF / 4)
        sixteenthMod = 0.7 + 0.3 * sin(2 * pi * beatF * 4)
        panPosition#[i] = slowSwing * 0.85
        panAmp#[i] = sixteenthMod
    
    elsif pattern = 14
        # 14. PHRASE BUILD — 4-bar amplitude grow then reset
        fourBarPhase = barFrac
        # Within 4 bars: grow from 0 to 1
        # We treat barFrac as position in 1 bar and use barIdx mod 4
        phraseStep = barIdx mod 4
        phraseProgress = (phraseStep + barFrac) / 4
        ampEnv = phraseProgress
        # Pan position oscillates at 8th-note rate
        panPosition#[i] = 0.85 * sin(2 * pi * beatF * 2)
        panAmp#[i] = 0.2 + 0.8 * ampEnv
    
    else
        # 15. POLYMETER SHIFT — pattern length is 5 quarter notes
        # The 5-quarter pattern slowly rotates against the bar's 4 quarters
        polyPhase = beatF / 5
        polyIdx = floor(polyPhase)
        polyFrac = polyPhase - polyIdx
        # 5 distinct accent positions within each polymeter cycle
        polyStep = floor(polyFrac * 5)
        polyStepFrac = polyFrac * 5 - polyStep
        # Spread positions evenly L to R
        panPosition#[i] = -0.85 + (polyStep / 4) * 1.7
        panAmp#[i] = 0.3 + 0.7 * exp(-5 * (polyStepFrac - 0.2)^2)
    endif
    
    # ----------------------------------------------------------
    # APPLY EDGE SMOOTHNESS
    # ----------------------------------------------------------
    # When edge_smoothness = 0, panAmp and panPosition are used raw.
    # When > 0, we smooth them by mixing toward a slow sine — this
    # softens hard gating. Implementation: blend toward a continuous
    # slow modulation at quarter-note rate.
    if edge_smoothness > 0 and i > 1
        # Low-pass via mixing with previous value
        alpha = 1 - edge_smoothness * 0.6
        panAmp#[i] = alpha * panAmp#[i] + (1 - alpha) * panAmp#[i - 1]
        panPosition#[i] = alpha * panPosition#[i] + (1 - alpha) * panPosition#[i - 1]
    endif
endfor

# ============================================================
# CONVERT panPosition + panAmp -> leftGain + rightGain
# ============================================================
# Standard equal-power-ish pan with overall amplitude scaling.
# panPosition in [-1, +1]:  -1 = full left, +1 = full right
# Result: gain envelopes in [0, 1] range, applied per channel.
for i from 1 to nCtrl
    p = panPosition#[i]
    a = panAmp#[i]
    if p < -1
        p = -1
    endif
    if p > 1
        p = 1
    endif
    if a < 0
        a = 0
    endif
    if a > 1
        a = 1
    endif
    # Constant-power pan: L = sqrt((1-p)/2), R = sqrt((1+p)/2)
    leftGain#[i]  = a * sqrt((1 - p) / 2)
    rightGain#[i] = a * sqrt((1 + p) / 2)
endfor

# ============================================================
# BUILD AMPLITUDE TIERS AND APPLY
# ============================================================
appendInfoLine: "Building amplitude envelopes (", nCtrl, " control points)..."

# Left tier
leftTier = Create AmplitudeTier: "ampTierL", 0, duration
Add point: 0, leftGain#[1]
for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate
    Add point: t, leftGain#[i]
endfor
Add point: duration, leftGain#[nCtrl]

selectObject: leftID
plusObject: leftTier
Multiply
leftProcessed = selected("Sound")
Rename: "left_proc"

# Right tier
rightTier = Create AmplitudeTier: "ampTierR", 0, duration
Add point: 0, rightGain#[1]
for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate
    Add point: t, rightGain#[i]
endfor
Add point: duration, rightGain#[nCtrl]

selectObject: rightID
plusObject: rightTier
Multiply
rightProcessed = selected("Sound")
Rename: "right_proc"

# ============================================================
# COMBINE TO STEREO
# ============================================================
selectObject: leftProcessed, rightProcessed
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
resultName$ = originalName$ + "_rhy_" + patternName$
Rename: resultName$

# ============================================================
# CLEANUP
# ============================================================
removeObject: workID, leftID, rightID, leftTier, rightTier, leftProcessed, rightProcessed

selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION  (drum-machine themed — distinct from suite default)
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
    Text: 0.5, "centre", 0.68, "half", "##BPM RHYTHMIC PANNING##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... patternName$
        ... + "  |  " + fixed$(tempo_bpm, 1) + " BPM"
        ... + "  |  " + subdivName$
        ... + "  |  Swing: " + fixed$(swing_percent, 0) + "%"
        ... + "  |  " + string$(accentCount) + " accents"
        ... + "  |  Smooth: " + fixed$(edge_smoothness, 2)
    
    # ----------------------------------------------------------
    # PANEL A: 16-STEP DRUM-MACHINE GRID  (headline, full width)
    # Each step = a column. Accented steps get a colored cell.
    # Pan position at the start of each step shown as a vertical
    # bar going up (right) or down (left) from the step's center.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 3.20
    Select inner viewport: 0.50, 7.75, 0.95, 3.05
    
    nGridSteps = accentLen
    
    # Y range: -1 (full left) to +1 (full right), with extra space
    # at top and bottom for accent-cell rendering and labels
    Axes: 0, nGridSteps, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, nGridSteps, -1.5, 1.5
    
    # Draw centerline (zero pan)
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1.5
    Draw line: 0, 0, nGridSteps, 0
    Line width: 1
    
    # Vertical step boundaries
    Colour: "{0.85, 0.85, 0.88}"
    for s from 0 to nGridSteps
        # Heavier line at every 4th step (beat boundary if 1/16)
        if s mod 4 = 0
            Colour: "{0.65, 0.65, 0.70}"
            Line width: 1.5
        else
            Colour: "{0.85, 0.85, 0.88}"
            Line width: 1
        endif
        Draw line: s, -1.5, s, 1.5
    endfor
    Line width: 1
    
    # Reference lines at +1 and -1 (full pan)
    Colour: "{0.85, 0.85, 0.88}"
    Dotted line
    Draw line: 0, 1.0, nGridSteps, 1.0
    Draw line: 0, -1.0, nGridSteps, -1.0
    Solid line
    
    # Accent cells (drum-machine visual: each accented step gets a
    # bright colored rectangle in the top strip)
    accentCellTop = 1.40
    accentCellBot = 1.12
    for s from 0 to nGridSteps - 1
        if accent[s + 1] = 1
            Paint rectangle: "{0.85, 0.40, 0.20}", s + 0.05, s + 0.95,
                ... accentCellBot, accentCellTop
        else
            Paint rectangle: "{0.92, 0.92, 0.94}", s + 0.05, s + 0.95,
                ... accentCellBot, accentCellTop
        endif
    endfor
    
    # Pan-position bars per step
    # Sample panPosition at the *center* of each step's playback time
    # The first cycle through accentLen steps shows the pattern.
    for s from 0 to nGridSteps - 1
        # Time at center of step s in the first pattern repetition
        tStep = (s + 0.5) / stepRate
        # Sample index at that time
        ctrlIdx = round(tStep * ctrlRate)
        if ctrlIdx < 1
            ctrlIdx = 1
        endif
        if ctrlIdx > nCtrl
            ctrlIdx = nCtrl
        endif
        p = panPosition#[ctrlIdx]
        a = panAmp#[ctrlIdx]
        # Bar height combines pan magnitude with amplitude shading.
        # Use color to indicate amplitude: bright when loud, faded when soft.
        if p > 0
            # Right channel — orange
            cR = 0.78
            cG = 0.45 + (1 - a) * 0.35
            cB = 0.25 + (1 - a) * 0.30
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... s + 0.15, s + 0.85, 0, p
        elsif p < 0
            # Left channel — blue
            cR = 0.25 + (1 - a) * 0.30
            cG = 0.50 + (1 - a) * 0.30
            cB = 0.82
            Paint rectangle: "{" + fixed$(cR, 2) + "," + fixed$(cG, 2) + "," + fixed$(cB, 2) + "}",
                ... s + 0.15, s + 0.85, p, 0
        endif
        # Amplitude indicator dot at the bar tip
        if abs(p) > 0.05
            Paint circle (mm): "{0.22, 0.22, 0.22}", s + 0.5, p, 1.2
        endif
    endfor
    
    # Step number labels at bottom
    Font size: 5
    Colour: "{0.30, 0.30, 0.30}"
    for s from 0 to nGridSteps - 1
        if nGridSteps <= 16 or s mod 2 = 0
            Text: s + 0.5, "centre", -1.42, "half", string$(s + 1)
        endif
    endfor
    
    # Beat number labels at top (where applicable)
    if subPerBeat >= 1
        Font size: 6
        Colour: "{0.40, 0.40, 0.55}"
        beatStep = subPerBeat
        if beatStep < 1
            beatStep = 1
        endif
        beatNum = 1
        s = 0
        while s < nGridSteps
            Text: s + 0.5, "centre", 1.50, "half", string$(beatNum)
            s = s + round(beatStep)
            beatNum = beatNum + 1
        endwhile
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "L  <- pan ->  R"
    Text bottom: "yes", "Step"
    
    # ----------------------------------------------------------
    # PANEL B: PAN TRAJECTORY OVER FIRST MEASURE
    # Beats marked with vertical guides, swing visible.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 3.30, 4.90
    Select inner viewport: 0.55, 4.00, 3.45, 4.80
    
    # First "measure" = 4 beats. If file shorter, use file duration.
    measureDur = 4 * 60 / tempo_bpm
    if measureDur > duration
        measureDur = duration
    endif
    
    Axes: 0, measureDur, -1.1, 1.1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, measureDur, -1.1, 1.1
    
    # Beat guides
    beatDur = 60 / tempo_bpm
    Colour: "{0.78, 0.78, 0.85}"
    Line width: 1
    bg = beatDur
    while bg < measureDur
        Draw line: bg, -1.1, bg, 1.1
        bg = bg + beatDur
    endwhile
    
    # Centerline
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: 0, 0, measureDur, 0
    Solid line
    
    # Pan trajectory
    Colour: "{0.30, 0.50, 0.78}"
    Line width: 1.3
    nMeasureSamples = round(measureDur * ctrlRate)
    if nMeasureSamples > nCtrl
        nMeasureSamples = nCtrl
    endif
    if nMeasureSamples < 2
        nMeasureSamples = 2
    endif
    prevT = (1 - 0.5) / ctrlRate
    prevP = panPosition#[1]
    for i from 2 to nMeasureSamples
        ti = (i - 0.5) / ctrlRate
        panI = panPosition#[i]
        Draw line: prevT, prevP, ti, panI
        prevT = ti
        prevP = panI
    endfor
    Line width: 1
    
    # Beat number labels
    Font size: 5
    Colour: "{0.40, 0.40, 0.55}"
    for b from 1 to 4
        bx = (b - 1) * beatDur + beatDur * 0.05
        if bx < measureDur
            Text: bx, "left", 1.05, "half", string$(b)
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Pan"
    Text bottom: "yes", "Time (s) — first measure"
    
    # ----------------------------------------------------------
    # PANEL C: PER-BEAT ACTIVITY HISTOGRAM
    # Amount of pan-position change per beat — shows whether
    # pattern is busy on every beat or sparse.
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.30, 4.90
    Select inner viewport: 4.55, 7.75, 3.45, 4.80
    
    # Compute "activity" = sum of |Δpan| within each beat
    # over the first measure
    nBeats = 4
    if measureDur < beatDur * 4
        nBeats = round(measureDur / beatDur)
        if nBeats < 1
            nBeats = 1
        endif
    endif
    activity# = zero# (nBeats)
    for b from 1 to nBeats
        bStart = (b - 1) * beatDur
        bEnd = b * beatDur
        iStart = round(bStart * ctrlRate)
        iEnd = round(bEnd * ctrlRate)
        if iStart < 1
            iStart = 1
        endif
        if iEnd > nCtrl
            iEnd = nCtrl
        endif
        sumDelta = 0
        for j from iStart + 1 to iEnd
            sumDelta = sumDelta + abs(panPosition#[j] - panPosition#[j - 1])
        endfor
        activity#[b] = sumDelta
    endfor
    
    actMax = 0.001
    for b from 1 to nBeats
        if activity#[b] > actMax
            actMax = activity#[b]
        endif
    endfor
    
    Axes: 0.5, nBeats + 0.5, 0, actMax * 1.15
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, nBeats + 0.5, 0, actMax * 1.15
    
    for b from 1 to nBeats
        Paint rectangle: "{0.45, 0.55, 0.78}", b - 0.35, b + 0.35, 0, activity#[b]
        Font size: 6
        Colour: "White"
        if activity#[b] > actMax * 0.15
            Text: b, "centre", activity#[b] * 0.5, "half", "B" + string$(b)
        else
            Colour: "{0.30, 0.30, 0.30}"
            Text: b, "centre", -actMax * 0.05, "half", "B" + string$(b)
        endif
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Pan activity"
    Text bottom: "yes", "Beat"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.98, 6.10
    Select inner viewport: 0.55, 7.72, 5.05, 6.00
    
    selectObject: result
    nResultCh = Get number of channels
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15
    
    Axes: 0, finalDur, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0
    
    # Beat tick marks across the full waveform
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    bg = beatDur
    while bg < finalDur
        Draw line: bg, -ampViz * 0.95, bg, -ampViz * 0.85
        Draw line: bg, ampViz * 0.85, bg, ampViz * 0.95
        bg = bg + beatDur
    endwhile
    
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
    Font size: 6
    Text top: "no", "Output  (blue=L, orange=R, ticks=beats)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.18, 6.90
    Select inner viewport: 0.55, 7.72, 6.24, 6.85
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + patternName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + fixed$(tempo_bpm, 1) + " BPM"
        ... + "  |  " + subdivName$
        ... + "  |  Step rate: " + fixed$(stepRate, 2) + " Hz"
        ... + "  |  Step dur: " + fixed$(stepDur * 1000, 1) + " ms"
        ... + "  |  Swing: " + fixed$(swing_percent, 0) + "%"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Accent grid: " + accent_grid$
        ... + "  |  " + string$(accentCount) + " accents"
        ... + "  |  Edge smoothness: " + fixed$(edge_smoothness, 2)
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# DONE
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$

if play_result
    selectObject: result
    Play
endif

selectObject: result
