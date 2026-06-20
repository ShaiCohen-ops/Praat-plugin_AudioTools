# ============================================================
# Praat AudioTools - NeuralResynthesisVocoder.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 2.6 (2026) - House-style colour accents (preset-coded, no more B&W)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# ---- INPUT CHECK ----
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object before running this script."
endif

sound_id = selected("Sound")
sound_name$ = selected$("Sound")
selectObject: sound_id
original_sr = Get sampling frequency

# ---- FORM INTERFACE WITH EXTREME PRESETS ----
form Neural Audio Resynthesis Vocoder v2.5
    comment ── Synthesis Configuration ──
    optionmenu Preset: 2
        option Custom Settings
        option Standard Resynthesis
        option Unit Gain x1.4 (brighter/pushed)
        option Soft-Unit Rounding (q=64)
        option Pushed + Heavy Rounding (q=128)
        option Coarse Rounding (q=4, crush)
        option Extreme Unit Gain x2.5 (off-manifold)
        option Noise Injection (high noise, low gain)
        option Combined Extreme (gain 0.1, q=128, noise 0.5)
        
    comment ── Latent Unit Operations (applied to HuBERT-Soft units) ──
    comment (Temperature: 1.0 = unchanged. 0.3-0.9 = softer/darker,
    comment  1.1-1.5 = brighter/pushed, 2.0+ = extreme/unstable)
    real Temperature 1.0
    comment (Quantization: 0 = off. Low values crush hard (4-16),
    comment  high values are subtle (64-256))
    integer Codebook_Quantization_Steps 0
    comment (Noise: 0.0 = off. 0.02-0.1 = subtle texture, 0.3-0.6 = stormy)
    real Noise_injection_scale 0.0
    
    comment ── Audio Playback ──
    boolean Play_result 1
    boolean Draw_visualization 1
endform

# ---- PRESET PROFILE CONFIGURATIONS ----
if preset = 2
    # Standard Resynthesis
    temperature = 1.0
    codebook_Quantization_Steps = 0
    noise_injection_scale = 0.0
elsif preset = 3
    # Unit Gain x1.4 (units scaled up -> brighter/pushed)
    temperature = 1.4
    codebook_Quantization_Steps = 0
    noise_injection_scale = 0.02
elsif preset = 4
    # Soft-Unit Rounding (q=64)
    temperature = 0.8
    codebook_Quantization_Steps = 64
    noise_injection_scale = 0.0
elsif preset = 5
    # Pushed units + heavy rounding (q=128) + light noise
    temperature = 1.2
    codebook_Quantization_Steps = 128
    noise_injection_scale = 0.05
elsif preset = 6
    # Coarse rounding (q=4) - aggressive unit crush
    temperature = 1.0
    codebook_Quantization_Steps = 4
    noise_injection_scale = 0.0
elsif preset = 7
    # Extreme unit gain x2.5 - pushes units far off-manifold
    temperature = 2.5
    codebook_Quantization_Steps = 0
    noise_injection_scale = 0.0
elsif preset = 8
    # Noise injection (high noise, reduced unit gain)
    temperature = 0.5
    codebook_Quantization_Steps = 0
    noise_injection_scale = 0.4
elsif preset = 9
    # Combined extreme: gain 0.1 + rounding q=128 + noise 0.5
    temperature = 0.1
    codebook_Quantization_Steps = 128
    noise_injection_scale = 0.5
endif

# ---- HOUSE-STYLE PRESET COLOUR MAP (visualization accent) ----
# Same palette family as the rest of AudioTools (see Bayesian Drone
# Weaver's class colours): each preset gets a fixed accent colour so the
# waveform/border/labels are never plain black-and-white.
if preset = 2
    presetColor$ = "{0.3, 0.6, 0.9}"
elsif preset = 3
    presetColor$ = "{0.9, 0.7, 0.3}"
elsif preset = 4
    presetColor$ = "{0.7, 0.7, 0.9}"
elsif preset = 5
    presetColor$ = "{0.9, 0.55, 0.25}"
elsif preset = 6
    presetColor$ = "{0.85, 0.3, 0.25}"
elsif preset = 7
    presetColor$ = "{0.85, 0.3, 0.6}"
elsif preset = 8
    presetColor$ = "{0.35, 0.75, 0.65}"
