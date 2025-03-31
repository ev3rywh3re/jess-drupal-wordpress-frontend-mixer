# Jess's WordPress Drupal Frontend Mixer

A basic web development environment for using Wordpress and Drupal websites with a frontend library like Vue or NextJS.

Goal is to use DDEV to create a local network of sites that will be used for development. In this case it will be a WordPress, Drupal, and blank frontend site. In my use case I am using Orbstack for my Docker/virtualization and Composer for my package and installation management.

The current setup is like so

* frontend
* wordpress
* drupal

## Basic Wordpress setup

mkdir wordpress
cd wordpress
ddev config --project-type=wordpress --docroot=web --create-docroot
ddev start
ddev composer create-project roots/bedrock

Setup .env file as directed at https://ddev.readthedocs.io/en/stable/users/quickstart/#wordpress
Use ddev describe for DB info.

ddev wp core install --url='http://wordpress.ddev.site' --title='My WordPress site' --admin_user=admin --admin_password=admin --admin_email=admin@example.com

