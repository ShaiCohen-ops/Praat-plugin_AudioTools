# ============================================================
# Praat AudioTools - Grisey_Spectral_Becoming_Engine.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.0 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Spectral synthesis engine inspired by Gérard Grisey's concept
#   of "spectral becoming" (devenir spectral). Generates a slowly
#   evolving additive synthesis sound that transforms from a fused
#   harmonic timbre into a progressively inharmonic, spectrally
#   diffused texture.
#
#   Implements continuous spectral metamorphosis:
#     - Phase-correct frequency chirps per partial (harmonic -> inharmonic)
#     - Time-varying spectral energy redistribution (brightness evolution)
#     - Micro-detuning emergence (beating patterns from spectral drift)
#     - Configurable temporal dilation curves (linear / exp / log)
#     - Spectral breathing (slow global amplitude modulation)
#     - Smooth global envelope (cosine fade in/out)
#
#   References:
#     - Grisey, G. (1987). Tempus ex Machina. Contemporary Music Review.
#     - Grisey: Partiels (1975), Les Espaces Acoustiques (1974-85)
#     - Murail, T. (2005). The Revolution of Complex Sounds.
#     - Fineberg, J. (2000). Spectral Music. Contemporary Music Review.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis-Resynthesis
#   Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Category: Generative & Synthesis Systems
# ============================================================

# ============================================================
# FORM
# ============================================================
form Grisey - Spectral Becoming Engine v1.0
    comment === Preset ===
    optionmenu Preset: 2
        option Custom
        option Partiels (trombone E, slow bloom)
        option Gondwana (deep drift)
        option Vortex (fast dissolution)
        option Meditation (static shimmer)
        option Prologue (voice-like)
    comment === Spectral Source ===
    positive Fundamental_Hz 41.2
    natural Number_of_partials 24
    positive Duration_s 30
    comment === Transformation ===
    positive Inharmonicity_factor 0.05
    positive Micro_detuning_Hz 2.0
    comment === Temporal Shape ===
    optionmenu Temporal_curve: 3
        option Linear
        option Exponential (early change)
        option Logarithmic (late change)
    comment === Output ===
    positive Sample_rate 44100
    boolean Show_visualization 1
endform

# ============================================================
# APPLY PRESETS
# ============================================================

# Default envelope/breathing parameters (presets override)
breathRate = 0.15
breathDepth = 0.12
fadeInFraction = 0.05
fadeOutFraction = 0.10

if preset = 2
    # PARTIELS: Trombone E1, slow spectral bloom
    # Inspired by the opening of Partiels (1975):
    # harmonic fusion slowly dissolving into spectral components
    presetName$ = "Partiels"
    fundamental_Hz = 41.2
    number_of_partials = 24
    duration_s = 30
    inharmonicity_factor = 0.04
    micro_detuning_Hz = 1.5
    temporal_curve = 3
    breathRate = 0.12
    breathDepth = 0.10
    fadeInFraction = 0.03
    fadeOutFraction = 0.12

elsif preset = 3
    # GONDWANA: Deep fundamental, very slow drift
    # Inspired by the geological time-scale transformations
    presetName$ = "Gondwana"
    fundamental_Hz = 32.7
    number_of_partials = 32
    duration_s = 45
    inharmonicity_factor = 0.08
    micro_detuning_Hz = 3.0
    temporal_curve = 3
    breathRate = 0.08
    breathDepth = 0.15
    fadeInFraction = 0.04
    fadeOutFraction = 0.15

elsif preset = 4
    # VORTEX: Fast spectral dissolution
    # Rapid transformation from order to chaos
    presetName$ = "Vortex"
    fundamental_Hz = 65.41
    number_of_partials = 20
    duration_s = 15
    inharmonicity_factor = 0.20
    micro_detuning_Hz = 5.0
    temporal_curve = 2
    breathRate = 0.25
    breathDepth = 0.08
    fadeInFraction = 0.02
    fadeOutFraction = 0.08

