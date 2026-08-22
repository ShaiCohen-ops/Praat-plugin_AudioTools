# ============================================================
# Praat AudioTools - Frequency Shifter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Bode-style frequency shifter using Single Sideband Modulation.
#   Shifts all frequencies by a constant Hz amount (not pitch scaling).
#   This creates inharmonic spectra - harmonic relationships are
#   destroyed.
#
# Theory:
#   y(t) = x(t)·cos(2πft) - H{x(t)}·sin(2πft)
#   with f signed: positive f shifts up, negative f shifts down. There
#   is ONE formula, not two - see the v0.3 note on double sign handling.
#
# Musical effects:
#   - Small shifts (5-20 Hz): chorus-like thickening (mix ~25-40% wet)
#   - Medium shifts (50-300 Hz): metallic, bell-like, robotic
#   - Large shifts (>500 Hz): alien, unintelligible speech
#   - Negative shifts: darker, subharmonic content
#
# Changelog v0.5 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.3 - reviewed by running the script under Parselmouth,
# so the figures below are measurements. v0.2 was not a working SSB
# shifter: three independent faults in the core.
#   - THE HILBERT TRANSFORM WAS WRONG. "if row = 1 then self[2, col]
#     else -self[1, col] fi" modifies the Spectrum IN PLACE, so once
#     row 1 has been overwritten, row 2 reads the ALREADY MODIFIED
#     value instead of the original real part. Correlation with a
#     correct Hilbert transform: 0.127. Consequence on a 440 Hz sine
#     shifted +100 Hz: 340 Hz came out STRONGER than the wanted
#     540 Hz, an unwanted-sideband ratio of -1.0 dB where SSB should
#     suppress it by tens of dB. The rotation now reads from a separate
#     unmodified copy of the Spectrum, and DC and Nyquist are zeroed.
#   - CARRIER PHASE RESET EVERY GRAIN. The modulation used the grain's
#     local x, so the carrier restarted every 50 ms hop. Only shifts
#     whose product with the hop is a whole number of cycles survived:
#     100 and 200 Hz happened to work, 8, 15, 150 and 666 Hz did not.
#     Measured on 440 Hz: "Chorus Thick" at 8 Hz produced 440, 420 and
#     460 Hz with the wanted 448 Hz about 70 dB down; "Robot Voice" at
#     150 Hz produced 580, 600, 280 and 300 Hz - products of the 20 Hz
#     grain rate, not a 150 Hz shift. The carrier phase is now global.
#   - THE SIGN WAS APPLIED TWICE. Direction "Down" negated shift_hz AND
#     the formula branched on the sign of shift_hz, so the two
#     cancelled: Up +100 Hz and Down -100 Hz gave a maximum sample
#     difference of 0 and correlation 1.0. "Deep Sub" did not shift
#     down at all. One signed formula now, no branch.
#   - Padded weighted overlap-add. There was no padding and no window
#     normalization, so even at 0 Hz shift the first and last 10 ms
#     fell to about 4.5% of the source RMS, a 1.013 s file lost its
#     final 13 ms to silence, and any file under 100 ms came out
#     completely silent.
#   - xmin handled: a Sound at 5.137-6.137 s produced output over
#     0-1 s with peak 0.
#   - Every channel processed and kept; v0.2 turned 4 channels into 2.
#   - Output_level_mode replaces the unconditional Scale peak, which
#     took a 0.1-peak source to 0.95 - 19.6 dB of gain - even at 0%
#     wet.
#   - Aliasing warning, and an optional pre-limit low-pass. Measured
#     on the corrected core: 7500 Hz at 16 kHz shifted +1200 Hz folded
#     back to 7300 Hz instead of reaching 8700 Hz.
#   - Grains are written with Formula (part) over their own sample
#     range. v0.2 ran a full-length Formula per grain, measured at
#     0.017 / 0.045 / 0.138 / 0.479 s for 1 / 2 / 4 / 8 s of audio -
#     near quadratic.
#   - Presets set Dry/wet. At 100% wet a shifted signal is not chorus
#     or thickening, however correct the shift.
#   - Downward shifts past 0 Hz are documented: 440 Hz shifted -666 Hz
#     lands at 226 Hz, the reflection of -226.
#
#
# Changelog v0.4 - Parselmouth-verified again. The three core fixes
# held: every shift landed on its exact frequency, Up and Down differ,
# xmin, four channels, bypass, pre-limit and the plots all passed. One
# new fault, introduced by my own overlap-add:
#   - THE WEIGHT BUFFER DID NOT MATCH THE WINDOWING. v0.3 applied Hann
#     on analysis only and divided by the sum of that Hann. The Hilbert
#     transform of a Hann-windowed grain does not vanish at the grain
#     edges, so the numerator stayed finite where the weight went to
#     zero. Measured on a 0.2-peak input: 20 Hz shifted +1200 Hz peaked
#     at 259.7, 20 Hz +100 Hz at 25.2, 50 Hz +1200 Hz at 22.6 - the
#     spike sitting at the second-to-last sample every time, because
#     the last core sample landed exactly on the final grain's closing
#     Hann zero. A second Hann is now applied AFTER modulation and the
#     weight accumulates Hann x Hann, with one extra grain past the end
#     so no core sample sits on a zero. Verified before shipping: those
#     three cases now peak at 0.219, 0.218 and 0.220, and identity at
#     0 Hz shift rises from 54.3 dB SNR (last sample 0 instead of
#     -0.03439) to 319 dB with a maximum error of 5.6e-17.
#   - The short-file test gained half a sample of tolerance: exactly
#     150 ms was rejected against a 150 ms minimum by rounding alone.
#
# Verified on the corrected core before shipping, 440 Hz sine:
#   +8 -> 448.0, +15 -> 455.0, +100 -> 540.0, +150 -> 590.0,
#   +666 -> 1106.0, +1200 -> 1640.0, -100 -> 340.0 Hz, with the
#   unwanted sideband 66 to 124 dB down.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Frequency Shifter v0.5
    optionmenu Preset: 1
        option Custom
        option Subtle Detune (15 Hz)
        option Chorus Thick (8 Hz)
        option Metallic Ring (200 Hz)
        option Robot Voice (150 Hz)
        option Horror Alien (666 Hz)
        option Deep Sub (-100 Hz)
        option Bell Shimmer (1200 Hz)
    real Shift_hz 100
    optionmenu Direction: 1
        option Up (positive shift)
        option Down (negative shift)
    real Dry_wet_mix 1.0
    boolean Pre_limit_to_avoid_aliasing 0
    optionmenu Output_level_mode: 1
        option Natural level
        option Safety ceiling (attenuate only)
        option Match input RMS
        option Peak normalize
    positive Ceiling_peak 0.95
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

