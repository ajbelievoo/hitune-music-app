<?php
// Test home page API response
require_once 'api/app/config.php';
require_once 'BOF/loader.php';

$BOF = BOF::instance();
$BOF->app_setup(['app_mode' => 'client']);

// Get home page data
$page = $BOF->platform([
    'object_type' => 'page',
    'slug' => 'home',
    'with_widgets' => true,
]);

echo "=== HOME PAGE DATA ===\n";
echo "Type: " . gettype($page) . "\n";

if (is_array($page)) {
    echo "Keys: " . implode(', ', array_keys($page)) . "\n\n";
    
    if (isset($page['widgets'])) {
        echo "WIDGETS COUNT: " . count($page['widgets']) . "\n\n";
        
        foreach ($page['widgets'] as $i => $widget) {
            echo "--- Widget $i ---\n";
            echo "ID: " . ($widget['ID'] ?? 'NULL') . "\n";
            echo "name: " . ($widget['name'] ?? 'NULL') . "\n";
            echo "slug: " . ($widget['slug'] ?? 'NULL') . "\n";
            
            if (isset($widget['display'])) {
                $display = $widget['display'];
                echo "display.type: " . ($display['type'] ?? 'NULL') . "\n";
                echo "display.title: " . ($display['title'] ?? 'NULL') . "\n";
                echo "display.link: " . ($display['link'] ?? 'NULL') . "\n";
                echo "display.o_type: " . ($display['o_type'] ?? 'NULL') . "\n";
            }
            
            if (isset($widget['items'])) {
                $items = $widget['items'];
                echo "items.type: " . gettype($items) . "\n";
                if (is_array($items)) {
                    echo "items.count: " . count($items) . "\n";
                    if (count($items) > 0) {
                        echo "first_item.keys: " . implode(', ', array_keys($items[0])) . "\n";
                    }
                }
            } else {
                echo "items: NOT SET\n";
            }
            echo "\n";
        }
    } else {
        echo "WIDGETS: NOT SET\n";
    }
}

echo "\n=== DONE ===\n";
