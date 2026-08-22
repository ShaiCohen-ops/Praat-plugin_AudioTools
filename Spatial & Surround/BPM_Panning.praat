# ============================================================
# Praat AudioTools - BPM_Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# v0.5.1 (2026): RUNTIME VISUAL QA - stacked-panel gaps and summary rows corrected; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BPM-locked rhythmic stereo panning. Where BPM_SURROUND_Panning is
#   about WHERE in 3D space, this is about WHEN in the bar: beat-locked
#   figures, swing, accent grids, polyrhythms and gates.
#
#   Deliberately stereo-only. Left/right, ping-pong and stereo
#   polyrhythms are the identity of this tool; quad or 8-channel output
#   would need a spatial model, not extra routing, and that belongs in
#   a separate BPM surround script.
#
# Changelog v0.5.1 (2026):
#   - FIX (critical): SWING DID NOTHING. swingFrac was computed and
#     then, in the odd-step branch, immediately overwritten with
#     stepFrac - and no pattern read it in any case, so moving
#     Swing_percent changed no sample of the output while the form and
#     the plot presented it as a headline parameter.
#     Swing now warps the STEP BOUNDARIES, which is what swing is. Each
#     pair of steps keeps its total length; the internal boundary moves
#     from the midpoint to a fraction s of the pair:
#       u = position within the pair, 0..2
#       u < 2s  -> first step,  frac = u / (2s)
#       u >= 2s -> second step, frac = (u - 2s) / (2 - 2s)
#     The scale is now the conventional one:
#       50%   = straight (equal halves)
#       66.7% = triplet swing (2:1)
#       75%   = hard shuffle (3:1)
#     v0.3 labelled 0% straight, 50% triplet, 66% hard shuffle, and its
#     own documented formula would have given 75:25 at "50% triplet"
#     rather than 66.7:33.3.
#     Swing applies to the step-clock patterns: Ping-pong, Trance gate,
#     Pulse train, Ghost notes, Stutter, Roll, and the polyrhythms that
#     derive from the subdivision. It does NOT apply to patterns with
#     their own independent clock - Hat 16ths, Dotted dub, Backbeat
#     snap, the pendulums, Phrase build, Polymeter shift - and the
#     report says which is which.
#   - FIX (critical): STEREO INPUT WAS NEVER PANNED. A stereo source
#     had the left envelope applied to its own left channel and the
#     right envelope to its own right channel, which is balance
#     modulation, not panning: material sitting only in the right
#     channel does not move left when the pattern calls for hard left,
#     it simply disappears. Stereo_input now defaults to downmixing to
#     mono and panning that, so every pattern really does place all the
#     source material. The old behaviour is kept as an explicit second
#     option, named Preserve stereo and modulate balance.
#   - FIX: the control rate was fixed at 100 Hz regardless of tempo. At
#     120 BPM with 1/32 that is 6.25 points per step, and Stutter
#     divides a step by four, leaving 1.56 points per sub-step. At
#     300 BPM 1/32 it is 2.5 per step; at 999 BPM the step rate itself
#     (133 Hz) exceeds the control rate and the rhythm aliases. The
#     control rate is now derived from the fastest event the chosen
#     pattern can produce, at 24 points per event, floored at 200 Hz
#     and capped for practicality, and the achieved points-per-event is
#     reported.
#   - FIX: Dotted dub used beat * 8/3, firing every 3/8 of a beat -
#     twice as fast as a dotted eighth. A dotted eighth is 3/4 of a
#     quarter, so the rate is beat * 4/3, one event every 3 sixteenths.
#     Its envelope also faded IN across each event, which is backwards
#     for a dub delay; it now strikes at the onset and decays.
#   - FIX: 3-against-4 was inverted. Pulsing left every 3 steps and
#     right every 4 gives, over a 12-step cycle, four events on the
#     left and three on the right - i.e. 4-against-3. Left now pulses
#     every 4 steps and right every 3, so the left really carries 3 and
#     the right 4.
#   - FIX: Ping-pong could repeat a side. It alternated on stepIdx,
#     which resets at the end of the accent grid, so an odd grid length
#     (15, 7, ...) put the same side at the end of one cycle and the
#     start of the next. Alternation now uses the global step index,
#     which never resets. Same fix applied to Trance gate.
#   - FIX: the plot drew a heavy beat line every 4 steps, which is only
#     correct for 1/16. Beat lines are now placed by time, t = b*60/BPM,
#     so they land correctly for 1/8, triplets and the dotted
#     subdivisions, where steps per beat is not even an integer.
#   - FIX: the input time domain was not normalised to 0 while the
#     AmplitudeTiers always started at 0, so anything extracted with
#     preserved times would be misaligned.
#   - RENAME, for accuracy:
#       "Quarter swing" completes one cycle every two beats and uses no
#         swing at all -> Two-beat pendulum.
#       "Half-bar arc" completes a cycle every eight beats, which is two
#         bars of 4/4, not half a bar -> Two-bar arc.
#       "5-against-7 (proper hemiola)" is correctly built - five and
#         seven cycles across the same 16 steps - but hemiola means 3:2,
#         so the word is dropped.
#   - RENAME: Edge_smoothness -> Edge_transition_percent, expressed as a
#     percentage of a STEP. v0.3's one-pole coefficient was tied to the
#     fixed control rate and had no musical unit, so the same setting
#     meant different things at 60 and 240 BPM. It is now a time
#     constant equal to that percentage of the step duration, so it
#     scales with tempo. Note that even at 0 the AmplitudeTier still
#     interpolates linearly between control points, so gates are very
#     fast rather than mathematically square - stated rather than
#     claimed otherwise.
#   - NEW: Output_normalisation - Peak (the v0.3 behaviour), Attenuate
#     only, or None. Peak is still the default and still applies one
#     shared gain to both channels, so the panning ratios, the gates
#     and the constant-power law all survive; it only removes level
#     differences between renders of different patterns.
#   - NOTE: Trance gate and Pulse train do not gate from silence. The
#     trance envelope floors at 0.1 and the Gaussian pulse is already
#     at 0.51 at the step onset, so both are modulation between a high
#     and a low level rather than on/off. Left alone sonically, but
#     described accurately.
#
# Changelog v0.3:
#   - Identity overhaul from abstract cycles to BPM + subdivision +
#     swing + accent grid; 15 rhythmic patterns; drum-machine plot.
# ============================================================

