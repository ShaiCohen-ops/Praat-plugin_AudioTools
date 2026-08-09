# ============================================================
# Praat AudioTools - Pitch_Processor.praat
# Author: Shai Cohen (Enhanced by Praat AudioTools)
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 1.1 (2026) - Enhanced Edition
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pitch-based transformation script with two modes:
#   1. Stereo Pitch Detune: Creates stereo spread via pitch shifting
#   2. Time-Delayed Canon: Multi-voice canon with pitch steps
#
#   Uses sample rate override technique for pitch shifting:
#   - Override sample rate = original_rate * (2 ^ (semitones / 12))
#   - Resample back to target rate
#   - Positive semitones raise pitch; negative semitones lower pitch
#
# Improvements in v1.1:
#   - Corrected detune direction: positive semitones now raise the right channel.
#   - Converts the processing source to a zero-based mono working copy, so
#     non-zero input xmin/xmax and multichannel inputs are handled consistently.
#   - Canon delays are guaranteed to be silence-before-audio despite Praat's
#     Objects-list Concatenate ordering.
#   - Canon intensity is applied to the active voice before delay silence.
#   - Canon voices are summed in a true mono accumulator; no iterative
#     stereo-combine/mono-average normalization.
#   - Attenuation-only peak safety; quiet material is never boosted.
#   - Validates output/resample/override sample rates.
#   - Keeps the established AudioTools six-panel visualization language;
#     fixes the Canon Timeline / Technique Explanation viewport overlap.
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

form Pitch Processor v1.1
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

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

# ============================================================
# PRESETS
# ============================================================
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

# ============================================================
# INPUT / VALIDATION
# ============================================================
orig$ = selected$("Sound")
id_original = selected("Sound")
id_final_output = 0
safety_applied = 0

selectObject: id_original
source_xmin = Get start time
source_xmax = Get end time
original_duration = source_xmax - source_xmin
original_rate = Get sampling frequency
original_channels = Get number of channels

if original_duration <= 0
    exitScript: "The selected Sound has no positive duration."
endif
if output_sample_rate < 8000 or output_sample_rate > 384000
    exitScript: "Output_sample_rate must be between 8000 and 384000 Hz."
endif
if resample_precision < 1 or resample_precision > 1000
    exitScript: "Resample_precision must be between 1 and 1000."
endif
if mode = 2 and number_of_voices > 32
    exitScript: "Number_of_voices is limited to 32 for safe rendering."
endif

selectObject: id_original
if original_channels > 1
    tmp_mono = Convert to mono
    selectObject: tmp_mono
    source_work = Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
    Rename: "PP_source_work"
    removeObject: tmp_mono
else
    source_work = Extract part: source_xmin, source_xmax, "rectangular", 1, "no"
    Rename: "PP_source_work"
endif

clearinfo
writeInfoLine: "=== Pitch Processor v1.1 ==="
if mode = 1
    appendInfoLine: "Mode: Stereo Pitch Detune"
else
    appendInfoLine: "Mode: Time-Delayed Canon"
    appendInfoLine: "Preset: ", presetName$
endif
appendInfoLine: "Source: ", orig$, "  (", fixed$(original_duration, 3), " s)"
appendInfoLine: "Source channels: ", original_channels, "  -> processing reference: mono"
appendInfoLine: "Source domain: ", fixed$(source_xmin, 6), " ... ", fixed$(source_xmax, 6), " s"
appendInfoLine: ""

