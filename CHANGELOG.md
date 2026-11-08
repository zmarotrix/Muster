# Changelog

## 0.2.0, 2026-11-07

- **Search for exactly who you want.** A box on Find sends one `/who` with your own words: a class, a level or range, a zone, a name.
  Class names become the game's class filter, so "priest 40-50" means priests from 40 to 50, and the game's own filters work too.
  Enter or Search sends it. Your last six searches stay as buttons, one click to ask again. Next still walks the levels in bands.
- **Edit the message right on Find.** The message you whisper with is an editable box beside the list, with what they'll read
  filled in for the person you clicked. All messages are still on the Asking tab.

## 0.1.0, 2026-11-07

First build: Stage 1 of `docs/muster-v1.md`, for one recruiter. Not yet run in game.

- **Find:** people asking for a guild in channels you're in, then one `/who` per press of Next, by level band. Only people without a guild,
  needed classes first. Anyone asked, who said no, or who you chose never to see stays hidden; someone asked over 90 days ago shows again.
- **Asking:** three whisper templates with `{name}`, `{class}`, `{level}`, `{guild}`, `{zone}` and `{need}`, and each template's results.
- **People:** a state for everyone (asked, replied, invited, joined, left, said no, declined, never), notes, a role label and a history.
  Replies move people along by themselves, and a clear no is final.
- **Invite** for people who've answered (Shift for anyone else), and **Ask an officer** when you can't invite.
- **Adverts:** one line, a button, and channels you're already in.
- **Results:** joined, stayed 7 and 30 days, by source, template and recruiter.
- **Limits:** 15 seconds between whispers, 20 an hour (never more than 40), 15 minutes between adverts in a channel. Nothing is sent
  without a click.
- Built on NorgannonDB Core 1.17's new shared guild roster.
