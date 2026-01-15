#!/usr/bin/env node

/**
 * Script to build firebase-messaging-sw.js from template
 * Replaces environment variables from .env file
 * 
 * Usage: node scripts/build-firebase-sw.js
 */

const fs = require('fs');
const path = require('path');

// Paths
const rootDir = path.join(__dirname, '..');
const envFile = path.join(rootDir, '.env');
const templateFile = path.join(rootDir, 'web', 'firebase-messaging-sw_template.js');
const outputFile = path.join(rootDir, 'web', 'firebase-messaging-sw.js');

/**
 * Parse .env file and return as object
 */
function parseEnvFile(filePath) {
  const env = {};
  
  if (!fs.existsSync(filePath)) {
    console.warn(`Warning: .env file not found at ${filePath}`);
    return env;
  }

  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n');

  for (const line of lines) {
    // Skip empty lines and comments
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) {
      continue;
    }

    // Parse KEY=VALUE format
    const match = trimmed.match(/^([^=]+)=(.*)$/);
    if (match) {
      const key = match[1].trim();
      let value = match[2].trim();
      
      // Remove quotes if present
      if ((value.startsWith('"') && value.endsWith('"')) ||
          (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      
      env[key] = value;
    }
  }

  return env;
}

/**
 * Replace placeholders in template with env values
 */
function processTemplate(template, env) {
  let result = template;
  
  // Find all placeholders like <VAR_NAME>
  const placeholderRegex = /<([A-Z_][A-Z0-9_]*)>/g;
  const replacements = new Map();
  let match;
  
  // Find all unique placeholders
  while ((match = placeholderRegex.exec(template)) !== null) {
    const placeholder = match[0]; // e.g., "<FIREBASE_WEB_APIKEY>"
    const varName = match[1]; // e.g., "FIREBASE_WEB_APIKEY"
    
    if (!replacements.has(placeholder)) {
      const envValue = env[varName];
      
      if (envValue === undefined) {
        console.warn(`Warning: Environment variable ${varName} not found in .env file`);
        // Keep the placeholder if variable not found
        replacements.set(placeholder, placeholder);
      } else {
        replacements.set(placeholder, envValue);
      }
    }
  }
  
  // Replace all placeholders
  for (const [placeholder, value] of replacements) {
    // Use global regex replace for compatibility with older Node.js versions
    const regex = new RegExp(placeholder.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'g');
    result = result.replace(regex, value);
  }
  
  return result;
}

/**
 * Main function
 */
function main() {
  console.log('Building firebase-messaging-sw.js from template...');
  
  // Check if template exists
  if (!fs.existsSync(templateFile)) {
    console.error(`Error: Template file not found: ${templateFile}`);
    process.exit(1);
  }
  
  // Read template
  const template = fs.readFileSync(templateFile, 'utf-8');
  console.log(`✓ Read template from ${templateFile}`);
  
  // Parse .env file
  const env = parseEnvFile(envFile);
  console.log(`✓ Parsed ${Object.keys(env).length} environment variables from .env`);
  
  // Process template
  const output = processTemplate(template, env);
  
  // Write output
  fs.writeFileSync(outputFile, output, 'utf-8');
  console.log(`✓ Generated ${outputFile}`);
  
  // Check for remaining placeholders
  const remainingPlaceholders = output.match(/<[A-Z_][A-Z0-9_]*>/g);
  if (remainingPlaceholders) {
    console.warn(`\nWarning: Some placeholders were not replaced:`);
    remainingPlaceholders.forEach(placeholder => {
      console.warn(`  - ${placeholder}`);
    });
  } else {
    console.log('\n✓ All placeholders replaced successfully');
  }
  
  console.log('\nDone!');
}

// Run the script
main();
