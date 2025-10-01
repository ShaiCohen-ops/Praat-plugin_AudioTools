# Convolution Synthesis with Multiple Sound Types
form Convolution Synthesis
    comment Choose sound type and parameters:
    optionmenu Sound_type: 1
        option Metallic/Bell
        option Drum
        option Water Drop
        option Robot Voice
        option Custom
    
    comment Common parameters:
    positive Duration 0.5
    positive Sampling_frequency 44100
    word Output_name convolution_result
    boolean Play_sound 1
    boolean Save_to_file 0
    
    comment Type-specific parameters:
    positive Frequency_1 800
    positive Frequency_2 1200
    positive Decay_rate 20
    positive Modulation 2
endform

# Initialize variables based on sound type
if sound_type = 1
    # Metallic/Bell
    source_formula$ = "randomGauss(0,0.3)"
    filter_formula$ = "sin(2*pi*'frequency_1'*x) * exp(-'decay_rate'*x) + 0.7*sin(2*pi*'frequency_2'*x) * exp(-'decay_rate'*1.5*x)"
elsif sound_type = 2
    # Drum
    source_formula$ = "if x < 0.001 then 1 else 0 fi"
    filter_formula$ = "sin(2*pi*'frequency_1'*x) * exp(-'decay_rate'*x) + 0.3*sin(2*pi*'frequency_2'*x) * exp(-'decay_rate'*1.2*x)"
elsif sound_type = 3
    # Water Drop
    source_formula$ = "if x < 0.01 then 1 else 0 fi"
    filter_formula$ = "sin(2*pi*'frequency_1'*x) * exp(-'decay_rate'*x) * sin(2*pi*'modulation'*x)"
elsif sound_type = 4
    # Robot Voice
    source_formula$ = "0.5*sin(2*pi*'frequency_1'*x) + 0.3*sin(2*pi*'frequency_2'*x)"
    filter_formula$ = "sin(2*pi*'frequency_1'*0.3*x) * exp(-'decay_rate'*x) + 0.5*sin(2*pi*'frequency_2'*2*x) * exp(-'decay_rate'*1.5*x)"
else
    # Custom - user can edit the formulas below
    source_formula$ = "sin(2*pi*'frequency_1'*x)"
    filter_formula$ = "sin(2*pi*'frequency_2'*x) * exp(-'decay_rate'*x)"
endif

# Create source sound
Create Sound from formula: "source", 1, 0, duration, sampling_frequency, source_formula$
source = selected("Sound")

# Create filter sound  
Create Sound from formula: "filter", 1, 0, duration/2, sampling_frequency, filter_formula$
filter = selected("Sound")

# Convolve them
selectObject: source, filter
Convolve: "sum", "zero"
result = selected("Sound")
Rename: output_name$
Scale peak: 0.99

# Play sound if requested
if play_sound
    Play
endif

# Save to file if requested
if save_to_file
    selectObject: result
    Save as WAV file: output_name$ + ".wav"
endif

# Clean up temporary objects
removeObject: source, filter

# Display information
writeInfoLine: "Convolution synthesis complete!"
appendInfoLine: "Sound type: ", sound_type$
appendInfoLine: "Duration: ", duration, " seconds"
appendInfoLine: "Output: ", output_name$
appendInfoLine: ""
appendInfoLine: "Source formula:"
appendInfoLine: source_formula$
appendInfoLine: ""
appendInfoLine: "Filter formula:"
appendInfoLine: filter_formula$