# ============================================================
# Praat AudioTools - Multiband_Distortion.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5b (2026) - deterministic presets, validation, output policy
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Multiband Distortion - splits audio into Low, Mid, and High
#   frequency bands. Applies independent distortion type and drive
#   to each band (soft clip, hard clip, or sine waveshaper).
#   Recombines using phase-coherent subtraction logic.
#
#   The split is complementary by construction:
#     Low = LP(lowSplit); Mid = LP(highSplit) - Low; High = x - LP(highSplit)
#   so Low + Mid + High reconstructs the input exactly (measured residual
#   about 2.2e-16 with identity waveshaping).
#
#   PRE-RINGING: Praat's Hann band filter works in the frequency domain
#   with a symmetric impulse response and zero phase, so it is ACAUSAL -
#   energy appears BEFORE a transient. With identity processing the bands
#   sum back and those components cancel; once each band is waveshaped
#   differently the cancellation is no longer exact and the pre-ringing
#   becomes audible around transients. Measured on an impulse with the
#   Frizz preset: 0.227 maximum amplitude before the event. This is
#   inherent to a zero-phase crossover, not a defect, but it is a real
#   property of the tool.
#
#   ANTI-ALIASING: oversampling reduces aliasing substantially (a 10 kHz
#   sine hard-clipped showed a strong alias near 14.1 kHz without it, and
#   far below that at 4x), but "alias-reduced" is the accurate term - the
#   processing is not alias-free.
#
# Changelog v0.5b:
#   Both code fixes are v0.5 regressions.
#   - FIXED: the near-silence guard wrapped the Output_Gain multiply as
#     well as the normalization, so below the 1e-9 threshold the master
#     trim silently stopped working - a source peaking at 1e-12 came out
#     at 1e-12 whether the gain was 0.5 or 2.0. The guard exists to
#     prevent dangerous normalization, not to disable level control; the
#     gain is now applied on both paths.
#   - FIXED: Drive_compensation broke at exactly Drive = 0. The division
#     guard `drive <> 0` fell back to the UNcompensated scales, setting
#     inScale = 0 and silencing the band, whereas the limit as drive -> 0
#     is linear output (tanh(x*d/pk) * gain*pk/d -> x*gain). A drive of
#     1e-12 reconstructed the input correctly while a drive of 0 gave
#     silence - a full discontinuity, contradicting the form's own "drive
#     changes shape only, not band level". Now a separate branch that
#     bypasses the waveshaper.
#   - Oversample = 2 is now REFUSED rather than warned about. The phase
#     offset was reproduced on Praat 6.1.38 (correlation 0.99937 at
#     1 kHz, 0.93722 at 10 kHz, 0.75676 at 20 kHz), and a warning does
#     not stop a tainted render at partial Mix. The check is a single
#     block, marked so it can be deleted once the behaviour is confirmed
#     fixed on the Praat version being targeted.
#   - Output mode 3 renamed "normalize if peak exceeds 0.95" - it is not
#     a clipping test, and a peak of 0.97 is not clipped but was
#     normalized.
#   - The applyDistortion comment still claimed drive "engages regardless
#     of how quiet the band is", contradicting the header and report that
#     v0.5 had just corrected. Rewritten.
#   - "All six presets" corrected to five named presets; Manual sets
#     nothing.
#   - A negative BAND gain is now reported: it inverts one band relative
#     to the others, so the crossover no longer reconstructs.
#   - The negative-Drive note distinguishes compensation on from off -
#     with an odd waveshaper and compensation ON the sign appears in both
#     scales and cancels, so the band is not actually inverted.
#
# Changelog v0.5:
#   This round follows a review that RAN every preset, every distortion
#   type, mono/stereo/4-channel, silence, non-zero start times,
#   oversampling 1-8, out-of-range crossovers and an impulse test.
#
#   BLOCKERS FIXED:
#   - Presets were not deterministic. Each set only some of the band
#     parameters and left the rest at whatever the form held, so the same
#     preset on the same input could give a different effect run to run -
#     measured maximum sample differences of 0.5755 (Warm Bass) and
#     0.5788 (V-Shape). All five named presets now set both crossovers, all
#     three drives, all three types and all three gains (Manual is not a
#     preset and sets nothing, so that is five named presets, not six as
#     the v0.5 note said). Master controls
#     (Mix, Output_Gain, Output_mode, Oversample, Normalize_drive) stay
#     with the user, since they are global rather than part of the
#     preset's identity.
#   - Mix = 0 was not a dry bypass. `Scale peak: 0.95` ran unconditionally,
#     so a source peaking at 0.1 came out at 0.855 with zero wet signal -
#     an 8.55x boost. Any non-zero peak landed on the same level, so
#     inputs peaking at 1e-15, 1e-12, 1e-6 and 0.1 all produced 0.855:
#     numerical noise became a full-scale signal. Output_mode makes the
#     policy explicit (mode 1 is the v0.4 behaviour) and a near-silence
#     guard stops normalization of what is only numerical noise.
#   - Mix_0_to_1 was unchecked. Values >= 1 read as fully wet, but
#     negative values extrapolated - Mix = -0.5 computes 1.5*dry -
#     0.5*wet. Now validated to 0..1.
#   - Crossover validation was one test (`low >= high`) whose "repair"
#     could invent negative frequencies: Low 200 / High -100 became
#     Low -101 / High 201, reported as "Low (< -101 Hz)". Nothing checked
#     zero, Nyquist (Low 30000 / High 40000 at 44.1 kHz was accepted) or
#     the filters' 20 Hz transition width (Low 1000 / High 1001 gave a
#     1 Hz mid band). Now refused with a specific message instead of
#     silently repaired.
#
#   DSP AND REPORTING:
#   - Drive_compensation (off by default). In normalized mode the linear
#     region gives out = in * drive * gain, so drive was multiplying the
#     band's LEVEL as well as setting how hard it hits the nonlinearity -
#     and since each band has its own drive, the spectral balance moved
#     too. v0.4's "restored on the way out" was true of the peak scale
#     but not of the drive.
#   - Normalize_drive is described accurately. It normalizes from ONE
#     whole-file absolute peak per band, so a single transient sets the
#     gain staging for the entire file: with an impulse of 1 followed by
#     a sine at 0.01, the quiet part stayed perfectly linear
#     (correlation 1.0, residual ~0) and distorted heavily once the
#     impulse was removed. The v0.4 claim that drive "distorts regardless
#     of how quiet the band is" was too strong.
#   - The same peak covers the whole multichannel object, so drive
#     normalization is LINKED across channels - stereo with L at 1.0 and
#     R at 0.01 left R nearly linear. Right for a stereo pair, worth
#     knowing for unrelated multichannel material. Now stated in the
#     report.
#   - RENAMED "Sine Fold" to "Sine Waveshaper". sin(x) is monotonic until
#     |x| passes pi/2 = 1.5708, so at normalized drive 1 the argument
#     spans only +/-1 rad and nothing folds at all; folding starts above
#     about 1.571.
#   - The report now covers Normalize_drive, drive compensation, the
#     effective oversample, Mix, Output_Gain, source peak, wet peak,
#     pre-output peak, which output policy ran, the measured output peak,
#     and a warning above full scale. Oversample clamping is reported
#     (a requested 20 silently ran as 8).
#   - Oversample = 2 now warns: a reviewer measured a frequency-dependent
#     phase offset of about a quarter sample from the 2x round trip on
#     Praat 6.1.38 (correlation 0.937 at 10 kHz, 0.757 at 20 kHz), which
#     matters most at partial Mix. 3x and above were clean. Not removed,
#     since this needs confirming on current Praat.
#   - Negative Drive and Output_Gain are noted rather than silently
#     inverting polarity.
#   - Visualization_max_Hz replaces the hardcoded 8 kHz display ceiling,
#     which hid crossovers set above it.
#   - Header documents the zero-phase crossover's pre-ringing (0.227
#     before an impulse with the Frizz preset) and uses "alias-reduced"
#     rather than implying alias-free processing.
#
# Changelog v0.2:
#   - Modern procedure call syntax (@)
#   - Enhanced visualization with band indicators
#   - Improved info output
#
# Changelog v0.3:
#   - Oversampled (anti-aliased) processing: the band split + per-band
#     nonlinearities + sum now run at an integer multiple of the sample rate,
#     then the wet sum is resampled back. Praat's downsampling resampler
#     band-limits, removing the harmonics that otherwise fold back as aliasing
#     (worst on hard-clip / sine-fold at high drive on high-frequency content).
#   - Output_Gain now applies AFTER peak-normalization, so it is an effective
#     master trim at any Mix (previously the final Scale peak cancelled it at
#     Mix = 1).
#
# Changelog v0.4:
#   - Normalize_drive (default on): each band is scaled into the waveshaper by
#     its own peak before 'drive' is applied, then restored on the way out - so
#     drive distorts regardless of how quiet the band is. Previously the split
#     left bands too low to engage the nonlinearity, so the effect was mostly a
#     filter (e.g. hard clip at drive 3 on a band produced zero harmonics).
#     Toggle off for the legacy level-dependent behaviour.
#   - Preset drive values re-tuned for the normalized (much hotter) response.
# ============================================================

