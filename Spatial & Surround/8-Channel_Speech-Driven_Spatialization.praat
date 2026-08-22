# ============================================================
# Praat AudioTools - 8-Channel_Speech-Driven_Spatialization.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026)
# v0.6.1 (2026): RUNTIME VISUAL QA - summary row collision fixed; DSP unchanged.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Speech-Driven 8-Channel Spatialization.
#   Pitch drives azimuth around an octagon of speakers; intensity
#   drives a proximity gain. Constant-power panning between the two
#   adjacent speakers, plus a low coherent bed on the other six.
#   Output as octophonic, stems, or a geometric downmix.
#
#   Speaker layout (y up, angle 0 = front, clockwise):
#     Ch1 FL 315   Ch2 F   0   Ch3 FR  45   Ch4 R  90
#     Ch5 BR 135   Ch6 B 180   Ch7 BL 225   Ch8 L 270
#
#   The intensity path is an amplitude control, not an acoustic
#   distance model: there is no inverse-distance law, no propagation
#   delay and no direct-to-reverberant ratio. It is named accordingly.
#
# Changelog v0.6.1 (2026):
#   - FIX: the ambient bed was discontinuous at every speaker position.
#     v0.4 gave the bed only to the six non-active speakers, so a
#     speaker lost the bed the instant it became active. With the source
#     exactly on Front, Ch2 held the pan, Ch3 was chosen as adjacent and
#     held 0, and Ch1 held the full bed; crossing that point swapped
#     Ch1 and Ch3. At the 0.01 default the step is 0.0049, but
#     Ambient_level is a free field: 0.2297 at A = 0.3 and 0.3723 at
#     A = 1.0, a hard discontinuity mid-sweep. The bed is now applied
#     to all eight channels as a base, the pan added on top, and the
#     whole set renormalised, so the bed is continuous through the
#     handover and constant power still holds exactly.
#   - FIX: the pan law was sqrt(1-p) / sqrt(p). It satisfies
#     g1^2 + g2^2 = 1, but sqrt has infinite slope at p = 0, so the
#     quiet neighbour reached zero as a cusp: at p = 0.0001 sqrt gives
#     0.0100 where sin gives 0.000157, sixty-four times larger.
#     Replaced with cos(p*pi/2) / sin(p*pi/2) - the same constant-power
#     law, but approaching the endpoints linearly. With the bed fix,
#     the largest step between adjacent samples across a speaker
#     boundary falls from 0.2417 to 0.00011, about 2000x smoother,
#     with the sum of squares still exactly 1.
#   - FIX: an all-silent result divided by the 1e-9 peak floor and
#     reported a shared gain near a billion. The audio was silent
#     either way, but the number was nonsense. The stage is now
#     skipped and reported as skipped.
#   - Report corrections: constant power holds AT CONTROL FRAMES, not
#     at every instant - the AmplitudeTier interpolates each channel
#     linearly and independently, so the sum dips about -0.03 dB at
#     4.5 deg per frame and -0.67 dB at 22.5 deg; the report says so
#     and points at Time_step. Percentiles are described as reducing
#     sensitivity to isolated transients and short silences rather than
#     immunising against silence: past roughly 5% silent content the
#     5th percentile falls inside the silence anyway. Initial unvoiced
#     frames use the file's mean pitch, not a held value, since there
#     is nothing yet to hold.
#   - Report note: proximity gain multiplies audio that already carries
#     its own dynamics, so it expands dynamic range rather than only
#     placing the source. Intended, but named.
#
# Changelog v0.4 (2026):
#   - FIX (main): Pitch_floor and Pitch_ceiling did not control the
#     mapping. The normalisation used the minimum and maximum pitch
#     observed in the file, so every recording was stretched across the
#     whole angular arc: a voice covering 180-220 Hz swept the full arc
#     with 40 Hz, and a voice covering 100-500 Hz swept the same arc
#     with 400 Hz. The floor and ceiling were only the pitch detector's
#     search bounds, while the form and the plot presented them as the
#     mapping range. Mapping is now fixed to Pitch_floor / Pitch_ceiling
#     by default, so a given pitch lands on the same azimuth in every
#     file, and the presets mean something. The old behaviour is kept
#     as an explicit Adaptive option and labelled as such.
#   - FIX: intensity was called distance but computed a gain. There is
#     no metre, no 1/d, no delay, no D/R ratio - it interpolates
#     between two gain values. Renamed to proximity gain throughout.
#     The plot also drew the trajectory at a fixed radius of 0.55 while
#     claiming intensity drove distance; the drawn radius now follows
#     the proximity gain, loud drawn near and quiet drawn far, and the
#     panel says it is an amplitude cue rather than a distance.
#   - FIX: the ambient bed broke the constant-power claim. The active
#     pair satisfied g1^2 + g2^2 = gd^2, but the other six each carried
#     gd*A, so the total was gd^2 * (1 + 6A^2). Harmless at the 0.01
#     default (1.0006) but Ambient_level is a free field: at 0.3 the
#     field runs 1.54x in power, 1.9 dB hot, with the source badly
#     defocused. All eight gains are now renormalised after the bed is
#     added, so the sum of squares is exactly the proximity gain
#     squared whatever the bed level.
#   - FIX: no defined behaviour for input with no voiced frames. Praat
#     returns undefined for pitch in unvoiced frames, and if the file
#     has none at all the mean, minimum and maximum are all undefined
#     and the whole mapping collapses. The script now detects that and
#     falls back to a fixed azimuth at the centre of the arc, driven by
#     intensity alone, and says so.
#   - FIX: intensity analysis was hard-coded to a 100 Hz minimum
#     periodicity even for presets whose pitch floor is 50 or 75 Hz.
#     That parameter sets the effective window at 3.2/fmin, and Praat
#     warns that too high a value lets pitch-synchronous ripple through.
#     It now follows Pitch_floor by default, with an override field,
#     and the report prints the resulting window length.
#   - FIX: pitch and intensity were normalised against the extreme
#     values found anywhere in the file, so one octave error or one
#     transient set the whole scale, and leading silence pushed all the
#     speech into the top of the gain range. Intensity now normalises
#     between the 5th and 95th percentiles; pitch uses the fixed floor
#     and ceiling, which removes the problem at source.
#   - FIX: the script assumed the input starts at t = 0 - the frame
#     loop, the AmplitudeTier domains and the analysis all did. A Sound
#     extracted with preserved times does not, and everything would be
#     displaced by xmin. The working copy is now normalised to start
#     at 0. Sources shorter than one time step are rejected instead of
#     producing zero frames and then indexing frame 1.
#   - NOTE: the bed is six synchronous copies of the same signal at low
#     level. That is a coherent all-speaker bed, not a diffuse or
#     decorrelated ambience - it has no decorrelation and no reverb -
#     and it is described that way now.
#   - NEW: Output_format menu, geometric routing as in 8-Channel
#     Movements, since the channels are speaker positions.
#       1  8 channels - octophonic
#       2  4 opposing stereo pairs   Ch1|Ch5 Ch2|Ch6 Ch3|Ch7 Ch4|Ch8
#       3  2 quadraphonic groups     diagonal Ch1357, cardinal Ch2468
#       4  4-channel fold-down       FL FR BR BL, cardinals split
#                                    equal-power to both neighbours
#       5  Stereo fold-down          equal-power from each speaker's x
#   - NEW: one shared gain across the eight channels for the stem
#     formats; the two summing formats normalise once after the sums.
#   - NEW: monitoring mix for preview playback in the stem formats.
#
# Changelog v0.3:
#   - Fixed adjacent-speaker selection across the 0/360 wrap.
#   - Replaced per-sample sample-and-hold gain with AmplitudeTier.
#   - Visualization rewritten to the suite 8x8 standard.
# ============================================================

