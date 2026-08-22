# ============================================================
# Praat AudioTools - Virtual_Subharmonic_Generator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6 (2026) - Compact main form
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Virtual Subharmonic Generator — phantom bass enhancement
#   (MaxxBass-style harmonic generation) plus optional Mid-Side
#   stereo widening with an optional low-cut on the Side channel.
#
#   The "phantom bass" trick: extract the bass band, run it
#   through tanh waveshaping to generate upper harmonics, filter
#   those harmonics, and add them on top of the high-passed
#   original. Because tanh is an odd (symmetric) function, a
#   balanced sinusoid mostly generates ODD harmonics (3f, 5f,
#   7f...); even harmonics (2f, 4f...) only appear from input
#   asymmetry, DC offset, or complex program material, and are
#   not guaranteed. The added upper harmonics can reinforce the
#   perceived bass on playback systems that reproduce the
#   fundamental poorly — but note the fundamental itself is NOT
#   removed from the signal: Highpass_freq is typically well
#   below Bass_high_freq, so a wide band of low-frequency energy
#   normally survives the high-pass stage and remains audible
#   alongside the added harmonics.
#
#   Pipeline:
#     1. Split into L and R channels
#     2. Extract bass band [Bass_low_freq, Bass_high_freq] per channel
#        (optionally normalized to a reference peak first — see
#        Bass_reference_mode — so Drive behaves consistently
#        across sources of different loudness)
#     3. tanh waveshape with Drive -> generates (mostly odd) harmonics
#     4. Bandpass-filter harmonics to [Bass_high_freq, Harmonic_lowpass]
#     5. High-pass the original L/R at Highpass_freq (clears low end)
#     6. Add harmonics onto the high-passed signal, scaled by
#        Harmonic_level (this is an addition gain, not a dry/wet
#        crossfade — see v0.4 changelog)
#     7. Optional M/S widening with an optional low-cut on the side
#        signal (see Mono_bass_side_lowcut)
#     8. Recombine to stereo and apply the selected Output_mode
#
#   Stereo width parameter behavior: the Side signal is multiplied
#   by `Stereo_width`. So 0 = mono collapse, 1 = identity (no
#   change), >1 = widen, <1 = narrow.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Changelog v0.6 (2026):
#   - FORM COMPACTION ONLY; audio/DSP, presets, parameter mapping,
#     analysis, rendering and the v0.5 visualization are unchanged.
#   - Main form now exposes only the musically central controls:
#     preset, bass band, drive, harmonic addition level, M/S widening
#     and stereo width, plus Draw/Play.
#   - Technical controls moved to an optional Advanced settings pause:
#     high-pass and harmonic-lowpass filters, bass-reference mode/peak,
#     Side low-cut, output policy/target and near-silence threshold.
#   - Advanced defaults are exactly the former v0.5 main-form defaults.
#
# Changelog v0.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention with
#     explicit inner viewports, standard title/subtitle, suite
#     typography, neutral panel backgrounds, summary strip and
#     full-page Picture export viewport.
#   - Preserved the script-specific nonlinear/diagnostic panels;
#     the visualization remains a direct explanation of the
#     transformation rather than a generic replacement plot.
#
# Changelog v0.4 (QA fixes):
#   - FIXED (blocker): visualization used hardcoded 0-based time
#     ranges (Get absolute extremum / Axes / Draw all started at
#     0). Any Sound with a non-zero start time (e.g. extracted
#     from 2.5-3.5 s) made Panel C's zoom window fall outside the
#     object's domain, crashing with "value undefined" on the
#     Axes call. Panel C now reads the real start/end time of
#     `original` and `result` and zooms relative to that; Panel D
#     now draws using the result's actual start/end time instead
#     of an assumed 0-finalDur range.
#   - FIXED (blocker): `Scale peak: 0.95` ran unconditionally at
#     the end, so silence, near-silence, and numerical residue
#     (peaks as low as 1e-15) were amplified to a near-full-scale
#     0.95. Replaced with an Output_mode choice (Preserve input
#     level / Normalize to target / Normalize only if it exceeds
#     target / Legacy always-normalize) plus a configurable
#     near-silence threshold (Near_silence_dB) below which
#     normalization is skipped and reported instead of applied.
#   - FIXED (blocker): `Harmonic_mix` was documented as a dry/wet
#     control ("0 = dry") but the signal is always high-passed
#     before mixing, so 0 produced a high-passed original, not a
#     dry signal (measured correlation with true dry: ~0.80).
#     Renamed to `Harmonic_level` and re-documented as an addition
#     gain (output = high-passed source + harmonics * level), which
#     is what the code actually does.
#   - FIXED (blocker): header/comments claimed the waveshaper
#     generates "2f, 3f, 4f..." harmonics. tanh() is odd-symmetric,
#     so a balanced input predominantly generates odd harmonics
#     (3f, 5f, 7f...); measured even-harmonic levels were >100 dB
#     below the 3rd harmonic on a clean sine. Description and
#     Panel A text corrected.
#   - FIXED (blocker): the "Wide Stereo" preset used
#     Stereo_width=0.8, which narrows (per the documented
#     width<1=narrow, width>1=widen semantics), not widens. Set to
#     1.4. "Aggressive MaxxBass" also used a narrowing width (0.7)
#     despite its name implying a bigger effect; set to 1.3.
#   - FIXED (blocker): no validation of frequency relationships.
#     Bass_low>=Bass_high, Bass_high>=Harmonic_lowpass,
#     Highpass/Harmonic_lowpass/Bass_high at or above Nyquist all
#     ran silently before. These combinations now exitScript with
#     a clear message. Harmonic_level and Stereo_width are still
#     allowed to go negative or beyond 0-1 (documented, musically
#     meaningful: phase-inverted addition / side polarity reversal),
#     but the script now reports when that's happening.
#   - Bass band (Bass_low_freq/Bass_high_freq) is now part of each
#     preset definition, so a preset's result no longer silently
#     depends on whatever is left in the Custom fields.
#   - Added Bass_reference_mode: optionally normalizes the
#     extracted bass band to Bass_reference_peak before waveshaping
#     (then rescales the resulting harmonics back down), so Drive
#     has a more consistent effect independent of input loudness.
#   - Multichannel input (>2 channels) is now explicitly handled:
#     channels 1 and 2 are used and a warning is printed reporting
#     how many channels were discarded (previously silent).
#   - Renamed `Preserve_mono_compatibility` to
#     `Mono_bass_side_lowcut`: the M/S math already guarantees
#     L'+R' = 2M regardless of this setting, so it was never really
#     protecting mono fold-down — it removes low-frequency stereo
#     difference information from the Side channel, which is what
#     the new name/label says.
#   - Removed the two mid-pipeline `@peakSafety` calls: since every
#     stage between them and the final output stage is linear, they
#     were fully undone by the final peak-scaling step (verified:
#     <3.3e-16 difference with them removed). The Output_mode logic
#     now includes its own safety ceiling.
#   - Info report now prints input peak, harmonic-branch peak,
#     pre-output peak, and the final normalization factor actually
#     applied (or "skipped, near-silent"); explicitly states the
#     output is always stereo; and reports whether Harmonic_level
#     or Stereo_width are set outside their normal [0,1] range.
#   - "Mixing harmonics (X%)" wording replaced with "Harmonic
#     addition gain: X" to stop implying a crossfade percentage.
#   - Panel A's diagram draws 5 stages (Input, Bass->Harmonics,
#     HP+Mix, M/S Width, Output); header/changelog text corrected
#     from "4 stages" to match.
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

