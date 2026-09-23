<?php
// Stands in for the ARM ingest: records each batch with its headers, answers 202.
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && ($_SERVER['REQUEST_URI'] ?? '') === '/v1/captures') {
    file_put_contents((string) getenv('ARM_RECORD'), json_encode([
        'client' => $_SERVER['HTTP_X_CITADEL_CLIENT'] ?? null,
        'key' => $_SERVER['HTTP_X_ARM_KEY'] ?? null,
        'body' => json_decode((string) file_get_contents('php://input'), true),
    ]) . "\n", FILE_APPEND | LOCK_EX);
    http_response_code(202);
    echo '{}';
    return true;
}
http_response_code(404);
return true;
