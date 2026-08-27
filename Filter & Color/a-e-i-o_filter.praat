# ============================================================
# Praat AudioTools - a-e-i-o_filter.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.5 (2026) - spectral visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Vowel Formant Filter - Applies vocal tract resonances
#   of vowels (a, e, i, o, u) to shape the input sound's timbre.
#
# Changelog v0.5 (2026):
#   - VISUALIZATION ONLY, plus a level report; audio processing,
#     analysis, synthesis and object management are byte-for-byte
#     unchanged. No gain is applied anywhere.
#   - REPLACED THE WAVEFORM PANELS. A vocal tract filter reshapes the
#     spectral envelope and leaves the amplitude envelope nearly intact,
#     so v0.4.3's stacked waveforms were near-identical traces in
#     different colours - nothing separating [a] from [i] was visible.
#   - The old panels were also misleading. "Draw: 0, 0, 0, 0" autoscales
#     each panel independently, so [u] (peak 5.90 on a test tone) was
#     drawn exactly as tall as [i] (peak 0.79). They hid the clipping
#     they should have shown.
#   - NEW panel 1: the vowel filter responses, read from the LPC objects
#     that actually filtered the audio, normalised per vowel so the
#     resonance SHAPES compare. Formant positions marked.
#   - NEW panel 2: input spectrum against every filtered output on one
#     shared dB scale, so level and spectral tilt are both readable.
#   - NEW panel 3: the selected vowels in F1/F2 space, in the usual
#     phonetic orientation.
#   - NEW panel 4: F1/F2/F3 and output peak per vowel, peaks above 1.0
#     flagged in red.
#   - Formants come from Praat's LPC "To Formant", not from peak-picking
#     the drawn envelope: a picker misses F2 whenever it sits on the
#     shoulder of F1, which for [a] reported F3 (2472 Hz) as F2 when F2
#     is 1002 Hz.
#   - Log frequency axes throughout, with own tick labels so 8000 reads
#     "8k" rather than Praat's "8*10^3".
#   - Drawing-frame discipline: Praat derives a panel's inner margins
#     from the CURRENT font size, so a font change made AFTER
#     "Select inner viewport" silently re-derives a wider frame and
#     shifts everything drawn next. Every panel now sets its font first
#     and re-issues the selection between drawing groups. v0.4.3 set the
#     font after the selection in the title and in every panel.
#   - Object names escaped for _ ^ # % markup before drawing.
#   - Fixed 8 x 9.2 in page, so the export is the same shape whatever
#     the vowel count; v0.4.3 grew the page with the number of vowels.
#   - Info window now reports the output peak and warns when it exceeds
#     1.0. Reporting only - the level is exactly as before.
#
# Changelog v0.4.3 (2026):
#   - VocalTractTier insertion time now uses dur / 2 instead of fixed 0.5 s,
#     so sounds shorter than 0.5 s are handled correctly.
#   - Audio processing is otherwise unchanged.
#
# Changelog v0.4.2 (2026):
#   - Visualization labels/colors now use an explicit vowel code stored
#     with each output instead of searching the full object name.
#   - Audio processing is unchanged.
#
# Changelog v0.4.1 (2026):
#   - Added the missing Manual preset option so the Include_a/e/i/o/u
#     checkboxes are reachable from the form. DSP is unchanged.
#
# Changelog v0.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v0.2:
#   - Fixed old syntax (select, exit)
#   - Added presets and vowel selection
#   - Added visualization
#   - ID-based object management
#   - Added 'u' vowel option
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

sound = selected("Sound")
origName$ = selected$("Sound")

form Vowel Formant Filter v0.5
    comment === Preset ===
    optionmenu Preset: 1
        option All Vowels (a-e-i-o-u)
        option Classic (a-e-i-o)
        option Front Vowels (e-i)
        option Back Vowels (a-o-u)
        option Single: a
        option Single: e
        option Single: i
        option Single: o
        option Single: u
        option Manual
    comment === Vowel Selection (for Manual) ===
    boolean Include_a 1
    boolean Include_e 1
    boolean Include_i 1
    boolean Include_o 1
    boolean Include_u 0
    comment === Output ===
    boolean Concatenate_results 1
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# Presets
# ============================================================
if preset = 1
    # All Vowels
    include_a = 1
    include_e = 1
    include_i = 1
    include_o = 1
    include_u = 1
    presetName$ = "AllVowels"
