# ============================================================
# Praat AudioTools - OT_CORPUS_CONCATENATOR.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.9 (2026) - Suite visualization + Bayesian-style folder entry
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   OT Corpus Concatenator - Optimality Theory-inspired audio
#   selection and concatenation based on weighted constraint violations.
#
# Changelog v0.8:
#   - VISUALIZATION STANDARDIZATION ONLY; corpus analysis, normalized
#     violations, weighted Harmony ranking, selection, joins and output
#     rendering are unchanged from v0.7.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, suite-standard title/subtitle, typography, neutral
#     panel colours, summary strip and full-page export viewport.
#   - Preserved the output waveform, Harmony ranking and Energy/C1
#     scatter; constraint weights are now consolidated in the summary.
#   - Harmony plot now states explicitly that lower scores rank better.
#
# Changelog v0.9:
#   - Added the same visible Audio Folder text field used by
#     Bayesian_Drone_Weaver: type/paste a path, or leave blank to
#     open the folder chooser.
#   - Retains the suite-standard visualization introduced in v0.8.
#   - Corpus analysis, Harmony ranking, concatenation and rendering
#     are unchanged.
#
# Changelog v0.8:
#   - VISUALIZATION STANDARDIZATION ONLY; corpus analysis, normalized
#     violations, weighted Harmony ranking, selection, joins and output
#     rendering are unchanged from v0.7.
#   - Adopted the Praat AudioTools 8-inch page convention with explicit
#     inner viewports, suite-standard title/subtitle, typography, neutral
#     panel colours, summary strip and full-page export viewport.
#   - Preserved the output waveform, Harmony ranking and Energy/C1
#     scatter; constraint weights are consolidated in the summary.
#   - Harmony plot states explicitly that lower scores rank better.
#
# Changelog v0.5:
#   - Standardized the Folder field to the shared blank-to-dialog idiom
#     (as in VoidMosaic): the typed path is whitespace- and trailing-
#     slash-trimmed, a blank field falls back to a chooseFolder$ dialog,
#     and cancelling exits cleanly. Synced the version string across
#     header/form/banner (form title was still v0.3.2).
# Changelog v0.4:
#   - FIXED: analysis loop now converts to mono before To MFCC; stereo
#            corpus files previously crashed there (the concat loop
#            already converted - only the analysis loop was missed).
# Changelog v0.3.2:
#   - FIXED: "Unknown symbol Get" error. Moved 'Get sampling frequency'
#            outside the 'if' statement.
# ============================================================

