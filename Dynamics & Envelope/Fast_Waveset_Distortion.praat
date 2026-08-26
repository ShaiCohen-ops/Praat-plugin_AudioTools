# ============================================================
# Praat AudioTools - Fast Waveset Distortion.praat
#  chops audio into fixed-size time chunks, not content-aware
#  wavesets between zero crossings, so the old name overclaimed)
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.11 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Fast fixed-size chunk audio distortion with stereo processing.
#   True stereo input is processed as independent L/R channels;
#   mono input is decorrelated into a synthetic stereo pair. Both
#   channels share the same chunk grid and the same structural
#   decisions (repeat count, gap period, chunk order, stretch
#   factor); stereo width comes from non-length-altering differences
#   (a small gain offset, a short pre-delay, and - for Ring Mod /
#   Tremolo - a phase offset) so L and R never drift out of sync.
#   Chunk boundaries are crossfaded with Praat's raised-cosine
#   overlap-add ("Concatenate with overlap"), not just faded to
#   silence and butt-spliced. This is a complementary-power
#   crossfade (fadeOut + fadeIn = 1), not an equal-power one
#   (fadeOut^2 + fadeIn^2 <> 1).
#
#   ENGINEERING NOTES:
#   - The chunk[], seq[], order[], result, and n_chunks identifiers
#     are used as SCRIPT-LEVEL (global) variables for inter-procedure
#     communication, even though they are written inside
#     processAudio. This is intentional for this two-call flow
#     (one call for L channel, one for R) — each call overwrites
#     the array entries with its own IDs and cleans them up before
#     returning. Fragile if extended to more than two calls per
#     session; consider passing IDs explicitly if doing so.
#   - The procedure communicates the final result Sound to the
#     caller via selection state, not return value.
#   - Assembly now selects the full ordered chunk/repeat sequence
#     once and calls Concatenate (with overlap) a single time,
#     which is O(N) rather than the old per-chunk Concatenate loop.
#
# Changelog v1.11 (2026):
#   - FIX: Peak normalization now checks for a non-zero output peak before
#     calling Scale peak; fully silent outputs are left unchanged and reported.
#   - FIX: The visualization/info chunk count now mirrors the engine rule that
#     merges a trailing remainder shorter than half a base chunk into the
#     previous chunk, so displayed boundaries and counts match processing.
#   - FIX: Time Stretch no longer silently becomes a no-op when its requested
#     intermediate resampling rate would exceed 192 kHz. The effective Amount
#     is clamped to the largest supported stretch factor and reported; if even
#     the minimum 1.1x factor is unsupported at the input sample rate, the
#     script exits with a clear message.
#   - FIX: Stereo_spread is constrained to the practical range -0.95..1.0 and
#     out-of-range custom values are clamped and reported.
#   - REPORTING: pre-header parameter adjustments are accumulated and printed
#     after the Info header instead of being erased by writeInfoLine.
#
# Changelog v1.10 (2026):
#   - VISUALIZATION / UI STANDARDIZATION ONLY. Audio analysis,
#     DSP, scheduling and rendering are unchanged from the
#     previous version.
#   - Adopted the Praat AudioTools 8-inch visualization header,
#     suite typography, neutral panel backgrounds, summary-style
#     reporting and full-page Picture export restoration.
#   - Preserved the script-specific diagnostic / transformation
#     views rather than replacing them with generic plots.
#
# Changelog v1.9:
#   - FIXED: Random Shuffle didn't actually shuffle. Concatenate (and
#     Concatenate with overlap) assemble objects in Objects-window
#     creation order, not selection order, so pointing seq[] at the
#     existing chunk[] objects in a shuffled index order had no
#     audible effect - they still concatenated in original 1..N
#     order. Shuffle now makes fresh copies of the chunks in the
#     shuffled order (so their creation order matches the desired
#     sequence order), then frees the originals.
#   - FIXED: Stutter applied a Hann fade-in/out to every repeat via
#     applyWindow AND then relied on Concatenate with overlap's own
#     raised-cosine crossfade at the same boundaries, stacking two
#     fades and dropping the crossfade midpoint to ~-6 dB for
#     otherwise-equal neighbouring repeats. applyWindow is no longer
#     called from Stutter; only the single overlap-add crossfade
#     remains.
#   - FIXED: Stereo_spread used to scale Amount and Chunk_ms
#     separately per channel, which could change the repeat count,
#     gap period, chunk grid, or stretch factor between L and R -
#     at extreme settings this desynced L and R by several seconds
#     and the old min-duration trim silently deleted the difference.
#     L and R now always share one chunk grid and one set of
#     structural decisions; Stereo_spread instead drives a small
#     post-processing gain offset and a short pre-delay on the R
#     channel (silence-padded, not trimmed), plus a phase offset
#     between L and R for Ring Mod / Tremolo.
#   - FIXED: Dry/Wet mixing trimmed the wet signal down to the dry
#     signal's length for any Mix < 1, so Mix = 1.00 kept the full
#     extended result (e.g. after Stutter/Stretch) while Mix = 0.99
#     abruptly cut it back to the source length. The shorter side
#     (dry or wet) is now silence-padded up to the longer side's
#     length instead of trimming the longer one, so output length no
#     longer jumps as Mix crosses 1.0, and the tail of whichever
#     signal is longer is naturally scaled by its own mix weight
#     rather than deleted.
#   - FIXED (docs/labels only): the crossfade produced by Praat's
#     "Concatenate with overlap" is a raised-cosine (complementary-
#     power) crossfade, not equal-power - fadeOut + fadeIn = 1, but
#     fadeOut^2 + fadeIn^2 <> 1. Header, panel labels and this
#     changelog now say "raised-cosine" throughout instead of
#     "equal-power".
#   - FIXED: a short trailing remainder chunk (e.g. 1 ms left over
#     from the chunk grid) forced .overlap = min(fade_sec,
#     shortest_member * 0.4) down to a fraction of a millisecond for
#     the ENTIRE sequence, silently ignoring the requested Fade_ms
#     everywhere, not just at the last boundary. A trailing remainder
#     shorter than half a chunk is now merged into the previous
#     chunk instead of forming its own tiny chunk, and if the
#     requested fade still has to be reduced to fit the shortest
#     member, that is now logged to the Info window.
#   - FIXED: the Bitcrush mode description shown in the visualization
#     said "quantization to max(2, round(16/amount)) levels", which
#     is off by roughly a factor of 2 (the formula spans +/- levels
#     around zero). Label now says "steps per polarity (~2L+1 total
#     values)" to match the actual formula.
#   - FIXED: Ring Mod frequency, Tremolo frequency/depth, and
#     Pumping gain could all go negative at negative Amount values -
#     Ring Mod/Tremolo frequency going negative is harmless (sin is
#     odd) but Tremolo depth going negative turned attenuation into
#     periodic amplification, and Pumping's gain_hi going negative
#     flipped polarity every other chunk instead of just changing
#     volume. All three are now clamped to their intended ranges
#     (frequency >= 0, depth in 0-0.9, Pumping gains always positive).
#   - FIXED: the 20,000-chunk safety cap was checked against the
#     number of SOURCE chunks, but Stutter expands each source chunk
#     into 2-8 repeats before assembly, so Stutter could still spawn
#     up to 160,000 temporary Sound objects per channel. The cap is
#     now divided by Stutter's repeat count before being applied, so
#     the actual object count stays bounded regardless of mode.
#   - NOTE (not changed): every crossfade shortens the assembled
#     result by the overlap duration at each boundary (Praat: output
#     duration = sum of chunk durations - overlap per boundary), so
#     even effects that don't intend to change timing (e.g. Reverse,
#     Bitcrush, Tremolo) will end up a little shorter than the
#     source. This is inherent to the single-pass Concatenate with
#     overlap approach and is not eliminated in v1.9; the Info window
#     now reports input vs. output duration explicitly so the effect
#     is visible rather than silent.
#
# Changelog v1.8:
#   - FIXED: Dry/Wet mix used object[id, x, y] (row/col indexing)
#     with time and channel values instead of indices. Now uses
#     object[id, row, col] against a grid-matched, length-matched
#     dry signal, and Mix is clamped to 0-1.
#   - FIXED: Time Stretch and Time Compress (and therefore the
#     Slow Motion / Fast Forward presets) were swapped - Stretch
#     was shortening audio, Compress was lengthening it. Formulas
#     swapped; both are varispeed (pitch shifts with speed).
#   - RENAMED: script and internal labels from "Waveset" to
#     "Chunk" - no zero-crossing/waveset detection was ever
#     implemented, only fixed-length slicing.
#   - FIXED: stereo input is now split into real L/R channels
#     instead of being downmixed to mono and duplicated; mono
#     input is still decorrelated into synthetic stereo, and
#     >2-channel input is downmixed with an explicit log message.
#   - FIXED: inputs with a non-zero start time (xmin <> 0) are
#     shifted to start at 0 internally before any chunking, mix,
#     or drawing math that assumed a 0-based time axis.
#   - FIXED: chunk boundaries now use a real equal-power crossfade
#     (Concatenate with overlap) instead of independent Hann
#     fade-to-zero on each chunk followed by a hard splice, which
#     produced periodic gating rather than a smooth join.
#   - FIXED: Stutter mode double-applied the Hann window to
#     repeats 2..R of the very first chunk (window applied once
#     to the master, then again to each copy). All repeats of all
#     chunks are now windowed exactly once, from an unwindowed
#     master copy.
#   - FIXED: Bitcrush level count was labeled as "L levels" but
#     actually produced roughly 2L+1 quantization steps. Comment
#     and formula intent now match (levels counts steps per polarity).
#   - ADDED: per-mode validation - Mix clamped 0-1, Fade_ms clamped
#     >= 0, Stereo_spread clamped above -0.95, Bitcrush guarded
#     against Amount = 0, Pumping guarded against a zero/singular
#     gain, Ring Mod / Tremolo frequencies clamped below Nyquist,
#     Chunk_ms floored to at least 2 samples and capped so a single
#     run cannot spawn an unreasonable number of chunk objects.
#   - RENAMED: "Sidechain Pump" preset to "Alternating Pump" - the
#     effect alternates gain by chunk parity; it never used a
#     sidechain signal, envelope follower, or transient detector.
#   - Assembly rewritten to build the full ordered sequence and
#     concatenate once per channel instead of looping Concatenate
#     per chunk (was O(N^2), now O(N)).
#
# Changelog v1.7:
#   - Audio pipeline UNCHANGED. Output is bit-identical to v1.6
#     for the same form parameters and the same RNG state
#     (shuffle mode draws from Praat's RNG; reset Praat for
#     reproducible shuffles).
#   - Added Play_result boolean form field (default 1). v1.6
#     had a stray unconditional `Play` at the end of the script
#     with no way to disable it; v1.7 guards it with the form
#     toggle.
#   - Dropped the 4 `comment === ... ===` decorative form lines
#     to keep the form compact (same lesson as the rest of the
#     suite — decorative comments cost vertical screen real
#     estate without functional value).
#   - Visualization rewritten to suite 8x8 standard:
#       Title bar + metadata subtitle (preset, mode, chunk count)
#       Panel A (left, headline): source waveform with chunk-
#         boundary grid overlay — shows what is being chopped up
#       Panel B (right, headline): mode description + parameter
#         report — explains per-mode what happens to each chunk
#       Panel C: zoom overlay (first 200 ms, gray = source,
#         blue = L, orange = R) — shows transformation at small
#         scale
#       Panel D: output waveform (full file, L blue, R orange)
#       Panel E: light-grey summary stats bar (suite standard)
#     v1.6 had 4 panels (title, original, L, R, parameter line).
#     v1.7 has 5 panels matching the rest of the suite.
#   - Added header documentation of the global-variable pattern.
# Changelog v1.6:
#   - Added presets
#   - Matched visualization style to other AudioTools scripts
#   - Added preset name to output filename
#
# Usage:
#   Select a Sound object and run this script.
# ============================================================

