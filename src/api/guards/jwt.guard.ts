import { Auth, configService } from '@config/env.config';
import { Logger } from '@config/logger.config';
import { UnauthorizedException } from '@exceptions';
import { NextFunction, Request, Response } from 'express';
import jwt, { JwtPayload, VerifyOptions } from 'jsonwebtoken';
import jwksClient, { JwksClient, SigningKey } from 'jwks-rsa';

const logger = new Logger('JWT_GUARD');

let client: JwksClient | null = null;

function getJwksClient(): JwksClient {
  if (!client) {
    const oidcConfig = configService.get<Auth>('AUTHENTICATION').OIDC;
    client = jwksClient({
      jwksUri: oidcConfig.JWKS_URI,
      cache: true,
      cacheMaxEntries: 5,
      cacheMaxAge: 600000, // 10 minutes
      rateLimit: true,
      jwksRequestsPerMinute: 10,
    });
  }
  return client;
}

function getSigningKey(kid: string): Promise<string> {
  return new Promise((resolve, reject) => {
    getJwksClient().getSigningKey(kid, (err: Error | null, key?: SigningKey) => {
      if (err) {
        logger.error(`Error getting signing key: ${err.message}`);
        reject(err);
        return;
      }
      if (!key) {
        reject(new Error('Signing key not found'));
        return;
      }
      const signingKey = key.getPublicKey();
      resolve(signingKey);
    });
  });
}

export interface JwtUserPayload extends JwtPayload {
  sub?: string;
  email?: string;
  name?: string;
  roles?: string[];
  permissions?: string[];
  tenant_id?: string;
  instance_id?: string;
}

async function verifyJwtToken(token: string): Promise<JwtUserPayload> {
  const oidcConfig = configService.get<Auth>('AUTHENTICATION').OIDC;

  // Decode token header to get kid
  const decoded = jwt.decode(token, { complete: true });
  if (!decoded || typeof decoded === 'string') {
    throw new UnauthorizedException('Invalid token format');
  }

  const kid = decoded.header.kid;
  if (!kid) {
    throw new UnauthorizedException('Token missing kid in header');
  }

  // Get signing key from JWKS
  const signingKey = await getSigningKey(kid);

  // Verify token
  const verifyOptions: VerifyOptions = {
    algorithms: oidcConfig.ALGORITHMS as jwt.Algorithm[],
    issuer: oidcConfig.ISSUER,
  };

  if (oidcConfig.AUDIENCE) {
    verifyOptions.audience = oidcConfig.AUDIENCE;
  }

  return new Promise((resolve, reject) => {
    jwt.verify(token, signingKey, verifyOptions, (err, payload) => {
      if (err) {
        logger.error(`JWT verification failed: ${err.message}`);
        reject(new UnauthorizedException(`Token verification failed: ${err.message}`));
        return;
      }
      resolve(payload as JwtUserPayload);
    });
  });
}

function extractBearerToken(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader) {
    return null;
  }

  const parts = authHeader.split(' ');
  if (parts.length !== 2 || parts[0].toLowerCase() !== 'bearer') {
    return null;
  }

  return parts[1];
}

export async function jwtGuard(req: Request, _: Response, next: NextFunction): Promise<void> {
  const oidcConfig = configService.get<Auth>('AUTHENTICATION').OIDC;

  if (!oidcConfig.ENABLED) {
    return next();
  }

  const token = extractBearerToken(req);
  if (!token) {
    // No Bearer token, let other auth methods handle it
    return next();
  }

  try {
    const payload = await verifyJwtToken(token);

    // Attach user info to request for use in controllers
    (req as any).user = payload;
    (req as any).isJwtAuth = true;

    logger.log(`JWT authenticated user: ${payload.sub || payload.email || 'unknown'}`);

    return next();
  } catch (error) {
    logger.error(`JWT authentication failed: ${error.message}`);
    throw new UnauthorizedException(error.message);
  }
}

export function isJwtAuthenticated(req: Request): boolean {
  return (req as any).isJwtAuth === true;
}

export function getJwtUser(req: Request): JwtUserPayload | null {
  return (req as any).user || null;
}

export const jwtAuthGuard = { jwtGuard, isJwtAuthenticated, getJwtUser, verifyJwtToken };
