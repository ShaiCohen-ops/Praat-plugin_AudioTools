# ============================================================
# Praat AudioTools - 8-Channel_Spectral_Shift.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.7 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Creates 8-voice frequency shift canons via FFT bin shifting.
#   Shifts spectrum up or down by specified number of bins.
#
# Changelog v0.7:
#   - Fixed: "Combine to stereo: sampling frequencies should be
#     equal" error. The Sound -> Spectrum -> Matrix -> Spectrum
#     -> To Sound roundtrip can introduce sub-sample-rate
#     floating-point drift between channels, which Combine
#     to stereo refuses to merge. Each shifted output is now
#     forced back to exactly the source sample rate via
#     Override sampling frequency before combination.
#   - Fixed: output duration. To Sound from a Spectrum returns
#     a sound padded out to the next power of two (often ~50%
#     longer than the input). Each channel is now Extract part
#     trimmed to the original duration before combination.
#     Side benefit: every downstream Combine to stereo runs
#     on the trimmed length instead of the padded length.
#   - Note on speed: the dominant cost in this script is the
#     8 inverse FFTs at the bottom of the per-channel loop.
#     For a 60 s 44.1 kHz file that is eight 4M-point IFFTs,
#     and Praat's FFT (FFTW) is already as fast as it can be
#     at that size. Further speedup on long files requires
#     chunked STFT processing, which is a future v0.8.
# Changelog v0.6:
#   - Speed: source spectrum and source Matrix computed ONCE,
#     shared across all 8 shifts (was 9 forward FFTs total).
#   - Speed: removed redundant per-channel Formula: "0".
#   - Speed: removed per-channel Sound copy.
# Changelog v0.5:
#   - Fixed: negative shifts produced silent channels (Matrix
#     Formula in-place overwrite). Now uses cross-Matrix
#     reference Matrix_shiftsrc[row, col +/- sInt] reading
#     from the unmodified source.
#   - Fixed: visualization bin->Hz conversion now reads
#     Get bin width directly from the source spectrum.
# Changelog v0.4:
#   - Resized visualization to 8x8 suite standard.
# ============================================================

form 8-Channel Spectral Shift
    comment === PRESETS ===
    optionmenu Preset: 1
        option: "Custom (use values below)"
        option: "Gentle Up (50-200 bins)"
        option: "Moderate Up (200-500 bins)"
        option: "Extreme Up (500-1500 bins)"
        option: "Symmetrical (up/down mirror)"
        option: "All Down (-100 to -400 bins)"
        option: "Spread (down to up)"
        option: "Cluster Up (small spread)"
        option: "Octave-like (doubling pattern)"

    comment === Bin shift amounts (positive=up, negative=down) ===
    integer Shift_1 100
    integer Shift_2 200
    integer Shift_3 300
    integer Shift_4 400
    integer Shift_5 -100
    integer Shift_6 -200
    integer Shift_7 -300
    integer Shift_8 -400

    comment === Output ===
    real Scale_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# === Apply Presets ===
if preset = 2
    shift_1 = 50
    shift_2 = 75
    shift_3 = 100
    shift_4 = 125
    shift_5 = 150
    shift_6 = 175
    shift_7 = 200
    shift_8 = 225
    presetName$ = "GentleUp"
elsif preset = 3
    shift_1 = 200
    shift_2 = 250
    shift_3 = 300
    shift_4 = 350
    shift_5 = 400
    shift_6 = 450
    shift_7 = 500
    shift_8 = 550
    presetName$ = "ModerateUp"
elsif preset = 4
    shift_1 = 500
    shift_2 = 650
    shift_3 = 800
    shift_4 = 950
    shift_5 = 1100
    shift_6 = 1250
    shift_7 = 1400
    shift_8 = 1550
    presetName$ = "ExtremeUp"
elsif preset = 5
    shift_1 = 400
    shift_2 = 300
    shift_3 = 200
    shift_4 = 100
    shift_5 = -100
    shift_6 = -200
    shift_7 = -300
    shift_8 = -400
    presetName$ = "Symmetrical"
elsif preset = 6
    shift_1 = -100
    shift_2 = -150
    shift_3 = -200
    shift_4 = -250
    shift_5 = -300
    shift_6 = -350
    shift_7 = -400
    shift_8 = -450
    presetName$ = "AllDown"
