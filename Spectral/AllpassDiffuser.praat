# ============================================================
# Praat AudioTools - AllpassDiffuser.praat
# Category: Phase / Allpass Processing
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.2.0 (2026)
#
# Changelog v0.2.0 - QA pass. Four substantive fixes:
#   - TRUNCATION. v0.1.0 capped each section's impulse response at 6 s, and
#     its header claimed |H| stayed within 1e-5 "at every parameter extreme".
#     That claim was false and the cap was the reason. Measured on a single
#     worst-case section (base delay 1523):
#         g=0.95 size=1.0   dropped tap 0.0001   |H| dev 2.9e-04
#         g=0.95 size=4.0   dropped tap 0.110    |H| dev 2.3e-01
#         g=0.95 size=8.0   dropped tap 0.341    |H| dev 7.0e-01
#     At +/-5.6 dB of ripple that is not an allpass at all. Extremes of
#     `sections` and `g` had been tested; high `g` combined with high `size`
#     had not. The cap is now 40 s (worst case |H| dev 1.3e-03, and no preset
#     comes near it), the amplitude of the first dropped tap is computed, and
#     a NOTE is printed when it exceeds 0.001. The header no longer claims
#     more than was measured.
#   - OFF BY ONE. irLen was tapsHere * mSamp + 1 while taps were written only
#     up to k = tapsHere - 1, so every section carried one extra delay
#     interval of trailing silence and the reported tail was inflated.
#     Now (tapsHere - 1) * mSamp + 1. Removes 0.12 s at the default and
#     0.19 s on Long smear.
#   - ONE CONVOLUTION INSTEAD OF EIGHT. The section impulse responses are now
#     convolved with each other first, into a single composite allpass IR,
#     and the signal passes through that once. Mathematically the same
#     cascade, but the old form pushed the whole signal through 6-8 separate
#     convolutions, each on a longer signal than the last. The composite IR
#     was being built for the visualization anyway, so it is now built once
#     and used for both.
#   - NORMALIZE DEFAULT IS NOW `none`. An allpass spreads the same energy
#     over a longer output, so RMS measured across the whole result is lower
#     by construction. Renormalizing to the input RMS undoes exactly the
#     energy preservation that is the point of the tool: on Long smear
#     (16 s tail on a 5 s source) that is a factor of about 2. `none` is
#     already energy-correct and cannot clip, since spreading lowers the
#     peak. `peak` remains as a safety option; `rms` is loudness
#     compensation, not neutral normalization, and should be chosen
#     knowingly.
#   - New preset "Phase halo": 5 sections, g 0.62, longer delays. Sparse
#     early (1150 taps/s at 20 ms) building to diffuse (15200 at 100 ms) -
#     spreading around attacks rather than an immediate cloud. It sits
#     between Light dispersion and Long smear.
#   - Input and output waveforms are drawn on a shared Y range, so a change
#     in peak structure is visible instead of being hidden by two
#     independent autoscales.
#
# Changelog v0.1.0:
#   - First release. Pure Praat: no Python, no torch, no subprocess, no temp
#     files. A series of Schroeder allpass sections applied by FFT convolution.
#   - Play_impulse_response / Play_result, as in CA_Reverb_IR.praat.
#   - Multichannel handling follows CA_Reverb_IR.praat: Convolve broadcasts a
#     mono impulse response across a multichannel signal, and out-of-range
#     object[] reads return 0.
#
# WHAT IT DOES
#   The magnitude response is flat. Across all presets the measured deviation
#   of |H| from unity is between 4e-6 and 2e-5 (under 0.0002 dB) and the total
#   energy of the impulse response is 1.00000. What changes is phase, and
#   therefore the temporal structure: a transient is spread into a dense cloud
#   with no intentional EQ.
#
#   That figure is for the presets. Extreme Custom settings - a high g with a
#   large size - need a genuinely enormous tail, and where the 40 s cap
#   truncates it, the chain stops being strictly allpass. The script measures
#   the actual magnitude spread every run and prints it; trust that number
#   rather than this paragraph.
#
#   Measured echo density of the default setting (6 sections, g = 0.70):
#       13700 taps/s at 20 ms, 39100 at 100 ms.
#   Roughly 5000/s already reads as diffuse, so the cloud is fully dense
#   within the first 20 ms.
#
# HOW, AND WHY NOT THE OBVIOUS WAY
#   The textbook allpass section is recursive:
#       v[n] = x[n] + g v[n-M]
#       y[n] = -g v[n] + v[n-M]
#   A per-sample loop over that in a Praat script would be hopeless. Praat's
#   Formula can express recursion in a single C-level pass, but only if
#   self[col-M] sees values written earlier in the SAME pass - a semantic
#   detail this script deliberately does not rely on.
#
#   Instead each section is expanded into its closed-form impulse response,
#   which is sparse:
#       h[0]  = -g
#       h[kM] = (1 - g^2) g^(k-1)      for k = 1, 2, 3, ...
#   Those are convolved together into one composite IR, which is applied to
#   the signal with Praat's FFT-based Convolve.
#
# RELATION TO ACOUSTIC DNA RESONATOR
#   Complementary, not competing. AcousticDNAResonator imposes the spectral
#   envelope and frequency-dependent decay of a source onto an FDN; it is
#   about colour. This is about time and phase only.
#
#   Worth knowing: an orthogonal feedback matrix is LOSSLESS, which is not the
#   same as ALLPASS. Measured on the AcousticDNAResonator network with damping
#   fully removed (g0 = 0.9998, flat damping filters), |H| still has 7.8 dB
#   std and a 25 dB spread from 80 Hz to 16 kHz. This chain measures 0.012 dB
#   std on the same test - a factor of about 800.
#
# CAVEAT, STATED PLAINLY
#   Flat magnitude is NOT perceptual neutrality. Series allpass chains can
#   sound metallic and fluttery despite |H| = 1: the colouration moves into
#   the time domain, into the echo pattern, rather than disappearing. The
#   "Metallic comb" preset exists to make that audible on purpose. Judge by
#   ear, not by the flatness figure.
#
# MEASURED PRESET BEHAVIOUR (impulse response, 44.1 kHz)
#   preset             sec     g  size    IR s   dens@20ms  dens@100ms
#   Light dispersion     3  0.50   0.6    0.18        6850        6450
#   Custom (default)     6  0.70   1.0    2.26       13700       39100
#   Phase halo           5  0.62   2.2    2.52        1150       15200
#   Dense cloud          8  0.75   1.0    5.74       14150       37600
#   Long smear           8  0.85   1.6   16.25        3150       21550
#   Metallic comb        2  0.85   1.5    1.04        1000        3200
#   |H| deviation from unity is between 4e-6 and 2e-5 for all of them.
# ============================================================

