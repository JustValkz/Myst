import { SlashCommandBuilder } from 'discord.js';
import { supabase } from '../lib/supabase.js';
import {
  durationToSeconds,
  formatDuration,
  generateLicenseKey,
  normalizeLicenseKey
} from '../lib/keys.js';
import { generatedKeysEmbed, errorEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('generate')
  .setDescription('Generate Myst license keys')
  .addIntegerOption((option) =>
    option
      .setName('count')
      .setDescription('How many keys to create (1-25)')
      .setRequired(true)
      .setMinValue(1)
      .setMaxValue(25)
  )
  .addStringOption((option) =>
    option
      .setName('duration')
      .setDescription('License duration type')
      .setRequired(true)
      .addChoices(
        { name: 'Lifetime', value: 'lifetime' },
        { name: 'Day(s)', value: 'day' },
        { name: 'Week(s)', value: 'week' },
        { name: 'Month(s)', value: 'month' }
      )
  )
  .addIntegerOption((option) =>
    option
      .setName('amount')
      .setDescription('Duration amount (ignored for lifetime)')
      .setMinValue(1)
      .setMaxValue(365)
  )
  .addStringOption((option) =>
    option
      .setName('notes')
      .setDescription('Optional note stored on the keys')
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const count = interaction.options.getInteger('count', true);
  const durationType = interaction.options.getString('duration', true);
  const amount = interaction.options.getInteger('amount') || 1;
  const notesInput = interaction.options.getString('notes') || '';
  const actorTag = interaction.user.tag;

  const durationSeconds = durationToSeconds(durationType, amount);
  const durationLabel = formatDuration(durationType, amount);
  const notes = notesInput
    ? `${notesInput} (Generated via Discord by ${actorTag} (${durationLabel}))`
    : `Generated via Discord by ${actorTag} (${durationLabel})`;

  const keys = [];
  for (let i = 0; i < count; i += 1) {
    keys.push(generateLicenseKey());
  }

  await interaction.deferReply({ ephemeral: true });

  const { data, error } = await supabase.rpc('bot_create_licenses', {
    p_keys: keys,
    p_duration_seconds: durationSeconds,
    p_notes: notes
  });

  if (error) {
    return interaction.editReply({
      embeds: [errorEmbed(`Key generation failed: ${error.message}`)]
    });
  }

  const inserted = Array.isArray(data?.inserted) ? data.inserted : keys;

  return interaction.editReply({
    embeds: [
      generatedKeysEmbed({
        keys: inserted,
        durationLabel,
        actor: `<@${interaction.user.id}>`,
        notes: notesInput || null
      })
    ]
  });
}
