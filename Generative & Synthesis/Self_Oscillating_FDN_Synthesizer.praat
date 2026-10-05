# ============================================================
# Praat AudioTools - Self_Oscillating_FDN_Synthesizer.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Self-Oscillating FDN Synthesizer — nonlinear feedback delay network
#   synthesis, entirely in Praat (no Python, no external programs).
#
#   Eight delay lines are mixed through an energy-preserving 8 x 8
#   feedback matrix (normalised Hadamard by default), scaled by the loop
#   radius g, passed through a bounded nonlinearity and written back. The
#   network is started by a short excitation and then left alone: every
#   sound after that comes from the coupled feedback itself, not from
#   oscillators and not from a continuously injected source.
#
#   Per sample, for every line k:
#     y_k   = g_k * (delay line k read d_k samples ago)
#     l_k   = one-pole low-pass of y_k        (damping, own state per line)
#     h_k   = DC blocker of l_k               (own state per line)
#     m     = H * h                            (all eight lines coupled)
#     x_k   = f(m_k) + excitation_k            (written into line k)
#   Output: stereo, quad or 8-channel, from the eight states (see SPATIAL
#   OUTPUT: Orthogonal Field, Distributed Network, Orbiting Network).
#
#   Instability sets the network's growth rate rho in dB per second
#   (rho = 60 * u^3, u = -1 .. +1, so the resolution is finest around 0).
#   Each line gets its own per-pass radius g_k = 10^(rho d_k / (20 sr)),
#   the standard FDN design (Jot): all lines then grow or decay at the
#   same rate per second, whatever their length. With ONE global radius
#   the same setting would mean +43 dB/s in a 1 ms network and +1 dB/s in
#   a 45 ms one. rho < 0: the network decays (T60 = 60/|rho| s); rho ~ 0:
#   it rings almost indefinitely; rho > 0: small signals grow until the
#   bounded nonlinearity holds them (self-oscillation). The damping filter
#   has unit gain at low frequencies and attenuates highs, so with damping
#   the loop exceeds unity only in its passband. Report and figure give
#   both rho and the resulting per-pass radii.
#
#   How this runs fast in pure Praat:
#   nothing written into a delay line is read back sooner than the
#   shortest delay d_min. The network is therefore computed in exact
#   blocks of up to d_min samples with Formula (part) on 8-channel Sound
#   objects (one channel per line); a Formula visits columns in order and
#   sees values it has just written, which also gives each line a true
#   recursive one-pole damper and DC blocker. This is the same recursion as
#   a sample loop, not an approximation. Roughly 0.5 s of computing per
#   second of 44.1 kHz audio with the default delays; very short delays
#   mean more blocks and take longer (reported).
#
#   Nonlinear drive and asymmetry:
#   f(x) = [S(D(x + b)) - S(D b)] / (D S'(D b)), S = the chosen saturator,
#   D = drive, b = asymmetry. f has unit small-signal gain, so the loop
#   growth rate alone decides growth or decay. With b = 0 the network is
#   scale-invariant apart from the fixed excitation level: a sustained
#   oscillation at drive D is nearly the drive-1 oscillation scaled by 1/D
#   (measured: drive 1 vs 4, second-half correlation 0.98 after
#   normalisation). The asymmetry bias breaks that invariance, so drive
#   then changes the sustained dynamics substantially (measured at b = 0.15:
#   centre of gravity 373 -> 906 Hz, 33 dB log-spectral distance); it also
#   creates even harmonics. The DC blockers keep the bias from latching
#   the loop into a constant state.
#
#   Bistability: with asymmetry, f has unit slope at 0 but a steeper slope
#   (up to 1 / S'(Db)) near x = -b. A strong enough excitation can then
#   keep the network sounding even at a slightly negative growth rate,
#   while a weak one decays (measured: -2.6 dB/s, drive 3, asymmetry 0.25
#   stayed level for 6 s). This is a genuine nonlinear regime, not an
#   error; lower Asymmetry if a decaying response is wanted.
#
#   Terminology: regimes are described by the growth rate (dissipative,
#   near-critical, sustained, self-oscillating, strongly nonlinear). An
#   irregular-sounding result is not claimed to be chaotic in the
#   mathematical sense; that would need e.g. Lyapunov analysis.
#
# Changelog v1.1:
#   - Normalization: Peak / Resonance (RMS of the body, -18 dBFS, with the
#     Output peak as ceiling and an 8 ms fade-in so the excitation
#     transient does not set the level) / None. The Damped Resonator was
#     quiet because its first impulse set the peak normalisation.
#   - Order fixed: Subtract mean -> fades -> normalisation (v1.0
#     normalised before fading).
#   - Spatial modes: Orthogonal Field (v1.0 default), Distributed Network
#     (fixed node positions 1-5-3-7-2-6-4-8; the image moves only through
#     the network's own energy exchange), Orbiting Network (the circle
#     swings slowly; Spatial motion = swing amplitude, Spatial rate).
#     "Line panning" is replaced by Distributed.
#   - Output layout: Stereo / Quad / 8-channel ring.
#   - Damped Resonator and Critical Network excite with a 15 ms noise burst
#     instead of a single impulse: the impulse returned as needle-like
#     echoes that set the peak, leaving the resonance at -51 / -46 dBFS
#     RMS under peak normalisation (now -28 / about -30 dBFS). Both presets
#     are linear (drive 1, asymmetry 0), so the excitation LEVEL would not
#     have helped; the excitation TYPE does.
#   - Figure: frequency-resolved spatial map measured from the output
#     channels (left-right position of every band over time).
#
# Changelog v1.0:
#   - First release.
#
# Requires: Praat 6.3+ (colon form syntax). Nothing else.
# ============================================================

version$ = "1.1"

# ============================================================
# FORM (short; all network parameters in the dialogs that follow)
# ============================================================
form: "Self-Oscillating FDN Synthesizer v1.1"
    optionmenu: "Preset", 4
        option: "Damped Resonator"
        option: "Critical Network"
        option: "Sustained FDN"
        option: "Self-Oscillating"
        option: "Strong Nonlinear"
        option: "Metallic Organism"
        option: "Glass Swarm"
        option: "Slow Attractor"
        option: "Rusted Machine"
        option: "Digital Insects"
        option: "Frozen Resonance"
        option: "Fractured Bell"
        option: "Breathing Metal"
        option: "Unstable Choir"
        option: "Chaotic Edge"
        option: "Collapse and Recover"
        option: "Ignition"
        option: "Feedback Storm"
        option: "Microstructure"
        option: "Deep Network"
        option: "Custom"
    positive: "Duration (s)", "8"
    positive: "Sample rate (Hz)", "44100"
    integer: "Random seed", "1"
    optionmenu: "Output layout", 1
        option: "Stereo"
        option: "Quad (FL FR RL RR)"
        option: "8-channel ring"
    optionmenu: "Normalization", 1
        option: "Peak"
        option: "Resonance (RMS of the body)"
        option: "None"
    real: "Output peak (dBFS)", "-1.0"
    optionmenu: "Ending", 2
        option: "Hard stop"
        option: "Short fade (20 ms)"
        option: "Longer fade (10% of duration)"
    boolean: "Show parameters", 0
    boolean: "Draw visualisation", 1
    boolean: "Play result", 1
endform

dur = duration
sr = sample_rate
seed = random_seed
if dur > 120
    exitScript: "Duration is limited to 120 s."
endif
if sr < 8000 or sr > 192000
    exitScript: "Sample rate must be between 8000 and 192000 Hz."
endif

# ============================================================
# PRESETS — every preset sets every sound parameter
# ============================================================
# Defaults (also the Custom starting point)
baseDelayMs = 7
spreadPct = 230
irregularity = 0.5
instStart = 0.35
instEnd = 0.35
driveStart = 2.0
driveEnd = 2.0
dampStart = 0.3
dampEnd = 0.3
stereoSpread = 70
excType = 1
excAmount = 0.5
excDurMs = 5
nlType = 1
asymmetry = 0.15
matrixType = 1
spatialMode = 1
spatialMotion = 0
spatialRate = 0.05
driftDepth = 0
driftRate = 0.2

