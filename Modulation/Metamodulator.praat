# ============================================================
# Praat AudioTools - Metamodulator.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 2.5 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Eight deterministic modulation families applied as a multiplicative
#   audio modulator. Frequency-defined algorithms use phase integration,
#   so the stated/visualized instantaneous-frequency trajectory is the
#   trajectory actually synthesized.
#
#   The modulator is generated once on the source sample grid and shared
#   by all channels. Sample rate, sample count, duration, start time and
#   arbitrary channel counts are preserved.
#
# Changelog v2.5:
#   - VISUALIZATION STANDARDIZATION ONLY; audio/DSP, analysis,
#     parameter mapping and rendering logic are unchanged.
#   - Standardized title/version, Picture-page restoration,
#     typography and summary/export behavior for AudioTools.
#
# v2.4 changes:
#   - Correct phase integration for exponential/log sweeps, SinFM,
#     Spiral FM and Trembling so displayed instantaneous frequency
#     matches the synthesized modulator.
#   - Uses local sound time; output is invariant to non-zero start time.
#   - Generates one mono modulator and reuses it for all channels.
#   - Adds exact Dry/Wet bypass and attenuation-only Safety_peak.
#   - Removes unconditional peak normalization.
#   - Clarifies TimeVar/Tremble f0 as chirp slope (Hz/s).
#   - Preserves all 33 musical presets and divider-selection protection.
#   - Updates visualization to the AudioTools house text layout.
# ============================================================

form Metamodulator v2.5
    optionmenu Preset: 1
        option Custom (Use Manual Settings)
        option --- Cubic Phase Distortion ---
        option Cubic: Mild Distortion
        option Cubic: Strong Distortion
        option Cubic: High Frequency
        option --- Exponential Sweep ---
        option ExpSweep: Slow
        option ExpSweep: Fast
        option ExpSweep: Narrow Range
        option --- Logarithmic Sweep ---
        option LogSweep: Descending Classic
        option LogSweep: Fast Descent
        option --- Quadratic Phase ---
        option Quad: Gentle Bend
        option Quad: Classic Sweep
        option Quad: Dramatic Warp
        option Quad: Reverse Bend
        option Quad: Extreme Distortion
        option Quad: Subtle Shimmer
        option --- Sinusoidal FM ---
        option SinFM: Classic
        option SinFM: Deep Modulation
        option --- Spiral FM ---
        option Spiral: Gentle
        option Spiral: Classic Vortex
        option Spiral: Intense Whirlpool
        option Spiral: Deep Rotation
        option Spiral: Hypnotic Spin
        option Spiral: Cosmic
        option --- Time-Varying (Chirp) ---
        option TimeVar: Subtle Shimmer
        option TimeVar: Rising Metallic
        option TimeVar: Sci-Fi Sweep
        option TimeVar: Laser Beam
        option TimeVar: Extreme Glitch
        option --- Trembling (Vibrato+Chirp) ---
        option Tremble: Gentle Warble
        option Tremble: Radio Interference
        option Tremble: Deep Space
        option Tremble: Vintage Synth
        option Tremble: Alien Voice
    optionmenu Manual_Algorithm: 1
        option 1. Cubic Phase Distortion
        option 2. Exponential Frequency Sweep
        option 3. Logarithmic Frequency Sweep
        option 4. Quadratic Phase Modulation
        option 5. Sinusoidal FM
        option 6. Spiral FM
        option 7. Time-Varying (Chirp)
        option 8. Trembling (Vibrato+Chirp)
    positive Carrier_Frequency_Hz: 200
    positive Start_Frequency_Hz: 100
    positive End_Frequency_Hz: 800
    real Modulation_Factor: 2.0
    real Modulation_Rate_Hz: 5.0
    real Dry_wet_percent: 100
    real Safety_peak: 0.99
    boolean Show_spectrogram: 0
    boolean Draw_visualization: 1
    boolean Play_result: 1
endform

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

if left$(preset$, 3) = "---"
    exitScript: "You selected a category divider (" + preset$ + ")." + newline$ + "Please pick a real preset, or choose Custom."
