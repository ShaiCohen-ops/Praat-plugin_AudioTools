# ============================================================
# Praat AudioTools - Amplitude-Varying_Ring_Modulation.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.8 (2026)
#
# Changelog v0.8 (2026):
#   - Rebuilt the Picture-window visualization to match the established
#     Praat AudioTools house style used by the library's analytical and
#     compositional dashboards: centred tool title, restrained metadata
#     subtitle, lettered panels, consistent outer/inner viewports,
#     pale-grey plotting fields, blue primary trajectory, red modulation
#     and warning accents, and a structured three-column result strip.
#   - Panel titles are now attached to their own viewports rather than
#     positioned in the global canvas, preventing drift and overlap when
#     the Picture window is resized or exported.
#   - Added an explicit Nyquist-risk region and carrier-status annotation.
#     The graph no longer suggests that the carrier is limited when it
#     actually continues beyond the displayed range.
#   - The tremolo curve now uses cycle-aware drawing density, so fast AM
#     settings are not visually under-sampled by a fixed 200-point grid.
#   - Visualization-only change: the audio Formula and all sound-affecting
#     parameters remain identical to v0.7.
#
# Changelog v0.7 (2026):
#   - Brought the script's validation and visualization conventions
#     in line with the rest of the library (cf. LZ-Inspired_Audio_
#     Variations.praat). No change to the audio-affecting math:
#     the carrier chirp, tremolo, and Formula call are unchanged
#     from v0.6, so output for a given parameter set is identical.
#   - Validation: the four range checks that previously called
#     exitScript (sweep exponent < 1, amplitude center out of
#     [0,1], amplitude rate >= Nyquist, scale peak > 1) now clamp
#     to a safe value and report the adjustment, matching the
#     warnLines$/"Adjustments:" pattern used elsewhere in the
#     library, rather than aborting the run. Only the structural
#     precondition (no Sound selected) still exits.
#   - Info window: single warnLines$ accumulator collects every
#     adjustment (including the pre-existing amplitude-depth
#     clamp) into one "Adjustments:" block instead of one-off
#     NOTE/WARNING lines scattered through the header.
#   - Visualization rebuilt on the library's outer+inner viewport
#     pattern with a title bar (preset/input/key params) and a
#     summary bar (output stats), aligned panel titles, and the
#     library's standard grey/blue/red panel palette.
#
# Changelog v0.6 (2026):
#   - Switched all modulation formulas to relative time (x - xmin),
#     so the chirp and tremolo timing no longer depend on the
#     selected Sound object's original start time.
#   - Added Nyquist-aware validation and reporting: the info window
#     now warns when a constant carrier already exceeds Nyquist, or
#     reports the crossover time t at which an accelerating chirp's
#     carrier will exceed it.
#   - Added native multichannel support: the ring-mod formula is
#     applied to every channel in a single Formula call, and channel
#     count is validated and reported rather than assumed to be mono.
#
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Ring modulation with frequency sweep (chirp) and amplitude
#   tremolo. Uses relative time (x - xmin) to guarantee consistent
#   modulation regardless of sound start time. Native multichannel
#   support with aliasing warning analysis.
# ============================================================

if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
originalName$ = selected$("Sound")

form Amplitude-Varying Ring Modulation v0.8
    comment Ring modulation with frequency chirp and amplitude tremolo.
    optionmenu Preset: 1
        option Manual
        option Subtle Modulation
        option Extreme Sweep
        option Fast Pulsing
        option Metallic
        option Alien Voice
        option Underwater Transmission
    comment === Carrier parameters ===
    positive Carrier_frequency 250
    comment Carrier frequency at t = 1s (f(t) = C * t^(E-1))
    positive Sweep_exponent 2
    comment Exponent E >= 1.0 (1 = fixed carrier, >1 = accelerating chirp)
    comment === Amplitude modulation ===
    positive Amplitude_rate 3
    real Amplitude_center 0.5
    real Amplitude_depth 0.5
    comment === Output options ===
    boolean Peak_normalize_output 0
    positive Scale_peak 0.99
    boolean Play_after_processing 1
    boolean Draw_modulation 1
endform

#=============================================================================
# APPLY PRESET OVERRIDES
#=============================================================================
# Each preset sets carrier, sweep, and amplitude-modulation parameters
# together so the result is a coherent character rather than an
# arbitrary combination the user would have to tune by hand.

if preset = 2
    # SubtleModulation — gentle, near-fixed carrier, slow tremolo
    carrier_frequency = 100
    sweep_exponent = 1.5
    amplitude_rate = 1
    amplitude_center = 0.7
    amplitude_depth = 0.3
    presetName$ = "Subtle"