procedure applyPreset: .p
    # space: reference presets use the Orthogonal Field; the experimental
    # ones are assigned below (Distributed = space driven by the network
    # state alone; Orbiting = Distributed plus a slow swing of the circle)
    spatialMode = 1
    spatialMotion = 0
    spatialRate = 0.05
    if .p >= 6
        spatialMode = 2
    endif
    if .p = 8 or .p = 13 or .p = 14 or .p = 15
        spatialMode = 3
        spatialMotion = 70
        spatialRate = 0.04
    endif
    if .p = 13
        spatialRate = 0.08
    endif
    if .p = 15
        spatialMotion = 100
        spatialRate = 0.12
    endif
    # reference presets
    if .p = 1
        # Damped Resonator: clearly below unity, long but decaying
        baseDelayMs = 6
        spreadPct = 200
        irregularity = 0.4
        instStart = -0.55
        instEnd = -0.55
        driveStart = 1.0
        driveEnd = 1.0
        dampStart = 0.25
        dampEnd = 0.25
        stereoSpread = 60
        excType = 2
        excAmount = 0.6
        excDurMs = 15
        nlType = 1
        asymmetry = 0.0
        matrixType = 1
        driftDepth = 0
    elsif .p = 2
        # Critical Network: extremely close to unity
        baseDelayMs = 6
        spreadPct = 200
        irregularity = 0.4
        instStart = -0.05
        instEnd = -0.05
        driveStart = 1.0
        driveEnd = 1.0
        dampStart = 0.05
        dampEnd = 0.05
        stereoSpread = 60
        excType = 2
        excAmount = 0.6
        excDurMs = 15
        nlType = 1
        asymmetry = 0.0
        matrixType = 1
        driftDepth = 0
    elsif .p = 3
        # Sustained FDN: about unity, gentle saturation
        baseDelayMs = 6
        spreadPct = 200
        irregularity = 0.4
        instStart = 0.3
        instEnd = 0.3
        driveStart = 1.5
        driveEnd = 1.5
        dampStart = 0.08
        dampEnd = 0.08
        stereoSpread = 60
        excType = 2
        excAmount = 0.4
        excDurMs = 20
        nlType = 1
        asymmetry = 0.1
        matrixType = 1
        driftDepth = 0
    elsif .p = 4
        # Self-Oscillating: slightly supercritical, moderate bounding
        baseDelayMs = 7
        spreadPct = 230
        irregularity = 0.5
        instStart = 0.55
        instEnd = 0.55
        driveStart = 2.0
        driveEnd = 2.0
        dampStart = 0.3
        dampEnd = 0.3
        stereoSpread = 70
        excType = 2
        excAmount = 0.5
        excDurMs = 20
        nlType = 1
        asymmetry = 0.15
        matrixType = 1
        driftDepth = 0
    elsif .p = 5
        # Strong Nonlinear: higher radius, stronger interaction
        baseDelayMs = 7
        spreadPct = 230
        irregularity = 0.6
        instStart = 0.75
        instEnd = 0.75
        driveStart = 4.0
        driveEnd = 4.0
        dampStart = 0.35
        dampEnd = 0.35
        stereoSpread = 80
        excType = 2
        excAmount = 0.5
        excDurMs = 20
        nlType = 4
        asymmetry = 0.3
        matrixType = 1
        driftDepth = 0
    # experimental presets
    elsif .p = 6
        # Metallic Organism: short irregular delays, high feedback, bright
        baseDelayMs = 1.6
        spreadPct = 260
        irregularity = 0.9
        instStart = 0.6
        instEnd = 0.6
        driveStart = 2.5
        driveEnd = 2.5
        dampStart = 0.05
        dampEnd = 0.05
        stereoSpread = 75
        excType = 1
        excAmount = 0.5
        excDurMs = 2
        nlType = 1
        asymmetry = 0.2
        matrixType = 1
        driftDepth = 0
    elsif .p = 7
        # Glass Swarm: very short distributed delays, wide, light saturation
        baseDelayMs = 0.6
        spreadPct = 400
        irregularity = 0.7
        instStart = 0.4
        instEnd = 0.4
        driveStart = 1.2
        driveEnd = 1.2
        dampStart = 0.1
        dampEnd = 0.1
        stereoSpread = 100
        excType = 3
        excAmount = 0.4
        excDurMs = 300
        nlType = 2
        asymmetry = 0.1
        matrixType = 1
        driftDepth = 0
    elsif .p = 8
        # Slow Attractor: longer delays, just above critical, low drive, dark
        baseDelayMs = 30
        spreadPct = 180
        irregularity = 0.4
        instStart = 0.42
        instEnd = 0.42
        driveStart = 1.3
        driveEnd = 1.3
        dampStart = 0.45
        dampEnd = 0.45
        stereoSpread = 35
        excType = 2
        excAmount = 0.3
        excDurMs = 40
        nlType = 1
        asymmetry = 0.12
        matrixType = 1
        driftDepth = 0
    elsif .p = 9
        # Rusted Machine: asymmetric delays, dark, strong saturation
        baseDelayMs = 4
        spreadPct = 520
        irregularity = 1.0
        instStart = 0.7
        instEnd = 0.7
        driveStart = 5.0
        driveEnd = 5.0
        dampStart = 0.6
        dampEnd = 0.6
        stereoSpread = 70
        excType = 5
        excAmount = 0.6
        excDurMs = 4
        nlType = 4
        asymmetry = 0.45
        matrixType = 2
        driftDepth = 0
    elsif .p = 10
        # Digital Insects: extremely short structure, sparse, high radius
        baseDelayMs = 0.35
        spreadPct = 350
        irregularity = 0.9
        instStart = 0.8
        instEnd = 0.8
        driveStart = 3.0
        driveEnd = 3.0
        dampStart = 0.05
        dampEnd = 0.05
        stereoSpread = 90
        excType = 3
        excAmount = 0.3
        excDurMs = 600
        nlType = 3
        asymmetry = 0.25
        matrixType = 1
        driftDepth = 0
    elsif .p = 11
        # Frozen Resonance: near-critical, very low damping, minimal drive
        baseDelayMs = 9
        spreadPct = 160
        irregularity = 0.3
        instStart = 0.22
        instEnd = 0.22
        driveStart = 1.0
        driveEnd = 1.0
        dampStart = 0.02
        dampEnd = 0.02
        stereoSpread = 70
        excType = 2
        excAmount = 0.4
        excDurMs = 30
        nlType = 1
        asymmetry = 0.0
        matrixType = 1
        driftDepth = 0
    elsif .p = 12
        # Fractured Bell: medium delays, impulsive, irregular, moderate NL
        baseDelayMs = 3.5
        spreadPct = 300
        irregularity = 1.0
        instStart = -0.35
        instEnd = -0.35
        driveStart = 2.0
        driveEnd = 2.0
        dampStart = 0.12
        dampEnd = 0.12
        stereoSpread = 80
        excType = 5
        excAmount = 0.8
        excDurMs = 3
        nlType = 1
        asymmetry = 0.06
        matrixType = 1
        driftDepth = 0
    elsif .p = 13
        # Breathing Metal: slow radius modulation in a small safe range
        baseDelayMs = 2.5
        spreadPct = 240
        irregularity = 0.6
        instStart = 0.45
        instEnd = 0.45
        driveStart = 2.0
        driveEnd = 2.0
        dampStart = 0.1
        dampEnd = 0.1
        stereoSpread = 40
        excType = 1
        excAmount = 0.5
        excDurMs = 2
        nlType = 1
        asymmetry = 0.15
        matrixType = 1
        driftDepth = 5
        driftRate = 0.25
    elsif .p = 14
        # Unstable Choir: longer clustered delays, gentle saturation, wide
        baseDelayMs = 14
        spreadPct = 45
        irregularity = 0.25
        instStart = 0.5
        instEnd = 0.5
        driveStart = 1.4
        driveEnd = 1.4
        dampStart = 0.4
        dampEnd = 0.4
        stereoSpread = 50
        excType = 2
        excAmount = 0.3
        excDurMs = 60
        nlType = 1
        asymmetry = 0.1
        matrixType = 1
        driftDepth = 0
    elsif .p = 15
        # Chaotic Edge: near the quasi-periodic / strongly nonlinear border
        baseDelayMs = 5
        spreadPct = 260
        irregularity = 0.7
        instStart = 0.55
        instEnd = 0.55
        driveStart = 3.5
        driveEnd = 3.5
        dampStart = 0.2
        dampEnd = 0.2
        stereoSpread = 30
        excType = 4
        excAmount = 0.3
        excDurMs = 0
        nlType = 1
        asymmetry = 0.35
        matrixType = 1
        driftDepth = 0
    elsif .p = 16
        # Collapse and Recover: supercritical, slowly moving into the stable region
        baseDelayMs = 6
        spreadPct = 230
        irregularity = 0.5
        instStart = 0.7
        instEnd = -0.45
        driveStart = 3.0
        driveEnd = 1.5
        dampStart = 0.2
        dampEnd = 0.35
        stereoSpread = 75
        excType = 2
        excAmount = 0.5
        excDurMs = 20
        nlType = 1
        asymmetry = 0.2
        matrixType = 1
        driftDepth = 0
    elsif .p = 17
        # Ignition: below critical, slowly crossing into self-oscillation
        baseDelayMs = 6
        spreadPct = 230
        irregularity = 0.5
        instStart = -0.45
        instEnd = 0.7
        driveStart = 1.5
        driveEnd = 3.0
        dampStart = 0.35
        dampEnd = 0.2
        stereoSpread = 75
        excType = 2
        excAmount = 0.5
        excDurMs = 30
        nlType = 1
        asymmetry = 0.2
        matrixType = 1
        driftDepth = 0
    elsif .p = 18
        # Feedback Storm: high drive, strong irregularity, bounded
        baseDelayMs = 2
        spreadPct = 420
        irregularity = 1.0
        instStart = 1.0
        instEnd = 1.0
        driveStart = 8.0
        driveEnd = 8.0
        dampStart = 0.15
        dampEnd = 0.15
        stereoSpread = 90
        excType = 2
        excAmount = 0.6
        excDurMs = 30
        nlType = 4
        asymmetry = 0.5
        matrixType = 1
        driftDepth = 0
    elsif .p = 19
        # Microstructure: very short delays, dense high-frequency texture
        baseDelayMs = 0.25
        spreadPct = 220
        irregularity = 0.8
        instStart = 0.5
        instEnd = 0.5
        driveStart = 2.5
        driveEnd = 2.5
        dampStart = 0.02
        dampEnd = 0.02
        stereoSpread = 90
        excType = 2
        excAmount = 0.4
        excDurMs = 10
        nlType = 2
        asymmetry = 0.2
        matrixType = 1
        driftDepth = 0
    elsif .p = 20
        # Deep Network: long delays, low slowly interacting resonances
        baseDelayMs = 45
        spreadPct = 150
        irregularity = 0.35
        instStart = 0.55
        instEnd = 0.55
        driveStart = 1.5
        driveEnd = 1.5
        dampStart = 0.7
        dampEnd = 0.7
        stereoSpread = 80
        excType = 2
        excAmount = 0.4
        excDurMs = 50
        nlType = 1
        asymmetry = 0.12
        matrixType = 1
        driftDepth = 0
    endif
