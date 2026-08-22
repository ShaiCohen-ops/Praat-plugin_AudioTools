# ============================================================
# Praat AudioTools - Stretch_Tremolo_Ambience.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Stretch-Tremolo Ambience creates an extended ambient cloud from the
#   selected Sound. A centered mono analysis/synthesis copy is lengthened
#   with Praat overlap-add, modulated by a unipolar tremolo envelope, and
#   mixed in parallel with the original dry channels. When the wet cloud is
#   active, output duration follows the stretched cloud; the dry source is
#   present over its original duration and the cloud continues as a tail.
#
#   Multichannel dry audio is preserved. The wet cloud is intentionally mono
#   and is copied equally to all output channels. If a multichannel fold-down
#   nearly cancels, the strongest input channel is used for the wet cloud.
#
# Changelog v0.4:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# Changelog v0.3:
#   - Keep the full stretched cloud instead of cropping it to source duration
#   - Preserve all dry input channels; centered mono wet cloud is deliberate
#   - Add fold-down cancellation fallback for the cloud source
#   - Use local-time tremolo that starts at unity gain
#   - Correct Ghostly Trail to a genuinely slow pulse
#   - Remove peak normalization; add attenuation-only Safety_peak
#   - Preserve source start time and sampling rate
#   - Add Random_seed for reproducible overlap-add stretching
#   - Exact source bypass for Dry_level=1 and Wet_cloud_level=0
#   - Update visualization to AudioTools house style
# ============================================================

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

original = selected("Sound")
original_name$ = selected$("Sound")

selectObject: original
originalStart = Get start time
originalEnd = Get end time
duration = Get total duration
sr = Get sampling frequency
channels = Get number of channels
originalPeak = Get absolute extremum: 0, 0, "None"
originalNSamples = Get number of samples

# === Form ===
form Stretch-Tremolo Ambience v0.4
    comment Select a Sound object first

    comment === Preset ===
    optionmenu Preset 1
        option Custom (use settings below)
        option Ethereal Pad (Smooth)
        option Ghostly Trail (Slow pulse)
        option Dark Drone (Deep stretch)
        option Shimmering Tail (Fast wobble)

    comment === Stretch / Cloud ===
    real Stretch_factor 3.0
    comment (1 = source duration; >1 creates a longer cloud tail)
    real Cloud_Rate_Hz 2.0
    real Cloud_Depth 0.5
    comment (0 = no tremolo; 1 = full attenuation at the trough)
    integer Random_seed 0
    comment (0 = unpredictable; nonzero = reproducible stretch)

    comment === Parallel Mix ===
    real Dry_level 1.0
    real Wet_cloud_level 0.6

    comment === Output ===
    real Safety_peak 0.99
    comment (0 disables; otherwise attenuation only)
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    stretch_factor = 4.0
    cloud_Rate_Hz = 0.5
    cloud_Depth = 0.3
    dry_level = 1.0
    wet_cloud_level = 0.5
    presetName$ = "Ethereal"
elsif preset = 3
    stretch_factor = 2.5
    cloud_Rate_Hz = 0.30
    cloud_Depth = 0.6
    dry_level = 1.0
    wet_cloud_level = 0.4
    presetName$ = "Ghostly"
elsif preset = 4
    stretch_factor = 8.0
    cloud_Rate_Hz = 0.2
    cloud_Depth = 0.2
    dry_level = 1.0
    wet_cloud_level = 0.7
    presetName$ = "Drone"
elsif preset = 5
    stretch_factor = 3.0
    cloud_Rate_Hz = 6.0
    cloud_Depth = 0.5
    dry_level = 1.0
    wet_cloud_level = 0.4
    presetName$ = "Shimmer"
else
    presetName$ = "Custom"
endif

# === Defensive limits ===
if stretch_factor < 1
    stretch_factor = 1
endif
if stretch_factor > 20
    stretch_factor = 20
endif
if cloud_Rate_Hz < 0
    cloud_Rate_Hz = 0
endif
if cloud_Rate_Hz > 30
    cloud_Rate_Hz = 30
endif
if cloud_Depth < 0
    cloud_Depth = 0
endif
if cloud_Depth > 1
    cloud_Depth = 1
endif
if random_seed < 0
    random_seed = 0
endif
if random_seed > 2147483647
    random_seed = 2147483647
endif
if dry_level < 0
    dry_level = 0
endif
if dry_level > 2
    dry_level = 2
endif
if wet_cloud_level < 0
    wet_cloud_level = 0
endif
if wet_cloud_level > 2
    wet_cloud_level = 2
endif
if safety_peak < 0
    safety_peak = 0
endif
if safety_peak > 1
    safety_peak = 1
endif

# Adaptive PSOLA pitch bounds for very short Sounds.
olaMinPitch = max(75, 3 / duration)
olaMaxPitch = max(600, 2 * olaMinPitch)
nyquistPitchLimit = 0.45 * sr
if olaMaxPitch > nyquistPitchLimit
    olaMaxPitch = nyquistPitchLimit
