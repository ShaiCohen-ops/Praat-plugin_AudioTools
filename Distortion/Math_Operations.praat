# ============================================================
# Praat AudioTools - Math_Operations.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.6.0 (2026) - DSP audit against SuperCollider / gen~ references
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Math Operations Between Two Sounds — combines two audio
#   files using mathematical operations. Includes basic math
#   (add, multiply/ring mod, etc.), modulation and sample-wise
#   waveshaping, nonlinear processing (wavefold, quantization),
#   and advanced transforms (vector morph, logistic-style shaping,
#   cross-phase waveshaping, random amplitude scatter).
#   Select exactly 2 Sound objects before running.
#
#   The two inputs must share the same sample rate. Different
#   durations are aligned at each Sound's OWN start time and
#   truncated to the shorter length. (v0.3 aligned both at absolute
#   time 0, which silently produced silence for Sounds whose time
#   domain did not begin there.)
#
#   OPERATION PRIORITY ORDER:
#   The script applies ONE operation chosen by priority:
#     Advanced > Nonlinear > Modulation > Basic
#   If you select both a Nonlinear and a Modulation operation,
#   only Nonlinear runs (Modulation is silently ignored). To
#   use a Basic operation, leave the other three menus on
#   "None". Presets handle this automatically.
#
#   NAMING NOTES (v0.4: several operations were renamed for what
#   they actually compute - see the changelog):
#   - The quantizer sets a STEP of 1/N, which is not N levels:
#     over -1..+1 a step of 1/8 gives 17 distinct values, and over
#     the -2..+2 that a sum of two normalized Sounds can reach, 33.
#     Since v0.6, N = round(4 / intensity): MORE intensity means a
#     COARSER step (0.5 still gives 1/8).
#   - "Logistic chaos" is not the recursive logistic map x_{n+1} =
#     r*x*(1-x). It is a memoryless product
#       (s1+s2) * 3.5 * (1 - k*|s1|*|s2|),  k = 2 * intensity
#     (k = 1 at intensity 0.5, which is the v0.3-v0.5.1 formula),
#     which produces audio-rate amplitude shaping but no
#     recursive iteration.
#   - "Hard sync sim" is an audio-effect pseudo-sync, not a
#     phase-reset oscillator-style hard sync.
#   - "AM depth control" (Nonlinear 3) computes exactly the same
#     expression as Tremolo (Modulation 9) with depth = intensity.
#     Both are kept so menu indices and saved settings stay valid.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#
# Changelog v0.6.0 (2026):
#   DSP audit against SuperCollider (sc_fold, sc_pow, BinaryOpUGen)
#   and Max gen~ (genlib fold, safediv, quant). Runtime-tested in
#   Praat 6.4.06, 6.4.63 and 7.0 (bit-identical across the three) and
#   6.1.38 (last-ulp libm differences only). Every changed operation was checked
#   against v0.5.1 with Output_mode = Preserve, so gain cannot hide a
#   difference.
#   DSP CHANGES (output differs from v0.5.1 only where stated):
#   - Wavefold: closed-form triangle fold, as in SC Fold / gen~ fold.
#     The repeated reflection only folded inputs up to (2N+1)*T and let
#     anything louder through unbounded and linear. Fold_passes = 0 (new
#     default) is the complete fold; 1..N keeps the v0.5.1 reflections
#     bit-for-bit. Output is unchanged wherever v0.5.1 had already
#     folded completely, which includes the Wavefold preset on inputs
#     that stay within +/-1.
#   - Power mod: removed the 1e-6 base floor. With the exponent clamped
#     at >= 0.05, 0^e is defined (= 0), so the floor guarded nothing but
#     created a jump: any |S1| below 1e-6 came out at about +/-0.5
#     (1e-6^0.05 = 0.501). Now sgn(S1)*|S1|^max(1+S2*depth, 0.05), which
#     is SC's sign-preserving pow. Continuous, and exact zero stays 0.
#     Changes only samples with 0 < |S1| < 1e-6. No preset uses it.
#   - Logistic-style: intensity was a pure output gain (r = 7*intensity),
#     so it did nothing after normalization. It now sets the fold-back
#     depth k = 2*intensity in (S1+S2)*3.5*(1 - k*|S1|*|S2|). Intensity
#     0.5 (the preset) is bit-identical; other values change the
#     transfer-function shape, not just the level.
#   - Quantizer: intensity direction inverted, N = round(4/intensity),
#     so more intensity is a coarser step, like every other intensity
#     control here. Intensity 0.5 still gives 1/8. Rounding is now
#     odd-symmetric (half away from zero): Praat's round() is
#     floor(x+0.5), so -1.5 went to -1 but +1.5 went to 2. The preset
#     differs from v0.5.1 only at samples landing exactly on a negative
#     half-step, by one step.
#   - XOR-like: uses the three-valued sign. v0.5.1 treated an exact zero
#     as "same sign", so a digitally silent Sound 1 turned Sound 2 into
#     +|S2|/2, a full-wave-rectified copy with heavy DC. Differs only at
#     samples where an input is exactly 0.
#   - COST (30 s stereo, 44.1 kHz, whole script): Wavefold 0.57 -> 0.37 s,
#     Power 0.61 -> 0.43 s, signed magnitude product 0.24 -> 0.12 s;
#     the symmetric quantizer 0.16 -> 0.28 s and XOR-like 0.26 -> 0.31 s
#     are slower (an extra branch per sample).
#   - Magnitude products: algebraically simplified. Signed and unsigned
#     |S1|*|S2| are bit-identical (S1*|S2|, |S1*S2|); the geometric
#     product uses one sqrt instead of two and differs by rounding only
#     (about 1e-16).
#   CRASH FIX (channels, not DSP):
#   - "Sound 1 defines layout" with Sound 1 having more channels than a
#     MULTICHANNEL Sound 2 (3ch + 2ch) aborted Praat with an internal
#     assertion (rc 134 on 6.4.06, 6.4.63 and 7.0; v0.5.1 too) instead
#     of processing the extra channels against silence as the NOTE says.
#     Sound 2 is now padded with silent channels. Mono Sound 2 (broadcast)
#     and every other layout are unchanged.
#   REPORTING / UI:
#   - Form shortened from 31 to 17 rows so it fits on screen: the section
#     headers and per-field hint comments were removed (the field order,
#     names and defaults are unchanged, so runScript callers and Matrix
#     Chain are unaffected). The hints now live here:
#       Nonlinear_intensity - used by Nonlinear 2-8 and Advanced 4-8
#       Fold_passes   - Wavefold only: 0 = complete fold, 1..N = v0.5.1
#       Divide_epsilon - Divide only: |S2| at or below it yields 0
#       Geometric_polarity - the two magnitude products only
#       Random_seed   - Random scatter only; 0 = unpredictable
#     The Info window and Panel B report which controls the run used.
#   - Fold_passes is now `integer`, 0 = complete fold (default).
#   - Wavefold, quantizer, logistic and Mod depth reports state what the
#     parameter does for the operation that ran.
#   - Random scatter warns when intensity > 1 (the gain crosses zero and
#     flips polarity on some samples).
#   - Removed the unused `intensityUsed$` variable.
#   UNCHANGED, AFTER REVIEW: Divide (see the comment at the operation),
#   and every other operation, the presets' numeric values, priority
#   order, time alignment, channel policies, output modes, visualization.
#
# Changelog v0.5.1 (2026):
#   - QA/TERMINOLOGY/REPORTING ONLY; DSP formulas and preset numeric
#     values are unchanged.
#   - Renamed several presets/operations so labels describe the actual
#     sample-wise math: Double Sine Waveshaping, Quantized Lo-Fi,
#     Pseudo-Sync, Logistic-Style Shaping, and the two magnitude-product
#     variants.
#   - Magnitude-product reports now state whether Sound 1 polarity is
#     restored or the result is unsigned.
#   - Clarified that Sound 1 / Sound 2 follow Praat Objects-list order
#     (top to bottom), which matters for non-commutative operations.
#   - Renamed the output guard to "Attenuate to 0.95 only if peak >
#     0.95 (after scaling)"; it is global peak scaling, not a limiter.
#   - Visualization parameter report and summary now show the controls
#     actually used by the selected operation (Divide epsilon, fold
#     passes, geometric polarity, random seed, channel policy, etc.)
#     rather than always showing Mod depth / Intensity.
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
# Changelog v0.4b:
#   All five items below are v0.4 regressions, found by a second
#   runtime pass.
#   - FIXED: the preset reset block set `output_scaling = 1.0`, so
#     choosing any preset discarded the user's Output_scaling. The
#     v0.4 output modes therefore worked only in Custom, which
#     reinstated part of the problem they were added to fix.
#     Presets select the operation; output level stays global.
#   - FIXED: the intensity-in-use report tested only
#     advanced_operation = 3, so Geometric product (sqrt magnitudes) (= 2)
#     showed "[in use]" while ignoring the control. Both magnitude
#     products are now reported correctly, and the count is FIVE
#     operations newly connected, not six - the form comment and
#     the v0.4 changelog both said six.
#   - FIXED (compatibility): I read v0.3's scatter range wrong
#     twice. `0.8 + 0.4*randomUniform(-1,1)` spans 0.4..1.2, not
#     0.8..1.2, since randomUniform(-1,1) spans -1..+1. The mapping
#     is now 0.8 + 0.8*intensity*randomUniform(-1,1), which gives
#     exactly 0.4..1.2 at intensity 0.5, and the Scatter preset is
#     set to 0.5 (v0.4 left it at 0.6).
#   - FIXED (compatibility): the Rectify preset still carried
#     v0.3's `nonlinear_intensity = 0.0`, but intensity is now the
#     weight on Sound 2 - so the preset computed abs(S1) alone with
#     Sound 2 contributing nothing. Set to 0.5, which reproduces
#     v0.3's abs(S1) - abs(S2).
#   - FIXED: Divide_epsilon was `real` and tested with `<`, so
#     entering 0 disabled the guard entirely (abs(0) < 0 is false)
#     and an exact zero divided to NaN again. Now `positive` and
#     tested with `<=`.
#   - RENAMED "Power mod: sgn(S1)*|S1|^(1 + S2*depth)" to "Power
#     mod (exponent floored at 0.05)". The code clamps the
#     exponent, so S1=0.5, S2=-1, depth=2 returns 0.5^0.05 =
#     0.9659, not the 0.5^-1 = 2 the label implied. Allowing
#     negative exponents would reintroduce the 0^-1 blow-up the
#     clamp prevents, so the clamp stays and the name changes.
#   - RENAMED the "Conditional limiter" output mode to "Conditional
#     peak normalization". `Scale peak` attenuates the whole signal
#     when any sample exceeds the target; it does not act on peaks
#     alone, so it is not a limiter.
#
# Changelog v0.4:
#   This round follows a review that RAN every preset and operation
#   through Praat rather than reading them, so several items below
#   are confirmed failures rather than suspected ones.
#
#   BLOCKERS FIXED:
#   - `sign()` is not a Praat function. Three operations therefore
#     did not run at all, failing with "Unknown function «sign»":
#     Wavefold, Hard sync sim, and Power mod - and with them the
#     Wavefold Distortion and Hard Sync presets. Replaced with the
#     ((x>0) - (x<0)) idiom that Hard_Clip.praat in this same suite
#     already uses and documents as "version-safe".
#   - Time alignment assumed both Sounds start at absolute 0.
#     `Extract part: 0, min_dur` is not "the first min_dur of this
#     object" - a Sound's start time is independent, and
#     Preserve times = no only shifts the part after selection. On
#     two Sounds starting at 2 s and 5 s the output was entirely
#     silent; with one at 0 and one at 5 s only the first survived
#     and the second became zeros, with no warning. Each Sound is
#     now cut from its own start time.
#   - Divide used `self / (S2 + 1e-10)`, which is not a
#     divide-by-zero guard: it moves the denominator's zero to
#     -1e-10, so S2 = -1e-10 divides by exactly zero and yields NaN
#     that survives normalization and is not caught by the peak
#     report. S2 = 0 gave 5e9 and S2 = 1e-12 gave 4.95e9. The guard
#     now tests |denominator| against Divide_epsilon.
#   - Sqrt domain and Exp domain added 1e-10 floors, so two silent
#     inputs produced a small CONSTANT which `Scale peak: 0.95`
#     then lifted to 0.95 on every sample - digital silence came
#     out as full-scale DC. The floors are gone (sqrt(0) is
#     defined), so silence stays silent.
#   - Output_scaling did nothing whenever Normalize was on, since
#     peak normalization divides any positive scalar back out;
#     0.5 and 2.0 gave byte-identical output. Output_mode now makes
#     the order explicit, including a normalize-then-gain mode, and
#     the default mode says outright that the scaling is inert.
#   - Channel behaviour was undefined and asymmetric: the result
#     was always a copy of Sound 1, so stereo+mono broadcast the
#     mono, 3ch+2ch processed channel 3 against silence, and
#     mono+stereo discarded Sound 2's right channel - all
#     dependent on selection order, which matters for Divide,
#     Subtract and Power mod. Channel_policy is now explicit, with
#     the v0.3 behaviour as default plus a warning when the counts
#     differ.
#
#   DSP AND INTERFACE:
#   - Power mod's guard tested the MODULATOR for being near zero,
#     which is not where the singularity is. The exponent is
#     1 + S2*depth (not S1^(S2/2) as the menu said), so S2 = -1 with
#     depth 2 gives 0^-1. The guard now tests the exponent and the
#     base, and the menu label states the real expression.
#   - Nonlinear_intensity was shown in the form and the report for
#     every run but was read by none of seven operations. FIVE now
#     use it (Quantizer, Logistic, Rectify, Cross-phase, Random
#     scatter), with the previous constants recovered at intensity
#     0.5; the two magnitude products are plain products with no
#     natural parameter for it to scale, and the report says per
#     run whether the control is live.
#   - Wavefold: threshold was 0.5 + intensity, so MORE intensity
#     meant LESS folding. Inverted, and folding now repeats
#     (Fold_passes) - a single reflection leaves anything past 3T
#     outside the threshold again, which is not what "wavefold"
#     describes.
#   - Vector morph warns when intensity exceeds 1, where it
#     extrapolates and Sound 1's weight goes negative.
#   - Random scatter takes a Random_seed. Three identical runs
#     previously gave three different outputs with nothing in the
#     form or the report to indicate it.
#   - Sqrt/Exp domain results are products of magnitudes and so
#     were always positive, carrying heavy DC. Geometric_polarity
#     restores Sound 1's sign by default.
#   - The result panel labelled anything non-mono "blue=L
#     orange=R" while drawing only two channels.
#   - Undefined output samples and peaks above 1.0 are now
#     reported.
#
#   RENAMED FOR ACCURACY (object names change accordingly):
#   - "Spectral Blur" -> "Soft Normalized Mix". There is no
#     spectrum, FFT, STFT, window or frequency-domain smoothing
#     anywhere in it - it is a sample-wise mix with nonlinear
#     normalization.
#   - "Granular Scatter" -> "Random Amplitude Scatter". No grains,
#     grain duration, displacement, density, overlap or windowing.
#   - "Frequency Shifter" / "Freq shift sim" -> cosine cross-
#     waveshaper. No phase accumulation, no fixed carrier, no
#     Hilbert transform; it uses S2's sample value as an angle.
#   - "Pseudo phase-vocoder" -> "Cross-phase waveshaper". No
#     framing, spectrum, phase estimate or overlap-add.
#   - "Exp domain mix" -> "Absolute product": exp(ln a + ln b) is
#     identically a*b, verified exactly.
#   - "Sqrt domain mix" -> "Geometric magnitude product".
#   - "FM Synthesis" -> "FM-like waveshaping": sample values are
#     used as angles with no frequency-to-phase integration.
#   - "Bitcrush (8 levels)" -> "Quantize to 1/N amplitude steps",
#     and there is no sample-rate reduction, so it is a quantizer
#     rather than a bitcrusher.
#   - The AM menu entries said S1 * sin(S2) but compute
#     S1 * (0.5 + 0.5*sin(...)), unipolar with a carrier offset.
#   - Tremolo's label notes that depth > 1 makes the gain bipolar
#     and inverts phase.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. Same Formula expressions
#     for every operation. Same priority order. Same Scale peak.
#   - Form syntax modernized: all five optionmenus use colon.
#   - Pre-computed display strings (replaces v0.2 inline if/then/
#     else fi in parameter-panel Text — unreliable in Praat's
#     script-level expression context).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (left, headline): operation diagram showing
#         S1 + S2 -> operation -> Out
#       Panel B (right, headline): parameter report listing
#         which menu's operation actually ran (so users see the
#         priority resolution)
#       Panel C: side-by-side input waveforms (S1 green, S2 blue,
#         half-width each)
#       Panel D: result waveform with L/R channels distinguished
#       Panel E: summary stats bar
#   - Header documents the priority order (Advanced > Nonlinear >
#     Modulation > Basic) so users understand why some menu
#     selections are silently ignored.
#   - Header documents the 8-level vs 8-bit naming, the
#     non-iterative "logistic chaos," and pseudo "hard sync"
#     so users understand what they are actually getting.
# Changelog v0.2:
#   - Fixed formula syntax (Formula: ~)
#   - Fixed undefined variable errors
#   - Added visualization
#   - Added info output
# ============================================================

