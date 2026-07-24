import { SlashCommandBuilder } from 'discord.js';
import { infoEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed, getAdminIds } from '../lib/permissions.js';

export const data = new SlashCommandBuilder()
  .setName('admins')
  .setDescription('List Discord users allowed to manage Myst licenses');

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  const admins = getAdminIds();

  return interaction.reply({
    embeds: [
      infoEmbed(
        'License Admins',
        admins.length
          ? admins.map((id) => `<@${id}>`).join('\n')
          : 'No admin list configured yet. Anyone can run admin commands until the first `/addadmin`.'
      )
    ],
    ephemeral: true
  });
}