elsif preset = 7
    shift_1 = -400
    shift_2 = -250
    shift_3 = -100
    shift_4 = 0
    shift_5 = 0
    shift_6 = 100
    shift_7 = 250
    shift_8 = 400
    presetName$ = "Spread"
elsif preset = 8
    shift_1 = 100
    shift_2 = 110
    shift_3 = 120
    shift_4 = 130
    shift_5 = 140
    shift_6 = 150
    shift_7 = 160
    shift_8 = 170
    presetName$ = "ClusterUp"
elsif preset = 9
    shift_1 = 50
    shift_2 = 100
    shift_3 = 200
    shift_4 = 400
    shift_5 = -50
    shift_6 = -100
    shift_7 = -200
    shift_8 = -400
    presetName$ = "OctaveLike"
else
    presetName$ = "Custom"
endif

# === Check Input ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

selectObject: originalID
originalDur = Get total duration
sr = Get sampling frequency
nch = Get number of channels

# === Store shifts in array ===
shiftAmt[1] = shift_1
shiftAmt[2] = shift_2
shiftAmt[3] = shift_3
shiftAmt[4] = shift_4
shiftAmt[5] = shift_5
shiftAmt[6] = shift_6
shiftAmt[7] = shift_7
shiftAmt[8] = shift_8

# === Mono base ===
selectObject: originalID
if nch > 1
    Convert to mono
else
    Copy: "mono_work"
endif
monoID = selected("Sound")

# === Info ===
writeInfoLine: "=== 8-Channel Spectral Shift ==="
appendInfoLine: "Source: ", originalName$, "  (", fixed$(originalDur, 2), " s @ ", sr, " Hz)"
appendInfoLine: "Preset: ", presetName$

# ============================================================
# Compute shared source FFT and Matrix (ONCE, not 8 times)
# ============================================================
stopwatch
selectObject: monoID
To Spectrum: "yes"
sourceSpecID = selected("Spectrum")
binHz = Get bin width

To Matrix
sourceMatID = selected("Matrix")
Rename: "shiftsrc"
fftElapsed = stopwatch

appendInfoLine: "Bin width: ", fixed$(binHz, 3), " Hz   (forward FFT once: ", fixed$(fftElapsed, 2), " s)"
appendInfoLine: ""

# ============================================================
# Per-channel shift
# ============================================================
stopwatch
for ch from 1 to 8
    # Fresh destination matrix, copied from the (untouched) source
    selectObject: sourceMatID
    Copy: "shiftdst"
    matDstID = selected("Matrix")

    s = shiftAmt[ch]
    sInt = round(abs(s))

    # Read from Matrix_shiftsrc (unmodified), write to dst.
    selectObject: matDstID
    if s >= 0
        Formula: "if col - 'sInt' >= 1 then Matrix_shiftsrc[row, col - 'sInt'] else 0 fi"
        if s > 0
            dir$ = "+"
        else
            dir$ = " "
        endif
    else
        Formula: "if col + 'sInt' <= ncol then Matrix_shiftsrc[row, col + 'sInt'] else 0 fi"
        dir$ = ""
    endif

    # Back to Spectrum, then inverse FFT to Sound
    To Spectrum
    shiftedSpecID = selected("Spectrum")

    To Sound
    fullID = selected("Sound")

    # --- Force exact sample rate (kills floating-point drift) ---
    Override sampling frequency: sr

    # --- Trim from padded length back to original duration ---
    # Spectrum -> To Sound returns a sound padded out to the
    # next power of two of the original length (often ~50%
    # longer). Trimming here makes all downstream Combine
    # operations work on the real audio length, not the
    # padded length, AND guarantees all 8 channels have
    # identical duration (a Combine-to-stereo prerequisite
    # that bites in some Praat builds).
    selectObject: fullID
    Extract part: 0, originalDur, "rectangular", 1, "no"
    shifted[ch] = selected("Sound")
    Scale peak: scale_peak

    removeObject: fullID, matDstID, shiftedSpecID

    appendInfoLine: "  Ch", ch, ": ", dir$, s, " bins  (", fixed$(s * binHz, 1), " Hz)"
endfor
shiftElapsed = stopwatch
appendInfoLine: "(8 channels: ", fixed$(shiftElapsed, 2), " s)"

