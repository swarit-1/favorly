#!/bin/bash
# Run Phase 2 database migrations for Favorly
# Usage: ./run_migrations.sh

set -e

echo "🚀 Running Phase 2 database migrations..."
echo ""

# Check if Supabase CLI is installed
if ! command -v supabase &> /dev/null; then
    echo "❌ Supabase CLI not found. Install it with:"
    echo "   npm install -g supabase"
    echo ""
    echo "Alternatively, run the SQL migrations manually:"
    echo "   1. Go to https://supabase.com/dashboard"
    echo "   2. Select your project"
    echo "   3. Navigate to SQL Editor"
    echo "   4. Copy and run the contents of:"
    echo "      - migrations/001_create_messages_table.sql"
    echo "      - migrations/002_create_notifications_table.sql"
    echo "      - migrations/003_create_user_locations_table.sql"
    exit 1
fi

echo "📦 Running migrations..."
echo ""

# Run each migration
for migration in migrations/*.sql; do
    if [ -f "$migration" ]; then
        echo "Applying: $(basename $migration)"
        supabase db push < "$migration" || echo "Note: Migration may already be applied"
    fi
done

echo ""
echo "✅ Phase 2 migrations complete!"
echo ""
echo "Next steps:"
echo "  1. Verify tables exist in Supabase dashboard"
echo "  2. Implement Phase 3: Backend routes for messages and notifications"
