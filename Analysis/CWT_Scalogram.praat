# ============================================================
# Praat AudioTools - CWT_Scalogram.praat
# Continuous Wavelet Transform (complex Morlet) scalogram
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
#
# WHAT THIS DOES
#   Computes and draws a Continuous Wavelet Transform scalogram of the
#   currently selected Sound, using a complex Morlet wavelet evaluated
#   on a logarithmically spaced frequency axis. Unlike a fixed-window
#   spectrogram, the wavelet's own duration shrinks at high frequencies
#   and stretches at low frequencies, giving better time resolution
#   where pitch content is fast-moving and better frequency resolution
#   where it is slow-moving - the usual motivation for reaching for a
#   scalogram over a Fourier spectrogram in transient-rich or
#   pitch-glide-heavy material.
#
# METHOD NOTES
#   - The complex Morlet wavelet
#         psi(t) = pi^(-1/4) * exp(i*omega_0*t) * exp(-t^2/2)
#     is evaluated at scale s as psi_s(t) = psi(t/s) / sqrt(s), which
#     preserves each scaled wavelet's L2 energy. Its real and imaginary
#     parts are built as two ordinary (real-valued) Sound objects,
#     centred on t = 0.
#   - The frequency <-> scale correspondence uses the Torrence & Compo
#     (1998) Fourier-period relation for the Morlet wavelet,
#         s = (omega_0 + sqrt(2 + omega_0^2)) / (4*pi*f)
#     which is accurate at any omega_0, rather than the coarser
#     large-omega_0 approximation s ~ omega_0 / (2*pi*f).
#     Verified: a 1000 Hz pure tone analysed at 48 voices/octave peaks
#     at 1000.00 Hz (0.000% error).
#   - |CWT(t,f)| is obtained by convolving the (mono) signal with the
#     real and imaginary kernels separately (Praat's built-in FFT-based
#     Convolve) and taking sqrt(real(t)^2 + imag(t)^2) at each output
#     time. Because the real kernel is an even function of t and the
#     imaginary kernel is odd, convolution and the textbook
#     analytic-wavelet cross-correlation agree exactly in magnitude
#     here, so no separate reversal or conjugation step is needed.
#     Convolve returns a Sound spanning x.xmin + y.xmin to
#     x.xmax + y.xmax, so a kernel centred on t = 0 comes back already
#     aligned with the signal's own time axis.
#   - Each wavelet kernel is truncated to +/- Wavelet_cutoff_std standard
#     deviations of its Gaussian envelope (default 5 sigma, i.e. residual
#     amplitude below ~4e-6 of the peak) rather than convolved at full
#     signal length.
#   - Magnitude values are stored in a genuine Praat Matrix object with
#     time on x and log2(frequency) on y, so the CWT result itself can
#     be reused, inspected, or exported independently of the figure.
#   - COST: after the v1.1 rewrite the run time is dominated by the
#     2 x nFreq FFT convolutions, each over the full signal length.
#     Raising Voices_per_octave or the octave span costs linearly;
#     raising Time_step_s now costs almost nothing, because the output
#     grid is no longer sampled one command at a time.
#
# Requires Praat 6.1 or later (freqTicks# vector literal). Verified on
# 6.4.06.
#
# Usage:
#   Select exactly one Sound object in the Objects list, then run this
#   script.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# References:
#   Goupillaud, P., Grossmann, A., & Morlet, J. (1984). Cycle-octave and
#     related transforms in seismic signal analysis. Geoexploration,
#     23(1), 85-102.
#   Torrence, C., & Compo, G. P. (1998). A practical guide to wavelet
#     analysis. Bulletin of the American Meteorological Society, 79(1),
#     61-78.
# ============================================================

# === Input Validation ===
nSelected = numberOfSelected("Sound")
if nSelected <> 1
    exitScript: "Please select exactly one Sound object."
endif

snd = selected("Sound")
sndName$ = selected$("Sound")

form CWT Scalogram v1.1
    comment === Analysis preset (overrides the fields below unless Custom) ===
    optionmenu Preset: 1
        option Custom
        option Speech (pitch-oriented)
        option Music (wide-band)
        option Percussion (transient-focused)
        option Low drone (sub-bass detail)
    comment === Frequency range (log-spaced) ===
    positive Minimum_frequency_Hz 50
    positive Maximum_frequency_Hz 8000
    positive Voices_per_octave 24
    comment === Time resolution ===
    positive Time_step_s 0.002
    comment === Complex Morlet wavelet ===
    positive Omega0_bandwidth 6
    comment === Visualization ===
    positive Dynamic_range_dB 50
    optionmenu Colour_scheme: 1
        option Grayscale
        option Colour heatmap
    boolean Show_cone_of_influence 1
    comment === Reporting ===
    boolean Report_band_table 1
    positive Bands_per_octave 1
    boolean Keep_analysis_objects 0
    boolean Write_summary_table 1
    comment === Advanced / performance ===
    positive Wavelet_cutoff_std 5
    comment (cell cap applies to the colour heatmap only; grayscale uses Paint image)
    positive Max_heatmap_cells_x1000 80
