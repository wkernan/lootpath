# Brain inbox

Work PRs record what they learned here, one file per issue, instead of editing
`docs/ARCHITECTURE.md`. No two PRs ever edit the same lines, so the brain stops
causing merge conflicts, and no session has to load a 2 MB file to add a
paragraph to it.

## For the PR author

Add `docs/brain/inbox/WKE-<n>.md` (or a short slug when there is no issue), in
the same voice and detail as a brain entry. Include only the sections you
need:

```markdown
# WKE-<n>: <tag and short title>

## §0
**As of <date, time of day>, <tag> (WKE-<n> built, PR open on `main` <sha>: <one-line summary>.)**
<What changed, premises checked, what is open. As a §0 entry today.>

## §7
**<date, time of day> - <tag> (WKE-<n>): <the decision> (<whose words>).**
<Decided / why / not decided. As a §7 entry today.>

## §<n> <section name>
<A change to another section: a new verified fact, a closed risk, a corrected
line. Say exactly which existing text it replaces, quoted, if it replaces any.>
```

A correction to existing brain text, where the brain and the code now
disagree, goes here as well, quoting the line it replaces. The PR body's
"Brain inbox" section names the file.

## For the coordinating session

After merging PRs, fold their inbox files into the brain in one docs-only PR
per batch:

1. Put each file's `## §0` entry at the top of §0 and its `## §7` entry at the
   top of §7, newest first. Apply the other sections where they say.
2. Delete the folded inbox files.
3. Refresh `docs/START-HERE.md` if a lane's state, a binding rule or an open
   decision changed.

Inbox files from PRs still open stay where they are; they are folded when
their PR merges.
