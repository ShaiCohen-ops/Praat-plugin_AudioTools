# ============================================================
# Praat AudioTools - Frequency-Dependent_Phase_Manipulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#
# Changelog v1.2.2 (2026) -- simplify performance path:
#   - REMOVED Speed_mode. Benchmarks showed the original-sample-rate Full Quality
#     path can be substantially faster than the 22.05/11.025 kHz paths for this
#     processor, because runtime is dominated by Praat's Spectrum -> Sound inverse
#     transform and its cost depends strongly on the resulting transform size.
#   - Processing now always runs at the source sample rate: no downsample/upsample
#     stage, no bandwidth reduction, and no resampling artifacts or extra work.
#   - Existing transform-character choice and all musical fast paths are unchanged.
#
# Changelog v1.2.1 (2026) -- performance only; active DSP unchanged:
#   - FAST BYPASS: Dry_wet=0 skips both spectral transforms. In Exact-length
#     mode, Phase_amount=0 can also bypass safely. Legacy zero-phase still runs
#     because its padded+trim round-trip itself contributes to that character.
#   - FAST MONO DUAL-MONO: for mono input with Stereo_width=0, the wet phase
#     result is calculated once and copied to R instead of running the identical
#     full FFT / inverse-transform path twice.
#   - Legacy padded FFT remains the default character. Its general-case runtime
#     is dominated by Praat's Spectrum -> Sound inverse transform; removing the
#     intermediate Matrix round-trip was benchmarked and did not materially help.
#   - Exact-length phase remains the recommended faster transform when its cleaner
#     phase-only character is musically appropriate.
#
# Description:
#   Frequency-dependent spectral phase rotation for spatial and temporal colour.
#   The complex spectrum is rotated by a frequency-dependent phase field while
#   retaining its magnitude inside the transform. With partial dry/wet mixing,
#   interference between dry and rotated spectra can create comb-/phaser-like
#   magnitude coloration. At 100% wet, the main effect is phase dispersion,
#   transient reshaping and stereo phase difference rather than a magnitude EQ.
#
#   Two transform characters are available:
#     - Legacy padded FFT: v1.1 character. Fast FFT zero-padding is followed by
#       trimming after inverse transform; this can add magnitude coloration.
#     - Exact-length phase: no FFT padding. Pure wet processing is phase-only
#       apart from unavoidable real-signal DC/Nyquist constraints.
#
# Changelog v1.2 (2026):
#   - MUSICAL PRIORITY: legacy padded+trim FFT remains the default character.
#     Exact-length phase rotation is added as an alternate, not substituted.
#   - FIX: stereo input is no longer collapsed to mono. Channels 1/2 are
#     processed independently, preserving native stereo and anti-phase material.
#     Mono input still generates stereo via the L/R phase-field difference.
#   - FIX (historical v1.2): the dry path remained at the ORIGINAL sample rate
#     when reduced-rate speed modes were used. Those speed modes are removed in
#     v1.2.2 after benchmarking showed no reliable performance advantage.
#   - FIX: Phase_amount and Stereo_width accept 0; documented 0..1 controls are
#     validated. Output peak is bounded to (0,1].
#   - EXACT mode leaves DC and (when present) Nyquist real-only bins untouched.
#   - ROBUSTNESS: Spectrum formulas reference source objects by ID rather than
#     fragile renamed-object formula aliases. Silent output scaling is safe.
#   - FIX: final script selection is the created result, not the original input.
#   - DOCUMENTATION: modes are phase fields, not magnitude filters by themselves;
#     the previous "randomized" blur is deterministic quasi-periodic phase.
#   - VIZ: updated only because v1.1 was misleading: it now shows wrapped phase
#     rotations actually seen by cos/sin, L/R phase difference, measured dry vs
#     pure-wet spectra after the full render path, and final waveform verification.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Phase Manipulation v1.2.2
    optionmenu Preset: 1
        option Custom
        option Subtle Comb
        option Wide Phaser
        option Chaotic Texture
        option Spectral Blur
        option Formant Resonance
        option Extreme Comb
        option Deep Stereo
    comment === Transform character ===
    optionmenu Transform_character: 1
        option Legacy padded FFT (v1.1 character; runtime depends on FFT size)
        option Exact-length phase rotation
    comment === Phase Parameters ===
    real Phase_amount 50.0
    comment (phase excursion in radians; 0 = off, values wrap modulo 2*pi)
    real Stereo_width 0.2
    comment (0 = same phase field L/R, 1 = maximum differential scaling)
    optionmenu Phase_mode: 1
        option Periodic phase ripple (comb-like when mixed)
        option Multi-period phase field
        option Quasi-periodic phase blur
        option Formant-band phase bumps
    comment === Output ===
    real Dry_wet 1.0
    comment (0 = original dry, 1 = pure phase-processed wet)
    real Scale_peak 0.95
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ---------------- Presets: preserve the v1.1 phase-field values ----------------
if preset = 2
    phase_amount = 20
    stereo_width = 0.15
    phase_mode = 1
    presetName$ = "SubtleComb"
