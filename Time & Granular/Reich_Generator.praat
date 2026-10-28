# ============================================================
# Praat AudioTools - Reich Generator (Auto-Phasing Tool)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Reich Generator (Auto-Phasing Tool) -- extracts a loop from a
#   source recording and phases it against a pitch/tempo-drifting
#   copy (and an optional static anchor voice), Steve Reich style.
#   Dual Locked Loops mode (v0.7.0) loops two user-locked regions of the
#   same Sound as two independent single-voice units, one per stereo side;
#   the phasing is the changing relationship between the two units.
#
# Changelog v0.7.1 (2026) - random region suggestions in Dual Locked Loops:
#   - The Dual dialog now opens with a RANDOM pair of regions on every run
#     instead of the fixed 25% / 70% suggestion. Lengths are drawn uniformly
#     from the main form's Min_loop_sec .. Max_loop_sec (raw form values;
#     Classic presets do not apply), each capped at 45% of the source; A is
#     placed anywhere, B anywhere that does not overlap A; both must contain
#     signal (Classic's RMS floor). Values are whole milliseconds.
#   - Random_seed: 0 = new suggestion every run; any other value gives the
#     same suggestion every run (as in Classic). The generator is seeded only
#     for this draw and released to safe mode before the dialog opens.
#   - Suggestions remain suggestions: the user edits / confirms them and they
#     lock at Render. Rendering itself is unchanged and fully deterministic.
#   - If 200 attempts find no non-silent pair (e.g. a mostly silent source),
#     or the source is too short for random placement, the fixed suggestion
#     is used and the dialog says so.
#
# Changelog v0.7.0 (2026) - Dual Locked Loops architecture corrected:
#   v0.6.0 implemented Dual Locked Loops as TWO INDEPENDENT TWO-VOICE
#   PHASING PAIRS (A1 static + A2 drifting copy of Region A, B1 + B2 of
#   Region B): four voices, each region doubled against itself, so each side
#   of the stereo image was a self-phasing / flanging effect. That was not
#   the intended composition.
#   v0.7.0 replaces it with TWO INDEPENDENT SINGLE-VOICE LOOPING UNITS:
#     Unit A loops Region A, Unit B loops Region B -- one voice each,
#     L(t) = gAL*A(t) + gBL*B(t), R(t) = gAR*A(t) + gBR*B(t). No second copy
#     of either region exists anywhere in the Dual signal path.
#   Phasing is now the changing relationship BETWEEN the two units: one
#   relative loop phase frac(uB - uA), where u is each unit's position in
#   its own loop (fraction of a loop). Loop frequencies f = rate / loop
#   length; relative cycle = 1 / |fB - fA|; equal frequencies are reported
#   as stationary (no drift is drawn or claimed).
#   - Different region lengths are kept as they are (never stretched); at
#     100% / 100% they phase naturally against each other.
#   - New dialog fields: Dual_Timing (Independent Rates | Target Relative
#     Cycle), Dual_A_Rate_percent, Dual_B_Rate_percent (50-200%, errors
#     outside), Dual_Target_Cycle_min + Dual_Drift_Direction (B's rate is
#     derived from A's so that fB - fA = +-1/target; a derived rate outside
#     50-200% is an error, never clamped). Start offsets now mean the start
#     position inside each unit's OWN loop. Dual_B_Level_dB replaces
#     Dual_Pair_B_Level_dB.
#   - Removed from Dual: Dual_A_Cycle_min, Dual_B_Cycle_min,
#     Dual_Drift_Interval, Dual_Flutter_st (they described the drifting
#     copies). Dual mode now uses no random numbers at all.
#   - Rates are plain resampling: speed and pitch change together, like
#     tape (stated in the dialog and the Info window). A unit at 100% reads
#     its loop by index (exact); any other rate tiles the loop into one wall
#     and resamples the WHOLE wall once (the v0.6.0 sub-sample method), so
#     loop periods are exact with no rounding to whole samples.
#   - Stereo: A at -s, B at +s, equal-power. Default separation is now 100%:
#     left = Unit A only, right = Unit B only (gains below 1e-12 are set to
#     exactly 0 and their terms left out of the mix).
#   - Figure: ONE square wheel for the one relationship (angle = relative
#     loop phase, radius = output time: a spiral, or a radial line when
#     stationary), two lanes showing each unit's own loop position, the
#     source with both regions, the relative-phase trajectory over the whole
#     render, Summary. No unison / anti-phase labels: 0 deg means "same
#     fraction of their own loops", not acoustic alignment.
#   - Single (Classic) is unchanged: bit-identical seeded output and a
#     pixel-identical figure against v0.5.0 / v0.6.0.
#
# Changelog v0.6.0 (2026) - Dual Locked Loops:
#   NEW MODE. The form gains one selector at the top, Mode:
#     Single (Classic)   -- the default; everything below behaves exactly as
#                           in v0.5.0 (same presets, random loop pick, V2/V3
#                           processing, offsets, make_wall, mix, naming,
#                           seed policy and phase-wheel figure).
#     Dual Locked Loops  -- opens a second dialog (pause form) with its own
#                           settings, so the main form grows by one row only.
#   API NOTE: Mode is the FIRST form field, so a caller that drives this
#   script with positional runScript arguments must now prepend
#   "Single (Classic)". No other public parameter changed.
#
#   Dual Locked Loops renders two independent two-voice phasing processes
#   from two user-locked regions of the same Sound:
#     A1 static / A2 drifting (Region A, left group)
#     B1 static / B2 drifting (Region B, right group)
#   - Regions: the dialog is pre-filled with two distinct, non-overlapping
#     regions derived deterministically from the source length (A around
#     25% of the source, B around 70%). They are suggestions; the user edits
#     and confirms them with Render, and they are never replaced afterwards.
#     Validation happens before any object is created: inside the Sound,
#     end > start, at least 0.100 s long, no overlap (touching is allowed).
#     Sources shorter than 0.200 s are refused. Cancel creates nothing.
#   - Boundaries snap to a zero crossing only if one lies within 15 ms
#     INSIDE the region, so snapping can never leave the source or make the
#     regions overlap. Snapped bounds are recorded for the figure/Summary.
#   - Same cancellation-safe mono analysis as Classic (strongest channel
#     when the channel average nearly cancels).
#   - Each drifting voice uses the Classic drift law on its OWN loop and
#     cycle: r = 1 + loop / cycle (= Classic (n+1)/n), with the same PSOLA
#     interval + multiplicative-semitone flutter and empty-PitchTier note.
#   - SUB-SAMPLE DRIFT (review fix). The drifting voice is not a resampled
#     loop repeated whole: that makes its length an integer number of
#     samples, and the per-repeat shortening is only ~sr * L^2 / T samples
#     (0.24 samples for a 0.095 s loop and a 5 min cycle at 8 kHz), so the
#     rounding distorted short-loop / long-cycle settings by tens of percent
#     or removed the drift entirely (equal lengths, undefined cycle).
#     Instead the processed loop is tiled into a wall at the native rate and
#     the rate change is applied ONCE to the whole wall (Override sampling
#     frequency + sinc Resample, precision 50). The drifting period is then
#     exactly loop / r, the realised cycle equals the requested cycle for
#     any loop length, cycle and sample rate, and the start offset is exact
#     to a sub-sample residue that is carried into the phase origin.
#     A 50 ms pre-roll keeps the sinc filter's edge outside the render.
#   - Every voice is read by sample index into one 2-channel buffer of
#     exactly round(Total_Duration_min * 60 * sr) samples: static voices as
#     object[loop, ((col - 1) mod n) + 1], drifting voices from their stream
#     at col + p0. Offsets are applied inside the stream, so the render is
#     never shortened. Classic keeps make_wall unchanged.
#   - Equal-power panning (angle = (pan + 1) * pi / 4), summed directly into
#     the stereo buffer in a single Formula; no Combine-to-stereo/averaging.
#     Pan positions are static and follow a continuous, monotonic two-segment
#     map of Stereo separation: 0% all at centre, 65% -85/-45 | +45/+85,
#     100% -100/-60 | +60/+100. Groups never cross the centre line.
#   - Pair B level (dB) scales B1 and B2 equally; voices are otherwise not
#     normalised individually. One Scale peak 0.99 on the finished mix.
#   - Seed policy as in Classic: seeded only while flutter draws happen,
#     then returned to safe/unpredictable mode, also on every error path.
#   - Output: <source>_ReichGen_Dual, 2 channels, left selected.
#   - Figure: two square 3.30 x 3.30 in phase wheels side by side (explicit
#     inner viewports), source waveform with both locked regions, both
#     relative-phase trajectories on one time axis (gaps at wraps), Summary.
#     Every phase value uses the loop lengths, rate ratios and offsets of
#     the audio engine; wrap counts are computed analytically from them.
#     The End label sits on the end dot's own radius (inside the path on
#     its outer lobe, outside it near the centre), so it cannot lie on the
#     path; the Summary drops repeated values to keep its lines short.
#   - Removed the unreachable v0.4 Section 8 drawing block (it was guarded by
#     "if create_polar_phase_wheel and 0"). No effect on Classic output,
#     verified by bit-identical seeded renders against v0.5.0.
#   - The Dual engine is a set of procedures between "DUAL ENGINE BEGIN/END"
#     markers; the headless test harness includes exactly that block, so
#     tests exercise the shipped rendering code, not a copy.
#
# Changelog v0.5.0 (2026) - measured proportion pass (visualization only):
#   ROOT CAUSE of the layout that v0.4.5 - v0.4.8 kept failing to fix: the
#   phase wheel set only its OUTER viewport and let Praat supply the inner
#   margins. Those defaults are NOT symmetric - 1.1667 in total horizontally
#   against 0.7778 in total vertically. A 5.40 x 5.40 outer viewport therefore
#   produced a 4.233 x 4.622 inner viewport, and the wheel was drawn as an
#   ELLIPSE, 8.4% narrower than tall. Every earlier version resized the outer
#   viewport, which cannot help, because the distortion is in the margins.
#   (Measured from Praat EPS output, not estimated.)
#
#   - FIXED: the wheel now sets its inner viewport explicitly and squarely
#     (1.85-6.15 x 0.48-4.78 = 4.30 x 4.30 in). Verified from the EPS: the
#     drawn wheel spans 3.956 x 3.956 in, aspect exactly 1.0000, centred on
#     the canvas centre line at x = 4.000.
#   - Reading order is now title -> phase wheel -> source waveform ->
#     relative phase trajectory -> summary: the wheel sits directly under the
#     title, and the waveform is context read after it rather than before it.
#   - Vertical budget now states the intended hierarchy instead of implying it:
#     wheel 4.30 in, trajectory 0.92 in, source waveform 0.62 in, summary 0.44
#     in, all inside the library's standard 8.00 x 7.58 in page. Wheel :
#     trajectory = 4.7 : 1. Previously the trajectory got 0.41 in, in which a
#     360-degree range left the 0/90/180/270/360 rows 0.09 in apart with their
#     labels inside the plot, on top of the curve; and the source strip got
#     0.22 in, which is not a waveform, it is a texture.
#   - The trajectory legend moved into the panel's title band. In a 0.92 in
#     panel an in-plot note line either overlaps the curve or forces the
#     y-range wider than the data it shows.
#   - The Source strip's rotated left label is placed explicitly rather than
#     with "Text left: yes", so it lines up with the trajectory panel's left
#     label below it. Praat's far-text distance depends on the panel height,
#     which put the two labels 0.23 in apart. Both now sit at 0.2833 in from
#     the canvas edge, verified from the EPS at two different source lengths.
#   - Trajectory degree references moved to real axis marks outside the box,
#     the time axis is numbered rather than merely labelled, and the wasted
#     y-range (-45..455 for 360 degrees of data) is tightened.
#   - Marker radii and font sizes rescaled to the new panel sizes: physical mm
#     markers do not grow with a panel, so every one of them had become
#     relatively smaller as the wheel grew across v0.4.5 - v0.4.8.
#   - Interference zones are drawn as concentric circles instead of 360 radial
#     hairlines. Their angular spacing scales with the wheel radius while their
#     width does not, so at 5.40 in the band separated into a visible comb.
#   - Removed the C1..C9 cycle-label ladder. Every wrap occurs at phase 0, so
#     all wrap markers coincide at the top of the wheel; the ladder placed the
#     C9 label about 30 wheel units away from the dot it named. The markers
#     remain and the count is stated once, in the panel corner.
#   - Cardinal labels no longer cross the panel border, and the wheel panel now
#     gets a Draw inner box like every other panel in the suite.
#   - Source strip gains a small rotated "Source" label; Summary gains the
#     source name and house-standard font sizes.
#   Canvas stays at the library standard, 8.00 x 7.58 in (was 8.00 x 7.50).
#   DSP, timing, randomization and output naming are unchanged.
#
# Changelog v0.4.8 (2026) - final wheel-dominant spacing:
#   - VISUALIZATION ONLY: removes the nonessential subtitle entirely.
#   - Moves the Source strip upward and enlarges the central wheel panel again.
#   - Guarantees a clean sequence: title -> waveform strip -> giant wheel -> trajectory.
#
# Changelog v0.4.7 (2026) - full-scale phase wheel:
#   - VISUALIZATION ONLY: expands the wheel geometry itself, not just its panel.
#     The main interference ring now uses almost the full square viewport.
#   - Removes the in-wheel legend/cycle-count clutter; phase semantics remain
#     explicit in the 0° Unison / 180° Anti cardinal labels and Summary.
#   - Rebuilds the top title/subtitle band so no text can overlap the Source strip.
#   - Source becomes a purely graphical context strip with no overlaid text.
#
# Changelog v0.4.6 (2026) - dominant phase-wheel layout:
#   - VISUALIZATION ONLY: makes the Phase wheel the dominant central object.
#   - Compresses Source into a narrow context strip and removes its in-panel
#     explanatory text/axis labels so nothing competes with the wheel.
#   - Gives the Phase wheel a 4.90 x 4.90 inch square viewport and increases
#     its cardinal/legend text for presentation-scale readability.
#   - Places Relative phase trajectory in a compact full-width strip below.
#   - Uses separate title bands to prevent text from touching adjacent panels.
#
# Changelog v0.4.5 (2026) - phase-wheel-centered visualization:
#   - Removed the separate blue Output waveform panel.
#   - Enlarged and centered the original Phase wheel as the primary visual.
#   - Placed the Relative phase trajectory directly below it at full width.
#   - Kept Source / loop extraction and Summary as supporting panels only.
#
# Changelog v0.4.4 (2026) - hybrid visualization pass:
#   - RESTORE + COMBINE: the original polar phase wheel is retained as the
#     script's visual identity and paired with the newer relative-phase
#     trajectory for a complementary time-domain reading.
#
# Changelog v0.4.3 (2026) - visualization alignment pass:
#   - VISUALIZATION ONLY: replaces the legacy standalone polar monitor with
#     the Praat AudioTools house layout: Source -> Phase wheel -> Relative phase
#     trajectory -> Summary. DSP, timing, randomization, and output naming are
#     unchanged.
#   - Source panel highlights the randomly selected loop interval.
#   - Relative-phase panel plots the actual V2-V1 phase difference over time,
#     with separate neutral references for unison and anti-phase, physical-size
#     cycle/end markers, and reserved headroom for explanatory text.
#   - Source names are display-sanitized so underscores do not become Praat
#     subscripts.
#
# Changelog v0.4.2 (2026) - compatibility/hardening pass:
#   - API COMPATIBILITY: the complete public form is byte-for-byte
#     unchanged, and the final output naming contract is unchanged.
#   - FIX: Random_seed=0 now explicitly returns Praat to safe/unpredictable
#     RNG mode before this script draws random values. A caller that had
#     previously installed a predictable global seed can no longer leak that
#     deterministic state into a nominally fresh Reich render.
#   - FIX: non-zero source time domains are handled through a zero-based
#     private analysis copy; random loop positions no longer assume xmin=0.
#   - FIX: quiet-but-valid sources are not rejected by an absolute 0.001 RMS
#     gate. The historical gate is retained for normal-level material but is
#     relaxed relative to the source RMS when the whole source is quiet.
#   - FIX: Start_Offset is measured against the ACTUAL post-drift V2 loop
#     duration. 50% now means exactly half of V2's loop (180 degrees), and
#     Random is uniform over one actual V2 cycle. The phase wheel uses the
#     same measured V2 duration, so picture and audio agree.
#   - FIX: phase normalization after adding the start offset uses modulo/floor
#     rather than a one-step >1 subtraction, making the monitor robust at
#     exact wrap points.
#   - HARDENING: Manual loop limits and flutter amount are validated before
#     any random draw; temporary source-analysis objects are cleaned early.
#
# Changelog v0.4.1 (2026) — second review pass:
#   - FIX: Classic Reich (the default preset) still forced
#     p_cycle = 2.0 while the default Total_Duration_min is 1.0 min,
#     so the default demo run ended halfway through the first phase
#     cycle. Classic Reich's cycle is now 1.0 min, matching the
#     default render length.
#   - FIX: the "no voiced material" notice only checked
#     pitch_ratio <> 1.0, so on unpitched loops with the V2 interval
#     left at Unison but Flutter_Amount_st > 0 (e.g. Broken Tape on
#     unvoiced material), flutter silently did nothing with no
#     warning. Notice now also fires when only flutter needed the
#     (empty) PitchTier.
#   - FIX: the phase wheel sampled t = (i-1) * (actual_duration /
#     num_samples), so the last sample landed one interval short of
#     the piece's actual end. For a duration that's an exact multiple
#     of the phase cycle, the drawn path approached but never
#     crossed the wrap point, undercounting cycle_count by one.
#     Sample interval is now actual_duration / (num_samples - 1) so
#     the last sample lands exactly at the end.
#
# Changelog v0.4 (2026) — response to internal review:
#   - FIX (audible, real bug): Flutter_Amount_st was labelled in
#     semitones but applied as "self + randomGauss(0, p_flut)"
#     directly to the PitchTier, whose values are in Hz. A "0.3"
#     setting was a 0.3 Hz standard deviation -- inaudibly small,
#     and its audible size depended on the loop's register. Flutter
#     is now applied multiplicatively/exponentially in log-frequency
#     space ("self * 2^(randomGauss(0, p_flut)/12)"), so the field
#     is genuinely in semitones and scales correctly with pitch.
#   - FIX (structural, real bug): a non-zero Start_Offset trimmed
#     the head off Voice 2 and the tail off Voice 1/3 to align them,
#     which shortened the final render to Total_Duration - Offset
#     instead of the requested Total_Duration. Voice 2's wall is now
#     built Offset_sec longer up front and only then has its head
#     trimmed, so every voice -- and the final mix -- lands at
#     exactly Total_Duration_min regardless of offset.
#   - ADDED: Random_seed (0 = fresh random sequence every run, any
#     other integer = reproducible loop pick / offset / flutter via
#     random_initializeWithSeedUnsafelyButPredictably).
#   - RENAMED: the form title, changelog, and output object name were
#     three different names ("Random Reich Generator",
#     "Harmonic Reich Generator [PRO]", "...ProReich..."). Unified to
#     "Reich Generator" everywhere.
#   - CHANGED: demo-friendlier defaults -- Cycle_Duration_min and
#     Total_Duration_min both default to 1.0 min (was 2.0 / 3.0), so
#     a full phase cycle completes within the default render.
#   - FIX: Voice 3 ("the anchor") was set with "Scale intensity: 65",
#     an absolute dB SPL-equivalent target unrelated to how loud the
#     actual source recording is. It's now set relative to the loop's
#     own intensity via a new V3_Level_dB_relative field (default
#     -6 dB under the loop), so the anchor sits under the other
#     voices instead of at an arbitrary absolute level.
#   - ADDED: final peak normalisation on the mixed output.
#
# Changelog v0.3 (2026):
#   - FIX (audible): loops were cut rectangularly at random
#     positions -- a hard discontinuity clicked at EVERY
#     repetition, metronomically, in both channels. Loop bounds
#     now snap to the nearest zero crossings (the standard looper
#     cure; no amplitude dips, no character change beyond the
#     tick's absence). If you ever want the raw splice ticks back
#     as a rhythm layer, say so -- it is one boolean.
#   - FIX: the phase wheel's cycle markers (C1, C2...) could
#     never draw -- prev_phase_norm was updated BEFORE the marker
#     test re-compared it against the current value. The cycle
#     COUNT was right (tested before the update); only the labels
#     were dead code. Wrapped-flag fix.
#   - Play is now gated by a form flag (house convention;
#     previously unconditional).
#   - NOTE printed when the pitch tier is empty (unvoiced loop):
#     Fifth/Octave settings act through PSOLA and silently do
#     nothing on unpitched material.
#   - AUDIT: the drift math verified exact -- Override to
#     base_sr*(n+1)/n makes V2's loop n/(n+1) shorter, so full
#     realignment lands at precisely Cycle_Duration; the ~0.8%
#     pitch lift is the authentic tape-phasing artifact.
#
# Changelog v0.2:
#   - Robustness: clamp the loop range (Min/Max_loop_sec) to the source
#     duration. Previously a source shorter than the loop length made
#     randomUniform(0, total_src_dur - ldur) negative and Extract part read
#     out of bounds, causing degenerate/silent loops or a misleading
#     "Could not find non-silent audio" exit.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Reich Generator
    comment --- Mode [Dual Locked Loops opens its own settings dialog] ---
    optionmenu Mode 1
        option Single (Classic)
        option Dual Locked Loops
    comment --- Presets ---
    optionmenu Preset 1
        option Classic Reich (Speech / Unison)
        option Deep Space (Sub-Bass Shadow)
        option Holy Trinity (5th + High Anchor)
        option Broken Tape (Flutter + Random Offset)
        option Manual (Settings below)

    comment --- Source Extraction ---
    real Min_loop_sec 0.6
    real Max_loop_sec 1.5
    
    comment --- Voice 2 (The Drifter) ---
    optionmenu V2_Interval 2
        option Unison
        option Perfect Fifth (+7st)
        option Octave Down
        option Octave Up
    
    comment --- Voice 3 (The Glue) ---
    optionmenu V3_Mode 1
        option None
        option Center Anchor (Unison Static)
        option Low Shadow (Octave Down Static)
        option High Shimmer (Octave Up Static)
    real V3_Level_dB_relative -6.0
    
    comment --- Structure & Feel ---
    positive Cycle_Duration_min 1.0
    
    optionmenu Start_Offset 3
        option 0% (Unison Start)
        option 50% (Anti-Phase)
        option Random
    
    real Flutter_Amount_st 0.05
    positive Total_Duration_min 1.0
    
    comment --- Reproducibility [0 = fresh random sequence each run] ---
    integer Random_seed 0
    
    comment --- Visualizations ---
    boolean Create_polar_phase_wheel 1
    comment --- Output ---
    boolean Play_result 1
