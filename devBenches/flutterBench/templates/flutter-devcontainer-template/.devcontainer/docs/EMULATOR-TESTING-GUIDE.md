# Flutter Emulator Testing & Debugging Guide
## Using VS Code Tasks for Development Workflow

---

## 🎯 Quick Start (TL;DR)

1. **Start containers**: Run VS Code task **"ADB Service: Check Status"** (or `docker-compose up -d`)
2. **Launch emulator**: Run VS Code task **"Launch Android Emulator"** 
3. **Verify connection**: Run VS Code task **"Emulator: Check ADB Connection"**
4. **Start debugging**: Press `F5` or run **"Flutter: Run Tests"** task

---

## 📋 Complete Testing & Debugging Workflow

### Step 1: Container Setup & Verification

#### 1.1 Start Development Environment
- **Task**: `Ctrl+Shift+P` → **"ADB Service: Check Status"**
- **Purpose**: Verify ADB service is running and ready
- **Expected output**: 
  ```
  ✅ ADB service container is running
  ✅ ADB service is reachable on port 5037
  ```

If ADB service is not running:
- **Task**: **"ADB Service: Start/Restart"**
- Wait 5-10 seconds for startup

#### 1.2 Verify Flutter Environment  
- **Task**: **"Flutter: Get Dependencies"**
- **Purpose**: Ensure all packages are installed
- **When to use**: After git pull or when pubspec.yaml changes

---

### Step 2: Emulator Management

#### 2.1 Launch Android Emulator (Preferred Method)
- **Task**: **"Launch Android Emulator"**
- **What happens**: 
  - Runs on Windows host (outside container)
  - Automatically selects from available AVDs
  - Emulator opens in new window

#### 2.2 Alternative: Manual Emulator Start
- **Task**: **"Emulator: Show Start Instructions"** 
- **Purpose**: Shows manual commands if automatic launch fails
- **Follow instructions**: Copy/paste commands to Windows terminal

#### 2.3 Verify Emulator Connection
- **Task**: **"Emulator: Check ADB Connection"**
- **Expected output**:
  ```
  ✅ ADB service container is running
  ✅ ADB service is reachable on port 5037
  🚀 Ready to deploy!
  ```

#### 2.4 List Connected Devices
- **Task**: **"Emulator: Show Connected Devices"**
- **Purpose**: Confirm emulator is detected by Flutter
- **Expected output**:
  ```
  List of devices attached
  emulator-5554    device
  ```

---

### Step 3: App Development & Testing

#### 3.1 Run Unit/Widget Tests
- **Task**: **"Flutter: Run Tests"**
- **Purpose**: Execute all tests without needing emulator
- **Use case**: Quick validation of business logic

#### 3.2 Debug on Emulator (Primary Method)
- **Method 1**: Press `F5` (Start Debugging)
- **Method 2**: `Ctrl+Shift+P` → **"Flutter: Launch App"**
- **What happens**:
  - Builds and installs app on emulator
  - Starts in debug mode with hot reload
  - VS Code debugger attaches automatically

#### 3.3 Release Build Testing
- **Task**: **"Flutter: Build APK"**
- **Purpose**: Test production-like build
- **Follow up**: Install APK manually on emulator

#### 3.4 Code Quality Checks
- **Task**: **"Dart: Analyze"** - Check for code issues
- **Task**: **"Dart: Format Code"** - Auto-format codebase

---

### Step 4: Troubleshooting & Maintenance

#### 4.1 Connection Issues
If `flutter run` fails with "No devices found":

1. **Task**: **"ADB Service: Check Status"**
2. If service is down: **"ADB Service: Start/Restart"**
3. **Task**: **"Emulator: Check ADB Connection"**
4. **Task**: **"Android: Verify Emulator Connection"**

#### 4.2 ADB Service Issues
**Task**: **"ADB Service: View Logs"**
- **Purpose**: See real-time ADB service logs
- **Look for**:
  ```
  ✅ Emulator connected successfully!
  ```
- **If you see**: Connection failures → Check if emulator is running

#### 4.3 Clean Build Issues
If app behaves strangely:
1. **Task**: **"Flutter: Clean"**
2. **Task**: **"Flutter: Get Dependencies"**
3. Restart debugging with `F5`

#### 4.4 Restart Everything
For major issues:
1. **Task**: **"ADB Service: Stop"**
2. Close emulator on Windows
3. **Task**: **"ADB Service: Start/Restart"**  
4. **Task**: **"Launch Android Emulator"**
5. Wait 30 seconds for auto-connection

---

## 🚀 Advanced Debugging Workflows

### Hot Reload Development
1. Start debugging with `F5`
2. Make code changes
3. Save file (`Ctrl+S`) → Hot reload triggers automatically
4. Changes appear instantly in emulator