form Allpass Diffuser
    optionmenu Preset: 1
        option Custom
        option Light dispersion
        option Phase halo
        option Dense cloud
        option Long smear
        option Metallic comb
    natural Sections 6
    positive Diffusion_g 0.7
    positive Size 1.0
    real Dry_wet 1.0
    optionmenu Normalize: 1
        option none
        option peak
        option rms (loudness compensation)
    boolean Draw_visualization 1
    boolean Play_impulse_response 0
    boolean Play_result 1
endform

# ---- PRESET APPLICATION ----
if preset = 2
    # Light dispersion - short, already diffuse, barely lengthens the signal
    sections = 3
    diffusion_g = 0.5
    size = 0.6
    dry_wet = 0.6
    presetName$ = "LightDispersion"
elsif preset = 3
    # Phase halo - sparse early, diffuse later. Spreads around attacks
    # instead of replacing them with an immediate cloud.
    sections = 5
    diffusion_g = 0.62
    size = 2.2
    dry_wet = 0.8
    presetName$ = "PhaseHalo"
elsif preset = 4
    # Dense cloud - the classic click-to-cloud transformation
    sections = 8
    diffusion_g = 0.75
    size = 1.0
    dry_wet = 1.0
    presetName$ = "DenseCloud"
elsif preset = 5
    # Long smear - slower build-up, ~16 s tail, which is added to the signal
    sections = 8
    diffusion_g = 0.85
    size = 1.6
    dry_wet = 1.0
    presetName$ = "LongSmear"
