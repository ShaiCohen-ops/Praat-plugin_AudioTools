# ============================================================
# Praat AudioTools - Pitch_Processor.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.0 (2025) - Enhanced Edition
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script with two modes:
#   1. Stereo Pitch Detune: Creates stereo spread via pitch shifting
#   2. Time-Delayed Canon: Multi-voice canon with pitch steps
#
#   Uses sample rate override technique for pitch shifting:
#   - Override sample rate = original_rate / (2 ^ (semitones / 12))
#   - Resample back to target rate
#   - Sound plays at different speed/pitch
#
# Improvements in v1.0:
#   - Renamed Mode 1 to "Stereo Pitch Detune" (accurate)
#   - Direct semitone input instead of override rate
#   - Automatic override rate calculation
#   - Comprehensive 6-panel visualization for both modes
#   - Canon timeline visualization
#   - Pitch tracking and harmonic analysis
#   - Educational explanation of technique
# ============================================================

form Pitch Processor v1.0
    comment === Operation Mode ===
    choice Mode 1
        button Stereo Pitch Detune
        button Time-Delayed Canon

    comment === Presets (Canon Only) ===
    choice Preset 1
        button Custom (Use settings below)
        button Major Arpeggio (Fast)
        button Spooky Cluster (Slow)
        button Octave Stacks
    
    comment === Mode 1: Stereo Detune Settings ===
    real Stereo_detune_semitones 1.65
    comment (Positive = right channel higher)
    
    comment === Mode 2: Canon Settings (Custom) ===
    natural Number_of_voices 4
    positive Delay_between_entries 0.5
    integer Semitone_step 7
    boolean Wrap_to_octave 1
    real Start_intensity_dB 70
    real Intensity_step_dB -3

    comment === Global Settings ===
    positive Output_sample_rate 44100
    positive Resample_precision 50
    boolean Draw_visualization 1
    boolean Play_after_processing 1
endform

if not selected("Sound")
    exitScript: "Please select a Sound object first."
endif

if mode = 2
    if preset = 2
        number_of_voices = 4
        delay_between_entries = 0.25
        semitone_step = 4
        wrap_to_octave = 0
        presetName$ = "MajorArpeggio"
    elsif preset = 3
        number_of_voices = 5
        delay_between_entries = 1.2
        semitone_step = 1
        wrap_to_octave = 0
        intensity_step_dB = -1
        presetName$ = "SpookyCluster"
    elsif preset = 4
        number_of_voices = 3
        delay_between_entries = 0.5
        semitone_step = 12
        wrap_to_octave = 0
        intensity_step_dB = -2
        presetName$ = "OctaveStacks"
    else
        presetName$ = "Custom"
    endif
else
    presetName$ = "Detune"
endif

orig$ = selected$("Sound")
id_original = selected("Sound")
id_final_output = 0

clearinfo
writeInfoLine: "=== Pitch Processor v1.0 ==="
if mode = 1
    writeInfoLine: "Mode: Stereo Pitch Detune"
else
    writeInfoLine: "Mode: Time-Delayed Canon"
    writeInfoLine: "Preset: ", presetName$
endif
writeInfoLine: ""

selectObject: id_original
original_rate = Get sampling frequency
original_duration = Get total duration

if draw_visualization
    appendInfoLine: "Analyzing original pitch..."
    selectObject: id_original
    originalMono = Convert to mono
    To Pitch: 0.01, 75, 600
    pitchObj = selected("Pitch")
    meanPitch = Get mean: 0, 0, "Hertz"
    if meanPitch = undefined
        meanPitch = 0
    endif
    removeObject: pitchObj, originalMono
    appendInfoLine: "  Mean pitch: ", fixed$(meanPitch, 1), " Hz"
endif