# === Source matrix and spectrum no longer needed ===
removeObject: sourceMatID, sourceSpecID

# === Combine all 8 channels (paired binary tree) ===
stopwatch

selectObject: shifted[1], shifted[2]
Combine to stereo
pair12 = selected("Sound")

selectObject: shifted[3], shifted[4]
Combine to stereo
pair34 = selected("Sound")

selectObject: shifted[5], shifted[6]
Combine to stereo
pair56 = selected("Sound")

selectObject: shifted[7], shifted[8]
Combine to stereo
pair78 = selected("Sound")

selectObject: pair12, pair34
Combine to stereo
quad1234 = selected("Sound")

selectObject: pair56, pair78
Combine to stereo
quad5678 = selected("Sound")

selectObject: quad1234, quad5678
Combine to stereo
result = selected("Sound")
Scale peak: scale_peak
Rename: originalName$ + "_8chSpectral_" + presetName$

combineElapsed = stopwatch
appendInfoLine: "(combine 8ch: ", fixed$(combineElapsed, 2), " s)"

# === Cleanup ===
removeObject: monoID
for ch from 1 to 8
    removeObject: shifted[ch]
endfor
removeObject: pair12, pair34, pair56, pair78, quad1234, quad5678

# ============================================================
# VISUALIZATION  (8 x 8 canvas — suite standard)
# ============================================================

