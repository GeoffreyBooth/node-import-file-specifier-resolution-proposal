# Background

## Motivating examples

- A project where all JavaScript is ESM.

- A project where all source is a transpiled language such as TypeScript or CoffeeScript.

- A project where some source is ESM and some is CommonJS.

- A package that aims to be imported into either a Node.js or a browser environment, without requiring a build step.

- A package that aims to be imported into either legacy Node environments as CommonJS or current Node environments as ESM.

## High level considerations

- The baseline behavior of relative imports should match a browser’s with a simple file server.

  This implies that `./x` will only ever import exactly the sibling file `"x"` without appending paths or extensions. `"x"` is never resolved to `x.mjs` or `x/index.mjs` (or the `.js` equivalents).

- As browsers support ESM in `import` statements of `.js` files, Node.js also needs to allow ESM in `import` statements of `.js` files.

  To be precise, browsers support ESM in files served via the MIME type `text/javascript`, which is the type associated with the `.js` extension and the MIME type served for `.js` files by all standard web servers.

  This is covered in summary in [nodejs/modules#149][nodejs/modules#149] with links to deeper discussions.

- Node also needs to allow ESM in `.js` files because transpiled languages such as CoffeeScript lack a way to use the file extension as a place to store metadata, the way `.mjs` does double duty both identifying the file as JavaScript and specifying an ESM parse goal.

  The only way CoffeeScript could do the same would be creating a new extension like `.mcoffee`, but this is impractical because of the scope of the ecosystem updates that would be required, with related packages like `gulp-coffee` and `coffee-loader` and so on needing updates.

  TypeScript has similar issues, though its situation is more complex because of its type definition files. This is covered in [nodejs/modules#150][nodejs/modules#150].

- Along with `.js` files needing to be able to contain ESM, they also still need to be able to contain CommonJS.

  We need to preserve CommonJS files’ ability to `require` CommonJS `.js` files, and ESM files need some way to import `.js` CommonJS files.

## Real world data

As part of preparing this proposal, @GeoffreyBooth did [research][npm-packages-module-field-analysis] into public NPM registry packages using ESM syntax already, as identified by packages that define a `"module"` field in their `package.json` files. There are 941 such packages as of 2018-10-22.

A project was created with those packages `npm install`ed, creating a gigantic `node_modules` folder containing 96,923 JavaScript (`.js` or `.mjs`) files.

Code was then written to parse all of those JavaScript files with `acorn` and look for `import` or `export` declarations, and inspect the specifiers used in the `import` or `export ... from` statements. The [code for this][esm-npm-modules-research-code] is in this repo.

### Findings

#### &#x2002; 5,870 `import` statements imported ESM modules<sup>⑴</sup>, as bare specifiers, e.g. `import 'esm-module'`

#### &#x200a; 25,763 `import` statements imported CommonJS modules<sup>⑵</sup>, as bare specifiers, e.g. `import 'cjs-module'`

#### &#x2002; 1,564 `import` statements imported ESM files within packages e.g. `import 'esm-module/file'`

#### &#x2002; 8,140 `import` statements imported CommonJS files within packages, e.g. `import 'cjs-module/file'`

#### &#x200a; 86,001 `import` statements imported relative ESM JavaScript files<sup>⑶</sup>, e.g. `import './esm-file.mjs'`

#### &#x2002; 4,229 `import` statements imported relative CommonJS JavaScript files<sup>⑷</sup>, e.g. `import './cjs-file.js'`

<pre>
 ⑴  packages with a <samp>"module"</samp> field in their package.json.
 ⑵  packages lacking a <samp>"module"</samp> field in their package.json.
 ⑶  files with an <samp>import</samp> or <samp>export</samp> declaration.
 ⑷  files with a <samp>require</samp> call or references to <samp>module.exports</samp>, <samp>exports</samp>, <samp>__filename</samp>, or <samp>__dirname</samp>.
</pre>

## Note on default treatment of `.js` files

This proposal takes the position that `.js` should be treated as ESM by default within an ESM context. This differs from the default behavior of the Node 8-11 `--experimental-modules` implementation which treats `.js` files to be CommonJS sources and `.mjs` to be ESM.

The rationale behind this position is to move towards directions that can:

1. Improve interoperability with browsers where file extension does not affect how they interpret and load a JavaScript source.

2. Be forward-looking in that ESM is the standard and should therefore be the default behavior within ESM files, rather than something to be opted into.

As of this writing, there is no way to modify Node’s default behavior and affect if and when files with a `.js` (or any other) extension should be treated as ESM instead of CommonJS, or other source types, without having to use a special loader (eg `--loader` with `--experimental-modules` for the time being).

Two proposals (at least) were made to try to address this specifically through declarative fields in the `package.json`, affecting the handling of files within the scope of their respective package:

1. **[`"mode"`][nodejs/node/pull/18392]** proposes a `"mode": "esm"` field to force Node to treat all `.js` files as ESM sources.

2. **[`"mimes"`][nodejs/modules#160]** proposes a `"mimes": { … }` block which defines fine-grained mappings for any extension.

The research findings show that `import` statements of CommonJS `.js` files appear to be far less popular compared to imports of ESM `.js` files, which are 19 times more common. From this, we can make an assumption that users in general may be more inclined to “intuitively” prefer `import` statements of `.js` files to be used to import from ESM sources over CommonJS ones. However, it is also the position of the authors that the `.mjs` file extension should retain its current connotation to be by default always treated as an ESM source, unless otherwise reconfigured.


[nodejs/modules#149]: https://github.com/nodejs/modules/issues/149 '[Booth] Web compatibility and ESM in .js files #149 (discussion)'

[nodejs/modules#150]: https://github.com/nodejs/modules/pull/150 '[Booth] ESM in .js files proposals #150 (pr)'

[npm-packages-module-field-analysis]: https://gist.github.com/GeoffreyBooth/1b0d7a06bae52d124ace313634cb2f4a '[Booth] Analysis of public NPM packages using the `"module"` field (gist)'

[esm-npm-modules-research-code]: ./esm-npm-modules-research 'The code to scrub packages (local)'

[nodejs/node/pull/18392]: https://github.com/nodejs/node/pull/18392 '[Bedford] ESM: Implement esm mode flag #18392 (PR)'

[nodejs/modules#160]: https://github.com/nodejs/modules/pull/160 "[Booth] \"mimes\" Field Proposal #160 (PR)"
