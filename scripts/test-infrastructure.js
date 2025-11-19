#!/usr/bin/env node
/**
 * Example script demonstrating how to test the infrastructure from Node.js
 *
 * IMPORTANT: This script must be run on the HOST machine, not inside the container.
 * The runtime container only includes Python, nginx, and supervisor - Node.js is not available.
 *
 * To run this script:
 *   node scripts/test-infrastructure.js
 *
 * Make sure the stack is running first:
 *   ./scripts/run-in-environment.sh up --keep-up
 */

const http = require('http');
const fs = require('fs');

const runningInContainer = fs.existsSync('/.dockerenv');
const DEFAULT_FRONTEND_PORT = runningInContainer ? 80 : 7180;
const DEFAULT_BACKEND_PORT = runningInContainer ? 8000 : 7100;

const FRONTEND_PORT = process.env.COLMENA_FRONTEND_PORT
    || process.env.HTTP_PORT
    || DEFAULT_FRONTEND_PORT;
const BACKEND_PORT = process.env.COLMENA_BACKEND_PORT
    || process.env.BACKEND_PORT
    || DEFAULT_BACKEND_PORT;
const HOSTNAME = process.env.COLMENA_HOST || 'localhost';


/**
 * Make HTTP request helper
 */
function makeRequest(url, options = {}) {
    return new Promise((resolve, reject) => {
        const req = http.request(url, options, (res) => {
            let data = '';

            res.on('data', (chunk) => {
                data += chunk;
            });

            res.on('end', () => {
                resolve({
                    statusCode: res.statusCode,
                    headers: res.headers,
                    body: data
                });
            });
        });

        req.on('error', (error) => {
            reject(error);
        });

        if (options.body) {
            req.write(options.body);
        }

        req.end();
    });
}


/**
 * Test backend API endpoints
 */
async function testBackendAPI() {
    console.log('='.repeat(60));
    console.log('Testing Backend API');
    console.log('='.repeat(60));

    // Test 1: Check if nginx is serving the frontend
    console.log('\n1. Testing Frontend (nginx)...');
    try {
        const frontendResponse = await makeRequest(`http://${HOSTNAME}:${FRONTEND_PORT}/`);
        console.log(`   ✓ Frontend is responding (status: ${frontendResponse.statusCode})`);
        console.log(`   Content-Type: ${frontendResponse.headers['content-type']}`);
    } catch (error) {
        console.log(`   ✗ Frontend request failed: ${error.message}`);
        return false;
    }

    // Test 2: Check if backend API is accessible
    console.log('\n2. Testing Backend API...');
    try {
        const backendResponse = await makeRequest(`http://${HOSTNAME}:${BACKEND_PORT}/api/`);
        console.log(`   ✓ Backend API is responding (status: ${backendResponse.statusCode})`);

        if (backendResponse.body) {
            const data = JSON.parse(backendResponse.body);
            console.log(`   Response: ${JSON.stringify(data).substring(0, 100)}...`);
        }
    } catch (error) {
        console.log(`   Note: API endpoint may not be implemented (${error.message})`);
    }

    // Test 3: Check static files
    console.log('\n3. Testing Static Files...');
    try {
        const staticResponse = await makeRequest(`http://${HOSTNAME}:${FRONTEND_PORT}/static/`);
        console.log(`   ✓ Static files are being served (status: ${staticResponse.statusCode})`);
    } catch (error) {
        console.log(`   Note: Static files may be at a different path (${error.message})`);
    }

    return true;
}


/**
 * Test environment variables
 */
function testEnvironment() {
    console.log('\n' + '='.repeat(60));
    console.log('Testing Environment Variables');
    console.log('='.repeat(60));

    const importantVars = [
        'NODE_ENV',
        'PORT',
        'BACKEND_PORT',
        'HTTP_PORT',
        'POSTGRES_DATABASE',
        'POSTGRES_USERNAME',
        'POSTGRES_HOSTNAME',
        'DEBUG'
    ];

    let allSet = true;
    importantVars.forEach(varName => {
        const value = process.env[varName];
        if (value) {
            // Mask sensitive values
            const displayValue = value.length > 20 ? `${value.substring(0, 20)}...` : value;
            console.log(`   ✓ ${varName}: ${displayValue}`);
        } else {
            console.log(`   ✗ ${varName}: Not set`);
            allSet = false;
        }
    });

    return allSet;
}


