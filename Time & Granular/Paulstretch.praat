# ============================================================
# Praat AudioTools - Paulstretch.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Paulstretch - extreme time stretching with phase randomization.
#
# Changelog v1.2 (internal DSP / compatibility pass):
#   Public parameter signature is intentionally unchanged from v1.1; only the form title version is updated.
#   - FIX C: zero-based working source. Inputs whose Sound domain does not
#     start at 0 are now shifted on an internal copy before frame extraction.
#   - FIX D: edge analysis windows. v1.1 windowed a truncated edge frame and
#     only then zero-padded it; this made the first/last real sample sit at a
#     Hann zero instead of at the correct part of a full centred window.
#     v1.2 extracts rectangularly, pads first, then applies one full Hann.
#   - FIX E: frame-centre alignment. Output frames are placed at
#     iframe*hopOut - window/2 on an extended timeline, then trimmed exactly
#     to inputDuration*stretchFactor. This removes the half-window latency.
#   - FIX F: overlap-add normalization. A shared synthesis-Hann weight buffer
#     is accumulated and each rendered channel is divided by it, preventing
#     overlap-dependent gain / breathing for arbitrary legal overlaps.
#   - FIX G: stereo phase control. L/R now reuse the SAME random phase draw
#     for every frame/bin; Right adds Stereo_phase_offset*pi. Thus offset=0
#     produces identical L/R, while larger values create a true controlled
#     quadrature-style phase separation. v1.1 used independent random draws,
#     so the parameter could not actually control inter-channel offset.
#   - FIX H: final duration is exactly the requested stretched duration rather
#     than target + ~50 ms. Peak scaling is now a safety ceiling only.
#   - Added guards for overlap < 100%, effective window >= 4 samples, and
#     finite frame counts. Visualization frequency is capped at Nyquist.
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

form Paulstretch v1.2
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
sourceStart = Get start time
sourceEnd = Get end time

# Runtime guards keep the external parameter list unchanged.
if overlap_percent <= 0 or overlap_percent >= 100
    exitScript: "Overlap percent must be > 0 and < 100"
endif
if stretch_factor <= 0
    exitScript: "Stretch factor must be > 0"
endif
if window_size_s <= 0
    exitScript: "Window size must be > 0"
endif
if stereo_phase_offset < 0
    exitScript: "Stereo phase offset must be >= 0"
endif

startTime = stopwatch

# Convert to mono for the Paulstretch engine, then force the INTERNAL copy to
# a zero-based time domain. The selected original object is never modified.
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "mono_temp"
    sourceSound = selected("Sound")
endif
selectObject: sourceSound
Shift times to: "start time", 0

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

selectObject: sourceSound
workingDuration = Get total duration
# === FIX A: round windowSamples UP to the next power of 2 ===
# This prevents Praat's `To Spectrum: "yes"` from silently
# zero-padding the FFT input. With windowSamples already pow2,
# the IFFT output has duration exactly window_size_s, so the
# synthesis Hanning window zeros the edges of the range that
# overlap-add actually uses. No step discontinuity, no clicks.
requestedWindowSizeS = window_size_s
requestedWindowSamples = round(window_size_s * workingSR)
if requestedWindowSamples < 4
    exitScript: "Effective window must contain at least 4 samples"
endif

windowSamples = 1
while windowSamples < requestedWindowSamples
    windowSamples = windowSamples * 2
endwhile

window_size_s = windowSamples / workingSR

overlapFrac = overlap_percent / 100
hopOut = window_size_s * (1 - overlapFrac)
hopIn = hopOut / stretch_factor
outputDuration = inputDuration * stretch_factor
nFrames = ceiling(workingDuration / hopIn) + 1
if nFrames < 1 or nFrames > 250000
    exitScript: "Requested stretch/window/overlap would require an impractical number of frames (" + string$(nFrames) + ")"
endif

# Shared random seeds make L/R phase draws corresponding rather than
# independent. The seeds themselves are unpredictable between runs.
frameSeeds# = randomInteger#(nFrames, 1, 2000000000)