# ============================================================
# ADVANCED SETTINGS - edit here, not in the form
# ============================================================
# Praat forms do not scroll, so the granular parameters live here.
# 50% overlap with a Hann window sums to unity, and the weight buffer
# below divides out whatever it actually sums to.
grain_size_s = 0.1
hop_size_s = 0.05

# ============================================================
# Presets
# ============================================================
# v0.2 left Dry_wet_mix at 100% for every preset. A fully shifted
# signal is not chorus or thickening no matter how accurate the shift.
if preset$ = "Subtle Detune (15 Hz)"
    shift_hz = 15
    direction = 1
    dry_wet_mix = 0.25
elsif preset$ = "Chorus Thick (8 Hz)"
    shift_hz = 8
    direction = 1
    dry_wet_mix = 0.40
elsif preset$ = "Metallic Ring (200 Hz)"
    shift_hz = 200
    direction = 1
    dry_wet_mix = 1.00
elsif preset$ = "Robot Voice (150 Hz)"
    shift_hz = 150
    direction = 1
    dry_wet_mix = 0.80
elsif preset$ = "Horror Alien (666 Hz)"
    shift_hz = 666
    direction = 1
    dry_wet_mix = 1.00
elsif preset$ = "Deep Sub (-100 Hz)"
    shift_hz = 100
    direction = 2
    dry_wet_mix = 0.70