endproc

presetName$ = preset$
if preset < 21
    @applyPreset: preset
endif

# ============================================================
# DETAIL DIALOGS (pre-filled with the preset; Custom forces them open)
# ============================================================
if show_parameters or preset = 21
    beginPause: "FDN — network"
        positive: "Base delay (ms)", string$(baseDelayMs)
        real: "Delay spread (%)", string$(spreadPct)
        real: "Delay irregularity (0-1)", string$(irregularity)
        comment: "Instability: growth 60 u^3 dB/s (-1 = T60 1 s, 0 = critical, +1 = +60 dB/s)"
        real: "Instability start", string$(instStart)
        real: "Instability end", string$(instEnd)
        positive: "Drive start", string$(driveStart)
        positive: "Drive end", string$(driveEnd)
        real: "Damping start (0-1)", string$(dampStart)
        real: "Damping end (0-1)", string$(dampEnd)
        real: "Stereo spread (%)", string$(stereoSpread)
    endPause: "Continue", 1
    baseDelayMs = base_delay
    spreadPct = delay_spread
    irregularity = delay_irregularity
    instStart = instability_start
    instEnd = instability_end
    driveStart = drive_start
    driveEnd = drive_end
    dampStart = damping_start
    dampEnd = damping_end
    stereoSpread = stereo_spread
    beginPause: "FDN — excitation and advanced"
        optionMenu: "Excitation type", excType
            option: "Single impulse"
            option: "Short noise burst"
            option: "Sparse random impulses"
            option: "Initial random state"
            option: "Bipolar pulse"
        real: "Excitation amount", string$(excAmount)
        real: "Excitation duration (ms)", string$(excDurMs)
        optionMenu: "Nonlinearity", nlType
            option: "Soft saturation (tanh)"
            option: "Softsign"
            option: "Cubic soft clip"
            option: "Harder saturation"
        real: "Asymmetry (0-0.6)", string$(asymmetry)
        optionMenu: "Feedback matrix", matrixType
            option: "Hadamard 8x8 (default)"
            option: "Householder 8x8"
            option: "Decoupled (identity; reference)"
        optionMenu: "Spatial mode", spatialMode
            option: "Orthogonal Field"
            option: "Distributed Network (state-driven)"
            option: "Orbiting Network"
        real: "Spatial motion (%)", string$(spatialMotion)
        positive: "Spatial rate (Hz)", string$(spatialRate)
        real: "Drift depth (dB/s)", string$(driftDepth)
        positive: "Drift rate (Hz)", string$(driftRate)
    endPause: "Continue", 1
    excType = excitation_type
    excAmount = excitation_amount
    excDurMs = excitation_duration
    nlType = nonlinearity
    asymmetry = asymmetry
    matrixType = feedback_matrix
    spatialMode = spatial_mode
    spatialMotion = spatial_motion
    spatialRate = spatial_rate
    driftDepth = drift_depth
    driftRate = drift_rate
endif

# ---- validation and safe ranges ----
irregularity = max(0, min(1, irregularity))
spreadPct = max(0, min(1000, spreadPct))
instStart = max(-1, min(1, instStart))
instEnd = max(-1, min(1, instEnd))
driveStart = max(0.1, min(20, driveStart))
driveEnd = max(0.1, min(20, driveEnd))
dampStart = max(0, min(1, dampStart))
dampEnd = max(0, min(1, dampEnd))
stereoSpread = max(0, min(100, stereoSpread))
asymmetry = max(0, min(0.6, asymmetry))
excAmount = max(0, min(2, excAmount))
excDurMs = max(0, excDurMs)
driftDepth = max(0, min(30, driftDepth))
spatialMotion = max(0, min(100, spatialMotion))
spatialRate = max(0.005, min(1, spatialRate))