elsif preset = 5
    # MEDITATION: Static shimmer, minimal drift
    # Near-harmonic with gentle beating patterns
    presetName$ = "Meditation"
    fundamental_Hz = 55.0
    number_of_partials = 16
    duration_s = 60
    inharmonicity_factor = 0.01
    micro_detuning_Hz = 0.8
    temporal_curve = 1
    breathRate = 0.06
    breathDepth = 0.20
    fadeInFraction = 0.08
    fadeOutFraction = 0.08

elsif preset = 6
    # PROLOGUE: Voice-like formant region
    # Mid-range fundamental with speech-like spectral distribution
    presetName$ = "Prologue"
    fundamental_Hz = 110.0
    number_of_partials = 18
    duration_s = 25
    inharmonicity_factor = 0.06
    micro_detuning_Hz = 2.5
    temporal_curve = 1
    breathRate = 0.18
    breathDepth = 0.14
    fadeInFraction = 0.06
    fadeOutFraction = 0.10

else
    presetName$ = "Custom"
endif

# ============================================================
# SETUP
# ============================================================
f0 = fundamental_Hz
nPartials = number_of_partials
duration = duration_s
inharm = inharmonicity_factor
detHz = micro_detuning_Hz
curveType = temporal_curve
sr = sample_rate
nyquist = sr / 2

piVal = 3.14159265358979
epsilon = 1e-12

# Spectral brightness evolution:
#   alphaStart = 1.0 (natural 1/n rolloff = fused timbre)
#   alphaEnd depends on inharmonicity (more inharm = brighter end state)
alphaStart = 1.0
alphaEnd = 1.0 - inharm * 1.5
if alphaEnd < 0.2
    alphaEnd = 0.2
endif

# Global envelope timing
fadeInDur = duration * fadeInFraction
if fadeInDur < 0.05
    fadeInDur = 0.05
endif
if fadeInDur > 2.0
    fadeInDur = 2.0
endif

fadeOutDur = duration * fadeOutFraction
if fadeOutDur < 0.1
    fadeOutDur = 0.1
endif
if fadeOutDur > 3.0
    fadeOutDur = 3.0
endif

# Curve names for display
if curveType = 1
    curveName$ = "Linear"
elsif curveType = 2
    curveName$ = "Exponential"
else
    curveName$ = "Logarithmic"
endif

# Constants for exponential curve phase integral
# curve(u) = (exp(3u) - 1) / (exp(3) - 1)
expDenom = exp(3) - 1

# Constants for logarithmic curve phase integral
# curve(u) = ln(1 + 9u) / ln(10)
logDenom = 9 * ln(10)

# ============================================================
# INFO HEADER
# ============================================================
writeInfoLine: "=== Grisey - Spectral Becoming Engine v1.0 ==="
appendInfoLine: ""
appendInfoLine: "Preset: ", presetName$
appendInfoLine: "Fundamental: ", fixed$(f0, 2), " Hz"
appendInfoLine: "Partials: ", nPartials
appendInfoLine: "Duration: ", fixed$(duration, 1), " s"
appendInfoLine: "Inharmonicity: ", fixed$(inharm, 3)
appendInfoLine: "Micro-detuning: ", fixed$(detHz, 1), " Hz"
appendInfoLine: "Temporal curve: ", curveName$
appendInfoLine: "Brightness: alpha ", fixed$(alphaStart, 2),
    ... " -> ", fixed$(alphaEnd, 2)
appendInfoLine: "Breathing: ", fixed$(breathRate, 2),
    ... " Hz, depth ", fixed$(breathDepth, 2)
appendInfoLine: "Sample rate: ", sr, " Hz"
appendInfoLine: ""

# ============================================================
# STEP 1: Compute partial parameters
# ============================================================
appendInfoLine: "[1/5] Computing partial parameters..."

nSynthesized = 0
maxFreqUsed = 0