# ============================================================
# Changelog v0.6 (2026):
#
#   CRITICAL 1 - the script read the wrong MFCC coefficients. Praat
#     keeps C0 in a separate slot: "Get value in frame: f, 1" returns
#     C1, not C0. Verified on 6.4.42, same frame of the same MFCC:
#       Get c0 value in frame: 10   ->  2362.51248
#       Get value in frame: 10, 1   ->   -78.43891
#       Get value in frame: 10, 2   ->    43.03514
#     So the column labelled C0_Energy held C1, C1_Tilt held C2, and
#     Stability was the standard deviation of C2. Every preset was
#     ranking on features other than the ones it names. Now
#     Get c0 value in frame for C0 and Get value in frame: f, 1 for C1.
#
#   CRITICAL 2 - dark and bright were the wrong way round. Measured
#     with two synthetic corpora at the same peak:
#       dark   (120 + 200 Hz)  -> mean C1 = +1105.84
#       bright (6 k + 9 kHz)   -> mean C1 =  -625.22
#     C1's DCT basis is positive over the low Mel filters and negative
#     over the high ones, so POSITIVE C1 means dark and NEGATIVE means
#     bright - the opposite of v0.5's assignment. Combined with
#     CRITICAL 1, Bright & Energetic was penalising the wrong sign of
#     the wrong coefficient. Corrected and re-verified.
#
#   CRITICAL 3 - the weights were not comparable. Harmony summed raw
#     violations on wildly different scales: an energy violation in the
#     hundreds, a tilt violation in the units or tens, and stability
#     multiplied by an arbitrary 10. "Balanced", with every weight at
#     1, was nothing of the kind. v0.6 runs two passes - collect raw
#     features, min-max normalise each violation across the corpus to
#     0-1, then apply the weights - so Weight_energy = 3 really is
#     about three times Weight_stability = 1. The 100 - C0 constant is
#     gone with it: the energy violation is now relative to the corpus,
#     not to a number with no basis in C0's range.
#
#   4 - Analysis now happens AFTER downmix and resampling. v0.5
#     resampled only during assembly, so a 44.1 kHz file and a 96 kHz
#     file went through different spectral front ends and their MFCCs
#     were not comparable.
#     CORRECTION (v0.7): this entry also claimed the normalised copy is
#     reused for assembly. It is not - the analysis copy is removed at
#     the end of each iteration and the selected files are read and
#     converted a second time. Acoustically harmless, since both passes
#     are deterministic and identical, but not the saving described.
#
#   5 - Unusable files are excluded from the ranking rather than
#     scoring well by accident. A file with no frames got zero
#     darkness, zero brightness and zero stability violation, so under
#     Timbral Consistency (stability weight 5, energy weight 0.5) a
#     silent or too-short file could rank near the top precisely
#     because it had nothing measurable. Files are now rejected for
#     near-silence, fewer than 2 frames, or undefined C0/C1, and
#     n_target is clamped to the number of VALID candidates.
#
#   6 - Stability_measure is explicit: Dispersion (the standard
#     deviation of C1, v0.5's behaviour and the right choice for
#     timbral consistency) or Temporal (mean |C1(t) - C1(t-1)|, which
#     distinguishes a slow sweep from fast jitter - they can share a
#     standard deviation).
#
#   7 - Join_mode is a musical choice, not an implementation detail.
#     Hard cut stays the default because abrupt joins are part of
#     corpus montage; short and long crossfades are options with their
#     own Crossfade_ms.
#
#   8 - Normalize_output_peak is a form field, and off means the mix is
#     left alone unless it would clip. v0.5 always ran Scale peak: 0.99,
#     which is full normalisation, not clipping protection.
#
#   9 - Validation: Limit_files >= 1, weights >= 0 with at least one
#     above zero. A negative weight turns a violation into a reward -
#     usable musically, but it stops being a constraint weight, so it
#     is rejected rather than silently accepted.
#
#   ON THE NAME: this is closer to HARMONIC GRAMMAR than to Optimality
#   Theory - a weighted SUM of violations, not lexicographic ranking of
#   strictly ordered constraints. "OT-inspired" is fair; the mechanism
#   is a weighted sum and the header now says so.
#
#   ON ENERGY (documented, unchanged): C0 tracks the file's level, so
#   the same material recorded 12 dB hotter scores differently. That is
#   what Maximum Energy selects for - recorded level - not musical
#   energy. Normalise your corpus first if you want the latter.
#
#   ON FILE DURATION (documented): every file is one candidate, so a
#   ten-minute file and a ten-second file weigh the same in the ranking
#   but not in the output, where the first dominates.
#
# ============================================================

form OT Corpus Concatenator v0.9  (weighted-sum / Harmonic Grammar)
    optionmenu Preset: 1
        option Manual
        option Bright & Energetic
        option Dark & Stable
        option Balanced
        option Maximum Energy
        option Timbral Consistency
    comment === Audio Folder ===
    comment (Leave blank to pick a folder with a dialog)
    sentence Folder 
    comment === Selection ===
    integer Limit_files 10
    real Weight_darkness 0.0
    real Weight_brightness 1.0
    real Weight_energy 2.0
    real Weight_stability 1.0
    optionmenu Stability_measure: 1
        option Dispersion (SD of C1)
        option Temporal (mean frame-to-frame change)
    optionmenu Join_mode: 1
        option Hard cut
        option Short crossfade
        option Long crossfade
    positive Crossfade_ms 30
    boolean Normalize_output_peak 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Type/paste Folder directly, or leave it blank to pick a folder with a dialog.
# Violations are min-max normalised ACROSS THE CORPUS before the
# weights are applied, so the weights are directly comparable.
# C0 tracks recorded level, so Maximum Energy selects for file gain,
# not musical energy - normalise the corpus first if you want that.
# Every file is one candidate regardless of duration.

# ============================================
# PRESET LOGIC
# ============================================