# ============================================================
# DELAY LENGTHS
# ============================================================
# Geometric spread from the base delay to base * (1 + spread), with fixed
# irregular offsets (golden-ratio sequence) scaled by Irregularity, then
# snapped to distinct primes (no common factors, no duplicates).
@delayLengths
procedure delayLengths
    # plain global indices (zk, zp): 'x' interpolation cannot see dotted locals
    .base = baseDelayMs / 1000 * sr
    .top = .base * (1 + spreadPct / 100)
    for zk to 8
        .r = (zk - 1) / 7
        .d = .base * (.top / .base) ^ .r
        .off = ((zk * 0.6180339887) mod 1) * 2 - 1
        .d = .d * exp(0.18 * irregularity * .off)
        rawDelay_'zk' = max(5, .d)
    endfor
    # ascending, distinct primes (the irregular offsets can reorder neighbours,
    # so each delay is at least one above the previous one before snapping)
    for zk to 8
        .target = round(rawDelay_'zk')
        if zk > 1
            zp = zk - 1
            .target = max(.target, delay_'zp' + 1)
        endif
        @nextPrime: .target
        delay_'zk' = nextPrime.p
    endfor
    dmin = delay_1
    dmax = delay_8
endproc

procedure nextPrime: .n
    .p = max(2, .n)
    .found = 0
    while .found = 0
        .isP = 1
        .q = 2
        while .q * .q <= .p and .isP
            if .p mod .q = 0
                .isP = 0
            endif
            .q = .q + 1
        endwhile
        if .isP
            .found = 1
        else
            .p = .p + 1
        endif
    endwhile
endproc

# ============================================================
# PARAMETER CURVES (shared by synthesis and figure)
# ============================================================
procedure rate: .u
    # growth rate in dB per second, cubic for fine resolution around 0
    .rho = 60 * .u ^ 3
endproc

procedure paramsAt: .tn
    # smooth (raised-cosine) interpolation from start to end values
    .s = 0.5 - 0.5 * cos(pi * max(0, min(1, .tn)))
    .inst = instStart + (instEnd - instStart) * .s
    @rate: .inst
    .rho = rate.rho + driftDepth * sin(2 * pi * driftRate * .tn * dur)
    # per-pass radii of the shortest and longest line (for reports)
    .gMin = 10 ^ (.rho * dmin / (20 * sr))
    .gMax = 10 ^ (.rho * dmax / (20 * sr))
    .drive = driveStart + (driveEnd - driveStart) * .s
    .damp = dampStart + (dampEnd - dampStart) * .s
    # damping 0..1 -> one-pole cutoff 20 kHz .. 150 Hz (log), capped at Nyquist
    .fc = min(0.45 * sr, 20000 * (150 / 20000) ^ .damp)
    .aLP = if .damp <= 0 then 0 else exp(-2 * pi * .fc / sr) fi
endproc

procedure regimeName: .rho
    if .rho < -3
        .s$ = "dissipative"
    elsif .rho < -0.3
        .s$ = "near-critical"
    elsif .rho <= 0.3
        .s$ = "sustained (about unity)"
    elsif .rho <= 15
        .s$ = "self-oscillating"
    else
        .s$ = "strongly nonlinear"
    endif
endproc

# ============================================================
# NONLINEARITY (bounded; unit small-signal gain)
# ============================================================
# S(u) and its slope S'(u); used through f(x) = [S(D(x+b)) - S(Db)] / (D S'(Db))
procedure satValue: .u
    if nlType = 1
        .v = tanh(.u)
    elsif nlType = 2
        .v = .u / (1 + abs(.u))
    elsif nlType = 3
        .c = max(-1, min(1, .u))
        .v = .c - .c ^ 3 / 3
    else
        .v = .u / (1 + .u ^ 4) ^ 0.25
    endif
endproc

procedure nlFormula
    # formula text for S(arg) with arg = drv * (self + asym)
    .arg$ = "(drv * (self + asym))"
    if nlType = 1
        .s$ = "tanh (" + .arg$ + ")"
    elsif nlType = 2
        .s$ = "(" + .arg$ + " / (1 + abs (" + .arg$ + ")))"
    elsif nlType = 3
        .c$ = "(min (max (" + .arg$ + ", -1), 1))"
        .s$ = "(" + .c$ + " - " + .c$ + " ^ 3 / 3)"
    else
        .s$ = "(" + .arg$ + " / (1 + " + .arg$ + " ^ 4) ^ 0.25)"
    endif
    # bounded, safety-clamped (the clamp should never be reached in use)
    nl$ = "min (max ((" + .s$ + " - sB) / (drv * kB), -8), 8) + object [exc, row, col]"
endproc

procedure nlConstants: .drv
    # Effective bias: D*b is capped at 0.7, where every saturator still has a
    # healthy slope (tanh 0.63, softsign 0.35, cubic 0.51, harder 0.88).
    # Beyond that S'(Db) collapses and the unit-gain normalisation would
    # inflate the output towards the safety clamp.
    asym = min(asymmetry, 0.7 / .drv)
    if asym < asymmetry - 1e-12
        asymCapped = 1
    endif
    @satValue: .drv * asym
    sB = satValue.v
    @satValue: .drv * asym + 1e-4
    .p = satValue.v
    @satValue: .drv * asym - 1e-4
    .m = satValue.v
    kB = max(0.05, (.p - .m) / 2e-4)
endproc

# ============================================================
# BUFFERS (8-channel Sounds: one channel per delay line)
# ============================================================
nOut = round(dur * sr)
off = dmax + 1
ntot = nOut + off
dx = 1 / sr
hist = Create Sound from formula: "fdn_lines", 8, 0, ntot / sr, sr, "0"
damp = Create Sound from formula: "fdn_damped", 8, 0, ntot / sr, sr, "0"
dcb = Create Sound from formula: "fdn_dcblocked", 8, 0, ntot / sr, sr, "0"
exc = Create Sound from formula: "fdn_excitation", 8, 0, ntot / sr, sr, "0"
dlay = Create simple Matrix: "fdn_delays", 8, 1, "0"
for k to 8
    Set value: k, 1, delay_'k'
endfor
mat = Create simple Matrix: "fdn_matrix", 8, 8, "0"
if matrixType = 1
    # normalised Sylvester-Hadamard: (-1)^popcount((r-1) and (c-1)) / sqrt(8)
    Formula: "(if ((((row-1) mod 2) * ((col-1) mod 2) + (((row-1) div 2) mod 2) * (((col-1) div 2) mod 2) + (((row-1) div 4) mod 2) * (((col-1) div 4) mod 2)) mod 2) = 0 then 1 else -1 fi) / sqrt (8)"
    matName$ = "Hadamard 8x8 / sqrt(8)"
elsif matrixType = 2
    Formula: "(if row = col then 1 else 0 fi) - 2 / 8"
    matName$ = "Householder 8x8"
else
    Formula: "if row = col then 1 else 0 fi"
    matName$ = "decoupled (identity)"
endif

# ============================================================
# EXCITATION (only initiates the network)
# ============================================================
random_initializeWithSeedUnsafelyButPredictably: seed
excN = max(1, round(excDurMs / 1000 * sr))
c0e = off + 1
t0e = (c0e - 1) * dx + dx / 2 - dx / 4
t1e = (c0e - 1 + excN - 1) * dx + dx / 2 + dx / 4
selectObject: exc
if excType = 1
    # one impulse into every line, alternating signs
    Formula (part): t0e, t0e + dx / 2, 1, 8, "excAmount * (if row mod 2 = 0 then 1 else -1 fi)"
    excName$ = "single impulse"
elsif excType = 2
    Formula (part): t0e, t1e, 1, 8, "excAmount * randomGauss (0, 0.5) * sin (pi * (col - c0e + 0.5) / excN)"
    excName$ = "noise burst " + fixed$(excDurMs, 0) + " ms"
elsif excType = 3
    # sparse impulses: about 40 per second per network, random line and sign
    Formula (part): t0e, t1e, 1, 8, "if randomUniform (0, 1) < 40 / (8 * sr) then excAmount * randomUniform (-1, 1) else 0 fi"
    excName$ = "sparse impulses over " + fixed$(excDurMs, 0) + " ms"
elsif excType = 4
    # random initial delay-line contents; no input at all afterwards
    selectObject: hist
    Formula (part): 0, (off - 1) * dx + dx / 4, 1, 8, "excAmount * randomGauss (0, 0.3)"
    excName$ = "initial random state"
