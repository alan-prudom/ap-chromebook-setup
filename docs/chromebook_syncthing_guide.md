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

## 4. Alternative: Syncthing-Fork (Android)

* **Where to get**: Google Play Store or F-Droid via ChromeOS's Android container.
* **Pros**: Runs in the Android subsystem, which can stay alive independently of Crostini.
* **Cons**: Limited by Android scoped storage permissions, lacks full Linux filesystem ownership/permissions parity, and can have higher I/O overhead.
