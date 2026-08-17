# ============================================================
# Praat AudioTools - Extract_Segment.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Unified, sample-aligned segment extraction tool combining Manual,
#   Percentage, Random Single, and Random Multiple extraction methods.
#   Segments preserve channel count, sampling rate, and source level by
#   default. Optional attenuation, sample-domain fades, and explicit peak
#   normalization can be applied after extraction.
#
# v1.1:
#   - FIX: attenuation is no longer cancelled by unconditional peak scaling.
#   - CHANGE: Peak_ceiling is a safety ceiling by default; normalization is
#     explicit via Normalize_to_peak.
#   - FIX: manual/percentage times are relative to the Sound start and work
#     correctly for Sounds whose time domain does not begin at 0.
#   - FIX: extraction windows are snapped to actual source samples and all
#     reported boundaries describe the samples that were really extracted.
#   - FIX: fades are sample-domain ramps that reach digital zero at the first
#     and last faded samples.
#   - VIZ: AudioTools 2x2 mechanism-first layout with actual windows, dry vs
#     processed comparison, applied gain envelope, and segment durations.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
soundName$ = selected$("Sound")

form Extract Segment v1.1
    optionmenu Preset: 1
        option Manual
        option Middle 50%
        option First Quarter
        option Last Quarter
        option Random Slice
        option Multiple Random
    comment === Extraction Method ===
    optionmenu Method: 1
        option Manual (relative start/end seconds)
        option Percentage (start/end %)
        option Random Single (fixed duration)
        option Random Multiple (variable durations)
    comment === Manual / Percentage Parameters ===
    real Start_time_or_percent 0.0
    real End_time_or_percent 1.0
    comment === Random Single Parameters ===
    real Extraction_duration 2.0
    comment === Random Multiple Parameters ===
    natural Number_of_segments 4
    real Min_duration 0.25
    real Max_duration 2.0
    comment (random windows are independent and may overlap)
    comment === Processing ===
    real Fade_time 0.05
    positive Attenuation_divisor 1.0
    positive Peak_ceiling 0.99
    boolean Normalize_to_peak 0
    comment (Normalize off = preserve level; ceiling only reduces excessive peaks)
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 2
    method = 2
    start_time_or_percent = 25
    end_time_or_percent = 75
    presetName$ = "Middle50"
elsif preset = 3
    method = 2
    start_time_or_percent = 0
    end_time_or_percent = 25
    presetName$ = "FirstQuarter"
elsif preset = 4
    method = 2
    start_time_or_percent = 75
    end_time_or_percent = 100
    presetName$ = "LastQuarter"
elsif preset = 5
    method = 3
    extraction_duration = 2.0
    presetName$ = "RandomSlice"
elsif preset = 6
    method = 4
    number_of_segments = 4
    min_duration = 0.25
    max_duration = 2.0
    presetName$ = "MultiRandom"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup / validation
# ============================================================
selectObject: sound
sourceStart = Get start time
sourceEnd = Get end time
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
numSamples = Get number of samples
samplePeriod = 1 / sampleRate

if totalDuration <= 0 or numSamples < 1
    exitScript: "The selected Sound contains no samples."
endif

if fade_time < 0
    fade_time = 0
endif
if attenuation_divisor < 1
    attenuation_divisor = 1
endif
if peak_ceiling > 1
    peak_ceiling = 1
endif
if peak_ceiling <= 0
    exitScript: "Peak ceiling must be greater than zero."
endif

clearinfo
writeInfoLine: "=== Extract Segment v1.1 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", soundName$, " | ", fixed$(totalDuration, 3), " s | ", sampleRate, " Hz | ", numChannels, " ch"
if sourceStart <> 0
    appendInfoLine: "Sound time domain: ", fixed$(sourceStart, 6), " - ", fixed$(sourceEnd, 6), " s"
    appendInfoLine: "Manual times are interpreted relative to the Sound start."
endif
appendInfoLine: ""

# ============================================================
# Resolve requested window(s) in relative time
# ============================================================
if method = 1
    requestedStart = start_time_or_percent
    requestedEnd = end_time_or_percent
    requestedStart = max(0, requestedStart)
    requestedEnd = min(totalDuration, requestedEnd)
    if requestedStart >= requestedEnd
        exitScript: "Start time must be less than end time after clamping to the Sound duration."
    endif
    methodName$ = "Manual"
    appendInfoLine: "Method: Manual | requested ", fixed$(requestedStart, 6), " - ", fixed$(requestedEnd, 6), " s relative"