for pn from 1 to nPartials
    # Harmonic frequency (start state)
    fStart = f0 * pn
    
    # Inharmonic frequency (end state): f0 * n^(1+inharm)
    fEnd = f0 * pn ^ (1 + inharm)
    
    # Micro-detuning offset (scales with partial number)
    # Higher partials get more detuning -> wider beating
    detScale = pn / nPartials
    detOffset = randomGauss(0, detHz * detScale)
    fEnd = fEnd + detOffset
    
    # Floor
    if fEnd < 1
        fEnd = 1
    endif
    
    # Nyquist check
    fMaxPartial = fEnd
    if fStart > fEnd
        fMaxPartial = fStart
    endif
    
    if fMaxPartial >= nyquist * 0.95
        partialActive_'pn' = 0
        appendInfoLine: "  Partial ", pn, ": SKIPPED (", 
            ... fixed$(fMaxPartial, 1), " Hz >= Nyquist)"
    else
        partialActive_'pn' = 1
        nSynthesized = nSynthesized + 1
        
        # Amplitude envelope (spectral brightness evolution)
        # alpha interpolates from alphaStart to alphaEnd via curve
        # At any time t: amp(t) = 1/pn^alpha(t)
        # We pre-compute start and end amplitudes
        ampStart = 1 / pn ^ alphaStart
        ampEnd = 1 / pn ^ alphaEnd
        
        # Random initial phase (prevents peaky transient)
        phaseOffset = randomUniform(0, 2 * piVal)
        
        # Store for synthesis and visualization
        fStart_'pn' = fStart
        fEnd_'pn' = fEnd
        ampStart_'pn' = ampStart
        ampEnd_'pn' = ampEnd
        phaseOff_'pn' = phaseOffset
        
        if fEnd > maxFreqUsed
            maxFreqUsed = fEnd
        endif
        if fStart > maxFreqUsed
            maxFreqUsed = fStart
        endif
        
        appendInfoLine: "  Partial ", pn, ": ",
            ... fixed$(fStart, 1), " -> ", fixed$(fEnd, 1), " Hz",
            ... " | amp: ", fixed$(ampStart, 4), " -> ", fixed$(ampEnd, 4)
    endif
endfor

appendInfoLine: ""
appendInfoLine: "  Synthesizing ", nSynthesized, " / ", nPartials, " partials"
appendInfoLine: "  Frequency range: ", fixed$(f0, 1),
    ... " - ", fixed$(maxFreqUsed, 1), " Hz"
appendInfoLine: ""

# ============================================================
# STEP 2: Additive synthesis (phase-correct chirps)
# ============================================================
appendInfoLine: "[2/5] Additive synthesis..."

# Create silent accumulator
Create Sound from formula: "accumulator", 1, 0, duration, sr, "0"
accumulator = selected("Sound")

durStr$ = fixed$(duration, 8)
piStr$ = fixed$(piVal, 14)

