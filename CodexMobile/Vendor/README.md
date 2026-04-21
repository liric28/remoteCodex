# Vendor Dependencies

## `textual`

- Source: `Vendor/textual`
- Upstream: `https://github.com/gonzalezreal/textual`
- Purpose: keep builds reproducible inside this repo instead of depending on Xcode's remote package checkout state.

### Why it is vendored

The upstream `textual` package version currently used by this project (`0.3.1`) hits Swift/Xcode actor-isolation build errors in this environment when used as a remote Swift package.

The project therefore points `Textual` to the local package under `Vendor/textual` so:

- builds do not depend on temporary `DerivedData` patches
- the compatibility fix stays versioned in the repository
- future clean builds work without manual package surgery

### Local compatibility patch

The vendored copy contains a small compatibility adjustment in these files:

- `Sources/Textual/Internal/StructuredText/OrderedList.swift`
- `Sources/Textual/Internal/StructuredText/Table.swift`
- `Sources/Textual/Internal/StructuredText/BlockVStack.swift`

The change replaces `onPreferenceChange { @MainActor ... }` write-backs with `Task { @MainActor in ... }` so the package compiles under the toolchain currently used by this project.

### Upgrade guidance

When upgrading `textual`:

1. sync the upstream package into `Vendor/textual`
2. re-apply or remove the compatibility patch as needed
3. run a clean Xcode build and verify `Textual` still resolves from the local package
