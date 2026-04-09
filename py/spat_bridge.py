import sys
import os
import subprocess

def run_cmd(cmd, log_file, env):
    """Runs a command and appends output to the log file, using a custom environment."""
    with open(log_file, "a") as f:
        f.write(f"\nRunning: {' '.join(cmd)}\n")
        # Pass the modified environment variables here
        result = subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, env=env)
        if result.returncode != 0:
            f.write(f"\nFAILED with exit code {result.returncode}\n")
            sys.exit(1)

def main():
    if len(sys.argv) < 13:
        print("Error: Missing arguments")
        sys.exit(1)

    # Map arguments (sys.argv[0] is the script name)
    in_wav     = sys.argv[1]
    hoa_wav    = sys.argv[2]
    spk_wav    = sys.argv[3]
    out_wav    = sys.argv[4]
    log_file   = sys.argv[5]
    tools_dir  = sys.argv[6]
    enc_preset = sys.argv[7]
    dec_preset = sys.argv[8]
    layout     = sys.argv[9]
    sofa       = sys.argv[10]
    itd        = sys.argv[11]
    room       = sys.argv[12]

    # --- THE FIX: Add the Spat5 support folder to the system PATH ---
    tools_path = os.path.abspath(tools_dir)
    spat_pkg_path = os.path.dirname(os.path.dirname(tools_path))
    support_path = os.path.join(spat_pkg_path, "support")

    # Copy current environment and prepend the support path
    custom_env = os.environ.copy()
    if sys.platform == "win32":
        custom_env["PATH"] = support_path + os.pathsep + custom_env.get("PATH", "")

    # Detect OS to append .exe only on Windows
    ext = ".exe" if sys.platform == "win32" else ""

    # Construct absolute paths to the Spat5 executables
    encoder         = os.path.join(tools_dir, f"spat5.hoa.encoder~{ext}")
    decoder         = os.path.join(tools_dir, f"spat5.hoa.decoder~{ext}")
    virtualspeakers = os.path.join(tools_dir, f"spat5.virtualspeakers~{ext}")

    # Clear previous log
    with open(log_file, "w") as f:
        f.write("Starting Python Spat5 Bridge...\n")
        f.write(f"Injected into PATH: {support_path}\n")

    # STAGE 1: Encode (FIXED: changed -m to -p)
    run_cmd([encoder, "-i", in_wav, "-o", hoa_wav, "-p", enc_preset], log_file, custom_env)

    # STAGE 2: Decode (FIXED: changed -m to -p)
    run_cmd([decoder, "-i", hoa_wav, "-o", spk_wav, "-p", dec_preset], log_file, custom_env)

    # STAGE 3: Virtual Speakers (Binaural)
    run_cmd([virtualspeakers, "-i", spk_wav, "-f", layout, "-o", out_wav, "-s", sofa, "-I", itd, "-R", room], log_file, custom_env)

if __name__ == "__main__":
    main()