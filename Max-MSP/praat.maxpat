{
    "patcher": {
        "fileversion": 1,
        "appversion": {
            "major": 9,
            "minor": 1,
            "revision": 0,
            "architecture": "x64",
            "modernui": 1
        },
        "classnamespace": "box",
        "rect": [ 325.0, 193.0, 984.0, 684.0 ],
        "boxes": [
            {
                "box": {
                    "id": "obj-18",
                    "maxclass": "meter~",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "float" ],
                    "patching_rect": [ 9.0, 420.0, 93.0, 171.0 ]
                }
            },
            {
                "box": {
                    "hidden": 1,
                    "id": "obj-10",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 295.0, 508.0, 73.0, 22.0 ],
                    "text": "loadmess 1."
                }
            },
            {
                "box": {
                    "id": "obj-43",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 176.25, 399.0, 35.0, 20.0 ],
                    "text": "stop"
                }
            },
            {
                "box": {
                    "id": "obj-41",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 179.0, 421.0, 29.5, 22.0 ],
                    "text": "0"
                }
            },
            {
                "box": {
                    "id": "obj-35",
                    "maxclass": "live.dial",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "", "float" ],
                    "parameter_enable": 1,
                    "patching_rect": [ 237.0, 482.0, 47.0, 48.0 ],
                    "saved_attribute_attributes": {
                        "valueof": {
                            "parameter_initial": [ -70 ],
                            "parameter_initial_enable": 1,
                            "parameter_longname": "Gain",
                            "parameter_mmax": 1.0,
                            "parameter_modmode": 0,
                            "parameter_shortname": "Gain",
                            "parameter_type": 0,
                            "parameter_units": "dB",
                            "parameter_unitstyle": 9
                        }
                    },
                    "varname": "live.dial[5]"
                }
            },
            {
                "box": {
                    "id": "obj-56",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 829.5, 79.5, 75.0, 20.0 ],
                    "text": "Shai Cohen "
                }
            },
            {
                "box": {
                    "bgcolor": [ 0.866667, 0.866667, 0.866667, 0.0 ],
                    "bgfillcolor_autogradient": 0.79,
                    "bgfillcolor_color": [ 0.228311182788346, 0.228311120731904, 0.228311136948243, 1 ],
                    "bgfillcolor_color1": [ 0.866667, 0.866667, 0.866667, 0.0 ],
                    "bgfillcolor_color2": [ 0.07451, 0.027451, 1.0, 1.0 ],
                    "bgfillcolor_type": "gradient",
                    "fontname": "Arial",
                    "fontsize": 17.136363636363633,
                    "gradient": 0,
                    "id": "obj-54",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 8.0, 621.0, 357.0, 28.0 ],
                    "text": "https://mashav.com/sha/Praat%20AudioTools/",
                    "textcolor": [ 0.0, 0.0, 0.0, 1.0 ]
                }
            },
            {
                "box": {
                    "hidden": 1,
                    "id": "obj-47",
                    "linecount": 2,
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 8.0, 665.0, 129.0, 36.0 ],
                    "text": ";\r\nmax launchbrowser $1"
                }
            },
            {
                "box": {
                    "id": "obj-42",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 613.0, 264.0, 35.0, 20.0 ],
                    "text": "input"
                }
            },
            {
                "box": {
                    "id": "obj-40",
                    "maxclass": "toggle",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 581.0, 262.0, 24.0, 24.0 ]
                }
            },
            {
                "box": {
                    "id": "obj-38",
                    "maxclass": "newobj",
                    "numinlets": 2,
                    "numoutlets": 0,
                    "patching_rect": [ 581.0, 339.0, 57.0, 22.0 ],
                    "text": "dac~"
                }
            },
            {
                "box": {
                    "id": "obj-37",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "signal", "bang" ],
                    "patching_rect": [ 581.0, 302.0, 84.0, 22.0 ],
                    "text": "play~ myInput"
                }
            },
            {
                "box": {
                    "fontname": "Arial",
                    "fontsize": 16.0,
                    "id": "obj-86",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 10.0, 77.0, 501.0, 25.0 ],
                    "saved_attribute_attributes": {
                        "textcolor": {
                            "expression": "themecolor.theme_textcolor"
                        }
                    },
                    "text": "An Offline Analysis–Resynthesis Toolkit for Experimental Composition"
                }
            },
            {
                "box": {
                    "fontface": 1,
                    "fontname": "Arial",
                    "fontsize": 54.0,
                    "id": "obj-34",
                    "maxclass": "comment",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 10.0, 6.0, 480.0, 69.0 ],
                    "saved_attribute_attributes": {
                        "textcolor": {
                            "expression": "themecolor.theme_textcolor"
                        }
                    },
                    "text": "AudioTools.praat~"
                }
            },
            {
                "box": {
                    "id": "obj-28",
                    "linecount": 2,
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 678.0, 325.0, 123.0, 36.0 ],
                    "text": ";\r\nmax clearmaxwindow"
                }
            },
            {
                "box": {
                    "id": "obj-24",
                    "maxclass": "newobj",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "multichannelsignal" ],
                    "patching_rect": [ 114.0, 533.0, 142.0, 22.0 ],
                    "text": "mc.*~ 0.5"
                }
            },
            {
                "box": {
                    "id": "obj-22",
                    "maxclass": "newobj",
                    "numinlets": 8,
                    "numoutlets": 1,
                    "outlettype": [ "multichannelsignal" ],
                    "patching_rect": [ 114.0, 499.0, 128.71428571428578, 22.0 ],
                    "text": "mc.pack~ 8"
                }
            },
            {
                "box": {
                    "id": "obj-31",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 519.0, 302.0, 48.0, 22.0 ],
                    "text": "replace"
                }
            },
            {
                "box": {
                    "id": "obj-27",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 316.0, 290.0, 31.0, 22.0 ],
                    "text": "stop"
                }
            },
            {
                "box": {
                    "id": "obj-25",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 146.0, 421.0, 29.5, 22.0 ],
                    "text": "1"
                }
            },
            {
                "box": {
                    "id": "obj-23",
                    "maxclass": "button",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "bang" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 146.0, 381.0, 24.0, 24.0 ]
                }
            },
            {
                "box": {
                    "id": "obj-14",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 369.0, 264.0, 35.0, 22.0 ],
                    "text": "clear"
                }
            },
            {
                "box": {
                    "id": "obj-19",
                    "maxclass": "number",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "", "bang" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 323.5, 140.5, 50.0, 22.0 ]
                }
            },
            {
                "box": {
                    "autopopulate": 1,
                    "depth": 1,
                    "fontsize": 18.0,
                    "id": "obj-15",
                    "items": [ "AI & Adaptive", ",", "AI & Adaptive/Bayesian Drone Weaver.praat", ",", "AI & Adaptive/Chaotic Neural Map Modulator.praat", ",", "AI & Adaptive/Genetic Recomposer.praat", ",", "AI & Adaptive/Gestural_Accumulator.praat", ",", "AI & Adaptive/Gesture-Based_Hard_Quantization.praat", ",", "AI & Adaptive/Granular_Attention_Resynth.praat", ",", "AI & Adaptive/HMM_Timbre_Sequencing.praat", ",", "AI & Adaptive/LZ-Inspired Audio Variations.praat", ",", "AI & Adaptive/Morphic_Form.praat", ",", "AI & Adaptive/MSE_Feature_Constrained_Variation.praat", ",", "AI & Adaptive/Neural Adaptive Phonetic Vibrato.praat", ",", "AI & Adaptive/Neural Ambient Drone Designer.praat", ",", "AI & Adaptive/Neural Audio Mosaic.praat", ",", "AI & Adaptive/Neural Delay Control.praat", ",", "AI & Adaptive/Neural Granular Texture Morpher.praat", ",", "AI & Adaptive/Neural Markov Soundscape Weaver.praat", ",", "AI & Adaptive/Neural Phonetic Harmonizer.praat", ",", "AI & Adaptive/Neural Phonetic Speed Mapper.praat", ",", "AI & Adaptive/NMF Spectral Resynthesizer .praat", ",", "AI & Adaptive/OT_CORPUS_CONCATENATOR.praat", ",", "AI & Adaptive/Parametric Autoencoder Resynthesis with Variations.praat", ",", "AI & Adaptive/PCA_Timbre_Selector.praat", ",", "AI & Adaptive/PCA_Tone_Shaper.praat", ",", "AI & Adaptive/Perceptual Graph.praat", ",", "AI & Adaptive/Perceptual_Synchrony.praat", ",", "AI & Adaptive/Self_Attention_Recomposer.praat", ",", "AI & Adaptive/Timbral_Similarity_Browser.praat", ",", "Analysis", ",", "Analysis/Acoustic Pedagogy.praat", ",", "Analysis/Acoustic_Features_Batch_Extraction.praat", ",", "Analysis/Adaptive Transient Decomposition.praat", ",", "Analysis/ASA Demos.praat", ",", "Analysis/Audio_Descriptions_and_Global_Statistics.praat", ",", "Analysis/Audio_File_Properties.praat", ",", "Analysis/BrightnessClassifier.praat", ",", "Analysis/CHORD DETECTION.praat", ",", "Analysis/Climax_Profile_Matcher.praat", ",", "Analysis/Continuous Pitch over MIDI Grid Visualizer.praat", ",", "Analysis/Correlation-Based Pitch Class Extraction.praat", ",", "Analysis/DTW-Aligned Multi-Feature Audio Analysis (MFCC, Loudness, Pitch).praat", ",", "Analysis/Extract_Segment.praat", ",", "Analysis/Formant to MIDI Chord Converter.praat", ",", "Analysis/Formant to MusicXML Chord Converter.praat", ",", "Analysis/Kick detector and bass adder.praat", ",", "Analysis/Krumhansl-Schmuckler Key Profiler.praat", ",", "Analysis/Melodic_Contour_Parsons_Code.praat", ",", "Analysis/MFCC.praat", ",", "Analysis/Multi-Band_Onset_Detector.praat", ",", "Analysis/Multi-Layer Audio Visualizer (EAnalysis Style).praat", ",", "Analysis/Musikalisches Würfelspiel Audio Game.praat", ",", "Analysis/OT Grammar Learning from Audio.praat", ",", "Analysis/Pitch Loop Finder.praat", ",", "Analysis/Pitch_and_Loudness_Comparison_Two_Sounds.praat", ",", "Analysis/Recursive WAV opener.praat", ",", "Analysis/Self-Similarity Matrix Calculator.praat", ",", "Analysis/Sonic Syntax.praat", ",", "Analysis/Spatial trajectory tracker.praat", ",", "Analysis/SPEAR Par-Text-Frame Format Parser for Praat.praat", ",", "Analysis/SpectraScore - Orchestration Matcher.praat", ",", "Analysis/Speech to MusicXML Rhythm Converter.praat", ",", "Analysis/Stereo Channel Similarity Meter.praat", ",", "Analysis/Tempo Curve (IOI) Estimator.praat", ",", "clip into buffer.amxd", ",", "Distortion", ",", "Distortion/Adaptive Wave Shaper.praat", ",", "Distortion/Asymmetric Soft Clipping.praat", ",", "Distortion/Chaos Distortion.praat", ",", "Distortion/Distortion & Bit-Crusher.praat", ",", "Distortion/Dynamic Distortion.praat", ",", "Distortion/Full-Wave Rectifier Abs.praat", ",", "Distortion/Hard Clip.praat", ",", "Distortion/Hysteresis Distortion.praat", ",", "Distortion/Math Operations.praat", ",", "Distortion/Multiband Distortion.praat", ",", "Distortion/Sidechain Feedback VCA.praat", ",", "Distortion/Tanh.praat", ",", "Distortion/Virtual Subharmonic Generator.praat", ",", "Distortion/Wave Shaper Distortion.praat", ",", "Distortion/Wavefolder (Foldback).praat", ",", "Dynamics & Envelope", ",", "Dynamics & Envelope/Auto-Swell.praat", ",", "Dynamics & Envelope/Auto-Trim Silence.praat", ",", "Dynamics & Envelope/Compressor.praat", ",", "Dynamics & Envelope/Concatenate with crossfade.praat", ",", "Dynamics & Envelope/Envelope Application.praat", ",", "Dynamics & Envelope/Fast Waveset Distortion.praat", ",", "Dynamics & Envelope/Intensity_Envelope_Processor.praat", ",", "Dynamics & Envelope/Kinematic Physics Envelope.praat", ",", "Dynamics & Envelope/Limiter.praat", ",", "Dynamics & Envelope/Linear_Fade-In.praat", ",", "Dynamics & Envelope/Linear_Fade-Out.praat", ",", "Dynamics & Envelope/LUFS Tool.praat", ",", "Dynamics & Envelope/Multiband Compressor.praat", ",", "Dynamics & Envelope/Noise Gate.praat", ",", "Dynamics & Envelope/Polynomial_Sound_Shaper.praat", ",", "Dynamics & Envelope/Sample-and-Hold Processor.praat", ",", "Dynamics & Envelope/Time-domain RMS envelope follower.praat", ",", "Dynamics & Envelope/Vintage Glue Compressor.praat", ",", "Dynamics & Envelope/Waveset Distortion.praat", ",", "Filter & Color", ",", "Filter & Color/a-e-i-o_filter.praat", ",", "Filter & Color/Adaptive Spectral Resonance Suppressor.praat", ",", "Filter & Color/Adaptive_Filter.praat", ",", "Filter & Color/Amplitude-Varying Ring Modulation.praat", ",", "Filter & Color/Autocorrelation-Based Self-Filtering.praat", ",", "Filter & Color/Band-Based Concatenative Synthesis.praat", ",", "Filter & Color/Bit Crusher (8-Bit Arcade).praat", ",", "Filter & Color/Classic FIR Filter Bank.praat", ",", "Filter & Color/Classic IIR Filter Bank.praat", ",", "Filter & Color/Creative Formant Manipulations.praat", ",", "Filter & Color/Cross_Synthesis.praat", ",", "Filter & Color/DYNAMIC FORMANT SWEEPER.praat", ",", "Filter & Color/Electrical_Hum_Removal.praat", ",", "Filter & Color/ENTROPY SMART DE-ESSER.praat", ",", "Filter & Color/Frequency Shifter.praat", ",", "Filter & Color/Golden_Ratio_Processor.praat", ",", "Filter & Color/GRM-Style_Resonator.praat", ",", "Filter & Color/Harmonic_Formant_Locking.praat", ",", "Filter & Color/Hilbert Transform(for drums).praat", ",", "Filter & Color/Individual_Formant_Stretcher.praat", ",", "Filter & Color/Intelligent_EQ_Adaptive_Bandpass.praat", ",", "Filter & Color/Jitter-Shimmer Formant Mapping.praat", ",", "Filter & Color/MFCC TRANSFORMER.praat", ",", "Filter & Color/Moog Ladder Filter.praat", ",", "Filter & Color/Onset-Based Oscillator Bank.praat", ",", "Filter & Color/Panning filter.praat", ",", "Filter & Color/Pitch-Based_Spectral_Notch.praat", ",", "Filter & Color/Resonant.praat", ",", "Filter & Color/Spectral Filtering Effect.praat", ",", "Filter & Color/Spectral_Band_EQ.praat", ",", "Filter & Color/Spectral_Morph.praat", ",", "Filter & Color/Voice_Quality_Sonification.praat", ",", "Filter & Color/Wah-Wah Effect.praat", ",", "Filter & Color/Whisper Morph.praat", ",", "Filter & Color/XMod.praat", ",", "Generative & Synthesis", ",", "Generative & Synthesis/Accelerating_Polyrhythm.praat", ",", "Generative & Synthesis/Advanced Brownian Synthesis.praat", ",", "Generative & Synthesis/Advanced Chaotic Modulation.praat", ",", "Generative & Synthesis/Advanced Formula Synthesis.praat", ",", "Generative & Synthesis/Advanced Poisson Synthesis.praat", ",", "Generative & Synthesis/Algorithmic Metallic Synthesis.praat", ",", "Generative & Synthesis/AM Additive Synthesis Generator.praat", ",", "Generative & Synthesis/Analogique_B_Stochastic_Mass.praat", ",", "Generative & Synthesis/Cellular Automata Synthesis.praat", ",", "Generative & Synthesis/Chaotic Function Generator.praat", ",", "Generative & Synthesis/Chaotic Granular Synthesis.praat", ",", "Generative & Synthesis/ChirikovStandardMap.praat", ",", "Generative & Synthesis/Competing Modulators.praat", ",", "Generative & Synthesis/Convolution Synthesis.praat", ",", "Generative & Synthesis/Dynamic Stochastic Synthesis.praat", ",", "Generative & Synthesis/Dynamic Vowel Transitions.praat", ",", "Generative & Synthesis/Evolving Grain Mass.praat", ",", "Generative & Synthesis/FM Texture Generator.praat", ",", "Generative & Synthesis/Formant Grain Texture.praat", ",", "Generative & Synthesis/Formant Synthesis.praat", ",", "Generative & Synthesis/Formula Markov Synthesis.praat", ",", "Generative & Synthesis/GENDYN_Synthesis.praat", ",", "Generative & Synthesis/Generative Sound System.praat", ",", "Generative & Synthesis/Grisey_Spectral_Becoming_Engine.praat", ",", "Generative & Synthesis/Karplus-Strong Texture Generator.praat", ",", "Generative & Synthesis/Kotoński_FSM_Event_Generator.praat", ",", "Generative & Synthesis/Layered Markov Texture.praat", ",", "Generative & Synthesis/Logistic Map Synthesis.praat", ",", "Generative & Synthesis/Lorenz Deep Analog.praat", ",", "Generative & Synthesis/Markov Rhythm Generator.praat", ",", "Generative & Synthesis/Organic No-Input Mixer.praat", ",", "Generative & Synthesis/Percussive Image Sonification.praat", ",", "Generative & Synthesis/Photo _sonification.praat", ",", "Generative & Synthesis/Photo Brightness-Controlled Pitch Sonification.praat", ",", "Generative & Synthesis/Poisson Point Process Synthesis.praat", ",", "Generative & Synthesis/Poisson Rhythm Synthesis.praat", ",", "Generative & Synthesis/PolyrhythmsFromDots.praat", ",", "Generative & Synthesis/Random Walk Melody.praat", ",", "Generative & Synthesis/Random Walk Rhythm.praat", ",", "Generative & Synthesis/Rich Formant Grains.praat", ",", "Generative & Synthesis/Risset's_Mutations.praat", ",", "Generative & Synthesis/SonifiedDrawing.praat", ",", "Generative & Synthesis/Spectral Image Sonification.praat", ",", "Generative & Synthesis/Stockhausen Studie II Generator.praat", ",", "Generative & Synthesis/Subtractive Synthesis Generator.praat", ",", "Generative & Synthesis/Vector_Synthesis.praat", ",", "Generative & Synthesis/Visual_Game_of_Life_Synthesis.praat", ",", "Generative & Synthesis/Wave Terrain Synthesis.praat", ",", "Generative & Synthesis/Waveguide & Modal Synthesis.praat", ",", "load_audio.praat", ",", "Modulation", ",", "Modulation/Amplitude-Following Wah-Wah.praat", ",", "Modulation/Barber-Pole_Orbit.praat", ",", "Modulation/Chaotic Prosody Manipulation.praat", ",", "Modulation/Dual-Mode Tremolo Generator.praat", ",", "Modulation/Fractal_Convolution_Swarm.praat", ",", "Modulation/Golden-chaos_vibrato.praat", ",", "Modulation/Hexaphonic Serial Audio Processor.praat", ",", "Modulation/Karplus-Strong Modulator .praat", ",", "Modulation/Metamodulator.praat", ",", "Modulation/Phonetic Tremolo-Glitch Effect.praat", ",", "Modulation/Rhythmic LFO Wah-Wah.praat", ",", "Modulation/Spectral-Driven Intensity Modulation.praat", ",", "Modulation/Spectral_Driven_Vibrato.praat", ",", "Modulation/Stereo Flanger.praat", ",", "Modulation/Stereo Phaser.praat", ",", "Modulation/Stereo Rotary Speaker.praat", ",", "Modulation/Stereo_Swirl_Vibrato.praat", ",", "Modulation/Stretch-Tremolo Ambience.praat", ",", "Modulation/Time_Varying_Spectral_Vibrato.praat", ",", "Modulation/Unified Chorus Generator.praat", ",", "Modulation/Unified Multi-Mode Vibrato.praat", ",", "Modulation/XY SHAPE LFO - FREQUENCY MODULATION.praat", ",", "Pitch", ",", "Pitch/Adaptive Pitch Shifter.praat", ",", "Pitch/Auto-Harmonic Layering.praat", ",", "Pitch/Bimodal Contour Grammar.praat", ",", "Pitch/Breathing_Pitch_Waves.praat", ",", "Pitch/Chord Generator from Audio.praat", ",", "Pitch/Doppler_Effect_Simulator.praat", ",", "Pitch/Exponential Glide Up.praat", ",", "Pitch/flip or expand the F0 contours.praat", ",", "Pitch/Formula Audio Manipulation.praat", ",", "Pitch/Fractal_Pitch_Terrain.praat", ",", "Pitch/L-System_Granular_Pitch.praat", ",", "Pitch/Messagesquisse_Opening.praat", ",", "Pitch/Microtonal_Harmonic_Field_Engine.praat", ",", "Pitch/Pitch Correction.praat", ",", "Pitch/Pitch Processor.praat", ",", "Pitch/Pitch Stylization and Shift.praat", ",", "Pitch/Pitch_Contour_Transfer.praat", ",", "Pitch/Pitch_Morphing_Between_Targets.praat", ",", "Pitch/Pitch_Shift_Semitones.praat", ",", "Pitch/Quantum_Pitch_Jumps.praat", ",", "Pitch/Rhythmic_Pitch_Percussion.praat", ",", "Pitch/Spectral_Pitch_Shifter.praat", ",", "Pitch/Spiral_Pitch_Dance.praat", ",", "Pitch/Spiral_Segmentation.praat", ",", "Pitch/Tempo-Pitch Curves (Accelerando & Ritardando).praat", ",", "Pitch/Undertone_Field.praat", ",", "Pitch/Voice_Transformation.praat", ",", "praat.maxpat", ",", "py", ",", "py/AI_Conductor_Mix.praat", ",", "py/ai_conductor_mix.py", ",", "py/Arranger.praat", ",", "py/arranger.py", ",", "py/Dereverberation.praat", ",", "py/dereverberation.py", ",", "py/Envelope_Editor.praat", ",", "py/envelope_editor.py", ",", "py/formant_swarm_granulator.py", ",", "py/FormantSwarmGranulator.praat", ",", "py/granular_navigation_engine.py", ",", "py/GranularNavigationEngine.praat", ",", "py/hierarchical_recomposition.py", ",", "py/HierarchicalRecomposition.praat", ",", "py/host_vst.py", ",", "py/HPSS_Phase_Vocoder.praat", ",", "py/identity_separation.py", ",", "py/IdentitySeparation.praat", ",", "py/INSTALL.txt", ",", "py/internal_polyphony.py", ",", "py/InternalPolyphony.praat", ",", "py/latent_barycentric.py", ",", "py/latent_counterpoint.py", ",", "py/latent_diffusion.py", ",", "py/latent_folding.py", ",", "py/latent_nav_plan.csv", ",", "py/latent_navigation.py", ",", "py/latent_relocation.py", ",", "py/latent_spat.py", ",", "py/latent_stft_decoder.py", ",", "py/latent_time_warp.py", ",", "py/LatentBarycentric.praat", ",", "py/LatentCounterpoint.praat", ",", "py/LatentDiffusion.praat", ",", "py/LatentFolding.praat", ",", "py/LatentNavigation.praat", ",", "py/LatentRelocation.praat", ",", "py/LatentSpat.praat", ",", "py/LatentSTFTDecoder.praat", ",", "py/multichannel_play.py", ",", "py/Paulstretch.praat", ",", "py/paulstretch.py", ",", "py/phase_diffusion_ai.py", ",", "py/phase_space_compose.py", ",", "py/PhaseDiffusion.praat", ",", "py/PhaseSpaceComposer.praat", ",", "py/phrase_rewriter.py", ",", "py/PhraseRewriter.praat", ",", "py/PlayMultichannel.praat", ",", "py/PraatPbind.praat", ",", "py/PraatPbind.py", ",", "py/Recomposer.praat", ",", "py/recomposer.py", ",", "py/reflect_analyze.py", ",", "py/rhythmic_voice_flattener.py", ",", "py/RhythmicVoiceFlattener.praat", ",", "py/self_attention_latent.py", ",", "py/SelfAttentionLatent.praat", ",", "py/SelfReflectiveFeedback.praat", ",", "py/Spatial_Panner.praat", ",", "py/spatial_panner.py", ",", "py/Spectral_Freeze.praat", ",", "py/spectral_freeze.py", ",", "py/Spectral_Morph.praat", ",", "py/spectral_morph.py", ",", "py/ssm_morph_engine.py", ",", "py/SSMComposer.praat", ",", "py/stretch.py", ",", "py/sympathetic_resonance.py", ",", "py/SympatheticResonance.praat", ",", "py/TemporalElasticity.praat", ",", "py/thermodynamic_transform.py", ",", "py/ThermodynamicTransform.praat", ",", "py/VST_Effect_from_Praat.praat", ",", "Reverb", ",", "Reverb/Artificial Room.praat", ",", "Reverb/Cascading_Echoes.praat", ",", "Reverb/Chaotic_Bloom.praat", ",", "Reverb/Convolve_Bursts_Taps.praat", ",", "Reverb/Convolve_Stereo_Fibonacci.praat", ",", "Reverb/Crystalline_Cascade.praat", ",", "Reverb/Entropy_Modulated_Reverb.praat", ",", "Reverb/Feedback_Aware_Convolution.praat", ",", "Reverb/Fractal Feedback.praat", ",", "Reverb/Fractal_Feedback_Reverb.praat", ",", "Reverb/Granular_Displacement.praat", ",", "Reverb/Gravitational_Lens_ Reverb.praat", ",", "Reverb/Harmonic Decay Reverb.praat", ",", "Reverb/Harmonic_Comb.praat", ",", "Reverb/Ligeti Micropolyphonic Choir Machine.praat", ",", "Reverb/Morphing_Resonance.praat", ",", "Reverb/Ping_Pong_Field.praat", ",", "Reverb/Quantum_Uncertainty_Reverb.praat", ",", "Reverb/Ray Tracing Room Acoustics.praat", ",", "Reverb/Ribbon_Shimmer.praat", ",", "Reverb/Smooth Cosmic Reverb.praat", ",", "Reverb/Spectral_Decay.praat", ",", "Reverb/Spectral_Drift.praat", ",", "Reverb/Spectral_Smearing Reverb.praat", ",", "Reverb/Stereo_Ping-Pong_Impulses .praat", ",", "Reverb/Stereo_Shimmer.praat", ",", "Reverb/Temporal_Erosion.praat", ",", "Reverb/Temporal_Warping.praat", ",", "Reverb/The Lucier Machine.praat", ",", "Reverb/Universal Convolution Generator.praat", ",", "setup.praat", ",", "Spatial & Surround", ",", "Spatial & Surround/3D Audio Room Simulator with Distance-Based Panning.praat", ",", "Spatial & Surround/4-Channel Canon.praat", ",", "Spatial & Surround/8 Channels Time Polyphony.praat", ",", "Spatial & Surround/8-Channel Canon.praat", ",", "Spatial & Surround/8-channel I Ching.praat", ",", "Spatial & Surround/8-Channel movements.praat", ",", "Spatial & Surround/8-Channel Spectral Shift.praat", ",", "Spatial & Surround/8-Channel Speech-Driven Spatialization.praat", ",", "Spatial & Surround/8-channel speed deviations.praat", ",", "Spatial & Surround/8-Channel_Comb_Delay.praat", ",", "Spatial & Surround/Advanced Stereo Panner.praat", ",", "Spatial & Surround/BPM_Panning.praat", ",", "Spatial & Surround/BPM_SURROUND _Panning.praat", ",", "Spatial & Surround/DBAP with Movement Control.praat", ",", "Spatial & Surround/Distance-Based Amplitude Panning (DBAP).praat", ",", "Spatial & Surround/Distribute sounds in stereo field.praat", ",", "Spatial & Surround/Even-Odd Harmonic Binaural Separation.praat", ",", "Spatial & Surround/Fast Spectral Swirl Multi-Channel.praat", ",", "Spatial & Surround/Higher-Order Ambisonic Decoder.praat", ",", "Spatial & Surround/Higher-Order Ambisonic Encoder.praat", ",", "Spatial & Surround/Knight's Tour Sonification.praat", ",", "Spatial & Surround/MCMC_Musical_Variation.praat", ",", "Spatial & Surround/Microphone Simulation.praat", ",", "Spatial & Surround/Mix Multi-Channel to Stereo.praat", ",", "Spatial & Surround/Multi-channel Random Slice Time-Stretcher.praat", ",", "Spatial & Surround/Multitrack_Router.praat", ",", "Spatial & Surround/Panning variations.praat", ",", "Spatial & Surround/Partial Panner.praat", ",", "Spatial & Surround/Perceptual_Fugue.praat", ",", "Spatial & Surround/Physics-Based Stereo Dynamics.praat", ",", "Spatial & Surround/Random DurationTier Multichannel Generator.praat", ",", "Spatial & Surround/Simple Rate Panning.praat", ",", "Spatial & Surround/Spectral_Panning_Mapper.praat", ",", "Spatial & Surround/Stereo_Mixer.praat", ",", "Spectral", ",", "Spectral/Basic Mirror.praat", ",", "Spectral/Bell curve envelope.praat", ",", "Spectral/Doppler shift.praat", ",", "Spectral/Dynamic Tremolo Effect.praat", ",", "Spectral/Fractal Spectral Hologram.praat", ",", "Spectral/Frequency-Dependent Phase Manipulation.praat", ",", "Spectral/Harmonic Resonance Boost.praat", ",", "Spectral/Hilbert Transform.praat", ",", "Spectral/LPC Voice Generator.praat", ",", "Spectral/LPC Voice Morphing.praat", ",", "Spectral/Non-Linear Frequency Folding.praat", ",", "Spectral/Partial Editing & Resynthesis.praat", ",", "Spectral/Phase History Swap.praat", ",", "Spectral/Phase Shaper.praat", ",", "Spectral/Self-Similarity Spectral Resynthesis.praat", ",", "Spectral/Spectral Effects Suite.praat", ",", "Spectral/Spectral Freeze Synthesis.praat", ",", "Spectral/Spectral Painter.praat", ",", "Spectral/Spectral swirl effect.praat", ",", "Spectral/Spectral_Blur.praat", ",", "Spectral/Stepped Notch Filter.praat", ",", "Spectral/Subtle Random Texture.praat", ",", "Spectral/Vocoding.praat", ",", "Spectral/Wave Interference Pattern.praat", ",", "Time & Granular", ",", "Time & Granular/Adaptive Grain Cloud Synthesis.praat", ",", "Time & Granular/Additive_Particle_Field.praat", ",", "Time & Granular/Beat Repeat.praat", ",", "Time & Granular/Beat-Synced ZigZag.praat", ",", "Time & Granular/Bigram_Stutter_Effect.praat", ",", "Time & Granular/Brownian Motion Texture Generator.praat", ",", "Time & Granular/Constraint-Based Duration Control.praat", ",", "Time & Granular/Delay Array.praat", ",", "Time & Granular/Dramaturgical_Structure_Composer.praat", ",", "Time & Granular/Evolving Granular.praat", ",", "Time & Granular/Fractal_Convolution_Matrix.praat", ",", "Time & Granular/Granular_Particle_Field.praat", ",", "Time & Granular/Harmonic_Resonance.praat", ",", "Time & Granular/Harmonic_Tension_Sorted_Grains.praat", ",", "Time & Granular/HFD-Driven Time Warping.praat", ",", "Time & Granular/In-Place Paulstretch Slicer (Multi-channel).praat", ",", "Time & Granular/L-Logic_Symbolic_Granular_Recomposition.praat", ",", "Time & Granular/Magnetic_Tape_Degradation.praat", ",", "Time & Granular/MDS Space Navigator.praat", ",", "Time & Granular/Paulstretch.praat", ",", "Time & Granular/Peephole montage.praat", ",", "Time & Granular/Percussive Audio Groove Creator.praat", ",", "Time & Granular/Phase_Modulation_Matrix.praat", ",", "Time & Granular/Polyphonic_Improviser.praat", ",", "Time & Granular/Quantum_State_Superposition.praat", ",", "Time & Granular/Reich Generator.praat", ",", "Time & Granular/Rhythmic Fractal Granulator.praat", ",", "Time & Granular/Segment_mixer.praat", ",", "Time & Granular/Sorts grains from dark to bright.praat", ",", "Time & Granular/Sound to Grain.praat", ",", "Time & Granular/Sound_atom_composer.praat", ",", "Time & Granular/Spectral_Echo_Cascade.praat", ",", "Time & Granular/Spectral_Freeze_&_Glitch.praat", ",", "Time & Granular/Stereo Delay Splitter.praat", ",", "Time & Granular/Stereo Mosaic.praat", ",", "Time & Granular/Stereo_Micro_Macro_Time_Collapser.praat", ",", "Time & Granular/Stochastic_Time_Folding.praat", ",", "Time & Granular/Temporal_Turing_Morph.praat", ",", "Time & Granular/Time Manipulation.praat", ",", "Time & Granular/Total Serialism Machine.praat", ",", "Time & Granular/ZigZag_Effect.praat", ",", "Vector Chain", ",", "Vector Chain/chain_1.praat", ",", "Vector Chain/chain_2.praat", ",", "Vector Chain/chain_3.praat", ",", "Vector Chain/chain_4.praat", ",", "Vector Chain/chain_5.praat", ",", "Vector Chain/chain_6.praat", ",", "Vector Chain/cleanup.praat", ",", "Vector Chain/Composition_1.praat", ",", "Vector Chain/Composition_2.praat", ",", "Vector Chain/Live_1.praat", ",", "Vector Chain/Live_1_Random.praat", ",", "Vector Chain/Live_2.praat", ",", "Vector Chain/Live_2_Random.praat", ",", "Vector Chain/Live_3.praat", ",", "Vector Chain/Live_3_Random.praat", ",", "Vector Chain/Live_4.praat", ",", "Vector Chain/Live_5.praat", ",", "Vector Chain/Live_6.praat", ",", "Vector Chain/send_audio_to_Ableton.praat", ",", "Vector Chain/send_audio_to_Max.praat" ],
                    "maxclass": "umenu",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "int", "", "" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 323.5, 172.5, 581.0, 29.0 ],
                    "prefix": "~/Praat/plugin_AudioTools/"
                }
            },
            {
                "box": {
                    "id": "obj-20",
                    "maxclass": "number",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "", "bang" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 9.0, 137.0, 50.0, 22.0 ]
                }
            },
            {
                "box": {
                    "id": "obj-17",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 146.0, 242.0, 85.0, 22.0 ],
                    "text": "prepend script"
                }
            },
            {
                "box": {
                    "autopopulate": 1,
                    "depth": 1,
                    "id": "obj-12",
                    "items": [ "AI & Adaptive", ",", "AI & Adaptive/Bayesian Drone Weaver.praat", ",", "AI & Adaptive/Chaotic Neural Map Modulator.praat", ",", "AI & Adaptive/Genetic Recomposer.praat", ",", "AI & Adaptive/Gestural_Accumulator.praat", ",", "AI & Adaptive/Gesture-Based_Hard_Quantization.praat", ",", "AI & Adaptive/Granular_Attention_Resynth.praat", ",", "AI & Adaptive/HMM_Timbre_Sequencing.praat", ",", "AI & Adaptive/LZ-Inspired Audio Variations.praat", ",", "AI & Adaptive/Morphic_Form.praat", ",", "AI & Adaptive/MSE_Feature_Constrained_Variation.praat", ",", "AI & Adaptive/Neural Adaptive Phonetic Vibrato.praat", ",", "AI & Adaptive/Neural Ambient Drone Designer.praat", ",", "AI & Adaptive/Neural Audio Mosaic.praat", ",", "AI & Adaptive/Neural Delay Control.praat", ",", "AI & Adaptive/Neural Granular Texture Morpher.praat", ",", "AI & Adaptive/Neural Markov Soundscape Weaver.praat", ",", "AI & Adaptive/Neural Phonetic Harmonizer.praat", ",", "AI & Adaptive/Neural Phonetic Speed Mapper.praat", ",", "AI & Adaptive/NMF Spectral Resynthesizer .praat", ",", "AI & Adaptive/OT_CORPUS_CONCATENATOR.praat", ",", "AI & Adaptive/Parametric Autoencoder Resynthesis with Variations.praat", ",", "AI & Adaptive/PCA_Timbre_Selector.praat", ",", "AI & Adaptive/PCA_Tone_Shaper.praat", ",", "AI & Adaptive/Perceptual Graph.praat", ",", "AI & Adaptive/Perceptual_Synchrony.praat", ",", "AI & Adaptive/Self_Attention_Recomposer.praat", ",", "AI & Adaptive/Timbral_Similarity_Browser.praat", ",", "Analysis", ",", "Analysis/Acoustic Pedagogy.praat", ",", "Analysis/Acoustic_Features_Batch_Extraction.praat", ",", "Analysis/Adaptive Transient Decomposition.praat", ",", "Analysis/ASA Demos.praat", ",", "Analysis/Audio_Descriptions_and_Global_Statistics.praat", ",", "Analysis/Audio_File_Properties.praat", ",", "Analysis/BrightnessClassifier.praat", ",", "Analysis/CHORD DETECTION.praat", ",", "Analysis/Climax_Profile_Matcher.praat", ",", "Analysis/Continuous Pitch over MIDI Grid Visualizer.praat", ",", "Analysis/Correlation-Based Pitch Class Extraction.praat", ",", "Analysis/DTW-Aligned Multi-Feature Audio Analysis (MFCC, Loudness, Pitch).praat", ",", "Analysis/Extract_Segment.praat", ",", "Analysis/Formant to MIDI Chord Converter.praat", ",", "Analysis/Formant to MusicXML Chord Converter.praat", ",", "Analysis/Kick detector and bass adder.praat", ",", "Analysis/Krumhansl-Schmuckler Key Profiler.praat", ",", "Analysis/Melodic_Contour_Parsons_Code.praat", ",", "Analysis/MFCC.praat", ",", "Analysis/Multi-Band_Onset_Detector.praat", ",", "Analysis/Multi-Layer Audio Visualizer (EAnalysis Style).praat", ",", "Analysis/Musikalisches Würfelspiel Audio Game.praat", ",", "Analysis/OT Grammar Learning from Audio.praat", ",", "Analysis/Pitch Loop Finder.praat", ",", "Analysis/Pitch_and_Loudness_Comparison_Two_Sounds.praat", ",", "Analysis/Recursive WAV opener.praat", ",", "Analysis/Self-Similarity Matrix Calculator.praat", ",", "Analysis/Sonic Syntax.praat", ",", "Analysis/Spatial trajectory tracker.praat", ",", "Analysis/SPEAR Par-Text-Frame Format Parser for Praat.praat", ",", "Analysis/SpectraScore - Orchestration Matcher.praat", ",", "Analysis/Speech to MusicXML Rhythm Converter.praat", ",", "Analysis/Stereo Channel Similarity Meter.praat", ",", "Analysis/Tempo Curve (IOI) Estimator.praat", ",", "clip into buffer.amxd", ",", "Distortion", ",", "Distortion/Adaptive Wave Shaper.praat", ",", "Distortion/Asymmetric Soft Clipping.praat", ",", "Distortion/Chaos Distortion.praat", ",", "Distortion/Distortion & Bit-Crusher.praat", ",", "Distortion/Dynamic Distortion.praat", ",", "Distortion/Full-Wave Rectifier Abs.praat", ",", "Distortion/Hard Clip.praat", ",", "Distortion/Hysteresis Distortion.praat", ",", "Distortion/Math Operations.praat", ",", "Distortion/Multiband Distortion.praat", ",", "Distortion/Sidechain Feedback VCA.praat", ",", "Distortion/Tanh.praat", ",", "Distortion/Virtual Subharmonic Generator.praat", ",", "Distortion/Wave Shaper Distortion.praat", ",", "Distortion/Wavefolder (Foldback).praat", ",", "Dynamics & Envelope", ",", "Dynamics & Envelope/Auto-Swell.praat", ",", "Dynamics & Envelope/Auto-Trim Silence.praat", ",", "Dynamics & Envelope/Compressor.praat", ",", "Dynamics & Envelope/Concatenate with crossfade.praat", ",", "Dynamics & Envelope/Envelope Application.praat", ",", "Dynamics & Envelope/Fast Waveset Distortion.praat", ",", "Dynamics & Envelope/Intensity_Envelope_Processor.praat", ",", "Dynamics & Envelope/Kinematic Physics Envelope.praat", ",", "Dynamics & Envelope/Limiter.praat", ",", "Dynamics & Envelope/Linear_Fade-In.praat", ",", "Dynamics & Envelope/Linear_Fade-Out.praat", ",", "Dynamics & Envelope/LUFS Tool.praat", ",", "Dynamics & Envelope/Multiband Compressor.praat", ",", "Dynamics & Envelope/Noise Gate.praat", ",", "Dynamics & Envelope/Polynomial_Sound_Shaper.praat", ",", "Dynamics & Envelope/Sample-and-Hold Processor.praat", ",", "Dynamics & Envelope/Time-domain RMS envelope follower.praat", ",", "Dynamics & Envelope/Vintage Glue Compressor.praat", ",", "Dynamics & Envelope/Waveset Distortion.praat", ",", "Filter & Color", ",", "Filter & Color/a-e-i-o_filter.praat", ",", "Filter & Color/Adaptive Spectral Resonance Suppressor.praat", ",", "Filter & Color/Adaptive_Filter.praat", ",", "Filter & Color/Amplitude-Varying Ring Modulation.praat", ",", "Filter & Color/Autocorrelation-Based Self-Filtering.praat", ",", "Filter & Color/Band-Based Concatenative Synthesis.praat", ",", "Filter & Color/Bit Crusher (8-Bit Arcade).praat", ",", "Filter & Color/Classic FIR Filter Bank.praat", ",", "Filter & Color/Classic IIR Filter Bank.praat", ",", "Filter & Color/Creative Formant Manipulations.praat", ",", "Filter & Color/Cross_Synthesis.praat", ",", "Filter & Color/DYNAMIC FORMANT SWEEPER.praat", ",", "Filter & Color/Electrical_Hum_Removal.praat", ",", "Filter & Color/ENTROPY SMART DE-ESSER.praat", ",", "Filter & Color/Frequency Shifter.praat", ",", "Filter & Color/Golden_Ratio_Processor.praat", ",", "Filter & Color/GRM-Style_Resonator.praat", ",", "Filter & Color/Harmonic_Formant_Locking.praat", ",", "Filter & Color/Hilbert Transform(for drums).praat", ",", "Filter & Color/Individual_Formant_Stretcher.praat", ",", "Filter & Color/Intelligent_EQ_Adaptive_Bandpass.praat", ",", "Filter & Color/Jitter-Shimmer Formant Mapping.praat", ",", "Filter & Color/MFCC TRANSFORMER.praat", ",", "Filter & Color/Moog Ladder Filter.praat", ",", "Filter & Color/Onset-Based Oscillator Bank.praat", ",", "Filter & Color/Panning filter.praat", ",", "Filter & Color/Pitch-Based_Spectral_Notch.praat", ",", "Filter & Color/Resonant.praat", ",", "Filter & Color/Spectral Filtering Effect.praat", ",", "Filter & Color/Spectral_Band_EQ.praat", ",", "Filter & Color/Spectral_Morph.praat", ",", "Filter & Color/Voice_Quality_Sonification.praat", ",", "Filter & Color/Wah-Wah Effect.praat", ",", "Filter & Color/Whisper Morph.praat", ",", "Filter & Color/XMod.praat", ",", "Generative & Synthesis", ",", "Generative & Synthesis/Accelerating_Polyrhythm.praat", ",", "Generative & Synthesis/Advanced Brownian Synthesis.praat", ",", "Generative & Synthesis/Advanced Chaotic Modulation.praat", ",", "Generative & Synthesis/Advanced Formula Synthesis.praat", ",", "Generative & Synthesis/Advanced Poisson Synthesis.praat", ",", "Generative & Synthesis/Algorithmic Metallic Synthesis.praat", ",", "Generative & Synthesis/AM Additive Synthesis Generator.praat", ",", "Generative & Synthesis/Analogique_B_Stochastic_Mass.praat", ",", "Generative & Synthesis/Cellular Automata Synthesis.praat", ",", "Generative & Synthesis/Chaotic Function Generator.praat", ",", "Generative & Synthesis/Chaotic Granular Synthesis.praat", ",", "Generative & Synthesis/ChirikovStandardMap.praat", ",", "Generative & Synthesis/Competing Modulators.praat", ",", "Generative & Synthesis/Convolution Synthesis.praat", ",", "Generative & Synthesis/Dynamic Stochastic Synthesis.praat", ",", "Generative & Synthesis/Dynamic Vowel Transitions.praat", ",", "Generative & Synthesis/Evolving Grain Mass.praat", ",", "Generative & Synthesis/FM Texture Generator.praat", ",", "Generative & Synthesis/Formant Grain Texture.praat", ",", "Generative & Synthesis/Formant Synthesis.praat", ",", "Generative & Synthesis/Formula Markov Synthesis.praat", ",", "Generative & Synthesis/GENDYN_Synthesis.praat", ",", "Generative & Synthesis/Generative Sound System.praat", ",", "Generative & Synthesis/Grisey_Spectral_Becoming_Engine.praat", ",", "Generative & Synthesis/Karplus-Strong Texture Generator.praat", ",", "Generative & Synthesis/Kotoński_FSM_Event_Generator.praat", ",", "Generative & Synthesis/Layered Markov Texture.praat", ",", "Generative & Synthesis/Logistic Map Synthesis.praat", ",", "Generative & Synthesis/Lorenz Deep Analog.praat", ",", "Generative & Synthesis/Markov Rhythm Generator.praat", ",", "Generative & Synthesis/Organic No-Input Mixer.praat", ",", "Generative & Synthesis/Percussive Image Sonification.praat", ",", "Generative & Synthesis/Photo _sonification.praat", ",", "Generative & Synthesis/Photo Brightness-Controlled Pitch Sonification.praat", ",", "Generative & Synthesis/Poisson Point Process Synthesis.praat", ",", "Generative & Synthesis/Poisson Rhythm Synthesis.praat", ",", "Generative & Synthesis/PolyrhythmsFromDots.praat", ",", "Generative & Synthesis/Random Walk Melody.praat", ",", "Generative & Synthesis/Random Walk Rhythm.praat", ",", "Generative & Synthesis/Rich Formant Grains.praat", ",", "Generative & Synthesis/Risset's_Mutations.praat", ",", "Generative & Synthesis/SonifiedDrawing.praat", ",", "Generative & Synthesis/Spectral Image Sonification.praat", ",", "Generative & Synthesis/Stockhausen Studie II Generator.praat", ",", "Generative & Synthesis/Subtractive Synthesis Generator.praat", ",", "Generative & Synthesis/Vector_Synthesis.praat", ",", "Generative & Synthesis/Visual_Game_of_Life_Synthesis.praat", ",", "Generative & Synthesis/Wave Terrain Synthesis.praat", ",", "Generative & Synthesis/Waveguide & Modal Synthesis.praat", ",", "load_audio.praat", ",", "Modulation", ",", "Modulation/Amplitude-Following Wah-Wah.praat", ",", "Modulation/Barber-Pole_Orbit.praat", ",", "Modulation/Chaotic Prosody Manipulation.praat", ",", "Modulation/Dual-Mode Tremolo Generator.praat", ",", "Modulation/Fractal_Convolution_Swarm.praat", ",", "Modulation/Golden-chaos_vibrato.praat", ",", "Modulation/Hexaphonic Serial Audio Processor.praat", ",", "Modulation/Karplus-Strong Modulator .praat", ",", "Modulation/Metamodulator.praat", ",", "Modulation/Phonetic Tremolo-Glitch Effect.praat", ",", "Modulation/Rhythmic LFO Wah-Wah.praat", ",", "Modulation/Spectral-Driven Intensity Modulation.praat", ",", "Modulation/Spectral_Driven_Vibrato.praat", ",", "Modulation/Stereo Flanger.praat", ",", "Modulation/Stereo Phaser.praat", ",", "Modulation/Stereo Rotary Speaker.praat", ",", "Modulation/Stereo_Swirl_Vibrato.praat", ",", "Modulation/Stretch-Tremolo Ambience.praat", ",", "Modulation/Time_Varying_Spectral_Vibrato.praat", ",", "Modulation/Unified Chorus Generator.praat", ",", "Modulation/Unified Multi-Mode Vibrato.praat", ",", "Modulation/XY SHAPE LFO - FREQUENCY MODULATION.praat", ",", "Pitch", ",", "Pitch/Adaptive Pitch Shifter.praat", ",", "Pitch/Auto-Harmonic Layering.praat", ",", "Pitch/Bimodal Contour Grammar.praat", ",", "Pitch/Breathing_Pitch_Waves.praat", ",", "Pitch/Chord Generator from Audio.praat", ",", "Pitch/Doppler_Effect_Simulator.praat", ",", "Pitch/Exponential Glide Up.praat", ",", "Pitch/flip or expand the F0 contours.praat", ",", "Pitch/Formula Audio Manipulation.praat", ",", "Pitch/Fractal_Pitch_Terrain.praat", ",", "Pitch/L-System_Granular_Pitch.praat", ",", "Pitch/Messagesquisse_Opening.praat", ",", "Pitch/Microtonal_Harmonic_Field_Engine.praat", ",", "Pitch/Pitch Correction.praat", ",", "Pitch/Pitch Processor.praat", ",", "Pitch/Pitch Stylization and Shift.praat", ",", "Pitch/Pitch_Contour_Transfer.praat", ",", "Pitch/Pitch_Morphing_Between_Targets.praat", ",", "Pitch/Pitch_Shift_Semitones.praat", ",", "Pitch/Quantum_Pitch_Jumps.praat", ",", "Pitch/Rhythmic_Pitch_Percussion.praat", ",", "Pitch/Spectral_Pitch_Shifter.praat", ",", "Pitch/Spiral_Pitch_Dance.praat", ",", "Pitch/Spiral_Segmentation.praat", ",", "Pitch/Tempo-Pitch Curves (Accelerando & Ritardando).praat", ",", "Pitch/Undertone_Field.praat", ",", "Pitch/Voice_Transformation.praat", ",", "praat.maxpat", ",", "py", ",", "py/AI_Conductor_Mix.praat", ",", "py/ai_conductor_mix.py", ",", "py/Arranger.praat", ",", "py/arranger.py", ",", "py/Dereverberation.praat", ",", "py/dereverberation.py", ",", "py/Envelope_Editor.praat", ",", "py/envelope_editor.py", ",", "py/formant_swarm_granulator.py", ",", "py/FormantSwarmGranulator.praat", ",", "py/granular_navigation_engine.py", ",", "py/GranularNavigationEngine.praat", ",", "py/hierarchical_recomposition.py", ",", "py/HierarchicalRecomposition.praat", ",", "py/host_vst.py", ",", "py/HPSS_Phase_Vocoder.praat", ",", "py/identity_separation.py", ",", "py/IdentitySeparation.praat", ",", "py/INSTALL.txt", ",", "py/internal_polyphony.py", ",", "py/InternalPolyphony.praat", ",", "py/latent_barycentric.py", ",", "py/latent_counterpoint.py", ",", "py/latent_diffusion.py", ",", "py/latent_folding.py", ",", "py/latent_nav_plan.csv", ",", "py/latent_navigation.py", ",", "py/latent_relocation.py", ",", "py/latent_spat.py", ",", "py/latent_stft_decoder.py", ",", "py/latent_time_warp.py", ",", "py/LatentBarycentric.praat", ",", "py/LatentCounterpoint.praat", ",", "py/LatentDiffusion.praat", ",", "py/LatentFolding.praat", ",", "py/LatentNavigation.praat", ",", "py/LatentRelocation.praat", ",", "py/LatentSpat.praat", ",", "py/LatentSTFTDecoder.praat", ",", "py/multichannel_play.py", ",", "py/Paulstretch.praat", ",", "py/paulstretch.py", ",", "py/phase_diffusion_ai.py", ",", "py/phase_space_compose.py", ",", "py/PhaseDiffusion.praat", ",", "py/PhaseSpaceComposer.praat", ",", "py/phrase_rewriter.py", ",", "py/PhraseRewriter.praat", ",", "py/PlayMultichannel.praat", ",", "py/PraatPbind.praat", ",", "py/PraatPbind.py", ",", "py/Recomposer.praat", ",", "py/recomposer.py", ",", "py/reflect_analyze.py", ",", "py/rhythmic_voice_flattener.py", ",", "py/RhythmicVoiceFlattener.praat", ",", "py/self_attention_latent.py", ",", "py/SelfAttentionLatent.praat", ",", "py/SelfReflectiveFeedback.praat", ",", "py/Spatial_Panner.praat", ",", "py/spatial_panner.py", ",", "py/Spectral_Freeze.praat", ",", "py/spectral_freeze.py", ",", "py/Spectral_Morph.praat", ",", "py/spectral_morph.py", ",", "py/ssm_morph_engine.py", ",", "py/SSMComposer.praat", ",", "py/stretch.py", ",", "py/sympathetic_resonance.py", ",", "py/SympatheticResonance.praat", ",", "py/TemporalElasticity.praat", ",", "py/thermodynamic_transform.py", ",", "py/ThermodynamicTransform.praat", ",", "py/VST_Effect_from_Praat.praat", ",", "Reverb", ",", "Reverb/Artificial Room.praat", ",", "Reverb/Cascading_Echoes.praat", ",", "Reverb/Chaotic_Bloom.praat", ",", "Reverb/Convolve_Bursts_Taps.praat", ",", "Reverb/Convolve_Stereo_Fibonacci.praat", ",", "Reverb/Crystalline_Cascade.praat", ",", "Reverb/Entropy_Modulated_Reverb.praat", ",", "Reverb/Feedback_Aware_Convolution.praat", ",", "Reverb/Fractal Feedback.praat", ",", "Reverb/Fractal_Feedback_Reverb.praat", ",", "Reverb/Granular_Displacement.praat", ",", "Reverb/Gravitational_Lens_ Reverb.praat", ",", "Reverb/Harmonic Decay Reverb.praat", ",", "Reverb/Harmonic_Comb.praat", ",", "Reverb/Ligeti Micropolyphonic Choir Machine.praat", ",", "Reverb/Morphing_Resonance.praat", ",", "Reverb/Ping_Pong_Field.praat", ",", "Reverb/Quantum_Uncertainty_Reverb.praat", ",", "Reverb/Ray Tracing Room Acoustics.praat", ",", "Reverb/Ribbon_Shimmer.praat", ",", "Reverb/Smooth Cosmic Reverb.praat", ",", "Reverb/Spectral_Decay.praat", ",", "Reverb/Spectral_Drift.praat", ",", "Reverb/Spectral_Smearing Reverb.praat", ",", "Reverb/Stereo_Ping-Pong_Impulses .praat", ",", "Reverb/Stereo_Shimmer.praat", ",", "Reverb/Temporal_Erosion.praat", ",", "Reverb/Temporal_Warping.praat", ",", "Reverb/The Lucier Machine.praat", ",", "Reverb/Universal Convolution Generator.praat", ",", "setup.praat", ",", "Spatial & Surround", ",", "Spatial & Surround/3D Audio Room Simulator with Distance-Based Panning.praat", ",", "Spatial & Surround/4-Channel Canon.praat", ",", "Spatial & Surround/8 Channels Time Polyphony.praat", ",", "Spatial & Surround/8-Channel Canon.praat", ",", "Spatial & Surround/8-channel I Ching.praat", ",", "Spatial & Surround/8-Channel movements.praat", ",", "Spatial & Surround/8-Channel Spectral Shift.praat", ",", "Spatial & Surround/8-Channel Speech-Driven Spatialization.praat", ",", "Spatial & Surround/8-channel speed deviations.praat", ",", "Spatial & Surround/8-Channel_Comb_Delay.praat", ",", "Spatial & Surround/Advanced Stereo Panner.praat", ",", "Spatial & Surround/BPM_Panning.praat", ",", "Spatial & Surround/BPM_SURROUND _Panning.praat", ",", "Spatial & Surround/DBAP with Movement Control.praat", ",", "Spatial & Surround/Distance-Based Amplitude Panning (DBAP).praat", ",", "Spatial & Surround/Distribute sounds in stereo field.praat", ",", "Spatial & Surround/Even-Odd Harmonic Binaural Separation.praat", ",", "Spatial & Surround/Fast Spectral Swirl Multi-Channel.praat", ",", "Spatial & Surround/Higher-Order Ambisonic Decoder.praat", ",", "Spatial & Surround/Higher-Order Ambisonic Encoder.praat", ",", "Spatial & Surround/Knight's Tour Sonification.praat", ",", "Spatial & Surround/MCMC_Musical_Variation.praat", ",", "Spatial & Surround/Microphone Simulation.praat", ",", "Spatial & Surround/Mix Multi-Channel to Stereo.praat", ",", "Spatial & Surround/Multi-channel Random Slice Time-Stretcher.praat", ",", "Spatial & Surround/Multitrack_Router.praat", ",", "Spatial & Surround/Panning variations.praat", ",", "Spatial & Surround/Partial Panner.praat", ",", "Spatial & Surround/Perceptual_Fugue.praat", ",", "Spatial & Surround/Physics-Based Stereo Dynamics.praat", ",", "Spatial & Surround/Random DurationTier Multichannel Generator.praat", ",", "Spatial & Surround/Simple Rate Panning.praat", ",", "Spatial & Surround/Spectral_Panning_Mapper.praat", ",", "Spatial & Surround/Stereo_Mixer.praat", ",", "Spectral", ",", "Spectral/Basic Mirror.praat", ",", "Spectral/Bell curve envelope.praat", ",", "Spectral/Doppler shift.praat", ",", "Spectral/Dynamic Tremolo Effect.praat", ",", "Spectral/Fractal Spectral Hologram.praat", ",", "Spectral/Frequency-Dependent Phase Manipulation.praat", ",", "Spectral/Harmonic Resonance Boost.praat", ",", "Spectral/Hilbert Transform.praat", ",", "Spectral/LPC Voice Generator.praat", ",", "Spectral/LPC Voice Morphing.praat", ",", "Spectral/Non-Linear Frequency Folding.praat", ",", "Spectral/Partial Editing & Resynthesis.praat", ",", "Spectral/Phase History Swap.praat", ",", "Spectral/Phase Shaper.praat", ",", "Spectral/Self-Similarity Spectral Resynthesis.praat", ",", "Spectral/Spectral Effects Suite.praat", ",", "Spectral/Spectral Freeze Synthesis.praat", ",", "Spectral/Spectral Painter.praat", ",", "Spectral/Spectral swirl effect.praat", ",", "Spectral/Spectral_Blur.praat", ",", "Spectral/Stepped Notch Filter.praat", ",", "Spectral/Subtle Random Texture.praat", ",", "Spectral/Vocoding.praat", ",", "Spectral/Wave Interference Pattern.praat", ",", "Time & Granular", ",", "Time & Granular/Adaptive Grain Cloud Synthesis.praat", ",", "Time & Granular/Additive_Particle_Field.praat", ",", "Time & Granular/Beat Repeat.praat", ",", "Time & Granular/Beat-Synced ZigZag.praat", ",", "Time & Granular/Bigram_Stutter_Effect.praat", ",", "Time & Granular/Brownian Motion Texture Generator.praat", ",", "Time & Granular/Constraint-Based Duration Control.praat", ",", "Time & Granular/Delay Array.praat", ",", "Time & Granular/Dramaturgical_Structure_Composer.praat", ",", "Time & Granular/Evolving Granular.praat", ",", "Time & Granular/Fractal_Convolution_Matrix.praat", ",", "Time & Granular/Granular_Particle_Field.praat", ",", "Time & Granular/Harmonic_Resonance.praat", ",", "Time & Granular/Harmonic_Tension_Sorted_Grains.praat", ",", "Time & Granular/HFD-Driven Time Warping.praat", ",", "Time & Granular/In-Place Paulstretch Slicer (Multi-channel).praat", ",", "Time & Granular/L-Logic_Symbolic_Granular_Recomposition.praat", ",", "Time & Granular/Magnetic_Tape_Degradation.praat", ",", "Time & Granular/MDS Space Navigator.praat", ",", "Time & Granular/Paulstretch.praat", ",", "Time & Granular/Peephole montage.praat", ",", "Time & Granular/Percussive Audio Groove Creator.praat", ",", "Time & Granular/Phase_Modulation_Matrix.praat", ",", "Time & Granular/Polyphonic_Improviser.praat", ",", "Time & Granular/Quantum_State_Superposition.praat", ",", "Time & Granular/Reich Generator.praat", ",", "Time & Granular/Rhythmic Fractal Granulator.praat", ",", "Time & Granular/Segment_mixer.praat", ",", "Time & Granular/Sorts grains from dark to bright.praat", ",", "Time & Granular/Sound to Grain.praat", ",", "Time & Granular/Sound_atom_composer.praat", ",", "Time & Granular/Spectral_Echo_Cascade.praat", ",", "Time & Granular/Spectral_Freeze_&_Glitch.praat", ",", "Time & Granular/Stereo Delay Splitter.praat", ",", "Time & Granular/Stereo Mosaic.praat", ",", "Time & Granular/Stereo_Micro_Macro_Time_Collapser.praat", ",", "Time & Granular/Stochastic_Time_Folding.praat", ",", "Time & Granular/Temporal_Turing_Morph.praat", ",", "Time & Granular/Time Manipulation.praat", ",", "Time & Granular/Total Serialism Machine.praat", ",", "Time & Granular/ZigZag_Effect.praat", ",", "Vector Chain", ",", "Vector Chain/chain_1.praat", ",", "Vector Chain/chain_2.praat", ",", "Vector Chain/chain_3.praat", ",", "Vector Chain/chain_4.praat", ",", "Vector Chain/chain_5.praat", ",", "Vector Chain/chain_6.praat", ",", "Vector Chain/cleanup.praat", ",", "Vector Chain/Composition_1.praat", ",", "Vector Chain/Composition_2.praat", ",", "Vector Chain/Live_1.praat", ",", "Vector Chain/Live_1_Random.praat", ",", "Vector Chain/Live_2.praat", ",", "Vector Chain/Live_2_Random.praat", ",", "Vector Chain/Live_3.praat", ",", "Vector Chain/Live_3_Random.praat", ",", "Vector Chain/Live_4.praat", ",", "Vector Chain/Live_5.praat", ",", "Vector Chain/Live_6.praat", ",", "Vector Chain/send_audio_to_Ableton.praat", ",", "Vector Chain/send_audio_to_Max.praat" ],
                    "maxclass": "umenu",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "int", "", "" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 9.0, 176.0, 293.0, 22.0 ],
                    "prefix": "~/Praat/plugin_AudioTools/"
                }
            },
            {
                "box": {
                    "id": "obj-11",
                    "maxclass": "toggle",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 114.0, 420.0, 24.0, 24.0 ]
                }
            },
            {
                "box": {
                    "id": "obj-8",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 0,
                    "patching_rect": [ 114.0, 569.0, 54.0, 22.0 ],
                    "text": "mc.dac~"
                }
            },
            {
                "box": {
                    "id": "obj-4",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 9,
                    "outlettype": [ "signal", "signal", "signal", "signal", "signal", "signal", "signal", "signal", "bang" ],
                    "patching_rect": [ 114.0, 458.0, 144.0, 22.0 ],
                    "text": "play~ myOutput 8"
                }
            },
            {
                "box": {
                    "id": "obj-9",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 260.0, 290.0, 47.0, 22.0 ],
                    "text": "receive"
                }
            },
            {
                "box": {
                    "id": "obj-6",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 216.0, 290.0, 35.0, 22.0 ],
                    "text": "send"
                }
            },
            {
                "box": {
                    "id": "obj-2",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "float", "bang" ],
                    "patching_rect": [ 369.0, 302.0, 141.0, 22.0 ],
                    "text": "buffer~ myOutput 5000 8"
                }
            },
            {
                "box": {
                    "id": "obj-7",
                    "maxclass": "message",
                    "numinlets": 2,
                    "numoutlets": 1,
                    "outlettype": [ "" ],
                    "patching_rect": [ 171.0, 290.0, 35.0, 22.0 ],
                    "text": "open"
                }
            },
            {
                "box": {
                    "id": "obj-5",
                    "maxclass": "button",
                    "numinlets": 1,
                    "numoutlets": 1,
                    "outlettype": [ "bang" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 9.0, 228.0, 88.0, 88.0 ]
                }
            },
            {
                "box": {
                    "id": "obj-3",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "float", "bang" ],
                    "patching_rect": [ 369.0, 339.0, 205.0, 22.0 ],
                    "text": "buffer~ myInput drumLoop.aif 5000 2"
                }
            },
            {
                "box": {
                    "id": "obj-1",
                    "maxclass": "newobj",
                    "numinlets": 1,
                    "numoutlets": 2,
                    "outlettype": [ "bang", "bang" ],
                    "patching_rect": [ 146.0, 339.0, 206.0, 22.0 ],
                    "text": "AudioTools.praat~ myInput myOutput"
                }
            },
            {
                "box": {
                    "background": 1,
                    "bgcolor": [ 0.9, 0.65, 0.05, 1.0 ],
                    "fontface": 1,
                    "hint": "",
                    "id": "obj-13",
                    "ignoreclick": 1,
                    "legacytextcolor": 1,
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 62.0, 138.0, 20.0, 20.0 ],
                    "rounded": 60.0,
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": "themecolor.lesson_step_circle"
                        }
                    },
                    "text": "1",
                    "textcolor": [ 0.34902, 0.34902, 0.34902, 1.0 ]
                }
            },
            {
                "box": {
                    "background": 1,
                    "bgcolor": [ 0.9, 0.65, 0.05, 1.0 ],
                    "fontface": 1,
                    "hint": "",
                    "id": "obj-21",
                    "ignoreclick": 1,
                    "legacytextcolor": 1,
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 116.0, 388.0, 20.0, 20.0 ],
                    "rounded": 60.0,
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": "themecolor.lesson_step_circle"
                        }
                    },
                    "text": "3",
                    "textcolor": [ 0.34902, 0.34902, 0.34902, 1.0 ]
                }
            },
            {
                "box": {
                    "background": 1,
                    "bgcolor": [ 0.9, 0.65, 0.05, 1.0 ],
                    "fontface": 1,
                    "hint": "",
                    "id": "obj-16",
                    "ignoreclick": 1,
                    "legacytextcolor": 1,
                    "maxclass": "textbutton",
                    "numinlets": 1,
                    "numoutlets": 3,
                    "outlettype": [ "", "", "int" ],
                    "parameter_enable": 0,
                    "patching_rect": [ 43.0, 202.0, 20.0, 20.0 ],
                    "rounded": 60.0,
                    "saved_attribute_attributes": {
                        "bgcolor": {
                            "expression": "themecolor.lesson_step_circle"
                        }
                    },
                    "text": "2",
                    "textcolor": [ 0.34902, 0.34902, 0.34902, 1.0 ]
                }
            }
        ],
        "lines": [
            {
                "patchline": {
                    "destination": [ "obj-23", 0 ],
                    "source": [ "obj-1", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-35", 0 ],
                    "hidden": 1,
                    "source": [ "obj-10", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-4", 0 ],
                    "midpoints": [ 123.5, 447.0, 123.5, 447.0 ],
                    "source": [ "obj-11", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-17", 0 ],
                    "midpoints": [ 155.5, 199.0, 155.5, 199.0 ],
                    "source": [ "obj-12", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-2", 0 ],
                    "midpoints": [ 378.5, 288.0, 378.5, 288.0 ],
                    "source": [ "obj-14", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "source": [ "obj-17", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-15", 0 ],
                    "midpoints": [ 333.0, 157.5, 333.0, 157.5 ],
                    "source": [ "obj-19", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-12", 0 ],
                    "midpoints": [ 18.5, 160.0, 18.5, 160.0 ],
                    "source": [ "obj-20", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-24", 0 ],
                    "source": [ "obj-22", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-25", 0 ],
                    "midpoints": [ 155.5, 406.0, 155.5, 406.0 ],
                    "source": [ "obj-23", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-18", 0 ],
                    "hidden": 1,
                    "midpoints": [ 123.5, 558.0, 108.0, 558.0, 108.0, 405.0, 18.5, 405.0 ],
                    "order": 1,
                    "source": [ "obj-24", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-8", 0 ],
                    "order": 0,
                    "source": [ "obj-24", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-4", 0 ],
                    "source": [ "obj-25", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "midpoints": [ 325.5, 324.0, 155.5, 324.0 ],
                    "source": [ "obj-27", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-3", 0 ],
                    "source": [ "obj-31", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-24", 1 ],
                    "source": [ "obj-35", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-38", 1 ],
                    "order": 0,
                    "source": [ "obj-37", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-38", 0 ],
                    "order": 1,
                    "source": [ "obj-37", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 7 ],
                    "source": [ "obj-4", 7 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 6 ],
                    "source": [ "obj-4", 6 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 5 ],
                    "source": [ "obj-4", 5 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 4 ],
                    "source": [ "obj-4", 4 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 3 ],
                    "source": [ "obj-4", 3 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 2 ],
                    "source": [ "obj-4", 2 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 1 ],
                    "source": [ "obj-4", 1 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-22", 0 ],
                    "source": [ "obj-4", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-37", 0 ],
                    "source": [ "obj-40", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-4", 0 ],
                    "source": [ "obj-41", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "midpoints": [ 18.5, 323.0, 155.5, 323.0 ],
                    "source": [ "obj-5", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-47", 0 ],
                    "hidden": 1,
                    "source": [ "obj-54", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "midpoints": [ 225.5, 324.0, 155.5, 324.0 ],
                    "source": [ "obj-6", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "midpoints": [ 180.5, 324.0, 155.5, 324.0 ],
                    "source": [ "obj-7", 0 ]
                }
            },
            {
                "patchline": {
                    "destination": [ "obj-1", 0 ],
                    "midpoints": [ 269.5, 324.0, 155.5, 324.0 ],
                    "source": [ "obj-9", 0 ]
                }
            }
        ],
        "parameters": {
            "obj-35": [ "Gain", "Gain", 0 ],
            "inherited_shortname": 1
        },
        "autosave": 0
    }
}