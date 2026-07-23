# ============================================================
# Praat AudioTools - BPM_SURROUND__Panning.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   BPM-locked 8-channel surround panning. A virtual source is moved on
#   a 2D trajectory around the listener; one shared panner converts that
#   position into speaker gains from the real speaker angles. The
#   multichannel counterpart of BPM_Panning, which does the same job in
#   stereo.
#
#   Two speaker models:
#     7.1 with a true LFE - the seven directional speakers carry the
#       trajectory; Ch4 is a lowpassed mono sum at its own level and is
#       excluded from the movement and from the normalisation.
#     8-channel octophonic ring - all eight are full-range and
#       directional, Ch4 becomes back-centre, and nothing is called LFE.
#
# Changelog v0.5 (2026):
#   - FIX: Speaker_format and Output_format contradicted each other. In
#     the full-range mode Ch4 is a directional back-centre speaker, but
#     the output stage still treated it as an LFE: format 1 was always
#     labelled "7.1 - LFE on Ch4", the 5.1 downmix routed that WIDEBAND
#     rear channel straight into the LFE slot, and quad and stereo left
#     it out of the matrix entirely so the speaker simply vanished.
#     There are now two sets of matrices. With a derived LF channel it
#     goes to the LFE slot and nowhere else; with a full-range Ch4 it is
#     folded equal-power into the surrounds, and a 5.1 output derives a
#     fresh LF channel by lowpassing the source rather than reusing a
#     directional one.
#   - FIX: the "octophonic ring" was not a ring. It kept the 7.1 angles
#     (330, 30, 0, 180, 250, 110, 210, 150) with the LFE slot reused,
#     which is not eight evenly spaced speakers. There are now three
#     formats: 7.1 with a derived LF channel; 8.0 full-range on the 7.1
#     layout, named for what it is; and a true octophonic ring at 45
#     degree spacing.
#   - FIX: Path_radius was not the maximum radius. Measured against the
#     0.85 default, Bounce and Plasma both reached sqrt(2)*r = 1.414r,
#     Quantum 1.134r and Wave 1.049r - at the 0.98 limit that is 1.386,
#     outside the speaker ring, while the header claimed everything
#     stayed inside the unit disc. One clamp at the end of the
#     trajectory procedure now holds every pattern to Path_radius.
#   - FIX: the LF channel did not take the global output gain. The
#     directional channels were scaled to Peak_target while the LF
#     channel kept its raw level, so Lfe_level was not a fixed ratio:
#     across a 90x change in input level the LF-to-main ratio moved
#     from 0.379 to 0.004. It is excluded from the SPATIAL
#     normalisation, as it should be, but now takes the shared gain.
#   - FIX: "pattern cycles" was only true for Circle and Figure-8. The
#     figure is the PRIMARY PHASE rate; the shape itself closes later
#     for Bounce (4 phase cycles, from the 0.75 axis ratio), Galaxy and
#     Breathing (3), Heartbeat (4), and never for Swarm and Quantum,
#     which combine incommensurate terms. Renamed and explained, and
#     the v0.4 claim that every pattern "declares how many orbits" is
#     withdrawn.
#   - FIX: Spiral reset rather than spiralling. The radius grew
#     linearly and snapped from 0.85 to 0 at every wrap, with the
#     amplitude dropping 1.00 to 0.55 in the same step. It now runs out
#     and back, r*(1 - |2q - 1|), which is continuous across the
#     boundary.
#   - FIX: the control rate and the plot sampling followed the phase
#     rate, ignoring faster internal terms. Quantum runs a 7.1x term
#     and Neural six nodes per cycle, so a flat 96 points per phase
#     cycle left Quantum 13.5 points on its fastest component. Each
#     pattern now declares that multiplier and both rates follow it.
#     The 400000-point cap is reported, which it was not before.
#   - FIX: the plotted path could alias badly. nTrace was capped at 600
#     for the whole file, so 64 file cycles times Lightning's 8 gave
#     1.17 points per cycle - the drawn path was not the path, and the
#     centroid and mean-gain figures derived from it were skewed.
#   - Wording: energy preservation is exact AT THE CONTROL POINTS; the
#     AmplitudeTier interpolates each channel independently between
#     them. The menu now says squared directional gains sum to 1, and
#     the LF channel is called a derived low-frequency channel rather
#     than a true LFE, since a real LFE carries separately authored
#     content.
#
# Changelog v0.4 (2026):
#   - FIX (critical): THE SPEAKER MAP AND THE PATTERN MATH DISAGREED.
#     spkAngle[] was called a single source of truth but only the plot
#     used it; every pattern carried its own hard-coded phases. In
#     Circle, Ch1 (FL, 330 deg) was driven at 225 deg and Ch7 (BL,
#     210 deg) at 315 deg - a 105 degree error each, in opposite
#     directions, so the two left speakers were effectively swapped:
#     the front-left speaker behaved as back-left and vice versa. The
#     other five sat within 20 degrees. All gains are now derived from
#     spkAngle[] through one panner, so a phase error of this kind is
#     no longer expressible.
#   - FIX: THERE WAS NO BPM. The rate was cycles divided by file
#     duration, so the same setting ran at 2 Hz on a 4 s file and
#     0.2 Hz on a 40 s one - a tenfold difference from the file length
#     alone, which is file-synchronous, not tempo-synchronous. There is
#     now a real Tempo_bpm with a subdivision and a beats-per-cycle
#     setting. The old behaviour is kept as an explicit Rate_mode
#     option, named File-synchronous cycles.
#   - FIX: "Cycles" was not the pattern's cycle count. Patterns
#     multiplied the base rate by their own factors: Circle used 2*pi*f
#     (1 cycle), Spiral 4*pi*f (2), Tornado 6*pi*f (3), Lightning
#     16*pi*f (8), Breathing pi*f (0.5). Choosing "8 cycles" gave
#     Lightning 64. Each pattern now declares its rate multiplier and
#     the report prints the resulting cycle count and Hz.
#   - FIX: no constant-power normalisation. Summing the independent
#     envelopes, Circle ran between sum g^2 = 1.91 and 2.81 over one
#     orbit - 1.68 dB of level pumping riding on top of the movement,
#     so spatial motion and global amplitude modulation were mixed
#     together. Spatialisation now offers Energy-preserving (gains
#     normalised so the directional channels sum to 1) or Creative
#     gain field (the pumping kept, deliberately).
#   - FIX: the patterns were not trajectories. Each wrote a separate
#     gain formula per channel, so "Circle", "Figure-8" and "Spiral"
#     described relationships between envelopes rather than shapes a
#     source moves along. All fifteen now compute a source position
#     x(t), y(t) plus an amplitude, and a single panner turns that into
#     speaker gains. The shapes are therefore real, and the plot can
#     draw the path the audio used.
#   - FIX: LFE was treated as a directional speaker. Ch4 was given an
#     angle of 180 degrees, a full-range copy of the source and its own
#     moving envelope. An LFE is not another speaker in the ring; it is
#     a band-limited effects channel. In 7.1 mode it now receives a
#     lowpassed mono sum at a fixed level and takes no part in the
#     trajectory or the normalisation. If you want eight full-range
#     directional channels, choose the octophonic ring, where Ch4
#     becomes back-centre and nothing is labelled LFE.
#   - FIX: "binaural mix" was a stereo downmix - a weighted sum with no
#     HRTF, no ITD, no head shadow and no pinna filtering. Renamed
#     Stereo downmix, and it is now one of several downmix formats
#     rather than a special case.
#   - FIX: Lightning still stepped. v0.3 replaced per-sample randomness
#     with a deterministic LFO, which fixed the character of the events
#     but not their edges: sin(phase) > 0.6 is binary, so the gate
#     jumps from 0 to 1 at the crossing. Replaced with the same tanh
#     soft gate already used by Neural, plus a decay after each strike.
#   - FIX: Heartbeat had a discontinuity at every cycle boundary. It
#     used exp(-10*phase^2) with phase in [0,1), which is 0.00005 just
#     before the boundary and exactly 1 immediately after - a step, and
#     an audible click on sustained material. It now measures the
#     circular distance to the beat, min(phase, 1-phase), so the
#     envelope is continuous across the boundary.
#   - FIX: the plot claimed a centre-of-mass trajectory that was never
#     drawn - Panel A only showed speaker positions and marker sizes.
#     It is drawn now, computed as the energy-weighted centroid
#     sum(g_i^2 * pos_i) / sum(g_i^2) with the LFE excluded, alongside
#     the source path itself so the two can be compared.
#   - FIX: Panel B divided processed audio by source audio, which is a
#     source-energy-weighted RMS ratio, not a gain envelope: on quiet
#     passages or transients it shows a different shape from the
#     envelope actually applied. The gains are now recomputed from the
#     same procedures the audio used, so the panel shows the envelope
#     itself.
#   - FIX: turning both outputs off deleted every channel and left
#     nothing at all, while the summary cheerfully reported "none
#     (channels only)". At least one output is now required, and Keep
#     8 mono stems is an explicit choice.
#   - FIX: the time domain was not normalised to 0. The formulas used
#     absolute x, so a Sound starting elsewhere got a different starting
#     phase and a different number of completed cycles.
#   - CORRECTION to the v0.3 changelog: it claimed Combine to stereo is
#     only defined for mono+mono. That is not true of current Praat -
#     it concatenates the channels of everything selected. Building the
#     multichannel object directly is still clearer, so the
#     implementation stands; only the justification was wrong.
#   - NEW: output formats chosen for what these channels actually are,
#     rather than the generic five used elsewhere in the suite:
#       7.1 (eight channels, LFE on Ch4)
#       7.0 full-range (no LFE)
#       5.1 downmix (BL/BR folded into SL/SR)
#       4.0 quad downmix
#       Stereo downmix
#       8 mono stems
#     A "4 stereo pairs" split would pair Centre with LFE, which is not
#     a stereo pair in any useful sense.
#
# Changelog v0.3:
#   - Lightning moved from per-sample randomness to a deterministic LFO.
#   - Neural given a tanh soft gate.
#   - 8-channel object built directly rather than by pyramid combining.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