elsif preset = 2
    # Classic
    include_a = 1
    include_e = 1
    include_i = 1
    include_o = 1
    include_u = 0
    presetName$ = "Classic"
elsif preset = 3
    # Front Vowels
    include_a = 0
    include_e = 1
    include_i = 1
    include_o = 0
    include_u = 0
    presetName$ = "FrontVowels"
elsif preset = 4
    # Back Vowels
    include_a = 1
    include_e = 0
    include_i = 0
    include_o = 1
    include_u = 1
    presetName$ = "BackVowels"
elsif preset = 5
    include_a = 1
    include_e = 0
    include_i = 0
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_a"
elsif preset = 6
    include_a = 0
    include_e = 1
    include_i = 0
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_e"
elsif preset = 7
    include_a = 0
    include_e = 0
    include_i = 1
    include_o = 0
    include_u = 0
    presetName$ = "Vowel_i"
elsif preset = 8
    include_a = 0
    include_e = 0
    include_i = 0
    include_o = 1
    include_u = 0
    presetName$ = "Vowel_o"
elsif preset = 9
    include_a = 0
    include_e = 0
    include_i = 0
    include_o = 0
    include_u = 1
    presetName$ = "Vowel_u"
else
    presetName$ = "Manual"
endif

# ============================================================
# Setup
# ============================================================
clearinfo
writeInfoLine: "=== Vowel Formant Filter v0.5 ==="
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Input: ", origName$
appendInfoLine: ""

selectObject: sound
dur = Get total duration
fs = Get sampling frequency
nch = Get number of channels

appendInfoLine: "Duration: ", fixed$(dur, 3), " s"
appendInfoLine: "Sample rate: ", fs, " Hz"
appendInfoLine: ""

# LPC Filter requires a mono signal. Build a mono copy to filter; the
# original (possibly stereo) is kept for the visualization.
selectObject: sound
if nch > 1
    filterSrc = Convert to mono
    Rename: "vt_filter_src"
else
    filterSrc = Copy: "vt_filter_src"
endif

# Count selected vowels
numVowels = include_a + include_e + include_i + include_o + include_u
if numVowels = 0
    exitScript: "Please select at least one vowel."
endif

# Build vowel list
vowelList$ = ""
if include_a
    vowelList$ = vowelList$ + "a "
endif
if include_e
    vowelList$ = vowelList$ + "e "
endif
if include_i
    vowelList$ = vowelList$ + "i "
endif
if include_o
    vowelList$ = vowelList$ + "o "
endif
if include_u
    vowelList$ = vowelList$ + "u "
endif

appendInfoLine: "Vowels: ", vowelList$
appendInfoLine: ""

# ============================================================
# Create Vocal Tracts and LPCs
# VocalTract -> VocalTractTier -> LPC (correct workflow)
# ============================================================
appendInfoLine: "Creating vocal tract models..."

if include_a
    Create Vocal Tract from phone: "a"
    vt_a = selected("VocalTract")
    selectObject: vt_a
    To VocalTractTier: 0, dur, dur / 2
    vtt_a = selected("VocalTractTier")
    To LPC: 0.005
    lpc_a = selected("LPC")
    appendInfoLine: "  [a] created"
endif

if include_e
    Create Vocal Tract from phone: "e"
    vt_e = selected("VocalTract")
    selectObject: vt_e
    To VocalTractTier: 0, dur, dur / 2
    vtt_e = selected("VocalTractTier")
    To LPC: 0.005
    lpc_e = selected("LPC")
    appendInfoLine: "  [e] created"
endif

if include_i
    Create Vocal Tract from phone: "i"
    vt_i = selected("VocalTract")
    selectObject: vt_i
    To VocalTractTier: 0, dur, dur / 2
    vtt_i = selected("VocalTractTier")
    To LPC: 0.005
    lpc_i = selected("LPC")
    appendInfoLine: "  [i] created"
endif

