# ============================================================
# Praat AudioTools - SPEAR Par-Text-Frame Format Parser.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - Input source toggle: SPEAR text file OR analyse selected Sound (spectral peak-picking)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Parses SPEAR's "par-text-frame-format" text export and resynthesises
#   the partials back to sound via an additive (sine-bank) engine.
#
#   File format (one frame per line):
#     par-text-frame-format
#     point-type index frequency amplitude
#     partials-count <N>
#     frame-count <M>
#     frame-data
#     <time> <count> <index freq amp> <index freq amp> ...
#     ...
#
#   Resynthesis: for each frame, the loudest partials are summed as
#   windowed sines (Hann, 50% overlap) and overlap-added into a master
#   Sound. This keeps the cost to one Formula pass per frame (hundreds),
#   not one per partial (tens of thousands), so it stays tractable in
#   pure Praat.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form SPEAR Resynthesis v0.5
    optionmenu Input_source: 1
        option SPEAR text file
        option Selected Sound (analyse)
    sentence File_path C:/Users/User/Desktop/sounds/Cello.txt
    comment Sound-analysis only: max-freq, hop(s), peak-threshold
    positive Analysis_max_freq 8000
    positive Analysis_hop_s 0.01
    real Analysis_threshold 0.01
    optionmenu Preset: 1
        option Custom
        option Faithful
        option OctaveUp
        option OctaveDown
        option GlassBells
        option HollowClarinet
        option FrozenDrone
        option SlowMotion
        option Reversed
        option DarkPad
        option Shimmer
        option Inharmonic
        option LowBand
    natural Max_partials_per_frame 64
    real Amplitude_scale 1.0
    comment Frequency: transpose x, inharmonicity ^, shift +Hz
    real Transpose_ratio 1.0
    real Inharmonicity_exponent 1.0
    real Frequency_shift_Hz 0.0
    comment Spectral: brightness tilt, amp gate, band lo/hi Hz
    real Brightness_tilt 0.0
    real Amplitude_gate 0.0
    real Band_low_Hz 0.0
    real Band_high_Hz 20000.0
    optionmenu Harmonic_selection: 1
        option all partials
        option odd index only
        option even index only
    comment Time: stretch x, reverse, freeze-on-frame (0=off)
    real Time_stretch 1.0
    boolean Reverse 0
    integer Freeze_on_frame 0
    boolean Draw_visualization 1
    boolean Play_result 1
    boolean Build_partials_table 0
endform

# Output sample rate (kept out of the form to save space). For the Selected
# Sound source it is overridden to the input sound's rate during analysis.
sampling_frequency = 44100

# ---- PRESET OVERRIDE ----
# Each preset sets the full manipulation cluster. Custom (1) keeps form values.
# freeze_target is a FRACTION of the total frames (resolved after parsing) so a
# preset can freeze "the middle" without knowing the frame count yet.
presetName$ = "Custom"
freezeFrac = 0
if preset = 2
    presetName$ = "Faithful"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 3
    presetName$ = "OctaveUp"
    transpose_ratio = 2.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 4
    presetName$ = "OctaveDown"
    transpose_ratio = 0.5
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 5
    presetName$ = "GlassBells"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.3
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.4
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 6
    presetName$ = "HollowClarinet"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.01
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 2
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 7
    presetName$ = "FrozenDrone"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 2.0
    reverse = 0
    freezeFrac = 0.5
elsif preset = 8
    presetName$ = "SlowMotion"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 3.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 9
    presetName$ = "Reversed"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.5
    reverse = 1
    freeze_on_frame = 0
elsif preset = 10
    presetName$ = "DarkPad"
    transpose_ratio = 0.5
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = -0.5
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 2.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 11
    presetName$ = "Shimmer"
    transpose_ratio = 2.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.6
    amplitude_gate = 0.02
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 12
    presetName$ = "Inharmonic"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.15
    frequency_shift_Hz = 30.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 20000.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
elsif preset = 13
    presetName$ = "LowBand"
    transpose_ratio = 1.0
    inharmonicity_exponent = 1.0
    frequency_shift_Hz = 0.0
    brightness_tilt = 0.0
    amplitude_gate = 0.0
    band_low_Hz = 0.0
    band_high_Hz = 1500.0
    harmonic_selection = 1
    time_stretch = 1.0
    reverse = 0
    freeze_on_frame = 0
endif

clearinfo

if not fileReadable(file_path$)
    exitScript: "File not readable: " + file_path$
endif