elsif preset = 3
    phase_amount = 60
    stereo_width = 0.4
    phase_mode = 1
    presetName$ = "WidePhaser"
elsif preset = 4
    phase_amount = 80
    stereo_width = 0.3
    phase_mode = 2
    presetName$ = "ChaoticTexture"
elsif preset = 5
    phase_amount = 50
    stereo_width = 0.25
    phase_mode = 3
    presetName$ = "SpectralBlur"
elsif preset = 6
    phase_amount = 40
    stereo_width = 0.2
    phase_mode = 4
    presetName$ = "FormantResonance"
elsif preset = 7
    phase_amount = 100
    stereo_width = 0.1
    phase_mode = 1
    presetName$ = "ExtremeComb"
elsif preset = 8
    phase_amount = 70
    stereo_width = 0.6
    phase_mode = 2
    presetName$ = "DeepStereo"
else
    presetName$ = "Custom"
endif

if phase_mode = 1
    modeName$ = "PeriodicRipple"
elsif phase_mode = 2
    modeName$ = "MultiPeriod"
elsif phase_mode = 3
    modeName$ = "PhaseBlur"
else
    modeName$ = "FormantPhase"
endif

# ---------------- Validation ----------------
if stereo_width < 0 or stereo_width > 1
    exitScript: "Stereo width must be between 0 and 1."
endif
if dry_wet < 0 or dry_wet > 1
    exitScript: "Dry/wet must be between 0 and 1."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

# ---------------- Transform character ----------------
if transform_character = 1
    fastFFT$ = "yes"
    transformStr$ = "legacy padded FFT + trim"
else
    fastFFT$ = "no"
    transformStr$ = "exact-length phase"
endif

# ---------------- Setup ----------------
selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency
uid$ = string$(randomInteger(10000,99999))
startTime = stopwatch

clearinfo
writeInfoLine: "=== Frequency-Dependent Phase Manipulation v1.2.2 ==="
appendInfoLine: "Input: ", originalName$, " | ", numChannels, " ch | ", fixed$(sampleRate,0), " Hz"
appendInfoLine: "Preset: ", presetName$, " | mode: ", modeName$
appendInfoLine: "Transform: ", transformStr$
appendInfoLine: "Processing rate: original sample rate (Full Quality)"
appendInfoLine: "Phase excursion: ", fixed$(phase_amount,2), " rad | stereo width: ", fixed$(stereo_width,2)
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet,2)
if numChannels > 2
    appendInfoLine: "Note: multichannel input uses channels 1 and 2 for stereo output."
endif
appendInfoLine: ""

# ---------------- Preserve original-rate dry channels ----------------
if numChannels = 1
    selectObject: originalID
    dryL = Copy: "phase_dryL_" + uid$
    selectObject: originalID
    dryR = Copy: "phase_dryR_" + uid$
else
    selectObject: originalID
    dryL = Extract one channel: 1
    Rename: "phase_dryL_" + uid$
    selectObject: originalID
    dryR = Extract one channel: 2
    Rename: "phase_dryR_" + uid$
