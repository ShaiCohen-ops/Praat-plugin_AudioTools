# ============================================================
# Praat AudioTools - Perceptual_Fugue.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Perceptual Fugue - a fugue-inspired polyphonic audio construction.
#     - Voices are pitch-transposed entries of the source (subject)
#     - Each voice carries a FIXED SPATIAL SIGNATURE (ITD/ILD/shadow)
#     - The subject is stated, answered, retrograded, augmented,
#       fragmented, and compressed in stretto
#
#   "A fugue where the voices are localization cues
#    and the subject is perceptual certainty."
#
#   VOICES. The SPATIAL identity is fixed for the whole piece; the
#   pitch and register follow the section, as they do in the tradition -
#   V1 takes the doubly transposed head motif in the episode, V3 takes
#   the augmented subject in the middle entries, and so on. v2.3 claimed
#   a fixed pitch identity per voice, which the score does not support.
#     V1 Dux    : original pitch, strongly LEFT-BIASED signature
#     V2 Comes  : answer interval, strongly RIGHT-BIASED (mirror of V1)
#     V3 Third  : octave below, centred, with a POLARITY-inverted right
#                 channel. That is polarity inversion, not melodic or
#                 contrapuntal inversion - the interval directions of
#                 the subject are unchanged. It also makes V3 poorly
#                 mono-compatible by design; see the report.
#     V4 Fourth : answer low, CENTRED reverberant field (optional).
#                 The wet signal is identical in both channels, so it
#                 is correlated and centred, not diffuse.
#
#   None of the voices is hard-panned: both channels always carry the
#   voice, with one leading in time, the other lowpassed, and a shared
#   wet component. The ITD range here (3-4 ms) is far larger than the
#   geometric interaural delay of a head, so it works as a precedence
#   or micro-echo effect rather than a natural ITD.
#
#   FUGUE STRUCTURE:
#     I.   Exposition     : subject/answer/subject entries, 1 per subDur
#     II.  Episode        : head-motif fragments, transposed, passed
#     III. Middle Entries : retrograde + answer + augmented (2x)
#     IV.  Stretto        : compressed entries pile up
#     V.   Pedal/Cadence  : augmented drone, final subject, fade
#
# Changelog v2.3 (2026):
#   Visualization fixes only - audio output is unchanged.
#   - FIX: spectrogram was computed on the stereo fugue, but
#     To Spectrogram is mono-only and errors on a stereo Sound.
#     Now analyzes the already-extracted left channel (vizLeft).
#   - FIX: subtitle (y=-0.2) overflowed the title band into the
#     left-waveform panel; title and subtitle now sit in separate
#     viewport bands.
#
# Changelog v2.2 (2026):
#   Speed-focused refactor. Output is the same construction —
#   placement, transposition, spatialization unchanged — just
#   considerably faster.
#
#   - SPEED: placeAt now mixes the fragment into the timeline
#     in-place via Formula (part) instead of Extract+Concat.
#     The original procedure rebuilt the entire timeline buffer
#     on every call (~20 calls per script run on multi-second
#     buffers). In-place mixing is dramatically faster.
#   - SPEED: makeDelay now writes the delayed signal into a
#     pre-allocated zero buffer via Formula (part) instead of
#     Concat+Extract. Called many times by applySpatial via
#     reverb taps and early reflections.
#   - SPEED: transposeByRatio's Resample precision is now tied
#     to a Speed_mode form parameter (Full/Balanced/Fast =
#     precision 50/20/10).
#   - FIX: Removed conflicting Scale intensity + Scale peak pair
#     at the end of the pipeline. Scale intensity was setting
#     RMS to a target dB, then Scale peak rescaled the peak —
#     making the intensity calibration meaningless. Now keeps
#     only Scale peak: 0.99 (predictable, no clipping). The
#     section_intensity_dB form field has been removed since
#     it no longer affects the output.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Spatial & Immersive Audio
# ============================================================

# ============================================================
# INPUT VALIDATION
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
soundName$ = selected$("Sound")

selectObject: original
nChannels = Get number of channels
monoDur = Get total duration
monoSr = Get sampling frequency

if nChannels > 2
    exitScript: "Please select a mono or stereo Sound."
endif

if monoDur < 0.1
    exitScript: "Sound too short (minimum 0.1 s)."
endif

# ============================================================
# FORM
# ============================================================

# Changelog v2.5 (2026):
#   - FIX: in the varispeed+PSOLA method the pitch analysis runs AFTER
#     the varispeed, so the material sits at r times its original
#     pitch - but the original Pitch_floor/Pitch_ceiling were still
#     used. An octave down turns 70 Hz into 35 Hz, below a 50 Hz floor;
#     the doubly transposed head motif turns 400 Hz into 898 Hz, above
#     an 800 Hz ceiling. In both cases the tracker loses the material
#     and the compensating stretch degrades. The range is scaled by the
#     ratio, with a 20 Hz floor and a Nyquist-relative ceiling. The
#     PitchTier method needs no such change - it analyses the source
#     before the frequencies are multiplied.
#   - FIX: Reverb_tail_seconds did not set any reverb time. The per-
#     voice decays are fixed (V1/V2 0.35 s, V3 0.5 s, V4 0.8 s) and the
#     field only sized the timeline, so a small value cut the tail off
#     and a large one left silence. Renamed Tail_allocation_seconds,
#     and it is now raised automatically to at least the longest
#     internal decay plus the ITD, so nothing is cut.
#   - Renamed the reverb amount, in the comments and the report, as a
#     SEND GAIN rather than a wet percentage: the three taps sum to 2.0
#     before filtering, so 0.60 is about 1.2x a single dry tap. The
#     values are unchanged - they were tuned by ear - only the claim is.
#   - Added the missing input checks: Pitch_floor below Pitch_ceiling,
#     Shadow_cutoff below Nyquist, and an ILD factor below 1 inverted
#     rather than silently swapping V1 and V2's declared sides.
#   - FIX: the mono figure was labelled "energy retained", which it is
#     not. It compares the mono fold against an UNCORRELATED reference,
#     so it runs 0-200%: 200 means identical and in phase, 100 means
#     uncorrelated, 0 means anti-phase. Labelled properly, with the
#     anchors printed and a correlation coefficient alongside.
#   - FIX: the cadence fade used exp(-5q), which ends at -43.5 dB
#     rather than zero. It is a raised cosine now, so it lands on
#     silence.
#   - The constant-power ILD claim is narrowed to the DIRECT path. The
#     far-side lowpass, the shared wet signal, the reflections, the
#     anchor and V3's polarity inversion all still move the final voice
#     energy slightly; what the fix removes is the near-side boost.
#   - The first transposition option no longer claims "any material":
#     the compensating stretch is a Manipulation and depends on the
#     pitch analysis.
#   - FIX: the Info header still said v2.3.
#
# Changelog v2.4 (2026):
#   - FIX (critical): TRANSPOSITION DID NOT PRESERVE THE SUBJECT.
#     transposeByRatio did varispeed and then forced the result back to
#     the original duration, so with a 2 s subject:
#       answer     x1.498 -> 1.335 s of audio + 0.665 s of padded silence
#       answer^2   x2.245 -> 0.891 s of audio + 1.109 s of silence
#       subjectLow x0.500 -> 4.000 s produced, cut to 2.000: HALF the
#                            subject gone, including its ending
#       answerLow  x0.749 -> 75% kept
#     The dux, the comes and the low versions were therefore not the
#     same subject at different pitches, which is the one thing a fugue
#     requires. Transposition_method now offers varispeed followed by a
#     compensating time-stretch (works on any material) or a PitchTier
#     manipulation (best on monophonic or clearly voiced sources); both
#     keep the whole subject at the new pitch. The old behaviour is
#     kept as an explicit third option, since it is a distinct sound.
#   - FIX: the closing fade fell entirely on silence. The last musical
#     material - the pedal drone and the final subject entry - ends at
#     strettoEnd + 2*subDur, but the fade started at
#     totalDur - 0.5*subDur, which with the old totalDur was exactly
#     that same instant. So the cadence fade spent its whole length
#     fading nothing. The end of the music is computed explicitly now
#     and the fade sits on it.
#   - FIX: the reverb allowance was 0.5*subDur, which gave a 0.2 s
#     subject 0.1 s of tail and a 10 s subject 5 s - but a reverb time
#     has nothing to do with the length of a theme. It is an absolute
#     field now.
#   - FIX: makeDelay allocated only the source duration, so the last
#     delaySec of every delayed signal was discarded - a few ms for an
#     ITD, but a whole tap for the long reverb delays. The buffer is
#     extended, and makeStereo pads the two channels to a common length
#     rather than relying on Combine to stereo to sort it out.
#   - FIX: the spatial signature also changed each voice's LEVEL.
#     v2.3 multiplied the near channel by the ILD factor and left the
#     far one alone, so V1 and V2 at factor 4 came out 2.915x louder in
#     energy than V4 at factor 1 - the spatial identity doubled as a
#     counterpoint hierarchy. Constant power is now the default:
#     gNear/gFar still equals the factor, but the voice energy is
#     unchanged at every setting.
#   - FIX: the source time domain was not normalised to 0, while the
#     head-motif extraction, applyFades, trimTo and every timeline
#     assume it is.
#   - FIX: augmentation was hard-wired to a 50-800 Hz pitch range;
#     it is a form field now, and the transposition uses it too.
#   - WORDING, in the header and the report:
#       "fixed pitch identity" per voice is not what the score does -
#         V1 takes the doubly transposed head motif, V3 the augmented
#         subject. The SPATIAL identity is fixed; pitch follows the
#         section, as in the tradition.
#       "inverted" is polarity inversion on V3's right channel, not
#         melodic or contrapuntal inversion.
#       "hard LEFT"/"hard RIGHT" - both channels always carry every
#         voice; these are strongly biased signatures.
#       "diffuse field" - V4's wet signal is identical in both
#         channels, so it is correlated and centred.
#       "true polyphonic fugue" -> fugue-inspired construction.
#   - NEW: V3's mono compatibility is measured and reported rather than
#     left to be discovered.
#   - NEW: a score panel in the visualization - one row per voice, one
#     block per entry, labelled by material type, so the form can be
#     read at a glance. The spectrogram of the left channel alone did
#     not show which voice entered when.
# ============================================================

