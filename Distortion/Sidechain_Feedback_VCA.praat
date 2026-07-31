# ============================================================
# Praat AudioTools - Sidechain_Feedback_VCA.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4b (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Sidechain Feedback VCA - an ITERATIVE, sidechain-controlled resonant
#   texture generator. The controller's mean pitch sets a resonance
#   centre and its intensity envelope drives the loop gain (VCA); the
#   Dry/Wet control blends the controller back in, and a synthetic
#   high-frequency exciter adds air.
#
#   WHAT THIS IS AND IS NOT (v0.4 correction):
#   v0.3 described this as simulating "a no-input mixer where feedback
#   creates self-oscillation". That is not what the code does, and the
#   difference matters if you are writing about the tool:
#
#   - There is no time-domain feedback. The loop has no delay, no read
#     of a previous sample, no self[row, col-1] and no state advancing
#     along the time axis. Each iteration filters the WHOLE buffer,
#     mixes it with the previous whole buffer, applies arctan, and
#     repeats. `Iterations` is a computational axis outside audio time,
#     not laps of a signal around a physical circuit. The accurate
#     description is buffer-domain feedback resynthesis, or an iterative
#     sidechain-controlled resonant texture generator.
#   - Nothing self-oscillates from nothing. The loop is explicitly
#     seeded with low-level noise and the output is then normalized, so
#     a completely silent controller still yields a full-level ring.
#     That is a legitimate no-input-mixer AESTHETIC, but technically it
#     is planted noise amplified, not a system crossing a threshold and
#     breaking into oscillation.
#   - The resonance centre is the MEAN pitch of the whole file. Pitch
#     movement in the controller - glissando, vibrato - does not reach
#     the circuit.
#   - The intensity envelope is mapped RELATIVE to the loudest moment in
#     the selected file, so it tracks dynamics WITHIN a file but not
#     absolute level BETWEEN files: four otherwise identical controllers
#     at amplitudes 0.001, 0.01, 0.1 and 0.9 gave outputs correlating
#     above 0.99999 with one another. "Louder input files drive more
#     feedback" is not accurate; "louder MOMENTS within the file drive
#     more feedback" is.
#   - Analog_Instability drifts the band BETWEEN iterations, not over
#     time, so it produces spectral spread across the iteration axis
#     rather than analog wander during playback. "Slow Evolution" does
#     not move the resonance slowly along the time axis.
#
# Changelog v0.2:
#   - Fixed form placement (before analysis)
#   - Fixed name-based references (use object IDs)
#   - Fixed formula syntax
#   - Added visualization
#   - Improved cleanup
#
# Changelog v0.4b:
#   All three blockers below are v0.4 regressions.
#   - FIXED: the new dB mapping is relative to the file's loudest
#     moment, so on a file that is silent THROUGHOUT, that loudest
#     moment is the silence itself (about -299.6 dB) and the window
#     mapped it to 1 - silence drove the loop at maximum gain (VCA 1.3
#     with the defaults), the opposite of the intent. An absolute
#     silence threshold at -150 dB now holds the envelope at 0.
#   - FIXED: the "Use the first two channels" policy crashed. It called
#     `Extract all channels` twice and then removed objects by index
#     from a shrinking selection, so the loop asked for Sound #3 after
#     it had gone ("No Sound #3 selected"). Only the two wanted
#     channels are extracted now, and both temporaries are removed.
#   - FIXED: the visualization block was lost when the exciter was
#     restructured in v0.4. Draw_visualization stayed in the form but
#     nothing read it, so Yes and No behaved identically. Restored.
#   - The description now states that the intensity mapping is relative
#     to each file's own peak - four identical controllers at
#     amplitudes 0.001 to 0.9 produced outputs correlating above
#     0.99999, so absolute level between files still does not drive the
#     circuit.
#   - "True bypass" is qualified: Dry_Wet 1 is sample-exact only with
#     Exciter_position 2, Output_mode Preserve, and an unchanged channel
#     layout. Under either normalizing mode a source peaking at 0.123
#     still comes back at 0.95.
#   - The seed band is clamped to Nyquist rather than only warned about,
#     and the effective edges are reported.
#   - The multichannel policy is named in the report, and a negative
#     High_Freq_Add is reported as behaving like off.
#
# Changelog v0.3:
#   - FIX: the feedback core seeded L and R from two independent noise calls,
#     so the channels resonated at the same pitch with random phase = decorrelated
#     noise (and cancelled when summed to mono). Now one shared seed feeds both
#     channels; stereo width is created by the spatial stage instead.
#   - ROBUSTNESS: VCA control is made stereo and the feedback formula indexes
#     object[id, row, col] explicitly, so the right channel can never read an
#     undefined mono value (NaN -> blow-up) on some Praat versions.
#   - Removed the redundant per-iteration Copy (filter the loop directly).
#   - Added Debug mode: per-stage levels, sample-count check, per-iteration loop
#     peak with an undefined / out-of-bound guard, and final per-channel peaks.
#   - FIX: Binaural right channel was silent (in-place delay read its own zeros);
#     now reads the 30-sample delay from an unmodified copy.
#   - HIGHS: High_Freq_Add adds a synthetic treble 'air' band by ring-
#     modulating the output with a high harmonic of the resonance, then
#     high-passing and blending it in (the pure feedback is dark/narrow).
#   - DOC: description updated for the Dry/Wet behaviour (the original input
#     can now be blended into the output).
#   - VIZ: title and parameter line were centred against a stale wide world
#     window so they spilled off the left edge; now pinned to a 0..1 axis.
#   - BALANCE: Stereo Wide high-passed the right channel at 200 Hz, silencing
#     low resonances on the right; both channels now overlap across the
#     resonance so L and R stay balanced.
#   - DRY/WET: Dry_Wet mixes the original controller back into the output
#     (0 = pure feedback / no-input-mixer, default 0.3). The pure feedback is a
#     self-generated resonance with no direct sound, which is what makes it
#     hollow / tunnel-like; blending dry restores body. Reduce feedback /
#     iterations and widen Bandwidth_Hz for an even less resonant character.
#   - CLEAN RING: the seed is band-limited to the resonance region so the loop
#     carries only in-band energy. The final Scale peak then amplifies a clean
#     pitched ring instead of a broadband noise floor (matters most at low
#     iteration counts, where a broadband seed has not yet been filtered out).
# ============================================================

