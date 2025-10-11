# Praat Plugin: AudioTools

**Author:** [Shai Cohen](https://music.biu.ac.il/en/ShaiCohen)  
**Affiliation:** Department of Music, Bar-Ilan University, Israel  
**YouTube:** [@Shai_Cohen](https://www.youtube.com/@Shai_Cohen/videos)

---

## Overview

**Praat AudioTools** is a collection of more than one hundred scripts for **audio processing, analysis, and synthesis** in [Praat](http://www.praat.org).  
The plugin adds a unified **AudioTools** menu to Praat, offering a wide range of effects, filters, transformations, and creative analysis-driven tools for sound design and experimental composition.

Developed for composers, sound designers, and researchers, the toolkit extends Praat’s phonetic analysis environment into a **complete offline sound laboratory** — enabling processes such as granular synthesis, adaptive filtering, spectral manipulation, fractal reverbs, and multichannel spatialisation.

---

## Installation

1. **Download or clone** this repository.  
   ```bash
   git clone https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools.git

2. Locate your Praat plugins folder.
Depending on your operating system, Praat looks for plugins here:

Windows:   C:\Users\<YourName>\Praat\plugins\

macOS:     ~/Library/Preferences/Praat/plugins/ 

Linux:     ~/.praat-dir/plugins/


Copy the folder plugin_AudioTools into the plugins directory.
Restart Praat.

## Scripts Documentation

https://mashav.com/sha/praat/scripts/index.html

## Script Categories

### <a id="analysis"></a> Analysis (23 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `compare loudness`
* `compare pitch`
* `descriptions`
* `DTW for 2 files`
* `duration_all_files`
* `extract portion`
* `Extraction`
* `HarmonicityS_all_files`
* `Intensity_all_files`
* `Jitter (local)_new`
* `jitter_all_files`
* `Maximum pitch`
* `maximum_pitch_all_files`
* `mean_pitch_all_files`
* `MFCC`
* `minimum pitch_all_files`
* `Recursive WAV opener`
* `shimmer_local`
* `Spectral Flatness and Roughness`
* `spectral roll-off frequency`
* `speech activity`
* `SPR_all_files_new`
* `voice report`
</details>

### <a id="delay"></a> Delay (16 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `ADAPTIVE GRAIN CLOUD SYNTHESIS`
* `delay_array`
* `Evolving Granular`
* `Fractal_Convolution_Matrix`
* `Harmonic_Resonance`
* `Magnetic_Tape_Degradation`
* `Phase_Modulation_Matrix`
* `Quantum_State_Superposition`
* `Sorts grains from dark to bright`
* `Sound to Grain`
* `Sound to Grain (Stereo with Independent Reversal)`
* `Spectral_Echo_Cascade`
* `Spectral_Freeze_&_Glitch`
* `Stereo Delay Splitter`
* `Stochastic_Time_Folding`
* `Time Manipulation`
</details>

### <a id="distortion"></a> Distortion (8 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Adaptive Wave Shaper`
* `abs`
* `Chaos Distortion`
* `crunchy`
* `crunchy_2`
* `tanh`
* `Wave Shaper Distortion`
* `Wavefolder Distortion`
</details>

### <a id="dynamics"></a> Dynamics (16 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Compressor`
* `Fast Waveset Distortion`
* `Intensity_Early_Arrival`
* `Intensity_Rhythmic_Gating`
* `Intensity_Sine_Modulation`
* `Intensity_Squaring`
* `Intensity_Time_Compression`
* `Intensity_Time_Delay`
* `Intensity_Time_Stretch`
* `Intensity_Wave_Inversion`
* `Limiter`
* `Linear Fade-In`
* `Linear Fade-out`
* `Multiband Compressor`
* `Noise Gate`
* `Waveset Distortion`
</details>

### <a id="fft"></a> FFT (32 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Basic Mirror`
* `Bell curve envelope`
* `Bright Modulation`
* `Doppler shift`
* `Dynamic Tremolo Effect`
* `Fast Chunked Spectral Blur`
* `flip or expand the F0 contours`
* `Gentle Low-Pass`
* `Harmonic Enhancer`
* `Harmonic Resonance Boost`
* `Hilbert Transform`
* `LPC Voice Generator`
* `LPC Voice Morphing`
* `Mirror at Harmonic Intervals`
* `Non-Linear Frequency Folding`
* `Oscillating amplitude with decay`
* `Partial Editing & Resynthesis`
* `Random Comb Filtering`
* `reversal with pulsing decay`
* `Reverse exponential`
* `Rhythmic Pulsing`
* `Rule-Based Evolution`
* `Spectral Comb Filter`
* `Spectral Filter with Exponential Fade`
* `Spectral swirl effect`
* `Stepped Notch Filter`
* `Subtle Random Texture`
* `Underwater`
* `Vocoding`
* `Wave Interference Pattern`
* `Wobble effect`
* `Wobbling frequency shift`
</details>

### <a id="filter"></a> Filter (27 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `a-e-i-o_filter`
* `Adaptive Low-pass Filter`
* `AMPLITUDE-VARYING RING MOD`
* `Bit Crusher (8-Bit Arcade)`
* `Creative Formant Manipulations`
* `Cross Synthesis`
* `CUBIC PHASE DISTORTION`
* `Dynamic Spectral Hole`
* `EXPONENTIAL FREQUENCY SWEEP`
* `Frequency Shifter (Pitch Warp)`
* `Hilbert Transform(for drums)`
* `Hum Removal using Formant Filtering`
* `Jitter-Shimmer Formant Mapping`
* `LOGARITHMIC FREQUENCY SWEEP`
* `MFCC Temporal Manipulations`
* `MFCC-based Sound Controller`
* `Panning filter`
* `QUADRATIC PHASE MODULATION`
* `Raised-cosine band boost`
* `Resonant`
* `SINUSOIDAL FREQUENCY MODULATION`
* `SPIRAL FREQUENCY MODULATION`
* `Time varying Ring Modulation`
* `Time-based jitter-shimmer to formant mapping`
* `TREMBLING RING MOD`
* `Working Adaptive Filter`
* `XMod`
</details>

### <a id="modulation"></a> Modulation (21 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Barber-Pole_Orbit`
* `Chaotic Prosody Manipulation`
* `Chirped_Vibrato`
* `Chorus`
* `Dual-Tap_Chorus`
* `Enveloped_Vibrato(attack-release)`
* `Fractal_Convolution_Swarm`
* `Golden-chaos_vibrato`
* `Lengthen`
* `Orbit_Chorus`
* `rate_modulation`
* `Rotary`
* `Spectral-Driven Intensity Modulation`
* `SpectralDrivenVibrato`
* `Stereo_Swirl_Vibrato`
* `Swarm_Vibrato_Stack`
* `TimeVaryingSpectralVibrato`
* `Tremolo`
* `tremolo_2`
* `vibrato`
* `wow_flutter`
</details>

### <a id="pitch"></a> Pitch (18 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Adaptive Pitch Shifter`
* `BREATHING_PITCH_WAVES`
* `building block`
* `canon`
* `canon_stereo`
* `Chord Generator from Audio`
* `Exponential Glide Up`
* `Formula Audio Manipulation`
* `FRACTAL_ PITCH_TERRAIN`
* `globally change the pitch and duration`
* `Mix_pitch`
* `Pitch change (semitones)`
* `Pitch Stylization and Shift`
* `PITCH_MORPHING_BETWEEN_TARGETS`
* `QUANTUM_PITCH_JUMPS`
* `RHYTHMIC PITCH PERCUSSION`
* `SpectralPitchShifter`
* `SPIRAL_PITCH_DANCE`
</details>

### <a id="reverb"></a> Reverb (33 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `Cascading_Echoes`
* `Chaotic_Bloom`
* `convolve`
* `convolve_ACCELERANDO`
* `convolve_BOUNCING BALL`
* `convolve_BURSTS`
* `convolve_EUCLIDEAN RHYTHM`
* `convolve_Fibonacci`
* `convolve_Fibonacci_random jitter`
* `convolve_GOLDEN-ANGLE DRIFT`
* `convolve_PING-PONG`
* `convolve_RANDOM WALK`
* `convolve_STEREO`
* `convolve_SWING`
* `Crystalline_Cascade`
* `Fractal Feedback`
* `Fractal_Feedback_Reverb`
* `Granular_Displacement`
* `Gravitational_Lens_ Reverb`
* `Harmonic Decay Reverb`
* `Harmonic_Comb`
* `Morphing_Resonance`
* `PING-PONG FIELD`
* `Quantum_Flutter`
* `Quantum_Uncertainty_Reverb`
* `RIBBON_SHIMMER`
* `Simple_Experimental_Reverberation`
* `Spectral_Decay`
* `Spectral_Drift`
* `Spectral_Smearing Reverb`
* `stereo_shimmer`
* `Temporal_Erosion`
* `Temporal_Warpping`
</details>

### <a id="spatial"></a> Spatial (14 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `4-Channel Canon`
* `8 - Odd forward Even reversed`
* `8-Channel Canon`
* `8-Channel Delay`
* `8-Channel movments`
* `8-channel speed deviations`
* `Add signals`
* `BPM_Panning`
* `BPM_SURROUND _Panning`
* `Fast Spectral Swirl Multi-Channel`
* `Mix selected multi-channel Sound into stereo`
* `Panning variations`
* `Simple Rate Panning`
* `SpectralPanningMapper`
</details>

### <a id="synthesis"></a> Synthesis (45 Scripts)
<details>
<summary>Expand to view all scripts</summary>

* `accelerating-polyrhythm`
* `Advanced Brownian Synthesis`
* `Advanced Chaotic Modulation`
* `Advanced Formula Synthesis`
* `Advanced Poisson Synthesis`
* `Algorithmic Metallic Synthesis`
* `AM Additive Synthesis Generator`
* `Cellular Automata Synthesis`
* `Chaotic Granular Synthesis`
* `Competing Modulators`
* `Convolution Synthesis`
* `Dynamic Stochastic Synthesis`
* `Dynamic Vowel Transitions`
* `Evolutionary Formula`
* `Evolving Grain Mass`
* `Fast Game of Life Synthesis`
* `FM Texture Generator`
* `Formant Grain Texture`
* `Formant Synthesis`
* `Formula Markov Synthesis`
* `Generative Sound System`
* `Image Pitch Sonification`
* `Image Spectral Sonification`
* `Karplus-Strong Texture Generator`
* `Layered Markov Texture`
* `Logistic Map Synthesis`
* `Markov Rhythm Generator`
* `Minimal Game of Life`
* `Percussive Image Sonification`
* `Photo Sonification`
* `Poisson Point Process Synthesis`
* `Poisson Rhythm Synthesis`
* `polyrhythms-from-dots`
* `Random Walk Melody`
* `Random Walk Rhythm`
* `Rich Formant Grains`
* `Simple Cellular Automata`
* `Simple Grain Mass`
* `Simple Poisson Sound`
* `Simple Tier Control`
* `sonified-drawing`
* `Statistical Mass of Grains`
* `Stochastic Synthesis`
* `Subtractive Synthesis Generator`
* `Texture Generator`
* `Waveguide & Modal Synthesis`
</details>

## Citation

If you use this toolkit in academic work, please cite:
Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
GitHub Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools

## Acknowledgements

Praat by Paul Boersma & David Weenink, University of Amsterdam.
This plugin repurposes Praat’s scientific tools for creative sound design and electroacoustic composition.