form Perceptual Fugue v2.5
    comment === Preset ===
    optionmenu Preset: 2
        option Custom
        option Classical Fugue (3 voices, fifth)
        option Spectral Fugue (4 voices, storm)
        option Chamber Fugue (3 voices, subtle)
        option Stretto Study (4 voices, tight)
    comment === Fugue Structure ===
    optionmenu Answer_interval: 1
        option Fifth up
        option Fourth up
        option Octave up
        option Tritone
    integer Number_of_voices 3
    real Stretto_compression 0.75
    boolean Include_retrograde 1
    boolean Include_augmentation 1
    comment === Transposition (see notes: v2.3 did not preserve the subject) ===
    optionmenu Transposition_method: 1
        option Varispeed + PSOLA compensation (keeps the subject; needs pitch)
        option PitchTier (monophonic/voiced material, keeps the whole subject)
        option Varispeed only (v2.3: truncates or pads to fit)
    positive Pitch_floor 50
    positive Pitch_ceiling 800
    comment === Spatial Parameters ===
    positive Exposition_ITD_ms 3.0
    positive Exposition_ILD_factor 4.0
    positive Shadow_cutoff_Hz 500
    optionmenu Ild_law: 1
        option Constant power (same ILD, no change in voice energy)
        option Boost near side (v2.3: raises the whole voice)
    positive Tail_allocation_seconds 1.5
    comment === Render speed (transpose resample precision) ===
    optionmenu Speed_mode: 2
        option Full Quality (precision 50)
        option Balanced (precision 20)
        option Fast (precision 10)
    comment === Output ===
    boolean Draw_visualization 1
endform

# ============================================================
# PRESETS & PARAMS
# ============================================================

if preset = 2
    presetName$ = "Classical Fugue"
    answer_interval = 1
    number_of_voices = 3
    stretto_compression = 0.75
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 3.0
    exposition_ILD_factor = 4.0
    shadow_cutoff_Hz = 500
elsif preset = 3
    presetName$ = "Spectral Fugue"
    answer_interval = 4
    number_of_voices = 4
    stretto_compression = 0.5
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 4.0
    exposition_ILD_factor = 5.0
    shadow_cutoff_Hz = 400
elsif preset = 4
    presetName$ = "Chamber Fugue"
    answer_interval = 1
    number_of_voices = 3
    stretto_compression = 0.85
    include_retrograde = 1
    include_augmentation = 0
    exposition_ITD_ms = 2.0
    exposition_ILD_factor = 2.5
    shadow_cutoff_Hz = 800
elsif preset = 5
    presetName$ = "Stretto Study"
    answer_interval = 1
    number_of_voices = 4
    stretto_compression = 0.4
    include_retrograde = 1
    include_augmentation = 1
    exposition_ITD_ms = 3.5
    exposition_ILD_factor = 4.5
    shadow_cutoff_Hz = 450
else
    presetName$ = "Custom"
endif

# Clamp
if number_of_voices < 3
    number_of_voices = 3
endif
if number_of_voices > 4
    number_of_voices = 4
endif
if stretto_compression < 0.2
    stretto_compression = 0.2
endif
if stretto_compression > 1.0
    stretto_compression = 1.0
endif

# Derived parameters
itdBase_s = exposition_ITD_ms / 1000
ildBase = exposition_ILD_factor
numV = number_of_voices
comp = stretto_compression

# v2.2: Resample precision tied to speed_mode.
# transposeByRatio is called several times for entries and head-
# motif transpositions. Lower precision is acceptable here —
# the script then crossfades, filters, and adds reverb to each
# voice, which masks small aliasing artifacts from the resample.
if speed_mode = 1
    resamplePrecision = 50
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    resamplePrecision = 20
    speedStr$ = "Balanced"
else
    resamplePrecision = 10
    speedStr$ = "Fast"
endif

if answer_interval = 1
    answerRatio = 2 ^ (7/12)
    intervalName$ = "fifth up"
elsif answer_interval = 2
    answerRatio = 2 ^ (5/12)
    intervalName$ = "fourth up"
elsif answer_interval = 3
    answerRatio = 2.0
    intervalName$ = "octave up"
else
    answerRatio = 2 ^ (6/12)
    intervalName$ = "tritone"
endif

# ============================================================
# INPUT CHECKS
# ============================================================
# v2.5: v2.4 checked only the channel count and a minimum duration.
if pitch_floor >= pitch_ceiling
    exitScript: "Pitch_floor (", pitch_floor, ") must be below Pitch_ceiling (",
        ... pitch_ceiling, ")."
endif

# Shadow cutoff against Nyquist - at 8 or 16 kHz a 500 Hz default is
# fine, but a user-raised value can sit at or above it.
selectObject: original
checkSr = Get sampling frequency
shadowCapped = 0
if shadow_cutoff_Hz > checkSr / 2 * 0.95
    shadow_cutoff_Hz = checkSr / 2 * 0.95
    shadowCapped = 1
endif

# An ILD factor below 1 swaps the declared identities: V1 becomes
# right-biased and V2 left-biased, which contradicts the whole score.
ildFlipped = 0
if exposition_ILD_factor < 1
    exposition_ILD_factor = 1 / exposition_ILD_factor
    ildFlipped = 1
endif

v1ratio = 1.0
v2ratio = answerRatio
v3ratio = 0.5
v4ratio = answerRatio * 0.5

# ============================================================
# SETUP
# ============================================================

selectObject: original
if nChannels = 2
    mono = Convert to mono
else
    mono = Copy: "mono_src"
endif

# v2.4: many stages assume the source starts at 0 - Extract part from
# 0 for the head motif, applyFades keyed on x, trimTo, and every
# timeline built from 0. A Sound extracted with preserved times does
# not, and the head motif and fades would land in the wrong place.
selectObject: mono
monoT0 = Get start time
if monoT0 <> 0
    selectObject: mono
    monoT1 = Get end time
    monoShift = Extract part: monoT0, monoT1, "rectangular", 1.0, "no"
    removeObject: mono
    mono = monoShift
endif
selectObject: mono
Rename: "mono_src"
monoDur = Get total duration

subDur = monoDur
monoSr = Get sampling frequency

