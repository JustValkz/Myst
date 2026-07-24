import { SlashCommandBuilder } from 'discord.js';
import { supabase } from '../lib/supabase.js';
import { errorEmbed, successEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';
import { normalizeLicenseKey } from '../lib/keys.js';

export const data = new SlashCommandBuilder()
  .setName('delete')
  .setDescription('Delete or deactivate a Myst license key')
  .addStringOption((option) =>
    option
      .setName('key')
      .setDescription('License key to delete/deactivate')
      .setRequired(true)
  )
  .addBooleanOption((option) =>
    option
      .setName('force')
      .setDescription('Permanently delete even if redeemed')
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const key = normalizeLicenseKey(interaction.options.getString('key', true));
  const force = interaction.options.getBoolean('force') || false;

  await interaction.deferReply({ ephemeral: true });

  const { data, error } = await supabase.rpc('bot_delete_license', {
    p_key: key,
    p_force: force
  });

  if (error) {
    return interaction.editReply({
      embeds: [errorEmbed(`Delete failed: ${error.message}`)]
    });
  }

  if (!data?.ok) {
    return interaction.editReply({
      embeds: [errorEmbed(data?.message || `No license found for \`${key}\`.`)]
    });
  }

  const mode = data.mode === 'removed' ? 'removed' : 'deactivated';

  return interaction.editReply({
    embeds: [
      successEmbed(
        'License Updated',
        `\`${data.key || key}\` was **${mode}** by <@${interaction.user.id}>.`
      )
    ]
  });
}
