#!/bin/bash
#
# -e: exit immediately if a command exits with a non-zero status.
# -u: treat unset variables as an error when substituting.
# -o pipefail: the return value of a pipeline is the status of the last
#              command to exit with a non-zero status, or zero if no
#              command exited with a non-zero status.
set -euo pipefail

# --- Script Configuration - start ---

# WoordPress configuration
WP_PROJECT_NAME="wordpress-bedrock"
WP_URL="https://${WP_PROJECT_NAME}.ddev.site"

# Drupal configuration
DRUPAL_PROJECT_NAME="drupal-site"
DRUPAL_URL="https://${DRUPAL_PROJECT_NAME}.ddev.site"

# Frontend configuration
FRONTEND_PROJECT_NAME="frontend-app"
FRONTEND_URL="https://${FRONTEND_PROJECT_NAME}.ddev.site"

# --- Operating System Detection for container host ---
OS_TYPE=$(uname -s)
PKG_MANAGER=""

# --- Script Configuration - end ---

# --- Helper Functions ---

# --- Log Functions ---
log() {
  echo "" # Add a newline for readability
  echo "--> $(date +'%T') | $*"
  echo "--------------------------------------------------"
}

# --- Precheck Functions ---

# --- WordPress Precheck Function ---
is_wordpress_installed() {
  [ -d "wordpress" ] && [ -f "wordpress/.ddev/config.yaml" ]
}

# --- Drupal Precheck Function ---
is_drupal_installed() {
  [ -d "drupal" ] && [ -f "drupal/.ddev/config.yaml" ]
}

# --- Frontend Precheck Function ---
is_frontend_installed() {
  [ -d "frontend" ] && [ -f "frontend/.ddev/config.yaml" ]
}

# --- Prerequisite Detection ---
detect_package_manager() {
  if [ "$OS_TYPE" != "Linux" ]; then
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    PKG_MANAGER="apt"
  elif command -v dnf >/dev/null 2>&1; then
    PKG_MANAGER="dnf"
  fi
}

# --- Prerequisite Checks ---
check_core_tools() {
  log "Checking for core tools (ddev, composer, node, npm)..."
  local missing_tools=()
  local tools=("ddev" "composer" "node" "npm" "yq")

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -ne 0 ]; then
    echo "ERROR: The following tools are missing and must be installed before proceeding:"
    echo ""
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    
    if [ "$PKG_MANAGER" = "apt" ]; then
      echo ""
      echo "On Debian/Ubuntu, you can try installing some with: sudo apt-get install composer nodejs npm jq yq"
    elif [ "$PKG_MANAGER" = "dnf" ]; then
      echo ""
      echo "On Fedora, you can try installing some with: sudo dnf install composer nodejs jq yq"
    fi

    echo ""
    echo "For DDEV and complete instructions, please see the 'Prerequisites' section in README.md."
    exit 1
  fi

  log "All core tools are installed."
}

# --- Helper Function to Ensure Docker is Running ---
# This function checks the current Docker context and ensures the corresponding
# provider (OrbStack or Colima) is running before proceeding.
ensure_docker_running() {
  log "Checking Docker provider and status..."

  if ! command -v docker &> /dev/null; then
    echo "❌ Docker CLI is not installed. Please install a compatible provider (e.g., OrbStack, Docker Desktop) and ensure the 'docker' command is in your PATH."
    exit 1
  fi

  # First, try a quiet `docker info` as a fast path. If it succeeds, we're good.
  if docker info >/dev/null 2>&1; then
    log "✅ Docker daemon is running and accessible."
    return
  fi

  log "Could not connect to Docker daemon. Will check for known DDEV providers..."
  local context
  context=$(docker context show)

  echo "ℹ️ Current Docker context is set to: '$context'"

  case "$context" in
    orbstack)
      if [ "$OS_TYPE" = "Darwin" ]; then
        log "-> OrbStack detected. Attempting to start..."
        open -a OrbStack
        log "   Waiting for OrbStack to initialize..."
        # Poll until the Docker daemon is responsive
        while ! docker info &> /dev/null; do
          printf "."
          sleep 2
        done
        echo ""
        log "✅ OrbStack is now running."
      else
        log "⚠️ OrbStack context detected, but this is not macOS. Manual start of Docker is required."
      fi
      ;;

    colima)
      log "-> Colima detected. Attempting to start..."
      if ! colima status &> /dev/null | grep -q "Running"; then
        if colima start; then
            log "✅ Colima started successfully."
        else
            log "❌ Failed to start Colima. Please check your Colima setup."
            exit 1
        fi
      fi
      ;;

    *)
      log "-> Unrecognized or default Docker context: '$context'."
      if [ "$OS_TYPE" = "Linux" ]; then
        echo "  On Linux, try running: sudo systemctl start docker"
        echo "  Also, ensure your user is in the 'docker' group (requires a logout/login after adding)."
      elif [ "$OS_TYPE" = "Darwin" ]; then
        echo "  On macOS, please start your Docker application (e.g., OrbStack, Docker Desktop)."
      fi
      ;;
  esac

  # Final check after attempting to start providers
  if ! docker info >/dev/null 2>&1; then
