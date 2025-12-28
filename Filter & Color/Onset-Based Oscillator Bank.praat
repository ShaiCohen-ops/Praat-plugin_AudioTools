# ============================================================
# Praat AudioTools - Onset-Based Oscillator Bank
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.3 (2025)
# License: MIT License
# ============================================================

form Onset-Based Oscillator Bank
    optionmenu Preset: 1
        option Custom
        option Gentle Resonance
        option Percussive Bells
        option Ethereal Pad
        option Metallic Shimmer
        option Natural Pluck
        option Dense Cluster
    comment === Onset Detection ===
    positive Onset_threshold_(dB) 1.5
    positive Min_intensity_(dB) 35.0
    positive Min_interval_(s) 0.1
    comment === Oscillators (Custom only) ===
    integer Num_partials 12
    positive Partial_spread 0.5
    positive Decay_(s) 1.5
    real Brightness 0.7
    comment === Output ===
    real Dry_wet_mix 1.0
    boolean Play_result 1
endform

# ============================================================
# PRESET DEFINITIONS
# ============================================================
attackBase = 0.005
attackRandom = 0.01
decayRandom = 0.5
ampRandom = 0.3
waveshapeAmt = 0.2
decayTime = decay

if preset = 2
    onset_threshold = 2.0
    min_intensity = 35.0
    min_interval = 0.15
    num_partials = 8
    partial_spread = 0.3
    decayTime = 2.0
    brightness = 0.5
    dry_wet_mix = 0.7
    attackBase = 0.01
    waveshapeAmt = 0.1
elsif preset = 3
    onset_threshold = 1.5
    min_intensity = 40.0
    min_interval = 0.08
    num_partials = 15
    partial_spread = 0.8
    decayTime = 1.0
    brightness = 0.9
    dry_wet_mix = 1.0
    attackBase = 0.002
    waveshapeAmt = 0.3
elsif preset = 4
    onset_threshold = 2.5
    min_intensity = 30.0
    min_interval = 0.2
    num_partials = 20
    partial_spread = 0.2
    decayTime = 3.5
    brightness = 0.6
    dry_wet_mix = 0.8
    attackBase = 0.05
    waveshapeAmt = 0.15
elsif preset = 5
    onset_threshold = 1.2
    min_intensity = 35.0
    min_interval = 0.1
    num_partials = 18
    partial_spread = 1.0
    decayTime = 1.2
    brightness = 1.0
    dry_wet_mix = 1.0
    attackBase = 0.003
    waveshapeAmt = 0.4
elsif preset = 6
    onset_threshold = 1.5
    min_intensity = 35.0
    min_interval = 0.12
    num_partials = 6
    partial_spread = 0.4
    decayTime = 0.8
    brightness = 0.7
    dry_wet_mix = 0.9
    attackBase = 0.001
    waveshapeAmt = 0.15
elsif preset = 7
    onset_threshold = 1.0
    min_intensity = 32.0
    min_interval = 0.05
    num_partials = 25
    partial_spread = 1.2
    decayTime = 1.8
    brightness = 0.8
    dry_wet_mix = 1.0
    attackBase = 0.008
    waveshapeAmt = 0.25
endif

# ============================================================
# INPUT VALIDATION
# ============================================================
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
name$ = selected$("Sound")
totalDur = Get total duration
sampleRate = Get sampling frequency
numChan = Get number of channels
nyquistFreq = sampleRate / 2

if totalDur < 0.1
    exitScript: "Sound too short (min 0.1s)."
endif

# ============================================================
# ONSET DETECTION
# ============================================================
selectObject: sound
intensityObj = To Intensity: 50, 0, "yes"

selectObject: intensityObj
numFrames = Get number of frames
onset_times# = zero#(500)
numOnsets = 0
lastOnset = -1

for iFrame from 3 to numFrames - 1
    frameTime = Get time from frame number: iFrame
    currInt = Get value in frame: iFrame
    prev2Int = Get value in frame: iFrame - 2
    
    if currInt <> undefined and prev2Int <> undefined
        intDiff = (currInt - prev2Int) / 2
        if intDiff > onset_threshold and currInt > min_intensity
            if frameTime - lastOnset > min_interval
                numOnsets += 1
                onset_times#[numOnsets] = frameTime
                lastOnset = frameTime
            endif
        endif
    endif
endfor

removeObject: intensityObj

if numOnsets = 0
    exitScript: "No onsets found. Try lowering threshold."
endif

writeInfoLine: "Found ", numOnsets, " onsets"

# ============================================================
# CREATE OUTPUT
# ============================================================
wetSignal = Create Sound from formula: "wet", numChan, 0, totalDur, sampleRate, "0"

maxBurstDur = attackBase + attackRandom + (decayTime + decayRandom) * 4
maxBurstDur = min(maxBurstDur, 5)