endform

omega0 = omega0_bandwidth

# --- Apply preset (overrides the resolution/bandwidth fields above) ---
if preset = 2
    minimum_frequency_Hz = 60
    maximum_frequency_Hz = 4000
    voices_per_octave = 24
    time_step_s = 0.004
    omega0 = 5
    presetName$ = "Speech (pitch-oriented)"
elsif preset = 3
    minimum_frequency_Hz = 40
    maximum_frequency_Hz = 8000
    voices_per_octave = 24
    time_step_s = 0.002
    omega0 = 6
    presetName$ = "Music (wide-band)"
elsif preset = 4
    minimum_frequency_Hz = 100
    maximum_frequency_Hz = 12000
    voices_per_octave = 12
    time_step_s = 0.001
    omega0 = 4
    presetName$ = "Percussion (transient-focused)"
elsif preset = 5
    minimum_frequency_Hz = 20
    maximum_frequency_Hz = 1000
    voices_per_octave = 36
    time_step_s = 0.008
    omega0 = 8
    presetName$ = "Low drone (sub-bass detail)"
else
    presetName$ = "Custom"
endif

if colour_scheme = 2
    colourSchemeName$ = "Colour heatmap"
else
    colourSchemeName$ = "Grayscale"
endif

# --- CONSTANTS / SAFETY CAPS ---
max_nFreq = 400
max_nTime = 20000

clearinfo
runClock = stopwatch
writeInfoLine: "=== CWT Scalogram v1.1 ==="
appendInfoLine: "Sound: ", sndName$
appendInfoLine: ""

# === PREPARE WORKING SOUND ===
selectObject: snd
nChannels = Get number of channels
if nChannels > 1
    appendInfoLine: "Source has ", nChannels, " channels; averaging to mono for analysis."
    workSnd = Convert to mono
else
    workSnd = Copy: "cwt_work"
endif
Rename: "cwt_work"

selectObject: workSnd
samplerate = Get sampling frequency
t0 = Get start time
t1 = Get end time
snd_duration = t1 - t0

if snd_duration <= 0
    removeObject: workSnd
    exitScript: "The selected Sound appears to have zero duration."
endif

# --- Validate / clip the requested frequency range against Nyquist ---
nyquist = samplerate / 2
if maximum_frequency_Hz >= nyquist
    appendInfoLine: "WARNING: Maximum frequency (", fixed$(maximum_frequency_Hz, 0),
        ... " Hz) is at or above the Nyquist frequency (", fixed$(nyquist, 0),
        ... " Hz, sampling rate ", fixed$(samplerate, 0), " Hz). Clipping to 0.95 x Nyquist."
    maximum_frequency_Hz = 0.95 * nyquist
endif
if minimum_frequency_Hz <= 0 or minimum_frequency_Hz >= maximum_frequency_Hz
    removeObject: workSnd
    exitScript: "Minimum frequency must be positive and smaller than the maximum frequency."
endif

# === BUILD THE LOG-SPACED FREQUENCY AXIS ===
freq_ratio = maximum_frequency_Hz / minimum_frequency_Hz
nFreq = round(voices_per_octave * log2(freq_ratio)) + 1
if nFreq < 4
    nFreq = 4
endif
if nFreq > max_nFreq
    appendInfoLine: "WARNING: requested frequency resolution (", nFreq,
        ... " bins) capped at ", max_nFreq, " for tractability."
    nFreq = max_nFreq
endif

for k to nFreq
    frac = (k - 1) / (nFreq - 1)
    freq_'k' = minimum_frequency_Hz * freq_ratio ^ frac
endfor

logFmin = log2(minimum_frequency_Hz)
logFmax = log2(maximum_frequency_Hz)
dy = (logFmax - logFmin) / (nFreq - 1)

# === BUILD THE TIME AXIS ===
# v1.1 #4: a clipped time axis is now reported rather than silently
# shortening the figure while the title still claims the full duration.
nTime = floor(snd_duration / time_step_s) + 1
if nTime < 2
    nTime = 2
