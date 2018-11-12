{ readFile, writeFile } = require 'mz/fs'
{ dirname, join } = require 'path'
globby = require 'globby'
{ parse } = require 'acorn-loose'
{ visit } = require 'ast-types'

esmPackages = require('./modules-using-module/package.json').dependencies


do ->
	try
		results = JSON.parse await readFile './results.json', 'utf8'
	catch
		results = {} # Hold our analysis of each file

		files = await globby './modules-using-module/node_modules/**/*.{js,mjs}'
		for file in files
			source = await readFile file, 'utf8'
			try
				ast = parse source
			catch
				continue # Skip unparsable files

			results[file] =
				isEsm: no # All files are presumed non-ESM unless they contain an import or export statement, as discovered below
				importSources: {} # What modules or files are imported by the import statements of this file
				importStatementsCount: 0 # We track this since importSources dedupes
				exportStatementsCount: 0

			visitImport = (path) ->
				results[file].isEsm = yes
				results[file].importStatementsCount++
				# Adapted from https://github.com/Jam3/detect-import-require/blob/master/index.js#L64
				if path.node.source.type is 'Literal'
					if path.node.source.value[0] is '.' # Relative file path
						importSource = join dirname(file), path.node.source.value
						unresolved = no
						try
							importSource = require.resolve join(process.cwd(), importSource)
							importSource = importSource.replace process.cwd(), '.'
						catch
							try
								importSource = require.resolve join(process.cwd(), "#{importSource}.mjs")
								importSource = importSource.replace process.cwd(), '.'
							catch # Unresolvable for some reason
								unresolved = yes
								console.error "Error: Could not resolve #{importSource} imported by #{file}"
						results[file].importSources[importSource] =
							type: 'file'
							source: path.node.source.value
						results[file].importSources[importSource].resolved = no if unresolved
					else # Bare specifier, so NPM module
						results[file].importSources[path.node.source.value] =
							type: 'package'
							source: path.node.source.value
							isEsm: esmPackages[path.node.source.value]?
				@traverse path

			visitExport = (path) ->
				results[file].isEsm = yes
				results[file].exportStatementsCount++
				@traverse path

			visit ast,
				visitImportDeclaration: visitImport
				visitExportNamedDeclaration: visitExport
				visitExportDefaultDeclaration: visitExport
				visitExportAllDeclaration: visitExport

		for file, result of results
			for importSourceKey, importSourceValue of result.importSources when importSourceValue.type is 'file'
				importSourceValue.isEsm = results[file].isEsm

		try
			await writeFile './results.json', JSON.stringify(results, null, '\t')