endif

# Wet work channels remain at the original sample rate. Full Quality was not only
# the bandwidth-preserving path but benchmarked faster than the reduced-rate paths
# for common file lengths, because Praat's inverse-transform cost is size-dependent.
selectObject: dryL
workL = Copy: "phase_workL_" + uid$
selectObject: dryR
workR = Copy: "phase_workR_" + uid$
workingSR = sampleRate
workingNyquist = sampleRate / 2

# ---------------- Performance fast paths ----------------
# Dry_wet=0 is always a safe bypass because the wet path is inaudible.
# Phase_amount=0 is a safe bypass only in Exact-length mode: the Legacy
# padded+trim round-trip can itself colour the signal and is part of its sound.
fastDryBypass = (dry_wet <= 1e-12 or (transform_character = 2 and abs(phase_amount) <= 1e-12))
monoDualMono = (numChannels = 1 and abs(stereo_width) <= 1e-12)
if fastDryBypass
    appendInfoLine: "Fast path: spectral transform bypassed (dry/zero-phase result)."
elsif monoDualMono
    appendInfoLine: "Fast path: mono + stereo width 0; wet transform will run once."
endif

# ---------------- Build phase laws ----------------
amtL$ = fixed$(phase_amount, 12)
amtR$ = fixed$(phase_amount * (1 + stereo_width), 12)
if phase_mode = 1
    shiftL$ = amtL$ + " * sin(2*pi*x/200)"
    shiftR$ = amtR$ + " * sin(2*pi*x/200)"
elsif phase_mode = 2
    shiftL$ = amtL$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
    shiftR$ = amtR$ + " * (sin(2*pi*x/147) + 0.7*sin(2*pi*x/283) + 0.4*sin(2*pi*x/521))"
elsif phase_mode = 3
    shiftL$ = amtL$ + " * sin(x/37) * sin(x/113)"
    shiftR$ = amtR$ + " * sin(x/37) * sin(x/113)"
else
    shiftL$ = amtL$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
    shiftR$ = amtR$ + " * (exp(-((x-800)/300)^2) + exp(-((x-1500)/400)^2) + exp(-((x-2500)/500)^2))"
endif

# ---------------- Per-channel spectral phase processor ----------------
procedure processPhaseChannel: .snd, .shift$, .side$
    selectObject: .snd
    .workDur = Get total duration
    .workNs = Get number of samples
    To Spectrum: fastFFT$
    .spec = selected("Spectrum")
    To Matrix
    .src = selected("Matrix")
    .srcID$ = string$(.src)
    selectObject: .src
    .shifted = Copy: "phase_shifted_" + .side$ + "_" + uid$

    selectObject: .shifted
    if transform_character = 1
        # Legacy v1.1 path: rotate every stored bin exactly as before.
        Formula: "if row=1 then sqrt(object[" + .srcID$ + ",1,col]^2 + object[" + .srcID$ + ",2,col]^2) * cos(arctan2(object[" + .srcID$ + ",2,col], object[" + .srcID$ + ",1,col]) + " + .shift$ + ") else sqrt(object[" + .srcID$ + ",1,col]^2 + object[" + .srcID$ + ",2,col]^2) * sin(arctan2(object[" + .srcID$ + ",2,col], object[" + .srcID$ + ",1,col]) + " + .shift$ + ") endif"
    else
        # Exact real-signal phase rotation: DC is real-only; Nyquist is also
        # real-only when N is even. Other complex bins keep magnitude exactly.
        .evenN = (.workNs mod 2 = 0)
        .evenN$ = string$(.evenN)
        Formula: "if col=1 or (" + .evenN$ + " and col=ncol) then object[" + .srcID$ + ",row,col] else if row=1 then sqrt(object[" + .srcID$ + ",1,col]^2 + object[" + .srcID$ + ",2,col]^2) * cos(arctan2(object[" + .srcID$ + ",2,col], object[" + .srcID$ + ",1,col]) + " + .shift$ + ") else sqrt(object[" + .srcID$ + ",1,col]^2 + object[" + .srcID$ + ",2,col]^2) * sin(arctan2(object[" + .srcID$ + ",2,col], object[" + .srcID$ + ",1,col]) + " + .shift$ + ") fi fi"
    endif

    selectObject: .shifted
    To Spectrum
    .modSpec = selected("Spectrum")
    To Sound
    .wet = selected("Sound")

    # Pin the inverse transform to the working sample grid before any trim.
    # v1.1 otherwise drifted slightly in sample rate after padded FFT + Extract part.
    Override sampling frequency: workingSR

    # Legacy fast FFT returns the zero-padded duration. Trimming is deliberately
    # retained as part of that character; exact mode normally needs no trim.
    selectObject: .wet
    .wetDur = Get total duration
    if .wetDur > .workDur + 1e-9
        Extract part: 0, .workDur, "rectangular", 1, "no"
        .trim = selected("Sound")
        removeObject: .wet
        .wet = .trim
    endif

    removeObject: .spec, .src, .shifted, .modSpec
    processPhaseChannel.result = .wet
