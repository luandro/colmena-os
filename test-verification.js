/**
 * Simple test verification script for ColmenaOS services
 * Tests service accessibility without full Playwright setup
 */

const { exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

const config = {
  services: {
    'ColmenaOS Frontend': 'http://localhost:7180',
    'ColmenaOS Backend': 'http://localhost:7100', 
    'pgAdmin': 'http://localhost:7050',
    'Nextcloud': 'http://localhost:7103',
    'Mail Service UI': 'http://localhost:7080'
  }
};

async function testService(name, url) {
  try {
    const { stdout, stderr } = await execPromise(`curl -I ${url} 2>/dev/null || echo "FAILED"`);
    if (stdout.includes('HTTP/') && !stdout.includes('FAILED')) {
      const statusMatch = stdout.match(/HTTP\/[\d.]+\s+(\d+)/);
      const status = statusMatch ? statusMatch[1] : 'Unknown';
      console.log(`✅ ${name}: HTTP ${status} - ACCESSIBLE`);
      return true;
    } else {
      console.log(`❌ ${name}: CONNECTION REFUSED`);
      return false;
    }
  } catch (error) {
    console.log(`❌ ${name}: ERROR - ${error.message}`);
    return false;
  }
}

async function testDatabaseConnection() {
  try {
    const { stdout } = await execPromise(`docker exec colmena_postgres psql -U colmena -d colmena -c "SELECT 'Database OK' as status;" 2>/dev/null`);
    if (stdout.includes('Database OK')) {
      console.log(`✅ PostgreSQL Database: CONNECTED and RESPONSIVE`);
      return true;
    }
  } catch (error) {
    console.log(`❌ PostgreSQL Database: ${error.message}`);
    return false;
  }
}

async function checkDockerServices() {
  try {
    const { stdout } = await execPromise(`docker-compose -f docker-compose.local.yml ps --format table`);
    console.log('\n🐳 Docker Services Status:');
    console.log(stdout);
  } catch (error) {
    console.log(`❌ Docker Services Check: ${error.message}`);
  }
}

async function checkColmenaAppLogs() {
  try {
    console.log('\n📝 ColmenaOS App Recent Logs:');
    const { stdout } = await execPromise(`docker-compose -f docker-compose.local.yml logs colmena-app --tail=10`);
    console.log(stdout);
  } catch (error) {
    console.log(`❌ Log Check: ${error.message}`);
  }
}

async function runTests() {
  console.log('🧪 ColmenaOS Service Accessibility Test\n');
  console.log('=' .repeat(50));
  
  const results = {};
  
  // Test all services
  for (const [name, url] of Object.entries(config.services)) {
    results[name] = await testService(name, url);
  }
  
  // Test database
  results['PostgreSQL Database'] = await testDatabaseConnection();
  
  // Summary
  console.log('\n' + '=' .repeat(50));
  console.log('📊 TEST SUMMARY:');
  console.log('=' .repeat(50));
  
  const working = Object.values(results).filter(r => r).length;
  const total = Object.keys(results).length;
  
  console.log(`Working Services: ${working}/${total}`);
  
  if (results['ColmenaOS Frontend'] && results['ColmenaOS Backend']) {
    console.log('🎉 READY FOR AUTHENTICATION TESTING');
  } else {
    console.log('⚠️  CORE COLMENAOS APP NOT ACCESSIBLE - Cannot test authentication');
  }
  
  // Additional diagnostics
  await checkDockerServices();
  await checkColmenaAppLogs();
  
  console.log('\n' + '=' .repeat(50));
  console.log('Next Steps:');
  if (!results['ColmenaOS Frontend'] || !results['ColmenaOS Backend']) {
    console.log('1. Fix ColmenaOS container configuration issues');
    console.log('2. Rebuild Docker image with proper nginx/Django setup');
    console.log('3. Re-run this test to verify fixes');
    console.log('4. Run full Playwright authentication tests: npm test');
  } else {
    console.log('✅ All services ready - Run: npm test');
  }
}

runTests().catch(console.error);