form Sidechain Feedback VCA v0.4b
    comment Select a Sound object - it CONTROLS the feedback circuit
    comment (use Dry/Wet below to blend the original sound back in)
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Gentle Resonance
        option Aggressive Feedback
        option Slow Evolution
        option Chaotic Burst
    
    comment === Circuit Behavior ===
    positive Base_Feedback 0.8
    real Input_Sensitivity 0.5
    comment (envelope adds this much on top of Base_Feedback)
    positive Envelope_range_dB 40
    comment (dB below the loudest moment that maps to 0)
    boolean Allow_negative_VCA 0
    positive Damping_Factor 0.92
    natural Iterations 40

    comment === Resonance ===
    real Frequency_Offset_Hz 0.0
    positive Bandwidth_Hz 150
    positive Analog_Instability 0.05

    comment === Dry / Wet (0 = pure feedback, 1 = dry path only) ===
    comment (exact bypass at 1 needs Exciter_position 2 + Output_mode Preserve)
    real Dry_Wet 0.3
    optionmenu Exciter_position: 1
        option After the dry/wet mix (v0.2/v0.3)
        option On the wet path only

    comment === Synthetic high frequencies / air (0 = off) ===
    real High_Freq_Add 0.3
    comment (negative behaves as off; the exciter runs only when this is > 0)

    comment === Spatial Mode ===
    optionmenu Spatial_Mode 2
        option Mono
        option Stereo Wide
        option Rotating
        option Binaural
    positive Interaural_delay_ms 0.68
    comment (Binaural mode; v0.3 used a fixed 30 samples)
    optionmenu Multichannel_policy: 1
        option Downmix to mono, then duplicate
        option Use the first two channels
        option Refuse more than 2 channels

    comment === Output ===
    optionmenu Output_mode: 1
        option Normalize each stage to 0.95 (v0.2/v0.3)
        option Normalize only at the end
        option Preserve loop level (output gain only)
    positive Output_Gain 1.0
    integer Random_seed 0
    comment (0 or below = unpredictable; positive = reproducible)
    boolean Draw_visualization 1
    boolean Play_result 1
    comment === Debug (logs per-stage levels to the Info window) ===
    boolean Debug 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object to act as the controller."
endif

original = selected("Sound")
input_Name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
n_channels = Get number of channels
xminOrig = Get start time
xmaxOrig = Get end time
srcPeak = Get absolute extremum: 0, 0, "None"
nyquist = sr / 2

# v0.4 (item 15): the loop draws randomGauss for the seed and again for the
# drift on every iteration, with no seed - three identical runs gave RMS
# differences of 0.36-0.48 and correlations between -0.12 and 0.28.
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably: random_seed
    seedDesc$ = string$(random_seed) + " (reproducible)"
else
    random_initializeSafelyAndUnpredictably()
    seedDesc$ = "none (this run is NOT reproducible)"
endif

# v0.4 (item 10): Dry_Wet is a `real` with no check. A negative value behaved
# exactly like 0 because the mix is guarded by `dry_Wet > 0`, and a value
# above 1 extrapolated - 1.5 computes -0.5*feedback + 1.5*dry, and the report
# printed "-50% feedback / 150% original".
if dry_Wet < 0 or dry_Wet > 1
    exitScript: "Dry_Wet must be between 0 and 1 (got " + fixed$(dry_Wet, 3) + ")."
endif

# v0.4 (item 6): v0.3 ran To Pitch and To Intensity with no length check, so
# short Sounds aborted the script and left intermediate objects behind.
# Measured: anything under about 65 ms failed - below 50 ms with a Pitch
# error, 50-60 ms with "Sound shorter than window length". To Intensity at a
# 100 Hz minimum pitch needs 6.4/100 = 64 ms of signal, and To Pitch at a
# 75 Hz floor needs about 3/75 = 40 ms. Rather than abort, the script now
# falls back to fixed control values and says so.
minPitchDur = 3 / 75
minIntensityDur = 6.4 / 100
shortFile = 0
if duration < minIntensityDur or duration < minPitchDur
    shortFile = 1
endif

# v0.4 (item 7): the feedback core is always mono or stereo, so with more
# than two input channels the dry blend used to call `Convert to stereo` on
# the original and Praat stopped with "The Sound has 4 channels; don't know
# which to choose." - which failed every spatial mode except Mono, and only
# when Dry_Wet > 0. Now an explicit policy.
if n_channels > 2 and multichannel_policy = 3
    exitScript: "The controller has " + string$(n_channels)
        ... + " channels. Choose a different Multichannel_policy, or reduce the input to mono or stereo."
endif

