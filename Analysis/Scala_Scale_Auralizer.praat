# ============================================================
# Praat AudioTools - Scala_Scale_Auralizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.3.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Scala Scale Archive auralizer. Loads a scale from the AudioTools
#   Scala library, a native file chooser, or a curated list, then maps degrees
#   to frequencies through an explicit tuning layer, synthesises
#   tones with a separately-specified spectrum and envelope, and
#   plays the scale in several modes (ascending, descending,
#   ping-pong, arpeggio, sustained chord, broken chord, scale
#   against drone, A/B comparison with a second scale).
#
# Design
# ------
# The script enforces the separation of concerns requested in
# the project brief:
#
#   SCALE     (.scl parser)
#       degree list: cents values above 1/1, plus the period
#       scale.nDeg, scale.cents[], scale.ratios$[], scale.period
#
#   TUNING    (cents + fundamental -> Hz)
#       buildTuning: given fundamental, optional reference anchor,
#       and period transposition, produces freqs[] per degree
#
#   SPECTRUM  (partial recipe)
#       spec.nPartials, spec.mult[], spec.amp[]
#       independent of pitch: applied at synthesis time
#
#   TIMBRE    (amplitude envelope + perceptual shaping)
#       env.attack, env.decay, env.sustain, env.release
#       env.noteDur, env.gap
#
#   VOICING   (respace degrees across periods)
#       closed vs open, compact vs expanded
#       operates on scale degrees, produces (degree, shift) pairs
#
#   PLAYBACK  (sequences notes or builds chords)
#       renders the final Sound object
#
# Scale selection
# ---------------
# v1.3 removes the need to paste long Windows paths. The main source
# menu offers five paths:
#
#   (1) Reuse last scale: default. Reopens the most recently used scale
#       without showing a chooser, so DSP/playback parameters can be auditioned
#       repeatedly. The remembered selection persists between script runs.
#   (2) Choose from library: automatically locates AudioTools/Analysis/scl,
#       asks for a short filename filter (e.g. bohlen, 07-19, slendro),
#       then builds a dynamic option menu from the matching .scl files.
#   (3) Browse external .scl: opens Praat's native read-file chooser.
#   (4) Curated built-in: keeps the compact familiar preset list.
#   (5) Synthetic 12-TET: needs no file.
#
# Empty library filters are allowed only for small archives. In the full
# Scala archive, the user is asked to narrow the filter rather than being
# shown a several-thousand-item menu.
#
# Scala file conventions honoured
# -------------------------------
# * Lines starting with "!" are comments and skipped.
# * First non-comment line = description (displayed).
# * Next non-comment line = note count N.
# * Following N non-comment lines = interval values: a value with a
#   decimal point is cents; otherwise it is a ratio (including a bare
#   integer such as 2 = 2/1).
# * The Nth interval is the period (not always 2/1).
# * Malformed or truncated pitch data is rejected explicitly.
# * CRLF line endings are stripped.
#
# Usage
# -----
# Run the script. Fill the form. Hear the result. The script
# creates a single Sound object and leaves it selected.
#
# Changelog v1.3.1:
#   - Fixed Scala-library discovery for Praat 7 on Windows when AudioTools is
#     still installed in the legacy C:/Users/<user>/Praat location. The script
#     now checks USERPROFILE/Praat in addition to preferencesDirectory$.
#   - If automatic discovery still fails, opens a native folder chooser instead
#     of exiting. The chooser accepts the scl folder itself, its Analysis parent,
#     or the plugin_AudioTools root and resolves Analysis/scl automatically.
#
# Changelog v1.3.2:
#   - Added persistent last-scale memory. The default source is now Reuse last
#     scale, so rerunning the script to change tuning, playback, voicing,
#     spectrum, or envelope parameters does not reopen the Scala chooser.
#   - The remembered selection is stored in the Praat preferences apps folder,
#     outside the plug-in tree, and survives Praat/script restarts.
#   - If the remembered file was moved or deleted, the script falls back to the
#     AudioTools library chooser instead of failing. Synthetic 12-TET is also
#     remembered as a valid last selection.
#
# Changelog v1.3:
#   - Added a dynamic Scala-library chooser. AudioTools/Analysis/scl is found
#     automatically; the user filters by a short filename fragment and then
#     chooses from a generated option menu. No full Windows path is required.
#   - Added a native Browse path with chooseReadFile$ and kept a separate
#     curated preset source plus synthetic 12-TET.
#   - Library search handles 0/1/many matches explicitly and requires a
#     narrower filter above 250 matches so the menu remains practical.
#
# Changelog v1.2:
#   - Corrected Scala parsing: bare integers are ratios (e.g. 2 = 2/1),
#     an empty description line is preserved, malformed/truncated pitch data
#     now fails explicitly instead of silently inserting 0-cent degrees.
#   - Tuning controls are now independent: reference anchoring is opt-in,
#     degree 0 means implicit 1/1, and period transposition is applied after
#     anchoring so it can no longer be cancelled by the reference setting.
#   - Added Nyquist-aware partial filtering to prevent aliased harmonics.
#   - Made Compact voicing a real minimum-span period-folding operation.
#   - Fixed A/B archive lookup, inserted an audible A/B pause, restored the
#     first scale after rendering B, and made naming/visualization report A/B.
#   - Visualization uses symmetric waveform limits and safer Picture viewport
#     resets; spectrogram bandwidth follows the actually synthesized range.
#
# Changelog v1.1:
#   - External_scl_path now accepts EITHER a single .scl file OR the
#     folder holding the archive. v1.0 passed whatever was typed
#     straight to fileReadable(), which is false for a directory, so
#     pasting an archive folder exited with "Scala file not found"
#     naming a path that exists. With a folder, the filename comes from
#     the Builtin_scale menu.
#   - Backslash paths are normalized, and a trailing separator is
#     stripped, so a path copied from Windows Explorer works as typed.
#   - Added <preferences>/plugin_AudioTools/Analysis/scl to the search
#     list, which is where the archive sits in a standard AudioTools
#     install; v1.0 only looked one level higher.
#   - Failures say which file was looked for and where, instead of
#     echoing the folder back as if it were a missing file.
# ============================================================

form Scala Scale Auralizer
    comment === Scale source ===
    optionmenu Scale_source: 1
        option Reuse last scale (no chooser)
        option Choose from AudioTools library
        option Browse external .scl file
        option Curated built-in scale
        option Synthetic 12-TET

    comment Reuse last scale is the default after the first successful selection.
    comment Curated_scale is used only when Scale_source = Curated built-in.
    optionmenu Curated_scale: 1
        option Pythagorean 12 (pyth_12)
        option Young-Lonnberg guitar (young-lm_guitar)
        option Werckmeister III (werck3)
        option Kirnberger III (kirnberger3)
        option 1/4-comma meantone (meanquar)
        option Just intonation 12 (ji_12)
        option Just intonation 7 (ji_7)
        option Indian 12 (indian_12)
        option Slendro (slendro)
        option Alves slendro (alves_slendro)
        option Alves pelog (alves_pelog)
        option Harrison 5 (harrison_5)
        option Harmonical (harmonical)
        option Partch 43 (partch_43)
        option Bohlen-Pierce (bohlen-p) [non-octave, 3/1]
        option Carlos Alpha (carlos_alpha) [non-octave]
        option Carlos Beta (carlos_beta) [non-octave]
        option Carlos Gamma (carlos_gamma) [non-octave]

    comment === Tuning ===
    positive Fundamental_Hz 220
    boolean Use_reference_anchor 0
    comment Reference degree uses Scala indexing: 0 = implicit 1/1.
    integer Reference_degree 0
    positive Reference_Hz 220
    integer Transpose_periods 0

    comment === Playback ===
    optionmenu Mode: 2
        option Single tone (1/1 fundamental)
        option Ascending scale
        option Descending scale
        option Ping-pong
        option Arpeggio (broken chord of degree subset)
        option Sustained chord of degree subset
        option Scale against drone on 1/1
        option A/B compare (this scale vs second built-in)
    comment Subset degrees use Scala indices: 0 = 1/1, 1 = first .scl interval.
    sentence Subset_degrees 0 2 4
    optionmenu Second_builtin_for_AB: 1
        option 12-TET (synthetic)
        option Pythagorean 12 (pyth_12)
        option Partch 43
        option Bohlen-Pierce
        option Carlos Alpha

    comment === Voicing (respace) ===
    optionmenu Voicing: 1
        option Closed (same period)
        option Open (alternate-degree period up)
        option Compact (minimum-span period folding)
        option Expanded (span two periods)

    comment === Spectrum ===
    optionmenu Spectrum: 2
        option Pure sine
        option Harmonic (8 partials, 1/n)
        option Harmonic (16 partials, 1/n)
        option Odd harmonics only (8 partials)
        option Bright (flat 8 partials)
        option Dark (steep 1/n^2 roll-off, 8 partials)

    comment === Envelope (per note) ===
    positive Note_duration_s 0.6
    positive Gap_s 0.05
    positive Attack_ms 15
    positive Release_ms 80

    comment === Output ===
    positive Output_gain 0.7
    boolean Show_visualization 1
    boolean Play_result 1
