# ============================================================
# Praat AudioTools - Electrical_Hum_Removal.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.3 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Removes electrical/power line hum (50 Hz or 60 Hz) and its
#   harmonics using cascaded band-stop (notch) filters. Auto-detection
#   scores a harmonic comb over a high-resolution spectrum and refuses
#   to act unless it finds real evidence of hum.
#
# Categories: Audio Restoration, Spectral Processing, Noise Reduction
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#
# Changelog v2.3 - Parselmouth-verified again. The v2.2 gating worked:
# every control - pure tones at 100, 115, 120, 230, 240, 345, 400, 440,
# 450, 460 and 880 Hz, noise, silence and a 220/330/440 chord - scored
# 0 and passed through bit-identical, while harmonic hum was found at
# 49.996, 59.996, 49.196 and 59.421 Hz. Six things remained:
#   - THE CODE STILL USED A RECTANGULAR WINDOW. v2.2's changelog said
#     Hann and the Extract part call said "rectangular". That is now
#     actually Hanning, which is what the scoring was calibrated on.
#   - REFINEMENT SEARCHED THE WRONG PLACE. It polished against one
#     harmonic within a fixed +/- 1 Hz window, but a 0.5 Hz coarse
#     error becomes 2.5 Hz at h = 5, so the true peak lay outside the
#     window: 50 Hz read 49.581 and 49.2 Hz read 48.781 on 1 s files.
#     Every active harmonic is now located in a window that scales with
#     h, and the fundamental estimates are combined by median.
#   - SUSTAINED BASS NOTES WERE READ AS HUM. Notes at 48.999, 51.913,
#     58.270 and 61.735 Hz scored 39-42 dB and lost about 18.5 dB.
#     These are genuine harmonic signals, so no spectral-evidence test
#     can reject them. Two limits now do most of the work: distance
#     from 50 or 60 Hz (mains is regulated to about +/- 0.2 Hz, and a
#     1.0 Hz limit rejects all four of those notes while keeping hum
#     drifted to 49.2 or 59.4 Hz), and a stationarity test requiring
#     the peak in all four sub-blocks within Max_freq_drift_Hz.
#     Stated plainly: a steady bass note at exactly 50.000 Hz is still
#     indistinguishable, and Fixed mode is the answer there.
#   - SHORT FILES NO LONGER GUESS. At 200 ms, 60 Hz hum was measured as
#     58.241 Hz - 1.76 Hz out, enough to miss a narrow stop band. Below
#     Min_auto_duration_s the result is snapped to the nearer standard
#     instead, and it says so.
#   - Fundamental-only hum is not detected at the default
#     Min_active_harmonics = 2, by design. The menu entry is now
#     "Auto-detect harmonic mains hum"; set the minimum to 1 for
#     near-sinusoidal hum, accepting more false positives.
#   - Min_active_harmonics is validated against the 5 harmonics the
#     comb actually scores; 6 could never be satisfied and detection
#     would have failed silently.
#   - The visualization was on a 10-inch canvas with 0.5/9.7 inner
#     margins, the only script in the suite not on the library's 8-inch
#     canvas with 0.6/7.7 margins. Rescaled: full-width panels are
#     0 to 8 with inner 0.6/7.7, and the two-column panels are 0-4 and
#     4-8 with inner 0.6/3.75 and 4.55/7.7.
#   - The form was too tall to fit on screen, and Praat forms do not
#     scroll. Nine advanced settings moved to an ADVANCED SETTINGS
#     block just below the form: the detection tuning and the notch
#     growth limits, which are worth having but rarely worth changing
#     per file. The variable names are unchanged, so moving any line
#     back into the form needs no other edit, and presets still
#     override them because they are set before the preset block.
#
# Changelog v2.2 - Parselmouth-verified again. Fixed mode, notch
# geometry, capped growth, xmin, four channels, hyphenated object
# names, the bypass and the stopwatch all passed; a 50 Hz notch
# measured symmetric (-0.14 dB at 48, -18.20 at 50, -0.15 at 52).
# Auto-detect did not:
#   - THE v2.1 SCORE WAS STILL MEANINGLESS IN THE FLOOR. It compared dB
#     levels - level(h*f) minus the mean of two points 5 Hz either side
#     - after a RECTANGULAR window and FFT zero-padding. A leakage lobe
#     sitting next to an FFT null gives tens of dB of contrast with no
#     energy present. Measured: 185 of 185 pure tones from 80 to
#     1000 Hz passed the 18 dB threshold, scoring 50-63 dB, and a clean
#     230 Hz tone lost 25.36 dB to notches at 57.45 Hz. Raising the
#     threshold could not have helped. Detection is now: Hann window;
#     linear power, not dB differences; a MEDIAN local baseline;
#     an absolute gate against the global floor as well as the local
#     one; the fundamental required to be present; a minimum count of
#     active harmonics; two narrow bands (47-53, 57-63) unless
#     Wide_search; and a refinement pass that locates the true spectral
#     peak and divides the highest active harmonic.
#     Re-verified before shipping: 13 controls - pure tones at 100,
#     115, 120, 230, 240, 345, 400, 440, 450, 460 and 880 Hz, noise,
#     and a 220/330 chord - now all score exactly 0, while 50, 60,
#     49.2 and 59.4 Hz hum score 39-49 dB at 1, 2, 3 and 5 seconds.
#     Default confidence lowered to 12 because clean material no longer
#     scores at all.
#   - Zero valid harmonics no longer crashes. If baseFreq >= 0.85 x
#     Nyquist, validHarmonics stayed 0 and the code still read
#     notchSpans#[1] and notchSpans#[validHarmonics]: "In vector
#     indexing, the element index should be positive", seen at sample
#     rates of 80, 100 and 120 Hz.
#   - The visualization spectrum is genuinely pre-normalization. v2.1
#     claimed this but took the Ltas after Stage 4, so Peak normalize
#     shifted the whole curve. A copy is now taken before the level
#     stage.
#   - The "each pass roughly doubles the attenuation" note is gone.
#     Measured at the notch centre: 1 pass -18.20 dB, 2 passes
#     -22.18 dB, 3 passes -24.29 dB - diminishing returns, though the
#     transition regions do accumulate more nearly additively.
#
# Changelog v2.1 - reviewed by running the script under Parselmouth,
# so the figures below are measurements.
#   - AUTO-DETECT REBUILT. v2.0 built its spectrum with "To Ltas: 100",
#     i.e. 100 Hz bins, and then searched it in 1 Hz steps between 45
#     and 65 Hz. A 100 Hz bin cannot distinguish 50 from 60, so the
#     search only ever returned an endpoint: pure 50 Hz hum, pure 60 Hz
#     hum, 49.2, 59.4 and 55 Hz hum, and plain noise ALL reported
#     45 Hz, while a 100 Hz tone and a 440 Hz tone both reported 65 Hz.
#     Auto-detect therefore removed almost nothing (about 0 dB at the
#     real hum frequency, against 15-16 dB in Fixed mode) and the three
#     auto presets were unreliable. Detection now scores a harmonic
#     comb - level at f, 2f, 3f... minus a local baseline either side,
#     weighted 1/h - over a spectrum whose bins come from the analysis
#     length rather than a fixed 100 Hz.
#   - CONFIDENCE TEST. v2.0 always picked a frequency and always
#     filtered, so on clean material it attenuated musical content: a
#     440 Hz tone lost 1.20 dB, 450 Hz lost 8.35 dB and 455 Hz lost
#     16.35 dB, all in the name of removing hum that was not there.
#     The comb score must now clear Detection_confidence_dB. In
#     calibration, hum scored 20-55 dB while noise, a 440 Hz tone, a
#     100 Hz tone and a two-tone chord all scored under 15 dB.
#   - NOTCH GEOMETRY IS EXPLICIT. The third argument of
#     Filter (stop Hann band) is the TRANSITION width, and v2.0 passed
#     currentBW * 2 while treating currentBW as a half-width, so a
#     "+/- 1.5 Hz" notch actually reached +/- 4.5 Hz. Measured on a
#     50 Hz notch at base bandwidth 1.5: -1.16 dB at 47 Hz, -3.46 at
#     48, -13.23 at 50 and -3.35 by 52. Notch width and transition
#     width are now separate fields, and the report and the plot both
#     show the full affected span.
#   - BANDWIDTH GROWTH IS CAPPED. BW = base * scaling^(n-1) reached
#     41.3 Hz at H10 for "50 Hz Strong" and 216 Hz at H12 for "Field
#     Recording" - with transitions, a 432 Hz wide hole. On noise,
#     Field Recording removed 46.02 dB from 300-600 Hz. Growth is
#     linear now and clamped by Max_notch_width_Hz.
#   - Notch depth is controlled by Notch_passes and by Dry_wet_mix,
#     which is exactly the residual control: the report prints the
#     residual in dB rather than adding a second control that would
#     multiply with the first.
#   - Auto-detect handled xmin. It extracted from time 0 regardless of
#     where the Sound lived, so the same signal detected 45 Hz at
#     0-1 s and 55 Hz at 5-6 s - in the shifted case it was analysing
#     a range containing none of the audio.
#   - The dry/wet Formula uses the object ID. "Sound_'name$'[]" broke
#     on any name Praat parses as an expression: an object called
#     "a-b" failed with "No such object: self * 0.5000 + Sound_a".
#   - Normalization is off by default and Dry/Wet = 0 is a full bypass.
#     With the v2.0 defaults a 0.10-peak input came back at 0.95, a
#     19.55 dB lift, even at 0% wet.
#   - stopwatch fixed. It returns the time since the previous call and
#     resets, so subtracting the first reading from the second gave
#     negative times: "Processing time: -24.56 seconds" was observed.
#   - Validation on harmonics, widths, growth, mix and peak, plus a
#     warning when adjacent notches would overlap.
#   - Visualization: transition bands drawn, dB axis fitted to the
#     data, waveforms follow the work copy, display spectra use 2 Hz
#     bins so a notch is actually visible, and the output spectrum is
#     measured before any normalization.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Electrical Hum Removal v2.3
    optionmenu Preset: 1
        option Custom
        option Auto-detect (mild)
        option 50 Hz European (strong)
        option 60 Hz American (strong)
        option Studio Recording (subtle)
        option Field Recording (aggressive)
    optionmenu Detection_mode: 1
        option Auto-detect harmonic mains hum
        option Fixed 50 Hz
        option Fixed 60 Hz
    optionmenu If_no_hum_found: 1
        option Return the input unchanged
        option Filter anyway at the best candidate
        option Stop with a message
    comment === Notch shape ===
    natural Max_harmonic 8
    positive Base_notch_width_Hz 2.0
    positive Transition_width_Hz 1.0
    comment (stop band = full width; total affected = width + 2 x transition)
    natural Notch_passes 1
    real Dry_wet_mix 1.0
    comment === Output ===
    optionmenu Output_level_mode: 1
        option None (natural level)
        option Safety ceiling (attenuate only if above)
        option Peak normalize (always scale to ceiling)
    positive Peak_level 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# ADVANCED SETTINGS - edit here, not in the form
