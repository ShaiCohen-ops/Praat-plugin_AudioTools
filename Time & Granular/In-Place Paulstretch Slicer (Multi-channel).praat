# ============================================================
# Praat AudioTools - In-Place_Paulstretch_Slicer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   In-Place Paulstretch Slicer - extracts random segments,
#   applies Paulstretch (phase-randomized time stretching),
#   and places them back at original positions. Creates
#   ethereal, frozen texture effects. Slices alternate L-R.
#
# Changelog v0.2:
#   - Added fade in/out on slices
#   - Added dry/wet mix (default: mix with original)
#   - Stereo output: dry on both channels, slices alternate L-R
#   - Added visualization
#   - Added presets
# ============================================================

form In-Place Paulstretch Slicer
    comment Select a Sound object first
    
    comment === Preset ===
    optionmenu Preset 1
        option Custom
        option Subtle Shimmer
        option Frozen Texture
        option Extreme Stretch
        option Glitch Clouds
        option Ambient Wash
    
    comment === Slice Parameters ===
    positive Number_of_slices 4
    real Min_duration_s 0.1
    real Max_duration_s 0.5
    
    comment === Paulstretch ===
    positive Stretch_factor 4.0
    positive Window_size_s 0.25
    positive Overlap_percent 50
    
    comment === Slice Fades ===
    positive Fade_in_s 0.05
    positive Fade_out_s 0.1
    
    comment === Mix ===
    real Dry_wet_mix 0.5
    comment (0 = dry only, 1 = wet only, 0.5 = equal mix)
    
    comment === Output ===
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    # Subtle Shimmer
    number_of_slices = 3
    min_duration_s = 0.15
    max_duration_s = 0.4
    stretch_factor = 3.0
    window_size_s = 0.2
    overlap_percent = 60
    fade_in_s = 0.08
    fade_out_s = 0.15
    dry_wet_mix = 0.3
elsif preset = 3
    # Frozen Texture
    number_of_slices = 5
    min_duration_s = 0.2
    max_duration_s = 0.6
    stretch_factor = 6.0
    window_size_s = 0.3
    overlap_percent = 50
    fade_in_s = 0.1
    fade_out_s = 0.2
    dry_wet_mix = 0.5
elsif preset = 4
    # Extreme Stretch
    number_of_slices = 3
    min_duration_s = 0.3
    max_duration_s = 0.8
    stretch_factor = 10.0
    window_size_s = 0.4
    overlap_percent = 70
    fade_in_s = 0.15
    fade_out_s = 0.3
    dry_wet_mix = 0.6
elsif preset = 5
    # Glitch Clouds
    number_of_slices = 8
    min_duration_s = 0.05
    max_duration_s = 0.2
    stretch_factor = 4.0
    window_size_s = 0.15
    overlap_percent = 40
    fade_in_s = 0.02
    fade_out_s = 0.05
    dry_wet_mix = 0.7
elsif preset = 6
    # Ambient Wash
    number_of_slices = 4
    min_duration_s = 0.4
    max_duration_s = 1.0
    stretch_factor = 8.0
    window_size_s = 0.35
    overlap_percent = 65
    fade_in_s = 0.2
    fade_out_s = 0.4
    dry_wet_mix = 0.4
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object"
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
totalDuration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels

# === Validate ===
if min_duration_s <= 0 or max_duration_s <= 0
    exitScript: "Durations must be positive"
endif
if min_duration_s > max_duration_s
    exitScript: "Min duration cannot exceed max duration"
endif
if max_duration_s > totalDuration
    exitScript: "Max duration cannot exceed sound duration"
endif

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
elsif dry_wet_mix > 1
    dry_wet_mix = 1
endif

# === Info ===
writeInfoLine: "=== In-Place Paulstretch Slicer ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(totalDuration, 2), " s)"
appendInfoLine: ""
appendInfoLine: "Slices: ", number_of_slices
appendInfoLine: "Duration: ", fixed$(min_duration_s, 2), " - ", fixed$(max_duration_s, 2), " s"
appendInfoLine: "Stretch: ", stretch_factor, "x"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_mix * 100, 0), "% wet"
appendInfoLine: ""

# === Calculate Padding ===
maxStretchedDuration = max_duration_s * stretch_factor
paddingDuration = maxStretchedDuration
paddedDuration = totalDuration + paddingDuration

# === Convert to Mono for Processing ===
selectObject: original
if numChannels > 1
    Convert to mono
    sourceSound = selected("Sound")
