# ============================================================
# Praat AudioTools - Classic IIR Filter Bank.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Classic IIR filter bank with frequency response, phase response,
#   and Z-plane visualization.
#
# Filter types:
#   - Bessel: Maximally flat group delay
#   - Butterworth: Maximally flat magnitude response
#   - Chebyshev I: Steeper rolloff, passband ripple
#   - Chebyshev II: Steeper rolloff, stopband ripple
#   - Elliptic: Steepest rolloff, both ripples
#
# Note: Fast mode uses Praat built-in filters (Hann window).
#       Custom IIR mode is slow but mathematically exact.
#
# Usage:
#   Select a Sound object in Praat and run this script.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Classic IIR Filter Bank
    optionmenu Preset: 1
        option Custom
        option Speech Lowpass (3.5 kHz)
        option Music Lowpass (8 kHz)
        option Rumble Filter (80 Hz HP)
        option Presence Cut (2-5 kHz)
    optionmenu Filter_type: 2
        option Bessel (flat delay)
        option Butterworth (flat magnitude)
        option Chebyshev I (passband ripple)
        option Chebyshev II (stopband ripple)
        option Elliptic (steepest)
    optionmenu Filter_mode: 1
        option Lowpass
        option Highpass
    integer order 4
    positive cutoff_frequency 1000
    positive passband_ripple_db 0.5
    positive stopband_attenuation_db 40
    boolean fast_mode 1
    positive scale_peak 0.95
    boolean plot_responses 1
    boolean plot_zplane 1
    boolean apply_filter 1
    boolean play_after_processing 1
endform

# ============================================================
# Apply presets
# ============================================================
if preset$ = "Speech Lowpass (3.5 kHz)"
    filter_type = 2
    filter_mode = 1
    order = 4
    cutoff_frequency = 3500
elif preset$ = "Music Lowpass (8 kHz)"
    filter_type = 2
    filter_mode = 1
    order = 4
    cutoff_frequency = 8000
elif preset$ = "Rumble Filter (80 Hz HP)"
    filter_type = 2
    filter_mode = 2
    order = 4
    cutoff_frequency = 80
elif preset$ = "Presence Cut (2-5 kHz)"
    filter_type = 2
    filter_mode = 1
    order = 4
    cutoff_frequency = 2000
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

if order mod 2 <> 0 or order < 2 or order > 8
    exitScript: "Order must be 2, 4, 6, or 8"
endif

if cutoff_frequency >= nyquist
    exitScript: "Cutoff must be below Nyquist (" + string$(nyquist) + " Hz)"
endif

nSections = order / 2

# Filter names
if filter_type = 1
    filterTypeName$ = "Bessel"
elif filter_type = 2
    filterTypeName$ = "Butterworth"
elif filter_type = 3
    filterTypeName$ = "ChebyshevI"
elif filter_type = 4
    filterTypeName$ = "ChebyshevII"
else
    filterTypeName$ = "Elliptic"
endif

if filter_mode = 1
    filterModeName$ = "LP"
else
    filterModeName$ = "HP"
endif

# ============================================================
# Initialize SOS coefficients
# ============================================================
for sec from 1 to nSections
    sos_b0[sec] = 1
    sos_b1[sec] = 2
    sos_b2[sec] = 1
    sos_a0[sec] = 1
    sos_a1[sec] = 0
    sos_a2[sec] = 0
endfor

wn = cutoff_frequency / nyquist

# ============================================================
# Report
# ============================================================
writeInfoLine: "Classic IIR Filter Bank"
appendInfoLine: "======================="
appendInfoLine: "Input: ", originalName$
appendInfoLine: "Filter: ", filterTypeName$, " ", filterModeName$
appendInfoLine: "Order: ", order
appendInfoLine: "Cutoff: ", cutoff_frequency, " Hz"
appendInfoLine: ""

# ============================================================
# Design filter coefficients (always, for plotting)
# ============================================================
appendInfoLine: "Designing ", filterTypeName$, " filter..."

