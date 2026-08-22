# ============================================================
# Praat AudioTools - Spectral_Filtering_Effect.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.4 (2026) - Suite-standard visualization
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Whole-file zero-phase spectral filtering for brightness/darkness,
#   band focus/notching, and low/high shelves.
#
#   LP/HP and shelf Cutoff_frequency is the midpoint of the transition.
#   For LP/HP, amplitude is 0.5 (-6.02 dB) at the cutoff.
#   For shelves, the midpoint is half the requested shelf gain in dB.
#   Bandwidth_hz is used only by band-pass / band-stop and specifies
#   the flat pass-band / stop-band width around Center_or_cutoff_frequency.
#   Transition_width_hz controls the raised-cosine transition width.
#
#   Processing is zero-phase / whole-file spectral multiplication; it can
#   therefore produce pre/post-ringing around sharp transients.
#
#   Instrument EQ presets are broad musical starting points, not source-
#   adaptive corrections and not copies of proprietary DAW preset curves.
#   Each instrument preset combines HP/LP, shelves, and raised-cosine bell
#   bands in one spectral transfer curve (one FFT/iFFT per channel).
#
# Changelog v1.4 (2026):
#   - VISUALIZATION STANDARDIZATION ONLY; audio processing, analysis,
#     synthesis, object-management and output behavior are unchanged.
#   - Adopted the Praat AudioTools 8-inch page convention, standard
#     title/subtitle, suite typography, neutral diagnostic panels,
#     summary strip and full-page Picture export.
#
# Changelog v1.3:
#   - Added eight multi-band Instrument EQ starting-point presets:
#     Bass, Piano, Acoustic Guitar, Electric Guitar, Drums, Percussion,
#     Electric Piano, and Vocals.
#   - Instrument presets combine HP/LP, shelves, and up to three bell bands
#     in one spectral curve; no serial FFT filtering is used.
#   - Visualization plots the complete combined instrument curve.
#   - Info output lists the active instrument EQ components.
# Changelog v1.2:
#   - Replaced ambiguous Bandwidth_or_slope with separate Bandwidth_hz
#     and Transition_width_hz controls.
#   - Reimplemented all modes as direct spectral gain curves per channel.
#   - Low/high shelves now reach their full gain at DC/Nyquist.
#   - High-pass no longer rolls off again near 0.95*Nyquist.
#   - Telephone preset is a true 300-3400 Hz flat pass-band.
#   - Removed peak normalization; optional Safety_peak only attenuates.
#   - Preserves arbitrary channel count, sample rate, and start time.
#   - Output remains selected.
#   - Visualization updated to AudioTools house style and plots the
#     designed transfer function used by the DSP.
# ============================================================

# === INPUT VALIDATION ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

soundID = selected("Sound")
soundName$ = selected$("Sound")

selectObject: soundID
duration = Get total duration
sampleRate = Get sampling frequency
samplePeriod = Get sampling period
numSamples = Get number of samples
numChannels = Get number of channels
xmin = Get start time
nyquist = sampleRate / 2

if numSamples < 2
    exitScript: "Sound is too short."
endif

form Spectral Filtering Effect v1.4
    optionmenu Preset: 1
        option Manual
        option Bright & Airy
        option Warm & Dark
        option Telephone (300-3400 Hz)
        option Radio Voice
        option Muffled
        option Presence & Treble Boost
        option Bass Boost
        option Treble Cut
        option Lo-Fi
        option Instrument EQ: Bass
        option Instrument EQ: Piano
        option Instrument EQ: Acoustic Guitar
        option Instrument EQ: Electric Guitar
        option Instrument EQ: Drums
        option Instrument EQ: Percussion
        option Instrument EQ: Electric Piano
        option Instrument EQ: Vocals
    comment === Manual Parameters (ignored by presets) ===
    optionmenu Filter_type: 1
        option Low-pass (darken)
        option High-pass (thin)
        option Band-pass (focus)
        option Band-stop (notch)
        option Shelf boost high
        option Shelf cut high
        option Shelf boost low
        option Shelf cut low
    positive Center_or_cutoff_frequency 3000
    positive Bandwidth_hz 2000
    real Transition_width_hz 500
    real Gain_db 6
    comment === Output ===
    boolean Safety_limit 1
    real Safety_peak 0.99
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

# Generic multi-band instrument curve state. 0 means inactive.
instrumentMode = 0
instrumentName$ = ""
instrumentCurve1$ = ""
instrumentCurve2$ = ""
hpCutoff = 0
hpTransition = 0
lpCutoff = 0
lpTransition = 0
lowShelfFreq = 0
lowShelfTransition = 0
lowShelfDb = 0
highShelfFreq = 0
highShelfTransition = 0
highShelfDb = 0
bell1Center = 0
bell1Width = 0
bell1Db = 0
bell2Center = 0
bell2Width = 0
bell2Db = 0
bell3Center = 0
bell3Width = 0
bell3Db = 0

