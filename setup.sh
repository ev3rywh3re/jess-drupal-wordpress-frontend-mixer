#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e
# Treat unset variables as an error when substituting.
set -u
# Prevent errors in pipelines from being masked.
set -o pipefail

# --- Configuration ---
# You can change these if you use different DDEV project names
WP_PROJECT_NAME="wordpress-bedrock"
DRUPAL_PROJECT_NAME="drupal-site"
FRONTEND_PROJECT_NAME="frontend-app"

# Derive URLs from project names (assumes default .ddev.site domain)
WP_URL="https://${WP_PROJECT_NAME}.ddev.site"
DRUPAL_URL="https://${DRUPAL_PROJECT_NAME}.ddev.site"
FRONTEND_URL="https://${FRONTEND_PROJECT_NAME}.ddev.site"

# --- Helper Functions ---
log() {
  echo "" # Add a newline for readability
  echo "--> $(date +'%T') | $*"
  echo "--------------------------------------------------"
}

# --- Check Prerequisites ---
log "Checking prerequisites..."
command -v ddev >/dev/null 2>&1 || { echo >&2 "DDEV not found. Aborting."; exit 1; }
command -v composer >/dev/null 2>&1 || { echo >&2 "Composer not found. Aborting."; exit 1; }
command -v node >/dev/null 2>&1 || { echo >&2 "Node.js not found. Aborting."; exit 1; }
command -v npm >/dev/null 2>&1 || { echo >&2 "npm not found. Aborting."; exit 1; }
log "Prerequisites found."

# --- WordPress Setup ---
log "Setting up WordPress (Bedrock)..."
if [ -d "wordpress" ]; then
  log "Warning: 'wordpress' directory already exists. Skipping creation."
else
  composer create-project roots/bedrock wordpress
fi
cd wordpress

log "Configuring DDEV for WordPress..."
ddev config --project-name="$WP_PROJECT_NAME" --project-type=wordpress --docroot=web

log "Configuring Bedrock .env file..."
if [ ! -f ".env" ]; then
    cp .env.example .env
    # Replace DB credentials and URLs using standard DDEV values
    # Using '|' as sed delimiter because URLs contain '/'
    sed -i.bak \
        -e "s|^DB_NAME=.*|DB_NAME='db'|" \
        -e "s|^DB_USER=.*|DB_USER='db'|" \
        -e "s|^DB_PASSWORD=.*|DB_PASSWORD='db'|" \
        -e "s|^DB_HOST=.*|DB_HOST='db'|" \
        -e "s|^WP_HOME=.*|WP_HOME='${WP_URL}'|" \
        -e "s|^WP_SITEURL=.*|WP_SITEURL='${WP_URL}/wp'|" \
        .env
    rm .env.bak # Remove backup file on success
    log "WordPress .env configured. CRITICAL: You MUST manually add unique salts!"
else
    log "WordPress .env file already exists. Skipping modification."
fi

log "Starting WordPress DDEV environment..."
ddev start

log "Installing WordPress core..."
# Use --path for Bedrock structure and --url as required
ddev wp --path=web/wp core install --url="$WP_URL" --title='My Bedrock Site' --admin_user=admin --admin_password=password --admin_email=admin@example.com

log "Configuring WordPress CORS (via mu-plugin)..."
mkdir -p web/app/mu-plugins
# Use cat with heredoc to create the CORS mu-plugin
cat << EOF > web/app/mu-plugins/ddev_cors_setup.php
<?php
/**
 * Plugin Name: DDEV CORS Setup
 * Description: Enables CORS headers for the REST API for the frontend DDEV site.
 */

add_action( 'rest_api_init', function() {
    remove_filter( 'rest_pre_serve_request', 'rest_send_cors_headers' );
    add_filter( 'rest_pre_serve_request', function( \$value ) {
        // Define your frontend origin (ensure this matches FRONTEND_URL)
        \$frontend_origin = '${FRONTEND_URL}';

        if ( isset( \$_SERVER['HTTP_ORIGIN'] ) && \$_SERVER['HTTP_ORIGIN'] === \$frontend_origin ) {
            header( 'Access-Control-Allow-Origin: ' . \$frontend_origin );
            header( 'Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS' );
            header( 'Access-Control-Allow-Credentials: true' );
            header( 'Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With, Accept' );

            // Handle OPTIONS preflight request
            if ( 'OPTIONS' === \$_SERVER['REQUEST_METHOD'] ) {
                status_header( 200 );
                exit();
            }
        }
        // Note: No fallback for other origins in this basic setup for security.
        return \$value;
    });
}, 15 );
EOF
log "WordPress CORS mu-plugin created."