form BPM Surround Panning v0.5
    comment === RATE ===
    optionmenu Rate_mode: 1
        option: "BPM-locked (real tempo sync)"
        option: "File-synchronous cycles (the v0.3 behaviour)"
    real Tempo_bpm 120
    optionmenu Subdivision: 3
        option: "1/1 (one cycle per bar of 4)"
        option: "1/2 (one cycle per two beats)"
        option: "1/4 (one cycle per beat)"
        option: "1/8"
        option: "1/16"
    optionmenu File_cycles: 4
        option: "1 cycle (very slow)"
        option: "2 cycles"
        option: "4 cycles"
        option: "8 cycles (medium)"
        option: "16 cycles"
        option: "32 cycles (fast)"
        option: "64 cycles (very fast)"

    comment === SPATIAL PATTERN ===
    optionmenu Pattern: 1
        option: "1. Circle (clockwise orbit)"
        option: "2. Figure-8 (lemniscate)"
        option: "3. Spiral (centre outwards)"
        option: "4. Bounce (wall collision)"
        option: "5. Swarm (quasi-random wander)"
        option: "6. Tornado (fast vortex)"
        option: "7. Wave (side-to-side current)"
        option: "8. Plasma (Lissajous field)"
        option: "9. Neural (soft-gated jumps)"
        option: "10. Quantum (jitter cloud)"
        option: "11. DNA (double helix)"
        option: "12. Galaxy (rotation with drift)"
        option: "13. Lightning (soft-gated strikes)"
        option: "14. Heartbeat (double pulse)"
        option: "15. Breathing (radius in and out)"

    comment === SPEAKERS AND PANNING ===
    optionmenu Speaker_format: 1
        option: "7.1 with a derived LF channel (Ch4 lowpassed, not spatialised)"
        option: "8.0 full-range on the 7.1 layout (Ch4 = back centre, irregular)"
        option: "True octophonic ring (8 speakers at 45 deg spacing)"
    optionmenu Spatialisation: 1
        option: "Energy-preserving (SQUARED directional gains sum to 1)"
        option: "Creative gain field (level pumps with the pattern)"
    positive Source_focus 1.6
    positive Path_radius 0.85

    comment === LFE (7.1 mode only) ===
    positive Lfe_cutoff_Hz 100
    real Lfe_level 0.4

    comment === OUTPUT ===
    optionmenu Output_format: 1
        option: "7.1 (8 channels, LFE on Ch4)"
        option: "7.0 full-range (7 channels, no LFE)"
        option: "5.1 downmix (BL/BR folded into SL/SR)"
        option: "4.0 quad downmix"
        option: "Stereo downmix"
    boolean Keep_8_mono_stems 0
    real Peak_target 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

if tempo_bpm < 1 or tempo_bpm > 999
    exitScript: "BPM must be between 1 and 999."
endif
if path_radius > 0.98
    path_radius = 0.98
endif
if lfe_level < 0
    lfe_level = 0
endif
if lfe_level > 1
    lfe_level = 1
endif
if peak_target <= 0 or peak_target > 1
    peak_target = 0.95
endif

# === Source: mono, time domain starting at 0 ===
originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
inputCh = Get number of channels
sr = Get sampling frequency
srcT1 = Get end time

if inputCh > 2
    exitScript: "Please use a mono or stereo source."
endif

if inputCh = 2
    selectObject: originalID
    Convert to mono
    monoID = selected("Sound")
else
    selectObject: originalID
    Copy: "bs_mono"
    monoID = selected("Sound")
endif

# v0.4: the formulas use x, i.e. absolute time. A Sound that does not
# start at 0 would get a different starting phase and a different
# number of completed cycles.
selectObject: monoID
workT0 = Get start time
if workT0 <> 0
    selectObject: monoID
    shiftedID = Extract part: workT0, srcT1, "rectangular", 1.0, "no"
    removeObject: monoID
    monoID = shiftedID
