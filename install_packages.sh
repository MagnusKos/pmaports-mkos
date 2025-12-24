#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CUSTOM_PMAPORTS_DIR="$SCRIPT_DIR"
CONFIG_FILE="$SCRIPT_DIR/.config.yml"
DEST_PMAPORTS_DIR=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to load config
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        DEST_PMAPORTS_DIR=$(grep "^dest_pmaports_dir:" "$CONFIG_FILE" | cut -d' ' -f2-)
        if [[ -z "$DEST_PMAPORTS_DIR" ]]; then
            return 1
        fi
        return 0
    fi
    return 1
}

# Function to save config
save_config() {
    echo "dest_pmaports_dir: $DEST_PMAPORTS_DIR" > "$CONFIG_FILE"
    echo -e "${GREEN}✓ Configuration saved to $CONFIG_FILE${NC}"
}

# Function to prompt for directory
prompt_for_directory() {
    while true; do
        read -p "Enter the path to destination pmaports directory: " input_dir
        
        # Expand ~ to home directory
        input_dir="${input_dir/#\~/$HOME}"
        
        if [[ ! -d "$input_dir" ]]; then
            echo -e "${RED}✗ Directory does not exist: $input_dir${NC}"
            continue
        fi
        
        if [[ ! -d "$input_dir/device/testing" ]]; then
            echo -e "${RED}✗ device/testing directory not found in $input_dir${NC}"
            continue
        fi
        
        DEST_PMAPORTS_DIR="$input_dir"
        return 0
    done
}