if filter_type = 1
    # BESSEL - tabulated poles
    if order = 2
        poles_re[1] = -1.1030
        poles_im[1] = 0.6368
        normFactor = 1.2736
    elsif order = 4
        poles_re[1] = -0.9952
        poles_im[1] = 0.4105
        poles_re[2] = -1.3808
        poles_im[2] = 0.7179
        normFactor = 1.4192
    elsif order = 6
        poles_re[1] = -0.9606
        poles_im[1] = 0.3272
        poles_re[2] = -1.3808
        poles_im[2] = 0.5950
        poles_re[3] = -1.5715
        poles_im[3] = 0.6301
        normFactor = 1.5069
    elsif order = 8
        poles_re[1] = -0.9425
        poles_im[1] = 0.2735
        poles_re[2] = -1.3797
        poles_im[2] = 0.5120
        poles_re[3] = -1.6140
        poles_im[3] = 0.5950
        poles_re[4] = -1.7627
        poles_im[4] = 0.5787
        normFactor = 1.5735
    endif
    
    for sec from 1 to nSections
        @analogToDigitalSOS: sec, poles_re[sec] * normFactor, poles_im[sec] * normFactor
    endfor

elif filter_type = 2
    # BUTTERWORTH
    for sec from 1 to nSections
        theta = pi * (2*sec + order - 1) / (2*order)
        pole_re = cos(theta)
        pole_im = sin(theta)
        @analogToDigitalSOS: sec, pole_re, pole_im
    endfor

elif filter_type = 3
    # CHEBYSHEV TYPE I
    epsilon = sqrt(10^(passband_ripple_db/10) - 1)
    sinhVal = arcsinh(1/epsilon) / order
    
    for sec from 1 to nSections
        theta = pi * (2*sec - 1) / (2*order)
        pole_re = -sinh(sinhVal) * sin(theta)
        pole_im = cosh(sinhVal) * cos(theta)
        @analogToDigitalSOS: sec, pole_re, pole_im
    endfor

elif filter_type = 4
    # CHEBYSHEV TYPE II
    epsilon = 1 / sqrt(10^(stopband_attenuation_db/10) - 1)
    sinhVal = arcsinh(1/epsilon) / order
    
    for sec from 1 to nSections
        theta = pi * (2*sec - 1) / (2*order)
        sinhMu = sinh(sinhVal)
        coshMu = cosh(sinhVal)
        sinTheta = sin(theta)
        cosTheta = cos(theta)
        
        s_re = sinhMu * sinTheta
        s_im = coshMu * cosTheta
        magSq = s_re^2 + s_im^2
        
        pole_re = -s_re / magSq
        pole_im = s_im / magSq
        @analogToDigitalSOS: sec, pole_re, pole_im
    endfor

else
    # ELLIPTIC (simplified)
    epsilon = sqrt(10^(passband_ripple_db/10) - 1)
    sinhVal = arcsinh(1/epsilon) / order
    
    for sec from 1 to nSections
        theta = pi * (2*sec - 1) / (2*order)
        pole_re = -0.95 * sinh(sinhVal) * sin(theta)
        pole_im = 0.95 * cosh(sinhVal) * cos(theta)
        @analogToDigitalSOS: sec, pole_re, pole_im
    endfor
endif

# Transform to highpass if needed
if filter_mode = 2
    @transformHighpass
endif

appendInfoLine: "Filter design complete."

