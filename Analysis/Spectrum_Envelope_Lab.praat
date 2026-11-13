# ============================================================
# Praat AudioTools - Spectrum & Envelope Lab
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 1.1.1 (2026)
# License: MIT License
# Category: Analysis
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Pedagogical comparison of measured spectra, harmonic peaks,
#   peak-based spectral envelopes, and cepstral smoothing.
#
# Usage:
#   Select one Sound for single-window or within-sound analysis
#   (modes A, B, D). Select two Sounds for cross-sound spectral
#   comparison (mode C; Sound A is the one higher in the Objects list).
#   Window start times are seconds from the
#   start of each Sound; duration 0 means "to the end of the Sound".
#     A  Single spectrum / envelope   - Window A of the Sound
#     B  Two windows in one Sound     - Windows A and B (both durations 0
#                                       = automatic attack / middle windows)
#     C  Two selected Sounds          - Window A of Sound 1, Window B of Sound 2
#     D  FFT window laboratory        - 10/40/160/640 ms Hann windows centred
#                                       on Window A (whole Sound: its midpoint)
#
# Outputs:
#   Praat Picture visualization, optional compact results Table, and an
#   Info-window summary. In modes A-C the Info window also carries a
#   Harmonic Components Report per window: H1-H10 in harmonic order with
#   expected frequency (n x F0), measured frequency and level of the
#   validated peak (sine-calibrated dBFS), level relative to the strongest
#   measured component, deviation in cents from the ideal harmonic series,
#   and status Validated / Missing / Out of range /
#   Unavailable. It is printed whatever the drawing and Table settings.
#   No audio is produced and the selected Sounds are never modified.
#
# Methodological notes and limitations:
#   Spectrum   One FFT per window: the window is multiplied by a Hann
#              window, zero-padded by Praat to a power of two, and shown as
#              an amplitude spectrum calibrated so that a sinusoid of
#              amplitude A reads 20*log10(A) dBFS (|X| * 4 / T, Hann coherent
#              gain 0.5) in every window length. This is not dB SPL and not a
#              density: broadband noise reads lower in longer windows.
#              Zero-padding interpolates the curve; it does not improve
#              resolution (Hann -3 dB width = 1.44 / T).
#   Channels   Multichannel Sounds are analysed on their strongest-RMS
#              channel (never a mono sum, which can cancel opposite-phase
#              channels). The channel is reported.
#   F0         Either user-specified, or the median of a Praat Pitch
#              analysis of the same window, accepted only when at least half
#              the frames are voiced and the 10-90 % spread is <= 2 semitones;
#              an automatic F0 is then refined from the validated peaks
#              (least squares through the origin).
#   Expected harmonic k*F0 is a POSITION. A measured peak is a local spectral
#              maximum within +/- tolerance*F0 of it that is not at the edge
#              of the search band, stands out from both neighbouring minima by
#              the prominence threshold (6 dB), lies the floor margin (15 dB)
#              above the median spectral level and within 80 dB of the
#              strongest component, and has a Hann-shaped main lobe (within
#              6 dB of the peak at +/-0.6 / T), which rejects window
#              sidelobes. The search centre follows the last
#              validated peak (+/-5 %) so harmonic numbering survives a
#              slightly wrong F0. An automatic F0 whose odd harmonics are all
#              missing is doubled (octave check). Expected harmonics without such a peak
#              are reported as missing; nothing is interpolated into them.
#              Harmonic tests need F0 >= 4 / T (resolved Hann main lobes).
#              The harmonic PATTERN is reported as "consistent" with k * F0
#              when >= 3 validated peaks cover >= 30 % of the first 10
#              expected harmonics, "inconclusive" with fewer, "not found"
#              with none. This is a heuristic, not proof of a single
#              harmonic source: inharmonic or polyphonic peaks can coincide
#              with multiples of an estimated F0. An octave-corrected F0 is a
#              periodicity estimate, not necessarily the perceived pitch.
#   Envelopes  Peak-derived: straight lines between validated peaks only
#              (dotted across gaps of more than one missing harmonic, no
#              extrapolation). Cepstral: Praat "Cepstral smoothing", which
#              lifters the log spectrum and therefore keeps its log-average
#              level: on a line spectrum it runs between peaks and valleys,
#              not over the peaks. That gap is a genuine property of the
#              method. An optional display-only alignment exists in the
#              advanced settings and is labelled as such. Neither envelope is
#              a formant measurement.
#   Levels     "Absolute" keeps every curve on the common sine-calibrated
#              dBFS scale; "Peak-normalized shape" sets each window's own
#              maximum to 0 dB, so only shapes are compared.
#
# Changelog:
#   v1.1.1 (2026) - Report gains a Deviation (cents) column:
#     1200 x log2 (measured / (n x F0)), deviation from the ideal harmonic
#     series (not equal temperament), with a note naming the F0 it refers
#     to (fitted, user-specified or Pitch median).
#   v1.1.0 (2026) - Harmonic Components Report in the Info window (modes
#     A, B, C; not in D). Reads the existing validation arrays; no new
#     detector, no form fields, no objects. Levels are independent of the
#     Peak-normalized display option.
#   v1.0.4 (2026) - Review round 4.
#     - FFT lab: the peak search range is checked before use (Praat searches
#       the whole Sound when a range is inverted); a display band too narrow
#       for a measurement is reported and the zoom stays inside it.
#     - Findings: the "... (see Info)" line is measured as a whole.
#   v1.0.3 (2026) - Review round 3.
#     - FFT lab: peak prominence compared on one scale (the floor is shifted
#       with the curves in Peak-normalized mode); the reference peak must be
#       an interior local maximum, not a value at the display edge.
#     - Findings / metadata text fitting: words or strings too wide for a
#       line are cut by measured width; iteration limits on every loop.
#     - Verified-peaks display with no validated peak shows the measured
#       spectrum in grey and says so.
#   v1.0.2 (2026) - Review round 2.
#     - Removed the start-of-run deletion of objects named SELab_tmp (it
#       could delete user objects); cleanup is by tracked ID only.
#     - Every expected failure after the first temporary object is created
#       goes through @fail, which removes the tracked objects.
#     - Findings strip: three zones (finding, finding, cue) wrapped by the
#       measured text width; the cue line is never dropped.
#     - FFT lab: title counts the windows actually used; the zoom component
#       and band respect the display range; a broadened -6 dB width is
#       reported as a peak width, not as a single main lobe.
#   v1.0.1 (2026) - Review round 1.
#     - FFT size guaranteed <= 2^21 points (windows limited to 2^21 samples).
#     - FFT lab reports a -6 dB width only for a tonal component and labels
#       broadened / non-isolated lobes; Table column Width_6dB_status.
#     - Automatic attack / middle windows use the analysed channel.
#     - Findings strip word-wrapped (max five lines).
#     - "Harmonic pattern consistent / inconclusive / not found" replaces
#       "model supported / weak / rejected"; first-10 coverage reported.
#     - Minimum frequency (display only) restored from the original script.
#     - Temporary objects named SELab_tmp. Dense k x F0 marks are hidden.
#   v1.0.0 (2026) - New Analysis script derived from Spectrum_draw.praat.
#     - Hann-windowed, sine-calibrated spectra instead of an unwindowed
#       whole-file FFT labelled "Sound pressure level (dB/Hz)".
#     - Harmonic peaks validated by local-maximum, prominence and floor
#       tests; missing harmonics are shown as missing instead of counting
#       the maximum of every band as a harmonic.
#     - Cepstral envelope no longer silently shifted to the spectrum maximum.
#     - Four modes (single, two windows, two Sounds, FFT window lab),
#       strongest-RMS channel rule, Nyquist-safe frequency range,
#       tracked temporary objects, optional results Table.
#
# Citation:
#   Cohen, S. (2026). Praat AudioTools.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

form Spectrum Envelope Lab v1.1.1
	optionmenu Analysis_mode 1
		option A. Single spectrum / envelope
		option B. Compare two windows in one Sound
		option C. Compare two selected Sounds
		option D. FFT window laboratory
	comment Windows: seconds from the Sound start (duration 0 = to the end)
	real Window_A_start_(s) 0
	real Window_A_duration_(s) 0
	real Window_B_start_(s) 0
	real Window_B_duration_(s) 0
	optionmenu Spectrum_display 3
		option Continuous measured spectrum
		option Verified harmonic peaks
		option Spectrum plus harmonic markers
	optionmenu Envelope 4
		option No envelope
		option Peak-derived envelope
		option Cepstral envelope
		option Both envelopes
	optionmenu Level_scale 1
		option Absolute (sine-calibrated dBFS)
		option Peak-normalized shape
	real Fundamental_frequency_(Hz,_0_=_auto) 0
	positive Cepstral_smoothing_(Hz) 300
	real Minimum_frequency_(Hz) 0
	positive Maximum_frequency_(Hz) 8000
	positive Dynamic_range_(dB) 70
	boolean Draw_visualization 1
	boolean Create_results_table 0
	boolean Advanced_settings 0
endform

# ---------------- Advanced settings (second dialog) ----------------
pitch_floor = 50
pitch_ceiling = 1500
peak_prominence = 6
floor_margin = 15
validation_range = 80
harmonic_tolerance = 0.2
align_cepstral_display = 0
if advanced_settings
	beginPause: "Spectrum Envelope Lab - advanced settings"
		comment: "Automatic F0 (Praat Pitch, median of the analysis window)"
		positive: "Pitch floor (Hz)", string$ (pitch_floor)
		positive: "Pitch ceiling (Hz)", string$ (pitch_ceiling)
		comment: "Harmonic peak validation"
		positive: "Peak prominence (dB)", string$ (peak_prominence)
		positive: "Floor margin (dB)", string$ (floor_margin)
		positive: "Harmonic tolerance (x F0)", string$ (harmonic_tolerance)
		comment: "Display only (does not change any measurement)"
		boolean: "Align cepstral display", align_cepstral_display
	endPause: "Continue", 1
endif

# ---------------- Constants and state ----------------
nTrack = 0
maxHarm = 400
colA$ = "{0.20, 0.40, 0.80}"
colB$ = "{0.80, 0.25, 0.20}"
colPeakEnv$ = "{0.20, 0.55, 0.30}"
colCep$ = "{0.80, 0.25, 0.20}"
colSpec$ = "{0.45, 0.45, 0.50}"
colContext$ = "{0.82, 0.82, 0.84}"
colTick$ = "{0.55, 0.55, 0.55}"
colMiss$ = "{0.90, 0.55, 0.10}"
colD$[1] = "{0.60, 0.60, 0.60}"
colD$[2] = "{0.20, 0.40, 0.80}"
colD$[3] = "{0.20, 0.55, 0.30}"
colD$[4] = "{0.80, 0.25, 0.20}"

# ---------------- Validation of form values ----------------
mode = analysis_mode
modeName$ [1] = "A  Single spectrum / envelope"
modeName$ [2] = "B  Two windows in one Sound"
modeName$ [3] = "C  Two selected Sounds"
modeName$ [4] = "D  FFT window laboratory"
if window_A_start < 0 or window_B_start < 0 or window_A_duration < 0 or window_B_duration < 0
	exitScript: "Window start times and durations must be zero or positive."
endif
if maximum_frequency < 100
	exitScript: "Maximum frequency must be at least 100 Hz."
endif
if minimum_frequency < 0 or minimum_frequency > maximum_frequency - 50
	exitScript: "Minimum frequency must be >= 0 and at least 50 Hz below the maximum frequency."