form Virtual Subharmonic Generator v0.6
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset: 1
        option Custom (use settings below)
        option Subtle Enhancement
        option Moderate Effect
        option Aggressive MaxxBass
        option Mono-Safe Narrowing
        option Wide Stereo

    comment === Phantom Bass ===
    positive Bass_low_freq 30
    positive Bass_high_freq 120
    positive Drive 3.0
    real Harmonic_level 0.6

    comment === Stereo ===
    boolean Apply_MS_widening 1
    real Stereo_width 0.5

    boolean Advanced_settings 0
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
xminOrig = Get start time
xmaxOrig = Get end time
nyquist = sr / 2

# === Advanced defaults (identical to the v0.5 main-form defaults) ===
highpass_freq = 100
harmonic_lowpass = 800
bass_reference_mode = 1
bass_reference_peak = 0.5
mono_bass_side_lowcut = 1
output_mode = 2
normalize_target = 0.95
near_silence_dB = -80

# Praat permits only one form...endform block. Optional secondary controls
# therefore use beginPause/endPause and appear only when requested.
if advanced_settings
    beginPause: "Virtual Subharmonic Generator v0.6 - Advanced settings"
        comment: "=== Harmonic branch filtering ==="
        positive: "Highpass_freq", "100"
        positive: "Harmonic_lowpass", "800"

        comment: "=== Bass reference ==="
        optionmenu: "Bass_reference_mode", 1
            option: "Preserve bass level (Drive scales with input loudness)"
            option: "Normalize bass before waveshaping (Drive is level-independent)"
        positive: "Bass_reference_peak", "0.5"

        comment: "=== Side channel ==="
        boolean: "Mono_bass_side_lowcut", 1
        comment: "(removes low-frequency content from Side only)"

        comment: "=== Output level ==="
        optionmenu: "Output_mode", 2
            option: "Preserve input level"
            option: "Normalize to target"
            option: "Normalize only if it exceeds target"
            option: "Legacy (always normalize to 0.95)"
        real: "Normalize_target", "0.95"
        real: "Near_silence_dB", "-80"
        comment: "(below this peak level, normalization is skipped)"
    clicked = endPause: "Continue", 1
