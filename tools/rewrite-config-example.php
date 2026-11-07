<?php
// Rewrites ONLY the DB credential lines in the clone's config.php.
// Values are read from files; nothing is printed and nothing is passed on a command line.
$configPath = '/work/www/config.php';
$secretPath = '/work/secrets/app.pw';

$new = [
    'database_host'     => getenv('CLONE_DB_HOST') ?: 'tng-clone-db',
    'database_name'     => 'bitcryptic',
    'database_username' => 'tngclone',
    'database_password' => rtrim(file_get_contents($secretPath), "\r\n"),
    'database_port'     => '3306',
];

$lines = file($configPath, FILE_IGNORE_NEW_LINES);
$report = [];

foreach ($lines as $i => $line) {
    foreach ($new as $key => $value) {
        if (preg_match('/^(\$' . $key . '\s*=\s*)"[^"]*";/', $line, $m)) {
            $before = $line;
            $replacement = $m[1] . '"' . addcslashes($value, '"\\') . '";';
            if ($replacement !== $before) {
                $lines[$i] = $replacement;
                $report[] = sprintf('line %-3d $%-18s CHANGED', $i + 1, $key);
            } else {
                $report[] = sprintf('line %-3d $%-18s unchanged', $i + 1, $key);
            }
        }
    }
    // Report (do not alter) any socket setting, which would override host/port.
    if (preg_match('/^\$database_socket\s*=\s*"(.*)";/', $line, $m)) {
        $report[] = sprintf('line %-3d $%-18s %s', $i + 1, 'database_socket', $m[1] === '' ? 'empty (ok)' : 'SET — check manually');
    }
}

file_put_contents($configPath, implode("\n", $lines) . "\n");

echo "clone config rewritten (values never printed):\n";
echo implode("\n", $report), "\n";