elsif preset = 3
    # ExtremeSweep — fast-accelerating chirp, deep tremolo
    carrier_frequency = 500
    sweep_exponent = 3
    amplitude_rate = 5
    amplitude_center = 0.5
    amplitude_depth = 0.5
    presetName$ = "ExtremeSweep"
elsif preset = 4
    # FastPulse — moderate chirp, rapid amplitude pulsing
    carrier_frequency = 200
    sweep_exponent = 2
    amplitude_rate = 10
    amplitude_center = 0.6
    amplitude_depth = 0.4
    presetName$ = "FastPulse"
elsif preset = 5
    # Metallic — fixed carrier at A4, fast shallow tremolo
    carrier_frequency = 440
    sweep_exponent = 1.0
    amplitude_rate = 7
    amplitude_center = 0.8
    amplitude_depth = 0.2
    presetName$ = "Metallic"
elsif preset = 6
    # AlienVoice — mid-range chirp, moderate tremolo
    carrier_frequency = 150
    sweep_exponent = 2.5
    amplitude_rate = 4
    amplitude_center = 0.5
    amplitude_depth = 0.5
    presetName$ = "AlienVoice"
elsif preset = 7
    # Underwater — low, slow-sweeping carrier, slow deep tremolo
    carrier_frequency = 80
    sweep_exponent = 1.2
    amplitude_rate = 0.5
    amplitude_center = 0.6
    amplitude_depth = 0.4
    presetName$ = "Underwater"
else
    presetName$ = "Manual"
endif

#=============================================================================
# INITIALIZATION
#=============================================================================

selectObject: sound
duration = Get total duration
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

#=============================================================================
# PARAMETER VALIDATION  (clamp-and-report, library convention)
#=============================================================================
# Explicit checks instead of letting a nonsensical value silently
# misbehave downstream (frequency singularity at t=0, inverted
# envelope range, clipping, etc). Everything short of the missing-
# Sound precondition above is clamped to a safe value and reported
# in warnLines$ rather than aborting the run.

warnLines$ = ""

if sweep_exponent < 1.0
    warnLines$ = warnLines$ + "  ! Sweep exponent < 1.0 (frequency singularity at t=0) -> clamped to 1.0" + newline$
    sweep_exponent = 1.0
endif
if amplitude_center < 0.0
    warnLines$ = warnLines$ + "  ! Amplitude center < 0.0 -> clamped to 0.0" + newline$
    amplitude_center = 0.0
endif
if amplitude_center > 1.0
    warnLines$ = warnLines$ + "  ! Amplitude center > 1.0 -> clamped to 1.0" + newline$
    amplitude_center = 1.0
endif
if amplitude_rate >= nyquist
    safeRate = nyquist * 0.99
    warnLines$ = warnLines$ + "  ! Amplitude rate (" + fixed$(amplitude_rate, 1) + " Hz) >= Nyquist (" + fixed$(nyquist, 0) + " Hz) -> clamped to " + fixed$(safeRate, 1) + " Hz" + newline$
    amplitude_rate = safeRate
endif
if peak_normalize_output and scale_peak > 1.0
    warnLines$ = warnLines$ + "  ! Scale peak > 1.0 (would clip) -> clamped to 1.0" + newline$
    scale_peak = 1.0
endif

#=============================================================================
# BOUNDARY CLAMPING
#=============================================================================
# Clamp depth so the amplitude envelope stays strictly within [0, 1]
# rather than folding or clipping unexpectedly during processing.

origDepth = amplitude_depth
if amplitude_depth < 0
    amplitude_depth = 0
endif
if amplitude_center - amplitude_depth < 0
    amplitude_depth = amplitude_center
endif
if amplitude_center + amplitude_depth > 1.0
    amplitude_depth = 1.0 - amplitude_center
endif

if amplitude_depth <> origDepth
    warnLines$ = warnLines$ + "  ! Amplitude depth (" + fixed$(origDepth, 2) + ") would push the envelope outside [0, 1] -> clamped to " + fixed$(amplitude_depth, 2) + newline$
endif

ampMin = amplitude_center - amplitude_depth
ampMax = amplitude_center + amplitude_depth

#=============================================================================
# INFO HEADER
#=============================================================================

clearinfo
writeInfoLine: "=== Amplitude-Varying Ring Modulation v0.8 ==="
appendInfoLine: "Source: ", originalName$, " (", fixed$(duration, 2), " s)"
appendInfoLine: "Preset: ", presetName$
appendInfoLine: ""