else
    # bipolar pulse: 1 ms positive, 1 ms negative
    nP = max(1, round(0.001 * sr))
    Formula (part): t0e, (c0e - 1 + 2 * nP - 1) * dx + dx / 2 + dx / 4, 1, 8, "excAmount * (if col - c0e < nP then 1 else -1 fi) * (if row mod 2 = 0 then 1 else -1 fi)"
    excName$ = "bipolar pulse"
endif
random_initializeSafelyAndUnpredictably ()

# ============================================================
# FDN LOOP — exact blocks of up to d_min samples
# ============================================================
@nlFormula
mix$ = ""
if matrixType = 3
    mix$ = "object [dcb, row, col]"
else
    for k to 8
        if k > 1
            mix$ = mix$ + " + "
        endif
        mix$ = mix$ + "object [mat, row, " + string$(k) + "] * object [dcb, " + string$(k) + ", col]"
    endfor
endif
dampF$ = "aLP * self [row, col - 1] + (1 - aLP) * exp (rhoK * object [dlay, row, 1]) * object [hist, row, col - object [dlay, row, 1]]"
rDC = exp(-2 * pi * 20 / sr)
dcbF$ = "object [damp, row, col] - object [damp, row, col - 1] + rDC * self [row, col - 1]"
mixF$ = mix$

nBlocks = 0
asymCapped = 0
stopwatch
c0 = off + 1
while c0 <= ntot
    c1 = min(c0 + dmin - 1, ntot)
    t0 = (c0 - 1) * dx + dx / 2 - dx / 4
    t1 = (c1 - 1) * dx + dx / 2 + dx / 4
    @paramsAt: ((c0 + c1) / 2 - off) / nOut
    rhoK = paramsAt.rho * ln (10) / (20 * sr)
    aLP = paramsAt.aLP
    drv = paramsAt.drive
    @nlConstants: drv
    selectObject: damp
    Formula (part): t0, t1, 1, 8, dampF$
    selectObject: dcb
    Formula (part): t0, t1, 1, 8, dcbF$
    selectObject: hist
    Formula (part): t0, t1, 1, 8, mixF$
    Formula (part): t0, t1, 1, 8, nl$
    nBlocks = nBlocks + 1
    c0 = c1 + 1
endwhile
synthTime = stopwatch

# ============================================================
# NUMERICAL CHECK
# ============================================================
selectObject: hist
stateMax = Get absolute extremum: 0, 0, "None"
if stateMax = undefined
    exitScript: "Numerical failure: the network produced undefined values (please report the parameters)."
endif
clampHit = stateMax >= 7.999

# ============================================================
# SPATIAL OUTPUT (Stereo / Quad / 8-channel ring)
# ============================================================
# Speaker azimuths in degrees (0 = front, + = right):
#   Stereo  L -30, R +30
#   Quad    1 FL -45, 2 FR +45, 3 RL -135, 4 RR +135
#   8-ring  speaker s at -22.5 + (s-1)*45, clockwise from front-left
# Spatial modes:
#   Orthogonal Field   each channel is a different zero-mean sign
#                      projection of the eight states (Hadamard rows); in
#                      8-channel, line k feeds speaker k directly
#   Distributed        line k sits at a FIXED position, in the order
#                      1-5-3-7-2-6-4-8 so delay length does not map
#                      monotonically onto position; nothing is panned:
#                      the image moves only because energy moves between
#                      the lines (the network state is the trajectory)
#   Orbiting           the eight nodes on an ARC whose width is the spread
#                      (100% = full circle) swinging back and forth by up to
#                      +-180 deg * motion at the spatial rate (projected onto
#                      L-R in stereo). A full uniform circle would not be
#                      heard to move, so narrower arcs orbit audibly.
# Orthogonal / Distributed: spread scales the image toward the centre
# (0 = mono). Orbiting: spread is the arc width.
nCh = 2
if output_layout = 2
    nCh = 4
elsif output_layout = 3
    nCh = 8
endif
for zs to 8
    spkAz_'zs' = 0
endfor
if nCh = 2
    spkAz_1 = -30
    spkAz_2 = 30
elsif nCh = 4
    spkAz_1 = -45
    spkAz_2 = 45
    spkAz_3 = -135
    spkAz_4 = 135
else
    for zs to 8
        spkAz_'zs' = -22.5 + (zs - 1) * 45
    endfor
endif
# node order on the line / circle
permIdx_1 = 0
permIdx_5 = 1
permIdx_3 = 2
permIdx_7 = 3
permIdx_2 = 4
permIdx_6 = 5
permIdx_4 = 6
permIdx_8 = 7
sp = stereoSpread / 100
mot = spatialMotion / 100
orbRate = spatialRate
dlt = 2 * pi / max(nCh, 3)
for zk to 8
    nodeAz_'zk' = (-22.5 + permIdx_'zk' * 45) * pi / 180
endfor

procedure hadSign: .r, .k
    # Sylvester-Hadamard sign of row .r, column .k (both 1-based)
    .a = .r - 1
    .b = .k - 1
    .pc = (.a mod 2) * (.b mod 2) + ((.a div 2) mod 2) * ((.b div 2) mod 2) + ((.a div 4) mod 2) * ((.b div 4) mod 2)
    .s = if .pc mod 2 = 0 then 1 else -1 fi
endproc

# gain text for node zk -> channel zc (numeric when static, formula when orbiting)
procedure gainText
    # uses the GLOBAL loop indices zc (channel) and zk (node): 'x'
    # interpolation cannot see procedure-local dotted names
    # orbit: the eight nodes sit on an ARC of width spread * 360 deg (in
    # the 1-5-3-7-2-6-4-8 order) and the whole arc swings by up to
    # +-180 deg * motion. A full uniform circle would not be heard to move:
    # every FDN resonance lives in all eight lines, so a turned uniform
    # constellation looks the same (measured: slow movement 0.049 vs 0.038)
    .arcOff = (permIdx_'zk' - 3.5) / 8 * 2 * pi * sp
    .phi$ = "(" + fixed$(.arcOff, 8) + " + mot * pi * sin (2 * pi * orbRate * x))"
    if spatialMode = 1
        if nCh = 8
            .w = (1 - sp) / 8 + sp * (if zc = zk then 1 else 0 fi)
        else
            @hadSign: zc + 1, zk
            .w = ((1 - sp) + sp * hadSign.s) / 8
        endif
        .t$ = fixed$(.w, 8)
    elsif nCh = 2
        if spatialMode = 2
            .pan = sp * (-1 + 2 * permIdx_'zk' / 7)
            .ang = (.pan + 1) * pi / 4
            .w = if zc = 1 then cos(.ang) else sin(.ang) fi
            .t$ = fixed$(.w, 8)
        else
            .ang$ = "((sin " + .phi$ + " + 1) * pi / 4)"
            .t$ = if zc = 1 then "cos " + .ang$ else "sin " + .ang$ fi
        endif
    else
        .phiS = spkAz_'zc' * pi / 180
        if spatialMode = 2
            .d = abs(((nodeAz_'zk' - .phiS + pi) mod (2 * pi)) - pi)
            .g = if .d < dlt then cos(pi / 2 * .d / dlt) else 0 fi
            .w = (1 - sp) / sqrt(nCh) + sp * .g
            .t$ = fixed$(.w, 8)
        else
            .d$ = "abs (((" + .phi$ + " - " + fixed$(.phiS, 8) + " + pi) mod (2 * pi)) - pi)"
            .t$ = "(if " + .d$ + " < dlt then cos (pi / 2 * " + .d$ + " / dlt) else 0 fi)"
        endif
    endif
endproc

outF$ = ""
for zc to nCh
    chan$ = ""
    for zk to 8
        if zk > 1
            chan$ = chan$ + " + "
        endif
        @gainText
        chan$ = chan$ + gainText.t$ + " * object [hist, " + string$(zk) + ", col + off]"
    endfor
    if zc = 1
        outF$ = "if row = 1 then " + chan$
    else
        outF$ = outF$ + " else if row = " + string$(zc) + " then " + chan$
    endif