form Fast Chunk Distortion v1.11
    optionmenu Preset: 1
        option Custom
        option Glitch Stutter
        option Rhythmic Gaps
        option Backwards Chunks
        option Random Shuffle
        option Slow Motion
        option Fast Forward
        option Alternating Pump
        option Robot Voice
        option Lo-Fi Crush
        option Wobble Tremolo
    optionmenu Mode: 1
        option 1. Stutter (repeat chunks)
        option 2. Gaps (silence chunks)
        option 3. Reverse chunks
        option 4. Shuffle order
        option 5. Time stretch (slower, varispeed - pitch drops)
        option 6. Time compress (faster, varispeed - pitch rises)
        option 7. Pumping (alt. volume)
        option 8. Ring modulator
        option 9. Bitcrush
        option 10. Tremolo
    real Amount 3.0
    positive Chunk_ms 40
    real Fade_ms 5
    real Stereo_spread 0.2
    real Mix 1.0
    boolean Normalize_output 1
    boolean Show_visualization 1
    boolean Play_result 1
endform

# === APPLY PRESETS ===
if preset = 2
    # Glitch Stutter
    mode = 1
    amount = 4.0
    chunk_ms = 30
    fade_ms = 3
    stereo_spread = 0.3
    presetName$ = "GlitchStutter"
elsif preset = 3
    # Rhythmic Gaps
    mode = 2
    amount = 3.0
    chunk_ms = 50
    fade_ms = 5
    stereo_spread = 0.1
    presetName$ = "RhythmicGaps"
elsif preset = 4
    # Backwards Chunks
    mode = 3
    amount = 1.0
    chunk_ms = 80
    fade_ms = 8
    stereo_spread = 0.15
    presetName$ = "BackwardsChunks"