# ============================================================
# PROCESS ONSETS
# ============================================================
appendInfoLine: "Processing..."

for onsetIdx from 1 to numOnsets
    onsetTime = onset_times#[onsetIdx]
    
    selectObject: sound
    segStart = max(0, onsetTime - 0.02)
    segEnd = min(onsetTime + 0.12, totalDur)
    
    if segEnd - segStart > 0.03
        Extract part: segStart, segEnd, "rectangular", 1, "no"
        segment = selected("Sound")
        
        pitchObj = To Pitch (ac): 0, 50, 15, "no", 0.01, 0.5, 0.01, 0.2, 0.1, 2500
        
        relTime = onsetTime - segStart
        detectedPitch = Get value at time: relTime, "Hertz", "Linear"
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get mean: 0, 0, "Hertz"
        endif
        if detectedPitch = undefined or detectedPitch <= 0
            detectedPitch = Get quantile: 0, 0, 0.5, "Hertz"
        endif
        
        removeObject: segment, pitchObj
        
        if detectedPitch <> undefined and detectedPitch >= 50 and detectedPitch < 4000
            burstEnd = min(onsetTime + maxBurstDur, totalDur)
            burstDur = burstEnd - onsetTime
            
            if burstDur > 0.01
                maxPartial = min(num_partials, floor(nyquistFreq * 0.9 / detectedPitch))
                
                # Create burst accumulator
                burstSound = Create Sound from formula: "burst", 1, 0, burstDur, sampleRate, "0"
                
                for partialNum from 1 to maxPartial
                    partialFreq = detectedPitch * partialNum * (1 + randomUniform(-0.01, 0.01) * partial_spread)
                    
                    if partialFreq < nyquistFreq * 0.95
                        attackTime = attackBase + randomUniform(0, attackRandom)
                        decayVal = decayTime + randomUniform(-decayRandom, decayRandom)
                        decayVal = max(decayVal, 0.05)
                        
                        ampVal = (0.1 / sqrt(partialNum)) * (brightness ^ (partialNum - 1))
                        ampVal = ampVal * (1 + randomUniform(-ampRandom, ampRandom))
                        
                        wsBlend = waveshapeAmt * brightness
                        ampClean = ampVal * (1 - wsBlend)
                        ampWS = ampVal * wsBlend
                        
                        # Build formula strings
                        attStr$ = fixed$(attackTime, 8)
                        decStr$ = fixed$(decayVal, 8)
                        freqStr$ = fixed$(partialFreq, 4)
                        
                        if ampClean > 0.001
                            ampStr$ = fixed$(ampClean, 8)
                            toneClean = Create Sound from formula: "tclean", 1, 0, burstDur, sampleRate,
                            ... ampStr$ + "*sin(2*pi*" + freqStr$ + "*x)*(if x<" + attStr$ + " then x/" + attStr$ + " else exp(-(x-" + attStr$ + ")/" + decStr$ + ") fi)"
                            
                            selectObject: burstSound
                            Formula: "self + Sound_tclean[]"
                            removeObject: toneClean
                        endif
                        
                        if ampWS > 0.001
                            ampWSStr$ = fixed$(ampWS, 8)
                            toneWS = Create Sound from formula: "tws", 1, 0, burstDur, sampleRate,
                            ... ampWSStr$ + "*sin(2*pi*" + freqStr$ + "*x)^3*(if x<" + attStr$ + " then x/" + attStr$ + " else exp(-(x-" + attStr$ + ")/" + decStr$ + ") fi)"
                            
                            selectObject: burstSound
                            Formula: "self + Sound_tws[]"
                            removeObject: toneWS
                        endif
                    endif
                endfor
                
                # Add burst to wet output at onset time
                onsetStr$ = fixed$(onsetTime, 8)
                selectObject: wetSignal
                Formula (part): onsetTime, burstEnd, 1, numChan, "self + Sound_burst(x - " + onsetStr$ + ")"
                
                removeObject: burstSound
            endif
        endif
    endif
    
    if onsetIdx mod 10 = 0
        appendInfoLine: "  ", onsetIdx, "/", numOnsets
    endif
endfor

# ============================================================
# MIX AND FINALIZE
# ============================================================
appendInfoLine: "Mixing..."

selectObject: sound
output = Copy: name$ + "_resonated"

selectObject: output
if dry_wet_mix >= 0.99
    Formula: "Sound_wet[]"
elsif dry_wet_mix <= 0.01
    # Keep original
else
    wetStr$ = fixed$(dry_wet_mix, 4)
    dryStr$ = fixed$(1 - dry_wet_mix, 4)
    Formula: "self * " + dryStr$ + " + Sound_wet[] * " + wetStr$
endif

removeObject: wetSignal
selectObject: output
Scale peak: 0.95

appendInfoLine: "Done!"

if play_result
    Play
endif

selectObject: output
plusObject: sound