form Math Operations Between Sounds v0.6.0
    comment Select 2 Sounds (Sound 1 / 2 = Objects-list order). Details: header and Info window.
    optionmenu Preset: 1
        option Custom (manual settings)
        option Clean Add
        option Clean Multiply (Ring Mod)
        option Tremolo Effect
        option Crunch Mod (Arctan)
        option FM-like Waveshaping
        option Double Sine Waveshaping
        option Wavefold Distortion
        option Quantized Lo-Fi
        option Cosine Cross-Waveshaper
        option Pseudo-Sync
        option Logistic-Style Shaping
        option Soft Normalized Mix
        option Cross-Phase Waveshaper
        option Random Amplitude Scatter
        option Geometric Product (sqrt magnitudes)
        option Vector Morph
        option Rectify Distortion
    optionmenu Operation: 2
        option Add (+)
        option Subtract (-)
        option Multiply (*) [Ring Mod]
        option Divide (/)
        option Average
        option Minimum
        option Maximum
        option Absolute difference
        option XOR-like (sign mixing)
    optionmenu Modulation_operation: 1
        option None
        option AM (unipolar): S1 * (0.5 + 0.5*sin(S2))
        option AM (unipolar): S1 * (0.5 + 0.5*cos(S2))
        option FM-like: sin(Sound1) * Sound2
        option FM-like: cos(Sound1) * Sound2
        option Double sine waveshaping: sin(S1) * sin(S2)
        option Soft clip: arctan(S1 * S2)
        option Power mod (exponent floored at 0.05)
        option Tremolo: S1 * (1 + S2*depth) [bipolar if depth>1]
    optionmenu Nonlinear_operation: 1
        option None
        option Cosine cross-waveshape (not a freq shift)
        option AM depth control
        option Wavefold
        option Hard sync sim
        option Quantize to 1/N amplitude steps
        option Amplitude-dependent blend
        option Soft normalize mix
    optionmenu Advanced_operation: 1
        option None
        option Geometric product (sqrt magnitudes)
        option Magnitude product (= |S1| * |S2|)
        option Vector morph
        option Logistic-style (non-recursive)
        option Rectify and mix
        option Cross-phase waveshaper
        option Random amplitude scatter
    positive Modulation_depth 1.0
    positive Nonlinear_intensity 0.5
    integer Fold_passes 0
    positive Divide_epsilon 0.001
    optionmenu Geometric_polarity: 1
        option Restore sign of Sound 1
        option Unsigned magnitude product (v0.2/v0.3)
    integer Random_seed 0
    optionmenu Channel_policy: 1
        option Sound 1 defines layout (v0.2/v0.3)
        option Require matching channel counts
        option Mix both to mono
    optionmenu Output_mode: 1
        option Normalize to 0.95 (v0.2/v0.3; scaling inert)
        option Normalize to 0.95, then apply scaling
        option Attenuate to 0.95 only if peak > 0.95 (after scaling)
        option Preserve (scaling only)
    positive Output_scaling 1.0
    boolean Draw_visualization 1
    boolean Play_result 1