elsif method = 2
    startPercent = max(0, start_time_or_percent)
    endPercent = min(100, end_time_or_percent)
    if startPercent >= endPercent
        exitScript: "Start percentage must be less than end percentage."
    endif
    requestedStart = totalDuration * startPercent / 100
    requestedEnd = totalDuration * endPercent / 100
    methodName$ = "Percentage"
    appendInfoLine: "Method: Percentage | ", fixed$(startPercent, 2), "% - ", fixed$(endPercent, 2), "%"

elsif method = 3
    if extraction_duration <= 0
        exitScript: "Extraction duration must be positive."
    endif
    desiredSamples = round(extraction_duration * sampleRate)
    desiredSamples = max(1, desiredSamples)
    if desiredSamples > numSamples
        exitScript: "Extraction duration exceeds the available number of samples."
    endif
    startSample = randomInteger(1, numSamples - desiredSamples + 1)
    endSample = startSample + desiredSamples - 1
    requestedStart = (startSample - 1) / sampleRate
    requestedEnd = endSample / sampleRate
    methodName$ = "RandomSingle"
    appendInfoLine: "Method: Random Single | requested duration ", fixed$(extraction_duration, 6), " s"

elsif method = 4
    if min_duration <= 0 or max_duration <= 0
        exitScript: "Random segment durations must be positive."
    endif
    if min_duration > max_duration
        exitScript: "Minimum duration cannot exceed maximum duration."
    endif
    minSamples = max(1, round(min_duration * sampleRate))
    maxSamples = max(minSamples, round(max_duration * sampleRate))
    if maxSamples > numSamples
        exitScript: "Maximum random duration exceeds the available number of samples."
    endif
    methodName$ = "RandomMultiple"
    appendInfoLine: "Method: Random Multiple | ", number_of_segments, " independent windows (overlap allowed)"
    appendInfoLine: "Sample-aligned duration range: ", minSamples, " - ", maxSamples, " samples"
else
    exitScript: "Invalid extraction method."
endif

# ============================================================
# Extraction
# ============================================================
if method <= 3
    if method <= 2
        # Select samples whose centres lie inside the requested interval.
        startSample = ceiling(requestedStart * sampleRate + 0.5)
        endSample = floor(requestedEnd * sampleRate + 0.5)
        startSample = max(1, min(numSamples, startSample))
        endSample = max(1, min(numSamples, endSample))
        if endSample < startSample
            exitScript: "The requested interval contains no source samples. Increase its duration."
        endif
    endif

    # Exact sample-edge boundaries used by Extract part.
    actualStartRel = (startSample - 1) / sampleRate
    actualEndRel = endSample / sampleRate
    actualStartAbs = sourceStart + actualStartRel
    actualEndAbs = sourceStart + actualEndRel
    segmentSamples = endSample - startSample + 1
    segmentDuration = segmentSamples / sampleRate

    selectObject: sound
    extracted = Extract part: actualStartAbs, actualEndAbs, "rectangular", 1, "no"

    if draw_visualization
        dryFirst = Copy: "dry_reference"
        selectObject: extracted
    endif

    @processSegment: extracted, fade_time, attenuation_divisor, peak_ceiling, normalize_to_peak
    firstFadeSamples = processSegment.fadeSamples
    firstPostScale = processSegment.postScale
    firstPeak = processSegment.finalPeak
    firstNSamples = processSegment.nSamples

    selectObject: extracted
    Rename: soundName$ + "_" + methodName$ + "_" + presetName$
    outputSound = selected("Sound")

    segStart_1 = actualStartRel
    segEnd_1 = actualEndRel
    segDur_1 = segmentDuration
    segSamples_1 = segmentSamples
    numExtracted = 1

    appendInfoLine: "Actual: ", fixed$(actualStartRel, 6), " - ", fixed$(actualEndRel, 6), " s relative"
    appendInfoLine: "Samples: ", startSample, " - ", endSample, " (", segmentSamples, " samples)"
    if method <= 2
        startErrSamples = (actualStartRel - requestedStart) * sampleRate
        endErrSamples = (actualEndRel - requestedEnd) * sampleRate
        appendInfoLine: "Boundary snap: start ", fixed$(startErrSamples, 2), " samples | end ", fixed$(endErrSamples, 2), " samples"
    endif

