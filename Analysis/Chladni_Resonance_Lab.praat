# ============================================================
# Praat AudioTools - Chladni Resonance Lab — Sound into Patterns
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.2 (2026)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Interactive Demo-window simulation of Chladni figure FORMATION: individual
#   virtual sand grains on a driven plate migrate, step by step, toward the
#   regions of low time-averaged vibration and organise into nodal patterns.
#   Explore mode drives the plate with sine tones; Sound mode derives the
#   modal excitation from a selected Sound (resonance-based or creative).
#
# PLATE MODELS (both are modal models, not elastic-plate solvers):
#   A. "Free square plate, cosine approximation". Mode shapes
#        psi(m,n,s) = N [cos(m pi u) cos(n pi v) + s cos(n pi u) cos(m pi v)]
#      on the unit square, s = +1 / -1 (m > n) or a single term (m = n).
#      This is the classical Rayleigh-Ritz-style approximation of a square
#      plate with FREE edges, in which cosines replace the true free-free
#      beam functions. Its nodal lines are the familiar textbook Chladni
#      figures. Frequencies f = fu (m^2 + n^2)(1 + 0.05 s) are ILLUSTRATIVE:
#      the m^2 + n^2 ordering with a small +/- split, not measured values.
#   B. "Simply supported plate, exact modes". psi(m,n) = 2 sin(m pi u) sin(n pi v),
#      f = fu (m^2 + (n/r)^2), r = Ly/Lx. These are the exact eigenmodes and
#      eigenfrequency ratios of a thin isotropic Kirchhoff plate with hinged
#      (simply supported) edges. Real Chladni plates are free or centre-clamped,
#      so B is physically exact for a DIFFERENT boundary condition.
#
# DRIVEN RESPONSE: a point exciter at (ud, vd) driving tone(s) F excites
#   each mode with c_k = level * a * psi_k(ud,vd) * H_k(F) / Q,
#   H_k(F) = 1 / (1 - (F/f_k)^2 + i F/(Q f_k))   (single-DOF modal resonance).
#   Same-frequency modes add coherently (complex), different tones add in
#   energy. Gamma^2(u,v) = sum_tones |sum_k c_k psi_k(u,v)|^2 is treated as
#   the squared peak plate acceleration in units of g: sand can hop only
#   where Gamma > 1. Moving the exciter changes which modes are excited.
#
# PARTICLE TRANSPORT (phenomenological, not granular dynamics), per step:
#   act  = Gamma^4 / (1 + Gamma^4)          probability-like hop activity
#   gate = kappa * act_max + (1 - kappa) act slow creep inside quiet bands
#   v    = damp v + (1-damp)(-mu gate grad(Gamma^2) / (Gamma^2_max k_dom))
#          (drift saturated at vmax)
#   x    = x + v + sigma act eta            eta ~ N(0,1), soft-bounded at 2.5
#   then reflected into the plate:  u = 1 - |1 - |u||
#   Grains therefore jitter where the plate is agitated and settle where
#   Gamma^2 is minimal; a change of excitation re-mobilises them in place
#   (no reset). Gradients are ANALYTIC (exact derivatives of the modes).
#
# SOUND MODE (offline analysis before animation):
#   Resonance-based: per 0.2 s window, the energy of the Sound inside each
#     mode's half-power band [f_k (1 - 1/2Q), f_k (1 + 1/2Q)], Q = 30, times
#     that mode's squared participation at the exciter (the sound is assumed
#     to reach the plate through the exciter) sets its weight; the strongest
#     modes are excited incoherently (distinct frequencies). Plate tuning is
#     automatic (the spectral centroid maps to the middle of the mode bank)
#     unless "Plate lowest resonance" is set. The share of the Sound's energy
#     inside the union of all plate bands is reported: a sound with no energy
#     near the plate's resonances produces NO pattern, as it should.
#   Creative spectral mapping (ARTISTIC, not predictive): spectral centroid
#     selects the mode order, spectral spread blends in a neighbour mode and
#     adds agitation, RMS sets the drive level. The exciter is not used.
#   Audio time advances at 0.25 x simulated time by default (keys , and .),
#     so that patterns have time to form between spectral changes.
#
# TRANSITIONS: changing frequency, mode, exciter, plate or PRESET never moves
#   a grain: the existing sand migrates into the new figure (R resets all
#   sand; presetSprinkle can re-enable a partial sprinkle on preset change). The mode
#   buttons step to the next resonance the exciter can actually drive.
#
# CONTROLS: buttons on the right, or keys:
#   Space start/pause · R reset sand · Left/Right previous/next resonance ·
#   Up/Down frequency +/- quarter tone · e/E drive -/+ · g/G grains -/+ ·
#   m/M mobility -/+ · s/S speed -/+ · N nodal lines · F field · B plate model ·
#   O source (Explore -> Sound resonance -> Sound creative) · P/p next/previous
#   preset · , . audio time scale · Q or Esc quit. Click the plate to move the
#   exciter; click the response strip to set the drive frequency. Paused, the
#   script blocks in demoWaitForInput (no busy-waiting).
#
# Notes:
#   - The layout assumes the Demo window's default 16:9 shape; on other
#     shapes the plate is stretched (the physics is unaffected).
#   - Temporary objects are five Matrix grids "ChladniLab_grid_..." and the
#     Sound "ChladniLab_tmp_sound"; matched by exact type + name, they
#     are removed on exit and, if a previous session was interrupted by
#     closing the Demo window, removed at the next launch. User objects are
#     never modified or removed.
#   - "Diagnostic self-test" runs without the Demo window and reports
#     pattern-concentration, boundedness, transition and sound-mapping checks.
#   - The frame rate shown while running is measured, not assumed. Measured
#     on a software-rendered virtual display (Praat 6.4.06, no overlays):
#     Fast 28, Balanced 21, Detailed 14 fps; a GPU-backed desktop is faster.
#   - Playing the Sound from inside the lab is not offered: audio playback
#     could not be verified in the test environment.
# ============================================================

# Changelog v1.2 (2026):
#   - FIX: every PRESET change doubled the audio time scale, and the "." key
#     (audio faster) did nothing - a missing "audioFaster" branch.
#   - FIX: start-up cleanup removed ANY object whose name contained
#     "ChladniLab_"; it now removes only the exact temporary objects
#     (type + name) that the lab itself creates.
#   - CHANGE: a preset change no longer re-sprinkles 40 % of the sand; the
#     existing grains migrate into the new figure. R still resets all sand.
#   - Self-test: preset change must move no grain and keep the audio time
#     scale; "." / "," must double / halve it.
#
# Changelog v1.1 (2026):
#   - FIX (Praat >= 6.4.58, incl. 7.0): Q / Esc / buttons did nothing while
#     running and closing the window crashed Praat. Cause: a Praat bug in the
#     halt/resume Demo-window model introduced in 6.4.58 — input that arrives
#     during demoPeekInput() re-runs the script from inside the event callback
#     (input lost, nested execution, assertion/crash on unwinding). The lab now
#     never calls demoPeekInput() on these versions: it runs in 3-s TAKES and
#     reads input safely with demoWaitForInput() between takes. Praat < 6.4.58
#     keeps continuous running with live input.
#   - Known Praat bug (Linux, >= 6.4.58): closing the Demo window DURING a take
#     crashes Praat (demoShow dereferences the destroyed editor). Use Q / Esc /
#     Exit, or close the window between takes. Windows and macOS defer the
#     close to the next wait, which is safe.
#
# Changelog v1.0 (2026):
#   - Initial release.
#
form Chladni Resonance Lab v1.2
    optionmenu Quality 2
        option Fast
        option Balanced
        option Detailed
    optionmenu Start_preset 1
        option 1 Fundamental Resonance
        option 2 Symmetric Cross
        option 3 Diagonal Interference
        option 4 Higher-Order Resonance
        option 5 Dual-Mode Interference
        option 6 Near-Degenerate Modes
        option 7 Modal Morphing
        option 8 Turbulent Sand
        option 9 Quiet Nodes
        option 10 Experimental Resonance
    optionmenu Sound_mapping 1
        option Resonance-based excitation
        option Creative spectral mapping (artistic)
    real Plate_lowest_resonance_Hz 0
    boolean Diagnostic_self_test 0
endform

# ============================================================
# 1. CONFIGURATION AND DEFAULTS
# ============================================================
if quality = 1
    qualityName$ = "Fast"
    nPartDefault = 900
    nGrid = 40
    maxActive = 4
    mMax = 7
    dotR = 0.75
elsif quality = 2
    qualityName$ = "Balanced"
    nPartDefault = 1800
    nGrid = 64
    maxActive = 6
    mMax = 9
    dotR = 0.62
else
    qualityName$ = "Detailed"
    nPartDefault = 3200
    nGrid = 96
    maxActive = 8
    mMax = 11
    dotR = 0.52
endif

# simulation constants (dimensionless plate units, one step = dtSim model s)
dtSim = 0.02
vmax = 0.008
mu0 = 0.006
sigma0 = 0.0035
kappa = 0.15
bandThr = 0.005
nPartMin = 150
nPartMax = 6000
splitEps = 0.05
nRespF = 110
audioRate = 0.25
# Share of grains re-sprinkled at random on a PRESET change (0 = none: the
# existing sand migrates into the new figure; R still resets all sand).
presetSprinkle = 0

# colours
cBg$ = "{0.075, 0.075, 0.080}"
cPlate$ = "{0.150, 0.150, 0.160}"
cEdge$ = "{0.330, 0.315, 0.290}"
cSand$ = "{0.870, 0.760, 0.560}"
cSandHop$ = "{0.985, 0.930, 0.820}"
cNodal$ = "{0.420, 0.600, 0.660}"
cText$ = "{0.900, 0.875, 0.825}"
cDim$ = "{0.560, 0.545, 0.515}"
cAccent$ = "{0.880, 0.720, 0.470}"
cCopper$ = "{0.860, 0.460, 0.300}"
cPanel$ = "{0.110, 0.110, 0.118}"
cBtn$ = "{0.190, 0.190, 0.200}"
cBtnOn$ = "{0.330, 0.270, 0.180}"
cBtnText$ = "{0.860, 0.840, 0.800}"

# Demo window layout (percent, bottom-up). The plate is square in pixels for
# the default 16:9 window: 90 % of the height = 50.6 % of the width.
demoAspect = 16 / 9
plateAreaX1 = 2.5
plateAreaX2 = 54.5
plateAreaY1 = 5
plateAreaY2 = 95

# ============================================================
# 2. INPUT VALIDATION
# ============================================================
userSound = 0
userSoundName$ = ""
selectionNote$ = ""
nSel = numberOfSelected ()
if nSel > 0
    nSnd = numberOfSelected ("Sound")
    if nSnd = 1 and nSel = 1
        userSound = selected ("Sound")
        userSoundName$ = selected$ ("Sound")
    elsif nSnd >= 1
        userSound = selected ("Sound", 1)
        userSoundName$ = selected$ ("Sound", 1)
        selectionNote$ = "Several objects selected: using the first Sound, " + userSoundName$ + "."
    else
        selectionNote$ = "The selection contains no Sound: running in Explore mode only."
    endif
endif

if plate_lowest_resonance_Hz < 0 or plate_lowest_resonance_Hz > 5000
    exitScript: "Plate lowest resonance must be 0 (automatic) or between 1 and 5000 Hz."
endif

@cleanupLeftovers
if userSound > 0
    selectObject: userSound
endif

# ============================================================
# HELPER PROCEDURES
# ============================================================