endform

divEps$ = string$(divide_epsilon)
if fold_passes < 0
    exitScript: "Fold_passes must be 0 (complete fold) or a positive number of reflections."
endif

# === Apply Presets ===
if preset > 1
    # Reset all menus to defaults
    modulation_operation = 1
    nonlinear_operation = 1
    advanced_operation = 1
    operation = 1
    # v0.4b: `output_scaling = 1.0` used to be reset here, so choosing
    # any preset silently discarded the user's Output_scaling - which
    # left the v0.4 output modes working only in Custom, reinstating
    # part of the very problem they were added to fix. The presets
    # select the OPERATION; output level is a global control and stays
    # under the user's hand. This does not affect v0.3 compatibility,
    # since in the default Normalize mode the scaling is inert anyway.
    
    if preset = 2
        operation = 1
        presetName$ = "Add"
    elsif preset = 3
        operation = 3
        presetName$ = "RingMod"
    elsif preset = 4
        modulation_operation = 9
        modulation_depth = 0.5
        presetName$ = "Tremolo"
    elsif preset = 5
        modulation_operation = 7
        modulation_depth = 2.0
        presetName$ = "Crunch"
    elsif preset = 6
        modulation_operation = 4
        modulation_depth = 2.0
        presetName$ = "FM"
    elsif preset = 7
        modulation_operation = 6
        modulation_depth = 1.5
        presetName$ = "DoubleSine"
    elsif preset = 8
        nonlinear_operation = 4
        nonlinear_intensity = 0.8
        presetName$ = "Wavefold"
    elsif preset = 9
        nonlinear_operation = 6
        nonlinear_intensity = 0.5
        presetName$ = "QuantizedLoFi"
    elsif preset = 10
        nonlinear_operation = 2
        nonlinear_intensity = 1.2
        presetName$ = "CosXWaveshape"
    elsif preset = 11
        nonlinear_operation = 5
        nonlinear_intensity = 0.9
        presetName$ = "PseudoSync"
    elsif preset = 12
        advanced_operation = 5
        nonlinear_intensity = 0.5
        presetName$ = "LogisticStyle"
    elsif preset = 13
        nonlinear_operation = 8
        nonlinear_intensity = 0.8
        presetName$ = "SoftNormMix"
    elsif preset = 14
        advanced_operation = 7
        nonlinear_intensity = 0.5
        presetName$ = "CrossPhase"
    elsif preset = 15
        advanced_operation = 8
        # v0.4b: 0.5 is the value that reproduces v0.3's 0.4-1.2 gain
        # range under the corrected mapping; v0.4's 0.6 did not.
        nonlinear_intensity = 0.5
        presetName$ = "RandAmpScatter"
    elsif preset = 16
        advanced_operation = 2
        nonlinear_intensity = 0.5
        presetName$ = "GeoProduct"
    elsif preset = 17
        advanced_operation = 4
        nonlinear_intensity = 0.5
        presetName$ = "VectorMorph"
    elsif preset = 18
        advanced_operation = 6
        # v0.4b: the preset kept v0.3's 0.0, but intensity is now the
        # weight on Sound 2, so 0.0 reduced the whole operation to
        # abs(S1) with Sound 2 doing nothing at all. 0.5 is the value
        # that reproduces v0.3's abs(S1) - abs(S2).
        nonlinear_intensity = 0.5
        presetName$ = "Rectify"
    endif
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 2
    exitScript: "Please select exactly 2 Sound objects."
endif

sound1 = selected("Sound", 1)
sound2 = selected("Sound", 2)

selectObject: sound1
name1$ = selected$("Sound")
sr1 = Get sampling frequency
dur1 = Get total duration
n_ch_1 = Get number of channels
start1 = Get start time

selectObject: sound2
name2$ = selected$("Sound")
sr2 = Get sampling frequency
dur2 = Get total duration
n_ch_2 = Get number of channels
start2 = Get start time

# Check sample rates match
if sr1 <> sr2
    exitScript: "Sample rates must match (S1: " + string$(sr1) + " Hz, S2: " + string$(sr2) + " Hz)"
endif

min_dur = min(dur1, dur2)

