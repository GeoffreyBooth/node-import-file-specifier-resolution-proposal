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

## `package.json` configuration

> Coming soon!

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

## Initial entry points

> Coming soon!


[nodejs/ecmascript-modules:esm.md#resolver-algorithm]: https://github.com/nodejs/ecmascript-modules/blob/esm-resolver-spec/doc/api/esm.md#resolver-algorithm '[Node.js] Documentation - ECMAScript Modules - Resolver Algorithm (doc)'

[jkrems/proposal-pkg-exports]: https://github.com/jkrems/proposal-pkg-exports '[Krems et al] Package Exports Proposal (repo)'

[nodejs/node/pull/18392]: https://github.com/nodejs/node/pull/18392 '[Bedford] ESM: Implement esm mode flag #18392 (PR)'