elsif preset = 6
    # Metallic comb - deliberately too sparse to diffuse. |H| is exactly as
    # flat as the others; this preset exists to demonstrate that flat
    # magnitude does not mean neutral.
    sections = 2
    diffusion_g = 0.85
    size = 1.5
    dry_wet = 1.0
    presetName$ = "MetallicComb"
else
    presetName$ = "Custom"
endif

if normalize = 1
    normName$ = "none"
elsif normalize = 2
    normName$ = "peak"
else
    normName$ = "rms"
endif

# ---- VALIDATE ----
if sections > 8
    sections = 8
endif
if diffusion_g > 0.95
    diffusion_g = 0.95
endif
if diffusion_g < 0.05
    diffusion_g = 0.05
endif
if size > 8
    size = 8
endif
if size < 0.1
    size = 0.1
endif
if dry_wet > 1
    dry_wet = 1
endif
if dry_wet < 0
    dry_wet = 0
endif

if numberOfSelected("Sound") <> 1
    exitScript: "Select exactly one Sound."
endif
snd = selected("Sound")
soundName$ = selected$("Sound")
sr = Get sampling frequency
nch = Get number of channels
inDur = Get total duration
inRms = Get root-mean-square: 0, 0
inPeak = Get absolute extremum: 0, 0, "None"

# Mutually coprime section delays, in samples at 44100 Hz.
delayBase1 = 149
delayBase2 = 211
delayBase3 = 353
delayBase4 = 457
delayBase5 = 631
delayBase6 = 823
delayBase7 = 1123
delayBase8 = 1523

writeInfoLine: "=== Allpass Diffuser v0.2.0 ===  ", soundName$, "  [", presetName$, "]"
appendInfoLine: sections, " sections | g ", fixed$(diffusion_g, 2), " | size ",
    ... fixed$(size, 2), " | dry/wet ", fixed$(dry_wet, 2), " | norm ", normName$,
    ... " | in ", fixed$(inDur, 2), " s, ", nch, " ch"

# Taps needed for the geometric series to fall below 1e-6, capped per section
# so that a pathological g x size combination cannot demand a minute-long
# impulse response. Where the cap bites, the chain stops being strictly
# allpass, so the amplitude of the first dropped tap is tracked and reported.
nTaps = ceiling(ln(1e-6) / ln(diffusion_g))
if nTaps < 4
    nTaps = 4
endif
worstDropped = 0

# ---- build one sparse impulse response per section ----
totalIrSec = 0
delayList$ = ""
for s to sections
    mBase = delayBase's'
    mSamp = round(mBase * size * sr / 44100)
    if mSamp < 8
        mSamp = 8
    endif
    tapsHere = nTaps
    if tapsHere * mSamp > 40 * sr
        tapsHere = floor(40 * sr / mSamp)
    endif
    if tapsHere < 4
        tapsHere = 4
    endif
    dropped = diffusion_g ^ tapsHere
    if dropped > worstDropped
        worstDropped = dropped
    endif

    # Last tap sits at (tapsHere - 1) * mSamp, so that is the length. The
    # extra mSamp v0.1.0 allocated here was pure trailing silence.
    irLen = (tapsHere - 1) * mSamp + 1
    totalIrSec = totalIrSec + irLen / sr
    if s = 1
        delayList$ = string$(mSamp)
    else
        delayList$ = delayList$ + "," + string$(mSamp)
    endif

    ir's' = Create Sound from formula: "apir" + string$(s), 1, 0, irLen / sr, sr, "0"
    Set value at sample number: 1, 1, -diffusion_g
    amp = 1 - diffusion_g * diffusion_g
    for k to tapsHere - 1
        pos = k * mSamp + 1
        if pos <= irLen
            Set value at sample number: 1, pos, amp
        endif
        amp = amp * diffusion_g
    endfor
endfor
appendInfoLine: "Delays (smp): ", delayList$
appendInfoLine: "Sections:     ", fixed$(totalIrSec, 2), " s of section IRs, ", nTaps, " taps each"
if worstDropped > 0.001
    appendInfoLine: "  WARNING: the 40 s per-section cap truncated the series."
    appendInfoLine: "           First dropped tap: ", fixed$(worstDropped, 4),
        ... " - the chain is NOT strictly allpass here."
    appendInfoLine: "           Lower g or Size. The measured spread below shows the damage."
