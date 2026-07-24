import fs from 'fs';
import path from 'path';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';
import 'dotenv/config';

const require = createRequire(import.meta.url);
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const pg = require('pg');

const password = process.env.SUPABASE_DB_PASSWORD || process.env.PGPASSWORD;
const connectionString =
  process.env.SUPABASE_DB_URL ||
  (password
    ? `postgresql://postgres.nxgjwtrqhrgpszpuzmkp:${encodeURIComponent(password)}@aws-0-us-east-1.pooler.supabase.com:6543/postgres`
    : null);

if (!connectionString) {
  console.error('Missing SUPABASE_DB_PASSWORD or SUPABASE_DB_URL');
  process.exit(1);
}

const resetSql = `
update public.license_keys
set artifact_hash = null,
    artifact_schema = 'v1:machine_guid_volume_computer',
    client_active = false,
    client_state = 'closed',
    active = true,
    blacklisted = false,
    locked_at = null,
    boot_requested = false,
    artifact_mismatch_count = 0,
    updated_at = now(),
    notes = concat_ws(E'\\n', nullif(notes, ''), 'Bulk HWID reset')
where artifact_hash is not null
  and artifact_hash <> '';
`;

async function main() {
  const client = new pg.Client({
    connectionString,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  try {
    const before = await client.query(
      `select count(*)::int as bound
         from public.license_keys
        where artifact_hash is not null and artifact_hash <> ''`
    );
    const boundBefore = before.rows[0]?.bound ?? 0;

    const updated = await client.query(resetSql);
    const cleared = updated.rowCount ?? 0;

    const blacklist = await client.query('delete from public.blacklisted_artifacts');
    const blacklistCleared = blacklist.rowCount ?? 0;

    const after = await client.query(
      `select count(*)::int as bound
         from public.license_keys
        where artifact_hash is not null and artifact_hash <> ''`
    );
    const boundAfter = after.rows[0]?.bound ?? 0;

    console.log(JSON.stringify({
      ok: true,
      bound_before: boundBefore,
      keys_reset: cleared,
      blacklist_cleared: blacklistCleared,
      bound_after: boundAfter
    }, null, 2));

    if (boundAfter !== 0) {
      process.exit(1);
    }
  } finally {
    await client.end();
  }
}

main().catch((error) => {
  console.error('Reset failed:', error.message);
  process.exit(1);
});