# ============================================================
# INPUT - either parse a SPEAR text file, or analyse the selected
# Sound into partials (spectral peak-picking). Both paths fill the
# same arrays: frFreq[f,p], frAmp[f,p], frIdx[f,p], frN[f], frTime[f],
# plus hop, fileMaxAmp, frameIdx.
# ============================================================
if build_partials_table
    table = Create Table with column names: "spear_partials", 0, "frame time index frequency amplitude"
endif
fileMaxAmp = 0
frameIdx = 0

if input_source = 1
# ------------------------------------------------------------
# SOURCE A: SPEAR par-text-frame-format text file
# ------------------------------------------------------------

# ---- READ FILE ----
Read Strings from raw text file: file_path$
strings = selected("Strings")
Rename: "spear_data"
n_lines = Get number of strings

appendInfoLine: "=== SPEAR Par-Text-Frame Resynthesis ==="
appendInfoLine: "File: ", file_path$
appendInfoLine: "Lines: ", n_lines

# ---- PARSE HEADER ----
selectObject: strings
header1$ = Get string: 1
if not startsWith(header1$, "par-text-frame-format")
    removeObject: strings
    exitScript: "Not a par-text-frame-format file (first line was: " + header1$ + ")"
endif

pointType$ = Get string: 2
partialsCountLine$ = Get string: 3
frameCountLine$ = Get string: 4
frameDataMarker$ = Get string: 5

frame_count = number(replace_regex$(frameCountLine$, "frame-count\s+", "", 1))
appendInfoLine: "Point-type: ", pointType$
appendInfoLine: "Declared frame-count: ", frame_count

# How many numbers per partial in this point-type? (index frequency amplitude = 3)
# Count the words after "point-type".
ptValues$ = replace_regex$(pointType$, "^point-type\s+", "", 1)
nPerPartial = 0
tmp$ = ptValues$
while tmp$ <> ""
    w$ = extractWord$(tmp$, "")
    if w$ <> ""
        nPerPartial = nPerPartial + 1
        tmp$ = replace_regex$(tmp$, "^\s*\S+\s*", "", 1)
    else
        tmp$ = ""
    endif
endwhile
# Layout is always: index, frequency, amplitude, [phase] -> we use freq (col 2)
# and amp (col 3) within each partial group of size nPerPartial.
if nPerPartial < 3
    removeObject: strings
    exitScript: "Unexpected point-type (need at least index frequency amplitude): " + pointType$
endif
appendInfoLine: "Values per partial: ", nPerPartial

# ---- FIRST PASS: find frame times (for hop) and total duration ----
# Data starts at line 6.
dataStart = 6
# read first two frame times to get the hop
firstTime = -1
secondTime = -1
lastTime = 0
nFrames = 0
for line from dataStart to n_lines
    selectObject: strings
    ln$ = Get string: line
    ln$ = replace_regex$(ln$, "^\s+", "", 0)
    if ln$ <> ""
        t = number(extractWord$(ln$, ""))
        if firstTime < 0
            firstTime = t
        elsif secondTime < 0
            secondTime = t
        endif
        lastTime = t
        nFrames = nFrames + 1
    endif
endfor

if nFrames < 2
    removeObject: strings
    exitScript: "Fewer than 2 frames found - nothing to resynthesise."
endif

hop = secondTime - firstTime
if hop <= 0
    hop = 0.01
endif
appendInfoLine: "Frames found: ", nFrames
appendInfoLine: "Hop: ", fixed$(hop * 1000, 2), " ms"
appendInfoLine: ""