# === Form ===
form Multiband Distortion v0.5b
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Manual (use settings below)
        option Warm Bass / Clean Highs
        option Frizz (Distorted Highs Only)
        option V-Shape Destruction
        option Mid-Range Crunch (Telephone)
        option Full Spectrum Fuzz

    comment === Crossovers ===
    real Low_Split_Hz 200
    real High_Split_Hz 2500

    comment === Drive normalizes into the waveshaper (off = legacy level-dependent) ===
    boolean Normalize_drive 1

    comment === Low Band ===
    real Low_Drive 1.0
    optionmenu Low_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Waveshaper
    real Low_Gain 1.0

    comment === Mid Band ===
    real Mid_Drive 1.0
    optionmenu Mid_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Waveshaper
    real Mid_Gain 1.0

    comment === High Band ===
    real High_Drive 1.0
    optionmenu High_Type 1
        option Soft Clip (Tanh)
        option Hard Clip
        option Sine Waveshaper
    real High_Gain 1.0

    comment === Master ===
    real Mix_0_to_1 1.0
    real Output_Gain 0.9
    optionmenu Output_mode: 1
        option Normalize to 0.95, then output gain (v0.3/v0.4)
        option Preserve level (output gain only)
        option Output gain, normalize if peak exceeds 0.95
    boolean Drive_compensation 0
    comment (on: drive changes shape only, not band level)

    comment === Anti-aliasing (oversample factor; 1 = off) ===
    integer Oversample 4

    comment === Output ===
    positive Visualization_max_Hz 8000
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
origName$ = selected$("Sound")