expoEnd = 3 * subDur
episodeEnd = expoEnd + subDur
middleEnd = episodeEnd + 2 * subDur
strettoDur = (numV - 1) * comp * subDur + subDur
strettoEnd = middleEnd + strettoDur
# v2.4: the last musical material is the pedal drone (2*subDur) and the
# final subject entry, which starts at pedStart + subDur and therefore
# also ends at pedStart + 2*subDur. So the music stops there - not at
# strettoEnd + 2.5*subDur, which is where v2.3's fade began.
pedalDur = 2.5 * subDur
lastMusicalEnd = strettoEnd + 2 * subDur
# The reverb tail is an absolute time. Tying it to 0.5*subDur, as v2.3
# did, gave a 0.2 s subject only 0.1 s of tail and a 10 s subject 5 s -
# but a reverb time does not scale with the length of a theme.
# The longest internal decay: V4's reverb time is 0.8 s, the last tap
# sits at rt * 1.0, and makeEarlyRef reaches the same, plus the ITD.
# v2.4 let the field run shorter than that, which cut the tail off, and
# the field's name implied it set the reverb time when it only sets how
# much room the timeline leaves for it.
maxInternalTail = 0.8
if numV < 4
    maxInternalTail = 0.5
endif
maxInternalTail = maxInternalTail + itdBase_s + 0.05
tailDur = tail_allocation_seconds
tailClamped = 0
if tailDur < maxInternalTail
    tailDur = maxInternalTail
    tailClamped = 1
endif
totalDur = lastMusicalEnd + tailDur

# Values the report needs before the render runs.
fadeDurPreview = 0.5 * subDur
if fadeDurPreview > lastMusicalEnd * 0.5
    fadeDurPreview = lastMusicalEnd * 0.5
endif
fadeStartPreview = lastMusicalEnd - fadeDurPreview
spatialIldPreview = exposition_ILD_factor

clearinfo
writeInfoLine: "=================================================="
writeInfoLine: " PERCEPTUAL FUGUE v2.5"
writeInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Source: ", soundName$, " | ", fixed$(monoDur, 3), " s | ", monoSr, " Hz"
appendInfoLine: "Voices: ", numV, " | Answer: ", intervalName$, " (x", fixed$(answerRatio, 3), ")"
appendInfoLine: "Speed:  ", speedStr$, " (resample precision=", resamplePrecision, ")"
appendInfoLine: "Output duration: ", fixed$(totalDur, 2), " s"
appendInfoLine: "  music ends ", fixed$(lastMusicalEnd, 2), " s, then ",
    ... fixed$(tailDur, 2), " s of tail allocation"
appendInfoLine: "    This reserves timeline room for the tail; it does not SET the"
appendInfoLine: "    reverb time, which is fixed per voice (V1/V2 0.35 s, V3 0.5 s",
    ... ", V4 0.8 s)."
if tailClamped = 1
    appendInfoLine: "    Raised to ", fixed$(maxInternalTail, 2),
        ... " s, the longest internal decay plus the ITD,"
    appendInfoLine: "    so the tail is not cut off."
endif
appendInfoLine: "  cadence fade ", fixed$(fadeStartPreview, 2), " - ",
    ... fixed$(lastMusicalEnd, 2), " s (on the music, not after it)"
appendInfoLine: ""
if transposition_method = 1
    appendInfoLine: "Transposition: varispeed + PSOLA time compensation."
    appendInfoLine: "  The whole subject survives at the new pitch. The compensating"
    appendInfoLine: "  stretch is still a Manipulation, so it depends on the pitch"
    appendInfoLine: "  analysis - it is general-purpose, not material-independent, and"
    appendInfoLine: "  polyphonic, noisy or percussive sources will show artefacts."
    appendInfoLine: "  The analysis range is scaled by the transposition ratio, since"
    appendInfoLine: "  the varispeed has already moved the material."
elsif transposition_method = 2
    appendInfoLine: "Transposition: PitchTier manipulation."
    appendInfoLine: "  Duration is untouched by construction. Best on monophonic or"
    appendInfoLine: "  clearly voiced material, where the pitch track is reliable."
else
    appendInfoLine: "Transposition: VARISPEED ONLY (the v2.3 behaviour)."
    appendInfoLine: "  WARNING: this does not preserve the subject. At x",
        ... fixed$(answerRatio, 3), " the answer keeps"
    appendInfoLine: "  ", fixed$(100 / answerRatio, 0),
        ... "% of its length and the rest is padded silence; the octave-below"
    appendInfoLine: "  voices are cut to 50% and 75% and lose their endings."
endif
appendInfoLine: "  PSOLA pitch range ", fixed$(pitch_floor, 0), "-",
    ... fixed$(pitch_ceiling, 0), " Hz"
if shadowCapped = 1
    appendInfoLine: "  NOTE: shadow cutoff clamped to 0.95 x Nyquist."
endif
if ildFlipped = 1
    appendInfoLine: "  NOTE: the ILD factor was below 1, which would have made V1"
    appendInfoLine: "        right-biased and V2 left-biased - the opposite of the"
    appendInfoLine: "        declared identities. It was inverted to ",
        ... fixed$(exposition_ILD_factor, 2), "."
endif
if ild_law = 1
    appendInfoLine: "Spatial ILD: constant power on the DIRECT path - gNear/gFar is"
    appendInfoLine: "  still the factor, but the two direct gains no longer inflate the"
    appendInfoLine: "  voice. v2.3 boosted the near channel only, so V1/V2 at factor ",
        ... fixed$(spatialIldPreview, 1), " were 2.9x louder than V4."
    appendInfoLine: "  This is not a calibration of the whole chain: the far-side"
    appendInfoLine: "  lowpass, the shared wet signal, the reflections, the anchor and"
    appendInfoLine: "  V3's polarity inversion all still move the final voice energy a"
    appendInfoLine: "  little. It removes the near-side boost, which was the problem."
else
    appendInfoLine: "Spatial ILD: near-side boost (the v2.3 behaviour) - louder voices"
    appendInfoLine: "  get a wider signature, so the spatial identity also sets a"
    appendInfoLine: "  counterpoint hierarchy."
endif
appendInfoLine: ""
appendInfoLine: "Note on the descriptions: the SPATIAL identity of each voice is"
appendInfoLine: "fixed, but the pitch follows the section, as in the tradition."
appendInfoLine: "V3's right channel is POLARITY inverted - not a melodic inversion -"
appendInfoLine: "so V3 is deliberately poor in mono. V4's wet signal is identical in"
appendInfoLine: "both channels, so it is a centred correlated field, not a diffuse"
appendInfoLine: "one. No voice is hard-panned: both channels always carry every voice."
appendInfoLine: "The per-voice reverb amount is a SEND GAIN, not a wet percentage:"
appendInfoLine: "the three taps sum to 2.0 before filtering, so a send of 0.60 puts"
appendInfoLine: "the wet bus near 1.2x a single dry tap."  
appendInfoLine: ""

# ============================================================
# PROCEDURES (Optimized)
# ============================================================

procedure mixAdd: .a, .b
    selectObject: .a
    Formula: "self + object[" + string$(.b) + "]"
endproc

procedure makeDelay: .snd, .delaySec
    # v2.2: writes the delayed signal into a pre-allocated zero
    # buffer via Formula (part), which is much faster than
    # Concatenate + Extract on long buffers.
    # v2.4: the buffer is now .dur + .delaySec, so nothing is cut.
    selectObject: .snd
    .sr = Get sampling frequency
    .dur = Get total duration
    if .delaySec <= 0
        delayResult = Copy: "dly"
    else
        .nSamples = round(.delaySec * .sr)
        if .nSamples < 1
            .nSamples = 1
        endif
        .startSec = .nSamples / .sr
        .sndIdStr$ = string$(.snd)
        .offsetStr$ = string$(.nSamples)

        # v2.4: the buffer is .dur + .delaySec long, so the tail is no
        # longer cut. v2.3 allocated only .dur, which threw away the
        # last .delaySec of every delayed signal - a few ms for an ITD,
        # but a whole reverb tap for the long taps.
        delayResult = Create Sound from formula: "dly", 1, 0, .dur + .startSec, .sr, "0"
        selectObject: delayResult
        # Write the delayed signal: at timeline col c >= .nSamples + 1,
        # read source col (c - .nSamples). Reads outside the source
        # return 0, which is fine for the trailing silence.
        Formula (part): .startSec, .dur + .startSec, 1, 1,
            ... "object[" + .sndIdStr$ + ", 1, col - " + .offsetStr$ + "]"
    endif
endproc

