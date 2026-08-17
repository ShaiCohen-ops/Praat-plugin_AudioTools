# ============================================================
# Praat AudioTools - Audio File Properties
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2026) - Technical audio inspector / QC
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Lightweight technical inspection of one selected Sound object.
#   Measures structural properties, level/headroom, per-channel signal health,
#   relative activity, and produces compact QC tables and visualization.
#
# Notes:
#   - dBFS-style values assume digital full scale corresponds to |sample| = 1.
#   - Praat Sound objects do not reliably preserve original file bit depth,
#     codec, container metadata, or source path, so those are not guessed here.
#   - "Activity" is relative to the strongest channel's maximum Intensity,
#     not an absolute calibrated SPL threshold.
# ============================================================

clearinfo

nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

soundID = selected("Sound")
selectObject: soundID
soundName$ = selected$("Sound")

form Audio File Properties v0.2
    comment === Technical QC ===
    positive Clipping_threshold_(absolute_sample) 0.999
    positive Activity_threshold_below_peak_(dB) 50
    boolean Draw_visualization 1
endform

if clipping_threshold <= 0
    clipping_threshold = 0.999
endif
if activity_threshold_below_peak <= 0
    activity_threshold_below_peak = 50
endif

procedure formatMaybe: .value, .decimals
    if .value = undefined
        .result$ = "NA"
    else
        .result$ = fixed$(.value, .decimals)
    endif
endproc

# ============================================================
# STRUCTURAL PROPERTIES
# ============================================================
selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
samplePeriod = Get sampling period
nSamples = Get number of samples
channels = Get number of channels
nyquist = sampleRate / 2
xminSound = object[soundID].xmin
xmaxSound = object[soundID].xmax

minutes = floor(duration / 60)
seconds = duration - minutes * 60

# ============================================================
# GLOBAL LEVEL PROPERTIES
# ============================================================
selectObject: soundID
peakAmplitude = Get absolute extremum: 0, 0, "None"
rmsAmplitude = Get root-mean-square: 0, 0
dcOffset = Get mean: 0, 0

peakDbfs = undefined
rmsDbfs = undefined
headroomDb = undefined
crestFactor = undefined
crestDb = undefined
dcRatioPercent = undefined

if peakAmplitude > 0
    peakDbfs = 20 * ln(peakAmplitude) / ln(10)
    headroomDb = -peakDbfs
endif
if rmsAmplitude > 0
    rmsDbfs = 20 * ln(rmsAmplitude) / ln(10)
    dcRatioPercent = 100 * abs(dcOffset) / rmsAmplitude
endif
if rmsAmplitude > 0 and peakAmplitude >= 0
    crestFactor = peakAmplitude / rmsAmplitude
    if crestFactor > 0
        crestDb = 20 * ln(crestFactor) / ln(10)
    endif
endif

# ============================================================
# PER-CHANNEL QC
# ============================================================
Create Table with column names: "AudioFile_Channel_QC", channels, "Channel PeakAmplitude Peak_dBFS RMSAmplitude RMS_dBFS Crest_dB DCOffset DC_over_RMS_percent"
channelTable = selected("Table")

strongestChannel = 1
strongestRms = -1
minChannelRms = undefined
maxChannelRms = undefined
maxDcRatio = 0

