import {
  ActionRowBuilder,
  ButtonBuilder,
  ButtonStyle,
  SlashCommandBuilder
} from 'discord.js';
import { errorEmbed, infoEmbed } from '../lib/embeds.js';
import { canManageLicenses, denyEmbed } from '../lib/permissions.js';

const UPDATE_MANIFEST_URL =
  process.env.MYST_UPDATE_MANIFEST_URL ||
  'https://raw.githubusercontent.com/JustValkz/Myst/main/update.json';

const INSTALL_SCRIPT_URL =
  process.env.MYST_INSTALL_SCRIPT_URL ||
  'https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1';

export const data = new SlashCommandBuilder()
  .setName('update')
  .setDescription('Show the latest Myst client version from GitHub');

export async function fetchManifest() {
  const response = await fetch(UPDATE_MANIFEST_URL, { cache: 'no-store' });
  if (!response.ok) {
    throw new Error(`GitHub manifest HTTP ${response.status}`);
  }

  return response.json();
}

export function buildUpdateEmbed(manifest) {
  const version = manifest?.version || 'unknown';
  const notes = manifest?.notes || 'No release notes.';

  return infoEmbed(
    `Myst v${version}`,
    [
      notes,
      '',
      `Install script: ${INSTALL_SCRIPT_URL}`,
      manifest?.dll_url ? `DLL: ${manifest.dll_url}` : null
    ]
      .filter(Boolean)
      .join('\n')
  );
}

export function buildUpdateButtons() {
  return new ActionRowBuilder().addComponents(
    new ButtonBuilder()
      .setCustomId('myst_update_refresh')
      .setLabel('Refresh')
      .setStyle(ButtonStyle.Primary),
    new ButtonBuilder()
      .setLabel('Open GitHub')
      .setStyle(ButtonStyle.Link)
      .setURL('https://github.com/JustValkz/Myst')
  );
}

export async function execute(interaction) {
  if (!canManageLicenses(interaction)) {
    return interaction.reply(denyEmbed());
  }

  await interaction.deferReply({ ephemeral: true });

  try {
    const manifest = await fetchManifest();
    return interaction.editReply({
      embeds: [buildUpdateEmbed(manifest)],
      components: [buildUpdateButtons()]
    });
  } catch (error) {
    return interaction.editReply({
      embeds: [errorEmbed(`Failed to load update manifest: ${error.message}`)]
    });
  }
}

export async function handleButton(interaction) {
  if (interaction.customId !== 'myst_update_refresh') {
    return false;
  }

  if (!canManageLicenses(interaction)) {
    await interaction.reply(denyEmbed());
    return true;
  }

  await interaction.deferUpdate();

  try {
    const manifest = await fetchManifest();
    await interaction.editReply({
      embeds: [buildUpdateEmbed(manifest)],
      components: [buildUpdateButtons()]
    });
  } catch (error) {
    await interaction.editReply({
      embeds: [errorEmbed(`Failed to refresh update manifest: ${error.message}`)],
      components: []
    });
  }

  return true;
}