procedure lowPassAsym: .snd, .cutHz
    selectObject: .snd
    filtResult = Filter (pass Hann band): 0, .cutHz, 100
endproc

procedure makeEarlyRef: .snd, .rvTime
    selectObject: .snd
    .sr = Get sampling frequency
    .dur = Get total duration
    .rt = .rvTime
    if .rt > 1.2
        .rt = 1.2
    endif
    if .rt < 0.05
        .rt = 0.05
    endif
    @makeDelay: .snd, .rt * 0.20
    .e1 = delayResult
    @makeDelay: .snd, .rt * 0.40
    .e2 = delayResult
    selectObject: .e2
    Formula: "self * 0.70"
    @mixAdd: .e1, .e2
    removeObject: .e2
    selectObject: .e1
    .eDur = Get total duration
    if .eDur >= .dur
        earlyResult = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .e1
    else
        .eext = .dur - .eDur
        .epad = Create Sound from formula: "pad", 1, 0, .eext, .sr, "0"
        selectObject: .e1
        plusObject: .epad
        earlyResult = Concatenate
        removeObject: .e1, .epad
    endif
    @makeDelay: .snd, .rt * 1.0
    .l1 = delayResult
    selectObject: .l1
    Formula: "self * 0.35"
    selectObject: .l1
    .lsmooth = Filter (pass Hann band): 0, 3500, 400
    removeObject: .l1
    selectObject: .lsmooth
    .lDur = Get total duration
    if .lDur >= .dur
        lateResult = Extract part: 0, .dur, "rectangular", 1, "no"
        removeObject: .lsmooth
    else
        .lext = .dur - .lDur
        .lpad = Create Sound from formula: "pad", 1, 0, .lext, .sr, "0"
        selectObject: .lsmooth
        plusObject: .lpad
        lateResult = Concatenate
        removeObject: .lsmooth, .lpad
    endif
endproc

procedure makeStereo: .left, .right
    # v2.4: makeDelay can now return a longer object than its sibling,
    # so the two channels are padded to a common length before they are
    # combined rather than relying on how Combine to stereo treats
    # unequal inputs.
    selectObject: .left
    .dl = Get total duration
    .sr = Get sampling frequency
    selectObject: .right
    .dr = Get total duration
    .dmax = .dl
    if .dr > .dmax
        .dmax = .dr
    endif
    .lUse = .left
    .rUse = .right
    .madeL = 0
    .madeR = 0
    if .dmax - .dl > 1 / .sr
        @trimTo: .left, .dmax
        .lUse = trimResult
        .madeL = 1
    endif
    if .dmax - .dr > 1 / .sr
        @trimTo: .right, .dmax
        .rUse = trimResult
        .madeR = 1
    endif
    selectObject: .lUse
    plusObject: .rUse
    stereoResult = Combine to stereo
    if .madeL = 1
        removeObject: .lUse
    endif
    if .madeR = 1
        removeObject: .rUse
    endif
endproc

procedure trimTo: .snd, .tDur
    selectObject: .snd
    .d = Get total duration
    .sr = Get sampling frequency
    if .d >= .tDur
        trimResult = Extract part: 0, .tDur, "rectangular", 1, "no"
    else
        .ext = .tDur - .d
        .pad = Create Sound from formula: "pad", 1, 0, .ext, .sr, "0"
        selectObject: .snd
        plusObject: .pad
        trimResult = Concatenate
        removeObject: .pad
    endif
endproc

procedure transposeByRatio: .snd, .ratio
    # v2.4: THE critical fix. v2.3 did varispeed and then forced the
    # result back to the original duration, which does not transpose a
    # subject - it mutilates it. Varispeed by r makes the content
    # D/r long, so with a 2 s subject:
    #   answer  (x1.498): 1.335 s of audio + 0.665 s of padded silence
    #   answer^2 (x2.245): 0.891 s of audio + 1.109 s of silence
    #   subjectLow (x0.5): 4.000 s produced, cut to 2.000 - HALF the
    #                      subject is gone, including its ending
    #   answerLow (x0.749): 75% kept
    # So the dux, the comes and the low versions were not the same
    # subject at different pitches at all.
    selectObject: .snd
    .intendedDur = Get total duration
    samplingFrequency = Get sampling frequency

    if transposition_method = 2
        # PitchTier: duration is untouched by construction. Best on
        # monophonic or clearly voiced material, where the pitch track
        # is reliable.
        selectObject: .snd
        .manip = To Manipulation: 0.01, pitch_floor, pitch_ceiling
        selectObject: .manip
        .pt = Extract pitch tier
        selectObject: .pt
        Multiply frequencies: 0, .intendedDur, .ratio
        selectObject: .manip
        plusObject: .pt
        Replace pitch tier
        selectObject: .manip
        .out = Get resynthesis (overlap-add)
        removeObject: .manip, .pt
        @trimTo: .out, .intendedDur
        removeObject: .out
        transposeResult = trimResult
    else
        # Varispeed first: pitch and speed move together, content
        # becomes D/ratio long.
        .tmp = Copy: "ps_tmp"
        selectObject: .tmp
        Override sampling frequency: round(samplingFrequency * .ratio)
        .shifted = Resample: samplingFrequency, resamplePrecision
        removeObject: .tmp

        if transposition_method = 1
            # ...then stretch by the same ratio to put the duration
            # back, so the WHOLE subject survives at the new pitch.
            # v2.5: the analysis happens AFTER the varispeed, so the
            # material now sits at r * its original pitch and the
            # original floor/ceiling no longer bracket it. An octave
            # down turns 70 Hz into 35 Hz, below a 50 Hz floor, and the
            # doubly transposed head motif turns 400 Hz into 898 Hz,
            # above an 800 Hz ceiling - in both cases the tracker loses
            # the material and the compensating stretch degrades.
            .pfShift = pitch_floor * .ratio
            .pcShift = pitch_ceiling * .ratio
            if .pfShift < 20
                .pfShift = 20
            endif
            .nyq = samplingFrequency / 2
            if .pcShift > .nyq * 0.45
                .pcShift = .nyq * 0.45
            endif
            if .pcShift <= .pfShift * 1.5
                .pcShift = .pfShift * 1.5
            endif
            selectObject: .shifted
            .sd = Get total duration
            .manip = To Manipulation: 0.01, .pfShift, .pcShift
            selectObject: .manip
            .dt = Extract duration tier
            selectObject: .dt
            Add point: .sd * 0.5, .ratio
            selectObject: .manip
            plusObject: .dt
            Replace duration tier
            selectObject: .manip
            .out = Get resynthesis (overlap-add)
            removeObject: .manip, .dt, .shifted
            @trimTo: .out, .intendedDur
            removeObject: .out
            transposeResult = trimResult
        else
            # v2.3 behaviour, kept only because it is a distinct sound.
            @trimTo: .shifted, .intendedDur
            removeObject: .shifted
            transposeResult = trimResult
        endif
    endif
endproc

procedure augmentByRatio: .snd, .durRatio
    selectObject: .snd
    .dur = Get total duration
    # v2.4: the pitch range is a form field now; 50-800 Hz suits some
    # voices and monophonic instruments but not every source.
    .manip = To Manipulation: 0.01, pitch_floor, pitch_ceiling
    selectObject: .manip
    .dt = Extract duration tier
    selectObject: .dt
    Add point: .dur * 0.5, .durRatio
    selectObject: .manip
    plusObject: .dt
    Replace duration tier
    selectObject: .manip
    augmentResult = Get resynthesis (overlap-add)
    removeObject: .manip, .dt
endproc

procedure reverseSound: .snd
    selectObject: .snd
    reverseResult = Copy: "rev"
    selectObject: reverseResult
    Reverse
endproc

procedure applyFades: .snd
    selectObject: .snd
    .dur = Get total duration
    .fadeDur = 0.005
    if .dur > 2 * .fadeDur
        .fdStr$ = string$(.fadeDur)
        .durStr$ = string$(.dur)
        Formula: "if x < " + .fdStr$ + " then self * (0.5 - 0.5 * cos(pi * x / " + .fdStr$ + ")) else if x > " + .durStr$ + " - " + .fdStr$ + " then self * (0.5 - 0.5 * cos(pi * (" + .durStr$ + " - x) / " + .fdStr$ + ")) else self fi fi"
    endif
endproc

