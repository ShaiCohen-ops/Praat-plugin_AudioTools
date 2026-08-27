# ============================================================
# Praat AudioTools - Classic FIR Filter Bank.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - log-axis response, measured specs
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Classic FIR filter bank with linear phase (zero phase distortion).
#   Implements windowed-sinc design with multiple window functions.
#
# Filter types:
#   - Windowed-sinc: Rectangular, Hamming, Hann, Blackman, Kaiser, Bartlett
#   - Moving Average: Simple smoothing filter
#   - Raised-Cosine: Pulse shaping filter (telecommunications)
#   - Hilbert Transform: 90-degree phase shifter
#
# Key advantage over IIR:
#   LINEAR PHASE - no phase distortion, symmetric impulse response
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Changelog v0.5 (2026):
#   - VISUALIZATION AND REPORTING ONLY; filter design, convolution,
#     dry/wet mixing, scaling and object management are byte-for-byte
#     unchanged. No coefficient is altered.
#   - LOG FREQUENCY AXIS, AND A LOG-SPACED EVALUATION GRID. v0.4.1
#     evaluated 512 LINEARLY spaced points up to Nyquist - one point
#     every 43 Hz at 44.1 kHz - and plotted them on a linear axis. The
#     "Rumble Filter (80 Hz HP)" preset therefore had its entire
#     transition described by about two samples and drawn in the
#     leftmost 1% of the panel: the filter was literally not visible.
#   - DRAWING-FRAME FIX. Praat derives a panel's inner margins from the
#     CURRENT font size, so a font change made AFTER "Select inner
#     viewport" silently re-derives a wider frame. v0.4.1 did this in
#     the title strip, and the panels never re-established it, so the
#     magnitude curve was drawn starting 0.35 in LEFT of its own axis
#     box and the phase curve ran 0.2 in below it. Measured on the
#     rendered PNG. Every panel now sets its font first and re-issues
#     "Select inner viewport" + "Axes" between drawing groups.
#   - Axis marks were drawn AFTER "Text left"/"Text top", which leave
#     the drawing frame on the outer viewport, so the tick numbers were
#     offset from the box they belong to. Garnish now comes last, on a
#     freshly re-established frame.
#   - PHASE PANEL REPLACED. v0.4.1 plotted WRAPPED phase: a sawtooth of
#     roughly fifty teeth that demonstrates nothing. The panel now shows
#     the DEVIATION from ideal linear phase, wrapped into (-180, 180].
#     A linear-phase FIR sits at 0, flipping to +/-180 only where the
#     amplitude function changes sign. Unwrapping was tried first and
#     does not work on a log grid: at 20 kHz consecutive points are
#     235 Hz apart, which for N = 101 is 959 degrees of true phase per
#     step, so the +/-180 unwrap rule aliases and loses turns.
#   - NEW measured specification panel: -6 dB edge against the requested
#     cutoff, passband variation, stopband rejection, group delay and a
#     linear-phase check made on the COEFFICIENTS (symmetric or
#     antisymmetric), not inferred from a picture.
#   - NEW "filter too short" warning. A windowed-sinc's transition width
#     is set by N and the window, not by the cutoff. Two shipped presets
#     trip it: "Rumble Filter (80 Hz HP)" (Blackman N=255 has a
#     476 Hz half-transition, so the -6 dB edge lands near 206 Hz, not
#     80 Hz) and "Bandpass Voice (300-3400 Hz)" (Hamming N=127, lower
#     edge realised near 376 Hz). Both are real limitations of those
#     presets and were previously invisible.
#   - Impulse response: tip dots are drawn in MILLIMETRES. v0.4.1 asked
#     for "Paint circle: ..., 0.008" with the x axis running 0 to N-1,
#     i.e. a radius of 0.008 SAMPLES - about a sixth of a pixel at
#     300 dpi. Those dots had never rendered. Both axes now carry marks;
#     v0.4.1 labelled them "h[n]" and "Sample" and drew no numbers at
#     all. The centre tap and the largest remaining tap are stated,
#     since a highpass impulse is a near-unit spike whose other taps are
#     invisible at linear scale.
#   - Panels are stacked in sequence, so switching one off closes the
#     gap. With plot_responses = 0 v0.4.1 left the top four inches blank.
#   - Own frequency tick labels, so 20000 reads "20k" and not "2*10^4".
#   - Object names escaped for _ ^ # % markup before drawing.
#   - The Info report now quotes measured values alongside requested
#     ones. Reporting only; the audio is unchanged.
#
# Changelog v0.4.1 (2026):
#   - CORRECTED WINDOWED-SINC CUTOFF NORMALIZATION. wc and wc2 are
#     normalized to Nyquist (fc / (fs/2)), so the ideal lowpass must use
#     h[0] = wc and sin(pi*wc*m)/(pi*m). The previous extra factor of two
#     placed the transition near twice the requested cutoff. The same fix
#     is applied to the second lowpass used by bandpass/bandstop.
#   - CORRECTED RAISED-COSINE UNITS. The symbol interval is now
#     T = 1/(2*cutoff_frequency) seconds and is evaluated against
#     t = m/fs. The removable singularity at t = +/-T/(2*alpha) uses the
#     analytic limit. Cutoff_frequency is therefore the centre of the
#     raised-cosine transition (about -6 dB in amplitude response).
#   - Raised-Cosine bandpass/bandstop now build both edges from the same
#     raised-cosine family instead of mixing a raised-cosine lower edge
#     with a windowed-sinc upper edge.
#   - Multichannel input now uses Praat's native multichannel convolution
#     with the mono FIR impulse, preserving every channel; the previous
#     non-mono branch silently returned only channels 1 and 2.
#   - Moving Average is explicitly limited to Lowpass/Highpass because it
#     has no user-defined cutoff pair from which to construct BP/BS.
#   - Visualization behavior is unchanged.
#
# Changelog v0.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.3:
#   - Rewrote the dry/wet mix. The linear-phase FIR delays the wet by
#     m_center samples; the dry is now read with the same delay so the
#     mix is phase-coherent (no comb). Unified mono/stereo via indexed
#     access (row=channel), which also fixes a stereo crash where the
#     dry object was renamed by Extract part but still referenced by its
#     old name. Default dry_wet_mix=1 is unchanged (block is skipped).
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Classic FIR Filter Bank v0.5
    optionmenu Preset: 1
        option Custom
        option Speech Lowpass (3.5 kHz, Hamming)
        option Music Lowpass (8 kHz, Blackman)
        option Rumble Filter (80 Hz HP)
        option Bandpass Voice (300-3400 Hz)
        option Hilbert 90deg Phase
    optionmenu Filter_type: 3
        option Windowed-sinc (Rectangular)
        option Windowed-sinc (Hamming)
        option Windowed-sinc (Hann)
        option Windowed-sinc (Blackman)
        option Windowed-sinc (Kaiser)
        option Windowed-sinc (Bartlett)
        option Moving Average
        option Raised-Cosine
        option Hilbert Transform
    optionmenu Filter_mode: 1
        option Lowpass
        option Highpass
        option Bandpass
        option Bandstop
    integer filter_length 101
    positive cutoff_frequency 1000
    positive cutoff_frequency_2 2000
    positive kaiser_beta 5.0
    positive rolloff_factor 0.5
    real dry_wet_mix 1.0
    positive scale_peak 0.95
    boolean plot_responses 1
    boolean plot_impulse 1
    boolean apply_filter 1
    boolean play_after_processing 1