# Remove temporary objects left by an interrupted earlier session. Only
# objects whose full name is exactly one of ours are touched.
procedure cleanupLeftovers
    .n = numberOfSelected ()
    for .i to .n
        .keep[.i] = selected (.i)
    endfor
    nocheck select all
    .nAll = numberOfSelected ()
    .nRm = 0
    for .i to .nAll
        .s$ = selected$ (.i)
        if .s$ = "Matrix ChladniLab_grid_ur" or .s$ = "Matrix ChladniLab_grid_ui"
        ... or .s$ = "Matrix ChladniLab_grid_g2" or .s$ = "Matrix ChladniLab_grid_nodal"
        ... or .s$ = "Matrix ChladniLab_grid_display" or .s$ = "Sound ChladniLab_tmp_sound"
            .nRm = .nRm + 1
            .rm[.nRm] = selected (.i)
        endif
    endfor
    for .i to .nRm
        removeObject: .rm[.i]
    endfor
    if .n > 0
        selectObject: .keep[1]
        for .i from 2 to .n
            plusObject: .keep[.i]
        endfor
    endif
endproc

# Mode bank for the current plate model, aspect ratio and tuning, sorted by
# frequency. Arrays: mb_m, mb_n, mb_s, mb_f, mb_nrm, mb_unit, mb_lab$.
procedure buildModeBank
    nModes = 0
    if plateModel = 1
        for .m from 1 to mMax
            for .n from 0 to .m
                if .m + .n >= 2
                    if .m = .n
                        nModes = nModes + 1
                        mb_m[nModes] = .m
                        mb_n[nModes] = .n
                        mb_s[nModes] = 0
                        mb_unit[nModes] = .m * .m + .n * .n
                    else
                        for .k to 2
                            .sg = if .k = 1 then -1 else 1 fi
                            nModes = nModes + 1
                            mb_m[nModes] = .m
                            mb_n[nModes] = .n
                            mb_s[nModes] = .sg
                            mb_unit[nModes] = (.m * .m + .n * .n) * (1 + splitEps * .sg)
                        endfor
                    endif
                endif
            endfor
        endfor
    else
        for .m from 1 to mMax
            for .n from 1 to mMax
                if .m * .m + .n * .n <= mMax * mMax + 2
                    nModes = nModes + 1
                    mb_m[nModes] = .m
                    mb_n[nModes] = .n
                    mb_s[nModes] = 0
                    mb_unit[nModes] = .m * .m + (.n / aspect) ^ 2
                endif
            endfor
        endfor
    endif
    # insertion sort by unit frequency (explicit flag: Praat's "and" does not
    # short-circuit, so the index guard cannot share the comparison)
    for .i from 2 to nModes
        .km = mb_m[.i]
        .kn = mb_n[.i]
        .ks = mb_s[.i]
        .ku = mb_unit[.i]
        .j = .i - 1
        .go = 1
        while .go
            if .j < 1
                .go = 0
            elsif mb_unit[.j] <= .ku
                .go = 0
            else
                mb_m[.j + 1] = mb_m[.j]
                mb_n[.j + 1] = mb_n[.j]
                mb_s[.j + 1] = mb_s[.j]
                mb_unit[.j + 1] = mb_unit[.j]
                .j = .j - 1
            endif
        endwhile
        mb_m[.j + 1] = .km
        mb_n[.j + 1] = .kn
        mb_s[.j + 1] = .ks
        mb_unit[.j + 1] = .ku
    endfor
    for .k to nModes
        mb_f[.k] = fUnit * mb_unit[.k]
        .mm = mb_m[.k]
        .nn = mb_n[.k]
        if plateModel = 1
            # unit RMS over the plate: ||cos(a pi u)||^2 = 1/2 (a > 0), 1 (a = 0)
            .am = if .mm = 0 then 1 else 0.5 fi
            .an = if .nn = 0 then 1 else 0.5 fi
            if mb_s[.k] = 0
                mb_nrm[.k] = 1 / sqrt(.am * .an)
                mb_lab$[.k] = "(" + string$(.mm) + "," + string$(.nn) + ")"
            else
                mb_nrm[.k] = 1 / sqrt(2 * .am * .an)
                .sgn$ = if mb_s[.k] > 0 then "+" else "−" fi
                mb_lab$[.k] = "(" + string$(.mm) + "," + string$(.nn) + ")" + .sgn$
            endif
        else
            mb_nrm[.k] = 2
            mb_lab$[.k] = "(" + string$(.mm) + "," + string$(.nn) + ")"
        endif
    endfor
    fBankLo = mb_f[1]
    fBankHi = mb_f[nModes]
endproc

# psi_k at one point (u, v)
procedure psiAt: .k, .u, .v
    .mm = mb_m[.k]
    .nn = mb_n[.k]
    if plateModel = 1
        if mb_s[.k] = 0
            psiAt.val = mb_nrm[.k] * cos(.mm * pi * .u) * cos(.nn * pi * .v)
        else
            psiAt.val = mb_nrm[.k] * (cos(.mm * pi * .u) * cos(.nn * pi * .v) + mb_s[.k] * cos(.nn * pi * .u) * cos(.mm * pi * .v))
        endif
    else
        psiAt.val = mb_nrm[.k] * sin(.mm * pi * .u) * sin(.nn * pi * .v)
    endif
endproc

# Mode index for (m, n, s); 0 if absent
# (result in findMode.idx: a procedure's dotted locals ARE its result
#  variables, so the loop counter must not share the result's name)
procedure findMode: .m, .n, .s
    findMode.idx = 0
    for .k to nModes
        if mb_m[.k] = .m and mb_n[.k] = .n and mb_s[.k] = .s
            findMode.idx = .k
        endif
    endfor
endproc

# Nearest resonance to frequency .f
procedure nearestMode: .f
    nearestMode.idx = 1
    .best = 1e30
    for .k to nModes
        .d = abs(ln(mb_f[.k] / .f))
        if .d < .best
            .best = .d
            nearestMode.idx = .k
        endif
    endfor
endproc

# Exciter at the interior/edge grid point where |psi_k| is largest
procedure autoDrivePoint: .k
    .best = -1
    for .i from 0 to 18
        for .j from 0 to 18
            .u = 0.04 + .i * 0.92 / 18
            .v = 0.04 + .j * 0.92 / 18
            @psiAt: .k, .u, .v
            # tiny tie-breaker keeps symmetric optima deterministic
            .score = abs(psiAt.val) - 0.0001 * (.i + 0.37 * .j)
            if .score > .best
                .best = .score
                driveU = .u
                driveV = .v
            endif
        endfor
    endfor
endproc

# Complex modal coefficients for every tone -> active-mode lists.
#   tone j: tf[j] Hz, ta[j] relative amplitude (Explore), or a precomputed
#   incoherent mode list (Sound mode, toneFixed = 1).
procedure computeTones
    gammaRef = 0
    domK = 0
    .domC = 0
    totShare = 0
    for .j to nTones
        if toneFixed = 0
            nAct[.j] = 0
            .cmax = 0
            for .k to nModes
                @psiAt: .k, driveU, driveV
                .w = psiAt.val
                .r = tf[.j] / mb_f[.k]
                .a = 1 - .r * .r
                .b = .r / qFactor
                .den = .a * .a + .b * .b
                # c = level * ta * w * H / Q ,  H = (a - i b) / den
                .cr[.k] = driveLevel * ta[.j] * .w * (.a / .den) / qFactor
                .ci[.k] = - driveLevel * ta[.j] * .w * (.b / .den) / qFactor
                .mag[.k] = sqrt(.cr[.k] ^ 2 + .ci[.k] ^ 2)
                if .mag[.k] > .cmax
                    .cmax = .mag[.k]
                endif
            endfor
            # keep the strongest modes (>= 2 % of the strongest), at most maxActive
            for .k to nModes
                .used[.k] = 0
            endfor
            .go = 1
            while .go
                .bk = 0
                .bv = 0
                for .k to nModes
                    if .used[.k] = 0 and .mag[.k] > .bv
                        .bv = .mag[.k]
                        .bk = .k
                    endif
                endfor
                if .bk = 0 or .bv < 0.02 * .cmax or .bv < 1e-6 or nAct[.j] >= maxActive
                    .go = 0
                else
                    .used[.bk] = 1
                    nAct[.j] = nAct[.j] + 1
                    actK[.j, nAct[.j]] = .bk
                    actCr[.j, nAct[.j]] = .cr[.bk]
                    actCi[.j, nAct[.j]] = .ci[.bk]
                endif
            endwhile
        endif
        for .i to nAct[.j]
            .mg = sqrt(actCr[.j, .i] ^ 2 + actCi[.j, .i] ^ 2)
            totShare = totShare + .mg * .mg
            if .mg > .domC
                .domC = .mg
                domK = actK[.j, .i]
            endif
        endfor
    endfor
    if domK > 0
        kDom = pi * sqrt(mb_m[domK] ^ 2 + (mb_n[domK] / aspect) ^ 2)
    else
        kDom = pi
    endif
    kDom = max(pi, kDom)
    gridDirty = 1
endproc

# Displacement and analytic u/v derivatives of mode k at all particles.
procedure modeVec: .k
    .mm = mb_m[.k]
    .nn = mb_n[.k]
    .nr = mb_nrm[.k]
    if plateModel = 1
        .cmu# = cos# (.mm * pi * px#)
        .smu# = sin# (.mm * pi * px#)
        .cnv# = cos# (.nn * pi * py#)
        .snv# = sin# (.nn * pi * py#)
        if mb_s[.k] = 0
            mvP# = .nr * .cmu# * .cnv#
            mvU# = - .nr * .mm * pi * .smu# * .cnv#
            mvV# = - .nr * .nn * pi * .cmu# * .snv#
        else
            .sg = mb_s[.k]
            .cnu# = cos# (.nn * pi * px#)
            .snu# = sin# (.nn * pi * px#)
            .cmv# = cos# (.mm * pi * py#)
            .smv# = sin# (.mm * pi * py#)
            mvP# = .nr * (.cmu# * .cnv# + .sg * .cnu# * .cmv#)
            mvU# = - .nr * pi * (.mm * .smu# * .cnv# + .sg * .nn * .snu# * .cmv#)
            mvV# = - .nr * pi * (.nn * .cmu# * .snv# + .sg * .mm * .cnu# * .smv#)
        endif
    else
        .smu# = sin# (.mm * pi * px#)
        .cmu# = cos# (.mm * pi * px#)
        .snv# = sin# (.nn * pi * py#)
        .cnv# = cos# (.nn * pi * py#)
        mvP# = .nr * .smu# * .snv#
        mvU# = .nr * .mm * pi * .cmu# * .snv#
        mvV# = .nr * .nn * pi * .smu# * .cnv#
    endif
endproc

# Gamma^2 and its gradient at every particle (vectors g2#, gu#, gv#)
procedure fieldAtParticles
    g2# = zero# (nPart)
    gu# = zero# (nPart)
    gv# = zero# (nPart)
    for .j to nTones
        .ur# = zero# (nPart)
        .ui# = zero# (nPart)
        .uru# = zero# (nPart)
        .urv# = zero# (nPart)
        .uiu# = zero# (nPart)
        .uiv# = zero# (nPart)
        for .i to nAct[.j]
            @modeVec: actK[.j, .i]
            .cr = actCr[.j, .i]
            .ci = actCi[.j, .i]
            .ur# = .ur# + .cr * mvP#
            .uru# = .uru# + .cr * mvU#
            .urv# = .urv# + .cr * mvV#
            if .ci <> 0
                .ui# = .ui# + .ci * mvP#
                .uiu# = .uiu# + .ci * mvU#
                .uiv# = .uiv# + .ci * mvV#
            endif
        endfor
        g2# = g2# + .ur# * .ur# + .ui# * .ui#
        gu# = gu# + 2 * (.ur# * .uru# + .ui# * .uiu#)
        gv# = gv# + 2 * (.ur# * .urv# + .ui# * .uiv#)
    endfor