else
    Copy: "source_mono"
    sourceSound = selected("Sound")
endif

# === Create Dry Channel (padded original) ===
Create Sound from formula: "pad", 1, 0, paddingDuration, sampleRate, "0"
padSound = selected("Sound")

selectObject: sourceSound, padSound
Concatenate
dryMono = selected("Sound")
Rename: "dry_mono"

removeObject: padSound

# === Create Wet Channels (L and R, empty) ===
Create Sound from formula: "wet_L", 1, 0, paddedDuration, sampleRate, "0"
wetL = selected("Sound")

Create Sound from formula: "wet_R", 1, 0, paddedDuration, sampleRate, "0"
wetR = selected("Sound")

# === Store slice info for visualization ===
for i to number_of_slices
    sliceStart[i] = 0
    sliceEnd[i] = 0
    sliceTargetStart[i] = 0
    sliceStretchedDur[i] = 0
    sliceChannel[i] = 0
endfor

# ===================================================================
# PROCEDURE: FAST PAULSTRETCH
# ===================================================================
procedure paulstretchFast: .inputID, .stretch, .winSize, .overlapPct
    selectObject: .inputID
    .dur = Get total duration
    .sr = Get sampling frequency
    
    .winSamples = round(.winSize * .sr)
    if .winSamples mod 2 = 1
        .winSamples += 1
    endif
    
    .overlapFrac = .overlapPct / 100
    .hopOut = .winSize * (1 - .overlapFrac)
    .hopIn = .hopOut / .stretch
    .outDur = .dur * .stretch
    .nFrames = ceiling(.outDur / .hopOut) + 1
    
    # Output buffer
    .outID = Create Sound from formula: "ps_out", 1, 0, .outDur + .winSize, .sr, "0"
    
    # Process frames
    for .i from 0 to .nFrames - 1
        .tIn = .i * .hopIn
        .tMidStart = .tIn - .winSize / 2
        .tMidEnd = .tIn + .winSize / 2
        
        selectObject: .inputID
        .exStart = max(0, .tMidStart)
        .exEnd = min(.dur, .tMidEnd)
        
        if .exEnd > .exStart
            .frame = Extract part: .exStart, .exEnd, "rectangular", 1, "no"
            
            # Pad frame if needed
            .durFrame = Get total duration
            if abs(.durFrame - .winSize) > 0.00001
                .padded = Create Sound from formula: "pad", 1, 0, .winSize, .sr, "0"
                .offset = 0
                if .tMidStart < 0
                    .offset = abs(.tMidStart)
                endif
                .sOff$ = fixed$(.offset, 6)
                .sEnd$ = fixed$(.offset + .durFrame, 6)
                .fid = .frame
                Formula: "if x >= " + .sOff$ + " and x <= " + .sEnd$ + " then self + object(" + string$(.fid) + ", x - " + .sOff$ + ") else self fi"
                removeObject: .frame
                .frame = .padded
            endif
            
            # Window
            selectObject: .frame
            Multiply by window: "Hanning"
            
            # Phase Randomization
            .spec = To Spectrum: "yes"
            selectObject: .spec
            .matC = To Matrix
            selectObject: .matC
            .matP = Copy: "phases"
            Formula: "randomUniform(-pi, pi)"
            
            selectObject: .matC
            .pid = .matP
            Formula: "if (col=1 or col=ncol) then self else (if row=1 then sqrt(self[1,col]^2 + self[2,col]^2) * cos(object[" + string$(.pid) + ",1,col]) else sqrt(self[1,col]^2 + self[2,col]^2) * sin(object[" + string$(.pid) + ",1,col]) fi) fi"
            
            .specMod = To Spectrum
            selectObject: .specMod
            .proc = To Sound
            
            # Window again
            selectObject: .proc
            Multiply by window: "Hanning"
            
            # Overlap Add
            .tOut = .i * .hopOut
            Shift times to: "start time", .tOut
            
            selectObject: .outID
            .procID = .proc
            .sT1$ = fixed$(.tOut, 6)
            .sT2$ = fixed$(.tOut + .winSize, 6)
            
            Formula: "if x >= " + .sT1$ + " and x <= " + .sT2$ + " then self + object(" + string$(.procID) + ", x) else self fi"
            
            removeObject: .frame, .spec, .matC, .matP, .specMod, .proc
        endif
    endfor
    
    selectObject: .outID
endproc

# ===================================================================
# MAIN PROCESSING LOOP
# ===================================================================

appendInfoLine: "Processing slices..."