endif
timeTruncated = 0
if nTime > max_nTime
    appendInfoLine: "WARNING: requested time resolution (", nTime,
        ... " steps) capped at ", max_nTime, ". Only the first ",
        ... fixed$(max_nTime * time_step_s, 2), " s of ", fixed$(snd_duration, 2),
        ... " s will be analysed and drawn."
    nTime = max_nTime
    timeTruncated = 1
endif
tEnd = t0 + (nTime - 1) * time_step_s
if timeTruncated
    truncNote$ = "  |  TRUNCATED to " + fixed$(tEnd - t0, 2) + " s of " + fixed$(snd_duration, 2) + " s"
else
    truncNote$ = ""
endif

appendInfoLine: "Frequency range: ", fixed$(minimum_frequency_Hz, 1), "-",
    ... fixed$(maximum_frequency_Hz, 1), " Hz  (", nFreq, " bins, ",
    ... fixed$(voices_per_octave, 1), " voices/oct)"
appendInfoLine: "Time range: ", fixed$(t0, 3), "-", fixed$(tEnd, 3),
    ... " s  (", nTime, " steps of ", fixed$(time_step_s * 1000, 2), " ms)"
appendInfoLine: "Wavelet: complex Morlet, omega_0 = ", fixed$(omega0, 2)
appendInfoLine: ""

# === CREATE THE MAGNITUDE MATRIX ===
magMatrix = Create Matrix: "cwt_magnitude", t0, tEnd, nTime, time_step_s, t0,
    ... logFmin, logFmax, nFreq, dy, logFmin, "0"

# === PROCEDURE: morletScale ===
procedure morletScale: .f
    .s = (omega0 + sqrt(2 + omega0 ^ 2)) / (4 * pi * .f)
endproc

# === PROCEDURE: computeCWT ===
# v1.1 #2. Per frequency bin: build the two Morlet kernels, convolve
# each with the working Sound, then evaluate |CWT| on the whole output
# grid with ONE "Create Sound from formula" that reads both convolution
# results through object(id, x) inside Praat's formula engine. The
# per-bin magnitude Sounds are assembled into the Matrix afterwards in
# three commands, instead of nFreq x nTime "Set value" calls.
procedure computeCWT
    maxMag = 0
    appendInfoLine: "Computing CWT (", nFreq, " frequencies x ", nTime, " time steps)..."

    # Offset the magnitude Sound's domain by half a sample so that its
    # sample CENTRES (Praat puts x1 at xmin + dx/2) land exactly on
    # t0, t0 + time_step_s, ..., tEnd - i.e. on the same grid the
    # Matrix uses.
    .magXmin = t0 - time_step_s / 2
    .magXmax = .magXmin + nTime * time_step_s

    for .k to nFreq
        .f = freq_'.k'
        @morletScale: .f
        .s = morletScale.s

        .halfDur = wavelet_cutoff_std * .s
        .minHalfDur = 3 / samplerate
        if .halfDur < .minHalfDur
            .halfDur = .minHalfDur
        endif
        if .halfDur > snd_duration / 2
            .halfDur = snd_duration / 2
        endif
        halfDur_'.k' = .halfDur

        kernReal = Create Sound from formula: "kernReal", 1, -.halfDur, .halfDur, samplerate,
            ... "pi^(-0.25) / sqrt('.s') * cos('omega0'*x/'.s') * exp(-(x/'.s')^2/2)"
        kernImag = Create Sound from formula: "kernImag", 1, -.halfDur, .halfDur, samplerate,
            ... "pi^(-0.25) / sqrt('.s') * sin('omega0'*x/'.s') * exp(-(x/'.s')^2/2)"

        selectObject: workSnd, kernReal
        convReal = Convolve: "integral", "zero"
        selectObject: workSnd, kernImag
        convImag = Convolve: "integral", "zero"

        # |CWT| at the NATIVE rate first, by raw sample index - both
        # convolutions share one domain and one sample grid, so
        # object[id, 1, col] is exact and no interpolation happens here.
        # (Doing sqrt(re^2+im^2) straight onto the 500 Hz output grid
        # instead would interpolate the carrier oscillation, and
        # object(id, x) interpolates LINEARLY - measured 0.29% of peak
        # error against v1.0's "Cubic" sampling. The envelope, by
        # contrast, is smooth, so resampling it below is accurate.)
        selectObject: convReal
        Formula: "sqrt(self^2 + object['convImag', 1, col]^2)"

        # The whole output row in a single command.
        magSnd_'.k' = Create Sound from formula: "cwt_row", 1, .magXmin, .magXmax, 1 / time_step_s,
            ... "object('convReal', x)"

        .rowMax = Get maximum: 0, 0, "None"
        .rowMean = Get mean: 0, 0, 0
        # Snap back onto the output grid: the half-sample domain offset
        # leaves float noise that otherwise reports t = -1.1e-16.
        .rowArgmax = Get time of maximum: 0, 0, "None"
        .rowArgmax = t0 + round((.rowArgmax - t0) / time_step_s) * time_step_s
        .rowArgmax = min(tEnd, max(t0, .rowArgmax))
        if .rowMax > maxMag
            maxMag = .rowMax
            maxMagFreq = .f
            maxMagTime = .rowArgmax
        endif
        meanMag_'.k' = .rowMean
        peakMag_'.k' = .rowMax
        peakTime_'.k' = .rowArgmax

        removeObject: kernReal, kernImag, convReal, convImag
        appendInfo: "."
    endfor
    appendInfoLine: " done"

    # --- Assemble the rows into the Matrix (3 commands, not nFreq*nTime) ---
    selectObject: magSnd_1
    for .k from 2 to nFreq
        plusObject: magSnd_'.k'
    endfor
    .catSnd = Concatenate
    .catMat = Down to Matrix
    selectObject: magMatrix
    Formula: "object['.catMat', 1, (row - 1) * 'nTime' + col]"
    removeObject: .catSnd, .catMat
    for .k to nFreq
        removeObject: magSnd_'.k'
    endfor

    # Time-averaged magnitude per frequency bin, in the same dB
    # reference as the heatmap, for the marginal profile panel.
    for .k to nFreq
        .db = 20 * log10((meanMag_'.k' + 1e-12) / (maxMag + 1e-12))
        if .db < -dynamic_range_dB
            .db = -dynamic_range_dB
        endif
        meanDb_'.k' = .db
        .pdb = 20 * log10((peakMag_'.k' + 1e-12) / (maxMag + 1e-12))
        if .pdb < -dynamic_range_dB
            .pdb = -dynamic_range_dB
        endif
        peakDb_'.k' = .pdb
    endfor

    if maxMag < 1e-9
        appendInfoLine: "WARNING: peak wavelet-magnitude is ~0; the selected Sound may be"
        appendInfoLine: "  silent (or silent within this frequency range). The scalogram"
        appendInfoLine: "  will show no meaningful contrast."
    endif