endif
selectObject: monoID
Rename: "bs_src"
duration = Get total duration

if duration <= 0
    removeObject: monoID
    exitScript: "Source has zero duration."
endif

nyq = sr / 2
lfeCut = lfe_cutoff_Hz
if lfeCut > nyq * 0.9
    lfeCut = nyq * 0.9
endif

# ============================================================
# RATE
# ============================================================
if subdivision = 1
    subFactor = 1 / 4
    subName$ = "1/1 (per bar)"
elsif subdivision = 2
    subFactor = 1 / 2
    subName$ = "1/2"
elsif subdivision = 3
    subFactor = 1
    subName$ = "1/4 (per beat)"
elsif subdivision = 4
    subFactor = 2
    subName$ = "1/8"
else
    subFactor = 4
    subName$ = "1/16"
endif

if file_cycles = 1
    numCycles = 1
elsif file_cycles = 2
    numCycles = 2
elsif file_cycles = 3
    numCycles = 4
elsif file_cycles = 4
    numCycles = 8
elsif file_cycles = 5
    numCycles = 16
elsif file_cycles = 6
    numCycles = 32
else
    numCycles = 64
endif

if rate_mode = 1
    baseRate = tempo_bpm / 60 * subFactor
    rateDesc$ = "BPM-locked: " + fixed$(tempo_bpm, 1) + " BPM at " + subName$
else
    baseRate = numCycles / duration
    rateDesc$ = "file-synchronous: " + string$(numCycles) + " cycles over the file"
endif
if baseRate <= 0
    baseRate = 1 / duration
endif

# ============================================================
# SPEAKERS
# ============================================================
chLabel$[1] = "FL"
chLabel$[2] = "FR"
chLabel$[3] = "C"
chLabel$[4] = "LFE"
chLabel$[5] = "SL"
chLabel$[6] = "SR"
chLabel$[7] = "BL"
chLabel$[8] = "BR"

spkAngle[1] = 330
spkAngle[2] = 30
spkAngle[3] = 0
spkAngle[4] = 180
spkAngle[5] = 250
spkAngle[6] = 110
spkAngle[7] = 210
spkAngle[8] = 150

# v0.5: three formats, because v0.4 called the second one an
# "octophonic ring" while keeping the 7.1 angles (330, 30, 0, 180, 250,
# 110, 210, 150) with the LFE slot reused. Those are not eight evenly
# spaced speakers. A real ring is 45 degrees apart, so it is now its own
# option and the 7.1-derived one is named for what it is.
if speaker_format = 1
    formatName$ = "7.1 with a derived LF channel"
elsif speaker_format = 2
    chLabel$[4] = "BC"
    formatName$ = "8.0 full-range on the 7.1 layout (irregular spacing)"
else
    # True ring: Ch1 front, then clockwise every 45 degrees.
    spkAngle[1] = 0
    spkAngle[2] = 45
    spkAngle[3] = 90
    spkAngle[4] = 135
    spkAngle[5] = 180
    spkAngle[6] = 225
    spkAngle[7] = 270
    spkAngle[8] = 315
    chLabel$[1] = "N"
    chLabel$[2] = "NE"
    chLabel$[3] = "E"
    chLabel$[4] = "SE"
    chLabel$[5] = "S"
    chLabel$[6] = "SW"
    chLabel$[7] = "W"
    chLabel$[8] = "NW"
    formatName$ = "true octophonic ring (45 deg spacing)"
endif

# Compass: 0 = front, increasing clockwise. x = sin, y = cos.
for k from 1 to 8
    aRad = spkAngle[k] * pi / 180
    spkX[k] = sin(aRad)
    spkY[k] = cos(aRad)
endfor

# isDirectional marks the channels that carry the trajectory. In 7.1
# the LFE is excluded, which is the whole point of it being an LFE.
nDir = 0
hasLF = 0
if speaker_format = 1
    hasLF = 1
endif
for k from 1 to 8
    if hasLF = 1 and k = 4
        isDir[k] = 0
    else
        isDir[k] = 1
        nDir = nDir + 1
    endif
endfor

# ============================================================
# PATTERN NAMES AND RATE MULTIPLIERS
# ============================================================
# v0.4: each pattern declares how many orbits it performs per base
# cycle, so "8 cycles" no longer silently means 64 for Lightning.
patternNames$[1]  = "Circle"
patternNames$[2]  = "Figure8"
patternNames$[3]  = "Spiral"
patternNames$[4]  = "Bounce"
patternNames$[5]  = "Swarm"
patternNames$[6]  = "Tornado"
patternNames$[7]  = "Wave"
patternNames$[8]  = "Plasma"
patternNames$[9]  = "Neural"
patternNames$[10] = "Quantum"
patternNames$[11] = "DNA"
patternNames$[12] = "Galaxy"
patternNames$[13] = "Lightning"
patternNames$[14] = "Heartbeat"
patternNames$[15] = "Breathing"
patternName$ = patternNames$[pattern]

# v0.5: the fastest internal component of each pattern, used to set the
# control rate and the plot sampling. v0.4 used a flat 96 points per
# phase cycle, which left Quantum with 96/7.1 = 13.5 points per its own
# fastest term.
fastMult[1] = 1
fastMult[2] = 2
fastMult[3] = 1
fastMult[4] = 1
fastMult[5] = 2.1
fastMult[6] = 1
fastMult[7] = 2
fastMult[8] = 5
fastMult[9] = 6
fastMult[10] = 7.1
fastMult[11] = 2
fastMult[12] = 1
fastMult[13] = 1
fastMult[14] = 9
fastMult[15] = 1

rateMult[1] = 1
rateMult[2] = 1
rateMult[3] = 2
rateMult[4] = 2
rateMult[5] = 3
rateMult[6] = 3
rateMult[7] = 1
rateMult[8] = 2
rateMult[9] = 4
rateMult[10] = 4
rateMult[11] = 2
rateMult[12] = 1
rateMult[13] = 8
rateMult[14] = 1
rateMult[15] = 0.5
patRate = baseRate * rateMult[pattern]
fastRate = patRate * fastMult[pattern]

# ============================================================
# CONTROL RATE
# ============================================================
# v0.5: derived from the FASTEST internal component, not from the phase
# rate alone.
ctrlRate = 32 * fastRate
if ctrlRate < 200
    ctrlRate = 200
endif
ctrlCapped = 0
if ctrlRate > 8000
    ctrlRate = 8000
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
ptsPerFast = ctrlRate / fastRate

# ============================================================
# TRAJECTORY
# ============================================================
# Every pattern returns a source position on the unit disc plus an
# overall amplitude. One panner converts position to speaker gains, so
# the shapes are real and the plot can draw the path the audio used.