cd ..
log "WordPress setup complete."

# --- Drupal Setup ---
log "Setting up Drupal..."
if [ -d "drupal" ]; then
  log "Warning: 'drupal' directory already exists. Skipping creation."
else
  composer create-project drupal/recommended-project drupal --no-interaction
fi
cd drupal

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
    log "Copying default.services.yml to services.yml..."
    cp "$DRUPAL_DEFAULT_SERVICES_YML" "$DRUPAL_SERVICES_YML"
fi

if [ -f "$DRUPAL_SERVICES_YML" ]; then
    # Check if cors.config seems to be already added (basic check)
    if ! grep -q "cors.config:" "$DRUPAL_SERVICES_YML"; then
        log "Appending CORS configuration to $DRUPAL_SERVICES_YML..."
        # Append CORS config block (ensure proper indentation)
        # WARNING: This is fragile. Assumes 'parameters:' exists and appends within it.
        # A better approach would use yq or similar tool.
        cat << EOF >> "$DRUPAL_SERVICES_YML"

  # Added by setup.sh for DDEV frontend interaction
  cors.config:
    enabled: true
    allowedOrigins: ['${FRONTEND_URL}']
    allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
    allowedHeaders: ['Content-Type', 'Authorization', 'X-Requested-With', 'Accept']
    exposedHeaders: false
    maxAge: 0
    supportsCredentials: false
EOF
    else
        log "CORS configuration (cors.config) seems to already exist in $DRUPAL_SERVICES_YML. Skipping append."
        log "Please manually verify CORS settings in $DRUPAL_SERVICES_YML allow origin: ${FRONTEND_URL}"
    fi
    log "Clearing Drupal cache..."
    ddev drush cr
else
    log "Warning: Could not find or create $DRUPAL_SERVICES_YML. Manual CORS configuration required."
fi

cd ..
log "Drupal setup complete."

# --- Frontend Setup ---
log "Setting up Frontend (Vue)..."
if [ -d "frontend" ]; then
  log "Warning: 'frontend' directory already exists. Skipping creation."
else
  mkdir frontend
fi
cd frontend

# Check if package.json exists to avoid re-initializing
if [ ! -f "package.json" ]; then
  log "Initializing Vue project using Vite..."
  # Pass template directly using '--' to avoid prompts
  npm create vite@latest . -- --template vue
  log "Installing npm dependencies..."
  npm install
else
  log "package.json found. Assuming project initialized. Running npm install..."
  npm install
fi

log "Building frontend assets..."
npm run build

log "Configuring DDEV for Frontend..."
# Use 'dist' as docroot, common for Vite builds
ddev config --project-name="$FRONTEND_PROJECT_NAME" --project-type=php --docroot=dist --webserver-type=nginx-fpm

log "Updating App.vue for demo..."
# Replace App.vue content using cat and heredoc
cat << EOF > src/App.vue
<script setup>
import { ref, onMounted } from 'vue';
import HelloWorld from './components/HelloWorld.vue';

// Reactive variables to hold post data and loading/error states
const wpPost = ref(null);
const drupalPost = ref(null);
const isLoading = ref(true);
const error = ref(null);

// DDEV URLs (ensure these match your project names)
const wpUrl = '${WP_URL}';
const drupalUrl = '${DRUPAL_URL}';
const frontendUrl = '${FRONTEND_URL}'; // For reference