for ch from 1 to channels
    selectObject: soundID
    if channels = 1
        channelSound = soundID
        channelIsTemporary = 0
    else
        Extract one channel: ch
        channelSound = selected("Sound")
        channelIsTemporary = 1
    endif

    selectObject: channelSound
    chPeak = Get absolute extremum: 0, 0, "None"
    chRms = Get root-mean-square: 0, 0
    chDc = Get mean: 0, 0

    chPeakDb = undefined
    chRmsDb = undefined
    chCrestDb = undefined
    chDcRatio = undefined

    if chPeak > 0
        chPeakDb = 20 * ln(chPeak) / ln(10)
    endif
    if chRms > 0
        chRmsDb = 20 * ln(chRms) / ln(10)
        chDcRatio = 100 * abs(chDc) / chRms
        chCrest = chPeak / chRms
        if chCrest > 0
            chCrestDb = 20 * ln(chCrest) / ln(10)
        endif
    endif

    channelPeak[ch] = chPeak
    channelPeakDb[ch] = chPeakDb
    channelRms[ch] = chRms
    channelRmsDb[ch] = chRmsDb
    channelDc[ch] = chDc
    channelDcRatio[ch] = chDcRatio
    channelCrestDb[ch] = chCrestDb

    if chRms > strongestRms
        strongestRms = chRms
        strongestChannel = ch
    endif
    if minChannelRms = undefined
        minChannelRms = chRms
    else
        if chRms < minChannelRms
            minChannelRms = chRms
        endif
    endif
    if maxChannelRms = undefined
        maxChannelRms = chRms
    else
        if chRms > maxChannelRms
            maxChannelRms = chRms
        endif
    endif
    if chDcRatio <> undefined
        if chDcRatio > maxDcRatio
            maxDcRatio = chDcRatio
        endif
    endif

    selectObject: channelTable
    Set numeric value: ch, "Channel", ch
    Set numeric value: ch, "PeakAmplitude", chPeak
    Set numeric value: ch, "Peak_dBFS", chPeakDb
    Set numeric value: ch, "RMSAmplitude", chRms
    Set numeric value: ch, "RMS_dBFS", chRmsDb
    Set numeric value: ch, "Crest_dB", chCrestDb
    Set numeric value: ch, "DCOffset", chDc
    Set numeric value: ch, "DC_over_RMS_percent", chDcRatio

    if channelIsTemporary
        selectObject: channelSound
        Remove
    endif
endfor

channelBalanceDb = undefined
if channels >= 2 and minChannelRms > 0 and maxChannelRms > 0
    channelBalanceDb = 20 * ln(maxChannelRms / minChannelRms) / ln(10)
endif

# ============================================================
# STRONGEST CHANNEL + RELATIVE ACTIVITY
# ============================================================
if channels = 1
    strongSound = soundID
    strongSoundIsTemporary = 0
else
    selectObject: soundID
    Extract one channel: strongestChannel
    strongSound = selected("Sound")
    strongSoundIsTemporary = 1
endif

activePercent = undefined
activityThresholdDb = undefined
validIntensityFrames = 0
activeFrames = 0

# Very short Sounds may not support a meaningful Intensity analysis.
if duration >= 0.08 and strongestRms > 0
    selectObject: strongSound
    To Intensity: 50, 0, "yes"
    intensityID = selected("Intensity")
    nIntensityFrames = Get number of frames
    maxIntensity = Get maximum: 0, 0, "Parabolic"

    if nIntensityFrames > 0
        if maxIntensity <> undefined
            activityThresholdDb = maxIntensity - activity_threshold_below_peak
            for f from 1 to nIntensityFrames
                selectObject: intensityID
                iValue = Get value in frame: f
                if iValue <> undefined
                    validIntensityFrames = validIntensityFrames + 1
                    if iValue >= activityThresholdDb
                        activeFrames = activeFrames + 1
                    endif
                endif
            endfor
            if validIntensityFrames > 0
                activePercent = 100 * activeFrames / validIntensityFrames
            endif
        endif
    endif

    selectObject: intensityID
    Remove
endif

# ============================================================
# QC INTERPRETATION
# ============================================================
qcCount = 0
qcText$ = ""

if peakAmplitude > 1
    qcText$ = qcText$ + "Samples exceed +/-1; playback/export clipping possible. "
    qcCount = qcCount + 1
elsif peakAmplitude >= clipping_threshold
    qcText$ = qcText$ + "Peak is at/near the clipping threshold. "
    qcCount = qcCount + 1
