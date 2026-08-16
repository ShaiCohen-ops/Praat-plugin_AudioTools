# ============================================================
# Praat AudioTools - Harmonic_Resonance_Boost.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Version: 0.6.1 (2026) - waveform-heading alignment
#
# Changelog v0.6.1 (2026) -- visualization only, DSP untouched:
#   - ALIGNMENT: the waveform labels "Original" and "Harmonic Filtered" now
#     share one explicit title strip, so both sit on the same visual baseline.
#     This avoids Praat Picture viewport state left behind by drawing mono vs
#     stereo Sound objects. Audio processing is unchanged.
#
# Changelog v0.6 (2026):
#   - FIX: when stereo output is requested, native stereo input is no longer
#     averaged to mono before filtering. Channels 1/2 are filtered independently;
#     mono input still creates synthetic stereo from one source.
#   - PERFORMANCE / SIMPLICITY: the gain law is now applied directly to Spectrum
#     objects. The previous Spectrum -> Matrix -> Spectrum round-trip was exactly
#     equivalent for this scalar real gain. Mono-to-stereo also reuses one source
#     FFT for L/R instead of computing it twice. Mono-input preset sound is
#     unchanged sample-for-sample.
#   - FORM / DOCUMENTATION: "Harmonic bandwidth" is named explicitly as a
#     harmonic HALF-WIDTH. The stereo control is named "Right-band widening":
#     v0.5 did not shift bands by +/-offset; it kept L at the base half-width and
#     widened only R by the stated number of Hz. The sound of existing presets
#     is retained, but the interface now states the real law.
#   - CONTROL FIXES: right-band widening and attenuation gains may be 0;
#     attenuation gains are validated to 0..1 and output peak to (0,1].
#   - VIZ: kept the existing layout, but corrected only what was misleading.
#     The filter-response panel now overlays the actual L and R laws and handles
#     overlapping bands exactly, including the round(f/f0)>=1 boundary.
#   - QC: reports the asymptotic boosted-bin coverage per harmonic period.
#
# v0.5 note: earlier versions also "boosted" the band around
# 0 Hz, because round(x/f0) = 0 satisfied the harmonic test.
# The comb starts at harmonic 1; DC/subsonic content is
# attenuated like any non-harmonic region.
# License: MIT License
#
# Description:
#   Applies a hard-edged, phase-preserving harmonic magnitude comb:
#   frequencies within a half-width of n*f0 (n >= 1) receive Harmonic_boost,
#   while non-harmonic regions receive low/high attenuation. Optional stereo
#   uses the base half-width on L and a wider half-width on R.
# ============================================================

# === Input Validation ===
if numberOfSelected("Sound") <> 1
    exitScript: "Please select exactly one Sound object."
endif

originalID = selected("Sound")
originalName$ = selected$("Sound")

form Harmonic Resonance Boost v0.6.1
    optionmenu Preset: 1
        option Custom
        option Sub Drone (50 Hz)
        option Industrial Hum (60 Hz)
        option Laser Comb (200 Hz)
        option Alien Voice (333 Hz)
        option Metallic Ring (666 Hz)
        option Glass Bells (1200 Hz)
        option Celestial Pad (528 Hz)
        option Swarm (77 Hz)
    comment === Harmonic Parameters ===
    positive Fundamental_frequency 440
    real Harmonic_half_width 50
    comment (boosted region is +/- this many Hz around each harmonic)
    real Harmonic_boost 1.5
    comment === Non-Harmonic Attenuation ===
    positive Mid_freq_cutoff 6000
    real Low_mid_attenuation 0.6
    real High_freq_attenuation 0.4
    comment (0 = suppress, 1 = unity)
    comment === Stereo ===
    boolean Create_stereo 1
    real Right_band_widening 15
    comment (R half-width = L half-width + this; 0 = same response)
    comment === Output ===
    real Scale_peak 0.90
    boolean Draw_visualization 1
    boolean Play_result 1
endform

# ============================================================
# PRESETS
# ============================================================

