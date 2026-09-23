<?php

declare(strict_types=1);

namespace Citadel\Arm;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

/**
 * PSR-15 middleware for Slim, Mezzio and anything else that runs a PSR-15
 * stack. Reports an exception that escapes the stack with its request, then
 * rethrows it — the framework's own error handling is unchanged. Needs
 * `psr/http-server-middleware`; the rest of this package does not.
 *
 * `$routeOf` names the route pattern when the framework knows it, so faults
 * group by route, not by every id in a path.
 */
final class ArmMiddleware implements MiddlewareInterface
{
    /** @param (callable(ServerRequestInterface): ?string)|null $routeOf */
    public function __construct(private readonly ?Arm $arm, private $routeOf = null)
    {
    }

    public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
    {
        try {
            $route = $this->routeOf !== null ? ($this->routeOf)($request) : null;
            if (is_string($route) && $route !== '') {
                $this->arm?->setRoute($route);
            }
        } catch (\Throwable) {
            // Never into the host.
        }
        try {
            return $handler->handle($request);
        } catch (\Throwable $error) {
            $this->arm?->captureException($error, ['operation' => 'request_error', 'severity' => 'serious', 'handled' => false]);
            throw $error;
        }
    }
}
