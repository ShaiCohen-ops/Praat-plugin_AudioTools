# ============================================================
# Praat AudioTools - Scala_Scale_Auralizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Scala Scale Archive auralizer. Loads a scale from a .scl file
#   (external path or a small built-in list), maps scale degrees
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
#       tuneBuild: given fundamental, reference-degree offset,
#       transposition, produces freqs[] per degree
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
#       closed vs open, compressed vs expanded
#       operates on scale degrees, produces (degree, shift) pairs
#
#   PLAYBACK  (sequences notes or builds chords)
#       renders the final Sound object
#
# Scale selection
# ---------------
# Praat forms cannot interactively filter a 5401-file archive,
# so selection has two paths:
#
#   (1) Built-in list: 16 curated scales + synthetic 12-TET.
#   (2) External path: user pastes the full path to any .scl file.
#       If given, overrides the built-in list.
#
# The user finds unusual scales in the archive via their OS
# file browser (which is genuinely better for this than any form
# dialog could be) and pastes the path.
#
# Scala file conventions honoured
# -------------------------------
# * Lines starting with "!" are comments and skipped.
# * First non-comment line = description (displayed).
# * Next non-comment line = note count N.
# * Following N non-comment lines = interval values, either
#   cents (anything containing "." or a bare integer) or ratios
#   (anything containing "/").
# * The Nth interval is the period (not always 2/1).
# * Files may be truncated; we detect this and warn.
# * CRLF line endings are stripped.
#
# Usage
# -----
# Run the script. Fill the form. Hear the result. The script
# creates a single Sound object and leaves it selected.
# ============================================================

form Scala Scale Auralizer
    comment Leave 'External_scl_path' empty to use the built-in scale.
    sentence External_scl_path
    optionmenu Builtin_scale: 1
        option 12-TET (synthetic)
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
        option Partch 43 (partch_43) [non-octave? no]
        option Bohlen-Pierce (bohlen-p) [non-octave, 3/1]
        option Carlos Alpha (carlos_alpha) [non-octave]
        option Carlos Beta (carlos_beta) [non-octave]
        option Carlos Gamma (carlos_gamma) [non-octave]

    comment === Tuning ===
    positive Fundamental_Hz 220
    integer Reference_degree 1
    positive Reference_Hz 220
    integer Transpose_periods 0

    comment === Playback ===
    optionmenu Mode: 2
        option Single tone (degree 1)
        option Ascending scale
        option Descending scale
        option Ping-pong
        option Arpeggio (broken chord of degree subset)
        option Sustained chord of degree subset
        option Scale against drone on degree 1
        option A/B compare (this scale vs second built-in)
    sentence Subset_degrees 1 3 5
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
        option Compressed (all within one period)
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
#   scale.truncated 1 if file declared more degrees than it supplied
# ============================================================
procedure parseScalaFile: .path$
    if not fileReadable(.path$)
        exitScript: "Scala file not found: " + .path$
    endif

    # Read whole file as a Strings object so we can iterate lines
    # without buffering dance.
    .strs = Read Strings from raw text file: .path$
    .nLines = Get number of strings

    scale.name$ = "(unnamed)"
    scale.nDeg = 0
    .haveName = 0
    .haveCount = 0
    .degIdx = 0

    for .i from 1 to .nLines
        selectObject: .strs
        .raw$ = Get string: .i
        # Strip trailing CR (Windows line endings from the archive)
        # and normalize whitespace.
        .line$ = replace_regex$(.raw$, "[\r\n]+$", "", 0)
        .trim$ = replace_regex$(.line$, "^[ \t]+|[ \t]+$", "", 0)

        # Skip comments
        if left$(.trim$, 1) = "!"
            # comment, ignore
        elsif .trim$ = ""
            # blank line, ignore
        elsif .haveName = 0
            # First non-comment line is the description
            scale.name$ = .trim$
            .haveName = 1
        elsif .haveCount = 0
            # Next is the note count. May have trailing comment or
            # whitespace; take the first integer-looking token.
            .tok$ = replace_regex$(.trim$, "^[ \t]*(\S+).*$", "\1", 0)
            scale.nDeg = number(.tok$)
            if scale.nDeg = undefined or scale.nDeg < 1
                removeObject: .strs
                exitScript: "Scala file has invalid note count: " + .trim$
            endif
            .haveCount = 1
        else
            # A scale-degree line. Take the first whitespace-
            # separated token (ignore any trailing comment text).
            .tok$ = replace_regex$(.trim$, "^[ \t]*(\S+).*$", "\1", 0)

            .degIdx = .degIdx + 1
            if .degIdx <= scale.nDeg
                @parseScalaValue: .tok$
                if parseScalaValue.ok = 1
                    scale.cents[.degIdx] = parseScalaValue.cents
                    scale.ratios$[.degIdx] = .tok$
                else
                    appendInfoLine: "WARN: unparseable degree '",
                        ... .tok$, "' at position ", .degIdx,
                        ... "; substituting 0 cents"
                    scale.cents[.degIdx] = 0
                    scale.ratios$[.degIdx] = "?"
                endif
            endif
        endif
    endfor

    removeObject: .strs

    # Detect truncation: declared N but got fewer degree lines.
    scale.truncated = 0
    if .degIdx < scale.nDeg
        scale.truncated = 1
        appendInfoLine: "WARN: .scl file declared ", scale.nDeg,
            ... " degrees but only ", .degIdx, " were supplied."
        appendInfoLine: "      Truncating to ", .degIdx, " degrees."
        scale.nDeg = .degIdx
    endif

    if scale.nDeg < 1
        exitScript: "Scala file produced zero usable degrees."
    endif

    scale.period = scale.cents[scale.nDeg]
    scale.isOctave = 0
    if abs(scale.period - 1200.0) < 1.0
        scale.isOctave = 1
    endif