if preset = 2
    # Sub Drone
    fundamental_frequency = 50
    harmonic_half_width = 20
    harmonic_boost = 4.0
    mid_freq_cutoff = 3000
    low_mid_attenuation = 0.15
    high_freq_attenuation = 0.05
    right_band_widening = 8
    presetName$ = "SubDrone"
elsif preset = 3
    # Industrial Hum
    fundamental_frequency = 60
    harmonic_half_width = 15
    harmonic_boost = 5.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.1
    high_freq_attenuation = 0.02
    right_band_widening = 5
    presetName$ = "Industrial"
elsif preset = 4
    # Laser Comb
    fundamental_frequency = 200
    harmonic_half_width = 8
    harmonic_boost = 6.0
    mid_freq_cutoff = 8000
    low_mid_attenuation = 0.05
    high_freq_attenuation = 0.02
    right_band_widening = 3
    presetName$ = "Laser"
elsif preset = 5
    # Alien Voice
    fundamental_frequency = 333
    harmonic_half_width = 40
    harmonic_boost = 3.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.08
    high_freq_attenuation = 0.03
    right_band_widening = 20
    presetName$ = "Alien"
elsif preset = 6
    # Metallic Ring
    fundamental_frequency = 666
    harmonic_half_width = 25
    harmonic_boost = 5.5
    mid_freq_cutoff = 6000
    low_mid_attenuation = 0.06
    high_freq_attenuation = 0.04
    right_band_widening = 12
    presetName$ = "Metallic"
elsif preset = 7
    # Glass Bells
    fundamental_frequency = 1200
    harmonic_half_width = 35
    harmonic_boost = 3.0
    mid_freq_cutoff = 4000
    low_mid_attenuation = 0.2
    high_freq_attenuation = 0.15
    right_band_widening = 25
    presetName$ = "Glass"
elsif preset = 8
    # Celestial Pad
    fundamental_frequency = 528
    harmonic_half_width = 80
    harmonic_boost = 2.0
    mid_freq_cutoff = 7000
    low_mid_attenuation = 0.25
    high_freq_attenuation = 0.15
    right_band_widening = 40
    presetName$ = "Celestial"
elsif preset = 9
    # Swarm
    fundamental_frequency = 77
    harmonic_half_width = 12
    harmonic_boost = 4.5
    mid_freq_cutoff = 5000
    low_mid_attenuation = 0.12
    high_freq_attenuation = 0.06
    right_band_widening = 6
    presetName$ = "Swarm"
else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP / VALIDATION
# ============================================================

selectObject: originalID
numChannels = Get number of channels
duration = Get total duration
sampleRate = Get sampling frequency
nyquist = sampleRate / 2

if fundamental_frequency <= 0 or fundamental_frequency >= nyquist
    exitScript: "Fundamental frequency must be greater than 0 and below Nyquist (" + fixed$(nyquist, 1) + " Hz)."
endif
if harmonic_half_width < 0
    exitScript: "Harmonic half-width must be 0 Hz or greater."
endif
if harmonic_boost < 0
    exitScript: "Harmonic boost must be 0 or greater."
endif
if low_mid_attenuation < 0 or low_mid_attenuation > 1
    exitScript: "Low/mid attenuation must be between 0 and 1."
endif
if high_freq_attenuation < 0 or high_freq_attenuation > 1
    exitScript: "High-frequency attenuation must be between 0 and 1."
endif
if right_band_widening < 0
    exitScript: "Right-band widening must be 0 Hz or greater."
endif
if scale_peak <= 0 or scale_peak > 1
    exitScript: "Scale peak must be greater than 0 and at most 1."
endif

bwL = harmonic_half_width
bwR = harmonic_half_width + right_band_widening
coverageL = min(1, 2 * bwL / fundamental_frequency)
coverageR = min(1, 2 * bwR / fundamental_frequency)

