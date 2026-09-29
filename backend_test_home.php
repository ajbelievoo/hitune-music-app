<?php
// Test script to check home page API response
// Place this in /www/wwwroot/music/test_home_api.php and run via browser or CLI

require_once 'api/app/config.php';
require_once 'BOF/loader.php';

$BOF = BOF::instance();
$BOF->app_setup(['app_mode' => 'client']);

// Simulate POST request
$_SERVER['REQUEST_METHOD'] = 'POST';
$input = ['platform' => 'mobile'];
$_POST = $input;

// Load the endpoint
$endpoint_file = BOF_ROOT . '/app/client/endpoints/page/endpoint_page_single.php';
if (!file_exists($endpoint_file)) {
    echo "Endpoint file not found: $endpoint_file\n";
    
    // Try to find it
    $search = shell_exec('find /www/wwwroot/music -name "*page*single*.php" 2>/dev/null | head -10');
    echo "Found files:\n$search\n";
    exit;
}

echo "=== Testing Home Page API ===\n\n";

// Check what the endpoint returns
if (file_exists($endpoint_file)) {
    echo "Endpoint exists: $endpoint_file\n";
    
    // Get raw page data
    $page_data = $BOF->platform([
        'object_type' => 'page',
        'slug' => 'home',
        'with_widgets' => true,
    ]);
    
    echo "\n=== Page Data Structure ===\n";
    echo "Type: " . gettype($page_data) . "\n";
    
    if (is_array($page_data)) {
        echo "Keys: " . implode(', ', array_keys($page_data)) . "\n";
        
        if (isset($page_data['widgets'])) {
            echo "\nWidgets count: " . count($page_data['widgets']) . "\n";
            
            foreach ($page_data['widgets'] as $i => $widget) {
                echo "\n--- Widget $i ---\n";
                echo "ID: " . ($widget['ID'] ?? 'null') . "\n";
                echo "Name: " . ($widget['name'] ?? 'null') . "\n";
                echo "Type: " . ($widget['display']['type'] ?? 'unknown') . "\n";
                echo "Link: " . ($widget['display']['link'] ?? 'null') . "\n";
                echo "Items count: " . (isset($widget['items']) ? count($widget['items']) : 'not set') . "\n";
            }
        }
    }
    
    echo "\n=== Raw Output (first 500 chars) ===\n";
    $json = json_encode($page_data);
    echo substr($json, 0, 500) . "...\n";
}

echo "\n=== Done ===\n";
