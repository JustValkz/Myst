-- Myst bot admin RPCs (service-role or SQL editor deploy)
-- Allows license management without exposing direct table access to anon.

create or replace function public.bot_list_licenses(
    p_limit integer default 5,
    p_offset integer default 0,
    p_search text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_search text := nullif(trim(coalesce(p_search, '')), '');
    v_limit integer := greatest(1, least(coalesce(p_limit, 5), 25));
    v_offset integer := greatest(coalesce(p_offset, 0), 0);
    v_total bigint;
    v_rows jsonb;
begin
    if v_search is not null then
        select count(*)
          into v_total
          from public.license_keys
         where "key" ilike '%' || v_search || '%';
    else
        select count(*)
          into v_total
          from public.license_keys;
    end if;

    if v_search is not null then
        select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
          into v_rows
          from (
            select
                "key",
                active,
                blacklisted,
                artifact_hash,
                artifact_display,
                key_duration_seconds,
                expires_at,
                notes,
                created_at
            from public.license_keys
            where "key" ilike '%' || v_search || '%'
            order by created_at desc
            limit v_limit offset v_offset
          ) t;
    else
        select coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
          into v_rows
          from (
            select
                "key",
                active,
                blacklisted,
                artifact_hash,
                artifact_display,
                key_duration_seconds,
                expires_at,
                notes,
                created_at
            from public.license_keys
            order by created_at desc
            limit v_limit offset v_offset
          ) t;
    end if;

    return jsonb_build_object(
        'ok', true,
        'total', v_total,
        'rows', v_rows
    );
end;
$$;

create or replace function public.bot_create_licenses(
    p_keys text[],
    p_duration_seconds bigint,
    p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text;
    v_inserted text[] := array[]::text[];
begin
    if p_keys is null or array_length(p_keys, 1) is null then
        return jsonb_build_object('ok', false, 'message', 'No keys provided');
    end if;

    foreach v_key in array p_keys loop
        begin
            insert into public.license_keys ("key", active, key_duration_seconds, notes)
            values (
                trim(v_key),
                true,
                greatest(coalesce(p_duration_seconds, 0), 0),
                nullif(trim(coalesce(p_notes, '')), '')
            );

            v_inserted := array_append(v_inserted, trim(v_key));
        exception
            when unique_violation then
                null;
        end;
    end loop;

    return jsonb_build_object('ok', true, 'inserted', to_jsonb(v_inserted));
end;
$$;

create or replace function public.bot_delete_license(
    p_key text,
    p_force boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text := trim(coalesce(p_key, ''));
    v_row public.license_keys%rowtype;
begin
    if v_key = '' then
        return jsonb_build_object('ok', false, 'message', 'Missing key');
    end if;

    select *
      into v_row
      from public.license_keys
     where "key" = v_key;

    if not found then
        return jsonb_build_object('ok', false, 'message', 'Key not found');
    end if;

    if coalesce(p_force, false) or v_row.artifact_hash is null or v_row.artifact_hash = '' then
        delete from public.license_keys where "key" = v_key;
        return jsonb_build_object('ok', true, 'mode', 'removed', 'key', v_key);
    end if;

    update public.license_keys
       set active = false,
           client_active = false,
           client_state = 'closed',
           notes = concat_ws(E'\n', nullif(notes, ''), 'Deactivated via Discord bot')
     where "key" = v_key;

    return jsonb_build_object('ok', true, 'mode', 'deactivated', 'key', v_key);
end;
$$;

create or replace function public.bot_reset_hwid(
    p_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_key text := trim(coalesce(p_key, ''));
    v_row public.license_keys%rowtype;
begin
    if v_key = '' then
        return jsonb_build_object('ok', false, 'message', 'Missing key');
    end if;

    select *
      into v_row
      from public.license_keys
     where "key" = v_key;

    if not found then
        return jsonb_build_object('ok', false, 'message', 'Key not found');
    end if;

    update public.license_keys
       set artifact_hash = null,
           artifact_schema = 'v1:machine_guid_volume_computer',
           client_active = false,
           client_state = 'closed',
           active = true,
           blacklisted = false,
           blacklisted_at = null,
           locked_at = null,
           boot_requested = false,
           artifact_mismatch_count = 0,
           last_status = null,
           last_message = null,
           updated_at = now(),
           notes = concat_ws(E'\n', nullif(notes, ''), 'HWID reset via Discord bot')
     where "key" = v_key;

    delete from public.blacklisted_artifacts ba
     using public.license_auth_events e
     where e."key" = v_key
       and ba.artifact_hash = e.artifact_hash;

    return jsonb_build_object(
        'ok', true,
        'key', v_key,
        'message', 'HWID cleared — key can be redeemed on a new machine',
        'was_redeemed', v_row.artifact_hash is not null and v_row.artifact_hash <> '',
        'previous_artifact', coalesce(
            v_row.artifact_display,
            case
                when v_row.artifact_hash is null or v_row.artifact_hash = '' then null
                else 'ART-' || upper(substr(v_row.artifact_hash, 1, 12))
            end
        )
    );
end;
$$;

create or replace function public.bot_reset_all_hwids()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_keys_reset integer := 0;
    v_blacklist_cleared integer := 0;
begin
    update public.license_keys
       set artifact_hash = null,
           artifact_schema = 'v1:machine_guid_volume_computer',
           client_active = false,
           client_state = 'closed',
           active = true,
           blacklisted = false,
           blacklisted_at = null,
           locked_at = null,
           boot_requested = false,
           artifact_mismatch_count = 0,
           last_status = case when last_status in ('artifact_mismatch', 'blacklisted') then null else last_status end,
           last_message = case when last_message in ('HWID Locked', 'Artifact Mismatch', 'Blacklisted') then null else last_message end,
           updated_at = now(),
           notes = concat_ws(E'\n', nullif(notes, ''), 'Bulk HWID reset via Discord bot')
     where artifact_hash is not null
       and artifact_hash <> '';

    get diagnostics v_keys_reset = row_count;

    delete from public.blacklisted_artifacts;
    get diagnostics v_blacklist_cleared = row_count;

    return jsonb_build_object(
        'ok', true,
        'keys_reset', v_keys_reset,
        'blacklist_cleared', v_blacklist_cleared
    );
end;
$$;

revoke all on function public.bot_list_licenses(integer, integer, text) from public;
revoke all on function public.bot_create_licenses(text[], bigint, text) from public;
revoke all on function public.bot_delete_license(text, boolean) from public;
revoke all on function public.bot_reset_hwid(text) from public;
revoke all on function public.bot_reset_all_hwids() from public;

grant execute on function public.bot_list_licenses(integer, integer, text) to anon;
grant execute on function public.bot_create_licenses(text[], bigint, text) to anon;
grant execute on function public.bot_delete_license(text, boolean) to anon;
grant execute on function public.bot_reset_hwid(text) to anon;
grant execute on function public.bot_reset_all_hwids() to anon;

grant execute on function public.bot_list_licenses(integer, integer, text) to service_role;
grant execute on function public.bot_create_licenses(text[], bigint, text) to service_role;
grant execute on function public.bot_delete_license(text, boolean) to service_role;
grant execute on function public.bot_reset_hwid(text) to service_role;
grant execute on function public.bot_reset_all_hwids() to service_role;