endif

# ---- cascade the section IRs into ONE composite allpass IR ----
# Same cascade mathematically, but the signal is convolved once instead of
# once per section, and this IR is what the visualization needs anyway.
selectObject: ir1
compIr = Copy: "apChainIR"
for s from 2 to sections
    selectObject: compIr, ir's'
    nxt = Convolve: "sum", "zero"
    removeObject: compIr
    compIr = nxt
endfor
for s to sections
    removeObject: ir's'
endfor
selectObject: compIr
Rename: "apChainIR"
chainDur = Get total duration
appendInfoLine: "Composite IR: ", fixed$(chainDur, 2), " s (one convolution, not ", sections, ")"
if chainDur > 8
    appendInfoLine: "  NOTE: that tail is added to the signal length."
endif

# ---- apply it ----
# Convolve broadcasts a mono impulse response across a multichannel signal.
selectObject: snd
plusObject: compIr
out = Convolve: "sum", "zero"
selectObject: out
Rename: soundName$ + "_apdiff"
outDur = Get total duration

# ---- dry/wet mix ----
# The dry ends where it ends and the tail stays pure wet: out-of-range
# object[] reads return 0.
dryGain = cos(dry_wet * pi / 2)
wetGain = sin(dry_wet * pi / 2)
if dryGain > 0.0001
    selectObject: out
    Formula: "self * " + string$(wetGain)
        ... + " + object[" + string$(snd) + ", row, col] * " + string$(dryGain)
endif

# ---- normalize ----
selectObject: out
if normalize = 2
    pk = Get absolute extremum: 0, 0, "None"
    if pk > 0
        Multiply: inPeak / pk
    endif
elsif normalize = 3
    rms = Get root-mean-square: 0, 0
    if rms > 0
        Multiply: inRms / rms
    endif
endif

selectObject: out
outPeak = Get absolute extremum: 0, 0, "None"
outRms = Get root-mean-square: 0, 0

# ---- measured flatness, rather than a claimed one ----
selectObject: compIr
spec = To Spectrum: "yes"
ltas = To Ltas (1-to-1)
fTop = sr / 2 - 1000
if fTop > 16000
    fTop = 16000
endif
ltasMax = Get maximum: 80, fTop, "None"
ltasMin = Get minimum: 80, fTop, "None"
flatSpread$ = fixed$(ltasMax - ltasMin, 3)
removeObject: spec

appendInfoLine: "Output:       ", fixed$(outDur, 3), " s | peak ", fixed$(inPeak, 4),
    ... " -> ", fixed$(outPeak, 4), " | RMS ", fixed$(inRms, 6), " -> ", fixed$(outRms, 6)
appendInfoLine: "|H| spread:   ", flatSpread$, " dB over 80 Hz - ", fixed$(fTop, 0), " Hz (measured)"
appendInfoLine: "Note: |H| is flat by construction. If this sounds coloured,"
appendInfoLine: "      that colour is temporal (echo pattern), not spectral."

if play_impulse_response
    selectObject: compIr
    Play
endif