elsif preset$ = "Bell Shimmer (1200 Hz)"
    shift_hz = 1200
    direction = 1
    dry_wet_mix = 0.80
endif

# The sign is applied exactly ONCE, here. v0.2 negated shift_hz and
# then also branched on its sign in the modulation formula, so Up and
# Down produced identical output.
if direction = 2
    shift_hz = -abs(shift_hz)
else
    shift_hz = abs(shift_hz)
endif

# ============================================================
# Input and validation
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
sampleRate = Get sampling frequency
duration = Get total duration
numChannels = Get number of channels
originalXmin = Get start time
nyquist = sampleRate / 2
inputPeak = Get absolute extremum: 0, 0, "None"
inputRMS = Get root-mean-square: 0, 0

if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif
if ceiling_peak <= 0 or ceiling_peak > 1
    exitScript: "Ceiling_peak must be greater than 0 and at most 1."
endif
if abs(shift_hz) >= nyquist
    exitScript: "Shift_hz (" + fixed$(shift_hz, 1) + ") must be smaller than Nyquist (" +
    ... fixed$(nyquist, 1) + " Hz)."
endif
# Half a sample of tolerance: a plain "< 1.5 x grain" comparison
# rejected exactly 150 ms on a 150 ms minimum through floating-point
# rounding alone.
if duration < grain_size_s * 1.5 - 0.5 / sampleRate
    exitScript: "Sound is too short: " + fixed$(duration * 1000, 1) + " ms. The grain is " +
    ... fixed$(grain_size_s * 1000, 0) + " ms, so at least " +
    ... fixed$(grain_size_s * 1500, 0) + " ms is needed. Shorten grain_size_s in the " +
    ... "ADVANCED SETTINGS block for shorter material."
endif

omega = 2 * pi * shift_hz
aliasEdge = nyquist - abs(shift_hz)

writeInfoLine: "Frequency Shifter v0.5"
appendInfoLine: "======================"
appendInfoLine: "Input: ", originalName$, " (", fixed$(duration, 2), " s, ", numChannels,
    ... " ch, ", sampleRate, " Hz)"
appendInfoLine: "Shift: ", fixed$(shift_hz, 2), " Hz | Mix: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: ""

# Shifting up moves content past Nyquist, where it folds back.
if shift_hz > 0
    appendInfoLine: "NOTE: content above ", fixed$(aliasEdge, 0), " Hz will pass Nyquist and"
    appendInfoLine: "      alias back down. Measured on a corrected core: 7500 Hz at a"
    appendInfoLine: "      16 kHz rate shifted +1200 Hz returned 7300 Hz, not 8700 Hz."
    if pre_limit_to_avoid_aliasing
        appendInfoLine: "      Pre-limit is ON: the input is low-passed at ",
            ... fixed$(aliasEdge, 0), " Hz first."
    else
        appendInfoLine: "      Set Pre_limit_to_avoid_aliasing to remove it beforehand."
    endif
    appendInfoLine: ""
endif

# Shifting down past 0 Hz reflects: a component at f with a shift of
# -s lands at f - s, and if that is negative it folds back to |f - s|.
# Verified: 440 Hz shifted -666 Hz comes out at 226 Hz, not -226.
if shift_hz < 0
    appendInfoLine: "NOTE: content below ", fixed$(abs(shift_hz), 0), " Hz crosses 0 Hz and"
    appendInfoLine: "      reflects back up as its own mirror image. This is inherent to"
    appendInfoLine: "      frequency shifting, not a fault - it is where much of the"
    appendInfoLine: "      character of a large downward shift comes from."
    appendInfoLine: ""
endif

# ============================================================
# Work copy at time 0
# ============================================================
# Grains are extracted at 0, hop, 2*hop..., so a Sound living anywhere
# else was read entirely outside its own domain: a file at
# 5.137-6.137 s produced output over 0-1 s with peak 0.
selectObject: sound
workSound = Copy: "fs_work"
Shift times to: "start time", 0