endif

sound = selected("Sound")
name$ = selected$("Sound")
selectObject: sound
numChannels = Get number of channels
sampleRate = Get sampling frequency
sampleCount = Get number of samples
originalStart = Get start time
duration = Get total duration
nyquist = sampleRate / 2

# ============================================================
# PRESET LOGIC
# ============================================================
algo = manual_Algorithm
f0 = carrier_Frequency_Hz
f_start = start_Frequency_Hz
f_end = end_Frequency_Hz
mod_factor = modulation_Factor
mod_rate = modulation_Rate_Hz

if preset$ = "Cubic: Mild Distortion"
    algo = 1
    f0 = 100
    mod_factor = 1
elsif preset$ = "Cubic: Strong Distortion"
    algo = 1
    f0 = 200
    mod_factor = 4
elsif preset$ = "Cubic: High Frequency"
    algo = 1
    f0 = 300
    mod_factor = 2.5
elsif preset$ = "ExpSweep: Slow"
    algo = 2
    f_start = 100
    f_end = 600
elsif preset$ = "ExpSweep: Fast"
    algo = 2
    f_start = 50
    f_end = 1200
elsif preset$ = "ExpSweep: Narrow Range"
    algo = 2
    f_start = 200
    f_end = 400
elsif preset$ = "LogSweep: Descending Classic"
    algo = 3
    f_start = 800
    f_end = 50
elsif preset$ = "LogSweep: Fast Descent"
    algo = 3
    f_start = 1000
    f_end = 100
elsif preset$ = "Quad: Gentle Bend"
    algo = 4
    f0 = 150
    mod_factor = 0.3
elsif preset$ = "Quad: Classic Sweep"
    algo = 4
    f0 = 200
    mod_factor = 0.5
elsif preset$ = "Quad: Dramatic Warp"
    algo = 4
    f0 = 250
    mod_factor = 1.0
elsif preset$ = "Quad: Reverse Bend"
    algo = 4
    f0 = 180
    mod_factor = -0.4
elsif preset$ = "Quad: Extreme Distortion"
    algo = 4
    f0 = 300
    mod_factor = 1.5
elsif preset$ = "Quad: Subtle Shimmer"
    algo = 4
    f0 = 120
    mod_factor = 0.1
elsif preset$ = "SinFM: Classic"
    algo = 5
    f0 = 300
    mod_rate = 2
    mod_factor = 100
elsif preset$ = "SinFM: Deep Modulation"
    algo = 5
    f0 = 400
    mod_rate = 3
    mod_factor = 200
elsif preset$ = "Spiral: Gentle"
    algo = 6
    f0 = 200
    mod_rate = 0.5
    mod_factor = 80
elsif preset$ = "Spiral: Classic Vortex"
    algo = 6
    f0 = 250
    mod_rate = 0.8
    mod_factor = 150
elsif preset$ = "Spiral: Intense Whirlpool"
    algo = 6
    f0 = 300
    mod_rate = 1.2
    mod_factor = 200
elsif preset$ = "Spiral: Deep Rotation"
    algo = 6
    f0 = 150
    mod_rate = 0.6
    mod_factor = 120
elsif preset$ = "Spiral: Hypnotic Spin"
    algo = 6
    f0 = 400
    mod_rate = 1.5
    mod_factor = 180
elsif preset$ = "Spiral: Cosmic"
    algo = 6
    f0 = 180
    mod_rate = 0.7
    mod_factor = 250
elsif preset$ = "TimeVar: Subtle Shimmer"
    algo = 7
    f0 = 100
elsif preset$ = "TimeVar: Rising Metallic"
    algo = 7
    f0 = 200
elsif preset$ = "TimeVar: Sci-Fi Sweep"
    algo = 7
    f0 = 300
elsif preset$ = "TimeVar: Laser Beam"
    algo = 7
    f0 = 500
elsif preset$ = "TimeVar: Extreme Glitch"
    algo = 7
    f0 = 800
elsif preset$ = "Tremble: Gentle Warble"
    algo = 8
    f0 = 200
    mod_rate = 5
    mod_factor = 0.03