procedure trajectory: .t
    .u = .t / duration
    .ph = 2 * pi * patRate * .t
    .r = path_radius
    .amp = 1

    if pattern = 1
        .x = .r * sin(.ph)
        .y = .r * cos(.ph)
    elsif pattern = 2
        # Gerono lemniscate, halved on y so the excursion is exactly r
        .x = .r * sin(.ph)
        .y = .r * 0.5 * sin(2 * .ph)
    elsif pattern = 3
        # v0.5: out and back, so there is no reset. v0.4 grew the radius
        # linearly and snapped it to 0 at every wrap - radius 0.85 -> 0
        # and amplitude 1.00 -> 0.55 in one control step.
        .q = .ph / (2 * pi) - floor(.ph / (2 * pi))
        .rr = .r * (1 - abs(2 * .q - 1))
        .x = .rr * sin(.ph)
        .y = .rr * cos(.ph)
        .amp = 0.55 + 0.45 * (.rr / .r)
    elsif pattern = 4
        .tx = 2 * abs(2 * (.ph / (2 * pi) - floor(.ph / (2 * pi))) - 1) - 1
        .py = .ph * 0.75 / (2 * pi)
        .ty = 2 * abs(2 * (.py - floor(.py)) - 1) - 1
        .x = .r * .tx
        .y = .r * .ty
        .amp = 0.6 + 0.4 * (abs(.tx) + abs(.ty)) / 2
    elsif pattern = 5
        .x = .r * 0.72 * sin(.ph * 1.7 + 0.4) * cos(.ph * 0.9)
        .y = .r * 0.72 * cos(.ph * 1.3) * sin(.ph * 2.1 + 1.1)
        .amp = 0.7 + 0.3 * abs(sin(.ph * 2.3))
    elsif pattern = 6
        .rr = .r * (0.35 + 0.65 * abs(sin(.ph / 6)))
        .x = .rr * sin(.ph)
        .y = .rr * cos(.ph)
        .amp = 0.65 + 0.35 * (.rr / .r)
    elsif pattern = 7
        .x = .r * sin(.ph)
        .y = .r * 0.35 * sin(.ph * 2 + pi / 3)
        .amp = 0.7 + 0.3 * abs(sin(.ph))
    elsif pattern = 8
        .x = .r * sin(3 * .ph)
        .y = .r * cos(2 * .ph)
        .amp = 0.65 + 0.35 * abs(sin(5 * .ph))
    elsif pattern = 9
        # Soft-gated jumps between six nodes
        .node = floor(.ph / (2 * pi) * 6)
        .nfrac = .ph / (2 * pi) * 6 - .node
        .na = (.node mod 6) / 6 * 2 * pi
        .x = .r * sin(.na)
        .y = .r * cos(.na)
        .gate = 0.5 + 0.5 * tanh(10 * (sin(pi * .nfrac) - 0.35))
        .amp = 0.25 + 0.75 * .gate
    elsif pattern = 10
        .cx = .r * 0.5 * sin(.ph / 4)
        .cy = .r * 0.5 * cos(.ph / 4)
        .x = .cx + .r * 0.45 * sin(.ph * 5.3)
        .y = .cy + .r * 0.45 * cos(.ph * 7.1)
        .amp = 0.6 + 0.4 * abs(sin(.ph * 3.7))
    elsif pattern = 11
        # Two strands: position follows one, amplitude the other
        .x = .r * sin(.ph)
        .y = .r * 0.45 * sin(2 * .ph)
        .amp = 0.55 + 0.45 * (0.5 + 0.5 * sin(.ph + pi / 2))
    elsif pattern = 12
        .rr = .r * (0.55 + 0.45 * sin(.ph / 3))
        .x = .rr * sin(.ph)
        .y = .rr * cos(.ph)
        .amp = 0.7 + 0.3 * abs(cos(.ph / 3))
    elsif pattern = 13
        # v0.4: tanh soft gate plus a decay, instead of sin(...) > 0.6,
        # which stepped from 0 to 1 at the crossing.
        .sph = sin(.ph)
        .gate = 0.5 + 0.5 * tanh(12 * (.sph - 0.6))
        .strikeFrac = .ph / (2 * pi) - floor(.ph / (2 * pi))
        .decay = exp(-3 * .strikeFrac)
        .na = floor(.ph / (2 * pi)) * 2.399963
        .x = .r * sin(.na)
        .y = .r * cos(.na)
        .amp = 0.12 + 0.88 * .gate * (0.35 + 0.65 * .decay)
    elsif pattern = 14
        # v0.4: circular distance to the beat, so the envelope is
        # continuous across the cycle boundary. exp(-10*phase^2) with
        # phase in [0,1) jumped from 0.00005 to 1 at every wrap.
        .bp = .ph / (2 * pi) - floor(.ph / (2 * pi))
        .d1 = min(.bp, 1 - .bp)
        .d2r = abs(.bp - 0.32)
        .d2 = min(.d2r, 1 - .d2r)
        .beat1 = exp(-90 * .d1 * .d1)
        .beat2 = 0.65 * exp(-140 * .d2 * .d2)
        .x = .r * 0.35 * sin(.ph / 4)
        .y = .r * 0.35 * cos(.ph / 4)
        .amp = 0.18 + 0.82 * min(1, .beat1 + .beat2)
    else
        .rr = .r * (0.15 + 0.85 * (0.5 + 0.5 * sin(.ph)))
        .x = .rr * sin(.ph / 3)
        .y = .rr * cos(.ph / 3)
        .amp = 0.5 + 0.5 * (0.5 + 0.5 * sin(.ph))
    endif

    # v0.5: one radius clamp for every pattern, so Path_radius really is
    # the greatest distance from the listener. Without it Bounce and
    # Plasma both reached sqrt(2)*r = 1.414r (1.386 at the 0.98 limit,
    # outside the speaker ring), Quantum 1.134r and Wave 1.049r, while
    # the header claimed everything stayed inside the unit disc.
    .rho = sqrt(.x * .x + .y * .y)
    if .rho > path_radius and .rho > 1e-12
        .scaleBack = path_radius / .rho
        .x = .x * .scaleBack
        .y = .y * .scaleBack
    endif

    if .amp < 0
        .amp = 0
    endif
    if .amp > 1
        .amp = 1
    endif
endproc

# Speaker gains from a source position. Gaussian weights on squared
# distance, with the common factor divided out so nothing underflows,
# then either constant-power normalised or left as a raw gain field.
procedure speakerGains: .sx, .sy, .amp
    .d2min = 1e300
    for .k from 1 to 8
        if isDir[.k] = 1
            .dx = .sx - spkX[.k]
            .dy = .sy - spkY[.k]
            .dd = .dx * .dx + .dy * .dy
            d2[.k] = .dd
            if .dd < .d2min
                .d2min = .dd
            endif
        endif
    endfor
    .sumsq = 0
    for .k from 1 to 8
        if isDir[.k] = 1
            gw[.k] = exp(-source_focus * (d2[.k] - .d2min))
            .sumsq = .sumsq + gw[.k] * gw[.k]
        else
            gw[.k] = 0
        endif
    endfor
    if spatialisation = 1
        .norm = sqrt(.sumsq)
        if .norm < 1e-12
            .norm = 1e-12
        endif
    else
        .norm = 1
    endif
    for .k from 1 to 8
        if isDir[.k] = 1
            gw[.k] = gw[.k] / .norm * .amp
        endif
    endfor
