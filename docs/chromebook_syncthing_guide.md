# Running Syncthing on a Chromebook (via Crostini)

Yes, running Syncthing on ChromeOS using the **Crostini Linux development environment** is fully supported, robust, and avoids Android-specific storage and background-process constraints.

---

## 1. Quick Setup in Crostini

### Step 1: Install Syncthing
Inside your ChromeOS Linux Terminal:

```bash
sudo apt update
sudo apt install syncthing
```

*(Note: For the absolute latest release rather than the Debian stable package, the upstream Syncthing apt repository can be configured instead).*

### Step 2: Enable & Start Syncthing Service
Run Syncthing under your user's systemd session so it launches automatically:

```bash
systemctl --user enable --now syncthing
```

Check status anytime with:
```bash
systemctl --user status syncthing
```

### Step 3: Access the Web GUI
Open Chrome in ChromeOS and visit:
```text
http://localhost:8384
```
ChromeOS automatically maps and forwards `localhost` ports from the Crostini container directly to the browser.

---

## 2. Syncing Native ChromeOS Directories

By default, Crostini has access to its own isolated file system (`/home/<username>/`). To share files between native ChromeOS (Downloads, SD Cards, Google Drive) and Syncthing:

1. Open the ChromeOS **Files** application.
2. Right-click on a target folder (for example, **Downloads** or a specific subfolder).
3. Select **"Share with Linux"**.
4. In Crostini, the folder will be mounted at:
   ```text
   /mnt/chromeos/MyFiles/Downloads
   ```
   *(Removable media/SD cards will typically appear under `/mnt/chromeos/removable/<label>` if shared).*
5. When adding or accepting a folder in the Syncthing Web UI (`http://localhost:8384`), set the folder path to the `/mnt/chromeos/...` path.

---

## 3. Container Lifecycle & Background Syncing

* **Container Sleep**: When all Crostini terminal windows and Linux applications are closed, ChromeOS suspends/shuts down the container after a short idle timeout to conserve battery.
* **Continuous Syncing**: To ensure Syncthing continues running and syncing in the background:
  * Leave a terminal window open or keep a lightweight background terminal/app running in ChromeOS.
  * Alternatively, prevent ChromeOS from sleeping or closing the Linux VM when on AC power if unattended syncing is needed.

---

## 4. Checking Syncthing Status from the Command Line

You can check Syncthing's status directly from the Crostini command line. Depending on whether you want to verify if the background service is running or inspect your live sync metrics, use the methods below:

### 4.1 Check if the Background Service is Running
If you started Syncthing as a systemd background service, query its runtime state and recent log history:
```bash
systemctl --user status syncthing
```
* **What to look for**: Look for a green `active (running)` indicator. If it failed, this command prints out the error logs explaining why.

### 4.2 Use the Built-In Syncthing CLI
Modern versions of Syncthing include an embedded command-line interface tool:

* **Quick System Summary**:
  Fetch a JSON summary of your system uptime, resource usage, and connection status:
  ```bash
  syncthing cli show system
  ```

* **Comprehensive Device and Folder Data Dump**:
  View a comprehensive layout of your actively connected devices, shared folders, and data percentages:
  ```bash
  syncthing cli config dump-json
  ```
  *(Tip: If you have `jq` installed, pipe the output into it via `syncthing cli config dump-json | jq` for a highly readable, color-coded structure).*

* **Authentication / API Key Note**:
  If the built-in CLI commands return an API key or authentication error, locate your API key inside `~/.local/state/syncthing/config.xml` (or `~/.config/syncthing/config.xml`):
  ```bash
  grep "<apikey>" ~/.local/state/syncthing/config.xml
  ```

### 4.3 Quick Network "Ping" Test
To perform a quick, definitive "Yes/No" check to confirm that the Syncthing engine is actively responding on its local port, send an API request using `curl`:
```bash
curl -s http://127.0.0.1:8384/rest/system/ping
```
* **Expected Output**: If the process is alive, the terminal returns `{"ping":"pong"}`. If it returns a connection error, Syncthing is entirely stopped or bound to a different port.

---

## 5. Alternative: Syncthing-Fork (Android)

* **Where to get**: Google Play Store or F-Droid via ChromeOS's Android container.
* **Pros**: Runs in the Android subsystem, which can stay alive independently of Crostini.
* **Cons**: Limited by Android scoped storage permissions, lacks full Linux filesystem ownership/permissions parity, and can have higher I/O overhead.

---

## 6. References & External Links

* [Google AI Shared Thread](https://share.google/aimode/cb3HUJ1x2xGAZvZoT)
* [Syncthing Documentation: CLI Command Reference](https://docs.syncthing.net/v1.27.4/users/syncthing.html)
* [Syncthing Forum: Command to check the status of Syncthing](https://forum.syncthing.net/t/command-to-check-the-status-of-syncthing/5266)
* [Syncthing Forum: How to programmatically set up Syncthing via built-in CLI](https://forum.syncthing.net/t/howto-programatically-set-up-syncthing-via-the-bulit-in-cli-command/23682/4)
* [Syncthing Forum: Service visibility & device troubleshooting](https://forum.syncthing.net/t/syncthing-running-on-linux-mint-visible-twice-for-other-devices-device-id-changes-on-reboot/19570)
