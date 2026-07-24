import { SlashCommandBuilder } from 'discord.js';
import { errorEmbed, infoEmbed } from '../lib/embeds.js';
import {
  addAdminId,
  canManageLicenses,
  denyEmbed,
  getAdminIds,
  removeAdminId
} from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('addadmin')
  .setDescription('Allow a Discord user to manage Myst licenses')
  .addUserOption((option) =>
    option.setName('user').setDescription('User to grant access').setRequired(true)
  );

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const user = interaction.options.getUser('user', true);
  const admins = addAdminId(user.id);

  return interaction.reply({
    embeds: [
      infoEmbed(
        'Admin Added',
        `<@${user.id}> can now manage licenses.\n\nCurrent admins:\n${admins.map((id) => `<@${id}>`).join('\n') || 'none'}`
      )
    ],
    ephemeral: true
  });
}