procedure placeAt: .timeline, .fragment, .startSec
    # v2.2: mixes the fragment into the timeline IN-PLACE via
    # Formula (part). Old version extracted before/middle/after
    # slices, mixed into middle, and concatenated — rebuilding
    # the full timeline buffer on every call. With ~20 placeAt
    # calls per script run on multi-second buffers, this was the
    # dominant runtime cost.
    #
    # Behavior identical to v2.1: the fragment is added to the
    # timeline starting at .startSec, clipped at the timeline
    # end. Returns placeAt_result = .timeline (same ID; the
    # caller's "vt1 = placeAt_result" is now a no-op rebind that
    # keeps existing call sites working unchanged).
    selectObject: .timeline
    .tDur = Get total duration
    .tSr = Get sampling frequency

    selectObject: .fragment
    .fDur = Get total duration
    .fNs = Get number of samples

    .endSec = .startSec + .fDur
    if .endSec > .tDur
        .endSec = .tDur
    endif
    if .startSec < 0
        .startSec = 0
    endif

    if .endSec > .startSec
        # Sample-index offset such that timeline col (offset+1)
        # reads fragment col 1. With Formula (part) starting at
        # .startSec, the first written col is round(.startSec *
        # sr) + 1, and we want fragment col 1 there, so offset =
        # round(.startSec * sr).
        .offsetCol = round(.startSec * .tSr)
        .offsetStr$ = string$(.offsetCol)
        .fragIdStr$ = string$(.fragment)

        selectObject: .timeline
        Formula (part): .startSec, .endSec, 1, 1,
            ... "self + object[" + .fragIdStr$ + ", 1, col - "
            ... + .offsetStr$ + "]"
    endif

    placeAt_result = .timeline
endproc

procedure applySpatial: .monoSnd
    selectObject: .monoSnd
    .dur = Get total duration
    .left = Copy: "sp_left"
    selectObject: .monoSnd
    .right = Copy: "sp_right"

    # ITD
    if sp_itd > 0
        @makeDelay: .right, sp_itd
        .rightDel = delayResult
        removeObject: .right
        .right = .rightDel
    elsif sp_itd < 0
        .absItd = abs(sp_itd)
        @makeDelay: .left, .absItd
        .leftDel = delayResult
        removeObject: .left
        .left = .leftDel
    endif

    # ILD
    # v2.4: constant-power by default. v2.3 multiplied the near channel
    # by the ILD factor and left the far one alone, so the signature
    # also changed the VOICE's energy: V1 and V2 at factor 4 came out
    # 2.915x louder than V4 at factor 1. The spatial identity was
    # doubling as a counterpoint hierarchy nobody asked for.
    # Constant-power keeps gNear/gFar = factor while gNear^2 + gFar^2 = 1.
    .ildF = sp_ild
    if .ildF <= 0
        .ildF = 1
    endif
    if ild_law = 1
        .den = sqrt(1 + .ildF * .ildF)
        if .ildF >= 1
            .gNear = .ildF / .den
            .gFar = 1 / .den
            selectObject: .left
            Formula: "self * " + string$(.gNear * sqrt(2))
            selectObject: .right
            Formula: "self * " + string$(.gFar * sqrt(2))
        else
            .gNear = 1 / .den
            .gFar = .ildF / .den
            selectObject: .left
            Formula: "self * " + string$(.gFar * sqrt(2))
            selectObject: .right
            Formula: "self * " + string$(.gNear * sqrt(2))
        endif
    else
        if .ildF > 1
            selectObject: .left
            Formula: "self * " + string$(.ildF)
        elsif .ildF < 1
            .rightBoost = 1 / .ildF
            selectObject: .right
            Formula: "self * " + string$(.rightBoost)
        endif
    endif

    # Spectral shadow
    if sp_shSide = 1
        @lowPassAsym: .right, sp_shCut
        .rightFilt = filtResult
        removeObject: .right
        .right = .rightFilt
    elsif sp_shSide = -1
        @lowPassAsym: .left, sp_shCut
        .leftFilt = filtResult
        removeObject: .left
        .left = .leftFilt
    endif

    if sp_invRight = 1
        selectObject: .right
        Formula: "self * -1"
    endif

    # Reverb
    # v2.5: sp_rvWet is a SEND GAIN, not a wet percentage. The three
    # taps sum to 1 + 0.65 + 0.35 = 2.0 before filtering, so a value of
    # 0.60 puts the wet bus at roughly 1.2x the level of a single dry
    # tap, and the actual balance also depends on how the taps overlap,
    # how correlated they are and what the source is doing. The value
    # is left as it is - these settings were tuned by ear - but it is
    # named honestly and the effective figure is reported.
    if sp_rvWet > 0
        .rt = sp_rvTime
        if .rt > 1.2
            .rt = 1.2
        endif
        if .rt < 0.05
            .rt = 0.05
        endif
        @makeDelay: .monoSnd, .rt * 0.25
        .tap1 = delayResult
        @makeDelay: .monoSnd, .rt * 0.5
        .tap2 = delayResult
        selectObject: .tap2
        Formula: "self * 0.65"
        @makeDelay: .monoSnd, .rt * 1.0
        .tap3 = delayResult
        selectObject: .tap3
        Formula: "self * 0.35"
        @mixAdd: .tap1, .tap2
        @mixAdd: .tap1, .tap3
        removeObject: .tap2, .tap3
        selectObject: .tap1
        .wetSmooth = Filter (pass Hann band): 0, 5000, 300
        removeObject: .tap1
        @trimTo: .wetSmooth, .dur
        .wet = trimResult
        removeObject: .wetSmooth
        selectObject: .wet
        Formula: "self * " + string$(sp_rvWet)
        selectObject: .left
        Formula: "self * " + string$(1 - sp_rvWet)
        selectObject: .right
        Formula: "self * " + string$(1 - sp_rvWet)
        @mixAdd: .left, .wet
        @mixAdd: .right, .wet
        removeObject: .wet
    endif

    # Reflections
    if sp_refGain > 0
        @makeEarlyRef: .monoSnd, sp_rvTime
        .early = earlyResult
        .late = lateResult
        selectObject: .early
        Formula: "self * " + string$(sp_refGain)
        selectObject: .late
        Formula: "self * " + string$(sp_refGain * 0.6)
        @trimTo: .early, .dur
        .earlyT = trimResult
        removeObject: .early
        @trimTo: .late, .dur
        .lateT = trimResult
        removeObject: .late
        if sp_itd >= 0
            @mixAdd: .right, .earlyT
            @mixAdd: .left, .lateT
        else
            @mixAdd: .left, .earlyT
            @mixAdd: .right, .lateT
        endif
        removeObject: .earlyT, .lateT
    endif

    # Identity anchor 
    if sp_anchorGain > 0
        selectObject: .monoSnd
        .mid = Filter (pass Hann band): 500, 3000, 200
        selectObject: .mid
        Formula: "self * " + string$(sp_anchorGain)
        @trimTo: .mid, .dur
        .midTrimmed = trimResult
        removeObject: .mid
        @mixAdd: .left, .midTrimmed
        @mixAdd: .right, .midTrimmed
        removeObject: .midTrimmed
    endif

    @trimTo: .left, .dur
    .leftFinal = trimResult
    removeObject: .left
    @trimTo: .right, .dur
    .rightFinal = trimResult
    removeObject: .right
    @makeStereo: .leftFinal, .rightFinal
    spatialResult = stereoResult
    removeObject: .leftFinal, .rightFinal
endproc

# ============================================================
# CREATE SUBJECT MATERIALS (DRY)
# ============================================================

appendInfoLine: "Creating subject materials..."

selectObject: mono
subject = Copy: "subject"
@applyFades: subject

@transposeByRatio: subject, answerRatio
answer = transposeResult
@applyFades: answer

@transposeByRatio: subject, 0.5
subjectLow = transposeResult
@applyFades: subjectLow

if numV >= 4
    @transposeByRatio: subject, v4ratio
    answerLow = transposeResult
    @applyFades: answerLow
endif

if include_retrograde
    @reverseSound: subject
    counterSubject = reverseResult
    @applyFades: counterSubject
    selectObject: counterSubject
    retroSubject = Copy: "retro_sub"
else
    selectObject: subject
    counterSubject = Copy: "counter_sub"
    selectObject: counterSubject
    Formula: "self * (0.3 + 0.7 * (0.5 + 0.5 * sin(2 * pi * 2 * x)))"
    @applyFades: counterSubject
    selectObject: subject
    retroSubject = Copy: "retro_sub"