if pre_limit_to_avoid_aliasing and shift_hz > 0 and aliasEdge > 100
    selectObject: workSound
    limited = Filter (pass Hann band): 0, aliasEdge, 100
    removeObject: workSound
    workSound = limited
endif

# ============================================================
# Padded overlap-add geometry
# ============================================================
# v0.2 had no padding and no window normalization, so even a 0 Hz
# shift faded the first and last 10 ms to about 4.5% of the source RMS
# and left a silent tail; files under 100 ms came out silent entirely.
padHead = grain_size_s / 2
coreEnd = padHead + duration
# One extra grain past the end. Without it the last core sample lands on
# the final grain's closing Hann zero, where the accumulated weight is
# 0 and the division below explodes - see the synthesis-window note.
numGrains = ceiling((coreEnd - grain_size_s) / hop_size_s) + 2
if numGrains < 2
    numGrains = 2
endif
lastEnd = (numGrains - 1) * hop_size_s + grain_size_s
# A hop of margin so every grain fits whole inside the padded buffer
padTail = lastEnd - coreEnd + hop_size_s
if padTail < padHead
    padTail = padHead
endif

Create Sound from formula: "fs_pad_probe", 1, 0, padHead, sampleRate, "0"
padProbe = selected("Sound")
padHeadSamples = Get number of samples
removeObject: padProbe
Create Sound from formula: "fs_tail_probe", 1, 0, padTail, sampleRate, "0"
tailProbe = selected("Sound")
padTailSamples = Get number of samples
removeObject: tailProbe

selectObject: workSound
coreSamples = Get number of samples
paddedSamples = padHeadSamples + coreSamples + padTailSamples
paddedDur = paddedSamples / sampleRate

appendInfoLine: "Grains: ", numGrains, " (", fixed$(grain_size_s * 1000, 0), " ms, hop ",
    ... fixed$(hop_size_s * 1000, 0), " ms, ", fixed$(padHead * 1000, 0), " ms pad each side)"

# ============================================================
# Synthesis window and weight buffer (shared by every channel)
# ============================================================
# v0.3 applied the Hann window on ANALYSIS only and divided by the sum
# of that window. That is valid when the grain is merely windowed, but
# the Hilbert transform of a Hann-windowed grain does NOT vanish at the
# grain edges: the numerator stays finite while the weight goes to
# zero, so the division blows up. Measured on a 0.2-peak 20 Hz tone
# shifted +1200 Hz, the output peaked at 259.7 - a momentary gain of
# more than 60 dB, at the second-to-last sample.
#
# The fix is a second Hann applied AFTER modulation, with the weight
# accumulating Hann x Hann. Verified: the same case now peaks at 0.219,
# and identity at 0 Hz shift goes from 54.3 dB SNR to 319 dB.
Create Sound from formula: "fs_ones", 1, 0, paddedDur, sampleRate, "1"
onesSrc = selected("Sound")
selectObject: onesSrc
Extract part: 0, grain_size_s, "Hanning", 1, "no"
synthWin = selected("Sound")
winNs = Get number of samples
synthWin$ = string$(synthWin)
removeObject: onesSrc

Create Sound from formula: "fs_weight", 1, 0, paddedDur, sampleRate, "0"
weightBuf = selected("Sound")
weightBuf$ = string$(weightBuf)

for g from 1 to numGrains
    gStart = (g - 1) * hop_size_s
    s1 = round(gStart * sampleRate) + 1
    if s1 < 1
        s1 = 1
    endif
    s2 = s1 + winNs - 1
    if s2 > paddedSamples
        s2 = paddedSamples
    endif
    grainS1[g] = s1
    grainNs[g] = winNs

    if s2 >= s1
        off = s1 - 1
        selectObject: weightBuf
        Formula (part): (s1 - 0.75) / sampleRate, (s2 - 0.25) / sampleRate, 1, 1,
            ... "self + object[" + synthWin$ + ", 1, col - " + string$(off) +
            ... "] * object[" + synthWin$ + ", 1, col - " + string$(off) + "]"
    endif