# Instantaneous frequency f(t) = C * t^(E-1)
if sweep_exponent = 1.0
    startFreq = carrier_frequency
    endFreq = carrier_frequency
else
    startFreq = 0
    endFreq = carrier_frequency * (duration ^ (sweep_exponent - 1.0))
endif

appendInfoLine: "Carrier (at t=1s): ", carrier_frequency, " Hz"
appendInfoLine: "Sweep exponent:    ", sweep_exponent
appendInfoLine: "Instantaneous Freq: ", fixed$(startFreq, 1), " Hz -> ", fixed$(endFreq, 1), " Hz"

# Aliasing analysis (also feeds the visualization status strip)
aliasRisk = 0
aliasStatus$ = "Carrier trajectory remains below Nyquist"
if sweep_exponent = 1.0 and carrier_frequency >= nyquist
    aliasRisk = 1
    aliasStatus$ = "Carrier above Nyquist throughout"
    warnLines$ = warnLines$ + "  ! Constant carrier (" + fixed$(carrier_frequency, 0) + " Hz) exceeds Nyquist (" + fixed$(nyquist, 0) + " Hz) and will alias throughout" + newline$
elsif endFreq > nyquist
    aliasRisk = 1
    t_nyq = (nyquist / carrier_frequency) ^ (1.0 / (sweep_exponent - 1.0))
    aliasStatus$ = "Carrier crosses Nyquist at " + fixed$(t_nyq, 3) + " s"
    warnLines$ = warnLines$ + "  ! Carrier exceeds Nyquist (" + fixed$(nyquist, 0) + " Hz) before the sound ends" + newline$
    warnLines$ = warnLines$ + "    (crossover at t = " + fixed$(t_nyq, 3) + " s; sideband aliasing from source content may begin earlier)" + newline$
endif

appendInfoLine: "Amplitude rate:     ", amplitude_rate, " Hz"
appendInfoLine: "Amplitude range:    ", fixed$(ampMin, 2), " - ", fixed$(ampMax, 2)
appendInfoLine: "Channels:           ", numChannels

if warnLines$ <> ""
    appendInfoLine: ""
    appendInfoLine: "Adjustments:"
    appendInfo: warnLines$
endif
appendInfoLine: ""

#=============================================================================
# PROCEDURE: DRAW MODULATION VISUALIZATION
#=============================================================================
# Praat AudioTools house style:
#   - centred tool title + restrained metadata line
#   - lettered analytical panels with attached titles
#   - pale-grey plotting fields
#   - blue primary trajectory, red modulation/warning accents
#   - result/status strip added after rendering

