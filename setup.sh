#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Prevent errors in pipelines from being masked.
set -o pipefail

# --- Configuration ---
WP_PROJECT_NAME="wordpress-bedrock"
DRUPAL_PROJECT_NAME="drupal-site"
FRONTEND_PROJECT_NAME="frontend-app"

WP_URL="https://${WP_PROJECT_NAME}.ddev.site"
DRUPAL_URL="https://${DRUPAL_PROJECT_NAME}.ddev.site"
FRONTEND_URL="https://${FRONTEND_PROJECT_NAME}.ddev.site"

# --- OS Detection ---
OS_TYPE=$(uname -s)
PKG_MANAGER=""

# --- Helper Functions ---
log() {
  echo "" # Add a newline for readability
  echo "--> $(date +'%T') | $*"
  echo "--------------------------------------------------"
}

# --- Precheck Functions ---
is_wordpress_installed() {
  [ -d "wordpress" ] && [ -f "wordpress/.ddev/config.yaml" ]
}

is_drupal_installed() {
  [ -d "drupal" ] && [ -f "drupal/.ddev/config.yaml" ]
}

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
  local tools=("ddev" "composer" "node" "npm")

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
      echo "On Debian/Ubuntu, you can try installing some with: sudo apt-get install composer nodejs npm jq"
    elif [ "$PKG_MANAGER" = "dnf" ]; then
      echo ""
      echo "On Fedora, you can try installing some with: sudo dnf install composer nodejs jq"
    fi

    echo ""
    echo "For DDEV and complete instructions, please see the 'Prerequisites' section in README.md."
    exit 1
  fi

  log "All core tools are installed."
}

check_docker_environment() {
  log "Checking for a running Docker environment..."

  if ! command -v docker >/dev/null 2>&1; then
    echo "ERROR: The 'docker' command was not found. Please install a Docker provider (like OrbStack or Docker Desktop) and ensure it's in your PATH."
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: Could not connect to the Docker daemon. Is it running?"
    if [ "$OS_TYPE" = "Linux" ]; then
      echo "  On Linux, try running: sudo systemctl start docker"
      echo "  Also, ensure your user is in the 'docker' group (requires a logout/login after adding)."
    elif [ "$OS_TYPE" = "Darwin" ]; then
      echo "  On macOS, please start your Docker provider (e.g., OrbStack, Docker Desktop)."
    fi
    exit 1
  fi

  log "Docker daemon is running and accessible."
}

check_orbstack_macos() {
  # This is an advisory check specific to macOS if OrbStack is the preferred provider.
  if [ "$OS_TYPE" != "Darwin" ]; then
    return
  fi

  log "Checking if OrbStack is running..."
  if ! command -v orb >/dev/null 2>&1; then
    log "Note: OrbStack CLI ('orb') not found. Assuming another Docker provider is in use."
    return
  elif ! orb status 2>/dev/null | tr -d '\n' | grep -iq "running"; then
    log "Warning: OrbStack is installed but does not appear to be running. The script will proceed if another Docker provider is active."
  fi

  log "OrbStack is running."
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
  elif [[ " wordpress drupal frontend " =~ " ${site_target} " ]]; then
    sites_to_control=("$site_target")
  else
    echo "Error: Invalid site specified for control: '${site_target}'. Must be wordpress, drupal, frontend, or all."
    exit 1
  fi

  for site_dir_name in "${sites_to_control[@]}"; do
    local friendly_name="${site_dir_name^}"
    control_ddev_project "$site_dir_name" "$friendly_name" "$do_start" "$do_stop"
  done
}