elsif preset = 9
    presetColor$ = "{0.6, 0.15, 0.2}"
else
    presetColor$ = "{0.45, 0.45, 0.45}"
endif

# ---- OS-Specific Python Discovery ----
if macintosh
    if fileReadable("/opt/homebrew/bin/python3")
        pythonCmd$ = "/opt/homebrew/bin/python3"
    elsif fileReadable("/Library/Frameworks/Python.framework/Versions/3.14/bin/python3")
        pythonCmd$ = "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3"
    elsif fileReadable("/usr/local/bin/python3")
        pythonCmd$ = "/usr/local/bin/python3"
    else
        pythonCmd$ = "python3"
    endif
elsif windows
    pythonCmd$ = "python"
else
    pythonCmd$ = "python3"
endif

# ---- PATHS ENGINE ----
pluginDir$    = preferencesDirectory$ + "/plugin_AudioTools/"
pythonScript$ = pluginDir$ + "py/neural_vocoder_engine.py"

if not fileReadable(pythonScript$)
    pythonScript$ = defaultDirectory$ + "/neural_vocoder_engine.py"
endif

if not fileReadable(pythonScript$)
    exitScript: "Cannot find Python script: neural_vocoder_engine.py" + newline$ + "Expected at: " + pluginDir$ + "py/ or next to this script."
endif

tempInput$   = temporaryDirectory$ + "/temp_neural_input.wav"
tempOutput$  = temporaryDirectory$ + "/temp_neural_output.wav"

procedure cleanUpTempFiles
    if fileReadable(tempInput$)
        deleteFile: tempInput$
    endif
    if fileReadable(tempOutput$)
        deleteFile: tempOutput$
    endif
endproc

@cleanUpTempFiles

# ---- INFO LOG GENERATION ----
clearinfo
appendInfoLine: "=== Praat AudioTools - Neural Audio Resynthesis Vocoder ==="
appendInfoLine: "Input Sound: ", sound_name$
appendInfoLine: "Preset Selected: ", preset$
appendInfoLine: "Parameters applied -> Temp: ", fixed$(temperature, 2), " | Quantization: ", codebook_Quantization_Steps, " | Noise Scale: ", fixed$(noise_injection_scale, 3)
appendInfoLine: ""

selectObject: sound_id
Save as WAV file: tempInput$