# ============================================================
# Apply filter
# ============================================================
if apply_filter
    if fast_mode
        appendInfoLine: ""
        appendInfoLine: "[Fast mode] Using Praat built-in filters..."
        
        selectObject: sound
        
        if numChannels = 1
            if filter_mode = 1
                filtered = Filter (pass Hann band): 0, cutoff_frequency, cutoff_frequency * 0.1
            else
                filtered = Filter (pass Hann band): cutoff_frequency, nyquist * 0.99, cutoff_frequency * 0.1
            endif
        else
            Extract one channel: 1
            left = selected("Sound")
            
            selectObject: sound
            Extract one channel: 2
            right = selected("Sound")
            
            if filter_mode = 1
                selectObject: left
                filteredL = Filter (pass Hann band): 0, cutoff_frequency, cutoff_frequency * 0.1
                selectObject: right
                filteredR = Filter (pass Hann band): 0, cutoff_frequency, cutoff_frequency * 0.1
            else
                selectObject: left
                filteredL = Filter (pass Hann band): cutoff_frequency, nyquist * 0.99, cutoff_frequency * 0.1
                selectObject: right
                filteredR = Filter (pass Hann band): cutoff_frequency, nyquist * 0.99, cutoff_frequency * 0.1
            endif
            
            selectObject: filteredL, filteredR
            Combine to stereo
            filtered = selected("Sound")
            
            removeObject: left, right, filteredL, filteredR
        endif
        
        selectObject: filtered
        Scale peak: scale_peak
        Rename: originalName$ + "_" + filterTypeName$ + "_" + filterModeName$
        
        appendInfoLine: "Done!"
        
    else
        appendInfoLine: ""
        appendInfoLine: "[Custom IIR] Warning: This is slow for long files..."
        
        selectObject: sound
        filtered = Copy: originalName$ + "_" + filterTypeName$ + "_" + filterModeName$
        
        @applyCascadeFilter
        
        selectObject: filtered
        Scale peak: scale_peak
        
        appendInfoLine: "Done!"
    endif
endif

# ============================================================
# Plot responses
# ============================================================
if plot_responses or plot_zplane
    Erase all
    
    if plot_responses
        @plotFrequencyResponse
    endif
    
    if plot_zplane
        @plotZPlane
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

procedure analogToDigitalSOS: .sec, .pole_re, .pole_im
    warp = tan(pi * wn / 2)
    
    p_re = .pole_re * warp
    p_im = .pole_im * warp
    
    p_mag_sq = p_re^2 + p_im^2
    denom = (1 - p_re)^2 + p_im^2
    
    sos_a0[.sec] = 1
    sos_a1[.sec] = 2 * (p_mag_sq - 1) / denom
    sos_a2[.sec] = ((1 + p_re)^2 + p_im^2) / denom
    
    sos_b0[.sec] = 1
    sos_b1[.sec] = 2
    sos_b2[.sec] = 1
    
    dcGain = (sos_b0[.sec] + sos_b1[.sec] + sos_b2[.sec]) / (sos_a0[.sec] + sos_a1[.sec] + sos_a2[.sec])
    if abs(dcGain) > 0.0001
        sos_b0[.sec] = sos_b0[.sec] / dcGain
        sos_b1[.sec] = sos_b1[.sec] / dcGain
        sos_b2[.sec] = sos_b2[.sec] / dcGain
    endif
endproc

procedure transformHighpass
    for sec from 1 to nSections
        sos_b1[sec] = -sos_b1[sec]
        sos_a1[sec] = -sos_a1[sec]
    endfor
    
    totalGain = 1
    for sec from 1 to nSections
        numNyq = sos_b0[sec] - sos_b1[sec] + sos_b2[sec]
        denNyq = sos_a0[sec] - sos_a1[sec] + sos_a2[sec]
        if abs(denNyq) > 0.0001
            totalGain = totalGain * numNyq / denNyq
        endif
    endfor
    
    if abs(totalGain) > 0.0001 and nSections > 0
        gainPerSection = totalGain ^ (1 / nSections)
        for sec from 1 to nSections
            sos_b0[sec] = sos_b0[sec] / gainPerSection
            sos_b1[sec] = sos_b1[sec] / gainPerSection
            sos_b2[sec] = sos_b2[sec] / gainPerSection
        endfor
    endif
endproc