endform

# ============================================
# 0. MODE DISPATCH
# ============================================
# Dual Locked Loops runs entirely here and ends the script; Single (Classic)
# falls through to the unchanged v0.5.0 code below. No object exists until
# the Dual dialog has been confirmed, so Cancel (or the dialog's Stop)
# leaves the object list exactly as it was.
if mode$ = "Dual Locked Loops"
    if numberOfSelected("Sound") <> 1
        exitScript: "Select exactly one Sound object."
    endif
    dual_source = selected("Sound")
    dual_dialogName$ = selected$("Sound")
    dual_dialogDur = Get total duration
    @dualConstants
    if dual_dialogDur < dual_minSource
        exitScript: "The source is " + fixed$(dual_dialogDur, 3) + " s long; Dual Locked Loops needs at least " + fixed$(dual_minSource, 3) + " s for two regions of " + fixed$(dual_minLoop, 3) + " s."
    endif
    # Random suggested regions (fresh each run; Random_seed <> 0 makes them
    # reproducible). The generator is released again BEFORE the dialog, so
    # Cancel, Stop or any later error leaves it in safe mode.
    if random_seed <> 0
        dual_seedResult = random_initializeWithSeedUnsafelyButPredictably (random_seed)
    else
        random_initializeSafelyAndUnpredictably ()
    endif
    dual_analysis = 0
    @dualRandomRegions: dual_dialogDur, min_loop_sec, max_loop_sec
    random_initializeSafelyAndUnpredictably ()
    dual_sugNote$ = "random suggestion"
    if random_seed <> 0
        dual_sugNote$ = "random suggestion, seed " + string$(random_seed)
    endif
    if dual_sugRandom = 0
        dual_sugNote$ = "no active random pair found; fixed suggestion"
    endif

    # Every dialog variable is initialised before the pause, so it is defined
    # whether or not the Praat build assigns pause fields in batch mode.
    dual_A_Start_sec = dual_sugA_start
    dual_A_End_sec = dual_sugA_end
    dual_B_Start_sec = dual_sugB_start
    dual_B_End_sec = dual_sugB_end
    dual_Timing = 1
    dual_Timing$ = "Independent Rates"
    dual_A_Rate_percent = 100
    dual_B_Rate_percent = 100
    dual_Target_Cycle_min = 1.0
    dual_Drift_Direction = 1
    dual_Drift_Direction$ = "B gains on A"
    dual_A_Start_Offset_percent = 0
    dual_B_Start_Offset_percent = 0
    dual_Stereo_Separation_percent = 100
    dual_B_Level_dB = 0

    beginPause: "Reich Generator - Dual Locked Loops"
        comment: "Source " + dual_dialogName$ + ": " + fixed$(dual_dialogDur, 3) + " s. Two units, one voice each: A loops Region A, B loops Region B."
        comment: "--- Regions (s from the start of the Sound; " + dual_sugNote$ + "; edit, then Render to lock) ---"
        real: "Dual_A_Start_sec", fixed$(dual_A_Start_sec, 3)
        real: "Dual_A_End_sec", fixed$(dual_A_End_sec, 3)
        real: "Dual_B_Start_sec", fixed$(dual_B_Start_sec, 3)
        real: "Dual_B_End_sec", fixed$(dual_B_End_sec, 3)
        comment: "--- Timing (rates 50-200%; speed and pitch change together) ---"
        optionmenu: "Dual_Timing", 1
            option: "Independent Rates"
            option: "Target Relative Cycle"
        real: "Dual_A_Rate_percent", "100"
        real: "Dual_B_Rate_percent", "100"
        comment: "Target Relative Cycle only (B rate is then derived from A):"
        positive: "Dual_Target_Cycle_min", "1.0"
        optionmenu: "Dual_Drift_Direction", 1
            option: "B gains on A"
            option: "B falls behind A"
        real: "Dual_A_Start_Offset_percent", "0"
        real: "Dual_B_Start_Offset_percent", "0"
        comment: "--- Spatialization and balance (100% = A only left, B only right) ---"
        real: "Dual_Stereo_Separation_percent", "100"
        real: "Dual_B_Level_dB", "0.0"
    dual_clicked = endPause: "Cancel", "Render", 2, 1
    if dual_clicked = 1
        exitScript ()
    endif

    dual_keep_intermediates = 0
    @dualRender
    if create_polar_phase_wheel
        @dualDraw
    endif
    selectObject: dual_out
    if play_result
        Play
    endif
    selectObject: dual_out
    exitScript ()