endif

if maxDcRatio >= 1
    qcText$ = qcText$ + "DC offset exceeds 1 percent of RMS in at least one channel. "
    qcCount = qcCount + 1
endif

if channelBalanceDb <> undefined
    if channelBalanceDb >= 3
        qcText$ = qcText$ + "Channel RMS spread is at least 3 dB. "
        qcCount = qcCount + 1
    endif
endif

if activePercent <> undefined
    if activePercent < 50
        qcText$ = qcText$ + "Less than half of analyzed frames are within the activity range. "
        qcCount = qcCount + 1
    endif
endif

if sampleRate < 40000
    qcText$ = qcText$ + "Nyquist is below 20 kHz. "
    qcCount = qcCount + 1
endif

if qcCount = 0
    qcText$ = "No basic technical QC flags detected."
endif

# ============================================================
# SUMMARY TABLE
# ============================================================
Create Table with column names: "AudioFile_Properties", 1, "SoundName Duration_s StartTime_s EndTime_s SampleRate_Hz Nyquist_Hz SamplePeriod_s Samples Channels PeakAmplitude Peak_dBFS RMSAmplitude RMS_dBFS Headroom_dB Crest_dB DCOffset DC_over_RMS_percent StrongestChannel Channel_RMS_Spread_dB Active_percent QC"
propertiesTable = selected("Table")

Set string value: 1, "SoundName", soundName$
Set numeric value: 1, "Duration_s", duration
Set numeric value: 1, "StartTime_s", xminSound
Set numeric value: 1, "EndTime_s", xmaxSound
Set numeric value: 1, "SampleRate_Hz", sampleRate
Set numeric value: 1, "Nyquist_Hz", nyquist
Set numeric value: 1, "SamplePeriod_s", samplePeriod
Set numeric value: 1, "Samples", nSamples
Set numeric value: 1, "Channels", channels
Set numeric value: 1, "PeakAmplitude", peakAmplitude
Set numeric value: 1, "Peak_dBFS", peakDbfs
Set numeric value: 1, "RMSAmplitude", rmsAmplitude
Set numeric value: 1, "RMS_dBFS", rmsDbfs
Set numeric value: 1, "Headroom_dB", headroomDb
Set numeric value: 1, "Crest_dB", crestDb
Set numeric value: 1, "DCOffset", dcOffset
Set numeric value: 1, "DC_over_RMS_percent", dcRatioPercent
Set numeric value: 1, "StrongestChannel", strongestChannel
Set numeric value: 1, "Channel_RMS_Spread_dB", channelBalanceDb
Set numeric value: 1, "Active_percent", activePercent
Set string value: 1, "QC", qcText$

# ============================================================
# INFO WINDOW
# ============================================================
clearinfo
writeInfoLine: "=== AUDIO FILE PROPERTIES / TECHNICAL QC ==="
appendInfoLine: "Sound:           ", soundName$
appendInfoLine: "Duration:        ", minutes, " min ", fixed$(seconds, 2), " s  (", fixed$(duration, 3), " s)"
appendInfoLine: "Time domain:     ", fixed$(xminSound, 6), " to ", fixed$(xmaxSound, 6), " s"
appendInfoLine: "Sample rate:     ", fixed$(sampleRate, 0), " Hz"
appendInfoLine: "Nyquist:         ", fixed$(nyquist, 0), " Hz"
appendInfoLine: "Samples:         ", nSamples, " per channel"
appendInfoLine: "Channels:        ", channels
appendInfoLine: "Strongest ch.:   ", strongestChannel
appendInfoLine: ""

