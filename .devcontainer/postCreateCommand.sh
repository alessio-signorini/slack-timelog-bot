#!/bin/bash
set -e

echo "Installing Fly.io CLI..."
curl -L https://fly.io/install.sh | sh

echo "Installing Ruby gems..."
bundle install

echo "Setting up .env file..."
cp .env.example .env 2>/dev/null || true

echo "Creating data directory..."
mkdir -p /data

echo "Dev container setup complete!"