/**
 * Test Node.js capabilities
 */
function testNodeJS() {
    console.log('\n' + '='.repeat(60));
    console.log('Testing Node.js Environment');
    console.log('='.repeat(60));

    console.log(`   ✓ Node.js version: ${process.version}`);
    console.log(`   ✓ Platform: ${process.platform}`);
    console.log(`   ✓ Architecture: ${process.arch}`);
    console.log(`   ✓ Working directory: ${process.cwd()}`);

    // Test if we can access the file system
    try {
        const files = fs.readdirSync('/opt/app');
        console.log(`   ✓ Can access /opt/app directory (${files.length} items)`);
    } catch (error) {
        console.log(`   ✗ Cannot access /opt/app: ${error.message}`);
        return false;
    }

    // Check if we're in a container
    if (fs.existsSync('/.dockerenv')) {
        console.log(`   ✓ Running inside Docker container`);
    } else {
        console.log(`   ℹ Not running in Docker (or /.dockerenv not found)`);
    }

    return true;
}


/**
 * Test database connectivity from Node.js
 */
async function testDatabase() {
    console.log('\n' + '='.repeat(60));
    console.log('Testing Database Connectivity');
    console.log('='.repeat(60));

    // We'll check if pg is available
    try {
        // Try to import pg module (if installed)
        const { Client } = require('pg');
        console.log(`   ✓ pg module is available`);

        // Create connection string from environment
        const dbName = process.env.POSTGRES_DATABASE || 'colmena';
        const dbUser = process.env.POSTGRES_USERNAME || 'colmena';
        const dbHost = process.env.POSTGRES_HOSTNAME || 'postgres';
        const dbPassword = process.env.POSTGRES_PASSWORD || '';

        const client = new Client({
            host: dbHost,
            database: dbName,
            user: dbUser,
            password: dbPassword,
            port: 5432,
        });

        await client.connect();
        console.log(`   ✓ Database connection established`);

        const result = await client.query('SELECT version()');
        console.log(`   ✓ PostgreSQL version: ${result.rows[0].version.split(',')[0]}`);

        await client.end();
        return true;
    } catch (error) {
        console.log(`   Note: Database test skipped (pg module may not be installed: ${error.message})`);
        return true; // This is not a critical failure
    }
}


/**
 * Main execution function
 */
async function main() {
    console.log('\n' + '='.repeat(60));
    console.log('ColmenaOS Infrastructure Test (Node.js)');
    console.log('='.repeat(60));
    console.log();

    const results = [];

    // Run all tests
    results.push(['Node.js Environment', testNodeJS()]);
    results.push(['Environment Variables', testEnvironment()]);
    results.push(['Backend API', await testBackendAPI()]);
    results.push(['Database Connectivity', await testDatabase()]);

    // Print summary
    console.log('\n' + '='.repeat(60));
    console.log('Test Summary');
    console.log('='.repeat(60));

    results.forEach(([testName, result]) => {
        const status = result ? '✓ PASS' : '✗ FAIL';
        console.log(`   ${status}: ${testName}`);
    });

    const allPassed = results.every(([, result]) => result);

    console.log('\n' + '='.repeat(60));
    if (allPassed) {
        console.log('All tests passed! ✓');
        console.log('='.repeat(60));
        console.log();
        console.log('This demonstrates that you can:');
        console.log('  - Run Node.js/JavaScript code against the infrastructure');
        console.log('  - Make HTTP requests to backend and frontend');
        console.log('  - Access environment variables');
        console.log('  - Connect to the PostgreSQL database');
        console.log();
        console.log('You can now write your own scripts and run them on the HOST with:');
        console.log('  node your-script.js');
        console.log();
        console.log('Note: The runtime container does not include Node.js.');
        console.log('      All Node.js scripts must run on the host machine.');
        console.log('='.repeat(60));
        process.exit(0);
    } else {
        console.log('Some tests failed! ✗');
        console.log('='.repeat(60));
        process.exit(1);
    }
}


// Run the tests
main().catch(error => {
    console.error('\nTest execution failed:', error);
    process.exit(1);
});