@formatMaybe: peakAmplitude, 6
appendInfoLine: "Peak amplitude:  ", formatMaybe.result$
@formatMaybe: peakDbfs, 2
appendInfoLine: "Peak level:      ", formatMaybe.result$, " dBFS  (assuming full scale = 1)"
@formatMaybe: rmsAmplitude, 6
appendInfoLine: "RMS amplitude:   ", formatMaybe.result$
@formatMaybe: rmsDbfs, 2
appendInfoLine: "RMS level:       ", formatMaybe.result$, " dBFS"
@formatMaybe: headroomDb, 2
appendInfoLine: "Headroom:        ", formatMaybe.result$, " dB"
@formatMaybe: crestDb, 2
appendInfoLine: "Crest factor:    ", formatMaybe.result$, " dB"
@formatMaybe: dcOffset, 7
appendInfoLine: "DC offset:       ", formatMaybe.result$
@formatMaybe: dcRatioPercent, 3
appendInfoLine: "DC / RMS:        ", formatMaybe.result$, " %"
if channelBalanceDb <> undefined
    appendInfoLine: "Channel spread:  ", fixed$(channelBalanceDb, 2), " dB RMS (max/min channel)"
endif
if activePercent <> undefined
    appendInfoLine: "Activity:        ", fixed$(activePercent, 1), "% of valid Intensity frames within ", fixed$(activity_threshold_below_peak, 1), " dB of peak"
endif
appendInfoLine: ""
appendInfoLine: "QC: ", qcText$
appendInfoLine: ""
appendInfoLine: "Tables: AudioFile_Properties, AudioFile_Channel_QC"
appendInfoLine: "Note: original file bit depth/codec/container metadata are not inferred from a Praat Sound object."