# === Synthetic high frequencies (harmonic air) ===
# Ring-modulates by a high harmonic of the resonance, then high-passes and
# blends the result back in. Operates on whichever Sound is passed in.
#
# v0.4 (item 13): v0.3 clamped the carrier to 16 kHz and always filtered
# 2000-20000 Hz, with no reference to the sample rate. At 8 kHz the Nyquist
# frequency is 4 kHz, so a 4.4 kHz carrier folded down to 3.6 kHz while the
# report still announced "around 4400 Hz", and the 20 kHz filter edge was
# meaningless. Everything is derived from Nyquist now.
procedure exciter: .target
    .carrier = resonance_Center * 20
    if .carrier < 3000
        .carrier = 3000
    endif
    .carrierMax = nyquist * 0.45
    if .carrier > .carrierMax
        .carrier = .carrierMax
    endif
    .hpLow = 2000
    if .hpLow > nyquist * 0.5
        .hpLow = nyquist * 0.5
    endif
    .hpHigh = nyquist

    selectObject: .target
    Copy: "exciter_raw"
    .raw = selected("Sound")
    .carr$ = string$(.carrier)
    Formula: "self * sin(2 * pi * " + .carr$ + " * x)"
    Filter (pass Hann band): .hpLow, .hpHigh, 100
    .high = selected("Sound")
    removeObject: .raw

    selectObject: .target
    .exc$ = string$(.high)
    .amt$ = string$(high_Freq_Add * 1.2)
    Formula: "self + object[" + .exc$ + ", row, col] * " + .amt$
    removeObject: .high
    exciterDesc$ = "carrier " + fixed$(.carrier, 0) + " Hz, band " + fixed$(.hpLow, 0) + "-" + fixed$(.hpHigh, 0) + " Hz"
endproc

# === Debug helper: report level/shape of the currently selected Sound ===
procedure dbg: .lbl$
    if debug
        .pk = Get absolute extremum: 0, 0, "None"
        .ns = Get number of samples
        .nc = Get number of channels
        if .pk = undefined
            appendInfoLine: "  [DBG] ", .lbl$, ": *** UNDEFINED / NaN *** (samples=", .ns, ", channels=", .nc, ")"
        else
            appendInfoLine: "  [DBG] ", .lbl$, ": peak=", fixed$(.pk, 4), "  samples=", .ns, "  channels=", .nc
            if .pk > 1.5
                appendInfoLine: "  [DBG]   ^^^ peak exceeds expected bound (>1.5) ^^^"
            endif
        endif
    endif
endproc

# === Apply Presets ===
if preset = 2
    # Gentle Resonance
    base_Feedback = 0.6
    input_Sensitivity = 0.3
    damping_Factor = 0.95
    iterations = 30
    bandwidth_Hz = 200
    analog_Instability = 0.03
    presetName$ = "Gentle"
elsif preset = 3
    # Aggressive Feedback
    base_Feedback = 0.9
    input_Sensitivity = 0.7
    damping_Factor = 0.88
    iterations = 50
    bandwidth_Hz = 100
    analog_Instability = 0.08
    presetName$ = "Aggressive"
elsif preset = 4
    # Slow Evolution
    base_Feedback = 0.75
    input_Sensitivity = 0.4
    damping_Factor = 0.96
    iterations = 60
    bandwidth_Hz = 250
    analog_Instability = 0.02
    presetName$ = "SlowEvolve"
elsif preset = 5
    # Chaotic Burst
    base_Feedback = 0.95
    input_Sensitivity = 0.9
    damping_Factor = 0.85
    iterations = 40
    bandwidth_Hz = 80
    analog_Instability = 0.15
    presetName$ = "Chaotic"
else
    presetName$ = "Custom"
endif

# === Info ===
writeInfoLine: "=== Sidechain Feedback VCA v0.4b ==="
appendInfoLine: "Controller: ", input_Name$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# ============================================================
# FEATURE EXTRACTION (The "Knobs")
# ============================================================

appendInfoLine: "Extracting control features..."

# A. Extract Pitch (Controls Resonance Center)
#
# v0.4 (item 4): this takes the MEAN pitch over the whole file and uses it as
# one global resonance centre. Glissando, vibrato and any pitch movement in the
# controller do not reach the circuit - only the average does. That is a
# reasonable design, but it is not pitch following, and the description said
# "the input's pitch controls the resonant frequency" as though it tracked.
if shortFile
    mean_Pitch = 100
    appendInfoLine: "  Controller is ", fixed$(duration * 1000, 1), " ms - too short for pitch analysis (needs ~", fixed$(minPitchDur * 1000, 0), " ms). Using 100 Hz."
else
    selectObject: original
    if n_channels > 1
        Convert to mono
        tempMono = selected("Sound")
        To Pitch: 0.0, 75, 600
        pitch = selected("Pitch")
        removeObject: tempMono
    else
        To Pitch: 0.0, 75, 600
        pitch = selected("Pitch")
    endif

    selectObject: pitch
    mean_Pitch = Get mean: 0, 0, "Hertz"

    if mean_Pitch = undefined
        mean_Pitch = 100
        appendInfoLine: "  No pitch detected. Defaulting resonance to 100 Hz."
    else
        appendInfoLine: "  Mean pitch over the whole file: ", fixed$(mean_Pitch, 1), " Hz (one global resonance centre; not tracked over time)"
    endif

    removeObject: pitch
endif

