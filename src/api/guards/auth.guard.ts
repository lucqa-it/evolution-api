import { InstanceDto } from '@api/dto/instance.dto';
import { prismaRepository } from '@api/server.module';
import { Auth, configService, Database } from '@config/env.config';
import { Logger } from '@config/logger.config';
import { ForbiddenException, UnauthorizedException } from '@exceptions';
import { NextFunction, Request, Response } from 'express';

import { isJwtAuthenticated, jwtGuard } from './jwt.guard';

const logger = new Logger('GUARD');

async function apikey(req: Request, res: Response, next: NextFunction) {
  const authConfig = configService.get<Auth>('AUTHENTICATION');
  const env = authConfig.API_KEY;
  const oidcConfig = authConfig.OIDC;
  const key = req.get('apikey');
  const db = configService.get<Database>('DATABASE');

  // Check if OIDC is enabled and try JWT authentication first
  if (oidcConfig.ENABLED) {
    try {
      await jwtGuard(req, res, () => {});

      // If JWT authentication succeeded, allow access
      if (isJwtAuthenticated(req)) {
        logger.log('Request authenticated via JWT/OIDC');
        return next();
      }
    } catch (error) {
      // If there was a Bearer token but it failed, throw the error
      const authHeader = req.headers.authorization;
      if (authHeader && authHeader.toLowerCase().startsWith('bearer ')) {
        throw error;
      }
      // Otherwise, fall through to API key authentication
    }
  }

  // Fall back to API key authentication
  if (!key) {
    throw new UnauthorizedException();
  }

  if (env.KEY === key) {
    return next();
  }

  if ((req.originalUrl.includes('/instance/create') || req.originalUrl.includes('/instance/fetchInstances')) && !key) {
    throw new ForbiddenException('Missing global api key', 'The global api key must be set');
  }
  const param = req.params as unknown as InstanceDto;

  try {
    if (param?.instanceName) {
      const instance = await prismaRepository.instance.findUnique({
        where: { name: param.instanceName },
      });
      if (instance.token === key) {
        return next();
      }
    } else {
      if (req.originalUrl.includes('/instance/fetchInstances') && db.SAVE_DATA.INSTANCE) {
        const instanceByKey = await prismaRepository.instance.findFirst({
          where: { token: key },
        });
        if (instanceByKey) {
          return next();
        }
      }
    }
  } catch (error) {
    logger.error(error);
  }

  throw new UnauthorizedException();
}

export const authGuard = { apikey };