# ============================================================
# Praat forms do not scroll, so these live in the script. They are the
# detection tuning and the notch-growth limits: worth having, rarely
# worth changing per file. The names are the same ones the body uses,
# so moving a line back into the form needs no other edit.

# --- Detection ---
# Score a candidate must reach. Hum scores 39-49; clean material scores 0.
detection_confidence_dB = 12
# A harmonic counts only this far above the global floor AND its local baseline.
detection_gate_dB = 10
# How many harmonics must be active (max 5). The fundamental must be one.
min_active_harmonics = 2
# How far from 50 or 60 Hz a candidate may sit. Mains is regulated to
# about 0.2 Hz; 1.0 Hz rejects sustained bass notes near the band.
max_deviation_from_standard_Hz = 1.0
# Below this length, Auto snaps to the nearer standard rather than
# trusting a measured value (200 ms measured 60 Hz hum as 58.241 Hz).
min_auto_duration_s = 1.0
# Require the peak to hold its frequency across four sub-blocks.
require_steady_hum = 1
max_freq_drift_Hz = 0.3
# 0 = scan 47-53 and 57-63 Hz; 1 = the whole 45-65 Hz span.
wide_search = 0

# --- Notch growth ---
# Added per harmonic, linearly, and capped.
notch_width_growth_Hz = 0.3
max_notch_width_Hz = 8.0