endproc

# ------------------------------------------------------------
# Parse a single scale-degree token into cents.
# Accepts: "386.314" (cents), "5/4" (ratio), "1200" (cents),
#          "2/1" (ratio).
# Praat convention: if the token contains ".", it's cents; if "/",
# it's a ratio; if a bare integer, it's cents (per Scala spec).
# Returns parseScalaValue.ok (1/0) and parseScalaValue.cents.
# ------------------------------------------------------------
procedure parseScalaValue: .tok$
    .ok = 0
    .cents = 0
    if index(.tok$, "/") > 0
        # Ratio N/M
        .slashPos = index(.tok$, "/")
        .num$ = left$(.tok$, .slashPos - 1)
        .den$ = mid$(.tok$, .slashPos + 1, length(.tok$))
        .numV = number(.num$)
        .denV = number(.den$)
        if .numV <> undefined and .denV <> undefined
            if .numV > 0 and .denV > 0
                .cents = 1200 * ln(.numV / .denV) / ln(2)
                .ok = 1
            endif
        endif
    else
        # Cents (float or integer)
        .v = number(.tok$)
        if .v <> undefined
            .cents = .v
            .ok = 1
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
#   - Degree 1 is conventionally the tonic (1/1 above fundamental).
#   - If reference_degree = 1 and reference_Hz = fundamental_Hz,
#     the tuning is "anchored at the tonic".
#   - If user picks another reference degree, we shift so that
#     THAT degree plays at reference_Hz. Lets you calibrate the
#     fifth to a fixed pitch, for example.
#   - Transpose_periods shifts the whole scale by N periods.
# ============================================================
procedure buildTuning: .fund, .refDeg, .refHz, .transposePeriods
    # Build freqs[0..nDeg] — index 0 is the fundamental (1/1).
    # Apply period transposition uniformly.
    .periodShift = .transposePeriods * scale.period

    freqs[0] = .fund * 2 ^ (.periodShift / 1200.0)
    for .d from 1 to scale.nDeg
        freqs[.d] = .fund * 2 ^ ((scale.cents[.d] + .periodShift) / 1200.0)
    endfor

    # Reference-degree anchoring is a separate, OPTIONAL correction.
    # We apply it only when the user has clearly requested it (i.e.,
    # chose a reference degree other than 0, or set reference_Hz to
    # something different from the fundamental). Otherwise applying
    # it with the default values (ref_deg=0, ref_Hz=fund) would
    # always cancel out any transposition the user chose, which is
    # not what 'transpose' means.
    .anchorRequested = 0
    if .refDeg <> 0
        .anchorRequested = 1
    endif
    if abs(.refHz - .fund) > 0.01
        .anchorRequested = 1
    endif

    if .anchorRequested = 1 and .refDeg >= 0 and .refDeg <= scale.nDeg
        .currentRefHz = freqs[.refDeg]
        if .currentRefHz > 0 and .refHz > 0
            .shift = .refHz / .currentRefHz
            for .d from 0 to scale.nDeg
                freqs[.d] = freqs[.d] * .shift
            endfor
        endif
    endif
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

    # Build the summed-partials formula string with literal values.
    # sum_k amp_k * sin(2*pi * mult_k * fHz * x)
    .formula$ = "0"
    for .k from 1 to spec.nPartials
        .partialFreq = spec.mult[.k] * .fHz
        .formula$ = .formula$ + " + " + fixed$(spec.amp[.k], 6)
            ... + " * sin(2*pi*" + fixed$(.partialFreq, 6) + "*x)"
    endfor

    synthNote.id = Create Sound from formula: .label$, 1, 0, .duration,
        ... .sampleRate, .formula$

    # Apply attack + release envelope (linear ramps, fast)
    .atkSec = .attack / 1000.0
    .relSec = .release / 1000.0
    if .atkSec > .duration * 0.5
        .atkSec = .duration * 0.5
    endif
    if .relSec > .duration * 0.5
        .relSec = .duration * 0.5
    endif
    .relStart = .duration - .relSec

    .atk$ = fixed$(.atkSec, 6)
    .rel$ = fixed$(.relSec, 6)
    .rs$ = fixed$(.relStart, 6)
    .dur$ = fixed$(.duration, 6)

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
        # Open: alternate-degree up one period
        for .i from 1 to .nList
            if (.i mod 2) = 0
                periodOff[.i] = 1
            endif
        endfor
    elsif .style = 3
        # Compressed: all within one period — no shift needed; our
        # subset degrees are already in [0..nDeg] by construction.
    elsif .style = 4
        # Expanded: spread across two periods.
        # First half stays, second half shifts up one period.
        .half = .nList / 2
        for .i from 1 to .nList
            if .i > .half
                periodOff[.i] = 1
            endif
        endfor
    endif