endif
if dynamic_range < 20 or dynamic_range > 150
	exitScript: "Dynamic range must lie between 20 and 150 dB."
endif
if fundamental_frequency < 0
	exitScript: "Fundamental frequency must be 0 (automatic) or positive."
endif
if cepstral_smoothing < 20 or cepstral_smoothing > 5000
	exitScript: "Cepstral smoothing must lie between 20 and 5000 Hz."
endif
if pitch_floor < 20 or pitch_ceiling <= pitch_floor * 1.5
	exitScript: "Pitch floor must be >= 20 Hz and the ceiling at least 1.5 x the floor."
endif
if harmonic_tolerance <= 0.02 or harmonic_tolerance > 0.45
	exitScript: "Harmonic tolerance must lie between 0.02 and 0.45 x F0."
endif

# ---------------- Selection ----------------
nSel = numberOfSelected ("Sound")
if mode = 3
	if nSel <> 2
		exitScript: "Mode C needs exactly two selected Sounds (" + string$ (nSel) + " selected)."
	endif
else
	if nSel <> 1
		exitScript: "Modes A, B and D need exactly one selected Sound (" + string$ (nSel) + " selected)."
	endif
endif
for i to nSel
	orig[i] = selected ("Sound", i)
	origName$[i] = selected$ ("Sound", i)
endfor



# Per-Sound properties and the effective (Nyquist-safe) frequency range
fmaxEff = maximum_frequency
for i to nSel
	selectObject: orig[i]
	sXmin[i] = Get start time
	sDur[i] = Get total duration
	sSR[i] = Get sampling frequency
	sNch[i] = Get number of channels
	if sSR[i] < 2000
		exitScript: "Sound " + origName$[i] + " has a sampling frequency below 2000 Hz."
	endif
	fmaxEff = min (fmaxEff, 0.98 * sSR[i] / 2)
endfor
nyquistLimited = fmaxEff < maximum_frequency
# Display range: Minimum frequency is display-only; the analysis band is
# always 20 Hz to the (Nyquist-safe) maximum frequency.
fminD = minimum_frequency
if fminD > fmaxEff - 50
	exitScript: "Minimum frequency " + fixed$ (fminD, 0) + " Hz is too close to the Nyquist-limited maximum (" + fixed$ (fmaxEff, 0) + " Hz)."
endif

# ---------------- Channel selection (strongest RMS) ----------------
for i to nSel
	selectObject: orig[i]
	if sNch[i] = 1
		sCh[i] = 1
		sMono[i] = orig[i]
	else
		bestRms = -1
		sCh[i] = 1
		for ch to sNch[i]
			selectObject: orig[i]
			tmpCh = Extract one channel: ch
			rmsCh = Get root-mean-square: 0, 0
			removeObject: tmpCh
			if rmsCh <> undefined and rmsCh > bestRms
				bestRms = rmsCh
				sCh[i] = ch
			endif
		endfor
		selectObject: orig[i]
		sMono[i] = Extract one channel: sCh[i]
		@track: sMono[i]
	endif
endfor

# ---------------- Window definition ----------------
# Each analysis slot = one Sound + one time window.
minWin = 0.02
maxFftSamples = 2 ^ 21
autoWin$ = ""
if mode = 1
	nSlot = 1
	@defineWindow: 1, 1, window_A_start, window_A_duration, "A"
elsif mode = 3
	nSlot = 2
	@defineWindow: 1, 1, window_A_start, window_A_duration, "A"
	@defineWindow: 2, 2, window_B_start, window_B_duration, "B"
elsif mode = 2
	nSlot = 2
	if window_A_duration = 0 and window_B_duration = 0
		@autoWindows
	else
		if window_A_duration = 0 or window_B_duration = 0
			@fail: "Mode B: give both windows a duration > 0, or set both to 0 for automatic attack / middle windows."
		endif
		@defineWindow: 1, 1, window_A_start, window_A_duration, "A"
		@defineWindow: 2, 1, window_B_start, window_B_duration, "B"
		if slotT1[1] = slotT1[2] and slotT2[1] = slotT2[2]
			@fail: "Mode B: windows A and B are identical; choose different intervals."
		endif
	endif
else
	# FFT laboratory: windows of different length centred on one time
	if window_A_duration > 0
		@defineWindow: 9, 1, window_A_start, window_A_duration, "c"
		centre = (slotT1[9] + slotT2[9]) / 2
		centreSource$ = "Window A centre"
	else
		if window_A_start > 0
			@fail: "Mode D: give Window A a duration > 0 to choose the centre (0 = Sound midpoint)."
		endif
		centre = sXmin[1] + sDur[1] / 2
		centreSource$ = "Sound midpoint"
	endif
	lenList# = {0.010, 0.040, 0.160, 0.640}
	nSlot = 0
	for j to 4
		lenD = lenList#[j]
		t1D = centre - lenD / 2
		t2D = centre + lenD / 2
		if t1D >= sXmin[1] - 1e-9 and t2D <= sXmin[1] + sDur[1] + 1e-9
			nSlot += 1
			slotSnd[nSlot] = 1
			slotT1[nSlot] = max (t1D, sXmin[1])
			slotT2[nSlot] = min (t2D, sXmin[1] + sDur[1])
			slotLabel$[nSlot] = fixed$ (lenD * 1000, 0) + " ms"
		endif
	endfor
	if nSlot < 2
		@fail: "Mode D needs room for at least the 10 and 40 ms windows around the centre (" + fixed$ (centre - sXmin[1], 3) + " s); choose another centre or a longer Sound."
	endif
endif

# ---------------- Analysis ----------------
hFreq## = zero## (4, maxHarm)
hDb## = zero## (4, maxHarm)
hStat## = zero## (4, maxHarm)
if mode = 4
	# Analyse the longest window first; its F0 is used for all windows.
	@analyzeSlot: nSlot, fundamental_frequency
	f0Common = slotF0[nSlot]
	for k to nSlot - 1
		if f0Common <> undefined
			@analyzeSlot: k, f0Common
			slotF0src$[k] = "from " + slotLabel$[nSlot] + " window"
		else
			@analyzeSlot: k, 0
		endif
	endfor
else
	for k to nSlot
		@analyzeSlot: k, fundamental_frequency
	endfor
endif

# ---------------- Level scale and display alignment ----------------
for k to nSlot
	slotShift[k] = 0
	slotCepShift[k] = 0
	if level_scale = 2
		slotShift[k] = - slotMaxDb[k]
		@shiftSlot: k, slotShift[k]
	endif
	if align_cepstral_display and slotCep[k] <> 0
		selectObject: slotCep[k]
		cepMax = Get maximum: 20, fmaxEff, "Parabolic"
		slotCepShift[k] = (slotMaxDb[k] + slotShift[k]) - cepMax
		Formula: "self + " + string$ (slotCepShift[k])
	endif
endfor

# Common vertical range
if level_scale = 2
	dbMax = 5
	axisLabel$ = "Level re own maximum (dB)"
else
	topDb = -1e9
	for k to nSlot
		topDb = max (topDb, slotMaxDb[k])
		if slotCep[k] <> 0
			selectObject: slotCep[k]
			cMx = Get maximum: 20, fmaxEff, "Parabolic"
			topDb = max (topDb, cMx)
		endif
	endfor
	dbMax = 5 * ceiling ((topDb + 1) / 5)
	axisLabel$ = "Level (dBFS, sine-calibrated)"
endif
dbMin = dbMax - dynamic_range

# ---------------- Measurements for the findings ----------------
@computeFindings

# ---------------- Results table ----------------
if create_results_table
	@buildTable
endif

# ---------------- Visualization ----------------
if draw_visualization
	@drawFigure
endif

# ---------------- Info window ----------------
@writeInfo

# ---------------- Cleanup and selection ----------------
@cleanupAll
selectObject: orig[1]
if nSel = 2
	plusObject: orig[2]
endif


# ====================================================================
# PROCEDURES
# ====================================================================

# Temporary objects are tracked by ID and removed by ID only. They are also
# named "SELab_tmp" so that, should an unexpected Praat error stop the script,
# the user can recognise and remove them; the script never deletes objects by
# name.
procedure track: .id
	nTrack += 1
	track[nTrack] = .id
	selectObject: .id
	Rename: "SELab_tmp"
endproc

procedure drop: .id
	for .i to nTrack
		if track[.i] = .id
			track[.i] = 0
		endif
	endfor
	removeObject: .id
endproc

procedure cleanupAll
	for .i to nTrack
		if track[.i] <> 0
			removeObject: track[.i]
			track[.i] = 0
		endif
	endfor
endproc

procedure fail: .msg$
	@cleanupAll
	selectObject: orig[1]
	if nSel = 2
		plusObject: orig[2]
	endif
	exitScript: .msg$
endproc