# ============================================================
# PRESETS
# ============================================================
if preset = 2
    detection_mode = 1
    max_harmonic = 6
    base_notch_width_Hz = 2.0
    notch_width_growth_Hz = 0.2
    max_notch_width_Hz = 6.0
    transition_width_Hz = 1.0
    notch_passes = 1
    dry_wet_mix = 0.7
    presetName$ = "AutoMild"
elsif preset = 3
    detection_mode = 2
    max_harmonic = 10
    base_notch_width_Hz = 3.0
    notch_width_growth_Hz = 0.3
    max_notch_width_Hz = 8.0
    transition_width_Hz = 1.0
    notch_passes = 2
    dry_wet_mix = 1.0
    presetName$ = "50Hz_Strong"
elsif preset = 4
    detection_mode = 3
    max_harmonic = 10
    base_notch_width_Hz = 3.0
    notch_width_growth_Hz = 0.3
    max_notch_width_Hz = 8.0
    transition_width_Hz = 1.0
    notch_passes = 2
    dry_wet_mix = 1.0
    presetName$ = "60Hz_Strong"
elsif preset = 5
    detection_mode = 1
    max_harmonic = 5
    base_notch_width_Hz = 1.6
    notch_width_growth_Hz = 0.1
    max_notch_width_Hz = 4.0
    transition_width_Hz = 0.8
    notch_passes = 1
    dry_wet_mix = 0.5
    presetName$ = "Studio"
elsif preset = 6
    # Recalibrated. The v2.0 version reached a 216 Hz notch at H12 and
    # removed 46.02 dB from 300-600 Hz of noise - a low-mid hole, not
    # hum removal.
    detection_mode = 1
    max_harmonic = 12
    base_notch_width_Hz = 4.0
    notch_width_growth_Hz = 0.5
    max_notch_width_Hz = 10.0
    transition_width_Hz = 1.5
    notch_passes = 2
    dry_wet_mix = 1.0
    presetName$ = "Field"
else
    presetName$ = "Custom"
endif

# stopwatch returns the time since the PREVIOUS call and resets. v2.0
# subtracted the first reading from the second and printed negative
# times such as -24.56 seconds.
dummyTimer = stopwatch

clearinfo
writeInfoLine: "=== Electrical Hum Removal v2.3 ==="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

selectObject: originalID
samplingFreq = Get sampling frequency
duration = Get total duration
nChannels = Get number of channels
originalXmin = Get start time
nyquist = samplingFreq / 2

# === Validation ===
if base_notch_width_Hz <= 0
    exitScript: "Base_notch_width_Hz must be greater than 0."
endif
if notch_width_growth_Hz < 0
    exitScript: "Notch_width_growth_Hz must be 0 or greater (it is added per harmonic)."
endif
if max_notch_width_Hz < base_notch_width_Hz
    exitScript: "Max_notch_width_Hz (" + fixed$(max_notch_width_Hz, 2) + ") must be at " +
    ... "least Base_notch_width_Hz (" + fixed$(base_notch_width_Hz, 2) + ")."
endif
if dry_wet_mix < 0 or dry_wet_mix > 1
    exitScript: "Dry_wet_mix must be between 0 and 1 (got " + fixed$(dry_wet_mix, 3) + ")."
endif
if peak_level <= 0 or peak_level > 1
    exitScript: "Peak_level must be greater than 0 and at most 1 (got " +
    ... fixed$(peak_level, 3) + ")."
endif
if notch_passes > 6
    exitScript: "Notch_passes above 6 widens the notch far beyond its stated width."
endif
# The comb only examines 5 harmonics, so a higher requirement could
# never be met and detection would silently always fail.
if min_active_harmonics > 5
    exitScript: "Min_active_harmonics cannot exceed 5: the comb scores harmonics 1 to 5 " +
    ... "only, so a higher value can never be satisfied."
endif

appendInfoLine: "Duration: ", fixed$(duration, 2), " s | Sample rate: ", samplingFreq,
    ... " Hz | Nyquist: ", fixed$(nyquist, 1), " Hz | Channels: ", nChannels
appendInfoLine: ""

# ============================================================
# Work copy at time 0
# ============================================================
# v2.0's auto-detect extracted "0 .. analysisLen" whatever the Sound's
# own start time was, so the same signal detected 45 Hz at 0-1 s and
# 55 Hz at 5-6 s - the shifted run analysed a range holding none of the
# audio at all.
selectObject: originalID
workSound = Copy: "hum_work"
Shift times to: "start time", 0

