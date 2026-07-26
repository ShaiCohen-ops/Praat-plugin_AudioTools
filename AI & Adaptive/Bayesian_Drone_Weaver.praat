# ============================================================
# Praat AudioTools - Bayesian_Drone_Weaver.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2026) - Second correctness pass: overlap/fade now agree,
#                        Scale intensity uses dB subtraction not
#                        multiplication, intensity-window math corrected,
#                        AGC/dynamics claim reconciled, Pulse honestly
#                        captioned, Praat 6.4+ requirement stated.
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bayesian Drone Weaver - Generative composition system that analyzes
#   audio clips, scores them with a Bayesian-inspired probabilistic
#   gesture classifier (softmax over heuristic per-class scores, not
#   calibrated log-likelihoods of an estimated distribution), and
#   assembles them into evolving drone textures.
#
# Requires Praat 6.4 or later (uses fileNames_caseInsensitive$#, added in
# that release; earlier versions will error immediately during folder scan).
#
# Usage:
#   Run this script. Type an audio-clip folder path into the form, or
#   leave the Folder field blank to pick one with a dialog.
#
# Changelog v0.7 (2026) - second correctness pass, see code review:
#   1. buildTimeline's overlap cap changed from 0.8 to 0.5 * min(prev_dur,
#      curr_dur), matching assembleDrone's independent .duration/2 fade
#      cap. Previously an overlap between 50-80% of a clip's duration was
#      stored in the timeline but then silently shortened by the fade
#      cap, so Fade in/Fade out no longer spanned the same interval and
#      stopped forming a true complementary crossfade (gain could sum to
#      >1 across part of the overlap).
#   2. Fixed a real level bug: in the Even-level 'soften' branch, `Scale
#      intensity` takes a target dB SPL, not an amplitude multiplier, so
#      `.scale * level_target_db` (e.g. 70 * 0.5 = 35 dB) was moving the
#      target itself -- a ~35 dB / ~56x cut for a fully Pulse-scored clip,
#      not a gentle pull-down. Replaced with a bounded dB subtraction
#      (new max_soften_attenuation_db constant, default 5 dB).
#   3. Corrected the intensity-analysis-window comment: Praat's effective
#      window is 3.2 / pitch floor, not 1 / pitch floor as an earlier
#      comment here claimed. At intensity_pitch_floor = 40 Hz these give
#      different values (3.2/40 = 80 ms vs 1/40 = 25 ms) -- the earlier
#      comment's number (~80 ms) was right, its formula was wrong -- and
#      raised min_clip_duration 0.3 -> 0.4 s so each quarter-clip window
#      (duration / 4) is comfortably wider than the real 80 ms analysis
#      window instead of narrower than it.
#   4. Removed the inaccurate "keeping within-clip dynamics" claim before
#      the flattenLoudness call; flattenLoudness's own documentation
#      already correctly says it flattens fades, crossfades, and slow
#      envelope breathing too, so the two comments contradicted each
#      other. The call site now matches.
#   5. Softened the buildTimeline target-reachability comment: Flow,
#      Growth, Edge and Space are all derived from the same five
#      posterior probabilities, so each one being inside its own marginal
#      range doesn't guarantee the combined 4D target is reachable --
#      only that the search is closer to the feasible region than before.
#   6. Documented the Pulse class honestly at its definition: its features
#      (intensity std dev, low harmonicity, negative-motion bonus) don't
#      measure periodicity, onset density, or modulation rate, so it's an
#      artistic label, not an acoustic pulse detector, unless a
#      modulation/onset feature is added later.
#   7. Added an explicit "Requires Praat 6.4 or later" note, since
#      fileNames_caseInsensitive$# was only added in that release.
#   8. Reordered assembleDrone: Scale intensity now runs BEFORE Fade
#      in/Fade out (was after). Normalizing an already-faded clip lets
#      the fade length leak into the achieved level -- a long-faded or
#      short clip has lower average energy at the point of measurement,
#      so Praat compensates with more whole-clip gain, making the
#      result depend on overlap/clip duration rather than only on
#      source loudness. Normalizing the unfaded source first makes
#      "Even level" mean equal source levels, with the fades then
#      purely shaping entrances/exits/overlaps on top.
#
# Changelog v0.6 (2026) - correctness pass, see code review:
#   1. Overlap is now clamped to a fraction of both the previous and
#      current clip's duration (not just an absolute 2 s ceiling), so it
#      can no longer exceed a clip's own length and produce a negative
#      or out-of-order start time. Minimum clip duration raised from
#      0.1 s to min_clip_duration (see CONSTANTS) so very short clips
#      that don't survive the intensity analysis window are rejected
#      up front instead of misbehaving downstream.
#   2. assembleDrone's fade-in/fade-out for the shared boundary between
#      two clips are now BOTH derived from the same stored overlap
#      duration (timeline_overlap_'seg'), so they form a real
#      complementary crossfade instead of two independently-computed
#      fade lengths that happened to be called a crossfade.
#   3. Renamed/annotated the classifier as "Bayesian-inspired": the
#      .ll_* terms are heuristic per-class scores, not fitted
#      log-likelihoods, and the uniform prior (ln(0.2) added to every
#      class) is correctly documented as canceling in the softmax
#      rather than implied to be doing something it isn't.
#   4. Classifier features are normalized to comparable ranges before
#      being combined (see the norm_* constants and the start of
#      classifyGesture), instead of mixing raw dB, dB/s, Hz and HNR
#      units directly, which previously let motion and brightness terms
#      dominate the score.
#   5. Timeline phase targets (intro/development/climax/resolution)
#      moved into the ranges computeMacros can actually produce, so the
#      nearest-clip search is choosing among reachable points instead
#      of always approximating an unreachable corner.
#   6. intensity_floor renamed to intensity_pitch_floor (it is Praat's
#      Pitch floor parameter to "To Intensity...", not a level
#      threshold) and the minimum clip duration raised so quarter-clip
#      windows are compatible with the effective analysis window
#      (~80 ms at 40 Hz; see v0.7 #3 for the corrected formula).
#   7. processClip now checks every extracted feature for `undefined`
#      (e.g. from a silent or near-silent clip) and rejects the clip
#      instead of letting an undefined value contaminate the
#      classifier and timeline.
#   8. "Even loudness" renamed to "Even level" throughout the UI and
#      comments: Scale intensity matches Praat's RMS-based dB SPL
#      convention, not perceptual loudness or LUFS.
#   9. Fixed a real logic bug: Dramatic arc (output_level = 1) was
#      still calling Scale intensity on any clip with soften > 0.5,
#      contradicting its own documentation. It now never rescales
#      clip level; only the Even-level modes (2, 3) do.
#  10. flattenLoudness relabeled/annotated accurately as an envelope
#      AGC/compressor (it already was one) so its effect on within-clip
#      fades and slow gestures isn't undersold as gentle leveling.
#  Minor:
#   - Textural preset's max_clips (40) is no longer silently capped by
#     a hardcoded 30-segment timeline; the cap now follows max_clips.
#   - File discovery now also matches .aif, and matches every extension
#     case-insensitively (fileNames_caseInsensitive$#) so .WAV/.AIFF on
#     case-sensitive filesystems are found too. Files are now loaded in
#     round-robin order across formats rather than exhausting WAV, then
#     AIFF, then FLAC, so file type no longer biases which clips survive
#     the max_clips cutoff.
#
# Changelog v0.5 (2026):
#   - Added an "Output level" form option. The clips are never loudness-
#     matched (processClip resamples but does not normalize level) and the
#     timeline picks clips by gesture, not loudness — so each section's
#     volume just followed whichever clips it used, and a single global
#     peak-normalize left the airy, fading-in opening sounding very quiet.
#     Options:
#       * Dramatic arc (original): clips keep their inherent recording
#         level (unchanged behaviour).
#       * Even loudness: every clip is normalized to a common intensity
#         (level_target_db), AND the assembled output's slow loudness
#         contour is flattened by a low-passed envelope AGC
#         (flattenLoudness) so the section-to-section swell is evened out.
#         (Per-clip averaging alone did not flatten the contour, since a
#         long-faded clip still has a quiet contour even at a matched
#         average level. NOTE, superseded by v0.6 #10 and v0.7 #4: the
#         AGC also flattens within-clip fades and slow gestures, it does
#         not leave them riding on top untouched -- see flattenLoudness.)
#       * Even loudness, quick start: same, plus the opening clip's
#         fade-in is capped short so the piece does not begin faint.
#     (Note: an earlier draft tried to divide the mix by an overlap-count
#     envelope, but the clips already crossfade at their overlaps, so the
#     summed gain stays ~1 and that had no audible effect — per-clip
#     normalization is the mechanism that matters.)
#
# Changelog v0.4 (2026):
#   - Added a "Folder" form field (mirrors VoidMosaic): type a path, or
#     leave it blank to fall back to a folder-selection dialog. The path
#     is whitespace- and trailing-slash-trimmed; cancelling the dialog
#     exits cleanly.
#
# Changelog v0.3 (2026):
#   - FIX: assembleDrone's mix Formula used "Object_<id>[...]" which
#     resolves by name, not numeric ID, and would fail at runtime.
#     Replaced with the correct "object[<id>, col - offset]" idiom.
#   - FIX: The same Formula had an off-by-one: when start_sample = 0,
#     it read part sample 2 at buffer col 1. Corrected so part col 1
#     aligns with buffer col (offset + 1).
#   - FIX: Terminator "endif" inside Formula string replaced with
#     "fi" which is the correct token in Praat's Formula language.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Bayesian Drone Weaver v0.7
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
    comment === Composition Style ===
    optionmenu Preset: 1
        option Custom
        option Ambient (slow evolution)
        option Cinematic (dramatic arc)
        option Meditative (sustained)
        option Textural (varied)
    comment === Parameters ===
    positive Max_clips 30
    positive Overlap_factor 1.0
    comment === Output level (controls the quiet-start / changing-volume) ===
    optionmenu Output_level: 1
        option Dramatic arc (original)
        option Even level
        option Even level, quick start
    boolean Draw_visualization 1
