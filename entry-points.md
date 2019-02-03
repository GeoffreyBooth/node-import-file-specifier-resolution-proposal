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

Also, CommonJS is basically finished at this point. In the unlikely event that new CommonJS globals are introduced, they can be added to the list of detected globals in the algorithm above; but more likely, the algorithm above will never need to change even as JavaScript continues to evolve.

### But the chance of an ambiguous detection, where Node cannot definitively detect either ESM or CommonJS is nonzero. That’s not acceptable for a runtime.

Current, pre-ESM versions of Node also have this problem. Users have been writing ESM JavaScript in `.js` files since 2015, and `node ambiguous.js` has been executing such ambiguous files as CommonJS since then.

So all we’re really proposing here is a change in Node’s behavior: rather than executing ambiguous files as CommonJS, Node will henceforth execute them as ESM. This is a very minor breaking change, as there should be no or almost no ambiguous files that behave differently in strict versus sloppy mode in actual practical use by users; such files probably only exist on the hard drives of Node/ESM developers and researchers. By finally documenting what Node is doing in this edge case, we’re making clear to users what Node’s behavior is and how it can be avoided (e.g. by making their entry point file or source code unambiguous).

### What about detecting ambiguous files before trying to evaluate them?

We _could_ avoid the breaking change by adding a step to the beginning of the detection algorithm:

1. Parse the initial entry point and detect if it is ambiguous—no ESM signifiers, no references to CommonJS globals—_and_ that it relies on sloppy mode behavior that would throw or behave differently in strict mode. If it is detected as such an ambiguous sloppy mode file, evaluate as CommonJS.

If the powers that be deem the breaking change to be unacceptable, this logic can be added and the breaking change goes away. But unless someone can point to a real-world use case where the breaking change would affect a significant class of users, however, we view the performance hit of this additional parsing and detection step to not be worth the compatibility preservation.

### But [unambiguous grammar](https://github.com/bmeck/UnambiguousJavaScriptGrammar) has been rejected in the past.

Most of the previous discussion around module mode detection via unambiguous syntax has assumed it would be used for _every_ file, not just the initial entry point. For example, not just `index.js` in `node index.js`, but also `startup.js` in `import './startup.js'`. It is common for at least _some_ files in a project to have neither `import` or `export` statements, for example a `startup.js` file with the entire contents of `console.log('Starting up...')`. Under a “use detection for every file in a project” scenario, detection would have a “tax” of needing to put something like `export {}` in every such ambiguous file.

Having detection for only the initial entry point, however, alleviates this concern. An entry point _should_ import something, or else by definition the program has no side effects other than what it can `console.log` or pipe to `STDOUT`. Even if a user’s program truly imports nothing yet does something useful, per this proposal it will merely execute in strict mode unless the user explicitly tells Node to run it as CommonJS. The “tax” therefore is to continue the using sloppy mode, which has been discouraged since strict mode was introduced in ES5 in 2011.

### But double parsing causes a performance hit.

Like the previous point, most discussion of detection/double parsing assumed that it would happen for _every_ file, not just the initial entry point. Under this proposal, double parsing only occurs for the initial entry point file—_and only if that intial entry point is CommonJS._ (And ambiguous, e.g. the user hasn’t used the `.cjs` extension or `--commonjs` flag.)

So if a CommonJS user wants to avoid the very slight performance hit of double parsing of the initial entry point file, all they need to do is use `.cjs` or `--commonjs`. We feel that this is acceptable in order to provide a zero configuration experience.

### But one typo and the user gets the wrong module system.

When unambiguous syntax was discussed as a method to detect _all_ imported files, a common complaint was something [like](https://github.com/nodejs/modules/pull/150#issuecomment-406515253) “It’s easy to accidentally change the parse goal. A commit adding a single export at the end of a file suddenly changes the parse goal of the whole file.”

This is true if you want to use detection for _all_ files in a project, since many projects might import some ambiguous files (see `startup.js` example above, `console.log('Starting up...')`, or polyfills). But it’s not a significant concern when the only detected file is the initial entry point. As written above, few if any real-world initial entry points should be ambiguous files, and so should generally `require` or `import` something.

Also this “one typo” concern is a bit of a canard—one typo of renaming an `.mjs` file to `.js` could cause it to behave differently, under another implementation. One typo in the ESM-signifying field in `package.json` and the user fails to opt into ESM, under a different implementation. Users can always screw things up; if anything, a detection algorithm is _more_ likely to correctly achieve the user’s intent than requiring them to correctly opt into ESM support.

### But it’s not too much to ask users to always be explicit.

Perhaps, but we’ve seen how popular “zero configuration” is as a feature among projects across the Web in recent years. Under this proposal Node can provide zero configuration ESM.

## References

- https://github.com/nodejs/modules/pull/150#issuecomment-406515253
- https://github.com/nodejs/node-eps/issues/57#issuecomment-300870976
- https://github.com/nodejs/modules/issues/254
