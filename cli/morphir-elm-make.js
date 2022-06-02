#!/usr/bin/env node
'use strict'

// NPM imports
const commander = require('commander')
const cli = require('./cli')

// logging
require('log-timestamp')

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm make')
    .description('Translate Elm sources to Morphir IR')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .option('-o, --output <path>', 'Target file location where the Morphir IR will be saved.', 'morphir-ir.json')
    .option('-t, --types-only', 'Only include type information in the IR, no values.', false)
    .parse(process.argv)

cli.make(program.opts().projectDir, program.opts())
    .then((packageDef) => {
        console.log(`Writing file ${program.opts().output}.`)
        cli.writeFile(program.opts().output, JSON.stringify(packageDef, null, 4))
            .then(() => {
                console.log('Done.')
            })
            .catch((err) => {
                console.error(`Could not write file: ${err}`)
            })
    })
    .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            if (err instanceof Error) {
                console.error(err)
            } else {
                console.error(`Error: ${JSON.stringify(err, null, 2)}`)
            }
        }
        process.exit(1)
    })