if preset = 2
    # Bright & Energetic
    weight_darkness = 2.0
    weight_brightness = 0.0
    weight_energy = 3.0
    weight_stability = 0.5
    presetName$ = "BrightEnergetic"
elsif preset = 3
    # Dark & Stable
    weight_darkness = 0.0
    weight_brightness = 2.0
    weight_energy = 1.0
    weight_stability = 3.0
    presetName$ = "DarkStable"
elsif preset = 4
    # Balanced
    weight_darkness = 1.0
    weight_brightness = 1.0
    weight_energy = 1.0
    weight_stability = 1.0
    presetName$ = "Balanced"
elsif preset = 5
    # Maximum Energy
    weight_darkness = 0.5
    weight_brightness = 0.5
    weight_energy = 5.0
    weight_stability = 0.0
    presetName$ = "MaxEnergy"
elsif preset = 6
    # Timbral Consistency
    weight_darkness = 0.5
    weight_brightness = 0.5
    weight_energy = 0.5
    weight_stability = 5.0
    presetName$ = "TimbralConsistency"
else
    presetName$ = "Manual"
endif

# ============================================
# DIRECTORY SELECTION
# ============================================

clearinfo
writeInfoLine: "=== OT Corpus Concatenator v0.9 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

n_target = limit_files

# v0.6 fix 4: the common analysis rate has to be known BEFORE the
# analysis loop now, since resampling moved ahead of the MFCC.
target_sample_rate = 44100

# v0.6 fix 9: validation. A negative weight turns a violation into a
# reward - usable musically, but then it is not a constraint weight.
if n_target < 1
    exitScript: "Limit_files must be at least 1."
endif
if weight_darkness < 0 or weight_brightness < 0 or weight_energy < 0 or weight_stability < 0
    exitScript: "Weights must be >= 0. A negative weight rewards the violation it names."
endif
if weight_darkness + weight_brightness + weight_energy + weight_stability <= 0
    exitScript: "At least one weight must be greater than zero, or every file scores 0."
endif

# --- FOLDER DISCOVERY ---
# Mirrors VoidMosaic: use the typed path, or fall back to a dialog when
# the Folder field is left blank. Trim whitespace and trailing slashes
# first; the OS-specific trailing-slash normalization just below re-adds
# the separator for the *.wav glob.
directory$ = replace_regex$(folder$, "^[ \t]*|[ \t]*$", "", 0)
directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)

if directory$ == ""
    directory$ = chooseFolder$: "Select folder with audio clips"
    directory$ = replace_regex$(directory$, "[\\/]+$", "", 0)
endif

if directory$ == ""
    exitScript: "Operation cancelled. Please supply a valid audio folder path."
endif

if right$(directory$, 1) <> "/" and right$(directory$, 1) <> "\"
    if environment$("OS") = "Windows"
        directory$ = directory$ + "\"
    else
        directory$ = directory$ + "/"
    endif
endif

stringsID = Create Strings as file list: "FileList", directory$ + "*.wav"
nFiles = Get number of strings

if nFiles = 0
    selectObject: stringsID
    Remove
    exitScript: "No .wav files found in that directory!"
endif

if n_target > nFiles
    n_target = nFiles
endif

appendInfoLine: "Found ", nFiles, " files, selecting top ", n_target

# ============================================
# ANALYSIS TABLE
# ============================================

# v0.6 CRITICAL 3: PASS 1 collects raw features; the table is built
# after normalisation, so only valid candidates appear in it.
nValid = 0
nRejected = 0
vIdx# = zero#(nFiles)
vC0# = zero#(nFiles)
vC1# = zero#(nFiles)
vStab# = zero#(nFiles)
vDark# = zero#(nFiles)
vBright# = zero#(nFiles)
for vi from 1 to nFiles
    vName$[vi] = ""
endfor

appendInfoLine: "Analyzing files..."

# ============================================
# ANALYSIS LOOP
# ============================================