endfor
outF$ = outF$ + " else 0"
for zc to nCh
    outF$ = outF$ + " fi"
endfor
resultName$ = "FDN_" + replace_regex$(presetName$, "[^A-Za-z0-9]", "", 0)
out = Create Sound from formula: resultName$, nCh, 0, nOut / sr, sr, outF$
Subtract mean

# ---- fades BEFORE normalisation ----
fadeIn = 0
if excType = 4
    fadeIn = 0.005
endif
if normalization = 2
    # Resonance mode: an 8 ms fade-in keeps the excitation transient from
    # setting the level (documented; it softens the very first click)
    fadeIn = max(fadeIn, 0.008)
endif
if fadeIn > 0
    Formula: "self * min (1, x / fadeIn)"
endif
if ending = 2
    fadeLen = 0.02
elsif ending = 3
    fadeLen = 0.1 * dur
else
    fadeLen = 0
endif
if fadeLen > 0
    Formula: "self * min (1, (xmax - x) / fadeLen)"
endif

# ---- normalisation (after the fades); silence is never scaled ----
rawPeak = Get absolute extremum: 0, 0, "None"
silent = rawPeak < 1e-9
ceiling = min(10 ^ (output_peak / 20), 0.999)
normNote$ = "none"
if not silent
    if normalization = 1
        Scale peak: ceiling
        normNote$ = "peak to " + fixed$(output_peak, 1) + " dBFS"
    elsif normalization = 2
        bodyEnd = min(dur, 1.0)
        bodyStart = min(0.02, bodyEnd / 2)
        bodyRms = Get root-mean-square: bodyStart, bodyEnd
        if bodyRms < 1e-12
            Scale peak: ceiling
            normNote$ = "resonance body silent; peak used instead"
        else
            gRms = 10 ^ (-18 / 20) / bodyRms
            gCeil = ceiling / rawPeak
            gNorm = min(gRms, gCeil)
            Formula: "self * gNorm"
            if gRms <= gCeil
                normNote$ = "body RMS (" + fixed$(bodyStart, 2) + "-" + fixed$(bodyEnd, 2) + " s) to -18 dBFS"
            else
                normNote$ = "body RMS target -18 dBFS limited by the " + fixed$(output_peak, 1) + " dBFS peak ceiling (" + fixed$(20 * log10(gCeil / gRms), 1) + " dB short)"
            endif
        endif
    else
        normNote$ = "none (raw level, peak " + fixed$(rawPeak, 3) + ")"
        if rawPeak > 1
            normNote$ = normNote$ + " - EXCEEDS FULL SCALE"
        endif
    endif
endif
layoutName$ = "stereo"
if nCh = 4
    layoutName$ = "quad (FL FR RL RR)"
elsif nCh = 8
    layoutName$ = "8-channel ring"
endif
spaceName$ = "Orthogonal Field"
if spatialMode = 2
    spaceName$ = "Distributed Network (state-driven)"
elsif spatialMode = 3
    spaceName$ = "Orbiting Network (swing +-" + fixed$(180 * mot, 0) + " deg at " + fixed$(orbRate, 3) + " Hz)"
endif

# ============================================================
# MEASUREMENTS FOR THE REPORT
# ============================================================
@paramsAt: 0
rhoStart = paramsAt.rho
gS1 = paramsAt.gMin
gS2 = paramsAt.gMax
@paramsAt: 1
rhoEnd = paramsAt.rho
gE1 = paramsAt.gMin
gE2 = paramsAt.gMax
@regimeName: rhoStart
regStart$ = regimeName.s$
@regimeName: rhoEnd
regEnd$ = regimeName.s$
selectObject: out
q1 = Get root-mean-square: 0, 0.25 * dur
q4 = Get root-mean-square: 0.75 * dur, dur
decayDb = if q1 > 0 and q4 > 0 then 20 * log10(q4 / q1) else undefined fi
excEnd = (excN / sr)

writeInfoLine: "=== Self-Oscillating FDN Synthesizer v", version$, " ==="
appendInfoLine: "Preset:      ", presetName$, "   seed ", seed
appendInfoLine: "Network:     8 lines, ", matName$, ", delays (samples):"
dl$ = ""
for k to 8
    dl$ = dl$ + string$(delay_'k') + " "
endfor
appendInfoLine: "             ", dl$, " (", fixed$(dmin / sr * 1000, 2), " - ", fixed$(dmax / sr * 1000, 2), " ms, all prime)"
appendInfoLine: "Growth rate: ", fixed$(rhoStart, 2), " dB/s (", regStart$, ") -> ", fixed$(rhoEnd, 2), " dB/s (", regEnd$, ")"
appendInfoLine: "             per-pass radius ", fixed$(gS1, 5), "-", fixed$(gS2, 5), " -> ", fixed$(gE1, 5), "-", fixed$(gE2, 5), " (shortest-longest line)"
if driftDepth > 0
    appendInfoLine: "Drift:       rate +/- ", fixed$(driftDepth, 2), " dB/s at ", fixed$(driftRate, 2), " Hz"
endif
appendInfoLine: "Drive:       ", fixed$(driveStart, 2), " -> ", fixed$(driveEnd, 2), "   asymmetry ", fixed$(asymmetry, 2)
if asymmetry = 0
    appendInfoLine: "             (asymmetry 0: the network is nearly scale-invariant, so drive mostly affects the transient)"
endif
if asymCapped
    appendInfoLine: "             (effective asymmetry capped at 0.7 / drive where drive x asymmetry exceeded 0.7)"
endif
@paramsAt: 0
fcS = paramsAt.fc
@paramsAt: 1
appendInfoLine: "Damping:     ", fixed$(dampStart, 2), " -> ", fixed$(dampEnd, 2), "   (one-pole cutoff ", fixed$(fcS, 0), " -> ", fixed$(paramsAt.fc, 0), " Hz)"
nlName$ = "tanh"
if nlType = 2
    nlName$ = "softsign"
elsif nlType = 3
    nlName$ = "cubic soft clip"
elsif nlType = 4
    nlName$ = "harder saturation"
endif
appendInfoLine: "Nonlinear:   ", nlName$
appendInfoLine: "Excitation:  ", excName$, ", amount ", fixed$(excAmount, 2), " (ends at ", fixed$(excEnd, 3), " s; everything later is feedback)"
appendInfoLine: "Computed in ", nBlocks, " exact blocks of up to ", dmin, " samples, ", fixed$(synthTime, 1), " s"
appendInfoLine: "Level:       last quarter vs first quarter ", fixed$(decayDb, 1), " dB"
clampTxt$ = "  (safety clamp not reached)"
if clampHit
    clampTxt$ = "  (SAFETY CLAMP REACHED)"
endif
appendInfoLine: "             max state ", fixed$(stateMax, 3), clampTxt$
if silent
    appendInfoLine: "WARNING: the network produced (near) silence — raise Excitation amount or Instability."
endif
appendInfoLine: "Space:       ", spaceName$, ", spread ", fixed$(stereoSpread, 0), "%, ", layoutName$
appendInfoLine: "Normalised:  ", normNote$
appendInfoLine: "Output:      ", resultName$, "  (", nCh, " channels, ", sr, " Hz, ", fixed$(dur, 2), " s)"

if draw_visualisation
    @drawFigure
endif
removeObject: damp, dcb, exc, dlay, mat, hist
selectObject: out
if play_result
    Play
endif

# ============================================================
# FIGURE
# ============================================================
procedure niceStep: .span, .n
    .raw = .span / .n
    if .raw <= 0
        .raw = 1
    endif
    .p = 10 ^ floor(log10(.raw))
    .m = .raw / .p
    if .m < 1.5
        .step = .p
    elsif .m < 3.5
        .step = 2 * .p
    elsif .m < 7.5
        .step = 5 * .p
    else
        .step = 10 * .p
    endif