if draw_visualization

    Erase all

    # Per-channel colour: blue = up, orange/red = down, grey = zero
    for ch from 1 to 8
        s = shiftAmt[ch]
        if s > 0
            intensity = s / 1600.0
            if intensity > 1
                intensity = 1
            endif
            chR[ch] = 0.22 + intensity * 0.08
            chG[ch] = 0.42 + intensity * 0.08
            chB[ch] = 0.80 + intensity * 0.15
            if chB[ch] > 1
                chB[ch] = 1
            endif
        elsif s < 0
            intensity = abs(s) / 1600.0
            if intensity > 1
                intensity = 1
            endif
            chR[ch] = 0.78 + intensity * 0.18
            if chR[ch] > 1
                chR[ch] = 1
            endif
            chG[ch] = 0.42 - intensity * 0.28
            if chG[ch] < 0
                chG[ch] = 0
            endif
            chB[ch] = 0.20 - intensity * 0.10
            if chB[ch] < 0
                chB[ch] = 0
            endif
        else
            chR[ch] = 0.60
            chG[ch] = 0.60
            chB[ch] = 0.60
        endif
    endfor

    # Axis range
    minShift = shiftAmt[1]
    maxShift = shiftAmt[1]
    for ch from 2 to 8
        if shiftAmt[ch] < minShift
            minShift = shiftAmt[ch]
        endif
        if shiftAmt[ch] > maxShift
            maxShift = shiftAmt[ch]
        endif
    endfor
    range = maxShift - minShift
    if range < 100
        range = 100
    endif
    plotMin = minShift - range * 0.18
    plotMax = maxShift + range * 0.18
    if plotMin > -50
        plotMin = -50
    endif
    if plotMax < 50
        plotMax = 50
    endif

    # ----------------------------------------------------------
    # TITLE BAR
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##8-CHANNEL SPECTRAL SHIFT##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.52}"
    Text: 0.5, "centre", -0.22, "half",
        ... originalName$
        ... + "  |  Preset: " + presetName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"
        ... + "  |  " + fixed$(binHz, 2) + " Hz/bin"

    # ----------------------------------------------------------
    # PANEL A: BIN SHIFT BAR CHART  (left column)
    # ----------------------------------------------------------
    Select outer viewport: 0, 4.2, 0.75, 4.60
    Select inner viewport: 0.38, 4.00, 0.85, 4.50

    Axes: 0.5, 8.5, plotMin, plotMax
    Paint rectangle: "{0.96, 0.96, 0.96}", 0.5, 8.5, plotMin, plotMax

    # Horizontal grid lines every 100 bins
    Colour: "{0.88, 0.88, 0.88}"
    Line width: 1
    gStep = 100
    gVal = 0
    while gVal <= plotMax
        Draw line: 0.5, gVal, 8.5, gVal
        gVal = gVal + gStep
    endwhile
    gVal = -gStep
    while gVal >= plotMin
        Draw line: 0.5, gVal, 8.5, gVal
        gVal = gVal - gStep
    endwhile

    # Zero line
    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw line: 0.5, 0, 8.5, 0
    Line width: 1

    for ch from 1 to 8
        s = shiftAmt[ch]
        xL = ch - 0.38
        xR = ch + 0.38

        if s >= 0
            Paint rectangle: "{" + string$(chR[ch]) + ", " + string$(chG[ch]) + ", " + string$(chB[ch]) + "}", xL, xR, 0, s
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: xL, xR, 0, s
        else
            Paint rectangle: "{" + string$(chR[ch]) + ", " + string$(chG[ch]) + ", " + string$(chB[ch]) + "}", xL, xR, s, 0
            Colour: "{0.30, 0.30, 0.30}"
            Draw rectangle: xL, xR, s, 0
        endif

        Font size: 6
        Colour: "White"
        if abs(s) > range * 0.12
            Text: ch, "centre", s / 2, "half", string$(s)
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: ch, "centre", plotMin + range * 0.06, "half", "Ch" + string$(ch)
    endfor

    Colour: "Black"
    Draw inner box
    Marks left every: 1, 100, "yes", "yes", "no"
    Font size: 6
    Text left: "yes", "Bins"
    Text bottom: "yes", "Channel  (blue = shift up,  orange = shift down)"

    # ----------------------------------------------------------
    # PANEL B: ACTUAL FREQUENCY SHIFT (Hz)  (right col, upper)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 0.75, 3.00
    Select inner viewport: 4.52, 7.75, 0.85, 2.92

    hzMin = plotMin * binHz
    hzMax = plotMax * binHz
    hzAbs = abs(hzMax)
    if abs(hzMin) > hzAbs
        hzAbs = abs(hzMin)
    endif
    if hzAbs < 5
        hzAbs = 5
    endif
    hzMin = -hzAbs * 1.05
    hzMax =  hzAbs * 1.05

    Axes: hzMin, hzMax, 0.5, 8.5
    Paint rectangle: "{0.96, 0.96, 0.96}", hzMin, hzMax, 0.5, 8.5

    Colour: "{0.75, 0.75, 0.75}"
    Dotted line
    Draw line: 0, 0.5, 0, 8.5
    Solid line

    for ch from 1 to 8
        y = 9 - ch
        yLo = y - 0.38
        yHi = y + 0.38
        hz = shiftAmt[ch] * binHz

        if hz >= 0
            Paint rectangle: "{" + string$(chR[ch]) + ", " + string$(chG[ch]) + ", " + string$(chB[ch]) + "}", 0, hz, yLo, yHi
        else
            Paint rectangle: "{" + string$(chR[ch]) + ", " + string$(chG[ch]) + ", " + string$(chB[ch]) + "}", hz, 0, yLo, yHi
        endif

        Font size: 5
        Colour: "{0.30, 0.30, 0.30}"
        Text: hzMin + (hzMax - hzMin) * 0.02, "left", y, "half", "Ch" + string$(ch)
        Colour: "White"
        if abs(hz) > (hzMax - hzMin) * 0.08
            Text: hz / 2, "centre", y, "half", fixed$(hz, 1) + " Hz"
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text left: "yes", "Ch"
    Text bottom: "yes", "Frequency shift (Hz)"

    # ----------------------------------------------------------
    # PANEL C: SHIFT DISTRIBUTION SCATTER  (right col, lower)
    # ----------------------------------------------------------
    Select outer viewport: 4.2, 8, 3.05, 4.60
    Select inner viewport: 4.52, 7.75, 3.12, 4.52

    Axes: plotMin - range * 0.05, plotMax + range * 0.05, -1.5, 1.5
    Paint rectangle: "{0.96, 0.96, 0.96}", plotMin - range * 0.05, plotMax + range * 0.05, -1.5, 1.5

    Colour: "{0.65, 0.65, 0.65}"
    Line width: 2
    Draw line: plotMin - range * 0.05, 0, plotMax + range * 0.05, 0
    Line width: 1

    Draw line: 0, -0.15, 0, 0.15

    Font size: 5
    Colour: "{0.50, 0.50, 0.50}"
    Text: plotMin - range * 0.04, "right", 0.75, "half", "up"
    Text: plotMin - range * 0.04, "right", -0.75, "half", "dn"

    upCount = 0
    dnCount = 0
    for ch from 1 to 8
        s = shiftAmt[ch]
        if s >= 0
            upCount = upCount + 1
            yDot = 0.55 + (upCount - 1) * 0.22
            if yDot > 1.35
                yDot = 1.35
            endif
        else
            dnCount = dnCount + 1
            yDot = -0.55 - (dnCount - 1) * 0.22
            if yDot < -1.35
                yDot = -1.35
            endif
        endif

        Paint circle (mm): "{" + string$(chR[ch]) + ", " + string$(chG[ch]) + ", " + string$(chB[ch]) + "}", s, yDot, 4.5
        Font size: 5
        Colour: "White"
        Text: s, "centre", yDot, "half", string$(ch)

        Colour: "{0.78, 0.78, 0.78}"
        Line width: 1
        if s >= 0
            Draw line: s, 0.12, s, yDot - 0.18
        else
            Draw line: s, -0.12, s, yDot + 0.18
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 5
    Text bottom: "yes", "Bin shift value  (above axis = up,  below = down)"

    # ----------------------------------------------------------
    # ALIGNED PANEL TITLES
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 0, 8
    Select inner viewport: 0, 8, 0, 8
    Axes: 0, 8, 0, 8

    Font size: 7
    Colour: "Black"
    Text: 2.10, "centre", 7.30, "half", "Bin shift per channel"
    Text: 6.10, "centre", 7.30, "half", "Freq. shift Hz (upper) & shift distribution (lower)"

    # ----------------------------------------------------------
    # PANEL D: OUTPUT WAVEFORM (full width)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 4.68, 5.75
    Select inner viewport: 0.55, 7.72, 4.75, 5.68

    selectObject: result
    outDurViz = Get total duration
    outPeak = Get absolute extremum: 0, 0, "None"
    if outPeak < 0.001
        outPeak = 0.001
    endif
    ampViz = outPeak * 1.15

    Axes: 0, outDurViz, -ampViz, ampViz
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, outDurViz, -ampViz, ampViz
    Colour: "{0.82, 0.82, 0.82}"
    Draw line: 0, 0, outDurViz, 0

    selectObject: result
    Extract one channel: 1
    vizCh1 = selected("Sound")
    Colour: "{0.25, 0.45, 0.78}"
    Line width: 1
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh1

    selectObject: result
    Extract one channel: 2
    vizCh2 = selected("Sound")
    Colour: "{0.82, 0.45, 0.25}"
    Draw: 0, 0, -ampViz, ampViz, "no", "Curve"
    removeObject: vizCh2

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text top: "no", "Output 8-ch mix  (blue = Ch1,  orange = Ch2)"
    Text left: "yes", "Amp"
    Text bottom: "yes", "Time (s)"

    # ----------------------------------------------------------
    # PANEL E: SUMMARY BAR (full width, bottom)
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 5.82, 6.58
    Select inner viewport: 0.55, 7.72, 5.88, 6.52
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    Font size: 6
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.75, "half",
        ... "##" + presetName$ + "##"
        ... + "  " + originalName$
        ... + "  |  " + fixed$(originalDur, 2) + " s"
        ... + "  |  @" + string$(sr) + " Hz"
        ... + "  |  " + fixed$(binHz, 2) + " Hz/bin"

    Text: 0.02, "left", 0.28, "half",
        ... "Ch1:" + string$(shiftAmt[1]) + "  "
        ... + "Ch2:" + string$(shiftAmt[2]) + "  "
        ... + "Ch3:" + string$(shiftAmt[3]) + "  "
        ... + "Ch4:" + string$(shiftAmt[4]) + "  "
        ... + "Ch5:" + string$(shiftAmt[5]) + "  "
        ... + "Ch6:" + string$(shiftAmt[6]) + "  "
        ... + "Ch7:" + string$(shiftAmt[7]) + "  "
        ... + "Ch8:" + string$(shiftAmt[8]) + "  bins"

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
    Line width: 1

endif

# === Done ===
appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Output: 8-channel spectral shift"

if play_result
    selectObject: result
    Play
endif

selectObject: result