endproc

# ============================================================
# BUILD THE GAIN ENVELOPES
# ============================================================
stopwatch
for k from 1 to 8
    if isDir[k] = 1
        Create AmplitudeTier: "bsTier" + string$(k), 0, duration
        tierID[k] = selected("AmplitudeTier")
    else
        tierID[k] = 0
    endif
endfor

# Also record the path and the energy centroid for the plot, so the
# picture is generated from the same numbers as the audio.
# v0.5: the drawn path has to resolve the motion too. v0.4 capped it at
# 600 points for the whole file, so 64 file cycles x Lightning's
# multiplier 8 = 512 phase cycles gave 1.17 points per cycle and the
# plotted path was not the path.
nTrace = ceiling(20 * fastRate * duration)
if nTrace < 600
    nTrace = 600
endif
traceCapped = 0
if nTrace > 6000
    nTrace = 6000
    traceCapped = 1
endif
if nTrace > nCtrl
    nTrace = nCtrl
endif
tracePerCycle = nTrace / (patRate * duration)

for i from 0 to nCtrl
    t = i * duration / nCtrl
    @trajectory: t
    @speakerGains: trajectory.x, trajectory.y, trajectory.amp
    for k from 1 to 8
        if isDir[k] = 1
            selectObject: tierID[k]
            Add point: t, gw[k]
        endif
    endfor
endfor
envElapsed = stopwatch

# ============================================================
# APPLY
# ============================================================
stopwatch
for k from 1 to 8
    if isDir[k] = 1
        selectObject: monoID
        plusObject: tierID[k]
        Multiply
        channel[k] = selected("Sound")
        Rename: "bsCh" + string$(k)
    endif
endfor

# v0.4: a real LFE. Band-limited mono sum at its own fixed level, no
# part in the trajectory and no part in the normalisation.
if speaker_format = 1
    selectObject: monoID
    Filter (pass Hann band): 0, lfeCut, 30
    lfeFiltered = selected("Sound")
    Formula: "self * " + fixed$(lfe_level, 8)
    channel[4] = lfeFiltered
    selectObject: channel[4]
    Rename: "bsCh4_LFE"
endif

for k from 1 to 8
    selectObject: channel[k]
    chDur[k] = Get total duration
endfor

# Shared gain across the directional channels, so the spatial field is
# preserved; the LFE keeps its own level and is not dragged with it.
peakDir = 0
for k from 1 to 8
    if isDir[k] = 1
        selectObject: channel[k]
        thisPeak = Get absolute extremum: 0, 0, "None"
        if thisPeak > peakDir
            peakDir = thisPeak
        endif
    endif
endfor
if peakDir < 1e-9
    peakDir = 1e-9
endif
sharedGain = peak_target / peakDir
# v0.5: the LF channel is excluded from the SPATIAL normalisation - it
# takes no part in sum(g^2) - but it must still take the global output
# gain, or Lfe_level stops meaning a fixed ratio to the main channels.
# In v0.4 a quiet source pushed sharedGain to x135 on the directional
# channels while the LF channel stayed put, so the LF:main ratio moved
# from 0.379 to 0.004 with nothing but the input level.
for k from 1 to 8
    selectObject: channel[k]
    Formula: "self * " + fixed$(sharedGain, 10)
endfor

for k from 1 to 8
    if tierID[k] <> 0
        removeObject: tierID[k]
    endif
endfor

# ============================================================
# OUTPUT FORMATS
# ============================================================
# Chosen for what these channels are. A "4 stereo pairs" split would
# pair Centre with LFE, which is not a stereo pair in any useful sense.

procedure mixDown: .name$, .n
    # Builds an .n-channel object from mixW[(out-1)*9 + src].
    # Source slot 9 is a derived LF channel, used only when Ch4 is a
    # full-range speaker and a 5.1 output still needs an LFE.
    for .o from 1 to .n
        .cnt = 0
        for .s from 1 to 9
            if mixW[(.o - 1) * 9 + .s] > 1e-9
                selectObject: channel[.s]
                Copy: "bsmixtmp"
                .cnt = .cnt + 1
                tmpM[.cnt] = selected("Sound")
                Formula: "self * " + fixed$(mixW[(.o - 1) * 9 + .s], 8)
            endif
        endfor
        selectObject: tmpM[1]
        for .j from 2 to .cnt
            plusObject: tmpM[.j]
        endfor
        if .cnt > 1
            Combine to stereo
            .stack = selected("Sound")
            Convert to mono
            mixCh[.o] = selected("Sound")
            removeObject: .stack
            selectObject: mixCh[.o]
            Formula: "self * " + fixed$(.cnt, 8)
        else
            Copy: "bsmixch"
            mixCh[.o] = selected("Sound")
        endif
        for .j from 1 to .cnt
            removeObject: tmpM[.j]
        endfor
    endfor
    selectObject: mixCh[1]
    for .o from 2 to .n
        plusObject: mixCh[.o]
    endfor
    Combine to stereo
    .out = selected("Sound")
    Rename: .name$
    for .o from 1 to .n
        removeObject: mixCh[.o]
    endfor
endproc

for o from 1 to 8
    for s from 1 to 9
        mixW[(o - 1) * 9 + s] = 0
    endfor
endfor

half = 1 / sqrt(2)

# Slot 9: a derived LF channel, created only when it is needed - Ch4 is
# a full-range speaker and the output format has an LFE slot.
channel[9] = 0
if hasLF = 0 and output_format = 3
    selectObject: monoID
    Filter (pass Hann band): 0, lfeCut, 30
    channel[9] = selected("Sound")
    Rename: "bsCh9_derivedLF"
    Formula: "self * " + fixed$(lfe_level * sharedGain, 10)
endif

# v0.5: the downmix matrices depend on what Ch4 IS. With a derived LF
# channel it belongs in the LFE slot of a 5.1 and nowhere else; with a
# full-range Ch4 it is a directional speaker that must be folded into
# the surrounds, and a fresh LF channel has to be derived for 5.1.
# v0.4 used one matrix for both, so in full-range mode a wideband rear
# speaker was routed straight into an LFE channel, and in quad and
# stereo it vanished entirely.

if output_format = 1
    selectObject: channel[1]
    for k from 2 to 8
        plusObject: channel[k]
    endfor
    Combine to stereo
    result = selected("Sound")
    outChannels = 8
    if hasLF = 1
        outFormat$ = "7.1 (LF on Ch4)"
    else
        outFormat$ = "8.0 full-range (Ch4 directional)"
    endif