endform

# ============================================================
# Apply presets
# ============================================================
if preset$ = "Speech Lowpass (3.5 kHz, Hamming)"
    filter_type = 2
    filter_mode = 1
    filter_length = 101
    cutoff_frequency = 3500
elif preset$ = "Music Lowpass (8 kHz, Blackman)"
    filter_type = 4
    filter_mode = 1
    filter_length = 127
    cutoff_frequency = 8000
elif preset$ = "Rumble Filter (80 Hz HP)"
    filter_type = 4
    filter_mode = 2
    filter_length = 255
    cutoff_frequency = 80
elif preset$ = "Bandpass Voice (300-3400 Hz)"
    filter_type = 2
    filter_mode = 3
    filter_length = 127
    cutoff_frequency = 300
    cutoff_frequency_2 = 3400
elif preset$ = "Hilbert 90deg Phase"
    filter_type = 9
    filter_mode = 1
    filter_length = 127
endif

# ============================================================
# Validate input
# ============================================================
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
selectObject: sound
originalName$ = selected$("Sound")
sampleRate = Get sampling frequency
numChannels = Get number of channels
nyquist = sampleRate / 2

# Ensure odd length for symmetry
if filter_length mod 2 = 0
    filter_length += 1
endif

if filter_length < 3
    exitScript: "Filter length must be at least 3"
endif

if cutoff_frequency >= nyquist
    exitScript: "Cutoff must be below Nyquist (" + string$(nyquist) + " Hz)"
endif

if filter_mode >= 3
    if cutoff_frequency_2 >= nyquist
        exitScript: "Second cutoff must be below Nyquist"
    endif
    if cutoff_frequency >= cutoff_frequency_2
        exitScript: "First cutoff must be lower than second"
    endif
endif

# Moving Average has no frequency parameter; a two-edge BP/BS design would
# otherwise mix unrelated filter families and make the cutoff fields false.
if filter_type = 7 and filter_mode >= 3
    exitScript: "Moving Average supports Lowpass or Highpass only; Bandpass/Bandstop require a cutoff-based filter type."
endif

# Standard raised-cosine rolloff range. The form's positive field already
# enforces alpha > 0.
if filter_type = 8 and rolloff_factor > 1
    exitScript: "Raised-Cosine rolloff_factor must be greater than 0 and at most 1."
endif

# Clamp dry/wet
if dry_wet_mix < 0
    dry_wet_mix = 0
endif
if dry_wet_mix > 1
    dry_wet_mix = 1
endif

# Filter type name
if filter_type = 1
    filterTypeName$ = "Sinc-Rect"
elif filter_type = 2
    filterTypeName$ = "Sinc-Hamming"
elif filter_type = 3
    filterTypeName$ = "Sinc-Hann"
elif filter_type = 4
    filterTypeName$ = "Sinc-Blackman"
elif filter_type = 5
    filterTypeName$ = "Sinc-Kaiser"
elif filter_type = 6
    filterTypeName$ = "Sinc-Bartlett"
elif filter_type = 7
    filterTypeName$ = "MovingAvg"
elif filter_type = 8
    filterTypeName$ = "RaisedCos"
else
    filterTypeName$ = "Hilbert"
endif

if filter_mode = 1
    filterModeName$ = "LP"
elif filter_mode = 2
    filterModeName$ = "HP"
elif filter_mode = 3
    filterModeName$ = "BP"
else
    filterModeName$ = "BS"
endif

# Normalized cutoff
wc = cutoff_frequency / nyquist
wc2 = cutoff_frequency_2 / nyquist
m_center = (filter_length - 1) / 2

uniqueID$ = string$(randomInteger(10000, 99999))

# ============================================================
# Report
# ============================================================
writeInfoLine: "Classic FIR Filter Bank"
appendInfoLine: "======================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Filter: ", filterTypeName$, " ", filterModeName$
appendInfoLine: "Length: ", filter_length, " samples"
if filter_mode <= 2
    appendInfoLine: "Cutoff: ", cutoff_frequency, " Hz"
else
    appendInfoLine: "Cutoff: ", cutoff_frequency, " - ", cutoff_frequency_2, " Hz"
endif
appendInfoLine: "Linear phase: YES"
appendInfoLine: ""

# ============================================================
# Design filter
# ============================================================
appendInfoLine: "Designing filter..."

# Initialize impulse response array
for n from 0 to filter_length - 1
    h[n] = 0
endfor

if filter_type >= 1 and filter_type <= 6
    @designWindowedSinc
elif filter_type = 7
    @designMovingAverage
elif filter_type = 8
    @designRaisedCosine
elif filter_type = 9
    @designHilbert
endif

# Transform for HP/BP/BS
if filter_type <> 9
    if filter_mode = 2
        @transformHighpass
    elif filter_mode = 3
        @transformBandpass
    elif filter_mode = 4
        @transformBandstop
    endif
endif

appendInfoLine: "Filter design complete."