endproc

if fastDryBypass
    # Wet equals dry for the purpose of the final mix. Use original-rate copies
    # so Dry_wet=0 remains the original dry path without any transform.
    selectObject: dryL
    wetL = Copy: "phase_wetL_bypass_" + uid$
    selectObject: dryR
    wetR = Copy: "phase_wetR_bypass_" + uid$
    removeObject: workL, workR
else
    appendInfoLine: "Processing wet phase fields..."
    @processPhaseChannel: workL, shiftL$, "L"
    wetL = processPhaseChannel.result
    if monoDualMono
        selectObject: wetL
        wetR = Copy: "phase_wetR_copy_" + uid$
        removeObject: workR
    else
        @processPhaseChannel: workR, shiftR$, "R"
        wetR = processPhaseChannel.result
    endif
    removeObject: workL

endif

# Duration-safe trim after the transform.
selectObject: wetL
wetLDur = Get total duration
if wetLDur > duration + 1e-9
    Extract part: 0, duration, "rectangular", 1, "no"
    wt = selected("Sound")
    removeObject: wetL
    wetL = wt
endif
selectObject: wetR
wetRDur = Get total duration
if wetRDur > duration + 1e-9
    Extract part: 0, duration, "rectangular", 1, "no"
    wt = selected("Sound")
    removeObject: wetR
    wetR = wt
endif

# Preserve pure wet for process verification only.
if draw_visualization
    selectObject: wetL
    wetVizL = Copy: "phase_wetVizL_" + uid$
endif

# ---------------- Dry/wet: original-rate dry path ----------------
wetStr$ = fixed$(dry_wet, 12)
dryStr$ = fixed$(1-dry_wet, 12)
dryLstr$ = string$(dryL)
dryRstr$ = string$(dryR)
if dry_wet < 0.999999999
    selectObject: wetL
    Formula: "self*" + wetStr$ + " + object[" + dryLstr$ + ",1,col]*" + dryStr$
    selectObject: wetR
    Formula: "self*" + wetStr$ + " + object[" + dryRstr$ + ",1,col]*" + dryStr$
endif

selectObject: wetL
plusObject: wetR
resultID = Combine to stereo
Rename: originalName$ + "_phase_" + modeName$
selectObject: resultID
resultPeakBefore = Get absolute extremum: 0, 0, "None"
if resultPeakBefore > 1e-12
    Scale peak: scale_peak
endif

processingTime = stopwatch - startTime