else
    appendInfoLine: "Extracting segments:"
    for i from 1 to number_of_segments
        segSamples = randomInteger(minSamples, maxSamples)
        segStartSample = randomInteger(1, numSamples - segSamples + 1)
        segEndSample = segStartSample + segSamples - 1
        segStartRel = (segStartSample - 1) / sampleRate
        segEndRel = segEndSample / sampleRate
        segStartAbs = sourceStart + segStartRel
        segEndAbs = sourceStart + segEndRel
        segDur = segSamples / sampleRate

        segStart_'i' = segStartRel
        segEnd_'i' = segEndRel
        segDur_'i' = segDur
        segSamples_'i' = segSamples

        selectObject: sound
        seg = Extract part: segStartAbs, segEndAbs, "rectangular", 1, "no"

        if draw_visualization and i = 1
            dryFirst = Copy: "dry_reference"
            selectObject: seg
        endif

        @processSegment: seg, fade_time, attenuation_divisor, peak_ceiling, normalize_to_peak

        if i = 1
            firstFadeSamples = processSegment.fadeSamples
            firstPostScale = processSegment.postScale
            firstPeak = processSegment.finalPeak
            firstNSamples = processSegment.nSamples
        endif

        selectObject: seg
        Rename: soundName$ + "_seg" + string$(i)
        segment_'i' = selected("Sound")

        appendInfoLine: "  Seg ", i, ": ", fixed$(segStartRel, 6), " - ", fixed$(segEndRel, 6), " s | ", segSamples, " samples"
    endfor

    numExtracted = number_of_segments
    outputSound = segment_1
endif

if normalize_to_peak and attenuation_divisor > 1
    appendInfoLine: "Note: peak normalization is enabled, so it can compensate the absolute attenuation."
endif

