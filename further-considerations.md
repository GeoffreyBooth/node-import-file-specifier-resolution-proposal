# Further Considerations

## `import` specifiers starting with `/` or `//`

These are currently unsupported but reserved for future use. Browsers support specifiers like `'/app.js'` to be relative to the base URL of the page, whereas in CommonJS a specifier starting with `/` refers to the root of the file system. We would like to find a solution that conforms Node closer to browsers for `/`-leading specifiers. That may not necessarily involve a leading `/`, for example if Node adopts the [`import:` proposal][import-urls] or something like it; but we would like to preserve design space for a future way to conveniently refer to the root of the current package.

## `createRequireFromPath` in ESM

Packages or files located from `require` calls created via [`module.createRequireFromPath`][nodejs-docs-modules-create-require-from-path] are _always_ parsed as CommonJS, following how `require` behaves now.

## `import` of “loose” CommonJS files (files outside of packages)

Currently, `module.createRequireFromPath` can be used to import CommonJS files that aren’t inside a CommonJS package scope. To import the file via an `import` statement, a symlink could also be created from inside a CommonJS package scope to the desired “loose” CommonJS file, or the file could simply be moved inside a CommonJS package scope. Seeing as there is low user demand for ESM files importing CommonJS files outside of CommonJS packages, we feel that these options are sufficient.

## CommonJS files inside an ESM package scope

One of our use cases is a package in transition, for example that’s migrating from CommonJS to ESM but the migration is not yet complete. This raises the issue of both parse goals (ESM and CommonJS) existing within an ESM package scope; but `import` will always treat JavaScript files within such a scope as ESM.

One way to import such CommonJS files is to use `module.createRequireFromPath`; another would be to move the CommonJS files into or under a folder with an empty `package.json` file, which would create a CommonJS package scope. `import` statements of symlinks inside a CommonJS package scope could also be used.

Of course, perhaps the most straightforward solution would be for users transitioning a package to simply transpile with a tool like Babel, like they do now, until the migration is complete.

We feel that these options are sufficient for now, but if user demand grows such that we want to provide a way to use `import` statements to import CommonJS files that are in an ESM package scope, we have a few options:

1. We could introduce a `.cjs` extension that Node always interprets as JavaScript with a CommonJS parse goal, the mirror of `.mjs`. (This might be a good thing to add in any case, for design symmetry.) Users could then rename their CommonJS `.js` files to use `.cjs` extensions and import them via `import` statements. We could also support symlinks, so that a `foo.cjs` symlink pointing at `foo.js` would be treated as CommonJS when imported via `import './foo.cjs';`, to support cases where users can’t rename their files for whatever reason.

2. We could implement the `"mimes"` proposal from [nodejs/modules#160][nodejs/modules#160], which lets users control how Node treats various file extensions within a package scope. This would let users create a configuration to tell Node to treat certain extensions as ESM and others as CommonJS, for example the `--experimental-modules` pattern of `.mjs` as ESM and `.js` as CommonJS.

3. Presumably loaders would be able to enable this functionality, deciding to treat a file as CommonJS either based on file extension or some detection inside the file source.

4. We could create some other form of configuration to enable this, like a section in `package.json` that explicitly lists files to be loaded as CommonJS.

Again, we think that user demand for this use case is so low as to not warrant supporting it any more conveniently for now, especially since there are several other potential solutions that remain possible in the future within the design space of this proposal.

## CommonJS files importing ESM

CommonJS import of ESM packages or files is outside the scope of this proposal. We presume it will be enabled via `import()`, where any specifier inside `import()` is treated like an ESM `import` statement specifier. We assume that CommonJS `require` of ESM will never be natively supported.

## Constancy expectations when loading files

Files are read as part of the module loading process: source code files and the `package.json` files used to locate those source files or determine those source files’ parse goals. Once a file is loaded for a particular resolved URL, or a `package.json` is read as part of resolving that URL, those files are not read again. If the source file or `package.json` changes on disk, or the virtual representation of the file on disk changes, Node is unaware of the change and will continue to use the cached versions of the files as they existed when Node first read them.

## Dual instantiation

The ESM and CommonJS interpretations of a module have independent storage. The same source module may be loaded as both an ESM version and a CommonJS version in the same application, in which case the module will be evaluated twice (once for each parse goal) and the resulting instances will **never** have the same identity. This means that whilst `import` and `import()` may return a CommonJS `exports` value for a module whose interpretation is confirmed to be CommonJS, `require()` will never return the ESM namespace object for a module whose interpretation is ESM.

Applications that avoid `require()` and only rely on Node’s interpretation of a module, via `import` and `import()`, will never trigger simultaneous instantiation of both versions. With this proposal, the only way to encounter this dual-instantiation scenario is if some part of the application uses `import`/`import()` to load a module **and** some other part of the application overrides Node’s interpretation by using `require()` or  [`module.createRequireFromPath`][nodejs-docs-modules-create-require-from-path] to load that same module.

The choice to allow dual-instantiation was made to provide well-defined deterministic behavior. Alternative behaviors, such as throwing a runtime exception upon encountering the scenario, were deemed brittle and likely to cause user frustration. Nevertheless, dual instantiation is not an encouraged pattern. Users should ideally avoid dual-instantiation by migrating consumers away from `require` to use `import` or `import()`.


[import-urls]: https://github.com/WICG/import-maps#import-urls '[Web Incubator CG] Import Maps Proposal section on `import:` URLs'

[nodejs-docs-modules-create-require-from-path]: https://nodejs.org/docs/latest/api/modules.html#modules_module_createrequirefrompath_filename '[Node.js] Documentation - Modules - createRequireFromPath (doc)'

[nodejs/modules#160]: https://github.com/nodejs/modules/pull/160 '[Booth] "mimes" Field Proposal #160 (PR)'
