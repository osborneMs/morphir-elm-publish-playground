#!/usr/bin/env node

// NPM imports
import { Command } from 'commander'
import { make } from './cliAPI'

// logging
require('log-timestamp')

// Set up Commander
const program = new Command()
program
    .name('morphir make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .option('-t, --types-only', 'Only include type information in the IR, no values.', false)
    .parse(process.argv)

const dirAndOutput = program.opts()

// run make
make( dirAndOutput.projectDir, dirAndOutput )