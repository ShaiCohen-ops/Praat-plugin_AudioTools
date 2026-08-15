{
  "patcher" : {
    "fileversion" : 1,
    "appversion" : { "major" : 9, "minor" : 1, "revision" : 4, "architecture" : "x64", "modernui" : 1 },
    "classnamespace" : "box",
    "rect" : [ 80.0, 80.0, 1000.0, 680.0 ],
    "openinpresentation" : 0,
    "boxes" : [
      { "box" : { "id" : "obj-1", "maxclass" : "comment", "text" : "AudioTools.praat~ macOS smoke test", "fontsize" : 20.0, "patching_rect" : [ 30.0, 16.0, 420.0, 28.0 ] } },
      { "box" : { "id" : "obj-40", "maxclass" : "comment", "text" : "Tip: use the short test-tone.wav so the waveforms are easy to see. Very long files look empty at default zoom.", "patching_rect" : [ 30.0, 44.0, 700.0, 20.0 ] } },

      { "box" : { "id" : "obj-30", "maxclass" : "newobj", "text" : "loadbang", "patching_rect" : [ 30.0, 72.0, 60.0, 22.0 ] } },
      { "box" : { "id" : "obj-4", "maxclass" : "message", "text" : "replace \"/Users/shlomikeslin/Desktop/AudioToolsPraat_Test/test-tone.wav\"", "patching_rect" : [ 30.0, 100.0, 480.0, 22.0 ] } },
      { "box" : { "id" : "obj-5", "maxclass" : "comment", "text" : "1. Click this to load the short test tone", "patching_rect" : [ 520.0, 100.0, 280.0, 22.0 ] } },

      { "box" : { "id" : "obj-2", "maxclass" : "newobj", "text" : "buffer~ input", "varname" : "bufin", "patching_rect" : [ 30.0, 130.0, 100.0, 22.0 ] } },
      { "box" : { "id" : "obj-3", "maxclass" : "newobj", "text" : "buffer~ output 5000", "varname" : "bufout", "patching_rect" : [ 150.0, 130.0, 140.0, 22.0 ] } },
      { "box" : { "id" : "obj-41", "maxclass" : "message", "text" : "size", "patching_rect" : [ 310.0, 130.0, 40.0, 22.0 ] } },
      { "box" : { "id" : "obj-42", "maxclass" : "newobj", "text" : "print input_buffer", "patching_rect" : [ 360.0, 130.0, 110.0, 22.0 ] } },

      { "box" : { "id" : "obj-35", "maxclass" : "message", "text" : "read", "patching_rect" : [ 30.0, 160.0, 40.0, 22.0 ] } },
      { "box" : { "id" : "obj-36", "maxclass" : "comment", "text" : "or click read / drag a wav onto left dropfile", "patching_rect" : [ 80.0, 160.0, 280.0, 22.0 ] } },
      { "box" : { "id" : "obj-31", "maxclass" : "newobj", "text" : "dropfile", "patching_rect" : [ 30.0, 190.0, 55.0, 22.0 ] } },
      { "box" : { "id" : "obj-32", "maxclass" : "newobj", "text" : "conformpath native boot", "patching_rect" : [ 30.0, 215.0, 145.0, 22.0 ] } },
      { "box" : { "id" : "obj-33", "maxclass" : "newobj", "text" : "prepend replace", "patching_rect" : [ 30.0, 240.0, 100.0, 22.0 ] } },

      { "box" : { "id" : "obj-20", "maxclass" : "newobj", "text" : "waveform~ input", "varname" : "wavein", "patching_rect" : [ 30.0, 280.0, 250.0, 120.0 ] } },
      { "box" : { "id" : "obj-21", "maxclass" : "newobj", "text" : "waveform~ output", "varname" : "waveout", "patching_rect" : [ 30.0, 430.0, 250.0, 120.0 ] } },
      { "box" : { "id" : "obj-43", "maxclass" : "message", "text" : "set input", "patching_rect" : [ 300.0, 280.0, 70.0, 22.0 ] } },
      { "box" : { "id" : "obj-44", "maxclass" : "message", "text" : "set output", "patching_rect" : [ 300.0, 430.0, 80.0, 22.0 ] } },

      { "box" : { "id" : "obj-7", "maxclass" : "message", "text" : "praat /Applications/Praat.app", "patching_rect" : [ 380.0, 190.0, 205.0, 22.0 ] } },
      { "box" : { "id" : "obj-8", "maxclass" : "comment", "text" : "2. Set Praat path", "patching_rect" : [ 595.0, 190.0, 130.0, 22.0 ] } },
      { "box" : { "id" : "obj-18", "maxclass" : "message", "text" : "open", "patching_rect" : [ 740.0, 190.0, 45.0, 22.0 ] } },

      { "box" : { "id" : "obj-9", "maxclass" : "newobj", "text" : "dropfile", "patching_rect" : [ 380.0, 230.0, 55.0, 22.0 ] } },
      { "box" : { "id" : "obj-23", "maxclass" : "newobj", "text" : "conformpath native boot", "patching_rect" : [ 380.0, 255.0, 145.0, 22.0 ] } },
      { "box" : { "id" : "obj-10", "maxclass" : "newobj", "text" : "prepend script", "patching_rect" : [ 380.0, 280.0, 95.0, 22.0 ] } },
      { "box" : { "id" : "obj-11", "maxclass" : "comment", "text" : "3. Drag a .praat script here (try roundtrip_identity.praat first)", "patching_rect" : [ 540.0, 230.0, 400.0, 22.0 ] } },

      { "box" : { "id" : "obj-12", "maxclass" : "message", "text" : "bang", "patching_rect" : [ 380.0, 320.0, 45.0, 22.0 ] } },
      { "box" : { "id" : "obj-13", "maxclass" : "comment", "text" : "4. Run bang", "patching_rect" : [ 435.0, 320.0, 100.0, 22.0 ] } },

      { "box" : { "id" : "obj-6", "maxclass" : "newobj", "text" : "AudioTools.praat~ input output", "varname" : "at", "patching_rect" : [ 380.0, 360.0, 220.0, 22.0 ] } },
      { "box" : { "id" : "obj-14", "maxclass" : "button", "patching_rect" : [ 380.0, 400.0, 24.0, 24.0 ] } },
      { "box" : { "id" : "obj-15", "maxclass" : "comment", "text" : "SUCCESS", "patching_rect" : [ 415.0, 402.0, 80.0, 22.0 ] } },
      { "box" : { "id" : "obj-16", "maxclass" : "button", "patching_rect" : [ 520.0, 400.0, 24.0, 24.0 ] } },
      { "box" : { "id" : "obj-17", "maxclass" : "comment", "text" : "ERROR / TIMEOUT", "patching_rect" : [ 555.0, 402.0, 130.0, 22.0 ] } },

      { "box" : { "id" : "obj-45", "maxclass" : "newobj", "text" : "t b b", "patching_rect" : [ 380.0, 450.0, 40.0, 22.0 ] } },
      { "box" : { "id" : "obj-22", "maxclass" : "comment", "text" : "SUCCESS also refreshes both waveforms. Console said it worked.", "patching_rect" : [ 380.0, 490.0, 420.0, 40.0 ] } }
    ],
    "lines" : [
      { "patchline" : { "source" : [ "obj-30", 0 ], "destination" : [ "obj-4", 0 ] } },
      { "patchline" : { "source" : [ "obj-4", 0 ], "destination" : [ "obj-2", 0 ] } },
      { "patchline" : { "source" : [ "obj-4", 0 ], "destination" : [ "obj-43", 0 ] } },
      { "patchline" : { "source" : [ "obj-35", 0 ], "destination" : [ "obj-2", 0 ] } },
      { "patchline" : { "source" : [ "obj-31", 0 ], "destination" : [ "obj-32", 0 ] } },
      { "patchline" : { "source" : [ "obj-32", 0 ], "destination" : [ "obj-33", 0 ] } },
      { "patchline" : { "source" : [ "obj-33", 0 ], "destination" : [ "obj-2", 0 ] } },
      { "patchline" : { "source" : [ "obj-33", 0 ], "destination" : [ "obj-43", 0 ] } },
      { "patchline" : { "source" : [ "obj-41", 0 ], "destination" : [ "obj-2", 0 ] } },
      { "patchline" : { "source" : [ "obj-2", 1 ], "destination" : [ "obj-42", 0 ] } },
      { "patchline" : { "source" : [ "obj-43", 0 ], "destination" : [ "obj-20", 0 ] } },
      { "patchline" : { "source" : [ "obj-44", 0 ], "destination" : [ "obj-21", 0 ] } },
      { "patchline" : { "source" : [ "obj-7", 0 ], "destination" : [ "obj-6", 0 ] } },
      { "patchline" : { "source" : [ "obj-18", 0 ], "destination" : [ "obj-6", 0 ] } },
      { "patchline" : { "source" : [ "obj-9", 0 ], "destination" : [ "obj-23", 0 ] } },
      { "patchline" : { "source" : [ "obj-23", 0 ], "destination" : [ "obj-10", 0 ] } },
      { "patchline" : { "source" : [ "obj-10", 0 ], "destination" : [ "obj-6", 0 ] } },
      { "patchline" : { "source" : [ "obj-12", 0 ], "destination" : [ "obj-6", 0 ] } },
      { "patchline" : { "source" : [ "obj-6", 0 ], "destination" : [ "obj-14", 0 ] } },
      { "patchline" : { "source" : [ "obj-6", 0 ], "destination" : [ "obj-45", 0 ] } },
      { "patchline" : { "source" : [ "obj-6", 1 ], "destination" : [ "obj-16", 0 ] } },
      { "patchline" : { "source" : [ "obj-45", 0 ], "destination" : [ "obj-43", 0 ] } },
      { "patchline" : { "source" : [ "obj-45", 1 ], "destination" : [ "obj-44", 0 ] } }
    ]
  }
}
