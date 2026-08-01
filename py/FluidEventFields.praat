# ============================================================
# Praat AudioTools - FluidEventFields.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.4 (2026)
#
# Description:
#   Fluid Event Fields -- a compositional companion to FluidVectorFields.praat
#   ("Fluid Spectral Warp"). Where that instrument continuously deforms a
#   sound's spectral phase through a vortex/sink/source/shear field, this
#   instrument segments the sound into discrete time-domain EVENTS (onsets,
#   or fixed grains), treats each event as a point in a (time, descriptor)
#   plane, carries that point forward through the same analytic field, and
#   re-renders the events at their new positions -- reordered, dispersed,
#   duplicated, collided -- as a new arrangement of the original material.
#
#   Praat is the user-facing controller: it validates the selection,
#   presents the form, applies presets, writes the temporary WAV and
#   field-plan CSV, runs the Python engine, imports and reports the result,
#   parses the statistics, draws the visualization, and cleans up. All
#   segmentation, field integration, and rendering happens in Python, in
#   the paired script fluid_event_fields.py.
#
#   Canvas policy is explicit. Preserve and Wrap always keep the source
#   duration; Expand may create a longer result when events are dispersed,
#   duplicated, or collision-resolved beyond the original boundary.
#
#   FluidVectorFields.praat / fluid_vector_fields.py are left untouched by
#   this script and remain the correct tool for continuous phase-warp
#   processing under the "Fluid Spectral Warp" identity.
#
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# ============================================================

# --------------------------- 1. Selection check --------------------------

nSel = numberOfSelected ("Sound")
if nSel = 0
    exitScript: "Please select exactly one Sound object."
elsif nSel > 1
    exitScript: "Please select exactly one Sound object (", nSel, " are selected)."
endif

sound = selected ("Sound")
selectObject: sound
sourceName$ = selected$ ("Sound")
sourceDuration = Get total duration
sourceSampleRate = Get sampling frequency
sourceChannels = Get number of channels
sourceRMS = Get root-mean-square: 0, 0
sourcePeak = Get absolute extremum: 0, 0, "None"

if sourceDuration <= 0
    exitScript: "The selected Sound has no usable samples."
endif
if sourceSampleRate <= 0
    exitScript: "The selected Sound has an invalid sample rate."
endif

# --------------------------------- 2. Form --------------------------------
# The normal preset workflow uses one compact dialog. The detailed controls
# are shown only when Custom is selected, split across three short pages so
# the interface fits on smaller displays.

form Fluid Event Fields
    optionmenu Preset: 1
        option Vortex Motion
        option Density Collapse
        option Spectral Bloom
        option Cyclic Return
        option Shear Scatter
        option Custom
    real Motion_amount_(0-2) 1.00
    real Centre_time_(0-1) 0.50
    optionmenu Normalize_mode: 3
        option None
        option Peak
        option RMS
    boolean Draw_visualization 1
    boolean Play_result 1
endform

motionAmount = motion_amount
centreTimeNorm = centre_time
normalizeMode$ = normalize_mode$
drawViz = draw_visualization
playResult = play_result

# Complete internal defaults. A named preset replaces this entire cluster;
# Custom exposes it through three compact forms below.
segmentationMode$ = "Fixed grain"
grainSize = 0.20
onsetSensitivity = 0.30
minEventDuration = 0.05
preOnset = 0.008
postTail = 0.030
verticalAxis$ = "Spectral centroid"
fieldType$ = "Vortex"
descriptorCentreNorm = 0.50
timeRadius = 0.50 * sourceDuration
descriptorRadiusNorm = 0.45
flowStrength = 0.60
flowDirection$ = "Positive"
viscosity = 0.65
integrationAmount = 1.20
flowSteps = 10
canvasPolicy$ = "Preserve"
durationResponse = 0.10
verticalResponseMode$ = "None"
verticalResponse = 0.00
collisionPolicy$ = "Layer"
minEventSpacing = 0.00
eventOverlap = 0.25
boundaryBehavior$ = "Reflect"
preserveOrder = 0
dupProbability = 0.00
dupCount = 0
densityGainCompensation = 0.35
dryEventInclusion = 0.00
originalLayerAmount = 0.00
randomSeed = 0
quality$ = "Standard"
sparseOnsetFallback = 1

# ----------------------------- 3. Apply preset ----------------------------

if preset$ = "Vortex Motion"
    segmentationMode$ = "Fixed grain"
    grainSize = 0.20
    preOnset = 0.00
    postTail = 0.00
    verticalAxis$ = "Spectral centroid"
    fieldType$ = "Vortex"
    descriptorCentreNorm = 0.50
    timeRadius = 0.50 * sourceDuration
    descriptorRadiusNorm = 0.45
    flowStrength = 0.60
    flowDirection$ = "Positive"
    viscosity = 0.65
    integrationAmount = 1.20
    flowSteps = 10
    canvasPolicy$ = "Preserve"
    durationResponse = 0.10
    verticalResponseMode$ = "None"
    verticalResponse = 0.00
    collisionPolicy$ = "Layer"
    minEventSpacing = 0.00
    eventOverlap = 0.25
    boundaryBehavior$ = "Reflect"
    preserveOrder = 0
    dupProbability = 0.00
    dupCount = 0
    densityGainCompensation = 0.35
    dryEventInclusion = 0.00
    originalLayerAmount = 0.00
