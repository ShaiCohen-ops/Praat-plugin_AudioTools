# ============================================================
# Praat AudioTools - Chaos_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Chaos Distortion. Multi-stage lo-fi pipeline:
#     1. Drive (level multiplier)
#     2. Wave folding (N reflection PASSES through +/-threshold;
#        not a periodic triangular fold - with high drive and a low
#        pass count a sample can finish outside the threshold)
#     3. Bit crushing (quantization)
#     4. Sample-rate reduction (band-limiting, or sample & hold for
#        true aliasing)
#     5. Optional uniform noise, position selectable
#     6. Output level stage
#   Five presets, plus manual control of every stage.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
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
#   - FIXED: sample & hold reported the REQUESTED rate, not the one
#     it runs at. The stage can only produce sr/N for whole N, so at
#     44.1 kHz the requested 85%, 50%, 40% and 99% all collapse to
#     hold 2 = 50% - asking for 85% quietly delivered 50%, and 40%
#     delivered MORE bandwidth than requested rather than less.
#     holdFactor is now resolved before anything is reported, the
#     rate and percentage derive from it everywhere (info, chain
#     panel, summary bar), and a note fires when the achievable
#     rate differs from the request by more than a point.
#   - FIXED: Fold_count was `natural`, which Praat restricts to
#     positive integers and so rejects 0 - the form's own "0 = none"
#     comment was unreachable and only a preset could set it. Now
#     `integer`, with a negative check.
#   - FIXED: the "above 100%" note was written with appendInfoLine
#     BEFORE the writeInfoLine banner, and writeInfoLine clears the
#     Info window - so it was erased before it could be read. Held
#     in a string and printed after the banner.
#   - The RNG is now seeded only when Add_noise is on, and
#     unpredictability is restored afterwards, so a seeded run no
#     longer determines the output of whatever runs next in the
#     same session.
#
# Changelog v0.4:
#   - FIXED (multichannel): after resampling, the result was read
#     back with `object[id, col]`. A Sound is a matrix where ROW is
#     the channel and col the sample, so the documented form is
#     object[id, row, col]; the two-argument version does not
#     select the current channel. Four of the five presets reduce
#     the sample rate, so this affected most stereo use. The read
#     is also now guarded against the resampled sound having a
#     different sample count after two rate conversions.
#   - RESOLVED the v0.2/v0.3 fold discrepancy. The v0.3 changelog
#     claimed bit-identical output while describing the change that
#     broke it: v0.2 ran two INDEPENDENT reflection tests per pass,
#     so a positive reflection overshooting past the negative
#     threshold was reflected again within the same pass; v0.3's
#     `else if` allows only one. At drive 3, threshold 0.7, one
#     fold, v0.2 gives +0.2 and v0.3 gives -1.6. Measured across
#     the full input range, though, the two CONVERGE once the fold
#     count absorbs the overshoot, and all five presets clear that
#     bar - they are identical under both algorithms. The
#     divergence is a Custom-mode matter (drive 4.5 with 2 folds
#     differs across 22% of the range, max 2.0). Both are kept as
#     labelled options; the transfer curve follows the choice.
#   - FIXED: the transfer curve drew the v0.2 two-`if` fold while
#     the audio ran the v0.3 `else if` - on the case above the
#     panel showed +0.2 against audio of -1.6. It now mirrors the
#     selected algorithm and quantizer exactly.
#   - FIXED: the +/-1.1 clamp on the drawn curve, which the audio
#     does not apply. Extent measured in a pre-pass, Y axis sized
#     to fit, range reported in the axis label.
#   - CORRECTED the bit-depth claim. `round(self * 2^N) / 2^N` sets
#     a STEP of 1/2^N with no bound on the span - over -1..+1 that
#     is 2*2^N + 1 distinct values (129 at 6 bits, not the reported
#     64), and folding can leave samples outside that range for
#     more still. The legacy quantizer now reports its step size
#     honestly, and Quantizer option 2 gives a genuine 2^N levels
#     across -1..+1 with clamping.
#   - CORRECTED the aliasing claim. Resample with precision > 1
#     uses sinc interpolation and anti-alias filters BEFORE
#     decimating, so the stage band-limits rather than aliasing.
#     Renamed accordingly, with Sample & hold added for those who
#     want real aliasing.
#   - FIXED the sample-rate reporting. v0.3 printed
#     round(sr * percent / 100) but clamped the rate to a 1000 Hz
#     floor during processing - at 44.1 kHz and 1% it reported
#     441 Hz and rendered 1000 Hz. Any percentage above 100 was
#     shown as an increased rate while nothing happened at all.
#     Everything now derives from the resolved effective rate.
#   - NEW Random_seed. The noise stage calls randomUniform but the
#     RNG was never seeded and no seed field existed, so Default,
#     Heavy Crush and Lo-Fi Glitch could not be reproduced.
#   - NEW Noise_position. Noise was always added last, so it was
#     full-rate, full-resolution, and neither quantized nor
#     band-limited - it did not sound as though it had been through
#     the same device. Default reproduces v0.3.
#   - Output_level replaces the Normalize boolean (preserve /
#     conditional limiter / normalize), with a peak warning on
#     preserve. Normalize remains the default.
#   - Fold_threshold is now a form field. It was hardcoded to 0.7
#     while the header promised full manual control.
#   - Noise_amount is `positive` rather than `real`; a negative
#     value made the call randomUniform(high, low).
#   - RENAMED preset "Clean Boost" -> "Mild Boost/Crush": it
#     applies 12-bit quantization and is not clean. Output object
#     name changes from _chaos_CleanBoost to _chaos_MildBoostCrush.
#
# Changelog v0.3:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v0.2
#     for the same form parameters. (Same operation order, same
#     fold threshold, same bit-crush quantization, same resample
#     dance, same noise math.)
#   - Speed: combined the two fold formulas into one if/elsif/else
#     branch. v0.2 ran 2 * fold_count formula passes; v0.3 runs
#     fold_count passes. Marginal speedup on the fold step.
#   - Form syntax modernized: optionmenu uses colon.
#   - Fixed inline if/then/else ternary in Info output (line was
#     "appendInfoLine: 'Noise: ', if add_noise then ... else ... fi"
#     — that's not reliable in Praat's script-level expression
#     context). Pre-computed the string instead.
#   - Modernized cross-Sound formula reference: 
#       Formula: ~ object[resampled]   ->   Formula: ~ object[<id>, col]
#     Same behavior, explicit indexing, doesn't depend on Praat
#     substituting script variables into formula strings.
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle
#       Panel A (headline, left): transfer function
#         (drive + fold + bit-crush composite)
#       Panel B (right): processing-chain diagram showing the
#         five stages with current values
#       Panel C: zoom comparison (original vs chaos, first 50ms)
#         — preserved from v0.2 because it shows quantization
#         steps and aliasing artifacts that are invisible in the
#         full-file waveform view
#       Panel D: output waveform with L/R channels distinguished
#       Panel E: summary stats bar
# Changelog v0.2:
#   - Fixed resampling bug (orphan objects)
#   - Fixed input check and selection syntax
#   - Added visualization
#   - Added info output
# ============================================================