if preset = 2
    filter_type = 5
    center_or_cutoff_frequency = 4000
    bandwidth_hz = 2000
    transition_width_hz = 1000
    gain_db = 8
    presetName$ = "BrightAiry"
elsif preset = 3
    filter_type = 1
    center_or_cutoff_frequency = 3500
    bandwidth_hz = 2000
    transition_width_hz = 500
    gain_db = 0
    presetName$ = "WarmDark"
elsif preset = 4
    filter_type = 3
    center_or_cutoff_frequency = 1850
    bandwidth_hz = 3100
    transition_width_hz = 250
    gain_db = 0
    presetName$ = "Telephone"
elsif preset = 5
    filter_type = 3
    center_or_cutoff_frequency = 2000
    bandwidth_hz = 3000
    transition_width_hz = 500
    gain_db = 0
    presetName$ = "RadioVoice"
elsif preset = 6
    filter_type = 1
    center_or_cutoff_frequency = 1000
    bandwidth_hz = 2000
    transition_width_hz = 300
    gain_db = 0
    presetName$ = "Muffled"
elsif preset = 7
    filter_type = 5
    center_or_cutoff_frequency = 2500
    bandwidth_hz = 2000
    transition_width_hz = 800
    gain_db = 6
    presetName$ = "PresenceTreble"
elsif preset = 8
    filter_type = 7
    center_or_cutoff_frequency = 200
    bandwidth_hz = 2000
    transition_width_hz = 150
    gain_db = 8
    presetName$ = "BassBoost"
elsif preset = 9
    filter_type = 6
    center_or_cutoff_frequency = 5000
    bandwidth_hz = 2000
    transition_width_hz = 1000
    gain_db = -10
    presetName$ = "TrebleCut"
elsif preset = 10
    filter_type = 1
    center_or_cutoff_frequency = 4000
    bandwidth_hz = 2000
    transition_width_hz = 500
    gain_db = 0
    presetName$ = "LoFi"
elsif preset = 11
    # Bass: remove subsonic rumble, add weight, reduce mud, add definition.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_Bass"
    instrumentName$ = "Bass"
    hpCutoff = 30
    hpTransition = 20
    lowShelfFreq = 80
    lowShelfTransition = 80
    lowShelfDb = 2.5
    bell1Center = 280
    bell1Width = 300
    bell1Db = -3.0
    bell2Center = 900
    bell2Width = 1200
    bell2Db = 2.0
    instrumentCurve1$ = "HP 30 Hz | low shelf +2.5 dB @80 Hz"
    instrumentCurve2$ = "bell -3 dB @280 Hz | +2 dB @900 Hz"
elsif preset = 12
    # Piano: clean subsonics, reduce boxiness, add articulation and air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_Piano"
    instrumentName$ = "Piano"
    hpCutoff = 35
    hpTransition = 30
    bell1Center = 300
    bell1Width = 400
    bell1Db = -2.0
    bell2Center = 3200
    bell2Width = 3000
    bell2Db = 1.5
    highShelfFreq = 9000
    highShelfTransition = 4000
    highShelfDb = 1.5
    instrumentCurve1$ = "HP 35 Hz | bell -2 dB @300 Hz"
    instrumentCurve2$ = "bell +1.5 dB @3.2 kHz | high shelf +1.5 dB @9 kHz"
elsif preset = 13
    # Acoustic guitar: remove low rumble, reduce boom, add pick detail and air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_AcousticGuitar"
    instrumentName$ = "Acoustic Guitar"
    hpCutoff = 80
    hpTransition = 60
    bell1Center = 220
    bell1Width = 240
    bell1Db = -2.5
    bell2Center = 3200
    bell2Width = 2600
    bell2Db = 2.0
    highShelfFreq = 9000
    highShelfTransition = 3000
    highShelfDb = 1.5
    instrumentCurve1$ = "HP 80 Hz | bell -2.5 dB @220 Hz"
    instrumentCurve2$ = "bell +2 dB @3.2 kHz | high shelf +1.5 dB @9 kHz"
elsif preset = 14
    # Electric guitar: remove lows, reduce boxiness, emphasize presence, tame fizz.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_ElectricGuitar"
    instrumentName$ = "Electric Guitar"
    hpCutoff = 70
    hpTransition = 60
    lpCutoff = 10000
    lpTransition = 4000
    bell1Center = 300
    bell1Width = 320
    bell1Db = -2.0
    bell2Center = 2200
    bell2Width = 2000
    bell2Db = 2.0
    instrumentCurve1$ = "HP 70 Hz | LP 10 kHz"
    instrumentCurve2$ = "bell -2 dB @300 Hz | +2 dB @2.2 kHz"
