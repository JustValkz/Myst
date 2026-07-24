import { SlashCommandBuilder } from 'discord.js';
import { infoEmbed } from '../lib/embeds.js';
import {
  canManageLicenses,
  denyEmbed,
  removeAdminId
} from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('removeadmin')
  .setDescription('Remove Myst license admin access from a Discord user')
  .addUserOption((option) =>
    option.setName('user').setDescription('User to remove').setRequired(true)
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const user = interaction.options.getUser('user', true);
  const admins = removeAdminId(user.id);

  return interaction.reply({
    embeds: [
      infoEmbed(
        'Admin Removed',
        `<@${user.id}> no longer has license admin access.\n\nCurrent admins:\n${admins.map((id) => `<@${id}>`).join('\n') || 'none (open to first admin setup)'}`
      )
    ],
    ephemeral: true
  });
}