# ============================================================
# Visualization
# ============================================================
if draw_visualization
    # Choose a representative source channel without mono fold-down.
    if numChannels = 1
        selectObject: sound
        vizSource = Copy: "viz_source"
        vizChannel = 1
    else
        bestRms = -1
        bestViz = 0
        vizChannel = 1
        for ch from 1 to numChannels
            selectObject: sound
            tmpCh = Extract one channel: ch
            tmpRms = Get root-mean-square: 0, 0
            if tmpRms > bestRms
                if bestViz <> 0
                    removeObject: bestViz
                endif
                bestRms = tmpRms
                bestViz = tmpCh
                vizChannel = ch
            else
                removeObject: tmpCh
            endif
        endfor
        vizSource = bestViz
    endif
    selectObject: vizSource
    Shift times to: "start time", 0

    # First dry and processed segment, same representative channel.
    selectObject: dryFirst
    dryChannels = Get number of channels
    if dryChannels > 1
        dryViz = Extract one channel: vizChannel
    else
        dryViz = Copy: "dry_viz"
    endif

    selectObject: outputSound
    outChannels = Get number of channels
    if outChannels > 1
        outViz = Extract one channel: vizChannel
    else
        outViz = Copy: "out_viz"
    endif

    # Exact gain envelope that transformed dryFirst -> outputSound.
    gainDur = firstNSamples / sampleRate
    attenBase = 1 / attenuation_divisor
    totalFlatGain = attenBase * firstPostScale
    fadeN$ = string$(firstFadeSamples)
    flatGain$ = string$(totalFlatGain)
    Create Sound from formula: "applied_gain_envelope", 1, 0, gainDur, sampleRate, "1"
    gainViz = selected("Sound")
    if firstFadeSamples <= 0
        Formula: flatGain$
    elsif firstFadeSamples = 1
        Formula: "if col = 1 or col = ncol then 0 else " + flatGain$ + " fi"
    else
        denom$ = string$(firstFadeSamples - 1)
        Formula: flatGain$ + " * min(1, min((col - 1) / " + denom$ + ", (ncol - col) / " + denom$ + "))"
    endif

    Erase all

    # Title strip
    Select outer viewport: 0.4, 7.8, 0.04, 0.25
    Select inner viewport: 0.4, 7.8, 0.04, 0.25
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Extract Segment v1.1 - " + presetName$

    # Process strip
    Select outer viewport: 0.4, 7.8, 0.28, 0.46
    Select inner viewport: 0.4, 7.8, 0.28, 0.46
    Axes: 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.35, 0.35, 0.35}"
    Text: 0.5, "centre", 0.5, "half", "requested window -> sample-aligned extraction -> attenuation -> zero-ended fades -> optional normalize / safety ceiling"

    # A title
    Select outer viewport: 0.3, 3.95, 0.52, 0.68
    Select inner viewport: 0.3, 3.95, 0.52, 0.68
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "A  SOURCE / ACTUAL WINDOWS"

    # A data
    selectObject: vizSource
    srcAmp = Get absolute extremum: 0, 0, "None"
    if srcAmp <= 0
        srcAmp = 1
    endif
    srcAmp = srcAmp * 1.08
    Select outer viewport: 0.3, 3.95, 0.70, 2.58
    Select inner viewport: 0.58, 3.84, 0.78, 2.47
    Axes: 0, totalDuration, -srcAmp, srcAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration, -srcAmp, srcAmp
    for i from 1 to numExtracted
        Paint rectangle: "{0.88, 0.93, 0.98}", segStart_'i', segEnd_'i', -srcAmp, srcAmp
    endfor
    selectObject: vizSource
    Colour: "{0.35, 0.35, 0.35}"
    Line width: 1
    Draw: 0, totalDuration, -srcAmp, srcAmp, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"
    if numChannels > 1
        Text: totalDuration * 0.98, "right", srcAmp * 0.88, "half", "display ch " + string$(vizChannel)
    endif

    # B title
    Select outer viewport: 4.05, 7.75, 0.52, 0.68
    Select inner viewport: 4.05, 7.75, 0.52, 0.68
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "B  DRY EXTRACT / PROCESSED OUTPUT (segment time)"

    # B data
    selectObject: dryViz
    dryAmp = Get absolute extremum: 0, 0, "None"
    selectObject: outViz
    outAmp = Get absolute extremum: 0, 0, "None"
    cmpAmp = max(dryAmp, outAmp)
    if cmpAmp <= 0
        cmpAmp = 1
    endif
    cmpAmp = cmpAmp * 1.08
    firstDur = firstNSamples / sampleRate
    Select outer viewport: 4.05, 7.75, 0.70, 2.58
    Select inner viewport: 4.33, 7.64, 0.78, 2.47
    Axes: 0, firstDur, -cmpAmp, cmpAmp
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, firstDur, -cmpAmp, cmpAmp
    selectObject: dryViz
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 1
    Draw: 0, firstDur, -cmpAmp, cmpAmp, "no", "Curve"
    selectObject: outViz
    Colour: "{0.15, 0.45, 0.75}"
    Line width: 1.5
    Draw: 0, firstDur, -cmpAmp, cmpAmp, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Font size: 6
    Colour: "{0.55, 0.55, 0.55}"
    Text: firstDur * 0.04, "left", cmpAmp * 0.88, "half", "dry"
    Colour: "{0.15, 0.45, 0.75}"
    Text: firstDur * 0.18, "left", cmpAmp * 0.88, "half", "processed"

    # C title
    Select outer viewport: 0.3, 3.95, 2.68, 2.84
    Select inner viewport: 0.3, 3.95, 2.68, 2.84
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.02, "left", 0.5, "half", "C  APPLIED GAIN ENVELOPE"

    selectObject: gainViz
    gainMax = Get maximum: 0, 0, "None"
    gainY = max(1.05, gainMax * 1.08)
    Select outer viewport: 0.3, 3.95, 2.86, 4.78
    Select inner viewport: 0.58, 3.84, 2.94, 4.66
    Axes: 0, firstDur, 0, gainY
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, firstDur, 0, gainY
    Colour: "{0.75, 0.75, 0.75}"
    Draw line: 0, 1, firstDur, 1
    selectObject: gainViz
    Colour: "{0.55, 0.25, 0.65}"
    Line width: 1.5
    Draw: 0, firstDur, 0, gainY, "no", "Curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Marks bottom: 3, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 6
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Gain"

    # D title
    Select outer viewport: 4.05, 7.75, 2.68, 2.84
    Select inner viewport: 4.05, 7.75, 2.68, 2.84
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    if method <= 3
        Text: 0.02, "left", 0.5, "half", "D  SAMPLE / BOUNDARY METRICS"
    else
        Text: 0.02, "left", 0.5, "half", "D  SEGMENT DURATIONS"
    endif

    Select outer viewport: 4.05, 7.75, 2.86, 4.78
    Select inner viewport: 4.33, 7.64, 2.94, 4.66
    if method <= 3
        # For a single extraction, boundary/sample metrics are more useful
        # than a one-bar duration chart.
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        Colour: "{0.25, 0.25, 0.25}"
        Font size: 6.5
        Text: 0.04, "left", 0.83, "half", "Requested: " + fixed$(requestedStart, 6) + " -> " + fixed$(requestedEnd, 6) + " s"
        Text: 0.04, "left", 0.64, "half", "Actual:    " + fixed$(actualStartRel, 6) + " -> " + fixed$(actualEndRel, 6) + " s"
        if method <= 2
            Text: 0.04, "left", 0.45, "half", "Boundary snap: start " + fixed$(startErrSamples, 2) + " smp | end " + fixed$(endErrSamples, 2) + " smp"
        else
            Text: 0.04, "left", 0.45, "half", "Random start is generated directly on the source sample grid"
        endif
        Text: 0.04, "left", 0.26, "half", string$(segmentSamples) + " samples | " + fixed$(segmentDuration, 6) + " s | peak " + fixed$(firstPeak, 4)
        Colour: "Black"
        Draw inner box
    else
        maxSegDur = 0
        for i from 1 to numExtracted
            if segDur_'i' > maxSegDur
                maxSegDur = segDur_'i'
            endif
        endfor
        if maxSegDur <= 0
            maxSegDur = samplePeriod
        endif
        showDurCount = min(numExtracted, 12)
        Axes: 0, maxSegDur * 1.08, 0.5, showDurCount + 0.5
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxSegDur * 1.08, 0.5, showDurCount + 0.5
        for i from 1 to showDurCount
            Colour: "{0.15, 0.45, 0.75}"
            Line width: 2
            Draw line: 0, i, segDur_'i', i
            Colour: "Black"
            Font size: 5.5
            Text: maxSegDur * 0.02, "left", i + 0.18, "half", "#" + string$(i) + "  " + string$(segSamples_'i') + " smp"
        endfor
        Line width: 1
        Colour: "Black"
        Draw inner box
        Marks bottom: 3, "yes", "yes", "no"
        Font size: 6
        Text bottom: "yes", "Duration (s)"
        if numExtracted > showDurCount
            Text: maxSegDur * 1.03, "right", showDurCount, "half", "+" + string$(numExtracted - showDurCount) + " more"
        endif
    endif

    # Summary strip
    Select outer viewport: 0.4, 7.7, 4.96, 5.22
    Select inner viewport: 0.4, 7.7, 4.96, 5.22
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 6.5
    Colour: "{0.25, 0.25, 0.25}"
    normWord$ = if normalize_to_peak then "normalize" else "ceiling-only" fi
    Text: 0.02, "left", 0.5, "half", methodName$ + " | n=" + string$(numExtracted) + " | fade=" + fixed$(firstFadeSamples / sampleRate * 1000, 1) + " ms | atten=/" + fixed$(attenuation_divisor, 2) + " | " + normWord$ + " " + fixed$(peak_ceiling, 2) + " | first=" + string$(firstNSamples) + " samples"

    # Cleanup visualization-only objects.
    removeObject: vizSource, dryViz, outViz, gainViz, dryFirst