echo "ERROR: Could not connect to the Docker daemon. Is it running?"
    if [ "$OS_TYPE" = "Linux" ]; then
      echo "  On Linux, try running: sudo systemctl start docker"
      echo "  Also, ensure your user is in the 'docker' group (requires a logout/login after adding)."
    elif [ "$OS_TYPE" = "Darwin" ]; then
      echo "  On macOS, please start your Docker provider (e.g., OrbStack, Docker Desktop)."
    fi
    log "❌ ERROR: Docker daemon is still not responsive after checks. Please start your Docker provider manually and try again."
    exit 1
  fi

  log "✅ Docker daemon is now running and accessible."
}

# --- Site Control Functions ---
control_ddev_project() {
  local project_dir_name="$1"
  local project_friendly_name="$2" # e.g., "WordPress"
  local do_start="$3"
  local do_stop="$4"

  if [ ! -d "$project_dir_name" ] || [ ! -f "$project_dir_name/.ddev/config.yaml" ]; then
    log "Project ${project_friendly_name} (${project_dir_name}) is not configured or directory does not exist. Skipping control."
    return
  fi

  local current_dir
  current_dir=$(pwd)
  cd "$project_dir_name"

  if [ "$do_stop" = true ]; then
    log "Issuing stop command for ${project_friendly_name} DDEV project..."
    ddev stop
  fi

  if [ "$do_start" = true ]; then
    log "Checking status of ${project_friendly_name} DDEV project..."
    if ddev status 2>/dev/null | grep -q "is running"; then # Check if DDEV reports project as running in current dir
      log "${project_friendly_name} DDEV project is already running."
    else
      log "Issuing start command for ${project_friendly_name} DDEV project..."
      if ! ddev start; then
        log "ERROR: Failed to start ${project_friendly_name} DDEV project in ${project_dir_name}. Continuing if other sites targeted..."
      fi
    fi
  fi

  cd "$current_dir"
}