# v0.4 (item 6): v0.3 had no channel policy at all. The result was always
# a copy of Sound 1, so Sound 1 silently dictated the layout and the
# behaviour differed by combination - verified: stereo+mono broadcast the
# mono across both channels; 3ch+2ch left channel 3 processed against
# ZEROS (cells outside an object read as 0); mono+stereo discarded Sound
# 2's right channel entirely. None of this was documented, all of it
# depended on selection order, and for non-commutative operations
# (Divide, Subtract, Power mod) the asymmetry matters. It is now a stated
# choice, with the v0.3 behaviour as the default and a warning whenever
# the counts differ.
chanNote$ = ""
if channel_policy = 2
    if n_ch_1 <> n_ch_2
        exitScript: "Channel counts differ (S1: " + string$(n_ch_1) + ", S2: " + string$(n_ch_2)
            ... + "). Choose a different Channel_policy, or match the inputs."
    endif
    chanDesc$ = "matched (" + string$(n_ch_1) + " ch)"
elsif channel_policy = 3
    chanDesc$ = "both mixed to mono"
else
    chanDesc$ = "Sound 1 defines layout (" + string$(n_ch_1) + " ch)"
    if n_ch_1 <> n_ch_2
        if n_ch_2 = 1
            chanNote$ = "  NOTE: Sound 2 is mono and will be applied to all " + string$(n_ch_1) + " channels of Sound 1."
        elsif n_ch_2 > n_ch_1
            chanNote$ = "  NOTE: Sound 2 has " + string$(n_ch_2) + " channels but only its first " + string$(n_ch_1) + " are used; the rest are discarded."
        else
            chanNote$ = "  NOTE: Sound 1 has " + string$(n_ch_1) + " channels and Sound 2 only " + string$(n_ch_2) + "; the extra channels of Sound 1 are processed against SILENCE."
        endif
    endif
endif

# v0.4 (item 14): Random scatter draws randomUniform per sample but v0.3
# had no seed, so the operation was not reproducible - the reviewer got
# three different outputs from three identical runs.
if advanced_operation = 8
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably: random_seed
    else
        random_initializeSafelyAndUnpredictably()
    endif
endif

# === Info ===
writeInfoLine: "=== Math Operations v0.6.0 ==="
appendInfoLine: "Sound 1: ", name1$, " (", fixed$(dur1, 2), " s, ", n_ch_1, " ch)"
appendInfoLine: "Sound 2: ", name2$, " (", fixed$(dur2, 2), " s, ", n_ch_2, " ch)"
appendInfoLine: "Using duration: ", fixed$(min_dur, 2), " s"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: S1 ", n_ch_1, " ch, S2 ", n_ch_2, " ch -> ", chanDesc$
if chanNote$ <> ""
    appendInfoLine: chanNote$
endif
appendInfoLine: "Start times: S1 ", fixed$(start1, 3), " s, S2 ", fixed$(start2, 3), " s (each cut from its own start)"
appendInfoLine: ""

# === Extract Equal Parts ===
# v0.4 CRITICAL (item 2): v0.3 extracted 0..min_dur from BOTH Sounds,
# which assumes each one's time domain starts at 0. A Sound's start time
# is an independent property - a Sound extracted with times preserved can
# sit at 2 s or 5 s - and "Preserve times = no" only shifts the part
# AFTER it has been selected; it does not make 0 mean "the beginning of
# this object". Verified by the reviewer on two three-sample Sounds
# starting at 2 s and 5 s: the output was entirely silent, because
# 0..0.003 lies outside both. With one Sound at 0 and one at 5 s, only
# the first survived and the second became zeros - silently. Each Sound
# is now cut from its own start.
selectObject: sound1
Extract part: start1, start1 + min_dur, "rectangular", 1, "no"
sound1_part = selected("Sound")

selectObject: sound2
Extract part: start2, start2 + min_dur, "rectangular", 1, "no"
sound2_part = selected("Sound")

# v0.6 (crash fix): with "Sound 1 defines layout", a Sound 1 with MORE
# channels than a multichannel Sound 2 (e.g. 3ch + 2ch) made every
# object[sound2, row, col] read for row 3 hit an internal assertion -
# "Crashing bug: Praat will crash", and the process aborts. Verified on
# Praat 6.4.06, 6.4.63 and 7.0, for v0.5.1 as well. The NOTE above
# documents that the extra channels are processed against SILENCE; that
# is now what happens: Sound 2 is padded with silent channels. (A mono
# Sound 2 is broadcast by Praat itself and needs no padding.) Praat's
# formula `if` is lazy, so the missing rows are never read.
if channel_policy = 1 and n_ch_2 > 1 and n_ch_2 < n_ch_1
    selectObject: sound2_part
    padSamples = Get number of samples
    padDur = Get total duration
    padded = Create Sound from formula: "s2pad", n_ch_1, 0, padDur, sr2,
        ... "if row <= " + string$(n_ch_2) + " then object[" + string$(sound2_part) + ", row, col] else 0 fi"
    padCheck = Get number of samples
    removeObject: sound2_part
    sound2_part = padded
    if padCheck <> padSamples
        exitScript: "Internal error: channel padding changed the sample count (" + string$(padSamples) + " -> " + string$(padCheck) + ")."
    endif
endif

if channel_policy = 3
    if n_ch_1 > 1
        selectObject: sound1_part
        monoS1 = Convert to mono
        removeObject: sound1_part
        sound1_part = monoS1
    endif
    if n_ch_2 > 1
        selectObject: sound2_part
        monoS2 = Convert to mono
        removeObject: sound2_part
        sound2_part = monoS2
    endif
endif

# === Create Result ===
selectObject: sound1_part
Copy: name1$ + "_" + presetName$ + "_" + name2$
result = selected("Sound")

# Build object reference string
s2_str$ = string$(sound2_part)

# === CORE MATH PROCESSING ===
# Priority: Advanced > Nonlinear > Modulation > Basic
# Track which tier ran for visualization clarity
ranTier$ = "none"
ranLabel$ = "(no operation)"

selectObject: result