for i from 1 to nFiles
    selectObject: stringsID
    fileName$ = Get string: i
    
    soundID = Read from file: directory$ + fileName$

    # v0.6 fix 4: downmix AND resample BEFORE the MFCC. v0.5 resampled
    # only during assembly, so files at different rates went through
    # different spectral front ends and their coefficients were not
    # comparable.
    selectObject: soundID
    nCh = Get number of channels
    if nCh > 1
        monoID = Convert to mono
        removeObject: soundID
        soundID = monoID
    endif
    selectObject: soundID
    curFs = Get sampling frequency
    if curFs <> target_sample_rate
        rsID = Resample: target_sample_rate, 50
        removeObject: soundID
        soundID = rsID
    endif

    # v0.6 fix 5: reject what cannot be measured, instead of letting it
    # score well by having no measurable variation.
    selectObject: soundID
    filePeak = Get absolute extremum: 0, 0, "None"
    fileDur = Get total duration
    isValid = 1
    rejectReason$ = ""
    if filePeak < 1e-5
        isValid = 0
        rejectReason$ = "silent"
    elsif fileDur < 0.05
        isValid = 0
        rejectReason$ = "shorter than the 50 ms minimum"
    endif

    if isValid
        selectObject: soundID
        mfccID = To MFCC: 12, 0.015, 0.005, 100.0, 100.0, 0
        nFrames = Get number of frames
        if nFrames < 2
            isValid = 0
            rejectReason$ = "fewer than 2 analysis frames"
        endif
    endif

    if isValid
        sum_c0 = 0
        sum_c1 = 0
        badVal = 0
        for f from 1 to nFrames
            # v0.6 CRITICAL 1: C0 lives in its own slot. Verified on
            # 6.4.42, same frame: Get c0 value = 2362.51248 while
            # Get value in frame ,1 = -78.43891 - so v0.5's "C0" was
            # C1 and its "C1" was C2.
            selectObject: mfccID
            val_c0 = Get c0 value in frame: f
            selectObject: mfccID
            val_c1 = Get value in frame: f, 1
            if val_c0 = undefined or val_c1 = undefined
                badVal = 1
            else
                sum_c0 = sum_c0 + val_c0
                sum_c1 = sum_c1 + val_c1
            endif
        endfor
        if badVal
            isValid = 0
            rejectReason$ = "undefined C0/C1"
        endif
    endif

    if isValid
        mean_c0 = sum_c0 / nFrames
        mean_c1 = sum_c1 / nFrames

        if stability_measure = 1
            # dispersion: how spread C1 is about its mean
            sum_sq_diff = 0
            for f from 1 to nFrames
                selectObject: mfccID
                val_c1 = Get value in frame: f, 1
                diff = val_c1 - mean_c1
                sum_sq_diff = sum_sq_diff + diff * diff
            endfor
            stab_raw = sqrt(sum_sq_diff / (nFrames - 1))
        else
            # v0.6 fix 6: temporal - mean |C1(t) - C1(t-1)|. A slow
            # sweep and fast jitter can share a standard deviation;
            # this separates them.
            selectObject: mfccID
            prevC1 = Get value in frame: 1, 1
            sumAbsD = 0
            for f from 2 to nFrames
                selectObject: mfccID
                curC1 = Get value in frame: f, 1
                sumAbsD = sumAbsD + abs(curC1 - prevC1)
                prevC1 = curC1
            endfor
            stab_raw = sumAbsD / (nFrames - 1)
        endif

        # v0.6 CRITICAL 2: POSITIVE C1 is dark, NEGATIVE is bright.
        # C1's DCT basis is positive over the low Mel filters and
        # negative over the high ones. Measured at equal peak:
        #   dark   (120 + 200 Hz) -> mean C1 = +1105.84
        #   bright (6 k + 9 kHz)  -> mean C1 =  -625.22
        # v0.5 had these reversed.
        raw_dark = 0
        if mean_c1 > 0
            raw_dark = mean_c1
        endif
        raw_bright = 0
        if mean_c1 < 0
            raw_bright = abs(mean_c1)
        endif

        # v0.6 CRITICAL 3: RAW values here; normalisation across the
        # corpus and the weights come in a second pass. v0.5 summed
        # these directly, so "100 - C0" in the hundreds swamped a tilt
        # violation in the units.
        nValid = nValid + 1
        vIdx#[nValid] = i
        vName$[nValid] = fileName$
        vC0#[nValid] = mean_c0
        vC1#[nValid] = mean_c1
        vStab#[nValid] = stab_raw
        vDark#[nValid] = raw_dark
        vBright#[nValid] = raw_bright
    else
        nRejected = nRejected + 1
        appendInfoLine: ""
        appendInfoLine: "  Skipping ", fileName$, " (", rejectReason$, ")"
    endif

    nocheck removeObject: mfccID
    nocheck removeObject: soundID

    if i mod 10 = 0
        appendInfo: "."
    endif
