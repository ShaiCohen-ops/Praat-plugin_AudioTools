# Double-click launcher for the Praat_Vangnet GUI (Windows: runs without
# a console window via pythonw). Keep this file next to the
# praat_vangnet/ package folder.
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent))
from praat_vangnet.gui import main
main()
