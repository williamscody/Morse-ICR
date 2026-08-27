# Morse ICR

Instant Character Recognition training for Morse Code.

[☕ Support Morse ICR](https://buymeacoffee.com/codycabana)

Morse ICR is a Flutter-based Morse code training app for iOS and Android, built around a "beat the computer" mechanic: the app plays a Morse code character, then gives you a short window to answer it — by speaking or simply recognizing it — before the app's own computer voice announces the character out loud for you. Answering correctly before the computer is "beating the computer," the app's core training loop.

## Features

- Adjustable Character Speed, Recognition Time, and Extra Gap to tune session difficulty
- Character Set selection (A-Z, 0-9, punctuation), or a custom Focus practice list
- Focus keyboard with per-character heat-map accuracy coloring and an all-time "X% Correct" summary
- Three-memory countdown Timer that can auto-stop a session
- Persistent Training Log with per-session notes, cumulative training time, and CSV export
- Computer voice announcements (Voice), and on-device Speech Recognition that credits you for speaking the right answer in time
- Configurable punctuation speaking ("." as Period/Dot, "/" as Slash/Stroke), Morse tone pitch/volume, and voice volume
- Random or fixed character ordering
- All settings persist across app restarts
- In-app Help page with a jump-to-section table of contents

## Help

The following is the content of the app's in-app Help page.

### Getting Started

Morse ICR plays a Morse code character, then gives you a short window to answer — by speaking or simply knowing it — before the computer's voice announces the character out loud. Answering correctly before the computer does is "beating the computer," this app's core training mechanic.

Tap Start on the main screen to begin a session. Tap Stop, or let an active Timer memory count down to zero, to end one.

### Character Speed, Recognition Time & Extra Gap

- **Character Speed (WPM):** how fast each Morse character is played, in words per minute.
- **Recognition Time:** how long you have to answer before the computer announces the character for you. Shorter times make training harder.
- **Extra Gap:** extra silence inserted before the next character starts. It does not affect whether you beat the computer — it only gives Speech Recognition a little more breathing room to finish processing your answer before the next round begins.

All three can be changed mid-session and take effect starting with the next character, never interrupting one already playing.

### Character Set & Focus

The Character Set chips (A-Z, 0-9, Punct) choose which characters are trained. Multiple chips can be selected at once.

The Focus button opens a full keyboard of every common Morse character. Tap characters on or off to build a custom practice list, then tap Done. A Focus list, once set, replaces the chips above entirely and stays active until you select a chip again or edit the Focus list. Clear removes every character from the list.

On the Focus keyboard, each character is colored by your all-time performance with it: red means it's mostly been missed, green means mostly correct, with everything in between scaled against your best-performing character. A character with no color at all has never come up in a session yet.

### Timer

The Timer row stores three duration memories and lets you select one as the active countdown for your next session. When the active timer reaches zero, the session stops automatically, the same as tapping Stop yourself.

Tap the Timer row (only available when not training) to edit any memory's duration or change which one, if any, is selected. Selecting none turns the timer off.

### Training Log

The clock-with-arrow icon at the top left opens the Training Log: every completed session, with its date, time, duration, and the character set or Focus list that was active.

Each entry can be given free-form notes. The log also shows your cumulative training time, and can be cleared or exported as a CSV file via the share sheet.

### Voice & Speech Recognition

Voice controls whether the computer speaks each character's answer out loud once your Recognition Time expires.

Speech Recognition listens for you speaking the answer and credits you if it hears you say it in time. It requires headphones (wired or Bluetooth). If Speech Recognition is on and no headphones are connected, the app will ask you to connect them or turn the toggle off.

### Punctuation Speaking

Choose how the computer announces two punctuation characters: "." as either "Period" or "Dot", and "/" as either "Slash" or "Stroke".

### Morse & Voice Audio

- **Morse Pitch:** the tone frequency of the Morse code sidetone, in Hz.
- **Morse Volume:** playback volume of the Morse tone.
- **Voice Volume:** playback volume of the computer's spoken answer, independent of Morse Volume.

### Random Character Order

When on (the default), characters are drawn randomly from the active set, with repeats allowed. Turning it off instead plays the active set's characters in a fixed, repeatable order — useful mainly for isolating a specific accuracy issue rather than everyday training.

### Getting the Best Recognition Accuracy

- A quiet room helps. Recognition timing is judged from the moment your speech first rises above the room's background noise, so a noisy room can delay real detection or trigger a false one.
- Speak clearly and promptly, at a consistent distance from the mic.
- Faster settings (short Recognition Time, high Character Speed) leave less margin for error — an on-time answer can occasionally miss by a few tens of milliseconds. That's an inherent tradeoff of fast settings, not a defect.

A few limits are inherent to any speech recognizer and not fixable through settings: some letters simply sound alike when spoken in isolation (B/P, M/N, and similar pairs), and a letter occasionally gets missed entirely rather than misheard. If recognition ever stops working entirely for a whole session, that is worth reporting — these smaller misses are not.

---

Created by K3CDY, [Cody Cabana Productions, LLC](https://codycabanaproductions.com).