elsif output_format = 2
    selectObject: channel[1], channel[2], channel[3], channel[5]
    plusObject: channel[6], channel[7], channel[8]
    Combine to stereo
    result = selected("Sound")
    outChannels = 7
    if hasLF = 1
        outFormat$ = "7.0 full-range (LF channel dropped)"
    else
        outFormat$ = "7.0 (Ch4 dropped - it was a directional speaker)"
    endif

elsif output_format = 3
    # 5.1, output order FL FR C LFE SL SR.
    mixW[1] = 1
    mixW[9 + 2] = 1
    mixW[18 + 3] = 1
    mixW[36 + 5] = 1
    mixW[36 + 7] = half
    mixW[45 + 6] = 1
    mixW[45 + 8] = half
    if hasLF = 1
        # Ch4 is already band-limited, so it is the LFE.
        mixW[27 + 4] = 1
        lfeNote$ = "LFE from the derived LF channel on Ch4"
    else
        # Ch4 is a full-range rear speaker. Routing it into an LFE slot
        # would put wideband content in a band-limited channel, which
        # is what v0.4 did. It is split equal-power into the surrounds,
        # and the LFE comes from slot 9 instead.
        mixW[36 + 4] = half
        mixW[45 + 4] = half
        mixW[27 + 9] = 1
        lfeNote$ = "LFE lowpassed from the source; Ch4 folded into SL/SR"
    endif
    @mixDown: originalName$ + "_51_" + patternName$, 6
    result = mixDown.out
    outChannels = 6
    outFormat$ = "5.1 downmix (BL/BR into SL/SR)"

elsif output_format = 4
    # Quad FL FR BL BR. C splits to the front pair, SL/SR to the back.
    mixW[1] = 1
    mixW[3] = half
    mixW[9 + 2] = 1
    mixW[9 + 3] = half
    mixW[18 + 7] = 1
    mixW[18 + 5] = half
    mixW[27 + 8] = 1
    mixW[27 + 6] = half
    if hasLF = 0
        # v0.5: a full-range Ch4 must not simply disappear.
        mixW[18 + 4] = half
        mixW[27 + 4] = half
    endif
    @mixDown: originalName$ + "_quad_" + patternName$, 4
    result = mixDown.out
    outChannels = 4
    outFormat$ = "4.0 quad downmix"

else
    # Stereo downmix. Not binaural: a weighted sum, with no HRTF, no
    # ITD, no head shadow and no pinna filtering.
    mixW[1] = 1
    mixW[3] = 0.707
    mixW[5] = 0.5
    mixW[7] = 0.35
    mixW[9 + 2] = 1
    mixW[9 + 3] = 0.707
    mixW[9 + 6] = 0.5
    mixW[9 + 8] = 0.35
    if hasLF = 0
        # v0.5: a full-range Ch4 sits centre-rear, so it goes to both
        # sides equally rather than being dropped.
        mixW[4] = 0.35
        mixW[9 + 4] = 0.35
    endif
    @mixDown: originalName$ + "_stereo_" + patternName$, 2
    result = mixDown.out
    outChannels = 2
    outFormat$ = "stereo downmix (not binaural)"
endif

selectObject: result
if output_format = 1 or output_format = 2
    Rename: originalName$ + "_surr_" + patternName$
endif
resultName$ = selected$("Sound")
Scale peak: peak_target
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
applyElapsed = stopwatch

# v0.4: keeping the stems is now an explicit choice, and there is
# always a result object, so it is no longer possible to end the run
# with nothing at all.
if keep_8_mono_stems
    for k from 1 to 8
        selectObject: channel[k]
        Rename: originalName$ + "_stem" + string$(k) + "_" + chLabel$[k]
    endfor
    stemNote$ = "8 mono stems kept"
else
    stemNote$ = "stems removed"
endif

# ============================================================
# REPORT
# ============================================================
writeInfoLine: "=== BPM Surround Panning v0.5 ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(duration, 2), " s @ ", sr, " Hz)"
appendInfoLine: "Pattern: ", patternName$
appendInfoLine: ""

appendInfoLine: "Rate: ", rateDesc$
appendInfoLine: "  Base rate ", fixed$(baseRate, 4), " Hz"
appendInfoLine: "  Primary phase rate: ", fixed$(rateMult[pattern], 2),
    ... "x the base = ", fixed$(patRate, 4), " Hz"
appendInfoLine: "  = ", fixed$(patRate * duration, 2),
    ... " PRIMARY PHASE CYCLES over the file"
appendInfoLine: "  Fastest internal component: ", fixed$(fastMult[pattern], 2),
    ... "x that = ", fixed$(fastRate, 3), " Hz"
appendInfoLine: "  Note this is the phase rate, not necessarily the rate at which the"
appendInfoLine: "  SHAPE repeats. Bounce uses a 0.75 ratio between its axes and closes"
appendInfoLine: "  after 4 phase cycles; Galaxy modulates its radius at phase/3 and"
appendInfoLine: "  Breathing steers at phase/3, so both take 3; Heartbeat moves its"
appendInfoLine: "  position at phase/4, so 4. Swarm and Quantum combine several"
appendInfoLine: "  incommensurate terms and have no single repeat period at all."
if rate_mode = 2
    appendInfoLine: "  NOTE: file-synchronous. The same setting gives a different rate"
    appendInfoLine: "        on a different-length file - 8 cycles is 2 Hz over 4 s and"
    appendInfoLine: "        0.2 Hz over 40 s. Use BPM-locked for tempo sync."
endif
appendInfoLine: "  v0.3 multiplied the base rate inside each pattern without saying so,"
appendInfoLine: "  so 'Circle' gave 1 cycle per base cycle and 'Lightning' gave 8."
appendInfoLine: ""

appendInfoLine: "Speakers: ", formatName$
for k from 1 to 8
    if isDir[k] = 1
        appendInfoLine: "  Ch", k, " ", chLabel$[k], "  ", spkAngle[k], " deg   x=",
            ... fixed$(spkX[k], 3), "  y=", fixed$(spkY[k], 3)
    else
        appendInfoLine: "  Ch", k, " ", chLabel$[k], "  lowpass ", fixed$(lfeCut, 0),
            ... " Hz at level ", fixed$(lfe_level, 2)
        appendInfoLine: "        DERIVED low-frequency channel: not spatialised and not"
        appendInfoLine: "        part of sum(g^2), but it DOES take the global output gain,"
        appendInfoLine: "        so Lfe_level stays a fixed ratio to the main channels."
        appendInfoLine: "        Strictly this is a derived LF channel, not a true LFE -"
        appendInfoLine: "        a real LFE carries separately authored content, not a"
        appendInfoLine: "        lowpass of the same source."
    endif
endfor
appendInfoLine: "  ", nDir, " directional channel(s) carry the movement."
appendInfoLine: "  All gains come from these angles through one panner, so a pattern"
appendInfoLine: "  cannot carry a phase that disagrees with the map. In v0.3 Circle"
appendInfoLine: "  drove FL at 225 deg and BL at 315 deg against a map of 330 and 210,"
appendInfoLine: "  which swapped the two left speakers."
appendInfoLine: ""

