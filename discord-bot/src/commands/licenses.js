import { SlashCommandBuilder } from 'discord.js';
import { supabase } from '../lib/supabase.js';
import { errorEmbed, licenseListEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('licenses')
  .setDescription('List Myst license keys')
  .addStringOption((option) =>
    option.setName('search').setDescription('Optional key fragment to search')
  )
  .addIntegerOption((option) =>
    option
      .setName('page')
      .setDescription('Page number (12 keys per page)')
      .setMinValue(1)
      .setMaxValue(100)
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const search = interaction.options.getString('search');
  const page = interaction.options.getInteger('page') || 1;
  const limit = 12;
  const offset = (page - 1) * limit;

  await interaction.deferReply({ ephemeral: true });

  const { data, error } = await supabase.rpc('bot_list_licenses', {
    p_limit: limit,
    p_offset: offset,
    p_search: search
  });

  if (error) {
    return interaction.editReply({
      embeds: [errorEmbed(`License lookup failed: ${error.message}`)]
    });
  }

  if (!data?.ok) {
    return interaction.editReply({
      embeds: [errorEmbed(data?.message || 'License lookup failed.')]
    });
  }

  return interaction.editReply({
    embeds: [
      licenseListEmbed({
        rows: data.rows || [],
        total: data.total || 0,
        offset,
        search
      })
    ]
  });
}