# ============================================================
# STAGE 1: HUM FREQUENCY
# ============================================================
appendInfoLine: "Stage 1: Hum frequency..."

humFound = 1
combScore = undefined
detectRes = undefined

if detection_mode = 2
    baseFreq = 50
    appendInfoLine: "  50 Hz (fixed)"
elsif detection_mode = 3
    baseFreq = 60
    appendInfoLine: "  60 Hz (fixed)"
else
    # --- Harmonic-comb detection on a high-resolution spectrum ---
    # Bin width comes from the analysis length, not from a fixed
    # 100 Hz. v2.0's 100 Hz bins could not tell 50 from 60 Hz at all.
    analysisLen = min(10.0, duration)
    if analysisLen < 2.0
        appendInfoLine: "  WARNING: only ", fixed$(analysisLen, 2), " s available. Frequency"
        appendInfoLine: "           resolution is about ", fixed$(1 / analysisLen, 2),
        ... " Hz, so detection may be unreliable."
    endif

    # A real channel, never a sum: a fold can cancel.
    if nChannels = 1
        selectObject: workSound
        detectSound = Copy: "hum_detect"
    else
        bestRms = -1
        pickCh = 1
        for ch from 1 to nChannels
            selectObject: workSound
            probeCh = Extract one channel: ch
            probeRms = Get root-mean-square: 0, 0
            removeObject: probeCh
            if probeRms > bestRms
                bestRms = probeRms
                pickCh = ch
            endif
        endfor
        selectObject: workSound
        detectSound = Extract one channel: pickCh
        appendInfoLine: "  Detection reads channel ", pickCh
    endif

    selectObject: detectSound
    # Hann, not rectangular. v2.2's changelog said Hann and the code
    # still passed "rectangular" - and rectangular leakage is exactly
    # what made the v2.1 score meaningless in the first place.
    Extract part: 0, analysisLen, "Hanning", 1, "no"
    partID = selected("Sound")
    removeObject: detectSound

    selectObject: partID
    detSpec = To Spectrum: "yes"
    selectObject: detSpec
    detLtas = To Ltas (1-to-1)
    selectObject: detLtas
    detectRes = Get bin width
    removeObject: partID, detSpec

    appendInfoLine: "  Spectrum bin width: ", fixed$(detectRes, 4), " Hz"

    # --- Scoring, rebuilt for v2.2 ---
    # v2.1 compared dB levels: level(h*f) minus the mean of two points
    # 5 Hz either side. With a rectangular window and FFT zero-padding
    # that is meaningless down in the floor - a leakage lobe next to an
    # FFT null gives tens of dB of "contrast" with no energy present.
    # Measured consequence: 185 of 185 pure tones from 80 to 1000 Hz
    # passed an 18 dB threshold, scoring 50-63 dB, and a clean 230 Hz
    # tone lost 25.36 dB to notches placed at 57.45 Hz.
    #
    # v2.2 works in LINEAR POWER against a median local baseline, gates
    # every harmonic against the global floor, and requires the
    # fundamental itself plus a minimum number of active harmonics.
    combH = 5
    baseOffsets# = {-7, -6, -5, 5, 6, 7}
    nOffsets = 6

    selectObject: detLtas
    floorTop = min(1000, nyquist - 10)
    globalFloorDb = Get mean: 20, floorTop, "dB"
    if globalFloorDb = undefined
        globalFloorDb = -100
    endif
    gateDb = globalFloorDb + detection_gate_dB
    appendInfoLine: "  Global floor: ", fixed$(globalFloorDb, 1), " dB | harmonic gate: ",
        ... fixed$(gateDb, 1), " dB"

    if wide_search
        nBands = 1
        bandLo# = {45}
        bandHi# = {65}
    else
        # Two narrow bands, as recommended: scanning the whole 45-65 Hz
        # span invites candidates like 57.4 Hz that belong to neither
        # mains standard.
        nBands = 2
        bandLo# = {47, 57}
        bandHi# = {53, 63}
    endif

    bestScore = 0
    bestFreq = 50
    bestActive = 0
    secondScore = 0

    for band from 1 to nBands
        bandBest = 0
        testF = bandLo#[band]
        while testF <= bandHi#[band]
            tot = 0
            wsum = 0
            active = 0
            fundActive = 0

            for h from 1 to combH
                fh = h * testF
                if fh < nyquist - 15
                    # Peak power within +/- 0.25 Hz, so a peak between
                    # bins is not missed
                    selectObject: detLtas
                    pkDb = -1000
                    for s from -2 to 2
                        vDb = Get value at frequency: fh + s * 0.125, "Nearest"
                        if vDb <> undefined and vDb > pkDb
                            pkDb = vDb
                        endif
                    endfor

                    # Median of the local baseline, in linear power
                    for k from 1 to nOffsets
                        bDb = Get value at frequency: fh + baseOffsets#[k], "Nearest"
                        if bDb = undefined
                            bDb = -1000
                        endif
                        blSort_'k' = 10 ^ (bDb / 10)
                    endfor
                    for a from 2 to nOffsets
                        keyV = blSort_'a'
                        b = a - 1
                        placed = 0
                        while placed = 0
                            if b < 1
                                placed = 1
                            else
                                if blSort_'b' > keyV
                                    b1 = b + 1
                                    blSort_'b1' = blSort_'b'
                                    b = b - 1
                                else
                                    placed = 1
                                endif
                            endif
                        endwhile
                        b1 = b + 1
                        blSort_'b1' = keyV
                    endfor
                    basePow = (blSort_3 + blSort_4) / 2
                    if basePow <= 0
                        basePow = 1e-30
                    endif

                    pkPow = 10 ^ (pkDb / 10)
                    snrDb = 10 * log10(pkPow / basePow)

                    # Two gates: above the global floor in absolute
                    # terms, AND above the local baseline.
                    if pkDb > gateDb and snrDb > detection_gate_dB
                        active = active + 1
                        tot = tot + snrDb / h
                        wsum = wsum + 1 / h
                        if h = 1
                            fundActive = 1
                        endif
                    endif
                endif
            endfor

            candScore = 0
            if wsum > 0 and active >= min_active_harmonics and fundActive = 1
                candScore = tot / wsum
            endif

            if candScore > bandBest
                bandBest = candScore
            endif
            if candScore > bestScore
                secondScore = bestScore
                bestScore = candScore
                bestFreq = testF
                bestActive = active
            endif

            testF = testF + 0.05
        endwhile

        bandScore_'band' = bandBest
    endfor

    # Margin over the runner-up band
    if nBands = 2
        if bandScore_1 > bandScore_2
            otherBand = bandScore_2
        else
            otherBand = bandScore_1
        endif
    else
        otherBand = 0
    endif

    combScore = bestScore
    combActive = bestActive

    # --- Refine the frequency ---
    # v2.2 refined against ONE harmonic and searched only +/- 1 Hz
    # around h * coarseEstimate. A 0.5 Hz coarse error becomes 2.5 Hz at
    # h = 5, so the true peak fell outside the search window - which is
    # where 50 Hz -> 49.581 and 49.2 Hz -> 48.781 on 1 s files came
    # from. Each active harmonic is now located in its own window, whose
    # width scales with h, and the fundamental estimates are combined by
    # median.
    if combScore > 0
        selectObject: detLtas
        stepRef = max(detectRes / 2, 0.005)
        coarseUnc = 0.6
        nEst = 0

        for h from 1 to combH
            fh = h * bestFreq
            if fh < nyquist - 15
                halfWin = h * coarseUnc
                refBest = -1000
                refAt = fh
                rf = fh - halfWin
                while rf <= fh + halfWin
                    vDb = Get value at frequency: rf, "Nearest"
                    if vDb <> undefined and vDb > refBest
                        refBest = vDb
                        refAt = rf
                    endif
                    rf = rf + stepRef
                endwhile
                if refBest > gateDb
                    nEst = nEst + 1
                    estF_'nEst' = refAt / h
                endif
            endif
        endfor

        if nEst > 0
            # median of the per-harmonic estimates
            for a from 2 to nEst
                keyE = estF_'a'
                b = a - 1
                placed = 0
                while placed = 0
                    if b < 1
                        placed = 1
                    else
                        if estF_'b' > keyE
                            b1 = b + 1
                            estF_'b1' = estF_'b'
                            b = b - 1
                        else
                            placed = 1
                        endif
                    endif
                endwhile
                b1 = b + 1
                estF_'b1' = keyE
            endfor
            midIdx = floor((nEst + 1) / 2)
            if nEst mod 2 = 1
                bestFreq = estF_'midIdx'
            else
                midNext = midIdx + 1
                bestFreq = (estF_'midIdx' + estF_'midNext') / 2
            endif
            appendInfoLine: "  Refined from ", nEst, " harmonic peak(s): ",
                ... fixed$(bestFreq, 3), " Hz"
        endif
    endif

    # --- Plausibility: how far from a mains standard? ---
    # A harmonic-comb detector cannot tell mains hum from a sustained
    # harmonic bass note whose fundamental sits in the search band. The
    # reviewer measured notes at 48.999, 51.913, 58.270 and 61.735 Hz
    # detected with 39-42 dB confidence and attenuated by about 18.5 dB.
    # Grid frequency is regulated to roughly +/- 0.2 Hz, so distance
    # from 50 or 60 Hz is a real discriminator - it rejects all four of
    # those notes while keeping hum drifted to 49.2 or 59.4 Hz.
    # It does NOT save a bass note sitting at exactly 50.000 Hz: nothing
    # spectral can, which is why Fixed mode exists.
    devFrom50 = abs(bestFreq - 50)
    devFrom60 = abs(bestFreq - 60)
    devStd = min(devFrom50, devFrom60)
    if combScore > 0 and devStd > max_deviation_from_standard_Hz
        appendInfoLine: "  Candidate is ", fixed$(devStd, 3), " Hz from the nearer mains"
        appendInfoLine: "  standard, beyond the ", fixed$(max_deviation_from_standard_Hz, 2),
            ... " Hz limit. This looks like sustained harmonic"
        appendInfoLine: "  material rather than mains hum - rejecting."
        combScore = 0
    endif

    # --- Short files: snap rather than trust a measured value ---
    # At 200 ms the reviewer measured 60 Hz hum detected as 58.241 Hz -
    # a 1.76 Hz error, enough to put the real hum outside a narrow stop
    # band. A warning did not prevent that.
    if combScore > 0 and analysisLen < min_auto_duration_s
        if devFrom50 <= devFrom60
            snapped = 50
        else
            snapped = 60
        endif
        appendInfoLine: "  Only ", fixed$(analysisLen, 2), " s of audio (minimum for a measured"
        appendInfoLine: "  value is ", fixed$(min_auto_duration_s, 2), " s): snapping ",
            ... fixed$(bestFreq, 3), " Hz to ", snapped, " Hz."
        bestFreq = snapped
    endif

    # --- Stationarity across sub-blocks ---
    # Mains hum holds its frequency; most musical material does not.
    # This will not separate a perfectly steady synthetic tone, but it
    # does catch notes that decay, drift or stop.
    if combScore > 0 and require_steady_hum and analysisLen >= 2.0
        nBlocks = 4
        blockLen = analysisLen / nBlocks
        blocksSeen = 0
        blockMin = 1e9
        blockMax = -1e9

        for blk from 1 to nBlocks
            selectObject: workSound
            if nChannels = 1
                blkSnd = Copy: "blk_probe"
            else
                blkSnd = Extract one channel: 1
            endif
            selectObject: blkSnd
            Extract part: (blk - 1) * blockLen, blk * blockLen, "Hanning", 1, "no"
            blkPart = selected("Sound")
            removeObject: blkSnd
            selectObject: blkPart
            blkSpec = To Spectrum: "yes"
            selectObject: blkSpec
            blkLtas = To Ltas (1-to-1)
            removeObject: blkPart, blkSpec

            selectObject: blkLtas
            blkFloor = Get mean: 20, floorTop, "dB"
            if blkFloor = undefined
                blkFloor = -100
            endif
            bBest = -1000
            bAt = bestFreq
            rf = bestFreq - 1.5
            while rf <= bestFreq + 1.5
                vDb = Get value at frequency: rf, "Nearest"
                if vDb <> undefined and vDb > bBest
                    bBest = vDb
                    bAt = rf
                endif
                rf = rf + 0.05
            endwhile
            removeObject: blkLtas

            if bBest > blkFloor + detection_gate_dB
                blocksSeen = blocksSeen + 1
                if bAt < blockMin
                    blockMin = bAt
                endif
                if bAt > blockMax
                    blockMax = bAt
                endif
            endif
        endfor

        if blocksSeen < nBlocks
            appendInfoLine: "  Present in only ", blocksSeen, " of ", nBlocks,
                ... " sub-blocks: not a continuous tone - rejecting."
            combScore = 0
        else
            blockDrift = blockMax - blockMin
            appendInfoLine: "  Steady across all ", nBlocks, " sub-blocks (drift ",
                ... fixed$(blockDrift, 3), " Hz, limit ", fixed$(max_freq_drift_Hz, 2), ")"
            if blockDrift > max_freq_drift_Hz
                appendInfoLine: "  Frequency wanders more than mains does - rejecting."
                combScore = 0
            endif
        endif
    endif

    removeObject: detLtas

    baseFreq = bestFreq
    combScore = bestScore
    appendInfoLine: "  Best candidate: ", fixed$(baseFreq, 3), " Hz | score ",
        ... fixed$(combScore, 2), " dB (threshold ", fixed$(detection_confidence_dB, 1),
        ... ") | active harmonics: ", combActive
    if combScore > 0 and otherBand > 0
        appendInfoLine: "  Runner-up band scored ", fixed$(otherBand, 2), " dB (margin ",
            ... fixed$(combScore - otherBand, 2), " dB)"
    endif

    if combScore < detection_confidence_dB
        humFound = 0
        appendInfoLine: "  NO CONVINCING HUM FOUND."
        appendInfoLine: "    A score of 0 means no candidate had an active fundamental plus ",
            ... min_active_harmonics, " harmonics above the floor."
        if if_no_hum_found = 3
            removeObject: workSound
            exitScript: "No hum detected: the best comb score was " + fixed$(combScore, 2) +
            ... " dB against a threshold of " + fixed$(detection_confidence_dB, 1) + " dB. " +
            ... "Use a Fixed mode if you know the frequency, or lower " +
            ... "Detection_confidence_dB."
        elsif if_no_hum_found = 1
            appendInfoLine: "    Returning the input unchanged."
        else
            appendInfoLine: "    Filtering anyway at ", fixed$(baseFreq, 2), " Hz, as requested."
        endif
    endif
