# ============================================================
# Praat AudioTools - Classic FIR Filter Bank.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.3 (2025)
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

form Classic FIR Filter Bank
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
    
    if numChannels = 1
        @applyFIRFilter: sound
        filtered = selected("Sound")
    else
        Extract one channel: 1
        left = selected("Sound")
        @applyFIRFilter: left
        filteredL = selected("Sound")
        
        selectObject: sound
        Extract one channel: 2
        right = selected("Sound")
        @applyFIRFilter: right
        filteredR = selected("Sound")
        
        selectObject: filteredL, filteredR
        Combine to stereo
        filtered = selected("Sound")
        
        removeObject: left, right, filteredL, filteredR
    endif
    
    selectObject: filtered
    
    # Dry/wet mix (only when < 1). The linear-phase FIR delays the wet by
    # m_center samples, so the dry is read with the same delay to stay
    # phase-coherent. Indexed access returns 0 out of range (covering the
    # leading latency and the convolution tail) and works for mono and
    # stereo alike via the row=channel index.
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
# Plot responses
# ============================================================
if plot_responses or plot_impulse
    Erase all
    
    if plot_responses
        @plotFrequencyResponse
    endif
    
    if plot_impulse
        @plotImpulseResponse
    endif
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
        
        # Sinc function
        if m = 0
            h[n] = 2 * wc
        else
            h[n] = sin(2 * pi * wc * m) / (pi * m)
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
    t_symbol = 1 / (2 * wc)
    
    for n from 0 to filter_length - 1
        m = n - m_center
        t = m / sampleRate
        
        if abs(t) < 0.00001
            h[n] = 1 / t_symbol
        elif abs(abs(t) - t_symbol/(2*alpha)) < 0.00001 and alpha > 0
            h[n] = (pi/(4*t_symbol)) * sin(pi/(2*alpha)) / (pi*t)
        else
            sincPart = sin(pi*t/t_symbol) / (pi*t/t_symbol)
            cosPart = cos(pi*alpha*t/t_symbol)
            denom = 1 - (2*alpha*t/t_symbol)^2
            
            if abs(denom) > 0.00001
                h[n] = sincPart * cosPart / denom
            else
                h[n] = 0
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
    # Design second lowpass at wc2
    for n from 0 to filter_length - 1
        m = n - m_center
        
        if m = 0
            h2[n] = 2 * wc2
        else
            h2[n] = sin(2 * pi * wc2 * m) / (pi * m)
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

procedure plotFrequencyResponse
    npts = 512
    
    for i from 1 to npts
        freq[i] = (i - 1) * nyquist / npts
        omega = 2 * pi * freq[i] / sampleRate
        
        h_re = 0
        h_im = 0
        
        for n from 0 to filter_length - 1
            h_re += h[n] * cos(omega * n)
            h_im += -h[n] * sin(omega * n)
        endfor
        
        mag = sqrt(h_re^2 + h_im^2)
        if mag > 0.00001
            magDb[i] = 20 * log10(mag)
        else
            magDb[i] = -120
        endif
        
        if magDb[i] < -80
            magDb[i] = -80
        endif
        
        phase[i] = arctan2(h_im, h_re) * 180 / pi
    endfor
    
    # PANEL 1: Magnitude
    if plot_impulse
        Select outer viewport: 0, 6, 0, 2.2
        Select inner viewport: 0.7, 5.8, 0.3, 2.0
    else
        Select outer viewport: 0, 6, 0, 3
        Select inner viewport: 0.7, 5.8, 0.4, 2.7
    endif
    
    Axes: 0, nyquist, -80, 10
    
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, -60, nyquist, -60
    Draw line: 0, -40, nyquist, -40
    Draw line: 0, -20, nyquist, -20
    Draw line: 0, 0, nyquist, 0
    
    Colour: "{0.6, 0.6, 1}"
    Dotted line
    Draw line: 0, -3, nyquist, -3
    Solid line
    
    if filter_type <> 9
        Colour: "{0.3, 0.7, 0.3}"
        Draw line: cutoff_frequency, -80, cutoff_frequency, 10
        if filter_mode >= 3
            Draw line: cutoff_frequency_2, -80, cutoff_frequency_2, 10
        endif
    endif
    
    Colour: "{0.8, 0.1, 0.1}"
    Line width: 2
    for i from 2 to npts
        if magDb[i] > -80 and magDb[i-1] > -80
            Draw line: freq[i-1], magDb[i-1], freq[i], magDb[i]
        endif
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "dB"
    Text top: "no", "##" + filterTypeName$ + " " + filterModeName$ + " N=" + string$(filter_length) + "##"
    Marks left every: 1, 20, "yes", "yes", "no"
    
    if nyquist > 10000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 5000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    
    # PANEL 2: Phase
    if plot_impulse
        Select outer viewport: 0, 6, 2.2, 4.4
        Select inner viewport: 0.7, 5.8, 2.5, 4.2
    else
        Select outer viewport: 0, 6, 3, 6
        Select inner viewport: 0.7, 5.8, 3.4, 5.7
    endif
    
    Axes: 0, nyquist, -180, 180
    
    Colour: "{0.85, 0.85, 0.85}"
    Draw line: 0, -90, nyquist, -90
    Draw line: 0, 0, nyquist, 0
    Draw line: 0, 90, nyquist, 90
    
    if filter_type <> 9
        Colour: "{0.3, 0.7, 0.3}"
        Draw line: cutoff_frequency, -180, cutoff_frequency, 180
        if filter_mode >= 3
            Draw line: cutoff_frequency_2, -180, cutoff_frequency_2, 180
        endif
    endif
    
    Colour: "{0.1, 0.3, 0.8}"
    Line width: 2
    for i from 2 to npts
        diff = phase[i] - phase[i-1]
        if abs(diff) < 170
            Draw line: freq[i-1], phase[i-1], freq[i], phase[i]
        endif
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text bottom: "yes", "Frequency (Hz)"
    Text left: "yes", "Phase"
    Marks left every: 1, 90, "yes", "yes", "no"
    
    if nyquist > 10000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 5000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
endproc

procedure plotImpulseResponse
    Select outer viewport: 0, 6, 4.5, 7
    Select inner viewport: 0.7, 5.8, 4.8, 6.8
    
    h_min = h[0]
    h_max = h[0]
    for n from 1 to filter_length - 1
        if h[n] < h_min
            h_min = h[n]
        endif
        if h[n] > h_max
            h_max = h[n]
        endif
    endfor
    
    margin = (h_max - h_min) * 0.15
    if margin < 0.001
        margin = 0.001
    endif
    
    Axes: 0, filter_length - 1, h_min - margin, h_max + margin
    
    # Zero line
    Colour: "{0.8, 0.8, 0.8}"
    Draw line: 0, 0, filter_length - 1, 0
    
    # Stems
    Colour: "{0.2, 0.5, 0.8}"
    Line width: 1
    for n from 0 to filter_length - 1
        Draw line: n, 0, n, h[n]
    endfor
    
    # Dots at tips
    Colour: "{0.8, 0.2, 0.2}"
    for n from 0 to filter_length - 1
        Paint circle: "{0.8, 0.2, 0.2}", n, h[n], 0.008
    endfor
    
    Black
    Draw inner box
    Text left: "yes", "h[n]"
    Text bottom: "yes", "Sample"
    Text top: "no", "##Impulse Response (Linear Phase)##"
endproc