elsif preset = 15
    # Full drum kit: weight, less boxiness, attack, and a little air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_Drums"
    instrumentName$ = "Drums"
    hpCutoff = 30
    hpTransition = 20
    lowShelfFreq = 80
    lowShelfTransition = 80
    lowShelfDb = 2.0
    bell1Center = 300
    bell1Width = 360
    bell1Db = -2.5
    bell2Center = 4500
    bell2Width = 3600
    bell2Db = 2.5
    highShelfFreq = 10000
    highShelfTransition = 4000
    highShelfDb = 1.5
    instrumentCurve1$ = "HP 30 Hz | low shelf +2 dB @80 Hz | -2.5 dB @300 Hz"
    instrumentCurve2$ = "bell +2.5 dB @4.5 kHz | high shelf +1.5 dB @10 kHz"
elsif preset = 16
    # General percussion: clear low space, preserve body, enhance attack and air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_Percussion"
    instrumentName$ = "Percussion"
    hpCutoff = 100
    hpTransition = 100
    bell1Center = 350
    bell1Width = 500
    bell1Db = 1.5
    bell2Center = 5500
    bell2Width = 5000
    bell2Db = 3.0
    highShelfFreq = 10000
    highShelfTransition = 4000
    highShelfDb = 2.0
    instrumentCurve1$ = "HP 100 Hz | bell +1.5 dB @350 Hz"
    instrumentCurve2$ = "bell +3 dB @5.5 kHz | high shelf +2 dB @10 kHz"
elsif preset = 17
    # Electric piano: reduce low-mid cloud, add definition and gentle air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_ElectricPiano"
    instrumentName$ = "Electric Piano"
    hpCutoff = 50
    hpTransition = 40
    bell1Center = 280
    bell1Width = 320
    bell1Db = -2.5
    bell2Center = 2200
    bell2Width = 1800
    bell2Db = 2.0
    highShelfFreq = 8500
    highShelfTransition = 3000
    highShelfDb = 1.0
    instrumentCurve1$ = "HP 50 Hz | bell -2.5 dB @280 Hz"
    instrumentCurve2$ = "bell +2 dB @2.2 kHz | high shelf +1 dB @8.5 kHz"
elsif preset = 18
    # General vocal starting point: remove rumble, reduce mud, add presence and air.
    instrumentMode = 1
    presetName$ = "InstrumentEQ_Vocals"
    instrumentName$ = "Vocals"
    hpCutoff = 90
    hpTransition = 60
    bell1Center = 280
    bell1Width = 260
    bell1Db = -2.5
    bell2Center = 3500
    bell2Width = 2600
    bell2Db = 2.5
    highShelfFreq = 11000
    highShelfTransition = 4000
    highShelfDb = 2.0
    instrumentCurve1$ = "HP 90 Hz | bell -2.5 dB @280 Hz"
    instrumentCurve2$ = "bell +2.5 dB @3.5 kHz | high shelf +2 dB @11 kHz"
else
    presetName$ = "Manual"
endif

# ============================================================
# PARAMETER VALIDATION / GEOMETRY
# ============================================================

cutoff = center_or_cutoff_frequency
if cutoff < 1
    cutoff = 1
endif
if cutoff > nyquist - 1
    cutoff = nyquist - 1
endif

bandwidth = bandwidth_hz
if bandwidth < 1
    bandwidth = 1
endif
if bandwidth > 2 * nyquist
    bandwidth = 2 * nyquist
endif

transition = transition_width_hz
if transition < 0
    transition = 0
endif
if transition > nyquist
    transition = nyquist
endif

if safety_peak <= 0
    safety_peak = 0.99
endif

# Shelf modes define the sign from the mode name.
if filter_type = 5 or filter_type = 7
    shelfGainDb = abs(gain_db)
elsif filter_type = 6 or filter_type = 8
    shelfGainDb = -abs(gain_db)
else
    shelfGainDb = 0
endif

# Band geometry. Bandwidth means the FLAT region width.
lowEdge = cutoff - bandwidth / 2
highEdge = cutoff + bandwidth / 2
if lowEdge < 0
    lowEdge = 0
endif
if highEdge > nyquist
    highEdge = nyquist
endif
if highEdge <= lowEdge
    highEdge = min(nyquist, lowEdge + 1)
endif

# LP/HP/shelf transition midpoint geometry.
transLo = cutoff - transition / 2
transHi = cutoff + transition / 2
if transLo < 0
    transLo = 0
endif
if transHi > nyquist
    transHi = nyquist
endif
transSpan = transHi - transLo

