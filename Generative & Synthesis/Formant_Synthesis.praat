# ============================================================
# Praat AudioTools - Formant_Synthesis.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 reviewed (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# KLATTGRID SOURCE-FILTER VOWEL SYNTHESIS
#
#   Praat KlattGrid is used as an explicit source-filter synthesizer:
#     phonation / aspiration / breathiness source
#                       -> four oral resonances F1..F4
#                       -> output Sound
#
#   F1..F4 are resonances of the filter, NOT sinusoidal oscillators.
#   The reference vowel values are synthesis targets; presets such as
#   High-F0 A or Low-F0 O describe parameter configurations rather than
#   demographic categories.
#
# v0.4 reviewed:
#   - Preserved the correct KlattGrid source-filter architecture.
#   - Added explicit aspiration and breathiness controls. The former Whisper
#     preset now has an aspiration-dominant source instead of merely lowering
#     voicing amplitude.
#   - Replaced demographic/instrument-like preset claims (Soprano, Bass,
#     Child, Robot, Alien) with mechanism-faithful parameter descriptions.
#   - Added Random_seed for KlattGrid stochastic source components.
#   - Added short-duration-safe attack/release timing for voicing/noise tiers.
#   - Vibrato is represented in semitones and applied multiplicatively to F0,
#     preventing the same Hz depth from meaning different things at low/high F0.
#   - Chorus synthesis now preserves the SAME vibrato, aspiration, breathiness,
#     formants and source envelope on both detuned channels.
#   - Replaced spectral "formant spread" stereo filtering with a short
#     micro-delay stereo field that preserves the vowel spectrum.
#   - Fixed stereo creation pattern: Combine to stereo followed by
#     selected("Sound"), never assignment from the command itself.
#   - Added common Nyquist scaling for F1..F4 and BW1..BW4 when necessary;
#     formant geometry is preserved rather than clipping formants independently.
#   - Added validation for formant ordering, bandwidths, source levels,
#     vibrato, sample rate and duration.
#   - Compact laptop-safe main form + two small Advanced pages.
#   - One combined edge fade; one optional final/common normalization.
#   - Visualization rebuilt around the mechanism:
#       A F1/F2 reference vowel space + actual target
#       B actual KlattGrid F0 control trajectory
#       C measured spectrogram + F1..F4 targets
#       D measured output spectrum + F1..F4 targets
#       source/filter/Nyquist/output QC
# ============================================================

form Formant Synthesis v0.4
    optionmenu Preset 1
        option Custom (baseline values)
        option Vowel A
        option Vowel E
        option Vowel I
        option Vowel O
        option Vowel U
        option High-F0 A
        option Low-F0 O
        option High-F0 E
        option Narrow-Band Synthetic Voice
        option Aspiration-Dominant Whisper
        option Vibrato Vocal Tone
        option Extreme Formant Voice

    positive Duration_s 3.0
    positive Pitch_Hz 120
    integer Sample_rate_Hz 44100

    optionmenu Spatial_mode 1
        option Mono
        option Stereo Micro-Delay
        option Detuned Stereo Chorus

    boolean Edit_formant_details 0
    boolean Edit_source_details 0
    boolean Normalize_output 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------------------------------------------------------------------
# ADVANCED DEFAULTS
# ---------------------------------------------------------------------------
f1 = 500
f2 = 1500
f3 = 2500
f4 = 3500
bw1 = 50
bw2 = 70
bw3 = 110
bw4 = 150

voicing_amplitude_dB = 60
aspiration_amplitude_dB = 0
breathiness_amplitude_dB = 0
enable_vibrato = 1
vibrato_rate_Hz = 6
vibrato_depth_semitones = 0.75
random_seed = 0
edge_fade_s = 0.02

# ---------------------------------------------------------------------------
# 0. PRESETS
# ---------------------------------------------------------------------------
preset_name$ = "Custom"

if preset = 2
    f1 = 730
    f2 = 1090
    f3 = 2440
    f4 = 3500
    bw1 = 40
    bw2 = 60
    bw3 = 100
    bw4 = 120
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 8
    breathiness_amplitude_dB = 4
    preset_name$ = "Vowel A"