# ============================================================
# PHASE 1 - Parse ALL frames into 2D arrays (random access is
# needed for time-stretch / reverse / freeze).
# ============================================================
appendInfoLine: "Parsing ", nFrames, " frames..."
for line from dataStart to n_lines
    selectObject: strings
    ln$ = Get string: line
    ln$ = replace_regex$(ln$, "^\s+", "", 0)
    ln$ = replace_regex$(ln$, "\s+$", "", 0)
    if ln$ <> ""
        frameIdx = frameIdx + 1

        @nextToken: ln$
        fTime = number(nextToken.tok$)
        rest$ = nextToken.rest$
        @nextToken: rest$
        pCount = number(nextToken.tok$)
        rest$ = nextToken.rest$

        frTime[frameIdx] = fTime
        nValid = 0
        for p to pCount
            pIndex = 0
            pFreq = 0
            pAmp = 0
            for v to nPerPartial
                @nextToken: rest$
                val = number(nextToken.tok$)
                rest$ = nextToken.rest$
                if v = 1
                    pIndex = val
                elsif v = 2
                    pFreq = val
                elsif v = 3
                    pAmp = val
                endif
            endfor

            if pFreq > 0 and pAmp > 0
                nValid = nValid + 1
                frIdx[frameIdx, nValid] = pIndex
                frFreq[frameIdx, nValid] = pFreq
                frAmp[frameIdx, nValid] = pAmp
                if pAmp > fileMaxAmp
                    fileMaxAmp = pAmp
                endif
            endif

            if build_partials_table
                selectObject: table
                Append row
                trow = Get number of rows
                Set numeric value: trow, "frame", frameIdx
                Set numeric value: trow, "time", fTime
                Set numeric value: trow, "index", pIndex
                Set numeric value: trow, "frequency", pFreq
                Set numeric value: trow, "amplitude", pAmp
            endif
        endfor
        frN[frameIdx] = nValid

        if frameIdx mod 100 = 0
            appendInfoLine: "  parsed ", frameIdx, " / ", nFrames
        endif
    endif
endfor
removeObject: strings

else
# ------------------------------------------------------------
# SOURCE B: analyse the SELECTED Sound into partials by per-frame
# spectral peak-picking (To Spectrogram -> local maxima per frame).
# Populates the same arrays as the SPEAR parser.
# ------------------------------------------------------------
if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound for the 'Selected Sound' input source."
endif
snd = selected("Sound")
sndName$ = selected$("Sound")
appendInfoLine: "=== SPEAR-style Resynthesis (Sound analysis) ==="
appendInfoLine: "Analysing Sound: ", sndName$

# Mono guard (To Spectrogram needs mono)
selectObject: snd
nch = Get number of channels
if nch > 1
    anaSound = Convert to mono
else
    anaSound = Copy: "ana_mono"
endif

selectObject: anaSound
sndDur = Get total duration
sampling_frequency = Get sampling frequency
hop = analysis_hop_s
if hop <= 0
    hop = 0.01
endif

# Spectrogram of the sound, then convert to a Matrix so the cell/column/row
# accessors are available (Get number of columns is a Matrix command, not a
# Spectrogram one). The Matrix keeps the time (x) and frequency (y) axes.
selectObject: anaSound
spgm = To Spectrogram: hop * 2.5, analysis_max_freq, hop, 20, "Gaussian"
spgMat = To Matrix
nCol = Get number of columns
nRow = Get number of rows
appendInfoLine: "  spectrogram: ", nCol, " frames x ", nRow, " bins"

# Peak-pick each time column. Read each column's cells ONCE into a vector,
# then find the max and pick peaks from memory (avoids re-reading cells).
for c to nCol
    selectObject: spgMat
    tCenter = Get x of column: c
    frameIdx = frameIdx + 1
    frTime[frameIdx] = tCenter

    # preload this column + track max in one pass
    sliceMax = 0
    for r to nRow
        colVal[r] = Get value in cell: r, c
        if colVal[r] > sliceMax
            sliceMax = colVal[r]
        endif
    endfor
    thr = sliceMax * analysis_threshold

    nValid = 0
    for r from 2 to nRow - 1
        pw = colVal[r]
        # local maximum above threshold = a partial
        if pw > colVal[r - 1] and pw >= colVal[r + 1] and pw > thr
            selectObject: spgMat
            pFreq = Get y of row: r
            pAmp = sqrt(pw)
            nValid = nValid + 1
            frIdx[frameIdx, nValid] = nValid
            frFreq[frameIdx, nValid] = pFreq
            frAmp[frameIdx, nValid] = pAmp
            if pAmp > fileMaxAmp
                fileMaxAmp = pAmp
            endif
            if build_partials_table
                selectObject: table
                Append row
                trow = Get number of rows
                Set numeric value: trow, "frame", frameIdx
                Set numeric value: trow, "time", tCenter
                Set numeric value: trow, "index", nValid
                Set numeric value: trow, "frequency", pFreq
                Set numeric value: trow, "amplitude", pAmp
            endif
        endif
    endfor
    frN[frameIdx] = nValid

    if frameIdx mod 50 = 0
        appendInfoLine: "  analysed ", frameIdx, " / ", nCol
    endif
endfor

nFrames = frameIdx
removeObject: spgMat
removeObject: spgm
removeObject: anaSound
appendInfoLine: "Frames analysed: ", nFrames
appendInfoLine: "Hop: ", fixed$(hop * 1000, 2), " ms"
appendInfoLine: ""