# ============================================================
# INPUT VALIDATION (before the form)
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form BPM Rhythmic Panning v0.5.1
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

    comment === SWING (50 = straight, 66.7 = triplet, 75 = hard shuffle) ===
    real Swing_percent 50
    sentence Accent_grid 1010100110101001

    comment === RHYTHMIC PATTERN ===
    optionmenu Pattern: 1
        option: "1.  Ping-pong (hard L/R alternation)"
        option: "2.  Two-beat pendulum (was Quarter swing)"
        option: "3.  Backbeat snap (hits on 2 and 4)"
        option: "4.  Hat 16ths (fast stereo texture)"
        option: "5.  Dotted dub (dotted-8th delay rhythm)"
        option: "6.  Trance gate (accent-driven level modulation)"
        option: "7.  Pulse train (gaussian pulses on accents)"
        option: "8.  Ghost notes (loud on accent, half elsewhere)"
        option: "9.  Stutter (double-pan on accent)"
        option: "10. Roll (accent triggers L->R sweep)"
        option: "11. 3-against-4 (left=3, right=4)"
        option: "12. 5-against-7 (5 and 7 across 16 steps)"
        option: "13. Two-bar arc (was Half-bar arc)"
        option: "14. Phrase build (4-bar amplitude grow)"
        option: "15. Polymeter shift (5/4 against the bar)"

    comment === SHAPING ===
    real Edge_transition_percent 12

    comment === INPUT / OUTPUT ===
    optionmenu Stereo_input: 1
        option: "Downmix to mono and pan (true panning)"
        option: "Preserve stereo and modulate balance"
    optionmenu Output_normalisation: 1
        option: "Peak (scale to target)"
        option: "Attenuate only (never boost)"
        option: "None"
    real Peak_target 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if tempo_bpm < 1 or tempo_bpm > 999
    exitScript: "BPM must be between 1 and 999."
endif

# v0.5: conventional swing scale. 50 is straight; below 50 is a
# reverse-swing feel, which is legal but unusual.
if swing_percent < 25
    swing_percent = 25
endif
if swing_percent > 75
    swing_percent = 75
endif
swingS = swing_percent / 100

if edge_transition_percent < 0
    edge_transition_percent = 0
endif
if edge_transition_percent > 100
    edge_transition_percent = 100
endif

if peak_target <= 0 or peak_target > 1
    peak_target = 0.95
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
inputCh = Get number of channels
sr = Get sampling frequency
srcT0 = Get start time
srcT1 = Get end time

if inputCh > 2
    exitScript: "Please use a mono or stereo source."
endif

# v0.5: the AmplitudeTiers are built from 0, so the working copy has to
# start there too.
selectObject: originalID
Copy: "bpm_work0"
prepID = selected("Sound")
selectObject: prepID
workT0 = Get start time
if workT0 <> 0
    selectObject: prepID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: prepID
    prepID = shiftedID
endif
selectObject: prepID
duration = Get total duration

if duration <= 0
    removeObject: prepID
    exitScript: "Source has zero duration."
endif

# v0.5: how the stereo field is handled. Downmixing and panning the
# result is true panning; keeping the two channels apart and gating
# each is balance modulation, which cannot move material across the
# image - it can only remove it.
if stereo_input = 1
    if inputCh = 2
        selectObject: prepID
        Convert to mono
        monoID = selected("Sound")
        removeObject: prepID
        prepID = monoID
    endif
    selectObject: prepID
    Copy: "bpm_L"
    leftID = selected("Sound")
    selectObject: prepID
    Copy: "bpm_R"
    rightID = selected("Sound")
    inputMode$ = "downmix to mono, true panning"
else
    if inputCh = 1
        selectObject: prepID
        Copy: "bpm_L"
        leftID = selected("Sound")
        selectObject: prepID
        Copy: "bpm_R"
        rightID = selected("Sound")
        inputMode$ = "mono source, true panning"
    else
        selectObject: prepID
        Extract one channel: 1
        leftID = selected("Sound")
        selectObject: prepID
        Extract one channel: 2
        rightID = selected("Sound")
        inputMode$ = "stereo preserved, BALANCE modulation (not panning)"
    endif
endif

# ============================================================
# SUBDIVISION
# ============================================================
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

beatRate = tempo_bpm / 60
stepRate = beatRate * subPerBeat
stepDur = 1 / stepRate

# ============================================================
# ACCENT GRID
# ============================================================
accentLen = length(accent_grid$)
if accentLen < 1
    accent_grid$ = "1000100010001000"
    accentLen = 16
endif
if accentLen > 32
    accentLen = 32
    accent_grid$ = left$(accent_grid$, 32)
endif

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
# PATTERN NAMES AND CLOCKS
# ============================================================
patternNames$[1]  = "Pingpong"
patternNames$[2]  = "TwoBeatPendulum"
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
patternNames$[13] = "TwoBarArc"
patternNames$[14] = "PhraseBuild"
patternNames$[15] = "PolymeterShift"
patternName$ = patternNames$[pattern]

# v0.5: swing warps the subdivision grid, so it reaches only the
# patterns that read that grid. Patterns with their own clock are
# unaffected, and the report says so rather than leaving the user to
# wonder why the control does nothing.
usesSwing = 0
if pattern = 1 or pattern = 6 or pattern = 7 or pattern = 8
    usesSwing = 1
elsif pattern = 9 or pattern = 10 or pattern = 11 or pattern = 12
    usesSwing = 1
endif

# Fastest event this pattern can produce, for the control rate.
if pattern = 9
    eventRate = stepRate * 4
elsif pattern = 4 or pattern = 13
    eventRate = beatRate * 4
elsif pattern = 5
    eventRate = beatRate * 4 / 3
elsif pattern = 2 or pattern = 3 or pattern = 15
    eventRate = beatRate
elsif pattern = 14
    eventRate = beatRate * 2
elsif pattern = 11
    eventRate = stepRate / 3
elsif pattern = 12
    eventRate = stepRate * 7 / 16
else
    eventRate = stepRate
endif
if eventRate < beatRate
    eventRate = beatRate
endif

# v0.5: control rate follows the music instead of sitting at 100 Hz.
ptsPerEvent = 24
ctrlRate = ptsPerEvent * eventRate
if ctrlRate < 200
    ctrlRate = 200
endif
ctrlCapped = 0
if ctrlRate > 6000
    ctrlRate = 6000
    ctrlCapped = 1
endif

nCtrl = round(duration * ctrlRate)
if nCtrl < 8
    nCtrl = 8
endif
nCtrlCapped = 0
if nCtrl > 400000
    nCtrl = 400000
    nCtrlCapped = 1
    ctrlRate = nCtrl / duration
endif
achievedPts = ctrlRate / eventRate

# ============================================================
# EDGE TRANSITION
# ============================================================
# A one-pole whose time constant is a percentage of the STEP, so the
# same setting means the same musical thing at any tempo. v0.3's
# coefficient was tied to the fixed 100 Hz control rate and had no
# musical unit.
edgeTau = edge_transition_percent / 100 * stepDur
if edgeTau > 0
    edgeAlpha = 1 - exp(-(1 / ctrlRate) / edgeTau)
    if edgeAlpha > 1
        edgeAlpha = 1
    endif
    if edgeAlpha < 0.0001
        edgeAlpha = 0.0001
    endif
else
    edgeAlpha = 1
endif

panPosition# = zero# (nCtrl)
panAmp# = zero# (nCtrl)
leftGain# = zero# (nCtrl)
rightGain# = zero# (nCtrl)

# ============================================================
# GENERATE ENVELOPES
# ============================================================
stopwatch
for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate

    # --- straight grid ---
    rawStepF = t * stepRate
    rawStepIdx = floor(rawStepF)

    # --- swing: move the boundary inside each pair of steps ---
    # The pair keeps its total length; the internal boundary sits at
    # 2*s of the pair instead of at the midpoint. s = 0.5 is straight.
    pairIdx = floor(rawStepF / 2)
    uPair = rawStepF - pairIdx * 2
    if usesSwing = 1
        boundary = 2 * swingS
        if uPair < boundary
            swStepIdx = pairIdx * 2
            if boundary > 0
                stepFrac = uPair / boundary
            else
                stepFrac = 0
            endif
        else
            swStepIdx = pairIdx * 2 + 1
            if boundary < 2
                stepFrac = (uPair - boundary) / (2 - boundary)
            else
                stepFrac = 0
            endif
        endif
    else
        swStepIdx = rawStepIdx
        stepFrac = rawStepF - rawStepIdx
    endif

    globalStep = swStepIdx
    stepIdx = globalStep mod accentLen
    if stepIdx < 0
        stepIdx = stepIdx + accentLen
    endif
    stepF = globalStep + stepFrac

    beatF = t * beatRate
    beatIdx = floor(beatF)
    beatFrac = beatF - beatIdx
    barF = beatF / 4
    barIdx = floor(barF)
    barFrac = barF - barIdx

    isAccent = accent[stepIdx + 1]

    if pattern = 1
        # 1. PING-PONG. v0.5: alternate on the GLOBAL step index, which
        # never resets, so an odd accent-grid length cannot put the
        # same side at the end of one cycle and the start of the next.
        if globalStep mod 2 = 0
            panPosition#[i] = -1.0
        else
            panPosition#[i] = 1.0
        endif
        panAmp#[i] = 1.0

    elsif pattern = 2
        # 2. TWO-BEAT PENDULUM. One full cycle every two beats. Its own
        # clock, so swing does not apply.
        panPosition#[i] = sin(pi * beatF)
        panAmp#[i] = 1.0

    elsif pattern = 3
        # 3. BACKBEAT SNAP
        twoBeatPhase = beatF mod 2
        pulseSharp = exp(-25 * (twoBeatPhase - 1.0)^2)
        fourBeatPhase = beatF mod 4
        if fourBeatPhase >= 2
            snapSign = 1
        else
            snapSign = -1
        endif
        panPosition#[i] = snapSign * pulseSharp
        panAmp#[i] = 0.4 + 0.6 * pulseSharp

    elsif pattern = 4
        # 4. HAT 16THS. Own 16th clock regardless of subdivision.
        sixteenthF = beatF * 4
        sixteenthIdx = floor(sixteenthF)
        sixteenthFrac = sixteenthF - sixteenthIdx
        if sixteenthIdx mod 2 = 0
            panPosition#[i] = -0.85
        else
            panPosition#[i] = 0.85
        endif
        panAmp#[i] = 0.5 + 0.5 * exp(-8 * (sixteenthFrac - 0.2)^2)

    elsif pattern = 5
        # 5. DOTTED DUB. v0.5: a dotted eighth is 3/4 of a quarter, so
        # the rate is beat * 4/3 - one event every 3 sixteenths. v0.3
        # used 8/3, firing twice as fast, every 3/8 of a beat. The
        # envelope also faded IN across each event; a dub delay strikes
        # at the onset and decays, so it now does.
        dottedF = beatF * 4 / 3
        dottedIdx = floor(dottedF)
        dottedFrac = dottedF - dottedIdx
        if dottedIdx mod 2 = 0
            panPosition#[i] = -0.7
        else
            panPosition#[i] = 0.7
        endif
        panAmp#[i] = 0.25 + 0.75 * exp(-4 * dottedFrac)

    elsif pattern = 6
        # 6. TRANCE GATE. Level modulation driven by the accent grid -
        # it floors at 0.1 rather than gating from silence.
        if isAccent = 1
            if globalStep mod 2 = 0
                panPosition#[i] = -0.9
            else
                panPosition#[i] = 0.9
            endif
            envShape = exp(-2 * (stepFrac - 0.3)^2)
            panAmp#[i] = 0.1 + 0.9 * envShape
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.05
        endif

    elsif pattern = 7
        # 7. PULSE TRAIN. The Gaussian is already at about 0.51 at the
        # step onset, so each event swells rather than striking.
        if isAccent = 1
            pulse = exp(-30 * (stepFrac - 0.15)^2)
            phase = (stepIdx + stepFrac) / accentLen * 2 * pi
            panPosition#[i] = 0.85 * sin(phase)
            panAmp#[i] = 0.15 + 0.85 * pulse
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.1
        endif

    elsif pattern = 8
        # 8. GHOST NOTES
        panPosition#[i] = 0.6 * sin(2 * pi * beatF / 4)
        if isAccent = 1
            panAmp#[i] = 0.95
        else
            panAmp#[i] = 0.45
        endif

    elsif pattern = 9
        # 9. STUTTER. Four sub-steps inside an accented step - the
        # fastest event in the script, which is what sets the control
        # rate for this pattern.
        if isAccent = 1
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
        # 10. ROLL
        if isAccent = 1
            panPosition#[i] = -0.9 + 1.8 * stepFrac
            panAmp#[i] = 0.3 + 0.7 * exp(-3 * (stepFrac - 0.4)^2)
        else
            panPosition#[i] = 0
            panAmp#[i] = 0.5
        endif

    elsif pattern = 11
        # 11. 3-AGAINST-4. v0.5: to put THREE events on the left and
        # FOUR on the right over a 12-step cycle, the left has to pulse
        # every 4 steps and the right every 3. v0.3 had it the other
        # way round, so the label was inverted.
        leftPeriod = 4
        rightPeriod = 3
        leftPhase = stepF / leftPeriod
        leftFrac = leftPhase - floor(leftPhase)
        rightPhase = stepF / rightPeriod
        rightFrac = rightPhase - floor(rightPhase)
        leftPulse = exp(-5 * (leftFrac - 0.15)^2)
        rightPulse = exp(-5 * (rightFrac - 0.15)^2)
        panPosition#[i] = rightPulse - leftPulse
        panAmp#[i] = 0.3 + 0.7 * max(leftPulse, rightPulse)

    elsif pattern = 12
        # 12. 5-AGAINST-7. Five and seven cycles across the same 16
        # steps - correctly built in v0.3; only the word "hemiola" was
        # wrong, since hemiola means 3:2.
        leftPhase = stepF / (16/5)
        leftFrac = leftPhase - floor(leftPhase)
        rightPhase = stepF / (16/7)
        rightFrac = rightPhase - floor(rightPhase)
        leftPulse = exp(-6 * (leftFrac - 0.15)^2)
        rightPulse = exp(-6 * (rightFrac - 0.15)^2)
        panPosition#[i] = rightPulse - leftPulse
        panAmp#[i] = 0.3 + 0.7 * max(leftPulse, rightPulse)

    elsif pattern = 13
        # 13. TWO-BAR ARC. sin(pi*beatF/4) completes a full cycle every
        # eight beats, which is two bars of 4/4 - not half a bar.
        slowSwing = sin(pi * beatF / 4)
        sixteenthMod = 0.7 + 0.3 * sin(2 * pi * beatF * 4)
        panPosition#[i] = slowSwing * 0.85
        panAmp#[i] = sixteenthMod

    elsif pattern = 14
        # 14. PHRASE BUILD
        phraseStep = barIdx mod 4
        phraseProgress = (phraseStep + barFrac) / 4
        panPosition#[i] = 0.85 * sin(2 * pi * beatF * 2)
        panAmp#[i] = 0.2 + 0.8 * phraseProgress

    else
        # 15. POLYMETER SHIFT
        polyPhase = beatF / 5
        polyIdx = floor(polyPhase)
        polyFrac = polyPhase - polyIdx
        polyStep = floor(polyFrac * 5)
        polyStepFrac = polyFrac * 5 - polyStep
        panPosition#[i] = -0.85 + (polyStep / 4) * 1.7
        panAmp#[i] = 0.3 + 0.7 * exp(-5 * (polyStepFrac - 0.2)^2)
    endif

    # --- edge transition: one-pole with a musical time constant ---
    if edgeAlpha < 1 and i > 1
        panAmp#[i] = edgeAlpha * panAmp#[i] + (1 - edgeAlpha) * panAmp#[i - 1]
        panPosition#[i] = edgeAlpha * panPosition#[i] + (1 - edgeAlpha) * panPosition#[i - 1]
    endif
endfor
envElapsed = stopwatch

# ============================================================
# PAN LAW
# ============================================================
# gL = a*sqrt((1-p)/2), gR = a*sqrt((1+p)/2), so gL^2 + gR^2 = a^2:
# constant power relative to the pattern's own amplitude envelope.
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
    leftGain#[i] = a * sqrt((1 - p) / 2)
    rightGain#[i] = a * sqrt((1 + p) / 2)
endfor

# ============================================================
# APPLY
# ============================================================
stopwatch
leftTier = Create AmplitudeTier: "bpmTierL", 0, duration
Add point: 0, leftGain#[1]
for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate
    if t < duration
        Add point: t, leftGain#[i]
    endif
endfor
Add point: duration, leftGain#[nCtrl]

selectObject: leftID
plusObject: leftTier
Multiply
leftProcessed = selected("Sound")
Rename: "bpm_left_proc"

rightTier = Create AmplitudeTier: "bpmTierR", 0, duration
Add point: 0, rightGain#[1]
for i from 1 to nCtrl
    t = (i - 0.5) / ctrlRate
    if t < duration
        Add point: t, rightGain#[i]
    endif
endfor
Add point: duration, rightGain#[nCtrl]

selectObject: rightID
plusObject: rightTier
Multiply
rightProcessed = selected("Sound")
Rename: "bpm_right_proc"

selectObject: leftProcessed, rightProcessed
Combine to stereo
result = selected("Sound")
resultName$ = originalName$ + "_rhy_" + patternName$
Rename: resultName$

# v0.5: three normalisation choices. Peak is the v0.3 behaviour and
# still applies ONE shared gain to both channels, so the panning
# ratios, the gates and the constant-power law all survive; it only
# removes level differences between renders of different patterns.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
normGain = 1
if output_normalisation = 1
    if prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "peak (scaled to target)"
elsif output_normalisation = 2
    if prePeak > peak_target and prePeak > 0
        normGain = peak_target / prePeak
    endif
    normMode$ = "attenuate only"
else
    normMode$ = "none"
endif
if normGain <> 1
    selectObject: result
    Formula: "self * " + fixed$(normGain, 10)
endif
selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration

applyElapsed = stopwatch

removeObject: prepID, leftID, rightID, leftTier, rightTier
removeObject: leftProcessed, rightProcessed

# ============================================================
# REPORT
# ============================================================
writeInfoLine: "=== BPM Rhythmic Panning v0.5.1 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ",
    ... inputCh, " ch @ ", sr, " Hz)"
appendInfoLine: "Input handling: ", inputMode$
if stereo_input = 2 and inputCh = 2
    appendInfoLine: "  WARNING: in this mode each envelope gates its own original"
    appendInfoLine: "  channel, so material that sits only on one side cannot move"
    appendInfoLine: "  across the image - it can only be turned down. That is balance"
    appendInfoLine: "  modulation, not panning. Use the downmix option for true panning."
endif
appendInfoLine: ""

appendInfoLine: "BPM ", fixed$(tempo_bpm, 1), "  |  ", subdivName$,
    ... "  |  step ", fixed$(stepRate, 2), " Hz = ", fixed$(stepDur * 1000, 1), " ms",
    ... "  |  ", fixed$(subPerBeat, 3), " steps/beat"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: "Accent grid (", accentLen, " steps, ", accentCount, " accents): ",
    ... accent_grid$
appendInfoLine: ""

appendInfoLine: "Swing: ", fixed$(swing_percent, 1), "%   (50 straight, 66.7 triplet, 75 hard)"
if usesSwing = 1
    firstPart = swingS * 100
    secondPart = 100 - firstPart
    appendInfoLine: "  Applied. Step pairs split ", fixed$(firstPart, 1), " : ",
        ... fixed$(secondPart, 1), " instead of 50 : 50."
    appendInfoLine: "  The pair keeps its total length; only the boundary inside it moves."
else
    appendInfoLine: "  NOT applied to this pattern: it runs on its own clock (beats,"
    appendInfoLine: "  16ths or dotted eighths), not on the swung subdivision grid."
endif
appendInfoLine: ""

appendInfoLine: "Control rate: ", fixed$(ctrlRate, 1), " Hz, ", nCtrl, " points"
appendInfoLine: "  Fastest event in this pattern: ", fixed$(eventRate, 2), " Hz"
appendInfoLine: "  Points per event: ", fixed$(achievedPts, 1), " (target ", ptsPerEvent, ")"
if ctrlCapped = 1 or nCtrlCapped = 1
    appendInfoLine: "  NOTE: the control rate hit its cap. At this tempo and"
    appendInfoLine: "        subdivision the pattern is near the limit of what a"
    appendInfoLine: "        control-rate envelope can resolve."
endif
appendInfoLine: "  v0.3 used a fixed 100 Hz, which at 120 BPM 1/32 gave 6.25 points"
appendInfoLine: "  per step and 1.56 per Stutter sub-step."
appendInfoLine: ""

appendInfoLine: "Edge transition: ", fixed$(edge_transition_percent, 1),
    ... "% of a step = ", fixed$(edgeTau * 1000, 2), " ms"
appendInfoLine: "  A time constant tied to the step, so it means the same musical"
appendInfoLine: "  thing at any tempo. Note that even at 0% the AmplitudeTier still"
appendInfoLine: "  interpolates linearly between control points (",
    ... fixed$(1000 / ctrlRate, 2), " ms apart), so"
appendInfoLine: "  gates are very fast rather than mathematically square."
appendInfoLine: ""

appendInfoLine: "Pan law: gL = a*sqrt((1-p)/2), gR = a*sqrt((1+p)/2)"
appendInfoLine: "  so gL^2 + gR^2 = a^2 - constant power relative to the pattern's"
appendInfoLine: "  own amplitude envelope."
appendInfoLine: "Normalisation: ", normMode$
appendInfoLine: "  Peak ", fixed$(prePeak, 4), " -> ", fixed$(finalPeak, 4),
    ... "   (gain x", fixed$(normGain, 4), ")"
appendInfoLine: ""
appendInfoLine: "(envelopes ", fixed$(envElapsed, 2), " s   apply ",
    ... fixed$(applyElapsed, 2), " s)"

