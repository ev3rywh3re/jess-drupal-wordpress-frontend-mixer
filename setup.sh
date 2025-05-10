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

# --- Prerequisite Checks ---
check_prerequisites() {
  log "Checking prerequisites..."
  local missing_tools=()
  local tools=("ddev" "composer" "node" "npm")

  for tool in "${tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done

  if [ ${#missing_tools[@]} -ne 0 ]; then
    echo "ERROR: The following tools are missing and must be installed before proceeding:"
    for tool in "${missing_tools[@]}"; do
      echo "  - $tool"
    done
    echo "Please install the missing tools and re-run the script."
    exit 1
  fi

  log "All prerequisites are installed."
}
check_orbstack() {
  log "Checking if OrbStack is running..."

  # Check if the `orb` command exists
  if ! command -v orb >/dev/null 2>&1; then
    echo "ERROR: OrbStack CLI ('orb') is not installed or not in the PATH. Please install OrbStack and re-run the script."
    exit 1
  fi

  # Check if OrbStack is running using the `orb` command
  if ! orb status 2>/dev/null | tr -d '\n' | grep -iq "running"; then
    echo "ERROR: OrbStack is not running. Please start OrbStack and re-run the script."
    exit 1
  fi

  log "OrbStack is running."
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
  if [ ! -f ".env" ]; then
    cp .env.example .env
    sed -i.bak \
        -e "s|^DB_NAME=.*|DB_NAME='db'|" \
        -e "s|^DB_USER=.*|DB_USER='db'|" \
        -e "s|^DB_PASSWORD=.*|DB_PASSWORD='db'|" \
        -e "s|^DB_HOST=.*|DB_HOST='db'|" \
        -e "s|^WP_HOME=.*|WP_HOME='${WP_URL}'|" \
        -e "s|^WP_SITEURL=.*|WP_SITEURL='${WP_URL}/wp'|" \
        .env
    rm .env.bak
    log "WordPress .env configured. CRITICAL: You MUST manually add unique salts!"
  else
    log "WordPress .env file already exists. Skipping modification."
  fi

  log "Starting WordPress DDEV environment..."
  ddev start
  log "Waiting a few seconds for services to initialize..."
  sleep 5

  log "Ensuring a clean database for WordPress installation..."
  # DDEV ensures 'db' database exists. We drop and recreate it to ensure it's empty.
  # Errors are ignored in case the DB wasn't fully there yet, though ddev start usually handles it.
  ddev mysql -e "DROP DATABASE IF EXISTS db; CREATE DATABASE db;" >/dev/null 2>&1 || log "Note: DB drop/create might have had minor issues, usually ignorable on first run."

  log "Installing WordPress core..."
  if ! ddev wp --path=web/wp core install --url="$WP_URL" --title='My Bedrock Site' --admin_user=admin --admin_password=password --admin_email=admin@example.com --debug; then
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

  log "Starting Drupal DDEV environment..."
  ddev start

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
    if ! grep -q "cors.config:" "$DRUPAL_SERVICES_YML"; then
      cat << EOF >> "$DRUPAL_SERVICES_YML"

  cors.config:
    enabled: true
    allowedOrigins: ['${FRONTEND_URL}']
    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With, Accept']
    exposedHeaders: false
    maxAge: 0
    supportsCredentials: false
EOF
    fi
    ddev drush cr
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

  ddev start
  cd ..
  log "Frontend setup complete."
}

# --- Main Script ---
if [ "$#" -eq 0 ]; then
  log "Running checks only (no installation)."
  check_prerequisites
  check_orbstack
elif [ "$1" == "--install" ]; then
  log "Running installation process."
  check_prerequisites
  check_orbstack
  setup_wordpress
  setup_drupal
  setup_frontend
else
  echo "Usage: $0 [--install]"
  echo "  --install   Run the full installation process after checks."
  echo "  (no args)   Run checks only."
  exit 1
fi

# --- Final Summary ---
log "Setup Script Finished!"
echo ""
echo "Project URLs:"
echo "  WordPress: ${WP_URL}"
echo "  Drupal:    ${DRUPAL_URL}"
echo "  Frontend:  ${FRONTEND_URL}"
echo ""
echo "Ensure you have at least one published post in WordPress and one published 'article' node in Drupal for the frontend demo to display data."
echo ""

exit 0