# --- WordPress Setup ---
setup_wordpress() {
  if is_wordpress_installed; then
    log "WordPress is already installed. Skipping setup."
    return
  fi

  log "Setting up WordPress (Bedrock)..."
  if [ -d "wordpress" ]; then
    log "Warning: 'wordpress' directory already exists. Skipping creation."
  else
    composer create-project roots/bedrock wordpress
  fi
  cd wordpress

  log "Attempting to unlist any existing DDEV project named '${WP_PROJECT_NAME}' associated with this directory..."
  # Suppress output and ignore errors (e.g., if project doesn't exist)
  ddev stop --unlist "${WP_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for WordPress..."
  ddev config --project-name="$WP_PROJECT_NAME" --project-type=wordpress --docroot=web

  log "Configuring Bedrock .env file..."
  # Ensure .env.example exists, as it's our source.
  if [ ! -f ".env.example" ]; then
    log "ERROR: .env.example is missing in $(pwd). Cannot configure WordPress. 'composer create-project roots/bedrock' might have failed or changed its output."
    exit 1
  fi

  log "Creating/refreshing .env from .env.example to ensure all base settings are present for DDEV."
  cp .env.example .env # This will overwrite .env if it exists, ensuring a clean base.

  log "Applying DDEV-specific values to .env..."
  # Using '#' as the sed delimiter because $WP_URL contains '/' characters.
  sed -i.bak \
      -e "s#^DB_NAME=.*#DB_NAME='db'#" \
      -e "s#^DB_USER=.*#DB_USER='db'#" \
      -e "s#^DB_PASSWORD=.*#DB_PASSWORD='db'#" \
      -e "s#^DB_HOST=.*#DB_HOST='db'#" \
      -e "s#^WP_HOME=.*#WP_HOME='${WP_URL}'#" \
      -e "s#^WP_SITEURL=.*#WP_SITEURL='${WP_URL}/wp'#" \
      .env
  rm .env.bak # Remove the backup file created by sed

  # Check if DB_HOST is present; if not, append it.
  if ! grep -q "^DB_HOST=" .env; then
    echo "DB_HOST='db'" >> .env
    log "DB_HOST was not found in .env and has been added."
  fi

    log "WordPress .env configured with DDEV values. CRITICAL: You MUST manually add unique salts if they were placeholders or if this is a fresh setup!"
    log "Verifying .env contents from script's perspective (in $(pwd)):"
    grep -E "^DB_HOST=|^WP_HOME=" .env || log "WARNING: DB_HOST or WP_HOME not found in .env by grep!"

  local needs_post_start_delay=false
  log "Checking status of ${WP_PROJECT_NAME} DDEV environment..."
  # `ddev status` run inside the project dir will refer to that project.
  # We grep for "is running" which is part of DDEV's status message for a running project.
  if ddev status 2>/dev/null | grep -q "is running"; then
    log "${WP_PROJECT_NAME} DDEV environment is already running."
  else
    log "Starting ${WP_PROJECT_NAME} DDEV environment..."
    if ! ddev start; then
      log "ERROR: Failed to start ${WP_PROJECT_NAME} DDEV environment."
      exit 1 # Critical failure for install process
    fi
    needs_post_start_delay=true
  fi

  if [ "$needs_post_start_delay" = true ]; then
    log "Waiting a few seconds for services to initialize after fresh start..."
    sleep 5
  else
    log "Brief pause for already running services..."
    sleep 2 # Shorter pause if it was already running
  fi

  log "Ensuring a clean database for WordPress installation..."
  # DDEV ensures 'db' database exists. We drop and recreate it to ensure it's empty.
  if ! ddev mysql -e "DROP DATABASE IF EXISTS db; CREATE DATABASE db;" >/dev/null 2>&1; then
    log "ERROR: Failed to drop/create the database for WordPress. This is a critical step."
    log "Please check DDEV service status and logs for the '${WP_PROJECT_NAME}' project (e.g., 'ddev logs -s db')."
    exit 1
  fi

  log "Installing WordPress core..."
  if ! ddev wp --path=web/wp core install --url="$WP_URL" --title="My Bedrock Site" --admin_user=admin --admin_password=password --admin_email=admin@example.com --debug; then
    log "ERROR: WordPress core installation failed. Please check the output above for details from WP-CLI."
    log "A common cause is not updating the salts in the wordpress/.env file. Please ensure they are unique."
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
        \$frontend_origin = '${FRONTEND_URL}';
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
  log "WordPress setup complete."
}