clearinfo
writeInfoLine: "=== Harmonic Resonance Boost v0.6.1 ==="
appendInfoLine: "Input: ", originalName$, " (", numChannels, " ch, ", fixed$(sampleRate,0), " Hz)"
appendInfoLine: "Duration: ", fixed$(duration, 2), " s"
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Fundamental: ", fundamental_frequency, " Hz"
appendInfoLine: "Harmonic half-width L/R: ", fixed$(bwL,1), " / ", fixed$(bwR,1), " Hz"
appendInfoLine: "Approx. periodic coverage L/R: ", fixed$(100*coverageL,0), "% / ", fixed$(100*coverageR,0), "%"
appendInfoLine: "Boost: ", harmonic_boost, "x"
appendInfoLine: "Attenuation: ", low_mid_attenuation, " / ", high_freq_attenuation
if create_stereo
    if numChannels = 1
        appendInfoLine: "Input mode: mono -> synthetic stereo"
    else
        appendInfoLine: "Input mode: native channels 1/2 preserved"
        if numChannels > 2
            appendInfoLine: "Note: channels above 2 are not included in the stereo output."
        endif
    endif
else
    if numChannels > 1
        appendInfoLine: "Input mode: multichannel fold-down -> mono output"
    else
        appendInfoLine: "Input mode: mono -> mono output"
    endif
endif
if coverageL >= 1
    appendInfoLine: "[Coverage note] L harmonic cells overlap/meet: response is continuously boosted above f0/2."
endif
if create_stereo and coverageR >= 1
    appendInfoLine: "[Coverage note] R harmonic cells overlap/meet: response is continuously boosted above f0/2."
endif
appendInfoLine: ""

# Build formula strings.
fundStr$ = fixed$(fundamental_frequency, 8)
boostStr$ = fixed$(harmonic_boost, 8)
lowAttStr$ = fixed$(low_mid_attenuation, 8)
highAttStr$ = fixed$(high_freq_attenuation, 8)
midCutStr$ = fixed$(mid_freq_cutoff, 8)

# ============================================================
# SOURCE SPECTRA
# ============================================================
#
# The filter is a scalar real gain g(f), applied equally to real and imaginary
# Spectrum rows. Therefore Spectrum -> Matrix -> Spectrum is unnecessary:
# multiplying Spectrum directly is mathematically and numerically identical.
#
# Native stereo is preserved when stereo output is requested. Mono input reuses
# one source FFT for both output sides; only the L/R gain masks differ.

tempSourceL = 0
tempSourceR = 0
tempMono = 0
sharedBaseSpectrum = 0

if create_stereo
    if numChannels = 1
        selectObject: originalID
        spectrumL_ID = To Spectrum: "yes"
        spectrumR_ID = spectrumL_ID
        sharedBaseSpectrum = 1
    else
        selectObject: originalID
        tempSourceL = Extract one channel: 1
        Rename: "harm_srcL"
        selectObject: originalID
        tempSourceR = Extract one channel: 2
        Rename: "harm_srcR"

        selectObject: tempSourceL
        spectrumL_ID = To Spectrum: "yes"
        selectObject: tempSourceR
        spectrumR_ID = To Spectrum: "yes"

        removeObject: tempSourceL, tempSourceR
        tempSourceL = 0
        tempSourceR = 0
    endif
else
    selectObject: originalID
    if numChannels > 1
        tempMono = Convert to mono
    else
        tempMono = Copy: "harm_mono"
    endif
    selectObject: tempMono
    spectrumL_ID = To Spectrum: "yes"
    spectrumR_ID = 0
    removeObject: tempMono
    tempMono = 0
endif

# ============================================================
# FILTER PROCEDURE / RENDER
# ============================================================

procedure filterSpectrum: .sourceSpectrum, .halfWidth, .tag$
    .bwStr$ = fixed$(.halfWidth, 8)

    selectObject: .sourceSpectrum
    .modified = Copy: "harm_spec_" + .tag$

    # Exact v0.5 gain law, now applied directly to Spectrum:
    # nearest harmonic n=round(f/f0) must satisfy n>=1.
    selectObject: .modified
    Formula: "self * (if round(x / " + fundStr$ + ") >= 1 and abs(x - round(x / " + fundStr$ + ") * " + fundStr$ + ") < " + .bwStr$ + " then " + boostStr$ + " else (if x < " + midCutStr$ + " then " + lowAttStr$ + " else " + highAttStr$ + " fi) fi)"

    selectObject: .modified
    .result = To Sound
    Override sampling frequency: sampleRate

    # Fast FFT zero-padding is retained as part of the existing filter character.
    selectObject: .result
    .rDur = Get total duration
    if .rDur > duration + 1e-12
        .trim = Extract part: 0, duration, "rectangular", 1, "no"
        removeObject: .result
        .result = .trim
    endif

    filterSpectrum.modified = .modified
    filterSpectrum.result = .result