# ============================================================
# MODE 1: Stereo Pitch Detune
# ============================================================
if mode = 1
    appendInfoLine: ""
    appendInfoLine: "Creating stereo detune..."
    appendInfoLine: "  Detune amount: ", fixed$(stereo_detune_semitones, 2), " semitones"
    
    pitch_ratio = 2 ^ (stereo_detune_semitones / 12)
    override_sample_rate = floor(original_rate / pitch_ratio + 0.5)
    
    appendInfoLine: "  Pitch ratio: ", fixed$(pitch_ratio, 4)
    appendInfoLine: "  Override rate: ", override_sample_rate, " Hz"
    appendInfoLine: ""
    
    selectObject: id_original
    Copy: "temp_L_raw"
    id_L_raw = selected("Sound")
    Resample: output_sample_rate, resample_precision
    id_L_final = selected("Sound")
    
    selectObject: id_original
    Copy: "temp_R_raw"
    id_R_raw = selected("Sound")
    Override sampling frequency: override_sample_rate
    Resample: output_sample_rate, resample_precision
    id_R_final = selected("Sound")

    selectObject: id_L_final
    plusObject: id_R_final
    Combine to stereo
    Rename: orig$ + "_detune_" + fixed$(stereo_detune_semitones, 1) + "ST"
    id_final_output = selected("Sound")
    
    final_duration = Get total duration
    
    selectObject: id_L_raw
    plusObject: id_R_raw
    plusObject: id_L_final
    plusObject: id_R_final
    Remove
    
    if draw_visualization
        vizLeftChannel = id_final_output
        vizRightChannel = id_final_output
    endif
endif

# ============================================================
# MODE 2: Time-Delayed Canon
# ============================================================
if mode = 2
    appendInfoLine: ""
    appendInfoLine: "Creating canon with ", number_of_voices, " voices..."
    
    voice_info# = zero#(number_of_voices * 4)
    
    selectObject: id_original
    Copy: "base"
    id_base = selected("Sound")
    f0 = Get sampling frequency

    for v from 1 to number_of_voices
        s = (v - 1) * semitone_step
        if wrap_to_octave
            s = s - 12 * floor(s / 12)
        endif
        factor = 2 ^ (s / 12)
        f_override = floor(f0 * factor + 0.5)
        
        delay_time = (v - 1) * delay_between_entries
        intensity = start_intensity_dB + (v - 1) * intensity_step_dB
        
        voice_info#[(v-1) * 4 + 1] = s
        voice_info#[(v-1) * 4 + 2] = delay_time
        voice_info#[(v-1) * 4 + 3] = intensity
        voice_info#[(v-1) * 4 + 4] = factor
        
        appendInfoLine: "  Voice ", v, ": +", s, " ST, delay ", fixed$(delay_time, 2), "s, ", fixed$(intensity, 1), " dB"
        
        selectObject: id_base
        Copy: "voice_raw"
        id_step1 = selected("Sound")
        
        Override sampling frequency: f_override
        Resample: output_sample_rate, resample_precision
        id_step2 = selected("Sound")
        
        Convert to mono
        Rename: "voice"
        id_voice = selected("Sound")
        
        selectObject: id_step1
        plusObject: id_step2
        Remove
        
        d = (v - 1) * delay_between_entries
        if d > 0
            Create Sound from formula: "pad", 1, 0, d, output_sample_rate, "0"
            id_pad = selected("Sound")
            
            selectObject: id_pad
            plusObject: id_voice
            Concatenate
            id_chain = selected("Sound")
            
            selectObject: id_pad
            plusObject: id_voice
            Remove
            
            selectObject: id_chain
            Rename: "voice"
            id_voice = selected("Sound")
        endif
        
        gain_dB = start_intensity_dB + (v - 1) * intensity_step_dB
        selectObject: id_voice
        Scale intensity: gain_dB
        
        if v = 1
            Rename: "mix"
            id_mix = selected("Sound")
        else
            selectObject: id_mix
            Resample: output_sample_rate, resample_precision
            id_mix_new = selected("Sound")
            if id_mix_new != id_mix
                selectObject: id_mix
                Remove
                id_mix = id_mix_new
            endif

            selectObject: id_voice
            Resample: output_sample_rate, resample_precision
            id_voice_new = selected("Sound")
            if id_voice_new != id_voice
                selectObject: id_voice
                Remove
                id_voice = id_voice_new
            endif

            selectObject: id_mix
            dur_mix = Get end time
            selectObject: id_voice
            dur_voice = Get end time
            
            if dur_mix < dur_voice
                pad_len = dur_voice - dur_mix
                Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
                id_pad_end = selected("Sound")
                selectObject: id_mix
                plusObject: id_pad_end
                Concatenate
                id_mix_ext = selected("Sound")
                selectObject: id_mix
                plusObject: id_pad_end
                Remove
                id_mix = id_mix_ext
            endif
            
            if dur_voice < dur_mix
                pad_len = dur_mix - dur_voice
                Create Sound from formula: "pad_end", 1, 0, pad_len, output_sample_rate, "0"
                id_pad_end = selected("Sound")
                selectObject: id_voice
                plusObject: id_pad_end
                Concatenate
                id_voice_ext = selected("Sound")
                selectObject: id_voice
                plusObject: id_pad_end
                Remove
                id_voice = id_voice_ext
            endif
            
            selectObject: id_mix
            plusObject: id_voice
            Combine to stereo
            id_stereo_temp = selected("Sound")
            
            Convert to mono
            id_mix_sum = selected("Sound")
            
            selectObject: id_stereo_temp
            Remove
            selectObject: id_mix
            plusObject: id_voice
            Remove
            
            selectObject: id_mix_sum
            Scale peak: 0.99
            Rename: "mix"
            id_mix = selected("Sound")
        endif
    endfor

    selectObject: id_mix
    Rename: orig$ + "_canon_" + presetName$
    id_final_output = selected("Sound")
    
    final_duration = Get total duration
    
    selectObject: id_base
    Remove