perform_site_control() {
  local site_target="$1"
  local do_start="$2"
  local do_stop="$3"

  log "Performing site control: Target=${site_target}, Start=${do_start}, Stop=${do_stop}"

  local sites_to_control=()
  if [ "$site_target" = "all" ]; then
    sites_to_control=("wordpress" "drupal" "frontend")
  else
    case "$site_target" in
      wordpress|drupal|frontend)
        sites_to_control=("$site_target")
        ;;
      *)
        echo "Error: Invalid site specified for control: '${site_target}'. Must be wordpress, drupal, frontend, or all."
        exit 1
        ;;
    esac
  fi

  for site_dir_name in "${sites_to_control[@]}"; do
    local friendly_name="${site_dir_name^}"
    control_ddev_project "$site_dir_name" "$friendly_name" "$do_start" "$do_stop"
  done
}
# --- WordPress Setup ---
generate_wp_salts() {
  log "Generating and applying WordPress salts..."
  # Fetch salts from the official Roots API
  local salts
  salts=$(curl -sL https://roots.io/salts.html)

  if [ -z "$salts" ]; then
    log "ERROR: Failed to fetch salts from roots.io. Please add them manually to wordpress/.env"
    # The installation will likely fail later, but this is a clear warning.
    return
  fi

  # Create a temporary file for the new .env content
  local temp_env
  temp_env=$(mktemp)

  # Write all lines from the current .env file to the temp file, EXCEPT for the salt lines
  grep -v -E "^(AUTH_KEY|SECURE_AUTH_KEY|LOGGED_IN_KEY|NONCE_KEY|AUTH_SALT|SECURE_AUTH_SALT|LOGGED_IN_SALT|NONCE_SALT)=" .env > "$temp_env"

  # Append the freshly generated salts to the temp file
  echo "" >> "$temp_env"
  echo "$salts" >> "$temp_env"

  # Replace the original .env file with the updated one
  mv "$temp_env" .env

  log "✅ WordPress salts have been automatically generated and applied."
}

# WordPress local website setup and installation using Bedrock
setup_wordpress() {
  if is_wordpress_installed; then
    log "WordPress is already installed. Skipping setup."
    return
  fi

  log "Setting up WordPress (Bedrock)..."
  if [ -d "wordpress" ]; then
    log "Warning: 'wordpress' directory already exists. Skipping 'composer create-project'."
  else
    composer create-project roots/bedrock wordpress
  fi
  cd wordpress

  log "Attempting to unlist any existing DDEV project named '${WP_PROJECT_NAME}' associated with this directory..."
  # Suppress output and ignore errors (e.g., if project doesn't exist)
  ddev stop --unlist "${WP_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for WordPress..."

  ddev config --project-name="$WP_PROJECT_NAME" --project-type=wordpress --docroot=web --create-docroot

  log "Configuring Bedrock .env file..."
  if [ ! -f ".env.example" ]; then
    log "ERROR: .env.example is missing in $(pwd). Cannot configure WordPress."
    exit 1
  fi

  cp .env.example .env

  log "Applying DDEV-specific database and URL values to .env..."
  # Using '#' as the sed delimiter because $WP_URL contains '/' characters.
  sed -i.bak \
      -e "s#^DB_NAME=.*#DB_NAME='db'#" \
      -e "s#^DB_USER=.*#DB_USER='db'#" \
      -e "s#^DB_PASSWORD=.*#DB_PASSWORD='db'#" \
      -e "s@^# DB_HOST='localhost'@DB_HOST='db'@" \
      -e "s#^WP_HOME=.*#WP_HOME='${WP_URL}'#" \
      -e "s#^WP_SITEURL=.*#WP_SITEURL='${WP_URL}/wp'#" \
      .env
  rm .env.bak

  # Automatically generate and apply salts
  generate_wp_salts

  log "Starting ${WP_PROJECT_NAME} DDEV environment..."
  ddev start

  log "Installing WordPress core..."
  if ! ddev wp --path=web/wp core install --url="$WP_URL" --title="My Bedrock Site" --admin_user=admin --admin_password=password --admin_email=admin@example.com; then
    log "ERROR: WordPress core installation failed. Please check the output above."
    log "Common causes include an unresponsive Docker environment or incorrect .env values."
    exit 1
  fi
  
  log "Configuring WordPress CORS (via mu-plugin)..."
  mkdir -p web/app/mu-plugins
  cat << EOF > web/app/mu-plugins/ddev_cors_setup.php
<?php
/**
 * Plugin Name: DDEV CORS Setup
 * Description: Enables CORS headers for the REST API for the frontend DDEV site.
 */

add_action( 'rest_api_init', function() {
    remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );
    add_filter( 'rest_pre_serve_request', function( \$value ) {
        \$frontend_origin = '${FRONTEND_URL}'; // Injected by setup script
        if ( isset( \$_SERVER['HTTP_ORIGIN'] ) && \$_SERVER['HTTP_ORIGIN'] === \$frontend_origin ) {
            header( 'Access-Control-Allow-Origin: ' . \$frontend_origin );
            header( 'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS' );
            header( 'Access-Control-Allow-Credentials: true' );
            header( 'Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Accept' );
            if ( 'OPTIONS' === \$_SERVER['REQUEST_METHOD'] ) {
                status_header( 200 );
                exit();
            }
        }
        return \$value;
    });
}, 15 );
EOF
  log "WordPress CORS mu-plugin created."

  cd ..
  log "✅ WordPress setup complete."
}