endif

# ============================================
# 1. PRESET LOGIC
# ============================================

p_min = min_loop_sec
p_max = max_loop_sec
p_v2$ = v2_Interval$
p_v3$ = v3_Mode$
p_v3_level = v3_Level_dB_relative
p_cycle = cycle_Duration_min
p_off$ = start_Offset$
p_flut = flutter_Amount_st

if preset$ = "Classic Reich (Speech / Unison)"
    p_min = 0.5
    p_max = 1.0
    p_v2$ = "Unison"
    p_v3$ = "None"
    # v0.4.1 FIX: was 2.0, which meant the (also default-selected)
    # Classic Reich preset needed a 2-minute cycle to complete, but
    # Total_Duration_min defaults to 1.0 -- the default demo run
    # ended halfway through the first phase cycle. Matches the
    # 1-minute default duration so a full cycle completes.
    p_cycle = 1.0
    p_off$ = "0% (Unison Start)"
    p_flut = 0.0

elsif preset$ = "Deep Space (Sub-Bass Shadow)"
    p_min = 2.0
    p_max = 4.0
    p_v2$ = "Unison"
    p_v3$ = "Low Shadow (Octave Down Static)"
    p_cycle = 5.0
    p_off$ = "50% (Anti-Phase)"
    p_flut = 0.1

elsif preset$ = "Holy Trinity (5th + High Anchor)"
    p_min = 0.8
    p_max = 1.2
    p_v2$ = "Perfect Fifth (+7st)"
    p_v3$ = "High Shimmer (Octave Up Static)"
    p_cycle = 3.0
    p_off$ = "Random"
    p_flut = 0.02

elsif preset$ = "Broken Tape (Flutter + Random Offset)"
    p_min = 0.4
    p_max = 0.9
    p_v2$ = "Unison"
    p_v3$ = "Center Anchor (Unison Static)"
    p_cycle = 1.5
    p_off$ = "Random"
    p_flut = 0.3
endif
# NOTE: p_v3_level (Voice 3's level relative to the loop) is
# deliberately never touched by a preset -- like Source pitch in
# Messagesquisse Opening, it's a mix-balance knob the user set for
# their own source material, not a trait of the compositional preset.

# RNG initialization is deliberately deferred until after input/parameter
# validation. This avoids leaving a caller in predictable RNG mode if the
# script has to stop before it draws anything.

# ============================================
# 2. SOURCE EXTRACTION (CLEAN)
# ============================================

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound object."
endif

source_id = selected("Sound")
source_name$ = selected$("Sound")
selectObject: source_id
source_xmin = Get start time
source_xmax = Get end time
total_src_dur = Get total duration

# Public parameters are unchanged; validate the Manual values before any RNG
# state is installed or any random draw occurs. Presets already provide valid
# positive values.
if p_min <= 0 or p_max <= 0
    exitScript: "Min_loop_sec and Max_loop_sec must be > 0."
endif
if p_min > p_max
    exitScript: "Min_loop_sec must be <= Max_loop_sec."
endif
if p_flut < 0
    exitScript: "Flutter_Amount_st must be >= 0."
endif

# Private zero-based source copy. Extract part with preserve-times=no gives a
# domain of 0..duration, so all existing random-loop math remains valid even
# when the selected Sound itself starts at a non-zero time.
selectObject: source_id
Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
Rename: "Reich_Source_Work"
source_work = selected("Sound")

# Cancellation-safe mono analysis. Preserve the normal channel average when it
# is healthy; if opposite-polarity / phase-opposed channels nearly cancel in
# the fold-down, analyse the strongest-RMS channel instead.
selectObject: source_work
source_channels = Get number of channels
strongest_channel = 1
strongest_rms = -1
if source_channels > 1
    for ch from 1 to source_channels
        selectObject: source_work
        tmp_channel = Extract one channel: ch
        channel_rms = Get root-mean-square: 0, 0
        if channel_rms > strongest_rms
            strongest_rms = channel_rms
            strongest_channel = ch
        endif
        removeObject: tmp_channel
    endfor
else
    strongest_rms = Get root-mean-square: 0, 0
endif

selectObject: source_work
Convert to mono
Rename: "Reich_Source_Average"
source_average = selected("Sound")
selectObject: source_average
average_rms = Get root-mean-square: 0, 0

use_strongest_channel = 0
if source_channels > 1 and strongest_rms > 1e-12 and average_rms < 0.10 * strongest_rms
    use_strongest_channel = 1
endif

if use_strongest_channel
    removeObject: source_average
    selectObject: source_work
    Extract one channel: strongest_channel
    Rename: "Reich_Source_Analysis"
    source_analysis = selected("Sound")
    appendInfoLine: "Mono analysis: channel average nearly cancelled; using strongest channel " + string$(strongest_channel) + "."
else
    selectObject: source_average
    Rename: "Reich_Source_Analysis"
    source_analysis = selected("Sound")
endif

selectObject: source_work
Remove
source_work = 0

selectObject: source_analysis
source_rms = Get root-mean-square: 0, 0
if source_rms <= 1e-12
    removeObject: source_analysis
    exitScript: "Selected Sound is silent."
endif
# Preserve v0.4.1's absolute 0.001 gate for normal-level material, but relax
# it for globally quiet sources so final peak normalization can still make
# them usable. The floor remains safely above numerical zero.
activity_rms_floor = min(0.001, source_rms * 0.05)
if activity_rms_floor < 1e-12
    activity_rms_floor = 1e-12
endif

# Guard: if the source is shorter than the requested loop length, clamp the
# range to available material. This preserves the established v0.2 behavior.
if p_max > total_src_dur
    p_max = total_src_dur
endif
if p_min > p_max
    p_min = p_max
endif
if p_min <= 0
    removeObject: source_analysis
    exitScript: "Source is too short for a positive loop duration."
endif

# Explicit RNG policy. Praat's predictable seed persists globally until safe
# initialization is called, so seed=0 must actively undo any predictable mode
# inherited from a caller. Non-zero seeds remain exactly reproducible here.
if random_seed <> 0
    seedResult = random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif

found = 0
attempts = 0
writeInfoLine: "Searching for audio..."

while found = 0 and attempts < 40
    ldur = randomUniform(p_min, p_max)
    st = randomUniform(0, total_src_dur - ldur)
    
    selectObject: source_analysis
    Extract part: st, st + ldur, "rectangular", 1, "no"
    check_id = selected("Sound")
    
    selectObject: check_id
    rms = Get root-mean-square: 0, 0
    if rms > activity_rms_floor
        # v0.3: snap loop bounds to zero crossings -- rectangular
        # random cuts clicked at every repetition
        .cd = Get total duration
        z1 = Get nearest zero crossing: 1, 0.003
        z2 = Get nearest zero crossing: 1, .cd - 0.003
        if z1 = undefined
            z1 = 0
        endif
        if z2 = undefined or z2 <= z1 + 0.05
            z2 = .cd
        endif
        snapped = Extract part: z1, z2, "rectangular", 1, "no"
        # Preserve the actual snapped boundaries for the Source visualization.
        # st/ldur describe the random candidate; these are the loop bounds that
        # the audio actually uses after zero-crossing correction.
        snapped_loop_start = st + z1
        snapped_loop_end = st + z2
        removeObject: check_id
        check_id = snapped
        found = 1
        Rename: "Loop_Base"
        loop_base = check_id
    else
        Remove
        attempts = attempts + 1
    endif
endwhile

if found = 0
    removeObject: source_analysis
    random_initializeSafelyAndUnpredictably ()
    exitScript: "Could not find non-silent audio."
endif

# The loop is now independent; release the full analysis copy early.
removeObject: source_analysis

selectObject: loop_base
base_sr = Get sampling frequency
dur_base = Get duration
loopBaseIntensity_dB = Get intensity (dB)

# ============================================
# 3. CALCULATE DRIFT
# ============================================

cycle_sec = p_cycle * 60
loops_in_cycle = cycle_sec / dur_base
drift_ratio = (loops_in_cycle + 1) / loops_in_cycle

appendInfoLine: "Loop: " + fixed$(dur_base, 3) + "s"
appendInfoLine: "Cycle: " + string$(p_cycle) + " min"
appendInfoLine: "Ratio: " + fixed$(drift_ratio, 6)

# ============================================
# 4. PROCESS VOICE 2 (Pitch + Flutter + Drift)
# ============================================

selectObject: loop_base
Copy: "V2_Temp"
v2_id = selected("Sound")

pitch_ratio = 1.0
if p_v2$ = "Perfect Fifth (+7st)"
    pitch_ratio = 1.4983
elsif p_v2$ = "Octave Down"
    pitch_ratio = 0.5
elsif p_v2$ = "Octave Up"
    pitch_ratio = 2.0
endif

if pitch_ratio <> 1.0 or p_flut > 0
    To Manipulation: 0.01, 75, 600
    manip_id = selected("Manipulation")
    
    Extract pitch tier
    pitch_id = selected("PitchTier")
    nPitchPts = Get number of points
    if nPitchPts = 0 and (pitch_ratio <> 1.0 or p_flut > 0)
        appendInfoLine: "NOTE: no voiced material in the loop -- V2 pitch interval and flutter will have no effect."
    endif
    
    if pitch_ratio <> 1.0
        Formula: "self * " + string$(pitch_ratio)
    endif
    
    if p_flut > 0
        # v0.4 FIX: PitchTier values are in Hz, so "self + randomGauss(0, st)"
        # was adding a fraction-of-a-Hz jitter, not a semitone-scaled one --
        # audibly negligible and register-dependent. Semitones are a ratio,
        # so the jitter has to be multiplicative/exponential in log-frequency
        # space: self * 2^(randomGauss(0, semitones)/12).
        Formula: "self * 2 ^ (randomGauss(0, " + string$(p_flut) + ") / 12)"
    endif
    
    selectObject: manip_id
    plusObject: pitch_id
    Replace pitch tier
    
    selectObject: manip_id
    Get resynthesis (overlap-add)
    Rename: "V2_Processed"
    
    v2_new = selected("Sound")
    selectObject: v2_id
    plusObject: manip_id
    plusObject: pitch_id
    Remove
    v2_id = v2_new
endif

selectObject: v2_id
Override sampling frequency: base_sr * drift_ratio
Resample: base_sr, 50
Rename: "V2_Drifting"
v2_final = selected("Sound")
selectObject: v2_final
dur_v2 = Get total duration
selectObject: v2_id
Remove

# ============================================
# 5. PROCESS VOICE 3 (The Anchor)
# ============================================

has_v3 = 0
v3_id = 0

if p_v3$ <> "None"
    has_v3 = 1
    selectObject: loop_base
    Copy: "V3_Temp"
    v3_temp = selected("Sound")
    
    v3_ratio = 1.0
    if p_v3$ = "Low Shadow (Octave Down Static)"
        v3_ratio = 0.5
    elsif p_v3$ = "High Shimmer (Octave Up Static)"
        v3_ratio = 2.0
    endif
    
    if v3_ratio <> 1.0
        To Manipulation: 0.01, 75, 600
        manip_id = selected("Manipulation")
        
        Extract pitch tier
        v3_pitch_id = selected("PitchTier")
        nV3Pts = Get number of points
        if nV3Pts = 0
            appendInfoLine: "NOTE: no voiced material in the loop -- the V3 octave acts through PSOLA and will have no effect."
        endif
        
        Formula: "self * " + string$(v3_ratio)
        
        selectObject: manip_id
        plusObject: v3_pitch_id
        Replace pitch tier
        
        selectObject: manip_id
        Get resynthesis (overlap-add)
        Rename: "V3_Final"
        v3_id = selected("Sound")
        
        selectObject: manip_id
        plusObject: v3_pitch_id
        plusObject: v3_temp
        Remove
    else
        Rename: "V3_Final"
        v3_id = selected("Sound")
    endif
    
    selectObject: v3_id
    # v0.4 FIX: was "Scale intensity: 65", an absolute dB SPL-equivalent
    # target with no relation to how loud the actual source recording is.
    # Set relative to the loop's own measured intensity instead, so the
    # anchor sits a controlled number of dB under/over the other voices
    # regardless of the source's absolute level.
    Scale intensity: loopBaseIntensity_dB + p_v3_level
endif

# ============================================
# 6. OFFSET (computed before the walls are built --
#    Voice 2's wall needs extra length up front so trimming its
#    head doesn't shorten the final render)
# ============================================

offset_sec = 0
if p_off$ = "50% (Anti-Phase)"
    offset_sec = dur_v2 * 0.5
elsif p_off$ = "Random"
    offset_sec = randomUniform(0, dur_v2)
endif

# All random choices (loop pick, PitchTier flutter, start offset) are complete.
# Return the global generator to Praat's safe/unpredictable mode so a seeded
# Reich render does not make subsequently-called scripts deterministic.
random_initializeSafelyAndUnpredictably ()

# ============================================
# 7. BUILD TRACKS
# ============================================

total_sec = total_Duration_min * 60