endfor

appendInfoLine: " done"

if nValid < 1
    exitScript: "No usable files: all " + string$(nFiles) +
        ... " were silent, too short, or produced undefined coefficients."
endif
if nRejected > 0
    appendInfoLine: "  ", nRejected, " file(s) excluded; ", nValid, " valid candidates"
endif

# ============================================
# PASS 2: NORMALISE VIOLATIONS, THEN WEIGHT
# ============================================
# v0.6 CRITICAL 3: v0.5 summed raw violations on wildly different
# scales - energy in the hundreds, tilt in the units, stability times
# an arbitrary 10 - so "Balanced" with all weights at 1 was nothing of
# the kind. Each violation is min-max normalised across the CORPUS
# first, which also removes the need for the "100 - C0" constant: the
# energy violation is now relative to the corpus rather than to a
# number with no basis in C0's range.

# energy violation = how far BELOW the corpus maximum this file sits
maxC0 = vC0#[1]
minC0 = vC0#[1]
for v from 2 to nValid
    if vC0#[v] > maxC0
        maxC0 = vC0#[v]
    endif
    if vC0#[v] < minC0
        minC0 = vC0#[v]
    endif
endfor
vEnergy# = zero#(nValid)
for v from 1 to nValid
    vEnergy#[v] = maxC0 - vC0#[v]
endfor

procedure normVec: .n
    .mn = normSrc#[1]
    .mx = normSrc#[1]
    for .v from 2 to .n
        if normSrc#[.v] < .mn
            .mn = normSrc#[.v]
        endif
        if normSrc#[.v] > .mx
            .mx = normSrc#[.v]
        endif
    endfor
    .rng = .mx - .mn
    if .rng < 1e-12
        .rng = 1
    endif
    for .v from 1 to .n
        normOut#[.v] = (normSrc#[.v] - .mn) / .rng
    endfor
endproc

normSrc# = zero#(nValid)
normOut# = zero#(nValid)
nDark# = zero#(nValid)
nBright# = zero#(nValid)
nEnergy# = zero#(nValid)
nStab# = zero#(nValid)

for v from 1 to nValid
    normSrc#[v] = vDark#[v]
endfor
@normVec: nValid
for v from 1 to nValid
    nDark#[v] = normOut#[v]
endfor

for v from 1 to nValid
    normSrc#[v] = vBright#[v]
endfor
@normVec: nValid
for v from 1 to nValid
    nBright#[v] = normOut#[v]
endfor

for v from 1 to nValid
    normSrc#[v] = vEnergy#[v]
endfor
@normVec: nValid
for v from 1 to nValid
    nEnergy#[v] = normOut#[v]
endfor

for v from 1 to nValid
    normSrc#[v] = vStab#[v]
endfor
@normVec: nValid
for v from 1 to nValid
    nStab#[v] = normOut#[v]
endfor

tableID = Create Table with column names: "OT_Leaderboard", nValid,
    ... "Filename C0_Energy C1_Tilt Stability Viol_Darkness Viol_Brightness Viol_Energy Viol_Stability Harmony_Score"

for v from 1 to nValid
    harmony = nDark#[v] * weight_darkness + nBright#[v] * weight_brightness +
        ... nEnergy#[v] * weight_energy + nStab#[v] * weight_stability
    selectObject: tableID
    Set string value: v, "Filename", vName$[v]
    Set numeric value: v, "C0_Energy", vC0#[v]
    Set numeric value: v, "C1_Tilt", vC1#[v]
    Set numeric value: v, "Stability", vStab#[v]
    Set numeric value: v, "Viol_Darkness", nDark#[v]
    Set numeric value: v, "Viol_Brightness", nBright#[v]
    Set numeric value: v, "Viol_Energy", nEnergy#[v]
    Set numeric value: v, "Viol_Stability", nStab#[v]
    Set numeric value: v, "Harmony_Score", harmony