endif

nSourceFrames = frameIdx

# Window length = 2 * hop (50% overlap), shared by both input sources.
winDur = 2 * hop

# Resolve a fractional freeze target (set by presets) now that we know the
# frame count - e.g. freezeFrac 0.5 -> freeze on the middle frame.
if freezeFrac > 0
    freeze_on_frame = round(freezeFrac * nSourceFrames)
    if freeze_on_frame < 1
        freeze_on_frame = 1
    endif
endif

# Amplitude gate is expressed as a fraction of the file's peak amplitude.
gateAbs = amplitude_gate * fileMaxAmp

# ============================================================
# PHASE 2 - Output loop. Each OUTPUT frame maps back to a SOURCE
# frame (via time-stretch / reverse / freeze) and is resynthesised
# with the per-partial manipulations applied.
# ============================================================
ts = time_stretch
if ts <= 0
    ts = 1.0
endif
nOutFrames = round(nSourceFrames * ts)
if nOutFrames < 1
    nOutFrames = 1
endif
totalDur = nOutFrames * hop + 2 * hop

master = Create Sound from formula: "spear_resynth", 1, 0, totalDur, sampling_frequency, "0"

appendInfoLine: ""
appendInfoLine: "Resynthesising ", nOutFrames, " output frames..."
if time_stretch <> 1.0
    appendInfoLine: "  time-stretch: ", fixed$(time_stretch, 2), "x"
endif
if reverse
    appendInfoLine: "  reversed"
endif
if freeze_on_frame > 0
    appendInfoLine: "  frozen on frame ", freeze_on_frame
endif

# Visualization capture (kept partials -> trajectory plot)
vizCount = 0
vizMax = 40000
vizPerFrame = 40
vizMaxAmp = 0
vizMaxFreq = 1
vizDrawCeilHz = 6000

for oFrame to nOutFrames
    # --- map output frame -> source frame ---
    if freeze_on_frame > 0
        srcF = freeze_on_frame
    else
        srcF = floor((oFrame - 1) / ts) + 1
    endif
    if srcF > nSourceFrames
        srcF = nSourceFrames
    endif
    if srcF < 1
        srcF = 1
    endif
    if reverse
        srcF = nSourceFrames - srcF + 1
    endif

    outTime = (oFrame - 1) * hop

    # --- read + transform this source frame's partials ---
    srcCount = frN[srcF]
    nValid = 0
    for p to srcCount
        pIndex = frIdx[srcF, p]
        pFreq = frFreq[srcF, p]
        pAmp = frAmp[srcF, p]

        # frequency: transpose, inharmonic exponent, +Hz shift, freq scale
        nf = pFreq * transpose_ratio
        if inharmonicity_exponent <> 1.0 and nf > 0
            nf = 1000 * ((nf / 1000) ^ inharmonicity_exponent)
        endif
        nf = nf + frequency_shift_Hz

        # amplitude: brightness tilt, master amp scale
        na = pAmp * amplitude_scale
        if brightness_tilt <> 0.0 and nf > 0
            na = na * ((nf / 1000) ^ brightness_tilt)
        endif

        # filters: gate, band, harmonic selection
        keep = 1
        if na < gateAbs
            keep = 0
        endif
        if nf < band_low_Hz or nf > band_high_Hz
            keep = 0
        endif
        if harmonic_selection = 2 and pIndex mod 2 = 0
            keep = 0
        endif
        if harmonic_selection = 3 and pIndex mod 2 = 1
            keep = 0
        endif
        if nf <= 0
            keep = 0
        endif

        if keep = 1
            nValid = nValid + 1
            idxArr[nValid] = pIndex
            freqArr[nValid] = nf
            ampArr[nValid] = na
        endif
    endfor

    # Keep only the loudest max_partials_per_frame
    keepN = nValid
    if keepN > max_partials_per_frame
        keepN = max_partials_per_frame
        for a to keepN
            bestI = a
            for b from a + 1 to nValid
                if ampArr[b] > ampArr[bestI]
                    bestI = b
                endif
            endfor
            if bestI <> a
                tmpF = freqArr[a]
                tmpA = ampArr[a]
                freqArr[a] = freqArr[bestI]
                ampArr[a] = ampArr[bestI]
                freqArr[bestI] = tmpF
                ampArr[bestI] = tmpA
            endif
        endfor
    endif

    # Build additive formula + capture viz data
    if keepN > 0
        formula$ = ""
        for a to keepN
            if a > 1
                formula$ = formula$ + " + "
            endif
            formula$ = formula$ + string$(ampArr[a]) + "*sin(2*pi*" + string$(freqArr[a]) + "*x)"

            if draw_visualization and a <= vizPerFrame and vizCount < vizMax
                vizCount = vizCount + 1
                vizTime[vizCount] = outTime
                vizFreq[vizCount] = freqArr[a]
                vizAmp[vizCount] = ampArr[a]
                if ampArr[a] > vizMaxAmp
                    vizMaxAmp = ampArr[a]
                endif
                if freqArr[a] < vizDrawCeilHz and freqArr[a] > vizMaxFreq
                    vizMaxFreq = freqArr[a]
                endif
            endif
        endfor

        segStart = outTime
        seg = Create Sound from formula: "seg", 1, 0, winDur, sampling_frequency, formula$
        Formula: "self * (0.5 - 0.5*cos(2*pi*x/" + string$(winDur) + "))"

        selectObject: seg
        segCols = Get number of samples
        selectObject: master
        startSample = round(segStart * sampling_frequency) + 1
        Formula (part): segStart, segStart + winDur, 1, 1,
            ... "self + if (col - " + string$(startSample - 1) + ") >= 1 and (col - " + string$(startSample - 1) + ") <= " + string$(segCols) + " then object[seg, col - " + string$(startSample - 1) + "] else 0 fi"
        removeObject: seg
    endif

    if oFrame mod 50 = 0
        appendInfoLine: "  frame ", oFrame, " / ", nOutFrames
    endif