for pn from 1 to nPartials
    if partialActive_'pn' = 1
        
        # Retrieve stored parameters
        fS = fStart_'pn'
        fE = fEnd_'pn'
        aS = ampStart_'pn'
        aE = ampEnd_'pn'
        ph = phaseOff_'pn'
        
        fDiff = fE - fS
        aDiff = aE - aS
        
        # Pre-stringify all values for Formula
        fsStr$ = fixed$(fS, 8)
        fdStr$ = fixed$(fDiff, 8)
        asStr$ = fixed$(aS, 8)
        adStr$ = fixed$(aDiff, 8)
        phStr$ = fixed$(ph, 8)
        
        # -----------------------------------------------
        # Build phase-correct Formula based on curve type
        #
        # For frequency f(t) varying over time, the correct
        # instantaneous phase is the integral of f(t):
        #   phi(t) = 2*pi * integral_0^t f(tau) dtau
        #
        # Each curve type has an analytical solution.
        # -----------------------------------------------
        
        if curveType = 1
            # === LINEAR ===
            # f(t) = fS + fDiff * t/dur
            # phi(t) = fS*t + fDiff*t^2 / (2*dur)
            # amp(t) = aS + aDiff * t/dur
            
            ampFormula$ = "(" + asStr$ + " + " + adStr$
                ... + " * x / " + durStr$ + ")"
            phaseFormula$ = "2 * " + piStr$ + " * ("
                ... + fsStr$ + " * x + " + fdStr$
                ... + " * x * x / (2 * " + durStr$
                ... + ")) + " + phStr$
        
        elsif curveType = 2
            # === EXPONENTIAL (early change) ===
            # curve(u) = (exp(3u) - 1) / (exp(3) - 1)
            # f(t) = fS + fDiff * curve(t/dur)
            # phi(t) = fS*t + fDiff/E * (dur/3*(exp(3t/dur)-1) - t)
            #   where E = exp(3) - 1 ≈ 19.0855
            # amp(t) = aS + aDiff * curve(t/dur)
            
            edStr$ = fixed$(expDenom, 8)
            
            ampFormula$ = "(" + asStr$ + " + " + adStr$
                ... + " * (exp(3 * x / " + durStr$
                ... + ") - 1) / " + edStr$ + ")"
            phaseFormula$ = "2 * " + piStr$ + " * ("
                ... + fsStr$ + " * x + " + fdStr$
                ... + " / " + edStr$ + " * (" + durStr$
                ... + " / 3 * (exp(3 * x / " + durStr$
                ... + ") - 1) - x)) + " + phStr$
        
        else
            # === LOGARITHMIC (late change) ===
            # curve(u) = ln(1 + 9u) / ln(10)
            # f(t) = fS + fDiff * curve(t/dur)
            # phi(t) = fS*t + fDiff*dur/(9*ln10) *
            #          ((1+9t/dur)*ln(1+9t/dur) - 9t/dur)
            # amp(t) = aS + aDiff * curve(t/dur)
            
            ldStr$ = fixed$(logDenom, 8)
            ln10Str$ = fixed$(ln(10), 8)
            
            ampFormula$ = "(" + asStr$ + " + " + adStr$
                ... + " * ln(1 + 9 * x / " + durStr$
                ... + ") / " + ln10Str$ + ")"
            phaseFormula$ = "2 * " + piStr$ + " * ("
                ... + fsStr$ + " * x + " + fdStr$
                ... + " * " + durStr$ + " / " + ldStr$
                ... + " * ((1 + 9 * x / " + durStr$
                ... + ") * ln(1 + 9 * x / " + durStr$
                ... + ") - 9 * x / " + durStr$
                ... + ")) + " + phStr$
        endif
        
        formula$ = ampFormula$ + " * sin(" + phaseFormula$ + ")"
        
        # Create partial sound
        Create Sound from formula: "partial_" + string$(pn),
            ... 1, 0, duration, sr, formula$
        partialSnd = selected("Sound")
        
        # Add to accumulator
        partId = partialSnd
        selectObject: accumulator
        Formula: "self + object[partId]"
        
        removeObject: partialSnd
        
        pnDiv4 = pn - floor(pn / 4) * 4
        if pnDiv4 = 0 or pn = nPartials
            appendInfoLine: "  ... partial ", pn, " / ", nPartials
        endif
    endif
endfor

appendInfoLine: "  Synthesis complete."
appendInfoLine: ""

# ============================================================
# STEP 3: Global envelope + spectral breathing
# ============================================================
appendInfoLine: "[3/5] Applying envelope and breathing..."

selectObject: accumulator

# --- Cosine fade in/out ---
fadeInStr$ = fixed$(fadeInDur, 8)
fadeOutStart = duration - fadeOutDur
fadeOutStartStr$ = fixed$(fadeOutStart, 8)
fadeOutStr$ = fixed$(fadeOutDur, 8)

Formula: "self * (if x < " + fadeInStr$
    ... + " then 0.5 - 0.5 * cos(" + piStr$
    ... + " * x / " + fadeInStr$ + ")"
    ... + " else (if x > " + fadeOutStartStr$
    ... + " then 0.5 + 0.5 * cos(" + piStr$
    ... + " * (x - " + fadeOutStartStr$
    ... + ") / " + fadeOutStr$ + ")"
    ... + " else 1 fi) fi)"