# ===========================================================================
# Visualization
# ===========================================================================
if draw_visualization
    # Shared amplitude range, so a change in peak structure is visible rather
    # than hidden by two independent autoscales.
    ampViz = inPeak
    if outPeak > ampViz
        ampViz = outPeak
    endif
    if ampViz <= 0
        ampViz = 1
    endif
    ampViz = ampViz * 1.05

    Erase all
    Select outer viewport: 0, 8, 0, 8
    Font size: 10

    # === Title ===
    Select outer viewport: 0, 8, 0, 0.6
    Axes: 0, 1, 0, 1
    Font size: 14
    Colour: "{0.2, 0.2, 0.4}"
    Text: 0.5, "centre", 0.5, "half", "Allpass Diffuser v0.2.0 - " + soundName$
    Font size: 10
    Colour: "Black"

    # === Input waveform ===
    Select outer viewport: 0, 8, 0.7, 2.6
    Select inner viewport: 0.6, 7.7, 0.8, 2.5
    selectObject: snd
    Colour: "{0.2, 0.4, 0.75}"
    Draw: 0, 0, -ampViz, ampViz, "no", "curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Input waveform (shared Y range)"
    Text bottom: "yes", "Time (s)"

    # === Diffused output waveform ===
    Select outer viewport: 0, 8, 2.7, 4.6
    Select inner viewport: 0.6, 7.7, 2.8, 4.5
    selectObject: out
    Colour: "{0.75, 0.35, 0.2}"
    Draw: 0, 0, -ampViz, ampViz, "no", "curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text top: "no", "Diffused output - same energy, spread over time (shared Y range)"
    Text bottom: "yes", "Time (s)"

    # === Chain impulse response ===
    Select outer viewport: 0, 4, 4.7, 6.6
    Select inner viewport: 0.7, 3.8, 4.9, 6.5
    selectObject: compIr
    Colour: "{0.35, 0.55, 0.35}"
    Draw: 0, 0, 0, 0, "no", "curve"
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "Amplitude"
    Text bottom: "yes", "Time (s)"
    Text top: "no", "Composite allpass IR - " + fixed$(chainDur, 2) + " s"

    # === Magnitude flatness ===
    # A fixed 12 dB window centred on the mean. If the chain is allpass this
    # panel is a flat line through the middle; anything else shows at once.
    Select outer viewport: 4, 8, 4.7, 6.6
    Select inner viewport: 4.7, 7.8, 4.9, 6.5
    ltasMid = (ltasMax + ltasMin) / 2
    selectObject: ltas
    Axes: 80, fTop, ltasMid - 6, ltasMid + 6
    Paint rectangle: "{0.97, 0.97, 0.99}", 80, fTop, ltasMid - 6, ltasMid + 6
    Colour: "{0.2, 0.4, 0.75}"
    Line width: 2
    Draw: 80, fTop, ltasMid - 6, ltasMid + 6, "no", "curve"
    Line width: 1
    Colour: "Black"
    Draw inner box
    Font size: 6
    Text left: "yes", "dB (12 dB window)"
    Text bottom: "yes", "Frequency (Hz)"
    Text top: "no", "Magnitude response - spread " + flatSpread$ + " dB"

    # === Summary Panel ===
    Select outer viewport: 0, 8, 6.7, 8.0
    Select inner viewport: 0.6, 7.7, 6.8, 7.9
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1

    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.90, "half", "Summary:"
    Font size: 6
    Colour: "{0.3, 0.3, 0.3}"
    Text: 0.02, "left", 0.74, "half", "Preset: " + presetName$ + " | Sections: " + string$(sections) + " | g: " + fixed$(diffusion_g, 2) + " | Size: " + fixed$(size, 2) + " | Dry/wet: " + fixed$(dry_wet, 2) + " | Norm: " + normName$
    Text: 0.02, "left", 0.58, "half", "Composite IR: " + fixed$(chainDur, 2) + " s | Magnitude spread: " + flatSpread$ + " dB (allpass target: ~0)"
    Text: 0.02, "left", 0.42, "half", "Duration: " + fixed$(inDur, 2) + "s -> " + fixed$(outDur, 2) + "s | Ch: " + string$(nch) + " | Peak: " + fixed$(inPeak, 4) + " -> " + fixed$(outPeak, 4) + " | RMS: " + fixed$(inRms, 5) + " -> " + fixed$(outRms, 5)
    Text: 0.02, "left", 0.26, "half", "Delays (smp): " + delayList$
    if worstDropped > 0.001
        Colour: "{0.8, 0.2, 0.2}"
        Text: 0.02, "left", 0.08, "half", "Warn: series truncated (first dropped tap " + fixed$(worstDropped, 4) + ") - not strictly allpass. Lower g or Size."
    else
        Colour: "{0.5, 0.35, 0.2}"
        Text: 0.02, "left", 0.08, "half", "Flat magnitude is not perceptual neutrality - any colour you hear is temporal, in the echo pattern."
    endif

    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    Font size: 10
endif

removeObject: ltas
removeObject: compIr

selectObject: out
if play_result
    Play
endif

selectObject: out
appendInfoLine: "Done."