for i to number_of_slices
    selectObject: sourceSound
    srcDur = Get total duration
    
    # Random slice position
    segLen = randomUniform(min_duration_s, max_duration_s)
    maxStart = srcDur - segLen
    winStart = randomUniform(0, maxStart)
    winEnd = winStart + segLen
    
    # Store for visualization
    sliceStart[i] = winStart
    sliceEnd[i] = winEnd
    
    # Determine channel (alternate L-R)
    if i mod 2 = 1
        sliceChannel[i] = 1
        chanLabel$ = "L"
    else
        sliceChannel[i] = 2
        chanLabel$ = "R"
    endif
    
    appendInfoLine: "  Slice ", i, " [", chanLabel$, "]: ", fixed$(winStart, 2), "s - ", fixed$(winEnd, 2), "s (", fixed$(segLen, 2), "s)"
    
    # Extract segment
    selectObject: sourceSound
    segID = Extract part: winStart, winEnd, "Hanning", 1, "no"
    
    # Paulstretch
    @paulstretchFast: segID, stretch_factor, window_size_s, overlap_percent
    psID = selected("Sound")
    
    # Get stretched duration
    selectObject: psID
    stretchedDur = Get total duration
    sliceStretchedDur[i] = stretchedDur
    
    # Apply fade in/out to slice
    if fade_in_s > 0 and fade_in_s < stretchedDur / 2
        Formula (part): 0, fade_in_s, 1, 1, "self * (0.5 - 0.5 * cos(pi * x / fade_in_s))"
    endif
    if fade_out_s > 0 and fade_out_s < stretchedDur / 2
        fadeOutStart = stretchedDur - fade_out_s
        Formula (part): fadeOutStart, stretchedDur, 1, 1, "self * (0.5 + 0.5 * cos(pi * (x - fadeOutStart) / fade_out_s))"
    endif
    
    # Normalize slice
    Scale peak: 0.95
    
    # Calculate placement (centered on original position)
    originalCenter = winStart + (segLen / 2)
    targetStart = originalCenter - (stretchedDur / 2)
    if targetStart < 0
        targetStart = 0
    endif
    sliceTargetStart[i] = targetStart
    
    # Place into appropriate wet channel (L or R)
    selectObject: psID
    Shift times to: "start time", targetStart
    
    psStr$ = string$(psID)
    tStart$ = fixed$(targetStart, 6)
    tEnd$ = fixed$(targetStart + stretchedDur, 6)
    
    if sliceChannel[i] = 1
        selectObject: wetL
    else
        selectObject: wetR
    endif
    Formula: "if x >= " + tStart$ + " and x <= " + tEnd$ + " then self + object(" + psStr$ + ", x) else self fi"
    
    # Cleanup
    removeObject: segID, psID
endfor

# === Normalize Wet Channels ===
selectObject: wetL
Scale peak: 0.95

selectObject: wetR
Scale peak: 0.95

# ===================================================================
# MIX OUTPUT (Stereo: dry on both + wet L-R)
# ===================================================================

appendInfoLine: ""
appendInfoLine: "Mixing stereo output..."

dryAmp = 1 - dry_wet_mix
wetAmp = dry_wet_mix

# Create Left channel: dry + wetL
Create Sound from formula: "outL", 1, 0, paddedDuration, sampleRate, "0"
outL = selected("Sound")

dryStr$ = string$(dryMono)
wetLStr$ = string$(wetL)
Formula: "object(" + dryStr$ + ", x) * dryAmp + object(" + wetLStr$ + ", x) * wetAmp"

# Create Right channel: dry + wetR
Create Sound from formula: "outR", 1, 0, paddedDuration, sampleRate, "0"
outR = selected("Sound")

wetRStr$ = string$(wetR)
Formula: "object(" + dryStr$ + ", x) * dryAmp + object(" + wetRStr$ + ", x) * wetAmp"

# Combine to stereo
selectObject: outL, outR
Combine to stereo
result = selected("Sound")
Scale peak: 0.95
Rename: original_name$ + "_PSslice"

# Cleanup mono channels
removeObject: outL, outR

# === Trim to reasonable length ===
selectObject: result
resultDur = Get total duration
if resultDur > totalDuration + 2
    Extract part: 0, totalDuration + 2, "rectangular", 1, "no"
    trimmed = selected("Sound")
    removeObject: result
    result = trimmed
    selectObject: result
    Rename: original_name$ + "_PSslice"
endif

# === Cleanup ===
removeObject: sourceSound, dryMono, wetL, wetR