endform

# Apply presets
if preset = 2
    # Ambient
    max_clips = 20
    overlap_factor = 1.2
    presetName$ = "Ambient"
elsif preset = 3
    # Cinematic
    max_clips = 30
    overlap_factor = 0.8
    presetName$ = "Cinematic"
elsif preset = 4
    # Meditative
    max_clips = 15
    overlap_factor = 1.5
    presetName$ = "Meditative"
elsif preset = 5
    # Textural
    max_clips = 40
    overlap_factor = 0.6
    presetName$ = "Textural"
else
    presetName$ = "Custom"
endif

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the field is left blank. Trim whitespace and trailing slashes first.
folder$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)

if folder$ == ""
    folder$ = chooseFolder$: "Select folder with audio clips"
    folder$ = replace_regex$(folder$, "[\\/]+$", "", 0)
endif

if folder$ == ""
    exitScript: "Operation cancelled. Please supply a valid audio folder path."
endif

# --- CONSTANTS ---
target_sr = 44100
min_clips = 3
level_target_db = 70   ; common per-clip intensity for the even-level modes
max_soften_attenuation_db = 5   ; dB below level_target_db for the most
                                 ; Pulse-heavy clip (soften = 1); a mild,
                                 ; deliberate pull-down, not a near-mute

# Minimum clip duration. Raised from the old 0.1 s: To Intensity's actual
# effective analysis window is 3.2 / intensity_pitch_floor seconds (not
# 1 / intensity_pitch_floor as an earlier comment here claimed), which is
# 80 ms at intensity_pitch_floor = 40 Hz below. processClip further splits
# each clip into quarters for the early/late intensity comparison, so each
# quarter (duration / 4) must itself be comfortably wider than that 80 ms
# window, or a quarter can contain too few intensity frames (worse still
# at intensity_time_step = 0.05 s) and the resulting features become
# unstable or undefined. 0.3 s clips only give 75 ms quarters, narrower
# than the window; 0.4 s gives 100 ms quarters, safely above it.
min_clip_duration = 0.4
max_clip_duration = 30