# B. Extract Intensity (Controls Feedback Gain)
#
# v0.4 CRITICAL (item 1): v0.3 took the Intensity object's values - which are
# DECIBELS, a logarithmic quantity with an arbitrary offset - converted them to
# a Sound and called `Scale peak: 1.0` on them. Peak-normalizing dB is not a
# normalization of level, and the consequences were severe. Silence reads as
# about -300 dB while a loud passage reads about +71 dB, so the largest
# MAGNITUDE in the file is the silence, and Scale peak divided everything by
# it: silence mapped to about -1 and every real signal level was crushed into
# a narrow band near zero. Measured on a file containing silence, a 0.001 sine
# and a 0.1 sine, the resulting VCA values were 0.36 / 0.85 / 0.90 - a
# hundredfold change in input amplitude moved the VCA by 0.05, while the
# SILENCE set the scale for the whole file. With a fixed random seed,
# continuous signals at 0.001, 0.01, 0.1 and 0.9 produced nearly identical
# output. The form's "higher = louder input drives more chaos" was not true.
#
# The dB values are now mapped to 0..1 across a window ending at the file's
# loudest moment and reaching Envelope_range_dB below it. Silence lands at 0,
# the loudest moment at 1, and the mapping is monotonic in level throughout.
if shortFile
    appendInfoLine: "  Controller is too short for intensity analysis (needs ~", fixed$(minIntensityDur * 1000, 0), " ms). Using a constant VCA at Base_Feedback."
    Create Sound from formula: "vca_flat", 1, xminOrig, xmaxOrig, sr, "0"
    vcaControl = selected("Sound")
    envDesc$ = "constant (file too short to analyse)"
else
    selectObject: original
    To Intensity: 100, 0, "yes"
    intensity = selected("Intensity")

    Down to Matrix
    matrix = selected("Matrix")

    To Sound
    controlRaw = selected("Sound")

    Resample: sr, 50
    vcaControl = selected("Sound")
    removeObject: intensity, matrix, controlRaw

    selectObject: vcaControl
    maxDb = Get maximum: 0, 0, "None"

    # v0.4b: the mapping is RELATIVE to the loudest moment in the file, so on
    # a file that is silent throughout, that loudest moment is the silence
    # itself - about -299.6 dB - and the window [max-40, max] mapped it to 1.
    # Silence therefore drove the loop at MAXIMUM gain (VCA 1.3 with the
    # defaults), the exact opposite of the intent. An absolute silence
    # threshold is needed as well as the relative window.
    silenceFloorDb = -150
    if maxDb < silenceFloorDb
        Formula: ~ 0
        envDesc$ = "controller is silent (peak intensity " + fixed$(maxDb, 1) + " dB) - envelope held at 0, VCA = Base_Feedback"
        appendInfoLine: "  Intensity envelope: ", envDesc$
    else
        floorDb = maxDb - envelope_range_dB
        spanDb = maxDb - floorDb
        if spanDb < 1
            spanDb = 1
        endif
        floor$ = string$(floorDb)
        span$ = string$(spanDb)
        Formula: "(self - " + floor$ + ") / " + span$
        Formula: ~ if self < 0 then 0 else (if self > 1 then 1 else self fi) fi
        envDesc$ = "dB mapped over " + fixed$(floorDb, 1) + " to " + fixed$(maxDb, 1) + " dB -> 0..1 (RELATIVE to this file's loudest moment)"
        appendInfoLine: "  Intensity envelope: ", envDesc$
    endif
endif

appendInfoLine: ""

# ============================================================
# PREPARE CONTROL SIGNAL
# ============================================================

selectObject: vcaControl
@dbg: "vcaControl envelope (0..1)"

# Apply sensitivity curve: base + (envelope * sensitivity)
base_str$ = string$(base_Feedback)
sens_str$ = string$(input_Sensitivity)
Formula: "" + base_str$ + " + (self * " + sens_str$ + ")"

# v0.4 (item 2): v0.3 clamped only the TOP at 1.8. With the old dB
# normalization silence could map to -1, so Base_Feedback 0.1 with
# Input_Sensitivity 2 produced a VCA of about -1.9 - not a VCA gain at all but
# a polarity inversion of the feedback branch. The envelope is now 0..1 so a
# negative product needs a negative Input_Sensitivity, but the floor is
# explicit rather than assumed. Allow_negative_VCA keeps it available as
# bipolar modulation for those who want it.
if allow_negative_VCA
    Formula: ~ if self > 1.8 then 1.8 else self fi
    vcaClampDesc$ = "upper 1.8 only (bipolar modulation allowed)"
else
    Formula: ~ if self > 1.8 then 1.8 else (if self < 0 then 0 else self fi) fi
    vcaClampDesc$ = "clamped to 0..1.8 (unipolar VCA)"
endif

# Make the control stereo so the per-channel feedback formula can read
# object[vca, row, col] for BOTH channels (a mono read from the right channel
# returns undefined in some Praat versions -> NaN -> blow-up).
selectObject: vcaControl
Convert to stereo
vcaMono = vcaControl
vcaControl = selected("Sound")
removeObject: vcaMono
if debug
    selectObject: vcaControl
    vcaPk = Get absolute extremum: 0, 0, "None"
    vcaNc = Get number of channels
    appendInfoLine: "  [DBG] vcaControl after sens+clip: peak=", fixed$(vcaPk, 4), "  channels=", vcaNc
endif

# ============================================================
# INITIALIZE CIRCUIT
# ============================================================

appendInfoLine: "Initializing feedback loop..."

# Create ONE coherent noise seed and copy it to both channels, so the feedback
# core stays phase-coherent (independent L/R seeds produced decorrelated noise).
# v0.4 (item 8): v0.3 created the seed over 0..duration, so the output always
# started at 0 no matter where the controller sat on the time axis - a Sound
# spanning 2.5..2.7 s came back as 0..0.2 s, and that happened even at
# Dry_Wet = 1 where the output is only the source. Created over the source's
# own domain instead.
Create Sound from formula: "temp_noise", 1, xminOrig, xmaxOrig, sr, "randomGauss(0, 0.0001)"
noiseSeed = selected("Sound")

selectObject: noiseSeed
Copy: "temp_noise_L"
noiseL = selected("Sound")

