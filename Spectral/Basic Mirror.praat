# ============================================================
# Praat AudioTools - Basic Mirror.praat 
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral analysis or frequency-domain processing 
# ============================================================

# ============================================================
# Praat AudioTools - Basic Mirror.praat (WORKING VERSION)
# ============================================================

form Spectral Mirroring (Fast)
    optionmenu Preset: 1
        option Mild mirroring (cutoff = nyquist/4)
        option Moderate mirroring (cutoff = nyquist/2)
        option Strong mirroring (cutoff = nyquist/8)
        option Custom cutoff
    positive cutoff_divisor 2
    positive processing_sample_rate 32000
    comment === Stereo ===
    real stereo_spread 0.25
    real stereo_mirror_offset 0.15
    comment === Mix ===
    real dry_wet_mix 0.7
    comment (0 = dry only, 1 = wet only)
    positive scale_peak 0.9
    boolean play_after_processing 1
endform

if preset = 1
    cutoff_divisor = 4
elsif preset = 2
    cutoff_divisor = 2
elsif preset = 3
    cutoff_divisor = 8
endif

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object first."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
original_sr = Get sampling frequency
original_duration = Get total duration
num_channels = Get number of channels

writeInfoLine: "=== SPECTRAL MIRROR (STEREO) ==="
appendInfoLine: "Duration: ", fixed$(original_duration, 2), " s"

stopwatch

# Convert to mono
if num_channels > 1
    selectObject: originalID
    monoID = Convert to mono
else
    selectObject: originalID
    monoID = Copy: "mono"
endif

# Keep dry signal
selectObject: monoID
dryID = Copy: "dry_temp"

# Downsample
selectObject: monoID
current_sr = Get sampling frequency
did_downsample = 0
if processing_sample_rate < current_sr
    downsampledID = Resample: processing_sample_rate, 50
    removeObject: monoID
    monoID = downsampledID
    did_downsample = 1
else
    processing_sample_rate = current_sr
endif

selectObject: monoID
total_dur = Get total duration

nyquist = processing_sample_rate / 2
baseCutoff = round(nyquist / cutoff_divisor)
baseNyquist = round(nyquist)

# Stereo spread
cutoffL = round(baseCutoff * (1 - stereo_spread))
cutoffR = round(baseCutoff * (1 + stereo_spread))
nyquistL = round(baseNyquist * (1 - stereo_mirror_offset))
nyquistR = round(baseNyquist * (1 + stereo_mirror_offset * 0.5))

if nyquistR > baseNyquist
    nyquistR = baseNyquist
endif

time1 = stopwatch
appendInfoLine: "1. Prep: ", fixed$(time1, 3), " s"
appendInfoLine: "   L: cutoff=", cutoffL, " mirror=", nyquistL
appendInfoLine: "   R: cutoff=", cutoffR, " mirror=", nyquistR

# Chunk parameters
chunkSamples = 32768
chunkDur = chunkSamples / processing_sample_rate
overlapDur = 0.02
hopDur = chunkDur - overlapDur
numChunks = ceiling(total_dur / hopDur)

appendInfoLine: "   Chunks: ", numChunks

outputL = Create Sound from formula: "outputL", 1, 0, total_dur, processing_sample_rate, "0"
outputR = Create Sound from formula: "outputR", 1, 0, total_dur, processing_sample_rate, "0"

stopwatch

for chunk to numChunks
    chunkStart = (chunk - 1) * hopDur
    chunkEnd = chunkStart + chunkDur
    if chunkEnd > total_dur
        chunkEnd = total_dur
    endif
    actualDur = chunkEnd - chunkStart
    
    selectObject: monoID
    chunkID = Extract part: chunkStart, chunkEnd, "Hanning", 1, "no"
    
    selectObject: chunkID
    actualSamples = Get number of samples
    if actualSamples < chunkSamples
        padDur = (chunkSamples - actualSamples) / processing_sample_rate
        silenceID = Create Sound from formula: "sil", 1, 0, padDur, processing_sample_rate, "0"
        selectObject: chunkID, silenceID
        paddedID = Concatenate
        removeObject: chunkID, silenceID
        chunkID = paddedID
    endif
    
    # === LEFT CHANNEL - EXACT WORKING FORMULA ===
    selectObject: chunkID
    specL = To Spectrum: "no"
    
    selectObject: specL
    Formula: "if col < " + string$(cutoffL) + " then self[1,col] + self[1," + string$(nyquistL) + "-col] else self[1,col] fi"
    
    selectObject: specL
    procL = To Sound
    
    selectObject: procL
    if actualDur < chunkDur
        trimL = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procL
        procL = trimL
    endif
    Rename: "procL"
    
    chunkStartStr$ = fixed$(chunkStart, 8)
    selectObject: outputL
    Formula (part): chunkStart, chunkEnd, 1, 1, "self + Sound_procL(x - " + chunkStartStr$ + ")"
    
    removeObject: specL, procL
    
    # === RIGHT CHANNEL - EXACT WORKING FORMULA ===
    selectObject: chunkID
    specR = To Spectrum: "no"
    
    selectObject: specR
    Formula: "if col < " + string$(cutoffR) + " then self[1,col] + self[1," + string$(nyquistR) + "-col] else self[1,col] fi"
    
    selectObject: specR
    procR = To Sound
    
    selectObject: procR
    if actualDur < chunkDur
        trimR = Extract part: 0, actualDur, "rectangular", 1, "no"
        removeObject: procR
        procR = trimR
    endif
    Rename: "procR"
    
    selectObject: outputR
    Formula (part): chunkStart, chunkEnd, 1, 1, "self + Sound_procR(x - " + chunkStartStr$ + ")"
    
    removeObject: specR, procR, chunkID
endfor

selectObject: outputL
Formula: "self * 0.5"
selectObject: outputR
Formula: "self * 0.5"

time2 = stopwatch
appendInfoLine: "2. Process L+R: ", fixed$(time2, 3), " s"

# === MIX DRY/WET ===
stopwatch

if did_downsample and original_sr > processing_sample_rate
    selectObject: outputL
    resampledL = Resample: original_sr, 50
    removeObject: outputL
    outputL = resampledL
    
    selectObject: outputR
    resampledR = Resample: original_sr, 50
    removeObject: outputR
    outputR = resampledR
endif

selectObject: outputL
Scale peak: 0.95
selectObject: outputR
Scale peak: 0.95

wetMixStr$ = fixed$(dry_wet_mix, 4)
dryMixStr$ = fixed$(1 - dry_wet_mix, 4)

selectObject: outputL
Rename: "wetL"
selectObject: outputL
Formula: "Sound_dry_temp(x) * " + dryMixStr$ + " + self * " + wetMixStr$

selectObject: outputR
Rename: "wetR"
selectObject: outputR
Formula: "Sound_dry_temp(x) * " + dryMixStr$ + " + self * " + wetMixStr$

selectObject: outputL
plusObject: outputR
stereoID = Combine to stereo

selectObject: stereoID
Scale peak: scale_peak

time3 = stopwatch
appendInfoLine: "3. Mix + Finalize: ", fixed$(time3, 3), " s"

selectObject: stereoID
Rename: originalName$ + "_mirrored"

removeObject: monoID, dryID, outputL, outputR

totalTime = time1 + time2 + time3
appendInfoLine: "=== TOTAL: ", fixed$(totalTime, 3), " s ==="

selectObject: stereoID
if play_after_processing
    Play
endif
