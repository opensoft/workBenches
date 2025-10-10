# Flutter DevContainer Networking Guide
## ADB Server Architecture with Docker Networks

---

## Table of Contents
1. [Port Usage Overview](#port-usage-overview)
2. [Binding vs Connecting](#binding-vs-connecting)
3. [Complete Architecture](#complete-architecture)
4. [Docker Network Configuration](#docker-network-configuration)
5. [Connection Strings](#connection-strings)
6. [Testing & Verification](#testing--verification)

---

## Port Usage Overview

### The Two Critical Ports

#### Port 5037: ADB Server Port
- **Used by**: ADB client ↔ ADB server communication
- **Who listens**: ADB server (in ADB container)
- **Who connects**: ADB clients (in Flutter dev containers)
- **Purpose**: Control channel for ADB commands

#### Port 5555: Emulator ADB Daemon Port
- **Used by**: ADB server ↔ Emulator communication  
- **Who listens**: adbd (ADB daemon in the emulator)
- **Who connects**: ADB server (in ADB container)
- **Purpose**: Actual communication with the Android device/emulator

### Communication Flow

```
Step 1: Flutter app runs "adb devices"
   Flutter Container → (port 5037) → ADB Container

Step 2: ADB server connects to emulator
   ADB Container → (port 5555) → Windows Emulator

Step 3: Response flows back
   Windows Emulator → (port 5555) → ADB Container → (port 5037) → Flutter Container
```

---

## Binding vs Connecting

### Key Concept: Only ONE Binds, MANY Connect

```
                    ┌─────────────────────┐
                    │   ADB Container     │
                    │                     │
                    │   Server BINDS to:  │
                    │   0.0.0.0:5037      │
                    │   (LISTENING)       │
                    └──────────▲──────────┘
                               │
                ┌──────────────┼──────────────┐
                │              │              │
                │              │              │
        ┌───────▼──────┐  ┌───▼────────┐  ┌──▼─────────┐
        │ Flutter 1    │  │ Flutter 2  │  │ Flutter 3  │
        │              │  │            │  │            │
        │ Client       │  │ Client     │  │ Client     │
        │ CONNECTS to  │  │ CONNECTS to│  │ CONNECTS to│
        │ adb-server:  │  │ adb-server:│  │ adb-server:│
        │ 5037         │  │ 5037       │  │ 5037       │
        └──────────────┘  └────────────┘  └────────────┘
```

### BIND (Listen)
- Creates a socket and listens for incoming connections
- **Only ONE process can bind to a port**
- The ADB server does this

### CONNECT
- Creates a socket and connects to a listening port
- **UNLIMITED processes can connect to the same port**
- All Flutter containers do this

### Restaurant Analogy
- **One host stand** at the entrance (ADB server binding to 5037)
- **Many customers** can approach the host stand (Flutter containers connecting to 5037)
- The host stand doesn't need multiple locations; it handles all customers

### What Causes Conflicts? ❌

```yaml
# BAD - Don't do this!
flutter-dev-1:
  ports:
    - "5037:5037"  # ❌ Trying to bind host port 5037

flutter-dev-2:
  ports:
    - "5037:5037"  # ❌ Conflict! Port already bound by dev-1
```

### What Works Perfectly ✅

```yaml
# GOOD - This works perfectly
adb-server:
  ports:
    - "5037:5037"  # ✅ ADB server binds to 5037

flutter-dev-1:
  environment:
    - ADB_SERVER_SOCKET=tcp:adb-server:5037  # ✅ Connects to 5037

flutter-dev-2:
  environment:
    - ADB_SERVER_SOCKET=tcp:adb-server:5037  # ✅ Also connects to 5037

flutter-dev-3:
  environment:
    - ADB_SERVER_SOCKET=tcp:adb-server:5037  # ✅ Also connects to 5037
```

---

## Complete Architecture

### Full System Diagram with Port Details

```
┌─────────────────────────────────────────────────────────┐
│                    Windows (Winland)                     │
│                                                          │
│  ┌──────────────────────────────┐                       │
│  │   Android Emulator           │                       │
│  │                              │                       │
│  │   adbd listening on:         │                       │
│  │   - localhost:5555 ◄─────────┼─────┐                │
│  │   (ADB daemon in emulator)   │     │                │
│  └──────────────────────────────┘     │                │
│                                        │                │
│  ┌─────────────────────────────────────┼──────────────┐ │
│  │              WSL2                   │              │ │
│  │                                     │              │ │
│  │  ┌──────────────────────────────────▼───────────┐ │ │
│  │  │    ADB Container                             │ │ │
│  │  │                                              │ │ │
│  │  │  ADB Server listening on:                   │ │ │
│  │  │  - 0.0.0.0:5037 ◄──────────┐                │ │ │
│  │  │    (for client connections)│                │ │ │
│  │  │                             │                │ │ │
│  │  │  Connects to emulator on:   │                │ │ │
│  │  │  - host.docker.internal:5555┘                │ │ │
│  │  └──────────────────────────────────────────────┘ │ │
│  │                    ▲                              │ │
│  │                    │                              │ │
│  │                    │ Port 5037                    │ │
│  │                    │                              │ │
│  │  ┌─────────────────┴────────────────┐            │ │
│  │  │  Flutter Dev 1                   │            │ │
│  │  │                                  │            │ │
│  │  │  ADB Client connects to:         │            │ │
│  │  │  - adb-server:5037               │            │ │
│  │  └──────────────────────────────────┘            │ │
│  │                                                   │ │
│  │  ┌──────────────────────────────────┐            │ │
│  │  │  Flutter Dev 2                   │            │ │
│  │  │                                  │            │ │
│  │  │  ADB Client connects to:         │            │ │
│  │  │  - adb-server:5037               │            │ │
│  │  └──────────────────────────────────┘            │ │
│  │                                                   │ │
│  └───────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────┘
```

### Connection Hierarchy

```
ADB Server (port 5037)
    │
    ├─── Connection 1 (Flutter Dev 1)
    ├─── Connection 2 (Flutter Dev 2)
    ├─── Connection 3 (Flutter Dev 3)
    ├─── Connection 4 (FlutterBench)
    └─── Connection 5 (any other container)

All connected simultaneously, no conflicts!
```

### Multiple Emulators

If you have multiple emulators running, they use different ports:

```
Emulator 1: localhost:5554 (console) / 5555 (adb)
Emulator 2: localhost:5556 (console) / 5557 (adb)
Emulator 3: localhost:5558 (console) / 5559 (adb)
```

Connect from ADB container:
```bash
adb connect host.docker.internal:5555  # First emulator
adb connect host.docker.internal:5557  # Second emulator
adb connect host.docker.internal:5559  # Third emulator
```

---

## Docker Network Configuration

### The dartnet Network

When all containers are on the same Docker network named **dartnet**, they can communicate using service names.

### Connection String Format

```
tcp:<service-name>:5037
```

or 

```
tcp:<container-name>:5037
```

**Important**: The network name (`dartnet`) is **NOT** in the connection string - it just defines which containers can see each other.

### docker-compose.yml with dartnet

```yaml
version: '3.8'

services:
  adb-server:
    build: ./adb-container
    container_name: shared-adb-server
    ports:
      - "5037:5037"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    networks:
      - dartnet  # ← On dartnet network
    command:
      - |
        adb -a -P 5037 nodaemon server &
        sleep 2
        adb connect host.docker.internal:5555
        wait

  flutter-dev-1:
    build: ./flutter-devcontainer
    container_name: flutter-dev-1
    environment:
      # Connect using SERVICE NAME
      - ADB_SERVER_SOCKET=tcp:adb-server:5037
    networks:
      - dartnet  # ← On dartnet network
    depends_on:
      - adb-server

  flutter-dev-2:
    build: ./flutter-devcontainer
    container_name: flutter-dev-2
    environment:
      # Can also use CONTAINER NAME
      - ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
    networks:
      - dartnet  # ← On dartnet network
    depends_on:
      - adb-server

  flutter-dev-3:
    build: ./flutter-devcontainer
    container_name: flutter-dev-3
    environment:
      # Service name is preferred (more portable)
      - ADB_SERVER_SOCKET=tcp:adb-server:5037
    networks:
      - dartnet  # ← On dartnet network
    depends_on:
      - adb-server

  flutterbench:
    build: ./flutterbench-container
    container_name: flutterbench
    networks:
      - dartnet  # ← On dartnet network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./flutter-devcontainer:/workbench/flutter-devcontainer
    environment:
      - ADB_SERVER_SOCKET=tcp:adb-server:5037
    depends_on:
      - adb-server

networks:
  dartnet:  # ← Define the network
    driver: bridge
```

### How Docker DNS Works on dartnet

```
Container: flutter-dev-1
    ↓ (DNS lookup: "adb-server")
Docker DNS on dartnet
    ↓ (resolves to container IP)
Container: shared-adb-server
```

Docker's internal DNS automatically resolves:
- `adb-server` → IP of the adb-server container
- `flutter-dev-1` → IP of flutter-dev-1 container
- `shared-adb-server` → IP of the adb-server container (by container name)

### dartnet Network Map with IPs

```
dartnet (Docker Bridge Network)
│
├── adb-server (172.18.0.2) ← Binds to 0.0.0.0:5037
│
├── flutter-dev-1 (172.18.0.3) ← Connects to adb-server:5037
│
├── flutter-dev-2 (172.18.0.4) ← Connects to adb-server:5037
│
├── flutter-dev-3 (172.18.0.5) ← Connects to adb-server:5037
│
└── flutterbench (172.18.0.6) ← Connects to adb-server:5037
```

---

## Connection Strings

### Option 1: Using Service Name ✅ (Recommended)
```bash
tcp:adb-server:5037
```
- ✅ Works even if container name changes
- ✅ More portable across environments
- ✅ Standard Docker Compose pattern

### Option 2: Using Container Name
```bash
tcp:shared-adb-server:5037
```
- ✅ Works if you know the exact container name
- ⚠️ Breaks if you rename the container

### Option 3: Using IP Address ❌ (Not Recommended)
```bash
tcp:172.18.0.2:5037
```
- ❌ IP addresses change
- ❌ Fragile and breaks easily
- ❌ Don't use this

### Setting in Environment

In your Flutter dev containers, set it once:

**In Dockerfile:**
```dockerfile
ENV ADB_SERVER_SOCKET=tcp:adb-server:5037
```

**Or in docker-compose.yml:**
```yaml
environment:
  - ADB_SERVER_SOCKET=tcp:adb-server:5037
```

Then ADB "just works" without any manual configuration!

---

## Testing & Verification

### Test Connectivity on dartnet

```bash
# From flutter-dev-1, test connection to ADB server
docker exec flutter-dev-1 ping adb-server
# PING adb-server (172.18.0.2): 56 data bytes
# 64 bytes from 172.18.0.2: icmp_seq=0 ttl=64 time=0.123 ms

# Test ADB connection
docker exec flutter-dev-1 sh -c 'export ADB_SERVER_SOCKET=tcp:adb-server:5037 && adb devices'
# List of devices attached
# host.docker.internal:5555  device

# Check all containers on dartnet
docker network inspect dartnet
```

### Verify All Containers Use Same ADB Server

```bash
# From Flutter Dev 1
docker exec flutter-dev-1 adb devices
# List of devices attached
# host.docker.internal:5555  device

# From Flutter Dev 2
docker exec flutter-dev-2 adb devices
# List of devices attached
# host.docker.internal:5555  device  ← Same device!

# From Flutter Dev 3
docker exec flutter-dev-3 adb devices
# List of devices attached
# host.docker.internal:5555  device  ← Same device!
```

All three containers see the same emulator because they're all clients of the same ADB server.

### From Inside a Container

```bash
# SSH into flutter-dev-1
docker exec -it flutter-dev-1 bash

# Set ADB server location
export ADB_SERVER_SOCKET=tcp:adb-server:5037

# Use ADB (connects to adb-server:5037)
adb devices

# You can also use the container name
export ADB_SERVER_SOCKET=tcp:shared-adb-server:5037
adb devices

# Test DNS resolution
nslookup adb-server
# Output shows it resolves to container IP
```

### Debug Network Issues

```bash
# Inspect dartnet network
docker network inspect dartnet

# Check which containers are connected
docker network inspect dartnet --format='{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'

# Test connectivity between containers
docker exec flutter-dev-1 ping flutter-dev-2
docker exec flutter-dev-1 nc -zv adb-server 5037
```

---

## Summary

### Port Usage
- **Port 5037**: Flutter containers talk to ADB server (client → server)
- **Port 5555**: ADB server talks to emulator (server → emulator)

### Network Architecture
- **Network name** (`dartnet`): Defines which containers can talk to each other
- **Service name** (`adb-server`): How to reach a specific container
- **Port** (`5037`): Which service on that container

### Connection Flow
```
Flutter App → (5037) → ADB Server → (5555) → Emulator
```

### Key Takeaways
✅ All Flutter containers can use the same ADB server on port 5037  
✅ No binding conflicts - only the ADB container binds the port  
✅ Multiple clients connecting is the intended design  
✅ Use service names (`adb-server:5037`) for portable connections  
✅ Docker DNS handles name resolution on dartnet automatically

---

## Quick Reference

### Connection String
```bash
tcp:adb-server:5037
```

### Test Command
```bash
docker exec flutter-dev-1 adb devices
```

### docker-compose Port Mapping
```yaml
adb-server:
  ports:
    - "5037:5037"  # Only ADB server binds this port

flutter-dev-1:
  environment:
    - ADB_SERVER_SOCKET=tcp:adb-server:5037  # Connects, doesn't bind
```

### Multiple Emulators
```bash
adb connect host.docker.internal:5555  # Emulator 1
adb connect host.docker.internal:5557  # Emulator 2
adb connect host.docker.internal:5559  # Emulator 3
```

---

*This architecture allows all your Flutter development containers to share a single ADB server, which communicates with emulators running in Windows - providing a clean, scalable development environment.*