selectObject: noiseSeed
Copy: "temp_noise_R"
noiseR = selected("Sound")

selectObject: noiseL, noiseR
Combine to stereo
stereoLoop = selected("Sound")

removeObject: noiseSeed, noiseL, noiseR

selectObject: stereoLoop
@dbg: "stereoLoop noise seed"

# Set center frequency
resonance_Center = mean_Pitch + frequency_Offset_Hz

# v0.4 (item 9): Frequency_Offset_Hz is a `real` and nothing checked the
# resulting centre against anything. Measured: a centre of -280 Hz, of about
# 0 Hz, of 30220 Hz at 44.1 kHz and of 100220 Hz all produced a SILENT output
# with no error and no warning - the user simply got nothing back.
if resonance_Center <= 20
    exitScript: "The resonance centre works out to " + fixed$(resonance_Center, 1)
        ... + " Hz (mean pitch " + fixed$(mean_Pitch, 1) + " + offset " + fixed$(frequency_Offset_Hz, 1)
        ... + "). It must be above 20 Hz - below that the band filter passes nothing and the output is silent."
endif
if resonance_Center >= nyquist
    exitScript: "The resonance centre works out to " + fixed$(resonance_Center, 1)
        ... + " Hz, at or above the Nyquist frequency (" + fixed$(nyquist, 1)
        ... + " Hz). The band filter would pass nothing and the output would be silent."
endif
if resonance_Center + bandwidth_Hz >= nyquist
    appendInfoLine: "  NOTE: the resonance band reaches ", fixed$(resonance_Center + bandwidth_Hz, 1),
        ... " Hz, past Nyquist (", fixed$(nyquist, 1), " Hz) - the upper part of the band is unavailable."
endif

appendInfoLine: "Resonance center: ", fixed$(resonance_Center, 1), " Hz"
appendInfoLine: ""

# Band-limit the seed to the resonance region. The loop retains its own state
# through self*damping, so a broadband seed leaves a broadband noise floor that
# the final Scale peak amplifies. Filtering the seed once keeps the whole loop
# in-band -> a clean pitched ring instead of amplified noise (no gain change).
seedLow = resonance_Center - bandwidth_Hz
seedHigh = resonance_Center + bandwidth_Hz
if seedLow < 20
    seedLow = 20
endif
# v0.4b: v0.4 warned when the band reached past Nyquist but did not clamp the
# seed filter, so the band silently became asymmetric about the centre. Now
# clamped, and the effective edges are reported.
if seedHigh > nyquist
    seedHigh = nyquist
endif
appendInfoLine: "Seed band (effective): ", fixed$(seedLow, 1), " - ", fixed$(seedHigh, 1), " Hz"
selectObject: stereoLoop
Filter (pass Hann band): seedLow, seedHigh, 20
seedBandLimited = selected("Sound")
removeObject: stereoLoop
stereoLoop = seedBandLimited
selectObject: stereoLoop
@dbg: "stereoLoop seed (band-limited to clean the floor)"

# ============================================================
# THE FEEDBACK LOOP
# ============================================================

appendInfoLine: "Running ", iterations, " iterations..."

damp_str$ = string$(damping_Factor)
vca_str$ = string$(vcaControl)

if debug
    selectObject: vcaControl
    nVca = Get number of samples
    selectObject: stereoLoop
    nLoop = Get number of samples
    appendInfoLine: "  [DBG] sample counts: vcaControl=", nVca, "  stereoLoop=", nLoop, "  match=", (nVca = nLoop)
endif

for i from 1 to iterations
    # Progress indicator
    if i mod 10 = 0
        appendInfoLine: "  Iteration ", i, "/", iterations
    endif
    
    # Dynamic drift (analog instability)
    drift_hz = resonance_Center * analog_Instability
    current_freq = resonance_Center + randomGauss(0, drift_hz)
    width_drift = bandwidth_Hz * analog_Instability
    current_width = bandwidth_Hz + randomGauss(0, width_drift)
    
    # Safety clamps
    # v0.4 (item 9): v0.3 clamped the drift only from below, so with a high
    # centre and a large Analog_Instability an iteration could place the band
    # past Nyquist and silently contribute nothing.
    if current_freq < 50
        current_freq = 50
    endif
    if current_freq > nyquist - 50
        current_freq = nyquist - 50
    endif
    if current_width < 10
        current_width = 10
    endif
    
    # Filter stage
    lowEdge = current_freq - (current_width / 2)
    highEdge = current_freq + (current_width / 2)
    if lowEdge < 20
        lowEdge = 20
    endif
    if highEdge > nyquist
        highEdge = nyquist
    endif
    
    selectObject: stereoLoop
    Filter (pass Hann band): lowEdge, highEdge, 20
    filteredSignal = selected("Sound")
    
    # Mixing stage (VCA) with soft clipping
    # Formula: arctan((loop * damping) + (filtered * vca_control))
    selectObject: stereoLoop
    filtered_str$ = string$(filteredSignal)
    
    Formula: "2/pi * arctan((self * " + damp_str$ + ") + (object[" + filtered_str$ + ", row, col] * object[" + vca_str$ + ", row, col]))"
    
    if debug
        selectObject: stereoLoop
        loopPk = Get absolute extremum: 0, 0, "None"
        if loopPk = undefined
            appendInfoLine: "  [DBG] iter ", i, ": *** stereoLoop UNDEFINED ***  band=[", fixed$(lowEdge, 1), ", ", fixed$(highEdge, 1), "]  <- explosion source"
        elsif loopPk > 1.5 or i <= 2 or i mod 10 = 0 or i = iterations
            appendInfoLine: "  [DBG] iter ", i, ": loop peak=", fixed$(loopPk, 5), "  band=[", fixed$(lowEdge, 1), ", ", fixed$(highEdge, 1), "]"
            if loopPk > 1.5
                appendInfoLine: "  [DBG]   ^^^ exceeds bound at iter ", i, " <- explosion source ^^^"
            endif
        endif
    endif
    
    # Cleanup iteration
    removeObject: filteredSignal
