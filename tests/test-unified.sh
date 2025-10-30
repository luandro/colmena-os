#!/bin/bash

# Test script for unified ColmenaOS Docker setup

echo "🧪 Testing Unified ColmenaOS Docker Setup"
echo "========================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

echo "✅ Docker is running"

# Build the unified image
echo "🏗️  Building unified Docker image..."
if docker build -t colmena-app-test .; then
    echo "✅ Unified image built successfully"
else
    echo "❌ Failed to build unified image"
    exit 1
fi

# Test that the image has both frontend and backend
echo "🔍 Inspecting built image..."
if docker run --rm colmena-app-test ls -la /app/backend/ 2>/dev/null | grep -q "manage.py"; then
    echo "✅ Backend files present in image"
else
    echo "❌ Backend files missing from image"
    exit 1
fi

if docker run --rm colmena-app-test ls -la /app/frontend/dist/ 2>/dev/null | grep -q "index.html"; then
    echo "✅ Frontend build files present in image"
else
    echo "❌ Frontend build files missing from image"
    exit 1
fi

# Check that supervisor is installed
if docker run --rm colmena-app-test which supervisord > /dev/null 2>&1; then
    echo "✅ Supervisor is installed"
else
    echo "❌ Supervisor not found in image"
    exit 1
fi

# Check that nginx is installed
if docker run --rm colmena-app-test which nginx > /dev/null 2>&1; then
    echo "✅ Nginx is installed"
else
    echo "❌ Nginx not found in image"
    exit 1
fi

echo ""
echo "🎉 All tests passed! Unified Docker setup is ready."
echo ""
echo "Next steps:"
echo "1. Run: docker-compose up -d"
echo "2. Access frontend: http://localhost:80"
echo "3. Access backend API: http://localhost:8000"
echo "4. Check logs: docker-compose logs colmena-app"