endform

clearinfo

# ============================================================
# SCALE: Parse a .scl file at path into globals scale.*
# Output:
#   scale.name$     description line
#   scale.nDeg      number of scale degrees (= declared N)
#   scale.cents[d] cents above 1/1, for d = 1..N (last = period)
#   scale.ratios$[d] textual representation ("5/4" or "386.314")
#   scale.period    cents value of the period (= scale.cents[N])
#   scale.isOctave  1 if period within 1 cent of 1200, else 0
#   scale.truncated 0 on every successful strict parse
# ============================================================
procedure parseScalaFile: .path$
    if not fileReadable(.path$)
        exitScript: "Scala file not found: " + .path$
    endif

    .strs = Read Strings from raw text file: .path$
    .nLines = Get number of strings

    scale.name$ = "(unnamed)"
    scale.nDeg = 0
    scale.truncated = 0
    .haveDescription = 0
    .haveCount = 0
    .degIdx = 0

    for .i from 1 to .nLines
        selectObject: .strs
        .raw$ = Get string: .i
        .line$ = replace_regex$(.raw$, "[\r\n]+$", "", 0)
        .trim$ = replace_regex$(.line$, "^[ \t]+|[ \t]+$", "", 0)

        # A leading ! marks a comment at every stage.
        if left$(.trim$, 1) = "!"
            # ignore

        elsif .haveDescription = 0
            # In the Scala format, the description line may intentionally be
            # empty. It still counts as the description line; do not skip it.
            if .trim$ <> ""
                scale.name$ = .trim$
            endif
            .haveDescription = 1

        elsif .haveCount = 0
            # Be tolerant of blank separator lines here, but require the
            # actual count token to be a positive integer. A zero-note .scl
            # is legal Scala, but has no explicit period and therefore cannot
            # drive this period-based auralizer.
            if .trim$ <> ""
                .tok$ = replace_regex$(.trim$, "^[ \t]*(\S+).*$", "\1", 0)
                .countV = number(.tok$)
                if .countV = undefined or .countV < 1 or abs(.countV - round(.countV)) > 0.0000001
                    removeObject: .strs
                    exitScript: "Scala file has invalid/unsupported note count: " + .trim$ + newline$ +
                    ... "This auralizer requires at least one pitch value so the final value can define the period."
                endif
                scale.nDeg = round(.countV)
                .haveCount = 1
            endif

        elsif .degIdx < scale.nDeg
            # Blank lines between pitch entries are tolerated. For a real
            # pitch line, only the first whitespace-delimited token matters.
            if .trim$ <> ""
                .tok$ = replace_regex$(.trim$, "^[ \t]*(\S+).*$", "\1", 0)
                @parseScalaValue: .tok$
                if parseScalaValue.ok = 0
                    removeObject: .strs
                    exitScript: "Invalid Scala pitch value at file line " + string$(.i) + ": " + .tok$
                endif
                .degIdx = .degIdx + 1
                scale.cents[.degIdx] = parseScalaValue.cents
                scale.ratios$[.degIdx] = .tok$
            endif
        endif
    endfor

    removeObject: .strs

    if .haveDescription = 0 or .haveCount = 0
        exitScript: "Scala file is incomplete: missing description or note count."
    endif
    if .degIdx < scale.nDeg
        scale.truncated = 1
        exitScript: "Scala file is truncated: declared " + string$(scale.nDeg) +
        ... " pitch values but supplied only " + string$(.degIdx) + "."
    endif

    scale.period = scale.cents[scale.nDeg]
    if scale.period <= 0
        exitScript: "Scala period must be above 1/1 for this auralizer; parsed period = " + fixed$(scale.period, 6) + " cents."
    endif

    scale.isOctave = 0
    if abs(scale.period - 1200.0) < 1.0
        scale.isOctave = 1
    endif
endproc

# ------------------------------------------------------------
# Parse a single Scala scale-degree token into cents.
# Official .scl rule:
#   * contains a decimal point -> cents
#   * otherwise -> ratio ("5/4" or a bare integer such as "2" = 2/1)
# Cents may be negative; ratio numerator/denominator must be positive.
# ------------------------------------------------------------
procedure parseScalaValue: .tok$
    .ok = 0
    .cents = 0

    if index(.tok$, ".") > 0
        .v = number(.tok$)
        if .v <> undefined
            .cents = .v
            .ok = 1
        endif
    else
        .numV = undefined
        .denV = 1
        if index(.tok$, "/") > 0
            .slashPos = index(.tok$, "/")
            .num$ = left$(.tok$, .slashPos - 1)
            .den$ = mid$(.tok$, .slashPos + 1, length(.tok$))
            .numV = number(.num$)
            .denV = number(.den$)
        else
            # Bare integer: Scala ratio shorthand, e.g. 2 == 2/1.
            .numV = number(.tok$)
        endif

        if .numV <> undefined and .denV <> undefined
            if .numV > 0 and .denV > 0
                .cents = 1200 * ln(.numV / .denV) / ln(2)
                .ok = 1
            endif
        endif
    endif
endproc

# ============================================================
# SCALE: Generate a synthetic 12-TET scale in memory.
# Used as the built-in fallback that needs no .scl file.
# ============================================================
procedure buildSynthetic12TET
    scale.name$ = "12-TET (synthetic, 100-cent equal steps)"
    scale.nDeg = 12
    for .d from 1 to 12
        scale.cents[.d] = .d * 100.0
        scale.ratios$[.d] = fixed$(.d * 100.0, 3)
    endfor
    scale.ratios$[12] = "2/1"
    scale.cents[12] = 1200.0
    scale.period = 1200.0
    scale.isOctave = 1
    scale.truncated = 0
endproc

# ============================================================
# TUNING: Given scale.* and fundamental/reference/transpose,
# fill freqs[1..nDeg] with the Hz for each degree.
#
# Semantics:
#   - Degree 0 is the implicit Scala 1/1; degree 1 is the first
#     interval listed in the .scl file.
#   - Fundamental_Hz sets degree 0 when reference anchoring is off.
#   - With Use_reference_anchor on, the chosen degree is first aligned
#     to Reference_Hz. Transpose_periods is then applied afterward.
#   - Therefore anchoring and transposition remain independent controls.
# ============================================================
procedure buildTuning: .fund, .useAnchor, .refDeg, .refHz, .transposePeriods
    if .fund <= 0
        exitScript: "Fundamental_Hz must be positive."
    endif

    # Build an untransposed tuning around the requested fundamental.
    .anchorFactor = 1.0
    if .useAnchor = 1
        if .refDeg < 0 or .refDeg > scale.nDeg
            exitScript: "Reference_degree is outside this scale: " + string$(.refDeg) +
            ... " (allowed 0.." + string$(scale.nDeg) + ")"
        endif
        if .refDeg = 0
            .refCents = 0
        else
            .refCents = scale.cents[.refDeg]
        endif
        .unanchoredRef = .fund * 2 ^ (.refCents / 1200.0)
        if .unanchoredRef <= 0 or .refHz <= 0
            exitScript: "Invalid reference tuning."
        endif
        .anchorFactor = .refHz / .unanchoredRef
    endif

    # Transposition is deliberately applied AFTER anchoring, so the two
    # controls remain independent instead of the anchor cancelling transpose.
    .transposeFactor = 2 ^ ((.transposePeriods * scale.period) / 1200.0)

    freqs[0] = .fund * .anchorFactor * .transposeFactor
    for .d from 1 to scale.nDeg
        freqs[.d] = .fund * 2 ^ (scale.cents[.d] / 1200.0)
        freqs[.d] = freqs[.d] * .anchorFactor * .transposeFactor
    endfor
endproc