if include_o
    Create Vocal Tract from phone: "o"
    vt_o = selected("VocalTract")
    selectObject: vt_o
    To VocalTractTier: 0, dur, dur / 2
    vtt_o = selected("VocalTractTier")
    To LPC: 0.005
    lpc_o = selected("LPC")
    appendInfoLine: "  [o] created"
endif

if include_u
    Create Vocal Tract from phone: "u"
    vt_u = selected("VocalTract")
    selectObject: vt_u
    To VocalTractTier: 0, dur, dur / 2
    vtt_u = selected("VocalTractTier")
    To LPC: 0.005
    lpc_u = selected("LPC")
    appendInfoLine: "  [u] created"
endif

# ============================================================
# Filter with each LPC
# ============================================================
appendInfoLine: ""
appendInfoLine: "Filtering..."

outputCount = 0

if include_a
    selectObject: filterSrc
    plusObject: lpc_a
    Filter: "no"
    filtered_a_temp = selected("Sound")
    selectObject: filtered_a_temp
    Resample: fs, 50
    filtered_a = selected("Sound")
    Rename: origName$ + "_VT_a"
    removeObject: filtered_a_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_a
    outputVowel_'outputCount' = 1
    appendInfoLine: "  [a] filtered"
endif

if include_e
    selectObject: filterSrc
    plusObject: lpc_e
    Filter: "no"
    filtered_e_temp = selected("Sound")
    selectObject: filtered_e_temp
    Resample: fs, 50
    filtered_e = selected("Sound")
    Rename: origName$ + "_VT_e"
    removeObject: filtered_e_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_e
    outputVowel_'outputCount' = 2
    appendInfoLine: "  [e] filtered"
endif

if include_i
    selectObject: filterSrc
    plusObject: lpc_i
    Filter: "no"
    filtered_i_temp = selected("Sound")
    selectObject: filtered_i_temp
    Resample: fs, 50
    filtered_i = selected("Sound")
    Rename: origName$ + "_VT_i"
    removeObject: filtered_i_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_i
    outputVowel_'outputCount' = 3
    appendInfoLine: "  [i] filtered"
endif

if include_o
    selectObject: filterSrc
    plusObject: lpc_o
    Filter: "no"
    filtered_o_temp = selected("Sound")
    selectObject: filtered_o_temp
    Resample: fs, 50
    filtered_o = selected("Sound")
    Rename: origName$ + "_VT_o"
    removeObject: filtered_o_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_o
    outputVowel_'outputCount' = 4
    appendInfoLine: "  [o] filtered"
endif

if include_u
    selectObject: filterSrc
    plusObject: lpc_u
    Filter: "no"
    filtered_u_temp = selected("Sound")
    selectObject: filtered_u_temp
    Resample: fs, 50
    filtered_u = selected("Sound")
    Rename: origName$ + "_VT_u"
    removeObject: filtered_u_temp
    outputCount = outputCount + 1
    output_'outputCount' = filtered_u
    outputVowel_'outputCount' = 5
    appendInfoLine: "  [u] filtered"
endif

# ============================================================
# Concatenate if requested
# ============================================================
if concatenate_results and outputCount > 1
    appendInfoLine: ""
    appendInfoLine: "Concatenating..."
    
    selectObject: output_1
    for i from 2 to outputCount
        plusObject: output_'i'
    endfor
    Concatenate
    concatenated = selected("Sound")
    Rename: origName$ + "_VT_" + presetName$
    
    finalOutput = concatenated
else
    finalOutput = output_1
endif

# ============================================================
# VISUALIZATION HELPERS
# ============================================================
# _ ^ # % are markup in Picture text and are SWALLOWED, so an object
# name like "take_2" loses its underscore and everything after a "#"
# turns bold. Escape them before any name reaches a Text command.
procedure sanitize: .s$
    .out$ = replace$(.s$, "_", "\_ ", 0)
    .out$ = replace$(.out$, "#", "\# ", 0)
    .out$ = replace$(.out$, "%", "\% ", 0)
    .out$ = replace$(.out$, "^", "\^ ", 0)
endproc

# Praat writes 8000 as 8*10^3 on an axis. Own labels avoid that.
procedure hzLabel: .v
    if .v >= 1000
        .out$ = fixed$(.v / 1000, 1)
        .out$ = replace$(.out$, ".0", "", 0) + "k"
    else
        .out$ = fixed$(.v, 0)
    endif
