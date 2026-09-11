# Reflections

Cross-phase patterns worth naming on their own, separate from the
phase-by-phase mechanics in [`build-log.md`](build-log.md). Written at the
close of Phase 7 and during Phase 8 — the point where the same mistake
started showing up in three different costumes.

## Scripts attempt things; state files know what happened

Three separate things went wrong across this phase that all rhyme with each
other, worth naming as one pattern instead of three unrelated bugs:
`finish-teardown.sh` printed "complete" while two real deletions had failed
just above it. The original Phase 5 script left a bastion instance running
with zero record of it existing. And Terraform got introduced specifically
*because* both of those are symptoms of the same root cause — imperative
scripts know how to attempt things, not whether they succeeded. A state file
doesn't have that blind spot by construction.

It's not that Terraform is smarter; it's that the entire tool exists because
"trust the script's own claim about what happened" is structurally
unreliable, and by this point there are three separate, lived examples
proving it, not just a definition memorized from a tutorial.

## "Surely that's covered by the other thing"

The Terraform backend-credentials gap and the four separate IAM
`PassRole`/permission gaps from earlier phases are the same shape of mistake
wearing different clothes: two things that feel obviously related — a
provider block and a backend block both talking to the same AWS account, an
EC2 role and the ability to attach it — are not automatically linked just
because a human would assume they should be.

That's not an AWS quirk or a Terraform quirk specifically. It's a property of
how permission and configuration systems tend to get designed in general:
explicit beats implicit, and "surely that's covered by the other thing" is
the exact sentence worth treating with suspicion.

## Five rounds, four wrong theories, one evidence check each

The Terraform install saga — five real rounds, each one a specific theory
eliminated with actual evidence instead of a guess stacked on a guess — is
worth keeping as a reference example independent of Terraform itself.
Xcode/Homebrew, file permissions, Gatekeeper quarantine, force-bottle, and
finally the real cause: a directory sitting where a file was expected.

Four of five theories were wrong, and that's fine — the discipline was in
checking each one before committing to a fix, not in guessing right on the
first try.

## Presented in chat is not the same as present on disk

Small, but it has now happened three times across the whole project
(`app-userdata.sh` in Phase 5, and twice in a row with `versions.tf` here): a
file being *presented* in chat and a file actually *existing* in
`~/Downloads` are two different facts, and commands chained immediately after
a download can easily run before the second one becomes true.

Not a deep lesson, but a cheap and recurring one — worth a standing habit of
a quick `ls ~/Downloads/<file>` before chaining a `mv` onto it, rather than
re-discovering the same gap a fourth time.

## Catching the mismatch at step one instead of step ten

The teardown-mode discrepancy is worth remembering less for the bug itself
and more for the moment right after discovering it: proceeding as if a blank
slate existed, when it didn't, would have been the actual mistake — not the
script quietly drifting from the plan on its own.

Catching "what actually happened doesn't match what I asked for" before
building on top of it is a skill in its own right, and one that won't show up
as a bullet point about NAT gateways or security groups, but absolutely shows
up in whether a real production incident gets caught at step one or step ten.
