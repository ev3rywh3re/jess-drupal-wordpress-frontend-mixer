# Jess's WordPress Drupal Frontend Mixer

A local web development environment using DDEV to run interconnected WordPress (Bedrock), Drupal, and JavaScript Frontend sites.

This project provides the structure and instructions to set up three distinct websites, each managed as a separate DDEV project. This allows them to run concurrently and communicate on your local machine via DDEV's network. Composer is used for dependency management in the WordPress and Drupal sites.

*   **WordPress Site:** Uses the [Roots Bedrock](https://roots.io/bedrock/) boilerplate for a modern development workflow.
*   **Drupal Site:** Uses the standard `drupal/recommended-project` Composer template.
*   **Frontend Site:** A placeholder for a JavaScript framework/library (Vue, Svelte, React, etc.), served statically by DDEV after being built.

The main repository (this one) contains  the setup instructions (README.md) and git .gitignore files along with a setup.sh script. 

The actual code for the WordPress, Drupal, and Frontend sites resides within their respective subdirectories, which are ignored by Git in *this* repository. Please note this if you want to use this for your own projects.

## Prerequisites

Before you begin, ensure you have the following installed and configured:

### A. Docker Environment

You need a working Docker environment that DDEV can use. The setup script will check for a running Docker daemon.

*   **DDEV-Compatible Docker Provider:** You need a working Docker environment that DDEV can use. Common options include:
    *   OrbStack (macOS)
    *   Docker Desktop (macOS, Windows, Linux)
    *   Colima (macOS, Linux)
    *   Rancher Desktop (macOS, Windows, Linux - ensure dockerd/moby runtime is selected)
    *   Linux native Docker installation.
    *   Verify your Docker provider is running and accessible: `docker info` or `docker context ls` (check the current context). DDEV typically auto-detects the active provider.
*   **DDEV:** Installed (e.g., `brew install ddev/ddev/ddev`). Verify with `ddev version`.
*   **Composer:** Installed globally (e.g., `brew install composer`). Verify with `composer --version`.
*   **Node.js & npm (or yarn/pnpm):** Installed (e.g., `brew install node`) for the frontend site build process. Verify with `node -v` and `npm -v`.
*   **(Optional but helpful) jq:** A command-line JSON processor, useful for extracting info from `ddev describe`. (e.g., `brew install jq`).

#### On macOS

**OrbStack** is highly recommended for its speed and low resource usage.

```bash
# Install OrbStack using Homebrew
brew install --cask orbstack

# After installation, launch the OrbStack application.
```

Alternatively, you can use Docker Desktop.

#### On Fedora Linux

Follow these steps to install Docker Engine and grant your user permission to run it.

1.  **Set up Docker's repository:**
    ```bash
    sudo dnf -y install dnf-plugins-core
    sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
    ```

2.  **Install Docker Engine:**
    ```bash
    sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ```

3.  **Start and enable the Docker service:**
    ```bash
    sudo systemctl start docker
    sudo systemctl enable docker
    ```

4.  **Add your user to the `docker` group (CRITICAL):** This allows you to run Docker commands without `sudo`.
    ```bash
    sudo usermod -aG docker $USER
    ```
    **You MUST log out and log back in for this change to take effect.** You can verify it worked by running `docker ps` in a new terminal session; it should execute without a permission error.

### B. Core Development Tools

#### On macOS (using Homebrew)

```bash
brew install ddev/ddev/ddev
brew install composer
brew install node
brew install jq # Optional but recommended
```

#### On Fedora Linux

```bash
# Install DDEV (official script)
curl -fsSL https://raw.githubusercontent.com/ddev/ddev/master/scripts/install_ddev.sh | bash

# Install other tools using dnf
sudo dnf install composer nodejs jq # For Node.js, you may want to use a specific module stream
```

## Project Structure

Clone this repository. The setup process will populate the subdirectories.

```text
jess-drupal-wordpress-frontend-mixer/
├── .gitignore      # Instructs Git to ignore sub-project contents
├── README.md       # This file
├── wordpress/      # WordPress (Bedrock) DDEV Project (Created during setup)
│   ├── .ddev/      # DDEV config for WordPress site
│   ├── web/        # Bedrock's docroot (WP core, app)
│   ├── config/     # Bedrock config files
│   ├── vendor/     # Composer dependencies
│   ├── composer.json
│   └── .env        # Bedrock environment variables
├── drupal/         # Drupal DDEV Project (Created during setup)
│   ├── .ddev/      # DDEV config for Drupal site
│   ├── web/        # Drupal's docroot
│   ├── vendor/     # Composer dependencies
│   └── composer.json
└── frontend/       # Frontend JS DDEV Project (Created during setup)
    ├── .ddev/      # DDEV config for Frontend site
    ├── dist/       # Example build output directory (docroot)
    ├── src/        # Example source code directory
    ├── package.json
    └── ... (other JS project files)
└──── assets/         # Some base project starting files
```

## Setup Steps

The setup script (`setup.sh`) is provided as an attempt to automate this project setup, configuration, and functionality. 

Follow these steps sequentially to configure and launch each site. Run commands from the main `jess-drupal-wordpress-frontend-mixer` directory unless specified otherwise.

### 1. WordPress Site (Bedrock)

This setup uses the Bedrock boilerplate.

1.  **Create Bedrock Project:**
    *   Navigate into the main project directory (`jess-drupal-wordpress-frontend-mixer`).
    *   Run the Composer command to create the Bedrock project *inside* a new `wordpress` directory:
        ```bash
        composer create-project roots/bedrock wordpress
        ```
    *   Navigate into the newly created WordPress directory:
        ```bash
        cd wordpress
        ```

2.  **Configure DDEV:**
*   Initialize DDEV for this WordPress/Bedrock project. DDEV should detect the `wordpress` type and `web` docroot from Bedrock's `composer.json`.
    ```bash
    ddev config --project-name=wordpress-bedrock --project-type=wordpress --docroot=web
    ```
    *(You can choose a different `--project-name` if desired; this affects the URL)*

3.  **Configure Bedrock Environment (`.env`):**
    *   Bedrock uses a `.env` file. Copy the example:
        ```bash
        cp .env.example .env
        ```
    *   **Edit the `.env` file.** You need database credentials and the site URL. DDEV provides these. Run `ddev describe` in another terminal tab (while inside the `wordpress` directory) to see the details, or use the standard DDEV values:
        ```dotenv
        # Find and update these lines in .env:

        DB_NAME='db'
        DB_USER='db'
        DB_PASSWORD='db'
        DB_HOST='db' # DDEV's database service hostname is 'db'

        # Set WP_HOME to your DDEV project URL (check 'ddev describe' output)
        # It will likely be https://wordpress-bedrock.ddev.site if you used the name above
        WP_HOME='https://wordpress-bedrock.ddev.site'

        # WP_SITEURL is typically WP_HOME + /wp for Bedrock
        WP_SITEURL="${WP_HOME}/wp"

        # Generate unique salts using the Roots generator: https://roots.io/salts.html
        # Replace the 'generateme' placeholders below with the generated salts
        AUTH_KEY='generateme'
        SECURE_AUTH_KEY='generateme'
        LOGGED_IN_KEY='generateme'
        NONCE_KEY='generateme'
        AUTH_SALT='generateme'
        SECURE_AUTH_SALT='generateme'
        LOGGED_IN_SALT='generateme'
        NONCE_SALT='generateme'
        ```
    *   **CRITICAL:** Go to https://roots.io/salts.html, copy the generated salts, and paste them into your `.env` file, replacing the `generateme` placeholders.

4.  **Start DDEV:**
    *   Make sure you are still inside the `wordpress` directory.
    * Start the DDEV environment:
    ```bash
    ddev start
    ```
    * Note the primary URL provided (e.g., `https://wordpress-bedrock.ddev.site`).

5.  **Install WordPress Core:**
    *   Use WP-CLI via DDEV to perform the installation. **Crucially, specify both the `--path` and `--url` for Bedrock compatibility.**
    ```bash
    # Explicitly provide the path and URL for Bedrock compatibility
    # Replace 'https://wordpress-bedrock.ddev.site' if your project URL is different
    ddev wp --path=web/wp core install --url='https://wordpress-bedrock.ddev.site' --title='My Bedrock Site' --admin_user=admin --admin_password=password --admin_email=admin@example.com
    ```
    *(Use strong credentials for any real project!)*
    *   You should now be able to access the WP Admin at `https://wordpress-bedrock.ddev.site/wp/wp-admin/`.

6.  **Manage Plugins/Themes (Composer - Recommended):**
    *   Bedrock is already configured for WPackagist.
    *   Require plugins/themes using Composer (run from the `wordpress` directory):
        ```bash
        # Example: ddev composer require wpackagist-plugin/jetpack
        # Example: ddev composer require wpackagist-theme/twentytwentyfour
        ```
    *   Activate them via the WP Admin interface or WP-CLI (remember the path):
        ```bash
        # Example: ddev wp --path=web/wp plugin activate jetpack
        # Example: ddev wp --path=web/wp theme activate twentytwentyfour
        ```

7.  **Return to Main Project Directory:**
    ```bash
    cd ..
    ```

### 2. Drupal Site

This uses the standard Composer-based Drupal setup.

1.  **Create Drupal Project:**
    *   From the main `jess-drupal-wordpress-frontend-mixer` directory, run:
        ```bash
        composer create-project drupal/recommended-project drupal --no-interaction
        ```
    *   Navigate into the new Drupal directory:
        ```bash
        cd drupal
        ```

2.  **Configure DDEV:**
    *   Initialize DDEV. It should detect `drupal10` (or your installed version) and the `web` docroot.
    ```bash
        ddev config --project-name=drupal-site --project-type=drupal10 --docroot=web
        ```
        *(Adjust `drupal10` if using Drupal 9 (`drupal9`) or 7 (`drupal7`). Change `--project-name` if desired.)*

3.  **Start DDEV:**
    *   Make sure you are inside the `drupal` directory.
        ```bash
        ddev start
        ```
    *   Note the URL (e.g., `https://drupal-site.ddev.site`).

4.  **Install Drupal:**
    *   **Option A (Browser):** Visit the project URL (`https://drupal-site.ddev.site`) and follow the graphical installation wizard. DDEV automatically provides the database connection details to Drupal.
    *   **Option B (Drush via DDEV):** Run from the `drupal` directory:
    
        ```bash
        #install Drush if needed
        ddev composer require drush/drush

        # install site
        ddev drush site:install standard --db-url=mysql://db:db@db/db --site-name="My Drupal Site" --account-name=admin --account-pass=password -y
        ```
        *(Use strong credentials!)*
    *   You should be able to access the Drupal site and log in.

5.  **Manage Modules/Themes (Composer - Standard):**
    *   Require modules/themes using Composer (run from the `drupal` directory):
        ```bash        # Example: ddev composer require drupal/admin_toolbar drupal/gin
        ```
    *   Enable them via the Drupal UI (`/admin/modules`) or Drush:
        ```bash
        # Example: ddev drush en admin_toolbar gin -y
        # Example: ddev drush config-set system.theme admin gin -y # Set Gin as admin theme
        ```

6.  **Return to Main Project Directory:**
    ```bash
    cd ..
    ```

### 3. Frontend Site (Vue/Svelte/React etc.)

This sets up DDEV to serve the *built static assets* of a JavaScript application.

1.  **Create Frontend Project Directory:**
    *   From the main `jess-drupal-wordpress-frontend-mixer` directory:
        ```bash
        mkdir frontend
        cd frontend
        ```

2.  **Initialize JS Project (Example using Vite + Vue):**
    *   Use your preferred tool (Vite, Create React App, SvelteKit init, etc.). This example uses Vite to create a Vue project *in the current directory* (`frontend`).
        ```bash
        # Example: Initialize a Vue project
        npm create vite@latest . -- --template vue
        # Or for Svelte: npm create vite@latest . -- --template svelte
        # Or for React: npm create vite@latest . -- --template react
        # Follow any prompts from the tool.

        # Install dependencies
        npm install
        ```

3.  **Build Static Assets:**
    *   Run the build command defined in your `package.json` (usually `npm run build`). This compiles your code and outputs static files (HTML, CSS, JS) typically into a `dist` or `build` directory.
        ```bash
        npm run build
        ```
    *   **Verify the output directory name.** Check your `vite.config.js` (or equivalent) and `package.json`. Let's assume it's `dist` for the next step.

4.  **Configure DDEV:**
    *   Initialize DDEV, telling it to serve the contents of your build output directory (`dist` in this example). We use `project-type=php` just to get a capable webserver (Nginx or Apache).
        ```bash
        # IMPORTANT: Replace 'dist' below if your build output directory has a different name!
        ddev config --project-name=frontend-app --project-type=php --docroot=dist --webserver-type=nginx-fpm
        ```
        *(Change `--project-name` if desired.)*

5.  **Start DDEV:**
    *   Make sure you are inside the `frontend` directory.
        ```bash
        ddev start
        ```
    *   Note the URL (e.g., `https://frontend-app.ddev.site`).

6.  **Development Workflow & Verification:**
    *   Visit the DDEV URL (`https://frontend-app.ddev.site`). You should see your *built* application.
    *   **Important:** DDEV serves the static files from your build directory (`dist`). If you change your frontend source code, you **must run `npm run build` again** for the changes to appear on the DDEV site.
    *   For a faster development experience with **hot-reloading**, you will typically run your framework's development server separately (e.g., `npm run dev` in the `frontend` directory). This usually starts a server on a different port (like `http://localhost:5173`) which you access directly in your browser during active development. The DDEV setup is primarily for serving the final build or testing integrations.

7.  **Return to Main Project Directory:**
    ```bash
    cd ..
    ```

## Usage and Management

*   **Navigate:** To work on a specific site, `cd` into its directory (`wordpress`, `drupal`, `frontend`).
*   **Start/Stop:**
    *   `ddev start`: Start the DDEV project for the site in the current directory.
    *   `ddev stop`: Stop the DDEV project for the site in the current directory.
    *   `ddev stop --all`: Stop all running DDEV projects on your machine.
*   **Access Sites:** Use the `.ddev.site` URLs provided by `ddev start` or `ddev describe` for each project.
    *   WordPress: `https://wordpress-bedrock.ddev.site` (or your chosen name)
    *   Drupal: `https://drupal-site.ddev.site` (or your chosen name)
    *   Frontend: `https://frontend-app.ddev.site` (or your chosen name)
*   **Common Tools (run from within the respective project directory):**
    *   `ddev ssh`: SSH into the web container for that project.
    *   `ddev composer ...`: Run Composer commands within the container.
    *   `ddev wp ...`: Run WP-CLI commands (in `wordpress` directory - remember `--path=web/wp` for most commands).
    *   `ddev drush ...`: Run Drush commands (in `drupal` directory).
    *   `ddev logs`: View container logs for the project.
    *   `ddev list`: Show status of all DDEV projects.
    *   `ddev describe`: Show detailed information about the project in the current directory.

## Site Interaction

*   **Browser:** You can open all site URLs in your browser simultaneously.
*   **Backend-to-Backend:** Code within one site (e.g., PHP in WordPress) can make HTTP requests (e.g., using cURL or Guzzle) to another site using its full DDEV URL (e.g., `https://drupal-site.ddev.site`). DDEV handles the internal network routing between containers.
*   **Frontend-to-Backend (API Calls):** Your JavaScript frontend app (running in the browser, loaded from `https://frontend-app.ddev.site`) can make API calls (e.g., using `fetch` or `axios`) to the WordPress or Drupal sites using their full DDEV URLs (e.g., `https://wordpress-bedrock.ddev.site/wp-json/wp/v2/posts` or `https://drupal-site.ddev.site/jsonapi`).
    *   **CORS:** You will almost certainly need to configure **Cross-Origin Resource Sharing (CORS)** headers on the WordPress and/or Drupal sites. This tells the browser that it's okay for JavaScript loaded from `frontend-app.ddev.site` to request resources from `wordpress-bedrock.ddev.site` or `drupal-site.ddev.site`.
        *   **WordPress:** Look into adding headers via your theme's `functions.php`, a custom plugin, or dedicated CORS plugins. For the REST API, filters like `rest_pre_serve_request` or `rest_send_cors_headers` can be used.
        *   **Drupal:** Configure `cors.config` in your site's configuration (often via `services.yml` or the `cors` module) or use a dedicated CORS module like Drupal CORS UI.

## Customization

*   **Frontend Framework:** Replace the example `npm create vite...` command in the Frontend setup with the initialization command for your chosen framework/library. Remember to update the `ddev config --docroot` if the build output directory name is different from `dist`.
*   **Project Names:** Feel free to change the `--project-name` arguments during `ddev config` for different DDEV hostnames. Just ensure you update the URLs accordingly (e.g., in Bedrock's `.env` file and the `--url` parameter during WP install).