if advanced_operation > 1
    ranTier$ = "Advanced"
    depth_str$ = string$(nonlinear_intensity)
    
    if advanced_operation = 2
        ranLabel$ = "Geometric product (sqrt magnitudes)"
        # v0.4 (item 4): the 1e-10 floors were unnecessary - sqrt(0) is
        # perfectly defined - and they were harmful: on two silent inputs
        # the formula returned a small CONSTANT (1e-9), which the
        # following `Scale peak: 0.95` then multiplied up so that every
        # sample became 0.95. Digital silence came out as full-scale DC,
        # which is a loud thump on playback. The floors are gone.
        # (item 11): the result is a product of magnitudes and so is
        # always positive - a unipolar signal with substantial DC. The
        # sign of S1 is restored to keep it bipolar; set
        # Geometric_polarity to "unsigned" for the v0.3 shape.
        # v0.6: sqrt(|a|)*sqrt(|b|) = sqrt(|a*b|) - one sqrt instead of
        # two. Differs from v0.5.1 by rounding only (~1e-16 relative); the
        # product a*b could only underflow for |a*b| < 1e-308, far below
        # any audio sample.
        if geometric_polarity = 1
            ranLabel$ = ranLabel$ + " [signed by S1]"
            Formula: ~ ((self>0) - (self<0)) * sqrt(abs(self * object[sound2_part]))
        else
            ranLabel$ = ranLabel$ + " [unsigned]"
            Formula: ~ sqrt(abs(self * object[sound2_part]))
        endif
        appendInfoLine: "Applying: ", ranLabel$
    elsif advanced_operation = 3
        ranLabel$ = "Magnitude product (|S1| * |S2|)"
        # v0.4 (items 4 and 10): exp(ln a + ln b) is identically a*b, so
        # this was never an "exp domain" transform - it is the product of
        # the two magnitudes, verified exactly. Written directly, which
        # also removes the 1e-10 floors that made two silent inputs
        # produce a constant 1e-21 that `Scale peak` then lifted to
        # 0.95 DC.
        # v0.6: sgn(a)*|a|*|b| = a*|b| and |a|*|b| = |a*b| exactly in IEEE
        # arithmetic (the sign of a product is handled separately from its
        # rounding), so these are bit-identical to v0.5.1 with fewer
        # operations.
        if geometric_polarity = 1
            ranLabel$ = ranLabel$ + " [signed by S1]"
            Formula: ~ self * abs(object[sound2_part])
        else
            ranLabel$ = ranLabel$ + " [unsigned]"
            Formula: ~ abs(self * object[sound2_part])
        endif
        appendInfoLine: "Applying: ", ranLabel$
    elsif advanced_operation = 4
        # v0.4 (item 12): this is a linear crossfade only for intensity in
        # 0..1. Nonlinear_intensity is `positive` with no ceiling, so above
        # 1 it extrapolates and Sound 1's weight goes negative. Allowed,
        # but no longer silent.
        if nonlinear_intensity > 1
            appendInfoLine: "  NOTE: Vector morph with intensity ", fixed$(nonlinear_intensity, 2), " > 1 extrapolates - Sound 1's weight is negative (", fixed$(1 - nonlinear_intensity, 2), ")."
        endif
        ranLabel$ = "Vector morph (depth=" + fixed$(nonlinear_intensity, 2) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 - " + depth_str$ + ") + object[" + s2_str$ + "] * " + depth_str$
    elsif advanced_operation = 5
        # v0.6: in v0.4-v0.5.1 intensity set r in (S1+S2)*(r - r*|S1||S2|),
        # i.e. it only multiplied the whole output by r/3.5 - a gain that
        # peak normalization divides straight back out. It now sets the
        # fold-back depth k of the amplitude-dependent factor:
        #   out = (S1+S2) * 3.5 * (1 - k*|S1|*|S2|),   k = 2*intensity
        # k = 0 is a plain (scaled) sum, k = 1 (intensity 0.5) is exactly
        # the v0.3-v0.5.1 formula, and k > 1 makes the factor go negative
        # where |S1||S2| > 1/k, folding loud coincident peaks back through
        # zero - the x(1-x) hump of the logistic map. Memoryless, no
        # recursion; for inputs within +/-1 the output is bounded by
        # 7*max(1, k-1). The coefficient string is 3.5*k = 7*intensity,
        # so at intensity 0.5 the formula text, and the output, are the
        # same as v0.5.1.
        chaosK = 2 * nonlinear_intensity
        chaosC$ = string$(3.5 * chaosK)
        ranLabel$ = "Logistic-style shaping (non-recursive, r=3.5, k=" + fixed$(chaosK, 2) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "(self + object[" + s2_str$ + "]) * (3.5 - " + chaosC$ + " * abs(self) * abs(object[" + s2_str$ + "]))"
    elsif advanced_operation = 6
        # v0.4 (item 7): intensity was reported but unused. It now sets
        # how much of Sound 2's magnitude is subtracted; 0.5 doubled to 1
        # reproduces the v0.3 formula, so intensity 0.5 is unchanged.
        rectMix$ = string$(2 * nonlinear_intensity)
        ranLabel$ = "Rectify & mix (S2 weight " + fixed$(2 * nonlinear_intensity, 2) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "abs(self) - " + rectMix$ + " * abs(object[" + s2_str$ + "])"
    elsif advanced_operation = 7
        # v0.4 (items 7 and 9): renamed - there is no framing, spectrum,
        # phase estimate or overlap-add here; it is a sample-wise cross
        # waveshaper. Intensity now scales the shaping index instead of
        # being displayed while unused (0.5 gives the v0.3 constant 50).
        pvIndex$ = string$(100 * nonlinear_intensity)
        ranLabel$ = "Cross-phase waveshaper (index " + fixed$(100 * nonlinear_intensity, 1) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * cos(object[" + s2_str$ + "] * " + pvIndex$ + " * pi) + object[" + s2_str$ + "] * sin(self * " + pvIndex$ + " * pi)"
    elsif advanced_operation = 8
        # v0.4 (items 7, 9, 14): renamed - there are no grains, no grain
        # duration, no time displacement, density, overlap or windowing.
        # It is per-sample random amplitude modulation. Intensity now
        # sets the modulation depth (0.5 gives the v0.3 range 0.8-1.2),
        # and the run is reproducible when a seed is given.
        # v0.4b: I mis-read the v0.3 range twice. v0.3 was
        # 0.8 + 0.4*randomUniform(-1,1), and randomUniform(-1,1) spans
        # -1..+1, so the gain spanned 0.4..1.2 - NOT 0.8..1.2. The
        # mapping below gives exactly 0.4..1.2 at intensity 0.5, and the
        # preset is set to 0.5 so it reproduces v0.3.
        scatDepth$ = string$(0.8 * nonlinear_intensity)
        ranLabel$ = "Random amplitude scatter (gain 0.8 +/- " + fixed$(0.8 * nonlinear_intensity, 2) + ")"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.6: above intensity 1 the gain range 0.8*(1 +/- intensity)
        # includes negative values, so some samples are polarity-flipped.
        # Allowed (it is still per-sample random AM), but no longer silent.
        if nonlinear_intensity > 1
            appendInfoLine: "  NOTE: intensity ", fixed$(nonlinear_intensity, 2), " > 1 - the random gain spans ", fixed$(0.8 * (1 - nonlinear_intensity), 2), "..", fixed$(0.8 * (1 + nonlinear_intensity), 2), " and flips polarity on some samples."
        endif
        Formula: "(self + object[" + s2_str$ + "]) * (0.8 + " + scatDepth$ + " * randomUniform(-1, 1))"
    endif

