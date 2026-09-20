#!/bin/bash
# Quick backend startup script

cd "$(dirname "$0")/backend" || exit 1

echo "🚀 Favorly Backend Startup"
echo "========================="
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo "❌ .env file not found in backend/"
    echo "Create it with your Supabase and OpenAI credentials"
    exit 1
fi

# Check required environment variables
check_env() {
    if ! grep -q "^$1=" .env; then
        echo "❌ Missing $1 in .env"
        return 1
    fi
    return 0
}

echo "✓ Checking environment variables..."
all_good=true
check_env "SUPABASE_URL" || all_good=false
check_env "SUPABASE_SERVICE_ROLE_KEY" || all_good=false
check_env "OPENAI_API_KEY" || all_good=false
check_env "ENVIRONMENT" || all_good=false

if [ "$all_good" = false ]; then
    echo ""
    echo "❌ Missing required environment variables in .env"
    exit 1
fi

echo "✓ Environment variables OK"
echo ""

# Print current IP
echo "📡 Network Information:"
IP=$(ipconfig getifaddr en0)
if [ -z "$IP" ]; then
    IP=$(ifconfig | grep "inet " | grep -v 127.0.0.1 | head -1 | awk '{print $2}')
fi
echo "   Mac IP: $IP"
echo "   Use this for iOS: http://$IP:8000"
echo ""

# Try to activate venv if it exists
if [ -d "venv" ]; then
    echo "✓ Virtual environment found"
    source venv/bin/activate
    echo "✓ Virtual environment activated"
elif [ -d ".venv" ]; then
    echo "✓ Virtual environment found"
    source .venv/bin/activate
    echo "✓ Virtual environment activated"
else
    echo "⚠️  No virtual environment found"
fi

echo ""
echo "🎯 Starting backend on http://localhost:8000"
echo "   iOS should connect to: http://$IP:8000"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start the server
python -m uvicorn app:app --reload --port 8000 --host 0.0.0.0
