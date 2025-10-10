# Android Emulator Control from VS Code Container

This setup allows you to control Android emulators on your Windows host machine directly from VS Code running in a dev container.

## Automatic Setup (Post Container Build)

After rebuilding your dev container, the following should work automatically:

1. **ADB Server Connection**: Environment variable `ADB_SERVER_SOCKET=tcp:host.docker.internal:5037` is set
2. **ADB Symlinks**: System ADB is symlinked to expected Flutter locations  
3. **Flutter Integration**: Flutter should detect emulators running on your Windows host

### Quick Verification

Run this command to verify everything is working:
```bash
/workspace/.devcontainer/verify-emulator-connection.sh
```

Or use the VS Code task: **"Android: Verify Emulator Connection"**

## Setup Options

### Option 1: Automated Control (Recommended)

This method uses a PowerShell server on your host to receive commands from the container.

#### Setup Steps:

1. **On your Windows host machine:**
   - Copy the file `/workspace/.devcontainer/emulator-server.ps1` to your Windows desktop
   - Open PowerShell as Administrator
   - Navigate to where you saved the file
   - Run: `.\emulator-server.ps1 -Action server`
   - Leave this PowerShell window open (it will listen for commands)

2. **In VS Code (container):**
   - Press `Ctrl+Shift+P`
   - Type "Tasks: Run Task"
   - Choose from available emulator tasks:
     - **Emulator: List AVDs (via Server)** - Shows available emulators
     - **Emulator: Start AVD (via Server)** - Starts a specific emulator
     - **Emulator: Stop All (via Server)** - Stops all emulators
     - **Emulator: Connect to Host Emulator** - Connects ADB to running emulator

#### Usage Workflow:
```bash
# List available AVDs
./workspace/.devcontainer/emulator-helper.sh list

# Start specific AVD
./workspace/.devcontainer/emulator-helper.sh start Pixel_7_API_34

# Check connection status  
./workspace/.devcontainer/emulator-helper.sh status

# Connect to running emulator
./workspace/.devcontainer/emulator-helper.sh connect
```

### Option 2: Manual Control

If the automated method doesn't work, use this simpler approach:

#### Setup Steps:

1. **Start emulator on Windows host:**
   - Open Command Prompt or PowerShell
   - Run: `cd "C:\Users\Brett\AppData\Local\Android\Sdk\emulator"`
   - Run: `emulator.exe -list-avds` (to see available AVDs)
   - Run: `emulator.exe -avd <AVD_NAME>` (replace with actual AVD name)

2. **Connect from container:**
   - In VS Code, run task: **Emulator: Connect to Host Emulator**
   - Or run: `./workspace/.devcontainer/emulator-helper.sh connect`

## Available VS Code Tasks

Access these via `Ctrl+Shift+P` → "Tasks: Run Task":

- **Emulator: Show Start Instructions** - Shows manual setup instructions
- **Emulator: Connect to Host Emulator** - Connects ADB to host emulator  
- **Emulator: Check Status** - Shows connected devices
- **Emulator: Disconnect** - Disconnects from all emulators
- **Emulator: List AVDs (via Server)** - Lists AVDs using PowerShell server
- **Emulator: Start AVD (via Server)** - Starts emulator using PowerShell server
- **Emulator: Stop All (via Server)** - Stops emulators using PowerShell server

## Troubleshooting

### Emulator not detected by VS Code extension:

1. Ensure emulator is running on host
2. Run the "Connect to Host Emulator" task
3. Check that `adb devices` shows the emulator

### PowerShell server not working:

1. Make sure PowerShell is running as Administrator
2. Check Windows Firewall isn't blocking port 8888
3. Verify the container can reach `host.docker.internal:8888`

### ADB connection issues:

1. Check that port forwarding is working: `5555`, `5554`, `5037`
2. Try manual ADB connection: `adb connect host.docker.internal:5555`
3. Restart ADB server: `adb kill-server && adb start-server`

## Common AVD Names

If you need to create AVDs, these are common names:
- `Pixel_7_API_34`
- `Pixel_4_API_30`  
- `Nexus_5X_API_29`
- `Medium_Phone_API_33`

Create AVDs using Android Studio's AVD Manager on your host machine.

## Development Workflow

1. Start emulator (using tasks or manually)
2. Connect ADB (using "Connect to Host Emulator" task)
3. Run your Flutter app: `flutter run`
4. The app should deploy to the emulator

Your Flutter development environment is now ready!