endproc

procedure railLabel: .y0, .y1, .name$
    Font size: 7
    Select inner viewport: 0.6, 7.7, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: -0.068, "centre", 0.5, "bottom", "Helvetica", 7, "90", .name$
endproc

procedure lineColour: .i
    .rgb$ = "{0.20, 0.40, 0.80}"
    if .i = 2
        .rgb$ = "{0.85, 0.35, 0.15}"
    elsif .i = 3
        .rgb$ = "{0.15, 0.60, 0.35}"
    elsif .i = 4
        .rgb$ = "{0.60, 0.25, 0.70}"
    elsif .i = 5
        .rgb$ = "{0.85, 0.65, 0.10}"
    elsif .i = 6
        .rgb$ = "{0.10, 0.65, 0.75}"
    elsif .i = 7
        .rgb$ = "{0.75, 0.20, 0.45}"
    elsif .i = 8
        .rgb$ = "{0.40, 0.40, 0.40}"
    endif
endproc

procedure phasePlot: .x0, .x1, .y0, .y1, .ta, .tb, .title$
    # line 1 against line 2 (state values, as written into the lines)
    selectObject: hist
    .ca = round(.ta * sr) + off + 1
    .cb = min(ntot, round(.tb * sr) + off)
    .n = .cb - .ca + 1
    .step = max(1, floor(.n / 3000))
    .lim = 1e-9
    .c = .ca
    while .c <= .cb
        .v1 = Get value at sample number: 1, .c
        .v2 = Get value at sample number: 2, .c
        .lim = max(.lim, abs(.v1), abs(.v2))
        .c = .c + .step
    endwhile
    .lim = .lim * 1.1
    Select inner viewport: .x0, .x1, .y0, .y1
    Axes: -.lim, .lim, -.lim, .lim
    Paint rectangle: "{0.98, 0.98, 0.99}", -.lim, .lim, -.lim, .lim
    Colour: "{0.85, 0.85, 0.88}"
    Draw line: -.lim, 0, .lim, 0
    Draw line: 0, -.lim, 0, .lim
    Line width: 1
    .xa = Get value at sample number: 1, .ca
    .ya = Get value at sample number: 2, .ca
    .c = .ca + .step
    .i = 0
    .nSeg = floor(.n / .step)
    while .c <= .cb
        .xb = Get value at sample number: 1, .c
        .yb = Get value at sample number: 2, .c
        .u = .i / max(.nSeg, 1)
        Colour: "{" + fixed$(0.20 + 0.70 * .u, 3) + ", 0.40, " + fixed$(0.80 - 0.70 * .u, 3) + "}"
        Draw line: .xa, .ya, .xb, .yb
        .xa = .xb
        .ya = .yb
        .c = .c + .step
        .i = .i + 1
    endwhile
    Select inner viewport: .x0, .x1, .y0, .y1
    Axes: -.lim, .lim, -.lim, .lim
    Colour: "Black"
    Text top: "no", .title$
    Select inner viewport: .x0, .x1, .y0, .y1
    Axes: -.lim, .lim, -.lim, .lim
    Draw inner box
    # axis names placed explicitly (Text left after Draw inner box drifts)
    Font size: 7
    Select inner viewport: .x0, .x1, .y0, .y1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text special: 0.5, "centre", -0.035, "top", "Helvetica", 7, "0", "line 1 state"
    Text special: -0.035, "centre", 0.5, "bottom", "Helvetica", 7, "90", "line 2 state"
endproc

procedure drawSpace
    # Frequency-resolved spatial map, measured from the output channels:
    # for every time window and log-frequency band, the left-right position
    # of that band = sum(E_c sin az_c) / sum(E_c) over the channels
    # (stereo: (R-L)/(R+L)). Colour: blue = left, red = right; pale =
    # quiet. A single energy centroid cannot show this: with eight lines of
    # similar energy it stays near the centre even while the image moves.
    .nW = 150
    .nB = 36
    .fLo = 60
    .fHi = min(10000, sr / 2 * 0.95)
    for zc to nCh
        selectObject: out
        .ch = Extract one channel: zc
        spcMap_'zc' = To Spectrogram: 0.03, .fHi * 1.05, max(0.002, dur / 300), 20, "Gaussian"
        removeObject: .ch
    endfor
    .eMax = 1e-30
    for zw to .nW
        .t = (zw - 0.5) / .nW * dur
        for zb to .nB
            .f = .fLo * (.fHi / .fLo) ^ ((zb - 0.5) / .nB)
            .sum = 0
            .lr = 0
            for zc to nCh
                selectObject: spcMap_'zc'
                .pw = Get power at: .t, .f
                if .pw = undefined
                    .pw = 0
                endif
                .sum = .sum + .pw
                if nCh = 2
                    .lr = .lr + .pw * (if zc = 2 then 1 else -1 fi)
                else
                    .lr = .lr + .pw * sin(spkAz_'zc' * pi / 180)
                endif
            endfor
            mapE_'zw'_'zb' = .sum
            mapLR_'zw'_'zb' = if .sum > 0 then .lr / .sum else 0 fi
            .eMax = max(.eMax, .sum)
        endfor
    endfor
    for zc to nCh
        removeObject: spcMap_'zc'
    endfor
    .y0 = log10(.fLo)
    .y1 = log10(.fHi)
    Select inner viewport: 0.6, 7.7, e0, e1
    Axes: 0, dur, .y0, .y1
    for zw to .nW
        .ta = (zw - 1) / .nW * dur
        .tb = zw / .nW * dur
        for zb to .nB
            .lev = max(0, min(1, (10 * log10(max(mapE_'zw'_'zb', 1e-30) / .eMax) + 50) / 50))
            .v = mapLR_'zw'_'zb'
            .a = min(1, abs(.v) * 1.4)
            if .v < 0
                .r = 0.55 + (0.20 - 0.55) * .a
                .g = 0.55 + (0.40 - 0.55) * .a
                .b = 0.55 + (0.80 - 0.55) * .a
            else
                .r = 0.55 + (0.85 - 0.55) * .a
                .g = 0.55 + (0.25 - 0.55) * .a
                .b = 0.55 + (0.15 - 0.55) * .a
            endif
            .r = 1 - .lev * (1 - .r)
            .g = 1 - .lev * (1 - .g)
            .b = 1 - .lev * (1 - .b)
            .fa = .y0 + (zb - 1) / .nB * (.y1 - .y0)
            .fb = .y0 + zb / .nB * (.y1 - .y0)
            Paint rectangle: "{" + fixed$(.r, 3) + ", " + fixed$(.g, 3) + ", " + fixed$(.b, 3) + "}", .ta, .tb, .fa, .fb
        endfor
    endfor
    Font size: 7
    Select inner viewport: 0.6, 7.7, e0, e1
    Axes: 0, dur, .y0, .y1
    Colour: "Black"
    .cap$ = "##Spatial map## (measured from the output) — position of each frequency band: blue left, red right, grey centre; pale = quiet"
    if spatialMode = 2
        .cap$ = "##Spatial map## — fixed line positions; any movement comes from energy moving between lines (blue L, red R)"
    elsif spatialMode = 3
        .cap$ = "##Spatial map## — fixed positions plus the slow swing of the circle (blue L, red R; pale = quiet)"
    endif
    Text top: "no", .cap$
    Select inner viewport: 0.6, 7.7, e0, e1
    Axes: 0, dur, .y0, .y1
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    for zf to 4
        .fm = {100, 300, 1000, 3000} [zf]
        if .fm > .fLo and .fm < .fHi
            One mark left: log10(.fm), "no", "yes", "no", string$(.fm)
        endif
    endfor
    @railLabel: e0, e1, "Space (Hz)"
endproc