endproc

# ============================================================
# PARSE: Turn "1 3 5" into integer list subset[], length nSubset.
# Skips tokens that are out of range for the current scale.
# ============================================================
procedure parseSubset: .str$
    nSubset = 0
    .s$ = replace_regex$(.str$, "[,;]+", " ", 0)
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
                if .vi >= 0 and .vi <= scale.nDeg
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
# RESOLVE: Look up a built-in filename from its menu index.
# Index 1 = synthetic 12-TET (no file), else the archive filename.
# ============================================================
procedure resolveBuiltin: .idx, .archiveDir$
    resolveBuiltin.filename$ = ""
    resolveBuiltin.useSynthetic = 0
    if .idx = 1
        resolveBuiltin.useSynthetic = 1
    elsif .idx = 2
        resolveBuiltin.filename$ = "pyth_12.scl"
    elsif .idx = 3
        resolveBuiltin.filename$ = "young-lm_guitar.scl"
    elsif .idx = 4
        resolveBuiltin.filename$ = "werck3.scl"
    elsif .idx = 5
        resolveBuiltin.filename$ = "kirnberger3.scl"
    elsif .idx = 6
        resolveBuiltin.filename$ = "meanquar.scl"
    elsif .idx = 7
        resolveBuiltin.filename$ = "ji_12.scl"
    elsif .idx = 8
        resolveBuiltin.filename$ = "ji_7.scl"
    elsif .idx = 9
        resolveBuiltin.filename$ = "indian_12.scl"
    elsif .idx = 10
        resolveBuiltin.filename$ = "slendro.scl"
    elsif .idx = 11
        resolveBuiltin.filename$ = "alves_slendro.scl"
    elsif .idx = 12
        resolveBuiltin.filename$ = "alves_pelog.scl"
    elsif .idx = 13
        resolveBuiltin.filename$ = "harrison_5.scl"
    elsif .idx = 14
        resolveBuiltin.filename$ = "harmonical.scl"
    elsif .idx = 15
        resolveBuiltin.filename$ = "partch_43.scl"
    elsif .idx = 16
        resolveBuiltin.filename$ = "bohlen-p.scl"
    elsif .idx = 17
        resolveBuiltin.filename$ = "carlos_alpha.scl"
    elsif .idx = 18
        resolveBuiltin.filename$ = "carlos_beta.scl"
    elsif .idx = 19
        resolveBuiltin.filename$ = "carlos_gamma.scl"
    endif

    if resolveBuiltin.useSynthetic = 0 and .archiveDir$ <> ""
        resolveBuiltin.fullpath$ = .archiveDir$ + "/" + resolveBuiltin.filename$
    else
        resolveBuiltin.fullpath$ = ""
    endif
