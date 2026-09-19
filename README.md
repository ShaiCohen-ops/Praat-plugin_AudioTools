# Praat Plugin: AudioTools

**Author:** [Shai Cohen](https://music.biu.ac.il/en/ShaiCohen)  
**Affiliation:** Department of Music, Bar-Ilan University, Israel  
**YouTube:** [@Shai_Cohen](https://www.youtube.com/@Shai_Cohen/videos)  
**Research Article:** [Praat Audiotools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition](https://www.cambridge.org/core/journals/organised-sound/article/praat-audiotools-an-offline-analysisresynthesis-toolkit-for-experimental-composition/5601EA626B76319A2723CA5DC56563F9), *Organised Sound*, Cambridge University Press, 2026  
**Book:** [The Syntax of Sound: Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition](https://link.springer.com/book/9789819225750), Springer Nature, 2026

---

## Overview

**Praat AudioTools** is an open-source analysis–resynthesis toolkit for **experimental composition, sound design, and music-technology research**, built on top of [Praat](http://www.praat.org). The current documentation presents **473 scripts across 13 categories** for audio processing, analysis, synthesis, spatialisation, interoperability, and hybrid computational workflows.

The plugin adds a unified **AudioTools** menu to Praat, bringing together effects, filters, transformations, generative processes, analysis-driven tools, and extended workflows for experimental composition.

Developed for composers, sound designers, students, and researchers, the toolkit recontextualises Praat's phonetic-analysis environment as an **offline, object-centric sound laboratory**. Analysis objects can function not only as measurements but as editable compositional structures within an iterative **analyse–edit–render–listen** workflow. The environment supports granular synthesis, adaptive filtering, spectral transformation, algorithmic and stochastic processes, multichannel spatialisation, machine-learning-assisted processing, and bridges to external systems.

The research framework behind the project is presented in the 2026 *Organised Sound* article and developed at book length in *The Syntax of Sound* (Springer, 2026).

---

## Installation

### 0. Install Praat

Praat AudioTools is a plugin for [Praat](https://www.praat.org/), so Praat must be installed first.

Download and install the latest version of Praat for your operating system:

https://www.praat.org/

After Praat is installed, continue with the AudioTools installation below.

### 1. Download AudioTools

1. **Download or clone** this repository.

   ```bash
   git clone https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools.git
   ```

   Or [⬇️ download the entire package](plugin_AudioTools.zip) · [⬇️ download Audio Figures](AudioFigures.zip)

2. **Locate your Praat preferences folder.**

   Praat automatically loads plugins from folders whose names begin with `plugin_` and that are placed directly inside the Praat preferences folder.

   ### Praat 7.x

   If you are installing a current version of Praat, use these locations:

   * **Windows:**
     `C:\Users\<YourName>\AppData\Roaming\Praat\plugin_AudioTools\`

   * **macOS:**
     `~/Library/Application Support/Praat/plugin_AudioTools/`

   * **Linux:**
     `~/.config/praat/plugin_AudioTools/`

     If the `XDG_CONFIG_HOME` environment variable is defined, use:
     `$XDG_CONFIG_HOME/praat/plugin_AudioTools/`

   > **Windows note:** `AppData` is normally a hidden folder. You can enter `%APPDATA%\Praat` directly in the File Explorer address bar.

   ### Praat 6.x

   For older Praat 6.x installations, use these locations:

   * **Windows:**
     `C:\Users\<YourName>\Praat\plugin_AudioTools\`

   * **macOS:**
     `~/Library/Preferences/Praat Prefs/plugin_AudioTools/`

   * **Linux:**
     `~/.praat-dir/plugin_AudioTools/`

3. **Copy the folder** `plugin_AudioTools` to the appropriate Praat preferences folder for your version.

   The final structure should look like this:

   ```text
   <Praat preferences folder>/
   └── plugin_AudioTools/
       ├── setup.praat
       ├── Analysis/
       ├── Spectral/
       ├── Time & Granular/
       └── ...
   ```

   ⚠️ The folder name must be exactly `plugin_AudioTools`.
   Do **not** place it inside an additional `plugins` folder. Praat looks for `plugin_*` folders directly inside its preferences folder.

4. **Restart Praat.**

   Praat automatically executes `setup.praat` when it starts. After restarting, you should see the new **AudioTools** menus in the main Praat **Objects** window.

---

## Scripts Documentation

**Interactive HTML documentation for the current AudioTools collection:**
https://mashav.com/sha/Praat%20AudioTools/

📖 [Detailed Script Overview](https://mashav.com/sha/Praat%20AudioTools/script-overview.html)

🎵 Did You Know? Algorithmic Music (1-Min Intros): [YouTube Playlist](https://www.youtube.com/playlist?list=PLgvns-wRHeYo-EcXGacjOwbmwA7vbSLW2)

The documentation includes searchable guides with detailed parameter descriptions, usage examples, and technical explanations for each script.

---

## Key Features

### 473 Scripts Across 13 Categories

The counts below follow the current public AudioTools documentation and may increase as the toolkit evolves.

| Category               | Scripts |
| ---------------------- | ------: |
| AI & Adaptive          | 33      |
| Analysis               | 44      |
| Distortion             | 16      |
| Dynamics & Envelope    | 23      |
| Filter & Color         | 38      |
| Generative & Synthesis | 56      |
| Modulation             | 23      |
| Pitch                  | 28      |
| Reverb                 | 31      |
| Spatial & Surround     | 39      |
| Spectral               | 31      |
| Time & Granular        | 45      |
| Hybrid Systems         | 66      |

### AI & Adaptive (33)

Neural-network, PCA, Bayesian, HMM, NMF, and self-attention based scripts for intelligent modulation, adaptive control, recomposition, classification, and phonetic-aware transformations. Includes Neural Audio Mosaic, PCA Timbre Selector, Genetic Recomposer, Granular Attention Resynth, and Self Attention Recomposer.

### Analysis (44)

Extract MFCCs, formants, pitch, loudness, jitter, shimmer, harmonicity, tempo curves, self-similarity matrices, chord profiles, and other descriptors for musical experimentation and acoustic research. Includes DTW-Aligned Multi-Feature Analysis, Krumhansl–Schmuckler Key Profiler, Speech to MusicXML Rhythm Converter, and Spatial Trajectory Tracker.

### Distortion (16)

Waveshaping, clipping, bit-crushing, and nonlinear processing tools. Includes Adaptive Wave Shaper, Chaos Distortion, Hysteresis Distortion, Multiband Distortion, Virtual Subharmonic Generator, and Wavefolder Distortion.

### Dynamics & Envelope (23)

Shape amplitude with compressors, multiband dynamics, limiters, noise gates, LUFS tools, swell generators, envelope processors, and mathematically defined amplitude trajectories. Includes Vintage Glue Compressor, Kinematic Physics Envelope, and Polynomial Envelope Shaper.

### Filter & Color (38)

Adaptive EQ, resonators, cross-synthesis, spectral morphing, formant filtering, frequency shifting, de-essing, hum removal, FIR/IIR filter banks, and timbral shaping tools. Includes GRM-Style Resonator, Moog Ladder Filter, MFCC Transformer, Intelligent EQ Adaptive Bandpass, and Jitter-Shimmer Formant Mapping.

### Generative & Synthesis (56)

Create sound from scratch using Markov models, stochastic processes, chaotic systems, cellular automata, Brownian motion, GENDYN-style methods, physical models, and formula-based synthesis. Includes GENDYN Synthesis, Pulsar Synthesis Engine, Karplus-Strong Texture Generator, Wave Terrain Synthesis, Grisey Spectral Becoming Engine, and Stockhausen Studie II Generator.

### Modulation (23)

LFO-driven and spectral modulation effects: vibrato, chorus, phaser, flanger, tremolo, wah-wah, and analysis-driven modulation. Includes Unified Multi-Mode Vibrato, Spectral Driven Vibrato, Metamodulator, Phonetic Tremolo-Glitch Effect, and XY Shape LFO.

### Pitch (28)

Pitch shifting, harmonization, tuning, PSOLA-based transformation, and microtonal tools. Includes Adaptive Pitch Shifter, Auto-Harmonic Layering, Breathing Pitch Waves, and analysis-driven pitch mapping and resynthesis.

### Reverb (31)

Convolution, algorithmic, fractal, and physically modelled reverberation. Includes Fractal Feedback Reverb, Gravitational Lens Reverb, Ray Tracing Room Acoustics, Quantum Uncertainty Reverb, The Lucier Machine, Ligeti Micropolyphonic Choir Machine, and Universal Convolution Generator.

### Spatial & Surround (39)

Multichannel spatialisation from stereo to 22.2, with panning laws, trajectory control, and HOA encoding/decoding. Includes 8-Channel Canon, 8-Channel Speed Deviations, Higher-Order Ambisonic Encoder/Decoder, DBAP with Movement Control, Hamasaki Square Ambience, and 22.2 Stem Renderer.

### Spectral (31)

FFT and phase-domain processing: spectral mirroring, freezing, blurring, phase manipulation, LPC morphing, and partial editing. Includes Spectral Freeze Synthesis, Fractal Spectral Hologram, LPC Voice Morphing, Self-Similarity Spectral Resynthesis, Phase Shaper, and Vocoding.

### Time & Granular (45)

Granular resynthesis, time-stretching, beat manipulation, and temporal recomposition. Includes Adaptive Grain Cloud Synthesis, Paulstretch, Stochastic Time Folding, Rhythmic Fractal Granulator, Phase Modulation Matrix, and Total Serialism Machine.

### Hybrid Systems (66)

Extended workflows bridging Praat with Python, Max/MSP, Ableton Live, IRCAM tools, VST3 plugins, neural-audio systems, and other external environments. Includes IRCAM SuperVP Transform, IRCAM RAVE Model, Latent Space Navigation, Phase-Space Composer, CNN Event Recomposer, and Praat for Max and M4L.

### Reproducible by Design

Scriptable parameters, seeds captured, versioned presets, and optional ablation variants support repeatable experimentation and method comparison.

### Interoperability for Composition

Cross-platform workflows connect Praat with Python, Max/MSP, Ableton Live, VST3, IRCAM tools, and other external systems while retaining Praat as the central analysis–resynthesis environment.

## Research & Publications

Praat AudioTools is developed as both a software environment and a research-creation framework for experimental composition.

### Peer-Reviewed Article

Cohen, S. (2026). **Praat Audiotools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.** *Organised Sound*, 1–9. Cambridge University Press.  
https://doi.org/10.1017/S1355771826101204

The article presents the toolkit's object-centric analysis–resynthesis methodology, its use of phonetic analysis objects as editable compositional structures, and the concept of **compositional deep time** within an iterative edit–render–listen workflow.

### Book

Cohen, S. (2026). **The Syntax of Sound: Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.** Springer Nature Singapore.  
https://link.springer.com/book/9789819225750

The book develops the AudioTools framework across analysis, transformation, synthesis, spatial audio, algorithmic composition, interoperability, hybrid systems, and distributed studio workflows.

---

## Citation

If you use Praat AudioTools in academic work, please cite the peer-reviewed article:

```text
Cohen, S. (2026). Praat Audiotools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
Organised Sound, 1–9. https://doi.org/10.1017/S1355771826101204
```

For the software itself, please also cite:

```text
Cohen, S. (2025–2026). Praat AudioTools [Software].
https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
```

For the extended book-length treatment of the project:

```text
Cohen, S. (2026). The Syntax of Sound: Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
Springer Nature Singapore. https://link.springer.com/book/9789819225750
```

---

## License

MIT License

---

## Acknowledgements

**Praat** by Paul Boersma & David Weenink, University of Amsterdam.
This plugin repurposes Praat's scientific tools for creative sound design and electroacoustic composition.

Special thanks to the Praat community and the Department of Music at Bar-Ilan University for supporting this research.