procedure drawFigure
    Erase all
    Line width: 1
    Solid line
    t0f = 0.10
    t1f = 0.60
    a0 = 0.90
    a1 = 2.40
    b0 = 2.70
    b1 = 3.85
    e0 = 4.15
    e1 = 4.95
    c0f = 5.25
    c1f = 6.10
    d0 = 6.65
    d1 = 8.80
    s0 = 9.35
    s1 = 10.45
    canvasH = 10.55

    Font size: 13
    Select inner viewport: 0.6, 7.7, t0f, t1f
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Text: 0.5, "centre", 0.72, "half", "##Self-Oscillating FDN — " + presetName$ + "##"
    Font size: 7
    Select inner viewport: 0.6, 7.7, t0f, t1f
    Axes: 0, 1, 0, 1
    Colour: "{0.35, 0.35, 0.42}"
    Text: 0.5, "centre", 0.18, "half", "8 lines, " + matName$ + "   |   growth " + fixed$(rhoStart, 1) + " → " + fixed$(rhoEnd, 1) + " dB/s   |   seed " + string$(seed)

    # A: spectrogram of the output (mono sum)
    selectObject: out
    .mono = Convert to mono
    .fmax = min(10000, sr / 2)
    .spec = To Spectrogram: 0.03, .fmax, max(0.002, dur / 1000), 20, "Gaussian"
    Select inner viewport: 0.6, 7.7, a0, a1
    Paint: 0, 0, 0, .fmax, 100, "yes", 50, 6, 0, "no"
    removeObject: .spec, .mono
    Font size: 7
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur, 0, .fmax
    Colour: "{0.85, 0.20, 0.20}"
    Dotted line
    Draw line: excEnd, 0, excEnd, .fmax
    Solid line
    Colour: "Black"
    Text top: "no", "##Output spectrogram## — red dotted: end of excitation; everything after it is feedback"
    Select inner viewport: 0.6, 7.7, a0, a1
    Axes: 0, dur, 0, .fmax
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    @niceStep: .fmax, 4
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    @railLabel: a0, a1, "Freq (Hz)"

    # B: network energy — RMS of each delay line (dB) over time
    .nW = 160
    .lo = 0
    .hi = -300
    for zk to 8
        selectObject: hist
        .ch = Extract one channel: zk
        for zw to .nW
            .ta = ((zw - 1) / .nW * dur) + off / sr
            .tb = (zw / .nW * dur) + off / sr
            .r = Get root-mean-square: .ta, .tb
            .db = 20 * log10(max(.r, 1e-12))
            en_'zk'_'zw' = .db
            .hi = max(.hi, .db)
        endfor
        removeObject: .ch
    endfor
    .lo = .hi - 80
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur, .lo, .hi + 3
    Paint rectangle: "{0.98, 0.98, 0.99}", 0, dur, .lo, .hi + 3
    Line width: 1.2
    for zk to 8
        @lineColour: zk
        Colour: lineColour.rgb$
        for zw from 2 to .nW
            zp = zw - 1
            Draw line: (zp - 0.5) / .nW * dur, max(.lo, en_'zk'_'zp'), (zw - 0.5) / .nW * dur, max(.lo, en_'zk'_'zw')
        endfor
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur, .lo, .hi + 3
    Colour: "Black"
    Text top: "no", "##Network energy## — RMS of each of the eight delay lines (dB, 80 dB range)"
    Select inner viewport: 0.6, 7.7, b0, b1
    Axes: 0, dur, .lo, .hi + 3
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "no", "yes", "no"
    Marks left every: 1, 20, "yes", "yes", "no"
    @railLabel: b0, b1, "Line RMS (dB)"

    # E: spatial centre of gravity, MEASURED from the output channels
    @drawSpace

    # C: growth rate over time (with critical line) and the regime bands
    .gLo = 1e9
    .gHi = -1e9
    for zi from 0 to 400
        @paramsAt: zi / 400
        gCurve_'zi' = paramsAt.rho
        .gLo = min(.gLo, paramsAt.rho)
        .gHi = max(.gHi, paramsAt.rho)
    endfor
    .gLo = min(.gLo, -4)
    .gHi = max(.gHi, 4)
    .pad = (.gHi - .gLo) * 0.1
    .yl = .gLo - .pad
    .yh = .gHi + .pad
    Select inner viewport: 0.6, 7.7, c0f, c1f
    Axes: 0, dur, .yl, .yh
    Paint rectangle: "{0.93, 0.95, 0.99}", 0, dur, .yl, -3
    Paint rectangle: "{0.99, 0.94, 0.90}", 0, dur, 0.3, .yh
    Colour: "{0.30, 0.30, 0.30}"
    Dashed line
    Draw line: 0, 0, dur, 0
    Solid line
    Colour: "{0.85, 0.35, 0.15}"
    Line width: 1.8
    for zi to 400
        zj = zi - 1
        Draw line: zj / 400 * dur, gCurve_'zj', zi / 400 * dur, gCurve_'zi'
    endfor
    Line width: 1
    Select inner viewport: 0.6, 7.7, c0f, c1f
    Axes: 0, dur, .yl, .yh
    Colour: "Black"
    Text top: "no", "##Growth rate (dB/s)## — dashed: critical; blue: dissipative (< -3); orange: self-oscillating (> +0.3)"
    Select inner viewport: 0.6, 7.7, c0f, c1f
    Axes: 0, dur, .yl, .yh
    Draw inner box
    @niceStep: dur, 8
    Marks bottom every: 1, niceStep.step, "yes", "yes", "no"
    @niceStep: .yh - .yl, 3
    Marks left every: 1, niceStep.step, "yes", "yes", "no"
    Text bottom: "yes", "Time (s)"
    @railLabel: c0f, c1f, "dB/s"

    # D: state-space, early (transient) vs late (long-term)
    .early = min(dur * 0.25, 1.0)
    @phasePlot: 0.6, 3.95, d0, d1, 0, .early, "##State space, first " + fixed$(.early, 2) + " s## (blue→orange = time)"
    @phasePlot: 4.35, 7.7, d0, d1, max(0, dur - 1.0), dur, "##State space, last " + fixed$(min(1, dur), 2) + " s##"

    # summary
    Font size: 7
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
    Colour: "Black"
    Text: 0.012, "left", 0.86, "half", "##Summary##"
    Font size: 6
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "{0.25, 0.25, 0.28}"
    Text: 0.012, "left", 0.66, "half", "Delays (samples, prime): " + dl$ + " (" + fixed$(dmin / sr * 1000, 2) + "–" + fixed$(dmax / sr * 1000, 2) + " ms)   |   " + matName$
    Text: 0.012, "left", 0.48, "half", "Growth " + fixed$(rhoStart, 2) + " dB/s (" + regStart$ + ") → " + fixed$(rhoEnd, 2) + " dB/s (" + regEnd$ + "); per-pass radius " + fixed$(gS1, 4) + "–" + fixed$(gS2, 4) + "   |   drive " + fixed$(driveStart, 2) + " → " + fixed$(driveEnd, 2) + ", asymmetry " + fixed$(asymmetry, 2) + "   |   " + nlName$
    Text: 0.012, "left", 0.30, "half", "Damping " + fixed$(dampStart, 2) + " → " + fixed$(dampEnd, 2) + "   |   excitation: " + excName$ + "   |   " + spaceName$ + ", spread " + fixed$(stereoSpread, 0) + "\%  , " + layoutName$
    Text: 0.012, "left", 0.12, "half", "Normalised: " + normNote$ + "   |   last vs first quarter " + fixed$(decayDb, 1) + " dB   |   max state " + fixed$(stateMax, 3) + "   |   " + string$(nBlocks) + " exact blocks, " + fixed$(synthTime, 1) + " s"
    Select inner viewport: 0.6, 7.7, s0, s1
    Axes: 0, 1, 0, 1
    Colour: "Black"
    Draw inner box
    Font size: 10
    Select outer viewport: 0, 8, 0, canvasH
endproc