elsif nonlinear_operation > 1
    ranTier$ = "Nonlinear"
    intensity_str$ = string$(nonlinear_intensity)
    
    if nonlinear_operation = 2
        ranLabel$ = "Cosine cross-waveshaper"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * cos(2 * pi * object[" + s2_str$ + "] * " + intensity_str$ + " * 100)"
    elsif nonlinear_operation = 3
        ranLabel$ = "AM depth control"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.6 note: this is the same expression as Modulation 9 (Tremolo)
        # with depth = intensity. Kept for menu-index compatibility.
        Formula: "self * (1 + object[" + s2_str$ + "] * " + intensity_str$ + ")"
    elsif nonlinear_operation = 4
        # v0.4 (item 11/12): the threshold used to be 0.5 + intensity, so
        # RAISING "intensity" produced LESS folding - the opposite of what
        # the name implies. Intensity now sets the fold amount directly and
        # the threshold falls as it rises.
        thresh = 1.0 / (0.5 + nonlinear_intensity)
        thresh_str$ = string$(thresh)
        sum$ = "(self + object[" + s2_str$ + "])"
        if fold_passes = 0
            # v0.6: closed-form triangle fold of x = S1+S2 into [-T, T],
            # the same transfer function as SC Fold.ar(x, -T, T) / sc_fold
            # and gen~ fold(x, -T, T):
            #   u = x + T;  m = u - 4T*floor(u / 4T);  out = T - |m - 2T|
            # m is u reduced to one fold period [0, 4T); T - |m - 2T| is the
            # triangle that runs -T -> T -> -T over that period, so
            # x = -T, 0, T, 2T, 3T map to -T, 0, T, 0, -T. It is continuous
            # (slope +/-1 everywhere, corners exactly at the thresholds),
            # odd-symmetric, branch-free, and bounded for ANY input - the
            # repeated reflection below only covers |x| <= (2N+1)T and lets
            # louder input through linearly. Where the reflection had
            # already folded completely the two agree (to rounding), so
            # the Wavefold preset is unchanged for inputs within +/-1.
            period$ = string$(4 * thresh)
            half$ = string$(2 * thresh)
            u$ = "(" + sum$ + " + " + thresh_str$ + ")"
            ranLabel$ = "Wavefold (complete, T=" + fixed$(thresh, 3) + ")"
            appendInfoLine: "Applying: ", ranLabel$
            Formula: thresh_str$ + " - abs(" + u$ + " - " + period$ + " * floor(" + u$ + " / " + period$ + ") - " + half$ + ")"
        else
            ranLabel$ = "Wavefold (" + string$(fold_passes) + " reflections, T=" + fixed$(thresh, 3) + ")"
            appendInfoLine: "Applying: ", ranLabel$
            sgnSum$ = "((" + sum$ + ">0) - (" + sum$ + "<0))"
            # v0.4 (item 12): a single reflection leaves anything past 3T
            # outside the threshold again, so this is repeated folding -
            # foldPasses reflections. v0.6 keeps it, bit-identical, as the
            # Fold_passes >= 1 option: |x| up to (2N+1)T is folded, and
            # anything louder leaves outside [-T, T].
            Formula: "if abs(" + sum$ + ") > " + thresh_str$ + " then 2 * " + thresh_str$ + " * " + sgnSum$ + " - " + sum$ + " else " + sum$ + " fi"
            for foldPass from 2 to fold_passes
                sgnSelf$ = "((self>0) - (self<0))"
                Formula: "if abs(self) > " + thresh_str$ + " then 2 * " + thresh_str$ + " * " + sgnSelf$ + " - self else self fi"
            endfor
        endif
    elsif nonlinear_operation = 5
        ranLabel$ = "Hard sync sim"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.4 (item 1): sign() is not a Praat function.
        s2ref$ = "object[" + s2_str$ + "]"
        sgnS2$ = "((" + s2ref$ + ">0) - (" + s2ref$ + "<0))"
        Formula: "if abs(" + s2ref$ + ") > abs(self) * " + intensity_str$ + " then " + sgnS2$ + " * abs(self) else self * " + s2ref$ + " fi"
    elsif nonlinear_operation = 6
        # v0.4 (items 7 and 8): `round(x*8)/8` sets a STEP of 1/8, which
        # is not 8 levels - verified, 17 distinct values over [-1,1] and
        # 33 over [-2,2], the actual range of a sum of two normalized
        # Sounds. The label is corrected, and Nonlinear_intensity now
        # drives the step size instead of being displayed while doing
        # nothing (intensity 0.5 reproduces the v0.3 step of 1/8).
        # v0.6 (direction): v0.4's N = round(16*intensity) made MORE
        # intensity give a FINER step, i.e. less quantization - the same
        # inverted sense v0.4 already corrected for Wavefold. Now
        # N = round(4/intensity): 0.5 -> 1/8 (unchanged, preset-safe),
        # 1 -> 1/4, 2 -> 1/2, 0.25 -> 1/16. Severity rises with intensity.
        # v0.6 (rounding): Praat's round(x) is floor(x + 0.5) - the same
        # rule as gen~'s quant macro and SC's round - which sends -1.5 to
        # -1 but +1.5 to 2, so the quantizer was not odd-symmetric at exact
        # half-steps (which 16-bit sources do hit). It is now
        # sgn(x)*floor(|x|*N + 0.5)/N, rounding half away from zero, so
        # q(-x) = -q(x) for every x. Still mid-tread: 0 is a level, so
        # silence stays silence. No sample-rate reduction (not a bitcrusher).
        crushSteps = round(4 / nonlinear_intensity)
        if crushSteps < 1
            crushSteps = 1
        endif
        crush_str$ = string$(crushSteps)
        ranLabel$ = "Quantize to 1/" + crush_str$ + " steps"
        appendInfoLine: "Applying: ", ranLabel$
        # Written as an if/else rather than sgn(x)*floor(|x|*N + 0.5)/N:
        # same values bit-for-bit, but x = S1+S2 is evaluated twice instead
        # of three times (measured 0.25 s vs 0.36 s on 30 s of stereo;
        # v0.5.1's asymmetric round() took 0.14 s).
        qx$ = "(self + object[" + s2_str$ + "])"
        Formula: "if " + qx$ + " < 0 then -floor(0.5 - " + qx$ + " * " + crush_str$ + ") / " + crush_str$
            ... + " else floor(" + qx$ + " * " + crush_str$ + " + 0.5) / " + crush_str$ + " fi"
    elsif nonlinear_operation = 7
        ranLabel$ = "Amplitude-dependent blend"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 - " + intensity_str$ + " * abs(object[" + s2_str$ + "])) + object[" + s2_str$ + "] * " + intensity_str$
    elsif nonlinear_operation = 8
        ranLabel$ = "Soft normalized mix"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "(self + object[" + s2_str$ + "]) / (1 + " + intensity_str$ + " * (abs(self) + abs(object[" + s2_str$ + "])))"
    endif

elsif modulation_operation > 1
    ranTier$ = "Modulation"
    mod_str$ = string$(modulation_depth)
    
    if modulation_operation = 2
        ranLabel$ = "AM unipolar (sin)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (0.5 + 0.5 * sin(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 3
        ranLabel$ = "AM unipolar (cos)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (0.5 + 0.5 * cos(object[" + s2_str$ + "] * pi * 10 * " + mod_str$ + "))"
    elsif modulation_operation = 4
        ranLabel$ = "FM-like (sin)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 5
        ranLabel$ = "FM-like (cos)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "cos(self * pi * 5 * " + mod_str$ + ") * object[" + s2_str$ + "]"
    elsif modulation_operation = 6
        ranLabel$ = "Double sine waveshaping"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "sin(self * pi * 5 * " + mod_str$ + ") * sin(object[" + s2_str$ + "] * pi * 5 * " + mod_str$ + ")"
    elsif modulation_operation = 7
        ranLabel$ = "Soft clip (arctan)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "(2/pi) * arctan((self * object[" + s2_str$ + "]) * 10 * " + mod_str$ + ")"
    elsif modulation_operation = 8
        # v0.4b: the menu previously advertised the unclamped
        # expression, but max(exponent, 0.05) means negative exponents
        # never happen - S1=0.5, S2=-1, depth=2 gives 0.5^0.05 = 0.9659,
        # not the 0.5^-1 = 2 the label implied. This is clamped power
        # waveshaping and is now named that way. Allowing negative
        # exponents would reintroduce the 0^-1 blow-up the clamp exists
        # to prevent, so the clamp stays and the label changes.
        ranLabel$ = "Clamped power waveshaping (exponent >= 0.05)"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.4 (items 1 and 13): sign() is not a Praat function; the
        # exponent is 1 + S2*depth (the menu used to say S1^(S2/2)).
        # v0.6: v0.5.1 also floored the BASE at 1e-6. Because the exponent
        # is already clamped to >= 0.05, |S1|^e is defined for every |S1|
        # including 0 (0^0.05 = 0), so the floor protected nothing - but
        # it created a plateau: every 0 < |S1| < 1e-6 came out as
        # +/-(1e-6)^e, which is +/-0.501 at e = 0.05, while |S1| = 0 gave 0.
        # A near-silent sample therefore jumped to half scale. Removed.
        # The result is SC's sign-preserving pow (sc_pow: "pow(a, b),
        # retaining the sign of a"), continuous at 0 for every exponent
        # >= 0.05. Small exponents are still very steep near zero
        # (0.001^0.05 = 0.71) - that is the transfer function, not a bug.
        sgnSelf$ = "((self>0) - (self<0))"
        expo$ = "(1 + object[" + s2_str$ + "] * " + mod_str$ + ")"
        Formula: sgnSelf$ + " * (abs(self) ^ max(" + expo$ + ", 0.05))"
    elsif modulation_operation = 9
        ranLabel$ = "Tremolo"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: "self * (1 + object[" + s2_str$ + "] * " + mod_str$ + ")"
    endif

