# Support for ESM syntax in entry points in Node.js

**Contributors**: Geoffrey Booth (@GeoffreyBooth), Guy Bedford (@guybedford), John-David Dalton (@jdalton), Jan Krems (@jkrems), Saleh Abdel Motaal (@SMotaal), Bradley Meck (@bmeck)

## Overview

This proposal aims to define how Node should determine the module format (CommonJS or ESM) for the following entry point types:

- Direct file with extension, e.g. `node file.js`

- extensionless files, e.g. `/usr/local/bin/npm`

- `--eval`, e.g. `node --eval 'console.log("hello")'`

- `STDIN`, e.g. `echo 'console.log("hello")' | node`

This proposal covers only the parse goal of the _entry point._ Once the entry point is loaded, if it is ESM then the determination of parse goals of imported files is covered by the [Import File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). CommonJS entry points use Node’s existing behavior.

## Proposal

We propose that Node provide the following methods for users to specify the parse goal of the entry point:

1. Entry point files with `.js` extensions or are extensionless are parsed as ESM if they are within an ESM package scope, or CommonJS otherwise.

1. Entry point files that symlinks are parsed as ESM or CommonJS depending on whether the _target_ is in an ESM package scope or has an explicit file extension.

1. Entry point files with `.mjs` extensions are parsed as ESM.

1. Entry point files with `.cjs` extensions are parsed as CommonJS.

1. If Node is run with the `--module` or `-m` command line flag, the entry point is parsed as ESM.

1. If Node is run with the `--commonjs` command line flag, the entry point is parsed as CommonJS.

1. If Node is run with the `--detect-module` command line flag, the entry point is first evaluated as ESM; if that fails, it is evaluated as CommonJS.

### Package scope

Per the [Import File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/), if the entry point is a `.js` file (`node file.js`) the path to `file.js` is searched for the closest `package.json` and that `package.json` is read to see if it has an [ESM-signifying field](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/#parsing-packagejson). If it does, `file.js` is parsed as ESM.

For example, say you have a folder `~/Sites/cool-app`, and in it the files `package.json` and `app.js`. If `package.json` has a field that defines its package scope to be ESM, `node app.js` will run as ESM; otherwise it will run as CommonJS, like today.

All of the above applies identically to extensionless files. `node_modules/typescript/bin/tsc`, for example, would evaluate as ESM if `node_modules/typescript/package.json` contains an ESM-signifying field.

Note that package scope does _not_ apply to `--eval` or `STDIN`. Running `node --eval 'import "fs"'` from within the `cool-app` folder will not apply the folder’s ESM package scope to `--eval`.

### Symlinks

A common case is a globally installed package like NPM, which creates a symlink like `/usr/local/bin/npm`. In NPM’s case, on macOS at least that path is a symlink to `/usr/local/lib/node_modules/npm/bin/npm-cli.js`.

To handle extensionless files like `npm` that are symlinks, the search for ESM package scope will begin at the symlink’s _target._ So in NPM’s case, Node will search for a `package.json` in `/usr/local/lib/node_modules/npm/bin/`, then `/usr/local/lib/node_modules/npm/` (where it finds one).

Alternatively, if the symlink’s target was a file with an `.mjs` extension, it would be evaluated as ESM directly without the package scope search. (Likewise for `.cjs` extensions being evaluated as CommonJS.)

For now there is simply no way to use ESM in an extensionless file that is not a symlink and is not in an ESM package scope, aside from invoking it via `node` with a flag (e.g. `node --module /usr/local/bin/npm`) or setting `--module` to the `NODE_OPTIONS` environment variable.

### `.mjs` file extension

Files with `.mjs` extensions are always parsed as ESM, regardless of package scope. If a flag is used that conflicts with the extension, like `node --commonjs file.mjs`, an error is thrown.

### `.cjs` file extension

Files with `.cjs` extensions are always parsed as CommonJS, regardless of package scope. If a flag is used that conflicts with the extension, like `node --module file.cjs`, an error is thrown.

The `.cjs` extension is needed because otherwise there would be no way to create explicitly CommonJS files inside an ESM package scope. In a CommonJS package, one can deep import an `.mjs` file to load it as ESM despite the package’s CommonJS scope, e.g. `import 'cjs-package/src/file.mjs'`. The `.cjs` extension allows the inverse, e.g. `import 'esm-package/dist/file.cjs'`.

### `--module` flag

`--module` and `-m` tell Node to parse as ESM entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`). For example:

```bash
node --module --eval 'import { sep } from "path"; console.log(sep)'

echo 'import { sep } from "path"; console.log(sep)' | node --module

NODE_OPTIONS='--module' node --eval 'import { sep } from "path"; console.log(sep)'

export NODE_OPTIONS='--module';
node --eval 'import { sep } from "path"; console.log(sep)'
```

### `--commonjs` flag

`--commonjs` tells Node to parse as CommonJS entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`). For example:

```bash
node --commonjs --eval 'const { sep } = require("path"); console.log(sep)'
```

### `--detect-module` flag

`--detect-module` tells Node to detect the module format for potentially ambiguous entry points (`.js` and extensionless files, string input via `--eval` or `STDIN`). The algorithm for this is as follows:

1. Attempt to evaluate the entry point as ESM.

	If it evaluates, great! Proceed per the [File Specifier Resolution proposal](https://github.com/GeoffreyBooth/node-import-file-specifier-resolution-proposal/). All `import` statements of `.js` files within the same package scope of the entry point are parsed as ESM.

	If it throws a `ReferenceError` that `require`, `module`, `exports`, `__filename`, or `__dirname` are not defined:

2. Attempt to evaluate the entry point as CommonJS.

	If it evaluates, great! Proceed per Node’s legacy CommonJS behavior.

	Otherwise, throw the error and exit.

This flag is needed because the user might not know the parse goal of the input. For example, `coffee --eval 'import "fs"'` pipes to Node as `node --eval 'import "fs";'`, but the `coffee` command didn’t know the parse goal of its initial input. Similar situations arise for TypeScript, Babel and other tools that take unknown source code as user input. While the tools themselves could essentially `try`/`catch` with running Node in one mode and then the other, it is more performant and consistent across tools for Node to provide such a service.

Note also that `--detect-module` evaluates “ambiguous” source code, that could evaluate successfully as either ESM or CommonJS, as ESM. This differs from Node’s current behavior of evaluating ambiguous files as CommonJS. This preference for ESM is for performance reasons, as whichever module mode is attempted first will be evaluated sooner. As ESM is the standard it should therefore be the default and run first.
