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
						importSource = path.node.source.value
						unresolved = no
						try
							# Try resolving an auto-supplied .mjs extension first, in case there’s both a file.mjs and a file.js side-by-side
							importSource = require.resolve "#{importSource}.mjs", paths: [dirname(file)]
						catch
							try
								importSource = require.resolve "#{importSource}/index.mjs", paths: [dirname(file)]
							catch
								try
									importSource = require.resolve importSource, paths: [dirname(file)]
								catch # Unresolvable for some reason
									unresolved = yes
									console.error "Error: Could not resolve #{importSource} imported by #{file}"
						importSource = importSource.replace process.cwd(), '.'
						results[file].importSources[importSource] =
							type: 'file'
							source: path.node.source.value
						results[file].importSources[importSource].resolved = no if unresolved
					else if path.node.source.value[0] in ['/', '~'] # Absolute path that the package relies on a build tool to resolve
						console.error "Error: Could not resolve #{path.node.source.value} imported by #{file}"
					else # Package bare specifier or deep import
						specifierParts = path.node.source.value.split '/'
						packageName = if specifierParts[0].startsWith '@' then "#{specifierParts[0]}/#{specifierParts[1]}" else specifierParts[0]
						if path.node.source.value is packageName # Bare specifier only, importing package entry point
							results[file].importSources[path.node.source.value] =
								type: 'package entry point'
								source: path.node.source.value
								isEsm: esmPackages[path.node.source.value]?
						else # Deep import
							importSource = path.node.source.value
							unresolved = no
							try
								# Try resolving an auto-supplied .mjs extension first, in case there’s both a file.mjs and a file.js side-by-side
								importSource = require.resolve "#{importSource}.mjs", paths: ['./modules-using-module']
							catch
								try
									# Try resolving an auto-supplied .mjs extension first, in case there’s both a file.mjs and a file.js side-by-side
									importSource = require.resolve "#{importSource}/index.mjs", paths: ['./modules-using-module']
								catch
									try
										importSource = require.resolve importSource, paths: ['./modules-using-module']
									catch # Unresolvable for some reason
										unresolved = yes
										console.error "Error: Could not resolve #{importSource} imported by #{file}"
							importSource = importSource.replace process.cwd(), '.'
							results[file].importSources[importSource] =
								type: 'package deep import'
								source: path.node.source.value
							results[file].importSources[importSource].resolved = no if unresolved

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
			for importSourceKey, importSourceValue of resultValue.importSources when importSourceValue.type in ['file', 'package deep import']
				importSourceValue.isEsm = results[importSourceKey]?.isEsm
				importSourceValue.isCjs = results[importSourceKey]?.isCjs
		try
			await writeFile './results.json', JSON.stringify(results, null, '\t')