endfor

nFilesValid = nValid

# v0.6 fix 5: clamp to the VALID candidates, not the raw file count.
if n_target > nValid
    n_target = nValid
    appendInfoLine: "  Limit_files reduced to ", n_target, " (valid candidates)"
endif

# ============================================
# SORTING
# ============================================

selectObject: tableID
Sort rows: "Harmony_Score"

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "CONSTRAINT WEIGHTS:"
appendInfoLine: "  *DARKNESS     = ", fixed$(weight_darkness, 2)
appendInfoLine: "  *BRIGHTNESS   = ", fixed$(weight_brightness, 2)
appendInfoLine: "  *LOW-ENERGY   = ", fixed$(weight_energy, 2)
appendInfoLine: "  *UNSTABLE     = ", fixed$(weight_stability, 2)
appendInfoLine: "============================================"
appendInfoLine: ""
appendInfoLine: "RANKING: Top ", n_target, " files by Harmony Score"
appendInfoLine: "--------------------------------------------"

# Store harmony scores for visualization
harmony_scores# = zero#(n_target)
energy_vals# = zero#(n_target)
tilt_vals# = zero#(n_target)

minSelDur = 1e9

for i from 1 to n_target
    selectObject: tableID
    name$ = Get value: i, "Filename"
    score = Get value: i, "Harmony_Score"
    
    harmony_scores#[i] = score
    
    v_dark = Get value: i, "Viol_Darkness"
    v_bright = Get value: i, "Viol_Brightness"
    v_energy = Get value: i, "Viol_Energy"
    v_stable = Get value: i, "Viol_Stability"
    
    c0 = Get value: i, "C0_Energy"
    c1 = Get value: i, "C1_Tilt"
    
    energy_vals#[i] = c0
    tilt_vals#[i] = c1
    
    appendInfoLine: i, ". ", name$, " -> Harmony: ", fixed$(score, 2)
    appendInfoLine: "   Features: Energy=", fixed$(c0, 1), " | Tilt=", fixed$(c1, 2)
    
    if v_dark > 0 or v_bright > 0 or v_energy > 0 or v_stable > 0
        appendInfoLine: "   Violations:"
        if v_dark > 0
            appendInfoLine: "      *DARKNESS    = ", fixed$(v_dark, 2), " x ", weight_darkness, " = ", fixed$(v_dark * weight_darkness, 2)
        endif
        if v_bright > 0
            appendInfoLine: "      *BRIGHTNESS  = ", fixed$(v_bright, 2), " x ", weight_brightness, " = ", fixed$(v_bright * weight_brightness, 2)
        endif
        if v_energy > 0
            appendInfoLine: "      *LOW-ENERGY  = ", fixed$(v_energy, 2), " x ", weight_energy, " = ", fixed$(v_energy * weight_energy, 2)
        endif
        if v_stable > 0
            appendInfoLine: "      *UNSTABLE    = ", fixed$(v_stable, 2), " x ", weight_stability, " = ", fixed$(v_stable * weight_stability, 2)
        endif
    endif
    
    appendInfoLine: ""
endfor

appendInfoLine: "--------------------------------------------"

# ============================================
# CONCATENATION (FIXED FOR SAMPLING RATES)
# ============================================

appendInfoLine: "Loading and concatenating files..."

# Create array to store sound IDs
soundIDs# = zero#(n_target)

# We set a standard sample rate to prevent "Unequal sampling frequencies" error

for i from 1 to n_target
    selectObject: tableID
    fileName$ = Get value: i, "Filename"
    
    # Read the file
    readID = Read from file: directory$ + fileName$
    
    # Check frequency and resample if necessary
    # FIX: Get frequency first, then check variable in IF statement
    current_fs = Get sampling frequency
    
    if current_fs <> target_sample_rate
        soundID = Resample: target_sample_rate, 50
        selectObject: readID
        Remove
    else
        soundID = readID
    endif

    # Fix channel mismatch: convert to mono if needed
    selectObject: soundID
    nCh = Get number of channels
    if nCh > 1
        monoID = Convert to mono
        removeObject: soundID
        soundID = monoID
    endif

    soundIDs#[i] = soundID
    selectObject: soundID
    thisDur = Get total duration
    if i = 1 or thisDur < minSelDur
        minSelDur = thisDur
    endif
