# Support for ESM syntax in entry points in Node.js

**Contributors**: Geoffrey Booth (@GeoffreyBooth), Guy Bedford (@guybedford), John-David Dalton (@jdalton), Jan Krems (@jkrems), Saleh Abdel Motaal (@SMotaal)

## Overview

This proposal aims to define how Node should determine the module format (CommonJS or ESM) for the following entry point types:

- Direct file with extension, e.g. `node file.js`

- extensionless files, e.g. `/usr/local/bin/npm`

- `--eval`, e.g. `node --eval 'console.log("hello")'`

- `STDIN`, e.g. `echo 'console.log("hello")' | node`

This proposal covers only the parse goal of the _entry point._ Once the initial entry point is loaded, if it is ESM then the determination of parse goals of imported files is covered by the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). CommonJS entry points use Node’s existing behavior.

## Proposal

### Explicit module format signifiers

We propose four ways to for the user to be explicit to Node as to what module format the entry point should be parsed as:

- `.mjs`: Files with an `.mjs` extension are always parsed as ESM.

- `.cjs`: Files with a `.cjs` extension are always parsed as CommonJS.

- `--module`: A new command line flag, `--module` and `-m`, tells Node to parse as ESM entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`).

- `--commonjs`: A new command line flag, `--commonjs`, tells Node to parse as CommonJS entry points that would otherwise be ambiguous.

The `NODE_OPTIONS` environment variable can also hold the flags, e.g. `NODE_OPTIONS='--module' node --eval 'import { sep } from "path"; console.log(sep)'`

Node will throw an error in the case of conflicting explicit signifiers, e.g. `node --commonjs file.mjs` or `node --module file.cjs`.

### Module format detection

In addition to the explicit methods listed above, Node will attempt to detect the module format for potentially ambiguous initial entry points (`.js` and extensionless files, string input via `--eval` or `STDIN`). The algorithm for this is as follows:

1. Attempt to evaluate the entry point as ESM.

	If it evaluates, great! Proceed per the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). All `import` statements of `.js` files within the same package scope of the initial entry point are parsed as ESM.

	If it throws a `ReferenceError` that `require`, `module`, `exports`, `__filename`, or `__dirname` are not defined:

2. Attempt to evaluate the entry point as CommonJS.

	If it evaluates, great! Proceed per Node’s legacy CommonJS behavior.

	Otherwise, throw the error and exit.

Note that this detection is **only ever applied to the initial entry point.** Once the initial entry point is evaluated, all subsequent imports follow the rules of the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). Imported packages must have an ESM signifier in their `package.json`s, or use `.mjs` extensions, to be parsed as ESM.

## Notes

### Ambiguous files

The sharp-eyed may have noticed that there’s one edge case that the above detection algorithm turns into a breaking change from pre-ESM versions of Node.

Ambiguous initial entry points (`.js` and extensionless files, string input via `--eval` or `STDIN`) that:

- Lack any `import` or `export` statements; and
- Lack any references to the CommonJS globals `require`, `module`, `exports`, `__filename`, or `__dirname`; and
- Lack a `'use strict';` directive; and
- Include some code that behaves differently in sloppy mode as opposed to strict mode

will be parsed in strict mode now, as opposed to sloppy mode in prior versions of Node.

This is because such an “ambiguous” file evaluates successfully as ESM, despite its lack of `import` or `export` statements, so Node never gets to the fallback attempt of evaluating it as CommonJS. Since it lacks `import` or `export` statements or any of the CommonJS globals, the only practical difference between being evaluated as ESM versus as CommonJS is that ESM mode implies strict mode, whereas CommonJS is sloppy mode.

We view this breaking change as acceptable, likely to affect only users doing research into ESM or strict mode. A file with no imports, not even of `fs` or of networking modules or of packages that use networking modules (like `express`), by definition has no effects on anything other than what gets printed to `STDOUT`. Such scripts are very likely experiments or trivial, and supporting the legacy behavior for such scripts is less of a priority, in our view, than providing the ideal user experience of Node automatically detecting the module mode for almost all cases. A user with such an ambiguous script can always force it to be executed in sloppy mode by running it with `--commonjs`, renaming its extension to `.cjs`, or adding `module.exports = {}` to the source code.
