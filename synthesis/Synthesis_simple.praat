form Synthesis Parameters
    choice Waveform_type: 1
        button Sine wave
        button Triangle wave
        button Square wave
        button Sawtooth wave
        button Pulse train
    positive Frequency_(Hz) 440
    positive Duration_(s) 1.0
    positive Amplitude 0.5
    boolean Apply_envelope 1
    positive Attack_(s) 0.01
    positive Release_(s) 0.2
endform

sampling_frequency = 44100

if waveform_type = 1
    sound = Create Sound from formula: "Sine", 1, 0, duration, sampling_frequency,
    ... "amplitude * sin(2*pi*frequency*x)"
elsif waveform_type = 2
    sound = Create Sound from formula: "Triangle", 1, 0, duration, sampling_frequency,
    ... "amplitude * (2/pi) * arcsin(sin(2*pi*frequency*x))"
elsif waveform_type = 3
    sound = Create Sound from formula: "Square", 1, 0, duration, sampling_frequency,
    ... "amplitude * if sin(2*pi*frequency*x) > 0 then 1 else -1 fi"
elsif waveform_type = 4
    sound = Create Sound from formula: "Sawtooth", 1, 0, duration, sampling_frequency,
    ... "amplitude * (2*(frequency*x - floor(frequency*x + 0.5)))"
elsif waveform_type = 5
    sound = Create Sound from formula: "Pulse", 1, 0, duration, sampling_frequency,
    ... "amplitude * if (frequency*x - floor(frequency*x)) < 0.5 then 1 else -1 fi"
endif

if apply_envelope
    selectObject: sound
    total_duration = Get total duration
    intensity_tier = Create IntensityTier: "envelope", 0, total_duration
    Add point: 0, 0
    Add point: attack, 1
    release_start = total_duration - release
    Add point: release_start, 1
    Add point: total_duration, 0
    selectObject: sound
    plusObject: intensity_tier
    Multiply: "yes"
    envelope_sound = selected("Sound")
    selectObject: sound
    Remove
    selectObject: intensity_tier
    Remove
    selectObject: envelope_sound
    Rename: "EnvelopedSound"
    sound = selected("Sound")
endif

selectObject: sound
Scale peak: 0.99
Play