# NOTE: this is Praat's "Pitch floor" parameter to "To Intensity...", not
# an intensity/level threshold - it sets the analysis window length, wider
# at lower values. Was misleadingly named intensity_floor.
intensity_pitch_floor = 40
intensity_time_step = 0.05 
pitch_floor = 75   ; tuned for voice/mid sources; fundamentals below this
                    ; may be missed for very low drones - lower if your
                    ; source material lives well under 75 Hz
pitch_ceiling = 600
harmonicity_time_step = 0.05

# --- CLASSIFIER FEATURE NORMALIZATION RANGES ---
# classifyGesture mixed raw dB, dB/s, Hz and HNR units directly, which let
# whichever term happened to have the largest numeric range dominate the
# score regardless of its actual musical relevance. Every feature is now
# mapped to a common ~[0,1] (or [-1,1] for the signed motion term) scale
# before the per-class scores are combined. These ranges are documented
# assumptions about typical clip content, not measured from a corpus;
# adjust them if your material runs unusually loud/quiet or bright/dark.
norm_intensity_lo = 30    ; dB, quiet clip
norm_intensity_hi = 90    ; dB, loud clip
norm_stdint_hi = 8        ; dB, a "very uneven" clip's intensity std dev
norm_motion_hi = 15       ; dB/s magnitude considered "fast" swell/decay
norm_bright_lo = 200      ; Hz, dark spectral centre of gravity
norm_bright_hi = 6000     ; Hz, bright spectral centre of gravity
norm_harm_lo = -10        ; dB HNR, noisy/inharmonic
norm_harm_hi = 25         ; dB HNR, strongly harmonic

# Bayesian hypothesis indices
h_sustain = 1
h_swell = 2
h_tension = 3
h_air = 4
h_pulse = 5   ; NAMING CAVEAT: scored from intensity std dev, low
              ; harmonicity, and a negative-motion bonus -- none of which
              ; measure actual periodicity, onset density, or modulation
              ; rate. An unstable/noisy or decaying clip can score high
              ; Pulse with no audible pulsation. Treat "Pulse" as an
              ; artistic label (roughly "unsettled/decaying") rather than
              ; an acoustic pulse-rate detector unless a modulation- or
              ; onset-based feature is added.
n_hypotheses = 5

clearinfo
writeInfoLine: "=== Bayesian Drone Weaver v0.7 ==="
appendInfoLine: "Preset: ", presetName$
if output_level = 2
    levelName$ = "Even level"
elsif output_level = 3
    levelName$ = "Even level, quick start"
else
    levelName$ = "Dramatic arc (original)"
endif
appendInfoLine: "Output level: ", levelName$
appendInfoLine: ""

# --- SCAN FOLDER ---
if right$(folder$, 1) <> "/" and right$(folder$, 1) <> "\"
    folder$ = folder$ + "/"
endif

# fileNames_caseInsensitive$# matches regardless of case, so .WAV/.Wav
# etc. are found on case-sensitive filesystems without listing every
# case variant by hand.
wav$# = fileNames_caseInsensitive$#: folder$ + "*.wav"
aiff$# = fileNames_caseInsensitive$#: folder$ + "*.aiff"
aif$# = fileNames_caseInsensitive$#: folder$ + "*.aif"
flac$# = fileNames_caseInsensitive$#: folder$ + "*.flac"

