#!/bin/bash

echo "🚀 Setting up DevBench Terminal Profiles"
echo ""

# Check what terminal applications are available
AVAILABLE_TERMINALS=""

if command -v gnome-terminal &> /dev/null; then
    AVAILABLE_TERMINALS+="gnome-terminal "
fi

if command -v konsole &> /dev/null; then
    AVAILABLE_TERMINALS+="konsole "
fi

if command -v tilix &> /dev/null; then
    AVAILABLE_TERMINALS+="tilix "
fi

if command -v alacritty &> /dev/null; then
    AVAILABLE_TERMINALS+="alacritty "
fi

echo "📟 Available terminals: $AVAILABLE_TERMINALS"
echo ""

# Create desktop entries for quick access
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

echo "🔧 Creating desktop entries..."

# DevJava Desktop Entry
cat > "$DESKTOP_DIR/devjava.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=DevJava
Comment=JavaBench Development Container
Exec=gnome-terminal --title="DevJava" -- /home/brett/projects/workBenches/devBenches/javaBench/scripts/launch-devbench.sh
Icon=applications-development
Terminal=false
Categories=Development;
StartupNotify=true
EOF

# DevDotNet Desktop Entry
cat > "$DESKTOP_DIR/devdotnet.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=DevDotNet
Comment=dotNetBench Development Container
Exec=gnome-terminal --title="DevDotNet" -- /home/brett/projects/workBenches/devBenches/dotNetBench/scripts/launch-devbench.sh
Icon=applications-development
Terminal=false
Categories=Development;
StartupNotify=true
EOF

# DevFlutter Desktop Entry
cat > "$DESKTOP_DIR/devflutter.desktop" << 'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=DevFlutter
Comment=FlutterBench Development Container
Exec=gnome-terminal --title="DevFlutter" -- /home/brett/projects/workBenches/devBenches/flutterBench/scripts/launch-devbench.sh
Icon=applications-development
Terminal=false
Categories=Development;
StartupNotify=true
EOF

chmod +x "$DESKTOP_DIR"/*.desktop

echo "✅ Desktop entries created:"
echo "   - DevJava (JavaBench)"
echo "   - DevDotNet (dotNetBench)" 
echo "   - DevFlutter (FlutterBench)"
echo ""

# Create shell aliases
SHELL_RC=""
if [[ "$SHELL" == *"zsh"* ]]; then
    SHELL_RC="$HOME/.zshrc"
elif [[ "$SHELL" == *"bash"* ]]; then
    SHELL_RC="$HOME/.bashrc"
fi

if [[ -n "$SHELL_RC" ]]; then
    echo "🐚 Adding shell aliases to $SHELL_RC..."
    
    # Remove existing DevBench aliases
    sed -i '/# DevBench Container Aliases/,/# End DevBench Aliases/d' "$SHELL_RC"
    
    # Add new aliases
    cat >> "$SHELL_RC" << 'EOF'

# DevBench Container Aliases
alias devjava='/home/brett/projects/workBenches/devBenches/javaBench/scripts/launch-devbench.sh'
alias devdotnet='/home/brett/projects/workBenches/devBenches/dotNetBench/scripts/launch-devbench.sh'
alias devflutter='/home/brett/projects/workBenches/devBenches/flutterBench/scripts/launch-devbench.sh'
alias devbench-status='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "(java_bench|dot_net_bench|flutter_bench)"'
alias devbench-stop='docker stop java_bench dot_net_bench flutter_bench 2>/dev/null || true'
# End DevBench Aliases
EOF
    
    echo "✅ Shell aliases added:"
    echo "   - devjava      (Launch JavaBench)"
    echo "   - devdotnet    (Launch dotNetBench)"
    echo "   - devflutter   (Launch FlutterBench)"
    echo "   - devbench-status (Check container status)"
    echo "   - devbench-stop   (Stop all containers)"
    echo ""
fi

# VS Code Tasks (if VS Code is installed)
if command -v code &> /dev/null; then
    VSCODE_TASKS_DIR="$HOME/.vscode"
    mkdir -p "$VSCODE_TASKS_DIR"
    
    echo "📝 Creating VS Code tasks..."
    cat > "$VSCODE_TASKS_DIR/tasks.json" << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "Launch DevJava",
            "type": "shell",
            "command": "/home/brett/projects/workBenches/devBenches/javaBench/scripts/launch-devbench.sh",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            }
        },
        {
            "label": "Launch DevDotNet", 
            "type": "shell",
            "command": "/home/brett/projects/workBenches/devBenches/dotNetBench/scripts/launch-devbench.sh",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            }
        },
        {
            "label": "Launch DevFlutter",
            "type": "shell", 
            "command": "/home/brett/projects/workBenches/devBenches/flutterBench/scripts/launch-devbench.sh",
            "group": "build",
            "presentation": {
                "echo": true,
                "reveal": "always",
                "focus": false,
                "panel": "new"
            }
        }
    ]
}
EOF
    echo "✅ VS Code tasks created (Ctrl+Shift+P → Tasks: Run Task)"
fi

echo ""
echo "🎯 How to use your new DevBench profiles:"
echo ""
echo "1. 🖱️  Desktop Applications:"
echo "   - Search for 'DevJava', 'DevDotNet', or 'DevFlutter' in your app launcher"
echo ""
echo "2. 🐚 Terminal Commands:"
echo "   - devjava      # Launch JavaBench"
echo "   - devdotnet    # Launch dotNetBench"  
echo "   - devflutter   # Launch FlutterBench"
echo ""
echo "3. 📝 VS Code Tasks:"
echo "   - Press Ctrl+Shift+P → 'Tasks: Run Task' → Select DevBench container"
echo ""
echo "4. 🔍 Management:"
echo "   - devbench-status  # Check which containers are running"
echo "   - devbench-stop    # Stop all DevBench containers"
echo ""
echo "🔄 To reload shell aliases: source $SHELL_RC"
echo ""
echo "🎉 Setup complete! Try: devjava"