elsif preset$ = "Tremble: Radio Interference"
    algo = 8
    f0 = 440
    mod_rate = 25
    mod_factor = 0.08
elsif preset$ = "Tremble: Deep Space"
    algo = 8
    f0 = 100
    mod_rate = 10
    mod_factor = 0.1
elsif preset$ = "Tremble: Vintage Synth"
    algo = 8
    f0 = 300
    mod_rate = 20
    mod_factor = 0.06
elsif preset$ = "Tremble: Alien Voice"
    algo = 8
    f0 = 150
    mod_rate = 30
    mod_factor = 0.12
endif

# ============================================================
# VALIDATION / NAMES
# ============================================================
dry_wet_percent = min(100, max(0, dry_wet_percent))
safety_peak = min(1, max(0, safety_peak))
mod_rate = max(0, mod_rate)
f0 = min(0.49 * sampleRate, max(0.001, f0))
f_start = min(0.49 * sampleRate, max(0.001, f_start))
f_end = min(0.49 * sampleRate, max(0.001, f_end))
wet = dry_wet_percent / 100
dry = 1 - wet

if algo = 1
    algo_name$ = "Cubic Phase"
elsif algo = 2
    algo_name$ = "Exponential Sweep"
elsif algo = 3
    algo_name$ = "Log Sweep"
elsif algo = 4
    algo_name$ = "Quadratic Phase"
elsif algo = 5
    algo_name$ = "Sinusoidal FM"
elsif algo = 6
    algo_name$ = "Spiral FM"
elsif algo = 7
    algo_name$ = "Linear Chirp"
else
    algo_name$ = "Trembling Chirp"
endif

# Diagnostic frequency bounds for warnings/summary.
if algo = 1
    f_begin = f0
    f_finish = f0 + 3 * mod_factor * duration^2 / (2*pi)
    estimatedMaxF = max(abs(f_begin), abs(f_finish))
elsif algo = 2 or algo = 3
    f_begin = f_start
    f_finish = f_end
    estimatedMaxF = max(f_start, f_end)
elsif algo = 4
    f_begin = f0
    f_finish = f0 + mod_factor * duration / pi
    estimatedMaxF = max(abs(f_begin), abs(f_finish))
elsif algo = 5
    f_begin = f0
    f_finish = f0
    estimatedMaxF = f0 + abs(mod_factor)
elsif algo = 6
    f_begin = f0
    f_finish = f0 + mod_factor * sin(2*pi*mod_rate*duration)
    estimatedMaxF = f0 + abs(mod_factor)
elsif algo = 7
    f_begin = 0
    f_finish = f0 * duration
    estimatedMaxF = abs(f_finish)
else
    f_begin = 0
    f_finish = f0 * duration * (1 + mod_factor * sin(2*pi*mod_rate*duration))
    estimatedMaxF = abs(f0 * duration) * (1 + abs(mod_factor))
endif

clearinfo
appendInfoLine: "=== Metamodulator v2.5 ==="
appendInfoLine: "Source: ", name$, " (", fixed$(duration, 3), " s)"
appendInfoLine: "Preset: ", preset$
appendInfoLine: "Algorithm: ", algo_name$
appendInfoLine: "Channels: ", numChannels, " | Sample rate: ", fixed$(sampleRate, 0), " Hz"
appendInfoLine: "Dry/Wet: ", fixed$(dry_wet_percent, 1), "%"
if algo = 1 or algo = 4
    appendInfoLine: "Carrier: ", fixed$(f0, 3), " Hz | phase factor: ", fixed$(mod_factor, 4)
elsif algo = 2 or algo = 3
    appendInfoLine: "Frequency trajectory: ", fixed$(f_start, 3), " -> ", fixed$(f_end, 3), " Hz"
elsif algo = 5 or algo = 6
    appendInfoLine: "Carrier: ", fixed$(f0, 3), " Hz | rate: ", fixed$(mod_rate, 3), " Hz | depth: ", fixed$(mod_factor, 3), " Hz"