# Info
writeInfoLine: "=== Paulstretch v1.2 ==="
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
    appendInfoLine: "Mode:    STEREO (controlled phase offset: ", stereo_phase_offset, ")"
else
    appendInfoLine: "Mode:    MONO"
endif
appendInfoLine: ""

# Process Channel Procedure
# .writeNorm is 1 only for the first rendered channel. Both channels use the
# same frame geometry, so one shared normalization track is sufficient.
procedure processChannel: .outputID, .phaseOffset, .channelName$, .writeNorm
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
        .extractEnd = min(workingDuration, .tEnd)
        
        if .extractEnd > .extractStart
            # Edge correctness: extract rectangularly, place into the proper
            # position of a full zero-padded frame, THEN apply the full Hann.
            Extract part: .extractStart, .extractEnd, "rectangular", 1.0, "no"
            .frame = selected("Sound")
            selectObject: .frame
            .durFrame = Get total duration
            
            if abs(.durFrame - window_size_s) > 0.5 / workingSR or .tStart < 0 or .tEnd > workingDuration
                Create Sound from formula: "padded", 1, 0, window_size_s, workingSR, "0"
                .padded = selected("Sound")
                .offset = max(0, -.tStart)
                .sOffset$ = fixed$(.offset, 9)
                .sEnd$ = fixed$(min(window_size_s, .offset + .durFrame), 9)
                .frameID = .frame
                selectObject: .padded
                Formula: "if x >= " + .sOffset$ + " and x <= " + .sEnd$ + " then object(" + string$(.frameID) + ", x - " + .sOffset$ + ") else 0 fi"
                removeObject: .frame
                .frame = .padded
            endif
            
            selectObject: .frame
            Multiply by window: "Hanning"
            
            # FFT (input sample count is power of two; no hidden padding).
            To Spectrum: "yes"
            .spectrum = selected("Spectrum")
            To Matrix
            .matComplex = selected("Matrix")
            selectObject: .matComplex
            .ncols = Get number of columns
            .matID = .matComplex
            
            # Preserve magnitudes in a frozen auxiliary matrix.
            Copy: "mags_aux"
            .magsMat = selected("Matrix")
            Formula: "if row = 1 then sqrt(object[.matID, 1, col]^2 + object[.matID, 2, col]^2) else self fi"
            
            # Use the SAME base random phase sequence for both rendered
            # channels. Left offset=0; Right offset=Stereo_phase_offset*pi.
            random_initializeWithSeedUnsafelyButPredictably(frameSeeds#[.iframe + 1])
            selectObject: .matComplex
            Copy: "phases_aux"
            .phasesMat = selected("Matrix")
            Formula: "if row = 1 then randomUniform(-pi, pi) + .phaseOffset * pi else self fi"
            
            selectObject: .matComplex
            Formula: "if col = 1 or col = .ncols then self else if row = 1 then object[.magsMat, 1, col] * cos(object[.phasesMat, 1, col]) else object[.magsMat, 1, col] * sin(object[.phasesMat, 1, col]) fi fi"
            removeObject: .magsMat, .phasesMat
            
            selectObject: .matComplex
            To Spectrum
            .spectrumMod = selected("Spectrum")
            To Sound
            .processed = selected("Sound")
            
            # Synthesis window. OLA normalization below divides by the sum
            # of these exact synthesis windows.
            selectObject: .processed
            Multiply by window: "Hanning"
            .procNs = Get number of samples
            
            # Centre alignment: the centre of input frame .tIn maps to the
            # centre at stretch*.tIn in output time.
            .tOut = .iframe * hopOut - window_size_s / 2
            
            selectObject: .outputID
            .s1 = Get sample number from time: .tOut
            .s2 = .s1 + .procNs - 1
            .outNs = Get number of samples
            if .s1 < 1
                .s1 = 1
            endif
            if .s2 > .outNs
                .s2 = .outNs
            endif
            .sOff = .s1 - 1
            .writeStart = max(outputBufferStart, .tOut)
            .writeEnd = min(outputBufferEnd, .tOut + window_size_s)
            
            if .writeEnd > .writeStart
                # Correct the processed-object index if the frame starts
                # before the buffer domain.
                .procSkip = max(0, round((outputBufferStart - .tOut) * workingSR))
                selectObject: .outputID
                Formula (part): .writeStart, .writeEnd, 1, 1,
                    ... "self + object[" + string$(.processed) + ", col - " + string$(.sOff) + " + " + string$(.procSkip) + "]"
                
                if .writeNorm
                    selectObject: olaNorm
                    Formula (part): .writeStart, .writeEnd, 1, 1,
                        ... "self + object[" + string$(synthWindow) + ", col - " + string$(.sOff) + " + " + string$(.procSkip) + "]"
                endif
            endif
            
            removeObject: .frame, .spectrum, .matComplex, .spectrumMod, .processed
        endif
    endfor
endproc

# Shared extended output timeline: the negative half-window lets the first
# frame be centred at output time 0. The final object is trimmed to [0,target].
outputBufferStart = -window_size_s / 2
outputBufferEnd = outputDuration + window_size_s / 2

# Exact synthesis Hann used both for audio and OLA normalization.
Create Sound from formula: "synth_window", 1, 0, window_size_s, workingSR, "1"
synthWindow = selected("Sound")
Multiply by window: "Hanning"

Create Sound from formula: "ola_norm", 1, outputBufferStart, outputBufferEnd, workingSR, "0"
olaNorm = selected("Sound")

# Process Left/Mono Channel
Create Sound from formula: "output_L", 1, outputBufferStart, outputBufferEnd, workingSR, "0"
outputL = selected("Sound")

if create_stereo
    @processChannel: outputL, 0.0, "LEFT", 1
else
    @processChannel: outputL, 0.0, "MONO", 1
endif

# Normalize the overlap-add envelope. Keep uncovered / vanishing-weight edge
# samples at zero rather than amplifying numerical residue.
selectObject: outputL
Formula: "if object[" + string$(olaNorm) + ", col] > 1e-6 then self / object[" + string$(olaNorm) + ", col] else 0 fi"

# Process Right Channel
if create_stereo
    appendInfoLine: ""
    Create Sound from formula: "output_R", 1, outputBufferStart, outputBufferEnd, workingSR, "0"
    outputR = selected("Sound")
    @processChannel: outputR, stereo_phase_offset, "RIGHT", 0
    selectObject: outputR
    Formula: "if object[" + string$(olaNorm) + ", col] > 1e-6 then self / object[" + string$(olaNorm) + ", col] else 0 fi"
    
    selectObject: outputL, outputR
    Combine to stereo
    result = selected("Sound")
    removeObject: outputL, outputR
else
    result = outputL
endif

removeObject: olaNorm, synthWindow
random_initializeSafelyAndUnpredictably ()

# Trim exactly to the requested stretched duration before optional upsampling.
selectObject: result
Extract part: 0, outputDuration, "rectangular", 1, "no"
trimmed = selected("Sound")
removeObject: result
result = trimmed

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
resultPeak = Get absolute extremum: 0, 0, "Sinc70"
if resultPeak > 0.95
    Formula: "self * 0.95 / resultPeak"
endif

if create_stereo
    Rename: original_name$ + "_PS_" + preset_name$ + "_stereo"
else
    Rename: original_name$ + "_PS_" + preset_name$
endif

removeObject: sourceSound

selectObject: result
finalDuration = Get total duration
processingTime = stopwatch - startTime
vizMaxHz = min(5000, sampleRate / 2)

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
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
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
    To Spectrogram: 0.03, vizMaxHz, 0.01, 20, "Gaussian"
    resSpec = selected("Spectrogram")
    Paint: 0, showDur, 0, vizMaxHz, 100, "yes", 50, 6, 0, "no"
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