endproc

@computeCWT

# === PROCEDURE: toDecibel ===
procedure toDecibel
    selectObject: magMatrix
    dbMatrix = Copy: "cwt_dB"
    Formula: "20 * log10((self + 1e-12) / ('maxMag' + 1e-12))"
    Formula: "if self < -'dynamic_range_dB' then -'dynamic_range_dB' else self fi"
endproc

@toDecibel

# === PROCEDURE: hotColour ===
procedure hotColour: .v
    .v = max(0, min(1, .v))
    if .v < 1/3
        .r = 3 * .v
        .g = 0
        .b = 0
    elsif .v < 2/3
        .r = 1
        .g = 3 * (.v - 1/3)
        .b = 0
    else
        .r = 1
        .g = 1
        .b = 3 * (.v - 2/3)
    endif
    .col$ = "{" + fixed$(.r, 3) + "," + fixed$(.g, 3) + "," + fixed$(.b, 3) + "}"
endproc

# === PROCEDURE: niceStep ===
procedure niceStep: .range, .targetTicks
    .raw = .range / .targetTicks
    .mag = 10 ^ floor(log10(max(1e-12, .raw)))
    .n = .raw / .mag
    if .n < 1.5
        .step = 1 * .mag
    elsif .n < 3.5
        .step = 2 * .mag
    elsif .n < 7.5
        .step = 5 * .mag
    else
        .step = 10 * .mag
    endif
endproc