endif

# === Apply Presets ===
# Bass band is now part of every preset definition, so a preset's
# result no longer silently depends on whatever is left in the
# Custom fields (v0.3 QA finding: same preset + different leftover
# bass band produced RMS difference of 0.093).
if preset = 2
    # Subtle Enhancement
    bass_low_freq = 30
    bass_high_freq = 100
    drive = 2.0
    harmonic_level = 0.4
    highpass_freq = 90
    harmonic_lowpass = 600
    apply_MS_widening = 1
    stereo_width = 0.3
    mono_bass_side_lowcut = 1
    presetName$ = "Subtle"
elsif preset = 3
    # Moderate Effect
    bass_low_freq = 30
    bass_high_freq = 120
    drive = 3.0
    harmonic_level = 0.6
    highpass_freq = 100
    harmonic_lowpass = 800
    apply_MS_widening = 1
    stereo_width = 0.5
    mono_bass_side_lowcut = 1
    presetName$ = "Moderate"
elsif preset = 4
    # Aggressive MaxxBass
    # v0.3 used stereo_width=0.7, which narrows despite the preset
    # name suggesting a bigger effect. Widened to 1.3.
    bass_low_freq = 25
    bass_high_freq = 150
    drive = 5.0
    harmonic_level = 0.8
    highpass_freq = 120
    harmonic_lowpass = 1000
    apply_MS_widening = 1
    stereo_width = 1.3
    mono_bass_side_lowcut = 0
    presetName$ = "Aggressive"
elsif preset = 5
    # Mono-Safe Narrowing
    bass_low_freq = 30
    bass_high_freq = 110
    drive = 2.5
    harmonic_level = 0.5
    highpass_freq = 100
    harmonic_lowpass = 700
    apply_MS_widening = 1
    stereo_width = 0.4
    mono_bass_side_lowcut = 1
    presetName$ = "MonoSafe"
elsif preset = 6
    # Wide Stereo
    # v0.3 used stereo_width=0.8, which narrows the image by 20%
    # (measured Side/Mid RMS 0.4 vs identity's 0.5). Fixed to 1.4,
    # which actually widens per the documented width>1=widen rule.
    bass_low_freq = 30
    bass_high_freq = 130
    drive = 3.5
    harmonic_level = 0.65
    highpass_freq = 100
    harmonic_lowpass = 900
    apply_MS_widening = 1
    stereo_width = 1.4
    mono_bass_side_lowcut = 0
    presetName$ = "WideStereo"