elsif preset = 3
    f1 = 530
    f2 = 1840
    f3 = 2480
    f4 = 3500
    bw1 = 45
    bw2 = 65
    bw3 = 105
    bw4 = 125
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 8
    breathiness_amplitude_dB = 4
    preset_name$ = "Vowel E"

elsif preset = 4
    f1 = 270
    f2 = 2290
    f3 = 3010
    f4 = 3500
    bw1 = 35
    bw2 = 70
    bw3 = 110
    bw4 = 130
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 7
    breathiness_amplitude_dB = 3
    preset_name$ = "Vowel I"

elsif preset = 5
    f1 = 570
    f2 = 840
    f3 = 2410
    f4 = 3500
    bw1 = 50
    bw2 = 60
    bw3 = 100
    bw4 = 120
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 8
    breathiness_amplitude_dB = 4
    preset_name$ = "Vowel O"

elsif preset = 6
    f1 = 300
    f2 = 870
    f3 = 2240
    f4 = 3500
    bw1 = 40
    bw2 = 55
    bw3 = 95
    bw4 = 115
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 8
    breathiness_amplitude_dB = 4
    preset_name$ = "Vowel U"

elsif preset = 7
    f1 = 800
    f2 = 1150
    f3 = 2900
    f4 = 3900
    pitch_Hz = 260
    bw1 = 35
    bw2 = 50
    bw3 = 90
    bw4 = 110
    voicing_amplitude_dB = 62
    aspiration_amplitude_dB = 6
    breathiness_amplitude_dB = 3
    vibrato_depth_semitones = 0.55
    preset_name$ = "High-F0 A"

elsif preset = 8
    f1 = 450
    f2 = 800
    f3 = 2830
    f4 = 3500
    pitch_Hz = 80
    bw1 = 60
    bw2 = 70
    bw3 = 120
    bw4 = 140
    voicing_amplitude_dB = 61
    aspiration_amplitude_dB = 7
    breathiness_amplitude_dB = 4
    vibrato_depth_semitones = 0.35
    preset_name$ = "Low-F0 O"

elsif preset = 9
    f1 = 600
    f2 = 2000
    f3 = 2600
    f4 = 3800
    pitch_Hz = 300
    bw1 = 30
    bw2 = 55
    bw3 = 95
    bw4 = 115
    voicing_amplitude_dB = 60
    aspiration_amplitude_dB = 7
    breathiness_amplitude_dB = 3
    vibrato_depth_semitones = 0.45
    preset_name$ = "High-F0 E"

elsif preset = 10
    f1 = 400
    f2 = 1200
    f3 = 2400
    f4 = 3200
    bw1 = 20
    bw2 = 30
    bw3 = 40
    bw4 = 50
    enable_vibrato = 0
    voicing_amplitude_dB = 64
    aspiration_amplitude_dB = 0
    breathiness_amplitude_dB = 0
    preset_name$ = "Narrow-Band Synthetic Voice"

elsif preset = 11
    f1 = 500
    f2 = 1500
    f3 = 2500
    f4 = 3500
    bw1 = 80
    bw2 = 100
    bw3 = 150
    bw4 = 200
    voicing_amplitude_dB = 0
    aspiration_amplitude_dB = 72
    breathiness_amplitude_dB = 0
    enable_vibrato = 0
    preset_name$ = "Aspiration-Dominant Whisper"

elsif preset = 12
    f1 = 600
    f2 = 1200
    f3 = 2400
    f4 = 3600
    pitch_Hz = 220
    bw1 = 35
    bw2 = 55
    bw3 = 95
    bw4 = 115
    voicing_amplitude_dB = 62
    aspiration_amplitude_dB = 6
    breathiness_amplitude_dB = 3
    enable_vibrato = 1
    vibrato_rate_Hz = 5.5
    vibrato_depth_semitones = 0.95
    preset_name$ = "Vibrato Vocal Tone"

