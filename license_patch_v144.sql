-- Myst license patch v1.4.4 (run in Supabase SQL Editor on existing DB)
-- Fixes: no auto-blacklist on HWID mismatch, roblox_user tracking, admin unblacklist helpers.

alter table public.license_keys
    add column if not exists roblox_user text,
    add column if not exists generated_by text;

create or replace function public.claim_license(
    p_key text,
    p_hwid text,
    p_client_version text default null,
    p_artifact_schema text default 'v1:machine_guid_volume_computer',
    p_roblox_user text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text := trim(coalesce(p_key, ''));
    v_hwid text := trim(coalesce(p_hwid, ''));
    v_client_version text := left(trim(coalesce(p_client_version, '')), 64);
    v_artifact_schema text := left(trim(coalesce(p_artifact_schema, '')), 128);
    v_roblox_user text := left(trim(coalesce(p_roblox_user, '')), 64);
    v_artifact_hash text;
    v_row public.license_keys%rowtype;
    v_expires_at timestamptz;
begin
    if v_artifact_schema = '' then
        v_artifact_schema := 'v1:machine_guid_volume_computer';
    end if;

    if length(v_key) < 4 or length(v_hwid) < 16 then
        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'client_error', 'Client Error', nullif(v_key, ''), nullif(v_hwid, ''), v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'client_error', 'status', 'Client Error', 'message', 'Client Error', 'boot', false);
    end if;

    v_artifact_hash := v_hwid;

    if public.auth_rate_limited('claim:' || v_key, 12, 60, 300) then
        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'rate_limited', 'Client Error', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'rate_limited', 'status', 'Client Error', 'message', 'Client Error', 'boot', false);
    end if;

    select *
      into v_row
      from public.license_keys
     where "key" = v_key
     for update;

    if not found then
        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'invalid_key', 'Invalid Key', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'invalid_key', 'status', 'Invalid Key', 'message', 'Invalid Key', 'boot', false);
    end if;

    if v_row.blacklisted then
        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'blacklisted', 'Blacklisted', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'blacklisted', 'status', 'Blacklisted', 'message', 'Blacklisted', 'boot', true);
    end if;

    if exists(select 1 from public.blacklisted_artifacts where artifact_hash = v_artifact_hash) then
        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'blacklisted', 'Blacklisted', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'blacklisted', 'status', 'Blacklisted', 'message', 'Blacklisted', 'boot', true);
    end if;

    if v_row.boot_requested then
        update public.license_keys
           set client_active = false,
               client_state = 'closed',
               client_version = coalesce(nullif(v_client_version, ''), client_version),
               artifact_schema = v_artifact_schema,
               last_status = 'booted',
               last_message = 'Booted',
               last_seen_at = now(),
               updated_at = now()
         where id = v_row.id;

        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'booted', 'Booted', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'booted', 'status', 'Booted', 'message', 'Booted', 'boot', true);
    end if;

    if not v_row.active then
        update public.license_keys
           set client_active = false,
               client_state = 'closed',
               client_version = coalesce(nullif(v_client_version, ''), client_version),
               artifact_schema = v_artifact_schema,
               last_status = 'inactive',
               last_message = 'Inactive',
               last_seen_at = now(),
               updated_at = now()
         where id = v_row.id;

        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'inactive', 'Inactive', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'inactive', 'status', 'Inactive', 'message', 'Inactive', 'boot', false);
    end if;

    if v_row.expires_at is not null and v_row.expires_at <= now() then
        update public.license_keys
           set active = false,
               client_active = false,
               client_state = 'closed',
               client_version = coalesce(nullif(v_client_version, ''), client_version),
               artifact_schema = v_artifact_schema,
               last_status = 'expired',
               last_message = 'Expired',
               updated_at = now()
         where id = v_row.id;

        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', false, 'expired', 'Expired', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', false, 'reason', 'expired', 'status', 'Expired', 'message', 'Expired', 'boot', false);
    end if;

    if v_row.artifact_hash is null or v_row.artifact_hash = '' then
        v_expires_at := case
            when v_row.key_duration_seconds <= 0 then null
            else now() + (v_row.key_duration_seconds * interval '1 second')
        end;

        update public.license_keys
           set artifact_hash = v_artifact_hash,
               artifact_schema = v_artifact_schema,
               expires_at = v_expires_at,
               client_active = true,
               client_state = 'open',
               client_version = nullif(v_client_version, ''),
               roblox_user = case when v_roblox_user <> '' then v_roblox_user else roblox_user end,
               use_count = use_count + 1,
               first_used_at = coalesce(first_used_at, now()),
               last_used_at = now(),
               last_seen_at = now(),
               last_status = 'valid_key',
               last_message = 'Valid Key',
               updated_at = now()
         where id = v_row.id;

        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', true, 'valid_key', 'Valid Key', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', true, 'reason', 'valid_key', 'status', 'Valid Key', 'message', 'Valid Key', 'action', 'redeemed', 'expires_at', v_expires_at, 'boot', false);
    end if;

    if v_row.artifact_hash = v_artifact_hash then
        update public.license_keys
           set client_active = true,
               client_state = 'open',
               client_version = coalesce(nullif(v_client_version, ''), client_version),
               artifact_schema = v_artifact_schema,
               roblox_user = case when v_roblox_user <> '' then v_roblox_user else roblox_user end,
               use_count = use_count + 1,
               last_used_at = now(),
               last_seen_at = now(),
               last_status = 'valid_key',
               last_message = 'Valid Key',
               updated_at = now()
         where id = v_row.id;

        insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
        values ('claim', true, 'valid_key', 'Valid Key', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

        return jsonb_build_object('ok', true, 'reason', 'valid_key', 'status', 'Valid Key', 'message', 'Valid Key', 'action', 'validated', 'expires_at', v_row.expires_at, 'boot', false);
    end if;

    update public.license_keys
       set artifact_mismatch_count = artifact_mismatch_count + 1,
           client_version = coalesce(nullif(v_client_version, ''), client_version),
           artifact_schema = v_artifact_schema,
           last_status = 'artifact_mismatch',
           last_message = 'HWID Locked',
           last_seen_at = now(),
           updated_at = now()
     where id = v_row.id;

    insert into public.license_auth_events (action, ok, status, message, "key", artifact_hash, artifact_schema, client_version)
    values ('claim', false, 'artifact_mismatch', 'HWID Locked', v_key, v_artifact_hash, v_artifact_schema, nullif(v_client_version, ''));

    return jsonb_build_object(
        'ok', false,
        'reason', 'artifact_mismatch',
        'status', 'HWID Locked',
        'message', 'This key is bound to another PC. Ask an admin to reset HWID.',
        'boot', false
    );
end;
$$;

-- Clear all blacklist state (run once to fix false positives)
delete from public.blacklisted_artifacts;

update public.license_keys
   set blacklisted = false,
       active = true,
       blacklisted_at = null,
       last_status = case when last_status in ('blacklisted', 'artifact_mismatch') then null else last_status end,
       last_message = case when last_message in ('Blacklisted', 'Artifact Mismatch', 'HWID Locked') then null else last_message end
 where blacklisted = true
    or last_status in ('blacklisted', 'artifact_mismatch');

revoke all on function public.claim_license(text, text, text, text, text) from public;
grant execute on function public.claim_license(text, text, text, text, text) to anon;
grant execute on function public.claim_license(text, text, text, text, text) to service_role;