endproc

# ============================================================
# RESOLVE AB: 5-option subset for the A/B second scale.
# ============================================================
procedure resolveBuiltinAB: .idx, .archiveDir$
    resolveBuiltinAB.useSynthetic = 0
    resolveBuiltinAB.fullpath$ = ""
    if .idx = 1
        resolveBuiltinAB.useSynthetic = 1
    elsif .idx = 2
        resolveBuiltinAB.fullpath$ = .archiveDir$ + "/pyth_12.scl"
    elsif .idx = 3
        resolveBuiltinAB.fullpath$ = .archiveDir$ + "/partch_43.scl"
    elsif .idx = 4
        resolveBuiltinAB.fullpath$ = .archiveDir$ + "/bohlen-p.scl"
    elsif .idx = 5
        resolveBuiltinAB.fullpath$ = .archiveDir$ + "/carlos_alpha.scl"
    endif
endproc

# ============================================================
# MAIN
# ============================================================
writeInfoLine: "=== Scala Scale Auralizer v1.0 ==="

# Determine which source to use.
# Priority: external_scl_path > built-in archive file > synthetic 12-TET
loadedFromPath$ = ""
archiveDir$ = ""

if external_scl_path$ <> ""
    # External file was provided.
    loadedFromPath$ = external_scl_path$
    # Extract directory so A/B can find a peer file if needed.
    .lastSlash = rindex(external_scl_path$, "/")
    if .lastSlash > 0
        archiveDir$ = left$(external_scl_path$, .lastSlash - 1)
    endif
    @parseScalaFile: loadedFromPath$
    appendInfoLine: "Loaded from external path:"
    appendInfoLine: "  ", loadedFromPath$