# --- Drupal Setup ---
setup_drupal() {
  if is_drupal_installed; then
    log "Drupal is already installed. Skipping setup."
    return
  fi

  log "Setting up Drupal..."
  if [ -d "drupal" ]; then
    log "Warning: 'drupal' directory already exists. Skipping 'composer create-project'."
  else
    composer create-project drupal/recommended-project drupal --no-interaction
  fi
  cd drupal

  log "Attempting to unlist any existing DDEV project named '${DRUPAL_PROJECT_NAME}' associated with this directory..."
  ddev stop --unlist "${DRUPAL_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for Drupal..."
  ddev config --project-name="$DRUPAL_PROJECT_NAME" --project-type=drupal10 --docroot=web

  log "Starting ${DRUPAL_PROJECT_NAME} DDEV environment..."
  ddev start

  log "Ensuring Drush is installed..."
  ddev composer require drush/drush --no-interaction --quiet

  log "Installing Drupal via Drush..."
  ddev drush site:install standard --db-url=mysql://db:db@db/db --site-name="My Drupal Site" --account-name=admin --account-pass=password -y

  log "Enabling Drupal JSON:API module..."
  ddev drush en jsonapi -y

  log "Configuring Drupal CORS..."
  DRUPAL_SERVICES_YML="web/sites/default/services.yml"
  if [ ! -f "$DRUPAL_SERVICES_YML" ] && [ -f "web/sites/default/default.services.yml" ]; then
    cp "web/sites/default/default.services.yml" "$DRUPAL_SERVICES_YML"
  fi

  if [ -f "$DRUPAL_SERVICES_YML" ]; then
    # Append a CORS configuration block. This is more robust than sed.
    # The last 'cors.config' block in the file will take precedence.
    echo "Appending CORS configuration to ${DRUPAL_SERVICES_YML}..."
    cat << EOF >> "$DRUPAL_SERVICES_YML"

# --- DDEV-generated CORS configuration ---
# This block was added by the setup script to allow API access from the frontend app.
parameters:
  cors.config:
    enabled: true
    allowedHeaders:
      - 'Content-Type'
      - 'Authorization'
      - 'X-Requested-With'
      - 'Accept'
    allowedMethods:
      - 'GET'
      - 'POST'
      - 'PUT'
      - 'DELETE'
      - 'OPTIONS'
    allowedOrigins:
      - '${FRONTEND_URL}'
    exposedHeaders: false
    maxAge: 0
    supportsCredentials: true
# --- End DDEV-generated CORS configuration ---
EOF
    log "Drupal CORS configuration appended. Clearing Drupal cache."
    ddev drush cr
  else
    log "ERROR: ${DRUPAL_SERVICES_YML} not found. Cannot configure Drupal CORS."
  fi

  cd ..
  log "✅ Drupal setup complete."
}

# --- Frontend Setup ---
setup_frontend() {
  if is_frontend_installed; then
    log "Frontend is already installed. Skipping setup."
    return
  fi

  log "Setting up Frontend..."
  if [ -d "frontend" ]; then
    log "Warning: 'frontend' directory already exists. Assuming it's set up."
  else
    mkdir frontend
  fi
  cd frontend

  if [ ! -f "package.json" ]; then
    log "Initializing Vue project using Vite..."
    echo "" | npm create vite@latest . -- --template vue
    npm install
  else
    log "package.json exists, running 'npm install'..."
    npm install
  fi

  log "Building static assets for production..."
  npm run build

  log "Attempting to unlist any existing DDEV project named '${FRONTEND_PROJECT_NAME}' associated with this directory..."
  ddev stop --unlist "${FRONTEND_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for Frontend..."
  ddev config --project-name="$FRONTEND_PROJECT_NAME" --project-type=php --docroot=dist --webserver-type=nginx-fpm

  log "Starting ${FRONTEND_PROJECT_NAME} DDEV environment..."
  ddev start

  cd ..
  log "✅ Frontend setup complete."
}
# --- Site Listing ---
list_sites() {
  log "Listing DDEV project statuses..."
  # Use ddev list and pipe to grep to only show our projects.
  # The -E flag allows for OR logic in grep.
  ddev list | grep -E "NAME|${WP_PROJECT_NAME}|${DRUPAL_PROJECT_NAME}|${FRONTEND_PROJECT_NAME}" || true
}



