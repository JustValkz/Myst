import * as addadminCommand from './addadmin.js';
import * as removeadminCommand from './removeadmin.js';
import * as adminsCommand from './admins.js';
import * as deleteCommand from './delete.js';
import * as generateCommand from './generate.js';
import * as licensesCommand from './licenses.js';
import * as resethwidCommand from './resethwid.js';
import * as resethwidallCommand from './resethwidall.js';
import * as updateCommand from './update.js';

export const commandModules = [
  generateCommand,
  licensesCommand,
  deleteCommand,
  resethwidCommand,
  resethwidallCommand,
  addadminCommand,
  removeadminCommand,
  adminsCommand,
  updateCommand
];
