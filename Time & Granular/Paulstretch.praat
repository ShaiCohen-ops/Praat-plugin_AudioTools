# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Paulstretch - extreme time stretching with phase randomization.
#
# Changelog v1.1 (audio CHANGES from v1.0 - both fixes are intentional):
#
#   FIX A -- "clicks" eliminated.
#     v1.0 produced an audible click every `hopOut` seconds (around
#     16 Hz at the default 0.25 s window, 75 % overlap). Root cause:
#       Praat's `To Spectrum: "yes"` uses the fast FFT path, which
#       silently zero-pads the input up to the next power of 2 for
#       efficiency. The resulting Spectrum has frequency step
#       dx = 1 / paddedDuration, NOT 1 / windowDuration. When the
#       inverse `To Sound` is then taken, the output Sound has
#       duration `paddedDuration = nextPow2(windowSamples) / sr`,
#       which is LONGER than the original `window_size_s`.
#       v1.0 then called `Multiply by window: "Hanning"` on this
#       longer sound, so the Hann window spanned [0, paddedDuration]
#       rather than [0, window_size_s]. v1.0 then overlap-added only
#       the FIRST `window_size_s` of this longer sound back into the
#       output (via `Formula (part): .tOut, .tOut + window_size_s`).
#       At the cutoff point (sample `windowSamples` of `.processed`)
#       the Hann value was Hann(window_size_s / paddedDuration), which
#       at the default 0.25 s window / 0.371 s paddedDuration is
#       ~0.74 -- not zero. So each frame's contribution to the output
#       ended with a non-zero value that was abruptly truncated, and
#       the next sample beyond the iterated range got no contribution
#       from this frame at all. That step of size 0.74 x audio_value,
#       repeating every `hopOut` seconds across all frames, is what
#       was heard as clicks.
#     v1.1 fix: round `windowSamples` UP to the next power of 2
#     before computing anything, so the FFT input is already pow2 and
#     `To Spectrum: "yes"` doesn't add any padding. `procDur` then
#     equals `window_size_s` exactly, the synthesis Hann zeros the
#     edges of the actually-used range, and overlap-add is COLA-clean
#     at the user's overlap setting.
#     Side effect: the effective window size differs slightly from the
#     user's input (rounded UP to nearest pow2). For the default 0.25 s
#     request at 22.05 kHz: 5512 samples -> 8192 samples = 0.371 s.
#     This is reported in the info log.
#
#   FIX B -- phase randomization corrected.
#     v1.0 Formula on the 2-row complex Matrix had two compounding bugs:
#       (1) In-place evaluation. When Praat processed row=2 of a column,
#           it read object[.matID, 1, col] -- but row 1 had ALREADY been
#           overwritten by the row=1 branch with `mag * cos(rand)`. So
#           the magnitude computed for row 2 was
#               sqrt((mag*cos(rand1))^2 + orig_imag^2)
#           not the original `sqrt(orig_real^2 + orig_imag^2)`.
#       (2) Two independent `randomUniform(-pi, pi)` calls -- one inside
#           cos(), one inside sin() -- gave row 1 and row 2 DIFFERENT
#           random phases. So new_real and new_imag at the same bin
#           weren't a coherent (mag, theta) pair; they were independent
#           scrambles.
#       Net effect: each frame's spectrum had random magnitudes as well
#       as random phases, breaking Paulstretch's "preserve magnitudes"
#       property. Audible as graininess and a brighter / noisier
#       character than canonical Paulstretch.
#     v1.1 fix: precompute the magnitudes into a separate Matrix and
#     the random phases into another, both indexed by column. The main
#     Formula on `.matComplex` then reads these via `object[]` (so
#     row 2 sees the original magnitude, not a modified row 1) and uses
#     the same phase value for both cos() and sin().
# ============================================================

form Paulstretch v1.1
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Stretch (2x)
        option Classic Paulstretch (8x)
        option Extreme Stretch (16x)
        option Quick Test (4x)
    
    comment === Performance ===
    optionmenu Speed_mode: 2
        option Full Quality (original sample rate)
        option Balanced (downsample to 22 kHz)
        option Fast (downsample to 11 kHz)
    
    comment === Parameters ===
    positive Stretch_factor 4.0
    positive Window_size_s 0.25
    positive Overlap_percent 75
    
    comment === Output ===
    boolean Create_stereo 1
    positive Stereo_phase_offset 0.3
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# Apply Presets
if preset = 2
    stretch_factor = 2.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.2
    preset_name$ = "Subtle"
elsif preset = 3
    stretch_factor = 8.0
    window_size_s = 0.25
    overlap_percent = 75
    create_stereo = 1
    stereo_phase_offset = 0.3
    preset_name$ = "Classic"