elsif preset = 5
    # Random Shuffle
    mode = 4
    amount = 1.0
    chunk_ms = 60
    fade_ms = 6
    stereo_spread = 0.25
    presetName$ = "RandomShuffle"
elsif preset = 6
    # Slow Motion
    mode = 5
    amount = 4.0
    chunk_ms = 100
    fade_ms = 10
    stereo_spread = 0.1
    presetName$ = "SlowMotion"
elsif preset = 7
    # Fast Forward
    mode = 6
    amount = 3.0
    chunk_ms = 50
    fade_ms = 5
    stereo_spread = 0.1
    presetName$ = "FastForward"
elsif preset = 8
    # Alternating Pump (not a real sidechain/envelope-follower effect)
    mode = 7
    amount = 4.0
    chunk_ms = 125
    fade_ms = 10
    stereo_spread = 0.05
    presetName$ = "AlternatingPump"
elsif preset = 9
    # Robot Voice
    mode = 8
    amount = 2.5
    chunk_ms = 20
    fade_ms = 2
    stereo_spread = 0.4
    presetName$ = "RobotVoice"
elsif preset = 10
    # Lo-Fi Crush
    mode = 9
    amount = 4.0
    chunk_ms = 30
    fade_ms = 3
    stereo_spread = 0.2
    presetName$ = "LoFiCrush"
elsif preset = 11
    # Wobble Tremolo
    mode = 10
    amount = 5.0
    chunk_ms = 40
    fade_ms = 5
    stereo_spread = 0.3
    presetName$ = "WobbleTremolo"
else
    presetName$ = "Custom"
endif

# === VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Select a Sound object."
endif

original_raw = selected("Sound")
name$ = selected$("Sound")
sr = Get sampling frequency
dur = Get total duration
n_channels = Get number of channels

# Work on a copy shifted to start at t = 0 if the input's time domain
# doesn't already start at 0. Every downstream chunk/mix/draw call in
# this script assumes a 0-based time axis (0 -> duration).
selectObject: original_raw
xmin_orig = Get start time
if xmin_orig <> 0
    original = Copy: name$ + "_t0"
    Shift times to: "start time", 0
else
    original = original_raw
endif

selectObject: original
dur = Get total duration

# Accumulate parameter adjustments here. Some older notes were appended before
# writeInfoLine below and were therefore immediately erased when the Info
# window was initialized. v1.11 reports all such adjustments after the header.
settingsWarning$ = ""
if xmin_orig <> 0
    settingsWarning$ = settingsWarning$ + "  - Input start time was " + fixed$(xmin_orig, 4) + " s; shifted internally to 0 for processing." + newline$
endif

# --- Clamp parameters that had no validation ---
if mix < 0
    mix = 0
    settingsWarning$ = settingsWarning$ + "  - Mix was below 0 and has been clamped to 0." + newline$
elsif mix > 1
    mix = 1
    settingsWarning$ = settingsWarning$ + "  - Mix was above 1 and has been clamped to 1." + newline$
endif

if fade_ms < 0
    fade_ms = 0
    settingsWarning$ = settingsWarning$ + "  - Fade_ms was negative and has been clamped to 0." + newline$
endif

# v1.11: Stereo_spread is a bounded width control, not an unbounded gain/delay
# multiplier. Keep the established negative floor and add a practical +1 cap.
if stereo_spread < -0.95
    stereo_spread = -0.95
    settingsWarning$ = settingsWarning$ + "  - Stereo_spread was below -0.95 and has been clamped to -0.95." + newline$
elsif stereo_spread > 1
    stereo_spread = 1
    settingsWarning$ = settingsWarning$ + "  - Stereo_spread was above 1 and has been clamped to 1." + newline$
endif

# v1.11: Stretch uses an intermediate resampling rate sr*factor and the engine
# intentionally caps that rate at 192 kHz. Previously requests beyond that
# ceiling simply skipped the stretch for every chunk while the UI still claimed
# the requested factor. Clamp the effective Amount so the requested operation is
# always performed, or stop if even the minimum 1.1x factor is impossible.
if mode = 5
    stretchFactorRequested = max(1.1, amount / 2)
    stretchFactorMax = 192000 / sr
    if stretchFactorMax < 1.1
        exitScript: "Time Stretch is unavailable at this sampling frequency: the minimum 1.1x factor would require an intermediate rate above 192 kHz."
    endif
    if stretchFactorRequested > stretchFactorMax
        amount = 2 * stretchFactorMax
        settingsWarning$ = settingsWarning$ + "  - Time Stretch Amount exceeded the 192 kHz intermediate-rate limit; effective factor clamped to " + fixed$(stretchFactorMax, 3) + "x (Amount " + fixed$(amount, 3) + ")." + newline$
    endif
endif

# Floor chunk size to at least 2 samples, and if the resulting chunk
# count would be unreasonably large, grow the chunk size instead of
# letting the script spawn tens of thousands of Sound objects.
min_chunk_ms = 1000 * 2 / sr
if chunk_ms < min_chunk_ms
    chunk_ms = min_chunk_ms
endif

# Stutter turns each SOURCE chunk into 2-8 temporary repeat copies
# before assembly, so the object-count cap has to be checked against
# (source chunks x repeats), not just source chunks, or Stutter can
# still spawn up to 160,000 temporary Sound objects per channel.
stutter_multiplier = 1
if mode = 1
    stutter_multiplier = max(2, min(8, round(amount)))
endif

max_chunks_allowed = 20000
max_source_chunks_allowed = max(1, floor(max_chunks_allowed / stutter_multiplier))
if dur / (chunk_ms / 1000) > max_source_chunks_allowed
    chunk_ms = 1000 * dur / max_source_chunks_allowed
    settingsWarning$ = settingsWarning$ + "  - Chunk_ms was too small for this file length/mode; raised to " + fixed$(chunk_ms, 3) + " ms to keep the total object count reasonable." + newline$
endif

# Ensure fade doesn't exceed half chunk
fadeBeforeFit = fade_ms
fade_ms = min(fade_ms, chunk_ms / 2 - 1)
if fade_ms < 0
    fade_ms = 0
endif
if abs(fade_ms - fadeBeforeFit) > 0.000001
    settingsWarning$ = settingsWarning$ + "  - Fade_ms was reduced to " + fixed$(fade_ms, 3) + " ms to fit the effective chunk size." + newline$
endif
fade_sec = fade_ms / 1000

# Pre-compute the ACTUAL source-chunk grid for display. processAudio merges a
# trailing remainder shorter than half a base chunk into the previous chunk;
# mirror that exact rule here so the grid/count shown in the visualization is
# not one chunk/boundary too large.
chunk_sec_disp = chunk_ms / 1000
n_chunks_disp = ceiling(dur / chunk_sec_disp)
last_chunk_sec_disp = dur - (n_chunks_disp - 1) * chunk_sec_disp
if n_chunks_disp > 1 and last_chunk_sec_disp < chunk_sec_disp * 0.5
    n_chunks_disp = n_chunks_disp - 1