endproc

appendInfo: "Processing left channel..."
@filterSpectrum: spectrumL_ID, bwL, "L"
spectrumL_mod_ID = filterSpectrum.modified
resultL_ID = filterSpectrum.result
appendInfoLine: " done"

if create_stereo
    appendInfo: "Processing right channel..."
    @filterSpectrum: spectrumR_ID, bwR, "R"
    spectrumR_mod_ID = filterSpectrum.modified
    resultR_ID = filterSpectrum.result
    appendInfoLine: " done"

    selectObject: resultL_ID
    plusObject: resultR_ID
    resultID = Combine to stereo

    removeObject: resultL_ID, resultR_ID
else
    spectrumR_mod_ID = 0
    resultID = resultL_ID
endif

# Finalize.
selectObject: resultID
if create_stereo
    Rename: originalName$ + "_harmonic_" + presetName$
else
    Rename: originalName$ + "_harmonic_" + presetName$ + "_mono"
endif
resultPeakBefore = Get absolute extremum: 0, 0, "None"
if resultPeakBefore > 1e-15
    Scale peak: scale_peak
endif

# ============================================================
# VISUALIZATION
# ============================================================

if draw_visualization
    appendInfoLine: "Drawing visualization..."
    
    Erase all
    
    # Title
    Select outer viewport: 0, 8, 0, 0.5
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "Black"
    Text: 0.5, "centre", 0.5, "half", "Harmonic Resonance: " + originalName$ + " [" + presetName$ + "]"
    
    # Original waveform
    Select outer viewport: 0, 4, 0.6, 1.8
    Select inner viewport: 0.5, 3.7, 0.7, 1.7
    selectObject: originalID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box
    Font size: 8
    
    # Processed waveform
    Select outer viewport: 4, 8, 0.6, 1.8
    Select inner viewport: 4.5, 7.7, 0.7, 1.7
    selectObject: resultID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, 0, 0, 0, "no", "Curve"
    Colour: "Black"
    Draw inner box

    # Shared waveform-heading strip: explicit viewport keeps both labels on
    # exactly the same baseline regardless of mono/stereo Draw viewport state.
    Select outer viewport: 0, 8, 0.58, 0.70
    Select inner viewport: 0, 8, 0.58, 0.70
    Axes: 0, 1, 0, 1
    Font size: 8
    Colour: "Black"
    Text: 0.25, "centre", 0.5, "half", "Original"
    Text: 0.75, "centre", 0.5, "half", "Harmonic Filtered"
    
    specPlotMax = min(5000, nyquist)

    # Original spectrum
    Select outer viewport: 0, 4, 2.0, 3.6
    Select inner viewport: 0.5, 3.7, 2.2, 3.4
    selectObject: spectrumL_ID
    Colour: "{0.7, 0.7, 0.7}"
    Draw: 0, specPlotMax, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Font size: 8
    Text top: "no", "Original Spectrum"
    Text left: "yes", "dB"
    
    # Modified spectrum
    Select outer viewport: 4, 8, 2.0, 3.6
    Select inner viewport: 4.5, 7.7, 2.2, 3.4
    selectObject: spectrumL_mod_ID
    Colour: "{0.2, 0.5, 0.8}"
    Draw: 0, specPlotMax, 0, 80, "no"
    Colour: "Black"
    Draw inner box
    Text top: "no", "Filtered Spectrum (pre-output scaling)"
    Text left: "yes", "dB"
    
    # Harmonic filter response
    # ----------------------------------------------------------
    # Existing layout retained; response law corrected/extended only where v0.5
    # was misleading. The old panel showed L only and its hand-built rectangles
    # did not enforce the round(f/f0)>=1 Voronoi boundary when bands overlapped.
    # ----------------------------------------------------------
    Select outer viewport: 0, 8, 3.8, 5.2
    Select inner viewport: 0.6, 7.6, 4.0, 5.0

    maxFreq = min(nyquist, min(5000, fundamental_frequency * 10))
    gainMax = max(harmonic_boost, max(low_mid_attenuation, high_freq_attenuation))
    if gainMax < 0.1
        gainMax = 0.1
    endif
    Axes: 0, maxFreq, 0, gainMax * 1.10

    # R first (blue dashed), then L (orange solid). Both call the exact gain law
    # used in audio, including n=round(f/f0)>=1 and overlapping-band behaviour.
    if create_stereo
        Colour: "{0.25, 0.50, 0.82}"
        Line width: 1.2
        Dashed line
        @drawExactResponse: bwR, maxFreq
        Solid line
    endif

    Colour: "{0.90, 0.40, 0.20}"
    Line width: 2
    @drawExactResponse: bwL, maxFreq

    # Mark mid cutoff.
    if mid_freq_cutoff < maxFreq
        Colour: "{0.5, 0.5, 0.5}"
        Dotted line
        Draw line: mid_freq_cutoff, 0, mid_freq_cutoff, gainMax * 1.06
        Solid line
    endif

    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 9
    Text top: "no", "Harmonic Gain Law (f0=" + string$(fundamental_frequency) + " Hz)"
    Text left: "yes", "Gain"
    Text bottom: "yes", "Frequency (Hz)"

    Font size: 6
    Colour: "{0.90, 0.40, 0.20}"
    Text: 0.02*maxFreq, "left", gainMax*0.96, "half", "L half-width " + fixed$(bwL,1) + " Hz"
    if create_stereo
        Colour: "{0.25, 0.50, 0.82}"
        Text: 0.27*maxFreq, "left", gainMax*0.96, "half", "R half-width " + fixed$(bwR,1) + " Hz"
    endif
    Colour: "Black"

    # Info panel
    Select outer viewport: 0, 8, 5.3, 5.9
    Select inner viewport: 0.5, 7.7, 5.35, 5.85
    
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    
    Font size: 9
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.5, "half", "f0: " + string$(fundamental_frequency) + " Hz"
    Text: 0.17, "left", 0.5, "half", "Half-width L/R: " + fixed$(bwL, 0) + "/" + fixed$(bwR, 0) + " Hz"
    Text: 0.40, "left", 0.5, "half", "Boost: " + fixed$(harmonic_boost, 1) + "x"
    Text: 0.55, "left", 0.5, "half", "Atten: " + fixed$(low_mid_attenuation, 2) + "/" + fixed$(high_freq_attenuation, 2)
    if create_stereo
        Text: 0.75, "left", 0.5, "half", "Comb coverage L/R: " + fixed$(100*coverageL,0) + "%/" + fixed$(100*coverageR,0) + "%"
    else
        Text: 0.75, "left", 0.5, "half", "Comb coverage: " + fixed$(100*coverageL,0) + "%"
    endif
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