elsif preset = 4
    stretch_factor = 16.0
    window_size_s = 0.5
    overlap_percent = 80
    create_stereo = 1
    stereo_phase_offset = 0.4
    preset_name$ = "Extreme"
elsif preset = 5
    stretch_factor = 4.0
    window_size_s = 0.15
    overlap_percent = 75
    create_stereo = 0
    stereo_phase_offset = 0.0
    preset_name$ = "QuickTest"
else
    preset_name$ = "Custom"
endif

# Set target sample rate
if speed_mode = 1
    targetSR = 0
    speedStr$ = "Full Quality"
elsif speed_mode = 2
    targetSR = 22050
    speedStr$ = "Balanced"
else
    targetSR = 11025
    speedStr$ = "Fast"
endif

# Check Input
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
sampleRate = Get sampling frequency
inputDuration = Get total duration
numChannels = Get number of channels

startTime = stopwatch

# Convert to Mono
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "mono_temp"
    sourceSound = selected("Sound")
endif

# === OPTIONAL DOWNSAMPLING ===
if targetSR > 0 and sampleRate > targetSR
    selectObject: sourceSound
    Resample: targetSR, 50
    resampledID = selected("Sound")
    removeObject: sourceSound
    sourceSound = resampledID
    workingSR = targetSR
else
    workingSR = sampleRate
endif

# === FIX A: round windowSamples UP to the next power of 2 ===
# This prevents Praat's `To Spectrum: "yes"` from silently
# zero-padding the FFT input. With windowSamples already pow2,
# the IFFT output has duration exactly window_size_s, so the
# synthesis Hanning window zeros the edges of the range that
# overlap-add actually uses. No step discontinuity, no clicks.
requestedWindowSizeS = window_size_s
requestedWindowSamples = round(window_size_s * workingSR)

windowSamples = 1
while windowSamples < requestedWindowSamples
    windowSamples = windowSamples * 2
endwhile

window_size_s = windowSamples / workingSR

overlapFrac = overlap_percent / 100
hopOut = window_size_s * (1 - overlapFrac)
hopIn = hopOut / stretch_factor
outputDuration = inputDuration * stretch_factor
nFrames = ceiling(outputDuration / hopOut) + 1

microFadeDur = 0.003