# ============================================================
# VISUALIZATION: TECHNICAL PROFILE
# ============================================================
if draw_visualization
    Erase all

    # Title strip
    Select outer viewport: 0, 8, 0.02, 0.36
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Audio File Properties##"

    # Metadata strip
    Select outer viewport: 0, 8, 0.40, 0.72
    Axes: 0, 1, 0, 1
    Font size: 8
    cleanName$ = replace$(soundName$, "_", " ", 0)
    cleanName$ = replace$(cleanName$, "%", "pct", 0)
    Text: 0.5, "centre", 0.5, "half", cleanName$ + "  |  " + fixed$(sampleRate, 0) + " Hz  |  " + string$(channels) + " ch  |  " + fixed$(duration, 2) + " s"

    # Panel 1 title
    Select outer viewport: 0, 8, 0.78, 1.04
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "##Strongest-channel waveform##   channel " + string$(strongestChannel)

    # Panel 1 waveform
    selectObject: strongSound
    strongPeak = Get absolute extremum: 0, 0, "None"
    waveRange = max(0.001, strongPeak * 1.08)
    Select outer viewport: 0, 8, 1.04, 3.20
    Select inner viewport: 0.62, 7.62, 1.18, 3.02
    Draw: xminSound, xmaxSound, -waveRange, waveRange, "no", "Curve"
    Select inner viewport: 0.62, 7.62, 1.18, 3.02
    Axes: xminSound, xmaxSound, -waveRange, waveRange
    Colour: "Black"
    Draw inner box
    Marks bottom: 4, "yes", "yes", "no"
    Marks left: 3, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Time (s)"
    Text left: "yes", "Amplitude"

    # Panel 2 title
    Select outer viewport: 0, 8, 3.30, 3.58
    Axes: 0, 1, 0, 1
    Font size: 9
    Text: 0.5, "centre", 0.5, "half", "##Channel level profile##   Peak and RMS relative to full scale"

    nVizChannels = min(channels, 8)
    levelTop = 3
    if peakDbfs <> undefined
        if peakDbfs > levelTop
            levelTop = peakDbfs + 2
        endif
    endif

    Select outer viewport: 0, 8, 3.58, 5.72
    Select inner viewport: 0.72, 7.55, 3.72, 5.52
    Axes: 0.5, nVizChannels + 0.5, -66, levelTop
    Paint rectangle: "{0.98, 0.98, 0.98}", 0.5, nVizChannels + 0.5, -66, levelTop

    Colour: "{0.75, 0.75, 0.75}"
    Draw line: 0.5, 0, nVizChannels + 0.5, 0
    Draw line: 0.5, -20, nVizChannels + 0.5, -20
    Draw line: 0.5, -40, nVizChannels + 0.5, -40
    Draw line: 0.5, -60, nVizChannels + 0.5, -60

    for ch from 1 to nVizChannels
        pDb = channelPeakDb[ch]
        rDb = channelRmsDb[ch]
        if pDb <> undefined
            pPlot = max(-60, min(levelTop, pDb))
            Paint rectangle: "{0.72, 0.76, 0.82}", ch - 0.28, ch + 0.28, -60, pPlot
        endif
        if rDb <> undefined
            rPlot = max(-60, min(levelTop, rDb))
            Paint rectangle: "{0.40, 0.49, 0.61}", ch - 0.13, ch + 0.13, -60, rPlot
        endif
        Colour: "Black"
        Font size: 7
        Text: ch, "centre", -64, "half", "Ch" + string$(ch)
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left every: 1, 20, "yes", "yes", "no"
    Text left: "yes", "dBFS"
    Text: 0.65, "left", levelTop - 3, "half", "wide=Peak   narrow=RMS"
    if channels > nVizChannels
        Text: nVizChannels + 0.35, "right", -64, "half", "first 8 shown"
    endif

    # Panel 3: activity + compact metrics
    Select outer viewport: 0, 8, 5.86, 7.36
    Select inner viewport: 0.52, 7.56, 5.98, 7.24
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1

    Font size: 9
    Colour: "Black"
    Text: 0.03, "left", 0.86, "half", "##Signal health##"

    Font size: 8
    Text: 0.03, "left", 0.66, "half", "Activity"
    Paint rectangle: "{0.88, 0.88, 0.88}", 0.16, 0.58, 0.62, 0.70
    if activePercent <> undefined
        activityCap = max(0, min(100, activePercent))
        Paint rectangle: "{0.48, 0.58, 0.48}", 0.16, 0.16 + 0.42 * activityCap / 100, 0.62, 0.70
        Colour: "Black"
        Text: 0.60, "left", 0.66, "half", fixed$(activePercent, 1) + " percent"
    else
        Text: 0.60, "left", 0.66, "half", "NA"
    endif

    @formatMaybe: headroomDb, 1
    Text: 0.03, "left", 0.44, "half", "Headroom: " + formatMaybe.result$ + " dB"
    @formatMaybe: crestDb, 1
    Text: 0.31, "left", 0.44, "half", "Crest: " + formatMaybe.result$ + " dB"
    @formatMaybe: dcRatioPercent, 2
    Text: 0.53, "left", 0.44, "half", "DC/RMS: " + formatMaybe.result$ + " percent"
    if channelBalanceDb <> undefined
        Text: 0.76, "left", 0.44, "half", "Ch spread: " + fixed$(channelBalanceDb, 1) + " dB"
    endif

    Font size: 7
    if qcCount = 0
        Text: 0.03, "left", 0.18, "half", "QC: no basic technical flags detected"
    else
        qcShort$ = left$(qcText$, 120)
        Text: 0.03, "left", 0.18, "half", "QC: " + qcShort$
    endif
    Draw rectangle: 0, 1, 0, 1

    # Footer
    Select outer viewport: 0, 8, 7.50, 7.92
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.5, "centre", 0.52, "half", "dBFS assumes full scale = +/-1  |  activity threshold = peak Intensity - " + fixed$(activity_threshold_below_peak, 1) + " dB  |  raw values in Tables"
endif

# Cleanup temporary strongest-channel object only after visualization.
if strongSoundIsTemporary
    selectObject: strongSound
    Remove
endif

# Return useful outputs to the selection.
selectObject: propertiesTable
plusObject: channelTable

appendInfoLine: "Done."
