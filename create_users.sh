#!/bin/bash

LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE_DIRECTORY="/var/secure"
PASSWORD_FILE="/var/secure/user_passwords.txt"
PASSWORD_ENCRYPTION_KEY="secure-all-things"
USERS_FILE=$1

# Check if script is run with sudo
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run with sudo. Exiting..."
    exit 1
fi

# Redirect stdout and stderr to log file
exec > >(tee -a "$LOG_FILE") 2>&1 
echo "Executing script... (note that this line will be logged twice)" | tee -a $LOG_FILE 

# Check if an argument was provided
if [ $# -eq 0 ]; then
    echo "No file path provided." 
    echo "Usage: $0 <user-data-file-path>" 
    exit 1
fi

# Check if the user's data file exists
if [ ! -e "$USERS_FILE" ]; then
    echo "The provided user's data file does not exist: $USERS_FILE"
    exit 1
fi

# Function to check if a package is installed
is_package_installed() {
    dpkg -s "$1" >/dev/null 2>&1
}

# Function to encrypt password
encrypt_password() {
    echo "$1" | openssl enc -aes-256-cbc -pbkdf2 -base64 -pass pass:"$2"
}

# Function to set Bash as default shell
set_bash_default_shell() {
    local user="$1"
    sudo chsh -s /bin/bash "$user"
}

# Check if openssl is installed
if ! is_package_installed openssl; then
    echo "openssl is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y openssl
fi

# Check if pwgen is installed
if ! is_package_installed pwgen; then
    echo "pwgen is not installed. Installing..."
    sudo apt-get update
    sudo apt-get install -y pwgen
fi

# Check if the file exists
if [ ! -f "$USERS_FILE" ]; then
    echo "Error: $USERS_FILE not found."
    exit 1
fi

# Create the directory where the user's password file will be stored
sudo mkdir -p "$PASSWORD_FILE_DIRECTORY"

# load the content of the users.txt file into an array: lines
mapfile -t lines < "$USERS_FILE"

# loop over each line in the array
for line in "${lines[@]}"; do
    # Remove leading and trailing whitespaces
    line=$(echo "$line" | xargs)
    
    # Split line by ';' and store the second part
    IFS=';' read -r user groups <<< "$line"
    
    # Remove leading and trailing whitespaces from the second part
    groups=$(echo "$groups" | xargs)

    # Create a variable groupsArray that is an array from spliting the groups of each user
    IFS=',' read -ra groupsArray <<< "$groups"

    # Check if user exists
    if id "$user" &>/dev/null; then
        echo "User $user already exists. Skipping creation."
        continue
    fi

    # Generate a 6-character password using pwgen
    password=$(pwgen -sBv1 6 1)

    # Encrypt the password before storing it
    encrypted_password=$(encrypt_password "$password" "$PASSWORD_ENCRYPTION_KEY")

    # Store the encrypted password in the file
    echo "$user:$encrypted_password" >> "$PASSWORD_FILE"

    # Create the user with the generated password
    sudo useradd -m -p $(openssl passwd -6 "$password") "$user"

    # Set Bash as the default shell
    set_bash_default_shell "$user"

    # loop over each group in the groups array
    for group in "${groupsArray[@]}"; do
        group=$(echo "$group" | xargs)
        
        # Check if group exists, if not, create it
        if ! grep -q "^$group:" /etc/group; then
            sudo groupadd "$group"
            echo "Created group $group"
        fi

        # Add user to the group
        sudo usermod -aG "$group" "$user"
        echo "Added $user to $group"
    done

    echo "User $user created and password stored securely"
done

# remove the created password from the current shell session
unset password
