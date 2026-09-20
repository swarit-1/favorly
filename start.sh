#!/bin/bash

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$REPO_ROOT/backend"
MOBILE_DIR="$REPO_ROOT/favorly_mobile"

echo "🚀 Starting Favorly (Backend + Frontend)..."
echo ""

# Start Backend
echo "📡 Starting backend server..."
cd "$BACKEND_DIR"

# Start backend in background
python3 app.py > /tmp/favorly_backend.log 2>&1 &
BACKEND_PID=$!
echo "✅ Backend started (PID: $BACKEND_PID)"

# Wait for backend to initialize
sleep 3

# Check if backend is running
if ! kill -0 $BACKEND_PID 2>/dev/null; then
    echo "❌ Backend failed to start. Check logs:"
    cat /tmp/favorly_backend.log
    exit 1
fi

# Check backend health
if curl -s http://localhost:8000/health > /dev/null 2>&1; then
    echo "✅ Backend is healthy"
else
    echo "⚠️  Backend may still be starting..."
fi

echo ""

# Start Frontend
echo "📱 Starting Flutter app..."
cd "$MOBILE_DIR"

# Get Mac's local IP for iOS device connectivity
MAC_IP=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")
echo "📍 API endpoint: http://$MAC_IP:8000"
echo ""

flutter run --dart-define=API_BASE_URL=http://$MAC_IP:8000 &
FLUTTER_PID=$!

echo ""
echo "═══════════════════════════════════════════"
echo "✅ Both services running!"
echo "═══════════════════════════════════════════"
echo "Backend:  http://localhost:8000"
echo "Docs:     http://localhost:8000/docs"
echo "Vision:   http://localhost:8000/vision/health"
echo "Logs:     tail -f /tmp/favorly_backend.log"
echo ""
echo "To stop all services: Ctrl+C (multiple times if needed)"
echo "═══════════════════════════════════════════"
echo ""

# Wait for both processes
wait