# ============================================================
# SPECTRUM: Fill spec.nPartials, spec.mult[], spec.amp[].
# spec.mult[k] is the frequency multiplier for partial k (e.g. 1,
# 2, 3 for harmonic; 1, 3, 5 for odd only). spec.amp[k] is its
# relative amplitude before envelope.
# ============================================================
procedure buildSpectrum: .mode
    if .mode = 1
        # Pure sine: one partial at the fundamental.
        spec.nPartials = 1
        spec.mult[1] = 1
        spec.amp[1] = 1.0
    elsif .mode = 2
        # Harmonic, 8 partials, 1/n
        spec.nPartials = 8
        for .k from 1 to 8
            spec.mult[.k] = .k
            spec.amp[.k] = 1.0 / .k
        endfor
    elsif .mode = 3
        # Harmonic, 16 partials, 1/n
        spec.nPartials = 16
        for .k from 1 to 16
            spec.mult[.k] = .k
            spec.amp[.k] = 1.0 / .k
        endfor
    elsif .mode = 4
        # Odd harmonics only, 8 partials: 1, 3, 5, 7, 9, 11, 13, 15
        spec.nPartials = 8
        for .k from 1 to 8
            spec.mult[.k] = 2 * .k - 1
            spec.amp[.k] = 1.0 / spec.mult[.k]
        endfor
    elsif .mode = 5
        # Bright: flat 8 partials
        spec.nPartials = 8
        for .k from 1 to 8
            spec.mult[.k] = .k
            spec.amp[.k] = 1.0
        endfor
    else
        # Dark: 8 partials, 1/n^2
        spec.nPartials = 8
        for .k from 1 to 8
            spec.mult[.k] = .k
            spec.amp[.k] = 1.0 / (.k * .k)
        endfor
    endif

    # Normalise so that sum of amplitudes = 1 (prevents clipping
    # regardless of which spectrum the user picks).
    .total = 0
    for .k from 1 to spec.nPartials
        .total = .total + spec.amp[.k]
    endfor
    if .total > 0
        for .k from 1 to spec.nPartials
            spec.amp[.k] = spec.amp[.k] / .total
        endfor
    endif

    spec.maxMult = 1
    for .k from 1 to spec.nPartials
        if spec.mult[.k] > spec.maxMult
            spec.maxMult = spec.mult[.k]
        endif
    endfor
endproc

# ============================================================
# SYNTH: Create one Sound object for a note at frequency fHz,
# with the current spec.* and envelope. Returns soundId via
# synthNote.id.
#
# Uses Create Sound from formula with literal values baked into
# the formula string (safer than variable interpolation inside
# Praat Formula contexts).
# ============================================================
procedure synthNote: .fHz, .duration, .attack, .release, .sampleRate, .label$
    if .fHz <= 0
        .fHz = 1
    endif
    if .duration < 0.02
        .duration = 0.02
    endif

    # Band-limit the partial recipe before synthesis. Without this, open or
    # expanded voicings of wide-period scales can push upper harmonics above
    # Nyquist and fold them back as aliases. Renormalize only the retained
    # partials so a note does not become quieter merely because high partials
    # were removed.
    .nyquistGuard = .sampleRate * 0.48
    .activeAmp = 0
    for .k from 1 to spec.nPartials
        .partialFreq = spec.mult[.k] * .fHz
        if .partialFreq > 0 and .partialFreq < .nyquistGuard
            .activeAmp = .activeAmp + spec.amp[.k]
        endif
    endfor

    .formula$ = "0"
    if .activeAmp > 0
        for .k from 1 to spec.nPartials
            .partialFreq = spec.mult[.k] * .fHz
            if .partialFreq > 0 and .partialFreq < .nyquistGuard
                .a = spec.amp[.k] / .activeAmp
                .formula$ = .formula$ + " + " + fixed$(.a, 8)
                ... + " * sin(2*pi*" + fixed$(.partialFreq, 8) + "*x)"
            endif
        endfor
    endif

    synthNote.id = Create Sound from formula: .label$, 1, 0, .duration,
        ... .sampleRate, .formula$

    # Linear attack and release. Form fields are positive, but retain the
    # guards so future programmatic calls cannot divide by zero.
    .atkSec = .attack / 1000.0
    .relSec = .release / 1000.0
    if .atkSec < 0.000001
        .atkSec = 0.000001
    endif
    if .relSec < 0.000001
        .relSec = 0.000001
    endif
    if .atkSec > .duration * 0.5
        .atkSec = .duration * 0.5
    endif
    if .relSec > .duration * 0.5
        .relSec = .duration * 0.5
    endif
    .relStart = .duration - .relSec

    .atk$ = fixed$(.atkSec, 8)
    .rel$ = fixed$(.relSec, 8)
    .rs$ = fixed$(.relStart, 8)
    .dur$ = fixed$(.duration, 8)

    selectObject: synthNote.id
    Formula: "if x < " + .atk$
        ... + " then self * (x / " + .atk$ + ")"
        ... + " else self fi"
    Formula: "if x > " + .rs$
        ... + " then self * ((" + .dur$ + " - x) / " + .rel$ + ")"
        ... + " else self fi"
endproc

# ============================================================
# SYNTH: Build a sustained chord from frequencies in chordFreqs[1..nFreqs].
# (Since Praat indexed-variable families can't be passed as arguments,
# we read the caller's frequencies via the globally-named convention:
# caller must populate chordFreqs[1..nFreqs] before calling.)
# Returns synthChord.id.
# ============================================================
procedure synthChord: .nFreqs, .duration, .attack, .release, .sampleRate, .label$
    if .nFreqs < 1
        exitScript: "synthChord: no frequencies"
    endif

    # Render first note to a buffer, add subsequent notes into it.
    @synthNote: chordFreqs[1], .duration, .attack, .release, .sampleRate, .label$ + "_p1"
    .bufId = synthNote.id

    for .k from 2 to .nFreqs
        @synthNote: chordFreqs[.k], .duration, .attack, .release, .sampleRate, "_tmp"
        .tmpId = synthNote.id
        .tmpStr$ = fixed$(.tmpId, 0)
        selectObject: .bufId
        Formula: "self + object[" + .tmpStr$ + ", col]"
        removeObject: .tmpId
    endfor

    # Normalize by N so chord stays within same amplitude range
    # regardless of voice count.
    .gain = 1.0 / .nFreqs
    selectObject: .bufId
    Formula: "self * " + fixed$(.gain, 6)

    synthChord.id = .bufId
endproc

# ============================================================
# VOICING: Populate periodOff[1..nList] based on the style index.
# Reads from the caller's own degree list by index count (.nList)
# only; the specific degrees are looked up elsewhere. This is a
# pure index-to-offset mapping, so no degree list is needed.
# ============================================================
procedure voicingRespace: .style, .nList
    for .i from 1 to .nList
        periodOff[.i] = 0
    endfor

    if .style = 2
        # Open: alternate voices up one period.
        for .i from 1 to .nList
            if (.i mod 2) = 0
                periodOff[.i] = 1
            endif
        endfor

    elsif .style = 3
        # Compact: find the circular cut that gives the minimum span within
        # one period, then choose a common register so voice 1 stays at its
        # original period. This is meaningfully different from Closed.
        if .nList > 1 and scale.period > 0
            .bestSpan = 1000000000
            .bestCut = 0

            for .j from 1 to .nList
                .dj = subset[.j]
                if .dj = 0
                    .cut = 0
                else
                    .cut = scale.cents[.dj]
                endif

                .minV = 1000000000
                .maxV = -1000000000
                for .i from 1 to .nList
                    .di = subset[.i]
                    if .di = 0
                        .c = 0
                    else
                        .c = scale.cents[.di]
                    endif
                    .shifted = .c
                    if .shifted < .cut
                        .shifted = .shifted + scale.period
                    endif
                    if .shifted < .minV
                        .minV = .shifted
                    endif
                    if .shifted > .maxV
                        .maxV = .shifted
                    endif
                endfor
                .span = .maxV - .minV
                if .span < .bestSpan
                    .bestSpan = .span
                    .bestCut = .cut
                endif
            endfor

            for .i from 1 to .nList
                .di = subset[.i]
                if .di = 0
                    .c = 0
                else
                    .c = scale.cents[.di]
                endif
                if .c < .bestCut
                    periodOff[.i] = 1
                else
                    periodOff[.i] = 0
                endif
            endfor

            .baseOff = periodOff[1]
            for .i from 1 to .nList
                periodOff[.i] = periodOff[.i] - .baseOff
            endfor
        endif

    elsif .style = 4
        # Expanded: first half stays, second half shifts up one period.
        .half = .nList / 2
        for .i from 1 to .nList
            if .i > .half
                periodOff[.i] = 1
            endif
        endfor
    endif
endproc

# ============================================================
# PARSE: Turn "0 2 4" into integer list subset[], length nSubset.
# Skips tokens that are out of range for the current scale.
# ============================================================
procedure parseSubset: .str$
    nSubset = 0
    .s$ = replace_regex$(.str$, "[,;\t]+", " ", 0)
    .s$ = replace_regex$(.s$, " +", " ", 0)
    .s$ = replace_regex$(.s$, "^[ \t]+|[ \t]+$", "", 0)

    while length(.s$) > 0
        .spPos = index(.s$, " ")
        if .spPos > 0
            .tok$ = left$(.s$, .spPos - 1)
            .s$ = replace_regex$(mid$(.s$, .spPos + 1, 10000), "^[ \t]+", "", 0)
        else
            .tok$ = .s$
            .s$ = ""
        endif
        if length(.tok$) > 0
            .v = number(.tok$)
            if .v <> undefined
                .vi = round(.v)
                if abs(.v - .vi) < 0.0000001 and .vi >= 0 and .vi <= scale.nDeg
                    nSubset = nSubset + 1
                    subset[nSubset] = .vi
                endif
            endif
        endif
    endwhile

    if nSubset = 0
        # Fall back to degree 0 alone (the fundamental)
        nSubset = 1
        subset[1] = 0
    endif