form Chaos Distortion v0.5
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset: 1
        option Default (balanced)
        option Gentle Grit
        option Heavy Crush
        option Lo-Fi Glitch
        option Mild Boost/Crush
        option Custom (use settings below)
    
    comment === Drive & Folding ===
    positive Drive 3.0
    integer Fold_count 3
    comment (0 = none; each is ONE reflection pass, not a full fold)
    positive Fold_threshold 0.7
    optionmenu Fold_algorithm: 1
        option Single reflection per pass (v0.3)
        option Double reflection per pass (v0.2 legacy)
    
    comment === Bit Crushing ===
    natural Bit_crush 6
    comment (16 = CD quality, 4 = extreme)
    optionmenu Quantizer: 1
        option Step 1/2^N, unbounded (v0.2/v0.3)
        option True 2^N levels over -1..+1
    
    comment === Sample Rate ===
    positive Sample_rate_percent 30
    comment (100 = original, lower = narrower band)
    optionmenu Rate_reduction: 1
        option Band-limit (resample, anti-aliased)
        option Sample & hold (true aliasing)
    
    comment === Extras ===
    boolean Add_noise 1
    positive Noise_amount 0.03
    optionmenu Noise_position: 3
        option Before bit crush
        option Before rate reduction
        option After processing (v0.2/v0.3)
    integer Random_seed 0
    comment (0 = unpredictable, positive = reproducible)
    
    comment === Output ===
    optionmenu Output_level: 3
        option Preserve
        option Conditional limiter to 0.9
        option Normalize to 0.9
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# v0.4b (item 2): Fold_count was `natural`, which Praat restricts to
# positive integers - it rejects 0. So the form's own "0 = none" comment
# was unreachable, and only a preset could set fold_count = 0. It is now
# `integer`, which admits 0 but also negatives, hence this check.
if fold_count < 0
    exitScript: "Fold count must be zero or greater."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
