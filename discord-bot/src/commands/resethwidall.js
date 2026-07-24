import { SlashCommandBuilder } from 'discord.js';
import { supabase } from '../lib/supabase.js';
import { errorEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('resethwidall')
  .setDescription('Reset HWID binding on every redeemed Myst license key')
  .addBooleanOption((option) =>
    option
      .setName('confirm')
      .setDescription('Must be true — clears every bound HWID')
      .setRequired(true)
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const confirm = interaction.options.getBoolean('confirm', true);
  if (!confirm) {
    return interaction.reply({
      embeds: [errorEmbed('Set `confirm` to true to reset every bound HWID.')],
      ephemeral: true
    });
  }

  await interaction.deferReply({ ephemeral: true });

  const { data, error } = await supabase.rpc('bot_reset_all_hwids');

  if (error) {
    return interaction.editReply({
      embeds: [errorEmbed(`Bulk HWID reset failed: ${error.message}`)]
    });
  }

  if (!data?.ok) {
    return interaction.editReply({
      embeds: [errorEmbed(data?.message || 'Bulk HWID reset failed.')]
    });
  }

  return interaction.editReply({
    embeds: [
      {
        color: 0x22c55e,
        title: 'All HWIDs Reset',
        description: [
          `Keys reset: **${data.keys_reset ?? 0}**`,
          `Blacklist entries cleared: **${data.blacklist_cleared ?? 0}**`,
          `Requested by: <@${interaction.user.id}>`
        ].join('\n'),
        footer: { text: 'Myst License Manager' }
      }
    ]
  });
}
