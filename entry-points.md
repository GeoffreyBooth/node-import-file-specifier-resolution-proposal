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

### Module format detection

Node will attempt to detect the module format for potentially ambiguous initial entry points (`.js` and extensionless files, string input via `--eval` or `STDIN`). The algorithm for this is as follows:

1. Attempt to evaluate the entry point as ESM.

	If it evaluates, great! Proceed per the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). All `import` statements of `.js` files within the same package scope of the initial entry point are parsed as ESM.

	If it throws a `ReferenceError` that `require`, `module`, `exports`, `__filename`, or `__dirname` are not defined:

2. Attempt to evaluate the entry point as CommonJS.

	If it evaluates, great! Proceed per Node’s legacy CommonJS behavior.

	Otherwise, throw the error and exit.

Note that this detection is **only ever applied to the initial entry point.** Once the initial entry point is evaluated, all subsequent imports follow the rules of the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). Imported packages must have an ESM signifier in their `package.json`s, or use `.mjs` extensions, to be parsed as ESM.

### Explicit module format file extensions

Since `.js` files will be treated as ambiguous and subject to detection, Node will support _two_ file extensions for users to make explicit their module format via file extension:

- `.mjs`: Files with an `.mjs` extension are always parsed as ESM.

- `.cjs`: Files with a `.cjs` extension are always parsed as CommonJS.

Using either file extension will tell Node to skip the detection algorithm and directly parse the file as the associated module format. An `.mjs` file with `require` statements will throw, as will a `.cjs` file with `import` statements.

### Explicit module format command line flags

Since `--eval`, `STDIN` and extenionless files all lack a file extension for users to be explicit about what module format Node should use, Node will provide two command line flags for users to make explicit their module format via flag:

- `--module` and `-m` tell Node to parse as ESM entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`). For example:

  ```bash
  node --module --eval 'import { sep } from "path"; console.log(sep)'
  ```

- `--commonjs` tells Node to parse as CommonJS entry points that would otherwise be ambiguous. For example:

  ```bash
  node --commonjs --eval 'const { sep } = require("path"); console.log(sep)'
  ```

Node will throw an error in the case of conflicting explicit signifiers, e.g. `node --commonjs file.mjs` or `node --module file.cjs`.

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

## FAQ

### Why detect the CommonJS globals rather than `import` or `export`?

If the order of evaluation were reversed, with Node attempting to parse ambiguous code as CommonJS first and falling back to ESM, then the breaking change described above would not occur. “Ambiguous” files would be evaluated in sloppy mode. So why evaluate as ESM first?

Simply put, because ESM is the standard and Node’s performance should be optimized for it. As time goes by, more and more `.js` files will be ESM, and fewer and fewer files will suffer the slight performance hit of the double evaluation when loading the initial entry point. Eventually Node could even decide to deprecate the CommonJS fallback and require users to use one of the explicit CommonJS signifiers (`--commonjs` or `.cjs`) to enable a legacy CommonJS entry point.

### But [unambiguous grammar](https://github.com/bmeck/UnambiguousJavaScriptGrammar)/double parsing has been rejected in the past.

Most of the previous discussion around module mode detection has assumed it would be used for _every_ file, not just the initial entry point. For example, not just `index.js` in `node index.js`, but also `startup.js` in `import './startup.js'`. It is common for at least _some_ files in a project to have neither `import` or `export` statements, for example a `startup.js` file with the entire contents of `console.log('Starting up...')`. Under a “use detection for every file in a project” scenario, detection would have a “tax” of needing to put something like `export {}` in every such ambiguous file. It also would be a performance hit, as potentially every file in a project takes longer to load.

Having detection for only the initial entry point, however, alleviates both concerns. Users are already familiar with specifying how their app should start, for example by defining `package.json`’s `scripts` » `start` field. And giving users ways to make explicit their module mode, either ESM or CommonJS, allows them to avoid the detection entirely with very minimal effort. Users who crave zero configuration, which from anecdotal evidence seems to be a very substantial percentage of users, get what they want; while users who want or need explicitness have easy ways to achieve that as well.