# --- Help Function ---
show_help() {
  echo "Usage: $0 [command]"
  echo ""
  echo "A script to automate the setup and control of a multi-site DDEV environment."
  echo ""
  echo "Commands:"
  echo "  --install                Run the full, first-time installation for all sites (WordPress, Drupal, Frontend)."
  echo "  --start --site=<name>    Start the specified DDEV project. <name> can be 'wordpress', 'drupal', 'frontend', or 'all'."
  echo "  --stop --site=<name>     Stop the specified DDEV project. <name> can be 'wordpress', 'drupal', 'frontend', or 'all'."
  echo "  --list                   List the status and URLs of all projects managed by this script."
  echo "  --help                   Show this help message."
  echo ""
  echo "Examples:"
  echo "  $0 --install                   # Install all three sites from scratch."
  echo "  $0 --start --site=wordpress    # Start only the WordPress DDEV project."
  echo "  $0 --stop --site=all           # Stop all three DDEV projects."
  echo "  $0 --list                      # Show project status and URLs."
  echo "  $0                             # With no command, runs checks and shows this help."
}

# --- Main Script ---
# Initialize control flags
SITE_TO_CONTROL=""
ACTION_START=false
ACTION_STOP=false
ACTION_INSTALL=false
ACTION_LIST=false
ACTION_HELP=false

# Parse arguments. If --help is found, show help and exit immediately.
for arg in "$@"; do
  if [ "$arg" == "--help" ]; then
    show_help
    exit 0
  fi
done

# If we're still here, parse arguments properly.
if [ "$#" -eq 0 ]; then
  # No arguments: Default to checks and help
  log "No command provided. Running prerequisite checks and then displaying help."
  ACTION_HELP=true
else
  while [[ "$#" -gt 0 ]]; do
      case $1 in
          --site=*) SITE_TO_CONTROL="${1#*=}"; shift ;;
          --start) ACTION_START=true; shift ;;
          --stop) ACTION_STOP=true; shift ;;
          --install) ACTION_INSTALL=true; shift ;;
          --list) ACTION_LIST=true; shift ;;
          *)
              echo "Unknown parameter passed: $1"
              show_help
              exit 1
              ;;
      esac
  done
fi

# Run prerequisite checks for all commands except --help (which exited above).
detect_package_manager
check_core_tools
ensure_docker_running

if [ "$ACTION_INSTALL" = true ]; then
  log "Running full installation process..."
  setup_wordpress
  setup_drupal
  rm -rf frontend # Ensure clean frontend install
  setup_frontend
  log "Installation complete. Listing sites..."
  list_sites
elif [ "$ACTION_START" = true ] || [ "$ACTION_STOP" = true ]; then
  if [ -z "$SITE_TO_CONTROL" ]; then
    echo "Error: --site=<name|all> must be specified with --start or --stop."
    show_help
    exit 1
  fi
  perform_site_control "$SITE_TO_CONTROL" "$ACTION_START" "$ACTION_STOP"
elif [ "$ACTION_LIST" = true ]; then
  list_sites
else # This 'else' will now cover the case where no arguments were provided initially (ACTION_HELP is true implicitly)
     # or if some other unknown argument path was taken and ACTION_HELP somehow didn't get set.
  log "Prerequisite checks complete. Displaying help."
  show_help
fi

# --- Final Summary ---
log "Setup Script Finished!"
if [ "$ACTION_INSTALL" = true ]; then
  echo ""
  echo "Project URLs (after installation):"
  echo "  WordPress: ${WP_URL}"
  echo "  Drupal:    ${DRUPAL_URL}"
  echo "  Frontend:  ${FRONTEND_URL}"
  echo ""
  echo "Next steps:"
  echo " - For WordPress, create a post."
  echo " - For Drupal, create an 'Article' content type."
  echo " - Visit the frontend URL to see the results."
fi
echo ""

exit 0