endproc

# Field grids (display, nodal overlay, normalisation, nodal-band area).
# Created once; overwritten in place.
procedure createGrids
    .d = 1 / nGrid
    gUr = Create Matrix: "ChladniLab_grid_ur", 0, 1, nGrid, .d, .d / 2, 0, 1, nGrid, .d, .d / 2, "0"
    gUi = Create Matrix: "ChladniLab_grid_ui", 0, 1, nGrid, .d, .d / 2, 0, 1, nGrid, .d, .d / 2, "0"
    gG2 = Create Matrix: "ChladniLab_grid_g2", 0, 1, nGrid, .d, .d / 2, 0, 1, nGrid, .d, .d / 2, "0"
    gS = Create Matrix: "ChladniLab_grid_nodal", 0, 1, nGrid, .d, .d / 2, 0, 1, nGrid, .d, .d / 2, "0"
    gD = Create Matrix: "ChladniLab_grid_display", 0, 1, nGrid, .d, .d / 2, 0, 1, nGrid, .d, .d / 2, "0"
endproc

procedure updateGrid
    selectObject: gG2
    Formula: "0"
    .sumRR = 0
    .sumII = 0
    .sumRI = 0
    for .j to nTones
        selectObject: gUr
        Formula: "0"
        selectObject: gUi
        Formula: "0"
        for .i to nAct[.j]
            .k = actK[.j, .i]
            .mm = mb_m[.k]
            .nn = mb_n[.k]
            .sg = mb_s[.k]
            .nr = mb_nrm[.k]
            .cr = actCr[.j, .i]
            .ci = actCi[.j, .i]
            if plateModel = 1
                selectObject: gUr
                Formula: ~ self + .cr * .nr * (cos(.mm * pi * x) * cos(.nn * pi * y) + .sg * cos(.nn * pi * x) * cos(.mm * pi * y))
                if .ci <> 0
                    selectObject: gUi
                    Formula: ~ self + .ci * .nr * (cos(.mm * pi * x) * cos(.nn * pi * y) + .sg * cos(.nn * pi * x) * cos(.mm * pi * y))
                endif
            else
                selectObject: gUr
                Formula: ~ self + .cr * .nr * sin(.mm * pi * x) * sin(.nn * pi * y)
                if .ci <> 0
                    selectObject: gUi
                    Formula: ~ self + .ci * .nr * sin(.mm * pi * x) * sin(.nn * pi * y)
                endif
            endif
        endfor
        selectObject: gG2
        Formula: ~ self + object[gUr, row, col] ^ 2 + object[gUi, row, col] ^ 2
        if .j = 1
            # principal-phase signed field of tone 1 (nodal lines)
            selectObject: gS
            Formula: ~ object[gUr, row, col] ^ 2
            .sumRR = Get sum
            Formula: ~ object[gUi, row, col] ^ 2
            .sumII = Get sum
            Formula: ~ object[gUr, row, col] * object[gUi, row, col]
            .sumRI = Get sum
        endif
    endfor
    selectObject: gG2
    g2Max = Get maximum
    if g2Max = undefined
        g2Max = 0
    endif
    gammaMax = sqrt(max(0, g2Max))
    if g2Max > 1e-20
        if nTones = 1
            .alpha = 0.5 * arctan2(2 * .sumRI, .sumRR - .sumII)
            .ca = cos(.alpha)
            .sa = sin(.alpha)
            selectObject: gS
            Formula: ~ object[gUr, row, col] * .ca + object[gUi, row, col] * .sa
            nodalByZero = 1
        else
            selectObject: gS
            Formula: ~ object[gG2, row, col] / g2Max - bandThr
            nodalByZero = 0
        endif
        selectObject: gD
        Formula: ~ - sqrt(object[gG2, row, col] / g2Max)
        # area fraction of the low-vibration band (uniform-sand baseline)
        selectObject: gUi
        Formula: ~ if object[gG2, row, col] / g2Max < bandThr then 1 else 0 fi
        bandArea = Get sum
        bandArea = bandArea / (nGrid * nGrid)
    else
        selectObject: gS
        Formula: "1"
        selectObject: gD
        Formula: "0"
        bandArea = 1
        nodalByZero = 0
    endif
    gridDirty = 0
endproc

# Particle vectors
procedure randomParticles: .n
    nPart = .n
    px# = randomUniform# (nPart, 0, 1)
    py# = randomUniform# (nPart, 0, 1)
    pvu# = zero# (nPart)
    pvv# = zero# (nPart)
    act# = zero# (nPart)
    g2# = zero# (nPart)
endproc

procedure resizeParticles: .n
    .n = max(nPartMin, min(nPartMax, round(.n)))
    if .n > nPart
        .add = .n - nPart
        px# = combine# (px#, randomUniform# (.add, 0, 1))
        py# = combine# (py#, randomUniform# (.add, 0, 1))
        pvu# = combine# (pvu#, zero# (.add))
        pvv# = combine# (pvv#, zero# (.add))
        act# = combine# (act#, zero# (.add))
        g2# = combine# (g2#, zero# (.add))
        nPart = .n
    elsif .n < nPart
        .nx# = zero# (.n)
        .ny# = zero# (.n)
        .nu# = zero# (.n)
        .nv# = zero# (.n)
        .na# = zero# (.n)
        .ng# = zero# (.n)
        for .i to .n
            .nx#[.i] = px#[.i]
            .ny#[.i] = py#[.i]
            .nu#[.i] = pvu#[.i]
            .nv#[.i] = pvv#[.i]
            .na#[.i] = act#[.i]
            .ng#[.i] = g2#[.i]
        endfor
        px# = .nx#
        py# = .ny#
        pvu# = .nu#
        pvv# = .nv#
        act# = .na#
        g2# = .ng#
        nPart = .n
    endif
endproc

# Re-sprinkle a fraction of the grains (presetSprinkle on a preset change;
# 0 by default, so nothing moves); the rest keep their positions. (Changing frequency,
# mode or exciter never moves a grain: the pattern must migrate.)
procedure sprinkle: .frac
    sprinkled = 0
    for .i to nPart
        if randomUniform (0, 1) < .frac
            px#[.i] = randomUniform (0, 1)
            py#[.i] = randomUniform (0, 1)
            pvu#[.i] = 0
            pvv#[.i] = 0
            sprinkled = sprinkled + 1
        endif
    endfor
endproc

# ============================================================
# 7. PARTICLE SIMULATION (one step, fully vectorised)
# ============================================================
procedure simStep
    @fieldAtParticles
    # hop activity and creep gate
    .g4# = g2# * g2#
    act# = .g4# / (1 + .g4#)
    .gm4 = g2Max * g2Max
    .actMax = .gm4 / (1 + .gm4)
    .gate# = kappa * .actMax + (1 - kappa) * act#
    if g2Max > 1e-12
        .sc = mu0 * mobility / (g2Max * kDom)
    else
        .sc = 0
    endif
    # drift (physical metric: v is scaled by the aspect ratio r = Ly/Lx)
    .du# = - .sc * .gate# * gu#
    .dv# = - .sc * .gate# * gv# / (aspect * aspect)
    .sp# = sqrt# (.du# * .du# + .dv# * .dv# * aspect * aspect)
    # (Praat has no scalar / vector: reciprocals are written as ^ (-1))
    .lim# = (1 + (.sp# / vmax) ^ 2) ^ (-0.5)
    .du# = .du# * .lim#
    .dv# = .dv# * .lim#
    pvu# = damping * pvu# + (1 - damping) * .du#
    pvv# = damping * pvv# + (1 - damping) * .dv#
    # bounded random hops (soft limit 2.5 sigma)
    .eu# = randomGauss# (nPart, 0, 1)
    .ev# = randomGauss# (nPart, 0, 1)
    .eu# = .eu# / sqrt# (1 + (.eu# / 2.5) ^ 2)
    .ev# = .ev# / sqrt# (1 + (.ev# / 2.5) ^ 2)
    .sig = sigma0 * noiseLevel * mobility ^ 0.5
    px# = px# + pvu# + .sig * act# * .eu#
    py# = py# + pvv# + .sig * act# * .ev# / aspect
    # reflecting boundaries (steps are bounded far below one plate width)
    px# = 1 - abs# (1 - abs# (px#))
    py# = 1 - abs# (1 - abs# (py#))
    stepCount = stepCount + 1
    stepsSinceChange = stepsSinceChange + 1
endproc

