#!/bin/bash
set -e # Exit on error

APP_DIR="/opt/quiz_project"

echo "Starting cleanup process..."

# Stop the application if it's running
if [ -f "$APP_DIR/_build/prod/rel/quiz_project/bin/quiz_project" ]; then
  echo "Stopping existing application..."
  "$APP_DIR/_build/prod/rel/quiz_project/bin/quiz_project" stop || true
fi

# Make sure the directory exists
echo "Ensuring directory exists..."
mkdir -p "$APP_DIR"

# Clean up thoroughly
echo "Cleaning up old deployment..."
rm -rf "$APP_DIR"/*
rm -rf "$APP_DIR"/.[!.]* # Remove hidden files too

# Reset permissions
echo "Setting up permissions..."
chown -R ubuntu:ubuntu "$APP_DIR"
chmod -R 755 "$APP_DIR"

echo "Before install script completed successfully"
exit 0