endfor

# Select all sounds for concatenation
selectObject: soundIDs#[1]
for i from 2 to n_target
    plusObject: soundIDs#[i]
endfor

# v0.6 fix 7: joining is a musical choice. Hard cut stays the default -
# abrupt joins are part of corpus montage - with crossfades available.
# Keep the ACTUAL overlap used after the 45% safety cap so the
# visualization reports what was rendered, not only what was requested.
actualJoinXfSec = 0
if join_mode = 1
    Concatenate
else
    if join_mode = 2
        actualJoinXfSec = crossfade_ms / 1000
    else
        actualJoinXfSec = crossfade_ms / 1000 * 4
    endif
    if actualJoinXfSec > minSelDur * 0.45
        actualJoinXfSec = minSelDur * 0.45
    endif
    if actualJoinXfSec < 0.001
        actualJoinXfSec = 0
        Concatenate
    else
        Concatenate with overlap: actualJoinXfSec
    endif
endif
finalID = selected("Sound")
Rename: "OT_Concat_" + presetName$

# Scale to prevent clipping
# v0.6 fix 8: Normalize_output_peak is a choice now; when off, the mix
# is only touched if it would clip.
outPeakNow = Get absolute extremum: 0, 0, "None"
if normalize_output_peak
    Scale peak: 0.99
elsif outPeakNow > 0.99
    Scale peak: 0.99
    appendInfoLine: "  Limiter engaged (peak was ", fixed$(outPeakNow, 3), ")"
endif

# Get duration for display
selectObject: finalID
finalDur = Get total duration