duration = Get total duration
sr = Get sampling frequency
input_n_channels = Get number of channels

# === Apply Presets ===
if preset = 1
    # Default (balanced)
    drive = 3.0
    fold_count = 3
    fold_threshold = 0.7
    bit_crush = 6
    sample_rate_percent = 30
    add_noise = 1
    noise_amount = 0.03
    presetName$ = "Default"
elsif preset = 2
    # Gentle Grit
    drive = 1.6
    fold_count = 1
    fold_threshold = 0.7
    bit_crush = 8
    sample_rate_percent = 85
    add_noise = 0
    noise_amount = 0.001
    presetName$ = "GentleGrit"
elsif preset = 3
    # Heavy Crush
    drive = 4.5
    fold_count = 5
    fold_threshold = 0.7
    bit_crush = 4
    sample_rate_percent = 40
    add_noise = 1
    noise_amount = 0.05
    presetName$ = "HeavyCrush"
elsif preset = 4
    # Lo-Fi Glitch
    drive = 2.2
    fold_count = 2
    fold_threshold = 0.7
    bit_crush = 3
    sample_rate_percent = 20
    add_noise = 1
    noise_amount = 0.04
    presetName$ = "LoFiGlitch"
elsif preset = 5
    # v0.4: was "Clean Boost". It applies 12-bit quantization, so it is
    # not clean - renamed to say what it does. The output object name
    # changes from _chaos_CleanBoost to _chaos_MildBoostCrush.
    drive = 1.25
    fold_count = 0
    fold_threshold = 0.7
    bit_crush = 12
    sample_rate_percent = 100
    add_noise = 0
    noise_amount = 0.001
    presetName$ = "MildBoostCrush"
else
    presetName$ = "Custom"
endif

# Pre-compute the "Noise: ..." display string (replaces v0.2's
# inline ternary in appendInfoLine — not reliable in script-level
# expression context across Praat builds).
if add_noise
    noiseStr$ = "yes (" + fixed$(noise_amount, 3) + ")"
    if noise_position = 1
        noiseStr$ = noiseStr$ + ", before bit crush"
    elsif noise_position = 2
        noiseStr$ = noiseStr$ + ", before rate reduction"
    else
        noiseStr$ = noiseStr$ + ", after processing"
    endif
else
    noiseStr$ = "no"
endif

if fold_algorithm = 2
    foldAlgoName$ = "double reflection, v0.2 legacy"
else
    foldAlgoName$ = "single reflection"
endif

if rate_reduction = 2
    rateName$ = "sample & hold, aliasing"
else
    rateName$ = "band-limited"
endif

if quantizer = 2
    quantName$ = string$(2^bit_crush) + " levels"
else
    quantName$ = "step 1/" + string$(2^bit_crush)
endif

# v0.4 (item 6): the effective rate is resolved BEFORE anything is
# reported. v0.3 printed round(sr * percent / 100) but then clamped the
# rate to a 1000 Hz floor during processing, so at 44.1 kHz and 1% the
# report said 441 Hz while the audio was resampled to 1000 Hz. And any
# percentage above 100 was displayed as an increased rate while the
# `if sample_rate_percent < 100` guard meant nothing happened at all.
srReduce = 0
new_rate = sr
holdFactor = 1
rateWarning$ = ""

# v0.4b (item 3): this warning used to be written with appendInfoLine
# BEFORE the writeInfoLine banner below, and writeInfoLine clears the
# Info window - so the message was erased before the user ever saw it.
# It is held in a string and printed after the banner instead.
if sample_rate_percent > 100
    rateWarning$ = "  NOTE: Sample_rate_percent above 100 does nothing - the stage only reduces. Treating as 100%."
    sample_rate_percent = 100
endif
if sample_rate_percent < 100
    srReduce = 1
    new_rate = sr * (sample_rate_percent / 100)
    if new_rate < 1000
        new_rate = 1000
    endif
    new_rate = round(new_rate)
    if new_rate >= sr
        srReduce = 0
        new_rate = sr
    endif
endif