# --- Drupal Setup ---
setup_drupal() {
  if is_drupal_installed; then
    log "Drupal is already installed. Skipping setup."
    return
  fi

  log "Setting up Drupal..."
  if [ -d "drupal" ]; then
    log "Warning: 'drupal' directory already exists. Skipping creation."
  else
    composer create-project drupal/recommended-project drupal --no-interaction
  fi
  cd drupal

  log "Attempting to unlist any existing DDEV project named '${DRUPAL_PROJECT_NAME}' associated with this directory..."
  # Suppress output and ignore errors
  ddev stop --unlist "${DRUPAL_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for Drupal..."
  ddev config --project-name="$DRUPAL_PROJECT_NAME" --project-type=drupal10 --docroot=web

  local needs_post_start_delay=false
  log "Checking status of ${DRUPAL_PROJECT_NAME} DDEV environment..."
  if ddev status 2>/dev/null | grep -q "is running"; then
    log "${DRUPAL_PROJECT_NAME} DDEV environment is already running."
  else
    log "Starting ${DRUPAL_PROJECT_NAME} DDEV environment..."
    if ! ddev start; then
      log "ERROR: Failed to start ${DRUPAL_PROJECT_NAME} DDEV environment."
      exit 1
    fi
    needs_post_start_delay=true
  fi

  if [ "$needs_post_start_delay" = true ]; then
    log "Waiting a few seconds for Drupal services to initialize after fresh start..."
    sleep 5
  else
    log "Brief pause for already running Drupal services..."
    sleep 2
  fi

  log "Ensuring Drush is installed..."
  ddev composer require drush/drush --no-interaction --quiet

  log "Installing Drupal site..."
  ddev drush site:install standard --db-url=mysql://db:db@db/db --site-name="My Drupal Site" --account-name=admin --account-pass=password -y

  log "Enabling Drupal JSON:API module..."
  ddev drush en jsonapi -y

  log "Configuring Drupal CORS..."
  DRUPAL_SERVICES_YML="web/sites/default/services.yml"
  DRUPAL_DEFAULT_SERVICES_YML="web/sites/default/default.services.yml"
  if [ ! -f "$DRUPAL_SERVICES_YML" ] && [ -f "$DRUPAL_DEFAULT_SERVICES_YML" ]; then
    cp "$DRUPAL_DEFAULT_SERVICES_YML" "$DRUPAL_SERVICES_YML"
  fi

  if [ -f "$DRUPAL_SERVICES_YML" ]; then
    log "Modifying $DRUPAL_SERVICES_YML for CORS..."
    # Escape FRONTEND_URL for sed replacement. Handles typical URL characters.
    # For YAML single-quoted strings, a single quote ' is escaped as ''.
    local frontend_url_escaped
    frontend_url_escaped=$(printf '%s\n' "$FRONTEND_URL" | sed -e 's/[\/&]/\\&/g' -e "s/'/''/g")

    # This sed command attempts to uncomment and configure CORS settings.
    # It assumes a structure similar to Drupal's default.services.yml where
    # 'parameters:' exists, and 'cors.config:' is commented out under it.
    # Heuristic block matching is used. Review $DRUPAL_SERVICES_YML if issues persist.
    sed -i.bak -E \
      -e "/^[[:space:]]*##*[[:space:]]*parameters:/s|^([[:space:]]*)##*([[:space:]]*parameters:)|\1\2|" \
      -e "/^[[:space:]]*parameters:/,/^([^[:space:]]|$)/{ \
            /^[[:space:]]*##*[[:space:]]*cors\.config:/s|^([[:space:]]*)##*([[:space:]]*cors\.config:)|\1\2| ; \
            /^[[:space:]]*cors\.config:/,/^([[:space:]]{0,2}[^[:space:]#]|$)/{ \
                s|^([[:space:]]*)##*([[:space:]]*enabled:[[:space:]]*)(false|true)|\1\2true| ; \
                s|^([[:space:]]*enabled:[[:space:]]*)(false|true)|\1true| ; \
                s|^([[:space:]]*)##*([[:space:]]*allowedOrigins:[[:space:]]*).*|\1allowedOrigins: ['${frontend_url_escaped}']| ; \
                s|^([[:space:]]*allowedOrigins:[[:space:]]*).*|\1allowedOrigins: ['${frontend_url_escaped}']| ; \
                s|^([[:space:]]*)##*([[:space:]]*allowedMethods:[[:space:]]*).*|\1allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']| ; \
                s|^([[:space:]]*allowedMethods:[[:space:]]*).*|\1allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']| ; \
                s|^([[:space:]]*)##*([[:space:]]*allowedHeaders:[[:space:]]*).*|\1allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept']| ; \
                s|^([[:space:]]*allowedHeaders:[[:space:]]*).*|\1allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept']| ; \
                s|^([[:space:]]*)##*([[:space:]]*exposedHeaders:[[:space:]]*).*|\1exposedHeaders: false| ; \
                s|^([[:space:]]*exposedHeaders:[[:space:]]*).*|\1exposedHeaders: false| ; \
                s|^([[:space:]]*)##*([[:space:]]*maxAge:[[:space:]]*).*|\1maxAge: 0| ; \
                s|^([[:space:]]*maxAge:[[:space:]]*).*|\1maxAge: 0| ; \
                s|^([[:space:]]*)##*([[:space:]]*supportsCredentials:[[:space:]]*).*|\1supportsCredentials: false| ; \
                s|^([[:space:]]*supportsCredentials:[[:space:]]*).*|\1supportsCredentials: false| ; \
            } \
         }" "$DRUPAL_SERVICES_YML"

    rm -f "${DRUPAL_SERVICES_YML}.bak" # Remove backup if sed was successful
    log "Drupal CORS configuration modification attempted. Clearing Drupal cache."
    ddev drush cr
  else
    log "ERROR: $DRUPAL_SERVICES_YML not found. Cannot configure Drupal CORS."
  fi

  cd ..
  log "Drupal setup complete."
}