procedure applyCascadeFilter
    selectObject: filtered
    ns = Get number of samples
    nc = Get number of channels
    
    for ch from 1 to nc
        for sec from 1 to nSections
            w1 = 0
            w2 = 0
            
            for n from 1 to ns
                if nc = 1
                    xVal = Get value at sample number: 1, n
                else
                    xVal = Get value at sample number: ch, n
                endif
                
                yVal = sos_b0[sec] * xVal + w1
                w1 = sos_b1[sec] * xVal - sos_a1[sec] * yVal + w2
                w2 = sos_b2[sec] * xVal - sos_a2[sec] * yVal
                
                if nc = 1
                    Set value at sample number: 1, n, yVal
                else
                    Set value at sample number: ch, n, yVal
                endif
                
                if n mod 20000 = 0
                    pct = floor((((ch-1) * nSections + sec - 1) * ns + n) / (nc * nSections * ns) * 100)
                    appendInfoLine: "  ", pct, "%"
                endif
            endfor
        endfor
    endfor
endproc

procedure plotFrequencyResponse
    npts = 512
    
    for i from 1 to npts
        freq[i] = (i - 1) * nyquist / npts
        omega = pi * (i - 1) / npts
        
        h_re = 1
        h_im = 0
        
        for sec from 1 to nSections
            cos1 = cos(omega)
            sin1 = sin(omega)
            cos2 = cos(2 * omega)
            sin2 = sin(2 * omega)
            
            num_re = sos_b0[sec] + sos_b1[sec] * cos1 + sos_b2[sec] * cos2
            num_im = -sos_b1[sec] * sin1 - sos_b2[sec] * sin2
            
            den_re = sos_a0[sec] + sos_a1[sec] * cos1 + sos_a2[sec] * cos2
            den_im = -sos_a1[sec] * sin1 - sos_a2[sec] * sin2
            
            denMag = den_re^2 + den_im^2
            if denMag > 0.0000001
                sec_re = (num_re * den_re + num_im * den_im) / denMag
                sec_im = (num_im * den_re - num_re * den_im) / denMag
            else
                sec_re = 0
                sec_im = 0
            endif
            
            temp_re = h_re * sec_re - h_im * sec_im
            temp_im = h_re * sec_im + h_im * sec_re
            h_re = temp_re
            h_im = temp_im
        endfor
        
        mag = sqrt(h_re^2 + h_im^2)
        if mag > 0.0000001
            magDb[i] = 20 * log10(mag)
        else
            magDb[i] = -100
        endif
        
        if magDb[i] < -80
            magDb[i] = -80
        endif
        
        phase[i] = arctan2(h_im, h_re) * 180 / pi
    endfor
    
    # PANEL 1: Magnitude
    if plot_zplane
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
    
    Colour: "{0.3, 0.7, 0.3}"
    Draw line: cutoff_frequency, -80, cutoff_frequency, 10
    
    Colour: "{0.8, 0.1, 0.1}"
    Line width: 2
    for i from 2 to npts
        Draw line: freq[i-1], magDb[i-1], freq[i], magDb[i]
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "dB"
    Text top: "no", "##" + filterTypeName$ + " " + filterModeName$ + " Order " + string$(order) + "##"
    Marks left every: 1, 20, "yes", "yes", "no"
    
    if nyquist > 10000
        Marks bottom every: 1, 5000, "yes", "yes", "no"
    elsif nyquist > 5000
        Marks bottom every: 1, 2000, "yes", "yes", "no"
    else
        Marks bottom every: 1, 1000, "yes", "yes", "no"
    endif
    
    # PANEL 2: Phase
    if plot_zplane
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
    
    Colour: "{0.3, 0.7, 0.3}"
    Draw line: cutoff_frequency, -180, cutoff_frequency, 180
    
    Colour: "{0.1, 0.3, 0.8}"
    Line width: 2
    for i from 2 to npts
        diff = phase[i] - phase[i-1]
        if abs(diff) < 150
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