selectObject: original
xmin = Get start time
xmax = Get end time
duration = Get total duration
sr = Get sampling frequency

# === Handle Presets ===
# v0.5 CRITICAL: v0.4's presets set only SOME of the band parameters and left
# the rest at whatever the form happened to hold, so the same preset on the
# same input could produce a completely different effect from one run to the
# next. Verified by the reviewer: selecting Warm Bass twice with different
# leftover gains and crossovers gave a maximum sample difference of 0.5755
# (RMS 0.2853), and V-Shape reached 0.5788. That is a different effect, not a
# variation. All five NAMED presets now set all eleven band parameters - both
# crossovers, three drives, three types, three gains - so a preset is
# reproducible. Master controls (Mix, Output_Gain, Output_mode, Oversample,
# Normalize_drive, Drive_compensation) stay under the user's hand, since those
# are global and not part of the preset's identity.
if preset = 1
    presetName$ = "Manual"
elsif preset = 2
    presetName$ = "WarmBass"
    low_Split_Hz = 200
    high_Split_Hz = 2500
    low_Drive = 2.0
    low_Type = 1
    low_Gain = 1.1
    mid_Drive = 1.0
    mid_Type = 1
    mid_Gain = 1.0
    high_Drive = 0.8
    high_Type = 1
    high_Gain = 1.0
elsif preset = 3
    presetName$ = "Frizz"
    low_Split_Hz = 200
    high_Split_Hz = 1500
    low_Drive = 1.0
    low_Type = 1
    low_Gain = 1.0
    mid_Drive = 1.0
    mid_Type = 1
    mid_Gain = 1.0
    high_Drive = 3.5
    high_Type = 2
    high_Gain = 1.0
elsif preset = 4
    presetName$ = "VShape"
    low_Split_Hz = 200
    high_Split_Hz = 2500
    low_Drive = 2.5
    low_Type = 2
    low_Gain = 1.0
    mid_Drive = 1.0
    mid_Type = 1
    mid_Gain = 0.7
    high_Drive = 2.5
    high_Type = 2
    high_Gain = 1.0
elsif preset = 5
    presetName$ = "MidCrunch"
    low_Split_Hz = 400
    high_Split_Hz = 3000
    low_Drive = 0.6
    low_Type = 1
    low_Gain = 0.5
    mid_Drive = 3.0
    mid_Type = 3
    mid_Gain = 1.2
    high_Drive = 0.6
    high_Type = 1
    high_Gain = 0.5
elsif preset = 6
    presetName$ = "FullFuzz"
    low_Split_Hz = 200
    high_Split_Hz = 2500
    low_Drive = 3.0
    low_Type = 2
    low_Gain = 1.0
    mid_Drive = 3.0
    mid_Type = 2
    mid_Gain = 1.0
    high_Drive = 3.0
    high_Type = 2
    high_Gain = 1.0
endif

# === Validation ===
# v0.5 CRITICAL: v0.4's only crossover check was `low >= high`, and its
# "repair" swapped-and-nudged the values, which could invent NEGATIVE
# frequencies - verified: entering Low 200 / High -100 produced Low -101 and
# High 201, and the report printed "Low (< -101 Hz)". Nothing checked against
# zero, against Nyquist (Low 30000 / High 40000 at 44.1 kHz was accepted
# whole), or against the filters' own 20 Hz transition width (Low 1000 /
# High 1001 gave a 1 Hz mid band narrower than the smoothing that defines
# it). Refused with a clear message rather than silently repaired, since a
# silent repair is what produced the negative-frequency case.
nyquist = sr / 2
minGap = 40