elsif preset$ = "Density Collapse"
    segmentationMode$ = "Onset detection"
    onsetSensitivity = 0.28
    minEventDuration = 0.04
    preOnset = 0.008
    postTail = 0.040
    verticalAxis$ = "RMS energy"
    fieldType$ = "Sink"
    descriptorCentreNorm = 0.60
    timeRadius = 0.45 * sourceDuration
    descriptorRadiusNorm = 0.55
    flowStrength = 0.80
    flowDirection$ = "Positive"
    viscosity = 0.60
    integrationAmount = 1.60
    flowSteps = 10
    canvasPolicy$ = "Preserve"
    durationResponse = 0.15
    verticalResponseMode$ = "Gain"
    verticalResponse = 0.25
    collisionPolicy$ = "Layer"
    minEventSpacing = 0.00
    eventOverlap = 0.25
    boundaryBehavior$ = "Clip"
    preserveOrder = 0
    dupProbability = 0.00
    dupCount = 0
    densityGainCompensation = 0.75
    dryEventInclusion = 0.00
    originalLayerAmount = 0.00
elsif preset$ = "Spectral Bloom"
    segmentationMode$ = "Fixed grain"
    grainSize = 0.18
    preOnset = 0.00
    postTail = 0.00
    verticalAxis$ = "Spectral centroid"
    fieldType$ = "Source"
    descriptorCentreNorm = 0.50
    timeRadius = 0.42 * sourceDuration
    descriptorRadiusNorm = 0.50
    flowStrength = 0.72
    flowDirection$ = "Positive"
    viscosity = 0.58
    integrationAmount = 1.35
    flowSteps = 10
    canvasPolicy$ = "Expand"
    durationResponse = 0.25
    verticalResponseMode$ = "None"
    verticalResponse = 0.00
    collisionPolicy$ = "Layer"
    minEventSpacing = 0.00
    eventOverlap = 0.30
    boundaryBehavior$ = "Open"
    preserveOrder = 0
    dupProbability = 0.10
    dupCount = 1
    densityGainCompensation = 0.55
    dryEventInclusion = 0.00
    originalLayerAmount = 0.00
elsif preset$ = "Cyclic Return"
    segmentationMode$ = "Fixed grain"
    grainSize = 0.16
    preOnset = 0.00
    postTail = 0.00
    verticalAxis$ = "Dominant frequency"
    fieldType$ = "Vortex"
    descriptorCentreNorm = 0.50
    timeRadius = 0.42 * sourceDuration
    descriptorRadiusNorm = 0.45
    flowStrength = 0.68
    flowDirection$ = "Positive"
    viscosity = 0.48
    integrationAmount = 2.40
    flowSteps = 14
    canvasPolicy$ = "Wrap"
    durationResponse = 0.10
    verticalResponseMode$ = "None"
    verticalResponse = 0.00
    collisionPolicy$ = "Layer"
    minEventSpacing = 0.00
    eventOverlap = 0.35
    boundaryBehavior$ = "Wrap"
    preserveOrder = 0
    dupProbability = 0.25
    dupCount = 2
    densityGainCompensation = 0.55
    dryEventInclusion = 0.00
    originalLayerAmount = 0.00
elsif preset$ = "Shear Scatter"
    segmentationMode$ = "Fixed grain"
    grainSize = 0.18
    preOnset = 0.00
    postTail = 0.00
    verticalAxis$ = "Spectral centroid"
    fieldType$ = "Shear"
    descriptorCentreNorm = 0.50
    timeRadius = 0.48 * sourceDuration
    descriptorRadiusNorm = 0.52
    flowStrength = 0.70
    flowDirection$ = "Positive"
    viscosity = 0.42
    integrationAmount = 1.35
    flowSteps = 10
    canvasPolicy$ = "Expand"
    durationResponse = 0.35
    verticalResponseMode$ = "None"
    verticalResponse = 0.00
    collisionPolicy$ = "Repel"
    minEventSpacing = 0.015
    eventOverlap = 0.25
    boundaryBehavior$ = "Open"
    preserveOrder = 0
    dupProbability = 0.00
    dupCount = 0
    densityGainCompensation = 0.50
    dryEventInclusion = 0.00
    originalLayerAmount = 0.00