elsif preset = 13
    f1 = 200
    f2 = 3000
    f3 = 4000
    f4 = 5000
    pitch_Hz = 180
    bw1 = 15
    bw2 = 25
    bw3 = 35
    bw4 = 45
    voicing_amplitude_dB = 64
    aspiration_amplitude_dB = 4
    breathiness_amplitude_dB = 2
    enable_vibrato = 0
    preset_name$ = "Extreme Formant Voice"
endif

# ---------------------------------------------------------------------------
# OPTIONAL COMPACT ADVANCED PAGES
# ---------------------------------------------------------------------------
if edit_formant_details
    beginPause: "Formant Synthesis - Resonance Details"
        positive: "F1 (Hz)", f1
        positive: "F2 (Hz)", f2
        positive: "F3 (Hz)", f3
        positive: "F4 (Hz)", f4
        positive: "BW1 (Hz)", bw1
        positive: "BW2 (Hz)", bw2
        positive: "BW3 (Hz)", bw3
        positive: "BW4 (Hz)", bw4
    endPause: "Run", 1
endif

if edit_source_details
    beginPause: "Formant Synthesis - Source Details"
        real: "Voicing amplitude (dB)", voicing_amplitude_dB
        real: "Aspiration amplitude (dB)", aspiration_amplitude_dB
        real: "Breathiness amplitude (dB)", breathiness_amplitude_dB
        boolean: "Enable vibrato", enable_vibrato
        positive: "Vibrato rate (Hz)", vibrato_rate_Hz
        real: "Vibrato depth (semitones)", vibrato_depth_semitones
        integer: "Random seed (0 = unpredictable)", random_seed
        real: "Edge fade (s)", edge_fade_s
    endPause: "Run", 1
endif

# ---------------------------------------------------------------------------
# 1. VALIDATION
# ---------------------------------------------------------------------------
if duration_s <= 0 or duration_s > 120
    exitScript: "Duration must be > 0 and <= 120 seconds."
endif
if sample_rate_Hz < 8000 or sample_rate_Hz > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif
if pitch_Hz <= 0
    exitScript: "Pitch must be greater than zero."
endif
if f1 <= 0 or f2 <= 0 or f3 <= 0 or f4 <= 0
    exitScript: "All formants must be greater than zero."
endif
if f1 >= f2 or f2 >= f3 or f3 >= f4
    exitScript: "Formants must be strictly ordered: F1 < F2 < F3 < F4."
endif
if bw1 <= 0 or bw2 <= 0 or bw3 <= 0 or bw4 <= 0
    exitScript: "All formant bandwidths must be greater than zero."
endif
if voicing_amplitude_dB < 0 or voicing_amplitude_dB > 120 or
    ... aspiration_amplitude_dB < 0 or aspiration_amplitude_dB > 120 or
    ... breathiness_amplitude_dB < 0 or breathiness_amplitude_dB > 120
    exitScript: "Source amplitude controls must be between 0 and 120 dB."
endif
if vibrato_rate_Hz <= 0 or vibrato_rate_Hz > 20
    exitScript: "Vibrato rate must be > 0 and <= 20 Hz."
endif
if vibrato_depth_semitones < 0 or vibrato_depth_semitones > 3
    exitScript: "Vibrato depth must be between 0 and 3 semitones."
endif
if random_seed < 0
    exitScript: "Random seed must be 0 or a positive integer."
endif
if edge_fade_s < 0
    exitScript: "Edge fade cannot be negative."
endif

safeTop = 0.45*sample_rate_Hz
maxPitch = pitch_Hz*2^(vibrato_depth_semitones/12)
minPitch = pitch_Hz/2^(vibrato_depth_semitones/12)
if maxPitch >= safeTop
    exitScript: "Pitch/vibrato exceeds practical sampling headroom."
endif

# Common scaling preserves the F1:F2:F3:F4 geometry.
formantScale = 1
if f4 > safeTop
    formantScale = safeTop/f4
endif