# ============================================================
# Apply filter
# ============================================================
if apply_filter
    appendInfoLine: ""
    appendInfoLine: "Applying filter (fast convolution)..."
    
    selectObject: sound
    
    # Praat can convolve a multichannel Sound directly with a mono FIR
    # impulse response, applying the same coefficients independently to
    # every channel. This preserves any channel count and the exact
    # convolution time domain/sample count without manual reassembly.
    @applyFIRFilter: sound
    filtered = selected("Sound")
    
    selectObject: filtered
    
    # Dry/wet mix (only when < 1). The linear-phase FIR delays the wet by
    # m_center samples, so the dry is read with the same delay to stay
    # phase-coherent. Indexed access returns 0 out of range (covering the
    # leading latency and the convolution tail) and works for any channel
    # count via the row=channel index.
    if dry_wet_mix < 1
        groupDelay = round(m_center)
        selectObject: sound
        dryAligned = Copy: "dryAligned_" + uniqueID$
        selectObject: filtered
        Formula: "dry_wet_mix * self + (1 - dry_wet_mix) * object[dryAligned, row, col - groupDelay]"
        removeObject: dryAligned
    endif
    
    selectObject: filtered
    Scale peak: scale_peak
    Rename: originalName$ + "_" + filterTypeName$ + "_" + filterModeName$
    
    appendInfoLine: "Done!"
endif

# ============================================================
# Measure the designed filter
# ============================================================
# Always computed, so the specification panel is available whichever
# plots are switched on, and so the Info report can quote real numbers
# instead of only the requested ones.
@analyseResponse

appendInfoLine: ""
appendInfoLine: "Measured response:"
if hasCutoffMeasure
    appendInfoLine: "  -6 dB point: ", edgeReport$
endif
if hasPassband
    appendInfoLine: "  Passband variation (to 0.6x edge): ", fixed$(pbRipple, 2), " dB"
endif
if hasStopband
    appendInfoLine: "  Stopband rejection: ", fixed$(-sbMax, 1), " dB"
endif
if linearPhase
    appendInfoLine: "  Linear phase: YES (coefficients ", symKind$,
    ... " to ", fixed$(symRel, 12), " of peak tap)"
else
    appendInfoLine: "  Linear phase: NO - coefficients are neither symmetric"
    appendInfoLine: "                nor antisymmetric (", fixed$(symRel, 6), ")"
endif
if hasTransEst
    appendInfoLine: "  Transition width (window/N limit): ", fixed$(transEst, 0), " Hz"
endif
if tooShort
    appendInfoLine: "  WARNING: N = ", filter_length, " is too short for this cutoff."
    appendInfoLine: "           The transition is wider than the band requested, so the"
    appendInfoLine: "           realised edge differs from the one asked for. Increase N."
endif
appendInfoLine: "  Max deviation from linear phase: ", fixed$(maxPhaseDev, 4), " deg"
appendInfoLine: "  Group delay: ", fixed$(m_center, 1), " samples (",
... fixed$(m_center / sampleRate * 1000, 3), " ms)"

# ============================================================
# Plot responses
# ============================================================
if plot_responses or plot_impulse
    Erase all

    # Bands are stacked in sequence, so switching a plot off closes the
    # gap instead of leaving a hole. v0.4.1 used fixed viewports, so
    # plot_responses = 0 with plot_impulse = 1 left the top four inches
    # of the page blank.
    py = 0.62
    if plot_responses
        magTop = py + 0.25
        magBot = py + 2.15
        py = py + 2.65
        phTop = py + 0.25
        phBot = py + 1.55
        py = py + 2.10
    endif
    if plot_impulse
        impTop = py + 0.25
        impBot = py + 1.85
        py = py + 2.35
    endif
    stripTop = py + 0.10
    stripBot = py + 1.35
    pageHeight = py + 1.60

    Select outer viewport: 0, 8, 0, pageHeight

    # === TITLE ===
    # Font size BEFORE the viewport selection. Praat derives a panel's
    # inner margins from the CURRENT font, so a font change made after
    # the selection silently re-derives a wider frame and everything
    # drawn next lands outside the axis box - which is why the v0.4.1
    # magnitude curve started 0.35 in left of its own frame and the
    # phase curve ran 0.2 in below it.
    @sanitizeText: originalName$
    vizName$ = sanitizeText.out$

    Font size: 12
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Classic FIR Filter Bank v0.5##"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + filterTypeName$ +
    ... " " + filterModeName$ + " | N = " + string$(filter_length)

    if plot_responses
        @plotMagnitude
        @plotPhase
    endif
    if plot_impulse
        @plotImpulse
    endif
    @plotStrip

    # Restore the complete page. "Save as ... PNG" and the Picture
    # window's Save/Copy export the CURRENT viewport selection, so
    # ending on the bottom strip would export only that strip.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# Finish
# ============================================================
if apply_filter
    selectObject: filtered
    
    if play_after_processing
        Play
    endif
endif

appendInfoLine: ""
appendInfoLine: "======================="
appendInfoLine: "Complete!"

# ============================================================
# PROCEDURES
# ============================================================

procedure designWindowedSinc
    for n from 0 to filter_length - 1
        m = n - m_center
        
        # wc is normalized to Nyquist: wc = fc / (fs/2).
        # Therefore the ideal lowpass is wc*sinc(wc*m).
        if m = 0
            h[n] = wc
        else
            h[n] = sin(pi * wc * m) / (pi * m)
        endif
        
        # Window function
        if filter_type = 1
            w = 1
        elif filter_type = 2
            w = 0.54 - 0.46 * cos(2 * pi * n / (filter_length - 1))
        elif filter_type = 3
            w = 0.5 - 0.5 * cos(2 * pi * n / (filter_length - 1))
        elif filter_type = 4
            w = 0.42 - 0.5 * cos(2 * pi * n / (filter_length - 1)) + 0.08 * cos(4 * pi * n / (filter_length - 1))
        elif filter_type = 5
            @besselI0: kaiser_beta
            i0_beta = besselI0.result
            arg = kaiser_beta * sqrt(1 - (2*n/(filter_length-1) - 1)^2)
            @besselI0: arg
            w = besselI0.result / i0_beta
        elif filter_type = 6
            w = 1 - abs(2*n/(filter_length-1) - 1)
        endif
        
        h[n] = h[n] * w
    endfor
    
    # Normalize DC gain
    sum = 0
    for n from 0 to filter_length - 1
        sum += h[n]
    endfor
    if abs(sum) > 0.0001
        for n from 0 to filter_length - 1
            h[n] = h[n] / sum
        endfor
    endif
endproc

procedure designMovingAverage
    for n from 0 to filter_length - 1
        h[n] = 1 / filter_length
    endfor
endproc

