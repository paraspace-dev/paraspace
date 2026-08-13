#!/usr/bin/env node
'use strict';

let input = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => { input += chunk; });
process.stdin.on('end', () => {
  let model;
  try {
    model = JSON.parse(input);
  } catch (error) {
    console.error(`warn: Docker mod could not parse Compose JSON: ${error.message}`);
    process.exitCode = 1;
    return;
  }

  if (!model || typeof model !== 'object' || !model.services || typeof model.services !== 'object') {
    console.error('warn: Docker mod could not find services in the resolved Compose model.');
    process.exitCode = 1;
    return;
  }

  const images = [];
  const seenImages = new Set();
  const usable = [];

  for (const [serviceName, service] of Object.entries(model.services)) {
    if (!service || typeof service !== 'object') continue;
    if (typeof service.image === 'string' && service.image && !seenImages.has(service.image)) {
      seenImages.add(service.image);
      images.push(service.image);
    }

    const servicePorts = [];
    for (const rawPort of Array.isArray(service.ports) ? service.ports : []) {
      const port = normalizePort(rawPort);
      if (!port) {
        console.error(`warn: Docker mod ignored a port on ${serviceName} that Compose did not resolve into fields.`);
        continue;
      }
      if (port.protocol !== 'tcp') continue;
      if (!isFixedPort(port.published)) {
        console.error(`warn: Docker mod ignored ${serviceName}'s unpublished or ranged port.`);
        continue;
      }
      if (isLoopback(port.hostIp)) {
        console.error(`warn: Docker mod ignored ${serviceName}:${port.published}, which is bound only to loopback.`);
        continue;
      }
      if (port.appProtocol && !/^(https?|h2c?|grpc)$/i.test(port.appProtocol)) {
        console.error(`warn: Docker mod ignored ${serviceName}:${port.published}, whose application protocol is ${port.appProtocol}.`);
        continue;
      }
      servicePorts.push(port);
    }
    for (const port of servicePorts) usable.push({ serviceName, servicePortCount: servicePorts.length, port });
  }

  console.log(`IMAGES=${images.join(' ')}`);
  if (usable.length === 0) {
    console.log('ROUTES=');
    return;
  }
  if (usable.length === 1) {
    console.log(`ROUTES=${usable[0].port.published}`);
    return;
  }

  const routes = [];
  const hosts = new Set();
  for (const item of usable) {
    let host = dnsLabel(item.serviceName);
    if (item.servicePortCount > 1) {
      const suffix = item.port.name ? dnsLabel(item.port.name) : item.port.published;
      host = `${host}-${suffix}`;
    }
    // No ROUTES line at all, which is how the shell side reads "leave it alone".
    if (!validDnsLabel(host) || hosts.has(host)) {
      console.error('warn: Docker mod could not generate unique DNS-safe route names; PARA_ROUTES was not changed.');
      return;
    }
    hosts.add(host);
    routes.push(`${host}:${item.port.published}`);
  }
  console.log(`ROUTES=${routes.join(' ')}`);
});

function normalizePort(raw) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  return {
    published: raw.published == null ? '' : String(raw.published),
    protocol: String(raw.protocol || 'tcp').toLowerCase(),
    appProtocol: raw.app_protocol == null ? '' : String(raw.app_protocol),
    hostIp: raw.host_ip == null ? '' : String(raw.host_ip),
    name: raw.name == null ? '' : String(raw.name)
  };
}

function isLoopback(hostIp) {
  const host = hostIp.toLowerCase();
  return host === 'localhost' || host === '::1' || /^127(?:\.|$)/.test(host) || /^::ffff:127\./.test(host);
}

function isFixedPort(value) {
  if (!/^\d+$/.test(value)) return false;
  const number = Number(value);
  return number >= 1 && number <= 65535;
}

function dnsLabel(value) {
  return String(value).toLowerCase().replace(/[^a-z0-9-]+/g, '-').replace(/^-+|-+$/g, '');
}

function validDnsLabel(value) {
  return value.length > 0 && value.length <= 63 && /^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/.test(value);
}
