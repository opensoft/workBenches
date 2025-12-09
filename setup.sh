#!/bin/bash

# Setup script for workBenches
# This script launches the interactive configuration manager

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the interactive setup script
"${SCRIPT_DIR}/scripts/interactive-setup.sh"
