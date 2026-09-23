<?php
// Stands in for the ARM ingest: records each batch with its headers, answers 202.
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && ($_SERVER['REQUEST_URI'] ?? '') === '/v1/captures') {
    // The ingest's own type rules (parseArmIngestBatch), so a client that
    // sends a shape the real ingest refuses fails here too rather than only
    // in production. `context`, `tags` and `errorData` are objects;
    // `breadcrumbs` is an array.
    $raw = json_decode((string) file_get_contents('php://input'));
    $valid = is_array($raw) && $raw !== [];
    foreach (is_array($raw) ? $raw : [] as $capture) {
        foreach (['context', 'tags', 'errorData'] as $field) {
            if (isset($capture->$field) && !is_object($capture->$field)) {
                $valid = false;
            }
        }
        if (isset($capture->breadcrumbs) && !is_array($capture->breadcrumbs)) {
            $valid = false;
        }
        foreach (['captureId', 'occurredAt', 'feature', 'operation', 'errorType', 'sessionId'] as $field) {
            if (!isset($capture->$field) || !is_string($capture->$field) || trim($capture->$field) === '') {
                $valid = false;
            }
        }
    }
    if (!$valid) {
        file_put_contents((string) getenv('ARM_RECORD'), json_encode(['refused' => true]) . "\n", FILE_APPEND | LOCK_EX);
        http_response_code(400);
        return true;
    }
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