endif

# Resolve short mode name for visualization
if mode = 1
    modeShort$ = "Stutter"
    modeDesc$ = "Each chunk repeated R times (R = round(amount), clamped 2-8), with 0.85^(r-1) decay"
elsif mode = 2
    modeShort$ = "Gaps"
    modeDesc$ = "Every Nth chunk silenced (N = max(2, round(amount)))"
elsif mode = 3
    modeShort$ = "Reverse"
    modeDesc$ = "Each chunk played backwards (order preserved)"
elsif mode = 4
    modeShort$ = "Shuffle"
    modeDesc$ = "Chunks reordered randomly (ascending Fisher-Yates)"
elsif mode = 5
    modeShort$ = "Stretch"
    modeDesc$ = "Each chunk slowed (lengthened) by factor = max(1.1, amount/2), varispeed - pitch drops too"
elsif mode = 6
    modeShort$ = "Compress"
    modeDesc$ = "Each chunk sped up (shortened) by factor = max(1.1, amount/2), varispeed - pitch rises too"
elsif mode = 7
    modeShort$ = "Pumping"
    modeDesc$ = "Alternating gain per chunk (odd = hi, even = lo)"
elsif mode = 8
    modeShort$ = "RingMod"
    modeDesc$ = "Each chunk multiplied by sin(2pi*f*t), f = 50 + amount*80 Hz"
elsif mode = 9
    modeShort$ = "Bitcrush"
    modeDesc$ = "Per-chunk quantization to max(2, round(16/amount)) steps per polarity (~2L+1 total values)"
elsif mode = 10
    modeShort$ = "Tremolo"
    modeDesc$ = "Per-chunk tremolo at 2 + amount*3 Hz, depth min(0.9, amount*0.15)"
endif

writeInfoLine: "=== Fast Chunk Distortion v1.11 ==="
appendInfoLine: "Input: ", name$, " | ", fixed$(dur, 2), "s | ", n_channels, " ch"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Mode: ", mode$
appendInfoLine: "Amount: ", amount, " | Chunk: ", chunk_ms, "ms | Fade: ", fade_ms, "ms"
appendInfoLine: "Stereo spread: ", stereo_spread, " | Mix: ", fixed$(mix, 2)
appendInfoLine: "Chunks: ", n_chunks_disp, " (base chunk ", fixed$(chunk_sec_disp * 1000, 1), " ms; final chunk may include a merged remainder)"
if settingsWarning$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Settings adjusted:"
    appendInfoLine: settingsWarning$
endif
appendInfoLine: ""

# === PREPARE L/R SOURCES ===
# True stereo input: process the real L and R channels independently.
# Mono input: decorrelate into a synthetic stereo pair (there is no
# real second channel to draw from).
# >2 channels: downmix to mono first (ambiguous otherwise), logged
# explicitly so this isn't a silent surprise.
if n_channels = 2
    selectObject: original
    left_source = Extract one channel: 1
    Rename: "left_source"
    selectObject: original
    right_source = Extract one channel: 2
    Rename: "right_source"
    appendInfoLine: "Input is stereo - processing the real L and R channels independently."
else
    selectObject: original
    source_mono = Convert to mono
    Rename: "mono_source"
    selectObject: source_mono
    left_source = Copy: "left_source"
    selectObject: source_mono
    right_source = Copy: "right_source"
    removeObject: source_mono
    if n_channels = 1
        appendInfoLine: "Input is mono - generating a decorrelated stereo output from the same source."
    else
        appendInfoLine: "Input has ", n_channels, " channels - downmixed to mono, then decorrelated into stereo."
    endif
endif

# === STEREO WIDTH PARAMETERS ===
# L and R now share the SAME chunk grid and the SAME structural
# decisions (repeat count, gap period, chunk order, stretch factor) -
# Stereo_spread no longer scales Amount or Chunk_ms per channel,
# because that could desync L and R by seconds at extreme settings
# (the old min-duration trim then silently deleted the difference).
# Instead Stereo_spread drives three non-length-altering differences
# applied to the R channel only: a phase offset (Ring Mod / Tremolo
# modes), a small gain offset, and a short pre-delay (silence-padded,
# not trimmed, so no content is lost).
phase_offset_R = stereo_spread * pi * 0.5
gain_R = 1 + stereo_spread * 0.15
predelay_R_sec = abs(stereo_spread) * 0.004

# === PROCESS LEFT CHANNEL ===
appendInfoLine: "Processing LEFT channel..."

tag$ = "L"
@processAudio: left_source, mode, amount, chunk_ms, fade_sec, tag$, 0
left_result = selected("Sound")

# === PROCESS RIGHT CHANNEL ===
appendInfoLine: "Processing RIGHT channel..."

tag$ = "R"
@processAudio: right_source, mode, amount, chunk_ms, fade_sec, tag$, phase_offset_R
right_result = selected("Sound")

# Small gain offset on R for stereo width
selectObject: right_result
Formula: "self * gain_R"

# Short R pre-delay: pad the FRONT of R with silence and the END of
# L with an equal amount of silence, so both channels stay the same
# final length without cutting any content from either one (the old
# per-channel chunk-grid divergence used to trim real audio off the
# end of whichever channel came out longer).
if predelay_R_sec > 0
    # Concatenate assembles objects in OBJECTS-WINDOW CREATION ORDER,
    # not selection order. predelay_snd used to be created AFTER
    # right_result already existed, so the real creation order was
    # "right_result, then predelay_snd" and Concatenate silently
    # built "right + silence" instead of the intended pre-delay
    # "silence + right". Fix: create the silence first, then make a
    # FRESH copy of the right-channel audio after it, so the copy's
    # (later) creation order - not right_result's original, earlier
    # one - is what Concatenate actually sees.
    selectObject: right_result
    r_sr = Get sampling frequency
    r_channels = Get number of channels
    predelay_snd = Create Sound from formula: "predelay", r_channels, 0, predelay_R_sec, r_sr, "0"
    selectObject: right_result
    right_copy_for_delay = Copy: "right_copy_for_delay"
    selectObject: predelay_snd
    plusObject: right_copy_for_delay
    right_delayed = Concatenate
    removeObject: predelay_snd, right_copy_for_delay, right_result
    right_result = right_delayed
    Rename: "right_result_delayed"

    selectObject: left_result
    l_sr = Get sampling frequency
    l_channels = Get number of channels
    posttail_snd = Create Sound from formula: "posttail", l_channels, 0, predelay_R_sec, l_sr, "0"
    selectObject: left_result
    plusObject: posttail_snd
    left_padded = Concatenate
    removeObject: posttail_snd, left_result
    left_result = left_padded
    Rename: "left_result_padded"
