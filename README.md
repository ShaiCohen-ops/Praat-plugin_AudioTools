# Praat Plugin: AudioTools

**Author:** [Shai Cohen](https://music.biu.ac.il/en/ShaiCohen)  
**Affiliation:** Department of Music, Bar-Ilan University, Israel  
**YouTube:** [@Shai_Cohen](https://www.youtube.com/@Shai_Cohen/videos)

---

## Overview

**Praat AudioTools** is a collection of more than **400 scripts** for **audio processing, analysis, and synthesis** in [Praat](http://www.praat.org).  
The plugin adds a unified **AudioTools** menu to Praat, offering a wide range of effects, filters, transformations, and creative analysis-driven tools for sound design and experimental composition.

Developed for composers, sound designers, and researchers, the toolkit extends Praat's phonetic analysis environment into a **complete offline sound laboratory** — enabling processes such as granular synthesis, adaptive filtering, spectral manipulation, fractal reverbs, multichannel spatialisation, and machine learning-driven audio effects.

---

## Installation

1. **Download or clone** this repository.  
   ```bash
   git clone https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools.git
   ```

2. **Locate your Praat plugins folder.**  
   Depending on your operating system, Praat looks for plugins here:

   - **Windows:**   `C:\Users\<YourName>\Praat\plugin_AudioTools\`
   - **macOS:**     `~/Library/Preferences/Praat Prefs/plugin_AudioTools/`
   - **Linux:**     `~/.praat-dir/plugin_AudioTools/`

3. **Important**⚠️ Rename the folder after downloading or cloning, ensure that the folder name is exactly:`plugin_AudioTools`.
 If the folder name differs, Praat will not display the “AudioTools” menu.
 Copy the renamed folder plugin_AudioTools into your Praat plugins directory.

4. **Restart Praat.** After restarting, you should see a new AudioTools menu in the main Praat window.

---

## Scripts Documentation

**Interactive HTML documentation for all 254 scripts:**  
[https://mashav.com/sha/Praat%20AudioTools/)
 Did You Know? Algorithmic Music (1-Min Intros) - https://www.youtube.com/playlist?list=PLgvns-wRHeYo-EcXGacjOwbmwA7vbSLW2

The documentation includes searchable guides with detailed parameter descriptions, usage examples, and technical explanations for each script.

---

## Key Features

- Offline, object-centric workflow
- Edit PitchTiers, FormantGrids, TextGrids, and Tables as compositional scores. Work in an edit → render → listen loop with full reproducibility.
- 250+ processes across categories
- Analysis, delay and temporal, distortion and dynamics, spectral and filter (FFT and LPC), modulation, pitch, convolution and reverb, spatial, and synthesis.
- Analysis-driven mappings
- Map pitch, formants and bandwidths, intensity, spectral centroid and flatness, zero-crossing rate, jitter, shimmer, and HNR directly to transformation parameters.
- Flagship scripts (ready to use)
- Adaptive Grain Cloud Synthesis (formant and spectral descriptor control of grain density, duration, and scatter)
- 8-Channel Spatial Canon / Speed Deviations (prosody to space: F0, intensity, speaking rate, jitter)
- Reproducible by design
- Scriptable parameters, seeds captured, versioned presets, optional ablation variants for method comparison.
- Interoperability for composition
- Cross-platform

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