endproc

procedure vowelStyle: .code
    if .code = 1
        .col$ = "{0.80, 0.30, 0.30}"
        .lab$ = "[a]"
    elsif .code = 2
        .col$ = "{0.25, 0.62, 0.28}"
        .lab$ = "[e]"
    elsif .code = 3
        .col$ = "{0.30, 0.30, 0.80}"
        .lab$ = "[i]"
    elsif .code = 4
        .col$ = "{0.80, 0.60, 0.20}"
        .lab$ = "[o]"
    else
        .col$ = "{0.60, 0.30, 0.70}"
        .lab$ = "[u]"
    endif
endproc

# Decade-style ticks for a log frequency axis
procedure logMarks: .where$
    for .m from 1 to 12
        if .m = 1
            .v = 100
        elsif .m = 2
            .v = 200
        elsif .m = 3
            .v = 300
        elsif .m = 4
            .v = 500
        elsif .m = 5
            .v = 700
        elsif .m = 6
            .v = 1000
        elsif .m = 7
            .v = 1500
        elsif .m = 8
            .v = 2000
        elsif .m = 9
            .v = 3000
        elsif .m = 10
            .v = 4000
        elsif .m = 11
            .v = 6000
        else
            .v = 8000
        endif
        if .v >= fLo and .v <= fHi
            @hzLabel: .v
            if .where$ = "bottom"
                One mark bottom: log10(.v), "no", "yes", "no", hzLabel.out$
            else
                One mark left: log10(.v), "no", "yes", "no", hzLabel.out$
            endif
        endif
    endfor
endproc

