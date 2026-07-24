import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { errorEmbed } from './embeds.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const adminStorePath = path.join(__dirname, '..', '..', 'data', 'admins.json');

function loadAdminIds() {
  const fromEnv = (process.env.LICENSE_ADMIN_IDS || '')
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  if (fromEnv.length) {
    return new Set(fromEnv);
  }

  try {
    if (fs.existsSync(adminStorePath)) {
      const parsed = JSON.parse(fs.readFileSync(adminStorePath, 'utf8'));
      const ids = Array.isArray(parsed?.ids) ? parsed.ids : [];
      return new Set(ids.map(String));
    }
  } catch {
    // fall through
  }

  return new Set();
}

function saveAdminIds(ids) {
  fs.mkdirSync(path.dirname(adminStorePath), { recursive: true });
  fs.writeFileSync(
    adminStorePath,
    `${JSON.stringify({ ids: [...ids].sort() }, null, 2)}\n`
  );
}

export function getAdminIds() {
  return [...loadAdminIds()];
}

export function canManageLicenses(interaction) {
  const admins = loadAdminIds();
  if (!admins.size) {
    return true;
  }

  return admins.has(interaction.user.id);
}

export function denyEmbed() {
  return {
    embeds: [errorEmbed('You are not allowed to manage Myst licenses.')],
    ephemeral: true
  };
}

export function addAdminId(userId) {
  const admins = loadAdminIds();
  admins.add(String(userId));
  saveAdminIds(admins);
  return admins;
}

export function removeAdminId(userId) {
  const admins = loadAdminIds();
  admins.delete(String(userId));
  saveAdminIds(admins);
  return admins;
}