# Order parameter: share of grains in the low-vibration band (smooth count)
procedure orderParameter
    if g2Max > 1e-12
        .r# = g2# / (g2Max * bandThr)
        .r2# = .r# * .r#
        .ind# = (1 + .r2# * .r2#) ^ (-1)
        pBand = mean (.ind#)
    else
        pBand = 0
    endif
    pBandSmooth = 0.9 * pBandSmooth + 0.1 * pBand
endproc

# Exact count (self-test and reports): grains with Gamma^2 < bandThr Gamma^2_max
procedure exactBandShare
    @fieldAtParticles
    .c = 0
    for .i to nPart
        if g2#[.i] < bandThr * g2Max
            .c = .c + 1
        endif
    endfor
    exactBandShare.p = .c / nPart
endproc

# Stage classification from the measured order parameter
procedure updateStage
    if stepCount = 0
        stage$ = "Initial random distribution"
    elsif gammaMax < 1
        stage$ = "Below hopping threshold (Γ < 1): sand at rest — tune toward a resonance"
    elsif stepCount < 25
        stage$ = "Excitation begins"
    elsif stepsSinceChange < 150 and transitionFlag
        if pBandSmooth > 0.6
            transitionFlag = 0
        endif
        stage$ = "Modal transition — grains redistribute"
    else
        # concentration = share of grains in the quiet band / its area share.
        # Multi-mode fields have tiny quiet areas, so both measures are used.
        .conc = pBandSmooth / max(0.002, bandArea)
        .lvl = max(min(1, pBandSmooth / 0.72), min(1, .conc / 8))
        if .lvl < 0.4
            stage$ = "Active particle migration"
        elsif .lvl < 1
            stage$ = "Emerging nodal concentration"
        else
            stage$ = "Near-equilibrium pattern"
        endif
    endif
endproc

# Called whenever the excitation changes (frequency, exciter, preset, ...)
procedure excitationChanged
    if pBandSmooth > 0.45
        transitionFlag = 1
    endif
    stepsSinceChange = 0
    @computeTones
    @computeResponseCurve
endproc

# Plate response at the exciter vs drive frequency (for the strip)
procedure computeResponseCurve
    respLo = fBankLo / 1.35
    respHi = fBankHi * 1.08
    .lf# = zero# (nRespF)
    for .i to nRespF
        .lf#[.i] = ln(respLo) + (.i - 1) / (nRespF - 1) * (ln(respHi) - ln(respLo))
    endfor
    .fq# = exp# (.lf#)
    .r# = zero# (nRespF)
    for .k to nModes
        @psiAt: .k, driveU, driveV
        modePart[.k] = abs(psiAt.val)
        .w2 = psiAt.val ^ 2
        .q# = .fq# / mb_f[.k]
        .a# = 1 - .q# * .q#
        .b# = .q# / qFactor
        .r# = .r# + (.w2 / (qFactor * qFactor)) * (.a# * .a# + .b# * .b#) ^ (-1)
    endfor
    respLog# = .lf# / ln(10)
    respR# = sqrt# (.r#)
    .mx = max (respR#)
    if .mx > 0
        respR# = respR# / .mx
    endif
endproc

# ============================================================
# 10. PRESET MANAGEMENT
#   Every preset is an explicit parameter set:
#   plate model, aspect r, tones (target modes and relative amplitudes), Q,
#   drive level, mobility, noise, damping and an optional automatic
#   frequency behaviour (1 = slow sweep, 2 = glide between two resonances).
# ============================================================
procedure presetDefs: .p
    pp_model = 1
    pp_aspect = 1
    pp_nt = 1
    pp_q = 50
    pp_level = 4
    pp_mob = 1
    pp_noise = 1
    pp_damp = 0.5
    pp_auto = 0
    pp_amp[1] = 1
    pp_amp[2] = 1
    pp_amp[3] = 1
    if .p = 1
        pp_name$ = "Fundamental Resonance"
        pp_note$ = "lowest bending mode: one central nodal cross"
        pp_tm[1] = 1
        pp_tn[1] = 1
        pp_ts[1] = 0
    elsif .p = 2
        pp_name$ = "Symmetric Cross"
        pp_note$ = "(3,1)+: orthogonal cross with corner arcs"
        pp_tm[1] = 3
        pp_tn[1] = 1
        pp_ts[1] = 1
    elsif .p = 3
        pp_name$ = "Diagonal Interference"
        pp_note$ = "(2,0)−: the two diagonals"
        pp_tm[1] = 2
        pp_tn[1] = 0
        pp_ts[1] = -1
    elsif .p = 4
        pp_name$ = "Higher-Order Resonance"
        pp_note$ = "(6,4)+: nested diamonds and rings"
        pp_tm[1] = 6
        pp_tn[1] = 4
        pp_ts[1] = 1
        pp_level = 5
    elsif .p = 5
        pp_name$ = "Dual-Mode Interference"
        pp_note$ = "two tones at (3,1)− and (4,0)−: sand seeks the shared quiet zones"
        pp_nt = 2
        pp_tm[1] = 3
        pp_tn[1] = 1
        pp_ts[1] = -1
        pp_tm[2] = 4
        pp_tn[2] = 0
        pp_ts[2] = -1
        pp_amp[2] = 0.9
    elsif .p = 6
        pp_name$ = "Near-Degenerate Modes"
        pp_note$ = "simply supported, r = 1.06: (3,2) and (2,3) sweep into each other"
        pp_model = 2
        pp_aspect = 1.06
        pp_tm[1] = 3
        pp_tn[1] = 2
        pp_ts[1] = 0
        pp_q = 80
        pp_auto = 1
    elsif .p = 7
        pp_name$ = "Modal Morphing"
        pp_note$ = "glide from (5,1)− to (5,3)− and back, through intermediate resonances"
        pp_tm[1] = 5
        pp_tn[1] = 1
        pp_ts[1] = -1
        pp_tm[2] = 5
        pp_tn[2] = 3
        pp_ts[2] = -1
        pp_auto = 2
        pp_q = 40
    elsif .p = 8
        pp_name$ = "Turbulent Sand"
        pp_note$ = "(4,0)− diamond lattice overdriven: high mobility, strong random hops"
        pp_tm[1] = 4
        pp_tn[1] = 0
        pp_ts[1] = -1
        pp_level = 7
        pp_mob = 1.4
        pp_noise = 2.2
        pp_damp = 0.25
    elsif .p = 9
        pp_name$ = "Quiet Nodes"
        pp_note$ = "(4,2)+: strong drift, little noise, heavy damping — fast crisp settling"
        pp_tm[1] = 4
        pp_tn[1] = 2
        pp_ts[1] = 1
        pp_level = 6
        pp_mob = 2
        pp_noise = 0.35
        pp_damp = 0.75
    else
        pp_name$ = "Experimental Resonance"
        pp_note$ = "three tones (3,1)−, (5,2)+, (7,2)− at low Q: a multimodal compromise"
        pp_nt = 3
        pp_tm[1] = 3
        pp_tn[1] = 1
        pp_ts[1] = -1
        pp_tm[2] = 5
        pp_tn[2] = 2
        pp_ts[2] = 1
        pp_tm[3] = 7
        pp_tn[3] = 2
        pp_ts[3] = -1
        pp_amp[2] = 0.8
        pp_amp[3] = 0.6
        pp_q = 25
    endif
endproc

procedure applyPreset: .p
    presetNo = .p
    presetModified = 0
    @presetDefs: .p
    presetName$ = pp_name$
    presetNote$ = pp_note$
    .rebuild = 0
    if pp_model <> plateModel or pp_aspect <> aspect
        .rebuild = 1
    endif
    plateModel = pp_model
    aspect = pp_aspect
    if .rebuild or nModes = 0
        @buildModeBank
    endif
    qFactor = pp_q
    driveLevel = pp_level
    mobility = pp_mob
    noiseLevel = pp_noise
    damping = pp_damp
    autoMode = pp_auto
    autoT0 = stepCount
    nTones = pp_nt
    toneFixed = 0
    if autoMode = 2
        nTones = 1
    endif
    for .j to pp_nt
        @findMode: pp_tm[.j], pp_tn[.j], pp_ts[.j]
        if findMode.idx = 0
            @nearestMode: fUnit * (pp_tm[.j] ^ 2 + pp_tn[.j] ^ 2)
            findMode.idx = nearestMode.idx
        endif
        presetK[.j] = findMode.idx
        tf[.j] = mb_f[findMode.idx]
        ta[.j] = pp_amp[.j]
    endfor
    @autoDrivePoint: presetK[1]
    if autoMode = 1
        # sweep across the degenerate pair (m,n) / (n,m)
        @findMode: pp_tn[1], pp_tm[1], pp_ts[1]
        .k2 = findMode.idx
        .fa = mb_f[presetK[1]]
        .fb = if .k2 > 0 then mb_f[.k2] else .fa * 1.03 fi
        autoFc = sqrt(.fa * .fb)
        autoSpan = 1.6 * abs(ln(.fb / .fa)) + 0.004
        autoPeriod = 40
        tf[1] = autoFc
        # exciter where both modes respond
        driveU = 0.21
        driveV = 0.17
    elsif autoMode = 2
        autoFa = mb_f[presetK[1]]
        autoFb = mb_f[presetK[2]]
        autoPeriod = 64
        tf[1] = autoFa
    endif
    if sourceMode > 1
        sourceMode = 1
    endif
    @excitationChanged
endproc

# Automatic frequency behaviours (called once per simulation step)
procedure autoFrequency
    if autoMode = 1
        .t = (stepCount - autoT0) * dtSim
        tf[1] = autoFc * exp(autoSpan * sin(2 * pi * .t / autoPeriod))
        @computeTones
    elsif autoMode = 2
        # hold A 8 s, glide 24 s, hold B 8 s, glide back 24 s (log-frequency)
        .t = ((stepCount - autoT0) * dtSim) mod autoPeriod
        if .t < 8
            .ph = 0
        elsif .t < 32
            .ph = (.t - 8) / 24
        elsif .t < 40
            .ph = 1
        else
            .ph = 1 - (.t - 40) / 24
        endif
        .ph = 0.5 - 0.5 * cos(pi * .ph)
        tf[1] = autoFa * exp(.ph * ln(autoFb / autoFa))
        @computeTones
    endif
endproc

# ============================================================
# 3. OPTIONAL AUDIO ANALYSIS (precomputed before the animation)
# ============================================================
soundOK = 0
soundState$ = "no Sound selected"
nWin = 0
procedure analyzeSound: .showProgress
    soundOK = 0
    selectObject: userSound
    .dur = Get total duration
    .nch = Get number of channels
    sndSr = Get sampling frequency
    if .dur < 0.02
        soundState$ = "Sound too short (< 20 ms): no analysis"
    else
        .copy = Copy: "ChladniLab_tmp_sound"
        if .nch > 1
            .mono = Convert to mono
            removeObject: .copy
            .copy = .mono
            Rename: "ChladniLab_tmp_sound"
        endif
        sndRms = Get root-mean-square: 0, 0
        if sndRms = undefined
            sndRms = 0
        endif
        if sndRms < 1e-7
            soundState$ = "Sound is silent (RMS below -140 dB): nothing to excite the plate"
            removeObject: .copy
        else
            .x0 = Get start time
            winDur = min(0.2, .dur)
            if .dur <= winDur + 1e-9
                nWin = 1
                hopDur = winDur
            else
                hopDur = max(0.05, (.dur - winDur) / 299)
                nWin = floor((.dur - winDur) / hopDur + 1e-9) + 1
            endif
            # pass 1: per-window centroid, spread, RMS, total energy
            .cw = 0
            .cwW = 0
            for .w to nWin
                .t1 = .x0 + (.w - 1) * hopDur
                .t2 = .t1 + winDur
                selectObject: .copy
                .part = Extract part: .t1, .t2, "Hanning", 1, "no"
                .rw = Get root-mean-square: 0, 0
                .sp = To Spectrum: "yes"
                .etot = Get band energy: 0, 0
                if .etot > 0
                    .c = Get centre of gravity: 2
                    .s = Get standard deviation: 2
                else
                    .c = 0
                    .s = 0
                endif
                removeObject: .part, .sp
                winRms[.w] = if .rw = undefined then 0 else .rw fi
                winCent[.w] = if .c = undefined then 0 else .c fi
                winSpread[.w] = if .s = undefined then 0 else .s fi
                winEtot[.w] = .etot
                if winCent[.w] > 0
                    .cw = .cw + winCent[.w] * .etot
                    .cwW = .cwW + .etot
                endif
                if .showProgress and .w mod 15 = 0
                    @progress: "Analysing sound (1/2): spectral features", 0.5 * .w / nWin
                endif
            endfor
            if .cwW > 0
                sndCentroid = .cw / .cwW
            else
                sndCentroid = 1000
            endif
            # plate tuning: centroid lands at the middle of the mode bank
            if plate_lowest_resonance_Hz > 0
                fUnit = plate_lowest_resonance_Hz / mb_unit[1]
                tuningNote$ = "lowest resonance set to " + fixed$(plate_lowest_resonance_Hz, 1) + " Hz"
            else
                .mid = mb_unit[round(nModes / 2)]
                fUnit = max(0.5, min(500, sndCentroid / .mid))
                tuningNote$ = "auto-tuned: sound centroid " + fixed$(sndCentroid, 0) + " Hz at mid-bank"
            endif
            @buildModeBank
            # pass 2: energy inside each mode's half-power band
            .nyq = sndSr / 2
            # merged (union) band intervals, so overlapping bands of nearly
            # coincident modes are not counted twice in the capture figure
            .nIv = 0
            for .k to nModes
                .lo = mb_f[.k] * (1 - 1 / (2 * qSound))
                .hi = mb_f[.k] * (1 + 1 / (2 * qSound))
                if .hi < .nyq
                    if .nIv > 0
                        if .lo <= .ivHi[.nIv]
                            .ivHi[.nIv] = max(.ivHi[.nIv], .hi)
                        else
                            .nIv = .nIv + 1
                            .ivLo[.nIv] = .lo
                            .ivHi[.nIv] = .hi
                        endif
                    else
                        .nIv = 1
                        .ivLo[1] = .lo
                        .ivHi[1] = .hi
                    endif
                endif
            endfor
            .eCapt = 0
            .eAll = 0
            winEmodeMax = 0
            wE## = zero## (nWin, nModes)
            for .w to nWin
                .t1 = .x0 + (.w - 1) * hopDur
                .t2 = .t1 + winDur
                selectObject: .copy
                .part = Extract part: .t1, .t2, "Hanning", 1, "no"
                .sp = To Spectrum: "yes"
                .sumW = 0
                for .k to nModes
                    .f = mb_f[.k]
                    .hw = .f / (2 * qSound)
                    if .f + .hw < .nyq
                        .eb = Get band energy: .f - .hw, .f + .hw
                        if .eb = undefined
                            .eb = 0
                        endif
                    else
                        .eb = 0
                    endif
                    wE##[.w, .k] = .eb
                    .sumW = .sumW + .eb
                endfor
                for .iv to .nIv
                    .eb = Get band energy: .ivLo[.iv], .ivHi[.iv]
                    if .eb <> undefined
                        .eCapt = .eCapt + .eb
                    endif
                endfor
                removeObject: .part, .sp
                .eAll = .eAll + winEtot[.w]
                winEmode[.w] = .sumW
                if .sumW > winEmodeMax
                    winEmodeMax = .sumW
                endif
                if .showProgress and .w mod 15 = 0
                    @progress: "Analysing sound (2/2): energy in plate resonance bands", 0.5 + 0.5 * .w / nWin
                endif
            endfor
            removeObject: .copy
            bandCapture = if .eAll > 0 then .eCapt / .eAll else 0 fi
            # (resonance-based weights are formed per window at run time from
            #  wE## and the exciter participation: see @soundWeights)
            .rmsMax = 0
            .cMin = 1e30
            .cMax = 0
            for .w to nWin
                .rmsMax = max(.rmsMax, winRms[.w])
            endfor
            for .w to nWin
                if winRms[.w] > 0.03 * .rmsMax and winCent[.w] > 0
                    .cMin = min(.cMin, winCent[.w])
                    .cMax = max(.cMax, winCent[.w])
                endif
            endfor
            if .cMax <= .cMin
                .cMax = .cMin * 2
            endif
            creK## = zero## (nWin, 2)
            creA## = zero## (nWin, 2)
            creNoise# = zero# (nWin)
            creLevel# = zero# (nWin)
            for .w to nWin
                # creative mapping (artistic): centroid -> mode rank, spread -> blend
                if winRms[.w] > 0.03 * .rmsMax and winCent[.w] > 0
                    .pos = ln(max(.cMin, winCent[.w]) / .cMin) / ln(.cMax / .cMin)
                    .rank = 1 + round(.pos * (nModes * 0.7 - 1))
                    .rank = max(1, min(nModes, .rank))
                    .ratio = winSpread[.w] / winCent[.w]
                    .rank2 = max(1, min(nModes, .rank + 1 + round(4 * .ratio)))
                    .blend = min(0.8, .ratio)
                    creK##[.w, 1] = .rank
                    creK##[.w, 2] = .rank2
                    creA##[.w, 1] = 1 - 0.5 * .blend
                    creA##[.w, 2] = 0.5 * .blend
                    creLevel#[.w] = (winRms[.w] / .rmsMax) ^ 0.7
                    creNoise#[.w] = 0.6 + 2 * .ratio
                endif
            endfor
            soundOK = 1
            if winEmodeMax <= 0
                soundState$ = "no energy inside any plate resonance band"
            else
                soundState$ = "analysed: " + string$(nWin) + " windows, plate bands hold " + fixed$(100 * bandCapture, 1) + " \% of the energy"
            endif
        endif
    endif
endproc

# Resonance-based modal weights of window .w: band energy of mode k times
# its squared participation at the exciter (a sound reaches the plate through
# the exciter; a mode with a node under it is not driven). Top modes >= 1 %.
procedure soundWeights: .w
    .pm = 0
    for .k to nModes
        .pm = max(.pm, modePart[.k])
    endfor
    swN = 0
    if .pm > 0 and winEmodeMax > 0
        for .k to nModes
            .sc[.k] = wE##[.w, .k] * (modePart[.k] / .pm) ^ 2
            .used[.k] = 0
        endfor
        .smax = 0
        for .k to nModes
            .smax = max(.smax, .sc[.k])
        endfor
        .go = 1
        while .go
            .bk = 0
            .bv = 0
            for .k to nModes
                if .used[.k] = 0 and .sc[.k] > .bv
                    .bv = .sc[.k]
                    .bk = .k
                endif
            endfor
            if .bk = 0 or swN >= maxActive or .bv < 0.01 * .smax
                .go = 0
            else
                .used[.bk] = 1
                swN = swN + 1
                swK[swN] = .bk
                swA[swN] = sqrt(.bv / winEmodeMax)
            endif
        endwhile
    endif
endproc

# Apply the sound window for the current audio time (Sound mode)
procedure soundExcitation
    .w = 1 + floor(audioT / hopDur)
    if .w > nWin
        audioT = 0
        .w = 1
    endif
    if .w <> curWin
        curWin = .w
        toneFixed = 1
        if sourceMode = 2
            @soundWeights: .w
            nTones = swN
            for .j to nTones
                nAct[.j] = 1
                actK[.j, 1] = swK[.j]
                actCr[.j, 1] = driveLevel * 1.5 * swA[.j]
                actCi[.j, 1] = 0
            endfor
            noiseLevel = 1
        else
            nTones = 0
            if creLevel#[.w] > 0
                nTones = 2
                for .j to 2
                    nAct[.j] = 1
                    actK[.j, 1] = creK##[.w, .j]
                    actCr[.j, 1] = driveLevel * 1.5 * creLevel#[.w] * creA##[.w, .j]
                    actCi[.j, 1] = 0
                endfor
            endif
            noiseLevel = creNoise#[.w]
        endif
        @computeTones
    endif
endproc

procedure enterSource: .s
    sourceMode = .s
    autoMode = 0
    stepsSinceChange = 0
    if pBandSmooth > 0.45
        transitionFlag = 1
    endif
    if sourceMode = 1
        @applyPreset: presetNo
    else
        # a generic exciter point (not on a symmetry line), so that few modes
        # are silenced by it; click the plate to move it
        driveU = 0.13
        driveV = 0.31
        @computeResponseCurve
        curWin = 0
        @soundExcitation
    endif
endproc

# ============================================================
# 8. RENDERING (Demo window, coordinates in percent, bottom-up)
# ============================================================
procedure plateViewport
    # square in pixels for a 16:9 window, scaled by the aspect ratio r = Ly/Lx
    .hMax = plateAreaY2 - plateAreaY1
    .wMax = .hMax / demoAspect
    if aspect >= 1
        .h = .hMax
        .w = .wMax / aspect
    else
        .w = .wMax
        .h = .hMax * aspect
    endif
    .cx = (plateAreaX1 + plateAreaX2) / 2
    .cy = (plateAreaY1 + plateAreaY2) / 2
    pvx1 = .cx - .w / 2
    pvx2 = .cx + .w / 2
    pvy1 = .cy - .h / 2
    pvy2 = .cy + .h / 2
endproc

procedure progress: .msg$, .frac
    demo Erase all
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: cBg$, 0, 100, 0, 100
    demo Font size: 14
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Colour: cText$
    demo Text: 50, "centre", 56, "half", .msg$
    demo Paint rectangle: cBtn$, 30, 70, 47, 49
    demo Paint rectangle: cAccent$, 30, 30 + 40 * max(0, min(1, .frac)), 47, 49
    demoShow ()
endproc

procedure addButton: .x1, .x2, .y1, .y2, .lab$, .act$
    nBtn = nBtn + 1
    btn_x1[nBtn] = .x1
    btn_x2[nBtn] = .x2
    btn_y1[nBtn] = .y1
    btn_y2[nBtn] = .y2
    btn_lab$[nBtn] = .lab$
    btn_act$[nBtn] = .act$
endproc

procedure defineButtons
    nBtn = 0
    .xa1 = 57.5
    .xa2 = 76.8
    .xb1 = 77.7
    .xb2 = 97
    # 10 rows from y = 42 down to y = 3.6
    .top = 42
    .h = 3.36
    .gap = 0.48
    @addButton: .xa1, .xa2, .top - .h, .top, "Start / Pause", "run"
    @addButton: .xb1, .xb2, .top - .h, .top, "Reset sand", "reset"
    .y = .top - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "◀ Mode", "modeDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Mode ▶", "modeUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Freq −", "freqDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Freq +", "freqUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Drive −", "levelDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Drive +", "levelUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Grains −", "grainsDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Grains +", "grainsUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Mobility −", "mobDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Mobility +", "mobUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Speed −", "speedDown"
    @addButton: .xb1, .xb2, .y - .h, .y, "Speed +", "speedUp"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Nodal lines", "nodal"
    @addButton: .xb1, .xb2, .y - .h, .y, "Vibration field", "field"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Plate model", "model"
    @addButton: .xb1, .xb2, .y - .h, .y, "Source", "source"
    .y = .y - (.h + .gap)
    @addButton: .xa1, .xa2, .y - .h, .y, "Next preset", "preset"
    @addButton: .xb1, .xb2, .y - .h, .y, "Exit", "quit"
    stripX1 = 57.5
    stripX2 = 97
    stripY1 = 45
    stripY2 = 57
endproc

procedure buttonOn: .act$
    buttonOn.v = 0
    if .act$ = "run"
        buttonOn.v = running
    elsif .act$ = "nodal"
        buttonOn.v = showNodal
    elsif .act$ = "field"
        buttonOn.v = showField
    elsif .act$ = "source"
        buttonOn.v = if sourceMode > 1 then 1 else 0 fi
    endif
endproc

procedure render
    frameCount = frameCount + 1
    if gridDirty
        # during automatic sweeps the display grid follows every 3rd frame;
        # the particles always use the exact current field
        if gridThrottle = 0 or frameCount mod 3 = 0
            @updateGrid
        endif
    endif
    @plateViewport
    demo Erase all
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Paint rectangle: cBg$, 0, 100, 0, 100

    # --- plate, optional field, optional nodal overlay ---
    demo Select inner viewport: pvx1, pvx2, pvy1, pvy2
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cPlate$, 0, 1, 0, 1
    if showField and g2Max > 1e-20
        selectObject: gD
        # value 0 (still) -> grey 0.13, value -1 (max) -> grey 0.36
        demo Paint image: 0, 1, 0, 1, -3.78, 0.565
    endif
    if showNodal and g2Max > 1e-20
        selectObject: gS
        demo Colour: cNodal$
        demo Line width: 1
        demo Draw one contour: 0, 1, 0, 1, 0
    endif
    demo Select inner viewport: pvx1, pvx2, pvy1, pvy2
    demo Axes: 0, 1, 0, 1
    demo Colour: cEdge$
    demo Line width: 1.5
    demo Draw rectangle: 0, 1, 0, 1
    demo Line width: 1

    # --- sand: settled grains warm, hopping grains pale ---
    for .i to nPart
        if act#[.i] > 0.35
            demo Paint circle (mm): cSandHop$, px#[.i], py#[.i], dotR * 0.85
        else
            demo Paint circle (mm): cSand$, px#[.i], py#[.i], dotR
        endif
    endfor

    # --- exciter (not used by the creative mapping) ---
    if sourceMode <> 3
        demo Colour: cCopper$
        demo Line width: 2
        demo Draw circle (mm): driveU, driveV, 2.2
        demo Line width: 1
        demo Paint circle (mm): cCopper$, driveU, driveV, 0.7
    endif

    # --- title ---
    demo Font size: 22
    demo Select inner viewport: 57.5, 97, 90.5, 97.5
    demo Axes: 0, 1, 0, 1
    demo Colour: cText$
    demo Text: 0, "left", 0.62, "half", "Chladni Resonance Lab"
    demo Font size: 11
    demo Select inner viewport: 57.5, 97, 90.5, 97.5
    demo Axes: 0, 1, 0, 1
    demo Colour: cDim$
    demo Text: 0, "left", 0.08, "half", "Sound into Patterns  ·  " + qualityName$ + " quality"

    # --- information panel ---
    demo Font size: 10
    demo Select inner viewport: 57.5, 97, 59, 90
    demo Axes: 0, 1, 0, 12
    .ly = 11.4
    demo Colour: cAccent$
    if sourceMode = 1
        .src$ = "Explore  ·  preset " + string$(presetNo) + ": " + presetName$
    elsif sourceMode = 2
        .src$ = "Sound (resonance-based)  ·  " + userSoundName$
    else
        .src$ = "Sound (CREATIVE mapping, artistic)  ·  " + userSoundName$
    endif
    demo Text: 0, "left", .ly, "half", .src$
    .ly = .ly - 1
    demo Colour: cDim$
    if sourceMode = 1
        if presetModified
            demo Text: 0, "left", .ly, "half", "retuned by hand from the preset · dominant mode " + (if domK > 0 then mb_lab$[domK] else "none" fi)
        else
            demo Text: 0, "left", .ly, "half", presetNote$
        endif
    else
        demo Text: 0, "left", .ly, "half", "window " + string$(curWin) + "/" + string$(nWin) + "  ·  audio t = " + fixed$(audioT, 2) + " s  ·  time scale ×" + fixed$(audioRate, 2)
    endif
    .ly = .ly - 1
    demo Colour: cText$
    if plateModel = 1
        .pl$ = "Plate: free square, cosine approximation (illustrative frequencies)"
    else
        .pl$ = "Plate: simply supported, exact Kirchhoff modes, Ly/Lx = " + fixed$(aspect, 2)
    endif
    demo Text: 0, "left", .ly, "half", .pl$
    .ly = .ly - 1
    if sourceMode = 1
        .fs$ = ""
        for .j to nTones
            .fs$ = .fs$ + (if .j > 1 then " + " else "" fi) + fixed$(tf[.j], 1)
        endfor
        @nearestMode: tf[1]
        .auto$ = if autoMode = 1 then "  ·  auto-sweep" else if autoMode = 2 then "  ·  auto-glide" else "" fi fi
        demo Text: 0, "left", .ly, "half", "Drive: " + .fs$ + " Hz  ·  nearest resonance " + mb_lab$[nearestMode.idx] + " " + fixed$(mb_f[nearestMode.idx], 1) + " Hz" + .auto$
    else
        demo Text: 0, "left", .ly, "half", "Plate tuning: " + tuningNote$
    endif
    .ly = .ly - 1
    demo Text: 0, "left", .ly, "half", "Drive level ×" + fixed$(driveLevel, 1) + "  ·  Q " + fixed$(qFactor, 0) + "  ·  peak acceleration Γ = " + fixed$(gammaMax, 1) + " g  (grains hop where Γ > 1)"
    .ly = .ly - 1
    # active modes with energy shares
    .am$ = ""
    .cnt = 0
    for .j to nTones
        for .i to nAct[.j]
            if .cnt < 4 and totShare > 0
                .sh = (actCr[.j, .i] ^ 2 + actCi[.j, .i] ^ 2) / totShare
                if .sh >= 0.01
                    .cnt = .cnt + 1
                    .am$ = .am$ + (if .cnt > 1 then "  " else "" fi) + mb_lab$[actK[.j, .i]] + " " + fixed$(100 * .sh, 0) + "\% "
                endif
            endif
        endfor
    endfor
    if .am$ = ""
        .am$ = "none"
    endif
    demo Text: 0, "left", .ly, "half", "Active modes: " + .am$
    .ly = .ly - 1
    demo Text: 0, "left", .ly, "half", "Grains " + string$(nPart) + "  ·  mobility ×" + fixed$(mobility, 2) + "  ·  noise ×" + fixed$(noiseLevel, 2) + "  ·  speed " + string$(stepsPerFrame) + " steps/frame" + (if running and fpsShown > 0 then "  ·  " + fixed$(fpsShown, 0) + " fps (measured)" else "" fi)
    .ly = .ly - 1
    .rs$ = if running then "running" else if takeEnded then "take finished — Space for the next take" else "paused" fi fi
    demo Text: 0, "left", .ly, "half", "Simulated time " + fixed$(stepCount * dtSim, 1) + " s  (step " + string$(stepCount) + ", model time, not audio)  ·  " + .rs$
    .ly = .ly - 1.25
    demo Font size: 12
    demo Select inner viewport: 57.5, 97, 59, 90
    demo Axes: 0, 1, 0, 12
    demo Colour: cAccent$
    demo Text: 0, "left", .ly, "half", stage$
    .ly = .ly - 1.15
    demo Font size: 10
    demo Select inner viewport: 57.5, 97, 59, 90
    demo Axes: 0, 1, 0, 12
    demo Paint rectangle: cBtn$, 0, 0.55, .ly - 0.22, .ly + 0.22
    demo Paint rectangle: cAccent$, 0, 0.55 * max(0, min(1, pBandSmooth)), .ly - 0.22, .ly + 0.22
    demo Colour: cDim$
    demo Line width: 1
    demo Draw line: 0.55 * bandArea, .ly - 0.35, 0.55 * bandArea, .ly + 0.35
    demo Select inner viewport: 57.5, 97, 59, 90
    demo Axes: 0, 1, 0, 12
    demo Colour: cText$
    demo Text: 0.57, "left", .ly, "half", fixed$(100 * pBandSmooth, 0) + "\%  in quiet band (uniform sand: " + fixed$(100 * bandArea, 0) + "\% )"

    # --- response strip ---
    demo Select inner viewport: stripX1, stripX2, stripY1, stripY2
    demo Axes: 0, 1, 0, 1
    demo Paint rectangle: cPanel$, 0, 1, 0, 1
    .lx1 = log10(respLo)
    .lx2 = log10(respHi)
    demo Axes: .lx1, .lx2, 0, 1.25
    if sourceMode = 1
        demo Colour: "{0.30, 0.29, 0.27}"
        demo Line width: 1
        for .k to nModes
            .lf = log10(mb_f[.k])
            demo Draw line: .lf, 0, .lf, 0.06 + 0.5 * min(2, modePart[.k]) / 2
        endfor
        demo Colour: cAccent$
        demo Line width: 1.5
        for .i from 2 to nRespF
            demo Draw line: respLog#[.i - 1], respR#[.i - 1], respLog#[.i], respR#[.i]
        endfor
        demo Line width: 1
        demo Colour: cCopper$
        demo Line width: 2
        for .j to nTones
            .lf = log10(max(respLo, min(respHi, tf[.j])))
            demo Draw line: .lf, 0, .lf, 1.18
        endfor
        demo Line width: 1
    else
        demo Colour: "{0.30, 0.29, 0.27}"
        for .k to nModes
            .lf = log10(mb_f[.k])
            demo Draw line: .lf, 0, .lf, 0.05
        endfor
        demo Colour: cAccent$
        demo Line width: 3
        for .j to nTones
            .k = actK[.j, 1]
            .h = min(1.15, sqrt(actCr[.j, 1] ^ 2 + actCi[.j, 1] ^ 2) / max(1e-9, 1.5 * driveLevel))
            .lf = log10(mb_f[.k])
            demo Draw line: .lf, 0, .lf, max(0.02, .h)
        endfor
        demo Line width: 1
        # timeline: window RMS and cursor
        demo Colour: cDim$
        .tr = max(1e-12, sndRms * 4)
        for .w from 2 to nWin
            .xa = .lx1 + (.w - 2) / max(1, nWin - 1) * (.lx2 - .lx1)
            .xb = .lx1 + (.w - 1) / max(1, nWin - 1) * (.lx2 - .lx1)
            demo Draw line: .xa, 1.02 + 0.2 * min(1, winRms[.w - 1] / .tr), .xb, 1.02 + 0.2 * min(1, winRms[.w] / .tr)
        endfor
        demo Colour: cCopper$
        .xc = .lx1 + (curWin - 1) / max(1, nWin - 1) * (.lx2 - .lx1)
        demo Line width: 2
        demo Draw line: .xc, 1.0, .xc, 1.25
        demo Line width: 1
    endif
    demo Font size: 9
    demo Select inner viewport: stripX1, stripX2, stripY1, stripY2
    demo Axes: 0, 1, 0, 1
    demo Colour: cDim$
    demo Text: 0.01, "left", 0.9, "half", fixed$(respLo, 0) + " Hz"
    demo Text: 0.99, "right", 0.9, "half", fixed$(respHi, 0) + " Hz"
    if sourceMode = 1
        demo Text: 0.5, "centre", 0.9, "half", "plate response at the exciter (click to tune)"
    else
        demo Text: 0.5, "centre", 0.9, "half", "modal weights of the current window"
    endif

    # --- buttons ---
    demo Font size: 10
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    for .b to nBtn
        @buttonOn: btn_act$[.b]
        .fill$ = if buttonOn.v then cBtnOn$ else cBtn$ fi
        demo Paint rounded rectangle: .fill$, btn_x1[.b], btn_x2[.b], btn_y1[.b], btn_y2[.b], 1.2
    endfor
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    for .b to nBtn
        @buttonOn: btn_act$[.b]
        .tc$ = if buttonOn.v then cAccent$ else cBtnText$ fi
        demo Colour: .tc$
        .lab$ = btn_lab$[.b]
        if btn_act$[.b] = "run"
            if legacyPeek
                .lab$ = if running then "Pause" else "Start" fi
            else
                .lab$ = if running then "Running take…" else "Run " + string$ (takeSeconds) + "-s take" fi
            endif
        endif
        demo Text: (btn_x1[.b] + btn_x2[.b]) / 2, "centre", (btn_y1[.b] + btn_y2[.b]) / 2, "half", .lab$
    endfor
    demo Font size: 8
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demo Colour: cDim$
    if legacyPeek
        demo Text: 57.5, "left", 1.6, "half", "Space · R · ←/→ mode · ↑/↓ freq · e/E drive · g/G grains · m/M mobility · s/S speed · N · F · B · O · P · Q"
    else
        demo Colour: cAccent$
        demo Text: 57.5, "left", 1.6, "half", "Praat " + praatVersion$ + ": runs in " + string$ (takeSeconds) + "-s takes (Space = next take, hold to chain) · keys act between takes · Q quits"
        demo Colour: cDim$
    endif
    if userSound = 0
        demo Text: 2.5, "left", 1.6, "half", "Click the plate to move the exciter. " + selectionNote$
    else
        demo Text: 2.5, "left", 1.6, "half", "Click the plate to move the exciter. Sound: " + soundState$
    endif
    # leave the window in percent coordinates for click handling
    demo Select inner viewport: 0, 100, 0, 100
    demo Axes: 0, 100, 0, 100
    demoShow ()
endproc

# ============================================================
# 9. USER INPUT HANDLING
# ============================================================
procedure doAction: .a$
    if .a$ = "run"
        running = 1 - running
    elsif .a$ = "reset"
        @randomParticles: nPart
        stepCount = 0
        stepsSinceChange = 0
        pBandSmooth = 0
        transitionFlag = 0
        audioT = 0
        autoT0 = 0
    elsif .a$ = "modeUp" or .a$ = "modeDown"
        if sourceMode = 1
            autoMode = 0
            @nearestMode: tf[1]
            .k = nearestMode.idx
            if .a$ = "modeUp"
                if mb_f[.k] <= tf[1] * 1.0005
                    .k = .k + 1
                endif
            else
                if mb_f[.k] >= tf[1] / 1.0005
                    .k = .k - 1
                endif
            endif
            # skip resonances the exciter cannot drive (it sits on their node):
            # participation below 10 % of the strongest mode at this point
            .pm = 0
            for .q to nModes
                .pm = max(.pm, modePart[.q])
            endfor
            .stepDir = if .a$ = "modeUp" then 1 else -1 fi
            .go = 1
            while .go
                if .k < 1 or .k > nModes
                    .go = 0
                elsif modePart[.k] >= 0.1 * .pm
                    .go = 0
                else
                    .k = .k + .stepDir
                endif
            endwhile
            .k = max(1, min(nModes, .k))
            tf[1] = mb_f[.k]
            presetModified = 1
            @excitationChanged
        endif
    elsif .a$ = "freqUp" or .a$ = "freqDown"
        if sourceMode = 1
            autoMode = 0
            .fac = if .a$ = "freqUp" then 2 ^ (1 / 24) else 2 ^ (-1 / 24) fi
            for .j to nTones
                tf[.j] = max(respLo, min(respHi, tf[.j] * .fac))
            endfor
            presetModified = 1
            @excitationChanged
        endif
    elsif .a$ = "levelUp" or .a$ = "levelDown"
        .fac = if .a$ = "levelUp" then 1.25 else 0.8 fi
        driveLevel = max(0.1, min(40, driveLevel * .fac))
        if sourceMode = 1
            @excitationChanged
        else
            curWin = 0
            @soundExcitation
        endif
    elsif .a$ = "grainsUp"
        @resizeParticles: nPart * 1.25
    elsif .a$ = "grainsDown"
        @resizeParticles: nPart * 0.8
    elsif .a$ = "mobUp"
        mobility = min(5, mobility * 1.25)
    elsif .a$ = "mobDown"
        mobility = max(0.1, mobility * 0.8)
    elsif .a$ = "speedUp"
        stepsPerFrame = min(8, stepsPerFrame + 1)
    elsif .a$ = "speedDown"
        stepsPerFrame = max(1, stepsPerFrame - 1)
    elsif .a$ = "nodal"
        showNodal = 1 - showNodal
    elsif .a$ = "field"
        showField = 1 - showField
    elsif .a$ = "model"
        plateModel = 3 - plateModel
        if plateModel = 1
            aspect = 1
        endif
        .f1 = tf[1]
        @buildModeBank
        if sourceMode > 1 and userSound > 0
            @analyzeSound: 1
            @computeResponseCurve
            curWin = 0
            @soundExcitation
        else
            autoMode = 0
            tf[1] = .f1
            presetModified = 1
            @excitationChanged
        endif
    elsif .a$ = "source"
        if soundOK
            .ns = sourceMode + 1
            if .ns > 3
                .ns = 1
            endif
            @enterSource: .ns
        endif
    elsif .a$ = "preset" or .a$ = "presetBack"
        .p = presetNo + (if .a$ = "preset" then 1 else -1 fi)
        if .p > 10
            .p = 1
        endif
        if .p < 1
            .p = 10
        endif
        sourceMode = 1
        @applyPreset: .p
        @sprinkle: presetSprinkle
    elsif .a$ = "audioFaster"
        audioRate = min(2, audioRate * 2)
    elsif .a$ = "audioSlower"
        audioRate = max(0.0625, audioRate / 2)
    elsif .a$ = "quit"
        quit = 1
    endif
endproc

procedure handleInput
    if demoClicked ()
        .cx = demoX ()
        .cy = demoY ()
        .hit = 0
        for .b to nBtn
            if .cx >= btn_x1[.b] and .cx <= btn_x2[.b] and .cy >= btn_y1[.b] and .cy <= btn_y2[.b]
                .hit = .b
            endif
        endfor
        if .hit > 0
            @doAction: btn_act$[.hit]
        elsif .cx >= pvx1 and .cx <= pvx2 and .cy >= pvy1 and .cy <= pvy2 and sourceMode <> 3
            driveU = max(0.005, min(0.995, (.cx - pvx1) / (pvx2 - pvx1)))
            driveV = max(0.005, min(0.995, (.cy - pvy1) / (pvy2 - pvy1)))
            if sourceMode = 1
                presetModified = 1
                @excitationChanged
            else
                if pBandSmooth > 0.45
                    transitionFlag = 1
                endif
                stepsSinceChange = 0
                @computeResponseCurve
                curWin = 0
                @soundExcitation
            endif
        elsif .cx >= stripX1 and .cx <= stripX2 and .cy >= stripY1 and .cy <= stripY2 and sourceMode = 1
            .lf = log10(respLo) + (.cx - stripX1) / (stripX2 - stripX1) * (log10(respHi) - log10(respLo))
            autoMode = 0
            .r = 10 ^ .lf / tf[1]
            for .j to nTones
                tf[.j] = tf[.j] * .r
            endfor
            presetModified = 1
            @excitationChanged
        endif
    elsif demoKeyPressed ()
        .k$ = demoKey$ ()
        .u = unicode (.k$)
        if .k$ = " "
            @doAction: "run"
        elsif .k$ = "r" or .k$ = "R"
            @doAction: "reset"
        elsif .u = 8594
            @doAction: "modeUp"
        elsif .u = 8592
            @doAction: "modeDown"
        elsif .u = 8593
            @doAction: "freqUp"
        elsif .u = 8595
            @doAction: "freqDown"
        elsif .k$ = "E"
            @doAction: "levelUp"
        elsif .k$ = "e"
            @doAction: "levelDown"
        elsif .k$ = "G"
            @doAction: "grainsUp"
        elsif .k$ = "g"
            @doAction: "grainsDown"
        elsif .k$ = "M"
            @doAction: "mobUp"
        elsif .k$ = "m"
            @doAction: "mobDown"
        elsif .k$ = "S"
            @doAction: "speedUp"
        elsif .k$ = "s"
            @doAction: "speedDown"
        elsif .k$ = "n" or .k$ = "N"
            @doAction: "nodal"
        elsif .k$ = "f" or .k$ = "F"
            @doAction: "field"
        elsif .k$ = "b" or .k$ = "B"
            @doAction: "model"
        elsif .k$ = "o" or .k$ = "O"
            @doAction: "source"
        elsif .k$ = "P"
            @doAction: "preset"
        elsif .k$ = "p"
            @doAction: "presetBack"
        elsif .k$ = "."
            @doAction: "audioFaster"
        elsif .k$ = ","
            @doAction: "audioSlower"
        elsif .k$ = "q" or .k$ = "Q" or .u = 27
            @doAction: "quit"
        endif
    endif
endproc

# ============================================================
# 4./5./6. INITIALISATION (modal parameters, field, particles)
# ============================================================
plateModel = 0
aspect = 0
nModes = 0
fUnit = 40
qSound = 30
tuningNote$ = "fixed"
if plate_lowest_resonance_Hz > 0
    # lowest mode of model A is (1,1) with unit 2
    fUnit = plate_lowest_resonance_Hz / 2
    tuningNote$ = "lowest resonance set to " + fixed$(plate_lowest_resonance_Hz, 1) + " Hz"
endif
stepCount = 0
stepsSinceChange = 0
pBand = 0
pBandSmooth = 0
transitionFlag = 0
gridDirty = 1
g2Max = 0
gammaMax = 0
bandArea = 1
nodalByZero = 1
sourceMode = 1
curWin = 0
audioT = 0
autoMode = 0
autoT0 = 0
running = 0
quit = 0
showNodal = 0
showField = 0
stepsPerFrame = 2
takeEnded = 0
legacyPeek = praatVersion < 6458
takeSeconds = 3
fpsShown = 0
sprinkled = 0
frameCount = 0
gridThrottle = 0
totShare = 0
stage$ = ""
presetNo = start_preset
presetModified = 0
toneFixed = 0
nTones = 1
tf[1] = 100
ta[1] = 1
driveU = 0.2
driveV = 0.2

@createGrids
@applyPreset: start_preset
@randomParticles: nPartDefault
@updateGrid

# ============================================================
# DIAGNOSTIC SELF-TEST (no Demo window)
# ============================================================
if diagnostic_self_test
    random_initializeWithSeedUnsafelyButPredictably (2026)
    clearinfo
    appendInfoLine: "=============================================="
    appendInfoLine: "  CHLADNI RESONANCE LAB v1.2 — DIAGNOSTIC SELF-TEST"
    appendInfoLine: "=============================================="
    appendInfoLine: "Quality ", qualityName$, " | grid ", nGrid, " | max active modes ", maxActive, " | mode bank m <= ", mMax
    appendInfoLine: ""
    nFailST = 0
    nStepsST = 500
    @resizeParticles: 1200
    appendInfoLine: "Preset                      steps  Γmax   band area  in band  ratio  bounds  finite  pass"
    for p to 10
        @applyPreset: p
        @randomParticles: 1200
        stepCount = 0
        stopwatch
        for s to nStepsST
            @autoFrequency
            if gridDirty
                @updateGrid
            endif
            @simStep
        endfor
        tSteps = stopwatch
        @updateGrid
        @exactBandShare
        ratio = exactBandShare.p / max(1e-9, bandArea)
        bx1 = min (px#)
        bx2 = max (px#)
        by1 = min (py#)
        by2 = max (py#)
        okB = bx1 >= 0 and bx2 <= 1 and by1 >= 0 and by2 <= 1
        okF = mean (px#) <> undefined and mean (py#) <> undefined
        # presets that keep moving by design (sweep, glide, overdrive) get a lower bar
        need = if p = 6 or p = 7 or p = 8 then 1.5 else 3 fi
        okP = ratio >= need and okB and okF
        if okP = 0
            nFailST = nFailST + 1
        endif
        # density histogram (8 x 8) for the distinctness check
        for c to 64
            hist[p, c] = 0
        endfor
        for i to nPart
            ci = 1 + min(7, floor(px#[i] * 8)) + 8 * min(7, floor(py#[i] * 8))
            hist[p, ci] = hist[p, ci] + 1 / nPart
        endfor
        stepsPerSec[p] = nStepsST / tSteps
        appendInfoLine: right$("  " + string$(p), 2), " ", left$(presetName$ + "                         ", 25), " ", nStepsST, "  ", fixed$(gammaMax, 1), "   ", fixed$(100 * bandArea, 1), " %      ", fixed$(100 * exactBandShare.p, 1), " %    ", fixed$(ratio, 1), "    ", if okB then "ok" else "OUT" fi, "     ", if okF then "ok" else "NaN" fi, "     ", if okP then "PASS" else "FAIL" fi
    endfor
    # distinctness: smallest L1 distance between preset density maps
    dMin = 99
    for a to 9
        for b from a + 1 to 10
            d = 0
            for c to 64
                d = d + abs(hist[a, c] - hist[b, c])
            endfor
            if d < dMin
                dMin = d
                dA = a
                dB = b
            endif
        endfor
    endfor
    appendInfoLine: ""
    appendInfoLine: "Distinctness: smallest L1 distance between final density maps = ", fixed$(dMin, 3), " (presets ", dA, " and ", dB, "; 0 = identical, 2 = disjoint)"

    # transitions: a MODE change (next resonance) must not move any grain;
    # a PRESET change moves no grain (presetSprinkle = 0) and must not touch
    # the audio time scale
    @applyPreset: 1
    @randomParticles: 1200
    for s to 300
        @simStep
    endfor
    keepX# = px#
    keepY# = py#
    @doAction: "modeUp"
    @updateGrid
    dJump = max (abs# (px# - keepX#)) + max (abs# (py# - keepY#))
    newMode$ = mb_lab$[domK]
    maxStep = 0
    for s to 400
        prevX# = px#
        prevY# = py#
        @simStep
        st = max (abs# (px# - prevX#))
        maxStep = max(maxStep, st)
    endfor
    @exactBandShare
    ratioT = exactBandShare.p / max(1e-9, bandArea)
    okT = dJump = 0 and ratioT >= 3 and maxStep < 0.05
    if okT = 0
        nFailST = nFailST + 1
    endif
    appendInfoLine: "Mode change (1,1) -> ", newMode$, ": grains moved by the switch ", fixed$(dJump, 6), ", largest step ", fixed$(maxStep, 4), " plate widths, new ratio ", fixed$(ratioT, 1), "  ", if okT then "PASS" else "FAIL" fi
    keepX# = px#
    keepY# = py#
    keepRate = audioRate
    @doAction: "preset"
    nMoved = 0
    for i to nPart
        if px#[i] <> keepX#[i] or py#[i] <> keepY#[i]
            nMoved = nMoved + 1
        endif
    endfor
    okS2 = abs(nMoved / nPart - presetSprinkle) < 0.06 and audioRate = keepRate
    if okS2 = 0
        nFailST = nFailST + 1
    endif
    appendInfoLine: "Preset change: grains moved ", fixed$(100 * nMoved / nPart, 1), " % (target ", fixed$(100 * presetSprinkle, 0), " %), audio time scale ", fixed$(keepRate, 4), " -> ", fixed$(audioRate, 4), "  ", if okS2 then "PASS" else "FAIL" fi
    @doAction: "audioFaster"
    rFast = audioRate
    @doAction: "audioSlower"
    rBack = audioRate
    okAR = abs(rFast - 2 * keepRate) < 1e-12 and abs(rBack - keepRate) < 1e-12
    if okAR = 0
        nFailST = nFailST + 1
    endif
    appendInfoLine: "Audio time scale keys: . ", fixed$(keepRate, 4), " -> ", fixed$(rFast, 4), ", then , -> ", fixed$(rBack, 4), "  ", if okAR then "PASS" else "FAIL" fi

    # sound-driven checks (synthetic material made here, removed afterwards)
    appendInfoLine: ""
    appendInfoLine: "Sound mapping (synthetic test sounds):"
    @applyPreset: 1
    keepUser = userSound
    keepName$ = userSoundName$
    # two well-isolated modes (nearest neighbour >= 6 % away) in the lower bank
    k1 = 0
    k2 = 0
    for k from 2 to nModes - 1
        iso = min(mb_f[k] / mb_f[k - 1], mb_f[k + 1] / mb_f[k])
        if iso >= 1.06 and mb_f[k] > 2 * mb_f[1]
            if k1 = 0
                k1 = k
            elsif k2 = 0 and mb_f[k] > 1.5 * mb_f[k1]
                k2 = k
            endif
        endif
    endfor
    f1 = mb_f[k1]
    f2 = mb_f[k2]
    for tcase to 5
        if tcase = 1
            tName$ = "two partials at the " + mb_lab$[k1] + " and " + mb_lab$[k2] + " resonances, mono"
            userSound = Create Sound from formula: "ChladniLab_test", 1, 0, 1.5, 44100, "0.3 * sin(2*pi*f1*x) + 0.2 * sin(2*pi*f2*x)"
        elsif tcase = 2
            tName$ = "same, stereo with different channel levels"
            userSound = Create Sound from formula: "ChladniLab_test", 2, 0, 1.5, 44100, "(if row = 1 then 0.3 else 0.1 fi) * sin(2*pi*f1*x) + 0.2 * sin(2*pi*f2*x)"
        elsif tcase = 3
            tName$ = "same at -80 dB (low amplitude)"
            userSound = Create Sound from formula: "ChladniLab_test", 1, 0, 1.5, 44100, "0.0001 * (0.3 * sin(2*pi*f1*x) + 0.2 * sin(2*pi*f2*x))"
        elsif tcase = 4
            tName$ = "digital silence"
            userSound = Create Sound from formula: "ChladniLab_test", 1, 0, 1.0, 44100, "0"
        else
            tName$ = "very short (15 ms)"
            userSound = Create Sound from formula: "ChladniLab_test", 1, 0, 0.015, 44100, "0.3 * sin(2*pi*f1*x)"
        endif
        userSoundName$ = "ChladniLab_test"
        # fixed tuning so the partials sit on known resonances
        keepPl = plate_lowest_resonance_Hz
        plate_lowest_resonance_Hz = mb_f[1]
        @analyzeSound: 0
        plate_lowest_resonance_Hz = keepPl
        removeObject: userSound
        res$ = soundState$
        okS = 1
        if tcase <= 3
            if soundOK = 0
                okS = 0
            else
                driveU = 0.04
                driveV = 0.04
                @computeResponseCurve
                w = round(nWin / 2)
                @soundWeights: w
                top1 = swK[1]
                top2 = swK[2]
                hit = (top1 = k1 and top2 = k2) or (top1 = k2 and top2 = k1)
                res$ = "top modes " + mb_lab$[top1] + ", " + mb_lab$[top2] + "; bands hold " + fixed$(100 * bandCapture, 1) + " %"
                okS = hit
            endif
        elsif tcase = 4
            okS = soundOK = 0 and index(soundState$, "silent") > 0
        else
            okS = soundOK = 0 and index(soundState$, "short") > 0
        endif
        if okS = 0
            nFailST = nFailST + 1
        endif
        appendInfoLine: "  ", tName$, ": ", res$, "  ", if okS then "PASS" else "FAIL" fi
    endfor
    userSound = keepUser
    userSoundName$ = keepName$
    soundOK = 0

    # timing
    @applyPreset: 2
    @resizeParticles: nPartDefault
    stopwatch
    for s to 200
        @simStep
    endfor
    tq = stopwatch
    appendInfoLine: ""
    appendInfoLine: "Simulation cost (", qualityName$, ", ", nPart, " grains, ", nTones, " tone): ", fixed$(1000 * tq / 200, 2), " ms per step (drawing is measured separately in the Demo window)"
    appendInfoLine: ""
    appendInfoLine: "SELF-TEST ", if nFailST = 0 then "PASSED" else "FAILED (" + string$(nFailST) + ")" fi
    removeObject: gUr, gUi, gG2, gS, gD
    if userSound > 0
        selectObject: userSound
    endif
    exitScript ()
endif

# ============================================================
# SOUND ANALYSIS (before the animation)
# ============================================================
if userSound > 0
    nocheck demoWindowTitle: "Chladni Resonance Lab — Sound into Patterns"
    @analyzeSound: 1
    if soundOK
        @computeResponseCurve
    endif
endif

# ============================================================
# MAIN LOOP
# ============================================================
nocheck demoWindowTitle: "Chladni Resonance Lab — Sound into Patterns"
@defineButtons
@updateStage
if soundOK
    # start with the Sound, in the mapping chosen in the form; the Source
    # button / O key cycles Explore -> Sound (resonance) -> Sound (creative)
    @enterSource: 1 + sound_mapping
endif
@render
fpsShown = 0
stopwatch
# Input model. Praat 6.4.58 (Jan 2026) introduced halt/resume scripting for
# the Demo window. Since then, a click or key that arrives DURING
# demoPeekInput() re-runs the script from inside the event callback: the
# input is lost, the animation continues one level deeper, and closing the
# window or unwinding trips an internal assertion (crash). Reproduced on 7.0;
# unchanged in the October 2026 sources. Therefore:
#   Praat < 6.4.58  : continuous running, input polled with demoPeekInput().
#   Praat >= 6.4.58 : demoPeekInput() is never called while animating. Running
#     happens in TAKES of takeSeconds wall time, after which the lab pauses
#     and waits with demoWaitForInput() (safe). Keys pressed during a take are
#     handled when it ends (Windows queues them); on Linux, demoShow() already
#     delivers them safely and they are handled at once. Takes stay below the
#     5 s after which Windows marks a window "Not responding".
legacyPeek = praatVersion < 6458
takeSeconds = 3
lastSig$ = ""
procedure inputSignature
    if demoClicked ()
        inputSignature.s$ = "C" + fixed$ (demoX (), 4) + "/" + fixed$ (demoY (), 4)
    elsif demoKeyPressed ()
        inputSignature.s$ = "K" + demoKey$ ()
    else
        inputSignature.s$ = ""
    endif
endproc

while quit = 0
    if running and legacyPeek = 0
        # ---- one take: animate without polling ----
        @inputSignature
        lastSig$ = inputSignature.s$
        tTake = 0
        takeActive = 1
        .dtw = stopwatch
        while takeActive
            for s to stepsPerFrame
                if sourceMode = 1
                    @autoFrequency
                else
                    audioT = audioT + dtSim * audioRate
                    @soundExcitation
                endif
                @simStep
            endfor
            @orderParameter
            gridThrottle = if autoMode > 0 and sourceMode = 1 then 1 else 0 fi
            @updateStage
            @render
            .dtw = stopwatch
            if .dtw > 0
                fpsShown = if fpsShown = 0 then 1 / .dtw else 0.9 * fpsShown + 0.1 / .dtw fi
            endif
            tTake = tTake + .dtw
            # input delivered safely by demoShow (Linux): handle new events now
            @inputSignature
            if inputSignature.s$ <> "" and inputSignature.s$ <> lastSig$
                lastSig$ = inputSignature.s$
                @handleInput
                if quit or running = 0
                    takeActive = 0
                endif
            endif
            if tTake >= takeSeconds
                takeActive = 0
            endif
        endwhile
        # ---- end of take: pause and wait safely ----
        if quit = 0
            running = 0
            takeEnded = 1
            gridThrottle = 0
            @updateStage
            @render
            if demoWaitForInput ()
                @handleInput
            endif
            takeEnded = 0
            .dtw = stopwatch
        endif
    else
        if running
            for s to stepsPerFrame
                if sourceMode = 1
                    @autoFrequency
                else
                    audioT = audioT + dtSim * audioRate
                    @soundExcitation
                endif
                @simStep
            endfor
            @orderParameter
        endif
        gridThrottle = if running and autoMode > 0 and sourceMode = 1 then 1 else 0 fi
        @updateStage
        @render
        # measured frame rate (wall clock, smoothed); only meaningful while running
        .dtw = stopwatch
        if running and .dtw > 0
            fpsShown = if fpsShown = 0 then 1 / .dtw else 0.9 * fpsShown + 0.1 / .dtw fi
        endif
        if running
            # legacy Praat only (< 6.4.58)
            if demoPeekInput ()
                @handleInput
            endif
        else
            if demoWaitForInput ()
                @handleInput
            endif
            # restart the clock so waiting time is not counted as a slow frame
            .dtw = stopwatch
        endif
    endif
endwhile

# ============================================================
# 11. CLEANUP
# ============================================================
removeObject: gUr, gUi, gG2, gS, gD
demo Erase all
demo Select inner viewport: 0, 100, 0, 100
demo Axes: 0, 100, 0, 100
demo Paint rectangle: cBg$, 0, 100, 0, 100
demo Font size: 16
demo Select inner viewport: 0, 100, 0, 100
demo Axes: 0, 100, 0, 100
demo Colour: cText$
demo Text: 50, "centre", 54, "half", "Chladni Resonance Lab — session ended"
demo Font size: 11
demo Select inner viewport: 0, 100, 0, 100
demo Axes: 0, 100, 0, 100
demo Colour: cDim$
demo Text: 50, "centre", 47, "half", fixed$(stepCount * dtSim, 1) + " s of simulated time · " + string$(nPart) + " grains · you can close this window"
demoShow ()
if userSound > 0
    selectObject: userSound
endif