if low_Split_Hz <= 0
    exitScript: "Low_Split_Hz must be above 0 (got " + fixed$(low_Split_Hz, 1) + " Hz)."
endif
if high_Split_Hz >= nyquist
    exitScript: "High_Split_Hz (" + fixed$(high_Split_Hz, 1)
        ... + " Hz) must be below the Nyquist frequency (" + fixed$(nyquist, 1) + " Hz)."
endif
if low_Split_Hz >= high_Split_Hz
    exitScript: "Low_Split_Hz (" + fixed$(low_Split_Hz, 1) + " Hz) must be below High_Split_Hz ("
        ... + fixed$(high_Split_Hz, 1) + " Hz)."
endif
if high_Split_Hz - low_Split_Hz < minGap
    exitScript: "The crossovers are " + fixed$(high_Split_Hz - low_Split_Hz, 1)
        ... + " Hz apart, but each Hann filter has a 20 Hz transition width, so the mid band would be "
        ... + "narrower than the smoothing that defines it. Leave at least " + string$(minGap) + " Hz."
endif

# v0.5 CRITICAL: Mix_0_to_1 is a `real` with no check. Values at or above 1
# were treated as fully wet, but NEGATIVE values fell through into the mixing
# formula and extrapolated - Mix = -0.5 computes 1.5*dry - 0.5*wet, which is
# neither a mix nor anything the field name suggests.
if mix_0_to_1 < 0 or mix_0_to_1 > 1
    exitScript: "Mix_0_to_1 must be between 0 and 1 (got " + fixed$(mix_0_to_1, 3) + ")."
endif

# v0.5: oversample clamping is now reported. v0.4 silently ran a requested 20
# as 8 with nothing in the Info window to say so.
osNote$ = ""
oversampleReq = oversample
if oversample < 1
    oversample = 1
endif
if oversample > 8
    oversample = 8
endif
if oversample <> oversampleReq
    osNote$ = "  NOTE: Oversample " + string$(oversampleReq) + " is outside the supported range 1-8; running at " + string$(oversample) + "." + newline$
endif
# v0.5b: 2x is refused rather than warned about. The 2x round trip was
# measured twice on Praat 6.1.38 to introduce a frequency-dependent phase
# offset of about a quarter sample - correlation with the source 0.99937 at
# 1 kHz, 0.93722 at 10 kHz, 0.75676 at 20 kHz - and at partial Mix the
# shifted wet sums with unshifted dry and comb-filters the highs. A warning
# does not stop the tainted render, and silently substituting another factor
# would be the kind of quiet repair that produced the negative-crossover bug.
# 3x and above measured clean. If this is confirmed fixed on the Praat
# version you target, delete this block - it is the only thing blocking 2x.
if oversample = 2
    exitScript: "Oversample = 2 is disabled. The 2x round trip introduces a frequency-dependent phase offset "
        ... + "(measured correlation with the source: 0.99937 at 1 kHz, 0.93722 at 10 kHz, 0.75676 at 20 kHz on "
        ... + "Praat 6.1.38), which comb-filters the high end at partial Mix. Use 1 (off), or 3 and above - "
        ... + "4 is the default and measured clean."
endif

# Get type names
if low_Type = 1
    lowTypeName$ = "Soft"
elsif low_Type = 2
    lowTypeName$ = "Hard"
else
    lowTypeName$ = "Sine"
endif

if mid_Type = 1
    midTypeName$ = "Soft"
elsif mid_Type = 2
    midTypeName$ = "Hard"
else
    midTypeName$ = "Sine"
endif

if high_Type = 1
    highTypeName$ = "Soft"
elsif high_Type = 2
    highTypeName$ = "Hard"
else
    highTypeName$ = "Sine"
endif

# === Info ===
# v0.5 (item 11): v0.4's report omitted Normalize_drive, the effective
# Oversample, Mix, Output_Gain, the input/wet/output peaks, and whether
# normalization ran at all - which made a result hard to reproduce or
# diagnose.
selectObject: original
srcPeak = Get absolute extremum: 0, 0, "None"
inputChannels = Get number of channels

writeInfoLine: "=== Multiband Distortion v0.5b ==="
appendInfoLine: "Source: ", origName$, " (", fixed$(duration, 2), " s, ", inputChannels, " ch, starts at ", fixed$(xmin, 3), " s, peak ", fixed$(srcPeak, 4), ")"
appendInfoLine: "Preset: ", presetName$
if osNote$ <> ""
    appendInfoLine: osNote$