elsif preset$ = "Custom"
    sparseOnsetFallback = 0

    beginPause: "Custom 1 of 4: Analysis"
        optionmenu: "Segmentation mode", 2
            option: "Onset detection"
            option: "Fixed grain"
        positive: "Grain size (s)", 0.20
        real: "Onset sensitivity (0-1)", 0.30
        positive: "Minimum event duration (s)", 0.05
        real: "Pre onset capture (s)", 0.008
        real: "Post event tail (s)", 0.030
        optionmenu: "Vertical axis", 1
            option: "Spectral centroid"
            option: "Dominant frequency"
            option: "RMS energy"
    endPause: "Next", 1
    segmentationMode$ = segmentation_mode$
    grainSize = grain_size
    onsetSensitivity = onset_sensitivity
    minEventDuration = minimum_event_duration
    preOnset = pre_onset_capture
    postTail = post_event_tail
    verticalAxis$ = vertical_axis$

    beginPause: "Custom 2 of 4: Field"
        optionmenu: "Field type", 1
            option: "Vortex"
            option: "Sink"
            option: "Source"
            option: "Shear"
        real: "Descriptor centre (0-1)", 0.50
        positive: "Time radius (s)", 1.00
        positive: "Descriptor radius (0-1)", 0.45
        real: "Flow strength (0-1)", 0.65
        optionmenu: "Flow direction", 1
            option: "Positive"
            option: "Negative"
        real: "Viscosity (0-1)", 0.60
        real: "Integration amount", 1.40
        natural: "Flow steps", 10
    endPause: "Next", 1
    fieldType$ = field_type$
    descriptorCentreNorm = descriptor_centre
    timeRadius = time_radius
    descriptorRadiusNorm = descriptor_radius
    flowStrength = flow_strength
    flowDirection$ = flow_direction$
    viscosity = viscosity
    integrationAmount = integration_amount
    flowSteps = flow_steps

    beginPause: "Custom 3 of 4: Timing"
        optionmenu: "Canvas policy", 1
            option: "Preserve"
            option: "Expand"
            option: "Wrap"
        real: "Event duration response (0-1)", 0.15
        optionmenu: "Vertical response", 1
            option: "None"
            option: "Pitch"
            option: "Gain"
            option: "Duration"
        real: "Vertical response amount (0-1)", 0.00
        optionmenu: "Collision policy", 1
            option: "Layer"
            option: "Repel"
            option: "Queue"
        real: "Minimum event spacing (s)", 0.00
        real: "Event overlap (0-1)", 0.25
        optionmenu: "Boundary behavior", 3
            option: "Clip"
            option: "Wrap"
            option: "Reflect"
            option: "Open"
        boolean: "Preserve original event order", 0
    endPause: "Next", 1
    canvasPolicy$ = canvas_policy$
    durationResponse = event_duration_response
    verticalResponseMode$ = vertical_response$
    verticalResponse = vertical_response_amount
    collisionPolicy$ = collision_policy$
    minEventSpacing = minimum_event_spacing
    eventOverlap = event_overlap
    boundaryBehavior$ = boundary_behavior$
    preserveOrder = preserve_original_event_order

    beginPause: "Custom 4 of 4: Output"
        real: "Event duplication probability (0-1)", 0.00
        integer: "Event duplication count", 0
        real: "Density gain compensation (0-1)", 0.40
        real: "Dry event inclusion (0-1)", 0.00
        real: "Original layer amount (0-2)", 0.00
        integer: "Random seed", 0
        optionmenu: "Quality", 2
            option: "Draft"
            option: "Standard"
            option: "High"
    endPause: "Finish", 1
    dupProbability = event_duplication_probability
    dupCount = event_duplication_count
    densityGainCompensation = density_gain_compensation
    dryEventInclusion = dry_event_inclusion
    originalLayerAmount = original_layer_amount
    randomSeed = random_seed
    quality$ = quality$

endif

# The compact Motion amount control scales how long particles travel through
# the selected field. It leaves segmentation and output level unchanged.
if motionAmount < 0
    motionAmount = 0
elsif motionAmount > 2
    motionAmount = 2
endif
integrationAmount = integrationAmount * motionAmount

# ------------------------- 4. Validate and clamp --------------------------

procedure clampReal: .value, .lo, .hi
    if .value < .lo
        .value = .lo
    elsif .value > .hi
        .value = .hi
    endif
endproc

@clampReal: centreTimeNorm, 0.0, 1.0
centreTimeNorm = clampReal.value
@clampReal: descriptorCentreNorm, 0.0, 1.0
descriptorCentreNorm = clampReal.value
@clampReal: descriptorRadiusNorm, 0.01, 4.0
descriptorRadiusNorm = clampReal.value
@clampReal: flowStrength, 0, 1
flowStrength = clampReal.value
@clampReal: viscosity, 0, 1
viscosity = clampReal.value
@clampReal: durationResponse, 0, 1
durationResponse = clampReal.value
@clampReal: verticalResponse, 0, 1
verticalResponse = clampReal.value
@clampReal: eventOverlap, 0, 1
eventOverlap = clampReal.value
@clampReal: densityGainCompensation, 0, 1
densityGainCompensation = clampReal.value
@clampReal: dryEventInclusion, 0, 1
dryEventInclusion = clampReal.value
@clampReal: originalLayerAmount, 0, 2
originalLayerAmount = clampReal.value
@clampReal: dupProbability, 0, 1
dupProbability = clampReal.value
@clampReal: onsetSensitivity, 0, 1
onsetSensitivity = clampReal.value
@clampReal: preOnset, 0, sourceDuration
preOnset = clampReal.value
@clampReal: postTail, 0, sourceDuration
postTail = clampReal.value

if timeRadius < 0.02
    timeRadius = 0.02
endif
if timeRadius > sourceDuration
    timeRadius = sourceDuration
endif
if minEventDuration < 0.005
    minEventDuration = 0.005
endif
if grainSize < 0.01
    grainSize = 0.01
endif
if minEventSpacing < 0
    minEventSpacing = 0
