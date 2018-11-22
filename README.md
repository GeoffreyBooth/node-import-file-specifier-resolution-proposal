# File Specifier Resolution in Node.js

**Contributors**: Geoffrey Booth (@GeoffreyBooth), John-David Dalton (@jdalton), Jan Krems (@jkrems), Guy Bedford (@guybedford), Saleh Abdel Motaal (@SMotaal), Bradley Meck (@bmeck)

## Motivating Examples

- A project where all JavaScript is ESM.
- A project where all source is a transpiled language such as TypeScript or CoffeeScript.
- A project where some source is ESM and some is CommonJS.
- A package that aims to be imported into either a Node.js or a browser environment, without requiring a build step.

## High Level Considerations

- The baseline behavior of relative imports should match a browser’s with a simple file server. This implies that `./x` will only ever import exactly the sibling file `"x"` without appending paths or extensions. `"x"` is never resolved to `x.mjs` or `x/index.mjs` (or the `.js` equivalents).
- As browsers support ESM in `import` statements of `.js` files, Node.js also needs to allow ESM in `import` statements of `.js` files. (To be precise, browsers support ESM in files served via the MIME type `text/javascript`, which is the type associated with the `.js` extension and the MIME type served for `.js` files by all standard web servers.) This is covered in summary in [nodejs/modules#149](https://github.com/nodejs/modules/issues/149) with links to deeper discussions.
- Node also needs to allow ESM in `.js` files because transpiled languages such as CoffeeScript lack a way to use the file extension as a place to store metadata, the way `.mjs` does double duty both identifying the file as JavaScript and specifying an ESM parse goal. The only way CoffeeScript could do the same would be creating a new extension like `.mcoffee`, but this is impractical because of the scope of the ecosystem updates that would be required, with related packages like `gulp-coffee` and `coffee-loader` and so on needing updates. (TypeScript has similar issues, though its situation is more complex because of its type definition files.) This is covered in [nodejs/modules#150](https://github.com/nodejs/modules/pull/150).
- Along with `.js` files needing to be able to contain ESM, they also still need to be able to contain CommonJS. We need to preserve CommonJS files’ ability to `require` CommonJS `.js` files, and ESM files need some way to import `.js` CommonJS files.
- The [package exports proposal](https://github.com/jkrems/proposal-pkg-exports) covers how Node should locate an ESM package’s entry point and how Node should locate deep imports of files inside ESM packages. File extensions (and filenames or paths) can be irrelevant for deep imports, allowing specifiers like `"lodash/forEach"` to resolve to a path like `./node_modules/lodash/collections/each.js` via the package exports map. That proposal covers how such files are *located,* while this proposal discusses how such files are *parsed.* The two proposals are intended as complements for each other.
- This proposal only covers `import` statement specifiers; this doesn’t aim to also cover `--eval`, STDIN, command line flags, extensionless files or any of the other ways Node can import an entry point into a project or package. We intend to build on this proposal with a follow up to cover entry points.

## Real World Data

As part of preparing the package exports proposal, @GeoffreyBooth did [research](https://gist.github.com/GeoffreyBooth/1b0d7a06bae52d124ace313634cb2f4a) into public NPM registry packages using ESM syntax already, as identified by packages that define a `"module"` field in their `package.json` files. There are 941 such packages as of 2018-10-22.

A project was created with those packages `npm install`ed, creating a gigantic `node_modules` folder containing 96,923 JavaScript (`.js` or `.mjs`) files. Code was then written to parse all of those JavaScript files with `acorn` and look for `import` or `export` declarations, and inspect the specifiers used in the `import` or `export ... from` statements. The [code for this](./esm-npm-modules-research) is in this repo. Here are the numbers:

- 5,870 `import` statements imported ESM modules (defined as NPM packages with a `"module"` field in their `package.json`) as bare specifiers, e.g. `import 'esm-module'`
- 25,763 `import` statements imported CommonJS modules (defined as packages lacking a `"module"` field) as bare specifiers, e.g. `import 'cjs-module'`
- 1,564 `import` statements imported ESM files within packages, e.g. `import 'esm-module/file'`
- 8,140 `import` statements imported CommonJS files within packages, e.g. `import 'cjs-module/file'`
- 86,001 `import` statements imported relative ESM JavaScript files (defined as files with an `import` or `export` declaration), e.g. `import './esm-file.mjs'`
- 4,229 `import` statements imported relative CommonJS JavaScript files (defined as files with a `require` call or reference to `module.exports` or `exports` or `__filename` or `__dirname`), e.g. `import './cjs-file.js'`

## A Note on Defaults

The `--experimental-modules` implementation takes the position that `.js` files should be treated as CommonJS by default, and as of this writing there is no way to configure Node to treat them otherwise. [nodejs/modules#160](https://github.com/nodejs/modules/pull/160) contains proposals for adding a configuration block for allowing users to override this default behavior to tell Node to treat `.js` files as ESM (or more broadly, to define how Node interprets any file extension). This proposal takes the position that `.js` should be treated as ESM by default within an ESM context, both to follow browsers but also to be forward-looking in that ESM is the standard and should therefore be the default behavior within ESM files, rather than something to be opted into. That doesn’t mean we can’t _still_ provide such a configuration block, for example to enable the `--experimental-modules` behavior, and that might indeed be a good idea. Two proposals for configuration blocks are [`"mode"`](https://github.com/nodejs/node/pull/18392) and [`"mimes"`](https://github.com/nodejs/modules/pull/160), which are complementary to this proposal.

As `import` statements of CommonJS `.js` files appear to be far less popular than imports of ESM `.js` files (the latter are 19 times more common), we come to the conclusion that users are likely to strongly prefer `import` statements of `.js` files to treat those files as ESM rather than CommonJS as Node’s default behavior. `import` statements of `.mjs` files would always be treated as ESM, as they are in both `--experimental-modules` and the new modules implementation.

## Proposal

There are (at least) two parts to module resolution: *location* and *interpretation.* Location is covered by the [resolver specification](https://github.com/nodejs/ecmascript-modules/blob/esm-resolver-spec/doc/api/esm.md), and involves things like taking the specifier string `'underscore'` and finding its package entry point file `./node_modules/underscore/underscore.js`. This proposal covers only the interpretation, or what Node should do once the file is found. For our purposes, interpretation means whether Node should load the package or file as ESM or as CommonJS.

### Parsing files as ESM or as CommonJS

There are four types of `import` statement specifiers:

1. “Bare” specifiers like `'lodash'`, which are the name of a package and refer to the package entry point.
2. “Deep import” specifiers like `'lodash/lib/shuffle.mjs'`, which refer to a file within a package.
3. Relative file specifiers like `'./startup.js'` or `'../config.mjs'`, which refer to a file relative to the importing file.
3. Absolute URL file specifiers like `'file:///opt/nodejs/config.js'`, which refer directly to a file.

In all cases, first Node follows its algorithm to locate a file to load. Once the file is found, Node must then decide whether to load it as ESM or as CommonJS. The algorithm goes as follows:

```
If the file is a package entry point
    And the package’s package.json is detected to be ESM
        Load the file as ESM.
    Else
        Load the file as CommonJS.
Else
    If there is a package.json in the folder where the file is
        And the package.json is detected to be ESM
            Load the file as ESM.
        Else
            Load the file as CommonJS.
    Else
        Go into the parent folder and look for a package.json there
        Repeat until we either find a package.json or hit the file system root
        If we found a package.json
            And the package.json is detected to be ESM
                Load the file as ESM.
            Else
                Load the file as CommonJS.
        Else we reach the file system root without finding a package.json
            Load the file as ESM.
```
			
A `package.json` file is detected as ESM if it contains a key that signifies ESM support, such as the `"exports"` field from the [package exports proposal](https://github.com/jkrems/proposal-pkg-exports) or another ESM-signifying field like [`"mode"`](https://github.com/nodejs/node/pull/18392).

The folder containing the located `package.json` and its subfolders are the *package scope,* and the parent folder is on the other side of a *package boundary.* There can be multiple `package.json` files in a path, creating multiple package boundaries, for example:

```
/usr/src/app/package.json - contains "exports" field, starts ESM package scope
/usr/src/app/index.js - parsed as ESM
/usr/src/app/startup/init.js - parsed as ESM

/usr/src/app/node_modules/sinon/package.json - contains "exports" with 
                                               {"": "./dist/index.mjs",
                                                "/stub": "./dist/stub/index.mjs"}
/usr/src/app/node_modules/sinon/dist/index.mjs - parsed as ESM
/usr/src/app/node_modules/sinon/dist/stub/index.mjs - parsed as ESM

/usr/src/app/node_modules/sinon/node_modules/underscore/package.json - no "exports", starts CJS scope
/usr/src/app/node_modules/sinon/node_modules/underscore/underscore.js - parsed as CommonJS
	
/usr/src/app/node_modules/request/package.json - no "exports", starts CJS package scope
/usr/src/app/node_modules/request/index.js - parsed as CommonJS
/usr/src/app/node_modules/request/lib/cookies.js - parsed as CommonJS
```

The following `import` statements from the above `/usr/src/app/index.js` would parse as follows:

```js
// Package entry points
import sinon from 'sinon'; // ESM
import request from 'request'; // CommonJS

// Deep imports
import stub from 'sinon/stub'; // ESM
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

File extensions are still relevant. While either a `.js` or an `.mjs` file can be loaded as ESM, only `.js` files can be loaded as CommonJS. If the above example’s `cookies.js` was renamed `cookies.mjs`, the theoretical `import cookies from 'request/lib/cookies.mjs'` would throw.

The CommonJS automatic file extension resolution or folder `index.js` discovery are not supported for `import` statements, even when referencing files inside CommonJS packages. Both `import cookies from 'request/lib/cookies'` and `import request from './node_modules/request'` would throw. Automatic file extension resolution or folder `index.js` discovery _are_ still supported for `package.json` `"main"` field specifiers, however, to preserve backward compatibility.

### Specifiers starting with `/` or `//`

These are currently unsupported but reserved for future use. Browsers support specifiers like `'/app.js'` to be relative to the base URL of the page, whereas in CommonJS a specifier starting with `/` refers to the root of the file system. We would like to find a solution that conforms Node closer to browsers for `/`-leading specifiers.

### `createRequireFromPath`

Packages or files located from `require` calls created via [`module.createRequireFromPath`](https://nodejs.org/docs/latest/api/modules.html#modules_module_createrequirefrompath_filename) are *always* parsed as CommonJS, following how `require` behaves now.

### “Dual mode” packages

A package can be “dual mode” if its `package.json` contains both a `"main"` field and an `"exports"` field (or some other ESM-signifying field). An `import` statement of such a package will treat the package as ESM and ignore the `"main"` field. To explicitly import a dual-mode package via its CommonJS entry point, [`module.createRequireFromPath`](https://nodejs.org/docs/latest/api/modules.html#modules_module_createrequirefrompath_filename) could be used.

The ESM and CommonJS versions of a dual-mode package are really two distinct packages, and would be treated as such by Node if both were imported. Unless there is a legitimate use case for such behavior, though, we expect Node would throw an exception if a user tries to import the same package in both modes into the same package scope. Different modes of the same package _should_ be importable if a package boundary separates them, for example if a user’s project imports ESM `lodash` and that project has a dependency which itself imports CommonJS `lodash`.

### “Double importing” of files

There is the possibility of `import` and `createRequireFromPath` both importing the same file into the same package scope, potentially the former as ESM and the latter as CommonJS. Allowing this would likely cause issues, and a solution would need to be worked out to handle this situation.

### “Loose” CommonJS files (files outside of packages)

Currently, `module.createRequireFromPath` can be used to import CommonJS files that aren’t inside a CommonJS package scope. A symlink could also be created from inside a CommonJS package scope to the desired “loose” CommonJS file, or the file could simply be moved inside a CommonJS package scope. Seeing as there is low user demand for ESM files importing CommonJS files outside of CommonJS packages, we feel that these options are sufficient for now.

If user demand grows such that we want to provide a way to use `import` statements to import CommonJS files that aren’t inside a CommonJS package scope, we have a few options:

1. We could treat all `.js` files outside of an ESM package (detected via a `package.json` file with a signifier that the package is ESM, such as having an `"exports"` field) as CommonJS and all `.mjs` files as ESM.
2. We could introduce a `.cjs` extension that Node always interprets as JavaScript with a CommonJS parse goal, the mirror of `.mjs`. (This might be a good thing to add in any case, for design symmetry.) Users could then rename their CommonJS `.js` files to use `.cjs` extensions and import them via `import` statements. We could also support symlinks, so that a `foo.cjs` symlink pointing at `foo.js` would be treated as CommonJS when imported via `import './foo.cjs';`, to support cases where users can’t rename their files for whatever reason.
3. We could implement the `"mimes"` proposal from [nodejs/modules#160](https://github.com/nodejs/modules/pull/160), which lets users control how Node treats various file extensions within a package scope. This would let users save their ESM files with `.mjs` while keeping their CommonJS files as `.js` and use them both. This would be an opt-in to the `--experimental-modules` behavior.
4. Presumably loaders would be able to enable this functionality, deciding to treat a file as CommonJS either based on file extension or some detection inside the file source.
5. We could create some other form of configuration to enable this, like a section in `package.json` that explicitly lists files to be loaded as CommonJS.

Again, we think that user demand for this use case is so low as to not warrant supporting it any more conveniently for now, especially since there are several other potential solutions that remain possible in the future within the design space of this proposal.

### CommonJS files importing ESM

CommonJS import of ESM packages or files is outside the scope of this proposal. We presume it will be enabled via `import()`, where any specifier inside `import()` is treated like an ESM `import` statement specifier. We assume that CommonJS `require` of ESM will never be natively supported.

## Prior Art

- [Package exports proposal](https://github.com/jkrems/proposal-pkg-exports)
- [`"mimes"` field proposal](https://github.com/nodejs/modules/pull/160)
- [Import Maps](https://github.com/domenic/import-maps)
- [node.js ESM resolver spec](https://github.com/nodejs/ecmascript-modules/pull/12)
- [HTML spec for resolving module specifiers](https://html.spec.whatwg.org/multipage/webappapis.html#integration-with-the-javascript-module-system)