procedure make_wall .src .len .name$
    selectObject: .src
    Copy: .name$
    .id = selected("Sound")
    .dur = Get duration
    while .dur < .len
        selectObject: .id
        Copy: "tmp"
        .c = selected("Sound")
        selectObject: .id
        plusObject: .c
        Concatenate
        .new = selected("Sound")
        selectObject: .id
        plusObject: .c
        Remove
        .id = .new
        selectObject: .id
        Rename: .name$
        .dur = Get duration
    endwhile
    selectObject: .id
    Extract part: 0, .len, "rectangular", 1, "no"
    .fin = selected("Sound")
    Rename: .name$
    selectObject: .id
    Remove
    selectObject: .fin
endproc

call make_wall loop_base total_sec "Track_1_Static"
t1 = selected("Sound")

# v0.4 FIX: previously built at total_sec and then had its HEAD cut by
# offset_sec afterwards, which shortened the whole render to
# total_sec - offset_sec instead of the requested Total_Duration_min.
# Build it offset_sec longer up front, then trim the head to length --
# the tail lands exactly at total_sec either way.
v2_wall_len = total_sec + offset_sec
call make_wall v2_final v2_wall_len "Track_2_Drift_Raw"
t2_raw = selected("Sound")

if offset_sec > 0
    selectObject: t2_raw
    Extract part: offset_sec, offset_sec + total_sec, "rectangular", 1, "no"
    Rename: "Track_2_Drift"
    t2 = selected("Sound")
    removeObject: t2_raw
else
    t2 = t2_raw
    selectObject: t2
    Rename: "Track_2_Drift"
endif

t3 = 0
if has_v3
    call make_wall v3_id total_sec "Track_3_Anchor"
    t3 = selected("Sound")
endif

# ============================================
# 8. (v0.6.0: the unreachable v0.4 drawing block that stood here, guarded by
#    "if create_polar_phase_wheel and 0", was removed. Section 8b draws.)
# ============================================

# ============================================
# 9. MIXING & CLEANUP
# ============================================

selectObject: t1
Rename: "Left"

selectObject: t2
Rename: "Right"

if has_v3
    selectObject: t1
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Left_Final"
    t1_final = selected("Sound")
    selectObject: temp_st
    plusObject: t1
    Remove
    t1 = t1_final

    selectObject: t2
    plusObject: t3
    Combine to stereo
    temp_st = selected("Sound")
    Convert to mono
    Rename: "Right_Final"
    t2_final = selected("Sound")
    selectObject: temp_st
    plusObject: t2
    Remove
    t2 = t2_final
    
    selectObject: t3
    Remove
endif

selectObject: t1
plusObject: t2
Combine to stereo
Rename: source_name$ + "_ReichGen_" + preset$
final_id = selected("Sound")

# Final Cleanup
selectObject: loop_base
plusObject: v2_final
plusObject: t1
plusObject: t2
if has_v3
   plusObject: v3_id
endif
Remove

# v0.4: final peak normalisation -- previously absent, so overall
# loudness depended entirely on the source recording's own level
# plus however the three voices happened to sum.
selectObject: final_id
Scale peak: 0.99

# ============================================
# 8b. HOUSE-STYLE VISUALIZATION (v0.4.5 phase-wheel centered)
# ============================================
# Combines the original polar phase wheel with the newer time-domain
# phase trajectory. The wheel remains the visual identity of the script;
# the trajectory is a complementary temporal reading, not a replacement.
if create_polar_phase_wheel
    displayName$ = replace$(source_name$, "_", " ", 0)
    actual_duration = total_sec

    selectObject: source_id
    srcPeakViz = Get absolute extremum: 0, 0, "None"
    selectObject: final_id
    outPeakViz = Get absolute extremum: 0, 0, "None"
    wavePeak = max(srcPeakViz, outPeakViz)
    if wavePeak < 0.10
        wavePeak = 0.10
    endif
    waveY = wavePeak * 1.30

    # Phase samples shared by the wheel, trajectory and summary.
    phaseSamples = 601
    phaseDt = actual_duration / (phaseSamples - 1)
    cycle_count = 0
    prevPhase = 0
    for i from 1 to phaseSamples
        t = (i - 1) * phaseDt
        phaseRaw = t / dur_v2 - t / dur_base
        phaseNorm = phaseRaw - floor(phaseRaw)
        if offset_sec > 0
            phaseNorm = phaseNorm + offset_sec / dur_v2
            phaseNorm = phaseNorm - floor(phaseNorm)
        endif
        if i > 1 and prevPhase > 0.90 and phaseNorm < 0.10
            cycle_count = cycle_count + 1
        endif
        prevPhase = phaseNorm
    endfor

    Erase all
    Colour: "Black"
    Font size: 10
    Line width: 1
    Solid line

    # ------------------------------------------------------------
    # LAYOUT, in inches on the 8-inch canvas. The vertical budget is
    # the visual hierarchy, stated once here instead of being implied
    # by scattered viewport calls:
    #
    # Reading order, top to bottom, with the height each band gets:
    #
    #   Title                      0.28
    #   Phase wheel                4.30  (rank 1, square, dominant)
    #   Source / loop waveform     0.62  (rank 3, but a real waveform now)
    #   Relative phase trajectory  0.92  (rank 2)
    #   Summary                    0.44
    #
    # Wheel : trajectory = 4.7 : 1, trajectory : source = 1.5 : 1.
    # Total canvas 8.00 x 7.58 in, i.e. the library's standard page.
    # ------------------------------------------------------------

    # TITLE -- one clean title only; the wheel follows immediately.
    Select outer viewport: 0, 8, 0, 0.28
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.50, "half", "##Reich Generator##"

    # ------------------------------------------------------------
    # POLAR PHASE WHEEL -- the centre of the figure.
    #
    # The inner viewport is set EXPLICITLY and squarely. Earlier versions
    # set only the outer viewport and let Praat apply its default margins,
    # which are 1.1667 in horizontally but only 0.7778 in vertically. A
    # 5.40 x 5.40 outer viewport therefore produced a 4.233 x 4.622 inner
    # viewport, and the "circle" was an ellipse 8.4% narrower than tall.
    # Resizing the outer viewport (v0.4.5 through v0.4.8) could never fix
    # that, because the distortion lives in the margins, not the size.
    # ------------------------------------------------------------
    Select outer viewport: 0, 8, 0.30, 0.46
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Phase wheel##"

    Select outer viewport: 0.60, 7.40, 0.48, 4.80
    Select inner viewport: 1.85, 6.15, 0.48, 4.78
    Axes: 0, 100, 0, 100
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, 100, 0, 100

    # Outer and inner interference zones from the original design, drawn as
    # concentric circles rather than 360 radial hairlines. At the old wheel
    # size the hairlines merged into a band; at 5.40 in they separate into a
    # visible comb, because their angular spacing scales with the radius while
    # their width does not. Concentric circles are resolution-independent.
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 0.6
    bandR = 41
    while bandR <= 46.001
        Draw circle: 50, 50, bandR
        bandR = bandR + 0.12
    endwhile

    Colour: "{1.00, 0.48, 0.48}"
    bandR = 2
    while bandR <= 9.501
        Draw circle: 50, 50, bandR
        bandR = bandR + 0.12
    endwhile

    # Cardinal phase references.
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 0.55
    Dotted line
    Draw line: 50, 50, 50, 96
    Draw line: 50, 50, 96, 50
    Draw line: 50, 50, 50, 4
    Draw line: 50, 50, 4, 50
    Solid line
    Line width: 1

    Colour: "{0.20, 0.20, 0.20}"
    Text special: 50, "centre", 99, "top", "Helvetica", 9, "0", "0° Unison"
    Text special: 98, "right", 50, "half", "Helvetica", 8, "0", "90°"
    Text special: 50, "centre", 1, "bottom", "Helvetica", 9, "0", "180° Anti"
    Text special: 2, "left", 50, "half", "Helvetica", 8, "0", "270°"

    # Process path: radius and colour preserve the original interference law.
    prev_x = 0
    prev_y = 0
    final_x = 0
    final_y = 0
    prev_phase_norm = 0
    wheelSamples = 900
    wheelDt = actual_duration / (wheelSamples - 1)
    wheelCycles = 0
    for i from 1 to wheelSamples
        t = (i - 1) * wheelDt
        v1_loops = t / dur_base
        v2_loops = t / dur_v2
        phase_raw = v2_loops - v1_loops
        phase_norm = phase_raw - floor(phase_raw)
        if offset_sec > 0
            phase_norm = phase_norm + offset_sec / dur_v2
            phase_norm = phase_norm - floor(phase_norm)
        endif

        wrapped = 0
        if i > 1 and prev_phase_norm > 0.90 and phase_norm < 0.10
            wheelCycles = wheelCycles + 1
            wrapped = 1
        endif

        angle_rad = phase_norm * 2 * pi
        beat_amp = 0.5 + 0.5 * cos(angle_rad)
        r = 5 + beat_amp * 39
        x = 50 + r * sin(angle_rad)
        y = 50 + r * cos(angle_rad)

        red_val = 1.0 - beat_amp
        blue_val = beat_amp
        Colour: {red_val, 0, blue_val}
        Line width: 1.6
        if i > 1
            dist = sqrt((x-prev_x)^2 + (y-prev_y)^2)
            if dist < 20
                Draw line: prev_x, prev_y, x, y
            endif
        endif

        # Every wrap happens at phase 0, i.e. at the top of the wheel, so all
        # wrap markers coincide. Earlier versions fanned out C1..C9 labels on a
        # fixed ladder, which by C9 sat 30 units away from the dot it named.
        # The markers stay; the count is stated once, in the corner.
        if wrapped
            Colour: "Black"
            Paint circle (mm): "White", x, y, 1.25
            Draw circle (mm): x, y, 1.25
        endif

        prev_x = x
        prev_y = y
        prev_phase_norm = phase_norm
        if i = wheelSamples
            final_x = x
            final_y = y
        endif
    endfor
    Line width: 1

    Paint circle (mm): "{0.82, 0.26, 0.24}", final_x, final_y, 1.85
    Draw circle (mm): final_x, final_y, 1.85
    final_degrees = prev_phase_norm * 360
    if final_degrees < 0.5 and wheelCycles > 0
        final_degrees = 360
    endif
    Colour: "{0.25, 0.25, 0.25}"
    Text special: final_x - 4, "right", final_y - 4, "top", "Helvetica", 7, "0", "End " + fixed$(final_degrees,0) + "°"

    Colour: "{0.35, 0.35, 0.35}"
    Text special: 3, "left", 97, "top", "Helvetica", 6, "0", "unison returns: " + string$(wheelCycles)
    Text special: 3, "left", 4, "bottom", "Helvetica", 6, "0", "radius = beating depth  |  blue = unison, red = anti"

    Colour: "Black"
    Draw inner box

    # SOURCE / SELECTED LOOP -- graphical context strip only; no text overlays.
    Select outer viewport: 0, 8, 4.86, 5.66
    Select inner viewport: 0.55, 7.75, 4.90, 5.52
    Axes: source_xmin, source_xmax, -waveY, waveY
    Paint rectangle: "{0.97, 0.97, 0.97}", source_xmin, source_xmax, -waveY, waveY
    loopVisStart = source_xmin + snapped_loop_start
    loopVisEnd = source_xmin + snapped_loop_end
    Paint rectangle: "{1.00, 0.94, 0.84}", loopVisStart, loopVisEnd, -waveY, waveY
    Colour: "{0.84, 0.84, 0.84}"
    Draw line: source_xmin, 0, source_xmax, 0
    selectObject: source_id
    Colour: "{0.52, 0.52, 0.52}"
    Draw: source_xmin, source_xmax, -waveY, waveY, "no", "Curve"
    Select outer viewport: 0, 8, 4.86, 5.66
    Select inner viewport: 0.55, 7.75, 4.90, 5.52
    Axes: source_xmin, source_xmax, -waveY, waveY
    Colour: "{0.88, 0.52, 0.18}"
    Line width: 1.3
    Draw line: loopVisStart, -waveY, loopVisStart, waveY
    Draw line: loopVisEnd, -waveY, loopVisEnd, waveY
    Line width: 1
    Colour: "Black"
    Draw inner box
    # Left label. "Text left: yes" cannot be used here: Praat's far-text
    # distance depends on the panel height, so in this 0.62 in strip it lands
    # about 0.23 in further left than the identical call on the 0.92 in
    # trajectory panel below, and the two left labels do not line up. The
    # label is therefore placed explicitly, on the trajectory panel's line
    # (0.2833 in from the canvas edge).
    #
    # NOTE, Praat gotcha: a rotated "Text special" also picks up the CURRENT
    # "Font size" when it computes its alignment offset, not the size passed
    # in the call. With "Font size: 6" active the same anchor lands 0.25 in
    # to the left. The size is reset here before the call for that reason.
    Font size: 10
    Colour: "{0.45, 0.45, 0.45}"
    srcLabelX = source_xmin - 0.04920 * (source_xmax - source_xmin)
    Text special: srcLabelX, "centre", 0, "half", "Times", 6, "90", "Source"
    Font size: 6

    # ------------------------------------------------------------
    # RELATIVE PHASE TRAJECTORY -- rank 2, given real vertical room.
    # At 0.41 in tall the 0/90/180/270/360 rows were 0.09 in apart and
    # their labels sat inside the plot, on top of the curve.
    # ------------------------------------------------------------
    phaseYmin = -25
    phaseYmax = 385

    Select outer viewport: 0, 8, 5.70, 5.86
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Relative phase trajectory##"
    # Legend lives in the title band. In a 0.92 in panel an in-plot note line
    # either overlaps the curve or pushes the y-range wider than the data.
    Font size: 6
    Colour: "{0.45, 0.45, 0.45}"
    Text: 0.97, "right", 0.5, "half", "blue dot = start  |  red dot = end  |  180° = anti-phase"

    Select outer viewport: 0, 8, 5.88, 7.08
    Select inner viewport: 0.55, 7.75, 5.90, 6.82
    Axes: 0, actual_duration, phaseYmin, phaseYmax
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, actual_duration, phaseYmin, phaseYmax

    Colour: "{0.86, 0.86, 0.86}"
    Line width: 0.6
    Draw line: 0, 90, actual_duration, 90
    Draw line: 0, 270, actual_duration, 270
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1.0
    Draw line: 0, 0, actual_duration, 0
    Draw line: 0, 360, actual_duration, 360
    Colour: "{0.82, 0.26, 0.24}"
    Line width: 1.1
    Draw line: 0, 180, actual_duration, 180

    prevPhaseDeg = 0
    prevT = 0
    firstPoint = 1
    Colour: "{0.36, 0.28, 0.72}"
    Line width: 1.4
    for i from 1 to phaseSamples
        t = (i - 1) * phaseDt
        phaseRaw = t / dur_v2 - t / dur_base
        phaseNorm = phaseRaw - floor(phaseRaw)
        if offset_sec > 0
            phaseNorm = phaseNorm + offset_sec / dur_v2
            phaseNorm = phaseNorm - floor(phaseNorm)
        endif
        phaseDeg = 360 * phaseNorm
        if i = phaseSamples and phaseNorm < 0.002 and prevPhaseDeg > 300
            phaseDeg = 360
        endif
        if firstPoint = 0
            if abs(phaseDeg - prevPhaseDeg) < 180
                Draw line: prevT, prevPhaseDeg, t, phaseDeg
            else
                Paint circle (mm): "{0.36, 0.28, 0.72}", t, phaseDeg, 1.15
            endif
        endif
        firstPoint = 0
        prevT = t
        prevPhaseDeg = phaseDeg
    endfor
    Line width: 1

    startPhaseRaw = offset_sec / dur_v2
    startPhaseNorm = startPhaseRaw - floor(startPhaseRaw)
    startPhaseDeg = 360 * startPhaseNorm
    Paint circle (mm): "{0.25, 0.50, 0.82}", 0, startPhaseDeg, 1.35
    Paint circle (mm): "{0.82, 0.26, 0.24}", actual_duration, prevPhaseDeg, 1.50

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "V2 - V1 phase (deg)"
    Text bottom: "yes", "Output time (s)"
    Marks bottom: 6, "yes", "yes", "no"

    # Degree references belong on the axis, not inside the data area.
    Font size: 6
    One mark left: 0, "no", "yes", "no", "0°"
    One mark left: 90, "no", "yes", "no", "90°"
    One mark left: 180, "no", "yes", "no", "180°"
    One mark left: 270, "no", "yes", "no", "270°"
    One mark left: 360, "no", "yes", "no", "360°"


    # SUMMARY
    Select outer viewport: 0, 8, 7.14, 7.58
    Select inner viewport: 0.30, 7.80, 7.18, 7.54
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    p_off_display$ = p_off$
    if p_off$ = "0% (Unison Start)"
        p_off_display$ = "0 percent (Unison Start)"
    elsif p_off$ = "50% (Anti-Phase)"
        p_off_display$ = "50 percent (Half-cycle)"
    endif
    Text: 0.02, "left", 0.49, "half", displayName$ + "  |  loop " + fixed$(dur_base,3) + " s  |  cycle " + fixed$(p_cycle,2) + " min  |  wraps " + string$(cycle_count) + "  |  start " + p_off_display$
    Text: 0.02, "left", 0.18, "half", "V2 " + p_v2$ + "  |  V3 " + p_v3$ + "  |  flutter " + fixed$(p_flut,2) + " st  |  duration " + fixed$(actual_duration/60,2) + " min  |  L static / R drifting"

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