# ============================================================
# Visualization
# ============================================================
# v0.4.3 drew the input waveform and one waveform per vowel. A vocal
# tract filter reshapes the SPECTRAL ENVELOPE and leaves the amplitude
# envelope nearly intact, so those panels were five near-identical
# traces: nothing that distinguishes [a] from [i] was visible in any of
# them. Worse, "Draw: 0, 0, 0, 0" autoscales each panel independently,
# so a vowel whose output peaks at 6.5 was drawn exactly as tall as one
# peaking at 0.78 - the panels concealed the clipping they should have
# shown. Everything is drawn on frequency axes now.
if draw_visualization
    appendInfoLine: ""
    appendInfoLine: "Drawing visualization..."

    Erase all
    pageHeight = 9.20
    Select outer viewport: 0, 8, 0, pageHeight

    @sanitize: origName$
    vizName$ = sanitize.out$

    # --- Shared log-frequency grid ---
    fLo = 80
    fHi = min(8000, fs / 2 * 0.98)
    logLo = log10(fLo)
    logHi = log10(fHi)
    nPts = 400
    for j from 0 to nPts
        gridF_'j' = 10 ^ (logLo + (logHi - logLo) * j / nPts)
        gridX_'j' = logLo + (logHi - logLo) * j / nPts
    endfor

    # --- Input spectrum ---
    selectObject: filterSrc
    To Ltas: 160
    ltasIn = selected("Ltas")
    dbMin = 1e9
    dbMax = -1e9
    for j from 0 to nPts
        fq = gridF_'j'
        vi = Get value at frequency: fq, "Cubic"
        if vi = undefined
            vi = -100
        endif
        envI_'j' = vi
        if vi < dbMin
            dbMin = vi
        endif
        if vi > dbMax
            dbMax = vi
        endif
    endfor
    removeObject: ltasIn

    # --- Filter envelope, output spectrum, formants and peak per vowel ---
    # The envelope is read from the very LPC object that filtered the
    # audio, so the curve drawn is the filter that actually ran.
    anyClip = 0
    for i from 1 to outputCount
        vc = outputVowel_'i'
        if vc = 1
            lpcId = lpc_a
        elsif vc = 2
            lpcId = lpc_e
        elsif vc = 3
            lpcId = lpc_i
        elsif vc = 4
            lpcId = lpc_o
        else
            lpcId = lpc_u
        endif

        selectObject: lpcId
        To Spectrum (slice): dur / 2, 20, 0, 50
        spTmp = selected("Spectrum")
        To Ltas (1-to-1)
        ltFilt = selected("Ltas")
        removeObject: spTmp

        selectObject: output_'i'
        To Ltas: 160
        ltOut = selected("Ltas")

        selectObject: output_'i'
        pk = Get absolute extremum: 0, 0, "None"
        peakOf_'i' = pk
        if pk > 1
            anyClip = 1
        endif

        curveMax = -1e9
        for j from 0 to nPts
            fq = gridF_'j'
            idx = (i - 1) * (nPts + 1) + j
            selectObject: ltFilt
            vf = Get value at frequency: fq, "Cubic"
            if vf = undefined
                vf = -100
            endif
            envF_'idx' = vf
            if vf > curveMax
                curveMax = vf
            endif
            selectObject: ltOut
            vo = Get value at frequency: fq, "Cubic"
            if vo = undefined
                vo = -100
            endif
            envO_'idx' = vo
            if vo < dbMin
                dbMin = vo
            endif
            if vo > dbMax
                dbMax = vo
            endif
        endfor
        filtMax_'i' = curveMax

        # Formants from Praat's own LPC analysis, not from peak-picking
        # the drawn envelope. A picker misses F2 whenever it sits on the
        # shoulder of F1 rather than forming a separate local maximum -
        # for [a] that reported F3 (2472 Hz) as F2, when F2 is 1002 Hz.
        # The dot is then placed at the curve's own height at that
        # frequency, so the marks still sit on the line.
        selectObject: lpcId
        To Formant
        fmObj = selected("Formant")
        nFound = 0
        for q from 1 to 3
            selectObject: fmObj
            fv = Get value at time: q, dur / 2, "hertz", "Linear"
            if fv <> undefined and fv >= fLo and fv <= fHi
                nFound = nFound + 1
                idf = (i - 1) * 3 + nFound
                formant_'idf' = fv
                jNear = round((log10(fv) - logLo) / (logHi - logLo) * nPts)
                jNear = min(max(jNear, 0), nPts)
                iNear = (i - 1) * (nPts + 1) + jNear
                formantY_'idf' = envF_'iNear' - curveMax
            endif
        endfor
        nFormants_'i' = nFound
        removeObject: fmObj

        removeObject: ltFilt, ltOut
    endfor

    if dbMax - dbMin > 80
        dbMin = dbMax - 80
    endif
    dbLo = floor((dbMin - 3) / 10) * 10
    dbHi = ceiling((dbMax + 10) / 10) * 10

    # === TITLE ===
    # Font size BEFORE the viewport selection: Praat derives a panel's
    # inner margins from the CURRENT font, so a font change made after
    # the selection silently re-derives a wider frame and shifts
    # everything drawn afterwards outward.
    Font size: 12
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Vowel Formant Filter v0.5##"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", vizName$ + " | " + presetName$ +
    ... " | " + string$(outputCount) + " vowel filters"

    # ============================================================
    # PANEL 1 - the vowel filters themselves
    # ============================================================
    # Each curve is normalised to its own peak, so this panel compares
    # the SHAPE of the resonances. The large absolute level differences
    # between vowels are reported in the table instead.
    Font size: 7
    Select outer viewport: 0, 8, 0.60, 3.45
    Select inner viewport: 0.60, 7.70, 0.85, 3.15
    Axes: logLo, logHi, -45, 12
    Paint rectangle: "{0.975, 0.975, 0.985}", logLo, logHi, -45, 12

    Select inner viewport: 0.60, 7.70, 0.85, 3.15
    Axes: logLo, logHi, -45, 12
    Colour: "{0.86, 0.86, 0.88}"
    Line width: 1
    Dotted line
    for gd from 1 to 4
        gy = -10 * gd
        Draw line: logLo, gy, logHi, gy
    endfor
    Solid line

    for i from 1 to outputCount
        vc = outputVowel_'i'
        @vowelStyle: vc
        Select inner viewport: 0.60, 7.70, 0.85, 3.15
        Axes: logLo, logHi, -45, 12
        Colour: vowelStyle.col$
        Line width: 1.5
        cmax = filtMax_'i'
        for j from 1 to nPts
            jm = j - 1
            ia = (i - 1) * (nPts + 1) + jm
            ib = (i - 1) * (nPts + 1) + j
            fa = envF_'ia'
            fb = envF_'ib'
            ya = max(fa - cmax, -45)
            yb = max(fb - cmax, -45)
            xa = gridX_'jm'
            xb = gridX_'j'
            Draw line: xa, ya, xb, yb
        endfor
        Line width: 1

        # Formant peaks
        nfm = nFormants_'i'
        for q from 1 to nfm
            idf = (i - 1) * 3 + q
            fx = formant_'idf'
            fy = formantY_'idf'
            if fx >= fLo and fx <= fHi and fy > -45
                Paint circle (mm): vowelStyle.col$, log10(fx), fy, 1.1
            endif
        endfor
    endfor

    # Legend row in the headroom above every normalised curve (they all
    # peak at 0 dB, so the band above 0 is guaranteed clear)
    Font size: 6
    Select inner viewport: 0.60, 7.70, 0.85, 3.15
    Axes: logLo, logHi, -45, 12
    for i from 1 to outputCount
        vc = outputVowel_'i'
        @vowelStyle: vc
        Colour: vowelStyle.col$
        lx = logLo + (logHi - logLo) * (0.02 + 0.055 * (i - 1))
        Text: lx, "left", 7, "half", vowelStyle.lab$
    endfor
    Colour: "{0.28, 0.28, 0.28}"
    Text: logHi - (logHi - logLo) * 0.005, "right", 7, "half",
    ... "dots mark the resonance peaks (F1, F2, F3)"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 0.85, 3.15
    Axes: logLo, logHi, -45, 12
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 10, "yes", "yes", "no"
    @logMarks: "bottom"
    Text left: "yes", "Relative gain (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    # ============================================================
    # PANEL 2 - what each filter did to THIS material
    # ============================================================
    Font size: 7
    Select outer viewport: 0, 8, 3.45, 6.20
    Select inner viewport: 0.60, 7.70, 3.70, 5.95
    Axes: logLo, logHi, dbLo, dbHi
    Paint rectangle: "{0.975, 0.975, 0.985}", logLo, logHi, dbLo, dbHi

    # Input first, in grey, so the coloured outputs read against it
    Select inner viewport: 0.60, 7.70, 3.70, 5.95
    Axes: logLo, logHi, dbLo, dbHi
    Colour: "{0.55, 0.55, 0.55}"
    Line width: 2
    for j from 1 to nPts
        jm = j - 1
        ya = min(max(envI_'jm', dbLo), dbHi)
        yb = min(max(envI_'j', dbLo), dbHi)
        xa = gridX_'jm'
        xb = gridX_'j'
        Draw line: xa, ya, xb, yb
    endfor
    Line width: 1

    for i from 1 to outputCount
        vc = outputVowel_'i'
        @vowelStyle: vc
        Select inner viewport: 0.60, 7.70, 3.70, 5.95
        Axes: logLo, logHi, dbLo, dbHi
        Colour: vowelStyle.col$
        Line width: 1.5
        for j from 1 to nPts
            jm = j - 1
            ia = (i - 1) * (nPts + 1) + jm
            ib = (i - 1) * (nPts + 1) + j
            oa = envO_'ia'
            ob = envO_'ib'
            ya = min(max(oa, dbLo), dbHi)
            yb = min(max(ob, dbLo), dbHi)
            xa = gridX_'jm'
            xb = gridX_'j'
            Draw line: xa, ya, xb, yb
        endfor
        Line width: 1
    endfor

    Font size: 6
    Select inner viewport: 0.60, 7.70, 3.70, 5.95
    Axes: logLo, logHi, dbLo, dbHi
    Colour: "{0.45, 0.45, 0.45}"
    Text: logLo + (logHi - logLo) * 0.02, "left", dbHi - (dbHi - dbLo) * 0.06,
    ... "half", "grey = input"
    Colour: "{0.28, 0.28, 0.28}"
    Text: logHi - (logHi - logLo) * 0.005, "right", dbHi - (dbHi - dbLo) * 0.06,
    ... "half", "coloured = filtered output, same dB scale"

    Font size: 7
    Select inner viewport: 0.60, 7.70, 3.70, 5.95
    Axes: logLo, logHi, dbLo, dbHi
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks left every: 1, 20, "yes", "yes", "no"
    @logMarks: "bottom"
    Text left: "yes", "Level (dB)"
    Text bottom: "yes", "Frequency (Hz)"

    # ============================================================
    # PANEL 3 - vowel space (F1 / F2), phonetic convention
    # ============================================================
    Font size: 7
    Select outer viewport: 0, 8, 6.20, 8.05
    Select inner viewport: 0.60, 3.30, 6.50, 7.70
    Axes: 2900, 400, 1050, 150
    Paint rectangle: "{0.975, 0.975, 0.985}", 2900, 400, 1050, 150

    Select inner viewport: 0.60, 3.30, 6.50, 7.70
    Axes: 2900, 400, 1050, 150
    for i from 1 to outputCount
        nfm = nFormants_'i'
        if nfm >= 2
            vc = outputVowel_'i'
            @vowelStyle: vc
            id1 = (i - 1) * 3 + 1
            id2 = (i - 1) * 3 + 2
            vF1 = formant_'id1'
            vF2 = formant_'id2'
            if vF1 >= 150 and vF1 <= 1050 and vF2 >= 400 and vF2 <= 2900
                Paint circle (mm): vowelStyle.col$, vF2, vF1, 1.8
            endif
        endif
    endfor

    Font size: 6
    Select inner viewport: 0.60, 3.30, 6.50, 7.70
    Axes: 2900, 400, 1050, 150
    for i from 1 to outputCount
        nfm = nFormants_'i'
        if nfm >= 2
            vc = outputVowel_'i'
            @vowelStyle: vc
            id1 = (i - 1) * 3 + 1
            id2 = (i - 1) * 3 + 2
            vF1 = formant_'id1'
            vF2 = formant_'id2'
            if vF1 >= 150 and vF1 <= 1050 and vF2 >= 400 and vF2 <= 2900
                Colour: vowelStyle.col$
                Text: vF2, "centre", vF1 - 72, "half", vowelStyle.lab$
            endif
        endif
    endfor

    Font size: 7
    Select inner viewport: 0.60, 3.30, 6.50, 7.70
    Axes: 2900, 400, 1050, 150
    Colour: "Black"
    Line width: 1
    Draw inner box
    Marks bottom every: 1, 500, "yes", "yes", "no"
    Marks left every: 1, 200, "yes", "yes", "no"
    Text left: "yes", "F1 (Hz)"
    Text bottom: "yes", "F2 (Hz)"

    # ============================================================
    # PANEL 4 - formant and level table
    # ============================================================
    Font size: 7
    Select outer viewport: 0, 8, 6.20, 8.05
    Select inner viewport: 4.20, 7.70, 6.50, 7.70
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.975, 0.975, 0.985}", 0, 1, 0, 1

    Select inner viewport: 4.20, 7.70, 6.50, 7.70
    Axes: 0, 1, 0, 1
    Colour: "{0.30, 0.30, 0.30}"
    Text: 0.04, "left", 0.90, "half", "##vowel##"
    Text: 0.30, "right", 0.90, "half", "##F1##"
    Text: 0.50, "right", 0.90, "half", "##F2##"
    Text: 0.70, "right", 0.90, "half", "##F3##"
    Text: 0.96, "right", 0.90, "half", "##peak##"

    Font size: 6
    Select inner viewport: 4.20, 7.70, 6.50, 7.70
    Axes: 0, 1, 0, 1
    for i from 1 to outputCount
        vc = outputVowel_'i'
        @vowelStyle: vc
        ry = 0.90 - 0.138 * i
        Colour: vowelStyle.col$
        Text: 0.04, "left", ry, "half", vowelStyle.lab$
        Colour: "{0.28, 0.28, 0.28}"
        nfm = nFormants_'i'
        for q from 1 to 3
            if q <= nfm
                idf = (i - 1) * 3 + q
                fv = formant_'idf'
                cell$ = string$(round(fv))
            else
                cell$ = "-"
            endif
            cx = 0.10 + 0.20 * q
            Text: cx, "right", ry, "half", cell$
        endfor
        pk = peakOf_'i'
        if pk > 1
            Colour: "{0.80, 0.15, 0.15}"
            Text: 0.96, "right", ry, "half", fixed$(pk, 2) + " !"
        else
            Colour: "{0.28, 0.28, 0.28}"
            Text: 0.96, "right", ry, "half", fixed$(pk, 2)
        endif
    endfor

    if anyClip
        Colour: "{0.80, 0.15, 0.15}"
        Text: 0.04, "left", 0.045, "half", "! peak above 1.0 - will clip in integer PCM"
    else
        Colour: "{0.40, 0.40, 0.40}"
        Text: 0.04, "left", 0.045, "half", "all peaks within 1.0"
    endif

    Font size: 7
    Select inner viewport: 4.20, 7.70, 6.50, 7.70
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # === SUMMARY STRIP ===
    Font size: 7
    Select outer viewport: 0, 8, 8.15, 9.05
    Select inner viewport: 0.60, 7.70, 8.25, 8.95
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1

    if concatenate_results and outputCount > 1
        outStr$ = "concatenated (" + string$(outputCount) + " segments, " +
        ... fixed$(dur * outputCount, 2) + " s)"
    else
        outStr$ = "separate objects"
    endif

    Select inner viewport: 0.60, 7.70, 8.25, 8.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.02, "left", 0.80, "half", "##Summary##"

    Font size: 6
    Select inner viewport: 0.60, 7.70, 8.25, 8.95
    Axes: 0, 1, 0, 1
    Colour: "{0.28, 0.28, 0.28}"
    Text: 0.02, "left", 0.50, "half",
    ... "Preset: " + presetName$
    ... + "  |  Vowels: " + vowelList$
    ... + "  |  Source: " + vizName$
    ... + "  |  Duration: " + fixed$(dur, 2) + " s"
    ... + "  |  Rate: " + string$(round(fs)) + " Hz"
    Text: 0.02, "left", 0.18, "half",
    ... "Output: " + outStr$
    ... + "  |  LPC from Vocal Tract phones, insertion at " + fixed$(dur / 2, 3) + " s"
    ... + "  |  Analysis span " + string$(round(fLo)) + "-" + string$(round(fHi)) + " Hz"

    Select inner viewport: 0.60, 7.70, 8.25, 8.95
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1

    # Restore the complete page. "Save as ... PNG" and the Picture
    # window's Save/Copy export the CURRENT viewport selection, so
    # ending on the summary strip would export only that strip.
    Select outer viewport: 0, 8, 0, pageHeight
    Font size: 10
    Colour: "Black"
    Line width: 1
    Solid line