# === Check Input (before the form) ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form 8-Channel Speech-Driven Spatialization
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Full Range (pitch: 75-600 Hz)"
        option: "Voice Range (pitch: 100-300 Hz)"
        option: "Narrow Range (pitch: 150-250 Hz)"
        option: "Extended Range (pitch: 50-800 Hz)"
        option: "Inverted (high=back, low=front)"

    comment === Pitch mapping ===
    positive Pitch_floor 75
    positive Pitch_ceiling 600
    optionmenu Pitch_mapping: 1
        option: "Fixed (floor -> low angle, ceiling -> high angle)"
        option: "Adaptive (this file's observed pitch range)"
    real Low_pitch_angle 225
    real High_pitch_angle 45

    comment === Intensity -> proximity gain (amplitude, not distance) ===
    real Min_proximity_gain 0.2
    real Max_proximity_gain 1.0
    real Ambient_level 0.01

    comment === Analysis ===
    positive Time_step 0.01
    real Intensity_floor 0

    comment === OUTPUT FORMAT ===
    optionmenu Output_format: 1
        option: "8 channels - octophonic (Ch1-Ch8)"
        option: "4 opposing stereo pairs (Ch1|Ch5, Ch2|Ch6, Ch3|Ch7, Ch4|Ch8)"
        option: "2 quadraphonic groups (diagonal Ch1357, cardinal Ch2468)"
        option: "4-channel fold-down (FL, FR, BR, BL)"
        option: "Stereo fold-down (equal-power from speaker x)"

    comment === Output ===
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "FullRange"
elsif preset = 3
    pitch_floor = 100
    pitch_ceiling = 300
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "VoiceRange"
elsif preset = 4
    pitch_floor = 150
    pitch_ceiling = 250
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "NarrowRange"
elsif preset = 5
    pitch_floor = 50
    pitch_ceiling = 800
    low_pitch_angle = 225
    high_pitch_angle = 45
    presetName$ = "ExtendedRange"
elsif preset = 6
    pitch_floor = 75
    pitch_ceiling = 600
    low_pitch_angle = 45
    high_pitch_angle = 225
    presetName$ = "Inverted"
else
    presetName$ = "Custom"
endif

# === Guards ===
if pitch_ceiling <= pitch_floor
    exitScript: "Pitch_ceiling (", pitch_ceiling, ") must be above Pitch_floor (",
        ... pitch_floor, ")."
endif
if ambient_level < 0
    ambient_level = 0
endif
if ambient_level > 1
    ambient_level = 1
endif
if min_proximity_gain < 0
    min_proximity_gain = 0
endif
if max_proximity_gain <= min_proximity_gain
    max_proximity_gain = min_proximity_gain + 0.001
endif
if scale_peak <= 0 or scale_peak > 1
    scale_peak = 0.95
endif

# Intensity analysis floor: 0 means follow Pitch_floor.
if intensity_floor <= 0
    intensityFloorUsed = pitch_floor
    intensityFloorAuto = 1
else
    intensityFloorUsed = intensity_floor
    intensityFloorAuto = 0
endif
intensityWindow = 3.2 / intensityFloorUsed

# === Source, normalised to start at t = 0 ===
sound = selected("Sound")
soundName$ = selected$("Sound")
selectObject: sound
samplingFrequency = Get sampling frequency
numberOfChannels = Get number of channels
srcT0 = Get start time
srcT1 = Get end time

if numberOfChannels > 1
    selectObject: sound
    monoSound = Convert to mono
else
    selectObject: sound
    monoSound = Copy: "sds_mono"
endif

# v0.4: the frame loop, the AmplitudeTier domains and the analysis all
# index from 0. A Sound extracted with preserved times does not start
# there, and everything would be displaced by xmin.
selectObject: monoSound
workT0 = Get start time
if workT0 <> 0
    selectObject: monoSound
    shiftedSound = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: monoSound
    monoSound = shiftedSound