procedure designRaisedCosine
    alpha = rolloff_factor
    # cutoff_frequency is the centre of the raised-cosine transition:
    # fc = 1/(2*T), so T is in seconds and matches t = m/sampleRate.
    t_symbol = 1 / (2 * cutoff_frequency)
    singular_t = t_symbol / (2 * alpha)
    singular_tol = 0.25 / sampleRate
    
    for n from 0 to filter_length - 1
        m = n - m_center
        t = m / sampleRate
        
        if m = 0
            h[n] = 1 / t_symbol
        elif alpha > 0 and abs(abs(t) - singular_t) <= singular_tol
            # Analytic limit of (1/T)*sinc(t/T)*cos(pi*alpha*t/T)
            # divided by (1-(2*alpha*t/T)^2) at t = +/-T/(2*alpha).
            h[n] = (1 / t_symbol) * (alpha / 2) * sin(pi / (2 * alpha))
        else
            sincPart = sin(pi * t / t_symbol) / (pi * t / t_symbol)
            cosPart = cos(pi * alpha * t / t_symbol)
            denom = 1 - (2 * alpha * t / t_symbol)^2
            
            if abs(denom) > 1e-12
                h[n] = (1 / t_symbol) * sincPart * cosPart / denom
            else
                # This branch is only a numerical safeguard; the sampled
                # singularity is handled by the analytic-limit branch above.
                h[n] = (1 / t_symbol) * (alpha / 2) * sin(pi / (2 * alpha))
            endif
        endif
    endfor
    
    # Normalize
    sum = 0
    for n from 0 to filter_length - 1
        sum += h[n]
    endfor
    if abs(sum) > 0.0001
        for n from 0 to filter_length - 1
            h[n] = h[n] / sum
        endfor
    endif
endproc

procedure designHilbert
    for n from 0 to filter_length - 1
        m = n - m_center
        
        if m = 0
            h[n] = 0
        elif m mod 2 = 0
            h[n] = 0
        else
            h[n] = 2 / (pi * m)
        endif
    endfor
    
    # Apply Hamming window
    for n from 0 to filter_length - 1
        w = 0.54 - 0.46 * cos(2 * pi * n / (filter_length - 1))
        h[n] = h[n] * w
    endfor
endproc

procedure besselI0: .x
    .sum = 1
    .term = 1
    
    for .k from 1 to 25
        .term = .term * (.x / 2)^2 / (.k^2)
        .sum = .sum + .term
        
        if abs(.term) < 1e-10
            .k = 26
        endif
    endfor
    
    .result = .sum
endproc

procedure transformHighpass
    for n from 0 to filter_length - 1
        h[n] = -h[n]
    endfor
    h[m_center] = h[m_center] + 1
endproc

procedure transformBandpass
    if filter_type = 8
        # h[] already contains the lower-cutoff Raised-Cosine. Preserve it,
        # design the upper-cutoff Raised-Cosine with the same rolloff, then
        # subtract LP(low) from LP(high).
        for n from 0 to filter_length - 1
            hLow[n] = h[n]
        endfor
        cutoffSave = cutoff_frequency
        cutoff_frequency = cutoff_frequency_2
        @designRaisedCosine
        cutoff_frequency = cutoffSave
        for n from 0 to filter_length - 1
            h[n] = h[n] - hLow[n]
        endfor
    else
        # Windowed-sinc second lowpass at wc2. Moving Average BP/BS is
        # rejected during validation, so only cutoff-based designs arrive
        # here.
        for n from 0 to filter_length - 1
            m = n - m_center
            
            # wc2 is also normalized to Nyquist.
            if m = 0
                h2[n] = wc2
            else
                h2[n] = sin(pi * wc2 * m) / (pi * m)
            endif
            
            # Same window as original
            if filter_type = 1
                w = 1
            elif filter_type = 2
                w = 0.54 - 0.46 * cos(2 * pi * n / (filter_length - 1))
            elif filter_type = 3
                w = 0.5 - 0.5 * cos(2 * pi * n / (filter_length - 1))
            elif filter_type = 4
                w = 0.42 - 0.5 * cos(2 * pi * n / (filter_length - 1)) + 0.08 * cos(4 * pi * n / (filter_length - 1))
            elif filter_type = 5
                @besselI0: kaiser_beta
                i0_beta = besselI0.result
                arg = kaiser_beta * sqrt(1 - (2*n/(filter_length-1) - 1)^2)
                @besselI0: arg
                w = besselI0.result / i0_beta
            elif filter_type = 6
                w = 1 - abs(2*n/(filter_length-1) - 1)
            else
                w = 1
            endif
            
            h2[n] = h2[n] * w
        endfor
        
        # Normalize h2
        sum2 = 0
        for n from 0 to filter_length - 1
            sum2 += h2[n]
        endfor
        if abs(sum2) > 0.0001
            for n from 0 to filter_length - 1
                h2[n] = h2[n] / sum2
            endfor
        endif
        
        # Bandpass = LP(wc2) - LP(wc)
        for n from 0 to filter_length - 1
            h[n] = h2[n] - h[n]
        endfor
    endif
endproc

procedure transformBandstop
    # First get bandpass
    @transformBandpass
    
    # Bandstop = allpass - bandpass
    for n from 0 to filter_length - 1
        h[n] = -h[n]
    endfor
    h[m_center] = h[m_center] + 1
endproc

procedure applyFIRFilter: .inputSound
    selectObject: .inputSound
    
    # Create impulse response Sound
    impulse = Create Sound from formula: "filter_ir_" + uniqueID$, 1, 0, filter_length / sampleRate, sampleRate, "0"
    
    selectObject: impulse
    for n from 0 to filter_length - 1
        Set value at sample number: 1, n + 1, h[n]
    endfor
    
    # Convolve (built-in, fast FFT)
    selectObject: .inputSound
    plusObject: impulse
    Convolve: "sum", "zero"
    
    removeObject: impulse
endproc


# ============================================================
# VISUALIZATION PROCEDURES
# ============================================================