selectObject: final_id
if play_result
    Play
endif
selectObject: final_id

# ============================================================
# >>> DUAL ENGINE BEGIN
# Dual Locked Loops engine (v0.7.0): TWO independent single-voice looping
# units. Procedures only: nothing in this block executes unless called. The
# main script calls them after its dialog; the headless test harness
# includes exactly this block and calls the same procedures with the same
# global parameter names, so tests exercise the shipped code.
#
#   Unit A: Region A -> one continuous loop stream A(t), rate vA, offset oA
#   Unit B: Region B -> one continuous loop stream B(t), rate vB, offset oB
#   L(t) = gAL * A(t) + gBL * B(t)
#   R(t) = gAR * A(t) + gBR * B(t)
# There is no second (static or drifting) copy of either region anywhere.
#
# Inputs (globals): dual_source, total_Duration_min,
#   dual_A_Start_sec, dual_A_End_sec, dual_B_Start_sec, dual_B_End_sec,
#   dual_Timing$ ("Independent Rates" | "Target Relative Cycle"),
#   dual_A_Rate_percent, dual_B_Rate_percent,
#   dual_Target_Cycle_min, dual_Drift_Direction$
#     ("B gains on A" | "B falls behind A"),
#   dual_A_Start_Offset_percent, dual_B_Start_Offset_percent,
#   dual_Stereo_Separation_percent, dual_B_Level_dB,
#   dual_keep_intermediates (0 in normal use; 1 lets a test inspect units)
# Output: dual_out (stereo Sound, selected) + measurement globals.
# Rendering draws no random numbers. Only dualRandomRegions (the suggested
# regions shown in the dialog) uses the generator, seeded by the caller.
# ============================================================

procedure dualConstants
    # Minimum region length (s). After inward zero-crossing snapping a loop
    # is at least 0.070 s long.
    dual_minLoop = 0.100
    dual_minSource = 2 * dual_minLoop
    # Snap a boundary only to a zero crossing within this distance INSIDE
    # the region; otherwise keep the user's boundary exactly.
    dual_snapWindow = 0.015
    # Supported playback-rate range (percent), for typed and derived rates.
    dual_rateMin = 50
    dual_rateMax = 200
    dualA_colour$ = "{0.10, 0.52, 0.50}"
    dualB_colour$ = "{0.80, 0.46, 0.10}"
    dualA_tint$ = "{0.87, 0.95, 0.94}"
    dualB_tint$ = "{1.00, 0.93, 0.84}"
    dualRel_colour$ = "{0.36, 0.28, 0.72}"
endproc

# Suggested starting regions, derived deterministically from the source
# length: A sits around 25% of the source, B around 70%, each confined to
# its own half, so they can never overlap. Lengths 30% / 38% of the source,
# capped at 0.90 s / 1.15 s, never below dual_minLoop. Integer milliseconds.
procedure dualSuggestRegions: .dur
    @dualConstants
    .dms = floor(.dur * 1000)
    .half = floor(.dms / 2)
    .minMs = round(dual_minLoop * 1000)
    .la = min(900, max(.minMs, round(0.30 * .dms)))
    .la = min(.la, .half)
    .lb = min(1150, max(.minMs, round(0.38 * .dms)))
    .lb = min(.lb, .half)
    .sa = round(0.25 * .dms - .la / 2)
    .sa = max(0, min(.sa, .half - .la))
    .sb = round(0.70 * .dms - .lb / 2)
    .sb = max(.half, min(.sb, .dms - .lb))
    dual_sugA_start = .sa / 1000
    dual_sugA_end = (.sa + .la) / 1000
    dual_sugB_start = .sb / 1000
    dual_sugB_end = (.sb + .lb) / 1000
endproc

# Random suggested regions (v0.7.1), drawn fresh on each run before the
# dialog opens; the user still edits and confirms them, and they lock at
# Render. Lengths: uniform in [Min_loop_sec, Max_loop_sec] of the main form
# (each capped at 45% of the source, never below dual_minLoop). Region A:
# uniform over the source. Region B: uniform over every start that does NOT
# overlap A (either side). Both must contain signal (the Classic loop
# search's RMS floor). All in integer milliseconds, so the dialog shows
# exactly the values that will be validated. Up to 200 attempts; otherwise
# the fixed 25% / 70% suggestion is kept (dual_sugRandom = 0).
# Uses the random generator; the CALLER seeds it and releases it.
procedure dualRandomRegions: .dur, .lo, .hi
    @dualSuggestRegions: .dur
    dual_sugRandom = 0
    dual_sugAttempts = 0
    .dms = floor(.dur * 1000)
    .minMs = round(dual_minLoop * 1000)
    .capMs = floor(0.45 * .dms)
    if .capMs >= .minMs
        .loMs = max(.minMs, min(round(min(.lo, .hi) * 1000), .capMs))
        .hiMs = max(.loMs, min(round(max(.lo, .hi) * 1000), .capMs))
        @dualMonoAnalysis
        selectObject: dual_analysis
        .srcRms = Get root-mean-square: 0, 0
        .floor = max(1e-12, min(0.001, .srcRms * 0.05))
        while dual_sugRandom = 0 and dual_sugAttempts < 200
            dual_sugAttempts = dual_sugAttempts + 1
            .la = randomInteger(.loMs, .hiMs)
            .lb = randomInteger(.loMs, .hiMs)
            .sa = randomInteger(0, .dms - .la)
            # B starts that do not overlap A: 0 .. sa - lb, and sa + la .. dms - lb
            .n1 = max(0, .sa - .lb + 1)
            .n2 = max(0, .dms - .lb - (.sa + .la) + 1)
            if .n1 + .n2 > 0
                .k = randomInteger(1, .n1 + .n2)
                if .k <= .n1
                    .sb = .k - 1
                else
                    .sb = .sa + .la + (.k - .n1 - 1)
                endif
                selectObject: dual_analysis
                .pa = Extract part: .sa / 1000, (.sa + .la) / 1000, "rectangular", 1, "no"
                .ra = Get root-mean-square: 0, 0
                selectObject: dual_analysis
                .pb = Extract part: .sb / 1000, (.sb + .lb) / 1000, "rectangular", 1, "no"
                .rb = Get root-mean-square: 0, 0
                removeObject: .pa, .pb
                if .ra > .floor and .rb > .floor
                    dual_sugA_start = .sa / 1000
                    dual_sugA_end = (.sa + .la) / 1000
                    dual_sugB_start = .sb / 1000
                    dual_sugB_end = (.sb + .lb) / 1000
                    dual_sugRandom = 1
                endif
            endif
        endwhile
        removeObject: dual_analysis
        dual_analysis = 0
    endif
endproc

procedure dualCheck: .bad, .msg$
    if dual_error$ = "" and .bad
        dual_error$ = .msg$
    endif
endproc

# Cancellation-safe mono analysis copy -- the same strategy as Classic
# Section 2 (zero-based private copy; channel average unless it nearly
# cancels, then the strongest-RMS channel).
procedure dualMonoAnalysis
    selectObject: dual_source
    .xmin = Get start time
    .xmax = Get end time
    .work = Extract part: .xmin, .xmax, "rectangular", 1, "no"
    Rename: "ReichDual_Source_Work"
    .nch = Get number of channels
    dual_strongestChannel = 1
    .strongestRms = -1
    if .nch > 1
        for .ch from 1 to .nch
            selectObject: .work
            .tmp = Extract one channel: .ch
            .r = Get root-mean-square: 0, 0
            if .r > .strongestRms
                .strongestRms = .r
                dual_strongestChannel = .ch
            endif
            removeObject: .tmp
        endfor
    else
        .strongestRms = Get root-mean-square: 0, 0
    endif
    selectObject: .work
    .avg = Convert to mono
    .avgRms = Get root-mean-square: 0, 0
    dual_usedStrongest = 0
    if .nch > 1 and .strongestRms > 1e-12 and .avgRms < 0.10 * .strongestRms
        dual_usedStrongest = 1
    endif
    if dual_usedStrongest
        removeObject: .avg
        selectObject: .work
        dual_analysis = Extract one channel: dual_strongestChannel
    else
        dual_analysis = .avg
    endif
    selectObject: dual_analysis
    Rename: "ReichDual_Source_Analysis"
    removeObject: .work
    dual_sourceChannels = .nch
endproc

# Extract one locked region from the analysis copy and snap its boundaries
# INWARD to a zero crossing within dual_snapWindow. Inward-only snapping keeps
# the loop inside the user's region, so it can neither leave the source nor
# overlap the other region.
procedure dualPrepareRegion: .start, .end, .tag$
    dualOut_loop = 0
    selectObject: dual_analysis
    .cut = Extract part: .start, .end, "rectangular", 1, "no"
    .rms = Get root-mean-square: 0, 0
    if .rms <= 1e-12
        removeObject: .cut
        dual_error$ = "Region " + .tag$ + " (" + fixed$(.start, 3) + "-" + fixed$(.end, 3) + " s) is digitally silent. Choose a region that contains signal."
    else
        .cd = Get total duration
        .z1 = Get nearest zero crossing: 1, 0.003
        if .z1 = undefined
            .z1 = 0
        endif
        if .z1 > dual_snapWindow
            .z1 = 0
        endif
        .z2 = Get nearest zero crossing: 1, .cd - 0.003
        if .z2 = undefined
            .z2 = .cd
        endif
        if .z2 < .cd - dual_snapWindow
            .z2 = .cd
        endif
        selectObject: .cut
        dualOut_loop = Extract part: .z1, .z2, "rectangular", 1, "no"
        Rename: "ReichDual_Loop_" + .tag$
        removeObject: .cut
        dualOut_snapStart = .start + .z1
        dualOut_snapEnd = .start + .z2
    endif
endproc

# Validation of every Dual parameter. Runs before any object is created.
procedure dualValidate: .dur
    dual_error$ = ""
    .tol = 1e-9
    .durTxt$ = fixed$(.dur, 3)
    .range$ = string$(dual_rateMin) + "-" + string$(dual_rateMax) + "%"
    @dualCheck: .dur < dual_minSource - .tol, "The source is " + .durTxt$ + " s long; Dual Locked Loops needs at least " + fixed$(dual_minSource, 3) + " s for two regions of " + fixed$(dual_minLoop, 3) + " s."
    @dualCheck: dual_A_Start_sec < 0, "Region A starts before the beginning of the Sound (start must be >= 0 s)."
    @dualCheck: dual_A_End_sec <= dual_A_Start_sec, "Region A: end must be later than start."
    @dualCheck: dual_A_End_sec > .dur + .tol, "Region A ends at " + fixed$(dual_A_End_sec, 3) + " s, after the end of the Sound (" + .durTxt$ + " s)."
    @dualCheck: dual_A_End_sec - dual_A_Start_sec < dual_minLoop - .tol, "Region A is " + fixed$(dual_A_End_sec - dual_A_Start_sec, 3) + " s long; the minimum is " + fixed$(dual_minLoop, 3) + " s."
    @dualCheck: dual_B_Start_sec < 0, "Region B starts before the beginning of the Sound (start must be >= 0 s)."
    @dualCheck: dual_B_End_sec <= dual_B_Start_sec, "Region B: end must be later than start."
    @dualCheck: dual_B_End_sec > .dur + .tol, "Region B ends at " + fixed$(dual_B_End_sec, 3) + " s, after the end of the Sound (" + .durTxt$ + " s)."
    @dualCheck: dual_B_End_sec - dual_B_Start_sec < dual_minLoop - .tol, "Region B is " + fixed$(dual_B_End_sec - dual_B_Start_sec, 3) + " s long; the minimum is " + fixed$(dual_minLoop, 3) + " s."
    .overlap = dual_A_End_sec > dual_B_Start_sec + .tol and dual_B_End_sec > dual_A_Start_sec + .tol
    @dualCheck: .overlap, "Regions A (" + fixed$(dual_A_Start_sec, 3) + "-" + fixed$(dual_A_End_sec, 3) + " s) and B (" + fixed$(dual_B_Start_sec, 3) + "-" + fixed$(dual_B_End_sec, 3) + " s) overlap; they must be distinct (touching is allowed)."
    .knownTiming = dual_Timing$ = "Independent Rates" or dual_Timing$ = "Target Relative Cycle"
    @dualCheck: not .knownTiming, "Unknown Dual_Timing: " + dual_Timing$
    @dualCheck: dual_A_Rate_percent < dual_rateMin or dual_A_Rate_percent > dual_rateMax, "Dual_A_Rate_percent is " + fixed$(dual_A_Rate_percent, 3) + "; the supported range is " + .range$ + "."
    if dual_Timing$ = "Independent Rates"
        @dualCheck: dual_B_Rate_percent < dual_rateMin or dual_B_Rate_percent > dual_rateMax, "Dual_B_Rate_percent is " + fixed$(dual_B_Rate_percent, 3) + "; the supported range is " + .range$ + "."
    else
        @dualCheck: dual_Target_Cycle_min <= 0, "Dual_Target_Cycle_min must be > 0."
        .knownDir = dual_Drift_Direction$ = "B gains on A" or dual_Drift_Direction$ = "B falls behind A"
        @dualCheck: not .knownDir, "Unknown Dual_Drift_Direction: " + dual_Drift_Direction$
    endif
    @dualCheck: dual_A_Start_Offset_percent < 0 or dual_A_Start_Offset_percent > 100, "Dual_A_Start_Offset_percent must be between 0 and 100."
    @dualCheck: dual_B_Start_Offset_percent < 0 or dual_B_Start_Offset_percent > 100, "Dual_B_Start_Offset_percent must be between 0 and 100."
    @dualCheck: dual_Stereo_Separation_percent < 0 or dual_Stereo_Separation_percent > 100, "Dual_Stereo_Separation_percent must be between 0 and 100."
    @dualCheck: total_Duration_min <= 0, "Total_Duration_min must be > 0."
endproc

# Static, symmetric pan positions (-100..+100): A at -s, B at +s.
procedure dualPanPositions: .s
    dual_panA = 0 - .s
    dual_panB = .s
endproc

# Equal-power law: angle = (p + 1) * pi / 4, L = cos, R = sin (p in -1..1).
# Gains below 1e-12 are set to exactly 0, so at 100% separation each
# channel holds only its own unit (cos(pi/2) would otherwise be 6e-17).
procedure dualEqualPower: .pan
    .angle = (.pan / 100 + 1) * pi / 4
    dualOut_gL = cos(.angle)
    dualOut_gR = sin(.angle)
    if abs(dualOut_gL) < 1e-12
        dualOut_gL = 0
    endif
    if abs(dualOut_gR) < 1e-12
        dualOut_gR = 0
    endif
endproc

# One looping unit: its locked loop played continuously at rate v from a
# start position inside its own loop. Sets dualOut_read$, the Formula term
# that yields the unit's signal at output sample col (1-based).
#
# v = 1  : no resampling. The term reads the loop itself by index,
#          object[loop, ((col - 1 + offS) mod n) + 1] -- exact.
# v <> 1 : the loop is tiled into one continuous wall at the native rate and
#          the rate change is applied ONCE to the whole wall (Override
#          sampling frequency + sinc Resample), never per loop. The loop
#          period is therefore exactly n / (v * sr) with no rounding to whole
#          samples (the v0.6.0 review finding). A 50 ms pre-roll keeps the
#          sinc filter's edge outside the render; the stream is read from
#          sample p0 = ceiling(pre / v) on.
#          Speed and pitch change TOGETHER (plain resampling, like tape):
#          v = 1.25 is also +3.86 semitones. Not a time stretch.
#
# Timing law, shared with the figure (t = (col - 1) / sr):
#   loop position u(t) = (offS + eps + v * sr * t) / n      [loops]
#   with eps = 0 for v = 1, else eps = (p0 * v - pre) + 0.5 * (v - 1),
#   the sub-sample residue of the pre-roll plus Praat's half-sample
#   convention when the rate is overridden (0 <= eps < 2.5 samples).
procedure dualMakeUnit: .loop, .ratePct, .offPct, .tag$
    selectObject: .loop
    .sr = Get sampling frequency
    .n = Get number of samples
    .v = .ratePct / 100
    dualOut_n = .n
    dualOut_v = .v
    dualOut_offS = round(.offPct / 100 * .n) mod .n
    dualOut_stream = 0
    dualOut_p0 = 0
    dualOut_eps = 0
    dualOut_nStream = 0
    if .v = 1
        dualOut_read$ = "object[" + string$(.loop) + ", 1, ((col - 1 + " + string$(dualOut_offS) + ") mod " + string$(.n) + ") + 1]"
    else
        .pre = round(0.05 * .sr)
        dualOut_p0 = ceiling(.pre / .v)
        dualOut_eps = (dualOut_p0 * .v - .pre) + 0.5 * (.v - 1)
        .nWall = ceiling((dual_nTotal + dualOut_p0) * .v) + 2 * .pre
        .shift = dualOut_offS - .pre + .n * ceiling(.pre / .n)
        .wall = Create Sound from formula: "ReichDual_Wall_" + .tag$, 1, 0, .nWall / .sr, .sr, "object[" + string$(.loop) + ", 1, ((col - 1 + " + string$(.shift) + ") mod " + string$(.n) + ") + 1]"
        Override sampling frequency: .sr * .v
        dualOut_stream = Resample: .sr, 50
        Rename: "ReichDual_Unit_" + .tag$
        dualOut_nStream = Get number of samples
        removeObject: .wall
        dualOut_read$ = "object[" + string$(dualOut_stream) + ", 1, col + " + string$(dualOut_p0) + "]"
    endif
endproc

procedure dualRemoveIntermediates
    if dual_analysis > 0
        removeObject: dual_analysis
        dual_analysis = 0
    endif
    if dualA_loop > 0
        removeObject: dualA_loop
        dualA_loop = 0
    endif
    if dualB_loop > 0
        removeObject: dualB_loop
        dualB_loop = 0
    endif
    if dualA_stream > 0
        removeObject: dualA_stream
        dualA_stream = 0
    endif
    if dualB_stream > 0
        removeObject: dualB_stream
        dualB_stream = 0
    endif
endproc

# Error exit: nothing this run created survives, and the original Sound and
# all unrelated objects are untouched.
procedure dualAbort
    @dualRemoveIntermediates
    if dual_out > 0
        removeObject: dual_out
        dual_out = 0
    endif
    selectObject: dual_source
    exitScript: dual_error$
endproc

# Loop positions and their relationship at output time t (seconds).
#   uA, uB          unwrapped loop positions (loops), from the timing law
#   dualOut_rel     uB - uA, unwrapped
#   dualOut_phase   frac(uB - uA): relative loop phase, 0..1
procedure dualRel: .t
    dualOut_uA = dualA_u0 + dualA_f * .t
    dualOut_uB = dualB_u0 + dualB_f * .t
    dualOut_rel = dualOut_uB - dualOut_uA
    dualOut_phase = dualOut_rel - floor(dualOut_rel)
endproc

procedure dualSemitones: .v
    dualOut_st = 12 * log2(.v)
endproc