procedure drawModulation
    Erase all
    Select outer viewport: 0, 8, 0, 8

    # Smart time ticks
    if duration > 30
        timeTickInterval = 5
    elsif duration > 15
        timeTickInterval = 2
    elsif duration > 6
        timeTickInterval = 1
    elsif duration > 2
        timeTickInterval = 0.5
    else
        timeTickInterval = 0.25
    endif

    # ----------------------------------------------------------
    # TITLE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.00, 0.58
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##Amplitude-Varying Ring Modulation##"

    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.10, "half",
        ... "[" + presetName$ + "]  " + originalName$
        ... + "  |  " + fixed$(duration, 2) + " s"
        ... + "  |  C@1s " + fixed$(carrier_frequency, 0) + " Hz"
        ... + "  |  E " + fixed$(sweep_exponent, 2)
        ... + "  |  AM " + fixed$(amplitude_rate, 1) + " Hz"
        ... + "  |  " + string$(numChannels) + " ch"

    # ----------------------------------------------------------
    # PANEL A — CARRIER-FREQUENCY TRAJECTORY
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0.76, 3.55
    Select inner viewport: 0.78, 7.72, 1.00, 3.31

    maxFreqDisplay = endFreq * 1.10
    if maxFreqDisplay < carrier_frequency * 1.35
        maxFreqDisplay = carrier_frequency * 1.35
    endif
    if maxFreqDisplay < nyquist * 0.12
        maxFreqDisplay = nyquist * 0.12
    endif
    if maxFreqDisplay > nyquist * 1.12
        maxFreqDisplay = nyquist * 1.12
    endif
    if maxFreqDisplay <= 0
        maxFreqDisplay = max(100, carrier_frequency * 1.5)
    endif

    if maxFreqDisplay > 20000
        freqTickInterval = 5000
    elsif maxFreqDisplay > 10000
        freqTickInterval = 2000
    elsif maxFreqDisplay > 5000
        freqTickInterval = 1000
    elsif maxFreqDisplay > 2000
        freqTickInterval = 500
    elsif maxFreqDisplay > 500
        freqTickInterval = 100
    else
        freqTickInterval = 50
    endif

    Axes: 0, duration, 0, maxFreqDisplay
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, maxFreqDisplay

    # Risk field above Nyquist: warning context, not a processing clamp.
    if nyquist < maxFreqDisplay
        Paint rectangle: "{0.99, 0.93, 0.93}", 0, duration, nyquist, maxFreqDisplay
        Colour: "{0.78, 0.20, 0.20}"
        Dotted line
        Draw line: 0, nyquist, duration, nyquist
        Solid line
        Font size: 7
        Text: duration * 0.015, "left", nyquist * 1.015, "bottom",
            ... "Nyquist  " + fixed$(nyquist, 0) + " Hz"
    endif

    # Carrier trajectory f(t) = C * t^(E-1).
    Colour: "{0.20, 0.40, 0.80}"
    Line width: 2
    numCarrierPoints = 400
    curveExceededDisplay = 0

    for iPoint from 1 to numCarrierPoints - 1
        t1 = (iPoint - 1) * duration / (numCarrierPoints - 1)
        t2 = iPoint * duration / (numCarrierPoints - 1)

        if sweep_exponent = 1.0
            freq1 = carrier_frequency
            freq2 = carrier_frequency
        else
            freq1 = carrier_frequency * (t1 ^ (sweep_exponent - 1.0))
            freq2 = carrier_frequency * (t2 ^ (sweep_exponent - 1.0))
        endif

        if freq1 > maxFreqDisplay or freq2 > maxFreqDisplay
            curveExceededDisplay = 1
        endif

        # Draw up to the display boundary, then stop. This avoids a false
        # horizontal plateau that could be mistaken for frequency limiting.
        if freq1 <= maxFreqDisplay or freq2 <= maxFreqDisplay
            f1Draw = min(freq1, maxFreqDisplay)
            f2Draw = min(freq2, maxFreqDisplay)
            Draw line: t1, f1Draw, t2, f2Draw
        endif
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "A  Carrier-frequency trajectory"
    Font size: 7
    Text bottom: "yes", "Time from sound start (s)"
    Text left: "yes", "Frequency (Hz)"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, freqTickInterval, "yes", "yes", "no"

    # Compact panel annotation.
    Font size: 7
    if aliasRisk
        Colour: "{0.78, 0.20, 0.20}"
    else
        Colour: "{0.28, 0.28, 0.36}"
    endif
    Text: duration * 0.985, "right", maxFreqDisplay * 0.92, "half", aliasStatus$

    if curveExceededDisplay
        Colour: "{0.78, 0.20, 0.20}"
        Text: duration * 0.985, "right", maxFreqDisplay * 0.82, "half",
            ... "trajectory continues above display range"
    endif

    # ----------------------------------------------------------
    # PANEL B — AMPLITUDE TREMOLO ENVELOPE
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.78, 6.48
    Select inner viewport: 0.78, 7.72, 4.02, 6.24
    Axes: 0, duration, 0, 1.05
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, duration, 0, 1.05

    # Valid gain span.
    Paint rectangle: "{0.89, 0.94, 0.98}", 0, duration, ampMin, ampMax

    # Centre reference.
    Colour: "{0.55, 0.55, 0.55}"
    Dotted line
    Draw line: 0, amplitude_center, duration, amplitude_center
    Solid line

    # Cycle-aware drawing density: at least 32 segments per AM cycle,
    # bounded to keep the Picture-window draw time reasonable.
    ampCycles = amplitude_rate * duration
    numAmpPoints = ceiling(ampCycles * 32) + 1
    if numAmpPoints < 400
        numAmpPoints = 400
    endif
    if numAmpPoints > 6000
        numAmpPoints = 6000
    endif

    Colour: "{0.80, 0.30, 0.30}"
    Line width: 2
    for iPoint from 1 to numAmpPoints - 1
        t1 = (iPoint - 1) * duration / (numAmpPoints - 1)
        t2 = iPoint * duration / (numAmpPoints - 1)
        amp1 = amplitude_center + amplitude_depth * sin(2 * pi * amplitude_rate * t1)
        amp2 = amplitude_center + amplitude_depth * sin(2 * pi * amplitude_rate * t2)
        Draw line: t1, amp1, t2, amp2
    endfor

    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "B  Post-ring-modulation amplitude envelope"
    Font size: 7
    Text bottom: "yes", "Time from sound start (s)"
    Text left: "yes", "Gain multiplier"
    Marks bottom every: 1, timeTickInterval, "yes", "yes", "no"
    Marks left every: 1, 0.2, "yes", "yes", "no"

    # Legend-like annotation inside the field.
    Font size: 7
    Colour: "{0.28, 0.28, 0.36}"
    Text: duration * 0.985, "right", 0.98, "half",
        ... "range " + fixed$(ampMin, 2) + "-" + fixed$(ampMax, 2)
        ... + "  |  centre " + fixed$(amplitude_center, 2)
        ... + "  |  depth " + fixed$(amplitude_depth, 2)

    Font size: 10
    Colour: "Black"
    Line width: 1
