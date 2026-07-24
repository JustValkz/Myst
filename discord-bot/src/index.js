import {
  Client,
  Collection,
  Events,
  GatewayIntentBits,
  MessageFlags,
  REST,
  Routes
} from 'discord.js';
import 'dotenv/config';
import { commandModules } from './commands/registry.js';
import * as updateCommand from './commands/update.js';
import { errorEmbed } from './lib/embeds.js';

const token = process.env.DISCORD_TOKEN;
if (!token) {
  throw new Error('Missing DISCORD_TOKEN in .env');
}

const commands = commandModules;
const commandMap = new Collection();

for (const command of commands) {
  commandMap.set(command.data.name, command);
}

async function registerSlashCommands() {
  const clientId = process.env.DISCORD_CLIENT_ID;
  if (!clientId) {
    console.warn('DISCORD_CLIENT_ID missing — skipping slash command registration.');
    return;
  }

  const rest = new REST({ version: '10' }).setToken(token);
  const body = commands.map((command) => command.data.toJSON());

  await rest.put(Routes.applicationCommands(clientId), { body });
  console.log(`Registered ${body.length} slash commands globally.`);
}

const client = new Client({
  intents: [GatewayIntentBits.Guilds]
});

client.once(Events.ClientReady, (readyClient) => {
  console.log(`Logged in as ${readyClient.user.tag}`);
});

client.on(Events.InteractionCreate, async (interaction) => {
  if (interaction.isButton()) {
    try {
      const handled = await updateCommand.handleButton(interaction);
      if (handled) {
        return;
      }
    } catch (error) {
      console.error('Button interaction failed:', error);
    }
    return;
  }

  if (!interaction.isChatInputCommand()) {
    return;
  }

  const command = commandMap.get(interaction.commandName);
  if (!command) {
    return;
  }

  try {
    await command.execute(interaction);
  } catch (error) {
    console.error(`Command /${interaction.commandName} failed:`, error);

    const detail =
      error?.message && process.env.NODE_ENV !== 'production'
        ? `Something went wrong while running that command.\n\`${error.message}\``
        : 'Something went wrong while running that command.';

    const payload = {
      embeds: [errorEmbed(detail)],
      flags: MessageFlags.Ephemeral
    };

    try {
      if (interaction.deferred || interaction.replied) {
        await interaction.editReply(payload);
      } else {
        await interaction.reply(payload);
      }
    } catch (replyError) {
      console.error(`Failed to send error reply for /${interaction.commandName}:`, replyError);
    }
  }
});

client.on('error', (error) => {
  console.error('Discord client error:', error);
});

process.on('unhandledRejection', (error) => {
  console.error('Unhandled promise rejection:', error);
});

await registerSlashCommands();
await client.login(token);