procedure dualRender
    @dualConstants
    dual_out = 0
    dual_analysis = 0
    dualA_loop = 0
    dualB_loop = 0
    dualA_stream = 0
    dualB_stream = 0

    selectObject: dual_source
    dual_sourceName$ = selected$("Sound")
    dual_srcXmin = Get start time
    dual_srcXmax = Get end time
    dual_srcDur = Get total duration

    # 1. Validate everything before allocating anything.
    @dualValidate: dual_srcDur
    if dual_error$ <> ""
        selectObject: dual_source
        exitScript: dual_error$
    endif

    writeInfoLine: "Reich Generator v0.7.0 -- mode: Dual Locked Loops (two units, one voice each)"
    appendInfoLine: "(Classic Preset, V2/V3 and Start_Offset are not used; Min/Max_loop_sec and Random_seed only shape the suggested regions.)"

    # 2. Mono analysis copy and the two locked regions.
    @dualMonoAnalysis
    if dual_usedStrongest
        appendInfoLine: "Mono analysis: channel average nearly cancelled; using strongest channel " + string$(dual_strongestChannel) + "."
    endif

    @dualPrepareRegion: dual_A_Start_sec, dual_A_End_sec, "A"
    dualA_loop = dualOut_loop
    if dual_error$ <> ""
        @dualAbort
    endif
    dualA_snapStart = dualOut_snapStart
    dualA_snapEnd = dualOut_snapEnd

    @dualPrepareRegion: dual_B_Start_sec, dual_B_End_sec, "B"
    dualB_loop = dualOut_loop
    if dual_error$ <> ""
        @dualAbort
    endif
    dualB_snapStart = dualOut_snapStart
    dualB_snapEnd = dualOut_snapEnd

    removeObject: dual_analysis
    dual_analysis = 0

    selectObject: dualA_loop
    dual_sr = Get sampling frequency
    dualA_n = Get number of samples
    selectObject: dualB_loop
    dualB_n = Get number of samples
    dual_nTotal = round(total_Duration_min * 60 * dual_sr)

    # 3. Rates. Independent Rates: both typed. Target Relative Cycle: A typed,
    #    B derived from the measured (snapped) loop lengths so that
    #    fB - fA = +-1 / target, with f = v * sr / n loops per second.
    dualA_ratePct = dual_A_Rate_percent
    if dual_Timing$ = "Target Relative Cycle"
        .dir = 1
        if dual_Drift_Direction$ = "B falls behind A"
            .dir = -1
        endif
        .fA = (dualA_ratePct / 100) * dual_sr / dualA_n
        .fB = .fA + .dir / (dual_Target_Cycle_min * 60)
        dualB_ratePct = 100 * .fB * dualB_n / dual_sr
        if dualB_ratePct < dual_rateMin or dualB_ratePct > dual_rateMax
            @dualSemitones: max(dualB_ratePct, 1e-6) / 100
            dual_error$ = "Target Relative Cycle: a " + fixed$(dual_Target_Cycle_min, 3) + " min cycle (" + dual_Drift_Direction$ + ") with Unit A at " + fixed$(dualA_ratePct, 2) + "% needs Unit B at " + fixed$(dualB_ratePct, 2) + "% (" + fixed$(dualOut_st, 2) + " semitones), outside the supported " + string$(dual_rateMin) + "-" + string$(dual_rateMax) + "%. The loops are " + fixed$(dualA_n / dual_sr, 4) + " s and " + fixed$(dualB_n / dual_sr, 4) + " s, so B must run at about " + fixed$(100 * dualA_ratePct / 100 * dualB_n / dualA_n, 1) + "% just to keep pace with A. Choose regions of more similar length, another A rate, or a longer cycle."
            @dualAbort
        endif
    else
        dualB_ratePct = dual_B_Rate_percent
    endif

    # 4. The two units.
    @dualMakeUnit: dualA_loop, dualA_ratePct, dual_A_Start_Offset_percent, "A"
    dualA_stream = dualOut_stream
    dualA_v = dualOut_v
    dualA_offS = dualOut_offS
    dualA_p0 = dualOut_p0
    dualA_eps = dualOut_eps
    dualA_nStream = dualOut_nStream
    dualA_read$ = dualOut_read$
    @dualMakeUnit: dualB_loop, dualB_ratePct, dual_B_Start_Offset_percent, "B"
    dualB_stream = dualOut_stream
    dualB_v = dualOut_v
    dualB_offS = dualOut_offS
    dualB_p0 = dualOut_p0
    dualB_eps = dualOut_eps
    dualB_nStream = dualOut_nStream
    dualB_read$ = dualOut_read$
    .shortA = dualA_stream > 0 and dualA_nStream < dual_nTotal + dualA_p0
    .shortB = dualB_stream > 0 and dualB_nStream < dual_nTotal + dualB_p0
    if .shortA or .shortB
        dual_error$ = "Internal error: a unit stream is shorter than the render (A " + string$(dualA_nStream) + ", B " + string$(dualB_nStream) + " samples for " + string$(dual_nTotal) + ")."
        @dualAbort
    endif

    # 5. Pans and gains (B level folded into B's gains).
    @dualPanPositions: dual_Stereo_Separation_percent
    dual_levelB = 10 ^ (dual_B_Level_dB / 20)
    @dualEqualPower: dual_panA
    dual_gLA = dualOut_gL
    dual_gRA = dualOut_gR
    @dualEqualPower: dual_panB
    dual_gLB = dualOut_gL * dual_levelB
    dual_gRB = dualOut_gR * dual_levelB

    # 6. Sample-exact two-voice stereo mix: one buffer of exactly nTotal
    #    samples; each channel is a weighted sum of A(col) and B(col) and
    #    nothing else. A term whose gain is exactly 0 is left out entirely.
    dual_out = Create Sound from formula: "ReichDual_Mix", 2, 0, dual_nTotal / dual_sr, dual_sr, "0"
    dual_nCheck = Get number of samples
    if dual_nCheck <> dual_nTotal
        dual_error$ = "Internal error: mix buffer has " + string$(dual_nCheck) + " samples, expected " + string$(dual_nTotal) + "."
        @dualAbort
    endif
    .left$ = ""
    if dual_gLA <> 0
        .left$ = string$(dual_gLA) + " * " + dualA_read$
    endif
    if dual_gLB <> 0
        if .left$ <> ""
            .left$ = .left$ + " + "
        endif
        .left$ = .left$ + string$(dual_gLB) + " * " + dualB_read$
    endif
    if .left$ = ""
        .left$ = "0"
    endif
    .right$ = ""
    if dual_gRA <> 0
        .right$ = string$(dual_gRA) + " * " + dualA_read$
    endif
    if dual_gRB <> 0
        if .right$ <> ""
            .right$ = .right$ + " + "
        endif
        .right$ = .right$ + string$(dual_gRB) + " * " + dualB_read$
    endif
    if .right$ = ""
        .right$ = "0"
    endif
    dual_formula$ = "if row = 1 then " + .left$ + " else " + .right$ + " fi"
    selectObject: dual_out
    Formula: dual_formula$

    # Mono fold-down check before normalisation: RMS of (L+R)/2 against the
    # mean channel RMS.
    selectObject: dual_out
    dual_rmsStereo = Get root-mean-square: 0, 0
    .monoTmp = Convert to mono
    dual_rmsMono = Get root-mean-square: 0, 0
    removeObject: .monoTmp
    dual_monoFoldDb = undefined
    if dual_rmsStereo > 0 and dual_rmsMono > 0
        dual_monoFoldDb = 20 * log10(dual_rmsMono / dual_rmsStereo)
    endif

    selectObject: dual_out
    dual_peakRaw = Get absolute extremum: 0, 0, "None"
    if dual_peakRaw > 0
        Scale peak: 0.99
    endif
    Rename: dual_sourceName$ + "_ReichGen_Dual"

    # 7. Timing measurements shared by the Info window, Summary and figure.
    dual_T = dual_nTotal / dual_sr
    dualA_L = dualA_n / dual_sr
    dualB_L = dualB_n / dual_sr
    dualA_f = dualA_v * dual_sr / dualA_n
    dualB_f = dualB_v * dual_sr / dualB_n
    dualA_u0 = (dualA_offS + dualA_eps) / dualA_n
    dualB_u0 = (dualB_offS + dualB_eps) / dualB_n
    dual_df = dualB_f - dualA_f
    # Stationary when the relative phase moves by less than a millionth of
    # a cycle over the whole render: no drift is reported or drawn.
    dual_stationary = abs(dual_df) * dual_T < 1e-6
    dual_relCycle = undefined
    if not dual_stationary
        dual_relCycle = 1 / abs(dual_df)
    endif
    # Cycles traversed = |fB - fA| * T (exact, may be fractional); "full"
    # is its integer part. Counting wraps instead would count a spurious
    # one at t = 0 whenever the relationship starts exactly at 0 deg and
    # B falls behind. Displayed degrees within 0.005 of 360 read as 0.
    @dualRel: 0
    dual_relStartDeg = 360 * dualOut_phase
    if dual_relStartDeg > 359.995
        dual_relStartDeg = 0
    endif
    @dualRel: dual_T
    dual_relEndDeg = 360 * dualOut_phase
    if dual_relEndDeg > 359.995
        dual_relEndDeg = 0
    endif
    dual_relCyclesExact = abs(dual_df) * dual_T
    dual_relCycles = floor(dual_relCyclesExact + 1e-9)
    if dual_stationary
        dual_relCyclesExact = 0
        dual_relCycles = 0
        dual_direction$ = "stationary"
    elsif dual_df > 0
        dual_direction$ = "B gains on A"
    else
        dual_direction$ = "B falls behind A"
    endif

    # 8. Cleanup (loops and streams survive only for a test that asks).
    if dual_keep_intermediates = 0
        @dualRemoveIntermediates
    endif

    # 9. Info window.
    appendInfoLine: "Source: ", dual_sourceName$, "  (", fixed$(dual_srcDur, 3), " s, ", dual_sourceChannels, " ch, ", dual_sr, " Hz)"
    @dualSemitones: dualA_v
    appendInfoLine: "Unit A: Region ", fixed$(dualA_snapStart, 4), "-", fixed$(dualA_snapEnd, 4), " s (requested ", fixed$(dual_A_Start_sec, 3), "-", fixed$(dual_A_End_sec, 3), "), loop ", fixed$(dualA_L, 4), " s (", dualA_n, " samples) | rate ", fixed$(dualA_ratePct, 3), "% (", fixed$(dualOut_st, 2), " st) | period ", fixed$(1 / dualA_f, 4), " s | start ", fixed$(dual_A_Start_Offset_percent, 1), "% of loop (sample ", dualA_offS, ")"
    @dualSemitones: dualB_v
    .derived$ = ""
    if dual_Timing$ = "Target Relative Cycle"
        .derived$ = ", derived"
    endif
    appendInfoLine: "Unit B: Region ", fixed$(dualB_snapStart, 4), "-", fixed$(dualB_snapEnd, 4), " s (requested ", fixed$(dual_B_Start_sec, 3), "-", fixed$(dual_B_End_sec, 3), "), loop ", fixed$(dualB_L, 4), " s (", dualB_n, " samples) | rate ", fixed$(dualB_ratePct, 3), "%", .derived$, " (", fixed$(dualOut_st, 2), " st) | period ", fixed$(1 / dualB_f, 4), " s | start ", fixed$(dual_B_Start_Offset_percent, 1), "% of loop (sample ", dualB_offS, ")"
    appendInfoLine: "Rates are plain resampling: speed and pitch change together (not a time stretch)."
    if dual_Timing$ = "Target Relative Cycle"
        appendInfoLine: "Timing: Target Relative Cycle ", fixed$(dual_Target_Cycle_min, 3), " min, ", dual_Drift_Direction$, " (Unit B's typed rate is not used)."
    else
        appendInfoLine: "Timing: Independent Rates."
    endif
    if dual_stationary
        appendInfoLine: "Relative loop phase (B - A): STATIONARY -- equal loop frequencies, no relative drift; it stays at ", fixed$(dual_relStartDeg, 2), " deg."
    else
        appendInfoLine: "Relative loop phase (B - A): cycle ", fixed$(dual_relCycle, 4), " s = 1 / |fB - fA| (fA ", fixed$(dualA_f, 6), ", fB ", fixed$(dualB_f, 6), " loops/s) | ", dual_direction$, " | ", fixed$(dual_relCyclesExact, 2), " relative cycles in this render | start ", fixed$(dual_relStartDeg, 2), " deg, end ", fixed$(dual_relEndDeg, 2), " deg"
        if dual_relCycle > dual_T
            appendInfoLine: "  (the relative cycle is longer than the render: less than one full cycle is heard)"
        endif
    endif
    appendInfoLine: "Stereo separation ", fixed$(dual_Stereo_Separation_percent, 1), "% -> pans A ", fixed$(dual_panA, 1), ", B ", fixed$(dual_panB, 1), " (equal-power; gains L/R A ", fixed$(dual_gLA, 4), "/", fixed$(dual_gRA, 4), ", B ", fixed$(dual_gLB, 4), "/", fixed$(dual_gRB, 4), ")"
    if dual_gRA = 0 and dual_gLB = 0
        appendInfoLine: "  Full isolation: left channel = Unit A only, right channel = Unit B only."
    endif
    appendInfoLine: "Unit B level: ", fixed$(dual_B_Level_dB, 2), " dB relative to Unit A (x", fixed$(dual_levelB, 4), ")"
    if dual_monoFoldDb <> undefined
        appendInfoLine: "Mono fold-down: (L+R)/2 RMS is ", fixed$(dual_monoFoldDb, 2), " dB relative to the stereo channel RMS."
    endif
    appendInfoLine: "Output: ", dual_nTotal, " samples x 2 channels = ", fixed$(dual_T, 6), " s (", fixed$(total_Duration_min, 3), " min requested); peak-normalised to 0.99"
    selectObject: dual_out
endproc

# ------------------------------------------------------------
# Dual visualization
# ------------------------------------------------------------

# Text in a strip of its own. Font size is set BEFORE the viewport (Praat
# derives viewport margins from the current font size), and the viewport is
# re-selected for every call because Text leaves the drawing frame on the
# outer viewport.
procedure dualStripText: .x1, .x2, .y1, .y2, .fs, .x, .align$, .col$, .text$
    Font size: .fs
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: 0, 1, 0, 1
    Colour: .col$
    Text: .x, .align$, 0.5, "half", .text$
endproc

procedure dualFrame: .x1, .x2, .y1, .y2, .ax1, .ax2, .ay1, .ay2
    Select inner viewport: .x1, .x2, .y1, .y2
    Axes: .ax1, .ax2, .ay1, .ay2
endproc

procedure dualNiceStep: .span, .target
    .raw = .span / .target
    .mag = 10 ^ floor(log10(.raw))
    .r = .raw / .mag
    if .r < 1.5
        dualOut_step = .mag
    elsif .r < 3.5
        dualOut_step = 2 * .mag
    elsif .r < 7.5
        dualOut_step = 5 * .mag
    else
        dualOut_step = 10 * .mag
    endif
endproc

# One wheel for the ONE inter-unit relationship (square inner viewport, as
# in the Classic wheel). Angle = relative loop phase frac(uB - uA); radius =
# output time (centre = start, rim = end), so the path is a spiral whose
# turns are the relative cycles, and a stationary relationship is a single
# radial line. Colour runs light -> dark along time. No unison / anti-phase
# semantics: 0 deg means both units are at the same fraction of their own
# loops, which is not acoustic alignment of two different sounds.
procedure dualRelWheel: .x1, .x2, .y1, .y2
    .tTotal = dual_T
    Font size: 10
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Paint rectangle: "{0.985, 0.985, 0.985}", 0, 100, 0, 100

    Colour: "{0.80, 0.80, 0.80}"
    Line width: 0.8
    Draw circle: 50, 50, 45
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 0.55
    Dotted line
    Draw line: 50, 50, 50, 95
    Draw line: 50, 50, 95, 50
    Draw line: 50, 50, 50, 5
    Draw line: 50, 50, 5, 50
    Solid line
    Line width: 1

    .rIn = 6
    .rOut = 42
    .turns = abs(dual_df) * .tTotal
    .samples = min(40000, max(900, round(90 * (.turns + 1))))
    .dt = .tTotal / (.samples - 1)
    .lw = 1.3
    if .turns > 12
        .lw = 0.8
    endif
    Line width: .lw
    .prevX = 0
    .prevY = 0
    for .i from 1 to .samples
        .t = (.i - 1) * .dt
        @dualRel: .t
        .ang = dualOut_phase * 2 * pi
        .c = .t / .tTotal
        .r = .rIn + (.rOut - .rIn) * .c
        .x = 50 + .r * sin(.ang)
        .y = 50 + .r * cos(.ang)
        Colour: {0.78 - 0.50 * .c, 0.76 - 0.58 * .c, 0.92 - 0.36 * .c}
        if .i > 1
            Draw line: .prevX, .prevY, .x, .y
        endif
        .prevX = .x
        .prevY = .y
    endfor
    Line width: 1
    @dualRel: 0
    .sx = 50 + .rIn * sin(dualOut_phase * 2 * pi)
    .sy = 50 + .rIn * cos(dualOut_phase * 2 * pi)
    Colour: "Black"
    Paint circle (mm): "White", .sx, .sy, 1.1
    Draw circle (mm): .sx, .sy, 1.1
    Paint circle (mm): dualRel_colour$, .prevX, .prevY, 1.5
    Draw circle (mm): .prevX, .prevY, 1.5

    # Labels last, each after a fresh frame (Text special moves the frame).
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Colour: "{0.20, 0.20, 0.20}"
    Text special: 50, "centre", 99, "top", "Helvetica", 8, "0", "0° aligned"
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 98, "right", 50, "half", "Helvetica", 7, "0", "90°"
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 50, "centre", 1, "bottom", "Helvetica", 8, "0", "180° opposite"
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 2, "left", 50, "half", "Helvetica", 7, "0", "270°"
    # Corner notes (outside the r = 45 ring, so never on the path).
    if dual_stationary
        .tl$ = "stationary: no relative drift"
        .tr$ = "equal loop frequencies"
    else
        .tl$ = "relative cycles: " + fixed$(dual_relCyclesExact, 1)
        .tr$ = "cycle " + fixed$(dual_relCycle, 2) + " s"
    endif
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Colour: "{0.35, 0.35, 0.35}"
    Text special: 3, "left", 97, "top", "Helvetica", 6, "0", .tl$
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 97, "right", 97, "top", "Helvetica", 6, "0", .tr$
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 3, "left", 3, "bottom", "Helvetica", 6, "0", "radius = output time"
    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Text special: 97, "right", 3, "bottom", "Helvetica", 6, "0", "start " + fixed$(dual_relStartDeg, 0) + "°  end " + fixed$(dual_relEndDeg, 0) + "°"

    @dualFrame: .x1, .x2, .y1, .y2, 0, 100, 0, 100
    Colour: "Black"
    Draw inner box