endif
appendInfoLine: ""
appendInfoLine: "Crossovers: ", fixed$(low_Split_Hz, 1), " / ", fixed$(high_Split_Hz, 1), " Hz (Nyquist ", fixed$(nyquist, 1), " Hz)"
appendInfoLine: "Oversampling: ", oversample, "x"
appendInfoLine: "Mix: ", fixed$(mix_0_to_1, 3), "  |  Output gain: ", fixed$(output_Gain, 3)
if normalize_drive
    # v0.5 (item 5): the v0.4 changelog said drive "distorts regardless of
    # how quiet the band is". The normalization is taken from ONE
    # whole-file absolute peak per band, so a single transient sets the
    # gain staging for the entire file: with an impulse of 1 followed by a
    # sustained sine at 0.01, the reviewer measured the quiet part staying
    # perfectly linear (correlation 1.0 with the original, residual ~0),
    # while the same sine distorted heavily once the impulse was removed.
    # (item 6): the peak is one value for the whole multichannel object, so
    # a loud channel sets the drive for quiet ones - stereo with L at 1.0
    # and R at 0.01 left R nearly linear. That keeps stereo imaging intact,
    # which is usually right for a stereo pair, but it is a linked
    # normalization and not a per-channel one.
    appendInfoLine: "Drive normalization: ON - whole-file absolute peak per band, LINKED across channels"
    appendInfoLine: "  (a single transient sets the gain staging for the whole file; a loud channel sets it for quiet ones)"
else
    appendInfoLine: "Drive normalization: OFF (legacy level-dependent)"
endif
if drive_compensation
    appendInfoLine: "Drive compensation: ON (drive changes shape only, not band level)"
else
    appendInfoLine: "Drive compensation: OFF (drive also multiplies band level by drive x gain)"
endif
if output_Gain < 0
    appendInfoLine: "  NOTE: negative Output_Gain inverts the polarity of the whole output."
endif
# v0.5b (minor 5): with an odd waveshaper and Drive_compensation ON, a
# negative drive appears in both inScale and outScale and the two signs
# cancel, so the band is NOT inverted. The note now distinguishes the cases.
if low_Drive < 0 or mid_Drive < 0 or high_Drive < 0
    if drive_compensation and normalize_drive
        appendInfoLine: "  NOTE: a negative Drive appears in both the input and output scales, and with Drive_compensation ON the signs cancel - the band is not inverted, but it enters the waveshaper mirrored."
    else
        appendInfoLine: "  NOTE: a negative Drive inverts that band before waveshaping."
    endif
endif
# v0.5b (minor 4): a negative BAND gain inverts one band relative to the
# others, which changes the crossover reconstruction rather than just the
# level - worth flagging separately from Output_Gain.
if low_Gain < 0 or mid_Gain < 0 or high_Gain < 0
    appendInfoLine: "  NOTE: a negative band Gain inverts that band before recombination, so the bands no longer sum back toward the original."
endif
appendInfoLine: ""
appendInfoLine: "Low (<", low_Split_Hz, " Hz): ", lowTypeName$, " @ ", low_Drive, "x, gain ", low_Gain
appendInfoLine: "Mid (", low_Split_Hz, "-", high_Split_Hz, " Hz): ", midTypeName$, " @ ", mid_Drive, "x, gain ", mid_Gain
appendInfoLine: "High (>", high_Split_Hz, " Hz): ", highTypeName$, " @ ", high_Drive, "x, gain ", high_Gain
appendInfoLine: ""

# ============================================================
# STEP 1: CROSSOVER SPLIT (Phase-Coherent)
# ============================================================

appendInfoLine: "Splitting into bands..."

# Working signal for the aliasing-prone split + distortion + sum stage.
# Oversample so the nonlinearities' harmonics have headroom; the summed
# result is downsampled afterwards (the resampler band-limits on the way down).
if oversample > 1
    selectObject: original
    workSig = Resample: sr * oversample, 50
else
    selectObject: original
    workSig = Copy: "Proc_Temp"
endif

# 1. Create Total Low Pass (Temp)
selectObject: workSig
Filter (pass Hann band): 0, high_Split_Hz, 20
Rename: "LP_Total_Temp"
lp_Total_Obj = selected("Sound")

# 2. Create Low Band
selectObject: workSig
Filter (pass Hann band): 0, low_Split_Hz, 20
Rename: "Low_Band"
low_Obj = selected("Sound")

# 3. Create Mid Band (LP_Total - Low)
selectObject: lp_Total_Obj
Copy: "Mid_Band"
mid_Obj = selected("Sound")
Formula: ~ self - object[low_Obj]

# 4. Create High Band (Proc - LP_Total)
selectObject: workSig
Copy: "High_Band"
high_Obj = selected("Sound")
Formula: ~ self - object[lp_Total_Obj]

# Cleanup temp objects
removeObject: lp_Total_Obj, workSig