endproc

# ============================================================
# LIBRARY FOLDER: locate the Scala archive without requiring a user path.
# Praat 6 and Praat 7 use different preferences folders on Windows, so we
# search both the current preferences folder and the legacy USERPROFILE/Praat
# location used by existing AudioTools installations.
# ============================================================
procedure locateScalaArchive
    locateScalaArchive.found = 0
    locateScalaArchive.dir$ = ""

    # Current Praat preferences location (Praat 6 or 7, platform-dependent).
    .candidate$ = preferencesDirectory$ + "/plugin_AudioTools/Analysis/scl"
    if folderExists(.candidate$)
        locateScalaArchive.dir$ = .candidate$
        locateScalaArchive.found = 1
    endif

    if locateScalaArchive.found = 0
        .candidate$ = preferencesDirectory$ + "/plugin_AudioTools/scl"
        if folderExists(.candidate$)
            locateScalaArchive.dir$ = .candidate$
            locateScalaArchive.found = 1
        endif
    endif

    # Windows legacy AudioTools location, e.g. C:/Users/User/Praat/... .
    # This is important when Praat 7 stores its preferences in AppData/Roaming
    # but the plug-in library still lives in the Praat 6-style folder.
    if locateScalaArchive.found = 0
        .userProfile$ = environment$("USERPROFILE")
        if .userProfile$ <> ""
            .userProfile$ = replace$(.userProfile$, "\", "/", 0)
            .candidate$ = .userProfile$ + "/Praat/plugin_AudioTools/Analysis/scl"
            if folderExists(.candidate$)
                locateScalaArchive.dir$ = .candidate$
                locateScalaArchive.found = 1
            endif
        endif
    endif

    if locateScalaArchive.found = 0
        .userProfile$ = environment$("USERPROFILE")
        if .userProfile$ <> ""
            .userProfile$ = replace$(.userProfile$, "\", "/", 0)
            .candidate$ = .userProfile$ + "/Praat/plugin_AudioTools/scl"
            if folderExists(.candidate$)
                locateScalaArchive.dir$ = .candidate$
                locateScalaArchive.found = 1
            endif
        endif
    endif

    # Relative fallbacks for portable/development layouts.
    if locateScalaArchive.found = 0
        .candidate$ = defaultDirectory$ + "/scl"
        if folderExists(.candidate$)
            locateScalaArchive.dir$ = .candidate$
            locateScalaArchive.found = 1
        endif
    endif

    if locateScalaArchive.found = 0
        .candidate$ = defaultDirectory$ + "/Analysis/scl"
        if folderExists(.candidate$)
            locateScalaArchive.dir$ = .candidate$
            locateScalaArchive.found = 1
        endif
    endif
endproc

# ============================================================
# LIBRARY CHOOSER: search by a short filename fragment, then show a
# dynamically-generated option menu. At most 250 entries are shown at once;
# a broad search is sent back to the filter dialog for refinement.
# Output:
#   chooseLibraryScale.cancelled = 1 if the user cancels
#   chooseLibraryScale.filename$ = selected basename
#   chooseLibraryScale.fullpath$ = selected full path
# ============================================================
procedure chooseLibraryScale: .archiveDir$
    chooseLibraryScale.cancelled = 0
    chooseLibraryScale.filename$ = ""
    chooseLibraryScale.fullpath$ = ""

    .allFiles$# = fileNames_caseInsensitive$# (.archiveDir$ + "/*.scl")
    .nAll = size(.allFiles$#)
    if .nAll < 1
        exitScript: "No .scl files were found in:" + newline$ + "  " + .archiveDir$
    endif

    .filter$ = ""
    .finished = 0
    while .finished = 0
        beginPause: "Scala library search"
            comment: "Archive: " + .archiveDir$
            comment: "There are " + string$(.nAll) + " .scl files. Type part of a filename."
            comment: "Examples: bohlen, 07-19, slendro, carlos, pelog"
            sentence: "Filter", .filter$
        .clicked = endPause: "Cancel", "Search", 2, 1

        if .clicked = 1
            chooseLibraryScale.cancelled = 1
            .finished = 1
        else
            .filter$ = filter$
            .filterLower$ = lowerCase$(.filter$)
            .nMatch = 0

            for .i to .nAll
                .name$ = .allFiles$#[.i]
                .include = 0
                if .filter$ = ""
                    .include = 1
                elsif index(lowerCase$(.name$), .filterLower$) > 0
                    .include = 1
                endif

                if .include = 1
                    .nMatch = .nMatch + 1
                    if .nMatch <= 250
                        .match$[.nMatch] = .name$
                    endif
                endif
            endfor

            if .nMatch = 0
                pauseScript: "No Scala files match '" + .filter$ + "'. Try another filename fragment."

            elsif .nMatch > 250
                pauseScript: "The filter '" + .filter$ + "' matches " + string$(.nMatch) +
                ... " files. Please narrow the search to 250 or fewer matches."

            elsif .nMatch = 1
                chooseLibraryScale.filename$ = .match$[1]
                chooseLibraryScale.fullpath$ = .archiveDir$ + "/" + chooseLibraryScale.filename$
                .finished = 1

            else
                beginPause: "Choose Scala scale"
                    comment: string$(.nMatch) + " matches for '" + .filter$ + "'."
                    optionmenu: "Library_choice", 1
                    for .i to .nMatch
                        option: .match$[.i]
                    endfor
                .pickClicked = endPause: "Cancel", "Back", "Load", 3, 1

                if .pickClicked = 1
                    chooseLibraryScale.cancelled = 1
                    .finished = 1
                elsif .pickClicked = 2
                    # Return to the search/filter window, preserving .filter$.
                else
                    chooseLibraryScale.filename$ = library_choice$
                    chooseLibraryScale.fullpath$ = .archiveDir$ + "/" + chooseLibraryScale.filename$
                    .finished = 1
                endif
            endif
        endif
    endwhile
endproc

# ============================================================
# RESOLVE: Look up a curated built-in filename from its menu index.
# Curated indices 1..18 map directly to archive filenames.
# ============================================================
procedure resolveBuiltin: .idx, .archiveDir$
    resolveBuiltin.filename$ = ""
    resolveBuiltin.useSynthetic = 0
    if .idx = 1
        resolveBuiltin.filename$ = "pyth_12.scl"
    elsif .idx = 2
        resolveBuiltin.filename$ = "young-lm_guitar.scl"
    elsif .idx = 3
        resolveBuiltin.filename$ = "werck3.scl"
    elsif .idx = 4
        resolveBuiltin.filename$ = "kirnberger3.scl"
    elsif .idx = 5
        resolveBuiltin.filename$ = "meanquar.scl"
    elsif .idx = 6
        resolveBuiltin.filename$ = "ji_12.scl"
    elsif .idx = 7
        resolveBuiltin.filename$ = "ji_7.scl"
    elsif .idx = 8
        resolveBuiltin.filename$ = "indian_12.scl"
    elsif .idx = 9
        resolveBuiltin.filename$ = "slendro.scl"
    elsif .idx = 10
        resolveBuiltin.filename$ = "alves_slendro.scl"
    elsif .idx = 11
        resolveBuiltin.filename$ = "alves_pelog.scl"
    elsif .idx = 12
        resolveBuiltin.filename$ = "harrison_5.scl"
    elsif .idx = 13
        resolveBuiltin.filename$ = "harmonical.scl"
    elsif .idx = 14
        resolveBuiltin.filename$ = "partch_43.scl"
    elsif .idx = 15
        resolveBuiltin.filename$ = "bohlen-p.scl"
    elsif .idx = 16
        resolveBuiltin.filename$ = "carlos_alpha.scl"
    elsif .idx = 17
        resolveBuiltin.filename$ = "carlos_beta.scl"
    elsif .idx = 18
        resolveBuiltin.filename$ = "carlos_gamma.scl"
    endif

    if .archiveDir$ <> ""
        resolveBuiltin.fullpath$ = .archiveDir$ + "/" + resolveBuiltin.filename$
    else
        resolveBuiltin.fullpath$ = ""
    endif
endproc

# ============================================================
# RESOLVE AB: 5-option subset for the A/B second scale.
# ============================================================
procedure resolveBuiltinAB: .idx
    resolveBuiltinAB.useSynthetic = 0
    resolveBuiltinAB.filename$ = ""
    if .idx = 1
        resolveBuiltinAB.useSynthetic = 1
    elsif .idx = 2
        resolveBuiltinAB.filename$ = "pyth_12.scl"
    elsif .idx = 3
        resolveBuiltinAB.filename$ = "partch_43.scl"
    elsif .idx = 4
        resolveBuiltinAB.filename$ = "bohlen-p.scl"
    elsif .idx = 5
        resolveBuiltinAB.filename$ = "carlos_alpha.scl"
    endif
endproc

# ============================================================
# ARCHIVE LOOKUP: search a preferred folder first, then standard
# AudioTools / working-directory locations.
# ============================================================
procedure findArchiveScale: .filename$, .preferredDir$
    findArchiveScale.found = 0
    findArchiveScale.fullpath$ = ""

    if .preferredDir$ <> ""
        .test$ = .preferredDir$ + "/" + .filename$
        if fileReadable(.test$)
            findArchiveScale.fullpath$ = .test$
            findArchiveScale.found = 1
        endif
    endif

    if findArchiveScale.found = 0
        .dir$ = preferencesDirectory$ + "/plugin_AudioTools/Analysis/scl"
        .test$ = .dir$ + "/" + .filename$
        if fileReadable(.test$)
            findArchiveScale.fullpath$ = .test$
            findArchiveScale.found = 1
        endif
    endif
    if findArchiveScale.found = 0
        .dir$ = preferencesDirectory$ + "/plugin_AudioTools/scl"
        .test$ = .dir$ + "/" + .filename$
        if fileReadable(.test$)
            findArchiveScale.fullpath$ = .test$
            findArchiveScale.found = 1
        endif
    endif
    if findArchiveScale.found = 0
        .userProfile$ = environment$("USERPROFILE")
        if .userProfile$ <> ""
            .userProfile$ = replace$(.userProfile$, "\", "/", 0)
            .dir$ = .userProfile$ + "/Praat/plugin_AudioTools/Analysis/scl"
            .test$ = .dir$ + "/" + .filename$
            if fileReadable(.test$)
                findArchiveScale.fullpath$ = .test$
                findArchiveScale.found = 1
            endif
        endif
    endif
    if findArchiveScale.found = 0
        .userProfile$ = environment$("USERPROFILE")
        if .userProfile$ <> ""
            .userProfile$ = replace$(.userProfile$, "\", "/", 0)
            .dir$ = .userProfile$ + "/Praat/plugin_AudioTools/scl"
            .test$ = .dir$ + "/" + .filename$
            if fileReadable(.test$)
                findArchiveScale.fullpath$ = .test$
                findArchiveScale.found = 1
            endif
        endif
    endif
    if findArchiveScale.found = 0
        .dir$ = defaultDirectory$ + "/scl"
        .test$ = .dir$ + "/" + .filename$
        if fileReadable(.test$)
            findArchiveScale.fullpath$ = .test$
            findArchiveScale.found = 1
        endif
    endif
    if findArchiveScale.found = 0
        .test$ = defaultDirectory$ + "/" + .filename$
        if fileReadable(.test$)
            findArchiveScale.fullpath$ = .test$
            findArchiveScale.found = 1
        endif
    endif
endproc

# ============================================================
# MAIN
# ============================================================
writeInfoLine: "=== Scala Scale Auralizer v1.3.2 ==="

# Determine which source to use.
# Scale_source:
#   1 = reuse last, 2 = library search, 3 = native Browse,
#   4 = curated built-in, 5 = synthetic 12-TET.
#
# Persistent state lives in Praat's preferences/apps area rather than inside
# the plug-in tree. This lets the selected scale survive script/Praat restarts.
stateAppsDir$ = preferencesDirectory$ + "/apps"
stateDir$ = stateAppsDir$ + "/AudioTools"
stateFile$ = stateDir$ + "/Scala_Scale_Auralizer_last_scale.txt"
syntheticStateToken$ = "__AUDIOTOOLS_SYNTHETIC_12TET__"
lastScaleToken$ = ""
if fileReadable(stateFile$)
    lastScaleToken$ = readFile$(stateFile$)
    lastScaleToken$ = replace$(lastScaleToken$, "\r", "", 0)
    lastScaleToken$ = replace$(lastScaleToken$, "\n", "", 0)
endif

loadedFromPath$ = ""
archiveDir$ = ""
selectedScaleFile$ = ""
scaleLoaded = 0
usedSynthetic = 0

if scale_source = 1
    # --- Fast path: reopen the previous scale without any chooser. ---
    if lastScaleToken$ = syntheticStateToken$
        @buildSynthetic12TET
        usedSynthetic = 1
        scaleLoaded = 1
        appendInfoLine: "Reusing last scale: synthetic 12-TET."
    elsif lastScaleToken$ <> "" and fileReadable(lastScaleToken$)
        loadedFromPath$ = lastScaleToken$
        lastSlashPos = rindex(loadedFromPath$, "/")
        lastBackPos = rindex(loadedFromPath$, "\")
        if lastBackPos > lastSlashPos
            lastSlashPos = lastBackPos
        endif
        if lastSlashPos > 0
            archiveDir$ = left$(loadedFromPath$, lastSlashPos - 1)
            selectedScaleFile$ = mid$(loadedFromPath$, lastSlashPos + 1, length(loadedFromPath$))
        else
            selectedScaleFile$ = loadedFromPath$
        endif
        @parseScalaFile: loadedFromPath$
        scaleLoaded = 1
        appendInfoLine: "Reusing last Scala scale: ", selectedScaleFile$
        appendInfoLine: "  ", loadedFromPath$
    else
        appendInfoLine: "No valid remembered Scala scale; opening the library chooser once."
    endif

elsif scale_source = 3
    # --- Native file browser: no path typing. ---
    loadedFromPath$ = chooseReadFile$: "Choose a Scala .scl file"
    if loadedFromPath$ = ""
        exitScript: "Scala file selection cancelled."
    endif
    if length(loadedFromPath$) < 5 or lowerCase$(right$(loadedFromPath$, 4)) <> ".scl"
        exitScript: "Please choose a Scala .scl file."
    endif
    if not fileReadable(loadedFromPath$)
        exitScript: "Scala file not readable:" + newline$ + "  " + loadedFromPath$
    endif

    loadedFromPath$ = replace$(loadedFromPath$, "\", "/", 0)
    lastSlashPos = rindex(loadedFromPath$, "/")
    if lastSlashPos > 0
        archiveDir$ = left$(loadedFromPath$, lastSlashPos - 1)
        selectedScaleFile$ = mid$(loadedFromPath$, lastSlashPos + 1, length(loadedFromPath$))
    else
        selectedScaleFile$ = loadedFromPath$
    endif

    @parseScalaFile: loadedFromPath$
    scaleLoaded = 1
    appendInfoLine: "Loaded from Browse:"
    appendInfoLine: "  ", loadedFromPath$

elsif scale_source = 4
    # --- Compact curated list; locate its .scl automatically. ---
    @resolveBuiltin: curated_scale, ""
    @findArchiveScale: resolveBuiltin.filename$, ""
    if findArchiveScale.found = 0
        exitScript: "Could not locate curated Scala file:" + newline$ +
        ... "  " + resolveBuiltin.filename$ + newline$ +
        ... "Use Choose from library or Browse external .scl instead."
    endif

    loadedFromPath$ = replace$(findArchiveScale.fullpath$, "\", "/", 0)
    selectedScaleFile$ = resolveBuiltin.filename$
    lastSlashPos = rindex(loadedFromPath$, "/")
    if lastSlashPos > 0
        archiveDir$ = left$(loadedFromPath$, lastSlashPos - 1)
    endif
    @parseScalaFile: loadedFromPath$
    scaleLoaded = 1
    appendInfoLine: "Loaded curated scale: ", selectedScaleFile$
    appendInfoLine: "  ", loadedFromPath$

elsif scale_source = 5
    # --- Synthetic 12-TET: no file. ---
    @buildSynthetic12TET
    usedSynthetic = 1
    scaleLoaded = 1
    appendInfoLine: "Using synthetic 12-TET (no file needed)."
endif

# Library selection is explicit (source 2), and also the graceful fallback when
# Reuse last scale has no state yet or its remembered file has disappeared.
if scale_source = 2 or scaleLoaded = 0
    @locateScalaArchive
    if locateScalaArchive.found = 0
        manualArchiveDir$ = chooseFolder$: "Choose the AudioTools Scala folder (scl)"
        if manualArchiveDir$ = ""
            exitScript: "Scala archive selection cancelled."
        endif

        manualArchiveDir$ = replace$(manualArchiveDir$, "\", "/", 0)
        if folderExists(manualArchiveDir$ + "/Analysis/scl")
            manualArchiveDir$ = manualArchiveDir$ + "/Analysis/scl"
        elsif folderExists(manualArchiveDir$ + "/scl")
            manualArchiveDir$ = manualArchiveDir$ + "/scl"
        endif

        manualFiles$# = fileNames_caseInsensitive$# (manualArchiveDir$ + "/*.scl")
        if size(manualFiles$#) < 1
            exitScript: "The selected folder contains no .scl files:" + newline$ +
            ... "  " + manualArchiveDir$
        endif
        archiveDir$ = manualArchiveDir$
        appendInfoLine: "Scala archive chosen manually: ", archiveDir$
    else
        archiveDir$ = locateScalaArchive.dir$
    endif

    @chooseLibraryScale: archiveDir$
    if chooseLibraryScale.cancelled = 1
        exitScript: "Scala scale selection cancelled."
    endif

    selectedScaleFile$ = chooseLibraryScale.filename$
    loadedFromPath$ = replace$(chooseLibraryScale.fullpath$, "\", "/", 0)
    @parseScalaFile: loadedFromPath$
    scaleLoaded = 1
    usedSynthetic = 0
    appendInfoLine: "Scala library: ", archiveDir$
    appendInfoLine: "Selected file: ", selectedScaleFile$
endif

# Remember only a successfully parsed/built selection. The state file contains
# either one normalized .scl path or a private token for synthetic 12-TET.
createFolder: stateAppsDir$
createFolder: stateDir$
if usedSynthetic = 1
    writeFile: stateFile$, syntheticStateToken$
elsif loadedFromPath$ <> ""
    writeFile: stateFile$, replace$(loadedFromPath$, "\", "/", 0)
endif

appendInfoLine: ""
appendInfoLine: "Scale: ", scale.name$
appendInfoLine: "Degrees: ", scale.nDeg,
    ... "  Period: ", fixed$(scale.period, 3), " cents"
if scale.isOctave = 1
    appendInfoLine: "Period type: octave (2/1)"
else
    appendInfoLine: "Period type: NON-OCTAVE"
endif
appendInfoLine: ""

# Safe defaults for comparison-only metadata; A/B mode overwrites these.
compare.nDeg = 0
compare.period = scale.period
compare.isOctave = scale.isOctave
compare.name$ = ""
sceneName$ = scale.name$

# ============================================================
# Build tuning
# ============================================================
@buildTuning: fundamental_Hz, use_reference_anchor, reference_degree, reference_Hz, transpose_periods

# ============================================================
# Build spectrum
# ============================================================
@buildSpectrum: spectrum

# ============================================================
# Print tuning table
# ============================================================
appendInfoLine: "Degree  Ratio/Cents        Cents       Frequency (Hz)"
appendInfoLine: "------- ------------------ ----------- -------------"
appendInfoLine: "     0  (1/1)                    0.00  ",
    ... fixed$(freqs[0], 3)
for d from 1 to scale.nDeg
    .ratioDisp$ = scale.ratios$[d]
    if length(.ratioDisp$) > 18
        .ratioDisp$ = left$(.ratioDisp$, 18)
    endif
    # Pad to align
    .rpad$ = .ratioDisp$
    while length(.rpad$) < 18
        .rpad$ = .rpad$ + " "
    endwhile
    .dstr$ = string$(d)
    while length(.dstr$) < 6
        .dstr$ = " " + .dstr$
    endwhile
    appendInfoLine: "  ", .dstr$, "  ", .rpad$,
        ... "  ", fixed$(scale.cents[d], 3), "   ",
        ... fixed$(freqs[d], 3)
endfor
appendInfoLine: ""

# ============================================================
# Build the note sequence for the chosen playback mode.
# produces:
#   seqFreqs[1..nSeq] and seqDurs#[1..nSeq] for sequential modes
#   chordFreqs[1..nChord]                    for sustained chord
#
# Then renders into one Sound object.
# ============================================================
sampleRate = 44100

# Defensive defaults for mode-specific variables. Declared BEFORE the
# mode block so the mode branches can overwrite them; never touched
# afterward.
nSubset = 0
nChord = 0

if mode = 1
    # Single tone on the implicit Scala degree 0 = 1/1 fundamental.
    appendInfoLine: "Mode: Single tone (fundamental)"
    nSeq = 1
    seqFreqs[1] = freqs[0]

elsif mode = 2
    # Ascending: 0, 1, 2, ..., N
    appendInfoLine: "Mode: Ascending scale"
    nSeq = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqs[i + 1] = freqs[i]
    endfor

elsif mode = 3
    # Descending: N, N-1, ..., 0
    appendInfoLine: "Mode: Descending scale"
    nSeq = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqs[i + 1] = freqs[scale.nDeg - i]
    endfor

elsif mode = 4
    # Ping-pong: 0..N then N-1..0 (no repeat of apex)
    appendInfoLine: "Mode: Ping-pong"
    nSeq = 2 * scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqs[i + 1] = freqs[i]
    endfor
    for i from 1 to scale.nDeg
        seqFreqs[scale.nDeg + 1 + i] = freqs[scale.nDeg - i]
    endfor

elsif mode = 5
    # Arpeggio: broken chord of subset
    appendInfoLine: "Mode: Arpeggio (broken subset)"
    @parseSubset: subset_degrees$
    @voicingRespace: voicing, nSubset
    nSeq = nSubset
    for i from 1 to nSubset
        d = subset[i]
        if d < 0 or d > scale.nDeg
            d = 0
        endif
        if periodOff[i] = 0
            seqFreqs[i] = freqs[d]
        else
            # Shift by period
            seqFreqs[i] = freqs[d] * 2 ^ (periodOff[i] * scale.period / 1200.0)
        endif
    endfor

elsif mode = 6
    # Sustained chord of subset
    appendInfoLine: "Mode: Sustained chord of subset"
    @parseSubset: subset_degrees$
    @voicingRespace: voicing, nSubset
    nChord = nSubset
    for i from 1 to nSubset
        d = subset[i]
        if d < 0 or d > scale.nDeg
            d = 0
        endif
        if periodOff[i] = 0
            chordFreqs[i] = freqs[d]
        else
            chordFreqs[i] = freqs[d] * 2 ^ (periodOff[i] * scale.period / 1200.0)
        endif
    endfor
    nSeq = 0

elsif mode = 7
    # Scale against drone on degree 0
    appendInfoLine: "Mode: Scale against drone"
    nSeq = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqs[i + 1] = freqs[i]
    endfor
    # Handled specially below.

elsif mode = 8
    # A/B compare: play this scale ascending, pause, then second scale
    # ascending. Save the current scale's freqs/state first.
    appendInfoLine: "Mode: A/B compare (first scale then second)"
    nSeq = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqs[i + 1] = freqs[i]
    endfor
    # We'll render A, then re-setup for B, then render B and concatenate.
endif

# Track the highest note fundamental actually requested; visualization uses
# this to choose a spectrogram ceiling that reflects the rendered spectrum.
maxNoteFreq = 0
if mode = 6
    for i from 1 to nChord
        if chordFreqs[i] > maxNoteFreq
            maxNoteFreq = chordFreqs[i]
        endif
    endfor
else
    for i from 1 to nSeq
        if seqFreqs[i] > maxNoteFreq
            maxNoteFreq = seqFreqs[i]
        endif
    endfor
endif

# ============================================================
# Render audio
# ============================================================
noteAtkMs = attack_ms
noteRelMs = release_ms
noteDur = note_duration_s
noteGap = gap_s

# For chord modes, use a longer duration.
chordDur = noteDur * (nSubset + 1)
if chordDur > 4.0
    chordDur = 4.0
endif

appendInfoLine: ""
appendInfoLine: "Rendering..."

if mode = 6
    # Sustained chord
    @synthChord: nChord, chordDur,
        ... noteAtkMs * 2, noteRelMs * 3, sampleRate, "chord"
    resultId = synthChord.id

elsif mode = 7
    # Scale against drone. Render drone sound of length (nSeq*(noteDur+noteGap)),
    # render scale sequence into same-length buffer, sum.
    totalDur = nSeq * (noteDur + noteGap)
    # Drone: fundamental, as a single long note.
    @synthNote: freqs[0], totalDur, noteAtkMs * 2, noteRelMs * 2,
        ... sampleRate, "drone"
    droneId = synthNote.id

    # Sequence buffer
    seqBufId = Create Sound from formula: "seq_buf", 1, 0, totalDur,
        ... sampleRate, "0"

    for i from 1 to nSeq
        @synthNote: seqFreqs[i], noteDur, noteAtkMs, noteRelMs,
            ... sampleRate, "n" + string$(i)
        .nid = synthNote.id
        .nstr$ = fixed$(.nid, 0)
        .off = (i - 1) * (noteDur + noteGap) * sampleRate
        .offS = (i - 1) * (noteDur + noteGap)
        .endS = .offS + noteDur
        if .endS > totalDur
            .endS = totalDur
        endif
        selectObject: seqBufId
        Formula (part): .offS, .endS, 1, 1,
            ... "self + object[" + .nstr$ + ", col - " + fixed$(.off, 0) + "]"
        removeObject: .nid
    endfor

    # Sum drone + sequence into drone buffer (it's already full length).
    .seqStr$ = fixed$(seqBufId, 0)
    selectObject: droneId
    Formula: "self * 0.5 + object[" + .seqStr$ + ", col] * 0.7"
    removeObject: seqBufId
    resultId = droneId

elsif mode = 8
    # A/B compare. Render A, create the comparison pause, then load/render B.
    .seqDur_A = nSeq * (noteDur + noteGap)
    seqBufA = Create Sound from formula: "seq_A", 1, 0, .seqDur_A,
        ... sampleRate, "0"
    for i from 1 to nSeq
        @synthNote: seqFreqs[i], noteDur, noteAtkMs, noteRelMs,
            ... sampleRate, "A" + string$(i)
        .nid = synthNote.id
        .nstr$ = fixed$(.nid, 0)
        .offS = (i - 1) * (noteDur + noteGap)
        .endS = .offS + noteDur
        if .endS > .seqDur_A
            .endS = .seqDur_A
        endif
        .off = (i - 1) * (noteDur + noteGap) * sampleRate
        selectObject: seqBufA
        Formula (part): .offS, .endS, 1, 1,
            ... "self + object[" + .nstr$ + ", col - " + fixed$(.off, 0) + "]"
        removeObject: .nid
    endfor

    # Save A's complete scale/tuning state before B overwrites globals.
    saved.nDeg = scale.nDeg
    saved.period = scale.period
    saved.isOctave = scale.isOctave
    saved.truncated = scale.truncated
    saved.name$ = scale.name$
    for d from 1 to scale.nDeg
        saved.cents[d] = scale.cents[d]
        saved.ratios$[d] = scale.ratios$[d]
    endfor
    for d from 0 to scale.nDeg
        saved.freqs[d] = freqs[d]
    endfor

    # Create the gap BEFORE B so Sounds: Concatenate sees object-list order
    # A -> gap -> B (Praat concatenates by object-list order).
    abGapDur = noteGap * 4
    if abGapDur < 0.35
        abGapDur = 0.35
    endif
    abGapId = Create Sound from formula: "AB_pause", 1, 0, abGapDur,
        ... sampleRate, "0"

    # Resolve and load scale B. Search A's archive folder first, then the
    # standard AudioTools locations, so A/B also works when A is synthetic.
    @resolveBuiltinAB: second_builtin_for_AB
    if resolveBuiltinAB.useSynthetic = 1
        @buildSynthetic12TET
    else
        @findArchiveScale: resolveBuiltinAB.filename$, archiveDir$
        if findArchiveScale.found = 1
            @parseScalaFile: findArchiveScale.fullpath$
        else
            appendInfoLine: "A/B: second scale file not found (", resolveBuiltinAB.filename$, "); using 12-TET."
            @buildSynthetic12TET
        endif
    endif
    @buildTuning: fundamental_Hz, use_reference_anchor, reference_degree, reference_Hz,
        ... transpose_periods

    compare.nDeg = scale.nDeg
    compare.period = scale.period
    compare.isOctave = scale.isOctave
    compare.name$ = scale.name$
    for d from 1 to scale.nDeg
        compare.cents[d] = scale.cents[d]
    endfor
    for d from 0 to scale.nDeg
        compare.freqs[d] = freqs[d]
    endfor

    nSeqB = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqsB[i + 1] = freqs[i]
        if freqs[i] > maxNoteFreq
            maxNoteFreq = freqs[i]
        endif
    endfor

    .seqDur_B = nSeqB * (noteDur + noteGap)
    seqBufB = Create Sound from formula: "seq_B", 1, 0, .seqDur_B,
        ... sampleRate, "0"
    for i from 1 to nSeqB
        @synthNote: seqFreqsB[i], noteDur, noteAtkMs, noteRelMs,
            ... sampleRate, "B" + string$(i)
        .nid = synthNote.id
        .nstr$ = fixed$(.nid, 0)
        .offS = (i - 1) * (noteDur + noteGap)
        .endS = .offS + noteDur
        if .endS > .seqDur_B
            .endS = .seqDur_B
        endif
        .off = (i - 1) * (noteDur + noteGap) * sampleRate
        selectObject: seqBufB
        Formula (part): .offS, .endS, 1, 1,
            ... "self + object[" + .nstr$ + ", col - " + fixed$(.off, 0) + "]"
        removeObject: .nid
    endfor

    selectObject: seqBufA
    plusObject: abGapId
    plusObject: seqBufB
    resultId = Concatenate
    removeObject: seqBufA, abGapId, seqBufB

    # Restore A so the post-render table/visualization is not silently relabelled
    # as B. Keep compare.* for the A/B overlay and summary.
    scale.nDeg = saved.nDeg
    scale.period = saved.period
    scale.isOctave = saved.isOctave
    scale.truncated = saved.truncated
    scale.name$ = saved.name$
    for d from 1 to scale.nDeg
        scale.cents[d] = saved.cents[d]
        scale.ratios$[d] = saved.ratios$[d]
    endfor
    for d from 0 to scale.nDeg
        freqs[d] = saved.freqs[d]
    endfor
    sceneName$ = saved.name$ + "  vs  " + compare.name$

else
    # Sequential modes (1-5): render notes into a buffer with gaps.
    totalDur = nSeq * (noteDur + noteGap)
    if totalDur < 0.1
        totalDur = 0.1
    endif
    seqBufId = Create Sound from formula: "seq_buf", 1, 0, totalDur,
        ... sampleRate, "0"
    for i from 1 to nSeq
        @synthNote: seqFreqs[i], noteDur, noteAtkMs, noteRelMs,
            ... sampleRate, "n" + string$(i)
        .nid = synthNote.id
        .nstr$ = fixed$(.nid, 0)
        .offS = (i - 1) * (noteDur + noteGap)
        .endS = .offS + noteDur
        if .endS > totalDur
            .endS = totalDur
        endif
        .off = (i - 1) * (noteDur + noteGap) * sampleRate
        selectObject: seqBufId
        Formula (part): .offS, .endS, 1, 1,
            ... "self + object[" + .nstr$ + ", col - " + fixed$(.off, 0) + "]"
        removeObject: .nid
    endfor
    resultId = seqBufId
endif

if maxNoteFreq >= sampleRate * 0.48
    appendInfoLine: "WARN: at least one requested note fundamental reached the Nyquist guard;"
    appendInfoLine: "      such notes cannot be represented at this sample rate and may be silent."
endif

# ============================================================
# Output finalisation
# ============================================================
selectObject: resultId
# Apply user output gain.
Formula: "self * " + fixed$(output_gain, 4)

# Peak-protect (no normalization; just clip guard)
.peak = Get maximum: 0, 0, "None"
.npeak = Get minimum: 0, 0, "None"
.absPeak = abs(.peak)
if abs(.npeak) > .absPeak
    .absPeak = abs(.npeak)
endif
if .absPeak > 0.98
    .safeGain = 0.95 / .absPeak
    Formula: "self * " + fixed$(.safeGain, 6)
    .absPeak = .absPeak * .safeGain
    appendInfoLine: "Peak-limited (scaled by ",
        ... fixed$(.safeGain, 3), ")"
endif

# Rename the result
.nameForOutput$ = scale.name$
if mode = 8
    .nameForOutput$ = sceneName$
endif
.safeName$ = replace_regex$(.nameForOutput$, "[^A-Za-z0-9_]+", "_", 0)
if length(.safeName$) > 40
    .safeName$ = left$(.safeName$, 40)
endif
Rename: "scale_" + .safeName$

# ============================================================
# Visualization
# ============================================================
if show_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Title
    Select outer viewport: 0, 8, 0, 0.50
    Axes: 0, 1, 0, 1
    Font size: 13
    Colour: "Black"
    Text: 0.5, "centre", -1.00, "half", "##Scala Scale Auralizer##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    .titleLine$ = scale.name$
    if mode = 8
        .titleLine$ = sceneName$
    endif
    if length(.titleLine$) > 80
        .titleLine$ = left$(.titleLine$, 77) + "..."
    endif
    Text: 0.5, "centre", 0.22, "half",
        ... .titleLine$
        ... + "   |   " + string$(scale.nDeg) + " degrees"
        ... + "   |   period " + fixed$(scale.period, 1) + " cents"
        ... + "   |   1/1 " + fixed$(freqs[0], 1) + " Hz"

    # Cents distribution. In A/B mode, show both scales on the same cent axis.
    Select outer viewport: 0, 8, 0.55, 2.00
    Select inner viewport: 0.6, 7.7, 0.65, 1.95
    .maxC = scale.period + 50
    if mode = 8 and compare.period + 50 > .maxC
        .maxC = compare.period + 50
    endif
    if .maxC < 1300
        .maxC = 1300
    endif
    Axes: -20, .maxC, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", -20, .maxC, 0, 1

    # Neutral octave reference where useful.
    if scale.isOctave = 0 or (mode = 8 and compare.isOctave = 0)
        Colour: "{0.70, 0.70, 0.70}"
        Dotted line
        Draw line: 1200, 0.05, 1200, 0.95
        Solid line
    endif

    if mode = 8
        # A (blue), lower lane.
        Colour: "{0.20, 0.40, 0.75}"
        Line width: 1.6
        Draw line: 0, 0.10, 0, 0.43
        for d from 1 to scale.nDeg
            Draw line: scale.cents[d], 0.10, scale.cents[d], 0.43
        endfor
        # B (orange), upper lane.
        Colour: "{0.82, 0.50, 0.15}"
        Draw line: 0, 0.57, 0, 0.90
        for d from 1 to compare.nDeg
            Draw line: compare.cents[d], 0.57, compare.cents[d], 0.90
        endfor
    else
        Colour: "{0.20, 0.40, 0.75}"
        Line width: 1.8
        Draw line: 0, 0.15, 0, 0.85
        for d from 1 to scale.nDeg
            Draw line: scale.cents[d], 0.15, scale.cents[d], 0.85
        endfor
        Colour: "{0.82, 0.50, 0.15}"
        Line width: 1.0
        Draw line: scale.period, 0.05, scale.period, 0.95
    endif

    Line width: 1
    Colour: "Black"
    Draw inner box

    # Re-enter the inner viewport after box/text-affecting Picture commands,
    # then add annotations only after all data geometry has been drawn.
    Select inner viewport: 0.6, 7.7, 0.65, 1.95
    Axes: -20, .maxC, 0, 1
    Font size: 5
    Colour: "{0.55, 0.55, 0.55}"
    if scale.isOctave = 0 or (mode = 8 and compare.isOctave = 0)
        Text: 1200, "centre", 0.96, "bottom", "1200c"
    endif

    if mode = 8
        Font size: 6
        Colour: "{0.20, 0.40, 0.75}"
        Text: 10, "left", 0.26, "half", "A"
        Colour: "{0.82, 0.50, 0.15}"
        Text: 10, "left", 0.74, "half", "B"
        Colour: "Black"
        Text top: "no", "Intervals on shared cent axis: A blue / B orange"
    else
        Colour: "{0.82, 0.50, 0.15}"
        Font size: 6
        Text: scale.period, "centre", 0.98, "bottom",
            ... "period " + fixed$(scale.period, 0) + "c"
        Colour: "{0.20, 0.40, 0.75}"
        Text: 0, "centre", 0.10, "top", "0"
        if scale.nDeg <= 20
            for d from 1 to scale.nDeg
                Text: scale.cents[d], "centre", 0.10, "top", string$(d)
            endfor
        else
            for d from 1 to scale.nDeg
                if d mod 4 = 0
                    Text: scale.cents[d], "centre", 0.10, "top", string$(d)
                endif
            endfor
        endif
        Colour: "Black"
        Text top: "no", "Degrees on cent axis (blue) — orange line = period"
    endif

    # Degree-frequency panel for scale A (the primary scale).
    Select outer viewport: 0, 8, 2.10, 3.60
    Select inner viewport: 0.6, 7.7, 2.20, 3.55

    .fMin = freqs[0]
    .fMax = freqs[0]
    for d from 0 to scale.nDeg
        if freqs[d] < .fMin
            .fMin = freqs[d]
        endif
        if freqs[d] > .fMax
            .fMax = freqs[d]
        endif
    endfor
    if .fMax <= .fMin
        .fMax = .fMin + 1
    endif
    Axes: 0, 1, .fMin * 0.95, .fMax * 1.05
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, 1, .fMin * 0.95, .fMax * 1.05

    Colour: "{0.20, 0.40, 0.75}"
    Line width: 2
    for d from 0 to scale.nDeg
        .xl = 0.05 + 0.90 * (d / (scale.nDeg + 0.01))
        Draw line: .xl, .fMin * 0.95, .xl, freqs[d]
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box

    Select inner viewport: 0.6, 7.7, 2.20, 3.55
    Axes: 0, 1, .fMin * 0.95, .fMax * 1.05
    for d from 0 to scale.nDeg
        if scale.nDeg <= 20 or d mod 3 = 0
            .xl = 0.05 + 0.90 * (d / (scale.nDeg + 0.01))
            Font size: 5
            Colour: "{0.30, 0.30, 0.30}"
            Text special: .xl, "centre", .fMin * 0.93, "top",
                ... "Helvetica", 5, "0", fixed$(freqs[d], 1)
        endif
    endfor
    Colour: "Black"
    Font size: 7
    Text left: "yes", "Hz"
    if mode = 8
        Text top: "no", "A: degree frequencies (Hz)"
    else
        Text top: "no", "Degree frequencies (Hz)"
    endif

    # Output waveform
    Select outer viewport: 0, 8, 3.70, 5.00
    Select inner viewport: 0.6, 7.7, 3.80, 4.95
    selectObject: resultId
    .plotPeak = .absPeak * 1.05
    if .plotPeak < 0.05
        .plotPeak = 0.05
    endif
    Colour: "{0.20, 0.45, 0.75}"
    .plotDur = Get total duration
    Draw: 0, 0, 0 - .plotPeak, .plotPeak, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 3.80, 4.95
    Axes: 0, .plotDur, 0 - .plotPeak, .plotPeak
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Output spectrogram
    Select outer viewport: 0, 8, 5.10, 6.50
    Select inner viewport: 0.6, 7.7, 5.20, 6.45
    selectObject: resultId
    Copy: "specTmp"
    .tmp = selected("Sound")
    .specTop = maxNoteFreq * spec.maxMult * 1.10
    if .specTop < 5000
        .specTop = 5000
    endif
    if .specTop > sampleRate * 0.48
        .specTop = sampleRate * 0.48
    endif
    To Spectrogram: 0.03, .specTop, 0.005, 20, "Gaussian"
    .sp = selected("Spectrogram")
    Paint: 0, 0, 0, .specTop, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Select inner viewport: 0.6, 7.7, 5.20, 6.45
    Axes: 0, 1, 0, .specTop
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Output spectrogram"
    removeObject: .sp, .tmp

    # Summary panel
    Select outer viewport: 0, 8, 6.60, 7.75
    Select inner viewport: 0.6, 7.7, 6.65, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Select inner viewport: 0.6, 7.7, 6.65, 7.72
    Axes: 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"
    .modeName$ = "mode " + string$(mode)
    if mode = 1
        .modeName$ = "single tone"
    elsif mode = 2
        .modeName$ = "ascending"
    elsif mode = 3
        .modeName$ = "descending"
    elsif mode = 4
        .modeName$ = "ping-pong"
    elsif mode = 5
        .modeName$ = "arpeggio"
    elsif mode = 6
        .modeName$ = "sustained chord"
    elsif mode = 7
        .modeName$ = "scale vs drone"
    elsif mode = 8
        .modeName$ = "A/B compare"
    endif
    .spectrumName$ = "spec " + string$(spectrum)
    if spectrum = 1
        .spectrumName$ = "pure sine"
    elsif spectrum = 2
        .spectrumName$ = "harmonic 8 (1/n)"
    elsif spectrum = 3
        .spectrumName$ = "harmonic 16 (1/n)"
    elsif spectrum = 4
        .spectrumName$ = "odd-only 8"
    elsif spectrum = 5
        .spectrumName$ = "bright flat 8"
    elsif spectrum = 6
        .spectrumName$ = "dark 1/n^2"
    endif
    .voicingName$ = "voicing " + string$(voicing)
    if voicing = 1
        .voicingName$ = "closed"
    elsif voicing = 2
        .voicingName$ = "open"
    elsif voicing = 3
        .voicingName$ = "compact"
    elsif voicing = 4
        .voicingName$ = "expanded"
    endif

    Text: 0.02, "left", 0.66, "half",
        ... "Mode: " + .modeName$
        ... + "   |   Spectrum: " + .spectrumName$
        ... + "   |   Voicing: " + .voicingName$
    Text: 0.02, "left", 0.44, "half",
        ... "Note: " + fixed$(noteDur, 2) + "s"
        ... + "   |   Gap: " + fixed$(noteGap, 2) + "s"
        ... + "   |   Atk/Rel: " + fixed$(noteAtkMs, 0)
        ... + "/" + fixed$(noteRelMs, 0) + " ms"
        ... + "   |   Gain: " + fixed$(output_gain, 2)
    .octStr$ = "non-octave"
    if scale.isOctave = 1
        .octStr$ = "octave"
    endif
    .anchorStr$ = "ref anchor off"
    if use_reference_anchor = 1
        .anchorStr$ = "ref deg " + string$(reference_degree) + " @ " + fixed$(reference_Hz, 2) + " Hz"
    endif
    Text: 0.02, "left", 0.22, "half",
        ... "1/1: " + fixed$(freqs[0], 2) + " Hz"
        ... + "   |   input fund " + fixed$(fundamental_Hz, 2) + " Hz"
        ... + "   |   " + .anchorStr$
        ... + "   |   Transpose " + string$(transpose_periods) + " period(s)"
        ... + "   |   " + .octStr$
    if mode = 8
        Text: 0.98, "right", 0.88, "half", "B: " + compare.name$
    endif

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# ============================================================
# Playback
# ============================================================
selectObject: resultId
if play_result
    Play
endif

appendInfoLine: ""
appendInfoLine: "=== DONE ==="
appendInfoLine: "Output: ", selected$("Sound")