endif

# ============================================================
# STAGE 2: NOTCH FILTERS
# ============================================================
doFilter = 1
if dry_wet_mix = 0
    doFilter = 0
    appendInfoLine: ""
    appendInfoLine: "Dry/Wet is 0: full bypass, the output is the input unchanged."
endif
if humFound = 0 and if_no_hum_found = 1
    doFilter = 0
endif

selectObject: workSound
processedID = Copy: "filtered_temp"

validHarmonics = 0
notchFreqs# = zero#(max_harmonic)
notchWidths# = zero#(max_harmonic)
notchSpans# = zero#(max_harmonic)
overlapWarned = 0

if doFilter
    appendInfoLine: ""
    appendInfoLine: "Stage 2: Notch filters..."

    for harmonic from 1 to max_harmonic
        freq = baseFreq * harmonic

        # Linear growth with a ceiling. v2.0 used base * scaling^(n-1),
        # which reached 41.3 Hz at H10 and 216 Hz at H12.
        currentW = base_notch_width_Hz + notch_width_growth_Hz * (harmonic - 1)
        if currentW > max_notch_width_Hz
            currentW = max_notch_width_Hz
        endif

        # The third argument of Filter (stop Hann band) is the
        # TRANSITION width, so the total affected span is
        # width + 2 x transition. v2.0 passed currentBW * 2 there while
        # calling currentBW a half-width, which tripled the real reach.
        halfW = currentW / 2
        lowCut = max(1, freq - halfW)
        highCut = freq + halfW
        totalSpan = currentW + 2 * transition_width_Hz

        if freq < nyquist * 0.85
            validHarmonics += 1

            if totalSpan >= baseFreq and overlapWarned = 0
                appendInfoLine: "  WARNING: at H", harmonic, " the affected span (",
                    ... fixed$(totalSpan, 1), " Hz) reaches the neighbouring harmonic (",
                    ... fixed$(baseFreq, 1), " Hz apart). Notches are overlapping."
                overlapWarned = 1
            endif

            for pass from 1 to notch_passes
                selectObject: processedID
                Filter (stop Hann band): lowCut, highCut, transition_width_Hz
                filteredID = selected("Sound")
                removeObject: processedID
                processedID = filteredID
            endfor

            notchFreqs#[validHarmonics] = freq
            notchWidths#[validHarmonics] = currentW
            notchSpans#[validHarmonics] = totalSpan
        endif
    endfor

    # v2.1 indexed notchSpans#[1] and [validHarmonics] unconditionally,
    # so a sample rate low enough that baseFreq >= 0.85 x Nyquist left
    # validHarmonics at 0 and crashed with "In vector indexing, the
    # element index should be positive" (seen at 80, 100 and 120 Hz).
    if validHarmonics = 0
        appendInfoLine: "  No harmonic of ", fixed$(baseFreq, 2), " Hz falls below 85% of"
        appendInfoLine: "  Nyquist (", fixed$(nyquist, 1), " Hz): nothing to filter."
        doFilter = 0
    else
        appendInfoLine: "  ", validHarmonics, " harmonics, ", notch_passes, " pass(es) each"
        appendInfoLine: "  H1 span: ", fixed$(notchSpans#[1], 2), " Hz | H", validHarmonics,
            ... " span: ", fixed$(notchSpans#[validHarmonics], 2), " Hz"
    endif
endif

# ============================================================
# STAGE 3: DRY/WET
# ============================================================
# Object ID, not the object NAME. v2.0 built "Sound_'name$'[]", which
# fails for any name Praat parses as an expression: an object called
# "a-b" produced "No such object: self * 0.5000 + Sound_a".
if doFilter and dry_wet_mix < 1
    selectObject: processedID
    Formula: "self * " + fixed$(dry_wet_mix, 6) + " + object[" + string$(workSound) +
        ... ", row, col] * " + fixed$(1 - dry_wet_mix, 6)
    residual_dB = -20 * log10(1 - dry_wet_mix)
    appendInfoLine: ""
    appendInfoLine: "Stage 3: ", fixed$(dry_wet_mix * 100, 0), "% wet"
    appendInfoLine: "  Dry/Wet is the depth control: the residual at each notch centre is",
        ... " about ", fixed$(residual_dB, 1), " dB down."
elsif doFilter
    appendInfoLine: ""
    appendInfoLine: "Stage 3: 100% wet (no residual added back)"
endif

# ============================================================
# PRE-LEVEL SNAPSHOT FOR THE VISUALIZATION
# ============================================================
# v2.1's changelog claimed the processed spectrum was measured before
# normalization, but Stage 4 ran first and the Ltas was taken after, so
# in Peak normalize mode the whole output spectrum was shifted and the
# comparison showed notches plus a global gain. This copy is the state
# the notches produced, nothing else.
if draw_visualization
    selectObject: processedID
    vizProcID = Copy: "viz_pre_level"
else
    vizProcID = 0
endif

# ============================================================
# STAGE 4: OUTPUT LEVEL
# ============================================================
selectObject: processedID
pre_level_peak = Get absolute extremum: 0, 0, "None"
level_gain = 1
level_action$ = "none"

if doFilter = 0
    level_action$ = "skipped - full bypass"
elsif output_level_mode = 2
    if pre_level_peak > peak_level and pre_level_peak > 0
        Scale peak: peak_level
        level_gain = peak_level / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_peak > 0
        Scale peak: peak_level
        level_gain = peak_level / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: processedID
out_peak = Get absolute extremum: 0, 0, "None"

processingTime = stopwatch

# ============================================================
# VISUALIZATION (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all

    maxFreqDisplay = min(1000, nyquist)
    # 2 Hz bins, not 100: a notch a few Hz wide is invisible at 100 Hz
    # resolution, so v2.0's spectra could not show their own effect.
    displayLtasBW = 2

    selectObject: workSound
    To Ltas: displayLtasBW
    origLtasID = selected("Ltas")
    origLtasMin = Get minimum: 0, maxFreqDisplay, "None"
    origLtasMax = Get maximum: 0, maxFreqDisplay, "None"

    selectObject: vizProcID
    To Ltas: displayLtasBW
    procLtasID = selected("Ltas")
    procLtasMin = Get minimum: 0, maxFreqDisplay, "None"
    procLtasMax = Get maximum: 0, maxFreqDisplay, "None"

    # Fitted dB axis. v2.0 always drew 20-80 dB, so uncalibrated, quiet
    # or silent audio fell outside the frame.
    dbLo = min(origLtasMin, procLtasMin)
    dbHi = max(origLtasMax, procLtasMax)
    if dbLo = undefined or dbHi = undefined or dbHi - dbLo < 10
        dbLo = 0
        dbHi = 80
    else
        dbLo = dbLo - 5
        dbHi = dbHi + 5
    endif

    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.6, "half", "##Electrical Hum Removal##"
    Font size: 8
    Colour: "{0.35, 0.35, 0.52}"
    if detection_mode = 1
        if humFound
            detStr$ = "auto " + fixed$(baseFreq, 2) + " Hz (score " +
                ... fixed$(combScore, 1) + " dB)"
        else
            detStr$ = "auto: NO HUM FOUND (score " + fixed$(combScore, 1) + " dB)"
        endif
    else
        detStr$ = "fixed " + fixed$(baseFreq, 0) + " Hz"
    endif
    Text: 0.5, "centre", -0.5, "half",
        ... originalName$ + "  |  " + presetName$ + "  |  " + detStr$

    # === ORIGINAL SPECTRUM ===
    Select outer viewport: 0, 4, 0.6, 3.0
    Select inner viewport: 0.6, 3.75, 0.8, 2.8

    selectObject: origLtasID
    Colour: "{0.70, 0.70, 0.70}"
    Draw: 0, maxFreqDisplay, dbLo, dbHi, "no", "Curve"

    Axes: 0, maxFreqDisplay, dbLo, dbHi
    for h to validHarmonics
        freq = notchFreqs#[h]
        wid = notchWidths#[h]
        span = notchSpans#[h]
        if freq < maxFreqDisplay
            # The transition bands are part of what the filter removes,
            # so they are drawn. v2.0 showed only freq +/- BW, which was
            # a third of the real reach.
            Paint rectangle: "{1.00, 0.93, 0.93}", freq - span / 2, freq + span / 2, dbLo, dbHi
            Paint rectangle: "{0.98, 0.80, 0.80}", freq - wid / 2, freq + wid / 2, dbLo, dbHi
            Colour: "{0.90, 0.30, 0.30}"
            Line width: 1
            Draw line: freq, dbLo, freq, dbHi
        endif
    endfor

    selectObject: origLtasID
    Colour: "{0.40, 0.40, 0.40}"
    Draw: 0, maxFreqDisplay, dbLo, dbHi, "no", "Curve"

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Text top: "no", "Original + notch bands (dark = stop, pale = transition)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # === PROCESSED SPECTRUM ===
    Select outer viewport: 4, 8, 0.6, 3.0
    Select inner viewport: 4.55, 7.7, 0.8, 2.8

    selectObject: procLtasID
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, maxFreqDisplay, dbLo, dbHi, "no", "Curve"

    Axes: 0, maxFreqDisplay, dbLo, dbHi
    for h to validHarmonics
        freq = notchFreqs#[h]
        if freq < maxFreqDisplay
            Colour: "{0.50, 0.80, 0.50}"
            Line width: 1
            Dashed line
            Draw line: freq, dbLo, freq, dbHi
            Solid line
        endif
    endfor

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 8
    Text top: "no", "Processed, measured BEFORE the output stage (same dB axis)"
    Text left: "yes", "dB"
    Text bottom: "yes", "Frequency (Hz)"

    # === WAVEFORMS ===
    displayDur = min(0.5, duration)

    Select outer viewport: 0, 4, 3.2, 4.2
    Select inner viewport: 0.6, 3.75, 3.3, 4.1
    selectObject: workSound
    wavePeak = Get absolute extremum: 0, 0, "None"
    selectObject: vizProcID
    procPeak = Get absolute extremum: 0, 0, "None"
    waveAmp = max(wavePeak, procPeak)
    if waveAmp < 0.001
        waveAmp = 0.001
    endif
    waveAmp = waveAmp * 1.1

    selectObject: workSound
    Colour: "{0.60, 0.60, 0.60}"
    Draw: 0, displayDur, -waveAmp, waveAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Original (0-" + fixed$(displayDur, 2) + " s, shared scale)"
    Text left: "yes", "Amp"

    Select outer viewport: 4, 8, 3.2, 4.2
    Select inner viewport: 4.55, 7.7, 3.3, 4.1
    selectObject: vizProcID
    Colour: "{0.20, 0.50, 0.80}"
    Draw: 0, displayDur, -waveAmp, waveAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Processed"
    Text left: "yes", "Amp"

    # === NOTCH TABLE ===
    Select outer viewport: 0, 8, 4.4, 5.5
    Select inner viewport: 0.6, 7.7, 4.5, 5.4
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.05, "left", 0.9, "half", "##Notch Filters Applied##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    if validHarmonics = 0
        Text: 0.08, "left", 0.6, "half", "None - no filtering was applied."
    else
        maxDisplay = min(validHarmonics, 8)
        for h to maxDisplay
            yPos = 0.75 - (h - 1) * 0.08
            freq = notchFreqs#[h]
            wid = notchWidths#[h]
            span = notchSpans#[h]
            text$ = "H" + string$(h) + ": " + fixed$(freq, 2) + " Hz  stop " +
                ... fixed$(wid, 2) + " Hz  total affected " + fixed$(span, 2) + " Hz  (" +
                ... fixed$(freq - span / 2, 1) + " - " + fixed$(freq + span / 2, 1) + " Hz)"
            Text: 0.08, "left", yPos, "half", text$
        endfor
        if validHarmonics > 8
            Text: 0.08, "left", 0.05, "half", "... and " + string$(validHarmonics - 8) + " more"
        endif
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === INFO PANEL ===
    Select outer viewport: 0, 8, 5.6, 6.1
    Select inner viewport: 0.6, 7.7, 5.65, 6.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 7
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.5, "centre", 0.5, "half",
        ... "Base: " + fixed$(baseFreq, 2) + " Hz  |  Harmonics: " + string$(validHarmonics)
        ... + "  |  Passes: " + string$(notch_passes)
        ... + "  |  Mix: " + fixed$(dry_wet_mix * 100, 0) + "%"
        ... + "  |  Peak: " + fixed$(pre_level_peak, 3) + " -> " + fixed$(out_peak, 3)
        ... + "  |  Time: " + fixed$(processingTime, 2) + " s"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

    removeObject: origLtasID, procLtasID, vizProcID
endif

# ============================================================
# OUTPUT
# ============================================================
selectObject: processedID
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
Rename: originalName$ + "_hum_removed_" + presetName$
outputID = selected("Sound")
finalName$ = selected$("Sound")

removeObject: workSound

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " s"
appendInfoLine: "Base frequency: ", fixed$(baseFreq, 2), " Hz"
appendInfoLine: "Harmonics filtered: ", validHarmonics
appendInfoLine: "Peak: ", fixed$(pre_level_peak, 4), " -> ", fixed$(out_peak, 4),
    ... " (", level_action$, ")"
if output_level_mode <> 3 and out_peak > 1
    appendInfoLine: "WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

selectObject: outputID
if play_result
    appendInfoLine: "Playing processed sound..."
    Play
endif

selectObject: outputID