# ============================================================
# CLEANUP
# ============================================================

# Keep visualization spectra until after drawing, then remove them here.
if create_stereo
    if sharedBaseSpectrum
        removeObject: spectrumL_ID
    else
        removeObject: spectrumL_ID, spectrumR_ID
    endif
    removeObject: spectrumL_mod_ID, spectrumR_mod_ID
else
    removeObject: spectrumL_ID, spectrumL_mod_ID
endif

# ============================================================
# OUTPUT
# ============================================================

appendInfoLine: ""
appendInfoLine: "=== COMPLETE ==="
appendInfoLine: ""
appendInfoLine: "Harmonics: ", fundStr$, ", ", fixed$(fundamental_frequency * 2, 0), ", ", fixed$(fundamental_frequency * 3, 0), ", ", fixed$(fundamental_frequency * 4, 0), "... Hz"
appendInfoLine: ""
appendInfoLine: "Created: ", originalName$, "_harmonic_", presetName$

if play_result
    selectObject: resultID
    Play
endif
selectObject: resultID

# ============================================================
# PROCEDURES
# ============================================================

# Baseline (non-harmonic) gain at frequency .f: mirrors the audio Formula.
procedure baseGain: .f
    if .f < mid_freq_cutoff
        .v = low_mid_attenuation
    else
        .v = high_freq_attenuation
    endif