endfor

appendInfoLine: ""

# ============================================================
# SPATIAL POST-PROCESSING
# ============================================================

appendInfoLine: "Applying spatial mode: ", spatial_Mode$, "..."

selectObject: stereoLoop

# Ensure stereo
nChLoop = Get number of channels
if nChLoop = 1
    Convert to stereo
    newStereo = selected("Sound")
    removeObject: stereoLoop
    stereoLoop = newStereo
endif

if spatial_Mode$ = "Mono"
    selectObject: stereoLoop
    Convert to mono
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    removeObject: stereoLoop
    
else
    selectObject: stereoLoop
    Extract all channels
    chL = selected("Sound", 1)
    chR = selected("Sound", 2)
    
    if spatial_Mode$ = "Stereo Wide"
        # Widen by giving L the lows and R the highs, but keep an overlap across
        # the resonance so both channels carry the fundamental and stay balanced.
        wideLowTop = resonance_Center * 4
        if wideLowTop < 2000
            wideLowTop = 2000
        endif
        wideHighBot = resonance_Center * 0.5
        if wideHighBot < 20
            wideHighBot = 20
        endif
        selectObject: chL
        Filter (pass Hann band): 20, wideLowTop, 100
        chL_filtered = selected("Sound")
        
        # v0.4 (item 13): 20000 Hz is above Nyquist at any rate below 40 kHz.
        wideHighTop = 20000
        if wideHighTop > nyquist
            wideHighTop = nyquist
        endif
        selectObject: chR
        Filter (pass Hann band): wideHighBot, wideHighTop, 100
        chR_filtered = selected("Sound")
        
    elsif spatial_Mode$ = "Rotating"
        rotation_rate = 0.2
        rot_str$ = string$(rotation_rate)
        
        selectObject: chL
        Copy: "temp_chL_rot"
        chL_filtered = selected("Sound")
        Formula: "self * (0.6 + cos(2*pi*" + rot_str$ + "*x) * 0.4)"
        
        selectObject: chR
        Copy: "temp_chR_rot"
        chR_filtered = selected("Sound")
        Formula: "self * (0.6 + sin(2*pi*" + rot_str$ + "*x) * 0.4)"
        
    elsif spatial_Mode$ = "Binaural"
        # v0.4 (item 13): clamp the binaural bands to Nyquist as well.
        binLTop = 3000
        if binLTop > nyquist
            binLTop = nyquist
        endif
        binRTop = 6000
        if binRTop > nyquist
            binRTop = nyquist
        endif
        selectObject: chL
        Filter (pass Hann band): 50, binLTop, 80
        chL_filtered = selected("Sound")
        
        selectObject: chR
        Copy: "temp_chR_src"
        chR_src = selected("Sound")
        # v0.4 (item 14): v0.3 delayed a fixed 30 SAMPLES, so the same setting
        # gave 3.75 ms at 8 kHz, 0.68 ms at 44.1 kHz and 0.31 ms at 96 kHz -
        # a different spatial impression for every file. Specified in
        # milliseconds and converted here. (Also note this is an interaural
        # delay with band filtering, i.e. a Haas-style effect, not HRTF-based
        # binaural rendering.)
        delaySamples = round(interaural_delay_ms / 1000 * sr)
        if delaySamples < 1
            delaySamples = 1
        endif
        ds$ = string$(delaySamples)
        selectObject: chR
        Formula: "if col > " + ds$ + " then object[chR_src, col - " + ds$ + "] else 0 fi"
        removeObject: chR_src
        Filter (pass Hann band): 200, binRTop, 80
        chR_filtered = selected("Sound")
    endif
    
    selectObject: chL_filtered, chR_filtered
    Combine to stereo
    result = selected("Sound")
    Rename: input_Name$ + "_feedback_" + presetName$
    
    # Cleanup
    removeObject: chL_filtered, chR_filtered, chL, chR, stereoLoop
endif

# Cleanup VCA control
removeObject: vcaControl

# v0.4 (item 12): v0.3 ran `Scale peak: 0.95` four separate times - on the
# wet, on the dry, after the mix, and after the exciter - so almost any
# non-silent result finished at exactly 0.95. Iteration count, feedback
# strength and Dry/Wet all stopped affecting the OUTPUT LEVEL, and a barely
# resonating circuit sounded as loud as a screaming one. Output_mode makes
# this a choice; mode 1 is the v0.3 behaviour.
selectObject: result
@dbg: "result (wet) before scale"
wetPeakRaw = Get absolute extremum: 0, 0, "None"

if output_mode = 1
    if wetPeakRaw > 1e-9
        Scale peak: 0.95
    endif
endif

# Exciter on the wet path, if requested (so Dry_Wet = 1 stays a true bypass)
if high_Freq_Add > 0 and exciter_position = 2
    @exciter: result
    appendInfoLine: "Added synthetic highs to the wet path (", exciterDesc$, ")"
endif

