const results = require('./results.json');

console.log('Analyzing results.json...');

let esmModulesImported = 0;
let cjsModulesImported = 0;
let esmFilesImported = 0;
let cjsFilesImported = 0;

for (const file in results) {
  for (const property in results[file].importSources) {
    const value = results[file].importSources[property];
    if (value.type === 'package') {
      if (value.isEsm) {
        esmModulesImported++;
      } else if (value.isEsm === false) {
        cjsModulesImported++;
      }
    } else {
      if (value.isEsm) {
        esmFilesImported++;
      } else if (value.isEsm === false) {
        cjsFilesImported++;
      }
    }
  }
}

console.log(`ESM modules imported: ${esmModulesImported.toLocaleString().padStart(7)}`);
console.log(`CJS modules imported: ${cjsModulesImported.toLocaleString().padStart(7)}`);
console.log(`ESM files imported:   ${esmFilesImported.toLocaleString().padStart(7)}`);
console.log(`CJS files imported:   ${cjsFilesImported.toLocaleString().padStart(7)}`);
