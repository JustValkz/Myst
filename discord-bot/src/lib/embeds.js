const BRAND = 0x4a7cff;

export function errorEmbed(description) {
  return {
    color: 0xef4444,
    title: 'Myst License Manager',
    description
  };
}

export function successEmbed(title, description) {
  return {
    color: 0x22c55e,
    title,
    description,
    footer: { text: 'Myst License Manager' }
  };
}

export function infoEmbed(title, description) {
  return {
    color: BRAND,
    title,
    description,
    footer: { text: 'Myst License Manager' }
  };
}

export function resetHwidEmbed({ key, wasRedeemed, previousArtifact, actor }) {
  const lines = [`Key: \`${key}\``];

  if (wasRedeemed) {
    lines.push('Previous binding cleared.');
    if (previousArtifact) {
      lines.push(`Was bound to: \`${previousArtifact}\``);
    }
  } else {
    lines.push('Key was not redeemed yet.');
  }

  if (actor) {
    lines.push(`Reset by: ${actor}`);
  }

  return successEmbed('HWID Reset', lines.join('\n'));
}

export function licenseListEmbed({ rows, total, offset, search }) {
  const header = search
    ? `Showing ${rows.length} of ${total} matches for \`${search}\``
    : `Showing ${rows.length} of ${total} licenses (offset ${offset})`;

  if (!rows.length) {
    return infoEmbed('Licenses', `${header}\n\nNo keys found.`);
  }

  const body = rows
    .map((row) => {
      const status = row.blacklisted
        ? 'blacklisted'
        : row.artifact_hash
          ? 'redeemed'
          : row.active
            ? 'unused'
            : 'inactive';
      const duration =
        !row.key_duration_seconds || row.key_duration_seconds <= 0
          ? 'Lifetime'
          : `${row.key_duration_seconds}s`;
      return `\`${row.key}\` · ${status} · ${duration}`;
    })
    .join('\n');

  return infoEmbed('Licenses', `${header}\n\n${body}`);
}

export function generatedKeysEmbed({ keys, durationLabel, actor, notes }) {
  const lines = [
    `Duration: **${durationLabel}**`,
    `Created: **${keys.length}**`,
    actor ? `By: ${actor}` : null,
    notes ? `Notes: ${notes}` : null,
    '',
    keys.map((key) => `\`${key}\``).join('\n')
  ].filter(Boolean);

  return successEmbed('Keys Generated', lines.join('\n'));
}