# === Dry / Wet Mix ===
# The feedback signal alone is self-generated resonance with no original sound.
# Blending the dry controller back in restores the direct sound.
#
# v0.4 (item 11): "1 = original sound" was not accurate. The dry path is
# itself peak-normalized to 0.95 and the result normalized again, so a source
# peaking at 0.2 came back scaled by about 4.75 - the waveform preserved, the
# level not. And the exciter ran AFTER the mix, so even at Dry_Wet = 1 with
# High_Freq_Add on the output was spectrally altered (at 5 it was dominated by
# the exciter). Exciter_position 2 puts the exciter on the wet path so
# Dry_Wet = 1 is a genuine bypass, and the form now says "dry path only".
if dry_Wet > 0
    selectObject: result
    nChResult = Get number of channels

    selectObject: original
    Copy: "dry_signal"
    drySig = selected("Sound")
    nChDry = Get number of channels

    # v0.4 (item 7): `Convert to stereo` on a 4-channel Sound stops Praat with
    # "The Sound has 4 channels; don't know which to choose." - which broke
    # every spatial mode except Mono whenever Dry_Wet > 0. Now an explicit
    # policy: downmix to mono first (then duplicate), or take the first two.
    if nChDry <> nChResult
        selectObject: drySig
        if nChResult = 1
            Convert to mono
            dryConv = selected("Sound")
        elsif nChDry > 2 and multichannel_policy = 2
            # v0.4b: v0.4 called `Extract all channels` TWICE and then removed
            # objects by index from a selection that was shrinking as it went,
            # so the loop asked for Sound #3 after it had gone:
            # "No Sound #3 selected. Formula not run." Only the two channels
            # that are actually wanted are extracted now, and both temporaries
            # are removed explicitly.
            selectObject: drySig
            Extract one channel: 1
            dryC1 = selected("Sound")
            selectObject: drySig
            Extract one channel: 2
            dryC2 = selected("Sound")
            selectObject: dryC1, dryC2
            Combine to stereo
            dryConv = selected("Sound")
            removeObject: dryC1, dryC2
        elsif nChDry > 2
            selectObject: drySig
            Convert to mono
            dryMonoTmp = selected("Sound")
            Convert to stereo
            dryConv = selected("Sound")
            removeObject: dryMonoTmp
        else
            Convert to stereo
            dryConv = selected("Sound")
        endif
        removeObject: drySig
        drySig = dryConv
    endif

    if output_mode = 1
        selectObject: drySig
        dryPk = Get absolute extremum: 0, 0, "None"
        if dryPk > 1e-9
            Scale peak: 0.95
        endif
    endif

    selectObject: result
    dry_str$ = string$(drySig)
    wetGain$ = string$(1 - dry_Wet)
    dryGain$ = string$(dry_Wet)
    Formula: "self * " + wetGain$ + " + object[" + dry_str$ + ", row, col] * " + dryGain$
    removeObject: drySig

    if output_mode = 1
        selectObject: result
        mixPk = Get absolute extremum: 0, 0, "None"
        if mixPk > 1e-9
            Scale peak: 0.95
        endif
    endif
    appendInfoLine: "Mixed dry/wet: ", fixed$((1-dry_Wet)*100, 0), "% feedback / ", fixed$(dry_Wet*100, 0), "% dry path"
endif

# Exciter after the mix (v0.2/v0.3 position)
if high_Freq_Add > 0 and exciter_position = 1
    @exciter: result
    appendInfoLine: "Added synthetic highs after the mix (", exciterDesc$, ")"
    if dry_Wet >= 1
        appendInfoLine: "  NOTE: Dry_Wet is 1 but the exciter runs after the mix, so the output is still altered. Use Exciter_position 2 for a true bypass."
    endif
    if output_mode = 1
        selectObject: result
        excPk = Get absolute extremum: 0, 0, "None"
        if excPk > 1e-9
            Scale peak: 0.95
        endif
    endif
endif

# === Final output stage ===
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"

if output_mode = 2
    if prePeak > 1e-9
        Scale peak: 0.95
        outDesc$ = "normalized once at the end"
    else
        outDesc$ = "silent - normalization skipped"
    endif
elsif output_mode = 3
    outDesc$ = "loop level preserved"
else
    outDesc$ = "normalized at each stage (v0.3)"
endif

if output_Gain <> 1.0
    selectObject: result
    og$ = string$(output_Gain)
    Formula: "self * " + og$
endif

selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"
finalCh = Get number of channels
finalStart = Get start time
finalEnd = Get end time

# === Parameter report ===
# v0.4 (item 16): with Debug off, v0.3 reported almost nothing - not the
# circuit parameters, not the sample rate, not the seed, not the time domain,
# not the final peak. None of it was recoverable from the output.
appendInfoLine: ""
appendInfoLine: "=== Parameters ==="
appendInfoLine: "Sample rate: ", fixed$(sr, 0), " Hz (Nyquist ", fixed$(nyquist, 1), " Hz)"
appendInfoLine: "Base feedback: ", fixed$(base_Feedback, 3), "  |  Input sensitivity: ", fixed$(input_Sensitivity, 3)
appendInfoLine: "VCA envelope: ", envDesc$
appendInfoLine: "VCA range: ", vcaClampDesc$
appendInfoLine: "Damping: ", fixed$(damping_Factor, 3), "  |  Iterations: ", iterations
appendInfoLine: "Resonance: ", fixed$(resonance_Center, 1), " Hz  |  Bandwidth: ", fixed$(bandwidth_Hz, 1), " Hz"
appendInfoLine: "Analog instability: ", fixed$(analog_Instability, 3), " (drift BETWEEN iterations, not over time)"
appendInfoLine: "Dry/Wet: ", fixed$(dry_Wet, 3), "  |  High freq add: ", fixed$(high_Freq_Add, 3)
appendInfoLine: "Spatial mode: ", spatial_Mode$
if spatial_Mode$ = "Binaural"
    appendInfoLine: "  Interaural delay: ", fixed$(interaural_delay_ms, 3), " ms (", round(interaural_delay_ms / 1000 * sr), " samples at this rate)"