# ===================================================================
# VISUALIZATION
# ===================================================================

if draw_visualization
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0.1, 0.5
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "In-Place Paulstretch Slicer: " + original_name$
    
    # Original waveform with slice markers
    Select outer viewport: 0, 8, 0.6, 2.0
    Select inner viewport: 0.6, 7.6, 0.7, 1.9
    selectObject: original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark original slice positions (color by channel)
    for i to number_of_slices
        if sliceChannel[i] = 1
            Colour: "{0.9, 0.3, 0.3}"
        else
            Colour: "{0.3, 0.3, 0.9}"
        endif
        Line width: 2
        Draw line: sliceStart[i], -0.8, sliceStart[i], 0.8
        Draw line: sliceEnd[i], -0.8, sliceEnd[i], 0.8
        
        if sliceChannel[i] = 1
            Colour: "{0.9, 0.5, 0.5}"
        else
            Colour: "{0.5, 0.5, 0.9}"
        endif
        Line width: 1
        Draw line: sliceStart[i], 0.8, sliceEnd[i], 0.8
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text left: "yes", "Original"
    
    # Result waveform (stereo - show both channels)
    Select outer viewport: 0, 8, 2.1, 3.5
    Select inner viewport: 0.6, 7.6, 2.2, 3.4
    selectObject: result
    Colour: "{0.2, 0.5, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    
    # Mark stretched slice positions
    for i to number_of_slices
        targetEnd = sliceTargetStart[i] + sliceStretchedDur[i]
        
        if sliceChannel[i] = 1
            Colour: "{0.9, 0.4, 0.4}"
        else
            Colour: "{0.4, 0.4, 0.9}"
        endif
        Line width: 2
        Draw line: sliceTargetStart[i], -0.8, sliceTargetStart[i], 0.8
        Draw line: targetEnd, -0.8, targetEnd, 0.8
        
        Line width: 1
        Draw line: sliceTargetStart[i], 0.8, targetEnd, 0.8
    endfor
    
    Line width: 1
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Result"
    Text bottom: "yes", "Time (s)"
    
    # Slice info diagram
    Select outer viewport: 0, 8, 3.7, 5.0
    Select inner viewport: 0.6, 7.6, 3.9, 4.9
    
    Axes: 0, totalDuration * 1.2, 0, number_of_slices + 1
    
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, totalDuration * 1.2, 0, number_of_slices + 1
    
    for i to number_of_slices
        y = number_of_slices - i + 1
        
        # Original slice (red=L, blue=R)
        if sliceChannel[i] = 1
            Paint rectangle: "{0.9, 0.6, 0.6}", sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35
            Paint rectangle: "{0.8, 0.5, 0.5}", sliceTargetStart[i], sliceTargetStart[i] + sliceStretchedDur[i], y - 0.25, y + 0.25
        else
            Paint rectangle: "{0.6, 0.6, 0.9}", sliceStart[i], sliceEnd[i], y - 0.35, y + 0.35
            Paint rectangle: "{0.5, 0.5, 0.8}", sliceTargetStart[i], sliceTargetStart[i] + sliceStretchedDur[i], y - 0.25, y + 0.25
        endif
        
        # Center marker
        originalCenter = (sliceStart[i] + sliceEnd[i]) / 2
        Colour: "{0.3, 0.3, 0.3}"
        Draw line: originalCenter, y - 0.4, originalCenter, y + 0.4
    endfor
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Slice"
    Text bottom: "yes", "Time (s)"
    
    # Legend
    Select outer viewport: 0, 8, 5.1, 5.4
    Font size: 7
    Colour: "{0.9, 0.5, 0.5}"
    Text: 0.15, "centre", 0.5, "half", "## Left"
    Colour: "{0.5, 0.5, 0.9}"
    Text: 0.30, "centre", 0.5, "half", "## Right"
    Colour: "{0.4, 0.4, 0.4}"
    Text: 0.65, "centre", 0.5, "half", "Stretch: " + string$(stretch_factor) + "x | Mix: " + fixed$(dry_wet_mix * 100, 0) + "% wet"
    
    Font size: 10
    Colour: "Black"
endif

# === Final Info ===
selectObject: result
finalDuration = Get total duration

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Duration: ", fixed$(finalDuration, 2), " s"
appendInfoLine: "Dry/Wet: ", fixed$((1 - dry_wet_mix) * 100, 0), "% / ", fixed$(dry_wet_mix * 100, 0), "%"

# === Play ===
if play_result
    selectObject: result
    Play
endif

selectObject: result