### Widget Inspector Debugging
1. Start app in debug mode (`F5`)
2. `Ctrl+Shift+P` → **"Flutter: Open Widget Inspector"**
3. Click widgets in emulator to inspect in VS Code

### Performance Profiling
1. Start app in profile mode: `Ctrl+Shift+P` → **"Flutter: Launch App in Profile Mode"**
2. `Ctrl+Shift+P` → **"Flutter: Open Performance View"**

---

## 📱 Multi-Emulator Testing

### Running Multiple Emulators
1. **First emulator**: Use **"Launch Android Emulator"** task
2. **Second emulator**: Manually start with different AVD:
   ```bash
   # On Windows
   %LOCALAPPDATA%\Android\Sdk\emulator\emulator.exe -avd Pixel_6_API_33
   ```
3. **Task**: **"Emulator: Show Connected Devices"** - Should show both
4. Select target in VS Code Flutter device selector

### Device-Specific Testing
- **Phone emulator**: Test responsive design
- **Tablet emulator**: Test layout adaptability  
- **Different Android versions**: Test API compatibility

---

## 🔍 Common Task Combinations

### Daily Development Start
```
1. "ADB Service: Check Status"
2. "Launch Android Emulator"  
3. "Flutter: Get Dependencies"
4. Press F5 (Start Debugging)
```

### Bug Investigation
```
1. "Flutter: Run Tests"
2. "Dart: Analyze"
3. "ADB Service: View Logs"
4. "Emulator: Check ADB Connection"
```

### Release Preparation
```
1. "Dart: Format Code"
2. "Dart: Analyze"  
3. "Flutter: Run Tests"
4. "Flutter: Build APK"
```

### Connection Troubleshooting
```
1. "ADB Service: View Logs"
2. "Emulator: Check ADB Connection"
3. "ADB Service: Start/Restart"
4. "Android: Verify Emulator Connection"
```

---

## ⚡ Keyboard Shortcuts

| Action | Shortcut | Task Equivalent |
|--------|----------|-----------------|
| Start Debugging | `F5` | Launch app in debug mode |
| Run Without Debugging | `Ctrl+F5` | Launch app in release mode |
| Hot Reload | `Ctrl+S` | Auto-triggers on save |
| Hot Restart | `Ctrl+Shift+F5` | Full app restart |
| Open Command Palette | `Ctrl+Shift+P` | Access all tasks |
| Run Task | `Ctrl+Shift+P` → "Run Task" | Browse all tasks |

---

## 📊 Task Categories Overview

### 🔧 **Development Tasks**
- **Flutter: Get Dependencies** - Install packages
- **Flutter: Clean** - Clean build cache  
- **Flutter: Run Tests** - Execute unit tests
- **Flutter: Build APK** - Create release build

### 🔍 **Code Quality Tasks** 
- **Dart: Analyze** - Check code issues
- **Dart: Format Code** - Auto-format code

### 📱 **Emulator Tasks**
- **Launch Android Emulator** - Start emulator on Windows
- **Emulator: Show Start Instructions** - Manual start guide
- **Emulator: Check ADB Connection** - Verify connection
- **Emulator: Show Connected Devices** - List devices

### 🛠️ **ADB Service Tasks**
- **ADB Service: Check Status** - Service health check
- **ADB Service: Start/Restart** - Control service
- **ADB Service: View Logs** - Debug connection issues
- **ADB Service: Stop** - Stop service

### 🔌 **Verification Tasks**
- **Android: Verify Emulator Connection** - Use Flutter to check
- **Android: Show All Connected Devices** - Detailed device info

---

## 💡 Pro Tips

1. **Use task dependencies**: Start with "ADB Service: Check Status" before emulator tasks
2. **Keep logs open**: Run "ADB Service: View Logs" in background during development  
3. **Quick device check**: "Android: Verify Emulator Connection" uses Flutter's detection
4. **Multiple projects**: ADB service is shared - no need to restart between projects
5. **Auto-save**: Enable auto-save for instant hot reload on changes

---

## 🎯 Success Indicators

### ✅ Everything Working
- ADB service status shows green checkmarks
- Emulator appears in device list
- `flutter run` or `F5` launches app successfully
- Hot reload works on file save

### ❌ Common Issues & Solutions
- **No devices found**: Run "Emulator: Check ADB Connection"
- **Connection refused**: Run "ADB Service: Start/Restart"  
- **App won't install**: Run "Flutter: Clean" then retry
- **Slow performance**: Check if using debug mode (normal for development)

---

*This architecture makes Flutter development seamless - the ADB service handles all connection complexity automatically!*