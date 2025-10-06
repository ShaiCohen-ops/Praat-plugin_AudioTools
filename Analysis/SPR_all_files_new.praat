# ============================================================
# Praat AudioTools - SPR_all_files_new.praat
# Author: Shai Cohen
# Affiliation: Department of Music, Bar-Ilan University, Israel
# Email: shai.cohen@biu.ac.il
# Version: 0.1 (2025)
# License: MIT License
# Repository: https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
#
# Description:
#   Analytical measurement or feature-extraction script
#
# Usage:
#   Select a Sound object in Praat and run this script.
#   Adjust parameters via the form dialog.
#
# Citation:
#   Cohen, S. (2025). Praat AudioTools: An Offline Analysis–Resynthesis Toolkit for Experimental Composition.
#   https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools
# ============================================================

# This Praat script is designed to measure the Singing Power Ratio (SPR) from multiple audio samples.
# It creates a spectrum of each sound file and tabulates the spectrum values. 
# Then it extracts the maximum power values from two frequency bands: 50-2000 Hz and 2000-4000 Hz.
# By calculating the difference between these maximum values, the script determines the SPR.
# The results are displayed in the Info window.
# Last update: January 13th 2025.
# Improved version with better error handling, object cleanup, and batch processing capability.
# Instructions:
# Open Praat and load the script.
# In the Praat Objects window, select all the audio files you want to analyze.
# Run the script.
# The Praat Info window will pop up and provide the SPR results for all files.
# If you use this script in your research or publication, please cite it as follows (or check the OSF page for more details):
# "Väisänen, A. (2025). Praat Script for Measuring Singing Power Ratio (SPR). https://doi.org/10.17605/OSF.IO/MGPFQ"
##########

clearinfo

# Check if Sound objects are selected
number_of_selected_sounds = numberOfSelected("Sound")
if number_of_selected_sounds = 0
    appendInfo: "Error: Please select one or more Sound objects first.", newline$
    exit
endif

# Store references to all selected sounds
for index to number_of_selected_sounds
    sound'index' = selected("Sound", index)
endfor

appendInfo: "SPR Analysis Results", newline$
appendInfo: "===================", newline$, newline$

# Create a results table for Excel export
Create Table with column names: "SPR_Results", number_of_selected_sounds, "Filename SPR_dB LowBand_dB HighBand_dB"

# Process each sound file
for current_sound_index from 1 to number_of_selected_sounds
    select sound'current_sound_index'
    soundname$ = selected$("Sound")
    
    appendInfo: "Processing: ", soundname$, newline$
    
    # Create spectrum
    To Spectrum: "yes"
    spectrumName$ = "Spectrum " + soundname$
    
    # Tabulate spectrum values
    selectObject: spectrumName$
    Tabulate: "no", "yes", "no", "no", "no", "yes"
    mainTableName$ = "Table " + soundname$
    
    # Extract the maximum value from the 50-2000 Hz band
    selectObject: mainTableName$
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 50
    lowTable1ID = selected()
    lowTable1$ = selected$()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 2000
    lowTable2ID = selected()
    lowTable2$ = selected$()
    lowbandmax = Get maximum: "pow(dB/Hz)"
    
    # Extract the maximum value from the 2000-4000 Hz band
    selectObject: mainTableName$
    Extract rows where column (number): "freq(Hz)", "greater than or equal to", 2000
    highTable1ID = selected()
    highTable1$ = selected$()
    Extract rows where column (number): "freq(Hz)", "less than or equal to", 4000
    highTable2ID = selected()
    highTable2$ = selected$()
    highbandmax = Get maximum: "pow(dB/Hz)"
    
    # Calculate the difference between the maximum values of the bands
    spr = lowbandmax - highbandmax
    
    # Output results for this file
    appendInfo: "  SPR: ", fixed$(spr, 3), " dB", newline$
    appendInfo: "  Low band max (50-2000 Hz): ", fixed$(lowbandmax, 3), " dB/Hz", newline$
    appendInfo: "  High band max (2000-4000 Hz): ", fixed$(highbandmax, 3), " dB/Hz", newline$, newline$
    
    # Add results to the table
    selectObject: "Table SPR_Results"
    Set string value: current_sound_index, "Filename", soundname$
    Set numeric value: current_sound_index, "SPR_dB", spr
    Set numeric value: current_sound_index, "LowBand_dB", lowbandmax
    Set numeric value: current_sound_index, "HighBand_dB", highbandmax
    
    # Remove all created objects for this sound using object IDs
    selectObject: spectrumName$
    plusObject: mainTableName$
    plusObject: lowTable1ID
    plusObject: lowTable2ID
    plusObject: highTable1ID
    plusObject: highTable2ID
    Remove
endfor

# Reselect all original sound files
select sound1
for current_sound_index from 2 to number_of_selected_sounds
    plus sound'current_sound_index'
endfor

appendInfo: "===================", newline$
appendInfo: "Analysis complete for ", number_of_selected_sounds, " sound file(s).", newline$
appendInfo: "All temporary objects removed. Original sound files remain selected.", newline$
appendInfo: newline$, "RESULTS TABLE CREATED: 'Table SPR_Results'", newline$
appendInfo: "To export to Excel: Select the 'Table SPR_Results' object and choose 'Save as comma-separated file...'", newline$