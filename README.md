# Module Interpretation in Node.js

This proposal aims to specify how Node.js should choose between its supported module systems, CommonJS and ECMAScript Modules (ESM), whenever such a decision needs to be made. By covering all cases where one or the other module system could be chosen as part of loading JavaScript source code, this proposal explains how support for ESM can be added to Node while preserving backward compatibility for CommonJS.

> In a hurry? Skip straight to the [Proposal](./proposal.md).

- [Background](./background.md)
  - Motivating examples
  - High level considerations
  - Real world data
  - Note on default treatment of `.js` files

- [Proposal](./proposal.md)
  - Introduction
  - Package scopes and package boundaries
  - Package scope algorithm
  - `package.json` fields
  - `import` statements and `import()` expressions
  - Initial entry points

- [Example](./tutorial.md): Node’s Hello World tutorial written per this proposal

- [Further Considerations](./further-considerations.md)
  - `import` specifiers starting with `/` or `//`
  - `createRequireFromPath` in ESM
  - `import` of “loose” CommonJS files (files outside of packages)
  - CommonJS files inside an ESM package scope
  - CommonJS files importing ESM
  - Constancy expectations when loading files

- [See Also](./see-also.md)

**Contributors**: Geoffrey Booth ([@GeoffreyBooth](https://github.com/GeoffreyBooth)), Guy Bedford ([@guybedford](https://github.com/guybedford)), John-David Dalton ([@jdalton](https://github.com/jdalton)), Jan Krems ([@jkrems](https://github.com/jkrems)), Saleh Abdel Motaal ([@SMotaal](https://github.com/SMotaal)), Bradley Meck ([@bmeck](https://github.com/bmeck))