endif
if olaMinPitch >= olaMaxPitch
    exitScript: "The selected Sound is too short for overlap-add stretching at this sample rate."
endif

# === Info ===
writeInfoLine: "=== Stretch-Tremolo Ambience v0.4 ==="
appendInfoLine: "Source: ", original_name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Channels: ", channels, " | Sample rate: ", fixed$(sr, 0), " Hz"
appendInfoLine: "Stretch: ", fixed$(stretch_factor, 2), "x"
appendInfoLine: "Cloud tremolo: ", fixed$(cloud_Rate_Hz, 3), " Hz | depth ", fixed$(cloud_Depth, 3)
appendInfoLine: "Dry level: ", fixed$(dry_level, 3), " | Wet cloud level: ", fixed$(wet_cloud_level, 3)
appendInfoLine: "Random seed: ", random_seed
appendInfoLine: "OLA pitch range: ", fixed$(olaMinPitch, 1), " - ", fixed$(olaMaxPitch, 1), " Hz"
appendInfoLine: "Safety peak: ", fixed$(safety_peak, 3), " (0 = disabled)"
appendInfoLine: ""

# ============================================================
# EXACT BYPASS / DRY-ONLY PATH
# ============================================================
if wet_cloud_level <= 0
    selectObject: original
    Copy: original_name$ + "_ambient_" + presetName$
    result = selected("Sound")

    if dry_level <> 1
        Formula: ~ self * dry_level
    endif

    selectObject: result
    peakBeforeSafety = Get absolute extremum: 0, 0, "None"
    if not (dry_level = 1)
        if safety_peak > 0 and peakBeforeSafety > safety_peak
            Multiply: safety_peak / peakBeforeSafety
        endif
    endif
    outputPeak = Get absolute extremum: 0, 0, "None"
    outputDuration = Get total duration

    appendInfoLine: "Wet cloud disabled."
    if dry_level = 1
        appendInfoLine: "Exact dry bypass; Safety_peak intentionally skipped."
    endif
    appendInfoLine: "Output duration: ", fixed$(outputDuration, 3), " s"
    appendInfoLine: "Peak before/after safety: ", fixed$(peakBeforeSafety, 6), " / ", fixed$(outputPeak, 6)

    goto FINISH
endif

# ============================================================
# 1. CENTERED MONO CLOUD SOURCE WITH CANCELLATION FALLBACK
# ============================================================
appendInfoLine: "Creating cloud source..."

if channels = 1
    selectObject: original
    cloudSource = Copy: original_name$ + "_cloud_source"
    cloudSourceLabel$ = "mono input"
else
    selectObject: original
    cloudSource = Convert to mono
    Rename: original_name$ + "_cloud_fold"
    foldPeak = Get absolute extremum: 0, 0, "None"

    bestChannel = 1
    bestPeak = -1
    for ch from 1 to channels
        selectObject: original
        Extract one channel: ch
        tmpCh = selected("Sound")
        chPeak = Get absolute extremum: 0, 0, "None"
        if chPeak > bestPeak
            bestPeak = chPeak
            bestChannel = ch
        endif
        removeObject: tmpCh
    endfor

    if bestPeak > 0 and foldPeak < 0.10 * bestPeak
        removeObject: cloudSource
        selectObject: original
        Extract one channel: bestChannel
        cloudSource = selected("Sound")
        Rename: original_name$ + "_cloud_ch" + string$(bestChannel)
        cloudSourceLabel$ = "channel " + string$(bestChannel) + " (fold-down cancellation fallback)"
    else
        cloudSourceLabel$ = "mono fold-down"
    endif
endif
appendInfoLine: "Cloud source: ", cloudSourceLabel$

# ============================================================
# 2. FULL TIME-STRETCHED CLOUD
# ============================================================
appendInfoLine: "Lengthening cloud..."
if random_seed <> 0
    random_initializeWithSeedUnsafelyButPredictably (random_seed)
else
    random_initializeSafelyAndUnpredictably ()
endif
selectObject: cloudSource
Lengthen (overlap-add): olaMinPitch, olaMaxPitch, stretch_factor
stretchedCloud = selected("Sound")
random_initializeSafelyAndUnpredictably ()
removeObject: cloudSource

selectObject: stretchedCloud
cloudStart = Get start time
cloudEnd = Get end time
cloudDuration = Get total duration

# Local-time unipolar tremolo: starts at unity, bottoms at 1-depth.
# A short tail fade avoids a hard truncation at the stretched endpoint.
tailFade = min(0.05, 0.05 * cloudDuration)
if tailFade < 1 / sr
    tailFade = 1 / sr