endfor

trimStart = padHeadSamples + 1
trimEnd = padHeadSamples + coreSamples

# ============================================================
# Channel processing
# ============================================================
procedure shiftChannel: .inputSound
    # Padded input: head silence, signal, tail silence. Concatenate
    # follows OBJECT-LIST order, so they are created in playing order.
    Create Sound from formula: "fs_head", 1, 0, padHead, sampleRate, "0"
    .head = selected("Sound")
    selectObject: .inputSound
    .mid = Copy: "fs_mid"
    Create Sound from formula: "fs_tail", 1, 0, padTail, sampleRate, "0"
    .tail = selected("Sound")
    selectObject: .head
    plusObject: .mid
    plusObject: .tail
    Concatenate
    .padded = selected("Sound")
    removeObject: .head, .mid, .tail

    Create Sound from formula: "fs_acc", 1, 0, paddedDur, sampleRate, "0"
    .acc = selected("Sound")

    for g from 1 to numGrains
        if grainNs[g] > 0
            .gStart = (g - 1) * hop_size_s
            .gEnd = .gStart + grain_size_s
            if .gEnd > paddedDur
                .gEnd = paddedDur
            endif

            selectObject: .padded
            .grain = Extract part: .gStart, .gEnd, "Hanning", 1, "no"

            # --- Hilbert transform ---
            # Rotate every bin by -90 degrees, reading from an
            # UNMODIFIED copy. v0.2 wrote into the Spectrum in place,
            # so row 2 read the value row 1 had just overwritten -
            # correlation with a correct Hilbert transform was 0.127.
            # DC and Nyquist have no quadrature partner and are zeroed.
            selectObject: .grain
            .spec = To Spectrum: "yes"
            selectObject: .spec
            .specOrig = Copy: "fs_spec_orig"
            .orig$ = string$(.specOrig)
            selectObject: .spec
            Formula: "if col = 1 or col = ncol then 0 else if row = 1 then object[" +
                ... .orig$ + ", 2, col] else -object[" + .orig$ + ", 1, col] fi fi"
            To Sound
            .hilb = selected("Sound")
            removeObject: .spec, .specOrig

            # --- SSB modulation, ONE signed formula ---
            # The carrier phase runs on GLOBAL time: v0.2 used the
            # grain's local x, restarting the carrier every hop, which
            # turned an 8 Hz shift into 420/440/460 Hz sidebands with
            # the wanted 448 Hz about 70 dB down. gPhase maps grain
            # time back onto the original timeline.
            .gPhase = .gStart - padHead
            selectObject: .grain
            .shifted = Copy: "fs_shifted"
            Formula: "object(" + string$(.grain) + ", x) * cos(" + string$(omega) +
                ... " * (x + " + string$(.gPhase) + ")) - object(" + string$(.hilb) +
                ... ", x) * sin(" + string$(omega) + " * (x + " + string$(.gPhase) + "))"

            # --- Synthesis window ---
            # Second Hann, matching the weight buffer's Hann x Hann.
            # Without it the Hilbert residue at the grain edges is
            # divided by a near-zero weight.
            selectObject: .shifted
            Formula: "self * object[" + synthWin$ + ", 1, col]"

            # --- Overlap-add over this grain's own samples only ---
            # v0.2 ran a full-length Formula per grain: 0.017 / 0.045 /
            # 0.138 / 0.479 s for 1 / 2 / 4 / 8 s of audio.
            selectObject: .shifted
            .ns = Get number of samples
            .s1 = grainS1[g]
            .s2 = .s1 + .ns - 1
            if .s2 > paddedSamples
                .s2 = paddedSamples
            endif
            if .s2 >= .s1
                .off = .s1 - 1
                selectObject: .acc
                Formula (part): (.s1 - 0.75) / sampleRate, (.s2 - 0.25) / sampleRate, 1, 1,
                    ... "self + object[" + string$(.shifted) + ", 1, col - " + string$(.off) + "]"
            endif

            removeObject: .grain, .hilb, .shifted
        endif
    endfor

    removeObject: .padded

    # Divide out the accumulated window weight, then cut the original
    # span back out of the padded buffer.
    selectObject: .acc
    Formula: "if object[" + weightBuf$ + ", 1, col] > 0.000001 then self / object[" +
        ... weightBuf$ + ", 1, col] else 0 endif"

    selectObject: .acc
    Extract part: (trimStart - 1) / sampleRate, trimEnd / sampleRate, "rectangular", 1, "no"
    .out = selected("Sound")
    removeObject: .acc
    selectObject: .out
