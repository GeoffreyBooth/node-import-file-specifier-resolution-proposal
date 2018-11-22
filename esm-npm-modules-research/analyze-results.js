const results = require('./results.json');

console.log('Analyzing results.json...');

let esmPackageEntryPointsImported = 0;
let cjsPackageEntryPointsImported = 0;
let esmPackageDeepImports = 0;
let cjsPackageDeepImports = 0;
let esmFilesImported = 0;
let cjsFilesImported = 0;

for (const file in results) {
  for (const property in results[file].importSources) {
    const value = results[file].importSources[property];
    if (value.unresolved) {
      continue;
    }
    if (value.type === 'package entry point') {
      if (value.isEsm) {
        esmPackageEntryPointsImported++;
      } else {
        cjsPackageEntryPointsImported++;
      }
    } else if (value.type === 'package deep import') {
      if (value.isEsm) {
        esmPackageDeepImports++;
      } else if (value.isCjs && value.isEsm === false) {
        cjsPackageDeepImports++;
      }
    } else if (value.type === 'file') {
      if (value.isEsm) {
        esmFilesImported++;
      } else if (value.isCjs && value.isEsm === false) {
        cjsFilesImported++;
      }
    }
  }
}

console.log(`ESM package entry points imported: ${esmPackageEntryPointsImported.toLocaleString().padStart(7)}`);
console.log(`CJS package entry points imported: ${cjsPackageEntryPointsImported.toLocaleString().padStart(7)}`);
console.log(`ESM package deep imports: ${esmPackageDeepImports.toLocaleString().padStart(7)}`);
console.log(`CJS package deep imports: ${cjsPackageDeepImports.toLocaleString().padStart(7)}`);
console.log(`ESM files imported:   ${esmFilesImported.toLocaleString().padStart(7)}`);
console.log(`CJS files imported:   ${cjsFilesImported.toLocaleString().padStart(7)}`);
