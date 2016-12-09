## Release Process
### All Releases
1. Update the version number in ReactiveSwift.podspec, and commit to `master`.
2. Create a GitHub release with the commit created in (1).
3. Push the new Pod spec to the Pod Thunk.

### Major and Point Releases with API changes
3. Generate documentations using [Jazzy](https://github.com/realm/jazzy/).
4. Open a PR in ReactiveCocoa.github.io. (TODO: Describe what needs to be changed.)