endif

selectObject: subject
headMotif = Extract part: 0, subDur * 0.5, "rectangular", 1, "no"
@applyFades: headMotif

if include_augmentation
    @augmentByRatio: subject, 2.0
    augSubject = augmentResult
    @applyFades: augSubject
else
    selectObject: subject
    augSubject = Copy: "aug_sub"
endif

if include_augmentation
    @augmentByRatio: subjectLow, 2.0
    pedalDrone = augmentResult
else
    selectObject: subjectLow
    pedalDrone = Copy: "pedal_drone"
endif
@applyFades: pedalDrone

@transposeByRatio: headMotif, answerRatio
headMotifT1 = transposeResult
@applyFades: headMotifT1

@transposeByRatio: headMotif, answerRatio * answerRatio
headMotifT2 = transposeResult
@applyFades: headMotifT2

# ============================================================
# BUILD VOICE TIMELINES
# ============================================================

appendInfoLine: "Building voice timelines..."
vt1 = Create Sound from formula: "vt1", 1, 0, totalDur, monoSr, "0"
vt2 = Create Sound from formula: "vt2", 1, 0, totalDur, monoSr, "0"
vt3 = Create Sound from formula: "vt3", 1, 0, totalDur, monoSr, "0"
if numV >= 4
    vt4 = Create Sound from formula: "vt4", 1, 0, totalDur, monoSr, "0"
endif

# ---- I. EXPOSITION ----
@placeAt: vt1, subject, 0
vt1 = placeAt_result
@placeAt: vt1, counterSubject, subDur
vt1 = placeAt_result

@lowPassAsym: subject, 800
.v1pad = filtResult
selectObject: .v1pad
Formula: "self * 0.4"
@applyFades: .v1pad
@placeAt: vt1, .v1pad, 2 * subDur
vt1 = placeAt_result
removeObject: .v1pad

@placeAt: vt2, answer, subDur
vt2 = placeAt_result
@placeAt: vt2, counterSubject, 2 * subDur
vt2 = placeAt_result

@placeAt: vt3, subjectLow, 2 * subDur
vt3 = placeAt_result

if numV >= 4
    @lowPassAsym: subject, 600
    .v4pad = filtResult
    selectObject: .v4pad
    Formula: "self * 0.3"
    @applyFades: .v4pad
    @placeAt: vt4, .v4pad, 2 * subDur
    vt4 = placeAt_result
    removeObject: .v4pad
endif

# ---- II. EPISODE ----
epStart = expoEnd
halfSub = subDur * 0.5

@placeAt: vt1, headMotif, epStart
vt1 = placeAt_result
@placeAt: vt2, headMotifT1, epStart + halfSub * 0.5
vt2 = placeAt_result
@placeAt: vt1, headMotifT2, epStart + halfSub
vt1 = placeAt_result
@placeAt: vt2, headMotif, epStart + halfSub * 1.5
vt2 = placeAt_result

@lowPassAsym: subjectLow, 500
.v3ep = filtResult
selectObject: .v3ep
Formula: "self * 0.3"
@applyFades: .v3ep
@placeAt: vt3, .v3ep, epStart
vt3 = placeAt_result
removeObject: .v3ep

# ---- III. MIDDLE ENTRIES ----
midStart = episodeEnd

@placeAt: vt1, retroSubject, midStart
vt1 = placeAt_result

@transposeByRatio: answer, answerRatio
.ansT2 = transposeResult
@applyFades: .ansT2
@placeAt: vt2, .ansT2, midStart + subDur
vt2 = placeAt_result
removeObject: .ansT2

@placeAt: vt3, augSubject, midStart
vt3 = placeAt_result

@placeAt: vt1, counterSubject, midStart + subDur
vt1 = placeAt_result

if numV >= 4
    @placeAt: vt4, answerLow, midStart + subDur
    vt4 = placeAt_result
endif

# ---- IV. STRETTO ----
strStart = middleEnd

@placeAt: vt1, subject, strStart
vt1 = placeAt_result
@placeAt: vt2, answer, strStart + comp * subDur
vt2 = placeAt_result
@placeAt: vt3, subjectLow, strStart + 2 * comp * subDur
vt3 = placeAt_result

if numV >= 4
    @placeAt: vt4, answerLow, strStart + 3 * comp * subDur
    vt4 = placeAt_result
endif

@placeAt: vt1, counterSubject, strStart + comp * subDur
vt1 = placeAt_result
@placeAt: vt2, counterSubject, strStart + 2 * comp * subDur
vt2 = placeAt_result

# ---- V. PEDAL + CADENCE ----
pedStart = strettoEnd

@placeAt: vt3, pedalDrone, pedStart
vt3 = placeAt_result

@lowPassAsym: answer, 600
.v2ped = filtResult
selectObject: .v2ped
Formula: "self * 0.35"
@applyFades: .v2ped
@placeAt: vt2, .v2ped, pedStart
vt2 = placeAt_result
removeObject: .v2ped

@placeAt: vt1, subject, pedStart + subDur
vt1 = placeAt_result

if numV >= 4
    @lowPassAsym: answerLow, 500
    .v4ped = filtResult
    selectObject: .v4ped
    Formula: "self * 0.25"
    @applyFades: .v4ped
    @placeAt: vt4, .v4ped, pedStart
    vt4 = placeAt_result
    removeObject: .v4ped
endif

# v2.4: the fade now lands ON the music. v2.3 set
# fadeStart = totalDur - 0.5*subDur, which with the old totalDur was
# exactly lastMusicalEnd - so the cadence fade began at the instant the
# dry material stopped and spent its whole length fading silence.
fadeDur = 0.5 * subDur
if fadeDur > lastMusicalEnd * 0.5
    fadeDur = lastMusicalEnd * 0.5
endif
fadeStart = lastMusicalEnd - fadeDur
fadeStartStr$ = string$(fadeStart)
fadeLenStr$ = string$(fadeDur)

# v2.5: a raised cosine, so the fade actually reaches zero. v2.4 used
# exp(-5q), which ends at e^-5 = 0.0067, i.e. -43.5 dB rather than
# silence. The reverb tail mostly covered it, but there is no reason
# for a cadence fade not to land on zero.
fadeFml$ = "if x > " + fadeStartStr$ + " then self * (0.5 * (1 + cos(pi * min(1, (x - "
    ... + fadeStartStr$ + ") / " + fadeLenStr$ + ")))) else self fi"
selectObject: vt1
Formula: fadeFml$
selectObject: vt2
Formula: fadeFml$
selectObject: vt3
Formula: fadeFml$
if numV >= 4
    selectObject: vt4
    Formula: fadeFml$
endif

voiceGain = 1 / numV
selectObject: vt1
Formula: "self * " + string$(voiceGain)
selectObject: vt2
Formula: "self * " + string$(voiceGain)
selectObject: vt3
Formula: "self * " + string$(voiceGain)
if numV >= 4
    selectObject: vt4
    Formula: "self * " + string$(voiceGain)
endif

appendInfoLine: "Applying spatial processing..."

# ============================================================
# SPATIAL PROCESSING
# ============================================================

sp_itd = itdBase_s
sp_ild = ildBase
sp_shSide = 1
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.35
sp_rvWet = 0.12
sp_refGain = 0.20
sp_anchorGain = 0.08
sp_invRight = 0

@applySpatial: vt1
stereoV1 = spatialResult

sp_itd = -itdBase_s
sp_ild = 1 / ildBase
sp_shSide = -1
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.35
sp_rvWet = 0.12
sp_refGain = 0.20
sp_anchorGain = 0.08
sp_invRight = 0

@applySpatial: vt2
stereoV2 = spatialResult

sp_itd = itdBase_s * 0.33
sp_ild = 1.3
sp_shSide = 0
sp_shCut = shadow_cutoff_Hz
sp_rvTime = 0.5
sp_rvWet = 0.35
sp_refGain = 0.15
sp_anchorGain = 0.10
sp_invRight = 1

@applySpatial: vt3
stereoV3 = spatialResult

if numV >= 4
    sp_itd = 0
    sp_ild = 1.0
    sp_shSide = 0
    sp_shCut = shadow_cutoff_Hz
    sp_rvTime = 0.8
    sp_rvWet = 0.60
    sp_refGain = 0.10
    sp_anchorGain = 0.12
    sp_invRight = 0

    @applySpatial: vt4
    stereoV4 = spatialResult