# Build execution payload. Single-double-quote helper (q$) so each path is
# wrapped in exactly ONE pair of quotes (the old Windows branch emitted
# doubled quotes + a dangling "", which was malformed).
q$ = """"
args$ = " --input " + q$ + tempInput$ + q$
args$ = args$ + " --output " + q$ + tempOutput$ + q$
args$ = args$ + " --temp " + string$(temperature)
args$ = args$ + " --quant " + string$(codebook_Quantization_Steps)
args$ = args$ + " --noise " + string$(noise_injection_scale)
cmd$ = pythonCmd$ + " " + q$ + pythonScript$ + q$ + args$

appendInfoLine: "[1/3] Running Neural Vocoder Engine (this blocks Praat until done)..."

runSystem_nocheck: cmd$

# ---- IMPORT AND UPSAMPLE PIPELINE ----
if fileReadable(tempOutput$)
    appendInfoLine: "[2/3] Importing neural array into Praat..."
    
    raw_output_id = Read from file: tempOutput$

    appendInfoLine: "[3/3] Resampling to original rate (", original_sr, " Hz) and finalizing..."

    if original_sr <> 16000
        selectObject: raw_output_id
        result_id = Resample: original_sr, 50
        removeObject: raw_output_id
    else
        result_id = raw_output_id
    endif

    selectObject: result_id
    Rename: sound_name$ + "_neuralResynth"

    appendInfoLine: ""
    appendInfoLine: "Done. Output Sound: ", sound_name$ + "_neuralResynth"

    # ---- VISUALIZATION (house style) ----
    if draw_visualization
        # mono-safe source for the spectrogram (output is mono, but guard anyway)
        selectObject: result_id
        nCh = Get number of channels
        if nCh > 1
            specSrc = Convert to mono
        else
            specSrc = Copy: "nv_spec_src"
        endif
        To Spectrogram: 0.005, 5000, 0.002, 20, "Gaussian"
        spectrogram_id = selected("Spectrogram")
        removeObject: specSrc

        Erase all
        Select outer viewport: 0, 8, 0, 8

        # Panel 0: Title (accent stripe + coloured preset tag, house style)
        Select outer viewport: 0, 8, 0, 0.9
        Axes: 0, 1, 0, 1
        Paint rectangle: presetColor$, 0, 1, 0.94, 1
        Black
        Font size: 14
        Text: 0.5, "centre", 0.62, "half", "##Neural Resynthesis Vocoder##"
        Font size: 8
        Text: 0.5, "centre", 0.22, "half", "HuBERT-Soft -> Acoustic Model -> HiFi-GAN  (16 kHz internal)"

        # Panel 1: Waveform of the resynthesis (coloured by preset).
        # Inner viewport is padded: 0.4 at the top for "Text top" (the
        # panel heading) and 0.3 at the bottom for "Marks bottom" +
        # "Text bottom" (the time-axis tick labels), so nothing bleeds
        # into the panels above/below.
        Select outer viewport: 0, 8, 1.05, 3.55
        Select inner viewport: 0.6, 7.7, 1.45, 3.25
        selectObject: result_id
        Colour: presetColor$
        Draw: 0, 0, 0, 0, "no", "Curve"
        Black
        Draw inner box
        Font size: 7
        Marks left: 3, "yes", "yes", "no"
        Text left: "yes", "Amplitude"
        Text bottom: "yes", "Time (seconds)"
        Font size: 9
        Colour: presetColor$
        Text top: "no", "##Resynthesized Waveform##"

        # Panel 2: Spectrogram of the resynthesis (greyscale cells are a
        # Praat engine limitation - Spectrogram Paint has no colormap - so
        # the accent colour goes on the frame/title instead, tying it
        # visually back to panel 1 and the preset tag). Same top/bottom
        # padding logic as panel 1, with a gap above from panel 1's
        # bottom axis labels.
        Select outer viewport: 0, 8, 3.75, 6.25
        Select inner viewport: 0.6, 7.7, 4.15, 5.95
        selectObject: spectrogram_id
        Paint: 0, 0, 0, 5000, 100, "yes", 50, 6, 0, "no"
        Colour: presetColor$
        Draw inner box
        Black
        Font size: 7
        Text left: "yes", "Frequency (Hz)"
        Text bottom: "yes", "Time (seconds)"
        Font size: 9
        Colour: presetColor$
        Text top: "no", "##Spectral Output (note 8 kHz model ceiling)##"

        # Panel 3: Summary panel - light tint of the preset colour instead
        # of flat grey, accent-coloured heading to match panels 1-2
        Select outer viewport: 0, 8, 6.45, 8.0
        Select inner viewport: 0.6, 7.7, 6.5, 7.95
        Axes: 0, 1, 0, 1
        Paint rectangle: "{0.96, 0.96, 0.97}", 0, 1, 0, 1
        Paint rectangle: presetColor$, 0, 0.012, 0, 1
        Font size: 9
        Colour: presetColor$
        Text: 0.03, "left", 0.84, "half", "##Latent Unit Operations##"
        Font size: 8
        Colour: "{0.25, 0.25, 0.25}"
        Text: 0.03, "left", 0.62, "half", "Preset: " + preset$
        Text: 0.03, "left", 0.44, "half", "Temperature (unit gain): " + fixed$(temperature, 2) + "    Quantization: " + string$(codebook_Quantization_Steps) + "    Noise: " + fixed$(noise_injection_scale, 3)
        Text: 0.03, "left", 0.26, "half", "Source: " + sound_name$ + "    Output rate: " + string$(original_sr) + " Hz"
        Colour: "{0.4, 0.4, 0.5}"
        Text: 0.03, "left", 0.08, "half", "Pipeline is speech-trained; non-speech input is 'speech-ified' (a feature, not a bug)."
        Black
        Draw rectangle: 0, 1, 0, 1

        removeObject: spectrogram_id
    endif

    selectObject: result_id
    if play_result
        Play
    endif
else
    appendInfoLine: "ERROR: Python engine did not produce an output file."
    appendInfoLine: "Check that PyTorch, soundfile, and torchaudio are installed,"
    appendInfoLine: "and that the bshall hubert / acoustic-model / hifigan torch.hub models are reachable."
    appendInfoLine: "If a crash_log.txt appears next to neural_vocoder_engine.py, check it for the traceback."
endif

@cleanUpTempFiles