endif

# === MATCH DURATIONS ===
# After sharing one chunk grid, L and R should already match almost
# exactly; this only reconciles sub-sample/rounding differences
# (e.g. from Stretch/Compress resampling), not structural ones.
selectObject: left_result
dur_L = Get total duration
selectObject: right_result
dur_R = Get total duration

min_dur = min(dur_L, dur_R)

if dur_L > min_dur
    selectObject: left_result
    left_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: left_result
    left_result = left_trimmed
endif

if dur_R > min_dur
    selectObject: right_result
    right_trimmed = Extract part: 0, min_dur, "rectangular", 1, "no"
    removeObject: right_result
    right_result = right_trimmed
endif

# === COMBINE TO STEREO ===
# Combine to stereo also goes by OBJECTS-WINDOW CREATION ORDER (top
# = left channel), not selection order - and that order can already
# have been scrambled by whichever of left_result/right_result
# needed duration-trimming just above (only one side gets a fresh,
# later-created object when the durations already matched). To
# guarantee L->left and R->right no matter what happened upstream,
# make fresh copies right here, in the exact order needed.
selectObject: left_result
left_final = Copy: "left_final"
selectObject: right_result
right_final = Copy: "right_final"
removeObject: left_result, right_result

selectObject: left_final
plusObject: right_final
stereo_result = Combine to stereo
Rename: name$ + "_FCD_" + presetName$

removeObject: left_final, right_final

# === MIX WITH ORIGINAL ===
# mix is already clamped to 0-1 in validation above.
if mix < 1
    selectObject: stereo_result
    result_sr = Get sampling frequency
    result_dur = Get total duration

    selectObject: original
    if n_channels = 1
        orig_stereo = Convert to stereo
    elsif n_channels = 2
        orig_stereo = Copy: "orig_stereo"
    else
        # >2 channels: match the WET path's treatment exactly -
        # downmix to mono, then decorrelate into stereo - instead of
        # the Formula step below silently reading only the raw first
        # two channels of "original" (channels the wet signal never
        # actually used, since wet was built from the full downmix).
        selectObject: original
        orig_mono_dry = Convert to mono
        selectObject: orig_mono_dry
        orig_stereo = Convert to stereo
        removeObject: orig_mono_dry
    endif

    # Match sampling rate to the wet result before touching length,
    # so row/col indices line up between the two objects.
    orig_sr = Get sampling frequency
    if orig_sr <> result_sr
        orig_resampled = Resample: result_sr, 50
        removeObject: orig_stereo
        orig_stereo = orig_resampled
    endif

    orig_dur = Get total duration
    use_dur = max(result_dur, orig_dur)

    # Pad the SHORTER side with trailing silence instead of trimming
    # the longer one. The old code trimmed both sides down to
    # min(result_dur, orig_dur), so Mix = 1.00 kept the full extended
    # wet result (e.g. after Stutter/Stretch) while ANY Mix < 1
    # abruptly cut it back to the dry source length - a sharp,
    # audible discontinuity right at the Mix = 1 boundary. Padding
    # instead means: wherever the padded side is silence, that side
    # contributes 0 to the mix, so the tail of whichever signal is
    # actually longer is naturally scaled by its own mix weight
    # (self * mix, or dry * (1 - mix)) rather than deleted outright.
    if result_dur < use_dur - 0.0001
        pad_dur = use_dur - result_dur
        selectObject: stereo_result
        pad_sr = Get sampling frequency
        pad_ch = Get number of channels
        silence_wet = Create Sound from formula: "silence_wet", pad_ch, 0, pad_dur, pad_sr, "0"
        selectObject: stereo_result
        plusObject: silence_wet
        stereo_padded = Concatenate
        removeObject: stereo_result, silence_wet
        stereo_result = stereo_padded
        Rename: "wet_padded"
    endif

    if orig_dur < use_dur - 0.0001
        pad_dur = use_dur - orig_dur
        selectObject: orig_stereo
        pad_sr = Get sampling frequency
        pad_ch = Get number of channels
        silence_dry = Create Sound from formula: "silence_dry", pad_ch, 0, pad_dur, pad_sr, "0"
        selectObject: orig_stereo
        plusObject: silence_dry
        orig_padded = Concatenate
        removeObject: orig_stereo, silence_dry
        orig_stereo = orig_padded
        Rename: "dry_padded"
    endif

    # Two independent builds can still differ by a sample due to
    # rounding - force an exact common sample count before indexing
    # (this trim is sub-millisecond, not a structural truncation).
    selectObject: stereo_result
    nx_result = Get number of samples
    selectObject: orig_stereo
    nx_orig = Get number of samples

    if nx_orig <> nx_result
        nx_common = min(nx_orig, nx_result)
        common_dur = nx_common / result_sr
        if nx_result > nx_common
            selectObject: stereo_result
            stereo_trimmed = Extract part: 0, common_dur, "rectangular", 1, "no"
            removeObject: stereo_result
            stereo_result = stereo_trimmed
        endif
        if nx_orig > nx_common
            selectObject: orig_stereo
            orig_trimmed = Extract part: 0, common_dur, "rectangular", 1, "no"
            removeObject: orig_stereo
            orig_stereo = orig_trimmed
        endif
    endif

    # [] means index by (row, col) in Praat, not by (time, channel).
    # row = channel, col = sample number; using the old (x, y) time/
    # channel values here read the wrong data or crashed outright.
    selectObject: stereo_result
    orig_str$ = string$(orig_stereo)
    Formula: "self * mix + object[" + orig_str$ + ", row, col] * (1 - mix)"

    removeObject: orig_stereo
endif

# === NORMALIZE ===
selectObject: stereo_result
normalizationApplied = 0
if normalize_output
    preNormalizePeak = Get absolute extremum: 0, 0, "Sinc70"
    if preNormalizePeak > 0
        Scale peak: 0.95
        normalizationApplied = 1
    else
        appendInfoLine: "Output is silent; normalization skipped."
    endif
endif

# stereo_result may carry an intermediate name (e.g. "wet_padded" or
# "dry_padded") left over from the Mix<1 padding/trimming steps
# above - restore the documented "<name>_FCD_<preset>" output name
# now that this object is final, so the promised name is never lost.
selectObject: stereo_result
Rename: name$ + "_FCD_" + presetName$