else
    # Try archive-relative path for built-ins that need a .scl file.
    # Heuristic: try a few common archive locations.
    @resolveBuiltin: builtin_scale, ""
    if resolveBuiltin.useSynthetic = 1
        @buildSynthetic12TET
        appendInfoLine: "Using synthetic 12-TET (no file needed)."
    else
        # Built-in requires a .scl file. The user must tell us the
        # archive location via external_scl_path or we can try a few
        # fallbacks. Prefer an educated guess.
        candidateDirs$ = preferencesDirectory$ + "/plugin_AudioTools/scl"
            ... + ":" + defaultDirectory$ + "/scl"
            ... + ":" + defaultDirectory$

        # Try each candidate. Customise the first entry below to
        # point at your own Scala archive location — this is the
        # fast path so your personal archive is checked first.
        found = 0

        # --- User-configurable archive path (edit this line) ---
        testDir$ = "C:/Users/User/Downloads/scales/scl"
        testFile$ = testDir$ + "/" + resolveBuiltin.filename$
        if fileReadable(testFile$)
            archiveDir$ = testDir$
            found = 1
        endif

        # Standard AudioTools plugin location
        if found = 0
            testDir$ = preferencesDirectory$ + "/plugin_AudioTools/scl"
            testFile$ = testDir$ + "/" + resolveBuiltin.filename$
            if fileReadable(testFile$)
                archiveDir$ = testDir$
                found = 1
            endif
        endif
        if found = 0
            testDir$ = defaultDirectory$ + "/scl"
            testFile$ = testDir$ + "/" + resolveBuiltin.filename$
            if fileReadable(testFile$)
                archiveDir$ = testDir$
                found = 1
            endif
        endif
        if found = 0
            testDir$ = defaultDirectory$
            testFile$ = testDir$ + "/" + resolveBuiltin.filename$
            if fileReadable(testFile$)
                archiveDir$ = testDir$
                found = 1
            endif
        endif

        if found = 0
            appendInfoLine: "Could not locate built-in scale file:"
            appendInfoLine: "  ", resolveBuiltin.filename$
            appendInfoLine: "Searched:"
            appendInfoLine: "  C:/Users/User/Downloads/scales/scl"
            appendInfoLine: "  ", preferencesDirectory$, "/plugin_AudioTools/scl"
            appendInfoLine: "  ", defaultDirectory$, "/scl"
            appendInfoLine: "  ", defaultDirectory$
            appendInfoLine: ""
            appendInfoLine: "Falling back to synthetic 12-TET."
            @buildSynthetic12TET
        else
            loadedFromPath$ = archiveDir$ + "/" + resolveBuiltin.filename$
            @parseScalaFile: loadedFromPath$
            appendInfoLine: "Loaded built-in: ", resolveBuiltin.filename$
        endif
    endif
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
if scale.truncated = 1
    appendInfoLine: "Note: file was truncated; scale uses only parsed degrees."
endif
appendInfoLine: ""

# ============================================================
# Build tuning
# ============================================================
@buildTuning: fundamental_Hz, reference_degree, reference_Hz, transpose_periods

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
    # Single tone on degree 1 (we present index 1 of the user-facing
    # 1..N degrees, i.e. the first interval above fundamental; the
    # fundamental itself would be degree 0).
    # Use degree 0 (fundamental) for this mode.
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
    # A/B compare
    # First render A (the sequence we already built).
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

    # Save A's scale state before clobbering for B.
    saved.nDeg = scale.nDeg
    saved.period = scale.period
    saved.isOctave = scale.isOctave
    saved.name$ = scale.name$

    # Load scale B.
    @resolveBuiltinAB: second_builtin_for_AB, archiveDir$
    if resolveBuiltinAB.useSynthetic = 1
        @buildSynthetic12TET
    else
        if fileReadable(resolveBuiltinAB.fullpath$)
            @parseScalaFile: resolveBuiltinAB.fullpath$
        else
            appendInfoLine: "A/B: second scale file not found, using 12-TET."
            @buildSynthetic12TET
        endif
    endif
    @buildTuning: fundamental_Hz, reference_degree, reference_Hz,
        ... transpose_periods

    nSeqB = scale.nDeg + 1
    for i from 0 to scale.nDeg
        seqFreqsB[i + 1] = freqs[i]
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

    # Concatenate A, silence gap, B into single result.
    selectObject: seqBufA
    plusObject: seqBufB
    resultId = Concatenate
    removeObject: seqBufA, seqBufB

    # Restore A's name for the summary (B's metadata will show below).
    sceneName$ = saved.name$ + "  vs  " + scale.name$

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
    appendInfoLine: "Peak-limited (scaled by ",
        ... fixed$(.safeGain, 3), ")"
endif