# Text-safe version of a string for Praat Picture markup
procedure safe: .s$
	.s$ = replace$ (.s$, "\", "\bs", 0)
	.s$ = replace$ (.s$, "_", "\_ ", 0)
	.s$ = replace$ (.s$, "%", "\% ", 0)
	.s$ = replace$ (.s$, "#", "\# ", 0)
	.s$ = replace$ (.s$, "^", "\^ ", 0)
	safe.out$ = .s$
endproc

procedure defineWindow: .slot, .snd, .start, .dur, .label$
	.total = sDur[.snd]
	if .start >= .total
		@fail: "Window " + .label$ + " starts at " + fixed$ (.start, 3) + " s, beyond the end of " + origName$[.snd] + " (" + fixed$ (.total, 3) + " s)."
	endif
	if .dur = 0
		.dur = .total - .start
	endif
	if .start + .dur > .total + 1e-9
		@fail: "Window " + .label$ + " (" + fixed$ (.start, 3) + "-" + fixed$ (.start + .dur, 3) + " s) extends beyond the end of " + origName$[.snd] + " (" + fixed$ (.total, 3) + " s)."
	endif
	if .dur < minWin
		@fail: "Window " + .label$ + " is " + fixed$ (.dur * 1000, 1) + " ms; the minimum is " + fixed$ (minWin * 1000, 0) + " ms."
	endif
	if .dur * sSR[.snd] > maxFftSamples
		@fail: "Window " + .label$ + " is " + fixed$ (.dur, 1) + " s; at " + fixed$ (sSR[.snd], 0) + " Hz the maximum is " + fixed$ (maxFftSamples / sSR[.snd], 1) + " s (2^21 samples). Choose a shorter interval."
	endif
	slotSnd[.slot] = .snd
	slotT1[.slot] = sXmin[.snd] + .start
	slotT2[.slot] = sXmin[.snd] + min (.start + .dur, .total)
	slotLabel$[.slot] = .label$
endproc

# Mode B with both durations 0: 100 ms at the onset and 100 ms in the middle
procedure autoWindows
	if sDur[1] < 0.3
		@fail: "Automatic attack / middle windows need a Sound of at least 0.3 s; set the two windows explicitly."
	endif
	# onset measured on the analysed (strongest-RMS) channel
	selectObject: sMono[1]
	.int = To Intensity: 100, 0, "yes"
	@track: .int
	.imax = Get maximum: 0, 0, "Parabolic"
	.nf = Get number of frames
	.onset = undefined
	.i = 1
	while .i <= .nf and .onset = undefined
		.v = Get value in frame: .i
		if .v <> undefined and .v >= .imax - 20
			.onset = Get time from frame number: .i
			.onset = max (sXmin[1], .onset - 0.016)
		endif
		.i += 1
	endwhile
	@drop: .int
	if .onset = undefined
		@fail: "Automatic windows: no onset found; set the two windows explicitly."
	endif
	.end = sXmin[1] + sDur[1]
	.a1 = .onset
	.a2 = .onset + 0.1
	.mid = (.onset + .end) / 2
	.b1 = max (.a2, .mid - 0.05)
	.b2 = .b1 + 0.1
	if .b2 > .end
		@fail: "Automatic windows: the Sound is too short after its onset; set the two windows explicitly."
	endif
	slotSnd[1] = 1
	slotT1[1] = .a1
	slotT2[1] = .a2
	slotLabel$[1] = "A attack"
	slotSnd[2] = 1
	slotT1[2] = .b1
	slotT2[2] = .b2
	slotLabel$[2] = "B middle"
	autoWin$ = "automatic windows (onset at -20 dB re max intensity)"
endproc

# --------------------------------------------------------------------
# Analysis of one slot: Hann spectrum, cepstral envelope, F0, peaks
# --------------------------------------------------------------------
procedure analyzeSlot: .k, .f0in
	.snd = slotSnd[.k]
	.t1 = slotT1[.k]
	.t2 = slotT2[.k]
	.tw = .t2 - .t1
	slotTw[.k] = .tw
	slotCep[.k] = 0

	# Raw (rectangular) excerpt: level check and pitch
	selectObject: sMono[.snd]
	.raw = Extract part: .t1, .t2, "rectangular", 1, "no"
	@track: .raw
	.rms = Get root-mean-square: 0, 0
	if .rms = undefined or .rms < 1e-6
		@fail: "Window " + slotLabel$[.k] + " of " + origName$[.snd] + " is silent or nearly silent (RMS below -120 dBFS)."
	endif
	slotRmsDb[.k] = 20 * log10 (.rms)
	.ns = Get number of samples
	slotNs[.k] = .ns

	# Hann-windowed excerpt and its FFT
	selectObject: sMono[.snd]
	.han = Extract part: .t1, .t2, "Hanning", 1, "no"
	@track: .han
	# Zero-pad so that peak values and lobe widths can be read accurately
	# between bins: 8 x the window while that stays within 2^20 points,
	# otherwise the smallest power of two that holds the window. Windows are
	# limited to 2^21 samples, so the FFT never exceeds 2^21 points. Padding
	# interpolates the spectrum of the same T-second window; it adds no
	# resolution.
	if .ns * 8 <= 2 ^ 20
		.nPad = .ns * 8
	else
		.nPad = 2 ^ ceiling (log2 (.ns))
	endif
	.sr = sSR[.snd]
	.pad = Create Sound from formula: "padded", 1, 0, .nPad / .sr, .sr, "if col <= " + string$ (.ns) + " then object [" + string$ (.han) + ", 1, col] else 0 fi"
	@track: .pad
	.sp = To Spectrum: "yes"
	@track: .sp
	.df = Get bin width
	.nb = Get number of bins
	slotDf[.k] = .df
	slotNfft[.k] = 2 * (.nb - 1)
	.nUse = min (.nb, floor (fmaxEff / .df) + 3)

	# Sine-calibrated amplitude spectrum in dBFS: 20*log10(4 |X| / T)
	.form$ = "20 * log10 (max (1e-15, 4 / " + string$ (.tw) + " * sqrt (object [" + string$ (.sp) + ", 1, col] ^ 2 + object [" + string$ (.sp) + ", 2, col] ^ 2)))"
	slotCurve[.k] = Create Sound from formula: "specdB_" + string$ (.k), 1, -.df / 2, (.nUse - 0.5) * .df, 1 / .df, .form$
	@track: slotCurve[.k]

	# Cepstral envelope on the same spectrum, same calibration
	if mode <> 4 and envelope >= 3
		selectObject: .sp
		.cs = Cepstral smoothing: cepstral_smoothing
		@track: .cs
		.formC$ = "20 * log10 (max (1e-15, 4 / " + string$ (.tw) + " * sqrt (object [" + string$ (.cs) + ", 1, col] ^ 2 + object [" + string$ (.cs) + ", 2, col] ^ 2)))"
		slotCep[.k] = Create Sound from formula: "cepdB_" + string$ (.k), 1, -.df / 2, (.nUse - 0.5) * .df, 1 / .df, .formC$
		@track: slotCep[.k]
		@drop: .cs
	endif
	@drop: .sp
	@drop: .pad
	@drop: .han

	# Strongest peak and median level of the displayed band
	selectObject: slotCurve[.k]
	.lo = min (20, fmaxEff / 2)
	slotMaxDb[.k] = Get maximum: .lo, fmaxEff, "Parabolic"
	slotMaxHz[.k] = Get time of maximum: .lo, fmaxEff, "Parabolic"
	.n1 = max (1, round (.lo / .df) + 1)
	.n2 = min (.nUse, round (fmaxEff / .df) + 1)
	.m = min (3000, .n2 - .n1 + 1)
	.vals# = zero# (.m)
	for .j to .m
		.idx = .n1 + round ((.j - 1) * (.n2 - .n1) / max (1, .m - 1))
		.vals#[.j] = Get value at sample number: 1, .idx
	endfor
	.sorted# = sort# (.vals#)
	slotFloor[.k] = .sorted#[round (.m / 2)]

	# ---- F0 ----
	slotF0[.k] = undefined
	slotF0pitch[.k] = undefined
	slotF0src$[.k] = ""
	slotF0note$[.k] = ""
	if .f0in > 0
		slotF0[.k] = .f0in
		slotF0src$[.k] = "user-specified"
	else
		if .tw < 3 / pitch_floor
			slotF0note$[.k] = "window shorter than 3 / pitch floor (" + fixed$ (3000 / pitch_floor, 0) + " ms)"
		else
			selectObject: .raw
			.pitch = To Pitch: 0, pitch_floor, pitch_ceiling
			@track: .pitch
			.nfr = Get number of frames
			.nv = Count voiced frames
			if .nv >= 3 and .nv / .nfr >= 0.5
				.q10 = Get quantile: 0, 0, 0.10, "Hertz"
				.q50 = Get quantile: 0, 0, 0.50, "Hertz"
				.q90 = Get quantile: 0, 0, 0.90, "Hertz"
				.spread = 12 * log2 (.q90 / .q10)
				slotF0pitch[.k] = .q50
				if .spread <= 2
					slotF0[.k] = .q50
					slotF0src$[.k] = "Pitch median"
				else
					slotF0note$[.k] = "pitch spread " + fixed$ (.spread, 1) + " semitones (> 2)"
				endif
			elsif .nv < 3
				slotF0note$[.k] = "only " + string$ (.nv) + " voiced pitch frames"
			else
				slotF0note$[.k] = "only " + fixed$ (100 * .nv / .nfr, 0) + " percent voiced frames"
			endif
			@drop: .pitch
		endif
	endif
	@drop: .raw

	# ---- Harmonic peak validation ----
	slotNexp[.k] = 0
	slotNval[.k] = 0
	slotModel$[.k] = "unavailable"
	slotFirstV[.k] = 0
	slotFirstN[.k] = 0
	slotCapped[.k] = 0
	if slotF0[.k] <> undefined
		if slotF0[.k] < 4 / .tw
			slotModel$[.k] = "unresolved"
			slotF0note$[.k] = "F0 below 4 / T: Hann main lobes of adjacent harmonics overlap"
		elsif slotF0[.k] > fmaxEff
			slotModel$[.k] = "unavailable"
			slotF0note$[.k] = "F0 above the displayed frequency range"
		else
			if slotF0src$[.k] = "Pitch median"
				# Pass 1 (automatic F0 only): refine F0 from the first validated
				# peaks by least squares through the origin
				@validatePeaks: .k, slotF0[.k], min (8, floor (fmaxEff / slotF0[.k])), 0.25, 0
				@lsF0: .k, validatePeaks.n
				if lsF0.n >= 2 and abs (12 * log2 (lsF0.f0 / slotF0[.k])) < 1
					slotF0[.k] = lsF0.f0
					slotF0src$[.k] = "Pitch median, peak-refined"
				endif
				# Octave check: a spectrum with validated even harmonics but no odd
				# ones has, by definition, twice this fundamental.
				.nChk = min (10, floor (fmaxEff / slotF0[.k]))
				@validatePeaks: .k, slotF0[.k], .nChk, harmonic_tolerance, 0
				.nOdd = 0
				.nEven = 0
				for .h to .nChk
					if hStat##[.k, .h] = 1
						if .h mod 2 = 1
							.nOdd += 1
						else
							.nEven += 1
						endif
					endif
				endfor
				if .nOdd = 0 and .nEven >= 2 and 2 * slotF0[.k] <= fmaxEff
					slotF0[.k] = 2 * slotF0[.k]
					@validatePeaks: .k, slotF0[.k], min (8, floor (fmaxEff / slotF0[.k])), 0.25, 0
					@lsF0: .k, validatePeaks.n
					if lsF0.n >= 2 and abs (12 * log2 (lsF0.f0 / slotF0[.k])) < 1
						slotF0[.k] = lsF0.f0
					endif
					slotF0src$[.k] = slotF0src$[.k] + ", doubled: no odd harmonics"
				endif
			endif
			# Pass 2: all expected harmonics in range
			.nexp = min (maxHarm, floor (fmaxEff / slotF0[.k]))
			slotCapped[.k] = floor (fmaxEff / slotF0[.k]) > maxHarm
			@validatePeaks: .k, slotF0[.k], .nexp, harmonic_tolerance, 1
			slotNexp[.k] = .nexp
			slotNval[.k] = validatePeaks.nval
			.nFirst = min (10, .nexp)
			.vFirst = 0
			for .h to .nFirst
				.vFirst += hStat##[.k, .h]
			endfor
			# A user-specified F0 is kept, but an even-only pattern is reported
			if slotF0src$[.k] = "user-specified" and .nexp >= 4
				.nOdd = 0
				.nEven = 0
				for .h to min (10, .nexp)
					if hStat##[.k, .h] = 1
						if .h mod 2 = 1
							.nOdd += 1
						else
							.nEven += 1
						endif
					endif
				endfor
				if .nOdd = 0 and .nEven >= 2
					slotF0note$[.k] = "only even multiples validated: the true F0 may be " + fixed$ (2 * slotF0[.k], 1) + " Hz"
				endif
			endif
			slotFirstV[.k] = .vFirst
			slotFirstN[.k] = .nFirst
			if validatePeaks.nval >= 3 and .vFirst / .nFirst >= 0.3
				slotModel$[.k] = "consistent"
			elsif validatePeaks.nval >= 1
				slotModel$[.k] = "inconclusive"
			else
				slotModel$[.k] = "not found"
			endif
		endif
	endif
endproc

# Search each expected harmonic position for a validated measured peak.
# .track = 1: the search centre follows the last validated peak
# (h * f_last / k_last, limited to +/-5 % of F0), so a slightly wrong F0 or
# mild string stretching does not shift the harmonic numbering.
procedure validatePeaks: .k, .f0, .n, .tol, .track
	.nval = 0
	.df = slotDf[.k]
	.fest = .f0
	.gate = slotMaxDb[.k] - validation_range
	selectObject: slotCurve[.k]
	for .h to maxHarm
		hStat##[.k, .h] = 0
		hFreq##[.k, .h] = 0
		hDb##[.k, .h] = 0
	endfor
	for .h to .n
		.fe = .h * .fest
		.lo = max (.df, .fe - .tol * .f0)
		.hi = min (fmaxEff, .fe + .tol * .f0)
		if .hi - .lo > 3 * .df
			.pv = Get maximum: .lo, .hi, "Parabolic"
			.pf = Get time of maximum: .lo, .hi, "Parabolic"
			# a genuine local maximum, not the rising edge of a neighbour
			.interior = .pf > .lo + 1.5 * .df and .pf < .hi - 1.5 * .df
			.lMin = Get minimum: max (0, .pf - 0.5 * .f0), .pf, "None"
			.rMin = Get minimum: .pf, min (fmaxEff, .pf + 0.5 * .f0), "None"
			.prom = .pv - max (.lMin, .rMin)
			# Main-lobe shape: a Hann main lobe is 2 / T wide at -6 dB, a window
			# sidelobe only about 1 / T between nulls. Require the level at
			# +/- 0.6 / T to stay within 6 dB of the peak.
			.vL = Get value at time: 1, .pf - 0.6 / slotTw[.k], "Cubic"
			.vR = Get value at time: 1, .pf + 0.6 / slotTw[.k], "Cubic"
			.lobe = .vL >= .pv - 6.02 and .vR >= .pv - 6.02
			if .interior and .lobe and .prom >= peak_prominence and .pv >= slotFloor[.k] + floor_margin and .pv >= .gate
				hStat##[.k, .h] = 1
				hFreq##[.k, .h] = .pf
				hDb##[.k, .h] = .pv
				.nval += 1
				if .track
					.fl = .pf / .h
					if abs (.fl / .f0 - 1) <= 0.05
						.fest = .fl
					endif
				endif
			endif
		endif
	endfor
endproc

procedure lsF0: .k, .nh
	.sw = 0
	.sk = 0
	.n = 0
	.f0 = undefined
	for .h to .nh
		if hStat##[.k, .h] = 1
			.sw += .h * hFreq##[.k, .h]
			.sk += .h * .h
			.n += 1
		endif
	endfor
	if .sk > 0
		.f0 = .sw / .sk
	endif
endproc

procedure shiftSlot: .k, .s
	selectObject: slotCurve[.k]
	Formula: "self + " + string$ (.s)
	if slotCep[.k] <> 0
		selectObject: slotCep[.k]
		Formula: "self + " + string$ (.s)
	endif
	for .h to maxHarm
		if hStat##[.k, .h] = 1
			hDb##[.k, .h] = hDb##[.k, .h] + .s
		endif
	endfor
endproc

# --------------------------------------------------------------------
# Factual findings (computed from the measurements, never assumed)
# --------------------------------------------------------------------
procedure computeFindings
	find1$ = ""
	find2$ = ""
	cue$ = ""
	if mode = 1
		.k = 1
		@harmSummary: .k
		find1$ = harmSummary.out$
		find2$ = "Strongest component " + fixed$ (slotMaxHz[.k], 1) + " Hz at " + fixed$ (slotMaxDb[.k], 1) + " dBFS; median spectral level " + fixed$ (slotFloor[.k], 1) + " dBFS."
		if slotCep[.k] <> 0 and slotNval[.k] >= 1
			@peakToCep: .k
			if peakToCep.n > 0
				find2$ = "Validated peaks lie a median " + fixed$ (peakToCep.med, 1) + " dB above the cepstral envelope (" + fixed$ (peakToCep.lo, 1) + " to " + fixed$ (peakToCep.hi, 1) + " dB, n = " + string$ (peakToCep.n) + ")."
			endif
		endif
		if slotCep[.k] <> 0
			cue$ = "Cue: the cepstral curve is a log-average of peaks and valleys, so its distance below the peaks grows with window length and a lower noise floor."
		else
			cue$ = "Cue: a measured peak passed the local-maximum, prominence and floor tests; k x F0 ticks are predictions. Neither envelope is a formant measurement."
		endif
	elsif mode = 2 or mode = 3
		@harmSummary: 1
		.s1$ = harmSummary.short$
		@harmSummary: 2
		.s2$ = harmSummary.short$
		find1$ = "A: " + .s1$ + "   |   B: " + .s2$
		# level differences over harmonics validated in both windows
		if slotF0[1] <> undefined and slotF0[2] <> undefined and abs (12 * log2 (slotF0[1] / slotF0[2])) < 1.5
			.n = 0
			.nLo = 0
			.nHi = 0
			.sLo = 0
			.sHi = 0
			.d# = zero# (maxHarm)
			for .h to maxHarm
				if hStat##[1, .h] = 1 and hStat##[2, .h] = 1
					.n += 1
					.d#[.n] = hDb##[2, .h] - hDb##[1, .h]
					if .h <= 5
						.nLo += 1
						.sLo += .d#[.n]
					else
						.nHi += 1
						.sHi += .d#[.n]
					endif
				endif
			endfor
			if .n > 0
				.dd# = zero# (.n)
				for .j to .n
					.dd#[.j] = .d#[.j]
				endfor
				.dd# = sort# (.dd#)
				.med = .dd#[round ((.n + 1) / 2)]
				find2$ = "B - A at " + string$ (.n) + " harmonics validated in both: median " + fixed$ (round ((.med) * 10) / 10, 1) + " dB"
				if .nLo > 0
					find2$ = find2$ + ", mean k<=5: " + fixed$ (round ((.sLo / .nLo) * 10) / 10, 1) + " dB"
				endif
				if .nHi > 0
					find2$ = find2$ + ", mean k>5: " + fixed$ (round ((.sHi / .nHi) * 10) / 10, 1) + " dB"
				endif
				if level_scale = 2
					find2$ = find2$ + " (shape, each re own maximum)."
				else
					find2$ = find2$ + " (absolute)."
				endif
			else
				find2$ = "No harmonic is validated in both windows, so no harmonic-by-harmonic level difference is reported."
			endif
		else
			find2$ = "Harmonic-by-harmonic comparison needs a valid F0 in both windows that agrees within 1.5 semitones."
		endif
		if mode = 2
			cue$ = "Cue: compare how many harmonics validate in each window and where the two envelopes diverge; transients rarely form stable harmonic peaks."
		else
			cue$ = "Cue: Absolute mode compares levels on one sine-calibrated scale; Peak-normalized mode compares spectral shape only."
		endif
	else
		@fftLabFindings
	endif
endproc

procedure harmSummary: .k
	if slotModel$[.k] = "unavailable" or slotModel$[.k] = "unresolved"
		if slotF0[.k] = undefined
			.out$ = "F0 not reliable (" + slotF0note$[.k] + "): harmonic markers and peak envelope unavailable; spectrum and cepstral envelope remain valid."
			.short$ = "F0 unavailable"
		else
			.out$ = "F0 " + fixed$ (slotF0[.k], 1) + " Hz, but " + slotF0note$[.k] + "; harmonic functions unavailable."
			.short$ = "F0 " + fixed$ (slotF0[.k], 1) + " Hz, harmonics unresolved"
		endif
	else
		.miss$ = ""
		.nm = 0
		for .h to slotNexp[.k]
			if hStat##[.k, .h] = 0 and .nm < 6
				.miss$ = .miss$ + " " + string$ (.h)
				.nm += 1
			endif
		endfor
		.out$ = "F0 " + fixed$ (slotF0[.k], 1) + " Hz (" + slotF0src$[.k] + "): " + string$ (slotNval[.k]) + " of " + string$ (slotNexp[.k]) + " expected harmonics validated (" + string$ (slotFirstV[.k]) + " of first " + string$ (slotFirstN[.k]) + "); harmonic pattern " + slotModel$[.k]
		if .nm > 0
			.out$ = .out$ + "; first missing k =" + .miss$
		endif
		if slotCapped[.k]
			.out$ = .out$ + "; only the first " + string$ (maxHarm) + " harmonics were tested"
		endif
		if slotF0note$[.k] <> ""
			.out$ = .out$ + "; WARNING " + slotF0note$[.k]
		endif
		.out$ = .out$ + "."
		.short$ = "F0 " + fixed$ (slotF0[.k], 1) + " Hz, " + string$ (slotNval[.k]) + "/" + string$ (slotNexp[.k]) + " validated, pattern " + slotModel$[.k]
		if slotF0note$[.k] <> ""
			.short$ = .short$ + " (check F0)"
		endif
	endif
endproc

# Validated peak level minus cepstral envelope at the same frequency
procedure peakToCep: .k
	.n = 0
	.v# = zero# (maxHarm)
	selectObject: slotCep[.k]
	for .h to maxHarm
		if hStat##[.k, .h] = 1
			# measured distance: undo any display-only cepstral alignment
			.c = Get value at time: 1, hFreq##[.k, .h], "Linear"
			.c = .c - slotCepShift[.k]
			.n += 1
			.v#[.n] = hDb##[.k, .h] - .c
		endif
	endfor
	.med = undefined
	if .n > 0
		.w# = zero# (.n)
		for .j to .n
			.w#[.j] = .v#[.j]
		endfor
		.w# = sort# (.w#)
		.med = .w#[round ((.n + 1) / 2)]
		.lo = .w#[1]
		.hi = .w#[.n]
	endif
endproc

# FFT laboratory: measured -6 dB main-lobe width at the strongest peak
procedure fftLabFindings
	# Reference component: strongest peak of the longest window inside the
	# displayed range, so the zoom never leaves the range the user asked for.
	# The search excludes one Hann lobe (2 / T) at each edge of the displayed
	# range, so the chosen value is an interior local peak, not a rising edge.
	# Praat searches the WHOLE Sound when the range is empty or inverted, so
	# the range is checked first: it must hold at least one lobe (2 / T)
	# beyond the two excluded edge bands.
	selectObject: slotCurve[nSlot]
	.edge = 2 / slotTw[nSlot]
	.lo = max (20, fminD) + .edge
	.hi = fmaxEff - .edge
	labBandOK = .hi - .lo >= .edge
	labInterior = 0
	labProm = -999
	if labBandOK
		labFreq = Get time of maximum: .lo, .hi, "Parabolic"
		labDb = Get maximum: .lo, .hi, "Parabolic"
		.vL = Get value at time: 1, labFreq - .edge / 2, "Cubic"
		.vR = Get value at time: 1, labFreq + .edge / 2, "Cubic"
		labInterior = .vL < labDb and .vR < labDb and labFreq > .lo + slotDf[nSlot] and labFreq < .hi - slotDf[nSlot]
	else
		# no measurement; the zoom simply shows the whole displayed range
		labFreq = (max (20, fminD) + fmaxEff) / 2
		labDb = undefined
	endif
	# Is the reference component tonal? 30 dB above the median level of the
	# longest window. Otherwise no lobe width is measured at all.
	# Curves may already be shifted (Peak-normalized shape); the floor is
	# compared on the same scale.
	if labBandOK
		labProm = labDb - (slotFloor[nSlot] + slotShift[nSlot])
	endif
	labTonal = labBandOK and labInterior and labProm >= 30
	find1$ = "-6 dB peak width at " + fixed$ (labFreq, 0) + " Hz, measured (one Hann lobe = 2/T):"
	# A width is reported only for a tonal component and labelled when the
	# lobe is not an isolated Hann main lobe (merged neighbours, vibrato).
	for .k to nSlot
		slotW6th[.k] = 2 / slotTw[.k]
		slotW6[.k] = undefined
		slotW6st$[.k] = if labBandOK then "no prominent peak" else "display band too narrow" fi
		if labTonal
			@lobeWidth: .k, labFreq
			if lobeWidth.w = undefined
				slotW6st$[.k] = "not isolated"
				.w$ = "not isolated"
			else
				slotW6[.k] = lobeWidth.w
				.ratio = lobeWidth.w / slotW6th[.k]
				if .ratio > 1.15
					# wider than one Hann lobe: neighbouring components or
					# modulation contribute; this is a peak width, not a lobe
					slotW6st$[.k] = "broadened peak, not a single lobe"
					.w$ = fixed$ (lobeWidth.w, 1) + " Hz peak (not one lobe)"
				elsif .ratio < 0.85
					slotW6st$[.k] = "narrower than Hann"
					.w$ = fixed$ (lobeWidth.w, 1) + " Hz (check)"
				else
					slotW6st$[.k] = "consistent with one Hann lobe"
					.w$ = fixed$ (lobeWidth.w, 1) + " Hz"
				endif
			endif
			# "~" = non-breaking space for the word wrap
			find1$ = find1$ + "   " + replace$ (slotLabel$[.k] + " " + .w$ + " (" + fixed$ (slotW6th[.k], 1) + ")", " ", "~", 0)
		endif
	endfor
	if not labBandOK
		find1$ = "Insufficient displayed bandwidth for a reliable peak-width measurement (" + fixed$ (fmaxEff - max (20, fminD), 0) + " Hz shown; at least 3 x 2/T = " + fixed$ (3 * 2 / slotTw[nSlot], 0) + " Hz needed for the " + slotLabel$[nSlot] + " window)."
	elsif not labInterior
		find1$ = "The strongest displayed value lies at the edge of the display range, not on a local peak: no width is measured."
	elsif labProm < 30
		find1$ = "Strongest displayed component (" + fixed$ (labFreq, 0) + " Hz) is only " + fixed$ (labProm, 0) + " dB above the median level: no prominent peak, so no width is measured."
	endif
	find2$ = "Validated harmonics:"
	for .k to nSlot
		if slotModel$[.k] = "unresolved"
			.v$ = "unresolved"
		elsif slotF0[.k] = undefined
			.v$ = "no F0"
		else
			.v$ = string$ (slotNval[.k]) + "/" + string$ (slotNexp[.k])
		endif
		find2$ = find2$ + "  " + replace$ (slotLabel$[.k] + " " + .v$ + ";", " ", "~", 0)
	endfor
	if slotF0[nSlot] <> undefined
		find2$ = find2$ + "  harmonics resolvable (F0 >= 4/T) from T >= " + fixed$ (4000 / slotF0[nSlot], 0) + " ms."
	endif
	cue$ = "Cue: only a longer window narrows the main lobe; zero-padding interpolates but adds no resolution, and long windows blur time."
endproc

procedure lobeWidth: .k, .fc
	# Full width of the main lobe at -6.02 dB (Hann: exactly 2 / T for an
	# isolated sinusoid). Crossings are bracketed on the FFT grid and then
	# refined by bisection on the sinc-interpolated curve.
	.w = undefined
	.df = slotDf[.k]
	.tw = slotTw[.k]
	selectObject: slotCurve[.k]
	.lo = max (.df, .fc - 1 / .tw)
	.hi = min (fmaxEff, .fc + 1 / .tw)
	.pv = Get maximum: .lo, .hi, "Parabolic"
	.pf = Get time of maximum: .lo, .hi, "Parabolic"
	.target = .pv - 6.02
	.nmax = Get number of samples
	.ic = round (.pf / .df) + 1
	.span = ceiling (4 / .tw / .df) + 2
	.fl = undefined
	.i = .ic
	while .fl = undefined and .i > max (2, .ic - .span)
		.v1 = Get value at sample number: 1, .i
		.v0 = Get value at sample number: 1, .i - 1
		if .v1 >= .target and .v0 < .target
			@bisect: (.i - 2) * .df, (.i - 1) * .df, .target
			.fl = bisect.x
		endif
		.i -= 1
	endwhile
	.fr = undefined
	.i = .ic
	while .fr = undefined and .i < min (.nmax - 1, .ic + .span)
		.v0 = Get value at sample number: 1, .i
		.v1 = Get value at sample number: 1, .i + 1
		if .v0 >= .target and .v1 < .target
			@bisect: .i * .df, (.i - 1) * .df, .target
			.fr = bisect.x
		endif
		.i += 1
	endwhile
	if .fl <> undefined and .fr <> undefined
		.w = .fr - .fl
	endif
endproc

# Bisection for the target level between .xBelow (curve < target) and .xAbove
procedure bisect: .xBelow, .xAbove, .target
	for .it to 24
		.xm = (.xBelow + .xAbove) / 2
		.vm = Get value at time: 1, .xm, "Cubic"
		if .vm >= .target
			.xAbove = .xm
		else
			.xBelow = .xm
		endif
	endfor
	.x = (.xBelow + .xAbove) / 2
endproc

# --------------------------------------------------------------------
# Results table and Info window
# --------------------------------------------------------------------
procedure buildTable
	resultsTable = Create Table with column names: "Spectrum_Envelope_Lab", nSlot,
	... "Mode Window Window_type Sound Channel SampleRate_Hz Start_s End_s Duration_s FFT_points Bin_Hz Hann_3dB_res_Hz F0_Hz F0_source F0_note Harmonics_expected Harmonics_validated Harmonic_pattern Median_level_dBFS Strongest_Hz Strongest_dBFS Cepstral_bw_Hz Level_scale Display_shift_dB Cepstral_display_shift_dB Peak_width_6dB_Hz Hann_lobe_width_2_over_T_Hz Width_6dB_status"
	for .k to nSlot
		.s = slotSnd[.k]
		Set string value: .k, "Mode", left$ (modeName$[mode], 1)
		Set string value: .k, "Window", replace$ (slotLabel$[.k], " ", "_", 0)
		Set string value: .k, "Sound", origName$[.s]
		Set numeric value: .k, "Channel", sCh[.s]
		Set numeric value: .k, "SampleRate_Hz", sSR[.s]
		Set numeric value: .k, "Start_s", slotT1[.k] - sXmin[.s]
		Set numeric value: .k, "End_s", slotT2[.k] - sXmin[.s]
		Set numeric value: .k, "Duration_s", slotTw[.k]
		Set string value: .k, "Window_type", "Hann"
		Set numeric value: .k, "FFT_points", slotNfft[.k]
		Set numeric value: .k, "Bin_Hz", slotDf[.k]
		Set numeric value: .k, "Hann_3dB_res_Hz", 1.44 / slotTw[.k]
		Set numeric value: .k, "F0_Hz", slotF0[.k]
		.src$ = if slotF0src$[.k] = "" then "none" else replace$ (slotF0src$[.k], " ", "_", 0) fi
		Set string value: .k, "F0_source", .src$
		.note$ = if slotF0note$[.k] = "" then "-" else replace$ (slotF0note$[.k], " ", "_", 0) fi
		Set string value: .k, "F0_note", .note$
		Set numeric value: .k, "Harmonics_expected", slotNexp[.k]
		Set numeric value: .k, "Harmonics_validated", slotNval[.k]
		Set string value: .k, "Harmonic_pattern", replace$ (slotModel$[.k], " ", "_", 0)
		Set numeric value: .k, "Median_level_dBFS", slotFloor[.k]
		Set numeric value: .k, "Strongest_Hz", slotMaxHz[.k]
		Set numeric value: .k, "Strongest_dBFS", slotMaxDb[.k]
		.cbw = if slotCep[.k] <> 0 then cepstral_smoothing else undefined fi
		Set numeric value: .k, "Cepstral_bw_Hz", .cbw
		Set string value: .k, "Level_scale", if level_scale = 1 then "absolute" else "peak_normalized" fi
		Set numeric value: .k, "Display_shift_dB", slotShift[.k]
		Set numeric value: .k, "Cepstral_display_shift_dB", slotCepShift[.k]
		if mode = 4
			Set numeric value: .k, "Peak_width_6dB_Hz", slotW6[.k]
			Set numeric value: .k, "Hann_lobe_width_2_over_T_Hz", slotW6th[.k]
			Set string value: .k, "Width_6dB_status", replace$ (slotW6st$[.k], " ", "_", 0)
		else
			Set string value: .k, "Width_6dB_status", "-"
			Set numeric value: .k, "Peak_width_6dB_Hz", undefined
			Set numeric value: .k, "Hann_lobe_width_2_over_T_Hz", undefined
		endif
	endfor
endproc

procedure writeInfo
	writeInfoLine: "Spectrum & Envelope Lab v1.1.1 - ", modeName$[mode]
	appendInfoLine: "Spectra: Hann window, amplitude calibrated so a sinusoid of amplitude A reads 20*log10(A) dBFS."
	if nyquistLimited
		appendInfoLine: "Frequency range limited to ", fixed$ (fmaxEff, 0), " Hz (98 percent of the lowest Nyquist frequency)."
	endif
	if autoWin$ <> ""
		appendInfoLine: "Mode B used ", autoWin$, "."
	endif
	for .k to nSlot
		.s = slotSnd[.k]
		appendInfoLine: ""
		appendInfoLine: "[", slotLabel$[.k], "] ", origName$[.s], "  channel ", sCh[.s], " of ", sNch[.s], "  ", fixed$ (slotT1[.k] - sXmin[.s], 3), "-", fixed$ (slotT2[.k] - sXmin[.s], 3), " s"
		appendInfoLine: "   T = ", fixed$ (slotTw[.k] * 1000, 1), " ms, FFT ", slotNfft[.k], " points (", slotNs[.k], " samples), bin ", fixed$ (slotDf[.k], 2), " Hz, Hann -3 dB resolution ", fixed$ (1.44 / slotTw[.k], 1), " Hz"
		if slotF0[.k] = undefined
			appendInfoLine: "   F0: unavailable (", slotF0note$[.k], ")"
		else
			appendInfoLine: "   F0: ", fixed$ (slotF0[.k], 2), " Hz (", slotF0src$[.k], ")"
		endif
		if slotNexp[.k] > 0
			appendInfoLine: "   Harmonics: ", slotNval[.k], " validated of ", slotNexp[.k], " expected (", slotFirstV[.k], " of first ", slotFirstN[.k], "); harmonic pattern ", slotModel$[.k], " (heuristic)"
		else
			appendInfoLine: "   Harmonics: not tested (harmonic pattern ", slotModel$[.k], ")"
		endif
		appendInfoLine: "   Strongest component ", fixed$ (slotMaxHz[.k], 1), " Hz at ", fixed$ (slotMaxDb[.k], 1), " dBFS; median level ", fixed$ (slotFloor[.k], 1), " dBFS"
		if slotCepShift[.k] <> 0
			appendInfoLine: "   Cepstral curve shifted by ", fixed$ (slotCepShift[.k], 1), " dB for display only"
		endif
	endfor
	appendInfoLine: ""
	appendInfoLine: replace$ (find1$, "~", " ", 0)
	if find2$ <> ""
		appendInfoLine: replace$ (find2$, "~", " ", 0)
	endif
	appendInfoLine: cue$
	if create_results_table
		appendInfoLine: "Table Spectrum_Envelope_Lab created (one row per analysis window)."
	endif
	if mode <> 4
		for .k to nSlot
			@harmonicReport: .k
		endfor
		appendInfoLine: ""
		appendInfoLine: "Expected frequencies are integer multiples of F0. Measured values are reported only for validated spectral peaks. Relative levels are referenced to the strongest measured component of the analysis window."
	endif
endproc

# --------------------------------------------------------------------
# Harmonic Components Report (Info window, modes A-C)
# H1-H10 in harmonic order, read from the existing validation arrays
# (hStat##, hFreq##, hDb##). Levels are restored to the analysis values:
# the display shift of "Peak-normalized shape" is subtracted, so the
# report is identical in both level scales. Relative dB is referenced to
# the strongest measured component of the window (20 Hz to the maximum
# analysis frequency). Nothing is measured here.
# --------------------------------------------------------------------
procedure harmonicReport: .k
	.s = slotSnd[.k]
	appendInfoLine: ""
	appendInfoLine: "=== HARMONIC COMPONENTS: " + slotLabel$[.k] + " ==="
	appendInfoLine: "Sound: ", origName$[.s], if sNch[.s] > 1 then "  (channel " + string$ (sCh[.s]) + " of " + string$ (sNch[.s]) + ")" else "" fi
	.t0 = slotT1[.k] - sXmin[.s]
	.t0$ = if abs (.t0) < 0.0005 then "0.000" else fixed$ (.t0, 3) fi
	appendInfoLine: "Window: start ", .t0$, " s | duration ", fixed$ (slotTw[.k], 3), " s | analysis range 20-", fixed$ (fmaxEff, 0), " Hz"
	if slotF0[.k] = undefined
		appendInfoLine: "F0: unavailable (", slotF0note$[.k], ")"
		appendInfoLine: "Harmonic analysis unavailable for this window; H1-H10 are not reported."
	elsif slotModel$[.k] = "unresolved" or slotModel$[.k] = "unavailable"
		appendInfoLine: "F0: ", fixed$ (slotF0[.k], 1), " Hz (", slotF0src$[.k], ")"
		appendInfoLine: "Harmonic analysis unavailable for this window (", slotF0note$[.k], "); H1-H10 are not reported."
	else
		.ref = slotMaxDb[.k]
		.st$ = "harmonic pattern " + slotModel$[.k]
		if slotF0note$[.k] <> ""
			.st$ = .st$ + "; WARNING " + slotF0note$[.k]
		endif
		appendInfoLine: "F0: ", fixed$ (slotF0[.k], 1), " Hz (", slotF0src$[.k], ") | status: ", .st$
		appendInfoLine: "Strongest measured component: ", fixed$ (slotMaxHz[.k], 1), " Hz at ", fixed$ (.ref, 1), " dBFS"
		appendInfoLine: ""
		@padR: "Harmonic", 10
		.l$ = padR.out$
		@padL: "Expected Hz", 12
		.l$ = .l$ + padL.out$
		@padL: "Measured Hz", 13
		.l$ = .l$ + padL.out$
		@padL: "Level dBFS", 12
		.l$ = .l$ + padL.out$
		@padL: "Relative dB", 13
		.l$ = .l$ + padL.out$
		@padL: "Deviation (cents)", 19
		.l$ = .l$ + padL.out$
		appendInfoLine: .l$, "   Status"
		appendInfoLine: "---------------------------------------------------------------------------------------------"
		for .h to 10
			.fe = .h * slotF0[.k]
			.meas$ = "--"
			.lev$ = "--"
			.rel$ = "--"
			.dev$ = "--"
			if .fe > fmaxEff
				.stat$ = "Out of range"
			elsif hStat##[.k, .h] = 1
				.f = hFreq##[.k, .h]
				# analysis level: undo any display-only shift
				.d = hDb##[.k, .h] - slotShift[.k]
				if .f = undefined or .d = undefined or .f <= 0
					.stat$ = "Unavailable"
				else
					.stat$ = "Validated"
					@fmt1: .f
					.meas$ = fmt1.out$
					@fmt1: .d
					.lev$ = fmt1.out$
					@fmt1: .d - .ref
					.rel$ = fmt1.out$
					# deviation from the ideal harmonic series, from the
					# unrounded measured and expected frequencies
					.cents = round (1200 * log2 (.f / .fe))
					.dev$ = if .cents > 0 then "+" + string$ (.cents) else string$ (.cents) fi
				endif
			else
				.stat$ = "Missing"
			endif
			@padR: "H" + string$ (.h), 10
			.l$ = padR.out$
			@fmt1: .fe
			@padL: fmt1.out$, 12
			.l$ = .l$ + padL.out$
			@padL: .meas$, 13
			.l$ = .l$ + padL.out$
			@padL: .lev$, 12
			.l$ = .l$ + padL.out$
			@padL: .rel$, 13
			.l$ = .l$ + padL.out$
			@padL: .dev$, 19
			.l$ = .l$ + padL.out$
			appendInfoLine: .l$, "   ", .stat$
		endfor
		# what the cents column is measured against
		if index (slotF0src$[.k], "peak-refined") > 0
			.ref$ = "an F0 fitted to the validated peaks of this window, so the column shows departures from that fitted series"
		elsif slotF0src$[.k] = "user-specified"
			.ref$ = "the user-specified F0"
		else
			.ref$ = "the F0 of the Pitch analysis (" + slotF0src$[.k] + ")"
		endif
		appendInfoLine: "Deviation (cents) = 1200 x log2 (measured / (n x F0)): deviation from the ideal harmonic series, not from equal temperament."
		appendInfoLine: "It is referenced to ", .ref$, ". It is an estimate: pitch movement within the window and peak-frequency precision (window ", fixed$ (slotTw[.k] * 1000, 0), " ms, Hann -3 dB width ", fixed$ (1.44 / slotTw[.k], 1), " Hz) also produce small deviations."
	endif
endproc

# One decimal, rounded first; never prints "-0.0" or fixed$'s bare "0"
procedure fmt1: .x
	.r = round (.x * 10) / 10
	if abs (.r) < 0.05
		.out$ = "0.0"
	else
		.out$ = fixed$ (.r, 1)
	endif
endproc

# Fixed-width columns (Praat has no pad primitive)
procedure padL: .s$, .w
	while length (.s$) < .w
		.s$ = " " + .s$
	endwhile
	padL.out$ = .s$
endproc

procedure padR: .s$, .w
	while length (.s$) < .w
		.s$ = .s$ + " "
	endwhile
	padR.out$ = .s$
endproc

# --------------------------------------------------------------------
# Visualization
# --------------------------------------------------------------------
# Word wrap of .t$ into findLine$[] by measured text width (8 pt, findings
# strip axes 0..1, usable width 0.97), at most .maxLines lines; a cut zone
# ends with "(see Info)".
procedure wrapMeasured: .t$, .maxLines, .col$
	.n = 0
	.avail = 0.97
	.guard = 0
	Font size: 8
	Select inner viewport: 0.48, 7.82, 7.05, 7.92
	Axes: 0, 1, 0, 1
	while length (.t$) > 0 and .n < .maxLines and .guard < 50
		.guard += 1
		@textW: .t$
		if textW.w <= .avail
			.line$ = .t$
			.t$ = ""
		else
			# longest word-prefix that fits
			.line$ = ""
			.rest$ = .t$
			.done = 0
			.g2 = 0
			while .done = 0 and .g2 < 500
				.g2 += 1
				.sp = index (.rest$, " ")
				if .sp = 0
					.word$ = .rest$
				else
					.word$ = left$ (.rest$, .sp - 1)
				endif
				.cand$ = if .line$ = "" then .word$ else .line$ + " " + .word$ fi
				@textW: .cand$
				if textW.w > .avail and .line$ <> ""
					.done = 1
				elsif textW.w > .avail
					# a single word wider than the line: cut it by characters
					@fitChars: .word$, .avail
					.line$ = fitChars.out$
					.rest$ = right$ (.rest$, length (.rest$) - length (.line$))
					.done = 1
				else
					.line$ = .cand$
					if .sp = 0
						.rest$ = ""
						.done = 1
					else
						.rest$ = right$ (.rest$, length (.rest$) - .sp)
					endif
				endif
			endwhile
			.t$ = .rest$
		endif
		.n += 1
		if .n = .maxLines and length (.t$) > 0
			# last permitted line: end it with the marker, cutting by
			# characters so that the result always fits
			@textW: " ... (see Info)"
			@fitChars: .line$ + " " + .t$, .avail - textW.w
			.line$ = fitChars.out$ + " ... (see Info)"
			# verify the final string (kerning) and trim until it fits
			@textW: .line$
			.g3 = 0
			while textW.w > .avail and length (fitChars.out$) > 1 and .g3 < 200
				.g3 += 1
				fitChars.out$ = left$ (fitChars.out$, length (fitChars.out$) - 1)
				.line$ = fitChars.out$ + " ... (see Info)"
				@textW: .line$
			endwhile
			.t$ = ""
		endif
		nFind += 1
		findLine$[nFind] = replace$ (.line$, "~", " ", 0)
		findCol$[nFind] = .col$
	endwhile
endproc

# Measured width (current font and axes) of the text as it will be drawn
procedure textW: .s$
	@safe: replace$ (.s$, "~", " ", 0)
	.w = Text width (world coordinates): safe.out$
endproc

# Longest character prefix of .s$ whose drawn width fits in .avail
# (bisection on the length; always returns at least one character)
procedure fitChars: .s$, .avail
	.lo = 1
	.hi = length (.s$)
	while .lo < .hi
		.mid = ceiling ((.lo + .hi) / 2)
		@textW: left$ (.s$, .mid)
		if textW.w <= .avail
			.lo = .mid
		else
			.hi = .mid - 1
		endif
	endwhile
	.out$ = left$ (.s$, .lo)
endproc

procedure metaLine: .y1, .y2, .t$
	# .t$ is already markup-safe. Try 8, 7 and 6 pt; if it still does not
	# fit, cut it at 6 pt and end it with "..." (full values are in Info).
	.size = 9
	.w = 2
	while .w > 1.0 and .size > 6
		.size -= 1
		Font size: .size
		Select inner viewport: 0.6, 7.7, .y1, .y2
		Axes: 0, 1, 0, 1
		.w = Text width (world coordinates): .t$
	endwhile
	if .w > 1.0
		.lo = 1
		.hi = length (.t$)
		while .lo < .hi
			.mid = ceiling ((.lo + .hi) / 2)
			.w = Text width (world coordinates): left$ (.t$, .mid) + "..."
			if .w <= 1.0
				.lo = .mid
			else
				.hi = .mid - 1
			endif
		endwhile
		.t$ = left$ (.t$, .lo) + "..."
	endif
	@stripText: .y1, .y2, .size, 0.5, "centre", .t$
endproc

procedure niceStep: .span, .n
	.raw = .span / .n
	.p = 10 ^ floor (log10 (.raw))
	.r = .raw / .p
	if .r < 1.5
		.out = .p
	elsif .r < 3.5
		.out = 2 * .p
	elsif .r < 7.5
		.out = 5 * .p
	else
		.out = 10 * .p
	endif
endproc

procedure stripText: .y1, .y2, .size, .x, .align$, .text$
	Font size: .size
	Select inner viewport: 0.6, 7.7, .y1, .y2
	Axes: 0, 1, 0, 1
	Colour: "Black"
	Text: .x, .align$, 0.5, "half", .text$
endproc

procedure frameAxes: .y1, .y2, .f1, .f2, .d1, .d2, .xlab$, .ylab$
	Font size: 7
	Select inner viewport: 0.6, 7.7, .y1, .y2
	Axes: .f1, .f2, .d1, .d2
	Colour: "Black"
	Line width: 1
	Solid line
	Draw inner box
	Select inner viewport: 0.6, 7.7, .y1, .y2
	Axes: .f1, .f2, .d1, .d2
	# frequency labels written as plain numbers (Marks every would switch to
	# 10^4 notation above 9999 Hz)
	@niceStep: .f2 - .f1, 8
	.st = niceStep.out
	.m = ceiling (.f1 / .st - 1e-9) * .st
	while .m <= .f2 + 1e-9
		One mark bottom: .m, "no", "yes", "no", fixed$ (.m, if .st < 1 then 1 else 0 fi)
		.m += .st
	endwhile
	@niceStep: .d2 - .d1, 6
	Marks left every: 1, niceStep.out, "yes", "yes", "no"
	Text bottom: "yes", .xlab$
	Text left: "yes", .ylab$
endproc

# Draw a dB curve Sound clipped to the panel range
procedure drawCurve: .id, .f1, .f2, .d1, .d2, .col$, .lw, .style$
	Select inner viewport: 0.6, 7.7, panY1, panY2
	Axes: .f1, .f2, .d1, .d2
	Colour: .col$
	Line width: .lw
	if .style$ = "dashed"
		Dashed line
	elsif .style$ = "dotted"
		Dotted line
	else
		Solid line
	endif
	selectObject: .id
	Draw: .f1, .f2, .d1, .d2, "no", "Curve"
	Solid line
	Line width: 1
endproc

# Validated peaks as sticks
procedure drawSticks: .k, .d1, .d2, .col$
	Select inner viewport: 0.6, 7.7, panY1, panY2
	Axes: fminD, fmaxEff, .d1, .d2
	Colour: .col$
	Line width: 1.5
	for .h to slotNexp[.k]
		if hStat##[.k, .h] = 1 and hDb##[.k, .h] > .d1 and hFreq##[.k, .h] >= fminD
			Draw line: hFreq##[.k, .h], .d1, hFreq##[.k, .h], min (.d2, hDb##[.k, .h])
		endif
	endfor
	Line width: 1
endproc

# Expected-position ticks, validated-peak dots, missing-harmonic rings
procedure drawMarkers: .k, .d1, .d2, .col$, .row
	# Expected-position ticks and missing-harmonic rings are hidden when they
	# would be closer than 0.06 inch on the page; validated peaks stay.
	.dense = slotF0[.k] * 7.1 / (fmaxEff - fminD) < 0.06
	if .dense
		markDense = 1
	endif
	if slotModel$[.k] = "consistent" or slotModel$[.k] = "inconclusive"
		Select inner viewport: 0.6, 7.7, panY1, panY2
		Axes: fminD, fmaxEff, .d1, .d2
		.r = .d2 - .d1
		.yb = .d1 + (0.015 + 0.045 * (.row - 1)) * .r
		for .h to slotNexp[.k]
			.fe = .h * slotF0[.k]
			if hStat##[.k, .h] = 1
				if not .dense and .fe >= fminD
					Colour: colTick$
					Draw line: .fe, .d1, .fe, .yb + 0.02 * .r
				endif
				if hDb##[.k, .h] > .d1 and hFreq##[.k, .h] >= fminD
					Paint circle (mm): .col$, hFreq##[.k, .h], min (.d2, hDb##[.k, .h]), 1.1
				endif
			elsif not .dense and .fe >= fminD
				Colour: colMiss$
				Draw line: .fe, .d1, .fe, .yb + 0.02 * .r
				Draw circle (mm): .fe, .yb + 0.02 * .r, 1.1
			endif
		endfor
	endif
endproc

procedure drawPeakEnvelope: .k, .d1, .d2, .col$
	if slotNval[.k] >= 2
		Select inner viewport: 0.6, 7.7, panY1, panY2
		Axes: fminD, fmaxEff, .d1, .d2
		Colour: .col$
		Line width: 2
		.prev = 0
		for .h to slotNexp[.k]
			if hStat##[.k, .h] = 1
				if .prev > 0
					if .h - .prev > 2
						Dotted line
					else
						Solid line
					endif
					.xa = hFreq##[.k, .prev]
					.xb = hFreq##[.k, .h]
					.ya = hDb##[.k, .prev]
					.yb = hDb##[.k, .h]
					if .xb > fminD
						if .xa < fminD
							.ya = .ya + (.yb - .ya) * (fminD - .xa) / (.xb - .xa)
							.xa = fminD
						endif
						Draw line: .xa, max (.d1, min (.d2, .ya)), .xb, max (.d1, min (.d2, .yb))
					endif
				endif
				.prev = .h
			endif
		endfor
		Solid line
		Line width: 1
		for .h to slotNexp[.k]
			if hStat##[.k, .h] = 1 and hDb##[.k, .h] > .d1 and hFreq##[.k, .h] >= fminD
				Paint circle (mm): .col$, hFreq##[.k, .h], min (.d2, hDb##[.k, .h]), 1.0
			endif
		endfor
	endif
endproc

# Legend entry: kind = line / dashed / dotted / dot / ring / tick
procedure legendItem: .x, .kind$, .col$, .label$
	Select inner viewport: 0.6, 7.7, legY1, legY2
	Axes: 0, 1, 0, 1
	Colour: .col$
	Line width: 1.5
	if .kind$ = "line"
		Draw line: .x, 0.5, .x + 0.035, 0.5
	elsif .kind$ = "dashed"
		Dashed line
		Draw line: .x, 0.5, .x + 0.035, 0.5
		Solid line
	elsif .kind$ = "dotline"
		Draw line: .x, 0.5, .x + 0.035, 0.5
		Paint circle (mm): .col$, .x + 0.0175, 0.5, 1.0
	elsif .kind$ = "dot"
		Paint circle (mm): .col$, .x + 0.0175, 0.5, 1.1
	elsif .kind$ = "ring"
		Draw circle (mm): .x + 0.0175, 0.5, 1.1
	elsif .kind$ = "tick"
		Draw line: .x + 0.0175, 0.2, .x + 0.0175, 0.8
	endif
	Line width: 1
	Font size: 7
	Select inner viewport: 0.6, 7.7, legY1, legY2
	Axes: 0, 1, 0, 1
	Colour: "Black"
	Text: .x + 0.045, "left", 0.5, "half", .label$
	# next free position: symbol + gap + approximate text width at 7 pt
	legendNext = .x + 0.07 + 0.0074 * length (.label$)
endproc

procedure drawFigure
	Erase all
	Helvetica
	Select outer viewport: 0, 8, 0, 8
	Colour: "Black"
	Line width: 1
	Solid line
	twoPanels = mode = 4 or envelope > 1
	noPeakNote$ = ""

	# ---- title and metadata ----
	Font size: 14
	Select outer viewport: 0, 8, 0.00, 0.48
	Axes: 0, 1, 0, 1
	Text: 0.5, "centre", 0.62, "half", "##Spectrum & Envelope Lab##"

	# each name is shortened on its own (45 characters) so that both A and B
	# stay visible; full names are in the Info window and the Table
	for .i to nSel
		.nm$ = origName$[.i]
		if length (.nm$) > 45
			.nm$ = left$ (.nm$, 42) + "..."
		endif
		@safe: .nm$
		.disp$[.i] = safe.out$
	endfor
	if nSel = 1
		.names$ = .disp$[1]
	else
		.names$ = "A = " + .disp$[1] + "   B = " + .disp$[2]
	endif
	.chInfo$ = ""
	for .i to nSel
		if sNch[.i] > 1
			.chInfo$ = .chInfo$ + "  ch " + string$ (sCh[.i]) + "/" + string$ (sNch[.i])
		endif
	endfor
	.win$ = ""
	for .k to nSlot
		.s = slotSnd[.k]
		@safe: slotLabel$[.k]
		.win$ = .win$ + safe.out$ + " " + fixed$ (slotT1[.k] - sXmin[.s], 3) + "-" + fixed$ (slotT2[.k] - sXmin[.s], 3) + " s   "
	endfor
	# Metadata: three lines (Sounds and mode / windows / F0 and ranges); a
	# line that is wider than the page at 8 pt is drawn at 7 pt.
	.m1$ = .names$ + .chInfo$ + "   |   " + modeName$[mode]
	.m2$ = .win$ + "|  Hann"
	if mode = 4
		.m2$ = .m2$ + ", centred on " + centreSource$
	elsif mode = 2 and autoWin$ <> ""
		.m2$ = .m2$ + ", automatic attack / middle windows"
	endif
	.m3$ = "F0: "
	for .k to nSlot
		if mode <> 4 or .k = nSlot
			if slotF0[.k] = undefined
				.m3$ = .m3$ + "unavailable "
			else
				.m3$ = .m3$ + fixed$ (slotF0[.k], 1) + " Hz "
			endif
		endif
	endfor
	.m3$ = .m3$ + " |  analysis 20-" + fixed$ (fmaxEff, 0) + " Hz"
	if fminD > 0
		.m3$ = .m3$ + ", display from " + fixed$ (fminD, 0) + " Hz"
	endif
	if nyquistLimited
		.m3$ = .m3$ + " (Nyquist-limited)"
	endif
	@metaLine: 0.49, 0.64, .m1$
	@metaLine: 0.64, 0.79, .m2$
	@metaLine: 0.79, 0.94, .m3$

	# ---- panel geometry ----
	if twoPanels
		p1top = 1.50
		p1bot = 3.95
		p2top = 4.98
		p2bot = 6.55
	else
		p1top = 1.50
		p1bot = 6.55
	endif

	# ===== Panel 1: measured spectra =====
	if mode = 4
		.t1$ = "##Measured spectra for " + string$ (nSlot) + " window lengths## (same centre time, Hann)"
	elsif mode = 1
		.t1$ = "##Measured spectrum and harmonic evidence##"
	else
		.t1$ = "##Measured spectra A and B on matched axes##"
	endif
	@stripText: 1.02, 1.22, 9, 0, "left", .t1$
	legY1 = 1.23
	legY2 = 1.41
	panY1 = p1top
	panY2 = p1bot
	Font size: 7
	Select inner viewport: 0.6, 7.7, panY1, panY2
	Axes: fminD, fmaxEff, dbMin, dbMax
	Paint rectangle: "{0.99, 0.99, 0.99}", fminD, fmaxEff, dbMin, dbMax

	if mode = 4
		legendNext = 0.02
		for .k to nSlot
			@drawCurve: slotCurve[.k], fminD, fmaxEff, dbMin, dbMax, colD$[.k], if .k = nSlot then 1.4 else 1 fi, "solid"
			@legendItem: legendNext, "line", colD$[.k], slotLabel$[.k]
		endfor
		@legendItem: legendNext, "tick", colTick$, "zoom band below"
		# mark the zoom band
		zoomHalf = min (fmaxEff / 2, max (5 / slotTw[1], 3 * (if slotF0[nSlot] <> undefined then slotF0[nSlot] else 0 fi)))
		if labBandOK
			zf1 = max (fminD, labFreq - zoomHalf)
			zf2 = min (fmaxEff, labFreq + zoomHalf)
		else
			zf1 = fminD
			zf2 = fmaxEff
		endif
		Select inner viewport: 0.6, 7.7, panY1, panY2
		Axes: fminD, fmaxEff, dbMin, dbMax
		Colour: colTick$
		Dotted line
		if zf1 > fminD
			Draw line: zf1, dbMin, zf1, dbMax
		endif
		if zf2 > fminD
			Draw line: zf2, dbMin, zf2, dbMax
		endif
		Solid line
	else
		.x = 0.02
		markDense = 0
		noPeakNote$ = ""
		for .k to nSlot
			if nSlot = 1
				.col$ = colSpec$
				.mcol$ = colA$
			else
				.col$ = if .k = 1 then colA$ else colB$ fi
				.mcol$ = .col$
			endif
			@safe: slotLabel$[.k]
			.lab$ = if nSlot = 1 then "" else safe.out$ + ": " fi
			if spectrum_display = 1 or spectrum_display = 3
				@drawCurve: slotCurve[.k], fminD, fmaxEff, dbMin, dbMax, .col$, 1, "solid"
				@legendItem: .x, "line", .col$, .lab$ + if nSlot = 1 then "measured spectrum" else "spectrum" fi
				.x = legendNext
			endif
			if spectrum_display = 2
				if slotNval[.k] = 0
					# no validated peak: show the measured spectrum faintly so an
					# empty plot is never read as "no energy"
					@drawCurve: slotCurve[.k], fminD, fmaxEff, dbMin, dbMax, "{0.62, 0.62, 0.66}", 1, "solid"
					noPeakNote$ = noPeakNote$ + if noPeakNote$ = "" then "" else ", " fi + slotLabel$[.k]
				else
					@drawSticks: .k, dbMin, dbMax, .col$
					@legendItem: .x, "tick", .col$, .lab$ + "validated peaks"
					.x = legendNext
				endif
			endif
			if spectrum_display >= 2
				@drawMarkers: .k, dbMin, dbMax, .mcol$, .k
			endif
		endfor
		.anyHarm = 0
		for .k to nSlot
			if slotModel$[.k] = "consistent" or slotModel$[.k] = "inconclusive"
				.anyHarm = 1
			endif
		endfor
		if spectrum_display >= 2 and .anyHarm
			if spectrum_display = 3
				@legendItem: .x, "dot", colA$, if nSlot = 1 then "validated peak" else "peak (window colour)" fi
				.x = legendNext
			endif
			if spectrum_display = 2 and noPeakNote$ <> ""
				@legendItem: .x, "line", colContext$, "spectrum"
				.x = legendNext
			endif
			if markDense
				Font size: 7
				Select inner viewport: 0.6, 7.7, legY1, legY2
				Axes: 0, 1, 0, 1
				Colour: colTick$
				Text: .x, "left", 0.5, "half", "k x F0 marks hidden (closer than 0.06 inch)"
				Colour: "Black"
			else
				@legendItem: .x, "tick", colTick$, "k x F0"
				.x = legendNext
				@legendItem: .x, "ring", colMiss$, "no validated peak"
			endif
		endif
	endif
	if mode <> 4 and spectrum_display = 2 and noPeakNote$ <> ""
		if nSlot = 1
			.msg$ = "No validated harmonic peaks under the current settings; grey = measured spectrum."
		else
			.msg$ = "No validated harmonic peaks for " + noPeakNote$ + "; grey = its measured spectrum."
		endif
		@safe: .msg$
		Font size: 7
		Select inner viewport: 0.6, 7.7, panY1, panY2
		Axes: 0, 1, 0, 1
		.w = Text width (world coordinates): safe.out$
		Paint rectangle: "{1.0, 1.0, 1.0}", 0.5 - .w / 2 - 0.01, 0.5 + .w / 2 + 0.01, 0.90, 0.98
		Font size: 7
		Select inner viewport: 0.6, 7.7, panY1, panY2
		Axes: 0, 1, 0, 1
		Colour: colMiss$
		Text: 0.5, "centre", 0.94, "half", safe.out$
		Colour: "Black"
	endif
	@frameAxes: panY1, panY2, fminD, fmaxEff, dbMin, dbMax, "Frequency (Hz)", axisLabel$

	# ===== Panel 2 =====
	if twoPanels
		legY1 = 4.71
		legY2 = 4.89
		panY1 = p2top
		panY2 = p2bot
		if mode = 4
			if labBandOK
				@stripText: 4.50, 4.70, 9, 0, "left", "##Zoom around " + fixed$ (labFreq, 0) + " Hz## (strongest displayed peak of the longest window)"
			else
				@stripText: 4.50, 4.70, 9, 0, "left", "##Displayed range " + fixed$ (zf1, 0) + "-" + fixed$ (zf2, 0) + " Hz## (too narrow for a peak-width measurement)"
			endif
			.zd2 = dbMax
			.zd1 = dbMax - min (60, dynamic_range)
			Font size: 7
			Select inner viewport: 0.6, 7.7, panY1, panY2
			Axes: zf1, zf2, .zd1, .zd2
			Paint rectangle: "{0.99, 0.99, 0.99}", zf1, zf2, .zd1, .zd2
			if slotF0[nSlot] <> undefined
				Select inner viewport: 0.6, 7.7, panY1, panY2
				Axes: zf1, zf2, .zd1, .zd2
				Colour: colTick$
				Dotted line
				.h = ceiling (zf1 / slotF0[nSlot])
				while .h * slotF0[nSlot] <= zf2
					if .h >= 1
						Draw line: .h * slotF0[nSlot], .zd1, .h * slotF0[nSlot], .zd2
					endif
					.h += 1
				endwhile
				Solid line
			endif
			for .k to nSlot
				@drawCurve: slotCurve[.k], zf1, zf2, .zd1, .zd2, colD$[.k], if .k = nSlot then 1.4 else 1.2 fi, "solid"
			endfor
			legendNext = 0.02
			for .k to nSlot
				@legendItem: legendNext, "line", colD$[.k], slotLabel$[.k]
			endfor
			if slotF0[nSlot] <> undefined
				@legendItem: legendNext, "tick", colTick$, "expected k x F0"
			endif
			@frameAxes: panY1, panY2, zf1, zf2, .zd1, .zd2, "Frequency (Hz)", axisLabel$
		else
			if envelope = 2
				.t2$ = "##Peak-derived envelope##"
			elsif envelope = 3
				.t2$ = "##Cepstral envelope## (" + fixed$ (cepstral_smoothing, 0) + " Hz smoothing)"
			else
				.t2$ = "##Peak-derived vs cepstral envelope## (" + fixed$ (cepstral_smoothing, 0) + " Hz smoothing)"
			endif
			if align_cepstral_display and envelope >= 3
				.t2$ = .t2$ + "   cepstral curve aligned for display only"
			endif
			# Panel 2 keeps the common top but extends its floor, when needed,
			# so that a cepstral envelope lying below the spectrum range is
			# drawn where it is instead of being clipped onto the frame.
			e1 = dbMin
			if envelope >= 3
				for .k to nSlot
					selectObject: slotCep[.k]
					.cMin = Get minimum: 20, fmaxEff, "None"
					e1 = min (e1, 10 * floor ((.cMin - 3) / 10))
				endfor
				.clipped = e1 < dbMax - 160
				e1 = max (e1, dbMax - 160)
			else
				.clipped = 0
			endif
			if e1 < dbMin
				.t2$ = .t2$ + "   range extended to " + fixed$ (e1, 0) + " dB"
			endif
			if .clipped
				.t2$ = .t2$ + " (lower values drawn on the frame)"
			endif
			@stripText: 4.50, 4.70, 9, 0, "left", .t2$
			Font size: 7
			Select inner viewport: 0.6, 7.7, panY1, panY2
			Axes: fminD, fmaxEff, e1, dbMax
			Paint rectangle: "{0.99, 0.99, 0.99}", fminD, fmaxEff, e1, dbMax
			# faint measured spectra as context
			for .k to nSlot
				@drawCurve: slotCurve[.k], fminD, fmaxEff, e1, dbMax, colContext$, 1, "solid"
			endfor
			.x = 0.02
			.peakMissing$ = ""
			for .k to nSlot
				if nSlot = 1
					.cP$ = colPeakEnv$
					.cC$ = colCep$
				else
					.cP$ = if .k = 1 then colA$ else colB$ fi
					.cC$ = .cP$
				endif
				@safe: slotLabel$[.k]
				.lab$ = if nSlot = 1 then "" else safe.out$ + ": " fi
				if envelope = 3 or envelope = 4
					@drawCurve: slotCep[.k], fminD, fmaxEff, e1, dbMax, .cC$, 1.8, if nSlot = 1 then "solid" else "dashed" fi
					@legendItem: .x, if nSlot = 1 then "line" else "dashed" fi, .cC$, .lab$ + "cepstral"
					.x = legendNext
				endif
				if envelope = 2 or envelope = 4
					if slotModel$[.k] = "consistent"
						@drawPeakEnvelope: .k, e1, dbMax, .cP$
						@legendItem: .x, "dotline", .cP$, .lab$ + "peak-derived"
						.x = legendNext
					else
						.peakMissing$ = .peakMissing$ + " " + slotLabel$[.k]
					endif
				endif
			endfor
			@legendItem: .x, "line", colContext$, "spectrum"
			.x = legendNext
			if .peakMissing$ <> ""
				@safe: .peakMissing$
				Font size: 7
				Select inner viewport: 0.6, 7.7, legY1, legY2
				Axes: 0, 1, 0, 1
				Colour: colMiss$
				Text: .x, "left", 0.5, "half", "no peak envelope for" + safe.out$ + " (harmonic pattern not consistent)"
				Colour: "Black"
			endif
			@frameAxes: panY1, panY2, fminD, fmaxEff, e1, dbMax, "Frequency (Hz)", axisLabel$
		endif
	endif

	# ===== Findings strip =====
	# Three zones: finding 1 (up to 2 lines), finding 2 (fills what is left),
	# cue (up to 2 lines, always shown). Lines are wrapped by the MEASURED
	# text width at 8 pt; a zone that does not fit ends with "(see Info)".
	# The full text is always in the Info window.
	Font size: 8
	Select inner viewport: 0.48, 7.82, 7.05, 7.92
	Axes: 0, 1, 0, 1
	Paint rectangle: "{0.94, 0.94, 0.94}", 0, 1, 0, 1
	nFind = 0
	@wrapMeasured: cue$, 2, "{0.20, 0.40, 0.80}"
	.nCue = wrapMeasured.n
	for .i to .nCue
		cueLine$[.i] = findLine$[.i]
	endfor
	nFind = 0
	@wrapMeasured: find1$, 2, "Black"
	if find2$ <> ""
		@wrapMeasured: find2$, 5 - .nCue - nFind, "Black"
	endif
	for .i to .nCue
		nFind += 1
		findLine$[nFind] = cueLine$[.i]
		findCol$[nFind] = "{0.20, 0.40, 0.80}"
	endfor
	.rows = max (3, nFind)
	for .i to nFind
		@safe: findLine$[.i]
		Font size: 8
		Select inner viewport: 0.48, 7.82, 7.05, 7.92
		Axes: 0, 1, 0, 1
		Colour: findCol$[.i]
		Text: 0.012, "left", 1 - (.i - 0.5) / .rows, "half", safe.out$
	endfor
	Colour: "Black"
	Select inner viewport: 0.48, 7.82, 7.05, 7.92
	Axes: 0, 1, 0, 1
	Draw rectangle: 0, 1, 0, 1

	# restore drawing state
	Font size: 10
	Line width: 1
	Solid line
	Colour: "Black"
	Select outer viewport: 0, 8, 0, 8
endproc
