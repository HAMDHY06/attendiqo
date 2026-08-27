# Dependency security review

`npm audit` previously reported seven moderate **transitive** findings in the Firebase Admin/Google Cloud dependency chain. No force upgrade or major-version upgrade was applied, because it could change deployed Functions behavior without a Node 22 staging run.

Before staging, run `npm.cmd --prefix Firebase/functions audit --omit=dev --json`, record the package names, dependency paths, fixed versions and whether each is reachable from the callable runtime. Apply only a reviewed compatible patch/minor update, then rerun package-boundary, callable, emulator and Node 22 tests. Findings without a safe compatible update remain a release risk with an explicit owner and review date.