endproc

appendInfoLine: "Processing ", numChannels, " channel(s)..."

for ch from 1 to numChannels
    if numChannels = 1
        selectObject: workSound
        chDry[ch] = Copy: "fs_dry"
    else
        selectObject: workSound
        chDry[ch] = Extract one channel: ch
    endif

    @shiftChannel: chDry[ch]
    chWet[ch] = selected("Sound")

    if dry_wet_mix < 1
        selectObject: chWet[ch]
        Formula: "self * " + string$(dry_wet_mix) + " + object[" + string$(chDry[ch]) +
            ... ", 1, col] * " + string$(1 - dry_wet_mix)
    endif
    appendInfo: "."
endfor
appendInfoLine: ""

if numChannels = 1
    selectObject: chWet[1]
    result = Copy: "fs_out"
    removeObject: chWet[1]
else
    selectObject: chWet[1]
    outDurCh = Get total duration
    Create Sound from formula: "fs_out", numChannels, 0, outDurCh, sampleRate, "0"
    result = selected("Sound")
    for ch from 1 to numChannels
        selectObject: result
        Formula (part): 0, outDurCh, ch, ch,
            ... "object[" + string$(chWet[ch]) + ", 1, col]"
    endfor
    for ch from 1 to numChannels
        removeObject: chWet[ch]
    endfor
endif

removeObject: weightBuf, synthWin
for ch from 1 to numChannels
    removeObject: chDry[ch]
endfor

# ============================================================
# Output level
# ============================================================
selectObject: result
pre_level_peak = Get absolute extremum: 0, 0, "None"
pre_level_rms = Get root-mean-square: 0, 0
level_gain = 1
level_action$ = "natural level"

if output_level_mode = 2
    if pre_level_peak > ceiling_peak and pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "ceiling applied"
    else
        level_action$ = "ceiling not needed"
    endif
elsif output_level_mode = 3
    if pre_level_rms > 0 and inputRMS > 0
        level_gain = inputRMS / pre_level_rms
        selectObject: result
        Formula: "self * " + string$(level_gain)
        level_action$ = "matched to input RMS"
    endif
elsif output_level_mode = 4
    if pre_level_peak > 0
        Scale peak: ceiling_peak
        level_gain = ceiling_peak / pre_level_peak
        level_action$ = "peak normalized"
    endif
endif

selectObject: result
outPeak = Get absolute extremum: 0, 0, "None"