else
    ranTier$ = "Basic"
    if operation = 1
        ranLabel$ = "Add"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self + object[sound2_part]
    elsif operation = 2
        ranLabel$ = "Subtract"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self - object[sound2_part]
    elsif operation = 3
        ranLabel$ = "Multiply (Ring Mod)"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ self * object[sound2_part]
    elsif operation = 4
        ranLabel$ = "Divide"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.4 (item 3): `self / (S2 + 1e-10)` is not a divide-by-zero
        # guard. It shifts the denominator's zero from 0 to -1e-10, so
        # S2 = -1e-10 gives an exact division by zero and a NaN that
        # survives normalization and is not caught by the peak report;
        # S2 = 0 gives 5e9; S2 = 1e-12 gives 4.95e9. The guard now tests
        # the MAGNITUDE of the denominator and substitutes a defined
        # value, so the zero stays where it is and no sample can blow up.
        # v0.4b: `<` meant Divide_epsilon = 0 turned the guard off
        # entirely - abs(0) < 0 is false - so an exact zero divided and
        # returned NaN again. The field is `positive` now and the test
        # is `<=`, so an exact zero is caught whatever the setting.
        # v0.6 review, NOT changed: inside the guard band the output is 0,
        # just outside it is S1/S2 ~ +/-S1/eps, so there is a jump of up to
        # |S1|/eps at |S2| = eps. Two alternatives were measured and
        # rejected. Clamping the denominator to sgn(S2)*max(|S2|, eps)
        # only moves the jump to the zero crossing of S2 and doubles it.
        # Tikhonov regularisation S1*S2/(S2^2 + eps^2) is continuous, but
        # it is no longer the quotient: 1% low at |S2| = 10*eps, 50% low
        # at |S2| = eps. gen~'s safediv is narrower still (0 only when the
        # denominator is exactly 0). Exact division outside the band is
        # the operation's identity, so the guard stays as it is.
        Formula: "if abs(object[" + s2_str$ + "]) <= " + divEps$ + " then 0 else self / object[" + s2_str$ + "] fi"
    elsif operation = 5
        ranLabel$ = "Average"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ (self + object[sound2_part]) / 2
    elsif operation = 6
        ranLabel$ = "Minimum"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ min(self, object[sound2_part])
    elsif operation = 7
        ranLabel$ = "Maximum"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ max(self, object[sound2_part])
    elsif operation = 8
        ranLabel$ = "Absolute difference"
        appendInfoLine: "Applying: ", ranLabel$
        Formula: ~ abs(self - object[sound2_part])
    elsif operation = 9
        ranLabel$ = "XOR-like (sign mixing)"
        appendInfoLine: "Applying: ", ranLabel$
        # v0.6: v0.5.1 tested `S1*S2 < 0`, so an exact zero in EITHER input
        # counted as "same sign" and returned +(|S1|+|S2|)/2. With Sound 1
        # digitally silent, the output was +|S2|/2 - a full-wave-rectified
        # Sound 2 with a large positive DC - and q(-S1,S2) = -q(S1,S2)
        # failed at S1 = 0. The three-valued sign (SC `sign`, gen~ `sign`:
        # 0 at 0) makes a zero input give 0. Bit-identical wherever both
        # inputs are nonzero. Written as v0.5.1's test plus an explicit zero
        # branch, which gives the same values as
        # sgn(S1)*sgn(S2)*(|S1|+|S2|)/2 at 0.28 s instead of 0.37 s on
        # 30 s of stereo (v0.5.1: 0.22 s).
        Formula: ~ if self * object[sound2_part] < 0 then -(abs(self) + abs(object[sound2_part])) / 2 else if self = 0 or object[sound2_part] = 0 then 0 else (abs(self) + abs(object[sound2_part])) / 2 fi fi
    endif
endif

# === POST PROCESSING ===
selectObject: result

# v0.4 (item 5): v0.3 multiplied by Output_scaling and then ran
# `Scale peak: 0.95`, which divides any positive scalar straight back
# out - verified, 0.5 and 2.0 produced byte-identical samples. The
# parameter was in the form, in the report, and connected to nothing.
# Output_mode makes the order explicit: Normalize (v0.3 default, and it
# says outright that the scaling is inert), Normalize-then-gain (so the
# scaling survives), conditional attenuation, or Preserve.
if output_mode = 4
    if output_scaling <> 1.0
        scale_str$ = string$(output_scaling)
        Formula: "self * " + scale_str$
    endif
    normStr$ = "preserve (scaling " + fixed$(output_scaling, 3) + " applied)"
elsif output_mode = 3
    if output_scaling <> 1.0
        scale_str$ = string$(output_scaling)
        Formula: "self * " + scale_str$
    endif
    prePeak = Get absolute extremum: 0, 0, "None"
    if prePeak > 0.95
        Scale peak: 0.95
        # v0.4b: this is not a limiter in the DSP sense - `Scale peak`
        # attenuates the WHOLE signal when any single sample exceeds the
        # target, rather than acting only on the peaks.
        normStr$ = "attenuated to 0.95 (scaling " + fixed$(output_scaling, 3) + " applied first)"
    else
        normStr$ = "unchanged, below 0.95 (scaling " + fixed$(output_scaling, 3) + " applied)"
    endif
elsif output_mode = 2
    prePeak = Get absolute extremum: 0, 0, "None"
    if prePeak > 0
        Scale peak: 0.95
    endif
    if output_scaling <> 1.0
        scale_str$ = string$(output_scaling)
        Formula: "self * " + scale_str$
    endif
    normStr$ = "normalized to 0.95, then x" + fixed$(output_scaling, 3)
else
    if output_scaling <> 1.0
        scale_str$ = string$(output_scaling)
        Formula: "self * " + scale_str$
    endif
    prePeak = Get absolute extremum: 0, 0, "None"
    if prePeak > 0
        Scale peak: 0.95
        normStr$ = "normalized to 0.95"
    else
        normStr$ = "silent - normalization skipped"
    endif
    if output_scaling <> 1.0
        appendInfoLine: "  NOTE: Output_scaling of ", fixed$(output_scaling, 3), " has NO effect in Normalize mode - peak normalization divides any positive scalar back out. Use mode 2 to keep it."
    endif
endif

# v0.5.1: report controls that actually affect the selected operation.
# Keep this compact so the visualization explains the running transform
# rather than listing inactive form fields.
# v0.6: removed the `intensityUsed$` flag (computed, never displayed since
# v0.5.1), and each line now says what the control does for the
# operation that ran - "Mod depth" scales an angle index for six of the
# eight modulation operations, not an AM depth.
activeParam1$ = "(none)"
activeParam2$ = ""
activeParam3$ = "Channel policy: " + chanDesc$

if ranTier$ = "Modulation"
    activeParam1$ = "Mod depth: " + fixed$(modulation_depth, 3)
    if modulation_operation = 2 or modulation_operation = 3
        activeParam2$ = "(S2 angle index 10 pi x depth; AM depth fixed 100 pct)"
    elsif modulation_operation = 4 or modulation_operation = 5
        activeParam2$ = "(S1 angle index 5 pi x depth)"
    elsif modulation_operation = 6
        activeParam2$ = "(both angle indices 5 pi x depth)"
    elsif modulation_operation = 7
        activeParam2$ = "(drive into arctan: 10 x depth)"
    elsif modulation_operation = 8
        activeParam2$ = "(exponent 1 + S2 x depth, floored at 0.05)"
    else
        activeParam2$ = "(gain 1 + S2 x depth)"
    endif
elsif ranTier$ = "Nonlinear"
    activeParam1$ = "Intensity: " + fixed$(nonlinear_intensity, 3)
    if nonlinear_operation = 4
        if fold_passes = 0
            activeParam2$ = "Fold: complete, T = " + fixed$(thresh, 3)
        else
            activeParam2$ = "Fold: " + string$(fold_passes) + " reflections (v0.5.1), T = " + fixed$(thresh, 3)
        endif
    elsif nonlinear_operation = 6
        activeParam2$ = "Step 1/" + crush_str$ + " (step = intensity / 4, rounded)"
    endif
elsif ranTier$ = "Advanced"
    if advanced_operation = 2 or advanced_operation = 3
        if geometric_polarity = 1
            activeParam1$ = "Polarity: sign of Sound 1"
        else
            activeParam1$ = "Polarity: unsigned magnitude"
        endif
    else
        activeParam1$ = "Intensity: " + fixed$(nonlinear_intensity, 3)
        if advanced_operation = 5
            activeParam2$ = "Fold-back depth k = " + fixed$(chaosK, 3) + " (k = 2 x intensity)"
        elsif advanced_operation = 8
            if random_seed > 0
                activeParam2$ = "Random seed: " + string$(random_seed)
            else
                activeParam2$ = "Random seed: unpredictable"
            endif
        endif
    endif
else
    if operation = 4
        activeParam1$ = "Divide epsilon: " + fixed$(divide_epsilon, 6)
    endif
endif

activeSummary$ = activeParam1$
if activeParam2$ <> ""
    activeSummary$ = activeSummary$ + "; " + activeParam2$
endif

# === Final stats ===
selectObject: result
finalDur = Get total duration
finalPeak = Get absolute extremum: 0, 0, "None"
n_ch_result = Get number of channels

# v0.4 (item 15): the result panel draws only channels 1 and 2 but
# labelled anything non-mono chanLegend$, so a 4-channel result
# looked like stereo with two channels simply missing.
if n_ch_result = 1
    chanLegend$ = "(mono)"
elsif n_ch_result = 2
    chanLegend$ = "(blue=ch1  orange=ch2)"