# ============================================================
# VISUALIZATION - changed only where v1.1 did not tell the true phase story
# ============================================================
if draw_visualization
    appendInfoLine: "Drawing process visualization..."

    # Final output channels for waveform verification.
    selectObject: resultID
    finalL = Extract one channel: 1
    Rename: "phase_finalL_" + uid$
    selectObject: resultID
    finalR = Extract one channel: 2
    Rename: "phase_finalR_" + uid$

    selectObject: dryL
    srcPeak = Get absolute extremum: 0, 0, "None"
    srcRms = Get root-mean-square: 0, 0
    selectObject: wetVizL
    wetPeak = Get absolute extremum: 0, 0, "None"
    wetRms = Get root-mean-square: 0, 0
    selectObject: finalL
    finalPeakL = Get absolute extremum: 0, 0, "None"
    finalRmsL = Get root-mean-square: 0, 0
    selectObject: finalR
    finalPeakR = Get absolute extremum: 0, 0, "None"
    finalRmsR = Get root-mean-square: 0, 0
    wavePeak = 1.05 * max(srcPeak, max(finalPeakL, finalPeakR))
    if wavePeak < 1e-8
        wavePeak = 1
    endif

    # Measured spectra AFTER the actual transform/trim/resample path.
    selectObject: dryL
    drySpec = To Spectrum: "yes"
    selectObject: wetVizL
    wetSpec = To Spectrum: "yes"

    vizFreqMax = min(10000, sampleRate/2)
    phaseFreqMax = min(5000, workingNyquist)
    if phaseFreqMax < 200
        phaseFreqMax = workingNyquist
    endif

    Erase all

    # ---- Header ----
    Select outer viewport: 0,8,0,0.42
    Select inner viewport: 0,8,0,0.42
    Axes: 0,1,0,1
    Font size: 12
    Colour: "Black"
    Text: 0.5,"centre",0.58,"half","Frequency-Dependent Phase Manipulation v1.2.2 — " + presetName$

    Select outer viewport: 0,8,0.44,0.72
    Select inner viewport: 0,8,0.44,0.72
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half","spectrum -> frequency-dependent complex rotation -> inverse transform -> dry/wet interference -> stereo output | " + transformStr$

    # ---- A title ----
    Select outer viewport: 0,8,0.80,1.00
    Select inner viewport: 0,8,0.80,1.00
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","A  Actual wrapped phase rotation and L/R phase difference"

    # ---- A data: wrapped phase ----
    Select outer viewport: 0,8,1.02,2.35
    Select inner viewport: 0.65,7.72,1.10,2.18
    Axes: 0,phaseFreqMax,-pi,pi
    Paint rectangle: "{0.975,0.975,0.978}",0,phaseFreqMax,-pi,pi
    nPhase = 420
    havePrev = 0
    for q from 0 to nPhase
        f = phaseFreqMax*q/nPhase
        if phase_mode = 1
            baseShape = sin(2*pi*f/200)
        elsif phase_mode = 2
            baseShape = sin(2*pi*f/147) + 0.7*sin(2*pi*f/283) + 0.4*sin(2*pi*f/521)
        elsif phase_mode = 3
            baseShape = sin(f/37)*sin(f/113)
        else
            baseShape = exp(-((f-800)/300)^2) + exp(-((f-1500)/400)^2) + exp(-((f-2500)/500)^2)
        endif
        rawL = phase_amount*baseShape
        rawR = phase_amount*(1+stereo_width)*baseShape
        wrapL = rawL - 2*pi*floor((rawL+pi)/(2*pi))
        wrapR = rawR - 2*pi*floor((rawR+pi)/(2*pi))
        rawD = rawR-rawL
        wrapD = rawD - 2*pi*floor((rawD+pi)/(2*pi))
        if havePrev
            if abs(wrapL-prevL) < pi
                Colour: "{0.25,0.50,0.80}"
                Line width: 1.5
                Draw line: prevF,prevL,f,wrapL
            endif
            if abs(wrapR-prevR) < pi
                Colour: "{0.80,0.38,0.24}"
                Line width: 1
                Draw line: prevF,prevR,f,wrapR
            endif
            if abs(wrapD-prevD) < pi
                Colour: "{0.25,0.62,0.40}"
                Line width: 1
                Draw line: prevF,prevD,f,wrapD
            endif
        endif
        prevF=f
        prevL=wrapL
        prevR=wrapR
        prevD=wrapD
        havePrev=1
    endfor
    Line width: 1
    Select inner viewport: 0.65,7.72,1.10,2.18
    Axes: 0,phaseFreqMax,-pi,pi
    Colour: "Black"
    Draw inner box
    Font size: 5
    One mark left: -pi,"no","yes","no","-pi"
    One mark left: 0,"no","yes","no","0"
    One mark left: pi,"no","yes","no","+pi"
    freqStep = max(250, round(phaseFreqMax/5/250)*250)
    nFM = floor(phaseFreqMax/freqStep)
    for q from 0 to nFM
        ff=q*freqStep
        if ff>=1000
            lab$=fixed$(ff/1000,1)+"k"
        else
            lab$=fixed$(ff,0)
        endif
        One mark bottom: ff,"no","yes","no",lab$
    endfor
    Font size: 5
    Colour: "{0.25,0.50,0.80}"
    Text: 0.02*phaseFreqMax,"left",0.82*pi,"half","blue phiL"
    Colour: "{0.80,0.38,0.24}"
    Text: 0.20*phaseFreqMax,"left",0.82*pi,"half","red phiR"
    Colour: "{0.25,0.62,0.40}"
    Text: 0.38*phaseFreqMax,"left",0.82*pi,"half","green delta(L,R)"

    Select outer viewport: 0,8,2.35,2.53
    Select inner viewport: 0,8,2.35,2.53
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half","X'(f)=X(f) exp(i phi(f)); plotted phase is wrapped to [-pi,pi] because cos/sin see phase modulo 2*pi | frequency in Hz"

    # ---- B title ----
    Select outer viewport: 0,8,2.60,2.80
    Select inner viewport: 0,8,2.60,2.80
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","B  Measured magnitude consequence: original dry vs pure wet L"

    # ---- B data ----
    Select outer viewport: 0,8,2.82,4.12
    Select inner viewport: 0.68,7.72,2.90,3.96
    selectObject: drySpec
    Colour: "{0.60,0.60,0.62}"
    Line width: 1.5
    Draw: 0,vizFreqMax,0,80,"no"
    selectObject: wetSpec
    Colour: "{0.25,0.50,0.80}"
    Line width: 1
    Draw: 0,vizFreqMax,0,80,"no"
    Select inner viewport: 0.68,7.72,2.90,3.96
    Axes: 0,vizFreqMax,0,80
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 5
    Marks left every: 1,20,"yes","yes","no"
    fStepB=max(1000,round(vizFreqMax/6/1000)*1000)
    nFB=floor(vizFreqMax/fStepB)
    for q from 0 to nFB
        ff=q*fStepB
        if ff>=1000
            lab$=fixed$(ff/1000,1)+"k"
        else
            lab$=fixed$(ff,0)
        endif
        One mark bottom: ff,"no","yes","no",lab$
    endfor
    Font size: 5
    Colour: "{0.55,0.55,0.58}"
    Text: 0.02*vizFreqMax,"left",75,"half","gray dry"
    Colour: "{0.25,0.50,0.80}"
    Text: 0.18*vizFreqMax,"left",75,"half","blue pure wet L"

    Select outer viewport: 0,8,4.12,4.30
    Select inner viewport: 0,8,4.12,4.30
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    if transform_character = 1
        Text: 0.5,"centre",0.5,"half","legacy padded FFT: phase rotation preserves FFT-bin magnitude, but trim can colour the measured wet spectrum | wet/dry RMS=" + fixed$(wetRms/max(srcRms,1e-12),3)
    else
        Text: 0.5,"centre",0.5,"half","exact-length mode: pure wet should retain source magnitude shape; dry/wet mixing can then create interference coloration | wet/dry RMS=" + fixed$(wetRms/max(srcRms,1e-12),3)
    endif

    # ---- C title ----
    Select outer viewport: 0,8,4.37,4.57
    Select inner viewport: 0,8,4.37,4.57
    Axes: 0,1,0,1
    Font size: 9
    Colour: "Black"
    Text: 0.02,"left",0.5,"half","C  Measured time-domain result (source and final L/R, shared amplitude scale)"

    # source stave
    Select outer viewport: 0,8,4.59,5.22
    Select inner viewport: 0.68,7.72,4.63,5.16
    selectObject: dryL
    Colour: "{0.60,0.60,0.62}"
    Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    Select inner viewport: 0.68,7.72,4.63,5.16
    Axes: 0,duration,-wavePeak,wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes","source"

    # final L stave
    Select outer viewport: 0,8,5.22,5.85
    Select inner viewport: 0.68,7.72,5.26,5.79
    selectObject: finalL
    Colour: "{0.25,0.50,0.80}"
    Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    Select inner viewport: 0.68,7.72,5.26,5.79
    Axes: 0,duration,-wavePeak,wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes","L"

    # final R stave with time marks only here
    Select outer viewport: 0,8,5.85,6.48
    Select inner viewport: 0.68,7.72,5.89,6.42
    selectObject: finalR
    Colour: "{0.80,0.38,0.24}"
    Draw: 0,0,-wavePeak,wavePeak,"no","Curve"
    Select inner viewport: 0.68,7.72,5.89,6.42
    Axes: 0,duration,-wavePeak,wavePeak
    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes","R"
    tStep=max(0.1,round(duration/5*10)/10)
    Marks bottom every: 1,tStep,"yes","yes","no"

    Select outer viewport: 0,8,6.48,6.66
    Select inner viewport: 0,8,6.48,6.66
    Axes: 0,1,0,1
    Font size: 6
    Colour: "{0.34,0.34,0.42}"
    Text: 0.5,"centre",0.5,"half","time in seconds | final peak L/R=" + fixed$(finalPeakL,3) + "/" + fixed$(finalPeakR,3) + " | RMS=" + fixed$(finalRmsL,3) + "/" + fixed$(finalRmsR,3)

    # ---- QC strip ----
    Select outer viewport: 0,8,6.74,7.46
    Select inner viewport: 0.18,7.82,6.78,7.42
    Axes: 0,3,0,2
    Paint rectangle: "{0.965,0.965,0.97}",0,3,0,2
    Colour: "{0.82,0.82,0.84}"
    Draw line: 1,0,1,2
    Draw line: 2,0,2,2
    Draw line: 0,1,3,1
    Colour: "Black"
    Draw rectangle: 0,3,0,2
    Font size: 5.5
    Text: 0.05,"left",1.55,"half","mode: " + modeName$ + " | phase " + fixed$(phase_amount,1) + " rad"
    Text: 1.05,"left",1.55,"half","stereo width: " + fixed$(stereo_width,2) + " | wet " + fixed$(dry_wet,2)
    Text: 2.05,"left",1.55,"half","transform: " + if transform_character=1 then "legacy padded" else "exact length" fi
    Text: 0.05,"left",0.55,"half","Full Quality: " + fixed$(workingSR,0) + " Hz | Nyq " + fixed$(workingNyquist,0)
    if numChannels=1
        inputMode$="mono -> synthetic stereo"
    else
        inputMode$="native L/R processed"
    endif
    Text: 1.05,"left",0.55,"half",inputMode$
    Text: 2.05,"left",0.55,"half","render " + fixed$(processingTime,2) + " s | output peak " + fixed$(max(finalPeakL,finalPeakR),3)

    removeObject: drySpec, wetSpec, wetVizL, finalL, finalR
endif

# ---------------- Cleanup / output ----------------
removeObject: dryL, dryR, wetL, wetR

appendInfoLine: ""
appendInfoLine: "Processing time: ", fixed$(processingTime,2), " seconds"
appendInfoLine: "Created: ", originalName$ + "_phase_" + modeName$
appendInfoLine: "Pure-wet phase fields use radians modulo 2*pi."
if transform_character = 1
    appendInfoLine: "Legacy padded FFT character retained; trim may add magnitude coloration."
else
    appendInfoLine: "Exact-length transform selected; DC/Nyquist real-only bins are retained."
endif

selectObject: resultID
if play_result
    Play
endif
selectObject: resultID