output = stereo_result
final_dur = Get total duration

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if show_visualization
    
    Erase all
    vizName$ = replace$(name$, "_", "\_ ", 0)
    pageWidth = 8
    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Fast Chunk Distortion v1.11##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ + " | " + modeShort$ + " | " + string$(n_chunks_disp) + " chunks | amount " + fixed$(amount, 1)

    # PANEL A: SOURCE + CHUNK GRID OVERLAY  (left, headline)
    # Shows the source waveform with vertical dotted lines at
    # chunk boundaries — visualises what is being chopped up.
    # If there are too many chunks to render legibly, the grid
    # is thinned so at most ~60 lines are drawn.
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.55, 4.00, 0.95, 4.40
    
    selectObject: original
    src_peak = Get absolute extremum: 0, 0, "None"
    if src_peak < 0.001
        src_peak = 0.001
    endif
    src_amp = src_peak * 1.15
    
    Axes: 0, dur, -src_amp, src_amp
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, dur, -src_amp, src_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, dur, 0
    
    # Draw source waveform behind the grid
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, dur, -src_amp, src_amp, "no", "Curve"
    
    # Chunk boundary grid (thinned if too many)
    if n_chunks_disp > 60
        grid_step = ceiling(n_chunks_disp / 60)
    else
        grid_step = 1
    endif
    
    Colour: "{0.65, 0.35, 0.70}"
    Line width: 1
    Dotted line
    for gc from 1 to n_chunks_disp - 1
        if gc mod grid_step = 0
            gx = gc * chunk_sec_disp
            Draw line: gx, -src_amp, gx, src_amp
        endif
    endfor
    Solid line
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL B: MODE DESCRIPTION + PARAMETER REPORT  (right, headline)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 4.60
    Select inner viewport: 4.55, 7.75, 0.95, 4.40
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.93, "half", "Mode:"
    
    Font size: 9
    Colour: "{0.65, 0.35, 0.70}"
    Text: 0.10, "left", 0.84, "half", "##" + modeShort$ + "##"
    
    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.10, "left", 0.76, "half", modeDesc$
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.66, "half", "Chunks:"
    
    Font size: 10
    Colour: "{0.70, 0.45, 0.20}"
    Text: 0.10, "left", 0.59, "half", string$(n_chunks_disp) + " chunks"
    Text: 0.10, "left", 0.52, "half", "Base size: " + fixed$(chunk_ms, 1) + " ms"
    Text: 0.10, "left", 0.45, "half", "Fade: " + fixed$(fade_ms, 1) + " ms (raised-cosine)"
    
    Font size: 9
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.05, "left", 0.36, "half", "Parameters:"
    
    Font size: 10
    Colour: "{0.30, 0.55, 0.30}"
    Text: 0.10, "left", 0.29, "half", "Amount:  " + fixed$(amount, 2)
    Text: 0.10, "left", 0.22, "half", "Spread:  " + fixed$(stereo_spread, 2) + " (L vs R)"
    Text: 0.10, "left", 0.15, "half", "Mix:     " + fixed$(mix, 2) + " (dry/wet)"
    
    Font size: 7
    if normalize_output
        if normalizationApplied
            Colour: "{0.20, 0.55, 0.30}"
            Text: 0.10, "left", 0.06, "half", "Normalized (peak 0.95)"
        else
            Colour: "{0.55, 0.30, 0.20}"
            Text: 0.10, "left", 0.06, "half", "Normalization skipped (silent output)"
        endif
    else
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.10, "left", 0.06, "half", "Not normalized"
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
    if grid_step > 1
        gridLabel$ = "Source + chunk grid (every " + string$(grid_step) + "th boundary shown)"
    else
        gridLabel$ = "Source + chunk grid (every chunk boundary)"
    endif
    Text: 2.10, "centre", 7.30, "half", gridLabel$
    Text: 6.10, "centre", 7.30, "half", "Mode and parameter report"
    
    # ----------------------------------------------------------
    # PANEL C: ZOOM OVERLAY  (first 200 ms)
    # Gray = source, blue = L, orange = R.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.55
    Select inner viewport: 0.55, 7.72, 4.75, 5.48
    
    zoomDur = 0.2
    if zoomDur > dur
        zoomDur = dur
    endif
    if zoomDur > final_dur
        zoomDur = final_dur
    endif
    
    # Probe peaks across all three sources for axis scaling
    selectObject: original
    z_peak1 = Get absolute extremum: 0, zoomDur, "None"
    selectObject: output
    Extract one channel: 1
    output_L_tmp = selected("Sound")
    z_peak2 = Get absolute extremum: 0, zoomDur, "None"
    
    selectObject: output
    Extract one channel: 2
    output_R_tmp = selected("Sound")
    z_peak3 = Get absolute extremum: 0, zoomDur, "None"
    
    z_max = z_peak1
    if z_peak2 > z_max
        z_max = z_peak2
    endif
    if z_peak3 > z_max
        z_max = z_peak3
    endif
    if z_max < 0.001
        z_max = 0.001
    endif
    z_amp = z_max * 1.15
    
    Axes: 0, zoomDur, -z_amp, z_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, zoomDur, -z_amp, z_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, zoomDur, 0
    
    # Light chunk-boundary marks in the zoom window
    Colour: "{0.88, 0.85, 0.92}"
    Line width: 1
    Dotted line
    n_zoom_chunks = floor(zoomDur / chunk_sec_disp)
    for gc from 1 to n_zoom_chunks
        gx = gc * chunk_sec_disp
        if gx < zoomDur
            Draw line: gx, -z_amp, gx, z_amp
        endif
    endfor
    Solid line
    
    # Source behind
    selectObject: original
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Output L
    selectObject: output_L_tmp
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    # Output R
    selectObject: output_R_tmp
    Colour: "{0.82, 0.45, 0.25}"
    Line width: 1
    Draw: 0, zoomDur, -z_amp, z_amp, "no", "Curve"
    
    removeObject: output_L_tmp, output_R_tmp
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Zoom: first " + fixed$(zoomDur * 1000, 0) + " ms  (gray = source, blue = L, orange = R)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (FULL FILE)  L blue, R orange
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.62, 6.55
    Select inner viewport: 0.55, 7.72, 5.69, 6.48
    
    selectObject: output
    out_peak = Get absolute extremum: 0, 0, "None"
    if out_peak < 0.001
        out_peak = 0.001
    endif
    out_amp = out_peak * 1.15
    
    Axes: 0, final_dur, -out_amp, out_amp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, final_dur, -out_amp, out_amp
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, final_dur, 0
    
    # L channel
    selectObject: output
    Extract one channel: 1
    output_L_full = selected("Sound")
    Colour: "{0.25, 0.50, 0.82}"
    Line width: 1
    Draw: 0, final_dur, -out_amp, out_amp, "no", "Curve"
    removeObject: output_L_full
    
    # R channel
    selectObject: output
    Extract one channel: 2
    output_R_full = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Line width: 1
    Draw: 0, final_dur, -out_amp, out_amp, "no", "Curve"
    removeObject: output_R_full
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output (full file)  blue = L, orange = R"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"
    
    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR  (suite standard — light grey)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 6.62, 7.30
    Select inner viewport: 0.55, 7.72, 6.68, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    
    if normalize_output
        if normalizationApplied
            normStr$ = "norm 0.95"
        else
            normStr$ = "norm skipped (silent)"
        endif
    else
        normStr$ = "no norm"
    endif
    
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + name$
        ... + "  |  Mode: " + modeShort$ + "  (" + mode$ + ")"
        ... + "  |  Chunks: " + string$(n_chunks_disp) + " | base " + fixed$(chunk_ms, 1) + " ms"
        ... + "  |  Fade: " + fixed$(fade_ms, 1) + " ms"
    
    Text: 0.02, "left", 0.28, "half",
        ... "Amount: " + fixed$(amount, 2)
        ... + "  |  Spread: " + fixed$(stereo_spread, 2)
        ... + "  |  Mix: " + fixed$(mix, 2)
        ... + "  |  " + normStr$
        ... + "  |  In: " + fixed$(dur, 2) + " s (" + string$(n_channels) + " ch)"
        ... + "  |  Out: " + fixed$(final_dur, 2) + " s (stereo)"
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore complete page for Picture export / clipboard.
    pageHeight = 8.15
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line