else
    chanLegend$ = "(channels 1-2 of " + string$(n_ch_result) + " shown)"
endif

appendInfoLine: ""
appendInfoLine: "Output: ", fixed$(finalDur, 2), " s, ", n_ch_result, " ch"
appendInfoLine: "Level: ", normStr$
appendInfoLine: "Measured peak: ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif
if finalPeak = undefined
    appendInfoLine: "  WARNING: the output contains undefined samples (NaN). Check the operation's inputs."
endif
if advanced_operation = 8
    if random_seed > 0
        appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
    else
        appendInfoLine: "Random seed: none (this run is NOT reproducible)"
    endif
endif

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization
    pageHeight = 8.0
    Line width: 1
    Colour: "Black"
    Solid line
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Math Operations Between Sounds v0.6.0##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... name1$ + "  o  " + name2$
        ... + "  |  " + presetName$
        ... + "  |  Tier: " + ranTier$
        ... + "  |  Op: " + ranLabel$
        ... + "  |  Duration: " + fixed$(min_dur, 2) + " s"
    
    # ----------------------------------------------------------
    # PANEL A: OPERATION DIAGRAM  (left, headline)
    # S1 + S2 -> [operation] -> Out
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    Axes: 0, 4, 0, 4
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 4, 0, 4
    
    # Sound 1 box (top left)
    Paint rectangle: "{0.65, 0.85, 0.65}", 0.30, 1.30, 2.50, 3.30
    Colour: "Black"
    Font size: 7
    Text: 0.80, "centre", 2.95, "half", "Sound 1"
    Font size: 6
    Colour: "{0.20, 0.40, 0.20}"
    Text: 0.80, "centre", 2.78, "half", name1$
    Text: 0.80, "centre", 2.65, "half", "(" + fixed$(dur1, 2) + " s, " + string$(n_ch_1) + " ch)"
    
    # Sound 2 box (bottom left)
    Paint rectangle: "{0.65, 0.65, 0.85}", 0.30, 1.30, 0.70, 1.50
    Colour: "Black"
    Font size: 7
    Text: 0.80, "centre", 1.20, "half", "Sound 2"
    Font size: 6
    Colour: "{0.15, 0.20, 0.45}"
    Text: 0.80, "centre", 1.03, "half", name2$
    Text: 0.80, "centre", 0.88, "half", "(" + fixed$(dur2, 2) + " s, " + string$(n_ch_2) + " ch)"
    
    # Operation box (center)
    Paint rectangle: "{0.85, 0.75, 0.80}", 1.65, 2.65, 1.50, 2.50
    Colour: "Black"
    Font size: 7
    Text: 2.15, "centre", 2.20, "half", presetName$
    Font size: 6
    Colour: "{0.45, 0.20, 0.30}"
    Text: 2.15, "centre", 2.05, "half", "[" + ranTier$ + "]"
    Font size: 6
    Text: 2.15, "centre", 1.85, "half", ranLabel$
    
    # Result box (right)
    Paint rectangle: "{0.85, 0.65, 0.55}", 3.00, 4.00, 1.50, 2.50
    Colour: "Black"
    Font size: 7
    Text: 3.50, "centre", 2.20, "half", "Result"
    Font size: 6
    Colour: "{0.40, 0.20, 0.10}"
    Text: 3.50, "centre", 2.05, "half", "(" + fixed$(min_dur, 2) + " s)"
    Text: 3.50, "centre", 1.90, "half", "peak " + fixed$(finalPeak, 3)
    
    # Arrows
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1.5
    Draw arrow: 1.30, 2.85, 1.65, 2.20
    Draw arrow: 1.30, 1.15, 1.65, 1.80
    Draw arrow: 2.65, 2.00, 3.00, 2.00
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    
    # ----------------------------------------------------------
    # PANEL B: PARAMETER REPORT  (right, headline-height)
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    # Section: Operation
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Operation tier:"
    
    Font size: 7
    if ranTier$ = "Advanced"
        Colour: "{0.78, 0.30, 0.40}"
    elsif ranTier$ = "Nonlinear"
        Colour: "{0.78, 0.50, 0.30}"
    elsif ranTier$ = "Modulation"
        Colour: "{0.30, 0.55, 0.78}"
    else
        Colour: "{0.30, 0.55, 0.30}"
    endif
    Text: 0.10, "left", 0.84, "half", ranTier$
    
    Font size: 7
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.10, "left", 0.76, "half", ranLabel$
    
    # Section: Parameters (only controls active for this operation)
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.65, "half", "Active parameters:"
    
    Font size: 7
    Colour: "{0.30, 0.45, 0.78}"
    Text: 0.10, "left", 0.57, "half", activeParam1$
    if activeParam2$ <> ""
        Text: 0.10, "left", 0.50, "half", activeParam2$
    endif
    Text: 0.10, "left", 0.43, "half", "Output scale: " + fixed$(output_scaling, 2)
    Text: 0.10, "left", 0.36, "half", "Output mode: " + normStr$
    Text: 0.10, "left", 0.29, "half", activeParam3$
    
    # Section: Duration / channel counts
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.20, "half", "Duration alignment:"
    
    Font size: 7
    Colour: "{0.55, 0.55, 0.55}"
    Text: 0.10, "left", 0.13, "half", "S1: " + fixed$(dur1, 2) + " s / " + string$(n_ch_1) + " ch   S2: " + fixed$(dur2, 2) + " s / " + string$(n_ch_2) + " ch"
    Font size: 7
    Colour: "{0.40, 0.40, 0.40}"
    Text: 0.10, "left", 0.05, "half", "Used: " + fixed$(min_dur, 2) + " s from each object's own start"
    
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
    Text: 2.10, "centre", 7.30, "half", "Operation diagram"
    Text: 6.10, "centre", 7.30, "half", "Parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: INPUT WAVEFORMS  (S1 left half, S2 right half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 4.68, 5.55
    Select inner viewport: 0.60, 3.85, 4.75, 5.48
    
    selectObject: sound1_part
    s1Peak = Get absolute extremum: 0, 0, "None"
    if s1Peak < 0.001
        s1Peak = 0.001
    endif
    s1Amp = s1Peak * 1.15
    
    Axes: 0, min_dur, -s1Amp, s1Amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, min_dur, -s1Amp, s1Amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, min_dur, 0
    
    selectObject: sound1_part
    Colour: "{0.30, 0.65, 0.30}"
    Line width: 1
    Draw: 0, 0, -s1Amp, s1Amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Sound 1 (green)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    Select outer viewport: 4, 8, 4.68, 5.55
    Select inner viewport: 4.45, 7.70, 4.75, 5.48
    
    selectObject: sound2_part
    s2Peak = Get absolute extremum: 0, 0, "None"
    if s2Peak < 0.001
        s2Peak = 0.001
    endif
    s2Amp = s2Peak * 1.15
    
    Axes: 0, min_dur, -s2Amp, s2Amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, min_dur, -s2Amp, s2Amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, min_dur, 0
    
    selectObject: sound2_part
    Colour: "{0.30, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -s2Amp, s2Amp, "no", "Curve"
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Sound 2 (blue)"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: RESULT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.60, 7.70, 5.69, 6.48
    
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
    if n_ch_result = 1
        Colour: "{0.78, 0.40, 0.55}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    else
        Extract one channel: 1
        vCh1 = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1
        Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
        removeObject: vCh1
        
        if n_ch_result >= 2
            selectObject: result
            Extract one channel: 2
            vCh2 = selected("Sound")
            Colour: "{0.82, 0.45, 0.25}"
            Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
            removeObject: vCh2
        endif
    endif
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    if n_ch_result > 1
        Text top: "no", "Result  " + chanLegend$
    else
        Text top: "no", "Result (mono)"
    endif
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
        ... + "  S1: " + name1$ + "  o  S2: " + name2$
        ... + "  |  Tier: " + ranTier$
        ... + "  |  Op: " + ranLabel$
    
    Text: 0.02, "left", 0.28, "half",
        ... activeSummary$
        ... + "  |  Out scale: " + fixed$(output_scaling, 2)
        ... + "  |  " + normStr$
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

# === Cleanup ===
removeObject: sound1_part, sound2_part

# === Final Info ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Tier: ", ranTier$, "  |  Op: ", ranLabel$
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s, peak ", fixed$(finalPeak, 4)

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
