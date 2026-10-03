---
name: fleet-vault
description: "What you know about a client and what you have learned: read the vault before answering any question about Adolia, Odae or Désirs d'Orient (what they are, their systems, what happened, what a founder decided), and record what happens with fleet-note."
version: 1.0.0
author: CoreCuity
license: proprietary
platforms: [linux]
metadata:
  hermes:
    tags: [Clients, Memory, Vault, Journal, Fleet]
    related_skills: [fleet-health, fleet-task]
---

# fleet-vault — what you know, and how you add to it

The vault is your memory of the clients: a folder of notes at
`/var/lib/fleet-vault`. Part of it was written by the founders and you cannot
change it. Part of it is your own journal, which you extend one dated entry at
a time. You have no other source of client knowledge: not a hostname, not a
config file, not another agent's instructions.

## Read before you answer

For any question about a client, read in this order:

```
read_file(path="/var/lib/fleet-vault/clients/<client>/card.md")
read_file(path="/var/lib/fleet-vault/clients/<client>/timeline.md")
search_files(path="/var/lib/fleet-vault/clients/<client>/journal", pattern="*.md", target="files")
```

then read the newest journal month (and the one before, if the question is
about earlier). `<client>` is the folder name under `clients/`.

- **card.md** — what the client is, what each system is, the founders'
  standing instructions, who the contact is. Founder-approved.
- **timeline.md** — the chronology the vault started from. Founder-approved.
- **journal/** — what you recorded since. Your own record.

How to use what you read:

- Give facts with their dates: "as of 28 Sep".
- A standing instruction on the card is binding. If a request conflicts with
  one, say so and name the founder who set it.
- **When a journal entry and the card disagree, the card wins** — and you tell
  the founders the two disagree.
- **"Not in my vault" is an answer.** Say it in those words, then say which
  tool or person would know: Sentinel for health (`fleet-health`), Plane for
  the state of the work, Meta for ad numbers, a founder for the rest.
- Never fill a gap from a name. What a hostname or a product name suggests is
  not a fact.
- No card for a client → you have nothing founder-approved about it. Say so.

## Write when something happens

```
terminal(command="fleet-note --client=<client> --kind=<kind> --source=<source> --text='<one or two plain sentences>'")
```

Optional: `--ref='<where to find it: channel, Plane ID, message>'`.

| kind | Use it for | Source it needs |
|---|---|---|
| `event` | something that happened or was done | `receipt:<id>`, `plane:<ID-n>`, `sentinel` or `founder:<name>` |
| `decision` | a founder decided something | `founder:Najlaa` or `founder:Massine` — nothing else is accepted |
| `waiting` | work is waiting on someone: say on whom and for what | any |
| `finding` | something you checked and found, that will still matter next week | `receipt:`, `sentinel` or `observation` |
| `lesson` | how to do the job better — goes in the fleet journal: `--client=fleet` | `observation` or `founder:<name>` |

Write an entry when:

- a founder decides or approves something → `decision`, in their words, the same turn
- a delegated run, an audit or a check finishes → `event`, with its receipt id
- you learn that work is blocked on someone → `waiting`
- a founder corrects you → `lesson`, saying what was wrong and what is right

Rules the tool enforces — it refuses the entry and tells you why:

- no amount of money, no email, no phone number, no secret
- no other client's name in a client's journal
- a decision only with a founder as its source
- one or two plain sentences, 15 to 500 characters
- the same entry is not stored twice in a day

Rules that are yours:

- **Record what happened, not what you suppose.** `observation` means you
  checked it yourself this turn. A guess is not an entry.
- **Say who.** "Najlaa approved …", "waiting on the owner for …".
- **No customer of a client, ever** — no name, no order, no message.
- The receipt the tool prints (`id`, `file`) is your proof the entry exists.
  Exit code 4: fix the entry once, per the error. Exit code 5: do not resend;
  tell the founders the vault did not answer.
- You cannot edit or delete an entry. If one is wrong, add a new `finding`
  that says which entry (its `id`) is wrong and what is right.

## One client at a time

A client's folder is that client's. Do not quote it in another client's
channel and do not put two clients in one delegated run.