endif

removeObject: vt1, vt2, vt3
if numV >= 4
    removeObject: vt4
endif

# ============================================================
# MIX VOICES
# ============================================================

selectObject: stereoV1
v1L = Extract one channel: 1
selectObject: stereoV1
v1R = Extract one channel: 2
removeObject: stereoV1

selectObject: stereoV2
v2L = Extract one channel: 1
selectObject: stereoV2
v2R = Extract one channel: 2
removeObject: stereoV2

selectObject: stereoV3
v3L = Extract one channel: 1
selectObject: stereoV3
v3R = Extract one channel: 2
removeObject: stereoV3

@mixAdd: v1L, v2L
@mixAdd: v1L, v3L
@mixAdd: v1R, v2R
@mixAdd: v1R, v3R
removeObject: v2L, v2R, v3L, v3R

if numV >= 4
    selectObject: stereoV4
    v4L = Extract one channel: 1
    selectObject: stereoV4
    v4R = Extract one channel: 2
    removeObject: stereoV4

    @mixAdd: v1L, v4L
    @mixAdd: v1R, v4R
    removeObject: v4L, v4R
endif

@makeStereo: v1L, v1R
fugue = stereoResult
removeObject: v1L, v1R

selectObject: fugue
Rename: soundName$ + "_perceptual_fugue"

# v2.2: Removed conflicting "Scale intensity: section_intensity_dB"
# that preceded "Scale peak: 0.99". The peak normalization
# would always overwrite the intensity setting, making the
# section_intensity_dB form parameter cosmetic. Now keeps only
# Scale peak — predictable, no clipping.
Scale peak: 0.99

fugueName$ = selected$("Sound")
fugueDur = Get total duration
fugueId = selected("Sound")

# ============================================================
# MONO COMPATIBILITY
# ============================================================
# v2.4: V3's right channel is polarity inverted, so folding to mono can
# cancel it. That is deliberate, but it should be measured and reported
# rather than discovered on someone's phone.
selectObject: fugueId
mcL = Extract one channel: 1
selectObject: fugueId
mcR = Extract one channel: 2
selectObject: mcL
mcEnergyL = Get energy: 0, 0
selectObject: mcR
mcEnergyR = Get energy: 0, 0
selectObject: mcL
mcSum = Copy: "mc_sum"
selectObject: mcR
Rename: "mc_right"
selectObject: mcSum
Formula: "(self + Sound_mc_right[1, col]) / 2"
mcEnergySum = Get energy: 0, 0
mcRef = (mcEnergyL + mcEnergyR) / 4
if mcRef < 1e-30
    mcRef = 1e-30
endif
mcRatio = mcEnergySum / mcRef
mcDb = 10 * log10(max(mcRatio, 1e-12))
# v2.5: also report a proper correlation coefficient. The ratio above
# compares the mono fold with what an uncorrelated pair would give, so
# it runs 0..200% rather than being a percentage of energy retained -
# which is what v2.4 called it.
#   E(L+R)/2 = (EL + ER + 2C)/4, so rho = 2C/(EL+ER) = mcRatio - 1
mcRho = mcRatio - 1
if mcRho > 1
    mcRho = 1
endif
if mcRho < -1
    mcRho = -1
endif
removeObject: mcL, mcR, mcSum
selectObject: fugueId

removeObject: subject, answer, subjectLow, counterSubject
removeObject: headMotif, augSubject, retroSubject, pedalDrone
removeObject: headMotifT1, headMotifT2, mono
if numV >= 4
    removeObject: answerLow
endif

appendInfoLine: ""
appendInfoLine: "Mono compatibility:"
appendInfoLine: "  mono-fold energy, against an UNCORRELATED L/R reference: ",
    ... fixed$(mcRatio * 100, 1), "% (", fixed$(mcDb, 2), " dB)"
appendInfoLine: "  Read it against these anchors, not as 'energy retained':"
appendInfoLine: "    200% = the two channels are identical and in phase"
appendInfoLine: "    100% = uncorrelated"
appendInfoLine: "      0% = anti-phase, complete cancellation"
appendInfoLine: "  Correlation coefficient: ", fixed$(mcRho, 3),
    ... "   (+1 in phase, 0 uncorrelated, -1 anti-phase)"
if mcRatio < 0.6
    appendInfoLine: "  Substantial cancellation, as expected: V3's right channel is"
    appendInfoLine: "  polarity inverted by design. This mix is NOT mono-compatible."
elsif mcRatio < 0.95
    appendInfoLine: "  Some cancellation from V3's polarity inversion. Check a mono"
    appendInfoLine: "  fold before distributing."
else
    appendInfoLine: "  Little cancellation on this material."
endif