f1_eff = f1*formantScale
f2_eff = f2*formantScale
f3_eff = f3*formantScale
f4_eff = f4*formantScale
bw1_eff = bw1*formantScale
bw2_eff = bw2*formantScale
bw3_eff = bw3*formantScale
bw4_eff = bw4*formantScale

if spatial_mode = 1
    spatial$ = "Mono"
elsif spatial_mode = 2
    spatial$ = "Stereo Micro-Delay"
else
    spatial$ = "Detuned Stereo Chorus"
endif

uid$ = string$(randomInteger(10000,99999))
seedWasFixed = 0
if random_seed > 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
    seedWasFixed = 1
    seedLabel$ = "seed " + string$(random_seed)
else
    seedLabel$ = "seed random"
endif

# ---------------------------------------------------------------------------
# 2. INFO
# ---------------------------------------------------------------------------
clearinfo
writeInfoLine: "=============================================="
writeInfoLine: "  FORMANT SYNTHESIS v0.4"
writeInfoLine: "=============================================="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Duration: ", fixed$(duration_s,2), " s"
appendInfoLine: "Pitch: ", fixed$(pitch_Hz,2), " Hz"
appendInfoLine: "Effective F1/F2/F3/F4: ",
    ... fixed$(f1_eff,0), " / ", fixed$(f2_eff,0), " / ",
    ... fixed$(f3_eff,0), " / ", fixed$(f4_eff,0), " Hz"
appendInfoLine: "Source dB voice/aspiration/breathiness: ",
    ... fixed$(voicing_amplitude_dB,1), " / ",
    ... fixed$(aspiration_amplitude_dB,1), " / ",
    ... fixed$(breathiness_amplitude_dB,1)
appendInfoLine: "Spatial: ", spatial$
appendInfoLine: "Randomness: ", seedLabel$
if formantScale < 0.9999
    appendInfoLine: "Formants/BWs scaled by ", fixed$(formantScale,4),
        ... " for sampling headroom."
endif
appendInfoLine: ""

# ---------------------------------------------------------------------------
# 3. SYNTHESIS / SPATIALIZATION
# ---------------------------------------------------------------------------
appendInfoLine: "Creating KlattGrid source-filter voice..."

if spatial_mode = 3
    # Both channels use the same full KlattGrid architecture and differ only
    # by a small pitch detuning. Vibrato and source-noise controls are retained.
    @makeVoice: 2^(-5/1200),"chorusL"
    leftSound = makeVoice.result

    @makeVoice: 2^(5/1200),"chorusR"
    rightSound = makeVoice.result

    selectObject: leftSound
    plusObject: rightSound
    Combine to stereo
    outputSound = selected("Sound")

    removeObject: leftSound,rightSound

else
    @makeVoice: 1,"centre"
    monoVoice = makeVoice.result

    if spatial_mode = 1
        outputSound = monoVoice

    else
        # Preserve the vowel spectrum: right channel is a short delayed copy,
        # not a complementary spectral split.
        stereoDelay = min(0.008,0.04*duration_s)
        monoID$ = string$(monoVoice)

        selectObject: monoVoice
        Copy: "formant_left_" + uid$
        leftSound = selected("Sound")
        Formula: "self/sqrt(2)"

        selectObject: monoVoice
        Copy: "formant_right_" + uid$
        rightSound = selected("Sound")
        Formula: "object(" + monoID$ + ",x-stereoDelay,1)/sqrt(2)"

        selectObject: leftSound
        plusObject: rightSound
        Combine to stereo
        outputSound = selected("Sound")

        removeObject: monoVoice,leftSound,rightSound
    endif
endif

if seedWasFixed
    random_initializeSafelyAndUnpredictably ()
endif

# ---------------------------------------------------------------------------
# 4. EDGE FADE / FINAL LEVEL
# ---------------------------------------------------------------------------
actualFade = min(edge_fade_s,0.20*duration_s)
if actualFade > 0
    fadeOutStart = duration_s-actualFade
    selectObject: outputSound
    Formula: "if x<actualFade then self*(x/actualFade) else if x>fadeOutStart then self*((duration_s-x)/actualFade) else self fi fi"
endif