endif

# ============================================================
# Cleanup
# ============================================================
appendInfoLine: ""
appendInfoLine: "Cleaning up..."

nocheck removeObject: filterSrc

# Remove VocalTracts, VocalTractTiers, and LPCs
if include_a
    removeObject: vt_a, vtt_a, lpc_a
endif
if include_e
    removeObject: vt_e, vtt_e, lpc_e
endif
if include_i
    removeObject: vt_i, vtt_i, lpc_i
endif
if include_o
    removeObject: vt_o, vtt_o, lpc_o
endif
if include_u
    removeObject: vt_u, vtt_u, lpc_u
endif

# Remove individual filtered sounds if concatenated
if concatenate_results and outputCount > 1
    for i from 1 to outputCount
        removeObject: output_'i'
    endfor
endif

# ============================================================
# Output
# ============================================================
# Level report. No gain is applied - the samples are exactly what
# previous versions produced. LPC vocal tract filters have large and
# very unequal passband gains ([u] can peak above 5 on material that
# [i] leaves below 0.8), and the old waveform panels autoscaled that
# difference away, so it is stated here instead.
selectObject: finalOutput
outPeak = Get absolute extremum: 0, 0, "None"

selectObject: sound
plusObject: finalOutput

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Output: ", selected$("Sound")
appendInfoLine: "Peak: ", fixed$(outPeak, 4)
if outPeak > 1
    appendInfoLine: "WARNING: peak exceeds 1.0 and will clip if saved to integer PCM."
    appendInfoLine: "         Level is unchanged from v0.4.3; apply Scale peak yourself"
    appendInfoLine: "         if you need a safe output."
endif

if play_result
    selectObject: finalOutput
    Play
endif

selectObject: finalOutput