# Function to get all package directories in custom-pmaports
get_custom_packages() {
    local packages=()
    
    if [[ ! -d "$CUSTOM_PMAPORTS_DIR" ]]; then
        echo -e "${RED}✗ custom-pmaports directory not found: $CUSTOM_PMAPORTS_DIR${NC}"
        return 1
    fi
    
    # Find all directories matching patterns: device-*, linux-*, firmware-*
    for package_dir in "$CUSTOM_PMAPORTS_DIR"/{device,linux,firmware}-*/; do
        if [[ -d "$package_dir" ]]; then
            local package_name=$(basename "$package_dir")
            packages+=("$package_name")
        fi
    done
    
    if [[ ${#packages[@]} -eq 0 ]]; then
        echo -e "${RED}✗ No package directories found in $CUSTOM_PMAPORTS_DIR${NC}"
        echo -e "${YELLOW}Expected directories matching: device-*, linux-*, firmware-*${NC}"
        return 1
    fi
    
    printf '%s\n' "${packages[@]}"
}

# Function to clean old incorrect symlinks
clean_old_symlinks() {
    local device_testing_dir="$DEST_PMAPORTS_DIR/device/testing"
    
    echo -e "${BLUE}Checking for incorrect symlinks in device/testing...${NC}"
    
    if [[ ! -d "$device_testing_dir" ]]; then
        return 0
    fi
    
    for symlink in "$device_testing_dir"/{device,linux,firmware}-*/; do
        if [[ -L "$symlink" ]]; then
            local symlink_name=$(basename "$symlink")
            local symlink_target=$(readlink "$symlink")
            
            # Check if symlink points to a directory in custom-pmaports
            if [[ "$symlink_target" == *"custom-pmaports"* ]] || [[ -d "$symlink" ]]; then
                # Verify it points to a valid custom package
                local valid=false
                while IFS= read -r package; do
                    if [[ "$symlink_target" == *"$package" ]]; then
                        valid=true
                        break
                    fi
                done < <(get_custom_packages)
                
                if [[ "$valid" == false ]]; then
                    echo -e "${YELLOW}⚠ Removing incorrect symlink: $symlink_name${NC}"
                    rm "$symlink"
                fi
            else
                # Symlink doesn't point to custom-pmaports, remove it
                echo -e "${YELLOW}⚠ Removing symlink not pointing to custom-pmaports: $symlink_name${NC}"
                rm "$symlink"
            fi
        fi
    done
}

# Function to add symlinks
add_symlinks() {
    local device_testing_dir="$DEST_PMAPORTS_DIR/device/testing"
    
    echo -e "${BLUE}Adding symlinks...${NC}"
    
    # Get list of packages
    local packages
    packages=$(get_custom_packages) || return 1
    
    # Calculate relative path from device/testing to custom-pmaports
    local symlink_rel=$(python3 -c "import os.path; print(os.path.relpath('$CUSTOM_PMAPORTS_DIR', '$device_testing_dir'))")
    
    while IFS= read -r package; do
        local symlink_path="$device_testing_dir/$package"
        local target_path="$symlink_rel/$package"
        
        if [[ -L "$symlink_path" ]]; then
            echo -e "${YELLOW}⚠ Symlink already exists: $package${NC}"
            continue
        fi
        
        if [[ -d "$symlink_path" ]] || [[ -f "$symlink_path" ]]; then
            echo -e "${RED}✗ Path already exists (not a symlink): $package${NC}"
            continue
        fi
        
        ln -s "$target_path" "$symlink_path"
        echo -e "${GREEN}✓ Created symlink: $package${NC}"
    done < <(echo "$packages")
    
    # Add to .gitignore if not already there
    local gitignore_path="$DEST_PMAPORTS_DIR/.gitignore"
    local patterns=("device-*" "linux-*" "firmware-*")
    
    if [[ -f "$gitignore_path" ]]; then
        for pattern in "${patterns[@]}"; do
            if ! grep -q "^$pattern$" "$gitignore_path"; then
                echo "$pattern" >> "$gitignore_path"
                echo -e "${GREEN}✓ Added pattern to .gitignore: $pattern${NC}"
            fi
        done
    else
        for pattern in "${patterns[@]}"; do
            echo "$pattern" >> "$gitignore_path"
        done
        echo -e "${GREEN}✓ Created .gitignore with patterns${NC}"
    fi
    
    echo -e "${GREEN}✓ Symlinks setup complete${NC}"
}

# Function to remove symlinks
remove_symlinks() {
    local device_testing_dir="$DEST_PMAPORTS_DIR/device/testing"
    
    echo -e "${BLUE}Removing symlinks...${NC}"
    
    # Get list of packages
    local packages
    packages=$(get_custom_packages) || return 1
    
    while IFS= read -r package; do
        local symlink_path="$device_testing_dir/$package"
        
        if [[ -L "$symlink_path" ]]; then
            rm "$symlink_path"
            echo -e "${GREEN}✓ Removed symlink: $package${NC}"
        elif [[ -d "$symlink_path" ]] || [[ -f "$symlink_path" ]]; then
            echo -e "${YELLOW}⚠ Path exists but is not a symlink: $package (skipping)${NC}"
        else
            echo -e "${YELLOW}⚠ Symlink not found: $package${NC}"
        fi
    done < <(echo "$packages")
    
    echo -e "${GREEN}✓ Symlinks removal complete${NC}"
}

# Function to show usage
show_usage() {
    echo -e "${BLUE}Custom pmaports Package Symlink Manager${NC}"
    echo ""
    echo "Usage: $0 [add|remove]"
    echo ""
    echo "Commands:"
    echo "  add     - Add symlinks for all custom packages (device-*, linux-*, firmware-*)"
    echo "  remove  - Remove symlinks for all custom packages"
    echo ""
    echo "If no command is provided, you will be prompted to choose."
    echo ""
    echo "This script should be placed in the custom-pmaports directory."
    echo "All packages will be symlinked to pmaports/device/testing/."
}

# Main script logic
main() {
    echo -e "${BLUE}=== Custom pmaports Package Symlink Manager ===${NC}"
    echo ""
    
    # Load existing config
    if load_config; then
        echo -e "${GREEN}Found existing configuration:${NC}"
        echo "dest_pmaports_dir: $DEST_PMAPORTS_DIR"
        echo ""
        
        while true; do
            read -p "Use this directory? (y/n): " use_existing
            case "$use_existing" in
                [Yy]*) break ;;
                [Nn]*) prompt_for_directory; save_config; break ;;
                *) echo "Please answer y or n." ;;
            esac
        done
    else
        echo -e "${YELLOW}No configuration file found.${NC}"
        prompt_for_directory
        save_config
    fi
    
    echo ""
    echo -e "${BLUE}custom-pmaports location: $CUSTOM_PMAPORTS_DIR${NC}"
    echo -e "${BLUE}dest-pmaports location: $DEST_PMAPORTS_DIR${NC}"
    echo ""
    
    # Determine command
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        echo "What do you want to do?"
        echo "1) Add symlinks"
        echo "2) Remove symlinks"
        echo "3) Exit"
        echo ""
        
        while true; do
            read -p "Choose an option (1-3): " choice
            case "$choice" in
                1) command="add"; break ;;
                2) command="remove"; break ;;
                3) echo "Exiting..."; exit 0 ;;
                *) echo "Invalid choice. Please enter 1, 2, or 3." ;;
            esac
        done
    fi
    
    # Execute command
    case "$command" in
        add)
            clean_old_symlinks
            add_symlinks
            ;;
        remove)
            remove_symlinks
            ;;
        *)
            show_usage
            exit 1
            ;;
    esac
    
    echo ""
    echo -e "${GREEN}Done!${NC}"
}

# Run main function
main "$@"