# ============================================
# VISUALIZATION
# ============================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    pageHeight = 5.55
    Erase all
    Select outer viewport: 0, 8, 0, pageHeight

    if stability_measure = 1
        stabilityDesc$ = "dispersion (SD of C1)"
    else
        stabilityDesc$ = "temporal mean |delta C1|"
    endif

    if join_mode = 1 or actualJoinXfSec = 0
        joinDesc$ = "hard cut"
    elsif join_mode = 2
        joinDesc$ = "short crossfade " + fixed$(actualJoinXfSec * 1000, 0) + " ms actual"
    else
        joinDesc$ = "long crossfade " + fixed$(actualJoinXfSec * 1000, 0) + " ms actual"
    endif

    if normalize_output_peak
        levelDesc$ = "normalize peak to 0.99"
    else
        levelDesc$ = "preserve gain; limit only if clipping"
    endif

    # === Header ===
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##OT Corpus Concatenator v0.9##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", presetName$ + " | " + string$(nFilesValid) + " valid candidates | top " + string$(n_target) + " selected | weighted-sum Harmony"

    # === Output waveform ===
    Select outer viewport: 0, 8, 0.66, 1.88
    Select inner viewport: 0.60, 7.70, 0.84, 1.66
    selectObject: finalID
    Colour: "{0.25, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Output"
    Text bottom: "no", "Time (s)"
    Text top: "no", "Concatenated Output | " + fixed$(finalDur, 2) + " s | " + string$(n_target) + " files"

    # === Harmony scores ===
    Select outer viewport: 0, 4, 2.08, 4.02
    Select inner viewport: 0.60, 3.85, 2.32, 3.78

    maxHarmony = harmony_scores#[n_target]
    if maxHarmony < 1
        maxHarmony = 1
    endif

    Axes: 0, n_target + 1, 0, maxHarmony * 1.12
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, n_target + 1, 0, maxHarmony * 1.12

    for i from 1 to n_target
        if n_target > 1
            rankFrac = (i - 1) / (n_target - 1)
        else
            rankFrac = 0
        endif
        rVal = 0.25 + 0.35 * rankFrac
        gVal = 0.45 + 0.25 * rankFrac
        bVal = 0.75 + 0.12 * rankFrac
        rVal$ = fixed$(rVal, 3)
        gVal$ = fixed$(gVal, 3)
        bVal$ = fixed$(bVal, 3)
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", i - 0.38, i + 0.38, 0, harmony_scores#[i]
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Harmony"
    Text bottom: "no", "Rank"
    Text top: "no", "Harmony Ranking | lower = better"

    # === Energy vs Tilt scatter ===
    Select outer viewport: 4, 8, 2.08, 4.02
    Select inner viewport: 4.45, 7.70, 2.32, 3.78

    minEnergy = energy_vals#[1]
    maxEnergy = energy_vals#[1]
    minTilt = tilt_vals#[1]
    maxTilt = tilt_vals#[1]

    for i from 2 to n_target
        if energy_vals#[i] < minEnergy
            minEnergy = energy_vals#[i]
        endif
        if energy_vals#[i] > maxEnergy
            maxEnergy = energy_vals#[i]
        endif
        if tilt_vals#[i] < minTilt
            minTilt = tilt_vals#[i]
        endif
        if tilt_vals#[i] > maxTilt
            maxTilt = tilt_vals#[i]
        endif
    endfor

    energyRange = maxEnergy - minEnergy
    if energyRange < 1
        energyRange = 1
    endif
    tiltRange = maxTilt - minTilt
    if tiltRange < 1
        tiltRange = 1
    endif

    xMinPlot = minEnergy - energyRange * 0.1
    xMaxPlot = maxEnergy + energyRange * 0.1
    yMinPlot = minTilt - tiltRange * 0.1
    yMaxPlot = maxTilt + tiltRange * 0.1

    Axes: xMinPlot, xMaxPlot, yMinPlot, yMaxPlot
    Paint rectangle: "{0.97, 0.97, 0.97}", xMinPlot, xMaxPlot, yMinPlot, yMaxPlot

    pointSize = energyRange * 0.025
    pointSizeY = tiltRange * 0.025

    for i from 1 to n_target
        if n_target > 1
            rankFrac = (i - 1) / (n_target - 1)
        else
            rankFrac = 0
        endif
        rVal = 0.25 + 0.35 * rankFrac
        gVal = 0.45 + 0.25 * rankFrac
        bVal = 0.75 + 0.12 * rankFrac
        rVal$ = fixed$(rVal, 3)
        gVal$ = fixed$(gVal, 3)
        bVal$ = fixed$(bVal, 3)
        x = energy_vals#[i]
        y = tilt_vals#[i]
        Paint rectangle: "{" + rVal$ + ", " + gVal$ + ", " + bVal$ + "}", x - pointSize, x + pointSize, y - pointSizeY, y + pointSizeY
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Tilt (C1)"
    Text bottom: "no", "Energy (C0)"
    Text top: "no", "Selected Corpus Space | darker = higher rank"

    # === Summary strip ===
    Select outer viewport: 0, 8, 4.23, 5.50
    Select inner viewport: 0.60, 7.70, 4.31, 5.42
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    summary1$ = "##Corpus##  " + string$(nFiles) + " files | " + string$(nFilesValid) + " valid | " + string$(n_target) + " selected | output " + fixed$(finalDur, 2) + " s"
    summary2$ = "##Constraints##  DARK " + fixed$(weight_darkness, 1) + " | BRIGHT " + fixed$(weight_brightness, 1) + " | ENERGY " + fixed$(weight_energy, 1) + " | STABLE " + fixed$(weight_stability, 1) + " | " + stabilityDesc$
    summary3$ = "##Output##  " + joinDesc$ + " | " + levelDesc$ + " | C0 = recorded-level proxy | C1 sign: + dark / - bright"
    Text: 0.02, "left", 0.78, "half", summary1$
    Text: 0.02, "left", 0.50, "half", summary2$
    Text: 0.02, "left", 0.22, "half", summary3$

    Colour: "Black"
    Draw inner box

    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
endif

# ============================================
# CLEANUP
# ============================================

# Remove individual sound files
for i from 1 to n_target
    removeObject: soundIDs#[i]
endfor

# Remove temporary objects
removeObject: stringsID, tableID

# ============================================
# OUTPUT
# ============================================

selectObject: finalID

appendInfoLine: ""
appendInfoLine: "============================================"
appendInfoLine: "SUCCESS!"
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Contains ", n_target, " concatenated files"
appendInfoLine: "Duration: ", fixed$(finalDur, 2), " s"
appendInfoLine: "============================================"

if play_result
    Play
endif

selectObject: finalID