## What does this change?

<!-- One or two sentences. Link the issue if there is one. -->

## Checklist

- [ ] `swift test` passes
- [ ] `scripts/validate.sh` passes
- [ ] Business-rule changes come with tests in `Tests/WindowHopTests`
- [ ] Every user-facing feature declares its default and configurability decision
- [ ] New preferences use typed centralized defaults, preserve existing values, and are covered by Restore Defaults tests
- [ ] Non-configurable behavior is justified (bug/security/internal/accessibility/single valid outcome)
- [ ] No private APIs, no new dependencies, no polling while idle
- [ ] Documentation updated if behavior changed