endproc

# Exact harmonic gain law at one frequency. This is the same predicate used by
# the Spectrum Formula, including the n>=1 DC/subsonic exclusion.
procedure exactGain: .f, .halfWidth
    .n = round(.f / fundamental_frequency)
    if .n >= 1 and abs(.f - .n * fundamental_frequency) < .halfWidth
        .v = harmonic_boost
    else
        @baseGain: .f
        .v = baseGain.v
    endif
endproc

# Draw the exact piecewise-constant response. Breakpoints are the intersection
# of each +/-halfWidth band with the nearest-harmonic Voronoi cell:
#   [(n-0.5)f0, (n+0.5)f0].
# This is important when halfWidth >= f0/2: cells meet and the response becomes
# continuously boosted above f0/2 instead of drawing fictitious gaps.
procedure drawExactResponse: .halfWidth, .fMax
    .cursor = 0
    .n = 1
    while (.n - 0.5) * fundamental_frequency < .fMax
        .cellL = (.n - 0.5) * fundamental_frequency
        .cellR = (.n + 0.5) * fundamental_frequency
        .bandL = max(.cellL, .n * fundamental_frequency - .halfWidth)
        .bandR = min(.cellR, .n * fundamental_frequency + .halfWidth)
        .bandL = max(0, .bandL)
        .bandR = min(.fMax, .bandR)

        if .bandL > .cursor
            @baseGain: .cursor
            .g0 = baseGain.v
            @baseGain: .bandL
            .g1 = baseGain.v
            if mid_freq_cutoff > .cursor and mid_freq_cutoff < .bandL
                Draw line: .cursor, .g0, mid_freq_cutoff, .g0
                @baseGain: mid_freq_cutoff + 1e-9
                .g2 = baseGain.v
                Draw line: mid_freq_cutoff, .g0, mid_freq_cutoff, .g2
                Draw line: mid_freq_cutoff, .g2, .bandL, .g2
            else
                Draw line: .cursor, .g0, .bandL, .g1
            endif
        endif

        if .bandR > .bandL
            @baseGain: .bandL
            .gbL = baseGain.v
            if .bandL > .cursor
                Draw line: .bandL, .gbL, .bandL, harmonic_boost
            elsif .bandL = 0
                Draw line: .bandL, .gbL, .bandL, harmonic_boost
            endif
            Draw line: .bandL, harmonic_boost, .bandR, harmonic_boost

            .nextL = max((.n + 0.5) * fundamental_frequency,
                ... (.n + 1) * fundamental_frequency - .halfWidth)
            if .nextL > .bandR + 1e-9 and .bandR < .fMax
                @baseGain: .bandR
                .gbR = baseGain.v
                Draw line: .bandR, harmonic_boost, .bandR, .gbR
            endif
            .cursor = max(.cursor, .bandR)
        endif

        .n = .n + 1
    endwhile

    if .cursor < .fMax
        @baseGain: .cursor
        .g0 = baseGain.v
        @baseGain: .fMax
        .g1 = baseGain.v
        if mid_freq_cutoff > .cursor and mid_freq_cutoff < .fMax
            Draw line: .cursor, .g0, mid_freq_cutoff, .g0
            @baseGain: mid_freq_cutoff + 1e-9
            .g2 = baseGain.v
            Draw line: mid_freq_cutoff, .g0, mid_freq_cutoff, .g2
            Draw line: mid_freq_cutoff, .g2, .fMax, .g2
        else
            Draw line: .cursor, .g0, .fMax, .g1
        endif
    endif
endproc