selectObject: outputSound
preNormPeak = Get absolute extremum: 0,0,"None"
preNormRMS = Get root-mean-square: 0,0

if normalize_output and preNormPeak > 0
    Scale peak: 0.90
endif

safePreset$ = replace$(preset_name$," ","_",0)
selectObject: outputSound
Rename: "formant_" + safePreset$

finalPeak = Get absolute extremum: 0,0,"None"
finalRMS = Get root-mean-square: 0,0
finalChannels = Get number of channels
finalDuration = Get total duration

# ---------------------------------------------------------------------------
# 5. VISUALIZATION
# ---------------------------------------------------------------------------
if draw_visualization
    @drawVisualization
endif

# ---------------------------------------------------------------------------
# 6. FINAL INFO / PLAY
# ---------------------------------------------------------------------------
selectObject: outputSound
appendInfoLine: ""
appendInfoLine: "Pre-normalization peak/RMS: ",
    ... fixed$(preNormPeak,4), " / ", fixed$(preNormRMS,4)
appendInfoLine: "Final peak/RMS: ",
    ... fixed$(finalPeak,4), " / ", fixed$(finalRMS,4)
appendInfoLine: "Duration: ", fixed$(finalDuration,3), " s"
appendInfoLine: "Done: ", selected$("Sound")

if play_result
    Play
endif

selectObject: outputSound


# ===========================================================================
# PROCEDURE: makeVoice
# Full KlattGrid source/filter voice. pitchScale is used for chorus detuning.
# ===========================================================================
procedure makeVoice: .pitchScale,.tag$

    .twoPi = 2*pi
    .dur = duration_s

    # Short-duration-safe source envelope timings.
    .attack = max(0.001,min(0.025,0.12*.dur))
    .release = max(0.001,min(0.060,0.18*.dur))
    .releaseStart = max(.attack,.dur-.release)

    .kg = Create KlattGrid:
        ... "formant_kg_" + .tag$ + "_" + uid$,
        ... 0,.dur,4,0,0,0,0,1,0

    selectObject: .kg

    # Pitch tier: exact control points used by the visualization as well.
    .basePitch = pitch_Hz*.pitchScale

    if enable_vibrato and vibrato_depth_semitones > 0
        .vibPoints = max(8,round(.dur*vibrato_rate_Hz*8)+1)
        for .p from 1 to .vibPoints
            .t = (.p-1)*.dur/(.vibPoints-1)
            .semi = vibrato_depth_semitones*sin(.twoPi*vibrato_rate_Hz*.t)
            .fp = .basePitch*2^(.semi/12)
            Add pitch point: .t,.fp
        endfor
    else
        Add pitch point: 0,.basePitch
        Add pitch point: .dur,.basePitch
    endif

    # Source amplitude tiers with attack/release; 0 dB is used as off/edge.
    if voicing_amplitude_dB > 0
        Add voicing amplitude point: 0,0
        Add voicing amplitude point: .attack,voicing_amplitude_dB
        Add voicing amplitude point: .releaseStart,voicing_amplitude_dB
        Add voicing amplitude point: .dur,0
    else
        Add voicing amplitude point: 0,0
        Add voicing amplitude point: .dur,0
    endif

    if aspiration_amplitude_dB > 0
        Add aspiration amplitude point: 0,0
        Add aspiration amplitude point: .attack,aspiration_amplitude_dB
        Add aspiration amplitude point: .releaseStart,aspiration_amplitude_dB
        Add aspiration amplitude point: .dur,0
    else
        Add aspiration amplitude point: 0,0
        Add aspiration amplitude point: .dur,0
    endif

    if breathiness_amplitude_dB > 0
        Add breathiness amplitude point: 0,0
        Add breathiness amplitude point: .attack,breathiness_amplitude_dB
        Add breathiness amplitude point: .releaseStart,breathiness_amplitude_dB
        Add breathiness amplitude point: .dur,0
    else
        Add breathiness amplitude point: 0,0
        Add breathiness amplitude point: .dur,0
    endif

    # Four constant oral resonances. Explicit start/end points make the
    # intended static trajectories unambiguous.
    Add oral formant frequency point: 1,0,f1_eff
    Add oral formant frequency point: 1,.dur,f1_eff
    Add oral formant bandwidth point: 1,0,bw1_eff
    Add oral formant bandwidth point: 1,.dur,bw1_eff

    Add oral formant frequency point: 2,0,f2_eff
    Add oral formant frequency point: 2,.dur,f2_eff
    Add oral formant bandwidth point: 2,0,bw2_eff
    Add oral formant bandwidth point: 2,.dur,bw2_eff

    Add oral formant frequency point: 3,0,f3_eff
    Add oral formant frequency point: 3,.dur,f3_eff
    Add oral formant bandwidth point: 3,0,bw3_eff
    Add oral formant bandwidth point: 3,.dur,bw3_eff

    Add oral formant frequency point: 4,0,f4_eff
    Add oral formant frequency point: 4,.dur,f4_eff
    Add oral formant bandwidth point: 4,0,bw4_eff
    Add oral formant bandwidth point: 4,.dur,bw4_eff

    selectObject: .kg
    To Sound
    .raw = selected("Sound")

    selectObject: .raw
    .rawFs = Get sampling frequency

    if abs(.rawFs-sample_rate_Hz) > 0.5
        .resampled = Resample: sample_rate_Hz,50
        removeObject: .raw
    else
        Copy: "formant_voice_" + .tag$
        .resampled = selected("Sound")
        removeObject: .raw
    endif

    removeObject: .kg

    selectObject: .resampled
    .result = selected("Sound")