else
    presetName$ = "Custom"
endif

# === Validate frequency relationships against each other and Nyquist ===
# (v0.3 QA finding: none of these were checked; all ran silently
# and produced a peak-0.95 output regardless of how nonsensical.)
if bass_low_freq >= bass_high_freq
    exitScript: "Bass_low_freq (", bass_low_freq, " Hz) must be less than Bass_high_freq (", bass_high_freq, " Hz)."
endif
if bass_high_freq >= harmonic_lowpass
    exitScript: "Bass_high_freq (", bass_high_freq, " Hz) must be less than Harmonic_lowpass (", harmonic_lowpass, " Hz)."
endif
if highpass_freq <= 0 or highpass_freq >= nyquist
    exitScript: "Highpass_freq (", highpass_freq, " Hz) must be between 0 and the Nyquist frequency (", nyquist, " Hz)."
endif
if harmonic_lowpass >= nyquist
    exitScript: "Harmonic_lowpass (", harmonic_lowpass, " Hz) must be below the Nyquist frequency (", nyquist, " Hz)."
endif
if bass_high_freq >= nyquist
    exitScript: "Bass_high_freq (", bass_high_freq, " Hz) must be below the Nyquist frequency (", nyquist, " Hz)."
endif

# Pre-compute status strings (replaces v0.2 inline ternary)
if apply_MS_widening
    msStr$ = "ON (width " + fixed$(stereo_width, 2) + ")"
else
    msStr$ = "OFF"
endif

if mono_bass_side_lowcut
    monoStr$ = "ON"
else
    monoStr$ = "OFF"
endif

if bass_reference_mode = 2
    bassRefStr$ = "ON (target peak " + fixed$(bass_reference_peak, 2) + ")"
else
    bassRefStr$ = "OFF"
endif

nearSilenceLin = 10 ^ (near_silence_dB / 20)