appendInfoLine: "  Fade in: ", fixed$(fadeInDur, 2), " s"
appendInfoLine: "  Fade out: ", fixed$(fadeOutDur, 2), " s"

# --- Spectral breathing (slow global AM) ---
# Creates the living, breathing quality characteristic of
# Grisey's sustained spectral textures
brStr$ = fixed$(breathRate, 8)
bdStr$ = fixed$(breathDepth, 8)

selectObject: accumulator
Formula: "self * (1 + " + bdStr$
    ... + " * sin(2 * " + piStr$
    ... + " * " + brStr$ + " * x))"

appendInfoLine: "  Breathing: ", fixed$(breathRate, 2),
    ... " Hz, depth ", fixed$(breathDepth, 2)
appendInfoLine: ""

# ============================================================
# STEP 4: Normalize and finalize
# ============================================================
appendInfoLine: "[4/5] Finalizing..."

selectObject: accumulator
Scale peak: 0.95
Rename: "Grisey_" + presetName$ + "_" + fixed$(f0, 0) + "Hz"
finalOutput = selected("Sound")
finalName$ = selected$("Sound")

appendInfoLine: "  Output: ", finalName$
appendInfoLine: ""

# ============================================================
# STEP 5: Visualization
# ============================================================
if show_visualization
    appendInfoLine: "[5/5] Visualization..."
    
    Erase all
    
    # --- Spectrogram parameters ---
    # Narrow-band to resolve individual partials
    specWindow = 0.05
    specMaxFreq = maxFreqUsed * 1.25
    if specMaxFreq > nyquist
        specMaxFreq = nyquist
    endif
    if specMaxFreq < 1000
        specMaxFreq = 1000
    endif
    
    # Create spectrogram
    selectObject: finalOutput
    To Spectrogram: specWindow, specMaxFreq, 0.002, 20, "Gaussian"
    specGram = selected("Spectrogram")
    
    # === TITLE ===
    Select outer viewport: 0, 8, 0, 0.55
    Axes: 0, 1, 0, 1
    Font size: 12
    Colour: "Black"
    Text: 0.5, "centre", 0.65, "half",
        ... "##Grisey - Spectral Becoming Engine v1.0##"
    Font size: 8
    Colour: "{0.4, 0.4, 0.5}"
    Text: 0.5, "centre", -0.3, "half",
        ... presetName$ + " | f0=" + fixed$(f0, 1)
        ... + " Hz | " + string$(nSynthesized) + " partials | "
        ... + fixed$(duration, 1) + " s | " + curveName$
    
    # === SPECTROGRAM + PARTIAL TRAJECTORIES (main panel) ===
    Select outer viewport: 0, 8, 0.65, 3.6
    Select inner viewport: 0.8, 7.5, 0.75, 3.5
    
    selectObject: specGram
    Paint: 0, 0, 0, specMaxFreq, 100, "yes", 50, 6, 0, "no"
    
    # Overlay partial trajectories
    # Draw frequency paths showing the spectral becoming
    Axes: 0, duration, 0, specMaxFreq
    
    nDrawPts = 40
    
    for pn from 1 to nPartials
        if partialActive_'pn' = 1
            fS = fStart_'pn'
            fE = fEnd_'pn'
            fD = fE - fS
            
            # Colour: warm-to-cool gradient
            # Low partials: warm yellow; high partials: cool cyan
            pnFrac = (pn - 1) / (nPartials - 1 + 0.001)
            rVal = 1.0 - pnFrac * 0.8
            gVal = 0.9 - pnFrac * 0.3
            bVal = 0.2 + pnFrac * 0.7
            Colour: "{" + fixed$(rVal, 2) + ", "
                ... + fixed$(gVal, 2) + ", "
                ... + fixed$(bVal, 2) + "}"
            Line width: 1
            
            # Draw trajectory as connected segments
            prevT = 0
            if curveType = 1
                prevF = fS
            elsif curveType = 2
                prevF = fS
            else
                prevF = fS
            endif
            
            for dp from 1 to nDrawPts
                t = dp / nDrawPts * duration
                u = t / duration
                
                # Compute curve value
                if curveType = 1
                    cu = u
                elsif curveType = 2
                    cu = (exp(3 * u) - 1) / expDenom
                else
                    cu = ln(1 + 9 * u) / ln(10)
                endif
                
                freq = fS + fD * cu
                
                if freq <= specMaxFreq and prevF <= specMaxFreq
                    Draw line: prevT, prevF, t, freq
                endif
                
                prevT = t
                prevF = freq
            endfor
        endif
    endfor
    
    Colour: "Black"
    Line width: 1
    Draw inner box
    Font size: 7
    Text left: "yes", "Hz"
    Text top: "no", "Spectrogram with Partial Trajectories"
    Marks left every: 1, 500, "yes", "yes", "no"
    
    removeObject: specGram
    
    # === WAVEFORM ZOOM: Start vs End ===
    # First 0.5s (harmonic fusion)
    zoomDur = 0.5
    if zoomDur > duration * 0.1
        zoomDur = duration * 0.1
    endif
    if zoomDur < 0.05
        zoomDur = 0.05
    endif
    
    # Get amp range
    selectObject: finalOutput
    startMax = Get maximum: fadeInDur, fadeInDur + zoomDur, "Sinc70"
    startMin = Get minimum: fadeInDur, fadeInDur + zoomDur, "Sinc70"
    endMax = Get maximum: duration - fadeOutDur - zoomDur, duration - fadeOutDur, "Sinc70"
    endMin = Get minimum: duration - fadeOutDur - zoomDur, duration - fadeOutDur, "Sinc70"
    
    absMax1 = startMax
    if absMax1 < 0
        absMax1 = -absMax1
    endif
    absMin1 = startMin
    if absMin1 < 0
        absMin1 = -absMin1
    endif
    if absMin1 > absMax1
        absMax1 = absMin1
    endif
    
    absMax2 = endMax
    if absMax2 < 0
        absMax2 = -absMax2
    endif
    absMin2 = endMin
    if absMin2 < 0
        absMin2 = -absMin2
    endif
    if absMin2 > absMax2
        absMax2 = absMin2
    endif
    
    if absMax1 > absMax2
        zoomAmp = absMax1 * 1.1
    else
        zoomAmp = absMax2 * 1.1
    endif
    if zoomAmp < 0.001
        zoomAmp = 0.001
    endif
    
    # Start zoom (harmonic state)
    Select outer viewport: 0, 4, 3.7, 4.6
    Select inner viewport: 0.8, 3.7, 3.75, 4.55
    
    selectObject: finalOutput
    Colour: "{0.3, 0.5, 0.8}"
    Draw: fadeInDur, fadeInDur + zoomDur, -zoomAmp, zoomAmp, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "Start: Harmonic Fusion (" + fixed$(zoomDur * 1000, 0) + " ms)"
    Text left: "yes", "Amp"
    
    # End zoom (inharmonic state)
    Select outer viewport: 4, 8, 3.7, 4.6
    Select inner viewport: 4.4, 7.5, 3.75, 4.55
    
    zoomEndStart = duration - fadeOutDur - zoomDur
    zoomEndEnd = duration - fadeOutDur
    
    selectObject: finalOutput
    Colour: "{0.8, 0.4, 0.2}"
    Draw: zoomEndStart, zoomEndEnd, -zoomAmp, zoomAmp, "no", "Curve"
    
    Colour: "Black"
    Draw inner box
    Font size: 7
    Text top: "no", "End: Spectral Dissolution (" + fixed$(zoomDur * 1000, 0) + " ms)"
    Text left: "yes", "Amp"
    
    # === STATS PANEL ===
    Select outer viewport: 0, 8, 4.7, 5.55
    Select inner viewport: 0.6, 7.7, 4.75, 5.5
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.95, 0.95, 0.95}", 0, 1, 0, 1
    Font size: 7
    Colour: "Black"
    Text: 0.02, "left", 0.88, "half", "##Spectral Becoming Summary##"
    Font size: 6
    Colour: "{0.3, 0.3, 0.35}"
    
    Text: 0.02, "left", 0.68, "half",
        ... "Source: f0=" + fixed$(f0, 1) + " Hz"
        ... + " | Partials: " + string$(nSynthesized) + "/" + string$(nPartials)
        ... + " | Range: " + fixed$(f0, 0) + "-" + fixed$(maxFreqUsed, 0) + " Hz"
        ... + " | Duration: " + fixed$(duration, 1) + " s"
        ... + " | SR: " + string$(sr) + " Hz"
    Text: 0.02, "left", 0.45, "half",
        ... "Transformation: inharm=" + fixed$(inharm, 3)
        ... + " | detune=" + fixed$(detHz, 1) + " Hz"
        ... + " | curve=" + curveName$
        ... + " | brightness: alpha " + fixed$(alphaStart, 2)
        ... + " -> " + fixed$(alphaEnd, 2)
    Text: 0.02, "left", 0.22, "half",
        ... "Envelope: fade in " + fixed$(fadeInDur, 2) + " s"
        ... + " / fade out " + fixed$(fadeOutDur, 2) + " s"
        ... + " | Breathing: " + fixed$(breathRate, 2) + " Hz"
        ... + " (depth " + fixed$(breathDepth, 2) + ")"
        ... + " | Preset: " + presetName$
    
    Colour: "Black"
    Draw rectangle: 0, 1, 0, 1
    
    # === LEGEND ===
    Select outer viewport: 0, 8, 5.6, 5.9
    Axes: 0, 1, 0, 1
    Font size: 6
    
    # Partial trajectory gradient sample
    Colour: "{1.0, 0.9, 0.2}"
    Draw line: 0.02, 0.5, 0.06, 0.5
    Colour: "Black"
    Text: 0.07, "left", 0.5, "half", "Low partials"
    
    Colour: "{0.5, 0.7, 0.6}"
    Draw line: 0.20, 0.5, 0.24, 0.5
    Colour: "Black"
    Text: 0.25, "left", 0.5, "half", "Mid partials"
    
    Colour: "{0.2, 0.6, 0.9}"
    Draw line: 0.38, 0.5, 0.42, 0.5
    Colour: "Black"
    Text: 0.43, "left", 0.5, "half", "High partials"
    
    Colour: "{0.3, 0.5, 0.8}"
    Draw line: 0.57, 0.5, 0.61, 0.5
    Colour: "Black"
    Text: 0.62, "left", 0.5, "half", "Start waveform"
    
    Colour: "{0.8, 0.4, 0.2}"
    Draw line: 0.77, 0.5, 0.81, 0.5
    Colour: "Black"
    Text: 0.82, "left", 0.5, "half", "End waveform"
    
    Font size: 10
    Colour: "Black"
    Line width: 1
    
    appendInfoLine: "  Visualization complete."
    appendInfoLine: ""
endif

# ============================================================
# PLAY + SELECT
# ============================================================
selectObject: finalOutput
Play

appendInfoLine: "=== Done ==="
appendInfoLine: "Output: ", finalName$
appendInfoLine: ""
appendInfoLine: "--- Compositional Notes ---"
appendInfoLine: "This sound models Grisey's 'spectral becoming':"
appendInfoLine: "  - Harmonic fusion at the start (unified timbre)"
appendInfoLine: "  - Progressive spectral fission (partials separate)"
appendInfoLine: "  - Beating patterns emerge from micro-detuning"
appendInfoLine: "  - Inharmonicity dissolves pitch into noise"
appendInfoLine: ""
appendInfoLine: "Suggested uses:"
appendInfoLine: "  - Source material for further spectral processing"
appendInfoLine: "  - Cross-synthesis filter (use as spectral envelope)"
appendInfoLine: "  - Layering with acoustic recordings"
appendInfoLine: "  - Time-stretching to reveal micro-structures"