endproc

if draw_modulation
    @drawModulation
endif

#=============================================================================
# MAIN PROCESSING (native multichannel via Praat Formula)
#=============================================================================
appendInfoLine: "Processing audio..."

selectObject: sound
finalOutput = Copy: originalName$ + "_ringmod_" + presetName$

selectObject: finalOutput

# Formula strings built with relative time (x - xmin), applied to all
# channels at once via a single Formula call.
relTime$ = "(x - xmin)"
carrierTerm$ = "sin(2 * pi * " + string$(carrier_frequency) + " * " + relTime$ + "^" + string$(sweep_exponent) + " / " + string$(sweep_exponent) + ")"
ampTerm$ = "(" + string$(amplitude_center) + " + " + string$(amplitude_depth) + " * sin(2 * pi * " + string$(amplitude_rate) + " * " + relTime$ + "))"

Formula: "self * " + carrierTerm$ + " * " + ampTerm$

if peak_normalize_output
    Scale peak: scale_peak
endif

#=============================================================================
# FINAL REPORT
#=============================================================================

selectObject: finalOutput
outName$ = selected$("Sound")
outPeak = Get absolute extremum: 0, 0, "None"

if peak_normalize_output
    normalizedLabel$ = "yes (" + fixed$(scale_peak, 2) + ")"
else
    normalizedLabel$ = "no"
endif

# ----------------------------------------------------------
# RESULT / STATUS STRIP
# ----------------------------------------------------------
if draw_modulation
    Select outer viewport: 0, 8, 6.67, 7.70
    Select inner viewport: 0.55, 7.72, 6.72, 7.65
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    # Column separators.
    Colour: "{0.78, 0.78, 0.78}"
    Draw line: 0.355, 0.10, 0.355, 0.90
    Draw line: 0.695, 0.10, 0.695, 0.90

    # OUTPUT
    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.02, "left", 0.78, "half", "OUTPUT"
    Font size: 6
    Colour: "{0.20, 0.20, 0.20}"
    Text: 0.02, "left", 0.45, "half", outName$
    Text: 0.02, "left", 0.20, "half",
        ... "peak " + fixed$(outPeak, 3) + "  |  normalized " + normalizedLabel$

    # PROCESS
    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.38, "left", 0.78, "half", "PROCESS"
    Font size: 6
    Colour: "{0.20, 0.20, 0.20}"
    Text: 0.38, "left", 0.45, "half", "input x chirped carrier x AM envelope"
    Text: 0.38, "left", 0.20, "half",
        ... fixed$(startFreq, 1) + " -> " + fixed$(endFreq, 1) + " Hz"
        ... + "  |  AM " + fixed$(amplitude_rate, 1) + " Hz"

    # STATUS
    Font size: 7
    Colour: "{0.35, 0.35, 0.45}"
    Text: 0.72, "left", 0.78, "half", "STATUS"
    Font size: 6
    if aliasRisk
        Colour: "{0.78, 0.20, 0.20}"
    else
        Colour: "{0.20, 0.40, 0.80}"
    endif
    Text: 0.72, "left", 0.45, "half", aliasStatus$

    if warnLines$ <> ""
        Colour: "{0.55, 0.30, 0.20}"
        Text: 0.72, "left", 0.20, "half", "parameter adjustments reported in Info"
    else
        Colour: "{0.28, 0.28, 0.36}"
        Text: 0.72, "left", 0.20, "half", "no parameter adjustments"
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10

    # Restore the complete canvas as the active export/inspection region.
    Select outer viewport: 0, 8, 0, 8
endif

appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output sound: ", outName$
appendInfoLine: "Channels:     ", numChannels
appendInfoLine: "Peak:         ", fixed$(outPeak, 3)

if draw_modulation
    appendInfoLine: "Visualization generated in Picture window."
endif

if play_after_processing
    appendInfoLine: "Playing..."
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput
