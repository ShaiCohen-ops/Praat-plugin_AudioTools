## Installation

1. **Download or clone** this repository.

   ```bash
   git clone https://github.com/ShaiCohen-ops/Praat-plugin_AudioTools.git
   ```

   Or [⬇️ download the entire package](plugin_AudioTools.zip) · [⬇️ download Audio Figures](AudioFigures.zip)

2. **Locate your Praat preferences folder.**

   Praat automatically loads plugins from folders whose names begin with `plugin_` and that are placed directly inside the Praat preferences folder.

   ### Praat 7.x

   * **Windows:**
     `C:\Users\<YourName>\AppData\Roaming\Praat\plugin_AudioTools\`

   * **macOS:**
     `~/Library/Application Support/Praat/plugin_AudioTools/`

   * **Linux:**
     `~/.config/praat/plugin_AudioTools/`

     If `XDG_CONFIG_HOME` is defined, use:
     `$XDG_CONFIG_HOME/praat/plugin_AudioTools/`

   ### Praat 6.x

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

   ⚠️ **Important:** The folder name must begin with `plugin_` and should remain exactly `plugin_AudioTools`. Do **not** place it inside an additional `plugins` directory.

4. **Restart Praat.**

   Praat automatically executes `setup.praat` when it starts. After restarting, you should see the **AudioTools** menus in the main Praat **Objects** window.
