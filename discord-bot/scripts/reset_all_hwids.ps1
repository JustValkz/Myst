# Resets every bound license HWID via Supabase Postgres.
$ErrorActionPreference = 'Stop'

$password = $env:SUPABASE_DB_PASSWORD
if (-not $password) {
    $password = 'Myst7866!!_'
}

$connectionString = "postgresql://postgres.nxgjwtrqhrgpszpuzmkp:$([uri]::EscapeDataString($password))@aws-0-us-east-1.pooler.supabase.com:6543/postgres"

$botDir = Split-Path -Parent $PSScriptRoot
$nodeModulesPg = Join-Path $botDir 'node_modules\pg'

if (-not (Test-Path $nodeModulesPg)) {
    Write-Error "Missing pg module. Run: cd `"$botDir`" && npm install"
}

$script = @'
const pg = require(process.argv[1]);
const connectionString = process.argv[2];

(async () => {
  const client = new pg.Client({ connectionString, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const before = await client.query(`select count(*)::int as bound from public.license_keys where artifact_hash is not null and artifact_hash <> ''`);
    const updated = await client.query(`
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
      where artifact_hash is not null and artifact_hash <> ''`);
    const blacklist = await client.query('delete from public.blacklisted_artifacts');
    const after = await client.query(`select count(*)::int as bound from public.license_keys where artifact_hash is not null and artifact_hash <> ''`);
    console.log(JSON.stringify({
      ok: true,
      bound_before: before.rows[0].bound,
      keys_reset: updated.rowCount,
      blacklist_cleared: blacklist.rowCount,
      bound_after: after.rows[0].bound
    }));
    process.exit(after.rows[0].bound === 0 ? 0 : 1);
  } finally {
    await client.end();
  }
})().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
'@

$node = 'C:\Program Files\nodejs\node.exe'
if (-not (Test-Path $node)) {
    $node = (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
}
if (-not $node) {
    Write-Error 'Node.js not found. Install Node LTS first.'
}

$tempJs = Join-Path $env:TEMP 'myst_reset_hwids.js'
Set-Content -LiteralPath $tempJs -Value $script -Encoding UTF8
& $node $tempJs $nodeModulesPg $connectionString
exit $LASTEXITCODE