endif
if dupCount < 0
    dupCount = 0
endif
if integrationAmount < 0
    integrationAmount = 0
endif
if flowSteps < 1
    flowSteps = 1
endif

centreTimeAbs = centreTimeNorm * sourceDuration

fieldTypeLower$ = fieldType$
if fieldType$ = "Vortex"
    fieldTypeLower$ = "vortex"
elsif fieldType$ = "Sink"
    fieldTypeLower$ = "sink"
elsif fieldType$ = "Source"
    fieldTypeLower$ = "source"
elsif fieldType$ = "Shear"
    fieldTypeLower$ = "shear"
endif

directionLower$ = "positive"
if flowDirection$ = "Negative"
    directionLower$ = "negative"
endif

segmentationLower$ = "onset"
if segmentationMode$ = "Fixed grain"
    segmentationLower$ = "fixed"
endif

axisLower$ = "centroid"
if verticalAxis$ = "Dominant frequency"
    axisLower$ = "dominant"
elsif verticalAxis$ = "RMS energy"
    axisLower$ = "rms"
endif

verticalResponseModeLower$ = "none"
if verticalResponseMode$ = "Pitch"
    verticalResponseModeLower$ = "pitch"
elsif verticalResponseMode$ = "Gain"
    verticalResponseModeLower$ = "gain"
elsif verticalResponseMode$ = "Duration"
    verticalResponseModeLower$ = "duration"
endif

canvasPolicyLower$ = "preserve"
if canvasPolicy$ = "Expand"
    canvasPolicyLower$ = "expand"
elsif canvasPolicy$ = "Wrap"
    canvasPolicyLower$ = "wrap"
endif

collisionPolicyLower$ = "layer"
if collisionPolicy$ = "Repel"
    collisionPolicyLower$ = "repel"
elsif collisionPolicy$ = "Queue"
    collisionPolicyLower$ = "queue"
endif

boundaryLower$ = "clip"
if boundaryBehavior$ = "Wrap"
    boundaryLower$ = "wrap"
elsif boundaryBehavior$ = "Reflect"
    boundaryLower$ = "reflect"
elsif boundaryBehavior$ = "Open"
    boundaryLower$ = "open"
endif

qualityLower$ = "standard"
if quality$ = "Draft"
    qualityLower$ = "draft"
elsif quality$ = "High"
    qualityLower$ = "high"
endif

normalizeLower$ = "rms"
if normalizeMode$ = "None"
    normalizeLower$ = "none"
elsif normalizeMode$ = "Peak"
    normalizeLower$ = "peak"
endif

preserveOrderInt = 0
if preserveOrder = 1
    preserveOrderInt = 1
endif

# ---------------------- 5. Locate the Python engine ------------------------