n_wav = size(wav$#)
n_aiff = size(aiff$#)
n_aif = size(aif$#)
n_flac = size(flac$#)
total_files = n_wav + n_aiff + n_aif + n_flac

appendInfoLine: "Found ", total_files, " audio files"

if total_files < min_clips
    exitScript: "Error: Need at least " + string$(min_clips) + " files."
endif

# --- PROCESS CLIPS ---
n_valid = 0

appendInfoLine: "Loading and analyzing clips..."

# Round-robin across formats (one file per format per pass) instead of
# exhausting WAV, then AIFF, then FLAC in sequence, so which format
# happens to be scanned first no longer decides which clips get in when
# max_clips is smaller than the total file count.
i_wav = 0
i_aiff = 0
i_aif = 0
i_flac = 0
more_files = 1
while n_valid < max_clips and more_files
    more_files = 0

    if n_valid < max_clips and i_wav < n_wav
        i_wav += 1
        filename$ = wav$#[i_wav]
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
        more_files = 1
    endif

    if n_valid < max_clips and i_aiff < n_aiff
        i_aiff += 1
        filename$ = aiff$#[i_aiff]
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
        more_files = 1
    endif

    if n_valid < max_clips and i_aif < n_aif
        i_aif += 1
        filename$ = aif$#[i_aif]
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
        more_files = 1
    endif

    if n_valid < max_clips and i_flac < n_flac
        i_flac += 1
        filename$ = flac$#[i_flac]
        soundID = Read from file: folder$ + filename$
        @processClip: soundID, n_valid
        if processClip.success
            n_valid += 1
            appendInfo: "."
        endif
        more_files = 1
    endif
endwhile

appendInfoLine: ""
appendInfoLine: "Loaded ", n_valid, " valid clips"

if n_valid < min_clips
    for i to n_valid
        removeObject: clip_sound_'i'
    endfor
    exitScript: "Error: Not enough valid clips loaded."
endif

# --- ANALYSIS & COMPOSITION ---
appendInfoLine: "Classifying gestures..."
for i to n_valid
    @classifyGesture: i
    @computeMacros: i
endfor

appendInfoLine: "Building timeline..."
@buildTimeline: n_valid

appendInfoLine: "Assembling drone..."
@assembleDrone

# Even-level modes: flatten the assembled output's slow loudness contour
# (section-to-section swell). Note this is a genuine AGC/compressor --
# see flattenLoudness below -- so it also flattens fades, crossfades,
# crescendos/decrescendos, and slow envelope "breathing", not only the
# section-to-section swell it targets; it does not selectively preserve
# within-clip dynamics.
if output_level >= 2
    appendInfoLine: "Applying envelope AGC/compressor to flatten the slow loudness contour..."
    @flattenLoudness: final_sound
endif

# --- FINALIZE ---
selectObject: final_sound
Scale peak: 0.95
Rename: "BayesianDrone_" + presetName$

# --- VISUALIZATION ---
if draw_visualization
    appendInfoLine: "Drawing visualization..."
    @drawVisualization: n_valid
endif

# --- CLEANUP SOURCE CLIPS ---
for i to n_valid
    removeObject: clip_sound_'i'
endfor

selectObject: final_sound

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: BayesianDrone_", presetName$
appendInfoLine: "Duration: ", fixed$(timeline_total_duration, 2), " s"
appendInfoLine: "Segments: ", timeline_n_segments

# ============================================================================
# PROCEDURES
# ============================================================================

procedure processClip: .soundID, .index
    .success = 0
    .sound = .soundID
    
    selectObject: .sound
    .nchannels = Get number of channels
    if .nchannels > 1
        .mono = Convert to mono
        removeObject: .sound
        .sound = .mono
    endif
    
    selectObject: .sound
    .sr = Get sampling frequency
    if .sr <> target_sr
        .resampled = Resample: target_sr, 50
        removeObject: .sound
        .sound = .resampled
    endif
    
    selectObject: .sound
    .duration = Get total duration
    
    # Validate duration
    if .duration < min_clip_duration or .duration > max_clip_duration
        removeObject: .sound
        .success = 0
    else
        # --- FEATURE EXTRACTION ---
        # Extract into local (procedure-scoped) variables first and only
        # commit to the clip_* arrays once every feature has passed the
        # undefined check below. A silent or near-silent clip can leave
        # intensity, harmonicity, or brightness undefined; letting that
        # flow into the classifier would contaminate its scores and the
        # whole timeline (see fix #7).

        # Intensity
        selectObject: .sound
        .intensity = To Intensity: intensity_pitch_floor, intensity_time_step, "yes"
        .mean_intensity = Get mean: 0, 0, "energy"
        .std_intensity = Get standard deviation: 0, 0
        
        .dur_quarter = .duration / 4
        .mean_early = Get mean: 0, .dur_quarter, "energy"
        .mean_late = Get mean: .duration - .dur_quarter, .duration, "energy"
        removeObject: .intensity
        
        # Spectrum
        selectObject: .sound
        .spectrum = To Spectrum: "yes"
        .brightness = Get centre of gravity: 2
        removeObject: .spectrum
        
        # Harmonicity
        selectObject: .sound
        .harmonicity = To Harmonicity (cc): harmonicity_time_step, pitch_floor, 0.1, 1.0
        .harmonicity_mean = Get mean: 0, 0
        removeObject: .harmonicity
        
        # Pitch / Voicing
        selectObject: .sound
        .pitch = To Pitch: 0.02, pitch_floor, pitch_ceiling
        .n_frames = Get number of frames
        .voiced_count = Count voiced frames
        removeObject: .pitch
        
        if .n_frames > 0
            .voiced_fraction = .voiced_count / .n_frames
        else
            .voiced_fraction = 0
        endif

        # Validity check: reject the clip if any extracted feature is
        # undefined (silent clip, all-unvoiced clip, etc.) rather than
        # letting an undefined value propagate into the classifier.
        .valid = 1
        if .mean_intensity = undefined or .std_intensity = undefined
            .valid = 0
        endif
        if .mean_early = undefined or .mean_late = undefined
            .valid = 0
        endif
        if .brightness = undefined or .harmonicity_mean = undefined
            .valid = 0
        endif

        if .valid
            .idx = .index + 1
            clip_sound_'.idx' = .sound
            clip_duration_'.idx' = .duration
            .intensity_motion = (.mean_late - .mean_early) / .duration

            clip_intensity_'.idx' = .mean_intensity
            clip_intensity_std_'.idx' = .std_intensity
            clip_intensity_motion_'.idx' = .intensity_motion
            clip_brightness_'.idx' = .brightness
            clip_harmonicity_'.idx' = .harmonicity_mean
            clip_voiced_'.idx' = .voiced_fraction
            
            .success = 1
        else
            removeObject: .sound
            .success = 0
        endif
    endif
endproc

procedure classifyGesture: .idx
    .intensity = clip_intensity_'.idx'
    .std_int = clip_intensity_std_'.idx'
    .motion = clip_intensity_motion_'.idx'
    .bright = clip_brightness_'.idx'
    .harm = clip_harmonicity_'.idx'
    .voiced = clip_voiced_'.idx'

    # --- Normalize each raw feature to a comparable range (see the
    # norm_* constants) before combining them. Clipped to [0,1] (or
    # [-1,1] for motion, which is signed) so no single feature's raw
    # units can dominate the score just because its numeric range
    # happens to be larger. ---
    .n_intensity = (.intensity - norm_intensity_lo) / (norm_intensity_hi - norm_intensity_lo)
    if .n_intensity < 0
        .n_intensity = 0
    elsif .n_intensity > 1
        .n_intensity = 1
    endif

    .n_std = .std_int / norm_stdint_hi
    if .n_std < 0
        .n_std = 0
    elsif .n_std > 1
        .n_std = 1
    endif

    .n_motion = .motion / norm_motion_hi
    if .n_motion < -1
        .n_motion = -1
    elsif .n_motion > 1
        .n_motion = 1
    endif

    .n_bright = (.bright - norm_bright_lo) / (norm_bright_hi - norm_bright_lo)
    if .n_bright < 0
        .n_bright = 0
    elsif .n_bright > 1
        .n_bright = 1
    endif

    .n_harm = (.harm - norm_harm_lo) / (norm_harm_hi - norm_harm_lo)
    if .n_harm < 0
        .n_harm = 0
    elsif .n_harm > 1
        .n_harm = 1
    endif

    # --- Per-class heuristic scores ("Bayesian-inspired": these are NOT
    # fitted log-likelihoods of an estimated distribution, just scores
    # designed to sit in roughly comparable ranges across classes now
    # that the inputs are normalized). ---
    # Weights below were checked numerically (uniform-random feature
    # sweep) so each class's achievable score ceiling is comparable
    # (roughly 3.5-5) - previously Air's ceiling was ~0.6 against ~5 for
    # Swell, so Air was almost never selected regardless of the clip.
    .ll_sustain = -((.n_std - 0.2)^2) * 1.5 - (.n_motion^2) * 1.5 - ((.n_bright - 0.3)^2) * 1.0 + .n_harm * 2 + .voiced * 2

    .ll_swell = 0
    if .n_motion > 0
        .ll_swell += .n_motion * 2.2
    else
        .ll_swell += .n_motion * 1
    endif
    .ll_swell += -((.n_bright - 0.4)^2) * 1.5 + .n_std * 1 + .n_harm * 0.5

    .ll_tension = (.n_bright - 0.2) * 2 - .n_harm * 1.5 + .n_intensity * 1.5 + .n_std * 1

    .ll_air = -((.n_intensity - 0.3)^2) * 1.5 + (.n_bright - 0.3) * 3 + (1 - .n_harm) * 2 - .voiced * 1

    .ll_pulse = .n_std * 2 - .n_harm * 1
    if .n_motion < -0.3
        .ll_pulse += 1.5
    endif

    # Uniform prior: adds the same constant (ln(0.2)) to every class, so
    # it cancels exactly in the softmax below and does not affect the
    # resulting probabilities. Kept for structural clarity (this is where
    # a non-uniform, corpus-estimated prior would go), not because it
    # currently changes the outcome.
    .prior = ln(0.2)
    .post_1 = .ll_sustain + .prior
    .post_2 = .ll_swell + .prior
    .post_3 = .ll_tension + .prior
    .post_4 = .ll_air + .prior
    .post_5 = .ll_pulse + .prior
    
    # Find max for numerical stability
    .max_post = .post_1
    if .post_2 > .max_post
        .max_post = .post_2
    endif
    if .post_3 > .max_post
        .max_post = .post_3
    endif
    if .post_4 > .max_post
        .max_post = .post_4
    endif
    if .post_5 > .max_post
        .max_post = .post_5
    endif
    
    # Normalize
    .post_1 = exp(.post_1 - .max_post)
    .post_2 = exp(.post_2 - .max_post)
    .post_3 = exp(.post_3 - .max_post)
    .post_4 = exp(.post_4 - .max_post)
    .post_5 = exp(.post_5 - .max_post)
    
    .sum = .post_1 + .post_2 + .post_3 + .post_4 + .post_5
    
    clip_post_'.idx'_1 = .post_1 / .sum
    clip_post_'.idx'_2 = .post_2 / .sum
    clip_post_'.idx'_3 = .post_3 / .sum
    clip_post_'.idx'_4 = .post_4 / .sum
    clip_post_'.idx'_5 = .post_5 / .sum
    
    # Store dominant class
    .max_p = clip_post_'.idx'_1
    clip_class_'.idx' = 1
    if clip_post_'.idx'_2 > .max_p
        .max_p = clip_post_'.idx'_2
        clip_class_'.idx' = 2
    endif
    if clip_post_'.idx'_3 > .max_p
        .max_p = clip_post_'.idx'_3
        clip_class_'.idx' = 3
    endif
    if clip_post_'.idx'_4 > .max_p
        .max_p = clip_post_'.idx'_4
        clip_class_'.idx' = 4
    endif
    if clip_post_'.idx'_5 > .max_p
        clip_class_'.idx' = 5
    endif
endproc

procedure computeMacros: .idx
    .p_sustain = clip_post_'.idx'_1
    .p_swell = clip_post_'.idx'_2
    .p_tension = clip_post_'.idx'_3
    .p_air = clip_post_'.idx'_4
    .p_pulse = clip_post_'.idx'_5
    
    clip_flow_'.idx' = 0.5 + 0.3 * .p_sustain + 0.4 * .p_air + 0.2 * .p_swell
    if clip_flow_'.idx' > 1
        clip_flow_'.idx' = 1
    endif
    
    clip_growth_'.idx' = 0.3 + 0.6 * .p_swell + 0.1 * .p_tension
    
    clip_edge_'.idx' = 0.2 + 0.6 * .p_tension + 0.2 * .p_swell
    if clip_edge_'.idx' > 0.85
        clip_edge_'.idx' = 0.85
    endif
    
    clip_space_'.idx' = 0.4 + 0.4 * .p_air + 0.3 * .p_sustain + 0.1 * .p_swell
    if clip_space_'.idx' > 1
        clip_space_'.idx' = 1
    endif
    
    clip_soften_'.idx' = .p_pulse
endproc

procedure buildTimeline: .n_clips
    # No separate hardcoded segment cap: every loaded clip gets a chance
    # to be placed. max_clips (set by the form/preset) is what limits how
    # many clips exist in the first place.
    timeline_n_segments = .n_clips
    
    for .i to .n_clips
        clip_used_'.i' = 0
    endfor
    
    for .seg to timeline_n_segments
        .phase = (.seg - 1) / (timeline_n_segments - 1)
        
        # Phase-based targets (intro→development→climax→resolution).
        # Kept within the per-axis ranges computeMacros can actually reach
        # (approximately Flow 0.5-0.9, Growth 0.3-0.9, Edge 0.2-0.8,
        # Space 0.4-0.8), moving the nearest-clip search closer to the
        # feasible macro space than before. Note Flow/Growth/Edge/Space
        # are not independent -- all four are computed from the same five
        # posterior probabilities -- so each coordinate being within its
        # own range does not guarantee the combined 4D target point is
        # itself reachable; the nearest-clip search still just picks the
        # closest clip that exists, which is why this matters less in
        # practice than it would for four free variables.
        if .phase < 0.25
            .target_flow = 0.85
            .target_growth = 0.3
            .target_edge = 0.2
            .target_space = 0.8
        elsif .phase < 0.60
            .target_flow = 0.75
            .target_growth = 0.7
            .target_edge = 0.4
            .target_space = 0.5
        elsif .phase < 0.80
            .target_flow = 0.5
            .target_growth = 0.4
            .target_edge = 0.75
            .target_space = 0.4
        else
            .target_flow = 0.9
            .target_growth = 0.3
            .target_edge = 0.2
            .target_space = 0.8
        endif
        
        .best_idx = 1
        .best_score = -1000
        
        for .i to .n_clips
            if clip_used_'.i' = 0
                .flow = clip_flow_'.i'
                .growth = clip_growth_'.i'
                .edge = clip_edge_'.i'
                .space = clip_space_'.i'
                
                .dist = 0
                .dist += (.flow - .target_flow)^2
                .dist += (.growth - .target_growth)^2
                .dist += (.edge - .target_edge)^2
                .dist += (.space - .target_space)^2
                .score = -sqrt(.dist)
                
                # Continuity bonus
                if .seg > 1
                    .prev_idx = timeline_clip_'.seg_minus_1'
                    .prev_flow = clip_flow_'.prev_idx'
                    .prev_edge = clip_edge_'.prev_idx'
                    .cont = abs(.flow - .prev_flow) + abs(.edge - .prev_edge)
                    .score += -(0.3 * .cont)
                endif
                
                if .score > .best_score
                    .best_score = .score
                    .best_idx = .i
                endif
            endif
        endfor
        
        timeline_clip_'.seg' = .best_idx
        clip_used_'.best_idx' = 1
        
        # Store for next iteration
        .seg_minus_1 = .seg
    endfor
    
    # Calculate start times
    .first_clip = timeline_clip_1
    timeline_start_1 = 0
    timeline_overlap_1 = 0
    .total_dur = clip_duration_'.first_clip'
    
    for .seg from 2 to timeline_n_segments
        .seg_prev = .seg - 1
        .prev_idx = timeline_clip_'.seg_prev'
        .curr_idx = timeline_clip_'.seg'
        
        .flow_prev = clip_flow_'.prev_idx'
        .flow_curr = clip_flow_'.curr_idx'
        .space_prev = clip_space_'.prev_idx'
        .space_curr = clip_space_'.curr_idx'
        
        .flow_avg = (.flow_prev + .flow_curr) / 2
        .space_avg = (.space_prev + .space_curr) / 2
        
        if .seg / timeline_n_segments > 0.8
            .overlap = 0.6 + .flow_avg * 1.2 + .space_avg * 0.5
        else
            .overlap = 0.4 + .flow_avg * 0.8 + .space_avg * 0.3
        endif
        
        .overlap = .overlap * overlap_factor
        
        # Absolute ceiling first...
        if .overlap > 2
            .overlap = 2
        endif

        # ...then the fix: the overlap can never exceed either clip's own
        # duration, or timeline_start below can go negative/out-of-order
        # and swallow the start of a short clip. Capped at 50% (not 80%)
        # of the shorter clip's duration: assembleDrone independently caps
        # each fade at .duration / 2, so if the overlap here could exceed
        # that, the stored overlap and the actual fade length would
        # silently disagree, and Fade in/Fade out would no longer be
        # complementary over the same stretch (Praat only forms a real
        # crossfade when both fades span the same interval). Capping at
        # 50% here keeps the two always equal, so the .duration/2 clamp in
        # assembleDrone becomes a no-op safety net rather than something
        # that actually fires.
        .prev_dur = clip_duration_'.prev_idx'
        .curr_dur = clip_duration_'.curr_idx'
        .max_overlap_by_dur = 0.5 * min(.prev_dur, .curr_dur)
        if .overlap > .max_overlap_by_dur
            .overlap = .max_overlap_by_dur
        endif
        if .overlap < 0
            .overlap = 0
        endif

        timeline_overlap_'.seg' = .overlap
        
        .prev_start = timeline_start_'.seg_prev'
        timeline_start_'.seg' = .prev_start + .prev_dur - .overlap

        .end_time = timeline_start_'.seg' + .curr_dur
        if .end_time > .total_dur
            .total_dur = .end_time
        endif
    endfor
    
    timeline_total_duration = .total_dur
endproc

procedure assembleDrone
    final_sound = Create Sound from formula: "base", 1, 0, timeline_total_duration, target_sr, "0"

    for .seg to timeline_n_segments
        .clip_idx = timeline_clip_'.seg'
        .start_time = timeline_start_'.seg'
        .duration = clip_duration_'.clip_idx'
        
        selectObject: clip_sound_'.clip_idx'
        .part = Copy: "part"
        
        .flow = clip_flow_'.clip_idx'
        .space = clip_space_'.clip_idx'
        .soften = clip_soften_'.clip_idx'
        
        # Real crossfade fix: the fade shared with the PREVIOUS clip and
        # the fade shared with the NEXT clip must each equal the overlap
        # duration stored for that boundary in buildTimeline, so the two
        # clips' complementary raised-cosine fades ("yes" below) actually
        # sum to a proper crossfade instead of two independently-sized
        # fades that happened to be called one. Only the first/last clip
        # (no overlap partner on that side) still uses a standalone,
        # gesture-shaped entrance/exit fade.
        if .seg > 1
            .fade_in = timeline_overlap_'.seg'
        else
            .fade_in = 0.05 + .flow * 0.2 + .soften * 0.2
        endif

        if .seg < timeline_n_segments
            .next_seg = .seg + 1
            .fade_out = timeline_overlap_'.next_seg'
        else
            .fade_out = 0.1 + .flow * 0.2 + .space * 0.2 + .soften * 0.2
        endif
        
        if .fade_in > .duration / 2
            .fade_in = .duration / 2
        endif
        if .fade_out > .duration / 2
            .fade_out = .duration / 2
        endif

        # Quick start: cap the opening clip's fade-in so the piece does
        # not begin faint (mode 3 only). Only applies to the standalone
        # entrance fade above (segment 1 never has a previous overlap).
        if .seg = 1 and output_level = 3
            if .fade_in > 0.06
                .fade_in = 0.06
            endif
        endif
        
        # Per-clip loudness -- deliberately BEFORE the fades (v0.7 #8).
        # Scale intensity measures the clip as it stands when called: if
        # applied after fading, a clip with long fades (proportionally
        # more of it) has lower average energy, so Praat compensates with
        # more gain on the WHOLE clip -- meaning short clips or clips with
        # long overlaps could get over-amplified relative to their true
        # source level, and achieved gain would depend on overlap/clip
        # duration rather than only on source loudness. Normalizing the
        # unfaded source first keeps "Even level" meaning what it says:
        # equal source levels, with the fades then purely shaping
        # entrances/exits/overlaps on top, not partly compensated by them.
        # Dramatic arc (mode 1) leaves EVERY clip at its inherent
        # recording level -- no Scale intensity call at all, matching the
        # documented behaviour (previously this branch still rescaled any
        # clip with soften > 0.5, contradicting itself).
        # Even-level modes (2,3) normalize every clip to a common
        # intensity; 'soften' still pulls pulse-y clips down relative to
        # the same target so they don't dominate the mix.
        if output_level >= 2
            selectObject: .part
            if .soften > 0.5
                # Scale intensity takes a target dB SPL, not an amplitude
                # multiplier -- multiplying level_target_db by a 0-1 scale
                # (as before) moved the target itself, e.g. 70 dB * 0.5 =
                # 35 dB, a ~35 dB / ~56x amplitude cut for a single
                # high-Pulse clip. The fix pulls pulse-y clips down by a
                # bounded dB attenuation instead: soften in (0.5, 1] maps
                # linearly to 0-max_soften_attenuation_db below the shared
                # target, so the loudest reduction is a deliberate, mild
                # amount rather than an accidental near-mute.
                .atten_db = (.soften - 0.5) / 0.5 * max_soften_attenuation_db
                Scale intensity: level_target_db - .atten_db
            else
                Scale intensity: level_target_db
            endif
        endif

        selectObject: .part
        Fade in: 0, 0, .fade_in, "yes"
        Fade out: 0, .duration, -.fade_out, "yes"
        
        # Mix into final sound.
        # v0.3 FIX: v0.2 used "Object_<id>[expr]" which resolves by
        # NAME (not numeric ID) and was off-by-one. Correct idiom is
        # object[<id>, <col_expr>] with col_expr = col - offset where
        # offset = round(start_time * sr). Terminator inside a Formula
        # string is `fi`, not `endif`.
        .off = round(.start_time * target_sr)
        selectObject: .part
        .partNSamples = Get number of samples

        .firstCol = .off + 1
        .lastCol  = .off + .partNSamples
        .partIdStr$ = fixed$(.part, 0)
        .offStr$ = fixed$(.off, 0)
        .firstStr$ = fixed$(.firstCol, 0)
        .lastStr$ = fixed$(.lastCol, 0)

        selectObject: final_sound
        Formula: "self + if col >= " + .firstStr$
            ... + " and col <= " + .lastStr$
            ... + " then object[" + .partIdStr$ + ", col - " + .offStr$ + "]"
            ... + " else 0 fi"

        removeObject: .part
    endfor
endproc

procedure flattenLoudness: .snd
    # This IS a compressor/AGC, not a gentle "leveling" pass: it divides
    # the signal by a low-passed amplitude envelope of the whole mix, so
    # anything slower than .env_cutoff Hz gets flattened. That includes
    # within-clip fades, crescendos/decrescendos, the crossfades between
    # clips, and slow envelope "breathing" -- not just the section-to-
    # section swell it's aimed at. The Hann-band filter used to build the
    # envelope is also zero-phase (non-causal), so it can smear slightly
    # across transitions rather than only reacting after them. The linear
    # floor below stops near-silence from being divided into noise, but
    # does not prevent pumping or broadband noise being pushed up during
    # quiet passages.
    .floor = 0.02            ; linear amplitude floor for the divide
    .env_cutoff = 1.5        ; Hz; below this is treated as the "slow" contour
    .env_smooth = 0.5        ; Hz; filter transition smoothing
    .floor$ = fixed$(.floor, 4)

    selectObject: .snd
    .env = Copy: "level_env"
    selectObject: .env
    Formula: "abs(self)"
    .envlow = Filter (pass Hann band): 0, .env_cutoff, .env_smooth
    removeObject: .env
    .elId$ = fixed$(.envlow, 0)

    selectObject: .snd
    Formula: "self / (if object[" + .elId$ + ", col] > " + .floor$
        ... + " then object[" + .elId$ + ", col] else " + .floor$ + " fi)"

    removeObject: .envlow
endproc

procedure drawVisualization: .n_clips
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.6
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Bayesian Drone Weaver: " + presetName$
    
    # Timeline visualization
    Select outer viewport: 0, 8, 0.8, 3.5
    Select inner viewport: 0.6, 7.6, 1.0, 3.3
    
    Axes: 0, timeline_total_duration, 0, timeline_n_segments + 1
    
    # Background
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, timeline_total_duration, 0, timeline_n_segments + 1
    
    # Draw segments
    for .seg to timeline_n_segments
        .clip_idx = timeline_clip_'.seg'
        .start = timeline_start_'.seg'
        .dur = clip_duration_'.clip_idx'
        .end = .start + .dur
        
        .class = clip_class_'.clip_idx'
        
        # Color by class
        if .class = 1
            .col$ = "{0.3, 0.6, 0.9}"
        elsif .class = 2
            .col$ = "{0.4, 0.8, 0.4}"
        elsif .class = 3
            .col$ = "{0.9, 0.4, 0.3}"
        elsif .class = 4
            .col$ = "{0.7, 0.7, 0.9}"
        else
            .col$ = "{0.9, 0.7, 0.3}"
        endif
        
        .y1 = .seg - 0.4
        .y2 = .seg + 0.4
        
        Paint rectangle: .col$, .start, .end, .y1, .y2
        
        # Label
        Colour: "Black"
        Font size: 7
        Text: (.start + .end) / 2, "centre", .seg, "half", string$(.clip_idx)
    endfor
    
    Colour: "Black"
    Font size: 10
    Draw inner box
    Text left: "yes", "Segment"
    Text bottom: "yes", "Time (s)"
    Marks bottom every: 1, 5, "yes", "yes", "no"
    
    # Legend
    Select outer viewport: 0, 8, 3.7, 4.3
    Axes: 0, 1, 0, 1
    Font size: 8
    
    Paint rectangle: "{0.3, 0.6, 0.9}", 0.02, 0.06, 0.4, 0.6
    Text: 0.08, "left", 0.5, "half", "Sustain"
    
    Paint rectangle: "{0.4, 0.8, 0.4}", 0.22, 0.26, 0.4, 0.6
    Text: 0.28, "left", 0.5, "half", "Swell"
    
    Paint rectangle: "{0.9, 0.4, 0.3}", 0.42, 0.46, 0.4, 0.6
    Text: 0.48, "left", 0.5, "half", "Tension"
    
    Paint rectangle: "{0.7, 0.7, 0.9}", 0.62, 0.66, 0.4, 0.6
    Text: 0.68, "left", 0.5, "half", "Air"
    
    Paint rectangle: "{0.9, 0.7, 0.3}", 0.82, 0.86, 0.4, 0.6
    Text: 0.88, "left", 0.5, "half", "Pulse"
    
    Font size: 10
endproc
Play