endfor

# ---- NORMALISE ----
selectObject: master
Scale peak: 0.95
Rename: "spear_resynth"

appendInfoLine: ""
appendInfoLine: "=== Done ==="
appendInfoLine: "Resynthesised Sound: spear_resynth (", fixed$(totalDur, 2), " s)"
if build_partials_table
    selectObject: table
    nRows = Get number of rows
    appendInfoLine: "Partials table: spear_partials (", nRows, " rows)"
endif

# ---- VISUALIZATION ----
if draw_visualization
    selectObject: master
    @drawVisualization: nOutFrames, totalDur
endif

# ---- PLAY ----
if play_result
    selectObject: master
    Play
endif

selectObject: master

# ============================================================
# Procedures
# ============================================================

# Split off the first whitespace-delimited token; return tok$ and rest$.
procedure nextToken: .s$
    .s$ = replace_regex$(.s$, "^\s+", "", 0)
    .tok$ = extractWord$(.s$, "")
    .rest$ = replace_regex$(.s$, "^\s*\S+", "", 1)
    .rest$ = replace_regex$(.rest$, "^\s+", "", 0)
endproc

# Amplitude -> heat colour (deep blue quiet -> red loud), over ~60 dB of log-amp.
procedure getHeatColor: .amp, .maxAmp
    .floor = .maxAmp / 1000
    if .amp < .floor
        .amp = .floor
    endif
    .t = (log10(.amp) - log10(.floor)) / 3
    if .t < 0
        .t = 0
    endif
    if .t > 1
        .t = 1
    endif
    # 5-stop ramp
    .x = .t * 4
    .i = floor(.x)
    .f = .x - .i
    if .i >= 4
        .r = 0.85
        .g = 0.25
        .b = 0.20
    elsif .i = 0
        .r = 0.15 + (0.10 - 0.15) * .f
        .g = 0.15 + (0.55 - 0.15) * .f
        .b = 0.55 + (0.75 - 0.55) * .f
    elsif .i = 1
        .r = 0.10 + (0.20 - 0.10) * .f
        .g = 0.55 + (0.70 - 0.55) * .f
        .b = 0.75 + (0.35 - 0.75) * .f
    elsif .i = 2
        .r = 0.20 + (0.90 - 0.20) * .f
        .g = 0.70 + (0.75 - 0.70) * .f
        .b = 0.35 + (0.20 - 0.35) * .f
    else
        .r = 0.90 + (0.85 - 0.90) * .f
        .g = 0.75 + (0.25 - 0.75) * .f
        .b = 0.20 + (0.20 - 0.20) * .f
    endif
endproc