# v0.4b (item 1): sample & hold can only produce rates of sr/N for whole
# N, so the rate it actually runs at is NOT the requested new_rate. v0.4
# reported new_rate regardless. At 44.1 kHz the requested percentages
# 85, 50, 40 and 99 all collapse to holdFactor 2, i.e. 50% - so asking
# for 85% quietly delivered 50%, and 40% delivered MORE bandwidth than
# asked for, not less. holdFactor is now resolved here, before anything
# is reported, and the rate, the percentage, the info window, the chain
# panel and the summary bar all derive from it. (A phase-accumulator
# hold would hit arbitrary rates; the integer block size is kept because
# it is what produces the hard, quantized-in-time character of the
# effect.)
if srReduce and rate_reduction = 2
    holdFactor = round(sr / new_rate)
    if holdFactor < 2
        holdFactor = 2
    endif
    new_rate = sr / holdFactor
    if abs(new_rate / sr * 100 - sample_rate_percent) > 1
        rateWarning$ = rateWarning$ + newline$
            ... + "  NOTE: sample & hold runs at sr/N for whole N. Requested "
            ... + fixed$(sample_rate_percent, 0) + "%, nearest achievable is "
            ... + fixed$(new_rate / sr * 100, 1) + "% (hold " + string$(holdFactor) + " samples)."
    endif
endif

effectivePercent = new_rate / sr * 100

if srReduce
    srSummary$ = fixed$(effectivePercent, 0) + "% (" + string$(round(new_rate)) + " Hz, " + rateName$ + ")"
else
    srSummary$ = "100% (off)"
endif

# v0.4b (item 4): v0.4 seeded the generator unconditionally, including
# when Add_noise was off, and never restored it - so running this script
# with a seed left the RNG in a predictable state for whatever ran next.
# It is now seeded only when the noise stage will actually draw, and
# unpredictability is restored at the end of processing.
if add_noise
    if random_seed > 0
        random_initializeWithSeedUnsafelyButPredictably: random_seed
    else
        random_initializeSafelyAndUnpredictably()
    endif
endif

# === Info ===
writeInfoLine: "=== Chaos Distortion v0.5 ==="
if rateWarning$ <> ""
    appendInfoLine: rateWarning$
endif
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 2), " s, ", input_n_channels, " ch)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""
appendInfoLine: "Drive: ", fixed$(drive, 2)
appendInfoLine: "Fold: ", fold_count, " reflection pass(es) at +/-", fixed$(fold_threshold, 2), " [", foldAlgoName$, "]"

# v0.4 (item 4): v0.3 reported 2^N levels, but `round(self * 2^N) / 2^N`
# does not produce 2^N levels - it produces a STEP of 1/2^N with no
# bound on how many steps the signal spans. Over -1..+1 that is
# 2*2^N + 1 distinct values (129 at 6 bits, not 64), and after folding a
# sample can sit outside +/-1 and add more. The report now describes the
# step size for the legacy quantizer, and the Quantizer option offers a
# genuine 2^N-level mapping.
if quantizer = 2
    appendInfoLine: "Bit crush: ", bit_crush, " bits (", 2^bit_crush, " levels over -1..+1, clamped)"
else
    appendInfoLine: "Bit crush: ", bit_crush, " bits (step 1/", 2^bit_crush, "; ", 2*2^bit_crush + 1, " values over -1..+1, unbounded)"
endif

if srReduce
    if rate_reduction = 2
        appendInfoLine: "Sample rate: ", fixed$(effectivePercent, 1), "% (", fixed$(new_rate, 1), " Hz, hold ", holdFactor, " samples) [", rateName$, "]"
    else
        appendInfoLine: "Sample rate: ", fixed$(effectivePercent, 1), "% (", round(new_rate), " Hz) [", rateName$, "]"
    endif
else
    appendInfoLine: "Sample rate: 100% (no reduction)"
endif
appendInfoLine: "Noise: ", noiseStr$
if random_seed > 0
    appendInfoLine: "Random seed: ", random_seed, " (reproducible)"
else
    appendInfoLine: "Random seed: none (unpredictable)"
endif
appendInfoLine: ""

# ============================================================
# PROCESSING
# ============================================================

appendInfoLine: "Processing..."

selectObject: original
Copy: original_name$ + "_chaos_" + presetName$
result = selected("Sound")

# 1. Drive
appendInfoLine: "  Applying drive (", fixed$(drive, 2), "x)..."
selectObject: result
Formula: ~ self * drive