procedure plotZPlane
    poleCount = 0
    zeroCount = 0
    
    for sec from 1 to nSections
        if abs(sos_b0[sec]) > 0.0001
            discriminant = sos_b1[sec]^2 - 4 * sos_b0[sec] * sos_b2[sec]
            
            if discriminant >= 0
                sqrtDisc = sqrt(discriminant)
                zeroCount += 1
                zeroRe[zeroCount] = (-sos_b1[sec] + sqrtDisc) / (2 * sos_b0[sec])
                zeroIm[zeroCount] = 0
                
                zeroCount += 1
                zeroRe[zeroCount] = (-sos_b1[sec] - sqrtDisc) / (2 * sos_b0[sec])
                zeroIm[zeroCount] = 0
            else
                sqrtDisc = sqrt(-discriminant)
                zeroCount += 1
                zeroRe[zeroCount] = -sos_b1[sec] / (2 * sos_b0[sec])
                zeroIm[zeroCount] = sqrtDisc / (2 * sos_b0[sec])
                
                zeroCount += 1
                zeroRe[zeroCount] = -sos_b1[sec] / (2 * sos_b0[sec])
                zeroIm[zeroCount] = -sqrtDisc / (2 * sos_b0[sec])
            endif
        endif
        
        if abs(sos_a0[sec]) > 0.0001
            discriminant = sos_a1[sec]^2 - 4 * sos_a0[sec] * sos_a2[sec]
            
            if discriminant >= 0
                sqrtDisc = sqrt(discriminant)
                poleCount += 1
                poleRe[poleCount] = (-sos_a1[sec] + sqrtDisc) / (2 * sos_a0[sec])
                poleIm[poleCount] = 0
                
                poleCount += 1
                poleRe[poleCount] = (-sos_a1[sec] - sqrtDisc) / (2 * sos_a0[sec])
                poleIm[poleCount] = 0
            else
                sqrtDisc = sqrt(-discriminant)
                poleCount += 1
                poleRe[poleCount] = -sos_a1[sec] / (2 * sos_a0[sec])
                poleIm[poleCount] = sqrtDisc / (2 * sos_a0[sec])
                
                poleCount += 1
                poleRe[poleCount] = -sos_a1[sec] / (2 * sos_a0[sec])
                poleIm[poleCount] = -sqrtDisc / (2 * sos_a0[sec])
            endif
        endif
    endfor
    
    Select outer viewport: 1, 5, 4.5, 8.5
    Select inner viewport: 1.3, 4.7, 4.8, 8.2
    
    Axes: -1.5, 1.5, -1.5, 1.5
    
    Colour: "{0.3, 0.3, 0.8}"
    Line width: 2
    nCirc = 72
    for ang from 1 to nCirc
        rad1 = (ang - 1) * 2 * pi / nCirc
        rad2 = ang * 2 * pi / nCirc
        Draw line: cos(rad1), sin(rad1), cos(rad2), sin(rad2)
    endfor
    
    Line width: 1
    Colour: "{0.7, 0.7, 0.7}"
    Draw line: -1.5, 0, 1.5, 0
    Draw line: 0, -1.5, 0, 1.5
    
    Colour: "{0, 0.7, 0}"
    Line width: 3
    markerSize = 0.08
    for i from 1 to zeroCount
        for ang from 1 to 24
            rad1 = (ang - 1) * 2 * pi / 24
            rad2 = ang * 2 * pi / 24
            Draw line: zeroRe[i] + markerSize * cos(rad1), zeroIm[i] + markerSize * sin(rad1), zeroRe[i] + markerSize * cos(rad2), zeroIm[i] + markerSize * sin(rad2)
        endfor
    endfor
    
    Colour: "{0.8, 0, 0}"
    Line width: 3
    for i from 1 to poleCount
        Draw line: poleRe[i] - markerSize, poleIm[i] - markerSize, poleRe[i] + markerSize, poleIm[i] + markerSize
        Draw line: poleRe[i] - markerSize, poleIm[i] + markerSize, poleRe[i] + markerSize, poleIm[i] - markerSize
    endfor
    
    Line width: 1
    Black
    Draw inner box
    Text left: "yes", "Im"
    Text bottom: "yes", "Re"
    Text top: "no", "##Z-Plane## (X=poles, O=zeros)"
    Marks left every: 1, 0.5, "yes", "yes", "no"
    Marks bottom every: 1, 0.5, "yes", "yes", "no"
endproc