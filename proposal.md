# Module Interpretation in Node.js Proposal

## Introduction

There are two general areas where Node loads JavaScript and therefore needs a way to know whether to parse the JavaScript source code as CommonJS or as ESM:

1. Initial entry points, such as running `node file.js` on the command line, or running `node` with  `--eval`, piping source code to Node via `STDIN`, or running an extensionless executable JavaScript file with a hashbang.

2. `import` statements and `import()` expressions, where a file or package is specified as the source to be imported, e.g. `import _ from 'lodash'`.

This proposal aims to cover how Node should decide what module system to use for each of the use cases within the above groups. This is the _interpretation_ part of module resolution; the other part is _location._ Locating the code to be interpreted is covered by the [resolver specification][nodejs/ecmascript-modules:esm.md#resolver-algorithm], and involves things like taking the specifier string `'underscore'` and finding its package entry point file `./node_modules/underscore/underscore.js`. Location is out of scope for this proposal. This proposal covers what Node should do once the source code to be parsed has already been located.

A central new concept used by many of the methods suggested in the proposal is the _package scope,_ delineated by _package boundaries._

## Package scopes and package boundaries

A _package scope_ is a folder containing a `package.json` file and all of that folder’s subfolders except those containing another `package.json` file and _that_ folder’s subfolders. A folder containing a `package.json` is a _package boundary._ For example:

```
/usr/                        - outside any package scope
/usr/src/                    - outside any package scope

/usr/src/app/package.json    - in “app” package scope
/usr/src/app/index.js        - in “app” package scope
/usr/src/app/startup/init.js - in “app” package scope
/usr/src/app/node_modules/   - in “app” package scope

/usr/src/app/node_modules/sinon/package.json - in “sinon” package scope
/usr/src/app/node_modules/sinon/lib/sinon.js - in “sinon” package scope
```

The `package.json` files here each create a new package scope for the folder they’re in, and all subfolders down until another `package.json` file creates a new scope below. Thus `/usr/src/app/` and `/usr/src/app/node_modules/sinon/` are each package boundaries, with different package scopes above and below.

Within a package scope, `package.json` files can hold metadata and configuration for the files contained within that scope. This proposal uses this concept to allow `package.json` values to opt in a package into being interpreted as ESM.

Package scopes apply only to files. While a user may execute code via `node --eval` from within a working directory of a particular package scope, that package scope has no effect on the source code passed in via `node --eval`.

## Package scope algorithm

After Node uses the algorithm in the [resolver specification][nodejs/ecmascript-modules:esm.md#resolver-algorithm] to locate a source code file to load, Node must then decide whether to load it as ESM or as CommonJS. If the source code file has an `.mjs` extension, Node is done; the file is loaded as ESM. Otherwise, Node needs to find the `package.json` governing the package scope that the file is in. That package scope algorithm goes as follows:

```
If the file is a package entry point
    And the package’s package.json says to load JavaScript as ESM
        Load the file as ESM.
    Else
        Load the file as CommonJS.
Else
    If there is a package.json in the folder where the file is
        And the package.json says to load JavaScript as ESM
            Load the file as ESM.
        Else
            Load the file as CommonJS.
    Else
        Go into the parent folder and look for a package.json there
        Repeat until we either find a package.json or hit the file system root
        If we found a package.json
            And the package.json says to load JavaScript as ESM
                Load the file as ESM.
            Else
                Load the file as CommonJS.
        Else we reach the file system root without finding a package.json
            Load the file as CommonJS if initial entry point, ESM otherwise.
```

The last case, when we reach the file system root without finding a `package.json`, covers files that are outside any package scope. If such files are the initial entry point, e.g. `node /usr/local/bin/backup.js`, they are parsed as CommonJS for backward compatibility. If such files are referenced via an `import` statement or `import()` expression, they are parsed as ESM.

## `package.json` fields

> Coming soon!

---

## Initial entry points

### Node’s supported initial entry point types

The _initial entry point_ is the first chunk of source code that the Node runtime loads and executes. Traditionally, this is a file passed to the `node` executable, e.g. `node file.js`, though there are a few other ways to start up Node and have it run some code. These are the types of initial entry points supported by Node:

- Direct file with extension, e.g. `node file.js`

- Extensionless files, e.g. `/usr/local/bin/npm`

- `--eval`, e.g. `node --eval 'console.log("hello")'`

- `STDIN`, e.g. `echo 'console.log("hello")' | node`

Node needs some way to know whether to interpret the code in the initial entry point as CommonJS or as ESM. Once that initial code is parsed, files referenced from that initial code are either treated as CommonJS or ESM based on the rules governing `require` and `import` (covered below). Initial entry points parsed as CommonJS follow Node’s existing CommonJS behavior, while initial entry points parsed as ESM follow the rules laid out in this proposal.

### Methods for interpreting initial entry points

The following methods can inform Node how to interpret the initial entry point:

1. Entry point files with `.mjs` extensions are parsed as ESM.

1. Entry point files with `.cjs` extensions are parsed as CommonJS.

1. Entry point files with `.js` extensions or are extensionless are parsed as ESM if they are within an ESM [package scope](#package-scopes-and-package-boundaries), or CommonJS otherwise.

1. Entry point files that symlinks are parsed as ESM or CommonJS depending on whether the _target_ is in an ESM package scope or has an explicit file extension.

1. If Node is run with the `--type=module` or `-m` command line flag, the entry point is parsed as ESM.

1. If Node is run with the `--type=commonjs` command line flag, the entry point is parsed as CommonJS.

1. If Node is run with the `--type=auto` or `-a` command line flag, the entry point is first evaluated as ESM; if that fails, it is evaluated as CommonJS.

### `.mjs` file extension

Files with `.mjs` extensions are always parsed as ESM, regardless of package scope. If a flag is used that conflicts with the extension, like `node --type=commonjs file.mjs`, an error is thrown.

### `.cjs` file extension

Files with `.cjs` extensions are always parsed as CommonJS, regardless of package scope. If a flag is used that conflicts with the extension, like `node --type=module file.cjs`, an error is thrown.

The `.cjs` extension is needed because otherwise there would be no way to create explicitly CommonJS files inside an ESM package scope. In a CommonJS package, one can deep import an `.mjs` file to load it as ESM despite the package’s CommonJS scope, e.g. `import 'cjs-package/src/file.mjs'`. The `.cjs` extension allows the inverse, e.g. `import 'esm-package/dist/file.cjs'`.

### `.js` and extensionless files as initial entry point

Per the [package scope algorithm](#package-scope-algorithm) above, if the entry point is a `.js` file (e.g. `node file.js`) the path to `file.js` is searched for the closest `package.json` and that `package.json` is read to see if it has an [ESM-signifying field](#packagejson-fields). If it does, `file.js` is parsed as ESM.

For example, say you have a folder `~/Sites/cool-app`, and in it the files `package.json` and `app.js`. If `package.json` has a field that defines its package scope to be ESM, `node app.js` will run as ESM; otherwise it will run as CommonJS.

The above also applies to extensionless files. `node_modules/typescript/bin/tsc`, for example, would evaluate as ESM if `node_modules/typescript/package.json` contains an ESM-signifying field.

### Symlinks

A common case is a globally installed package like NPM, which creates a symlink like `/usr/local/bin/npm`. In NPM’s case, on macOS at least that path is a symlink to `/usr/local/lib/node_modules/npm/bin/npm-cli.js`.

To handle extensionless files like `npm` that are symlinks, the search for package scope will begin at the symlink’s _target._ So in NPM’s case, Node will search for a `package.json` in `/usr/local/lib/node_modules/npm/bin/`, then `/usr/local/lib/node_modules/npm/` (where it finds one).

Alternatively, if the symlink’s target was a file with an `.mjs` extension, it would be evaluated as ESM directly without the package scope search. (Likewise for `.cjs` extensions being evaluated as CommonJS.)

For now there is simply no way to use ESM in an extensionless file that is not a symlink and is not in an ESM package scope, aside from invoking it via `node` with a flag (e.g. `node -m /usr/local/bin/npm`) or setting `--type=module` to the `NODE_OPTIONS` environment variable.

### `--type=module` flag

The command line flags `--type=module` and `-m` tell Node to parse as ESM entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`). For example:

```bash
node --type=module --eval 'import { sep } from "path"; console.log(sep)'

echo 'import { sep } from "path"; console.log(sep)' | node -m

NODE_OPTIONS='--type=module' node --eval 'import { sep } from "path"; console.log(sep)'

export NODE_OPTIONS='--type=module';
node --eval 'import { sep } from "path"; console.log(sep)'
```

The name `--type=module` was chosen to match the Web’s `<script type="module">`.

### `--type=commonjs` flag

The command line flag `--type=commonjs` tell Node to parse as CommonJS entry points that would otherwise be ambiguous (`.js` and extensionless files, string input via `--eval` or `STDIN`). For example:

```bash
node --type=commonjs --eval 'const { sep } = require("path"); console.log(sep)'
```

### `--type=auto` flag

The command line flags `--type=auto` and `-a` tell Node to detect the module format for potentially ambiguous entry points (`.js` and extensionless files, string input via `--eval` or `STDIN`). The algorithm for this is as follows:

1. Attempt to evaluate the entry point as ESM.

    If it evaluates, great! Proceed per the rules outlined in this proposal.

    Else if it throws a `ReferenceError` that `require`, `module`, `exports`, `__filename`, or `__dirname` (the CommonJS globals) are not defined:

2. Attempt to evaluate the entry point as CommonJS.

    If it evaluates, great! Proceed per Node’s legacy CommonJS behavior.

    Otherwise, throw the error and exit.

This flag is needed because the user might not know the parse goal of the input. For example, `coffee --eval 'import "fs"'` pipes to Node as `node --eval 'import "fs";'`, but the `coffee` command didn’t know the parse goal of its initial input. Similar situations arise for TypeScript, Babel and other tools that take unknown source code as user input. While the tools themselves could essentially `try`/`catch` with running Node in one mode and then the other, it is more performant and consistent across tools for Node to provide such a service.

Note also that `--type=auto` evaluates “ambiguous” source code, that could evaluate successfully as either ESM or CommonJS, as ESM. This differs from Node’s current behavior of evaluating ambiguous files as CommonJS. This preference for ESM is for performance reasons, as whichever module mode is attempted first will be evaluated sooner. As ESM is the standard it should therefore be the default and run first.

---

## `import` statements and `import()` expressions

### `import` specifiers

There are four types of specifiers used in `import` statements or `import()` expressions:

- _Bare specifiers_ like `'lodash'`

  > They refer to an entry point of a package by the package name.

- _Deep import specifiers_ like `'lodash/lib/shuffle.mjs'`

  > They refer to a file within a package prefixed by the package name.

- _Relative file specifiers_ like `'./startup.js'` or `'../config.mjs'`

  > They refer to a file relative to the location of the importing file.

- _Absolute URL file specifiers_ like `'file:///opt/nodejs/config.js'`

  > They refer directly and explicity to a file by its location.

### Parsing `package.json`

A `package.json` file is detected as ESM if it contains a key that signifies ESM support, such as the `"type"` field from the [package type proposal](https://github.com/guybedford/ecmascript-modules-mode) or the `"exports"` field from the [package exports proposal][jkrems/proposal-pkg-exports] or another ESM-signifying field like [`"mode"`][nodejs/node/pull/18392]. For the purposes of this proposal we will refer to `"type"`, but in all cases that’s a placeholder for whatever `package.json` field or fields end up signifying that a package exports ESM files.

A `package.json` file is detected as CommonJS by the _lack_ of an ESM-signifying field. A package may also export both ESM and CommonJS files; such packages’ files are loaded as ESM via `import` and as CommonJS via `require`.

### Example

```
 ├─ /usr/src/app/                        <- ESM package scope
 │    package.json {                        created by package.json with "type": "esm"
 │      "type": "esm"
 │    }
 │
 ├─ index.js                             <- parsed as ESM
 │
 ├─┬─ startup/
 │ │
 │ └─ init.js                            <- parsed as ESM
 │
 └─┬ node_modules/
   │
   ├─┬─ sinon/                           <- ESM package scope
   │ │    package.json {                    created by package.json with "type": "esm"
   │ │      "type": "esm"
   │ │      "main": "index.mjs"
   │ │    }
   │ │
   │ ├─┬─ dist/
   │ │ │
   │ │ ├─ index.mjs                      <- parsed as ESM
   │ │ │
   │ │ └─┬─ stub/
   │ │   │
   │ │   └─ index.mjs                    <- parsed as ESM
   │ │
   │ └─┬ node_modules/
   │   │
   │   └─┬ underscore/                   <- CommonJS package scope
   │     │   package.json {                 created by package.json with no "type" field
   │     │     "main": "underscore.js"
   │     │   }
   │     │
   │     └─ underscore.js                <- parsed as CommonJS
   │
   └─┬ request/                          <- CommonJS package scope
     │   package.json {                     created by package.json with no "type" field
     │     "main": "index.js"
     │   }
     │
     ├─ index.js                         <- parsed as CommonJS
     │
     └─┬─ lib/
       │
       └─ cookies.js                     <- parsed as CommonJS
```

The following `import` statements from the above `/usr/src/app/index.js` would parse as follows:

```js
// Package entry points
import sinon from 'sinon'; // ESM
import request from 'request'; // CommonJS

// Deep imports
import stub from 'sinon/stub/index.mjs'; // ESM
import cookies from 'request/lib/cookies.js'; // CommonJS

// File specifiers: relative
import './startup/init.js'; // ESM
import cookies from './node_modules/request/lib/cookies.js'; // CommonJS
import stub from './node_modules/sinon/dist/stub/index.mjs'; // ESM
import _ from './node_modules/sinon/node_modules/underscore/underscore.js'; // CommonJS

// File specifiers: absolute
import 'file:///usr/src/app/startup/init.js'; // ESM
import cookies from 'file:///usr/src/app/node_modules/request/lib/cookies.js'; // CommonJS
```

File extensions are still relevant. While either a `.js` or an `.mjs` file can be loaded as ESM, only `.js` files can be loaded as CommonJS. If the above example’s `cookies.js` was renamed `cookies.mjs`, the theoretical `import cookies from 'request/lib/cookies.mjs'` would still load as ESM as the `.mjs` extension is itself unambiguous.

The CommonJS automatic file extension resolution or folder `index.js` discovery are not supported for `import` statements, even when referencing files inside CommonJS packages. Both `import cookies from 'request/lib/cookies'` and `import request from './node_modules/request'` would throw. Automatic file extension resolution or folder `index.js` discovery _are_ still supported for `package.json` `"main"` field specifiers for CommonJS packages, however, to preserve backward compatibility.


[nodejs/ecmascript-modules:esm.md#resolver-algorithm]: https://github.com/nodejs/ecmascript-modules/blob/esm-resolver-spec/doc/api/esm.md#resolver-algorithm '[Node.js] Documentation - ECMAScript Modules - Resolver Algorithm (doc)'

[jkrems/proposal-pkg-exports]: https://github.com/jkrems/proposal-pkg-exports '[Krems et al] Package Exports Proposal (repo)'

[nodejs/node/pull/18392]: https://github.com/nodejs/node/pull/18392 '[Bedford] ESM: Implement esm mode flag #18392 (PR)'