# Band transitions live outside the flat pass/stop band.
lowTransStart = max(0, lowEdge - transition)
highTransEnd = min(nyquist, highEdge + transition)
lowTransSpan = lowEdge - lowTransStart
highTransSpan = highTransEnd - highEdge

# ============================================================
# REPORT HEADER
# ============================================================

clearinfo
writeInfoLine: "=== Spectral Filtering Effect v1.4 ==="
appendInfoLine: "Input: ", soundName$, "   ", fixed$(duration, 3), " s   ", numChannels, " ch"
appendInfoLine: "Sample rate: ", fixed$(sampleRate, 0), " Hz   start ", fixed$(xmin, 6), " s"
appendInfoLine: "Preset: ", presetName$

if instrumentMode
    filterDesc$ = "Instrument EQ - " + instrumentName$
    appendInfoLine: "Filter: Multi-band Instrument EQ starting point - ", instrumentName$
    appendInfoLine: "  ", instrumentCurve1$
    appendInfoLine: "  ", instrumentCurve2$
elsif filter_type = 1
    filterDesc$ = "Low-pass"
    appendInfoLine: "Filter: Low-pass, cutoff midpoint ", fixed$(cutoff, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
elsif filter_type = 2
    filterDesc$ = "High-pass"
    appendInfoLine: "Filter: High-pass, cutoff midpoint ", fixed$(cutoff, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
elsif filter_type = 3
    filterDesc$ = "Band-pass"
    appendInfoLine: "Filter: Band-pass, flat ", fixed$(lowEdge, 1), "-", fixed$(highEdge, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
elsif filter_type = 4
    filterDesc$ = "Band-stop"
    appendInfoLine: "Filter: Band-stop, flat stop ", fixed$(lowEdge, 1), "-", fixed$(highEdge, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
elsif filter_type = 5 or filter_type = 6
    filterDesc$ = "High shelf"
    appendInfoLine: "Filter: High shelf ", fixed$(shelfGainDb, 2), " dB, midpoint ", fixed$(cutoff, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
else
    filterDesc$ = "Low shelf"
    appendInfoLine: "Filter: Low shelf ", fixed$(shelfGainDb, 2), " dB, midpoint ", fixed$(cutoff, 1), " Hz, transition ", fixed$(transition, 1), " Hz"
endif
appendInfoLine: "Processing: whole-file zero-phase spectral gain"

# ============================================================
# BUILD OUTPUT / PROCESS EACH CHANNEL
# ============================================================

outputID = Create Sound from formula: "sfe_output", numChannels, 0, numSamples * samplePeriod, sampleRate, "0"

for ch from 1 to numChannels
    selectObject: soundID
    chanID = Extract one channel: ch
    specID = To Spectrum: "no"

    selectObject: specID

    if instrumentMode
        # ---- Multi-band instrument curve: all gains multiply on this one Spectrum. ----
        # Optional HPF.
        if hpCutoff > 0
            hpLo = hpCutoff - hpTransition / 2
            hpHi = hpCutoff + hpTransition / 2
            if hpTransition <= 0
                Formula: "self * (x >= 'hpCutoff:12')"
            else
                Formula: "self * (if x <= 'hpLo:12' then 0 else if x >= 'hpHi:12' then 1 else 0.5 - 0.5*cos(pi*(x-'hpLo:12')/'hpTransition:12') fi fi)"
            endif
        endif

        # Optional LPF.
        if lpCutoff > 0 and lpCutoff < nyquist + lpTransition / 2
            lpLo = lpCutoff - lpTransition / 2
            lpHi = lpCutoff + lpTransition / 2
            if lpTransition <= 0
                Formula: "self * (x <= 'lpCutoff:12')"
            else
                Formula: "self * (if x <= 'lpLo:12' then 1 else if x >= 'lpHi:12' then 0 else 0.5 + 0.5*cos(pi*(x-'lpLo:12')/'lpTransition:12') fi fi)"
            endif
        endif

        # Low shelf, interpolated in dB.
        if lowShelfDb <> 0
            lsLo = lowShelfFreq - lowShelfTransition / 2
            lsHi = lowShelfFreq + lowShelfTransition / 2
            if lowShelfTransition <= 0
                Formula: "self * 10 ^ (('lowShelfDb:12' * (x <= 'lowShelfFreq:12')) / 20)"
            else
                Formula: "self * 10 ^ (('lowShelfDb:12' * (if x <= 'lsLo:12' then 1 else if x >= 'lsHi:12' then 0 else 0.5 + 0.5*cos(pi*(x-'lsLo:12')/'lowShelfTransition:12') fi fi)) / 20)"
            endif
        endif

        # High shelf, interpolated in dB. If its transition is above Nyquist it naturally has no effect.
        if highShelfDb <> 0 and highShelfFreq - highShelfTransition / 2 < nyquist
            hsLo = highShelfFreq - highShelfTransition / 2
            hsHi = highShelfFreq + highShelfTransition / 2
            if highShelfTransition <= 0
                Formula: "self * 10 ^ (('highShelfDb:12' * (x >= 'highShelfFreq:12')) / 20)"
            else
                Formula: "self * 10 ^ (('highShelfDb:12' * (if x <= 'hsLo:12' then 0 else if x >= 'hsHi:12' then 1 else 0.5 - 0.5*cos(pi*(x-'hsLo:12')/'highShelfTransition:12') fi fi)) / 20)"
            endif
        endif

        # Raised-cosine bell bands. Width is zero-to-zero full width; gain is exact at center.
        if bell1Db <> 0 and bell1Center < nyquist and bell1Width > 0
            Formula: "self * 10 ^ ((if abs(x-'bell1Center:12') >= 'bell1Width:12'/2 then 0 else 'bell1Db:12' * 0.5 * (1 + cos(2*pi*(x-'bell1Center:12')/'bell1Width:12')) fi) / 20)"
        endif
        if bell2Db <> 0 and bell2Center < nyquist and bell2Width > 0
            Formula: "self * 10 ^ ((if abs(x-'bell2Center:12') >= 'bell2Width:12'/2 then 0 else 'bell2Db:12' * 0.5 * (1 + cos(2*pi*(x-'bell2Center:12')/'bell2Width:12')) fi) / 20)"
        endif
        if bell3Db <> 0 and bell3Center < nyquist and bell3Width > 0
            Formula: "self * 10 ^ ((if abs(x-'bell3Center:12') >= 'bell3Width:12'/2 then 0 else 'bell3Db:12' * 0.5 * (1 + cos(2*pi*(x-'bell3Center:12')/'bell3Width:12')) fi) / 20)"
        endif

    elsif filter_type = 1
        # Low-pass: unity below transition, zero above.
        if transSpan <= 0
            Formula: "self * (x <= 'cutoff:12')"
        else
            Formula: "self * (if x <= 'transLo:12' then 1 else if x >= 'transHi:12' then 0 else 0.5 + 0.5*cos(pi*(x-'transLo:12')/'transSpan:12') fi fi)"
        endif

    elsif filter_type = 2
        # High-pass: zero below transition, unity above.
        if transSpan <= 0
            Formula: "self * (x >= 'cutoff:12')"
        else
            Formula: "self * (if x <= 'transLo:12' then 0 else if x >= 'transHi:12' then 1 else 0.5 - 0.5*cos(pi*(x-'transLo:12')/'transSpan:12') fi fi)"
        endif

    elsif filter_type = 3
        # Band-pass with a truly flat pass band lowEdge..highEdge.
        if transition <= 0
            Formula: "self * (x >= 'lowEdge:12' and x <= 'highEdge:12')"
        else
            Formula: "self * (if x < 'lowTransStart:12' or x > 'highTransEnd:12' then 0 else if x < 'lowEdge:12' then if 'lowTransSpan:12' > 0 then 0.5 - 0.5*cos(pi*(x-'lowTransStart:12')/'lowTransSpan:12') else 1 fi else if x <= 'highEdge:12' then 1 else if 'highTransSpan:12' > 0 then 0.5 + 0.5*cos(pi*(x-'highEdge:12')/'highTransSpan:12') else 1 fi fi fi fi)"
        endif

    elsif filter_type = 4
        # Band-stop with a truly flat zero-gain stop band.
        if transition <= 0
            Formula: "self * (x < 'lowEdge:12' or x > 'highEdge:12')"
        else
            Formula: "self * (if x < 'lowTransStart:12' or x > 'highTransEnd:12' then 1 else if x < 'lowEdge:12' then if 'lowTransSpan:12' > 0 then 0.5 + 0.5*cos(pi*(x-'lowTransStart:12')/'lowTransSpan:12') else 0 fi else if x <= 'highEdge:12' then 0 else if 'highTransSpan:12' > 0 then 0.5 - 0.5*cos(pi*(x-'highEdge:12')/'highTransSpan:12') else 0 fi fi fi fi)"
        endif

    elsif filter_type = 5 or filter_type = 6
        # High shelf. Interpolate in dB, so transition midpoint = half gain in dB.
        if transSpan <= 0
            Formula: "self * 10 ^ (('shelfGainDb:12' * (x >= 'cutoff:12')) / 20)"
        else
            Formula: "self * 10 ^ (('shelfGainDb:12' * (if x <= 'transLo:12' then 0 else if x >= 'transHi:12' then 1 else 0.5 - 0.5*cos(pi*(x-'transLo:12')/'transSpan:12') fi fi)) / 20)"
        endif

    else
        # Low shelf. Full gain at DC, unity above the transition.
        if transSpan <= 0
            Formula: "self * 10 ^ (('shelfGainDb:12' * (x <= 'cutoff:12')) / 20)"
        else
            Formula: "self * 10 ^ (('shelfGainDb:12' * (if x <= 'transLo:12' then 1 else if x >= 'transHi:12' then 0 else 0.5 + 0.5*cos(pi*(x-'transLo:12')/'transSpan:12') fi fi)) / 20)"
        endif
    endif

    chanOutID = To Sound

    selectObject: outputID
    Formula (part): 0, numSamples * samplePeriod, ch, ch, "object['chanOutID:0', 1, col]"

    removeObject: chanID, specID, chanOutID
endfor

# Restore original time domain.
selectObject: outputID
if xmin <> 0
    Shift times by: xmin
endif
Rename: soundName$ + "_" + presetName$
resultID = selected("Sound")

# ============================================================
# SAFETY ATTENUATION (NEVER BOOST)
# ============================================================

selectObject: resultID
peakBeforeSafety = Get absolute extremum: 0, 0, "None"
safetyApplied = 0
if safety_limit and peakBeforeSafety > safety_peak
    safetyScale = safety_peak / peakBeforeSafety
    Formula: "self * 'safetyScale:12'"
    safetyApplied = 1
    appendInfoLine: "Safety attenuation: peak ", fixed$(peakBeforeSafety, 4), " -> ", fixed$(safety_peak, 4)
endif
peakOut = Get absolute extremum: 0, 0, "None"

selectObject: soundID
peakIn = Get absolute extremum: 0, 0, "None"

# ============================================================
# VISUALIZATION - AUDIOTOOLS HOUSE STYLE
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."

    if numChannels > 1
        selectObject: soundID
        vizInID = Convert to mono
        selectObject: resultID
        vizOutID = Convert to mono
    else
        selectObject: soundID
        vizInID = Copy: "sfe_viz_in"
        selectObject: resultID
        vizOutID = Copy: "sfe_viz_out"
    endif

    maxFreqDisplay = min(8000, nyquist)
    if maxFreqDisplay < 100
        maxFreqDisplay = nyquist
    endif
    vizDuration = min(duration, 10)

    Erase all
    pageHeight = 8.00
    Select outer viewport: 0, 8, 0, pageHeight

    # Title
    suiteVizName$ = replace$(soundName$, "_", "\_ ", 0)
    Select outer viewport: 0, 8, 0, 0.52
    Select inner viewport: 0.60, 7.70, 0.02, 0.50
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.68, "half", "##Spectral Filtering Effect v1.4##"
    Font size: 7
    Colour: "{0.35, 0.35, 0.50}"
    Text: 0.5, "centre", 0.22, "half", suiteVizName$ + " | " + presetName$

    Select outer viewport: 0, 8, 0.72, 1.42
    Select inner viewport: 0.55, 7.75, 0.78, 1.36
    selectObject: vizInID
    Colour: "{0.55, 0.55, 0.55}"
    Draw: xmin, xmin + vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Input waveform"

    # Output waveform
    Select outer viewport: 0, 8, 1.46, 2.16
    Select inner viewport: 0.55, 7.75, 1.52, 2.10
    selectObject: vizOutID
    Colour: "{0.25, 0.50, 0.82}"
    Draw: xmin, xmin + vizDuration, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Output waveform"

    # Spectrograms
    selectObject: vizInID
    specInID = To Spectrogram: 0.03, maxFreqDisplay, 0.002, 20, "Gaussian"
    selectObject: vizOutID
    specOutID = To Spectrogram: 0.03, maxFreqDisplay, 0.002, 20, "Gaussian"

    Select outer viewport: 0, 4, 2.24, 3.64
    Select inner viewport: 0.55, 3.82, 2.34, 3.56
    selectObject: specInID
    Paint: xmin, xmin + vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Input spectrum over time"

    Select outer viewport: 4, 8, 2.24, 3.64
    Select inner viewport: 4.20, 7.75, 2.34, 3.56
    selectObject: specOutID
    Paint: xmin, xmin + vizDuration, 0, maxFreqDisplay, 100, "yes", 50, 6, 0, "no"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Filtered spectrum over time"

    # Designed transfer function
    Select outer viewport: 0, 8, 3.72, 4.92
    Select inner viewport: 0.65, 7.75, 3.82, 4.84

    if instrumentMode
        responseMinDb = -18
        responseMaxDb = 10
    elsif filter_type <= 4
        responseMinDb = -60
        responseMaxDb = 3
    else
        responseMinDb = min(-18, shelfGainDb - 6)
        responseMaxDb = max(6, shelfGainDb + 6)
    endif
    Axes: 0, maxFreqDisplay, responseMinDb, responseMaxDb
    Paint rectangle: "{0.97, 0.97, 0.97}", 0, maxFreqDisplay, responseMinDb, responseMaxDb
    Colour: "{0.88, 0.88, 0.88}"
    Draw line: 0, 0, maxFreqDisplay, 0

    responsePts = 180
    prevF = 0
    prevDb = 0
    for q from 0 to responsePts
        f = maxFreqDisplay * q / responsePts
        g = 1

        if instrumentMode
            # Compute the same combined instrument curve used by DSP.
            gdb = 0
            hpG = 1
            lpG = 1

            if hpCutoff > 0
                hpLo = hpCutoff - hpTransition / 2
                hpHi = hpCutoff + hpTransition / 2
                if hpTransition <= 0
                    hpG = (f >= hpCutoff)
                elsif f <= hpLo
                    hpG = 0
                elsif f >= hpHi
                    hpG = 1
                else
                    hpG = 0.5 - 0.5*cos(pi*(f-hpLo)/hpTransition)
                endif
            endif

            if lpCutoff > 0 and lpCutoff < nyquist + lpTransition / 2
                lpLo = lpCutoff - lpTransition / 2
                lpHi = lpCutoff + lpTransition / 2
                if lpTransition <= 0
                    lpG = (f <= lpCutoff)
                elsif f <= lpLo
                    lpG = 1
                elsif f >= lpHi
                    lpG = 0
                else
                    lpG = 0.5 + 0.5*cos(pi*(f-lpLo)/lpTransition)
                endif
            endif

            if lowShelfDb <> 0
                lsLo = lowShelfFreq - lowShelfTransition / 2
                lsHi = lowShelfFreq + lowShelfTransition / 2
                if lowShelfTransition <= 0
                    lsFrac = (f <= lowShelfFreq)
                elsif f <= lsLo
                    lsFrac = 1
                elsif f >= lsHi
                    lsFrac = 0
                else
                    lsFrac = 0.5 + 0.5*cos(pi*(f-lsLo)/lowShelfTransition)
                endif
                gdb = gdb + lowShelfDb * lsFrac
            endif

            if highShelfDb <> 0 and highShelfFreq - highShelfTransition / 2 < nyquist
                hsLo = highShelfFreq - highShelfTransition / 2
                hsHi = highShelfFreq + highShelfTransition / 2
                if highShelfTransition <= 0
                    hsFrac = (f >= highShelfFreq)
                elsif f <= hsLo
                    hsFrac = 0
                elsif f >= hsHi
                    hsFrac = 1
                else
                    hsFrac = 0.5 - 0.5*cos(pi*(f-hsLo)/highShelfTransition)
                endif
                gdb = gdb + highShelfDb * hsFrac
            endif

            if bell1Db <> 0 and bell1Center < nyquist and bell1Width > 0
                if abs(f-bell1Center) < bell1Width/2
                    gdb = gdb + bell1Db * 0.5 * (1 + cos(2*pi*(f-bell1Center)/bell1Width))
                endif
            endif
            if bell2Db <> 0 and bell2Center < nyquist and bell2Width > 0
                if abs(f-bell2Center) < bell2Width/2
                    gdb = gdb + bell2Db * 0.5 * (1 + cos(2*pi*(f-bell2Center)/bell2Width))
                endif
            endif
            if bell3Db <> 0 and bell3Center < nyquist and bell3Width > 0
                if abs(f-bell3Center) < bell3Width/2
                    gdb = gdb + bell3Db * 0.5 * (1 + cos(2*pi*(f-bell3Center)/bell3Width))
                endif
            endif

            g = hpG * lpG * 10 ^ (gdb / 20)

        elsif filter_type = 1
            if transSpan <= 0
                g = (f <= cutoff)
            elsif f <= transLo
                g = 1
            elsif f >= transHi
                g = 0
            else
                g = 0.5 + 0.5*cos(pi*(f-transLo)/transSpan)
            endif
        elsif filter_type = 2
            if transSpan <= 0
                g = (f >= cutoff)
            elsif f <= transLo
                g = 0
            elsif f >= transHi
                g = 1
            else
                g = 0.5 - 0.5*cos(pi*(f-transLo)/transSpan)
            endif
        elsif filter_type = 3
            if transition <= 0
                g = (f >= lowEdge and f <= highEdge)
            elsif f < lowTransStart or f > highTransEnd
                g = 0
            elsif f < lowEdge
                if lowTransSpan > 0
                    g = 0.5 - 0.5*cos(pi*(f-lowTransStart)/lowTransSpan)
                else
                    g = 1
                endif
            elsif f <= highEdge
                g = 1
            elsif highTransSpan > 0
                g = 0.5 + 0.5*cos(pi*(f-highEdge)/highTransSpan)
            else
                g = 1
            endif
        elsif filter_type = 4
            if transition <= 0
                g = (f < lowEdge or f > highEdge)
            elsif f < lowTransStart or f > highTransEnd
                g = 1
            elsif f < lowEdge
                if lowTransSpan > 0
                    g = 0.5 + 0.5*cos(pi*(f-lowTransStart)/lowTransSpan)
                else
                    g = 0
                endif
            elsif f <= highEdge
                g = 0
            elsif highTransSpan > 0
                g = 0.5 - 0.5*cos(pi*(f-highEdge)/highTransSpan)
            else
                g = 0
            endif
        elsif filter_type = 5 or filter_type = 6
            if transSpan <= 0
                shelfFrac = (f >= cutoff)
            elsif f <= transLo
                shelfFrac = 0
            elsif f >= transHi
                shelfFrac = 1
            else
                shelfFrac = 0.5 - 0.5*cos(pi*(f-transLo)/transSpan)
            endif
            g = 10 ^ (shelfGainDb * shelfFrac / 20)
        else
            if transSpan <= 0
                shelfFrac = (f <= cutoff)
            elsif f <= transLo
                shelfFrac = 1
            elsif f >= transHi
                shelfFrac = 0
            else
                shelfFrac = 0.5 + 0.5*cos(pi*(f-transLo)/transSpan)
            endif
            g = 10 ^ (shelfGainDb * shelfFrac / 20)
        endif

        if g <= 0.001
            db = responseMinDb
        else
            db = 20 * log10(g)
            if db < responseMinDb
                db = responseMinDb
            endif
            if db > responseMaxDb
                db = responseMaxDb
            endif
        endif

        if q > 0
            Colour: "{0.38, 0.36, 0.68}"
            Line width: 1.5
            Draw line: prevF, prevDb, f, db
        endif
        prevF = f
        prevDb = db
    endfor
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 6
    Marks left every: 1, 10, "yes", "yes", "no"
    Text left: "yes", "Gain (dB)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Designed transfer function"

    # Summary
    Select outer viewport: 0, 8, 5.02, 6.02
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 7
    Text: 0.02, "left", 0.84, "half", "##" + filterDesc$ + "##  preset=" + presetName$
    Font size: 6
    Colour: "{0.25, 0.25, 0.35}"
    if instrumentMode
        Text: 0.02, "left", 0.60, "half", instrumentCurve1$
        Text: 0.02, "left", 0.40, "half", instrumentCurve2$
    elsif filter_type = 3 or filter_type = 4
        Text: 0.02, "left", 0.55, "half", "center " + fixed$(cutoff, 0) + " Hz | flat bandwidth " + fixed$(highEdge-lowEdge, 0) + " Hz | transition " + fixed$(transition, 0) + " Hz"
    elsif filter_type >= 5
        Text: 0.02, "left", 0.55, "half", "midpoint " + fixed$(cutoff, 0) + " Hz | transition " + fixed$(transition, 0) + " Hz | shelf " + fixed$(shelfGainDb, 1) + " dB"
    else
        Text: 0.02, "left", 0.55, "half", "cutoff midpoint " + fixed$(cutoff, 0) + " Hz | transition " + fixed$(transition, 0) + " Hz"
    endif
    if instrumentMode
        Text: 0.02, "left", 0.14, "half", string$(numChannels) + " ch | " + fixed$(sampleRate, 0) + " Hz | peak " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4) + " | safety=" + string$(safetyApplied)
    else
        Text: 0.02, "left", 0.22, "half", string$(numChannels) + " ch | " + fixed$(sampleRate, 0) + " Hz | peak " + fixed$(peakIn, 4) + " -> " + fixed$(peakOut, 4) + " | safety=" + string$(safetyApplied)
    endif

    removeObject: specInID, specOutID, vizInID, vizOutID

    Font size: 10
    Colour: "Black"
    Line width: 1
    appendInfoLine: "Visualization complete."
# Restore complete page for Picture export / clipboard.
Select outer viewport: 0, 8, 0, pageHeight
Font size: 10
Colour: "Black"
Line width: 1
Solid line
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: "Created: ", soundName$, "_", presetName$
appendInfoLine: "Channels: ", numChannels, "   start ", fixed$(xmin, 6), " s"
appendInfoLine: "Peak: ", fixed$(peakIn, 4), " -> ", fixed$(peakOut, 4)
if not safetyApplied
    appendInfoLine: "No peak normalization applied."
endif

selectObject: resultID
if play_result
    Play
endif