elsif algo = 7
    appendInfoLine: "Chirp slope: ", fixed$(f0, 3), " Hz/s"
else
    appendInfoLine: "Chirp slope: ", fixed$(f0, 3), " Hz/s | tremble rate: ", fixed$(mod_rate, 3), " Hz | depth: ", fixed$(mod_factor, 4)
endif
if estimatedMaxF >= nyquist
    appendInfoLine: "Warning: requested modulator trajectory reaches/exceeds Nyquist; aliasing may occur."
endif

# ============================================================
# BUILD MODULATOR ONCE (only if processing or drawing needs it)
# ============================================================
needModulator = (wet > 0 or draw_visualization)
modulator = 0
if needModulator
    selectObject: sound
    Extract one channel: 1
    modulator = selected("Sound")
    Rename: "metamodulator_control"

    sweepLog = ln(f_end / f_start)
    omega = 2*pi*mod_rate
    globalStart = originalStart
    globalDur = duration
    globalF0 = f0
    globalFs = f_start
    globalSweepLog = sweepLog
    globalFactor = mod_factor
    globalRate = mod_rate
    globalOmega = omega

    selectObject: modulator
    if algo = 1
        Formula: "sin(2*pi*'globalF0'*(x-'globalStart') + 'globalFactor'*(x-'globalStart')^3)"
    elsif algo = 2 or algo = 3
        if abs(sweepLog) < 1e-12
            Formula: "sin(2*pi*'globalFs'*(x-'globalStart'))"
        else
            Formula: "sin(2*pi*'globalFs'*'globalDur'/'globalSweepLog' * (exp('globalSweepLog'*(x-'globalStart')/'globalDur') - 1))"
        endif
    elsif algo = 4
        Formula: "sin(2*pi*'globalF0'*(x-'globalStart') + 'globalFactor'*(x-'globalStart')^2)"
    elsif algo = 5
        if mod_rate <= 0
            Formula: "sin(2*pi*'globalF0'*(x-'globalStart'))"
        else
            Formula: "sin(2*pi*'globalF0'*(x-'globalStart') + ('globalFactor'/'globalRate')*(1-cos(2*pi*'globalRate'*(x-'globalStart'))))"
        endif
    elsif algo = 6
        if mod_rate <= 0
            Formula: "sin(2*pi*'globalF0'*(x-'globalStart'))"
        else
            Formula: "sin(2*pi*'globalF0'*(x-'globalStart') + 2*pi*'globalFactor'/'globalDur' * (-(x-'globalStart')*cos('globalOmega'*(x-'globalStart'))/'globalOmega' + sin('globalOmega'*(x-'globalStart'))/('globalOmega'^2)))"
        endif
    elsif algo = 7
        Formula: "sin(pi*'globalF0'*(x-'globalStart')^2)"
    else
        if mod_rate <= 0
            Formula: "sin(pi*'globalF0'*(x-'globalStart')^2)"
        else
            Formula: "sin(pi*'globalF0'*(x-'globalStart')^2 + 2*pi*'globalF0'*'globalFactor' * (-(x-'globalStart')*cos('globalOmega'*(x-'globalStart'))/'globalOmega' + sin('globalOmega'*(x-'globalStart'))/('globalOmega'^2)))"
        endif
    endif
endif

# ============================================================
# APPLY MODULATOR / EXACT DRY BYPASS
# ============================================================
selectObject: sound
result = Copy: name$ + "_Metamod_" + algo_name$

if wet > 0
    globalWet = wet
    globalDry = dry
    globalMod = modulator
    selectObject: result
    Formula: "self * ('globalDry' + 'globalWet' * object ['globalMod', 1, col])"
endif

# Attenuation-only safety. Never boost quiet material; dry bypass is exact.
selectObject: result
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
if wet > 0 and safety_peak > 0 and peakBeforeSafety > safety_peak
    Scale peak: safety_peak
endif
finalPeak = Get absolute extremum: 0, 0, "None"
finalDur = Get total duration