endproc

# One lane: a unit's own loop position (0..100% of its loop) over the first
# .w seconds -- a sawtooth whose drops are the unit's loop restarts.
procedure dualLane: .x1, .x2, .y1, .y2, .w, .unit, .col$, .numbers
    Font size: 6
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .w, -0.08, 1.08
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 0.6
    Draw line: 0, 0.5, .w, 0.5
    Colour: "{0.70, 0.70, 0.70}"
    Draw line: 0, 0, .w, 0
    Draw line: 0, 1, .w, 1
    .samples = 1600
    .dt = .w / (.samples - 1)
    Colour: .col$
    Line width: 1.3
    .prevT = 0
    .prevP = 0
    for .i from 1 to .samples
        .t = (.i - 1) * .dt
        @dualRel: .t
        if .unit = 1
            .u = dualOut_uA
        else
            .u = dualOut_uB
        endif
        .p = .u - floor(.u)
        if .i > 1 and .p >= .prevP
            Draw line: .prevT, .prevP, .t, .p
        endif
        .prevT = .t
        .prevP = .p
    endfor
    Line width: 1
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    Colour: "Black"
    Draw inner box
    @dualNiceStep: .w, 6
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    if .numbers
        Marks bottom every: 1, dualOut_step, "yes", "yes", "no"
        @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
        Text bottom: "yes", "Output time (s)"
    else
        Marks bottom every: 1, dualOut_step, "no", "yes", "no"
    endif
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    One mark left: 0, "no", "yes", "no", "0"
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    One mark left: 0.5, "no", "yes", "no", "50\% "
    @dualFrame: .x1, .x2, .y1, .y2, 0, .w, -0.08, 1.08
    One mark left: 1, "no", "yes", "no", "100\% "
endproc

procedure dualDraw
    .tTotal = dual_T
    .disp$ = replace$(dual_sourceName$, "_", " ", 0)
    .xmin = dual_srcXmin
    .xmax = dual_srcXmax

    Erase all
    Colour: "Black"
    Line width: 1
    Solid line

    # ------------------------------------------------------------
    # LAYOUT (inches, 8.00 x 7.58 canvas -- the library standard page):
    #   Title                                   0.02 - 0.28
    #   Headers                                 0.32 - 0.48
    #   Relative-phase wheel, 3.30 x 3.30 sq.   0.52 - 3.82  (x 0.55 - 3.85)
    #   Unit lanes A / B (right column)         0.52 - 3.46  (x 4.45 - 7.75)
    #   Region labels                           3.98 - 4.10
    #   Source waveform                         4.12 - 4.70
    #   Trajectory header + key                 4.80 - 4.96
    #   Relative phase trajectory               5.00 - 6.05  (+ axis)
    #   Summary                                 6.64 - 7.54
    # ------------------------------------------------------------
    @dualStripText: 0, 8, 0.02, 0.28, 12, 0.5, "centre", "Black", "##Reich Generator — Dual Locked Loops##"

    .longest = max(1 / dualA_f, 1 / dualB_f)
    .w = min(.tTotal, 6 * .longest)
    @dualStripText: 0.55, 3.85, 0.32, 0.48, 9, 0.5, "centre", dualRel_colour$, "##Relative loop phase##  (B − A)"
    @dualStripText: 4.45, 7.75, 0.32, 0.48, 9, 0.5, "centre", "Black", "##Two units##  (loop position, first " + fixed$(.w, 1) + " s)"

    @dualRelWheel: 0.55, 3.85, 0.52, 3.82

    @dualStripText: 4.45, 7.75, 0.52, 0.66, 7, 0, "left", dualA_colour$, "##Unit A##  Region A, rate " + fixed$(dualA_ratePct, 2) + "\% , period " + fixed$(1 / dualA_f, 3) + " s"
    @dualLane: 4.45, 7.75, 0.70, 1.95, .w, 1, dualA_colour$, 0
    @dualStripText: 4.45, 7.75, 2.03, 2.17, 7, 0, "left", dualB_colour$, "##Unit B##  Region B, rate " + fixed$(dualB_ratePct, 2) + "\% , period " + fixed$(1 / dualB_f, 3) + " s"
    @dualLane: 4.45, 7.75, 2.21, 3.46, .w, 2, dualB_colour$, 1

    # SOURCE with both locked regions.
    selectObject: dual_source
    .srcPeak = Get absolute extremum: 0, 0, "None"
    .waveY = .srcPeak * 1.15
    if .waveY <= 0
        .waveY = 1
    endif
    .aS = .xmin + dualA_snapStart
    .aE = .xmin + dualA_snapEnd
    .bS = .xmin + dualB_snapStart
    .bE = .xmin + dualB_snapEnd

    Font size: 10
    @dualFrame: 0.55, 7.75, 3.98, 4.10, .xmin, .xmax, 0, 1
    Colour: dualA_colour$
    Text special: (.aS + .aE) / 2, "centre", 0.5, "half", "Helvetica", 7, "0", "##A##"
    @dualFrame: 0.55, 7.75, 3.98, 4.10, .xmin, .xmax, 0, 1
    Colour: dualB_colour$
    Text special: (.bS + .bE) / 2, "centre", 0.5, "half", "Helvetica", 7, "0", "##B##"

    @dualFrame: 0.55, 7.75, 4.12, 4.70, .xmin, .xmax, -.waveY, .waveY
    Paint rectangle: "{0.97, 0.97, 0.97}", .xmin, .xmax, -.waveY, .waveY
    Paint rectangle: dualA_tint$, .aS, .aE, -.waveY, .waveY
    Paint rectangle: dualB_tint$, .bS, .bE, -.waveY, .waveY
    selectObject: dual_source
    Colour: "{0.52, 0.52, 0.52}"
    Draw: .xmin, .xmax, -.waveY, .waveY, "no", "Curve"
    @dualFrame: 0.55, 7.75, 4.12, 4.70, .xmin, .xmax, -.waveY, .waveY
    Colour: "{0.84, 0.84, 0.84}"
    Draw line: .xmin, 0, .xmax, 0
    Line width: 1.3
    Colour: dualA_colour$
    Draw line: .aS, -.waveY, .aS, .waveY
    Draw line: .aE, -.waveY, .aE, .waveY
    Colour: dualB_colour$
    Draw line: .bS, -.waveY, .bS, .waveY
    Draw line: .bE, -.waveY, .bE, .waveY
    Line width: 1
    @dualFrame: 0.55, 7.75, 4.12, 4.70, .xmin, .xmax, -.waveY, .waveY
    Colour: "Black"
    Draw inner box
    Font size: 10
    @dualFrame: 0.55, 7.75, 4.12, 4.70, .xmin, .xmax, -.waveY, .waveY
    Colour: "{0.45, 0.45, 0.45}"
    .srcLabelX = .xmin - 0.04920 * (.xmax - .xmin)
    Text special: .srcLabelX, "centre", 0, "half", "Times", 6, "90", "Source"

    # RELATIVE PHASE TRAJECTORY -- the one relationship, over the whole render.
    @dualStripText: 0.55, 7.75, 4.80, 4.96, 8, 0, "left", "Black", "##Relative loop phase over time##  (B − A, fraction of each unit's own loop)"
    @dualStripText: 0.55, 7.75, 4.80, 4.96, 6, 1, "right", "{0.45, 0.45, 0.45}", "open dot = start  |  filled dot = end  |  gap = wrap"

    .yLo = -25
    .yHi = 385
    Font size: 6
    @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, .tTotal, .yLo, .yHi
    Colour: "{0.86, 0.86, 0.86}"
    Line width: 0.6
    Draw line: 0, 90, .tTotal, 90
    Draw line: 0, 180, .tTotal, 180
    Draw line: 0, 270, .tTotal, 270
    Colour: "{0.45, 0.45, 0.45}"
    Line width: 1.0
    Draw line: 0, 0, .tTotal, 0
    Draw line: 0, 360, .tTotal, 360

    .turns = abs(dual_df) * .tTotal
    .samples = min(40000, max(1201, round(60 * (.turns + 1))))
    .dt = .tTotal / (.samples - 1)
    .prevDeg = 0
    .prevT = 0
    Colour: dualRel_colour$
    Line width: 1.2
    for .i from 1 to .samples
        .t = (.i - 1) * .dt
        @dualRel: .t
        .deg = 360 * dualOut_phase
        if .i > 1
            if abs(.deg - .prevDeg) < 180
                Draw line: .prevT, .prevDeg, .t, .deg
            endif
        endif
        .prevT = .t
        .prevDeg = .deg
    endfor
    Line width: 1
    Colour: dualRel_colour$
    Paint circle (mm): "White", 0, dual_relStartDeg, 1.1
    Draw circle (mm): 0, dual_relStartDeg, 1.1
    Paint circle (mm): dualRel_colour$, .tTotal, .prevDeg, 1.2

    @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
    Colour: "Black"
    Draw inner box
    @dualNiceStep: .tTotal, 6
    @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
    Marks bottom every: 1, dualOut_step, "yes", "yes", "no"
    @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
    Text bottom: "yes", "Output time (s)"
    @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
    Text left: "yes", "B − A (deg)"
    for .k from 0 to 4
        @dualFrame: 0.55, 7.75, 5.00, 6.05, 0, .tTotal, .yLo, .yHi
        One mark left: .k * 90, "no", "yes", "no", string$(.k * 90) + "°"
    endfor

    # SUMMARY.
    Font size: 6
    @dualFrame: 0.30, 7.80, 6.64, 7.54, 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "{0.48, 0.48, 0.48}"
    Draw rectangle: 0, 1, 0, 1

    .timing$ = "independent rates"
    if dual_Timing$ = "Target Relative Cycle"
        .timing$ = "target relative cycle " + fixed$(dual_Target_Cycle_min, 2) + " min (B rate derived)"
    endif
    .line1$ = .disp$ + "  |  duration " + fixed$(.tTotal / 60, 2) + " min  |  " + .timing$ + "  |  stereo separation " + fixed$(dual_Stereo_Separation_percent, 0) + "\%  |  Unit B level " + fixed$(dual_B_Level_dB, 1) + " dB"
    .lineA$ = "Unit A  " + fixed$(dualA_snapStart, 3) + "-" + fixed$(dualA_snapEnd, 3) + " s  |  loop " + fixed$(dualA_L, 3) + " s  |  rate " + fixed$(dualA_ratePct, 2) + "\%  |  start " + fixed$(dual_A_Start_Offset_percent, 0) + "\%  of loop  |  pan " + fixed$(dual_panA, 0)
    .lineB$ = "Unit B  " + fixed$(dualB_snapStart, 3) + "-" + fixed$(dualB_snapEnd, 3) + " s  |  loop " + fixed$(dualB_L, 3) + " s  |  rate " + fixed$(dualB_ratePct, 2) + "\%  |  start " + fixed$(dual_B_Start_Offset_percent, 0) + "\%  of loop  |  pan " + fixed$(dual_panB, 0)
    if dual_stationary
        .line4$ = "Relative loop phase B − A: stationary (equal loop frequencies), fixed at " + fixed$(dual_relStartDeg, 1) + "°"
    else
        .line4$ = "Relative loop phase B − A: cycle " + fixed$(dual_relCycle, 3) + " s  |  " + dual_direction$ + "  |  " + fixed$(dual_relCyclesExact, 2) + " cycles in the render  |  start " + fixed$(dual_relStartDeg, 1) + "°, end " + fixed$(dual_relEndDeg, 1) + "°"
    endif

    @dualStripText: 0.30, 7.80, 6.66, 6.82, 7, 0.02, "left", "Black", "##Summary##"
    @dualStripText: 0.30, 7.80, 6.84, 6.98, 6, 0.02, "left", "{0.28, 0.28, 0.28}", .line1$
    @dualStripText: 0.30, 7.80, 7.00, 7.14, 6, 0.02, "left", dualA_colour$, .lineA$
    @dualStripText: 0.30, 7.80, 7.16, 7.30, 6, 0.02, "left", dualB_colour$, .lineB$
    @dualStripText: 0.30, 7.80, 7.32, 7.46, 6, 0.02, "left", dualRel_colour$, .line4$

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Leave the whole page selected so Save/Copy from the Picture window
    # exports the full figure rather than the last panel.
    Select outer viewport: 0, 8, 0, 7.58
endproc

# <<< DUAL ENGINE END
# ============================================================