# _ ^ # % are markup in Picture text and are SWALLOWED, so a Sound
# called "take_2" loses its underscore before it reaches the page.
procedure sanitizeText: .s$
    .out$ = replace$(.s$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

# Praat writes 20000 as 2*10^4 on an axis, next to a plain "5000".
procedure hzLab: .v
    if .v >= 1000
        .out$ = fixed$(.v / 1000, 1)
        .out$ = replace$(.out$, ".0", "", 0) + "k"
    else
        .out$ = fixed$(.v, 0)
    endif
endproc

# Decade ticks for the shared log frequency axis
procedure logMarksBottom
    for .m from 1 to 16
        if .m = 1
            .v = 10
        elsif .m = 2
            .v = 20
        elsif .m = 3
            .v = 50
        elsif .m = 4
            .v = 100
        elsif .m = 5
            .v = 200
        elsif .m = 6
            .v = 500
        elsif .m = 7
            .v = 1000
        elsif .m = 8
            .v = 2000
        elsif .m = 9
            .v = 5000
        elsif .m = 10
            .v = 10000
        elsif .m = 11
            .v = 20000
        else
            .v = 0
        endif
        if .v >= fPlotMin and .v <= fPlotMax and .v > 0
            @hzLab: .v
            One mark bottom: log10(.v), "no", "yes", "no", hzLab.out$
        endif
    endfor
endproc

# ============================================================
# Response analysis
# ============================================================
# The magnitude is evaluated on a LOG-spaced grid. v0.4.1 used 512
# LINEARLY spaced points to nyquist, which on a 44.1 kHz file is one
# point every 43 Hz: the 80 Hz Rumble preset had its whole transition
# described by about two samples, and the plot showed a vertical wall
# at the left edge instead of a filter.
procedure analyseResponse
    nF = 600

    fPlotMin = 20
    if filter_type <> 7 and filter_type <> 9
        if cutoff_frequency / 5 < fPlotMin
            fPlotMin = cutoff_frequency / 5
        endif
    endif
    if fPlotMin < 5
        fPlotMin = 5
    endif
    fPlotMax = nyquist
    lgMin = log10(fPlotMin)
    lgMax = log10(fPlotMax)

    # Rough floor used only to keep deep-null numerical noise out of the
    # phase-deviation metric; the plotted floor is derived later.
    dbFloorGuess = -90

    for i from 0 to nF
        frq[i] = 10 ^ (lgMin + (lgMax - lgMin) * i / nF)
        lgx[i] = lgMin + (lgMax - lgMin) * i / nF
        om = 2 * pi * frq[i] / sampleRate
        hre = 0
        him = 0
        for n from 0 to filter_length - 1
            hre = hre + h[n] * cos(om * n)
            him = him - h[n] * sin(om * n)
        endfor
        mg = sqrt(hre^2 + him^2)
        if mg > 1e-7
            mdb[i] = 20 * log10(mg)
        else
            mdb[i] = -140
        endif
        phs[i] = arctan2(him, hre) * 180 / pi
    endfor

    # DEVIATION from ideal linear phase, wrapped into (-180, 180].
    # Unwrapping was tried first and does not work on a log grid: at
    # 20 kHz consecutive points are 235 Hz apart, which for N = 101 is
    # 959 degrees of true phase per step, so the +/-180 unwrap rule
    # aliases and the curve loses turns. Subtracting the ideal ramp
    # BEFORE wrapping avoids the problem entirely and is exact at any
    # spacing. A perfectly linear-phase filter sits at 0, flipping to
    # +/-180 wherever the amplitude function changes sign (every
    # stopband null). Anything else is real phase distortion.
    maxPhaseDev = 0
    for i from 0 to nF
        rs = phs[i] + 360 * m_center * frq[i] / sampleRate
        rs = rs - 360 * round(rs / 360)
        pdev[i] = rs
        # Fold the legitimate +/-180 branch onto 0 for the metric
        .fold = abs(rs)
        if .fold > 90
            .fold = 180 - .fold
        endif
        if mdb[i] > dbFloorGuess and .fold > maxPhaseDev
            maxPhaseDev = .fold
        endif
    endfor

    # Linear phase is a property of the COEFFICIENTS, so it is tested
    # there rather than inferred from a picture: a symmetric or
    # antisymmetric h gives exactly linear phase and a group delay of
    # (N-1)/2 samples.
    symErr = 0
    antiErr = 0
    hPeak = 0
    for n from 0 to filter_length - 1
        nr = filter_length - 1 - n
        ds = abs(h[n] - h[nr])
        da = abs(h[n] + h[nr])
        if ds > symErr
            symErr = ds
        endif
        if da > antiErr
            antiErr = da
        endif
        if abs(h[n]) > hPeak
            hPeak = abs(h[n])
        endif
    endfor
    if hPeak > 0
        symRelS = symErr / hPeak
        symRelA = antiErr / hPeak
    else
        symRelS = 0
        symRelA = 0
    endif
    linearPhase = 0
    symKind$ = "symmetric"
    symRel = symRelS
    if symRelA < symRelS
        symRel = symRelA
        symKind$ = "antisymmetric"
    endif
    if symRel < 1e-9
        linearPhase = 1
    endif

    # --- Band edges, measured at -6 dB from the passband ---
    hasCutoffMeasure = 0
    edgeReport$ = ""
    edgeLo = 0
    edgeHi = 0
    if filter_type <> 9
        if filter_mode = 1
            @findCross: 1, -6, 1
            edgeLo = findCross.f
            if edgeLo > 0
                hasCutoffMeasure = 1
                @hzLab: round(edgeLo)
                edgeReport$ = hzLab.out$ + " Hz"
            endif
        elsif filter_mode = 2
            @findCross: 1, -6, 2
            edgeLo = findCross.f
            if edgeLo > 0
                hasCutoffMeasure = 1
                @hzLab: round(edgeLo)
                edgeReport$ = hzLab.out$ + " Hz"
            endif
        elsif filter_mode = 3
            @findCross: 1, -6, 2
            edgeLo = findCross.f
            @findCross: 2, -6, 2
            edgeHi = findCross.f
            if edgeLo > 0 and edgeHi > 0
                hasCutoffMeasure = 1
                @hzLab: round(edgeLo)
                .a$ = hzLab.out$
                @hzLab: round(edgeHi)
                edgeReport$ = .a$ + " - " + hzLab.out$ + " Hz"
            endif
        else
            @findCross: 1, -6, 1
            edgeLo = findCross.f
            @findCross: 2, -6, 1
            edgeHi = findCross.f
            if edgeLo > 0 and edgeHi > 0
                hasCutoffMeasure = 1
                @hzLab: round(edgeLo)
                .a$ = hzLab.out$
                @hzLab: round(edgeHi)
                edgeReport$ = .a$ + " - " + hzLab.out$ + " Hz"
            endif
        endif
    endif

    # --- Passband ripple and stopband rejection ---
    # Regions are set from the MEASURED edges, with a margin either side
    # so the transition itself is never counted as ripple or as leakage.
    pbMax = -999
    pbMin = 999
    sbMax = -999
    nPb = 0
    nSb = 0
    for i from 0 to nF
        fr = frq[i]
        inPb = 0
        inSb = 0
        if filter_type = 9
            if fr > 0.15 * nyquist and fr < 0.85 * nyquist
                inPb = 1
            endif
        elsif filter_mode = 1
            if edgeLo > 0
                if fr < 0.6 * edgeLo
                    inPb = 1
                endif
                if fr > 1.8 * edgeLo
                    inSb = 1
                endif
            endif
        elsif filter_mode = 2
            if edgeLo > 0
                if fr > 1.8 * edgeLo
                    inPb = 1
                endif
                if fr < 0.6 * edgeLo
                    inSb = 1
                endif
            endif
        elsif filter_mode = 3
            if edgeLo > 0 and edgeHi > 0
                if fr > 1.4 * edgeLo and fr < 0.72 * edgeHi
                    inPb = 1
                endif
                if fr < 0.55 * edgeLo or fr > 1.8 * edgeHi
                    inSb = 1
                endif
            endif
        else
            if edgeLo > 0 and edgeHi > 0
                if fr < 0.55 * edgeLo or fr > 1.8 * edgeHi
                    inPb = 1
                endif
                if fr > 1.4 * edgeLo and fr < 0.72 * edgeHi
                    inSb = 1
                endif
            endif
        endif
        if inPb
            nPb = nPb + 1
            if mdb[i] > pbMax
                pbMax = mdb[i]
            endif
            if mdb[i] < pbMin
                pbMin = mdb[i]
            endif
        endif
        if inSb
            nSb = nSb + 1
            if mdb[i] > sbMax
                sbMax = mdb[i]
            endif
        endif
    endfor
    hasPassband = 0
    hasStopband = 0
    pbRipple = 0
    if nPb > 2
        hasPassband = 1
        pbRipple = pbMax - pbMin
    endif
    if nSb > 2
        hasStopband = 1
    endif

    # --- Is the filter long enough to place the cutoff it was asked for?
    # A windowed-sinc's transition width is set by N and the window, not
    # by the cutoff, so a short filter simply cannot realise a low
    # cutoff. The shipped "Rumble Filter (80 Hz HP)" preset is a case in
    # point: Blackman at N = 255 on 44.1 kHz has a half-transition of
    # about 476 Hz, six times the 80 Hz it asks for, so the -6 dB point
    # lands near 206 Hz. That was invisible on v0.4.1's linear axis.
    transEst = 0
    hasTransEst = 0
    tooShort = 0
    if filter_type >= 1 and filter_type <= 6
        if filter_type = 1
            kWin = 0.9
        elsif filter_type = 2
            kWin = 3.3
        elsif filter_type = 3
            kWin = 3.1
        elsif filter_type = 4
            kWin = 5.5
        elsif filter_type = 5
            kWin = 2.0 + 0.6 * kaiser_beta
        else
            kWin = 2.0
        endif
        transEst = kWin / filter_length * sampleRate
        hasTransEst = 1
        if filter_mode = 1 or filter_mode = 2
            if cutoff_frequency < transEst / 2
                tooShort = 1
            endif
            if nyquist - cutoff_frequency < transEst / 2
                tooShort = 1
            endif
        else
            if cutoff_frequency_2 - cutoff_frequency < transEst
                tooShort = 1
            endif
            if cutoff_frequency < transEst / 2
                tooShort = 1
            endif
        endif
    endif

    # Plot floor, derived from what the filter actually reaches
    dbFloor = -100
    if hasStopband
        dbFloor = floor((sbMax - 25) / 20) * 20
    endif
    if dbFloor < -140
        dbFloor = -140
    endif
    if dbFloor > -60
        dbFloor = -60
    endif
    dbCeil = 6
endproc

# First crossing of a dB level. .from = 1 scans upward in frequency,
# 2 scans downward; .dir = 1 finds a fall below the level, 2 a rise
# above it. Returns 0 when the response never crosses.
# NOTE the direction is relative to the SCAN, not to frequency: coming
# down from Nyquist into a bandpass passband is a RISE (dir 2), and
# down into a bandstop passband is a FALL out of the notch (dir 1).
# Getting these backwards made both bandpass edges report the same
# frequency, which then swallowed the passband into the stopband
# region and gave a "stopband rejection" of -0.06 dB.
procedure findCross: .from, .level, .dir
    .f = 0
    if .from = 1
        .i0 = 1
        .i1 = nF
        .st = 1
    else
        .i0 = nF - 1
        .i1 = 1
        .st = -1
    endif
    .done = 0
    for .k from 0 to nF - 1
        .i = .i0 + .k * .st
        if .i >= 1 and .i <= nF and .done = 0
            .ip = .i - .st
            .a = mdb[.ip]
            .b = mdb[.i]
            .hit = 0
            if .dir = 1
                if .a > .level and .b <= .level
                    .hit = 1
                endif
            else
                if .a < .level and .b >= .level
                    .hit = 1
                endif
            endif
            if .hit
                if .b <> .a
                    .t = (.level - .a) / (.b - .a)
                else
                    .t = 0
                endif
                .lg = lgx[.ip] + (lgx[.i] - lgx[.ip]) * .t
                .f = 10 ^ .lg
                .done = 1
            endif
        endif
    endfor
endproc

# ============================================================
# PANEL 1 - magnitude response
# ============================================================
procedure plotMagnitude
    Font size: 7
    Select outer viewport: 0, 8, magTop - 0.25, magBot + 0.50
    Select inner viewport: 0.60, 7.70, magTop, magBot
    Axes: lgMin, lgMax, dbFloor, dbCeil
    Paint rectangle: "{0.975, 0.975, 0.985}", lgMin, lgMax, dbFloor, dbCeil

    Select inner viewport: 0.60, 7.70, magTop, magBot
    Axes: lgMin, lgMax, dbFloor, dbCeil
    Colour: "{0.88, 0.88, 0.90}"
    Line width: 1
    .g = -20
    while .g > dbFloor
        Draw line: lgMin, .g, lgMax, .g
        .g = .g - 20
    endwhile

    # -6 dB, the level the measured edges are taken at
    Colour: "{0.60, 0.60, 0.85}"
    Dotted line
    Draw line: lgMin, -6, lgMax, -6
    Solid line

    # Requested cutoffs, for comparison with where the filter landed
    if filter_type <> 9 and filter_type <> 7
        Colour: "{0.25, 0.65, 0.30}"
        Line width: 1
        Dashed line
        if cutoff_frequency >= fPlotMin and cutoff_frequency <= fPlotMax
            Draw line: log10(cutoff_frequency), dbFloor, log10(cutoff_frequency), dbCeil
        endif
        if filter_mode >= 3 and cutoff_frequency_2 <= fPlotMax
            Draw line: log10(cutoff_frequency_2), dbFloor, log10(cutoff_frequency_2), dbCeil
        endif
        Solid line
    endif

    Select inner viewport: 0.60, 7.70, magTop, magBot
    Axes: lgMin, lgMax, dbFloor, dbCeil
    Colour: "{0.80, 0.15, 0.15}"
    Line width: 2
    for .i from 1 to nF
        .ya = min(max(mdb[.i - 1], dbFloor), dbCeil)
        .yb = min(max(mdb[.i], dbFloor), dbCeil)
        Draw line: lgx[.i - 1], .ya, lgx[.i], .yb
    endfor
    Line width: 1

    # Measured -6 dB edges
    if hasCutoffMeasure
        Colour: "{0.10, 0.10, 0.10}"
        if edgeLo > 0
            Paint circle (mm): "{0.10, 0.10, 0.10}", log10(edgeLo), -6, 1.2
        endif
        if edgeHi > 0
            Paint circle (mm): "{0.10, 0.10, 0.10}", log10(edgeHi), -6, 1.2
        endif
    endif

    Font size: 6
    Select inner viewport: 0.60, 7.70, magTop, magBot
    Axes: lgMin, lgMax, dbFloor, dbCeil
    Colour: "{0.25, 0.65, 0.30}"
    if filter_type <> 9 and filter_type <> 7
        Text: lgMin + (lgMax - lgMin) * 0.02, "left", dbFloor * 0.10, "half",
        ... "dashed green = requested cutoff"
    endif
    Colour: "{0.28, 0.28, 0.28}"
    Text: lgMax - (lgMax - lgMin) * 0.005, "right", dbFloor * 0.10, "half",
    ... "dots = measured -6 dB edge"

    Font size: 7
    Select inner viewport: 0.60, 7.70, magTop, magBot
    Axes: lgMin, lgMax, dbFloor, dbCeil
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    @logMarksBottom
    Text left: "yes", "Magnitude (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "##Magnitude response##"
endproc

# ============================================================
# PANEL 2 - unwrapped phase against the ideal linear ramp
# ============================================================
procedure plotPhase
    Font size: 7
    Select outer viewport: 0, 8, phTop - 0.25, phBot + 0.50
    Select inner viewport: 0.60, 7.70, phTop, phBot
    Axes: lgMin, lgMax, -250, 250
    Paint rectangle: "{0.975, 0.975, 0.985}", lgMin, lgMax, -250, 250

    Select inner viewport: 0.60, 7.70, phTop, phBot
    Axes: lgMin, lgMax, -250, 250
    Colour: "{0.88, 0.88, 0.90}"
    Draw line: lgMin, 90, lgMax, 90
    Draw line: lgMin, -90, lgMax, -90
    # The two levels a linear-phase filter is allowed to occupy
    Colour: "{0.60, 0.80, 0.62}"
    Dashed line
    Draw line: lgMin, 180, lgMax, 180
    Draw line: lgMin, -180, lgMax, -180
    Solid line
    Colour: "{0.25, 0.65, 0.30}"
    Line width: 2
    Draw line: lgMin, 0, lgMax, 0
    Line width: 1

    Select inner viewport: 0.60, 7.70, phTop, phBot
    Axes: lgMin, lgMax, -250, 250
    Colour: "{0.15, 0.30, 0.75}"
    Line width: 1.5
    for .i from 1 to nF
        # Do not join across a 0 to +/-180 flip: that vertical jump is a
        # branch change, not a trajectory the phase passes through.
        if abs(pdev[.i] - pdev[.i - 1]) < 100
            Draw line: lgx[.i - 1], pdev[.i - 1], lgx[.i], pdev[.i]
        endif
    endfor
    Line width: 1

    Font size: 6
    Select inner viewport: 0.60, 7.70, phTop, phBot
    Axes: lgMin, lgMax, -250, 250
    Colour: "{0.28, 0.28, 0.28}"
    Text: lgMin + (lgMax - lgMin) * 0.02, "left", 220, "half",
    ... "0 or +/-180 everywhere = exactly linear phase (+/-180 = sidelobe sign change)"
    Text: lgMax - (lgMax - lgMin) * 0.005, "right", -220, "half",
    ... "max deviation " + fixed$(maxPhaseDev, 4) + " deg"

    Font size: 7
    Select inner viewport: 0.60, 7.70, phTop, phBot
    Axes: lgMin, lgMax, -250, 250
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 90, "yes", "yes", "no"
    @logMarksBottom
    Text left: "yes", "Deviation (deg)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "##Phase: deviation from ideal linear phase##"
endproc

procedure niceStepP: .span
    .raw = .span / 4
    if .raw <= 0
        .step = 1
    else
        .mag = 10 ^ floor(log10(.raw))
        .n = .raw / .mag
        if .n < 1.5
            .step = .mag
        elsif .n < 3.5
            .step = 2 * .mag
        elsif .n < 7.5
            .step = 5 * .mag
        else
            .step = 10 * .mag
        endif
    endif
endproc

# ============================================================
# PANEL 3 - impulse response
# ============================================================
procedure plotImpulse
    .hMin = h[0]
    .hMax = h[0]
    for .n from 1 to filter_length - 1
        if h[.n] < .hMin
            .hMin = h[.n]
        endif
        if h[.n] > .hMax
            .hMax = h[.n]
        endif
    endfor
    .margin = (.hMax - .hMin) * 0.15
    if .margin < 1e-6
        .margin = 1e-6
    endif
    .yLo = .hMin - .margin
    .yHi = .hMax + .margin

    Font size: 7
    Select outer viewport: 0, 8, impTop - 0.25, impBot + 0.50
    Select inner viewport: 0.60, 7.70, impTop, impBot
    Axes: -1, filter_length, .yLo, .yHi
    Paint rectangle: "{0.975, 0.975, 0.985}", -1, filter_length, .yLo, .yHi

    Select inner viewport: 0.60, 7.70, impTop, impBot
    Axes: -1, filter_length, .yLo, .yHi
    Colour: "{0.75, 0.75, 0.75}"
    Draw line: -1, 0, filter_length, 0
    # Centre of symmetry: the tap the whole linear-phase argument rests on
    Colour: "{0.25, 0.65, 0.30}"
    Dashed line
    Draw line: m_center, .yLo, m_center, .yHi
    Solid line

    Select inner viewport: 0.60, 7.70, impTop, impBot
    Axes: -1, filter_length, .yLo, .yHi
    Colour: "{0.20, 0.45, 0.75}"
    Line width: 1
    for .n from 0 to filter_length - 1
        Draw line: .n, 0, .n, h[.n]
    endfor

    # v0.4.1 asked for "Paint circle: ..., 0.008" with the x axis running
    # 0 to N-1, i.e. a radius of 0.008 SAMPLES - about a sixth of a pixel
    # at 300 dpi. The tip dots have never been visible. Millimetres are
    # the unit that survives both the screen and the export.
    if filter_length <= 129
        for .n from 0 to filter_length - 1
            Paint circle (mm): "{0.75, 0.20, 0.20}", .n, h[.n], 0.9
        endfor
    endif

    # A highpass built as (unit impulse - lowpass) is a near-unit spike
    # with every other tap around a thousandth of it. The stems are then
    # correct but invisible, so the actual numbers are stated.
    .other = 0
    for .n from 0 to filter_length - 1
        if .n <> m_center and abs(h[.n]) > .other
            .other = abs(h[.n])
        endif
    endfor

    Font size: 6
    Select inner viewport: 0.60, 7.70, impTop, impBot
    Axes: -1, filter_length, .yLo, .yHi
    Colour: "{0.25, 0.65, 0.30}"
    Text: m_center, "left", .yHi - (.yHi - .yLo) * 0.06, "half",
    ... "  centre tap " + string$(m_center) + " = " + fixed$(h[m_center], 4)
    Colour: "{0.28, 0.28, 0.28}"
    Text: filter_length - 1, "right", .yHi - (.yHi - .yLo) * 0.06, "half",
    ... "largest other tap " + fixed$(.other, 5) + "  "

    Font size: 7
    Select inner viewport: 0.60, 7.70, impTop, impBot
    Axes: -1, filter_length, .yLo, .yHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    @niceStepP: filter_length
    Marks bottom every: 1, niceStepP.step, "yes", "yes", "no"
    @niceStepP: .yHi - .yLo
    Marks left every: 1, niceStepP.step, "yes", "yes", "no"
    Text left: "yes", "h[n]"
    Text bottom: "yes", "Tap index n"
    Text top: "no", "##Impulse response##"
endproc

# ============================================================
# PANEL 4 - measured specification and run summary
# ============================================================
procedure plotStrip
    Font size: 7
    Select outer viewport: 0, 8, stripTop - 0.10, stripBot + 0.15
    Select inner viewport: 0.60, 3.90, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, 1, 0, 1

    Select inner viewport: 0.60, 3.90, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.03, "left", 0.88, "half", "##Measured##"

    Font size: 6
    Select inner viewport: 0.60, 3.90, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"

    if hasCutoffMeasure
        .r1$ = "-6 dB edge: " + edgeReport$
        if filter_type <> 7 and filter_type <> 9
            @hzLab: round(cutoff_frequency)
            .r1$ = .r1$ + "   (requested " + hzLab.out$
            if filter_mode >= 3
                @hzLab: round(cutoff_frequency_2)
                .r1$ = .r1$ + " - " + hzLab.out$
            endif
            .r1$ = .r1$ + " Hz)"
        endif
    else
        .r1$ = "-6 dB edge: not applicable for this design"
    endif
    Text: 0.03, "left", 0.72, "half", .r1$

    if hasPassband
        .r2$ = "Passband variation (to 0.6x edge): " + fixed$(pbRipple, 2) + " dB"
    else
        .r2$ = "Passband variation: not measurable"
    endif
    if hasStopband
        .r2$ = .r2$ + "    Stopband: " + fixed$(-sbMax, 1) + " dB down"
    endif
    Text: 0.03, "left", 0.54, "half", .r2$

    .r3$ = "Group delay: " + fixed$(m_center, 1) + " samples (" +
    ... fixed$(m_center / sampleRate * 1000, 3) + " ms)"
    if hasTransEst
        @hzLab: round(transEst)
        .r3$ = .r3$ + "    Transition = " + hzLab.out$ + " Hz"
    endif
    Text: 0.03, "left", 0.36, "half", .r3$

    if tooShort
        Colour: "{0.80, 0.15, 0.15}"
        Text: 0.03, "left", 0.18, "half",
        ... "! N = " + string$(filter_length) + " is too short for this cutoff -"
        Text: 0.03, "left", 0.06, "half",
        ... "  the transition is wider than the band asked for; increase N"
    elsif linearPhase
        Colour: "{0.15, 0.50, 0.20}"
        Text: 0.03, "left", 0.14, "half",
        ... "Linear phase: yes - coefficients " + symKind$
    else
        Colour: "{0.80, 0.15, 0.15}"
        Text: 0.03, "left", 0.14, "half",
        ... "Linear phase: NO - h is neither symmetric nor antisymmetric"
    endif

    Font size: 7
    Select inner viewport: 0.60, 3.90, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # --- run summary, right half ---
    Font size: 7
    Select inner viewport: 4.30, 7.70, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Select inner viewport: 4.30, 7.70, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.03, "left", 0.88, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 4.30, 7.70, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.03, "left", 0.68, "half",
    ... "Filter: " + filterTypeName$ + " " + filterModeName$ +
    ... "   N = " + string$(filter_length)
    if filter_type = 5
        Text: 0.03, "left", 0.48, "half",
        ... "Kaiser beta: " + fixed$(kaiser_beta, 2)
    elsif filter_type = 8
        Text: 0.03, "left", 0.48, "half",
        ... "Rolloff alpha: " + fixed$(rolloff_factor, 2)
    else
        Text: 0.03, "left", 0.48, "half",
        ... "Source: " + vizName$
    endif
    Text: 0.03, "left", 0.28, "half",
    ... "Rate: " + fixed$(sampleRate, 0) + " Hz   Channels: " + string$(numChannels)
    if apply_filter
        Text: 0.03, "left", 0.08, "half",
        ... "Output: dry/wet " + fixed$(dry_wet_mix, 2) +
        ... "   scaled to peak " + fixed$(scale_peak, 2)
    else
        Text: 0.03, "left", 0.08, "half", "Output: design only, filter not applied"
    endif

    Font size: 7
    Select inner viewport: 4.30, 7.70, stripTop, stripBot
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
endproc