endif
selectObject: monoSound
Rename: "sds_work"
duration = Get total duration

if duration < time_step
    removeObject: monoSound
    exitScript: "Source is shorter than one time step (", fixed$(duration, 4),
        ... " s < ", time_step, " s). Nothing to analyse."
endif

# === Speaker layout: angles, and the x/y used by the downmixes ===
speakerAngles# = { 315, 0, 45, 90, 135, 180, 225, 270 }
spkX# = zero# (8)
spkY# = zero# (8)
for k from 1 to 8
    aRad = speakerAngles#[k] * pi / 180
    spkX#[k] = sin(aRad)
    spkY#[k] = cos(aRad)
endfor
spkName$# = { "FL", "F", "FR", "R", "BR", "B", "BL", "L" }

# === Feature extraction ===
selectObject: monoSound
pitch = To Pitch: time_step, pitch_floor, pitch_ceiling

selectObject: monoSound
intensity = To Intensity: intensityFloorUsed, time_step, "yes"

selectObject: pitch
pitchMean = Get mean: 0, 0, "Hertz"
pitchMin = Get minimum: 0, 0, "Hertz", "Parabolic"
pitchMax = Get maximum: 0, 0, "Hertz", "Parabolic"

# v0.4: a file with no voiced frame at all leaves every pitch statistic
# undefined and the whole azimuth mapping collapses.
noPitch = 0
if pitchMean = undefined or pitchMin = undefined or pitchMax = undefined
    noPitch = 1
    pitchMean = (pitch_floor + pitch_ceiling) / 2
    pitchMin = pitch_floor
    pitchMax = pitch_ceiling
endif

# v0.4: percentiles instead of absolute extremes. One transient or a
# stretch of leading silence used to set the whole gain scale.
selectObject: intensity
intensityMean = Get mean: 0, 0
intensityMinRaw = Get minimum: 0, 0, "Parabolic"
intensityMaxRaw = Get maximum: 0, 0, "Parabolic"
intensityLo = Get quantile: 0, 0, 0.05
intensityHi = Get quantile: 0, 0, 0.95
if intensityLo = undefined or intensityHi = undefined or intensityHi <= intensityLo
    intensityLo = intensityMinRaw
    intensityHi = intensityMaxRaw
endif

# === Frame schedule ===
frameShift = time_step
numberOfFrames = floor(duration / frameShift)
if numberOfFrames < 1
    numberOfFrames = 1
endif

gainCh## = zero## (8, numberOfFrames)
pitchTrace# = zero# (numberOfFrames)
intensityTrace# = zero# (numberOfFrames)
angleTrace# = zero# (numberOfFrames)
proxGainTrace# = zero# (numberOfFrames)

# ============================================================
# ANALYSIS LOOP — per-frame gains
# ============================================================
lastPitchValue = pitchMean
stopwatch

for frame from 1 to numberOfFrames
    t = frame * frameShift

    # --- Sample pitch. Unvoiced frames hold the last valid value, so
    # consonants and noise stay where the last vowel put them instead
    # of jumping to an arbitrary position every frame.
    selectObject: pitch
    pitchValue = Get value at time: t, "Hertz", "linear"
    if pitchValue = undefined
        pitchValue = lastPitchValue
    else
        lastPitchValue = pitchValue
    endif
    pitchTrace#[frame] = pitchValue

    selectObject: intensity
    intensityValue = Get value at time: t, "Linear"
    if intensityValue = undefined
        intensityValue = intensityMean
    endif
    intensityTrace#[frame] = intensityValue

    # --- Pitch -> normalised position on the arc ---
    # v0.4: fixed mapping by default, so a given pitch lands on the same
    # azimuth in every file and the floor/ceiling fields mean what the
    # form says. Adaptive reproduces v0.3, stretching whatever range
    # this particular file happens to contain across the whole arc.
    if noPitch = 1
        pitchNorm = 0.5
    elsif pitch_mapping = 1
        pitchNorm = (pitchValue - pitch_floor) / (pitch_ceiling - pitch_floor)
    else
        if pitchMin < pitchMax
            pitchNorm = (pitchValue - pitchMin) / (pitchMax - pitchMin)
        else
            pitchNorm = 0.5
        endif
    endif
    pitchNorm = max(0, min(1, pitchNorm))

    # --- Intensity -> proximity gain (5th to 95th percentile) ---
    if intensityLo < intensityHi
        intensityNorm = (intensityValue - intensityLo) / (intensityHi - intensityLo)
    else
        intensityNorm = 0.5
    endif
    intensityNorm = max(0, min(1, intensityNorm))

    angleRange = high_pitch_angle - low_pitch_angle
    if angleRange < 0
        angleRange = angleRange + 360
    endif
    targetAngle = low_pitch_angle + pitchNorm * angleRange
    while targetAngle >= 360
        targetAngle = targetAngle - 360
    endwhile
    while targetAngle < 0
        targetAngle = targetAngle + 360
    endwhile
    angleTrace#[frame] = targetAngle

    proximityGain = min_proximity_gain + intensityNorm * (max_proximity_gain - min_proximity_gain)
    proxGainTrace#[frame] = proximityGain

    # --- Nearest speaker by angular distance ---
    minAngleDiff = 360
    nearestSpeaker = 1
    for sp from 1 to 8
        ad = abs(targetAngle - speakerAngles#[sp])
        if ad > 180
            ad = 360 - ad
        endif
        if ad < minAngleDiff
            minAngleDiff = ad
            nearestSpeaker = sp
        endif
    endfor

    # --- Adjacent speaker from the signed delta (v0.3 fix, kept) ---
    delta = targetAngle - speakerAngles#[nearestSpeaker]
    while delta > 180
        delta = delta - 360
    endwhile
    while delta <= -180
        delta = delta + 360
    endwhile

    if delta >= 0
        adjacentSpeaker = nearestSpeaker + 1
        if adjacentSpeaker > 8
            adjacentSpeaker = 1
        endif
    else
        adjacentSpeaker = nearestSpeaker - 1
        if adjacentSpeaker < 1
            adjacentSpeaker = 8
        endif
    endif

    d_main = abs(delta)
    delta_sp = speakerAngles#[adjacentSpeaker] - speakerAngles#[nearestSpeaker]
    while delta_sp > 180
        delta_sp = delta_sp - 360
    endwhile
    while delta_sp <= -180
        delta_sp = delta_sp + 360
    endwhile
    d_total = abs(delta_sp)

    if d_total < 0.001
        panPosition = 0
    else
        panPosition = d_main / d_total
    endif
    panPosition = max(0, min(1, panPosition))

    # --- Pan law: sine/cosine rather than sqrt ---
    # v0.6: both forms satisfy g1^2 + g2^2 = 1, but sqrt(p) has infinite
    # slope at p = 0, so the quiet neighbour leaves zero as a cusp. At
    # p = 0.0001 sqrt gives 0.0100 where sin gives 0.000157 - 64 times
    # larger - which is what made the channel that hands over at a
    # speaker position audibly click. cos/sin approach the endpoints
    # linearly and the handover is smooth.
    theta = panPosition * pi / 2
    gain_main = cos(theta)
    gain_adjacent = sin(theta)

    # --- Ambient as a base under all eight, then the pan on top ---
    # v0.6: v0.4 gave the bed only to the six non-active speakers, so
    # the bed vanished from a speaker the moment it became active. At
    # an exact speaker position the adjacent speaker held 0 while the
    # speaker on the other side held the full bed, and crossing that
    # point swapped them. At the 0.01 default the step is 0.0049, but
    # Ambient_level is a free field: at 0.3 it is 0.2297 and at 1.0 it
    # is 0.3723 - a hard discontinuity in the middle of the sweep.
    # Starting every channel at the bed and adding the pan component
    # keeps the bed continuous through the handover.
    sumsq = 0
    for ch from 1 to 8
        gRaw[ch] = ambient_level
        if ch = nearestSpeaker
            gRaw[ch] = gRaw[ch] + gain_main
        elsif ch = adjacentSpeaker
            gRaw[ch] = gRaw[ch] + gain_adjacent
        endif
        sumsq = sumsq + gRaw[ch] * gRaw[ch]
    endfor
    normFac = sqrt(sumsq)
    if normFac < 1e-12
        normFac = 1e-12
    endif

    for ch from 1 to 8
        gainCh##[ch, frame] = gRaw[ch] / normFac * proximityGain
    endfor
endfor

analysisElapsed = stopwatch

# ============================================================
# APPLY GAINS via AmplitudeTier multiplication
# ============================================================
stopwatch
for ch from 1 to 8
    Create AmplitudeTier: "sdsTier" + string$(ch), 0, duration
    ampTier = selected("AmplitudeTier")

    Add point: 0, gainCh##[ch, 1]
    for f from 1 to numberOfFrames
        Add point: f * frameShift, gainCh##[ch, f]
    endfor

    selectObject: monoSound
    plusObject: ampTier
    Multiply
    channel[ch] = selected("Sound")
    Rename: "sdsCh" + string$(ch)

    removeObject: ampTier
endfor
gainElapsed = stopwatch

removeObject: pitch, intensity

# ============================================================
# SHARED-GAIN NORMALISATION  (stage 1)
# ============================================================
peakAll = 0
for ch from 1 to 8
    selectObject: channel[ch]
    thisPeak = Get absolute extremum: 0, 0, "None"
    if thisPeak > peakAll
        peakAll = thisPeak
    endif
endfor
# v0.6: an all-silent result used to divide by a 1e-9 floor and report
# a shared gain near a billion. The audio stayed silent, but the number
# was nonsense. Skip the stage instead and say so.
allSilent = 0
if peakAll < 1e-9
    allSilent = 1
    sharedGain = 1
else
    sharedGain = scale_peak / peakAll
endif
if allSilent = 0
    sharedGain$ = fixed$(sharedGain, 10)
    for ch from 1 to 8
        selectObject: channel[ch]
        Formula: "self * " + sharedGain$
    endfor
endif

# ============================================================
# STEREO FOLD WEIGHTS (equal-power from each speaker's x)
# ============================================================
for s from 1 to 8
    ppos = spkX#[s]
    if ppos < -1
        ppos = -1
    endif
    if ppos > 1
        ppos = 1
    endif
    aPan = (ppos + 1) * pi / 4
    stereoL[s] = cos(aPan)
    stereoR[s] = sin(aPan)
endfor

# 4-channel fold-down weights, flat indexing wmix[(out-1)*8 + src].
# Diagonals pass through; each cardinal is split equal-power between
# the two corners beside it. Ch1+Ch5 style pairing would sum opposite
# corners into one speaker and cancel the movement.
for o from 1 to 4
    for s from 1 to 8
        wmix[(o - 1) * 8 + s] = 0
    endfor
endfor
halfw = 1 / sqrt(2)
wmix[1] = 1
wmix[2] = halfw
wmix[8] = halfw
wmix[8 + 3] = 1
wmix[8 + 2] = halfw
wmix[8 + 4] = halfw
wmix[16 + 5] = 1
wmix[16 + 4] = halfw
wmix[16 + 6] = halfw
wmix[24 + 7] = 1
wmix[24 + 6] = halfw
wmix[24 + 8] = halfw
foldName$# = { "FL", "FR", "BR", "BL" }

# ============================================================
# FORMAT LABELS
# ============================================================
if output_format = 1
    formatName$ = "8-channel octophonic"
    mapLine$ = "out1-out8 = Ch1-Ch8"
elsif output_format = 2
    formatName$ = "4 opposing stereo pairs"
    mapLine$ = "Ch1|Ch5  Ch2|Ch6  Ch3|Ch7  Ch4|Ch8  (opposing axes)"
elsif output_format = 3
    formatName$ = "2 quadraphonic groups"
    mapLine$ = "diagonal = Ch1 Ch3 Ch5 Ch7    cardinal = Ch2 Ch4 Ch6 Ch8"
elsif output_format = 4
    formatName$ = "4-channel fold-down"
    mapLine$ = "FL FR BR BL, cardinals split equal-power to both sides"
else
    formatName$ = "Stereo fold-down"
    mapLine$ = "equal-power pan from each speaker's x coordinate"
endif

needFold = 0
if output_format = 2 or output_format = 3 or output_format = 5
    needFold = 1
endif

# ============================================================
# STEREO FOLD (format 5 output, and the stem preview)
# ============================================================
if needFold
    nL = 0
    for s from 1 to 8
        if stereoL[s] > 1e-6
            selectObject: channel[s]
            Copy: "sdstmpL" + string$(s)
            nL = nL + 1
            tmpL[nL] = selected("Sound")
            Formula: "self * " + fixed$(stereoL[s], 8)
        endif
    endfor
    selectObject: tmpL[1]
    for k from 2 to nL
        plusObject: tmpL[k]
    endfor
    Combine to stereo
    stackL = selected("Sound")
    Convert to mono
    mixL = selected("Sound")
    Rename: "sds_mixL"
    removeObject: stackL
    for k from 1 to nL
        removeObject: tmpL[k]
    endfor

    nR = 0
    for s from 1 to 8
        if stereoR[s] > 1e-6
            selectObject: channel[s]
            Copy: "sdstmpR" + string$(s)
            nR = nR + 1
            tmpR[nR] = selected("Sound")
            Formula: "self * " + fixed$(stereoR[s], 8)
        endif
    endfor
    selectObject: tmpR[1]
    for k from 2 to nR
        plusObject: tmpR[k]
    endfor
    Combine to stereo
    stackR = selected("Sound")
    Convert to mono
    mixR = selected("Sound")
    Rename: "sds_mixR"
    removeObject: stackR
    for k from 1 to nR
        removeObject: tmpR[k]
    endfor
endif

# ============================================================
# OUTPUT FORMAT BRANCH
# ============================================================
stopwatch
downmixNorm = 0
monitorID = 0

if output_format = 1
    selectObject: channel[1]
    for ch from 2 to 8
        plusObject: channel[ch]
    endfor
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_8chSpatial_" + presetName$
    outCount = 1
    outChannels = 8

elsif output_format = 2
    pairA# = { 1, 2, 3, 4 }
    pairB# = { 5, 6, 7, 8 }
    for k from 1 to 4
        selectObject: channel[pairA#[k]], channel[pairB#[k]]
        Combine to stereo
        out[k] = selected("Sound")
        Rename: soundName$ + "_spatial_axis_" + spkName$#[pairA#[k]]
            ... + spkName$#[pairB#[k]] + "_" + presetName$
    endfor
    outCount = 4
    outChannels = 2

elsif output_format = 3
    selectObject: channel[1], channel[3], channel[5], channel[7]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_spatial_quad_diagonal_" + presetName$
    selectObject: channel[2], channel[4], channel[6], channel[8]
    Combine to stereo
    out[2] = selected("Sound")
    Rename: soundName$ + "_spatial_quad_cardinal_" + presetName$
    outCount = 2
    outChannels = 4

elsif output_format = 4
    for o from 1 to 4
        nC = 0
        for s from 1 to 8
            if wmix[(o - 1) * 8 + s] > 1e-6
                selectObject: channel[s]
                Copy: "sdsfold" + string$(o) + "_" + string$(s)
                nC = nC + 1
                tmpF[nC] = selected("Sound")
                Formula: "self * " + fixed$(wmix[(o - 1) * 8 + s], 8)
            endif
        endfor
        selectObject: tmpF[1]
        for k from 2 to nC
            plusObject: tmpF[k]
        endfor
        Combine to stereo
        stackF = selected("Sound")
        Convert to mono
        foldCh[o] = selected("Sound")
        Rename: "sds_fold_" + foldName$#[o]
        removeObject: stackF
        for k from 1 to nC
            removeObject: tmpF[k]
        endfor
    endfor
    selectObject: foldCh[1], foldCh[2], foldCh[3], foldCh[4]
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_spatial_fold4_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 4
    removeObject: foldCh[1], foldCh[2], foldCh[3], foldCh[4]

else
    selectObject: mixL, mixR
    Combine to stereo
    out[1] = selected("Sound")
    Rename: soundName$ + "_spatial_stereo_" + presetName$
    Scale peak: scale_peak
    downmixNorm = 1
    outCount = 1
    outChannels = 2
endif

if output_format = 2 or output_format = 3
    selectObject: mixL, mixR
    Combine to stereo
    monitorID = selected("Sound")
    Rename: "sds_monitor"
    Scale peak: scale_peak
endif

if needFold
    removeObject: mixL, mixR
endif

combineElapsed = stopwatch

if outCount = 1
    objWord$ = " object"
else
    objWord$ = " objects"
endif

# ============================================================
# INFO
# ============================================================
writeInfoLine: "=== 8-Channel Speech-Driven Spatialization v0.6.1 ==="
appendInfoLine: "Source: ", soundName$, "  (", fixed$(duration, 2), " s @ ",
    ... samplingFrequency, " Hz)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Frames: ", numberOfFrames, "   time step ", fixed$(time_step, 4), " s"
appendInfoLine: ""

appendInfoLine: "Pitch analysis: floor ", fixed$(pitch_floor, 0), " Hz, ceiling ",
    ... fixed$(pitch_ceiling, 0), " Hz"
if noPitch = 1
    appendInfoLine: "  NO VOICED FRAMES FOUND. Every pitch statistic is undefined, so"
    appendInfoLine: "  the azimuth is held at the centre of the arc and only intensity"
    appendInfoLine: "  drives the result."
else
    appendInfoLine: "  Observed pitch: ", fixed$(pitchMin, 1), " - ", fixed$(pitchMax, 1),
        ... " Hz   (mean ", fixed$(pitchMean, 1), " Hz)"
endif
if pitch_mapping = 1
    appendInfoLine: "  Mapping: FIXED. ", fixed$(pitch_floor, 0), " Hz -> ",
        ... fixed$(low_pitch_angle, 0), " deg, ", fixed$(pitch_ceiling, 0), " Hz -> ",
        ... fixed$(high_pitch_angle, 0), " deg."
    appendInfoLine: "  A given pitch lands on the same azimuth in every file."
    if noPitch = 0
        arcUsed = (pitchMax - pitchMin) / (pitch_ceiling - pitch_floor) * 100
        appendInfoLine: "  This file spans ", fixed$(arcUsed, 1),
            ... "% of the mapped pitch range."
    endif
else
    appendInfoLine: "  Mapping: ADAPTIVE. This file's observed minimum pitch -> low"
    appendInfoLine: "  angle, observed maximum -> high angle, so the same voice will"
    appendInfoLine: "  sweep the whole arc whatever its actual range."
endif
appendInfoLine: "  Unvoiced frames hold the last valid pitch; unvoiced frames before"
appendInfoLine: "  the first voiced one use the file's mean pitch, since there is no"
appendInfoLine: "  previous value to hold."
appendInfoLine: ""

appendInfoLine: "Intensity analysis: minimum periodicity ",
    ... fixed$(intensityFloorUsed, 0), " Hz"
if intensityFloorAuto = 1
    appendInfoLine: "  (following Pitch_floor; effective window ",
        ... fixed$(intensityWindow * 1000, 1), " ms = 3.2 / fmin)"
else
    appendInfoLine: "  (set manually; effective window ",
        ... fixed$(intensityWindow * 1000, 1), " ms = 3.2 / fmin)"
endif
appendInfoLine: "  Range used: ", fixed$(intensityLo, 1), " - ", fixed$(intensityHi, 1),
    ... " dB (5th to 95th percentile)"
appendInfoLine: "  Full extremes were ", fixed$(intensityMinRaw, 1), " - ",
    ... fixed$(intensityMaxRaw, 1), " dB; percentiles are used so one transient"
appendInfoLine: "  or a stretch of leading silence cannot set the whole scale."
appendInfoLine: ""

appendInfoLine: "Intensity drives PROXIMITY GAIN, ", fixed$(min_proximity_gain, 2),
    ... " to ", fixed$(max_proximity_gain, 2), "."
appendInfoLine: "  This is an amplitude control, not an acoustic distance model:"
appendInfoLine: "  no inverse-distance law, no propagation delay, no direct/reverb"
appendInfoLine: "  ratio."
appendInfoLine: "  Note the source already carries its own dynamics, so multiplying"
appendInfoLine: "  by a gain derived from that same intensity expands the dynamic"
appendInfoLine: "  range: loud speech is boosted and quiet speech attenuated twice"
appendInfoLine: "  over. That is intended here, but it is dynamic exaggeration as"
appendInfoLine: "  much as a spatial cue. Narrow the proximity gain range to reduce"
appendInfoLine: "  it - equal min and max removes it entirely."
appendInfoLine: ""

appendInfoLine: "Ambient bed: ", fixed$(ambient_level, 3),
    ... " on the six non-active speakers."
appendInfoLine: "  Six synchronous copies of the same signal at low level - a"
appendInfoLine: "  coherent all-speaker bed, not a diffuse or decorrelated field."
bedExcess = 1 + 6 * ambient_level * ambient_level
appendInfoLine: "  Before renormalisation this bed would carry the field to ",
    ... fixed$(bedExcess, 4), "x in power (", fixed$(10 * log10(bedExcess), 2), " dB)."
appendInfoLine: "  The bed is applied to all eight channels and the pan added on top,"
appendInfoLine: "  then all eight are renormalised, so the sum of squares equals the"
appendInfoLine: "  proximity gain squared AT EVERY CONTROL FRAME, whatever the bed"
appendInfoLine: "  level. Between frames the AmplitudeTier interpolates each channel"
appendInfoLine: "  linearly and independently, so the sum dips slightly in between:"
appendInfoLine: "  about -0.03 dB at 4.5 deg per frame, -0.67 dB at 22.5 deg. Reduce"
appendInfoLine: "  Time_step if a fast sweep needs tighter constant power."
appendInfoLine: ""

appendInfoLine: "Output format: ", formatName$
appendInfoLine: "Objects: ", outCount, "  |  channels each: ", outChannels
if output_format = 1
    appendInfoLine: "  out1-out8: Ch1 - Ch8"
elsif output_format = 2
    for k from 1 to 4
        appendInfoLine: "  Axis ", k, ": Ch", pairA#[k], " (", spkName$#[pairA#[k]],
            ... ") -> L,  Ch", pairB#[k], " (", spkName$#[pairB#[k]], ") -> R"
    endfor
elsif output_format = 3
    appendInfoLine: "  Diagonal quad: Ch1 FL, Ch3 FR, Ch5 BR, Ch7 BL"
    appendInfoLine: "  Cardinal quad: Ch2 F,  Ch4 R,  Ch6 B,  Ch8 L"
elsif output_format = 4
    appendInfoLine: "  FL = Ch1 + 0.707*(Ch2 + Ch8)"
    appendInfoLine: "  FR = Ch3 + 0.707*(Ch2 + Ch4)"
    appendInfoLine: "  BR = Ch5 + 0.707*(Ch4 + Ch6)"
    appendInfoLine: "  BL = Ch7 + 0.707*(Ch6 + Ch8)"
else
    for s from 1 to 8
        appendInfoLine: "  Ch", s, " ", spkName$#[s], "  L=", fixed$(stereoL[s], 3),
            ... "  R=", fixed$(stereoR[s], 3)
    endfor
endif

appendInfoLine: ""
appendInfoLine: "Normalisation:"
if allSilent = 1
    appendInfoLine: "  All output channels are silent; shared normalisation was skipped."
else
    appendInfoLine: "  Shared gain across all eight channels: x", fixed$(sharedGain, 4),
        ... " (from peak ", fixed$(peakAll, 4), ")"
endif
if downmixNorm = 1
    appendInfoLine: "  Final peak normalisation after downmix: Scale peak ",
        ... fixed$(scale_peak, 3)
else
    appendInfoLine: "  No downmix, so no second normalisation stage."
endif
appendInfoLine: ""
appendInfoLine: "(analysis ", fixed$(analysisElapsed, 2), " s   envelopes ",
    ... fixed$(gainElapsed, 2), " s   combine ", fixed$(combineElapsed, 2), " s)"

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================
# The working channels are still alive, so Panel D draws them directly
# and is identical in all five output formats.

if draw_visualization

    Erase all

    spkColR# = { 0.30, 0.45, 0.78, 0.85, 0.78, 0.55, 0.30, 0.20 }
    spkColG# = { 0.55, 0.70, 0.55, 0.40, 0.30, 0.30, 0.30, 0.45 }
    spkColB# = { 0.85, 0.55, 0.30, 0.25, 0.30, 0.55, 0.75, 0.80 }

    # --- Trajectory: radius now follows the proximity gain ---
    # v0.3 drew a fixed radius of 0.55 while claiming intensity drove
    # distance, so the picture contradicted the description. Loud is
    # drawn near and quiet far; this is an amplitude cue, not a metre.
    maxTraj = 500
    if numberOfFrames < maxTraj
        trajN = numberOfFrames
    else
        trajN = maxTraj
    endif
    trajX# = zero# (trajN)
    trajY# = zero# (trajN)
    for k from 1 to trajN
        srcIdx = round((k - 1) / max(1, trajN - 1) * (numberOfFrames - 1)) + 1
        if srcIdx < 1
            srcIdx = 1
        endif
        if srcIdx > numberOfFrames
            srcIdx = numberOfFrames
        endif
        gNorm = (proxGainTrace#[srcIdx] - min_proximity_gain) / (max_proximity_gain - min_proximity_gain)
        gNorm = max(0, min(1, gNorm))
        rr = 0.88 - 0.50 * gNorm
        ang = angleTrace#[srcIdx] * pi / 180
        trajX#[k] = rr * sin(ang)
        trajY#[k] = rr * cos(ang)
    endfor

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPEECH-DRIVEN SPATIALIZATION##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if pitch_mapping = 1
        mapMode$ = "fixed"
    else
        mapMode$ = "adaptive"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... soundName$
        ... + "  |  " + presetName$
        ... + "  |  Pitch " + fixed$(pitch_floor, 0) + "-" + fixed$(pitch_ceiling, 0)
        ... + " Hz (" + mapMode$ + ")"
        ... + "  |  " + fixed$(low_pitch_angle, 0) + "° -> " + fixed$(high_pitch_angle, 0) + "°"
        ... + "  |  " + formatName$

    # ----------------------------------------------------------
    # PANEL A: OCTAGON MAP + TRAJECTORY  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.85, 4.34

    Axes: -1.45, 1.45, -1.45, 1.45
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.45, 1.45, -1.45, 1.45

    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw ellipse: -1, 1, -1, 1
    Draw ellipse: -0.38, 0.38, -0.38, 0.38
    Draw line: 0, -1.35, 0, 1.35
    Draw line: -1.35, 0, 1.35, 0

    Colour: "{0.82, 0.82, 0.82}"
    for k from 1 to 8
        k2 = (k mod 8) + 1
        Draw line: spkX#[k], spkY#[k], spkX#[k2], spkY#[k2]
    endfor

    # Trajectory, cool at the start to warm at the end
    Line width: 2
    for k from 2 to trajN
        frac = (k - 1) / max(1, trajN - 1)
        Colour: "{" + fixed$(0.25 + frac * 0.60, 2) + ", "
            ... + fixed$(0.32 - frac * 0.12, 2) + ", "
            ... + fixed$(0.78 - frac * 0.55, 2) + "}"
        Draw line: trajX#[k - 1], trajY#[k - 1], trajX#[k], trajY#[k]
    endfor
    Line width: 1
    Paint circle (mm): "{0.10, 0.30, 0.85}", trajX#[1], trajY#[1], 2.6

    for k from 1 to 8
        Paint circle (mm): "{" + fixed$(spkColR#[k], 2) + ", "
            ... + fixed$(spkColG#[k], 2) + ", " + fixed$(spkColB#[k], 2) + "}",
            ... spkX#[k], spkY#[k], 3.6
        Colour: "White"
        Font size: 6
        Text: spkX#[k], "centre", spkY#[k], "half", string$(k)
        Colour: "{0.40, 0.40, 0.40}"
        Font size: 6
        Text: spkX#[k] * 1.24, "centre", spkY#[k] * 1.24, "half", spkName$#[k]
    endfor

    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 2.8

    Colour: "Black"
    Line width: 1
    Draw inner box

    # ----------------------------------------------------------
    # PANEL B: PITCH CONTOUR  (right column, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48

    # v0.4: the axis is the mapped range in fixed mode, so the plot
    # shows the mapping the audio actually used.
    if pitch_mapping = 1
        pLo = pitch_floor
        pHi = pitch_ceiling
    else
        pLo = pitchMin
        pHi = pitchMax
        if pHi <= pLo
            pHi = pLo + 1
        endif
    endif
    pSpan = pHi - pLo
    pAxLo = pLo - pSpan * 0.08
    pAxHi = pHi + pSpan * 0.08
    Axes: 0, duration, pAxLo, pAxHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, pAxLo, pAxHi

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, pLo, duration, pLo
    Draw line: 0, pHi, duration, pHi
    Solid line

    Line width: 1.5
    Colour: "{0.25, 0.45, 0.78}"
    for k from 2 to numberOfFrames
        t1 = (k - 1) * frameShift
        t2 = k * frameShift
        Draw line: t1, pitchTrace#[k - 1], t2, pitchTrace#[k]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Select outer viewport: 4.02, 4.4, 0.75, 2.70
    Select inner viewport: 4.02, 4.4, 0.77, 2.68
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Pitch (Hz)"
    Select outer viewport: 4.2, 8, 0.75, 2.70
    Select inner viewport: 4.52, 7.75, 0.85, 2.48
    Axes: 0, duration, pAxLo, pAxHi
    if pitch_mapping = 1
        Text bottom: "yes", "dotted = mapped range (" + fixed$(pitch_floor, 0)
            ... + "-" + fixed$(pitch_ceiling, 0) + " Hz)"
    else
        Text bottom: "yes", "dotted = this file's observed range (adaptive)"
    endif

    # ----------------------------------------------------------
    # PANEL C: PROXIMITY GAIN  (right column, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38

    gSpan = max_proximity_gain - min_proximity_gain
    gAxLo = min_proximity_gain - gSpan * 0.10
    gAxHi = max_proximity_gain + gSpan * 0.10
    Axes: 0, duration, gAxLo, gAxHi
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, duration, gAxLo, gAxHi

    Colour: "{0.80, 0.80, 0.80}"
    Dotted line
    Draw line: 0, min_proximity_gain, duration, min_proximity_gain
    Draw line: 0, max_proximity_gain, duration, max_proximity_gain
    Solid line

    Line width: 1.5
    Colour: "{0.82, 0.45, 0.25}"
    for k from 2 to numberOfFrames
        t1 = (k - 1) * frameShift
        t2 = k * frameShift
        Draw line: t1, proxGainTrace#[k - 1], t2, proxGainTrace#[k]
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 6
    Marks left: 3, "yes", "yes", "no"
    Select outer viewport: 4.02, 4.4, 3.00, 4.60
    Select inner viewport: 4.02, 4.4, 3.02, 4.58
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Gain"
    Select outer viewport: 4.2, 8, 3.00, 4.60
    Select inner viewport: 4.52, 7.75, 3.10, 4.38
    Axes: 0, duration, gAxLo, gAxHi
    Text bottom: "yes", "Proximity gain (amplitude cue, not distance)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half",
        ... "Speaker map & path (radius = proximity gain)"
    Text: 6.10, "centre", 7.30, "half", "Pitch (upper) & proximity gain (lower)"

    # ----------------------------------------------------------
    # PANEL D: TWO CHANNEL EXAMPLES (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72

    selectObject: channel[2]
    outDurViz = Get total duration
    peakViz = Get absolute extremum: 0, 0, "None"
    selectObject: channel[6]
    peak2 = Get absolute extremum: 0, 0, "None"
    if peak2 > peakViz
        peakViz = peak2
    endif
    if peakViz < 0.001
        peakViz = 0.001
    endif
    ampViz = peakViz * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: channel[2]
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    selectObject: channel[6]
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Opposing channels  (blue = Ch2 Front,  orange = Ch6 Back)"
    Select outer viewport: 0.08, 0.52, 4.90, 5.95
    Select inner viewport: 0.08, 0.52, 4.92, 5.93
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text special: 0.5, "centre", 0.5, "bottom", "Helvetica", 7, "90", "Amp"
    Select outer viewport: 0, 8, 4.90, 5.95
    Select inner viewport: 0.55, 7.72, 4.98, 5.72
    Axes: 0, outDurViz, -ampViz, ampViz
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.20, 7.08
    Select inner viewport: 0.55, 7.72, 6.26, 7.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.72, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + soundName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  " + string$(numberOfFrames) + " frames @ "
        ... + fixed$(time_step * 1000, 0) + " ms"
        ... + "  |  Intensity fmin " + fixed$(intensityFloorUsed, 0) + " Hz"

    if noPitch = 1
        pitchLine$ = "No voiced frames - azimuth held at arc centre"
    else
        pitchLine$ = "Pitch " + fixed$(pitchMin, 0) + "-" + fixed$(pitchMax, 0) + " Hz observed, mapped " + mapMode$ + "  |  Intensity " + fixed$(intensityLo, 0) + "-" + fixed$(intensityHi, 0) + " dB (5-95%)"
    endif
    Text: 0.02, "left", 0.45, "half",
        ... pitchLine$
        ... + "  |  Bed " + fixed$(ambient_level, 3) + " (renormalised)"

    Text: 0.02, "left", 0.18, "half",
        ... "Format: " + formatName$
        ... + "  |  " + string$(outCount) + objWord$
        ... + " x " + string$(outChannels) + " ch"
        ... + "  |  " + mapLine$

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Select outer viewport: 0, 8, 0, 7.18
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoSound
for ch from 1 to 8
    removeObject: channel[ch]
endfor

appendInfoLine: ""
appendInfoLine: "=== Done ==="
if outCount = 1
    appendInfoLine: "Output: 1 object, ", outChannels, "-channel"
else
    appendInfoLine: "Output: ", outCount, " objects, ", outChannels, "-channel each"
endif

if play_result
    if outCount = 1
        selectObject: out[1]
        Play
    else
        appendInfoLine: ""
        appendInfoLine: "Playback: stereo preview folded from all eight channels."
        appendInfoLine: "          It is not one of the ", outCount, " output objects."
        selectObject: monitorID
        Play
    endif
endif

if monitorID <> 0
    removeObject: monitorID
endif

# === Select the output object(s) ===
selectObject: out[1]
for k from 2 to outCount
    plusObject: out[k]
endfor