meanPitch = 0
if draw_visualization
    appendInfoLine: "Analyzing original pitch..."
    analysis_ceiling = min(600, 0.45 * original_rate)
    if analysis_ceiling > 75
        selectObject: source_work
        To Pitch: 0.01, 75, analysis_ceiling
        pitchObj = selected("Pitch")
        meanPitch = Get mean: 0, 0, "Hertz"
        if meanPitch = undefined
            meanPitch = 0
        endif
        removeObject: pitchObj
    endif
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
    override_sample_rate = round(original_rate * pitch_ratio)

    if override_sample_rate < 100 or override_sample_rate > 655350
        removeObject: source_work
        exitScript: "Detune requires an unsafe override sample rate (" +
            ... string$(override_sample_rate) + " Hz). Reduce Stereo_detune_semitones."
    endif

    appendInfoLine: "  Pitch ratio: ", fixed$(pitch_ratio, 4)
    appendInfoLine: "  Override rate: ", override_sample_rate, " Hz"

    selectObject: source_work
    left_resampled = Resample: output_sample_rate, resample_precision
    Rename: "PP_detune_left"

    selectObject: source_work
    right_raw = Copy: "PP_detune_right_raw"
    Override sampling frequency: override_sample_rate
    right_resampled = Resample: output_sample_rate, resample_precision
    Rename: "PP_detune_right"
    removeObject: right_raw

    selectObject: left_resampled
    dur_left = Get total duration
    selectObject: right_resampled
    dur_right = Get total duration
    final_duration = max(dur_left, dur_right)

    if dur_left < final_duration - 0.000001
        pad_len = final_duration - dur_left
        Create Sound from formula: "PP_pad_L", 1, 0, pad_len, output_sample_rate, "0"
        pad_id = selected("Sound")
        selectObject: left_resampled
        plusObject: pad_id
        left_ext = Concatenate
        removeObject: left_resampled, pad_id
        left_resampled = left_ext
    endif

    if dur_right < final_duration - 0.000001
        pad_len = final_duration - dur_right
        Create Sound from formula: "PP_pad_R", 1, 0, pad_len, output_sample_rate, "0"
        pad_id = selected("Sound")
        selectObject: right_resampled
        plusObject: pad_id
        right_ext = Concatenate
        removeObject: right_resampled, pad_id
        right_resampled = right_ext
    endif

    selectObject: left_resampled
    left_ordered = Copy: "PP_L_ordered"
    selectObject: right_resampled
    right_ordered = Copy: "PP_R_ordered"
    removeObject: left_resampled, right_resampled

    selectObject: left_ordered
    plusObject: right_ordered
    id_final_output = Combine to stereo
    Rename: orig$ + "_detune_" + fixed$(stereo_detune_semitones, 1) + "ST"

    removeObject: left_ordered, right_ordered

    selectObject: id_final_output
    out_peak = Get absolute extremum: 0, 0, "None"
    if out_peak > 0.99
        Scale peak: 0.99
        safety_applied = 1
    endif

    if stereo_detune_semitones >= 0
        detuneLabel$ = "+" + fixed$(stereo_detune_semitones, 2)
    else
        detuneLabel$ = fixed$(stereo_detune_semitones, 2)
    endif
endif

