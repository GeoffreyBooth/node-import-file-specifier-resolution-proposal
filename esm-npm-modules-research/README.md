# ESM NPM Modules Research

The code in this folder was written to generate the included `results.json` file. You don’t really need to run this code unless you want to regenerate that file or change its form, for example to capture additional metadata about the files being inspected. To do some analysis of the file, run `npm start` (and see `analyze-results.js`, and modify it to your liking).

The contents of `results.json` are an object where each key is a file inside `./modules-using-module/node_modules` and each value is metadata about that file. So before we go any further, let’s discuss the `modules-using-module` folder.

`modules-using-module` is a Node project where hundreds of NPM packages that specify a `"module"` field in their `package.json` files are installed as dependencies. (There are [941 such packages](https://gist.github.com/GeoffreyBooth/1b0d7a06bae52d124ace313634cb2f4a), but not all installed successfully.) See `modules-using-module/install.sh` for the commands used to install its dependencies.

Once all of `modules-using-module`’s dependencies were installed, `npm run get-results` at this level was run to execute `get-results.coffee` which created `results.json`. If you want to recreate `results.json`, first delete `results.json` and then change into `modules-using-module` and run `npm install`, then return to this folder and run `npm install` and `npm run regenerate-results`.

Inside `results.json`, you should see entries like this:

```js
"./modules-using-module/node_modules/2gl/Geometry.js": {
  "isEsm": true,
  "importSources": {
    "@2gis/gl-matrix/vec3": {
      "type": "package",
      "source": "@2gis/gl-matrix/vec3",
      "isEsm": false
    },
    "./modules-using-module/node_modules/2gl/GeometryBuffer.js": {
      "type": "file",
      "source": "./GeometryBuffer",
      "isEsm": true
    },
    "./modules-using-module/node_modules/2gl/math/Box.js": {
      "type": "file",
      "source": "./math/Box",
      "isEsm": true
    }
  },
  "importStatementsCount": 3,
  "exportStatementsCount": 1
},
```

In this case, the package `2gl`’s `Geometry.js` file was parsed, and 3 `import` statements and 1 `export` statement were found. Because there was at least one `import` or `export` statement, `Geometry.js` is flagged as ESM (`isEsm: true`). The resolved paths of the specifiers from the `import` statements are listed as the keys of the `importSources`; the first is a deep import from a CommonJS package, while the others are imports of files that themselves contain `import` or `export` statements and are categorized as ESM. The actual string in the `import` statement’s specifier is saved in the `source` field.
