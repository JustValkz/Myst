import { REST, Routes } from 'discord.js';
import 'dotenv/config';
import { commandModules } from '../src/commands/registry.js';

const token = process.env.DISCORD_TOKEN;
const clientId = process.env.DISCORD_CLIENT_ID;

if (!token || !clientId) {
  throw new Error('Missing DISCORD_TOKEN or DISCORD_CLIENT_ID in .env');
}

const commands = commandModules.map((command) => command.data.toJSON());
const rest = new REST({ version: '10' }).setToken(token);

await rest.put(Routes.applicationCommands(clientId), { body: commands });
console.log(`Registered ${commands.length} global slash commands.`);
