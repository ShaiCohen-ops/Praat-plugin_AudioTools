# Praat Plugin: AudioTools
**Author:** [Shai Cohen](https://music.biu.ac.il/en/ShaiCohen)  
**Affiliation:** Department of Music, Bar-Ilan University, Israel  
**YouTube:** [@Shai_Cohen](https://www.youtube.com/@Shai_Cohen/videos)

---

## Overview

**Praat AudioTools** is a collection of **415 scripts** across **13 categories** for **audio processing, analysis, and synthesis** in [Praat](http://www.praat.org).  
The plugin adds a unified **AudioTools** menu to Praat, bringing together effects, filters, transformations, generative processes, and analysis-driven tools for sound design and experimental composition.

Developed for composers, sound designers, and researchers, the toolkit extends Praat's phonetic analysis environment into a **complete offline sound laboratory** — enabling granular synthesis, adaptive filtering, spectral transformation, fractal reverbs, multichannel spatialisation, and machine learning-driven audio effects.

---

## Installation

1. **Download or clone** this repository.  
   ```bash
   git clone https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools.git
   ```
   Or [⬇️ download the entire package](plugin_AudioTools.zip) · [⬇️ download Audio Figures](AudioFigures.zip)

2. **Locate your Praat plugins folder.**  
   Depending on your operating system, Praat looks for plugins here:
   - **Windows:**   `C:\Users\<YourName>\Praat\plugins\`
   - **macOS:**     `~/Library/Preferences/Praat/plugins/`
   - **Linux:**     `~/.praat-dir/plugins/`

3. **Copy the folder** `plugin_AudioTools` into the plugins directory.  
   ⚠️ The folder name must be exactly `plugin_AudioTools`. If it differs, Praat will not display the AudioTools menu.

4. **Restart Praat.** After restarting, you should see a new **AudioTools** menu in the main Praat window.

---

## Scripts Documentation

**Interactive HTML documentation for all 415 scripts:**  
[https://mashav.com/sha/Praat%20AudioTools/](https://mashav.com/sha/Praat%20AudioTools/)

📖 [Detailed Script Overview](https://mashav.com/sha/Praat%20AudioTools/script-overview.html)

🎵 Did You Know? Algorithmic Music (1-Min Intros): [YouTube Playlist](https://www.youtube.com/playlist?list=PLgvns-wRHeYo-EcXGacjOwbmwA7vbSLW2)

The documentation includes searchable guides with detailed parameter descriptions, usage examples, and technical explanations for each script.

---

## Key Features

### 415 Scripts Across 13 Categories

| Category | Scripts |
|---|---|
| AI & Adaptive | 27 |
| Analysis | 36 |
| Distortion | 15 |
| Dynamics & Envelope | 19 |
| Filter & Color | 35 |
| Generative & Synthesis | 54 |
| Modulation | 23 |
| Pitch | 26 |
| Reverb | 29 |
| Spatial & Surround | 36 |
| Spectral | 26 |
| Time & Granular | 44 |
| Hybrid Systems | 49 |

### AI & Adaptive (27)
Neural-network, PCA, Bayesian, HMM, NMF, and self-attention based scripts for intelligent modulation, adaptive control, recomposition, classification, and phonetic-aware transformations. Includes Neural Audio Mosaic, PCA Timbre Selector, Genetic Recomposer, Granular Attention Resynth, and Self Attention Recomposer.
### Analysis (36)
Extract MFCCs, formants, pitch, loudness, jitter, shimmer, harmonicity, tempo curves, self-similarity matrices, chord profiles, and other descriptors for musical experimentation and acoustic research. Includes DTW-Aligned Multi-Feature Analysis, Krumhansl–Schmuckler Key Profiler, Speech to MusicXML Rhythm Converter, and Spatial Trajectory Tracker.
### Distortion (15)
Waveshaping, clipping, bit-crushing, and nonlinear processing tools. Includes Adaptive Wave Shaper, Chaos Distortion, Hysteresis Distortion, Multiband Distortion, Virtual Subharmonic Generator, and Wavefolder Distortion.
### Dynamics & Envelope (19)
Shape amplitude with compressors, multiband dynamics, limiters, noise gates, LUFS tools, swell generators, envelope processors, and mathematically defined amplitude trajectories. Includes Vintage Glue Compressor, Kinematic Physics Envelope, and Polynomial Envelope Shaper.
### Filter & Color (35)
Adaptive EQ, resonators, cross-synthesis, spectral morphing, formant filtering, frequency shifting, de-essing, hum removal, FIR/IIR filter banks, and timbral shaping tools. Includes GRM-Style Resonator, Moog Ladder Filter, MFCC Transformer, Intelligent EQ Adaptive Bandpass, and Jitter-Shimmer Formant Mapping.
### Generative & Synthesis (54)
Create sound from scratch using Markov models, stochastic processes, chaotic systems, cellular automata, Brownian motion, GENDYN-style methods, physical models, and formula-based synthesis. Includes GENDYN Synthesis, Pulsar Synthesis Engine, Karplus-Strong Texture Generator, Wave Terrain Synthesis, Grisey Spectral Becoming Engine, and Stockhausen Studie II Generator.
### Modulation (23)
LFO-driven and spectral modulation effects: vibrato, chorus, phaser, flanger, tremolo, wah-wah, and analysis-driven modulation. Includes Unified Multi-Mode Vibrato, Spectral Driven Vibrato, Metamodulator, Phonetic Tremolo-Glitch Effect, and XY Shape LFO.
### Pitch (26)
Pitch shifting, harmonization, tuning, PSOLA-based transformation, and microtonal tools. Includes Adaptive Pitch Shifter, Auto-Harmonic Layering, Breathing Pitch Waves, and analysis-driven pitch mapping and resynthesis.
### Reverb (29)
Convolution, algorithmic, fractal, and physically modelled reverberation. Includes Fractal Feedback Reverb, Gravitational Lens Reverb, Ray Tracing Room Acoustics, Quantum Uncertainty Reverb, The Lucier Machine, Ligeti Micropolyphonic Choir Machine, and Universal Convolution Generator.
### Spatial & Surround (36)
Multichannel spatialisation from stereo to 22.2, with panning laws, trajectory control, and HOA encoding/decoding. Includes 8-Channel Canon, 8-Channel Speed Deviations, Higher-Order Ambisonic Encoder/Decoder, DBAP with Movement Control, Hamasaki Square Ambience, and 22.2 Stem Renderer.
### Spectral (26)
FFT and phase-domain processing: spectral mirroring, freezing, blurring, phase manipulation, LPC morphing, and partial editing. Includes Spectral Freeze Synthesis, Fractal Spectral Hologram, LPC Voice Morphing, Self-Similarity Spectral Resynthesis, Phase Shaper, and Vocoding.
### Time & Granular (44)
Granular resynthesis, time-stretching, beat manipulation, and temporal recomposition. Includes Adaptive Grain Cloud Synthesis, Paulstretch, Stochastic Time Folding, Rhythmic Fractal Granulator, Phase Modulation Matrix, and Total Serialism Machine.
### Hybrid Systems (49)
Extended workflows bridging Praat with Python, Max/MSP, Ableton Live, IRCAM tools, and VST3 plugins, plus latent-space and AI-driven composition engines. Includes IRCAM SuperVP Transform, IRCAM RAVE Model, Latent Space Navigation, Phase-Space Composer, CNN Event Recomposer, and Praat for Max and M4L.

### Reproducible by Design
Scriptable parameters, seeds captured, versioned presets, optional ablation variants for method comparison.

### Interoperability for Composition
Cross-platform, with bridges to Python, Max/MSP, Ableton Live, VST3, and IRCAM tools.

---

## Citation

If you use this toolkit in academic work, please cite:

```
Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
GitHub Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
```

---

## License

MIT License

---

## Acknowledgements

**Praat** by Paul Boersma & David Weenink, University of Amsterdam.  
This plugin repurposes Praat's scientific tools for creative sound design and electroacoustic composition.

Special thanks to the Praat community and the Department of Music at Bar-Ilan University for supporting this research.