# Info
writeInfoLine: "=== Paulstretch v1.1 ==="
appendInfoLine: "Preset: ", preset_name$
appendInfoLine: "Speed:  ", speedStr$
appendInfoLine: "Source: ", original_name$, " (", fixed$(inputDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Stretch: ", stretch_factor, "x"
if abs(window_size_s - requestedWindowSizeS) > 0.0005
    appendInfoLine: "Window:  ", fixed$(window_size_s, 4), " s (", windowSamples,
        ... " samples; pow2-rounded up from request of ", fixed$(requestedWindowSizeS, 4), " s)"
else
    appendInfoLine: "Window:  ", fixed$(window_size_s, 4), " s (", windowSamples, " samples)"
endif
appendInfoLine: "Output:  ", fixed$(outputDuration, 2), " s"
appendInfoLine: "Frames:  ", nFrames
appendInfoLine: "Overlap: ", overlap_percent, "%"
if create_stereo
    appendInfoLine: "Mode:    STEREO (phase offset: ", stereo_phase_offset, ")"
else
    appendInfoLine: "Mode:    MONO"
endif
appendInfoLine: ""

# Process Channel Procedure
procedure processChannel: .outputID, .phaseScale, .channelName$
    appendInfoLine: "Processing ", .channelName$, " channel..."
    
    .progressInterval = max(1, round(nFrames / 10))
    
    for .iframe from 0 to nFrames - 1
        if .iframe mod .progressInterval = 0
            appendInfoLine: "  ", floor(.iframe / nFrames * 100), "%"
        endif
        
        .tIn = .iframe * hopIn
        .tStart = .tIn - window_size_s / 2
        .tEnd = .tIn + window_size_s / 2
        
        selectObject: sourceSound
        .extractStart = max(0, .tStart)
        .extractEnd = min(inputDuration, .tEnd)
        
        if .extractEnd > .extractStart
            Extract part: .extractStart, .extractEnd, "Hanning", 1.0, "no"
            .frame = selected("Sound")
            
            selectObject: .frame
            .durFrame = Get total duration
            
            # Pad if needed
            if abs(.durFrame - window_size_s) > 0.00001
                Create Sound from formula: "padded", 1, 0, window_size_s, workingSR, "0"
                .padded = selected("Sound")
                .offset = max(0, -.tStart)
                .sOffset$ = fixed$(.offset, 6)
                .sEnd$ = fixed$(.offset + .durFrame, 6)
                .frameID = .frame
                selectObject: .padded
                Formula: "if x >= " + .sOffset$ + " and x <= " + .sEnd$ + " then object(" + string$(.frameID) + ", x - " + .sOffset$ + ") else 0 fi"
                removeObject: .frame
                .frame = .padded
            endif
            
            # FFT (input is already pow2 thanks to Fix A, so no auto-padding)
            selectObject: .frame
            To Spectrum: "yes"
            .spectrum = selected("Spectrum")
            
            To Matrix
            .matComplex = selected("Matrix")
            
            selectObject: .matComplex
            .ncols = Get number of columns
            .matID = .matComplex
            
            # === FIX B: phase randomization via auxiliary matrices ===
            # v1.0's in-place Formula on .matComplex had two bugs:
            #   (1) Row 2 read row 1 AFTER row 1 had been overwritten,
            #       corrupting the magnitude term for the imag part.
            #   (2) cos() and sin() called randomUniform() independently,
            #       so real and imag got DIFFERENT random phases.
            # v1.1 precomputes magnitudes and phases into separate
            # matrices, then the main Formula reads them via object[]
            # (so the original magnitudes survive) and uses the same
            # phase value for cos() and sin() (so real/imag are a
            # coherent rotation).

            # Magnitudes -> row 1 of .magsMat (row 2 left alone, unused)
            selectObject: .matComplex
            Copy: "mags_aux"
            .magsMat = selected("Matrix")
            Formula: "if row = 1 then sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) else self fi"

            # Random phases -> row 1 of .phasesMat (one phase per column)
            selectObject: .matComplex
            Copy: "phases_aux"
            .phasesMat = selected("Matrix")
            Formula: "if row = 1 then randomUniform(-pi, pi) * .phaseScale else self fi"

            # Apply: new_real = mag * cos(phase),  new_imag = mag * sin(phase)
            # DC (col=1) and Nyquist (col=.ncols) preserved.
            selectObject: .matComplex
            Formula: "if col = 1 or col = .ncols then self else if row = 1 then object[.magsMat, 1, col] * cos(object[.phasesMat, 1, col]) else object[.magsMat, 1, col] * sin(object[.phasesMat, 1, col]) fi fi"

            removeObject: .magsMat, .phasesMat

            # IFFT
            selectObject: .matComplex
            To Spectrum
            .spectrumMod = selected("Spectrum")
            
            To Sound
            .processed = selected("Sound")
            
            # Window (Fix A guarantees .processed duration == window_size_s,
            # so the Hann zeros the edges of the actually-used range)
            selectObject: .processed
            Multiply by window: "Hanning"
            
            # Micro-fades (kept for defensive zero-edge enforcement;
            # post-Fix A, these are redundant with the Hann zeros but
            # harmless -- they cost a microsecond and protect against
            # any floating-point edge residue.)
            .procDur = Get total duration
            .fadeDur = min(microFadeDur, .procDur * 0.05)
            if .fadeDur > 0.0005
                Fade in: 0, 0, .fadeDur, "yes"
                Fade out: 0, .procDur - .fadeDur, .fadeDur, "yes"
            endif
            
            # Overlap-add (now click-free: every frame's contribution
            # is zero at its iterated-range endpoint, since the Hann
            # was applied over exactly window_size_s)
            .tOut = .iframe * hopOut

            selectObject: .processed
            .procNs = Get number of samples

            selectObject: .outputID
            .s1 = Get sample number from time: .tOut
            if .s1 < 1
                .s1 = 1
            endif
            .s2 = .s1 + .procNs - 1
            .outNs = Get number of samples
            if .s2 > .outNs
                .s2 = .outNs
            endif
            .sOff = .s1 - 1

            .tOutEnd = .tOut + window_size_s
            if .tOutEnd > outputDuration + window_size_s
                .tOutEnd = outputDuration + window_size_s
            endif

            Formula (part): .tOut, .tOutEnd, 1, 1,
                ... "self + object[" + string$(.processed) + ", col - " + string$(.sOff) + "]"
            
            removeObject: .frame, .spectrum, .matComplex, .spectrumMod, .processed
        endif
    endfor
endproc

# Process Left/Mono Channel
Create Sound from formula: "output_L", 1, 0, outputDuration + window_size_s, workingSR, "0"
outputL = selected("Sound")

if create_stereo
    @processChannel: outputL, 1.0, "LEFT"
else
    @processChannel: outputL, 1.0, "MONO"
endif

# Process Right Channel
if create_stereo
    appendInfoLine: ""
    
    Create Sound from formula: "output_R", 1, 0, outputDuration + window_size_s, workingSR, "0"
    outputR = selected("Sound")
    
    phaseScale = 1 + stereo_phase_offset
    @processChannel: outputR, phaseScale, "RIGHT"
    
    # Combine to stereo
    selectObject: outputL, outputR
    Combine to stereo
    result = selected("Sound")
    
    removeObject: outputL, outputR
else
    result = outputL
endif

# === UPSAMPLE IF NEEDED ===
if targetSR > 0 and sampleRate > targetSR
    appendInfoLine: ""
    appendInfoLine: "Upsampling to ", sampleRate, " Hz..."
    selectObject: result
    Resample: sampleRate, 50
    upsampledID = selected("Sound")
    removeObject: result
    result = upsampledID
endif

# Finalize
selectObject: result
Scale peak: 0.95

# Trim excess
resultDur = Get total duration
if resultDur > outputDuration + 0.1
    Extract part: 0, outputDuration + 0.05, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
endif

selectObject: result
if create_stereo
    Rename: original_name$ + "_PS_" + preset_name$ + "_stereo"
else
    Rename: original_name$ + "_PS_" + preset_name$
endif

removeObject: sourceSound

selectObject: result
finalDuration = Get total duration

processingTime = stopwatch - startTime

# Visualization
if draw_visualization
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # ----------------------------------------------------------
    # Title
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.45
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half", "##Paulstretch - Spectral Time Stretch##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.25, "half",
        ... original_name$ + "  |  " + preset_name$
        ... + "  |  " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  " + speedStr$
        ... + "  |  " + fixed$(processingTime, 1) + "s"

    # ----------------------------------------------------------
    # Input waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.52, 1.42
    Select inner viewport: 0.55, 7.65, 0.57, 1.37
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text top: "no", "Original  (" + fixed$(inputDuration, 2) + " s)"

    # ----------------------------------------------------------
    # Output waveform
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 1.46, 2.36
    Select inner viewport: 0.55, 7.65, 1.51, 2.31
    selectObject: result
    nChResult = Get number of channels
    if nChResult > 1
        Extract one channel: 1
        vizL = selected("Sound")
        Colour: "{0.25, 0.50, 0.82}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        selectObject: result
        Extract one channel: 2
        vizR = selected("Sound")
        Colour: "{0.82, 0.45, 0.25}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        removeObject: vizL, vizR
    else
        selectObject: result
        Colour: "{0.35, 0.58, 0.78}"
        Draw: 0, 0, 0, 0, "no", "Curve"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Stretched"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Output  (" + fixed$(finalDuration, 2) + " s,  " + fixed$(stretch_factor, 1) + "x)"

    # ----------------------------------------------------------
    # Original spectrogram (left half)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.1, 2.44, 3.84
    Select inner viewport: 0.55, 3.85, 2.54, 3.74
    selectObject: original
    if numChannels > 1
        Extract one channel: 1
        vizSpecOrig = selected("Sound")
    else
        Copy: "vizSpecOrig"
        vizSpecOrig = selected("Sound")
    endif
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: origSpec, vizSpecOrig
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Original spectrogram"

    # ----------------------------------------------------------
    # Stretched spectrogram (right half)
    # ----------------------------------------------------------
    Select outer viewport: 4.1, 8, 2.44, 3.84
    Select inner viewport: 4.40, 7.65, 2.54, 3.74
    selectObject: result
    if nChResult > 1
        Extract one channel: 1
        vizSpecOut = selected("Sound")
    else
        Copy: "vizSpecOut"
        vizSpecOut = selected("Sound")
    endif
    resDur = Get total duration
    showDur = min(10, resDur)
    To Spectrogram: 0.03, 5000, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, showDur, 0, 5000, 100, "yes", 50, 6, 0, "no"
    removeObject: resSpec, vizSpecOut
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Stretched spectrogram"

    # ----------------------------------------------------------
    # Summary panel
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.92, 4.72
    Select inner viewport: 0.55, 7.65, 3.98, 4.66
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.82, "half", "##Summary##"
    Font size: 6
    Colour: "{0.30, 0.30, 0.30}"

    if create_stereo
        stereoStr$ = "Stereo (offset=" + fixed$(stereo_phase_offset, 2) + ")"
    else
        stereoStr$ = "Mono"
    endif

    Text: 0.02, "left", 0.52, "half",
        ... "Preset: " + preset_name$
        ... + "  |  Stretch: " + fixed$(stretch_factor, 1) + "x"
        ... + "  |  Window: " + fixed$(window_size_s, 3) + " s (" + string$(windowSamples) + " smp)"
        ... + "  |  Overlap: " + fixed$(overlap_percent, 0) + "%"
        ... + "  |  " + stereoStr$
    Text: 0.02, "left", 0.18, "half",
        ... "In: " + fixed$(inputDuration, 2) + " s -> Out: " + fixed$(finalDuration, 2) + " s"
        ... + "  |  " + speedStr$
        ... + "  |  Frames: " + string$(nFrames)
        ... + "  |  Render: " + fixed$(processingTime, 1) + " s"
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
endif

# Final Info
selectObject: result

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Processing time: ", fixed$(processingTime, 2), " seconds"
appendInfoLine: "Created: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"

# Play
if play_result
    selectObject: result
    Play
endif

selectObject: result