# ============================================================
# MODE 2: Time-Delayed Canon
# ============================================================
if mode = 2
    appendInfoLine: ""
    appendInfoLine: "Creating canon with ", number_of_voices, " voices..."

    voice_info# = zero#(number_of_voices * 4)
    voice_ids# = zero#(number_of_voices)
    voice_dur# = zero#(number_of_voices)

    final_duration = 0

    for v from 1 to number_of_voices
        s = (v - 1) * semitone_step
        if wrap_to_octave
            s = s - 12 * floor(s / 12)
        endif

        factor = 2 ^ (s / 12)
        f_override = round(original_rate * factor)

        if f_override < 100 or f_override > 655350
            for vv from 1 to v - 1
                if voice_ids#[vv] > 0
                    removeObject: voice_ids#[vv]
                endif
            endfor
            removeObject: source_work
            exitScript: "Voice " + string$(v) + " requires an unsafe override sample rate (" +
                ... string$(f_override) + " Hz). Reduce Semitone_step / Number_of_voices."
        endif

        delay_time = (v - 1) * delay_between_entries
        intensity = start_intensity_dB + (v - 1) * intensity_step_dB

        voice_info#[(v-1) * 4 + 1] = s
        voice_info#[(v-1) * 4 + 2] = delay_time
        voice_info#[(v-1) * 4 + 3] = intensity
        voice_info#[(v-1) * 4 + 4] = factor

        appendInfoLine: "  Voice ", v, ": ", s, " ST, delay ",
            ... fixed$(delay_time, 2), " s, ", fixed$(intensity, 1), " dB"

        selectObject: source_work
        voice_raw = Copy: "PP_voice_raw_" + string$(v)
        Override sampling frequency: f_override
        voice_shifted = Resample: output_sample_rate, resample_precision
        Rename: "PP_voice_active_" + string$(v)
        removeObject: voice_raw

        selectObject: voice_shifted
        Scale intensity: intensity

        active_dur = Get total duration
        voice_ids#[v] = voice_shifted
        voice_dur#[v] = active_dur

        voice_end = delay_time + active_dur
        if voice_end > final_duration
            final_duration = voice_end
        endif
    endfor

    if final_duration <= 0
        for v from 1 to number_of_voices
            removeObject: voice_ids#[v]
        endfor
        removeObject: source_work
        exitScript: "Canon rendering produced no positive duration."
    endif

    Create Sound from formula: "PP_canon_mix", 1, 0, final_duration,
        ... output_sample_rate, "0"
    id_mix = selected("Sound")

    for v from 1 to number_of_voices
        id_voice = voice_ids#[v]
        delay_time = voice_info#[(v-1) * 4 + 2]

        if delay_time > 0.000001
            Create Sound from formula: "PP_delay_" + string$(v), 1,
                ... 0, delay_time, output_sample_rate, "0"
            id_pad = selected("Sound")

            selectObject: id_voice
            ordered_voice = Copy: "PP_ordered_voice_" + string$(v)

            selectObject: id_pad
            plusObject: ordered_voice
            with_delay = Concatenate

            removeObject: id_pad, ordered_voice, id_voice
        else
            with_delay = id_voice
        endif

        selectObject: with_delay
        layer_dur = Get total duration
        pad_end_len = final_duration - layer_dur

        if pad_end_len > 0.000001
            Create Sound from formula: "PP_endpad_" + string$(v), 1,
                ... 0, pad_end_len, output_sample_rate, "0"
            id_pad_end = selected("Sound")

            selectObject: with_delay
            plusObject: id_pad_end
            full_layer = Concatenate
            removeObject: with_delay, id_pad_end
        elsif pad_end_len < -0.000001
            selectObject: with_delay
            full_layer = Extract part: 0, final_duration, "rectangular", 1, "no"
            removeObject: with_delay
        else
            full_layer = with_delay
        endif

        selectObject: id_mix
        Formula: "self + object[" + string$(full_layer) + ", 1, col]"
        removeObject: full_layer
    endfor

    selectObject: id_mix
    Rename: orig$ + "_canon_" + presetName$
    id_final_output = id_mix

    out_peak = Get absolute extremum: 0, 0, "None"
    if out_peak > 0.99
        Scale peak: 0.99
        safety_applied = 1
    endif
endif

removeObject: source_work

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
        Text left: "yes", "Right (" + detuneLabel$ + " ST)"
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
        Text: 0.7, "centre", 0.6 + stereo_detune_semitones * 0.02, "half", "R: " + detuneLabel$ + " ST"
        
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
        Select outer viewport: 0, 4, 4.7, 6.5
        Select inner viewport: 0.6, 3.7, 4.8, 6.4
        
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
        Text: 0.05, "left", 0.5, "half", "3. Override rate: " + string$(original_rate) + " x " + fixed$(pitch_ratio, 4) + " = " + string$(override_sample_rate) + " Hz"
        Text: 0.05, "left", 0.4, "half", "4. Resample back to " + string$(output_sample_rate) + " Hz"
        Text: 0.05, "left", 0.3, "half", "5. Pitch changes by ratio " + fixed$(pitch_ratio, 4)
        
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
        Text: 0.05, "left", 0.05, "half", "Override rate = " + string$(original_rate) + " x 2^(semitones/12)"
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
appendInfoLine: "Peak safety applied: ", safety_applied

if play_after_processing
    appendInfoLine: "Playing result..."
    Play
endif