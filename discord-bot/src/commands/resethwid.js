import { SlashCommandBuilder } from 'discord.js';
import { supabase } from '../lib/supabase.js';
import { errorEmbed, resetHwidEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';
import { normalizeLicenseKey } from '../lib/keys.js';

export const data = new SlashCommandBuilder()
  .setName('resethwid')
  .setDescription('Clear HWID binding on a Myst license key so it can be redeemed on a new PC')
  .addStringOption((option) =>
    option
      .setName('key')
      .setDescription('License key to reset (example: MYST-A7K9M2Q4ZX)')
      .setRequired(true)
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const key = normalizeLicenseKey(interaction.options.getString('key', true));
  if (!key || key.length < 8) {
    return interaction.reply({
      embeds: [errorEmbed('Enter a valid Myst license key.')],
      ephemeral: true
    });
  }

  await interaction.deferReply({ ephemeral: true });

  const { data, error } = await supabase.rpc('bot_reset_hwid', {
    p_key: key
  });

  if (error) {
    return interaction.editReply({
      embeds: [
        errorEmbed(
          `HWID reset failed: ${error.message}\n\nIf this keeps happening, redeploy \`supabase/bot_admin_rpcs.sql\` and \`license_patch_v145.sql\` in Supabase.`
        )
      ]
    });
  }

  if (!data?.ok) {
    return interaction.editReply({
      embeds: [errorEmbed(data?.message || `No license found for \`${key}\`.`)]
    });
  }

  return interaction.editReply({
    embeds: [
      resetHwidEmbed({
        key: data.key || key,
        wasRedeemed: data.was_redeemed !== false,
        previousArtifact: data.previous_artifact || null,
        actor: `<@${interaction.user.id}>`
      })
    ]
  });
}