endif

# ============================================================
# Output
# ============================================================
appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
if method <= 3
    appendInfoLine: "Created 1 segment: ", soundName$, "_", methodName$, "_", presetName$
else
    appendInfoLine: "Created ", numExtracted, " segments"
endif

if play_result
    selectObject: outputSound
    Play
endif

if method <= 3
    selectObject: sound
    plusObject: outputSound
else
    selectObject: sound
    for i from 1 to numExtracted
        plusObject: segment_'i'
    endfor
endif

# ============================================================
# Procedure: processSegment
# Applies attenuation, exact sample-domain fade, then either explicit
# normalization or a safety ceiling. The same scalar is applied to all
# channels, preserving inter-channel balance.
# ============================================================
procedure processSegment: .id, .fadeSec, .attenDiv, .ceiling, .normalize
    selectObject: .id
    .nSamples = Get number of samples
    .sr = Get sampling frequency

    # Attenuation first.
    if .attenDiv > 1
        .att$ = string$(.attenDiv)
        Formula: "self / " + .att$
    endif

    # Fade length in whole samples, never exceeding half the segment.
    .fadeSamples = round(.fadeSec * .sr)
    .fadeSamples = max(0, min(.fadeSamples, floor(.nSamples / 2)))
    if .fadeSamples = 1
        Formula: "if col = 1 or col = ncol then 0 else self fi"
    elsif .fadeSamples > 1
        .denom$ = string$(.fadeSamples - 1)
        Formula: "self * min(1, min((col - 1) / " + .denom$ + ", (ncol - col) / " + .denom$ + "))"
    endif

    .peakBefore = Get absolute extremum: 0, 0, "None"
    .postScale = 1
    if .normalize
        if .peakBefore > 0
            .postScale = .ceiling / .peakBefore
            .scale$ = string$(.postScale)
            Formula: "self * " + .scale$
        endif
    elsif .peakBefore > .ceiling
        .postScale = .ceiling / .peakBefore
        .scale$ = string$(.postScale)
        Formula: "self * " + .scale$
    endif

    .finalPeak = Get absolute extremum: 0, 0, "None"
endproc