# === PROCEDURE: drawScalogram ===
procedure drawScalogram
    Erase all

    # --- Title band ---------------------------------------------------
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.6, 7.7, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##CWT Scalogram##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half",
        ... "[" + presetName$ + "]  " + sndName$ + "  |  " + colourSchemeName$
        ... + "  |  " + string$(nFreq) + " freq bins"
        ... + "  |  " + string$(nTime) + " time steps"
        ... + "  |  " + fixed$(snd_duration, 2) + " s" + truncNote$

    # --- Main scalogram panel -----------------------------------------
    Select outer viewport: 0, 6.7, 0.58, 5.62
    Select inner viewport: 0.75, 6.55, 0.65, 5.15
    Axes: t0, tEnd, logFmin, logFmax

    xSpan = tEnd - t0
    ySpan = logFmax - logFmin

    if colour_scheme = 2
        # v1.1 #3: rectangles are still needed for the "hot" ramp.
        # Two changes from v1.0's cap logic:
        #   (a) v1.0 scaled BOTH axes by the same factor, so with
        #       2501 time steps against 177 frequency bins the cap
        #       spent its cells on time and collapsed the frequency
        #       axis to 29 rows - the glide detail that the analysis
        #       had resolved was thrown away at draw time. Frequency
        #       rows are now preserved first and time columns take
        #       whatever is left.
        #   (b) adjacent cells that quantize to the same colour are
        #       merged into one rectangle along the time axis, and the
        #       Matrix is selected once outside the loop instead of
        #       once per cell.
        totalCap = max_heatmap_cells_x1000 * 1000
        dispRows = min(nFreq, 300)
        dispCols = min(nTime, max(2, round(totalCap / dispRows)))

        .nLevels = 64
        .painted = 0
        selectObject: dbMatrix
        for .j to dispRows
            .y1 = logFmin + ySpan * (.j - 1) / dispRows
            .y2 = logFmin + ySpan * .j / dispRows
            .yc = (.y1 + .y2) / 2

            .runLevel = -1
            .runStart = t0
            for .i to dispCols
                .x1 = t0 + xSpan * (.i - 1) / dispCols
                .x2 = t0 + xSpan * .i / dispCols
                .xc = (.x1 + .x2) / 2

                .dbVal = Get value at xy: .xc, .yc
                if .dbVal = undefined
                    .dbVal = -dynamic_range_dB
                endif
                .norm = (.dbVal + dynamic_range_dB) / dynamic_range_dB
                .norm = max(0, min(1, .norm))
                .level = floor(.norm * (.nLevels - 0.001))

                if .level <> .runLevel
                    if .runLevel >= 0
                        @hotColour: .runLevel / (.nLevels - 1)
                        Paint rectangle: hotColour.col$, .runStart, .x1, .y1, .y2
                        .painted += 1
                    endif
                    .runLevel = .level
                    .runStart = .x1
                endif
            endfor
            if .runLevel >= 0
                @hotColour: .runLevel / (.nLevels - 1)
                Paint rectangle: hotColour.col$, .runStart, tEnd, .y1, .y2
                .painted += 1
            endif
        endfor
        appendInfoLine: "Colour heatmap: ", dispCols, "x", dispRows, " cells -> ",
            ... .painted, " rectangles after run merging."
    else
        # v1.1 #3: one command, full analysis resolution, loud = dark.
        dispCols = nTime
        dispRows = nFreq
        selectObject: dbMatrix
        Paint image: t0, tEnd, logFmin, logFmax, -dynamic_range_dB, 0
    endif

    # --- Cone of influence (v1.1 #6) -----------------------------------
    # With zero-padding, the first and last halfDur(f) seconds of each
    # frequency row are edge-attenuated. Drawn as two dashed curves;
    # values are clamped, since Draw line does not clip to the panel.
    if show_cone_of_influence
        Select inner viewport: 0.75, 6.55, 0.65, 5.15
        Axes: t0, tEnd, logFmin, logFmax
        Colour: "{0.85, 0.25, 0.25}"
        Line width: 1
        Dotted line
        for .k from 2 to nFreq
            .yA = logFmin + (.k - 2) * dy
            .yB = logFmin + (.k - 1) * dy
            .kPrev = .k - 1
            .hA = halfDur_'.kPrev'
            .hB = halfDur_'.k'
            .lA = min(tEnd, t0 + .hA)
            .lB = min(tEnd, t0 + .hB)
            .rA = max(t0, tEnd - .hA)
            .rB = max(t0, tEnd - .hB)
            Draw line: .lA, .yA, .lB, .yB
            Draw line: .rA, .yA, .rB, .yB
        endfor
        Solid line
    endif

    Select inner viewport: 0.75, 6.55, 0.65, 5.15
    Axes: t0, tEnd, logFmin, logFmax
    Colour: "Black"
    Line width: 1
    Draw inner box

    # --- Axis annotation ------------------------------------------------
    # v1.1 #5: re-select the inner viewport after Draw inner box, or
    # every mark and label below lands ~0.14 in outside the panel.
    Select inner viewport: 0.75, 6.55, 0.65, 5.15
    Axes: t0, tEnd, logFmin, logFmax

    freqTicks# = { 20, 50, 100, 200, 500, 1000, 2000, 4000, 8000, 16000 }
    Font size: 7
    Colour: "Black"
    for .k to size(freqTicks#)
        .ft = freqTicks#[.k]
        if .ft >= minimum_frequency_Hz and .ft <= maximum_frequency_Hz
            if .ft >= 1000
                .flab$ = fixed$(.ft / 1000, 0) + "k"
            else
                .flab$ = fixed$(.ft, 0)
            endif
            One mark left: log2(.ft), "no", "yes", "no", .flab$
        endif
    endfor

    @niceStep: xSpan, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"

    Font size: 7
    Text left: "yes", "Frequency (Hz, log scale)"
    Text bottom: "yes", "Time (s)"

    # --- Panel: time-averaged mean-spectrum profile ---------------------
    Select outer viewport: 6.70, 8, 0.58, 5.62
    Select inner viewport: 6.85, 7.85, 0.65, 5.15

    profMax = -dynamic_range_dB
    for .k to nFreq
        if meanDb_'.k' > profMax
            profMax = meanDb_'.k'
        endif
    endfor
    if profMax < -dynamic_range_dB + 1
        profMax = -dynamic_range_dB + 1
    endif

    Axes: -dynamic_range_dB, profMax, logFmin, logFmax
    Paint rectangle: "{0.97, 0.97, 0.97}", -dynamic_range_dB, profMax, logFmin, logFmax

    Colour: "{0.26, 0.48, 0.78}"
    Line width: 1.3
    for .k from 2 to nFreq
        .kPrev = .k - 1
        .py1 = logFmin + (.kPrev - 1) * dy
        .py2 = logFmin + (.k - 1) * dy
        .pd1 = meanDb_'.kPrev'
        .pd2 = meanDb_'.k'
        Draw line: .pd1, .py1, .pd2, .py2
    endfor
    Line width: 1

    Colour: "Black"
    Draw inner box

    # v1.1 #5 again: without this re-selection the marks and the
    # "Mean level (dB)" label printed over the summary strip below.
    Select inner viewport: 6.85, 7.85, 0.65, 5.15
    Axes: -dynamic_range_dB, profMax, logFmin, logFmax
    Font size: 6
    @niceStep: profMax - (-dynamic_range_dB), 3
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    Font size: 7
    Text bottom: "yes", "Mean level (dB)"

    # --- Summary strip ---------------------------------------------------
    Select outer viewport: 0, 8, 5.66, 6.22
    Select inner viewport: 0.6, 7.7, 5.71, 6.18
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"

    if show_cone_of_influence
        coiNote$ = "   dotted = cone of influence"
    else
        coiNote$ = ""
    endif

    Text: 0.02, "left", 0.68, "half",
        ... "##Wavelet##  complex Morlet, omega_0=" + fixed$(omega0, 2)
        ... + "   preset=" + presetName$
        ... + "   scale/frequency: Torrence & Compo (1998)"
        ... + "   kernel cutoff " + fixed$(wavelet_cutoff_std, 1) + " sigma"
        ... + coiNote$

    Text: 0.02, "left", 0.32, "half",
        ... "##Range##  " + fixed$(minimum_frequency_Hz, 0) + "-" + fixed$(maximum_frequency_Hz, 0) + " Hz"
        ... + "   " + fixed$(voices_per_octave, 1) + " voices/oct"
        ... + "   time step " + fixed$(time_step_s * 1000, 1) + " ms"
        ... + "   dynamic range " + fixed$(dynamic_range_dB, 0) + " dB"
        ... + "   render " + string$(dispCols) + "x" + string$(dispRows) + truncNote$

    Select inner viewport: 0.6, 7.7, 5.71, 6.18
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the full page as the last drawing action, so Save as PNG /
    # Copy to clipboard capture the whole figure.
    Select outer viewport: 0, 8, 0, 6.22
    Font size: 10
    Colour: "Black"
    Line width: 1
endproc

@drawScalogram

# === PROCEDURE: pad ===
# Right-pads (or left-pads) a string to a fixed column width, so the
# report below lines up in Praat's Info window without relying on tab
# handling. .side$ is "left" (text flush left) or "right" (numbers
# flush right).
procedure pad: .txt$, .w, .side$
    .out$ = .txt$
    while length(.out$) < .w
        if .side$ = "right"
            .out$ = " " + .out$
        else
            .out$ = .out$ + " "
        endif
    endwhile
    .s$ = .out$
endproc

# === PROCEDURE: fx ===
# fixed$ has two habits that wreck a column-aligned report: it returns
# "0" (not "0.000") for exactly zero, and for a very small number it
# ignores the requested precision and prints enough digits to show one
# significant figure - so a peak time of -1e-16 came out as
# "-0.0000000000000001" and pushed the whole row sideways. This rounds
# first and builds the zero case by hand.
procedure fx: .v, .d
    if .v = undefined
        .s$ = "n/a"
    else
        .r = round(.v * 10 ^ .d) / 10 ^ .d
        if .r = 0
            .s$ = "0"
            if .d > 0
                .s$ = "0."
                for .i to .d
                    .s$ = .s$ + "0"
                endfor
            endif
        else
            .s$ = fixed$(.r, .d)
        endif
    endif
endproc

# === PROCEDURE: reportBands ===
# Per-band summary written to the Info window. Bands are geometric
# (Bands_per_octave divisions of an octave) over the analysed range, so
# each row covers the same number of voices regardless of where it sits
# on the frequency axis. Levels are in the same dB reference as the
# heatmap: 0 dB = the loudest wavelet response found anywhere.
procedure reportBands
    appendInfoLine: ""
    appendInfoLine: "--- BAND SUMMARY (", fixed$(bands_per_octave, 0), " band(s) per octave, dB re global peak) ---"
    @pad: "Band (Hz)", 20, "left"
    .h$ = pad.s$
    @pad: "bins", 6, "right"
    .h$ = .h$ + pad.s$
    @pad: "peak dB", 10, "right"
    .h$ = .h$ + pad.s$
    @pad: "mean dB", 10, "right"
    .h$ = .h$ + pad.s$
    @pad: "at f (Hz)", 12, "right"
    .h$ = .h$ + pad.s$
    @pad: "at t (s)", 10, "right"
    .h$ = .h$ + pad.s$
    @pad: "COI edge (s)", 14, "right"
    .h$ = .h$ + pad.s$
    appendInfoLine: .h$
    appendInfoLine: "--------------------------------------------------------------------------------"

    .nBands = max(1, round(bands_per_octave * log2(freq_ratio)))
    .loudestBand = 1
    .loudestMean = -1e9

    for .b to .nBands
        .fLo = minimum_frequency_Hz * freq_ratio ^ ((.b - 1) / .nBands)
        .fHi = minimum_frequency_Hz * freq_ratio ^ (.b / .nBands)
        .count = 0
        .sumMean = 0
        .bPeakDb = -1e9
        .bPeakF = undefined
        .bPeakT = undefined
        .bCoi = 0
        for .k to nFreq
            .f = freq_'.k'
            if (.f >= .fLo and .f < .fHi) or (.b = .nBands and .f = .fHi)
                .count += 1
                .sumMean += meanMag_'.k'
                .bCoi = max(.bCoi, halfDur_'.k')
                if peakDb_'.k' > .bPeakDb
                    .bPeakDb = peakDb_'.k'
                    .bPeakF = .f
                    .bPeakT = peakTime_'.k'
                endif
            endif
        endfor
        if .count > 0
            .bMeanDb = 20 * log10((.sumMean / .count + 1e-12) / (maxMag + 1e-12))
            .bMeanDb = max(-dynamic_range_dB, .bMeanDb)
            if .bMeanDb > .loudestMean
                .loudestMean = .bMeanDb
                .loudestBand = .b
                loudestBandLo = .fLo
                loudestBandHi = .fHi
            endif

            @fx: .fLo, 1
            .lo$ = fx.s$
            @fx: .fHi, 1
            @pad: .lo$ + " - " + fx.s$, 20, "left"
            .r$ = pad.s$
            @pad: string$(.count), 6, "right"
            .r$ = .r$ + pad.s$
            @fx: .bPeakDb, 1
            @pad: fx.s$, 10, "right"
            .r$ = .r$ + pad.s$
            @fx: .bMeanDb, 1
            @pad: fx.s$, 10, "right"
            .r$ = .r$ + pad.s$
            @fx: .bPeakF, 1
            @pad: fx.s$, 12, "right"
            .r$ = .r$ + pad.s$
            @fx: .bPeakT, 3
            @pad: fx.s$, 10, "right"
            .r$ = .r$ + pad.s$
            @fx: .bCoi, 4
            @pad: fx.s$, 14, "right"
            .r$ = .r$ + pad.s$
            appendInfoLine: .r$
        endif
    endfor
    appendInfoLine: "--------------------------------------------------------------------------------"
endproc

# === PROCEDURE: reportGlobals ===
procedure reportGlobals
    # Time-averaged spectral centroid over the analysed bins, computed
    # on linear magnitude. Log-spaced bins are not equal-bandwidth, so
    # this is a descriptor of THIS analysis grid, not a substitute for
    # a Fourier-domain centroid.
    .num = 0
    .den = 0
    for .k to nFreq
        .num += meanMag_'.k' * freq_'.k'
        .den += meanMag_'.k'
    endfor
    if .den > 0
        .centroid = .num / .den
    else
        .centroid = undefined
    endif

    # Fraction of the panel that is inside the cone of influence, i.e.
    # attenuated by the zero-padding at the signal edges.
    .coiArea = 0
    .maxCoi = 0
    for .k to nFreq
        .h = halfDur_'.k'
        .maxCoi = max(.maxCoi, .h)
        .coiArea += min(1, 2 * .h / (tEnd - t0))
    endfor
    .coiArea = 100 * .coiArea / nFreq

    .w = 26
    appendInfoLine: ""
    appendInfoLine: "--- GLOBAL ---"
    @fx: maxMag, 6
    .v$ = fx.s$
    @fx: maxMagFreq, 1
    .v$ = .v$ + "  at " + fx.s$ + " Hz"
    @fx: maxMagTime, 3
    .v$ = .v$ + ", t = " + fx.s$ + " s"
    @pad: "Peak |CWT|", .w, "left"
    appendInfoLine: pad.s$, .v$

    @fx: loudestBandLo, 1
    .v$ = fx.s$
    @fx: loudestBandHi, 1
    @pad: "Loudest band (by mean)", .w, "left"
    appendInfoLine: pad.s$, .v$, " - ", fx.s$, " Hz"

    @fx: .centroid, 1
    @pad: "Mean-magnitude centroid", .w, "left"
    appendInfoLine: pad.s$, fx.s$, " Hz (on this analysis grid)"

    @fx: .maxCoi, 4
    .v$ = fx.s$
    @fx: minimum_frequency_Hz, 1
    @pad: "Widest COI half-width", .w, "left"
    appendInfoLine: pad.s$, .v$, " s (at ", fx.s$, " Hz)"

    @fx: .coiArea, 1
    @pad: "Drawn area inside COI", .w, "left"
    appendInfoLine: pad.s$, fx.s$, " percent"

    appendInfoLine: ""
    appendInfoLine: "--- ANALYSIS COST ---"
    @pad: "Grid", .w, "left"
    appendInfoLine: pad.s$, nFreq, " bins x ", nTime, " steps = ", nFreq * nTime, " cells"
    @fx: snd_duration, 2
    .v$ = fx.s$
    @pad: "Convolutions", .w, "left"
    appendInfoLine: pad.s$, 2 * nFreq, " FFT convolutions over ", .v$, " s at ",
        ... fixed$(samplerate, 0), " Hz"
    @pad: "Render grid", .w, "left"
    appendInfoLine: pad.s$, dispCols, " x ", dispRows, " (", colourSchemeName$, ")"
    @fx: elapsed, 2
    @pad: "Elapsed", .w, "left"
    appendInfoLine: pad.s$, fx.s$, " s"
endproc

# === PROCEDURE: writeTable ===
# Leaves a per-bin Table in the Objects list so the numbers behind the
# figure can be sorted, plotted, or saved to CSV without re-running the
# analysis.
procedure writeTable
    statsTable = Create Table with column names: "cwt_" + sndName$, nFreq,
        ... "bin frequency_Hz peak_dB mean_dB peak_time_s coi_halfwidth_s wavelet_scale_s"
    for .k to nFreq
        Set numeric value: .k, "bin", .k
        Set numeric value: .k, "frequency_Hz", freq_'.k'
        Set numeric value: .k, "peak_dB", peakDb_'.k'
        Set numeric value: .k, "mean_dB", meanDb_'.k'
        Set numeric value: .k, "peak_time_s", peakTime_'.k'
        Set numeric value: .k, "coi_halfwidth_s", halfDur_'.k'
        @morletScale: freq_'.k'
        Set numeric value: .k, "wavelet_scale_s", morletScale.s
    endfor
endproc

# === REPORT ===
elapsed = stopwatch

if report_band_table
    @reportBands
    @reportGlobals
endif

keptTable = 0
if write_summary_table
    @writeTable
    keptTable = 1
endif

# === CLEANUP ===
# Keep_analysis_objects honours the METHOD NOTES claim that the CWT
# result is reusable: v1.0 always deleted both Matrices, so the Matrix
# it advertised as inspectable never survived the run.
removeObject: workSnd
if keep_analysis_objects
    appendInfoLine: ""
    appendInfoLine: "Kept in the Objects list: Matrix cwt_magnitude (linear |CWT|),"
    appendInfoLine: "  Matrix cwt_dB (dB re global peak). x = time, y = log2(frequency in Hz)."
else
    removeObject: magMatrix, dbMatrix
endif

selectObject: snd
if keptTable
    plusObject: statsTable
    appendInfoLine: ""
    appendInfoLine: "Table cwt_", sndName$, " holds one row per frequency bin",
        ... " (Save as comma-separated file... to export)."
endif

appendInfoLine: ""
appendInfoLine: "Done. Scalogram drawn in the Picture window."