if macintosh
    if fileReadable ("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable ("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable ("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# Engine scripts live in the plugin's py/ subfolder (AudioTools convention).
pluginDir$ = preferencesDirectory$ + "/plugin_AudioTools/"
engineScript$ = pluginDir$ + "py/fluid_event_fields.py"
if not fileReadable (engineScript$)
    exitScript: "Could not find fluid_event_fields.py in the plugin folder: ", pluginDir$ + "py/"
endif

tempDir$ = temporaryDirectory$ + "/"
probeMarker$ = tempDir$ + "temp_fluidevt_probe.ok"
probeLog$ = tempDir$ + "temp_fluidevt_probe.log"
if fileReadable (probeMarker$)
    deleteFile: probeMarker$
endif
if fileReadable (probeLog$)
    deleteFile: probeLog$
endif
probeCmd$ = pythonCmd$ + " -c ""import numpy, scipy, soundfile; open(r'" + probeMarker$ + "','w').write('ok')"" > """ + probeLog$ + """ 2>&1"
runSystem_nocheck: probeCmd$
probeOk = 0
if fileReadable (probeMarker$)
    probeText$ = readFile$ (probeMarker$)
    if probeText$ = "ok"
        probeOk = 1
    endif
    deleteFile: probeMarker$
endif
if probeOk = 0
    probeError$ = "Python dependencies are unavailable (NumPy, SciPy, SoundFile)."
    if fileReadable (probeLog$)
        probeError$ = probeError$ + newline$ + readFile$ (probeLog$)
        deleteFile: probeLog$
    endif
    exitScript: probeError$
endif
if fileReadable (probeLog$)
    deleteFile: probeLog$
endif

# ------------------------- 6. Temporary file paths -------------------------

tempInput$ = tempDir$ + "temp_fluidevt_input.wav"
tempField$ = tempDir$ + "temp_fluidevt_field.csv"
tempOutput$ = tempDir$ + "temp_fluidevt_output.wav"
tempStats$ = tempDir$ + "temp_fluidevt_stats.txt"

if fileReadable (tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable (tempStats$)
    deleteFile: tempStats$
endif

# ----------------------------- 7. Export Sound ------------------------------

selectObject: sound
Save as WAV file: tempInput$

# ------------------------ 8. Write the field-plan CSV -----------------------

writeFile: tempField$, "field_id,field_type,center_time_norm,center_descriptor_norm,time_radius_sec,descriptor_radius_norm,strength,direction,viscosity,enabled" + newline$
appendFile: tempField$, "0,", fieldTypeLower$, ",", fixed$ (centreTimeNorm, 6), ",",
    ... fixed$ (descriptorCentreNorm, 6), ",", fixed$ (timeRadius, 6), ",",
    ... fixed$ (descriptorRadiusNorm, 6), ",", fixed$ (flowStrength, 4), ",",
    ... directionLower$, ",", fixed$ (viscosity, 4), ",1", newline$

# --------------------------- 9. Run Python engine ---------------------------

writeInfoLine: "Fluid Event Fields -- processing..."
appendInfoLine: "Event segmentation + forward field integration + grain rendering"
appendInfoLine: ""

command$ = pythonCmd$ + " """ + engineScript$ + """ """ + tempInput$ + """ """ +
    ... tempField$ + """ """ + tempOutput$ + """ """ + tempStats$ + """" +
    ... " --segmentation " + segmentationLower$ +
    ... " --grain-size " + fixed$ (grainSize, 4) +
    ... " --onset-sensitivity " + fixed$ (onsetSensitivity, 4) +
    ... " --min-event-duration " + fixed$ (minEventDuration, 4) +
    ... " --sparse-onset-fallback " + fixed$ (sparseOnsetFallback, 0) +
    ... " --pre-onset " + fixed$ (preOnset, 4) +
    ... " --post-tail " + fixed$ (postTail, 4) +
    ... " --vertical-axis " + axisLower$ +
    ... " --integration-amount " + fixed$ (integrationAmount, 4) +
    ... " --flow-steps " + fixed$ (flowSteps, 0) +
    ... " --canvas-policy " + canvasPolicyLower$ +
    ... " --duration-response " + fixed$ (durationResponse, 4) +
    ... " --vertical-response-mode " + verticalResponseModeLower$ +
    ... " --vertical-response " + fixed$ (verticalResponse, 4) +
    ... " --collision-policy " + collisionPolicyLower$ +
    ... " --min-spacing " + fixed$ (minEventSpacing, 4) +
    ... " --event-overlap " + fixed$ (eventOverlap, 4) +
    ... " --boundary " + boundaryLower$ +
    ... " --preserve-order " + fixed$ (preserveOrderInt, 0) +
    ... " --duplication-probability " + fixed$ (dupProbability, 4) +
    ... " --duplication-count " + fixed$ (dupCount, 0) +
    ... " --density-gain-compensation " + fixed$ (densityGainCompensation, 4) +
    ... " --dry-event-inclusion " + fixed$ (dryEventInclusion, 4) +
    ... " --original-layer-amount " + fixed$ (originalLayerAmount, 4) +
    ... " --seed " + fixed$ (randomSeed, 0) +
    ... " --quality " + qualityLower$ +
    ... " --normalize " + normalizeLower$ +
    ... " --cleanup" +
    ... " > """ + tempDir$ + "temp_fluidevt_run.log"" 2>&1"

runSystem_nocheck: command$

if fileReadable (tempDir$ + "temp_fluidevt_run.log")
    runLog$ = readFile$ (tempDir$ + "temp_fluidevt_run.log")
    appendInfoLine: runLog$
    deleteFile: tempDir$ + "temp_fluidevt_run.log"
endif

# --------------------------- 10. Verify the result ---------------------------

if not fileReadable (tempOutput$)
    exitScript: "Python did not produce an output file. See the Info window for details."
endif
if not fileReadable (tempStats$)
    exitScript: "Python did not produce a statistics file. See the Info window for details."
endif

# ------------------------- 11. Parse the statistics --------------------------

Read Strings from raw text file: tempStats$
statsStrings = selected ("Strings")
nLines = Get number of strings

statusOk = 0
warningText$ = ""
errorMessage$ = ""
nVectors = 0
nArrows = 0
nInstancesPlotted = 0
fieldGridNx = 12
fieldGridNy = 9
statDescCentre = 0
statDescRadius = 1
statAxisUnit$ = "hz_log2"
statVerticalResponseMode$ = "none"
statMeanFieldTimeDisp$ = "0"
statMaxFieldTimeDisp$ = "0"
statMeanFinalTimeDisp$ = "0"
statMaxFinalTimeDisp$ = "0"
statMeanDescriptorGain$ = "0"
statMaxDescriptorGain$ = "0"
statMinTimeScale$ = "1"
statMaxTimeScale$ = "1"
statEffectiveSeed$ = "0"
statIdentityShortcut = 0
statMovedFraction$ = "0"
statMovementThreshold$ = "0"

procedure setStatField: .key$, .val$
    if .key$ = "status"
        if .val$ = "ok"
            statusOk = 1
        endif
    elsif .key$ = "engine_version"
        statEngineVersion$ = .val$
    elsif .key$ = "segmentation_mode"
        statSegmentation$ = .val$
    elsif .key$ = "n_events_detected"
        statNEventsDetected = number (.val$)
    elsif .key$ = "n_events_rendered"
        statNEventsRendered = number (.val$)
    elsif .key$ = "n_duplicates"
        statNDuplicates = number (.val$)
    elsif .key$ = "n_dry_events_included"
        statNDryEvents = number (.val$)
    elsif .key$ = "field_type"
        statFieldType$ = .val$
    elsif .key$ = "direction"
        statDirection$ = .val$
    elsif .key$ = "vertical_axis"
        statVerticalAxis$ = .val$
    elsif .key$ = "vertical_axis_unit"
        statAxisUnit$ = .val$
    elsif .key$ = "vertical_response_mode"
        statVerticalResponseMode$ = .val$
    elsif .key$ = "descriptor_min"
        statDescMin = number (.val$)
    elsif .key$ = "descriptor_max"
        statDescMax = number (.val$)
    elsif .key$ = "descriptor_centre"
        statDescCentre = number (.val$)
    elsif .key$ = "descriptor_radius"
        statDescRadius = number (.val$)
    elsif .key$ = "canvas_policy"
        statCanvasPolicy$ = .val$
    elsif .key$ = "collision_policy"
        statCollisionPolicy$ = .val$
    elsif .key$ = "boundary"
        statBoundary$ = .val$
    elsif .key$ = "quality"
        statQuality$ = .val$
    elsif .key$ = "normalize_mode"
        statNormalize$ = .val$
    elsif .key$ = "sample_rate"
        statSampleRate = number (.val$)
    elsif .key$ = "n_channels_output"
        statChannelsOut = number (.val$)
    elsif .key$ = "output_duration"
        statOutputDuration = number (.val$)
    elsif .key$ = "input_duration"
        statInputDuration = number (.val$)
    elsif .key$ = "input_rms"
        statInputRMS$ = .val$
    elsif .key$ = "output_rms"
        statOutputRMS$ = .val$
    elsif .key$ = "input_peak"
        statInputPeak$ = .val$
    elsif .key$ = "output_peak"
        statOutputPeak$ = .val$
    elsif .key$ = "mean_time_displacement_sec"
        statMeanTimeDisp$ = .val$
    elsif .key$ = "max_time_displacement_sec"
        statMaxTimeDisp$ = .val$
    elsif .key$ = "mean_field_time_displacement_sec"
        statMeanFieldTimeDisp$ = .val$
    elsif .key$ = "max_field_time_displacement_sec"
        statMaxFieldTimeDisp$ = .val$
    elsif .key$ = "mean_final_time_displacement_sec"
        statMeanFinalTimeDisp$ = .val$
    elsif .key$ = "max_final_time_displacement_sec"
        statMaxFinalTimeDisp$ = .val$
    elsif .key$ = "mean_pitch_shift_semitones"
        statMeanPitch$ = .val$
    elsif .key$ = "max_pitch_shift_semitones"
        statMaxPitch$ = .val$
    elsif .key$ = "mean_descriptor_gain_db"
        statMeanDescriptorGain$ = .val$
    elsif .key$ = "max_descriptor_gain_db"
        statMaxDescriptorGain$ = .val$
    elsif .key$ = "min_time_scale"
        statMinTimeScale$ = .val$
    elsif .key$ = "max_time_scale"
        statMaxTimeScale$ = .val$
    elsif .key$ = "effective_seed"
        statEffectiveSeed$ = .val$
    elsif .key$ = "identity_shortcut"
        statIdentityShortcut = number (.val$)
    elsif .key$ = "moved_event_fraction"
        statMovedFraction$ = .val$
    elsif .key$ = "movement_threshold_sec"
        statMovementThreshold$ = .val$
    elsif .key$ = "warning"
        warningText$ = .val$
    elsif .key$ = "error_message"
        errorMessage$ = .val$
    elsif .key$ = "n_event_vectors"
        nVectors = number (.val$)
    elsif .key$ = "n_field_arrows"
        nArrows = number (.val$)
    elsif .key$ = "field_grid_nx"
        fieldGridNx = number (.val$)
    elsif .key$ = "field_grid_ny"
        fieldGridNy = number (.val$)
    elsif .key$ = "n_instances_plotted"
        nInstancesPlotted = number (.val$)
    elsif startsWith (.key$, "vec_")
        idx$ = replace$ (.key$, "vec_", "", 1)
        idx = number (idx$)
        vecLine$[idx+1] = .val$
    elsif startsWith (.key$, "arrowgrid_")
        idx$ = replace$ (.key$, "arrowgrid_", "", 1)
        idx = number (idx$)
        arrowLine$[idx+1] = .val$
    elsif startsWith (.key$, "inst_")
        idx$ = replace$ (.key$, "inst_", "", 1)
        idx = number (idx$)
        instLine$[idx+1] = .val$
    endif
endproc

for i to nLines
    selectObject: statsStrings
    line$ = Get string: i
    eqPos = index (line$, "=")
    if eqPos > 0
        key$ = left$ (line$, eqPos - 1)
        val$ = right$ (line$, length (line$) - eqPos)
        @setStatField: key$, val$
    endif
endfor

removeObject: statsStrings

if statusOk = 0
    msg$ = "Python engine reported failure."
    if errorMessage$ <> ""
        msg$ = msg$ + " " + errorMessage$
    endif
    exitScript: msg$
endif

if statDescRadius <= 0
    statDescRadius = 1
endif

# ---------------------- 12. Import and check the result --------------------
# Expand may create a longer canvas. Preserve and Wrap must remain exactly
# source-length; a mismatch there indicates an engine-contract failure.

Read from file: tempOutput$
result = selected ("Sound")
resultSampleRate = Get sampling frequency
resultChannels = Get number of channels
resultDuration = Get total duration

ok = 1
if resultSampleRate <> sourceSampleRate
    ok = 0
endif
if resultChannels <> sourceChannels
    ok = 0
endif
if canvasPolicyLower$ = "preserve" or canvasPolicyLower$ = "wrap"
    if abs (resultDuration - sourceDuration) > 1.1 / sourceSampleRate
        ok = 0
    endif
endif

if ok = 0
    removeObject: result
    exitScript: "The processed Sound violated the output contract (sample rate, "
        ... + "channel count, or closed-canvas duration). The run has been rejected."
endif

Rename: sourceName$ + "_fluidevt"

appendInfoLine: ""
appendInfoLine: "Events detected: ", statNEventsDetected, "   Rendered instances: ", statNEventsRendered,
    ... " (duplicates: ", statNDuplicates, ", dry copies: ", statNDryEvents, ")"
appendInfoLine: "Duration: ", fixed$ (sourceDuration, 3), " s -> ", fixed$ (resultDuration, 3), " s"
appendInfoLine: "Seed used: ", statEffectiveSeed$, "   Identity bypass: ", fixed$ (statIdentityShortcut, 0)
appendInfoLine: "Final event motion: mean ", statMeanFinalTimeDisp$, " s, max ", statMaxFinalTimeDisp$,
    ... " s; moved fraction ", fixed$ (100 * number (statMovedFraction$), 1), "%"
if warningText$ <> ""
    appendInfoLine: "Warning: ", warningText$
endif

# ------------------------------ 13. Visualization ----------------------------

if drawViz = 1
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    Select outer viewport: 0, 8, 0, 8

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.33
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "##Fluid Event Fields##"

    # === Subtitle ===
    subtitle$ = sourceName$ + " | " + preset$ + " | field=" + fieldTypeLower$ + "/" + directionLower$ +
        ... " | " + segmentationLower$ + "/" + axisLower$ +
        ... " | events=" + fixed$ (statNEventsDetected, 0) + "->" + fixed$ (statNEventsRendered, 0) +
        ... " | " + fixed$ (sourceDuration, 2) + "s->" + fixed$ (resultDuration, 2) + "s"
    Select outer viewport: 0, 8, 0.33, 0.5
    Axes: 0, 1, 0, 1
    Font size: 9
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", 0.5, "half", subtitle$

    # === Input Waveform ===
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.65, 1.45
    selectObject: sound
    Colour: "{0.5, 0.5, 0.5}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Axes: 0, sourceDuration, -1, 1
    Colour: "Black"
    Text top: "no", fixed$ (sourceDuration, 2) + " s | " + fixed$ (statNEventsDetected, 0) + " events segmented"

    # === Output Waveform ===
    Select outer viewport: 0, 8, 1.5, 2.4
    Select inner viewport: 0.6, 7.7, 1.55, 2.35
    selectObject: result
    Colour: "{0.25, 0.55, 0.35}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Fluid"
    Text bottom: "yes", "Time (s)"

    # === Event Field Map (normalized u/v space, background field + before/after vectors) ===
    Select outer viewport: 0, 8, 2.5, 4.3
    Select inner viewport: 0.6, 7.7, 2.6, 4.2

    Axes: -2.7, 2.7, -2.7, 2.7
    Paint rectangle: "{0.97, 0.97, 0.99}", -2.7, 2.7, -2.7, 2.7

    Colour: "{0.75, 0.75, 0.85}"
    Line width: 1
    for a to nArrows
        line$ = arrowLine$[a]
        p1 = index (line$, ",")
        v1$ = left$ (line$, p1 - 1)
        rest$ = right$ (line$, length (line$) - p1)
        p2 = index (rest$, ",")
        v2$ = left$ (rest$, p2 - 1)
        rest2$ = right$ (rest$, length (rest$) - p2)
        p3 = index (rest2$, ",")
        v3$ = left$ (rest2$, p3 - 1)
        v4$ = right$ (rest2$, length (rest2$) - p3)
        au = number (v1$)
        av = number (v2$)
        adu = number (v3$)
        adv = number (v4$)
        Draw arrow: au, av, au + adu * 3, av + adv * 3
    endfor

    Colour: "{0.2, 0.6, 0.3}"
    Paint circle (mm): "{0.2, 0.6, 0.3}", 0, 0, 1.6

    if directionLower$ = "negative"
        eventColour$ = "{0.8, 0.3, 0.2}"
    else
        eventColour$ = "{0.25, 0.4, 0.85}"
    endif
    Colour: 'eventColour$'
    Line width: 1
    for v to nVectors
        line$ = vecLine$[v]
        p1 = index (line$, ",")
        v1$ = left$ (line$, p1 - 1)
        rest$ = right$ (line$, length (line$) - p1)
        p2 = index (rest$, ",")
        v2$ = left$ (rest$, p2 - 1)
        rest2$ = right$ (rest$, length (rest$) - p2)
        p3 = index (rest2$, ",")
        v3$ = left$ (rest2$, p3 - 1)
        rest3$ = right$ (rest2$, length (rest2$) - p3)
        p4 = index (rest3$, ",")
        v4$ = left$ (rest3$, p4 - 1)
        v5$ = right$ (rest3$, length (rest3$) - p4)
        et0 = number (v1$)
        edesc0 = number (v2$)
        etField = number (v3$)
        etFinal = number (v4$)
        edesc1 = number (v5$)
        eu0 = (et0 - centreTimeAbs) / timeRadius
        eu1 = (etField - centreTimeAbs) / timeRadius
        if statAxisUnit$ = "hz_log2"
            ev0 = (log2 (max (edesc0, 1)) - statDescCentre) / statDescRadius
            ev1 = (log2 (max (edesc1, 1)) - statDescCentre) / statDescRadius
        else
            ev0 = (edesc0 - statDescCentre) / statDescRadius
            ev1 = (edesc1 - statDescCentre) / statDescRadius
        endif
        Draw arrow: eu0, ev0, eu1, ev1
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "normalized descriptor (v)"
    Text bottom: "yes", "normalized time (u)"
    Text top: "no", "Field map (" + fieldTypeLower$ + ", direction=" + directionLower$ +
        ... ") -- foreground shows analytic field motion before collision handling"

    # === Time Displacement (before -> after, absolute seconds) ===
    Select outer viewport: 0, 8, 4.4, 5.7
    Select inner viewport: 0.6, 7.7, 4.5, 5.6

    Axes: 0, sourceDuration, 0, resultDuration
    Paint rectangle: "{0.97, 0.97, 0.99}", 0, sourceDuration, 0, resultDuration
    Colour: "{0.6, 0.6, 0.6}"
    Draw line: 0, 0, sourceDuration, sourceDuration
    Colour: 'eventColour$'
    for v to nVectors
        line$ = vecLine$[v]
        p1 = index (line$, ",")
        v1$ = left$ (line$, p1 - 1)
        rest$ = right$ (line$, length (line$) - p1)
        p2 = index (rest$, ",")
        rest2$ = right$ (rest$, length (rest$) - p2)
        p3 = index (rest2$, ",")
        rest3$ = right$ (rest2$, length (rest2$) - p3)
        p4 = index (rest3$, ",")
        v4$ = left$ (rest3$, p4 - 1)
        et0 = number (v1$)
        etFinal = number (v4$)
        Paint circle (mm): 'eventColour$', et0, etFinal, 0.7
    endfor
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "New time (s)"
    Text bottom: "yes", "Original time (s)"
    Text top: "no", "Final rendered placement after collision, duplication policy and canvas handling"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 5.9, 7.0
    Select inner viewport: 0.6, 7.7, 6.0, 6.9

    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.92, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.78, "half", "Field: " + fieldTypeLower$ + " (" + statDirection$ + ")   Strength: " + fixed$ (flowStrength, 2) +
        ... "   Integration: " + fixed$ (integrationAmount, 2) + " x " + fixed$ (flowSteps, 0) + " steps"
    Text: 0.02, "left", 0.62, "half", "Segmentation: " + segmentationLower$ + "   Axis: " + axisLower$ +
        ... "   Response: " + statVerticalResponseMode$ + " (" + fixed$ (verticalResponse, 2) + ")" +
        ... "   Events: " + fixed$ (statNEventsDetected, 0) + " -> " + fixed$ (statNEventsRendered, 0) +
        ... " (dup " + fixed$ (statNDuplicates, 0) + ", dry " + fixed$ (statNDryEvents, 0) + ")"
    Text: 0.02, "left", 0.46, "half", "Canvas policy: " + canvasPolicyLower$ + "   Collision: " + collisionPolicyLower$ +
        ... "   Boundary: " + boundaryLower$ + "   Order preserved: " + fixed$ (preserveOrderInt, 0)
    Text: 0.02, "left", 0.30, "half", "Field time mean/max: " + statMeanFieldTimeDisp$ + "/" + statMaxFieldTimeDisp$ + " s" +
        ... "   Final time mean/max: " + statMeanFinalTimeDisp$ + "/" + statMaxFinalTimeDisp$ + " s"
    Text: 0.02, "left", 0.14, "half", "Time scale min/max: " + statMinTimeScale$ + "/" + statMaxTimeScale$ +
        ... "   Pitch mean/max: " + statMeanPitch$ + "/" + statMaxPitch$ + " st" +
        ... "   Vertical gain: " + statMeanDescriptorGain$ + "/" + statMaxDescriptorGain$ + " dB   Seed: " + statEffectiveSeed$

    if warningText$ <> ""
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", -0.02, "half", "Warning: " + warningText$
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endif

# ------------------------------- 14. Cleanup ---------------------------------

if fileReadable (tempInput$)
    deleteFile: tempInput$
endif
if fileReadable (tempField$)
    deleteFile: tempField$
endif
; Python cleanup removes only Praat-created input/plan files. The output and
; statistics remain available until Praat has imported and parsed them.
if fileReadable (tempOutput$)
    deleteFile: tempOutput$
endif
if fileReadable (tempStats$)
    deleteFile: tempStats$
endif

# --------------------------- 15. Select and play ------------------------------

selectObject: result
if playResult = 1
    Play
endif

appendInfoLine: ""
appendInfoLine: "Done. Result: ", sourceName$, "_fluidevt"
