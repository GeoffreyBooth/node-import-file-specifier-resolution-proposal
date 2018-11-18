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
				# Use Acorn to parse the source, with the most permissive settings
				ast = parse source,
					ecmaVersion: 10 # Highest supported ES version as of 2018
					allowReserved: yes
					allowReturnOutsideFunction: yes
					allowImportExportEverywhere: yes
					allowAwaitOutsideFunction: yes
					allowHashBang: yes
			catch
				console.error "Error: Could not parse #{file}"
				continue # Skip unparsable files

			results[file] =
				isEsm: no # Presume nothing until we affirmatively detect ESM or CommonJS signifiers
				isCjs: no # A file could be both ESM and CommonJS, e.g. containing both an import statement and a require call
				importSources: {} # What modules or files are imported by the import statements of this file
				importStatementsCount: 0 # We track this since importSources dedupes
				exportStatementsCount: 0

			visitImport = (path) ->
				results[file].isEsm = yes
				results[file].importStatementsCount++
				# Adapted from https://github.com/Jam3/detect-import-require/blob/master/index.js#L64
				if path.node.source?.type is 'Literal'
					if path.node.source.value[0] is '.' # Relative file path
						importSource = join dirname(file), path.node.source.value
						unresolved = no
						try
							# Try resolving an auto-supplied .mjs extension first, in case there’s both a file.mjs and a file.js side-by-side
							importSource = require.resolve join(process.cwd(), "#{importSource}.mjs")
							importSource = importSource.replace process.cwd(), '.'
						catch
							try
								importSource = require.resolve join(process.cwd(), importSource)
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

			visitCallExpression = (path) ->
				if path.node.callee?.name is 'require'
					results[file].isCjs = yes
				@traverse path

			visitMemberExpression = (path) ->
				if path.node.object?.name is 'module' and path.node.property?.name is 'exports'
					results[file].isCjs = yes
				@traverse path

			visitIdentifier = (path) ->
				if path.node.name in ['exports', '__dirname', '__filename']
					results[file].isCjs = yes
				@traverse path

			visit ast,
				visitImportDeclaration: visitImport
				visitExportNamedDeclaration: visitImport
				visitExportDefaultDeclaration: visitExport
				visitExportAllDeclaration: visitExport
				visitCallExpression: visitCallExpression
				visitMemberExpression: visitMemberExpression
				visitIdentifier: visitIdentifier

		for resultKey, resultValue of results
			for importSourceKey, importSourceValue of resultValue.importSources when importSourceValue.type is 'file'
				importSourceValue.isEsm = results[importSourceKey]?.isEsm
				importSourceValue.isCjs = results[importSourceKey]?.isCjs
		try
			await writeFile './results.json', JSON.stringify(results, null, '\t')