# ============================================================
# VISUALIZATION  (drum-machine themed)
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
    Text: 0.5, "centre", 0.68, "half", "##BPM RHYTHMIC PANNING v0.5.1##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if usesSwing = 1
        swingTag$ = "Swing " + fixed$(swing_percent, 0) + "%"
    else
        swingTag$ = "Swing n/a"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... patternName$
        ... + "  |  " + fixed$(tempo_bpm, 1) + " BPM"
        ... + "  |  " + subdivName$
        ... + "  |  " + swingTag$
        ... + "  |  " + string$(accentCount) + " accents"
        ... + "  |  Edge " + fixed$(edge_transition_percent, 0) + "%"

    # ----------------------------------------------------------
    # PANEL A: STEP GRID  (headline, full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.75, 3.20
    Select inner viewport: 0.50, 7.75, 0.95, 3.05

    nGridSteps = accentLen
    Axes: 0, nGridSteps, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, nGridSteps, -1.5, 1.5

    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1.5
    Draw line: 0, 0, nGridSteps, 0
    Line width: 1

    # v0.5: step boundaries follow the swing, so the grid drawn here is
    # the grid the audio actually used.
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    for s from 0 to nGridSteps
        if usesSwing = 1
            sPair = floor(s / 2)
            if s - sPair * 2 = 0
                xPos = s
            else
                xPos = sPair * 2 + 2 * swingS
            endif
        else
            xPos = s
        endif
        Draw line: xPos, -1.5, xPos, 1.5
    endfor

    # v0.5: beat lines placed by TIME, t = b*60/BPM, converted to step
    # position. v0.3 drew a heavy line every 4 steps, which is only
    # right for 1/16 - and steps per beat is not even an integer for
    # the dotted subdivisions.
    Colour: "{0.60, 0.60, 0.68}"
    Line width: 1.5
    nBeatsShown = nGridSteps / subPerBeat
    for b from 0 to ceiling(nBeatsShown)
        bx = b * subPerBeat
        if bx <= nGridSteps
            Draw line: bx, -1.5, bx, 1.5
            Font size: 6
            Colour: "{0.45, 0.45, 0.50}"
            Text: bx, "centre", 1.36, "half", string$(b + 1)
            Colour: "{0.60, 0.60, 0.68}"
        endif
    endfor
    Line width: 1

    # Per-step cells: accent shading and pan direction
    for s from 0 to nGridSteps - 1
        tStep = s * stepDur
        if usesSwing = 1
            sPair = floor(s / 2)
            if s - sPair * 2 = 0
                xL = s
                xR = sPair * 2 + 2 * swingS
            else
                xL = sPair * 2 + 2 * swingS
                xR = sPair * 2 + 2
            endif
        else
            xL = s
            xR = s + 1
        endif
        xMid = (xL + xR) / 2

        # Sample the envelopes at the middle of this step
        iMid = round((xL + xR) / 2 * stepDur * ctrlRate)
        if iMid < 1
            iMid = 1
        endif
        if iMid > nCtrl
            iMid = nCtrl
        endif
        pv = panPosition#[iMid]
        av = panAmp#[iMid]

        if accent[s + 1] = 1
            Paint rectangle: "{0.90, 0.86, 0.72}", xL, xR, -1.5, 1.5
        endif

        if pv < 0
            barCol$ = "{0.25, 0.50, 0.82}"
        elsif pv > 0
            barCol$ = "{0.82, 0.45, 0.25}"
        else
            barCol$ = "{0.55, 0.60, 0.55}"
        endif
        cellA = xL + (xR - xL) * 0.18
        cellB = xR - (xR - xL) * 0.18
        Paint rectangle: barCol$, cellA, cellB, 0, pv * av
        Colour: "{0.35, 0.35, 0.35}"
        Draw rectangle: cellA, cellB, 0, pv * av

        Font size: 6
        Colour: "{0.40, 0.40, 0.40}"
        Text: xMid, "centre", -1.36, "half", string$(s + 1)
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Select outer viewport: 0.08, 0.52, 0.75, 3.2
    Select inner viewport: 0.08, 0.52, 0.77, 3.18
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "L  <-  pan  ->  R"
    Select outer viewport: 0, 8, 0.75, 3.2
    Select inner viewport: 0.5, 7.75, 0.95, 3.05
    Axes: 0, nGridSteps, -1.5, 1.5
    Text bottom: "yes", "Step  (shaded = accent, heavy lines = beats, bar height = pan x amp)"

    # ----------------------------------------------------------
    # PANEL B: PAN AND AMPLITUDE OVER THE FIRST BARS
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 3.30, 4.90
    Select inner viewport: 0.50, 3.98, 3.38, 4.78

    showDur = 8 * 60 / tempo_bpm
    if showDur > duration
        showDur = duration
    endif
    Axes: 0, showDur, -1.1, 1.1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, showDur, -1.1, 1.1

    Colour: "{0.86, 0.86, 0.86}"
    Draw line: 0, 0, showDur, 0

    # Beat ticks by time
    Colour: "{0.78, 0.78, 0.82}"
    for b from 0 to 16
        bt = b * 60 / tempo_bpm
        if bt <= showDur
            Draw line: bt, -1.1, bt, 1.1
        endif
    endfor

    nPlot = 400
    Line width: 1.5
    Colour: "{0.30, 0.35, 0.75}"
    for k from 1 to nPlot
        t1 = (k - 1) / nPlot * showDur
        t2 = k / nPlot * showDur
        i1 = round(t1 * ctrlRate)
        i2 = round(t2 * ctrlRate)
        if i1 < 1
            i1 = 1
        endif
        if i2 < 1
            i2 = 1
        endif
        if i1 > nCtrl
            i1 = nCtrl
        endif
        if i2 > nCtrl
            i2 = nCtrl
        endif
        Draw line: t1, panPosition#[i1], t2, panPosition#[i2]
    endfor
    Colour: "{0.85, 0.45, 0.20}"
    for k from 1 to nPlot
        t1 = (k - 1) / nPlot * showDur
        t2 = k / nPlot * showDur
        i1 = round(t1 * ctrlRate)
        i2 = round(t2 * ctrlRate)
        if i1 < 1
            i1 = 1
        endif
        if i2 < 1
            i2 = 1
        endif
        if i1 > nCtrl
            i1 = nCtrl
        endif
        if i2 > nCtrl
            i2 = nCtrl
        endif
        Draw line: t1, panAmp#[i1], t2, panAmp#[i2]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 0.08, 0.52, 3.3, 4.9
    Select inner viewport: 0.08, 0.52, 3.32, 4.88
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Pan / Amp"
    Select outer viewport: 0, 4.2, 3.3, 4.9
    Select inner viewport: 0.5, 3.98, 3.38, 4.78
    Axes: 0, showDur, -1.1, 1.1
    Text bottom: "yes", "Time (s), first 8 beats  (blue = pan, orange = amp)"

    # ----------------------------------------------------------
    # PANEL C: L AND R GAIN ENVELOPES
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.30, 4.90
    Select inner viewport: 4.55, 7.75, 3.38, 4.78

    Axes: 0, showDur, 0, 1.1
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, showDur, 0, 1.1

    Colour: "{0.78, 0.78, 0.82}"
    for b from 0 to 16
        bt = b * 60 / tempo_bpm
        if bt <= showDur
            Draw line: bt, 0, bt, 1.1
        endif
    endfor

    Line width: 1.5
    for k from 1 to nPlot
        t1 = (k - 1) / nPlot * showDur
        t2 = k / nPlot * showDur
        i1 = round(t1 * ctrlRate)
        i2 = round(t2 * ctrlRate)
        if i1 < 1
            i1 = 1
        endif
        if i2 < 1
            i2 = 1
        endif
        if i1 > nCtrl
            i1 = nCtrl
        endif
        if i2 > nCtrl
            i2 = nCtrl
        endif
        Colour: "{0.25, 0.50, 0.82}"
        Draw line: t1, leftGain#[i1], t2, leftGain#[i2]
        Colour: "{0.82, 0.45, 0.25}"
        Draw line: t1, rightGain#[i1], t2, rightGain#[i2]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 3.3, 4.9
    Select inner viewport: 4.02, 4.4, 3.32, 4.88
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 3.3, 4.9
    Select inner viewport: 4.55, 7.75, 3.38, 4.78
    Axes: 0, showDur, 0, 1.1
    Text bottom: "yes", "Channel gains  (blue = L, orange = R)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.10, 6.22
    Select inner viewport: 0.55, 7.75, 5.16, 6.15

    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    ampMax = resPeak * 1.15
    Axes: 0, finalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampMax, ampMax

    Colour: "{0.88, 0.88, 0.90}"
    nBeatTicks = floor(finalDur * tempo_bpm / 60)
    if nBeatTicks > 400
        nBeatTicks = 400
    endif
    for b from 0 to nBeatTicks
        bt = b * 60 / tempo_bpm
        if bt <= finalDur
            Draw line: bt, -ampMax, bt, ampMax
        endif
    endfor
    Colour: "{0.80, 0.80, 0.80}"
    Draw line: 0, 0, finalDur, 0

    selectObject: result
    Extract one channel: 1
    vizL = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

    selectObject: result
    Extract one channel: 2
    vizR = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizL, vizR

    Colour: "Black"
    Draw inner box
    Font size: 7
    Select outer viewport: 0.08, 0.52, 5.10, 6.22
    Select inner viewport: 0.08, 0.52, 5.12, 6.20
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Output"
    Select outer viewport: 0, 8, 5.10, 6.22
    Select inner viewport: 0.55, 7.75, 5.16, 6.15
    Axes: 0, finalDur, -ampMax, ampMax
    Text top: "no", "Output  (blue = L, orange = R, ticks = beats)"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.42, 7.44
    Select inner viewport: 0.55, 7.75, 6.48, 7.38
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + patternName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + fixed$(tempo_bpm, 1) + " BPM " + subdivName$
        ... + "  |  step " + fixed$(stepDur * 1000, 1) + " ms"
        ... + "  |  " + fixed$(finalDur, 2) + " s out"

    if usesSwing = 1
        swLine$ = "Swing " + fixed$(swing_percent, 1) + "% applied (" + fixed$(swingS * 100, 1) + ":" + fixed$(100 - swingS * 100, 1) + " pairs)"
    else
        swLine$ = "Swing not used by this pattern (own clock)"
    endif
    Text: 0.02, "left", 0.45, "half",
        ... swLine$
        ... + "  |  Ctrl " + fixed$(ctrlRate, 0) + " Hz = "
        ... + fixed$(achievedPts, 1) + " pts/event"
        ... + "  |  Edge " + fixed$(edgeTau * 1000, 1) + " ms"

    Text: 0.02, "left", 0.18, "half",
        ... "Input: " + inputMode$
        ... + "  |  Norm: " + normMode$
        ... + "  |  Peak " + fixed$(prePeak, 3) + " -> " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.54
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# DONE
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$, "  (stereo, ", fixed$(finalDur, 2), " s)"

if play_result
    selectObject: result
    Play
endif

selectObject: result