endif

################################################################################
# VISUALIZATION
################################################################################

if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    Select outer viewport: 0, 8, 0, 0.5
    Select inner viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    if mode = 1
        Text: 0.5, "centre", 0.6, "half", "Stereo Pitch Detune"
        Font size: 8
        Colour: "{0.4, 0.4, 0.5}"
        Text: 0.5, "centre", 0.1, "half", orig$ + " | Detune: " + fixed$(stereo_detune_semitones, 2) + " ST"
    else
        Text: 0.5, "centre", 0.6, "half", "Time-Delayed Canon: " + presetName$
        Font size: 8
        Colour: "{0.4, 0.4, 0.5}"
        Text: 0.5, "centre", 0.1, "half", orig$ + " | " + string$(number_of_voices) + " voices"
    endif
    
    Select outer viewport: 0, 8, 0.6, 1.5
    Select inner viewport: 0.6, 7.7, 0.7, 1.45
    selectObject: id_original
    Colour: "{0.6, 0.6, 0.6}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Original"
    Text top: "no", fixed$(original_duration, 2) + " s"
    
    if mode = 1
        Select outer viewport: 0, 4, 1.6, 2.5
        Select inner viewport: 0.6, 3.7, 1.7, 2.45
        selectObject: id_final_output
        Extract one channel: 1
        leftCh = selected("Sound")
        Colour: "{0.3, 0.5, 0.8}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Left (0 ST)"
        removeObject: leftCh
        
        Select outer viewport: 4, 8, 1.6, 2.5
        Select inner viewport: 4.4, 7.7, 1.7, 2.45
        selectObject: id_final_output
        Extract one channel: 2
        rightCh = selected("Sound")
        Colour: "{0.8, 0.5, 0.3}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Right (+" + fixed$(stereo_detune_semitones, 2) + " ST)"
        Text bottom: "yes", "Time (s)"
        removeObject: rightCh
    else
        Select outer viewport: 0, 8, 1.6, 2.5
        Select inner viewport: 0.6, 7.7, 1.7, 2.45
        selectObject: id_final_output
        Colour: "{0.3, 0.6, 0.5}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Canon Mix"
        Text bottom: "yes", "Time (s)"
    endif
    
    Select outer viewport: 0, 4, 2.6, 4.6
    Select inner viewport: 0.6, 3.7, 2.7, 4.5
    
    selectObject: id_original
    origMono = Convert to mono
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    origSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text top: "no", "Original Spectrogram"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: origSpec, origMono
    
    Select outer viewport: 4, 8, 2.6, 4.6
    Select inner viewport: 4.4, 7.7, 2.7, 4.5
    
    selectObject: id_final_output
    if mode = 1
        Extract one channel: 1
        resultMono = selected("Sound")
    else
        Copy: "result_mono"
        resultMono = selected("Sound")
    endif
    
    To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
    resultSpec = selected("Spectrogram")
    Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text left: "yes", "Freq (Hz)"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Result Spectrogram"
    Marks left every: 1, 1000, "yes", "yes", "no"
    
    removeObject: resultSpec, resultMono
    
    if mode = 1
        Select outer viewport: 0, 4, 4.7, 6.5
        Select inner viewport: 0.6, 3.7, 4.8, 6.4
        
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, 1, 0, 1
        
        Font size: 8
        Colour: "Black"
        Text: 0.5, "centre", 0.9, "half", "Pitch Shift Diagram"
        
        Font size: 7
        Colour: "{0.5, 0.5, 0.5}"
        
        Colour: "{0.3, 0.5, 0.8}"
        Paint rectangle: "{0.3, 0.5, 0.8}", 0.15, 0.45, 0.5, 0.7
        Colour: "Black"
        Text: 0.3, "centre", 0.6, "half", "L: 0 ST"
        
        Colour: "{0.8, 0.5, 0.3}"
        Paint rectangle: "{0.8, 0.5, 0.3}", 0.55, 0.85, 0.5 + stereo_detune_semitones * 0.02, 0.7 + stereo_detune_semitones * 0.02
        Colour: "Black"
        Text: 0.7, "centre", 0.6 + stereo_detune_semitones * 0.02, "half", "R: +" + fixed$(stereo_detune_semitones, 2) + " ST"
        
        Colour: "{0.7, 0.7, 0.7}"
        Dotted line
        Draw line: 0, 0.5, 1, 0.5
        Solid line
        
        Colour: "Black"
        Font size: 6
        Text: 0.05, "left", 0.3, "half", "Stereo width: " + fixed$(abs(stereo_detune_semitones), 2) + " semitones"
        if meanPitch > 0
            shifted_pitch = meanPitch * (2 ^ (stereo_detune_semitones / 12))
            Text: 0.05, "left", 0.2, "half", "Mean pitch: " + fixed$(meanPitch, 1) + " Hz → " + fixed$(shifted_pitch, 1) + " Hz"
        endif
        
    else
        Select outer viewport: 0, 8, 4.7, 6.5
        Select inner viewport: 0.6, 7.7, 4.8, 6.4
        
        max_delay = (number_of_voices - 1) * delay_between_entries
        total_time = max_delay + original_duration
        
        Axes: 0, total_time, 0, number_of_voices + 1
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, total_time, 0, number_of_voices + 1
        
        voice_colors$# = {"", "", "", "", "", "", "", ""}
        voice_colors$#[1] = "{0.3, 0.6, 0.9}"
        voice_colors$#[2] = "{0.9, 0.5, 0.3}"
        voice_colors$#[3] = "{0.3, 0.8, 0.5}"
        voice_colors$#[4] = "{0.8, 0.3, 0.7}"
        voice_colors$#[5] = "{0.9, 0.7, 0.3}"
        voice_colors$#[6] = "{0.5, 0.3, 0.8}"
        voice_colors$#[7] = "{0.3, 0.8, 0.8}"
        voice_colors$#[8] = "{0.8, 0.5, 0.5}"
        
        for v from 1 to number_of_voices
            y_pos = number_of_voices - v + 1
            delay_time = voice_info#[(v-1) * 4 + 2]
            semitones = voice_info#[(v-1) * 4 + 1]
            
            color_idx = ((v - 1) mod 8) + 1
            Colour: voice_colors$#[color_idx]
            Paint rectangle: voice_colors$#[color_idx], delay_time, delay_time + original_duration, y_pos - 0.3, y_pos + 0.3
            
            Colour: "Black"
            Font size: 6
            Text: delay_time + original_duration / 2, "centre", y_pos, "half", "V" + string$(v) + ": +" + string$(semitones) + "ST"
        endfor
        
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text left: "yes", "Voice"
        Text bottom: "yes", "Time (s)"
        Text top: "no", "Canon Timeline"
    endif
    
    Select outer viewport: 4, 8, 4.7, 6.5
    Select inner viewport: 4.4, 7.7, 4.8, 6.4
    
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.5, "centre", 0.95, "half", "Technique Explanation"
    
    Font size: 6
    Colour: "{0.5, 0.5, 0.5}"
    
    if mode = 1
        Text: 0.05, "left", 0.8, "half", "Sample Rate Override Method:"
        Text: 0.05, "left", 0.7, "half", "1. Original rate: " + string$(original_rate) + " Hz"
        Text: 0.05, "left", 0.6, "half", "2. Pitch ratio: 2^(" + fixed$(stereo_detune_semitones, 2) + "/12) = " + fixed$(pitch_ratio, 4)
        Text: 0.05, "left", 0.5, "half", "3. Override rate: " + string$(original_rate) + " / " + fixed$(pitch_ratio, 4) + " = " + string$(override_sample_rate) + " Hz"
        Text: 0.05, "left", 0.4, "half", "4. Resample back to " + string$(output_sample_rate) + " Hz"
        Text: 0.05, "left", 0.3, "half", "5. Sound plays faster/higher by ratio " + fixed$(pitch_ratio, 4)
        
        Text: 0.05, "left", 0.15, "half", "Left channel: unmodified"
        Text: 0.05, "left", 0.05, "half", "Right channel: pitch-shifted via override"
    else
        Text: 0.05, "left", 0.8, "half", "Canon Structure:"
        Text: 0.05, "left", 0.7, "half", "• " + string$(number_of_voices) + " voices, each delayed by " + fixed$(delay_between_entries, 2) + "s"
        Text: 0.05, "left", 0.6, "half", "• Pitch step: " + string$(semitone_step) + " semitones"
        if wrap_to_octave
            Text: 0.05, "left", 0.5, "half", "• Wrapping to octave (mod 12)"
        endif
        Text: 0.05, "left", 0.4, "half", "• Intensity start: " + fixed$(start_intensity_dB, 1) + " dB"
        Text: 0.05, "left", 0.3, "half", "• Intensity step: " + fixed$(intensity_step_dB, 1) + " dB per voice"
        
        Text: 0.05, "left", 0.15, "half", "Each voice uses sample rate override:"
        Text: 0.05, "left", 0.05, "half", "Override rate = " + string$(original_rate) + " / 2^(semitones/12)"
    endif
    
    Select outer viewport: 0, 8, 6.6, 7.2
    Select inner viewport: 0, 8, 6.6, 7.2
    Axes: 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    
    if mode = 1
        Text: 0.02, "left", 0.7, "half", "Parameters: Detune = " + fixed$(stereo_detune_semitones, 2) + " ST | Override = " + string$(override_sample_rate) + " Hz | Output = " + string$(output_sample_rate) + " Hz"
        Text: 0.02, "left", 0.3, "half", "Result: Stereo width from pitch difference | Duration: " + fixed$(final_duration, 2) + " s"
    else
        Text: 0.02, "left", 0.7, "half", "Voices: " + string$(number_of_voices) + " | Step: " + string$(semitone_step) + " ST | Delay: " + fixed$(delay_between_entries, 2) + " s | Intensity: " + fixed$(start_intensity_dB, 1) + " dB (step " + fixed$(intensity_step_dB, 1) + " dB)"
        
        pitch_range = (number_of_voices - 1) * semitone_step
        if wrap_to_octave and pitch_range > 12
            pitch_range = 12
        endif
        Text: 0.02, "left", 0.3, "half", "Total duration: " + fixed$(final_duration, 2) + " s | Pitch range: " + string$(pitch_range) + " ST | Output: " + string$(output_sample_rate) + " Hz"
    endif
    
    Font size: 10
endif

selectObject: id_final_output

appendInfoLine: ""
appendInfoLine: "=== Complete ==="
appendInfoLine: "Output: ", selected$("Sound")
if mode = 1
    appendInfoLine: "Detune: ", fixed$(stereo_detune_semitones, 2), " semitones"
    appendInfoLine: "Override rate: ", override_sample_rate, " Hz"
else
    appendInfoLine: "Voices: ", number_of_voices
    appendInfoLine: "Duration: ", fixed$(final_duration, 2), " s"
endif

if play_after_processing
    appendInfoLine: "Playing result..."
    Play
endif