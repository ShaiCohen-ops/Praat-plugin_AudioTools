# ============================================================
# Praat AudioTools - Multi-Band Attenuator.praat
# ============================================================

form Multi-Band Attenuator
    optionmenu Preset: 1
        option Custom
        option Vocal Notch (remove 2-4kHz presence)
        option De-Esser (reduce 5-8kHz)
        option Hollow Middle (scoop mids)
        option Telephone (bandpass effect)
    comment === Band 1 ===
    positive band1_low 2000
    positive band1_high 2200
    positive band1_gain 0.1
    comment === Band 2 ===
    positive band2_low 5500
    positive band2_high 5800
    positive band2_gain 0.2
    comment === Outside Bands ===
    positive outside_gain 1.0
    comment === Output ===
    positive scale_peak 0.90
    boolean play_after_processing 1
endform

# Presets
if preset = 2
    band1_low = 2000
    band1_high = 4000
    band1_gain = 0.3
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
elsif preset = 3
    band1_low = 5000
    band1_high = 8000
    band1_gain = 0.4
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
elsif preset = 4
    band1_low = 400
    band1_high = 2000
    band1_gain = 0.2
    band2_low = 0
    band2_high = 0
    band2_gain = 1.0
elsif preset = 5
    band1_low = 0
    band1_high = 300
    band1_gain = 0.1
    band2_low = 3400
    band2_high = 20000
    band2_gain = 0.1
    outside_gain = 1.0
endif

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly ONE Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")
selectObject: originalID
duration = Get total duration
n_channels = Get number of channels

writeInfoLine: "=== Multi-Band Attenuator ==="
appendInfoLine: "Band 1: ", band1_low, "-", band1_high, " Hz (gain: ", band1_gain, ")"
appendInfoLine: "Band 2: ", band2_low, "-", band2_high, " Hz (gain: ", band2_gain, ")"
appendInfoLine: ""

# Convert to mono
selectObject: originalID
if n_channels > 1
    workingID = Convert to mono
else
    workingID = Copy: "working"
endif

# To spectrum
selectObject: workingID
spectrum = To Spectrum: "yes"

# Build formula using x (frequency in Hz - correct!)
b1l$ = fixed$(band1_low, 0)
b1h$ = fixed$(band1_high, 0)
b1g$ = fixed$(band1_gain, 4)
b2l$ = fixed$(band2_low, 0)
b2h$ = fixed$(band2_high, 0)
b2g$ = fixed$(band2_gain, 4)
outG$ = fixed$(outside_gain, 4)

# Apply multi-band attenuation
selectObject: spectrum
Formula: "if x >= " + b1l$ + " and x <= " + b1h$ + " then self * " + b1g$ + " else if x >= " + b2l$ + " and x <= " + b2h$ + " then self * " + b2g$ + " else self * " + outG$ + " fi fi"

# Back to sound
selectObject: spectrum
resultID = To Sound

# Trim
selectObject: resultID
resultDur = Get total duration
if resultDur > duration
    trimmed = Extract part: 0, duration, "rectangular", 1, "no"
    removeObject: resultID
    resultID = trimmed
endif

selectObject: resultID
Rename: originalName$ + "_attenuated"
Scale peak: scale_peak

removeObject: workingID, spectrum

appendInfoLine: "Complete!"

selectObject: resultID
if play_after_processing
    Play
endif