endproc


# ===========================================================================
# PROCEDURE: RESEARCH-GRADE VISUALIZATION
# ===========================================================================
procedure drawVisualization

    .left = 0.78
    .right = 7.58
    .bg$ = "{0.975,0.975,0.978}"
    .grid$ = "{0.80,0.80,0.82}"
    .blue$ = "{0.18,0.43,0.72}"
    .orange$ = "{0.76,0.38,0.18}"
    .green$ = "{0.25,0.58,0.38}"
    .purple$ = "{0.52,0.30,0.62}"

    Erase all

    # -----------------------------------------------------------------------
    # HEADER
    # -----------------------------------------------------------------------
    Select inner viewport: 0.20,7.80,0.05,0.33
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.55,"half",
        ... "FORMANT SYNTHESIS | " + preset_name$

    Select inner viewport: 0.35,7.65,0.37,0.67
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.35,0.35,0.35}"
    Text: 0.5,"centre",0.68,"half",
        ... "KlattGrid source-filter | F0 " + fixed$(pitch_Hz,1)
        ... + " Hz | " + spatial$
    Text: 0.5,"centre",0.20,"half",
        ... "phonation / aspiration / breathiness -> F1..F4 resonances -> measured output"

    # -----------------------------------------------------------------------
    # PANEL A: VOWEL SPACE
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,0.76,0.98
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "A  F1-F2 VOWEL SPACE | reference targets + current synthesis target"

    Select inner viewport: .left,.right,1.05,2.24
    Axes: 2500,500,900,200
    Paint rectangle: .bg$,500,2500,200,900

    Colour: .grid$
    Line width: 1
    Draw line: 2290,270,1840,530
    Draw line: 1840,530,1090,730
    Draw line: 1090,730,840,570
    Draw line: 840,570,870,300
    Draw line: 870,300,2290,270

    Colour: "{0.50,0.50,0.70}"
    Paint circle (mm): "{0.50,0.50,0.70}",2290,270,1.0
    Paint circle (mm): "{0.50,0.50,0.70}",1840,530,1.0
    Paint circle (mm): "{0.50,0.50,0.70}",1090,730,1.0
    Paint circle (mm): "{0.50,0.50,0.70}",840,570,1.0
    Paint circle (mm): "{0.50,0.50,0.70}",870,300,1.0

    Colour: "Black"
    Font size: 5
    Text: 2290,"centre",270,"top","i"
    Text: 1840,"centre",530,"top","e"
    Text: 1090,"centre",730,"top","a"
    Text: 840,"centre",570,"top","o"
    Text: 870,"centre",300,"top","u"

    if f2_eff >= 500 and f2_eff <= 2500 and f1_eff >= 200 and f1_eff <= 900
        Paint circle (mm): "{0.82,0.20,0.18}",f2_eff,f1_eff,1.5
        Colour: "{0.82,0.20,0.18}"
        Font size: 5
        Text: f2_eff,"centre",f1_eff,"bottom","TARGET"
    endif

    Colour: "Black"
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","F1 (Hz)"
    Text bottom: "yes","F2 (Hz)"

    # -----------------------------------------------------------------------
    # PANEL B: ACTUAL F0 CONTROL TRAJECTORY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,2.40,2.62
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "B  KLATTGRID PITCH CONTROL | exact control-point trajectory used for the centre voice"

    .pitchPad = max(2,0.12*(maxPitch-minPitch+1))
    .pitchLo = max(1,minPitch-.pitchPad)
    .pitchHi = maxPitch+.pitchPad

    Select inner viewport: .left,.right,2.69,3.58
    Axes: 0,duration_s,.pitchLo,.pitchHi
    Paint rectangle: .bg$,0,duration_s,.pitchLo,.pitchHi

    Colour: .grid$
    Dotted line
    Draw line: 0,pitch_Hz,duration_s,pitch_Hz
    Plain line

    Colour: .blue$
    Line width: 1.5

    if enable_vibrato and vibrato_depth_semitones > 0
        .n = max(8,round(duration_s*vibrato_rate_Hz*8)+1)
        .tPrev = 0
        .fPrev = pitch_Hz
        for .p from 1 to .n
            .t = (.p-1)*duration_s/(.n-1)
            .semi = vibrato_depth_semitones*sin(2*pi*vibrato_rate_Hz*.t)
            .fp = pitch_Hz*2^(.semi/12)
            if .p > 1
                Draw line: .tPrev,.fPrev,.t,.fp
            endif
            .tPrev = .t
            .fPrev = .fp
        endfor
    else
        Draw line: 0,pitch_Hz,duration_s,pitch_Hz
    endif

    if spatial_mode = 3
        Colour: .orange$
        Draw line: 0,pitch_Hz*2^(-5/1200),duration_s,pitch_Hz*2^(-5/1200)
        Colour: .green$
        Draw line: 0,pitch_Hz*2^(5/1200),duration_s,pitch_Hz*2^(5/1200)
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","F0 (Hz)"

    # -----------------------------------------------------------------------
    # REPRESENTATIVE OUTPUT CHANNEL
    # -----------------------------------------------------------------------
    if finalChannels = 1
        selectObject: outputSound
        Copy: "formant_display_" + uid$
        .disp = selected("Sound")
    else
        selectObject: outputSound
        Extract one channel: 1
        .leftDisp = selected("Sound")
        .leftRms = Get root-mean-square: 0,0

        selectObject: outputSound
        Extract one channel: 2
        .rightDisp = selected("Sound")
        .rightRms = Get root-mean-square: 0,0

        if .rightRms > .leftRms
            removeObject: .leftDisp
            .disp = .rightDisp
        else
            removeObject: .rightDisp
            .disp = .leftDisp
        endif
    endif

    # -----------------------------------------------------------------------
    # PANEL C: MODEL -> MEASUREMENT SPECTROGRAM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,3.74,3.96
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "C  MODEL -> MEASUREMENT | measured spectrogram + F1..F4 synthesis targets"

    .specMax = min(safeTop,max(4000,1.15*f4_eff))
    .specStep = max(0.002,duration_s/1100)

    selectObject: .disp
    To Spectrogram: 0.025,.specMax,.specStep,20,"Gaussian"
    .spec = selected("Spectrogram")

    Select inner viewport: .left,.right,4.03,5.11
    selectObject: .spec
    Paint: 0,0,0,.specMax,100,"yes",50,6,0,"no"
    removeObject: .spec

    Axes: 0,duration_s,0,.specMax
    Line width: 1.2
    Colour: "{0.85,0.25,0.25}"
    Draw line: 0,f1_eff,duration_s,f1_eff
    Colour: "{0.25,0.65,0.30}"
    Draw line: 0,f2_eff,duration_s,f2_eff
    Colour: "{0.25,0.40,0.85}"
    Draw line: 0,f3_eff,duration_s,f3_eff
    Colour: "{0.75,0.55,0.15}"
    Draw line: 0,f4_eff,duration_s,f4_eff

    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left: 4,"yes","yes","no"
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text left: "yes","Frequency (Hz)"
    Text bottom: "yes","Time (s)"

    # -----------------------------------------------------------------------
    # PANEL D: MEASURED SPECTRUM
    # -----------------------------------------------------------------------
    Select inner viewport: 0.35,7.65,5.27,5.49
    Axes: 0,1,0,1
    Font size: 8
    Colour: "Black"
    Text: 0.5,"centre",0.52,"half",
        ... "D  MEASURED OUTPUT SPECTRUM | resonance targets over the measured spectrum"

    selectObject: .disp
    To Spectrum: "yes"
    .spectrum = selected("Spectrum")

    Select inner viewport: .left,.right,5.56,6.35
    selectObject: .spectrum
    Colour: .purple$
    Draw: 0,.specMax,0,0,"no"
    removeObject: .spectrum

    # Restore frequency-world axes after Spectrum Draw before guide lines.
    Axes: 0,.specMax,0,1
    Colour: "{0.70,0.20,0.20}"
    Dotted line
    Draw line: f1_eff,0,f1_eff,1
    Draw line: f2_eff,0,f2_eff,1
    Draw line: f3_eff,0,f3_eff,1
    Draw line: f4_eff,0,f4_eff,1
    Plain line

    Colour: "Black"
    Draw inner box
    Marks bottom: 5,"yes","yes","no"
    Font size: 6
    Text bottom: "yes","Frequency (Hz)"

    removeObject: .disp

    # -----------------------------------------------------------------------
    # QC SUMMARY
    # -----------------------------------------------------------------------
    Select inner viewport: 0.50,7.50,6.58,7.82
    Axes: 0,1,0,1
    Paint rectangle: "{0.93,0.93,0.935}",0,1,0,1

    Font size: 6
    Colour: "{0.25,0.25,0.25}"

    Text: 0.02,"left",0.80,"half",
        ... "SOURCE  |  voice " + fixed$(voicing_amplitude_dB,0)
        ... + " dB  |  aspiration " + fixed$(aspiration_amplitude_dB,0)
        ... + " dB  |  breathiness " + fixed$(breathiness_amplitude_dB,0)
        ... + " dB  |  " + seedLabel$

    Text: 0.02,"left",0.58,"half",
        ... "FILTER  |  F1/F2/F3/F4 " + fixed$(f1_eff,0) + "/"
        ... + fixed$(f2_eff,0) + "/" + fixed$(f3_eff,0) + "/"
        ... + fixed$(f4_eff,0) + " Hz  |  scale " + fixed$(formantScale,3)

    Text: 0.02,"left",0.37,"half",
        ... "PITCH  |  " + fixed$(minPitch,1) + "-" + fixed$(maxPitch,1)
        ... + " Hz  |  vibrato " + fixed$(vibrato_rate_Hz,1) + " Hz / "
        ... + fixed$(vibrato_depth_semitones,2) + " st  |  " + spatial$

    if normalize_output
        .norm$ = "normalized"
    else
        .norm$ = "raw level"
    endif

    Text: 0.02,"left",0.16,"half",
        ... "OUTPUT  |  pre-peak " + fixed$(preNormPeak,3)
        ... + "  |  pre-RMS " + fixed$(preNormRMS,4)
        ... + "  |  final peak " + fixed$(finalPeak,3)
        ... + "  |  " + .norm$

    Colour: "{0.52,0.52,0.54}"
    Draw rectangle: 0,1,0,1

    Colour: "Black"
    Line width: 1
    Font size: 10
endproc