appendInfoLine: "Peak before safety: ", fixed$(peakBeforeSafety, 6)
appendInfoLine: "Output peak: ", fixed$(finalPeak, 6)
if safety_peak > 0
    appendInfoLine: "Safety ceiling: ", fixed$(safety_peak, 3)
else
    appendInfoLine: "Safety: disabled"
endif
appendInfoLine: "=== Done ==="
appendInfoLine: "Created: ", selected$("Sound")

# ============================================================
# VISUALIZATION - AudioTools house layout
# ============================================================
if draw_visualization
    pageHeight = 6.7
    if safety_peak > 0
        safeStr$ = fixed$(safety_peak, 2)
    else
        safeStr$ = "off"
    endif
    if show_spectrogram
        outMode$ = "spectrogram"
    else
        outMode$ = "waveform"
    endif

    if algo = 1 or algo = 4
        if algo = 1
            paramStr$ = "f0 " + fixed$(f0, 0) + " Hz | k " + fixed$(mod_factor, 2) + " | cubic phase"
        else
            paramStr$ = "f0 " + fixed$(f0, 0) + " Hz | k " + fixed$(mod_factor, 2) + " | quadratic phase"
        endif
    elsif algo = 2 or algo = 3
        paramStr$ = fixed$(f_start, 0) + " -> " + fixed$(f_end, 0) + " Hz"
    elsif algo = 5 or algo = 6
        paramStr$ = "f0 " + fixed$(f0, 0) + " Hz | rate " + fixed$(mod_rate, 1) + " Hz | depth " + fixed$(mod_factor, 0) + " Hz"
    elsif algo = 7
        paramStr$ = "slope " + fixed$(f0, 0) + " Hz/s"
    else
        paramStr$ = "slope " + fixed$(f0, 0) + " Hz/s | rate " + fixed$(mod_rate, 1) + " Hz | depth " + fixed$(mod_factor*100, 1) + "%"
    endif

    Erase all
    Select outer viewport: 0, 8, 0, pageHeight
    Black
    Plain line

    # Title
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Metamodulator v2.5##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", 0.22, "half", name$ + "  |  " + preset$ + "  |  " + algo_name$

    # Input waveform
    Select outer viewport: 0, 4.2, 0.75, 2.30
    Select inner viewport: 0.55, 4.00, 0.95, 2.18
    selectObject: sound
    Colour: "{0.55, 0.55, 0.55}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Input"
    Font size: 6
    Text left: "yes", "Amp"

    # Output waveform or spectrogram
    Select outer viewport: 4.2, 8, 0.75, 2.30
    Select inner viewport: 4.55, 7.75, 0.95, 2.18
    if show_spectrogram
        selectObject: result
        To Spectrogram: 0.01, min(8000, nyquist), 0.002, 20, "Gaussian"
        spec_result = selected("Spectrogram")
        Paint: 0, 0, 0, min(8000, nyquist), 100, "yes", 50, 6, 0, "no"
        removeObject: spec_result
        Colour: "Black"
        Draw inner box
        Font size: 7
        Text top: "no", "Output spectrum"
        Font size: 6
        Text left: "yes", "Hz"
    else
        selectObject: result
        Colour: "{0.25, 0.45, 0.80}"
        Draw: 0, 0, 0, 0, "no", "Curve"
        Colour: "Black"
        Line width: 1
        Draw inner box
        Font size: 7
        Text top: "no", "Output"
        Font size: 6
        Text left: "yes", "Amp"
    endif

    # Control trajectory
    Select outer viewport: 0, 8, 2.40, 4.25
    Select inner viewport: 0.55, 7.75, 2.60, 4.12
    displayDur = min(1, duration)
    nPoints = 300

    if algo = 1 or algo = 4
        if algo = 1
            phaseEnd = mod_factor * displayDur^3
        else
            phaseEnd = mod_factor * displayDur^2
        endif
        phaseMax = max(0.1, abs(phaseEnd) * 1.2)
        Axes: 0, displayDur, -phaseMax, phaseMax
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, displayDur, -phaseMax, phaseMax
        Colour: "{0.48, 0.36, 0.72}"
        for p from 2 to nPoints
            t1 = (p-2)/(nPoints-1)*displayDur
            t2 = (p-1)/(nPoints-1)*displayDur
            if algo = 1
                y1 = mod_factor*t1^3
                y2 = mod_factor*t2^3
            else
                y1 = mod_factor*t1^2
                y2 = mod_factor*t2^2
            endif
            Draw line: t1, y1, t2, y2
        endfor
        controlLabel$ = "Phase offset (rad)"
    else
        # Exact instantaneous-frequency curve implied by integrated phase.
        fLo = 1e30
        fHi = -1e30
        for p from 1 to nPoints
            tt = (p-1)/(nPoints-1)*displayDur
            if algo = 2 or algo = 3
                ff = f_start * exp(ln(f_end/f_start)*tt/duration)
            elsif algo = 5
                ff = f0 + mod_factor*sin(2*pi*mod_rate*tt)
            elsif algo = 6
                ff = f0 + mod_factor*sin(2*pi*mod_rate*tt)*tt/duration
            elsif algo = 7
                ff = f0*tt
            else
                ff = f0*tt*(1 + mod_factor*sin(2*pi*mod_rate*tt))
            endif
            fLo = min(fLo, ff)
            fHi = max(fHi, ff)
        endfor
        fMargin = max(10, 0.1*(fHi-fLo))
        Axes: 0, displayDur, fLo-fMargin, fHi+fMargin
        Paint rectangle: "{0.97, 0.97, 0.97}", 0, displayDur, fLo-fMargin, fHi+fMargin
        Colour: "{0.48, 0.36, 0.72}"
        for p from 2 to nPoints
            t1 = (p-2)/(nPoints-1)*displayDur
            t2 = (p-1)/(nPoints-1)*displayDur
            if algo = 2 or algo = 3
                y1 = f_start*exp(ln(f_end/f_start)*t1/duration)
                y2 = f_start*exp(ln(f_end/f_start)*t2/duration)
            elsif algo = 5
                y1 = f0 + mod_factor*sin(2*pi*mod_rate*t1)
                y2 = f0 + mod_factor*sin(2*pi*mod_rate*t2)
            elsif algo = 6
                y1 = f0 + mod_factor*sin(2*pi*mod_rate*t1)*t1/duration
                y2 = f0 + mod_factor*sin(2*pi*mod_rate*t2)*t2/duration
            elsif algo = 7
                y1 = f0*t1
                y2 = f0*t2
            else
                y1 = f0*t1*(1 + mod_factor*sin(2*pi*mod_rate*t1))
                y2 = f0*t2*(1 + mod_factor*sin(2*pi*mod_rate*t2))
            endif
            Draw line: t1, y1, t2, y2
        endfor
        controlLabel$ = "Frequency (Hz)"
    endif
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Control trajectory"
    Font size: 6
    Text left: "yes", controlLabel$
    Text bottom: "yes", "Time (s)"

    # Modulator waveform preview from the actual generated control Sound.
    Select outer viewport: 0, 8, 4.35, 5.55
    Select inner viewport: 0.55, 7.75, 4.50, 5.43
    previewDur = min(duration, 0.05)
    selectObject: modulator
    Colour: "{0.48, 0.36, 0.72}"
    Draw: originalStart, originalStart + previewDur, -1.05, 1.05, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Actual modulator"
    Font size: 6
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # Summary
    Select outer viewport: 0, 8, 5.65, 6.55
    Select inner viewport: 0.55, 7.75, 5.72, 6.47
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.78, "half", "##Summary##"
    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.48, "half", algo_name$ + "  |  " + paramStr$ + "  |  Wet " + fixed$(dry_wet_percent, 0) + "%"
    Text: 0.02, "left", 0.20, "half", "Safety " + safeStr$ + "  |  Output " + outMode$ + "  |  " + fixed$(duration, 2) + " s / " + fixed$(sampleRate, 0) + " Hz / " + string$(numChannels) + " ch  |  peak " + fixed$(finalPeak, 3)

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

if modulator <> 0
    removeObject: modulator
endif

selectObject: result
if play_result
    Play
endif
selectObject: result