endif
Formula: ~ self * (1 - cloud_Depth * (1 - cos(2*pi*cloud_Rate_Hz*(x-originalStart))) / 2) * if x > cloudEnd-tailFade then max(0, (cloudEnd-x)/tailFade) else 1 fi
Rename: original_name$ + "_cloud_" + presetName$
cloudFinal = selected("Sound")

appendInfoLine: "Cloud duration: ", fixed$(cloudDuration, 3), " s"
appendInfoLine: "Cloud tail extension: ", fixed$(cloudDuration-duration, 3), " s"

# ============================================================
# 3. CREATE EXTENDED MULTICHANNEL OUTPUT AND MIX DRY + CLOUD
# ============================================================
appendInfoLine: "Mixing dry source with extended cloud..."

Create Sound from formula: original_name$ + "_ambient_" + presetName$, channels, originalStart, cloudEnd, sr, "0"
result = selected("Sound")

originalStr$ = string$(original)
cloudStr$ = string$(cloudFinal)
dryStr$ = string$(dry_level)
wetStr$ = string$(wet_cloud_level)
originalNStr$ = string$(originalNSamples)

Formula: "if col <= " + originalNStr$ + " then " + dryStr$ + " * object[" + originalStr$ + ", row, col] + " + wetStr$ + " * object[" + cloudStr$ + ", 1, col] else " + wetStr$ + " * object[" + cloudStr$ + ", 1, col] fi"

selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if safety_peak > 0 and peakBeforeSafety > safety_peak
    Multiply: safety_peak / peakBeforeSafety
endif
outputPeak = Get absolute extremum: 0, 0, "None"
outputDuration = Get total duration

appendInfoLine: "Output duration: ", fixed$(outputDuration, 3), " s"
appendInfoLine: "Peak before/after safety: ", fixed$(peakBeforeSafety, 6), " / ", fixed$(outputPeak, 6)

# ============================================================
# VISUALIZATION - AudioTools house style
# ============================================================
if draw_visualization
    pageHeight = 5.2
    Erase all

    # Title
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Stretch-Tremolo Ambience v0.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", "Stretch-Tremolo Ambience.praat  |  " + presetName$ + "  |  extended mono cloud + dry source"

    # Input
    Select outer viewport: 0, 4, 0.62, 1.72
    Select inner viewport: 0.45, 3.82, 0.78, 1.58
    selectObject: original
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Input"
    Text bottom: "yes", "Time (s)"

    # Output
    Select outer viewport: 4, 8, 0.62, 1.72
    Select inner viewport: 4.35, 7.78, 0.78, 1.58
    selectObject: result
    Colour: "{0.22, 0.46, 0.82}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Text left: "yes", "Output"
    Text bottom: "yes", "Time (s)"

    # Cloud waveform
    Select outer viewport: 0, 8, 1.92, 2.92
    Select inner viewport: 0.55, 7.70, 2.06, 2.80
    selectObject: cloudFinal
    Colour: "{0.48, 0.35, 0.74}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Wet cloud"
    Text bottom: "yes", "Time (s)"

    # Tremolo envelope
    Select outer viewport: 0, 8, 3.10, 4.05
    Select inner viewport: 0.55, 7.70, 3.24, 3.92
    vizDur = min(4, cloudDuration)
    Axes: 0, vizDur, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, vizDur, 0, 1.05
    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 1, vizDur, 1
    Solid line
    Colour: "{0.48, 0.35, 0.74}"
    Line width: 1.5
    nPoints = 300
    for p from 2 to nPoints
        t1 = (p-2)/(nPoints-1)*vizDur
        t2 = (p-1)/(nPoints-1)*vizDur
        a1 = 1 - cloud_Depth * (1 - cos(2*pi*cloud_Rate_Hz*t1)) / 2
        a2 = 1 - cloud_Depth * (1 - cos(2*pi*cloud_Rate_Hz*t2)) / 2
        Draw line: t1, a1, t2, a2
    endfor
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Cloud gain"
    Text bottom: "yes", "Local time (s)"

    # Summary
    Select outer viewport: 0, 8, 4.25, 5.05
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half", "Stretch " + fixed$(stretch_factor, 2) + "x  |  cloud " + fixed$(cloudDuration, 2) + " s  |  tremolo " + fixed$(cloud_Rate_Hz, 2) + " Hz / depth " + fixed$(cloud_Depth, 2)
    Text: 0.02, "left", 0.18, "half", "Dry " + fixed$(dry_level, 2) + "  |  Wet " + fixed$(wet_cloud_level, 2) + "  |  output " + fixed$(outputDuration, 2) + " s  |  channels " + string$(channels) + "  |  Safety " + fixed$(safety_peak, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1
    # Restore full Picture page for export
    Select outer viewport: 0, 8, 0, pageHeight
    Axes: 0, 1, 0, 1
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

removeObject: cloudFinal

goto FINISH

label FINISH
selectObject: result
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

if play_result
    Play
endif

selectObject: result
