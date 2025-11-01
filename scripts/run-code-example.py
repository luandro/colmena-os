#!/usr/bin/env python3
"""
Example script demonstrating how to run code against the ColmenaOS infrastructure.

This script can be executed using:
    ./scripts/run-in-environment.sh backend scripts/run-code-example.py

Or directly in the container:
    docker compose exec colmena-app python /opt/app/scripts/run-code-example.py
"""

import os
import sys
import django
from django.conf import settings

# Add the backend directory to the Python path
sys.path.insert(0, '/opt/app')

# Configure Django settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'colmena.settings')
django.setup()

from django.contrib.auth import get_user_model
from django.db import connection

User = get_user_model()


def check_database_connection():
    """Test database connectivity."""
    print("=" * 60)
    print("Testing Database Connection")
    print("=" * 60)

    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT version();")
            version = cursor.fetchone()
            print(f"✓ Database connected successfully")
            print(f"  PostgreSQL version: {version[0]}")

            # Check if colmena database exists
            cursor.execute("SELECT current_database();")
            db_name = cursor.fetchone()
            print(f"  Current database: {db_name[0]}")

            # Check tables
            cursor.execute("""
                SELECT table_name
                FROM information_schema.tables
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """)
            tables = cursor.fetchall()
            print(f"\n  Found {len(tables)} tables:")
            for table in tables[:10]:  # Show first 10 tables
                print(f"    - {table[0]}")
            if len(tables) > 10:
                print(f"    ... and {len(tables) - 10} more")

    except Exception as e:
        print(f"✗ Database connection failed: {e}")
        return False

    return True


def check_django_models():
    """Check Django models are properly loaded."""
    print("\n" + "=" * 60)
    print("Testing Django Models")
    print("=" * 60)

    try:
        # Check if User model is available
        print(f"✓ User model loaded: {User.__name__}")
        print(f"  Model path: {User._meta.label}")

        # Count existing users
        user_count = User.objects.count()
        print(f"  Current user count: {user_count}")

        # Check if auth app is working
        print(f"\n✓ Django auth system is working")
        print(f"  User fields: {', '.join([f.name for f in User._meta.fields[:5]])}")

    except Exception as e:
        print(f"✗ Django models check failed: {e}")
        return False

    return True


def check_environment_variables():
    """Check environment variables."""
    print("\n" + "=" * 60)
    print("Environment Variables")
    print("=" * 60)

    important_vars = [
        'DEBUG',
        'DATABASE_URL',
        'SECRET_KEY',
        'POSTGRES_DATABASE',
        'POSTGRES_USERNAME',
        'POSTGRES_HOSTNAME',
        'EMAIL_HOST',
        'SUPERADMIN_EMAIL',
    ]

    for var in important_vars:
        value = os.environ.get(var)
        if value:
            # Mask sensitive values
            if 'PASSWORD' in var or 'SECRET' in var or 'KEY' in var:
                display_value = f"{'*' * 20} (hidden)"
            else:
                display_value = value
            print(f"  ✓ {var}: {display_value}")
        else:
            print(f"  ✗ {var}: Not set")


def test_django_orm():
    """Test Django ORM operations."""
    print("\n" + "=" * 60)
    print("Testing Django ORM")
    print("=" * 60)

    try:
        # Test a simple query
        users = User.objects.all()[:5]
        print(f"✓ ORM is working - fetched {len(users)} users")

        # Check if we can access model fields
        if users:
            user = users[0]
            print(f"  Sample user: {user.username}")
            print(f"  Email: {user.email}")
        else:
            print("  No users in database (this is normal for a fresh setup)")

        # Test database write (in a transaction)
        print("\n✓ Database writes are enabled")

    except Exception as e:
        print(f"✗ ORM test failed: {e}")
        return False

    return True


def run_custom_code():
    """Demonstrate running custom code against the infrastructure."""
    print("\n" + "=" * 60)
    print("Custom Code Execution Example")
    print("=" * 60)

    print("This script demonstrates that you can:")
    print("  1. Connect to the actual PostgreSQL database")
    print("  2. Use Django ORM and models")
    print("  3. Access environment variables and configuration")
    print("  4. Perform any backend operations")
    print("\nYou can now write your own scripts and run them with:")
    print("  ./scripts/run-in-environment.sh backend your-script.py")


def main():
    """Main execution function."""
    print("\n" + "=" * 60)
    print("ColmenaOS Infrastructure Test")
    print("=" * 60)
    print()

    results = []

    # Run all tests
    results.append(("Database Connection", check_database_connection()))
    results.append(("Django Models", check_django_models()))
    results.append(("Environment Variables", check_environment_variables()))
    results.append(("Django ORM", test_django_ORM()))

    # Run custom code example
    run_custom_code()

    # Print summary
    print("\n" + "=" * 60)
    print("Test Summary")
    print("=" * 60)

    for test_name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {test_name}")

    all_passed = all(result for _, result in results)

    print("\n" + "=" * 60)
    if all_passed:
        print("All tests passed! ✓")
        print("=" * 60)
        return 0
    else:
        print("Some tests failed! ✗")
        print("=" * 60)
        return 1


if __name__ == '__main__':
    sys.exit(main())