# --- Frontend Setup ---
setup_frontend() {
  if is_frontend_installed; then
    log "Frontend is already installed. Skipping setup."
    return
  fi

  log "Setting up Frontend..."
  if [ -d "frontend" ]; then
    log "Warning: 'frontend' directory already exists. Skipping creation."
  else
    mkdir frontend
  fi
  cd frontend

  if [ ! -f "package.json" ]; then
    log "Initializing Vue project using Vite..."
    npm create vite@latest . -- --template vue
    npm install
  else
    npm install
  fi

  npm run build

  log "Attempting to unlist any existing DDEV project named '${FRONTEND_PROJECT_NAME}' associated with this directory..."
  # Suppress output and ignore errors
  ddev stop --unlist "${FRONTEND_PROJECT_NAME}" >/dev/null 2>&1 || true

  log "Configuring DDEV for Frontend..."
  ddev config --project-name="$FRONTEND_PROJECT_NAME" --project-type=php --docroot=dist --webserver-type=nginx-fpm

  log "Checking status of ${FRONTEND_PROJECT_NAME} DDEV environment..."
  if ddev status 2>/dev/null | grep -q "is running"; then
    log "${FRONTEND_PROJECT_NAME} DDEV environment is already running."
  else
    log "Starting ${FRONTEND_PROJECT_NAME} DDEV environment..."
    if ! ddev start; then
      log "ERROR: Failed to start ${FRONTEND_PROJECT_NAME} DDEV environment."
      exit 1
    fi
    # Frontend doesn't have a DB install step, so less critical for long sleep,
    # but good to ensure webserver is up.
    log "Waiting a moment for frontend services..."
    sleep 3
  fi

  cd ..
  log "Frontend setup complete."
}

# --- Help Function ---
show_help() {
  echo "Usage: $0 [options]"
  echo ""
  echo "Options:"
  echo "  --help                   Show this help message"
  echo "  --install                Run the full installation process after checks."
  echo "  --site=<name|all>        Specify the site to control (wordpress, drupal, frontend, or all)."
  echo "  --start                  Start the specified DDEV project(s)."
  echo "  --stop                   Stop the specified DDEV project(s)."
  echo ""
  echo "Examples:"
  echo "  $0 --help                 Show this help message."
  echo "  $0                       Run checks only."
  echo "  $0 --install              Install all sites."
  echo "  $0 --site=wordpress --start  Start the WordPress site."
}
# --- Main Script ---
# Initialize control flags
SITE_TO_CONTROL=""
ACTION_START=false
ACTION_STOP=false
ACTION_INSTALL=false

# Parse arguments
if [ "$#" -eq 0 ]; then
  # No arguments: Default to checks only
  log "No arguments provided. Running checks only."
elif [[ "$1" == "--help" ]]; then
    show_help
    exit 0
else
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --site=*) SITE_TO_CONTROL="${1#*=}"; shift ;;
            --start) ACTION_START=true; shift ;;
            --stop) ACTION_STOP=true; shift ;;
            --install) ACTION_INSTALL=true; shift ;;
            *)
                echo "Unknown parameter passed: $1"
                show_help
                exit 1
                ;;
        esac
    done
fi

# Always run prerequisite checks
detect_package_manager
check_core_tools
check_docker_environment
check_orbstack_macos # Advisory check for macOS users

if [ "$ACTION_INSTALL" = true ]; then
  log "Running installation process."
  setup_wordpress
  setup_drupal
  setup_frontend
elif [ "$ACTION_START" = true ] || [ "$ACTION_STOP" = true ]; then
  if [ -z "$SITE_TO_CONTROL" ]; then
    echo "Error: --site must be specified with --start or --stop."
    echo "Usage: $0 [--site=<wordpress|drupal|frontend|all>] [--start] [--stop]"
    exit 1
  fi
  perform_site_control "$SITE_TO_CONTROL" "$ACTION_START" "$ACTION_STOP"
else
  log "Checks complete. No installation or specific control actions were requested."
fi

# --- Final Summary ---
log "Setup Script Finished!"
echo ""
if [ "$ACTION_INSTALL" = true ]; then
  echo "Project URLs (after installation):"
  echo "  WordPress: ${WP_URL}"
  echo "  Drupal:    ${DRUPAL_URL}"
  echo "  Frontend:  ${FRONTEND_URL}"
  echo ""
  echo "Ensure you have at least one published post in WordPress and one published 'article' node in Drupal for the frontend demo to display data."
elif [ "$ACTION_START" = true ] || [ "$ACTION_STOP" = true ]; then
  echo "Site control actions completed for: '${SITE_TO_CONTROL}'."
  if [ "$ACTION_START" = true ]; then
    echo "Relevant project URLs should have been displayed by DDEV during startup if they were started."
    echo "Use 'ddev list' or 'ddev describe' in the respective project directories to see current URLs and status."
  fi
else
  echo "Prerequisite checks completed. No further actions were performed."
fi
echo ""

exit 0