# ============================================================
# STEP 2: APPLY DISTORTION PER BAND
# ============================================================

appendInfoLine: "Applying distortion..."

# --- LOW BAND ---
selectObject: low_Obj
@applyDistortion: low_Drive, low_Type, low_Gain

# --- MID BAND ---
selectObject: mid_Obj
@applyDistortion: mid_Drive, mid_Type, mid_Gain

# --- HIGH BAND ---
selectObject: high_Obj
@applyDistortion: high_Drive, high_Type, high_Gain

# ============================================================
# STEP 3: SUM AND MIX
# ============================================================

appendInfoLine: "Summing bands..."

# Sum the bands (Wet Signal)
selectObject: low_Obj
Copy: "Wet_Sum_Temp"
wet_Obj = selected("Sound")
Formula: ~ self + object[mid_Obj] + object[high_Obj]

# CLEANUP: Remove the bands
removeObject: low_Obj, mid_Obj, high_Obj

# Downsample the wet sum back to the original rate (anti-aliased)
if oversample > 1
    selectObject: wet_Obj
    wet_Down = Resample: sr, 50
    removeObject: wet_Obj
    wet_Obj = wet_Down
endif

selectObject: wet_Obj
wetPeak = Get absolute extremum: 0, 0, "None"

# Handle Mix (Output_Gain is applied later as a master trim)
if mix_0_to_1 >= 1.0
    # 100% Wet: Just rename the Wet object
    selectObject: wet_Obj
    Rename: origName$ + "_MultiDist_" + presetName$
    result = wet_Obj
else
    # Partial Mix: Create a Dry Copy and mix
    selectObject: original
    Copy: "Dry_Temp"
    dry_Obj = selected("Sound")
    
    wet_Mix = mix_0_to_1
    dry_Mix = 1.0 - mix_0_to_1
    
    # Mix into the Dry object
    Formula: ~ self * dry_Mix + object[wet_Obj] * wet_Mix
    
    Rename: origName$ + "_MultiDist_" + presetName$
    result = dry_Obj
    
    # CLEANUP: Remove the Wet object
    removeObject: wet_Obj
endif

# === Output stage ===
# v0.5 CRITICAL: v0.4 always ran `Scale peak: 0.95` here, so Mix = 0 was not a
# dry bypass - it was the dry signal normalized. Verified: a source peaking at
# 0.1 came out at 0.855 with Mix = 0 and Output_Gain 0.9, an 8.55x boost with
# zero wet signal. Worse, ANY non-zero peak lands on the same output level, so
# a near-silent input is amplified enormously: peaks of 1e-15, 1e-12, 1e-6 and
# 0.1 all produced 0.855. Numerical noise or a very quiet passage became a
# full-scale signal. Exact silence was safe, but nothing else was.
# Output_mode makes this a visible choice; mode 1 is the v0.3/v0.4 behaviour.
selectObject: result
prePeak = Get absolute extremum: 0, 0, "None"

if output_mode = 2
    Formula: ~ self * output_Gain
    outModeDesc$ = "preserve (output gain only)"
elsif output_mode = 3
    Formula: ~ self * output_Gain
    midPeak = Get absolute extremum: 0, 0, "None"
    if midPeak > 0.95
        Scale peak: 0.95
        outModeDesc$ = "output gain, then normalized (peak was " + fixed$(midPeak, 3) + ")"
    else
        outModeDesc$ = "output gain, no normalization needed (peak " + fixed$(midPeak, 3) + ")"
    endif
else
    # v0.5: near-silence guard. Below this the "peak" is numerical noise, and
    # normalizing it is what turned 1e-15 into 0.855.
    #
    # v0.5b: the guard used to wrap the Output_Gain multiply as well, so
    # below the threshold the master trim silently stopped working - a
    # source peaking at 1e-12 came out at 1e-12 whether the gain was 0.5 or
    # 2.0. The guard exists to prevent dangerous NORMALIZATION, not to
    # disable level control, so the gain is now applied on both paths. That
    # also halves the step at the threshold, though a step remains: this
    # mode normalizes, so 1.0e-9 and 1.1e-9 legitimately end up far apart.
    if prePeak > 1e-9
        Scale peak: 0.95
        outModeDesc$ = "normalized to 0.95, then output gain"
    else
        outModeDesc$ = "near-silent (peak " + fixed$(prePeak, 12) + ") - normalization skipped, output gain still applied"
    endif
    Formula: ~ self * output_Gain
endif

selectObject: result
finalPeak = Get absolute extremum: 0, 0, "None"