# ============================================================
# VISUALIZATION & OUTPUT
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    selectObject: fugue
    Extract one channel: 1
    vizLeft = selected("Sound")
    selectObject: fugue
    Extract one channel: 2
    vizRight = selected("Sound")
    # To Spectrogram is mono-only; fugue is stereo, so analyze the
    # already-extracted left channel to avoid a crash.
    selectObject: vizLeft
    vizSpec = To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"

    selectObject: vizLeft
    lMax = Get maximum: 0, 0, "Sinc70"
    lMin = Get minimum: 0, 0, "Sinc70"
    if lMax < 0
        lMax = -lMax
    endif
    if lMin < 0
        lMin = -lMin
    endif
    if lMin > lMax
        lMax = lMin
    endif

    selectObject: vizRight
    rMax = Get maximum: 0, 0, "Sinc70"
    rMin = Get minimum: 0, 0, "Sinc70"
    if rMax < 0
        rMax = -rMax
    endif
    if rMin < 0
        rMin = -rMin
    endif
    if rMin > rMax
        rMax = rMin
    endif

    if lMax > rMax
        ampMax = lMax * 1.1
    else
        ampMax = rMax * 1.1
    endif
    if ampMax < 0.001
        ampMax = 0.001
    endif

    sb1 = expoEnd
    sb2 = episodeEnd
    sb3 = middleEnd
    sb4 = strettoEnd

    Erase all
    Select outer viewport: 0, 8, 0, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Perceptual Fugue v2.5##"
    Select outer viewport: 0, 8, 0.28, 0.5
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", presetName$ + " | " + soundName$ + " | " + string$(numV) + " voices | " + intervalName$ + " | " + fixed$(fugueDur, 1) + " s"

    # ------------------------------------------------------------
    # SCORE PANEL
    # ------------------------------------------------------------
    # v2.4: one row per voice, one block per entry, coloured and
    # labelled by material. A spectrogram of the left channel alone did
    # not show which voice entered when, which is the one thing this
    # engine is actually doing.
    Select outer viewport: 0, 8, 0.55, 2.30
    Select inner viewport: 0.8, 7.6, 0.62, 2.22

    Axes: 0, fugueDur, 0.4, numV + 0.6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, 0.4, numV + 0.6

    # Section boundaries and names
    Colour: "{0.86, 0.86, 0.88}"
    Line width: 1
    Draw line: sb1, 0.4, sb1, numV + 0.6
    Draw line: sb2, 0.4, sb2, numV + 0.6
    Draw line: sb3, 0.4, sb3, numV + 0.6
    Draw line: sb4, 0.4, sb4, numV + 0.6
    Font size: 5
    Colour: "{0.50, 0.50, 0.55}"
    Text: sb1 / 2, "centre", numV + 0.5, "half", "Exposition"
    Text: (sb1 + sb2) / 2, "centre", numV + 0.5, "half", "Episode"
    Text: (sb2 + sb3) / 2, "centre", numV + 0.5, "half", "Middle entries"
    Text: (sb3 + sb4) / 2, "centre", numV + 0.5, "half", "Stretto"
    Text: (sb4 + lastMusicalEnd) / 2, "centre", numV + 0.5, "half", "Pedal"

    # Cadence fade and reverb tail
    Colour: "{0.93, 0.90, 0.86}"
    Paint rectangle: "{0.95, 0.92, 0.88}", fadeStart, lastMusicalEnd, 0.4, numV + 0.42
    Colour: "{0.90, 0.90, 0.94}"
    Paint rectangle: "{0.94, 0.94, 0.97}", lastMusicalEnd, fugueDur, 0.4, numV + 0.42

    # Entry blocks: {voice, start, length, kind}
    # kind 1 subject, 2 answer, 3 retrograde, 4 augmented,
    #      5 fragment, 6 pedal
    # Built inline: a Praat procedure cannot be declared inside an if
    # block, and this whole panel lives inside one.
    nEntry = 0
    nEntry += 1
    entV[nEntry] = 1
    entT[nEntry] = 0
    entL[nEntry] = subDur
    entK[nEntry] = 1
    nEntry += 1
    entV[nEntry] = 2
    entT[nEntry] = subDur
    entL[nEntry] = subDur
    entK[nEntry] = 2
    nEntry += 1
    entV[nEntry] = 3
    entT[nEntry] = 2 * subDur
    entL[nEntry] = subDur
    entK[nEntry] = 1
    if numV >= 4
        nEntry += 1
        entV[nEntry] = 4
        entT[nEntry] = 2.5 * subDur
        entL[nEntry] = subDur
        entK[nEntry] = 2
    endif
    nEntry += 1
    entV[nEntry] = 1
    entT[nEntry] = expoEnd
    entL[nEntry] = subDur * 0.5
    entK[nEntry] = 5
    nEntry += 1
    entV[nEntry] = 2
    entT[nEntry] = expoEnd + subDur * 0.25
    entL[nEntry] = subDur * 0.5
    entK[nEntry] = 5
    nEntry += 1
    entV[nEntry] = 3
    entT[nEntry] = expoEnd + subDur * 0.5
    entL[nEntry] = subDur * 0.5
    entK[nEntry] = 5
    nEntry += 1
    entV[nEntry] = 1
    entT[nEntry] = episodeEnd
    entL[nEntry] = subDur
    entK[nEntry] = 3
    nEntry += 1
    entV[nEntry] = 2
    entT[nEntry] = episodeEnd + subDur * 0.5
    entL[nEntry] = subDur
    entK[nEntry] = 2
    nEntry += 1
    entV[nEntry] = 3
    entT[nEntry] = episodeEnd
    entL[nEntry] = 2 * subDur
    entK[nEntry] = 4
    for k from 1 to numV
        nEntry += 1
        entV[nEntry] = k
        entT[nEntry] = middleEnd + (k - 1) * comp * subDur
        entL[nEntry] = subDur
        entK[nEntry] = 1
    endfor
    nEntry += 1
    entV[nEntry] = 2
    entT[nEntry] = strettoEnd
    entL[nEntry] = 2 * subDur
    entK[nEntry] = 6
    nEntry += 1
    entV[nEntry] = 1
    entT[nEntry] = strettoEnd + subDur
    entL[nEntry] = subDur
    entK[nEntry] = 1
    if numV >= 4
        nEntry += 1
        entV[nEntry] = 4
        entT[nEntry] = strettoEnd
        entL[nEntry] = 2 * subDur
        entK[nEntry] = 6
    endif

    for ent from 1 to nEntry
        vv = entV[ent]
        if vv <= numV
            yy = numV + 1 - vv
            kk = entK[ent]
            if kk = 1
                kCol$ = "{0.28, 0.48, 0.80}"
                kLab$ = "S"
            elsif kk = 2
                kCol$ = "{0.82, 0.45, 0.22}"
                kLab$ = "A"
            elsif kk = 3
                kCol$ = "{0.55, 0.30, 0.70}"
                kLab$ = "R"
            elsif kk = 4
                kCol$ = "{0.20, 0.60, 0.45}"
                kLab$ = "Aug"
            elsif kk = 5
                kCol$ = "{0.75, 0.68, 0.20}"
                kLab$ = "frag"
            else
                kCol$ = "{0.45, 0.45, 0.50}"
                kLab$ = "Ped"
            endif
            Paint rectangle: kCol$, entT[ent], entT[ent] + entL[ent], yy - 0.26, yy + 0.26
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: entT[ent], entT[ent] + entL[ent], yy - 0.26, yy + 0.26
            Font size: 5
            Colour: "White"
            if entL[ent] > fugueDur * 0.035
                Text: entT[ent] + entL[ent] / 2, "centre", yy, "half", kLab$
            endif
        endif
    endfor

    Font size: 5
    Colour: "{0.30, 0.30, 0.35}"
    for vv from 1 to numV
        yy = numV + 1 - vv
        if vv = 1
            vLab$ = "V1 dux L"
        elsif vv = 2
            vLab$ = "V2 comes R"
        elsif vv = 3
            vLab$ = "V3 8vb pol."
        else
            vLab$ = "V4 rev."
        endif
        Text: -fugueDur * 0.012, "right", yy, "half", vLab$
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text bottom: "yes", "Score: S subject, A answer, R retrograde, Aug augmented, frag fragment, Ped pedal"

    Select outer viewport: 0, 8, 2.36, 3.20
    Select inner viewport: 0.8, 7.6, 2.42, 3.14
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizLeft
    Colour: "{0.2, 0.45, 0.82}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Left"

    Select outer viewport: 0, 8, 3.26, 4.10
    Select inner viewport: 0.8, 7.6, 3.32, 4.04
    Axes: 0, fugueDur, -ampMax, ampMax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, fugueDur, -ampMax, ampMax
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, -ampMax, sb1, ampMax
    Draw line: sb2, -ampMax, sb2, ampMax
    Draw line: sb3, -ampMax, sb3, ampMax
    Draw line: sb4, -ampMax, sb4, ampMax
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, 0, fugueDur, 0
    selectObject: vizRight
    Colour: "{0.82, 0.3, 0.2}"
    Draw: 0, 0, -ampMax, ampMax, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Right"

    Select outer viewport: 0, 8, 4.16, 5.35
    Select inner viewport: 0.8, 7.6, 4.22, 5.28
    Axes: 0, fugueDur, 0, 5000
    selectObject: vizSpec
    Paint: 0, 0, 0, 0, 100, "yes", 50, 6, 0, "yes"
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: sb1, 0, sb1, 5000
    Draw line: sb2, 0, sb2, 5000
    Draw line: sb3, 0, sb3, 5000
    Draw line: sb4, 0, sb4, 5000
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"

    Font size: 8
    Colour: "Black"
    Text: sb1 / 2, "centre", 5500, "half", "EXPOSITION"
    Text: sb1 + (sb2 - sb1) / 2, "centre", 5500, "half", "EPISODE"
    Text: sb2 + (sb3 - sb2) / 2, "centre", 5500, "half", "MIDDLE ENTRIES"
    Text: sb3 + (sb4 - sb3) / 2, "centre", 5500, "half", "STRETTO"
    Text: sb4 + (fugueDur - sb4) / 2, "centre", 5500, "half", "PEDAL"

    removeObject: vizLeft, vizRight, vizSpec
endif

selectObject: fugue
Play

appendInfoLine: ""
appendInfoLine: "=================================================="
appendInfoLine: "  DONE"
appendInfoLine: "=================================================="
appendInfoLine: ""
appendInfoLine: "Output:   ", fugueName$
appendInfoLine: "Duration: ", fixed$(fugueDur, 2), " s (~", fixed$(fugueDur / subDur, 1), "x input)"
appendInfoLine: ""
appendInfoLine: "FUGUE SCORE:"
appendInfoLine: "  Voices:"
appendInfoLine: "    V1 Dux   : pitch x1.0, LEFT  (ITD +", fixed$(exposition_ITD_ms, 1), "ms)"
appendInfoLine: "    V2 Comes : pitch x", fixed$(answerRatio, 3), " (", intervalName$, "), RIGHT"
appendInfoLine: "    V3 Third : pitch x0.5 (8vb), center + polarity inv"
if numV >= 4
    appendInfoLine: "    V4 Fourth: pitch x", fixed$(v4ratio, 3), ", diffuse field"
endif
appendInfoLine: ""
appendInfoLine: "  Structure:"
appendInfoLine: "    I.   EXPOSITION     S -> A -> S(low)  [overlapping]"
appendInfoLine: "    II.  EPISODE        head motif x3 transpositions"
appendInfoLine: "    III. MIDDLE ENTRIES retrograde + answer^2 + augmented"
appendInfoLine: "    IV.  STRETTO        ", numV, " entries at ", fixed$(comp * 100, 0), "% compression"
appendInfoLine: "    V.   PEDAL          augmented drone cadence"
appendInfoLine: "=================================================="