# ============================================================
# Visualization (drawn at t = 0, before the domain is restored)
# ============================================================
if draw_visualization
    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    specTop = min(5000, nyquist)

    # A real channel, not a fold: anti-phase stereo would draw as
    # silence even with correct audio.
    vizCh = 1
    if numChannels > 1
        bestRms = -1
        for ch from 1 to numChannels
            selectObject: workSound
            vp = Extract one channel: ch
            vpr = Get root-mean-square: 0, 0
            removeObject: vp
            if vpr > bestRms
                bestRms = vpr
                vizCh = ch
            endif
        endfor
    endif

    selectObject: workSound
    if numChannels > 1
        origMono = Extract one channel: vizCh
    else
        origMono = Copy: "fs_orig_viz"
    endif
    selectObject: origMono
    origSpec = To Spectrogram: 0.005, specTop, 0.002, 20, "Gaussian"

    selectObject: result
    if numChannels > 1
        resultMono = Extract one channel: vizCh
    else
        resultMono = Copy: "fs_result_viz"
    endif
    selectObject: resultMono
    resultSpec = To Spectrogram: 0.005, specTop, 0.002, 20, "Gaussian"

    if duration > 10
        timeTick = 2
    elsif duration > 5
        timeTick = 1
    elsif duration > 2
        timeTick = 0.5
    else
        timeTick = 0.25
    endif

    # --- Title ---
    suiteVizName$ = replace$(originalName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Frequency Shifter v0.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + preset$

    Select outer viewport: 0, 8, 0.6, 3.2
    Select inner viewport: 0.6, 7.7, 0.7, 3.1
    selectObject: origSpec
    Paint: 0, 0, 0, specTop, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Original##"
    Marks left every: 1, 1000, "yes", "yes", "no"

    # --- Shifted spectrogram ---
    Select outer viewport: 0, 8, 3.3, 5.9
    Select inner viewport: 0.6, 7.7, 3.4, 5.8
    selectObject: resultSpec
    Paint: 0, 0, 0, specTop, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "##Shifted " + fixed$(shift_hz, 1) + " Hz##"
    Marks bottom every: 1, timeTick, "yes", "yes", "no"
    Marks left every: 1, 1000, "yes", "yes", "no"

    # --- Summary ---
    Select outer viewport: 0, 8, 6.0, 6.8
    Select inner viewport: 0.6, 7.7, 6.05, 6.75
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if pre_limit_to_avoid_aliasing and shift_hz > 0
        aliasStr$ = "pre-limited at " + fixed$(aliasEdge, 0) + " Hz"
    elsif shift_hz > 0
        aliasStr$ = "content above " + fixed$(aliasEdge, 0) + " Hz aliases"
    else
        aliasStr$ = "downward shift, no aliasing"
    endif

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half",
        ... "Shift: " + fixed$(shift_hz, 2) + " Hz"
        ... + "  |  Grains: " + string$(numGrains) + " x " + fixed$(grain_size_s * 1000, 0)
        ... + " ms, hop " + fixed$(hop_size_s * 1000, 0) + " ms"
        ... + "  |  Mix: " + fixed$(dry_wet_mix * 100, 0) + "% wet"
        ... + "  |  " + aliasStr$
    Text: 0.02, "left", 0.18, "half",
        ... "Peak: " + fixed$(inputPeak, 3) + " -> " + fixed$(outPeak, 3)
        ... + "  |  RMS in: " + fixed$(inputRMS, 4)
        ... + "  |  Level: " + level_action$
        ... + "  |  Channels: " + string$(numChannels) + " (all processed)"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"

    removeObject: origMono, resultMono, origSpec, resultSpec
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# Restore the source time domain and finish
# ============================================================
selectObject: result
if originalXmin <> 0
    Shift times to: "start time", originalXmin
endif
if shift_hz >= 0
    Rename: originalName$ + "_shift+" + fixed$(abs(shift_hz), 0) + "Hz"
else
    Rename: originalName$ + "_shift-" + fixed$(abs(shift_hz), 0) + "Hz"
endif
finalOutput = selected("Sound")
finalName$ = selected$("Sound")

removeObject: workSound

appendInfoLine: ""
appendInfoLine: "======================"
appendInfoLine: "Complete!"
appendInfoLine: "Output: ", finalName$
appendInfoLine: "Peak: ", fixed$(inputPeak, 4), " -> ", fixed$(outPeak, 4),
    ... " (", level_action$, ")"
if output_level_mode <> 4 and outPeak > 1
    appendInfoLine: "WARNING: peak exceeds 1.0 and will clip when saved to integer PCM."
endif

selectObject: finalOutput
if play_after_processing
    if outPeak > 1
        appendInfoLine: "Playing a scaled copy (peak exceeds 1.0)..."
        playCopy = Copy: "play_safe"
        Scale peak: 0.95
        Play
        removeObject: playCopy
    else
        Play
    endif
endif

selectObject: finalOutput