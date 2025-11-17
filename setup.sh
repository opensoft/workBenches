#!/bin/bash

# Setup script for workBenches
# This script calls the main setup script located in the scripts directory

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Call the main setup script
"${SCRIPT_DIR}/scripts/setup-workbenches"