appendInfoLine: ""
appendInfoLine: "Wet sum peak (before mix): ", fixed$(wetPeak, 4)
appendInfoLine: "Peak before output stage: ", fixed$(prePeak, 4)
appendInfoLine: "Output stage: ", outModeDesc$
appendInfoLine: "Measured output peak: ", fixed$(finalPeak, 4)
if finalPeak > 1.0
    appendInfoLine: "  WARNING: output peak is ", fixed$(finalPeak, 3), " - above 1.0 it will clip on playback or export."
endif

# ============================================================
# VISUALIZATION
# ============================================================
if draw_visualization
    Erase all
    
    # === Title ===
    Select outer viewport: 0, 8, 0, 0.5
    Font size: 11
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Multiband Distortion: " + origName$ + " (" + presetName$ + ")"
    
    # === Original Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.6, 0.7, 1.4
    
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # === Result Waveform ===
    Select outer viewport: 0, 8, 1.6, 2.5
    Select inner viewport: 0.6, 7.6, 1.7, 2.4
    
    selectObject: result
    Colour: "{0.8, 0.4, 0.4}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Processed"
    Text bottom: "yes", "Time (s)"
    
    # === Spectral Analysis ===
    Select outer viewport: 0, 8, 2.7, 4.3
    Select inner viewport: 0.6, 7.6, 2.8, 4.2
    
    # Get spectra
    selectObject: original
    spec_Orig = To Spectrum: "yes"
    selectObject: result
    spec_Res = To Spectrum: "yes"
    
    # Set dB range
    maxDB = 80
    minDB = 0
    
    # Determine frequency range
    maxFreq = sr / 2
    if maxFreq > visualization_max_Hz
        freqMax = visualization_max_Hz
    else
        freqMax = maxFreq
    endif
    
    Axes: 0, freqMax, minDB, maxDB
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, freqMax, minDB, maxDB
    
    # Shade band regions
    Paint rectangle: "{0.9, 0.85, 0.85}", 0, low_Split_Hz, minDB, maxDB
    Paint rectangle: "{0.85, 0.9, 0.85}", low_Split_Hz, min(high_Split_Hz, freqMax), minDB, maxDB
    Paint rectangle: "{0.85, 0.85, 0.9}", min(high_Split_Hz, freqMax), freqMax, minDB, maxDB
    
    # Draw Original (Grey)
    selectObject: spec_Orig
    Colour: "{0.5, 0.5, 0.5}"
    Line width: 1
    Draw: 0, freqMax, minDB, maxDB, "no"
    
    # Draw Result (Red)
    selectObject: spec_Res
    Colour: "{0.8, 0.3, 0.3}"
    Line width: 1.5
    Draw: 0, freqMax, minDB, maxDB, "no"
    Line width: 1
    
    # Draw Crossover Lines
    Colour: "{0.3, 0.3, 0.3}"
    Line width: 1.5
    if low_Split_Hz < freqMax
        Draw line: low_Split_Hz, minDB, low_Split_Hz, maxDB
    endif
    if high_Split_Hz < freqMax
        Draw line: high_Split_Hz, minDB, high_Split_Hz, maxDB
    endif
    Line width: 1
    
    # Box and labels
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Power (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    
    # Band labels at top
    Font size: 6
    Colour: "{0.6, 0.4, 0.4}"
    Text: low_Split_Hz / 2, "centre", maxDB - 5, "half", "LOW"
    Colour: "{0.4, 0.6, 0.4}"
    midCenter = (low_Split_Hz + min(high_Split_Hz, freqMax)) / 2
    Text: midCenter, "centre", maxDB - 5, "half", "MID"
    Colour: "{0.4, 0.4, 0.6}"
    if high_Split_Hz < freqMax
        highCenter = (high_Split_Hz + freqMax) / 2
        Text: highCenter, "centre", maxDB - 5, "half", "HIGH"
    endif
    
    # Cleanup Spectra
    removeObject: spec_Orig, spec_Res
    
    # === Band Settings Display ===
    Select outer viewport: 0, 8, 4.5, 5.3
    Select inner viewport: 0.6, 7.6, 4.6, 5.2
    
    Axes: 0, 3, 0, 2
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 3, 0, 2
    
    # Low band info
    Paint rectangle: "{0.9, 0.85, 0.85}", 0, 1, 0, 2
    Font size: 6
    Colour: "{0.5, 0.3, 0.3}"
    Text: 0.5, "centre", 1.6, "half", "LOW"
    Text: 0.5, "centre", 1.2, "half", "<" + string$(low_Split_Hz) + " Hz"
    Text: 0.5, "centre", 0.8, "half", lowTypeName$ + " @ " + fixed$(low_Drive, 1) + "x"
    Text: 0.5, "centre", 0.4, "half", "Gain: " + fixed$(low_Gain, 1)
    
    # Mid band info
    Paint rectangle: "{0.85, 0.9, 0.85}", 1, 2, 0, 2
    Colour: "{0.3, 0.5, 0.3}"
    Text: 1.5, "centre", 1.6, "half", "MID"
    Text: 1.5, "centre", 1.2, "half", string$(low_Split_Hz) + "-" + string$(high_Split_Hz) + " Hz"
    Text: 1.5, "centre", 0.8, "half", midTypeName$ + " @ " + fixed$(mid_Drive, 1) + "x"
    Text: 1.5, "centre", 0.4, "half", "Gain: " + fixed$(mid_Gain, 1)
    
    # High band info
    Paint rectangle: "{0.85, 0.85, 0.9}", 2, 3, 0, 2
    Colour: "{0.3, 0.3, 0.5}"
    Text: 2.5, "centre", 1.6, "half", "HIGH"
    Text: 2.5, "centre", 1.2, "half", ">" + string$(high_Split_Hz) + " Hz"
    Text: 2.5, "centre", 0.8, "half", highTypeName$ + " @ " + fixed$(high_Drive, 1) + "x"
    Text: 2.5, "centre", 0.4, "half", "Gain: " + fixed$(high_Gain, 1)
    
    Colour: "Black"
    Draw inner box
    
    # === Master Info ===
    Select outer viewport: 0, 8, 5.4, 5.7
    Font size: 7
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Mix: " + fixed$(mix_0_to_1 * 100, 0) + "% | Output Gain: " + fixed$(output_Gain, 2)
    
    Font size: 10
    Colour: "Black"
endif

# === Finalize ===
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    selectObject: result
    Play
endif

selectObject: result

# ============================================================
# PROCEDURE: Apply Distortion
# ============================================================
procedure applyDistortion: .drive, .type, .gain
    # Gain-staging. If Normalize_drive is on, scale the band UP into the
    # waveshaper by its own peak, then restore the level on the way out.
    # Off = legacy behaviour (input = self * drive).
    #
    # Note that the normalization uses ONE whole-file absolute peak per band,
    # so a single loud transient sets the gain staging for the entire file and
    # a quiet passage after it may stay essentially linear. (v0.4's claim that
    # drive "engages regardless of how quiet the band is" was too strong; see
    # the header.) The peak also covers the whole multichannel object, so the
    # normalization is linked across channels.
    #
    # v0.5b: with compensation on, the limit as drive -> 0 is LINEAR output,
    # not silence: tanh(x*d/pk) * gain*pk/d -> x*gain. v0.5 guarded the
    # division with `drive <> 0` and fell back to the UNcompensated scales,
    # which set inScale = 0 and silenced the band - a full discontinuity at
    # exactly zero, contradicting the form's own "drive changes shape only,
    # not band level". Handled as its own branch, with no goto.
    .bypass = 0
    if normalize_drive and drive_compensation and abs(.drive) < 1e-9
        .bypass = 1
    endif

    if .bypass = 1
        .bp$ = string$(.gain)
        Formula: "self * " + .bp$
    else
        if normalize_drive
            .pk = Get absolute extremum: 0, 0, "None"
            if .pk <= 0
                .pk = 1
            endif
            .inScale = .drive / .pk
            # v0.5 (item 9): with outScale = gain * pk, the linear region
            # gives out = in * (drive/pk) * (gain*pk) = in * drive * gain -
            # so drive multiplied the band's LEVEL as well as setting how
            # hard it hits the nonlinearity, and since each band has its own
            # drive the spectral balance moved too. v0.4's "restored on the
            # way out" was true of the peak scale but not of the drive.
            # Compensation divides it back out so drive changes SHAPE only.
            if drive_compensation
                .outScale = .gain * .pk / .drive
            else
                .outScale = .gain * .pk
            endif
        else
            .inScale = .drive
            .outScale = .gain
        endif
        .is$ = string$(.inScale)
        .os$ = string$(.outScale)
        .nos$ = string$(-.outScale)

        if .type = 1
            # Soft Clip (Tanh)
            Formula: "tanh(self * " + .is$ + ") * " + .os$

        elsif .type = 2
            # Hard Clip - nested if/then/else (no elsif in formula language)
            .input$ = "(self * " + .is$ + ")"
            Formula: "if " + .input$ + " > 1 then " + .os$ + " else (if " + .input$ + " < -1 then " + .nos$ + " else " + .input$ + " * " + .os$ + " fi) fi"

        elsif .type = 3
            # Sine waveshaper (v0.5: was called "Sine Fold").
            # sin(x) is monotonic until |x| passes pi/2 = 1.5708, so with
            # Normalize_drive on and drive 1 the argument only spans +/-1 rad
            # and NOTHING folds - it is a gentle saturating curve. Folding
            # begins above drive ~1.571 and becomes repeated folding higher up.
            Formula: "sin(self * " + .is$ + ") * " + .os$
        endif
    endif
endproc