# Rename the result
.safeName$ = replace_regex$(scale.name$, "[^A-Za-z0-9_]+", "_", 0)
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
    if length(.titleLine$) > 80
        .titleLine$ = left$(.titleLine$, 77) + "..."
    endif
    Text: 0.5, "centre", 0.22, "half",
        ... .titleLine$
        ... + "   |   " + string$(scale.nDeg) + " degrees"
        ... + "   |   period " + fixed$(scale.period, 1) + " cents"
        ... + "   |   fund " + fixed$(fundamental_Hz, 1) + " Hz"

    # Cents distribution: horizontal line with tick per degree
    Select outer viewport: 0, 8, 0.55, 2.00
    Select inner viewport: 0.6, 7.7, 0.65, 1.95
    .maxC = scale.period + 50
    if .maxC < 1300
        .maxC = 1300
    endif
    Axes: -20, .maxC, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.99}", -20, .maxC, 0, 1

    # Period marker
    Colour: "{0.82, 0.50, 0.15}"
    Line width: 1.0
    Draw line: scale.period, 0.05, scale.period, 0.95
    Font size: 6
    Text: scale.period, "centre", 0.98, "bottom",
        ... "period " + fixed$(scale.period, 0) + "c"

    # 1200-cent octave reference (grey dotted)
    if scale.isOctave = 0
        Colour: "{0.70, 0.70, 0.70}"
        Dotted line
        Draw line: 1200, 0.05, 1200, 0.90
        Solid line
        Font size: 5
        Text: 1200, "centre", 0.90, "bottom", "1200c"
    endif

    # Draw degrees as vertical ticks with labels
    Colour: "{0.20, 0.40, 0.75}"
    Line width: 1.8
    # Degree 0 (fundamental)
    Draw line: 0, 0.15, 0, 0.85
    Font size: 6
    Text: 0, "centre", 0.10, "top", "0"
    for d from 1 to scale.nDeg
        .cx = scale.cents[d]
        Draw line: .cx, 0.15, .cx, 0.85
        if scale.nDeg <= 20
            Text: .cx, "centre", 0.10, "top", string$(d)
        elsif d mod 4 = 0
            Text: .cx, "centre", 0.10, "top", string$(d)
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Degrees on cent axis (blue) — orange line = period"

    # Frequencies bar — each degree as a horizontal mark at its Hz
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

    .ny = scale.nDeg + 1
    for d from 0 to scale.nDeg
        .xl = 0.05 + 0.90 * (d / (scale.nDeg + 0.01))
        Colour: "{0.20, 0.40, 0.75}"
        Line width: 2
        Draw line: .xl, .fMin * 0.95, .xl, freqs[d]
        if scale.nDeg <= 20 or d mod 3 = 0
            Font size: 5
            Colour: "{0.30, 0.30, 0.30}"
            Text special: .xl, "centre", .fMin * 0.93, "top",
                ... "Helvetica", 5, "0", fixed$(freqs[d], 1)
        endif
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Degree frequencies (Hz)"

    # Output waveform
    Select outer viewport: 0, 8, 3.70, 5.00
    Select inner viewport: 0.6, 7.7, 3.80, 4.95
    selectObject: resultId
    Colour: "{0.20, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Output spectrogram
    Select outer viewport: 0, 8, 5.10, 6.50
    Select inner viewport: 0.6, 7.7, 5.20, 6.45
    selectObject: resultId
    Copy: "specTmp"
    .tmp = selected("Sound")
    To Spectrogram: 0.03, 5000, 0.005, 20, "Gaussian"
    .sp = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text special: 4.15, "centre", 5300, "bottom", "Helvetica", 7, "0", "Output spectrogram"
    removeObject: .sp, .tmp

    # Summary panel
    Select outer viewport: 0, 8, 6.60, 7.75
    Select inner viewport: 0.6, 7.7, 6.65, 7.72
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

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
        .voicingName$ = "compressed"
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
    Text: 0.02, "left", 0.22, "half",
        ... "Fundamental: " + fixed$(fundamental_Hz, 2) + " Hz"
        ... + "   |   Ref deg " + string$(reference_degree)
        ... + " @ " + fixed$(reference_Hz, 2) + " Hz"
        ... + "   |   Transpose " + string$(transpose_periods) + " period(s)"
        ... + "   |   " + .octStr$
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

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