endif
if n_channels > 2
    if multichannel_policy = 2
        mcDesc$ = "use the first two channels"
    elsif multichannel_policy = 3
        mcDesc$ = "refuse more than 2 channels"
    else
        mcDesc$ = "downmix to mono, then duplicate"
    endif
    appendInfoLine: "Multichannel policy: input had ", n_channels, " channels -> ", mcDesc$
endif
if high_Freq_Add < 0
    appendInfoLine: "  NOTE: High_Freq_Add is negative, which behaves exactly as 0 (the exciter is skipped)."
endif
appendInfoLine: "Random seed: ", seedDesc$
appendInfoLine: "Output mode: ", outDesc$, "  |  Output gain: ", fixed$(output_Gain, 3)
appendInfoLine: "Source peak: ", fixed$(srcPeak, 4), "  |  Wet peak before scaling: ", fixed$(wetPeakRaw, 4)
appendInfoLine: "Output: ", fixed$(finalEnd - finalStart, 3), " s, ", finalCh, " ch, ", fixed$(finalStart, 3), "-", fixed$(finalEnd, 3), " s, peak ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif

# ============================================================
# VISUALIZATION
# ============================================================
# v0.4b: this block was lost in v0.4 when the exciter was restructured -
# Draw_visualization remained in the form but nothing read it, so Yes and No
# behaved identically. Restored from v0.3 unchanged, other than the parameter
# line now naming the envelope mapping and the seed.
if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Sidechain Feedback VCA: " + input_Name$ + " (" + presetName$ + ")"
    
    # Controller input waveform
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Controller"
    
    # Output waveform
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    selectObject: result
    Colour: "{0.6, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Feedback Out"
    Text bottom: "yes", "Time (s)"
    
    # Signal flow diagram
    Select outer viewport: 0, 8, 2.7, 4.2
    Select inner viewport: 0.6, 7.6, 2.8, 4.1
    
    Axes: 0, 10, 0, 4
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 10, 0, 4
    
    Font size: 5
    
    # Input analysis
    Paint rectangle: "{0.7, 0.7, 0.7}", 0.2, 1.5, 2.8, 3.6
    Colour: "Black"
    Text: 0.85, "centre", 3.2, "half", "Input"
    
    Draw arrow: 1.5, 3.2, 2.2, 3.5
    Draw arrow: 1.5, 3.2, 2.2, 2.9
    
    # Pitch extraction
    Paint rectangle: "{0.7, 0.8, 0.7}", 2.2, 3.2, 3.2, 3.8
    Text: 2.7, "centre", 3.5, "half", "Pitch"
    Text: 2.7, "centre", 3.1, "half", fixed$(mean_Pitch, 0) + "Hz"
    
    # Intensity extraction
    Paint rectangle: "{0.8, 0.7, 0.7}", 2.2, 3.2, 2.6, 3.1
    Text: 2.7, "centre", 2.85, "half", "Intensity"
    
    # Feedback loop box
    Paint rectangle: "{0.8, 0.8, 0.9}", 4, 8.5, 1.2, 3.8
    Colour: "{0.5, 0.5, 0.6}"
    Text: 6.25, "centre", 3.6, "half", "FEEDBACK LOOP"
    
    # Loop components
    Colour: "Black"
    Paint rectangle: "{0.6, 0.7, 0.6}", 4.3, 5.3, 2.2, 2.8
    Text: 4.8, "centre", 2.5, "half", "Filter"
    
    Draw arrow: 5.3, 2.5, 5.6, 2.5
    
    Paint rectangle: "{0.7, 0.6, 0.6}", 5.6, 6.6, 2.2, 2.8
    Text: 6.1, "centre", 2.5, "half", "VCA"
    
    Draw arrow: 6.6, 2.5, 6.9, 2.5
    
    Paint rectangle: "{0.6, 0.6, 0.7}", 6.9, 7.9, 2.2, 2.8
    Text: 7.4, "centre", 2.5, "half", "Clip"
    
    # Feedback arrow
    Colour: "{0.5, 0.5, 0.6}"
    Draw arrow: 7.9, 2.5, 8.2, 2.5
    Draw line: 8.2, 2.5, 8.2, 1.6
    Draw line: 8.2, 1.6, 4.1, 1.6
    Draw arrow: 4.1, 1.6, 4.1, 2.2
    
    # Control arrows
    Colour: "{0.5, 0.7, 0.5}"
    Draw arrow: 3.2, 3.5, 4.8, 3.0
    Font size: 4
    Text: 4.0, "centre", 3.4, "half", "freq"
    
    Colour: "{0.7, 0.5, 0.5}"
    Draw arrow: 3.2, 2.85, 6.1, 3.0
    Text: 4.7, "centre", 2.9, "half", "gain"
    
    # Output
    Colour: "Black"
    Draw arrow: 8.2, 2.5, 9.0, 2.5
    Paint rectangle: "{0.6, 0.8, 0.6}", 9.0, 9.8, 2.2, 2.8
    Text: 9.4, "centre", 2.5, "half", "Out"
    
    Colour: "Black"
    Draw inner box
    
    # Parameters
    Select outer viewport: 0, 8, 4.3, 4.8
    Axes: 0, 1, 0, 1
    Font size: 6
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Feedback: " + fixed$(base_Feedback, 2) + " | Sensitivity: " + fixed$(input_Sensitivity, 2) + " | Damping: " + fixed$(damping_Factor, 2) + " | Iterations: " + string$(iterations) + " | Bandwidth: " + fixed$(bandwidth_Hz, 0) + " Hz"
    
    Font size: 10
    Colour: "Black"
endif

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
