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

### AI, Adaptive & Feature-Driven Processing
Neural-network, PCA, Bayesian, HMM, NMF, and self-attention based scripts for intelligent modulation, adaptive control, recomposition, classification, and phonetic-aware transformations.

### Advanced Analysis & Research Tools
Extract MFCCs, formants, pitch, loudness, jitter, shimmer, harmonicity, tempo curves, spatial trajectories, self-similarity matrices, and other descriptors for both musical experimentation and acoustic research.

### Filtering, Spectral Color & Resonance Design
Adaptive EQ, resonators, cross-synthesis, spectral morphing, formant filtering, frequency shifting, de-essing, hum removal, FIR/IIR filter banks, and detailed timbral shaping tools.

### Dynamics, Envelope & Amplitude Control
Compressors, multiband dynamics, limiters, gates, LUFS tools, envelope processors, fades, swell generators, and mathematically defined amplitude trajectories.

### Time, Granular, Pitch & Modulation Workflows
Granular resynthesis, time-stretching, pitch transformation, vibrato, chorus, phaser, flanger, tremolo, delay-based modulation, looping analysis, and rhythm-aware temporal manipulation.

### Generative Synthesis & Algorithmic Composition
Markov models, stochastic processes, chaotic systems, cellular automata, Brownian motion, GENDYN-style methods, sonification engines, and formula-based synthesis environments.

### Reverb, Spatialization & Hybrid Systems
Immersive multichannel textures with algorithmic reverbs, stereo and surround spatialisation, trajectory-based motion, and hybrid workflows connecting Praat with extended offline systems.

### Flagship Scripts
- **Adaptive Grain Cloud Synthesis** — formant and spectral descriptor control of grain density, duration, and scatter
- **8-Channel Spatial Canon / Speed Deviations** — prosody to space: F0, intensity, speaking rate, jitter
- **Latent Space Navigation** — AI-powered tool that learns a latent space from audio patches and navigates it to generate new timelines
- **IRCAM SuperVP Transform** — spectral voice transformation bridge supporting 11 transform modes
- **Phase-Space Composer** — attractor-driven event montage engine (Hopf, Lorenz, Rössler, Logistic Map)

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