# 2. Wave folding
# v0.4 (item 2): the v0.3 changelog claimed the output was bit-identical
# to v0.2 while describing the change that broke it - v0.2 ran two
# INDEPENDENT reflection tests per pass, so a positive reflection that
# overshot past the negative threshold was reflected again in the same
# pass; v0.3's `else if` allows only one. With drive 3, threshold 0.7 and
# a single fold, v0.2 gives +0.2 and v0.3 gives -1.6. That said, the two
# converge once the fold count is high enough to absorb the overshoot,
# and ALL FIVE PRESETS clear that bar - measured over the full input
# range they are identical to within floating point. The divergence is a
# Custom-mode matter (drive 4.5 with 2 folds differs across 22% of the
# range, max 2.0). Both algorithms are kept as labelled options rather
# than one being declared correct.
#
# Note also that this is N reflection PASSES, not a periodic triangular
# wavefolder: with high drive and a low fold count a sample can finish
# outside +/-threshold. That is intended behaviour, not a shortfall.
if fold_count > 0
    appendInfoLine: "  Applying ", fold_count, " fold pass(es)..."
    for i from 1 to fold_count
        selectObject: result
        if fold_algorithm = 2
            Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold) else self fi
            Formula: ~ if self < -fold_threshold then -fold_threshold - (self + fold_threshold) else self fi
        else
            Formula: ~ if self > fold_threshold then fold_threshold - (self - fold_threshold)
                ... else if self < -fold_threshold then -fold_threshold - (self + fold_threshold)
                ... else self fi fi
        endif
    endfor
endif

# v0.4 (item "noise position"): v0.3 always added noise last, so the hiss
# was full-rate, full floating-point resolution, and neither quantized
# nor band-limited - it did not sound as though it had passed through the
# same lo-fi device as the signal. The position is now selectable;
# "After processing" is the default and reproduces v0.3.
if add_noise and noise_position = 1
    appendInfoLine: "  Adding noise (before bit crush)..."
    selectObject: result
    Formula: ~ self + randomUniform(-noise_amount, noise_amount)
endif

# 3. Bit crushing
appendInfoLine: "  Applying bit crush (", bit_crush, " bits)..."
levels = 2 ^ bit_crush
selectObject: result
if quantizer = 2
    # True 2^N levels across -1..+1. Clamps first, so anything the fold
    # left outside full scale is brought in rather than extending the
    # quantizer's range.
    Formula: ~ 2 * round((min(max(self, -1), 1) + 1) / 2 * (levels - 1)) / (levels - 1) - 1
else
    Formula: ~ round(self * levels) / levels
endif

if add_noise and noise_position = 2
    appendInfoLine: "  Adding noise (before rate reduction)..."
    selectObject: result
    Formula: ~ self + randomUniform(-noise_amount, noise_amount)
endif

# 4. Sample rate reduction
# v0.4 (item 5): the description called this "resample down + back up =
# aliasing", but Resample with a precision above 1 uses sinc
# interpolation and applies an anti-aliasing filter BEFORE decimating.
# The stage therefore removes content above the new Nyquist rather than
# folding it back down - it is band limiting, which is a perfectly good
# lo-fi effect but not aliasing. Sample & hold holds each sample across a
# block with no filtering, which does alias.
if srReduce
    if rate_reduction = 2
        appendInfoLine: "  Applying sample & hold (", fixed$(new_rate, 1), " Hz, hold ", holdFactor, ", true aliasing)..."
        selectObject: result
        # In-place Formula evaluates columns left to right, so a
        # backward `self[row, col - k]` read normally sees data this same
        # pass has already overwritten. It is safe here by construction:
        # each block LEADER (col where (col-1) mod holdFactor = 0) maps
        # to itself and is therefore unchanged, and the followers read
        # only their leader. Verified against a pristine-copy reference.
        Formula: ~ self[row, col - ((col - 1) mod holdFactor)]
    else
        appendInfoLine: "  Applying band limit (", round(new_rate), " Hz)..."
        selectObject: result
        Resample: round(new_rate), 50
        downsampled = selected("Sound")
        
        selectObject: downsampled
        Resample: sr, 50
        resampled = selected("Sound")
        
        # v0.4 CRITICAL (item 1): v0.3 read back with
        # `object[id, col]`. A Sound is a matrix object where row is the
        # CHANNEL and col is the sample, so the documented two-index form
        # is object[id, row, col]. The two-argument form does not select
        # the current channel, which made every preset with
        # Sample_rate_percent < 100 unsafe on stereo or multichannel
        # input - and four of the five presets reduce the rate.
        #
        # Resample can also return a different sample COUNT than the
        # original (rounding through two rate conversions), so the read
        # is guarded: past the end of the resampled sound, hold the last
        # available sample rather than reading out of bounds.
        selectObject: resampled
        nResampCols = Get number of samples
        resampledIdStr$ = string$(resampled)
        nColsStr$ = string$(nResampCols)
        selectObject: result
        Formula: "object[" + resampledIdStr$ + ", row, min(col, " + nColsStr$ + ")]"
        
        removeObject: downsampled, resampled
    endif
