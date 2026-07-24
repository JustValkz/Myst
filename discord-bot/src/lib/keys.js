const KEY_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function generateLicenseKey() {
  let suffix = '';
  for (let i = 0; i < 10; i += 1) {
    suffix += KEY_CHARS[Math.floor(Math.random() * KEY_CHARS.length)];
  }
  return `MYST-${suffix}`;
}

export function normalizeLicenseKey(raw) {
  let key = String(raw ?? '').trim().toUpperCase();
  key = key.replace(/\s+/g, '');
  if (!key) {
    return '';
  }
  if (!key.startsWith('MYST-')) {
    key = `MYST-${key.replace(/^MYST-?/i, '')}`;
  }
  return key;
}

export function durationToSeconds(durationType, durationValue) {
  const value = Math.max(1, Number(durationValue) || 1);

  switch (durationType) {
    case 'lifetime':
      return 0;
    case 'day':
      return value * 86_400;
    case 'week':
      return value * 604_800;
    case 'month':
      return value * 2_592_000;
    default:
      throw new Error(`Unknown duration type: ${durationType}`);
  }
}

export function formatDuration(durationType, durationValue) {
  switch (durationType) {
    case 'lifetime':
      return 'Lifetime';
    case 'day':
      return `${durationValue} day${durationValue === 1 ? '' : 's'}`;
    case 'week':
      return `${durationValue} week${durationValue === 1 ? '' : 's'}`;
    case 'month':
      return `${durationValue} month${durationValue === 1 ? '' : 's'}`;
    default:
      return durationType;
  }
}

export function formatDurationFromSeconds(seconds) {
  const value = Number(seconds);
  if (!Number.isFinite(value) || value <= 0) {
    return 'Lifetime';
  }

  if (value % 2_592_000 === 0) {
    const months = value / 2_592_000;
    return `${months} month${months === 1 ? '' : 's'}`;
  }

  if (value % 604_800 === 0) {
    const weeks = value / 604_800;
    return `${weeks} week${weeks === 1 ? '' : 's'}`;
  }

  if (value % 86_400 === 0) {
    const days = value / 86_400;
    return `${days} day${days === 1 ? '' : 's'}`;
  }

  return `${value} seconds`;
}

export function formatTimestamp(value) {
  if (!value) {
    return '—';
  }

  const date = new Date(value);
  if (Number.isNaN(date.getTime())) {
    return '—';
  }

  return `<t:${Math.floor(date.getTime() / 1000)}:R>`;
}

export function chunkLines(lines, maxLength = 950) {
  const chunks = [];
  let current = '';

  for (const line of lines) {
    const next = current ? `${current}\n${line}` : line;
    if (next.length > maxLength) {
      if (current) {
        chunks.push(current);
      }
      current = line;
    } else {
      current = next;
    }
  }

  if (current) {
    chunks.push(current);
  }

  return chunks;
}

export function chunkArray(items, size = 12) {
  const chunks = [];
  const count = Math.max(1, Number(size) || 1);

  for (let i = 0; i < items.length; i += count) {
    chunks.push(items.slice(i, i + count));
  }

  return chunks;
}
