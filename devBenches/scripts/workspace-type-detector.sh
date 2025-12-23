#!/bin/bash
# Workspace Type Detector - Heuristic analysis and interactive TUI
# Version: 1.0.0
# Manual fallback when no AI provider is available
# Shared across all bench types (frappe, flutter, dotnet)

# Prevent double-sourcing
if [ -n "$_WORKSPACE_TYPE_DETECTOR_SOURCED" ]; then
    return 0
fi
_WORKSPACE_TYPE_DETECTOR_SOURCED=1

# Confidence levels
readonly CONFIDENCE_HIGH="HIGH"
readonly CONFIDENCE_MEDIUM="MEDIUM"
readonly CONFIDENCE_LOW="LOW"
readonly CONFIDENCE_NONE="NONE"

# Colors
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_BOLD='\033[1m'
readonly COLOR_NC='\033[0m'

# ============================================================================
# Heuristic Detection Functions
# ============================================================================

# Detect Frappe workspace indicators
detect_frappe_indicators() {
    local search_dir="${1:-.}"
    local -a indicators=()
    local confidence="$CONFIDENCE_NONE"
    
    # Check for Frappe-specific files and directories
    [ -d "$search_dir/sites" ] && indicators+=("sites/")
    [ -d "$search_dir/apps" ] && indicators+=("apps/")
    [ -f "$search_dir/Procfile" ] && indicators+=("Procfile")
    [ -f "$search_dir/sites/apps.txt" ] && indicators+=("sites/apps.txt")
    [ -f "$search_dir/sites/common_site_config.json" ] && indicators+=("sites/common_site_config.json")
    [ -d "$search_dir/config" ] && indicators+=("config/")
    
    # Determine confidence level
    local count=${#indicators[@]}
    if [ $count -ge 4 ]; then
        confidence="$CONFIDENCE_HIGH"
    elif [ $count -ge 2 ]; then
        confidence="$CONFIDENCE_MEDIUM"
    elif [ $count -ge 1 ]; then
        confidence="$CONFIDENCE_LOW"
    fi
    
    # Output: confidence|indicator1,indicator2,...
    if [ ${#indicators[@]} -gt 0 ]; then
        echo "$confidence|$(IFS=','; echo "${indicators[*]}")"
    else
        echo "$CONFIDENCE_NONE|"
    fi
}

# Detect Flutter workspace indicators
detect_flutter_indicators() {
    local search_dir="${1:-.}"
    local -a indicators=()
    local confidence="$CONFIDENCE_NONE"
    
    # Check for Flutter-specific files and directories
    [ -f "$search_dir/pubspec.yaml" ] && indicators+=("pubspec.yaml")
    [ -d "$search_dir/lib" ] && indicators+=("lib/")
    [ -d "$search_dir/android" ] && indicators+=("android/")
    [ -d "$search_dir/ios" ] && indicators+=("ios/")
    [ -f "$search_dir/analysis_options.yaml" ] && indicators+=("analysis_options.yaml")
    [ -d "$search_dir/test" ] && indicators+=("test/")
    
    # Determine confidence level
    local count=${#indicators[@]}
    if [ $count -ge 4 ]; then
        confidence="$CONFIDENCE_HIGH"
    elif [ $count -ge 2 ]; then
        confidence="$CONFIDENCE_MEDIUM"
    elif [ $count -ge 1 ]; then
        confidence="$CONFIDENCE_LOW"
    fi
    
    # Output: confidence|indicator1,indicator2,...
    if [ ${#indicators[@]} -gt 0 ]; then
        echo "$confidence|$(IFS=','; echo "${indicators[*]}")"
    else
        echo "$CONFIDENCE_NONE|"
    fi
}

# Detect .NET workspace indicators
detect_dotnet_indicators() {
    local search_dir="${1:-.}"
    local -a indicators=()
    local confidence="$CONFIDENCE_NONE"
    
    # Check for .NET-specific files and directories
    [ -n "$(find "$search_dir" -maxdepth 2 -name "*.csproj" 2>/dev/null | head -1)" ] && indicators+=("*.csproj")
    [ -n "$(find "$search_dir" -maxdepth 2 -name "*.sln" 2>/dev/null | head -1)" ] && indicators+=("*.sln")
    [ -f "$search_dir/Program.cs" ] && indicators+=("Program.cs")
    [ -f "$search_dir/appsettings.json" ] && indicators+=("appsettings.json")
    [ -f "$search_dir/Startup.cs" ] && indicators+=("Startup.cs")
    [ -d "$search_dir/Properties" ] && indicators+=("Properties/")
    
    # Determine confidence level
    local count=${#indicators[@]}
    if [ $count -ge 3 ]; then
        confidence="$CONFIDENCE_HIGH"
    elif [ $count -ge 2 ]; then
        confidence="$CONFIDENCE_MEDIUM"
    elif [ $count -ge 1 ]; then
        confidence="$CONFIDENCE_LOW"
    fi
    
    # Output: confidence|indicator1,indicator2,...
    if [ ${#indicators[@]} -gt 0 ]; then
        echo "$confidence|$(IFS=','; echo "${indicators[*]}")"
    else
        echo "$CONFIDENCE_NONE|"
    fi
}

# Get all detections for a directory
get_all_detections() {
    local search_dir="${1:-.}"
    
    echo "frappe=$(detect_frappe_indicators "$search_dir")"
    echo "flutter=$(detect_flutter_indicators "$search_dir")"
    echo "dotnet=$(detect_dotnet_indicators "$search_dir")"
}

# Find workspace type with highest confidence
get_recommended_type() {
    local search_dir="${1:-.}"
    local best_type=""
    local best_confidence="$CONFIDENCE_NONE"
    
    # Parse detections
    local frappe_result=$(detect_frappe_indicators "$search_dir")
    local frappe_conf=$(echo "$frappe_result" | cut -d'|' -f1)
    
    local flutter_result=$(detect_flutter_indicators "$search_dir")
    local flutter_conf=$(echo "$flutter_result" | cut -d'|' -f1)
    
    local dotnet_result=$(detect_dotnet_indicators "$search_dir")
    local dotnet_conf=$(echo "$dotnet_result" | cut -d'|' -f1)
    
    # Find highest confidence (priority: HIGH > MEDIUM > LOW > NONE)
    if [ "$frappe_conf" = "$CONFIDENCE_HIGH" ]; then
        best_type="frappe"
        best_confidence="$CONFIDENCE_HIGH"
    elif [ "$flutter_conf" = "$CONFIDENCE_HIGH" ]; then
        best_type="flutter"
        best_confidence="$CONFIDENCE_HIGH"
    elif [ "$dotnet_conf" = "$CONFIDENCE_HIGH" ]; then
        best_type="dotnet"
        best_confidence="$CONFIDENCE_HIGH"
    elif [ "$frappe_conf" = "$CONFIDENCE_MEDIUM" ]; then
        best_type="frappe"
        best_confidence="$CONFIDENCE_MEDIUM"
    elif [ "$flutter_conf" = "$CONFIDENCE_MEDIUM" ]; then
        best_type="flutter"
        best_confidence="$CONFIDENCE_MEDIUM"
    elif [ "$dotnet_conf" = "$CONFIDENCE_MEDIUM" ]; then
        best_type="dotnet"
        best_confidence="$CONFIDENCE_MEDIUM"
    elif [ "$frappe_conf" = "$CONFIDENCE_LOW" ]; then
        best_type="frappe"
        best_confidence="$CONFIDENCE_LOW"
    elif [ "$flutter_conf" = "$CONFIDENCE_LOW" ]; then
        best_type="flutter"
        best_confidence="$CONFIDENCE_LOW"
    elif [ "$dotnet_conf" = "$CONFIDENCE_LOW" ]; then
        best_type="dotnet"
        best_confidence="$CONFIDENCE_LOW"
    fi
    
    if [ -n "$best_type" ]; then
        echo "$best_type|$best_confidence"
        return 0
    else
        echo "|$CONFIDENCE_NONE"
        return 1
    fi
}

# ============================================================================
# Interactive TUI
# ============================================================================

# Display workspace type selection TUI
show_workspace_selection_tui() {
    local search_dir="${1:-.}"
    
    echo ""
    echo -e "${COLOR_BLUE}=========================================="
    echo "Workspace Type Detection (Manual Mode)"
    echo -e "==========================================${COLOR_NC}"
    echo ""
    echo -e "Analyzed directory: ${COLOR_CYAN}$(cd "$search_dir" && pwd)${COLOR_NC}"
    echo ""
    
    # Get detections
    local frappe_result=$(detect_frappe_indicators "$search_dir")
    local frappe_conf=$(echo "$frappe_result" | cut -d'|' -f1)
    local frappe_indicators=$(echo "$frappe_result" | cut -d'|' -f2)
    
    local flutter_result=$(detect_flutter_indicators "$search_dir")
    local flutter_conf=$(echo "$flutter_result" | cut -d'|' -f1)
    local flutter_indicators=$(echo "$flutter_result" | cut -d'|' -f2)
    
    local dotnet_result=$(detect_dotnet_indicators "$search_dir")
    local dotnet_conf=$(echo "$dotnet_result" | cut -d'|' -f1)
    local dotnet_indicators=$(echo "$dotnet_result" | cut -d'|' -f2)
    
    # Get recommendation
    local recommended=$(get_recommended_type "$search_dir")
    local recommended_type=$(echo "$recommended" | cut -d'|' -f1)
    
    echo "Detected indicators:"
    echo ""
    
    # Format confidence with color
    format_confidence() {
        case "$1" in
            "$CONFIDENCE_HIGH")
                echo -e "${COLOR_GREEN}HIGH${COLOR_NC}"
                ;;
            "$CONFIDENCE_MEDIUM")
                echo -e "${COLOR_YELLOW}MEDIUM${COLOR_NC}"
                ;;
            "$CONFIDENCE_LOW")
                echo -e "${COLOR_YELLOW}LOW${COLOR_NC}"
                ;;
            "$CONFIDENCE_NONE")
                echo -e "${COLOR_RED}NONE${COLOR_NC}"
                ;;
        esac
    }
    
    # Display Frappe option
    local frappe_marker=""
    [ "$recommended_type" = "frappe" ] && frappe_marker="${COLOR_CYAN} ← Recommended${COLOR_NC}"
    echo -e "  ${COLOR_BOLD}1. Frappe${COLOR_NC}   [$(format_confidence "$frappe_conf") confidence]$frappe_marker"
    if [ -n "$frappe_indicators" ]; then
        echo -e "     ${COLOR_BLUE}Found:${COLOR_NC} $frappe_indicators"
    else
        echo -e "     ${COLOR_RED}Found: (none)${COLOR_NC}"
    fi
    echo ""
    
    # Display Flutter option
    local flutter_marker=""
    [ "$recommended_type" = "flutter" ] && flutter_marker="${COLOR_CYAN} ← Recommended${COLOR_NC}"
    echo -e "  ${COLOR_BOLD}2. Flutter${COLOR_NC}  [$(format_confidence "$flutter_conf") confidence]$flutter_marker"
    if [ -n "$flutter_indicators" ]; then
        echo -e "     ${COLOR_BLUE}Found:${COLOR_NC} $flutter_indicators"
    else
        echo -e "     ${COLOR_RED}Found: (none)${COLOR_NC}"
    fi
    echo ""
    
    # Display .NET option
    local dotnet_marker=""
    [ "$recommended_type" = "dotnet" ] && dotnet_marker="${COLOR_CYAN} ← Recommended${COLOR_NC}"
    echo -e "  ${COLOR_BOLD}3. .NET${COLOR_NC}     [$(format_confidence "$dotnet_conf") confidence]$dotnet_marker"
    if [ -n "$dotnet_indicators" ]; then
        echo -e "     ${COLOR_BLUE}Found:${COLOR_NC} $dotnet_indicators"
    else
        echo -e "     ${COLOR_RED}Found: (none)${COLOR_NC}"
    fi
    echo ""
    
    echo -e "${COLOR_BLUE}==========================================${COLOR_NC}"
    echo ""
    echo -ne "${COLOR_YELLOW}Select workspace type [1-3] (or 'q' to quit): ${COLOR_NC}"
    read -r choice
    
    case "$choice" in
        1)
            echo "frappe"
            return 0
            ;;
        2)
            echo "flutter"
            return 0
            ;;
        3)
            echo "dotnet"
            return 0
            ;;
        q|Q)
            echo ""
            echo -e "${COLOR_YELLOW}Operation cancelled${COLOR_NC}"
            return 1
            ;;
        *)
            echo ""
            echo -e "${COLOR_RED}Invalid selection${COLOR_NC}"
            return 1
            ;;
    esac
}

# Non-interactive detection (returns best guess or empty)
detect_workspace_type_auto() {
    local search_dir="${1:-.}"
    local recommended=$(get_recommended_type "$search_dir")
    local recommended_type=$(echo "$recommended" | cut -d'|' -f1)
    
    if [ -n "$recommended_type" ]; then
        echo "$recommended_type"
        return 0
    else
        return 1
    fi
}