if spatialisation = 1
    appendInfoLine: "Spatialisation: energy-preserving."
    appendInfoLine: "  The SQUARED directional gains sum to the pattern amplitude"
    appendInfoLine: "  squared, so movement does not pump the level."
    appendInfoLine: "  v0.3's Circle ran between 1.91 and 2.81 - 1.68 dB of pumping."
    appendInfoLine: "  Exact AT THE CONTROL POINTS: the AmplitudeTier interpolates each"
    appendInfoLine: "  channel linearly and independently, so between two points the sum"
    appendInfoLine: "  dips slightly. At ", fixed$(ptsPerFast, 0),
        ... " points per fast cycle that is negligible." 
else
    appendInfoLine: "Spatialisation: creative gain field."
    appendInfoLine: "  Gains are left unnormalised, so the overall level rises and falls"
    appendInfoLine: "  with the pattern. That is an effect, not panning alone."
endif
appendInfoLine: "  Source focus ", fixed$(source_focus, 2), "   path radius ",
    ... fixed$(path_radius, 2)
appendInfoLine: ""

appendInfoLine: "Control rate: ", fixed$(ctrlRate, 1), " Hz, ", nCtrl, " points"
appendInfoLine: "  = ", fixed$(ctrlRate / patRate, 1), " points per primary phase cycle"
appendInfoLine: "  = ", fixed$(ptsPerFast, 1),
    ... " points per cycle of the fastest internal component"
if ctrlCapped = 1
    appendInfoLine: "  NOTE: the control rate hit its 8000 Hz cap, so the figure above"
    appendInfoLine: "        is lower than the 32 points per fast cycle asked for."
endif
if nCtrlCapped = 1
    appendInfoLine: "  NOTE: the point count hit its 400000 cap and the control rate"
    appendInfoLine: "        was reduced to fit. Use a shorter source for finer motion."
endif
appendInfoLine: "Plot sampling: ", nTrace, " points = ", fixed$(tracePerCycle, 1),
    ... " per primary phase cycle"
if traceCapped = 1
    appendInfoLine: "  NOTE: the drawn path hit its cap and is decimated relative to"
    appendInfoLine: "        the audio. The rendering is unaffected."
endif
appendInfoLine: ""

appendInfoLine: "Output: ", outFormat$, "  (", outChannels, " channels, ",
    ... fixed$(finalDur, 2), " s)"
if output_format = 3
    appendInfoLine: "  ", lfeNote$
endif
appendInfoLine: "  ", stemNote$
appendInfoLine: "  Shared gain across the directional channels: x",
    ... fixed$(sharedGain, 4), " (from peak ", fixed$(peakDir, 4), ")"
appendInfoLine: "  Final peak ", fixed$(finalPeak, 4)
if output_format = 5
    appendInfoLine: "  The stereo downmix is a weighted sum. It is NOT binaural:"
    appendInfoLine: "  no HRTF, no ITD, no head shadow, no pinna filtering."