endif

# 5. Noise, default position
if add_noise and noise_position = 3
    appendInfoLine: "  Adding noise (after processing)..."
    selectObject: result
    Formula: ~ self + randomUniform(-noise_amount, noise_amount)
endif

# 6. Output level
# v0.4 (item 9): v0.3's Normalize boolean always scaled to 0.9, so Drive
# shaped the signal but never set its level, a very quiet source was
# lifted a long way, and the loudness difference between noise settings
# was flattened out. Normalize stays the default so v0.3 renders are
# reproducible.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"
appendInfoLine: "  Peak before output stage: ", fixed$(prePeak, 3)

if output_level = 1
    levelDesc$ = "preserved"
    if prePeak > 1.0
        appendInfoLine: "  WARNING: peak is ", fixed$(prePeak, 3), " - above 1.0 it will clip on playback or export."
    endif
elsif output_level = 2
    if prePeak > 0.9
        selectObject: result
        Scale peak: 0.9
        levelDesc$ = "limited to 0.9"
    else
        levelDesc$ = "unchanged"
    endif
else
    selectObject: result
    Scale peak: 0.9
    levelDesc$ = "normalized to 0.9"
endif
appendInfoLine: "  Output level: ", levelDesc$

# v0.4b (item 4): leave the generator unpredictable so a seeded run of
# this script does not silently determine the output of whatever runs
# next in the same Praat session.
if add_noise and random_seed > 0
    random_initializeSafelyAndUnpredictably()
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
    vizName$ = replace$(original_name$, "_", "\_ ", 0)
    Erase all
    
    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Chaos Distortion v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half",
        ... vizName$
        ... + "  |  " + presetName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Folds: " + string$(fold_count)
        ... + "  |  Bits: " + string$(bit_crush)
        ... + "  |  SR: " + srSummary$
        ... + "  |  Noise: " + noiseStr$
    
    # ----------------------------------------------------------
    # PANEL A: TRANSFER FUNCTION  (left, headline)
    # Composite of drive + fold + bit-crush.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4, 0.75, 4.60
    Select inner viewport: 0.60, 3.85, 0.95, 4.40
    
    levels_disp = 2 ^ bit_crush
    nPoints = 200
    yLim = 1.2
    for p from 0 to nPoints
        xs = -1.0 + (p / nPoints) * 2.0
        ys = xs * drive
        for f from 1 to fold_count
            if fold_algorithm = 2
                if ys > fold_threshold
                    ys = fold_threshold - (ys - fold_threshold)
                endif
                if ys < -fold_threshold
                    ys = -fold_threshold - (ys + fold_threshold)
                endif
            else
                if ys > fold_threshold
                    ys = fold_threshold - (ys - fold_threshold)
                elsif ys < -fold_threshold
                    ys = -fold_threshold - (ys + fold_threshold)
                endif
            endif
        endfor
        if quantizer = 2
            ys = 2 * round((min(max(ys, -1), 1) + 1) / 2 * (levels_disp - 1)) / (levels_disp - 1) - 1
        else
            ys = round(ys * levels_disp) / levels_disp
        endif
        if abs(ys) * 1.1 > yLim
            yLim = abs(ys) * 1.1
        endif
    endfor
    
    
    Axes: -1.2, 1.2, -yLim, yLim
    Paint rectangle: "{0.97, 0.97, 0.97}", -1.2, 1.2, -yLim, yLim
    
    # Grid
    Colour: "{0.85, 0.85, 0.88}"
    Line width: 1
    Draw line: -1.2, 0, 1.2, 0
    Draw line: 0, -yLim, 0, yLim
    
    # y=x reference (no shaping)
    Dotted line
    Colour: "{0.65, 0.65, 0.70}"
    Draw line: -1.2, -1.2, 1.2, 1.2
    Solid line
    
    # Fold threshold lines
    Colour: "{0.55, 0.78, 0.55}"
    Dotted line
    Draw line: -1.2, fold_threshold, 1.2, fold_threshold
    Draw line: -1.2, -fold_threshold, 1.2, -fold_threshold
    Solid line
    Font size: 6
    Colour: "{0.30, 0.55, 0.30}"
    Text: -1.15, "left", fold_threshold, "bottom", " ±" + fixed$(fold_threshold, 2) + " fold"
    
    # Draw transfer function
    # v0.4 (item 3): the curve used two independent `if` folds - the v0.2
    # algorithm - while the v0.3 audio used `else if`. On the reviewer's
    # case (drive 3, threshold 0.7, one fold) the panel drew +0.2 while
    # the audio produced -1.6. It now mirrors whichever fold algorithm
    # and quantizer are actually selected.
    # (item 10): the +/-1.1 value clamp is gone; the extent is measured
    # first and the Y axis sized to fit, since the audio has no such
    # clamp and Custom settings can exceed it easily.
    Colour: "{0.78, 0.50, 0.30}"
    Line width: 2
    
    # First point
    prev_x = -1.0
    prev_y = prev_x * drive
    for f from 1 to fold_count
        if fold_algorithm = 2
            if prev_y > fold_threshold
                prev_y = fold_threshold - (prev_y - fold_threshold)
            endif
            if prev_y < -fold_threshold
                prev_y = -fold_threshold - (prev_y + fold_threshold)
            endif
        else
            if prev_y > fold_threshold
                prev_y = fold_threshold - (prev_y - fold_threshold)
            elsif prev_y < -fold_threshold
                prev_y = -fold_threshold - (prev_y + fold_threshold)
            endif
        endif
    endfor
    if quantizer = 2
        prev_y = 2 * round((min(max(prev_y, -1), 1) + 1) / 2 * (levels_disp - 1)) / (levels_disp - 1) - 1
    else
        prev_y = round(prev_y * levels_disp) / levels_disp
    endif
    
    for p from 1 to nPoints
        curr_x = -1.0 + (p / nPoints) * 2.0
        curr_y = curr_x * drive
        for f from 1 to fold_count
            if fold_algorithm = 2
                if curr_y > fold_threshold
                    curr_y = fold_threshold - (curr_y - fold_threshold)
                endif
                if curr_y < -fold_threshold
                    curr_y = -fold_threshold - (curr_y + fold_threshold)
                endif
            else
                if curr_y > fold_threshold
                    curr_y = fold_threshold - (curr_y - fold_threshold)
                elsif curr_y < -fold_threshold
                    curr_y = -fold_threshold - (curr_y + fold_threshold)
                endif
            endif
        endfor
        if quantizer = 2
            curr_y = 2 * round((min(max(curr_y, -1), 1) + 1) / 2 * (levels_disp - 1)) / (levels_disp - 1) - 1
        else
            curr_y = round(curr_y * levels_disp) / levels_disp
        endif
        Draw line: prev_x, prev_y, curr_x, curr_y
        prev_x = curr_x
        prev_y = curr_y
    endfor
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Output (+/-" + fixed$(yLim, 2) + ")"
    Text bottom: "yes", "Input"
    
    # ----------------------------------------------------------
    # PANEL B: PROCESSING CHAIN DIAGRAM  (right, headline-height)
    # The five-stage pipeline shown explicitly with current values.
    # Preserved from v0.2 — it's the script's most distinctive viz.
    # ----------------------------------------------------------
    Select outer viewport: 4, 8, 0.75, 4.60
    Select inner viewport: 4.45, 7.70, 0.95, 4.40
    
    Axes: 0, 1, 0, 6
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 6
    
    # Five vertical boxes representing the pipeline stages
    # Each at y range [stage*1.0, stage*1.0+0.7] for stages 5..1 (top to bottom)
    
    # Stage 1: Drive
    yTop = 5.6
    yBot = 5.0
    Paint rectangle: "{0.85, 0.70, 0.55}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "1. DRIVE"
    Font size: 7
    Colour: "{0.30, 0.20, 0.10}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", fixed$(drive, 2) + " x"
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 5.0, 0.50, 4.7
    
    # Stage 2: Fold
    yTop = 4.6
    yBot = 4.0
    if fold_count > 0
        Paint rectangle: "{0.70, 0.85, 0.60}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "2. FOLD"
    Font size: 7
    if fold_count > 0
        Colour: "{0.20, 0.40, 0.15}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", string$(fold_count) + " x"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 4.0, 0.50, 3.7
    
    # Stage 3: Crush
    yTop = 3.6
    yBot = 3.0
    Paint rectangle: "{0.60, 0.70, 0.85}", 0.10, 0.90, yBot, yTop
    Colour: "Black"
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "3. CRUSH"
    Font size: 7
    Colour: "{0.10, 0.20, 0.40}"
    Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", string$(bit_crush) + " bits"
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 3.0, 0.50, 2.7
    
    # Stage 4: SR
    yTop = 2.6
    yBot = 2.0
    if srReduce
        Paint rectangle: "{0.60, 0.85, 0.75}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "4. SR REDUCE"
    Font size: 7
    if srReduce
        Colour: "{0.10, 0.40, 0.30}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", fixed$(effectivePercent, 0) + "%"
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
    endif
    
    # Arrow down
    Colour: "{0.45, 0.45, 0.45}"
    Draw arrow: 0.50, 2.0, 0.50, 1.7
    
    # Stage 5: Noise
    yTop = 1.6
    yBot = 1.0
    if add_noise
        Paint rectangle: "{0.85, 0.65, 0.60}", 0.10, 0.90, yBot, yTop
    else
        Paint rectangle: "{0.85, 0.85, 0.88}", 0.10, 0.90, yBot, yTop
    endif
    Colour: "Black"
    Font size: 7
    Text: 0.50, "centre", (yTop + yBot) / 2 + 0.10, "half", "5. NOISE"
    Font size: 7
    if add_noise
        Colour: "{0.40, 0.15, 0.10}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "+/- " + fixed$(noise_amount, 3)
    else
        Colour: "{0.55, 0.55, 0.55}"
        Text: 0.50, "centre", (yTop + yBot) / 2 - 0.13, "half", "off"
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
    Text: 2.10, "centre", 7.30, "half", "Transfer (drive + fold + crush)"
    Text: 6.10, "centre", 7.30, "half", "Processing chain"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM COMPARISON  (full width, first 50ms)
    # Original (gray) vs chaos (orange) overlaid. Reveals
    # quantization steps and aliasing artifacts that the
    # full-file waveform can't show.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.60, 7.70, 4.75, 5.48
    
    zoomDur = 0.05
    if zoomDur > duration
        zoomDur = duration
    endif
    
    selectObject: original
    origPeak = Get absolute extremum: 0, zoomDur, "None"
    selectObject: result
    resPeak = Get absolute extremum: 0, zoomDur, "None"
    zoomMax = origPeak
    if resPeak > zoomMax
        zoomMax = resPeak
    endif
    if zoomMax < 0.001
        zoomMax = 0.001
    endif
    zAmpViz = zoomMax * 1.15
    
    Axes: 0, zoomDur, -zAmpViz, zAmpViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -zAmpViz, zAmpViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Original (gray, behind)
    selectObject: original
    if input_n_channels > 1
        Extract one channel: 1
        zOrig = selected("Sound")
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zOrig
    else
        Colour: "{0.65, 0.65, 0.65}"
        Line width: 1
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    
    # Chaos (orange, on top)
    selectObject: result
    if nResultCh > 1
        Extract one channel: 1
        zRes = selected("Sound")
        Colour: "{0.78, 0.45, 0.20}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
        removeObject: zRes
    else
        Colour: "{0.78, 0.45, 0.20}"
        Line width: 1.3
        Draw: 0, zoomDur, -zAmpViz, zAmpViz, "no", "Curve"
    endif
    Line width: 1
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = original, orange = chaos)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full file)
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
        
        if nResultCh >= 2
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
    if nResultCh > 1
        Text top: "no", "Output (full file)  (blue=L  orange=R)"
    else
        Text top: "no", "Output (full file, mono)"
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
        ... + "  " + vizName$
        ... + "  |  Drive: " + fixed$(drive, 2)
        ... + "  |  Folds: " + string$(fold_count)
        ... + "  |  Crush: " + string$(bit_crush) + " bits (" + quantName$ + ")"
    
    Text: 0.02, "left", 0.28, "half",
        ... "SR: " + srSummary$
        ... + "  |  Noise: " + noiseStr$
        ... + "  |  Level: " + levelDesc$
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
appendInfoLine: "Peak: ", fixed$(finalPeak, 4)

if play_result
    selectObject: result
    Play
endif

selectObject: result