endif

# original was a t=0-shifted working copy, not the user's own object
if original <> original_raw
    removeObject: original
endif

selectObject: output

appendInfoLine: ""
appendInfoLine: "Original: ", fixed$(dur, 2), "s (", n_channels, " ch)"
appendInfoLine: "Output:   ", fixed$(final_dur, 2), "s (stereo)"
appendInfoLine: ""
appendInfoLine: "Done! -> ", name$, "_FCD_", presetName$

# ============================================================
# MAIN PROCESSING PROCEDURE
# Uses script-level (global) variables chunk[], seq[], order[],
# result, and n_chunks for inter-procedure communication. This is
# safe for the two-call flow used by this script (L then R) — each
# call overwrites entries with its own IDs and removes them before
# returning. Fragile if extended to more than two calls per session.
#
# Every mode builds seq[1..n_seq]: the ordered list of Sound IDs to
# assemble. Assembly then selects that whole list once and calls
# Concatenate (with overlap) exactly one time - O(N), and a real
# raised-cosine crossfade at each boundary instead of independent
# fade-to-zero windows butt-spliced together.
#
# .phase_offset (radians) is added inside the Ring Mod / Tremolo
# formulas only, so the L and R calls can share one carrier/rate and
# still differ in stereo width without diverging in chunk grid,
# repeat count, or length.
# ============================================================
procedure processAudio: .source, .mode, .amount, .chunk_ms, .fade_sec, .tag$, .phase_offset
    selectObject: .source
    .sr = Get sampling frequency
    .dur = Get total duration
    .nyquist = .sr / 2 - 1
    
    .chunk_sec = .chunk_ms / 1000
    .n_chunks = ceiling(.dur / .chunk_sec)
    
    # A trailing remainder shorter than half a chunk is merged into
    # the previous chunk instead of becoming its own tiny chunk: a
    # very short last member would otherwise force the single-pass
    # overlap down to ~40% of ITS OWN duration for the whole
    # sequence (see .overlap below), silently shrinking the
    # requested Fade_ms everywhere, not just at the last boundary.
    .last_chunk_sec = .dur - (.n_chunks - 1) * .chunk_sec
    if .n_chunks > 1 and .last_chunk_sec < .chunk_sec * 0.5
        .n_chunks = .n_chunks - 1
    endif
    
    # Extract chunks into GLOBAL array
    for c from 1 to .n_chunks
        .t1 = (c - 1) * .chunk_sec
        if c = .n_chunks
            .t2 = .dur
        else
            .t2 = c * .chunk_sec
        endif
        
        if .t2 > .t1
            selectObject: .source
            chunk[c] = Extract part: .t1, .t2, "rectangular", 1, "no"
            Rename: "chunk_" + .tag$ + "_" + string$(c)
        else
            chunk[c] = 0
        endif
    endfor
    
    n_chunks = .n_chunks
    .n_seq = 0
    
    # Process by mode - each branch fills seq[1..n_seq] with the
    # ordered Sound IDs to assemble.
    if .mode = 1
        # STUTTER - each chunk repeated .reps times with decay.
        # Repeats are no longer separately Hann-windowed here: the
        # single-pass Concatenate with overlap below already
        # crossfades every boundary in the assembled sequence,
        # including between repeats of the same chunk. Windowing
        # each repeat AND crossfading it produced a stacked fade
        # (~-6 dB dip) at every repeat boundary.
        .reps = max(2, min(8, round(.amount)))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                for .r from 1 to .reps
                    selectObject: chunk[c]
                    .temp = Copy: "temp"
                    if .r > 1
                        .decay = 0.85 ^ (.r - 1)
                        Formula: "self * .decay"
                    endif
                    .n_seq = .n_seq + 1
                    seq[.n_seq] = .temp
                endfor
            endif
        endfor
        
        # Masters were only ever copied from, never used directly -
        # free them now so they don't leak.
        for c from 1 to n_chunks
            if chunk[c] <> 0
                removeObject: chunk[c]
                chunk[c] = 0
            endif
        endfor
        
    elsif .mode = 2
        # GAPS - every Nth chunk silenced in place, others untouched
        .skip_n = max(2, round(.amount))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                if c mod .skip_n = 0
                    selectObject: chunk[c]
                    Formula: "0"
                endif
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 3
        # REVERSE - each chunk reversed, chunk order preserved
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Reverse
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 4
        # SHUFFLE - L and R must share the SAME chunk order (see the
        # "Both channels share the same chunk order and structural
        # decisions" contract above). processAudio is called once per
        # channel, and a fresh randomInteger() draw per call would
        # give L and R independent orders, desyncing the stereo image
        # chunk-by-chunk. L is always processed before R (see the
        # PROCESS LEFT/RIGHT CHANNEL calls), so: generate the order
        # once during the L call and stash it in a GLOBAL array;
        # during the R call, reuse that same array instead of drawing
        # new random numbers.
        if .tag$ = "L"
            for c from 1 to n_chunks
                order[c] = c
            endfor
            # Ascending Fisher-Yates (Praat for-loops only increment)
            for c from 1 to n_chunks - 1
                .j = randomInteger(c, n_chunks)
                .tmp = order[c]
                order[c] = order[.j]
                order[.j] = .tmp
            endfor
            for c from 1 to n_chunks
                sharedShuffleOrder[c] = order[c]
            endfor
        else
            for c from 1 to n_chunks
                order[c] = sharedShuffleOrder[c]
            endfor
        endif
        
        # Concatenate (and Concatenate with overlap) assemble objects
        # in their Objects-window CREATION order, not selection
        # order - so just pointing seq[] at the existing chunk[]
        # objects in shuffled index order has no audible effect,
        # since those objects were all created in original 1..N
        # order. Instead, make a fresh copy of each chunk AT THE
        # POINT it's added to seq[], so the copies' creation order
        # matches the shuffled sequence order, then free the
        # now-unused originals.
        for c from 1 to n_chunks
            .idx = order[c]
            if chunk[.idx] <> 0
                selectObject: chunk[.idx]
                .shuffled_copy = Copy: "chunk_" + .tag$ + "_shuf_" + string$(c)
                .n_seq = .n_seq + 1
                seq[.n_seq] = .shuffled_copy
            endif
        endfor
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                removeObject: chunk[c]
                chunk[c] = 0
            endif
        endfor
        
    elsif .mode = 5
        # STRETCH - slow down / lengthen (varispeed, pitch drops).
        # Resample UP then override the sampling frequency back down
        # to the original chunk rate: playing more samples at the
        # original rate takes longer. (v1.7 had this backwards - it
        # used chunk_sr / factor here, which shortens the chunk.)
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr * .factor
                # v1.11 validates/clamps Amount before processAudio, so this
                # intermediate rate is guaranteed to be <= 192 kHz. Do not
                # silently skip the effect here.
                Resample: .new_sr, 50
                .new_chunk = selected("Sound")
                removeObject: chunk[c]
                selectObject: .new_chunk
                Override sampling frequency: .chunk_sr
                chunk[c] = .new_chunk
                Rename: "chunk_" + .tag$ + "_" + string$(c)
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 6
        # COMPRESS - speed up / shorten (varispeed, pitch rises).
        # Resample DOWN then override back up: fewer samples played
        # at the original rate takes less time. (v1.7 had this
        # backwards - it used chunk_sr * factor here, which lengthens
        # the chunk.)
        .factor = max(1.1, .amount / 2)
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                .chunk_sr = Get sampling frequency
                .new_sr = .chunk_sr / .factor
                if .new_sr >= 100
                    Resample: .new_sr, 50
                    .new_chunk = selected("Sound")
                    removeObject: chunk[c]
                    selectObject: .new_chunk
                    Override sampling frequency: .chunk_sr
                    chunk[c] = .new_chunk
                    Rename: "chunk_" + .tag$ + "_" + string$(c)
                endif
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 7
        # PUMPING - alternating gain by chunk parity. Built from
        # abs(.amount) so a negative Amount changes magnitude only,
        # never sign: the old formula let gain_hi go negative at
        # negative Amount, which flips polarity every other chunk
        # (an inversion) rather than just a volume change.
        .gain_hi = 1 + (abs(.amount) - 1) * 0.5
        if .gain_hi < 0.05
            .gain_hi = 0.05
        endif
        .gain_lo = 1 / .gain_hi
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                if c mod 2 = 1
                    Formula: "self * .gain_hi"
                else
                    Formula: "self * .gain_lo"
                endif
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 8
        # RING MOD - carrier clamped to 0..Nyquist (a negative
        # Amount used to be able to push the carrier below 0 Hz;
        # harmless for sin() but not a meaningful frequency, so it's
        # clamped for clarity). .phase_offset gives L/R stereo width
        # without changing chunk grid, repeat count, or length.
        .ring_freq = 50 + .amount * 80
        if .ring_freq > .nyquist
            .ring_freq = .nyquist
        endif
        if .ring_freq < 0
            .ring_freq = 0
        endif
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * sin(2 * pi * .ring_freq * x + .phase_offset)"
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 9
        # BITCRUSH - guarded against Amount = 0 (division by zero).
        # .levels is the number of steps per polarity: the actual
        # quantized value count is roughly 2*.levels + 1 (it spans
        # both the positive and negative half of the signal, plus
        # zero), not .levels as the old label implied.
        .safe_amount = .amount
        if .safe_amount = 0
            .safe_amount = 0.01
        endif
        .levels = max(2, round(16 / abs(.safe_amount)))
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "round(self * .levels) / .levels"
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
        
    elsif .mode = 10
        # TREMOLO - rate clamped to 0..Nyquist, depth clamped to
        # 0..0.9. The old depth formula (min(0.9, amount*0.15)) let
        # a negative Amount push depth negative, which turns the
        # (1 - depth * ...) attenuation term into periodic
        # AMPLIFICATION instead of tremolo. .phase_offset gives L/R
        # stereo width without changing chunk grid or length.
        .trem_freq = 2 + .amount * 3
        if .trem_freq > .nyquist
            .trem_freq = .nyquist
        endif
        if .trem_freq < 0
            .trem_freq = 0
        endif
        .trem_depth = min(0.9, .amount * 0.15)
        if .trem_depth < 0
            .trem_depth = 0
        endif
        
        for c from 1 to n_chunks
            if chunk[c] <> 0
                selectObject: chunk[c]
                Formula: "self * (1 - .trem_depth * (0.5 + 0.5 * sin(2 * pi * .trem_freq * x + .phase_offset)))"
                .n_seq = .n_seq + 1
                seq[.n_seq] = chunk[c]
            endif
        endfor
    endif
    
    # === SINGLE-PASS ASSEMBLY ===
    # Select the whole ordered sequence and concatenate once (O(N),
    # not the old per-chunk Concatenate loop, which was O(N^2)).
    # Concatenate with overlap crossfades each boundary with a
    # raised-cosine curve instead of relying on fade-to-zero windows
    # meeting at a hard splice.
    
    # Guard the overlap time against the shortest member of the
    # sequence, since post-effect chunk durations vary (Stretch/
    # Compress change length). A short trailing remainder chunk is
    # already merged into the previous chunk above so it can no
    # longer be the culprit here, but Stretch/Compress or an
    # unusually short source can still produce a short member.
    .min_seq_dur = 1000000
    for .i from 1 to .n_seq
        selectObject: seq[.i]
        .d = Get total duration
        if .d < .min_seq_dur
            .min_seq_dur = .d
        endif
    endfor
    
    .overlap = .fade_sec
    if .overlap > .min_seq_dur * 0.4
        .overlap = .min_seq_dur * 0.4
    endif
    if .overlap < 0
        .overlap = 0
    endif
    
    if .overlap < .fade_sec - 0.0001
        appendInfoLine: "Note (", .tag$, "): requested fade ", fixed$(.fade_sec * 1000, 2), " ms reduced to effective overlap ", fixed$(.overlap * 1000, 2), " ms (limited by the shortest segment in the sequence)."
    endif
    
    if .n_seq = 1
        selectObject: seq[1]
        result = Copy: "result_" + .tag$
    else
        selectObject: seq[1]
        for .i from 2 to .n_seq
            plusObject: seq[.i]
        endfor
        if .overlap > 0
            result = Concatenate with overlap: .overlap
        else
            result = Concatenate
        endif
        Rename: "result_" + .tag$
    endif
    
    # Cleanup the sequence objects (this also covers chunk[] entries
    # that were reused directly in seq[], for every mode except
    # Stutter, whose masters were already freed above)
    for .i from 1 to .n_seq
        removeObject: seq[.i]
    endfor
    
    removeObject: .source
    
    selectObject: result
endproc

if play_result
    selectObject: output
    Play
endif