# === Info ===
writeInfoLine: "=== Virtual Subharmonic Generator v0.6 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s, ", numChannels, " ch, starts at ", fixed$(xminOrig, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Output is always stereo, regardless of input channel count."
appendInfoLine: ""
appendInfoLine: "Phantom Bass:"
appendInfoLine: "  Bass band: ", fixed$(bass_low_freq, 1), "-", fixed$(bass_high_freq, 1), " Hz"
appendInfoLine: "  Drive: ", fixed$(drive, 2)
appendInfoLine: "  Harmonic addition gain: ", fixed$(harmonic_level, 2)
if harmonic_level < 0
    appendInfoLine: "    Note: negative -- harmonics are added phase-inverted."
elsif harmonic_level > 1
    appendInfoLine: "    Note: > 1 -- harmonics are boosted above their generated level."
endif
appendInfoLine: "  Highpass: ", fixed$(highpass_freq, 1), " Hz"
appendInfoLine: "  Harmonic LP: ", fixed$(harmonic_lowpass, 1), " Hz"
appendInfoLine: "  Bass reference normalization: ", bassRefStr$
appendInfoLine: "M/S widening: ", msStr$
if apply_MS_widening and stereo_width < 0
    appendInfoLine: "    Note: negative width -- Side polarity is inverted (L/R exchange character)."
endif
appendInfoLine: "Mono bass side low-cut: ", monoStr$
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

# Convert to stereo if mono; warn and use channels 1-2 for anything
# wider than stereo (v0.3 QA finding: 4-channel input was silently
# reduced to 2 channels with no warning or documented policy).
if numChannels = 1
    appendInfoLine: "Converting mono to stereo..."
    selectObject: original
    Convert to stereo
    workingSound = selected("Sound")
else
    if numChannels > 2
        appendInfoLine: "WARNING: input has ", numChannels, " channels; using channels 1 and 2 only, discarding the other ", numChannels - 2, "."
    endif
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

selectObject: bassLfiltered
bassLpeak = Get absolute extremum: 0, 0, "None"
selectObject: bassRfiltered
bassRpeak = Get absolute extremum: 0, 0, "None"
bassPeak = max(bassLpeak, bassRpeak)
appendInfoLine: "  Extracted bass peak: ", fixed$(bassPeak, 4)

# Optional: normalize the extracted bass to a reference peak before
# waveshaping, so Drive has a consistent effect independent of how
# loud the source is (v0.3 QA finding: at Drive=5 the 3rd-harmonic
# level relative to the fundamental ranged from -143.7 dB at input
# amplitude 0.0001 up to -0.94 dB at amplitude 1.0). The harmonic
# branch is scaled back down by the same factor afterwards so it
# stays proportionate to the original input level.
refScaleL = 1
refScaleR = 1
if bass_reference_mode = 2
    if bassLpeak > 0
        refScaleL = bass_reference_peak / bassLpeak
        selectObject: bassLfiltered
        Formula: "self * " + string$(refScaleL)
    endif
    if bassRpeak > 0
        refScaleR = bass_reference_peak / bassRpeak
        selectObject: bassRfiltered
        Formula: "self * " + string$(refScaleR)
    endif
endif

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
if bass_reference_mode = 2 and refScaleL <> 0
    selectObject: harmLfiltered
    Formula: "self / " + string$(refScaleL)
endif

# RIGHT harmonics
selectObject: bassRfiltered
Copy: "harm_R_temp"
harmRtemp = selected("Sound")
Formula: "tanh(self * " + drive_str$ + ")"
Filter (pass Hann band): bass_high_freq, harmonic_lowpass, 100
harmRfiltered = selected("Sound")
removeObject: harmRtemp
if bass_reference_mode = 2 and refScaleR <> 0
    selectObject: harmRfiltered
    Formula: "self / " + string$(refScaleR)
endif

selectObject: harmLfiltered
harmLpeak = Get absolute extremum: 0, 0, "None"
selectObject: harmRfiltered
harmRpeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Harmonic-branch peak: ", fixed$(max(harmLpeak, harmRpeak), 4)

# === STAGE 3: HIGH-PASS ORIGINAL CHANNELS ===
appendInfoLine: "High-passing original at ", highpass_freq, " Hz..."

selectObject: leftChannel
Filter (stop Hann band): 0, highpass_freq, 100
leftHP = selected("Sound")

selectObject: rightChannel
Filter (stop Hann band): 0, highpass_freq, 100
rightHP = selected("Sound")

removeObject: leftChannel, rightChannel

# === STAGE 4: ADD HARMONICS ONTO THE HIGH-PASSED SIGNAL ===
# This is an addition gain, not a dry/wet crossfade: the source is
# already high-passed by this point, so Harmonic_level=0 yields a
# high-passed original, not a dry signal (see v0.4 changelog).
appendInfoLine: "Harmonic addition gain: ", fixed$(harmonic_level, 2)

mix_str$ = string$(harmonic_level)
harmL_str$ = string$(harmLfiltered)
harmR_str$ = string$(harmRfiltered)

selectObject: leftHP
Formula: "self + object[" + harmL_str$ + "] * " + mix_str$

selectObject: rightHP
Formula: "self + object[" + harmR_str$ + "] * " + mix_str$

# Cleanup intermediates
removeObject: bassLfiltered, bassRfiltered, harmLfiltered, harmRfiltered

# NOTE (v0.4): the mid-pipeline peak-safety call that used to run
# here was removed. Every stage between here and the final output
# stage is linear (addition, filtering, scaling), so it was fully
# undone by the final peak-scaling step regardless of Output_mode
# (verified: <3.3e-16 difference in the final output with/without
# it). The final Output_mode logic includes its own safety ceiling.

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
    
    # Low-cut the Side channel below 200 Hz. Note this does NOT
    # change the mono sum L'+R' = 2M, which holds regardless of
    # this setting -- it simply removes low-frequency stereo
    # difference information from the Side channel (keeps bass
    # centered), which is what the option name says.
    if mono_bass_side_lowcut
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
endif

# === STAGE 6: COMBINE TO STEREO ===
appendInfoLine: "Combining to stereo..."

selectObject: leftHP, rightHP
Combine to stereo
result = selected("Sound")
Rename: originalName$ + "_subharm_" + presetName$

# Cleanup
removeObject: leftHP, rightHP, workingSound

# === OUTPUT LEVEL (Output_mode) ===
# v0.3 always ran `Scale peak: 0.95` unconditionally, so silence
# and near-silence (numerical residue as low as 1e-15) were
# amplified to a near-full-scale 0.95. Below, normalization is
# skipped and reported whenever the output peak is under the
# Near_silence_dB threshold, in every mode that would otherwise
# normalize.
selectObject: result
preOutputPeak = Get absolute extremum: 0, 0, "None"
isNearSilent = preOutputPeak < nearSilenceLin
normFactor = 1

if isNearSilent
    appendInfoLine: "Output is near-silent (peak ", fixed$(preOutputPeak, 6), ", below ", fixed$(near_silence_dB, 0), " dB) -- normalization skipped."
elsif output_mode = 1
    # Preserve input level: no scaling, just a hard safety ceiling
    # so an unusual parameter combination can't overflow.
    if preOutputPeak > 0.999
        normFactor = 0.999 / preOutputPeak
        Formula: "self * " + string$(normFactor)
    endif
elsif output_mode = 2
    # Normalize to target
    normFactor = normalize_target / preOutputPeak
    Scale peak: normalize_target
elsif output_mode = 3
    # Normalize only if it exceeds target
    if preOutputPeak > normalize_target
        normFactor = normalize_target / preOutputPeak
        Scale peak: normalize_target
    endif
elsif output_mode = 4
    # Legacy: always normalize to 0.95 (near-silence guard above still applies)
    normFactor = 0.95 / preOutputPeak
    Scale peak: 0.95
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
nResultCh = Get number of channels

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    vizName$ = replace$(originalName$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Virtual Subharmonic Generator v0.6##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Bass " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Harm gain: " + fixed$(harmonic_level, 2)
        ... + "  |  M/S: " + msStr$
        ... + "  |  Mono: " + monoStr$
    
    # ----------------------------------------------------------
    # PANEL A: PROCESSING CHAIN  (left, headline)
    # Vertical 5-stage diagram (Input, Bass->Harmonics, HP+Mix,
    # M/S Width, Output; style matching Chaos Distortion v0.3 and
    # Distortion+BitCrusher v0.3 for visual consistency)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 6
    
    # Stage 1: Input
    yTop = 5.6
    yBot = 5.0
    Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 7
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
    Font size: 7
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
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "HP + MIX"
    Font size: 7
    Colour: "{0.15, 0.40, 0.15}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half",
        ... "HP " + fixed$(highpass_freq, 0) + " Hz + harm * "
        ... + fixed$(harmonic_level, 2)
    
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
    Font size: 7
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
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "OUTPUT"
    Font size: 7
    Colour: "{0.15, 0.40, 0.30}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "(enhanced stereo)"
    
    # Side low-cut badge
    if mono_bass_side_lowcut
        Font size: 6
        Colour: "{0.55, 0.30, 0.30}"
        Text: 0.50, "centre", 0.50, "half", "[side HP @ 200 Hz]"
    endif
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.95, "half", "Phantom Bass:"
    
    Font size: 7
    Colour: "{0.85, 0.55, 0.20}"
    Text: 0.10, "left", 0.87, "half", "Bass:    " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
    Text: 0.10, "left", 0.79, "half", "Drive:   " + fixed$(drive, 2)
    Text: 0.10, "left", 0.71, "half", "Harm gain: " + fixed$(harmonic_level, 2)
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.61, "half", "Filtering:"
    
    Font size: 7
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.53, "half", "HP cut:  " + fixed$(highpass_freq, 0) + " Hz"
    Text: 0.10, "left", 0.45, "half", "Harm LP: " + fixed$(harmonic_lowpass, 0) + " Hz"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.34, "half", "Stereo:"
    
    Font size: 7
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
    
    Font size: 7
    if mono_bass_side_lowcut
        Colour: "{0.55, 0.30, 0.30}"
        Text: 0.10, "left", 0.08, "half", "Side low-cut: ON (200 Hz)"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.10, "left", 0.08, "half", "Side low-cut: OFF"
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
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    # v0.4 FIX (blocker): v0.3 zoomed into the hardcoded range
    # 0-0.03 s, which crashed ("value undefined" on Axes) whenever
    # the Sound didn't start at time 0. Zoom relative to the
    # object's real start time instead.
    zoomDur = 0.03
    if zoomDur > duration
        zoomDur = duration
    endif
    zoomStart = xminOrig
    zoomEnd = zoomStart + zoomDur
    if zoomEnd > xmaxOrig
        zoomEnd = xmaxOrig
    endif
    
    selectObject: original
    origPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    selectObject: result
    resPeak = Get absolute extremum: zoomStart, zoomEnd, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", zoomStart, zoomEnd, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: zoomStart, 0, zoomEnd, 0
    
    # Original (gray, behind)
    selectObject: original
    if numChannels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Enhanced (purple, on top)
    selectObject: result
    Extract one channel: 1
    zRes = selected("Sound")
    Colour: "{0.55, 0.30, 0.65}"
    Line width: 1.3
    Draw: zoomStart, zoomEnd, -zAmpViz, zAmpViz, "no", "Curve"
    removeObject: zRes
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$((zoomEnd - zoomStart) * 1000, 0) + " ms  (gray = original L, purple = enhanced L)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
    # v0.4 FIX: axes were drawn as 0-finalDur while `result` actually
    # occupies the source's original time domain (e.g. 2.5-3.5 s),
    # so the waveform was drawn outside the visible axes and never
    # appeared. Use the result's real start/end time instead.
    selectObject: result
    resultStart = Get start time
    resultEnd = Get end time
    outPeakViz = Get absolute extremum: resultStart, resultEnd, "None"
    if outPeakViz < 0.001
        outPeakViz = 0.001
    endif
    ampViz = outPeakViz * 1.15
    
    Axes: resultStart, resultEnd, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", resultStart, resultEnd, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: resultStart, 0, resultEnd, 0
    
    selectObject: result
    Extract one channel: 1
    vCh1 = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: resultStart, resultEnd, -ampViz, ampViz, "no", "Curve"
    removeObject: vCh1
    
    selectObject: result
    Extract one channel: 2
    vCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: resultStart, resultEnd, -ampViz, ampViz, "no", "Curve"
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
    Select inner viewport: 0.60, 7.70, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + vizName$
        ... + "  |  Bass: " + fixed$(bass_low_freq, 0) + "-" + fixed$(bass_high_freq, 0) + " Hz"
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Harm gain: " + fixed$(harmonic_level, 2)
        ... + "  |  HP: " + fixed$(highpass_freq, 0) + " Hz"
    
    Text: 0.02, "left", 0.28, "half",
        ... "M/S: " + msStr$
        ... + "  |  Side low-cut: " + monoStr$
        ... + "  |  Output: " + fixed$(finalDur, 2) + " s, peak " + fixed$(finalPeak, 3)
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 7
    Colour: "Black"
    Line width: 1

    # Restore complete page for Picture export / clipboard.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "Pre-output peak: ", fixed$(preOutputPeak, 4)
if isNearSilent
    appendInfoLine: "Normalization: skipped (near-silent)"
else
    appendInfoLine: "Normalization factor applied: ", fixed$(normFactor, 4)
endif
appendInfoLine: "Final peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result

# (No procedures remain: the v0.3 `peakSafety` procedure was
# removed in v0.4 -- see changelog.)