endif
appendInfoLine: ""
appendInfoLine: "(envelopes ", fixed$(envElapsed, 2), " s   apply ",
    ... fixed$(applyElapsed, 2), " s)"

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all

    chColR[1] = 0.80
    chColG[1] = 0.25
    chColB[1] = 0.25
    chColR[2] = 0.85
    chColG[2] = 0.50
    chColB[2] = 0.15
    chColR[3] = 0.25
    chColG[3] = 0.60
    chColB[3] = 0.25
    chColR[4] = 0.45
    chColG[4] = 0.45
    chColB[4] = 0.45
    chColR[5] = 0.25
    chColG[5] = 0.45
    chColB[5] = 0.82
    chColR[6] = 0.55
    chColG[6] = 0.30
    chColB[6] = 0.72
    chColR[7] = 0.15
    chColG[7] = 0.62
    chColB[7] = 0.70
    chColR[8] = 0.70
    chColG[8] = 0.62
    chColB[8] = 0.15

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##BPM SURROUND PANNING##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    if rate_mode = 1
        rateTag$ = fixed$(tempo_bpm, 0) + " BPM " + subName$
    else
        rateTag$ = string$(numCycles) + " file cycles"
    endif
    if spatialisation = 1
        spatTag$ = "energy-preserving"
    else
        spatTag$ = "gain field"
    endif
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  " + patternName$
        ... + "  |  " + rateTag$
        ... + "  |  " + fixed$(patRate, 2) + " Hz"
        ... + "  |  " + spatTag$
        ... + "  |  " + outFormat$

    # ----------------------------------------------------------
    # PANEL A: SPEAKER MAP, SOURCE PATH AND ENERGY CENTROID
    # ----------------------------------------------------------
    # v0.4: the centre-of-mass trajectory the v0.3 changelog promised
    # but never drew, computed as sum(g^2 * pos) / sum(g^2) with the
    # LFE excluded - alongside the source path, so the two can be
    # compared. The centroid always sits inside the speaker ring; the
    # source path may reach further out.
    Select outer viewport: 0, 4.2, 0.72, 4.20
    Select inner viewport: 0.40, 4.00, 0.82, 4.08

    Axes: -1.5, 1.5, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.5, 1.5, -1.5, 1.5

    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    Draw ellipse: -1, 1, -1, 1
    Draw ellipse: -0.5, 0.5, -0.5, 0.5
    Draw line: 0, -1.4, 0, 1.4
    Draw line: -1.4, 0, 1.4, 0

    # Source path
    Line width: 1.5
    prevSX = 0
    prevSY = 0
    prevCX = 0
    prevCY = 0
    for j from 0 to nTrace
        tj = j * duration / nTrace
        @trajectory: tj
        sxj = trajectory.x
        syj = trajectory.y
        @speakerGains: sxj, syj, trajectory.amp
        wsum = 0
        cxj = 0
        cyj = 0
        for k from 1 to 8
            if isDir[k] = 1
                wsq = gw[k] * gw[k]
                wsum = wsum + wsq
                cxj = cxj + wsq * spkX[k]
                cyj = cyj + wsq * spkY[k]
            endif
        endfor
        if wsum > 1e-12
            cxj = cxj / wsum
            cyj = cyj / wsum
        else
            cxj = 0
            cyj = 0
        endif
        if j > 0
            frac = j / nTrace
            srcCol$ = "{" + fixed$(0.55 + frac * 0.35, 2) + ", " + fixed$(0.72 - frac * 0.30, 2) + ", " + fixed$(0.85 - frac * 0.45, 2) + "}"
            Colour: srcCol$
            Draw line: prevSX, prevSY, sxj, syj
            cenCol$ = "{" + fixed$(0.15 + frac * 0.35, 2) + ", 0.15, " + fixed$(0.55 - frac * 0.35, 2) + "}"
            Colour: cenCol$
            Line width: 2
            Draw line: prevCX, prevCY, cxj, cyj
            Line width: 1.5
        endif
        prevSX = sxj
        prevSY = syj
        prevCX = cxj
        prevCY = cyj
    endfor
    Line width: 1

    # Speakers, sized by their mean gain
    for k from 1 to 8
        meanG[k] = 0
    endfor
    for j from 0 to nTrace
        tj = j * duration / nTrace
        @trajectory: tj
        @speakerGains: trajectory.x, trajectory.y, trajectory.amp
        for k from 1 to 8
            meanG[k] = meanG[k] + gw[k]
        endfor
    endfor
    for k from 1 to 8
        meanG[k] = meanG[k] / (nTrace + 1)
    endfor

    for k from 1 to 8
        if isDir[k] = 1
            dotR = 2.2 + 5.0 * meanG[k]
            if dotR > 7
                dotR = 7
            endif
            spkCol$ = "{" + fixed$(chColR[k], 2) + ", " + fixed$(chColG[k], 2) + ", " + fixed$(chColB[k], 2) + "}"
            Paint circle (mm): spkCol$, spkX[k], spkY[k], dotR
            Colour: "White"
            Font size: 5
            Text: spkX[k], "centre", spkY[k], "half", string$(k)
            Colour: "{0.40, 0.40, 0.40}"
            Font size: 4
            Text: spkX[k] * 1.22, "centre", spkY[k] * 1.22, "half", chLabel$[k]
        endif
    endfor
    if speaker_format = 1
        Paint circle (mm): "{0.55, 0.55, 0.55}", 0, -1.28, 2.4
        Font size: 4
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0.30, "left", -1.28, "half", "LFE (not spatialised)"
    endif

    Paint circle (mm): "{0.22, 0.62, 0.30}", 0, 0, 2.6

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Source path (light) and energy centroid (dark)"

    # ----------------------------------------------------------
    # PANEL B: GAIN ENVELOPES OVER ONE PATTERN CYCLE
    # ----------------------------------------------------------
    # v0.4: recomputed from the same procedures the audio used. v0.3
    # divided processed audio by source audio, which is a
    # source-energy-weighted RMS ratio and shows a different shape
    # wherever the source is quiet or transient.
    Select outer viewport: 4.2, 8, 0.72, 2.55
    Select inner viewport: 4.55, 7.75, 0.82, 2.45

    cycDur = 1 / patRate
    if cycDur > duration
        cycDur = duration
    endif

    Axes: 0, cycDur, 0, 1.05
    Paint rectangle: "{0.96, 0.96, 0.96}", 0, cycDur, 0, 1.05

    nPlot = 300
    Line width: 1.2
    for k from 1 to 8
        if isDir[k] = 1
            envCol$ = "{" + fixed$(chColR[k], 2) + ", " + fixed$(chColG[k], 2) + ", " + fixed$(chColB[k], 2) + "}"
            Colour: envCol$
            @trajectory: 0
            @speakerGains: trajectory.x, trajectory.y, trajectory.amp
            prevG = gw[k]
            prevT = 0
            for j from 1 to nPlot
                tj = j / nPlot * cycDur
                @trajectory: tj
                @speakerGains: trajectory.x, trajectory.y, trajectory.amp
                gj = gw[k]
                if gj > 1.05
                    gj = 1.05
                endif
                Draw line: prevT, prevG, tj, gj
                prevT = tj
                prevG = gj
            endfor
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 5
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Gain"
    Text bottom: "yes", "Gain envelopes, one pattern cycle (colour = channel)"

    # ----------------------------------------------------------
    # PANEL C: POLAR MEAN GAIN
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 2.62, 4.20
    Select inner viewport: 4.55, 7.75, 2.70, 4.10

    Axes: -1.35, 1.35, -1.35, 1.35
    Paint rectangle: "{0.96, 0.96, 0.96}", -1.35, 1.35, -1.35, 1.35
    Colour: "{0.88, 0.88, 0.88}"
    Draw ellipse: -1, 1, -1, 1
    Draw ellipse: -0.5, 0.5, -0.5, 0.5
    Draw line: 0, -1.25, 0, 1.25
    Draw line: -1.25, 0, 1.25, 0

    maxMean = 0.001
    for k from 1 to 8
        if isDir[k] = 1 and meanG[k] > maxMean
            maxMean = meanG[k]
        endif
    endfor

    Line width: 3
    for k from 1 to 8
        if isDir[k] = 1
            rr = meanG[k] / maxMean
            polCol$ = "{" + fixed$(chColR[k], 2) + ", " + fixed$(chColG[k], 2) + ", " + fixed$(chColB[k], 2) + "}"
            Colour: polCol$
            Draw line: 0, 0, spkX[k] * rr, spkY[k] * rr
            Paint circle (mm): polCol$, spkX[k] * rr, spkY[k] * rr, 1.8
        endif
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text bottom: "yes", "Mean gain per speaker (normalised to the loudest)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.28, 5.40
    Select inner viewport: 0.55, 7.75, 4.34, 5.33

    selectObject: result
    resPeak = Get absolute extremum: 0, 0, "None"
    if resPeak < 0.001
        resPeak = 0.001
    endif
    ampMax = resPeak * 1.15
    Axes: 0, finalDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, finalDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, finalDur, 0

    selectObject: result
    Extract one channel: 1
    vizA = selected("Sound")
    Colour: "{0.80, 0.25, 0.25}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"

    selectObject: result
    Extract one channel: 2
    vizB = selected("Sound")
    Colour: "{0.85, 0.50, 0.15}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    removeObject: vizA, vizB

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text top: "no", "Output channels 1 and 2  (two of " + string$(outChannels) + ")"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.48, 6.55
    Select inner viewport: 0.55, 7.75, 5.54, 6.49
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.80, "half",
        ... "##" + patternName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + rateTag$
        ... + "  |  " + fixed$(patRate, 3) + " Hz = "
        ... + fixed$(patRate * duration, 1) + " cycles"
        ... + "  |  " + fixed$(finalDur, 2) + " s"

    Text: 0.02, "left", 0.50, "half",
        ... formatName$
        ... + "  |  " + string$(nDir) + " directional ch"
        ... + "  |  " + spatTag$
        ... + "  |  focus " + fixed$(source_focus, 2)
        ... + "  |  radius " + fixed$(path_radius, 2)

    Text: 0.02, "left", 0.20, "half",
        ... "Output: " + outFormat$
        ... + "  |  " + stemNote$
        ... + "  |  Peak " + fixed$(finalPeak, 3)

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# CLEANUP
# ============================================================
removeObject: monoID
if channel[9] <> 0
    removeObject: channel[9]
endif
if keep_8_mono_stems = 0
    for k from 1 to 8
        removeObject: channel[k]
    endfor
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", resultName$

if play_result
    selectObject: result
    Play
endif

selectObject: result
if keep_8_mono_stems
    for k from 1 to 8
        plusObject: channel[k]
    endfor
endif