procedure drawVisualization: .nFrames, .totalDur
    Erase all
    Select outer viewport: 0, 8, 0, 8

    selectObject: master
    .rDur = Get total duration

    # === TITLE ===
    Select outer viewport: 0, 8, 0.0, 0.65
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.70, "half", "##SPEAR Additive Resynthesis##  |  " + presetName$
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -1.22, "half", string$(.nFrames) + " frames  |  " + fixed$(.totalDur, 2) + " s  |  " + string$(vizCount) + " partials drawn (loudest per frame)"

    # === PARTIAL TRAJECTORY PLOT (centerpiece) ===
    # x = time, y = frequency, colour = amplitude (blue quiet -> red loud).
    # This is the signature spectral-modelling view: the partials being resynthesised.
    Select outer viewport: 0, 8, 0.9, 5.1
    Select inner viewport: 0.7, 7.3, 1.15, 5.0
    .ceil = vizMaxFreq * 1.05
    if .ceil < 1000
        .ceil = 1000
    endif
    Axes: 0, .totalDur, 0, .ceil
    Paint rectangle: "{0.07, 0.07, 0.12}", 0, .totalDur, 0, .ceil

    # faint frequency gridlines
    Colour: "{0.20, 0.20, 0.28}"
    for gl to 5
        .gy = .ceil * gl / 6
        Draw line: 0, .gy, .totalDur, .gy
    endfor

    # draw each kept partial as a small filled mark, heat-coloured by amplitude.
    .markR = .totalDur * 0.0016
    for v to vizCount
        if vizFreq[v] < .ceil
            @getHeatColor: vizAmp[v], vizMaxAmp
            Colour: "{" + fixed$(getHeatColor.r, 3) + ", " + fixed$(getHeatColor.g, 3) + ", " + fixed$(getHeatColor.b, 3) + "}"
            Paint circle: "{" + fixed$(getHeatColor.r, 3) + ", " + fixed$(getHeatColor.g, 3) + ", " + fixed$(getHeatColor.b, 3) + "}", vizTime[v], vizFreq[v], .markR
        endif
    endfor

    Colour: "Black"
    Draw inner box
    Font size: 7
    Marks left: 4, "yes", "yes", "no"
    Text left: "yes", "Frequency (Hz)"
    Font size: 9
    Text top: "no", "##Partial Trajectories (colour = amplitude)##"

    # amplitude colour legend (small ramp strip, top-right inside the panel)
    Axes: 0, 1, 0, 1
    .lx0 = 0.74
    .lx1 = 0.98
    for s to 24
        .ct = (s - 1) / 23
        @getHeatColor: vizMaxAmp * (10 ^ (3 * (.ct - 1))), vizMaxAmp
        .sx0 = .lx0 + (.lx1 - .lx0) * (s - 1) / 24
        .sx1 = .lx0 + (.lx1 - .lx0) * s / 24
        Paint rectangle: "{" + fixed$(getHeatColor.r, 3) + ", " + fixed$(getHeatColor.g, 3) + ", " + fixed$(getHeatColor.b, 3) + "}", .sx0, .sx1, 0.93, 0.97
    endfor
    Font size: 6
    Colour: "White"
    Text: .lx0, "left", 0.90, "half", "quiet"
    Text: .lx1, "right", 0.90, "half", "loud"

    # === RESYNTHESISED WAVEFORM ===
    Select outer viewport: 0, 8, 5.3, 6.9
    Select inner viewport: 0.7, 7.3, 5.5, 6.8
    selectObject: master
    Colour: "{0.20, 0.45, 0.75}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Black
    Draw inner box
    Font size: 7
    Marks left: 3, "yes", "yes", "no"
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Font size: 9
    Select outer viewport: 0, 8, 5.0, 6.9 
Text top: "no", "##Resynthesised Waveform##"

    # === GREY SUMMARY ===
    Select outer viewport: 0, 8, 7.0, 8.0
    Select inner viewport: 0.6, 7.6, 7.05, 7.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Font size: 9
    Colour: "Black"
    Text: 0.02, "left", 0.70, "half", "##SPEAR Resynthesis##"
    Font size: 8
    Colour: "{0.25, 0.25, 0.25}"
    Text: 0.02, "left", 0.40, "half", "Frames: " + string$(.nFrames) + "    Duration: " + fixed$(.totalDur, 2) + " s    Max partials/frame: " + string$(max_partials_per_frame) + "    Drawn: " + string$(vizCount)
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.02, "left", 0.12, "half", "Transpose: " + fixed$(transpose_ratio, 2) + "   Inharm: " + fixed$(inharmonicity_exponent, 2) + "   Bright: " + fixed$(brightness_tilt, 2) + "   Stretch: " + fixed$(time_stretch, 2) + "x   Gate: " + fixed$(amplitude_gate, 2)
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    Font size: 10
    Colour: "Black"
endproc
