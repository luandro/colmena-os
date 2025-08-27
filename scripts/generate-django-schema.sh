#!/bin/bash

# Script to generate the Django backend OpenAPI schema
# This script starts the backend service, fetches the schema, and saves it to the correct location

set -e

echo "🔄 Generating Django backend OpenAPI schema..."

# Navigate to project root
cd "$(dirname "$0")/.."

# Check if .env file exists, if not create from example
if [ ! -f .env ]; then
    echo "📋 Creating .env file from .env.example..."
    cp .env.example .env
fi

# Generate a secret key if not set
if ! grep -q "^SECRET_KEY=" .env || [ -z "$(grep '^SECRET_KEY=' .env | cut -d'=' -f2)" ]; then
    echo "🔐 Generating SECRET_KEY..."
    SECRET_KEY=$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')
    sed -i "s/^SECRET_KEY=.*/SECRET_KEY=$SECRET_KEY/" .env
fi

# Set required environment variables if not set
if ! grep -q "^POSTGRES_PASSWORD=" .env || [ -z "$(grep '^POSTGRES_PASSWORD=' .env | cut -d'=' -f2)" ]; then
    echo "🔧 Setting default POSTGRES_PASSWORD..."
    # Generate a random password instead of hardcoding
    POSTGRES_PASSWORD=$(openssl rand -base64 12 | tr -d "=+/" | cut -c1-12)
    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> .env
fi

# Fix docker-compose.yml volume issue temporarily
echo "🔧 Fixing docker-compose volume configuration..."
cp docker-compose.yml docker-compose.yml.backup
sed -i '/nextcloud_config:/d' docker-compose.yml
sed -i 's/- nextcloud_config:\/var\/www\/html\/config/#- nextcloud_config:\/var\/www\/html\/config/' docker-compose.yml

# Start required services (postgres first, then backend)
echo "🐳 Starting PostgreSQL..."
docker compose up -d postgres

echo "⏳ Waiting for PostgreSQL to be ready..."
sleep 10

echo "🐳 Starting Django backend..."
docker compose up -d backend

echo "⏳ Waiting for Django backend to be ready..."
sleep 15

# Fetch the schema from the running Django backend
echo "📥 Fetching Django OpenAPI schema..."
SCHEMA_URL="http://localhost:8000/api/schema/"
OUTPUT_FILE="backend/schema.json"

if curl -f -s "$SCHEMA_URL" -o "$OUTPUT_FILE"; then
    echo "✅ Schema successfully saved to $OUTPUT_FILE"
    
    # Also copy to frontend location if it exists
    if [ -d "frontend/src/api" ]; then
        cp "$OUTPUT_FILE" "frontend/src/api/schema.json"
        echo "✅ Schema also copied to frontend/src/api/schema.json"
    fi
    
    # Display basic info about the schema
    echo "📊 Schema information:"
    if command -v jq >/dev/null 2>&1; then
        jq -r '.info.title + " v" + .info.version' "$OUTPUT_FILE" 2>/dev/null || echo "Schema file created (jq not available for details)"
        echo "📍 Available endpoints: $(jq '.paths | keys | length' "$OUTPUT_FILE" 2>/dev/null || echo 'N/A')"
    else
        echo "Schema file created successfully"
    fi
else
    echo "❌ Failed to fetch schema from $SCHEMA_URL"
    echo "Backend logs:"
    docker compose logs backend --tail=20
    exit 1
fi

# Restore original docker-compose.yml
echo "🔄 Restoring original docker-compose.yml..."
mv docker-compose.yml.backup docker-compose.yml

# Stop services
echo "🛑 Stopping services..."
docker compose down

echo "🎉 Django schema generation completed!"
echo "📁 Schema file location: $OUTPUT_FILE"