// Function to fetch data
async function fetchData() {
  isLoading.value = true;
  error.value = null;
  wpPost.value = null;
  drupalPost.value = null;

  try {
    // Fetch latest post from WordPress REST API
    const wpResponse = await fetch(\`\${wpUrl}/wp-json/wp/v2/posts?per_page=1\`);
    if (!wpResponse.ok) {
      throw new Error(\`WordPress API Error: \${wpResponse.status} \${wpResponse.statusText}\`);
    }
    const wpData = await wpResponse.json();
    if (wpData && wpData.length > 0) {
      wpPost.value = wpData[0]; // Get the first post
    }

    // Fetch latest 'article' from Drupal JSON:API
    // Note: Assumes standard 'article' content type exists. Adjust if needed.
    const drupalResponse = await fetch(\`\${drupalUrl}/jsonapi/node/article?page[limit]=1&sort=-created\`); // Sort by newest
     if (!drupalResponse.ok) {
      throw new Error(\`Drupal API Error: \${drupalResponse.status} \${drupalResponse.statusText}\`);
    }
    const drupalData = await drupalResponse.json();
     // JSON:API data is nested under 'data'
    if (drupalData && drupalData.data && drupalData.data.length > 0) {
      drupalPost.value = drupalData.data[0]; // Get the first article
    }

  } catch (err) {
    console.error("Failed to fetch data:", err);
    error.value = err.message;
  } finally {
    isLoading.value = false;
  }
}

// Fetch data when the component is mounted
onMounted(() => {
  fetchData();
});
</script>

<template>
  <div>
    <a href="https://vite.dev" target="_blank">
      <img src="/vite.svg" class="logo" alt="Vite logo" />
    </a>
    <a href="https://vuejs.org/" target="_blank">
      <img src="./assets/vue.svg" class="logo vue" alt="Vue logo" />
    </a>
    <a :href="wpUrl" target="_blank">
      <img src="https://s.w.org/style/images/about/WordPress-logotype-simplified.png" class="logo wp" alt="WordPress logo" />
    </a>
     <a :href="drupalUrl" target="_blank">
      <img src="https://www.drupal.org/files/drupal_logo-blue.png" class="logo drupal" alt="Drupal logo" />
    </a>
  </div>

  <HelloWorld :msg="\`DDEV Multi-Site Demo (Frontend: \${frontendUrl})\`" />

  <div class="fetch-status">
    <button @click="fetchData" :disabled="isLoading">
      {{ isLoading ? 'Loading...' : 'Refresh Data' }}
    </button>
    <p v-if="error" class="error-message">Error fetching data: {{ error }}</p>
  </div>

  <div class="posts-container">
    <div class="post-column">
      <h2>Latest WordPress Post</h2>
      <div v-if="isLoading">Loading...</div>
      <div v-else-if="wpPost">
        <h3 v-html="wpPost.title?.rendered || 'Title not found'"></h3>
        <p>ID: {{ wpPost.id }}</p>
        <a :href="wpPost.link" target="_blank">View Post</a>
      </div>
      <div v-else-if="!error">No WordPress post found.</div>
    </div>

    <div class="post-column">
      <h2>Latest Drupal Article</h2>
       <div v-if="isLoading">Loading...</div>
      <div v-else-if="drupalPost">
        <!-- Drupal JSON:API title is often under attributes -->
        <h3>{{ drupalPost.attributes?.title || 'Title not found' }}</h3>
        <p>ID: {{ drupalPost.id }}</p>
        <!-- Basic link to the node page -->
        <a :href="\`\${drupalUrl}/node/\${drupalPost.attributes?.drupal_internal__nid}\`" target="_blank">View Article</a>
      </div>
      <div v-else-if="!error">No Drupal article found.</div>
    </div>
  </div>
</template>

<style scoped>
.logo {
  height: 4em; /* Smaller logos */
  padding: 1em;
  will-change: filter;
  transition: filter 300ms;
  vertical-align: middle;
}
.logo.wp {
  height: 2.5em; /* Adjust WP logo size */
}
.logo.drupal {
  height: 3.5em; /* Adjust Drupal logo size */
}
.logo:hover {
  filter: drop-shadow(0 0 1em #646cffaa);
}
.logo.vue:hover {
  filter: drop-shadow(0 0 1em #42b883aa);
}
.logo.wp:hover {
  filter: drop-shadow(0 0 1em #0073aa);
}
.logo.drupal:hover {
  filter: drop-shadow(0 0 1em #0678be);
}

.fetch-status {
  margin: 2em 0;
}
.error-message {
  color: red;
  font-weight: bold;
}

.posts-container {
  display: flex;
  justify-content: space-around;
  gap: 2em;
  margin-top: 2em;
  text-align: left;
}

.post-column {
  border: 1px solid #ccc;
  padding: 1.5em;
  border-radius: 8px;
  width: 45%;
  background-color: #f9f9f9;
}

.post-column h2 {
  margin-top: 0;
  border-bottom: 1px solid #eee;
  padding-bottom: 0.5em;
}
</style>
EOF
log "App.vue updated."

log "Starting Frontend DDEV environment..."
ddev start

cd ..
log "Frontend setup complete."

# --- Final Summary ---
log "Setup Script Finished!"
echo ""
echo "Project URLs:"
echo "  WordPress: ${WP_URL}"
echo "  Drupal:    ${DRUPAL_URL}"
echo "  Frontend:  ${FRONTEND_URL}"
echo ""
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo "!! CRITICAL: You MUST generate unique salts and add them to wordpress/.env  !!"
echo "!! Visit: https://roots.io/salts.html                                     !!"
echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
echo ""
echo "Ensure you have at least one published post in WordPress and one published"
echo "'article' node in Drupal for the frontend demo to display data."
echo ""

exit 0
