# Morse ICR Trainer — Product & Technical Specification v0.2

## 1. Product Purpose

Morse ICR Trainer is an auditory training application designed to develop **instant character recognition (ICR)** in Morse code.

The fundamental training objective is to move the learner from:

**Morse sound → consciously decode dits/dahs → character**

to:

**Morse sound → instantly recognize character**

The application is intended for serious Morse/CW learners, particularly students using high-character-speed training methodologies such as those taught by CW Innovations.

This is **not primarily a Morse copying-speed application**. The objective is auditory pattern recognition and rapid character recall.

---

# 2. Core Training Philosophy

The application must support the following training methodology:

1. Begin at a **character speed intentionally higher than the learner can comfortably decode**.
2. High speed discourages conscious counting of individual dits and dahs.
3. Gradually lower character speed until the learner reaches a challenging but usable recognition zone.
4. Establish this as the learner's **personal character speed**.
5. Once established, character speed remains constant during subsequent training.
6. Training difficulty is then increased by progressively reducing the **recognition time**.
7. The learner should intentionally operate in a difficult "learning zone," potentially missing approximately 30–50% of characters.
8. Missed/problematic characters should be identified and subsequently practiced individually.
9. Problem characters should then be reintegrated into the complete character set.

The application should encourage **pattern recognition**, not conscious Morse-element decoding.

---

# 3. Platforms

The application must target:

- iPhone
- iPad
- Android phones
- Android tablets

Technology:

- Flutter
- Dart
- VS Code development environment
- iOS builds through Xcode
- Android builds through Android SDK

Prefer a single shared Flutter/Dart implementation.

---

# 4. Audio

## CW sidetone

The default Morse audio tone is:

**600 Hz sine wave**

The sidetone frequency should remain constant regardless of WPM.

Make the frequency configurable internally so that a future user preference can be added without redesigning the audio engine.

The Morse information is represented entirely by the temporal envelope of the 600 Hz tone.

## Morse timing

Use standard International Morse timing.

One timing unit is:

**60 / (50 × WPM) seconds**

Therefore:

- dit = 1 unit
- dah = 3 units
- intra-character gap = 1 unit
- inter-character gap = 3 units
- word gap = 7 units

The application should generate Morse audio with precise timing rather than relying on ordinary UI timers.

Timing accuracy is important because the application is specifically intended to train very high character speeds.

---

# 5. Character Speed

Character speed is the WPM used to generate individual Morse characters.

This is **not necessarily normal conversational/copying WPM**.

The application must support unusually high character speeds.

Initial range:

**40–150 WPM**

Allow 1 WPM increments.

The architecture should not artificially prevent future speeds above 150 WPM.

The UI should make high speeds easy to select.

Examples:

- 60 WPM
- 80 WPM
- 90 WPM
- 100 WPM
- 110 WPM
- 120 WPM
- 140 WPM
- 150 WPM

The application should not assume that 50, 60, or 80 WPM represents a high-speed ceiling.

---

# 6. Recognition Time

Recognition time is the interval between the **end of the Morse character** and the computer speaking the answer.

This distinction is critical.

The recognition timer MUST NOT begin when Morse transmission begins.

Correct sequence:

1. Generate character.
2. Play complete Morse character.
3. Morse character ends.
4. Start recognition timer.
5. If the learner does not respond before the timer expires, computer speaks the character.
6. Begin next character according to the selected training mode.

Recognition time should initially support:

**50 ms through 1 second**

with user-adjustable values.

Recommended presets:

- 1000 ms
- 750 ms
- 500 ms
- 250 ms
- 200 ms
- 150 ms
- 100 ms
- 75 ms
- 50 ms

The architecture should allow additional values later.

Recognition time is the primary difficulty variable after the learner's personal character speed has been established.

---

# 7. "Beat the Computer" Mechanic

The core interaction is:

**Morse character → learner recognizes character → learner says character aloud → computer announces answer**

The learner's goal is to say the character **before the computer does**.

The application should eventually use microphone/speech recognition to determine what character the learner said.

For the initial implementation, separate the following concerns:

- Morse generation
- timing
- answer scheduling
- microphone input
- speech recognition
- scoring

Do not tightly couple them.

The audio/timing engine should be testable independently of microphone functionality.

---

# 8. Three-Session Training Cycle

The course's standard training cycle consists of **three timed sessions**. The application must provide three separate countdown timers corresponding to these sessions.

Each timer must **remember its state**, including the user's selected duration, across app launches.

The three sessions are:

### Session A — Selected Character Set

Duration target:

**3–5 minutes**

Train using the user's currently selected character set.

### Session B — Problem Characters

Duration target:

**2–3 minutes**

Train only the user's manually entered problem characters.

### Session C — Selected Character Set

Duration target:

**2–3 minutes**

Return to the same selected character set used in Session A.

The three timers are independent. Changing the duration of one timer must not change the others.

Each timer should remember its own configured duration.

The application should make the three-session sequence obvious to the user.

Example UI concept:

```text
SESSION A
Selected Characters
[ 5:00 ]

SESSION B
Problem Characters
[ 3:00 ]

SESSION C
Selected Characters
[ 3:00 ]
```

The actual visual design may differ, but the three distinct timers must remain obvious.

---

# 9. Countdown Timer Behavior

Each session timer must:

- Display remaining time.
- Count down while its session is active.
- Stop at zero.
- Be independently startable/stoppable.
- Remember its configured duration.
- Persist its configured duration across application launches.
- Not lose its configured duration when the user changes training settings.

The timer should not reset simply because the user changes screens.

If practical, the active timer should also survive normal navigation within the application.

When a session reaches zero:

1. Stop generating new training characters.
2. Finish any currently playing Morse character cleanly if technically appropriate.
3. Stop the recognition cycle.
4. Record the completed session in the training log.
5. Update cumulative training time.

---

# 10. Session A and Session C Character Set

Session A and Session C use the user's **selected character set**.

The selected character set should be saved as part of the training configuration.

The selected set may be:

- Letters A–Z
- Numbers 0–9
- Letters + Numbers
- Punctuation
- Other custom sets supported by the application

Session C should use the selected character set associated with the training cycle.

The application should not silently substitute a different character set.

---

# 11. Problem Characters

Session B uses a manually specified list of problem characters.

The user should be able to enter problem characters into a text field.

Example:

```text
K R F L Y Q
```

The application should treat the entered characters as the active problem-character set.

The problem-character list must be persisted.

The list should remain available when the user returns to the application.

The user should be able to edit or replace the list at any time.

---

# 12. Problem Character Keyboard

When entering problem characters, the application should present **all common Morse characters in one view**.

The objective is to avoid requiring the user to switch between multiple standard device keyboard layouts.

The custom character-entry interface should provide one-tap access to the common Morse character set.

At minimum, include:

- A–Z
- 0–9
- Common Morse punctuation

The interface should make it easy to tap characters to add/remove them from the problem-character set.

A visual indication should show which characters are currently selected.

The exact punctuation list should be defined by the Morse character-set implementation.

The custom character selector should work consistently on:

- iPhone
- iPad
- Android phones
- Android tablets

---

# 13. Initial Prototype

The first functional prototype should be intentionally simple.

It should provide:

- Character speed control
- Recognition time control
- Character-set selection
- Problem-character selection
- Three independent countdown timers
- Start/stop controls
- 600 Hz Morse audio
- Computer voice announcing the character
- Countdown/recognition timer
- Basic indication of success/failure
- Persistent timer settings
- Persistent character-set settings
- Persistent problem-character settings

No accounts.

No cloud services.

No networking.

No unnecessary graphics.

No social features.

No gamification beyond the core "beat the computer" mechanic.

---

# 14. Character Sets

The application must support these training sets:

### Letters

A–Z

### Numbers

0–9

### Letters + Numbers

A–Z + 0–9

### Punctuation

Initially support the common Morse punctuation characters.

The architecture should make character sets data-driven so additional characters can be added without changing the training engine.

---

# 15. Randomization

Characters should be randomly selected from the active character set, uniformly and independently on each draw -- including immediate repeats. (Revised 2026-08-22: an earlier version of this section said to avoid immediately repeating the same character. On-device use showed that rule distorting output at small active-set sizes -- a 2-character focus set was forced into perfect strict alternation every time, which reads as far less random than genuine uniform selection, not more.)

The randomization architecture should eventually support:

- uniform random selection
- weighted selection
- weak/problem-character selection

Do not over-engineer this in the first prototype.

---

# 16. Character Speed Discovery Mode

This is a major feature.

The purpose is to discover the learner's **personal character-recognition speed**.

The methodology should be:

**Start too fast → gradually reduce WPM → find the learner's useful recognition zone.**

Do NOT make the default discovery algorithm start at a comfortable speed and increase upward.

Initial discovery speeds could be:

150 → 140 → 130 → 120 → 110 → 100 → 90 → 80 WPM

The exact starting speed should eventually be user-configurable.

At each speed, present a defined number of characters.

Initially, use approximately 10–20 characters per step.

The learner's accuracy is recorded.

The application should recognize that the objective is **not 100% accuracy**.

A speed where the learner recognizes nothing is too fast.

A speed where the learner recognizes virtually everything effortlessly may be too slow.

The desired region is a challenging recognition zone.

The final implementation should allow the discovery algorithm to become adaptive in a future version.

---

# 17. Personal Character Speed

Once the learner identifies an appropriate speed, save it as:

**Personal Character Speed**

Example:

> Personal Character Speed: 110 WPM

This value becomes the fixed speed for subsequent training sessions unless the learner explicitly changes it.

Do not automatically lower the WPM during normal training.

The philosophy is:

**Find the speed → lock the speed → reduce recognition time.**

---

# 18. Training Mode

Once Personal Character Speed is established:

Example:

**110 WPM**

The WPM remains fixed.

The recognition time becomes the primary variable.

Example progression:

1000 ms  
750 ms  
500 ms  
250 ms  
200 ms  
150 ms  
100 ms  
75 ms  
50 ms

The application should allow the learner to select a preset or custom recognition time.

Eventually, the application may automatically adjust recognition time based on performance.

Do not implement automatic adaptive difficulty until the basic training system is working correctly.

---

# 19. Performance Philosophy

The application should not treat 100% accuracy as the primary goal.

The training philosophy intentionally seeks a difficult zone in which the learner is challenged and may miss approximately **30–50%** of characters.

This should be reflected in the eventual statistics and UI.

Potential future metrics:

- Accuracy
- Characters attempted
- Characters recognized
- Characters missed
- Response time
- Recognition-time setting
- Personal character speed
- Character-specific accuracy

---

# 20. Problem Characters and Targeted Practice

The application should eventually identify characters that consistently cause problems.

Example:

```text
K   42% accuracy
R   48%
F   51%
L   89%
A   94%
```

Problem characters can then be practiced individually.

Training progression:

1. Individual problem character
2. Small group of problem characters
3. Full character set

The system should retain character-level performance data.

The manually entered problem-character list used by Session B remains distinct from automatically calculated performance statistics. This allows the learner to deliberately target characters even before sufficient statistics exist.

---

# 21. Training Log and History

The application must maintain a persistent training log.

Each completed training session should record at minimum:

- Date
- Time
- Session type
- Character set
- Problem-character set, when applicable
- Character speed/WPM
- Recognition time
- Total training time for that session
- Number of characters attempted
- Number recognized correctly, when speech recognition/scoring is available
- Number missed, when scoring is available
- **Notes/comments entered by the user for that session**

## Session Notes

Each training session must provide a place for the user to enter free-form notes or comments.

The notes field should be optional.

Examples of useful notes:

- "Had trouble with K and R."
- "110 WPM felt too fast today."
- "Recognition improved after second session."
- "Tired today."
- "50 ms was too aggressive."

The notes must be saved as part of that individual training-session record and displayed when reviewing the training history.

The notes must persist across app launches.

## Cumulative training time

The application must maintain cumulative total training time.

Cumulative time should be calculated from recorded session durations rather than being a manually maintained counter.

The application should eventually provide a history view showing:

- Total lifetime training time
- Training time by day
- Training time by session
- Training time by character set
- Recent sessions
- Session notes

The architecture should allow future statistics and export functionality.

Training history must persist across application launches.

---

# 22. Training Session Definition

A training session begins when the user starts one of the three session timers and ends when:

- The timer reaches zero, or
- The user manually stops the session.

The log should record the actual elapsed training time, not merely the configured timer duration.

If a user starts a 5-minute timer and stops after 3 minutes 12 seconds, the log should record approximately 3 minutes 12 seconds.

If the timer reaches zero, record the full configured duration.

A session that is started but stopped almost immediately should still be handled consistently; define a minimum meaningful duration only if technically necessary.

---

# 23. Training Log Persistence

Use local persistent storage initially.

Do not require an account or cloud service.

The data model should be designed so that cloud synchronization or export can be added later without redesigning the training engine.

At minimum, persist:

### User configuration

- Personal Character Speed
- Recognition Time
- Selected Character Set
- Problem Characters
- Session A duration
- Session B duration
- Session C duration
- Sidetone frequency (pitch)
- Morse volume
- Voice volume
- Speak "." as: Period or Dot
- Speak "/" as: Slash or Stroke

### Training session records

- Unique session ID
- Date/time started
- Date/time ended
- Session type
- Character set
- Problem-character set
- WPM
- Recognition time
- Actual elapsed training time
- Characters attempted
- Correct responses
- Missed responses
- User notes/comments

---

# 24. UI

The UI should be minimalist.

No spectrum displays.

No Morse visualizations.

No flashing dots/dashes.

No character display during recognition.

The learner should primarily **hear** the Morse.

The character itself must NOT be displayed before or during recognition.

The computer's answer is audio.

The UI should clearly communicate:

- WPM
- Recognition time
- Current training set
- Problem-character set when applicable
- Session A/B/C
- Countdown timer
- Start/Stop
- Basic result/status

The UI should be comfortable on both phone and tablet screens.

---

# 25. Timing Architecture

This is a critical technical requirement.

Do not use ordinary Flutter UI timers as the source of truth for Morse audio timing.

The audio engine should schedule audio events using an appropriate high-resolution mechanism.

UI timers may be used to display countdown information, but they must not determine the actual Morse timing.

The timing engine should be independently testable.

For example, given:

**90 WPM**

the engine should reliably produce:

- dit ≈ 13.333 ms
- dah ≈ 40.000 ms
- intra-character gap ≈ 13.333 ms
- inter-character gap ≈ 40.000 ms

The system should minimize cumulative timing drift.

---

# 26. Audio Architecture

Separate:

### Morse generator

Converts a character into a sequence of timed dit/dah events.

### Audio engine

Generates/plays the 600 Hz tone according to the Morse timing.

### Training engine

Controls:

- character selection
- timing state
- recognition deadline
- answer announcement
- scoring
- session countdown

### Speech engine

Speaks the answer.

### Speech recognition engine

Eventually detects the learner's spoken response.

These should be separate components.

---

# 27. Speech Recognition

The learner should eventually be able to simply say:

> "A"

rather than pressing a button.

The system should determine:

- what character the learner said
- whether it matches the target
- whether it occurred before the recognition deadline

Speech recognition latency must be considered separately from the learner's actual response time.

Do not initially assume that the speech-recognition API's callback time represents the exact instant the learner spoke.

This needs to be investigated and tested.

The architecture should allow the speech-recognition implementation to be replaced or improved later.

---

# 28. Computer Voice

When recognition time expires, the computer announces the character.

Example:

Morse:

`.−`

Recognition timer:

**250 ms**

If the learner has not successfully responded before the deadline:

> "A"

The voice should be clear and concise.

The speech voice should be configurable later.

---

# 29. Important Timing Question

The application should define the timeline precisely:

```text
Morse starts
      ↓
Morse plays
      ↓
Morse ends
      ↓
Recognition timer starts
      ↓
      ├── learner responds correctly
      │        ↓
      │      SUCCESS
      │
      └── recognition deadline expires
               ↓
         computer says character
               ↓
              MISS
```

This sequence must be implemented and tested explicitly.

---

# 30. Testing Requirements

Before adding complex UI or statistics, create automated tests for:

### Morse timing

Verify timing calculations at:

- 40 WPM
- 60 WPM
- 90 WPM
- 100 WPM
- 120 WPM
- 150 WPM

### Morse encoding

Verify every A–Z and 0–9 character.

### Recognition timing

Verify that recognition time begins only after Morse playback ends.

### Character selection

Verify valid selection from each character set.

### Randomization

Verify that the selected character always belongs to the active set.

### Scoring

Verify:

- correct response before deadline = success
- incorrect response = failure
- response after deadline = failure
- no response before deadline = failure

### Session timers

Verify:

- Session A, B, and C have independent durations.
- Each duration persists across app launches.
- A running timer counts down correctly.
- Timer expiration records the session.
- Manual stopping records actual elapsed time.
- Session notes are saved with the correct session.
- Cumulative training time equals the sum of recorded session durations.

---

# 31. Development Strategy

Implement incrementally.

### Milestone 1

Flutter project and architecture.

### Milestone 2

600 Hz Morse audio engine.

### Milestone 3

High-speed Morse timing tests.

### Milestone 4

Simple training screen.

### Milestone 5

Character generation and training loop.

### Milestone 6

Recognition timer.

### Milestone 7

Computer speech announcement.

### Milestone 8

Manual user entry of problem characters (sections 11, 12, 39): a "Prob" button on the training screen opens a custom keyboard (A-Z, 0-9, and common punctuation) for entering the problem-character set; the next session started trains only those characters.

### Milestone 9

Three-session training cycle and persistent countdown timers.

### Milestone 10

Persistent training log, cumulative training time, and session notes.

### Milestone 11

Problem-character training.

### Milestone 12

Settings screen (section 35): Speak "." as Period/Dot, Speak "/" as Slash/Stroke, Morse pitch, Morse volume, Voice volume -- all persisted per section 23.

### Milestone 13

On-device, enrollment-based speech recognition (section 38), as a candidate replacement for the general-purpose speech-recognition engine implemented earlier (`package:speech_to_text`, section 27).

### Milestone 14

Beat-the-computer scoring. Sequenced after Milestone 13 since scoring ingests data from whichever speech-recognition engine is in use, and Milestone 13 is expected to be the one actually relied on.

**Status: done, 2026-08-30 (Bill).** Delivered as part of the Focus/Problem Character work rather than a separate feature: every response is tallied win/loss per character (`TrainingScreen._sessionHits`/`_sessionMisses`), folded into an all-time per-character score (`ProblemCharacterStore`/`_persistCharacterScores`), and surfaced as the Focus keyboard's heat-map chip coloring (section 39, `ProblemCharacterKeyboard._heatMapColor`). No further work planned here.

### Milestone 15

Character-level statistics. Sequenced after Milestone 13 for the same reason as Milestone 14.

**Status: done, 2026-08-30 (Bill).** Same mechanism as Milestone 14 above -- the persisted per-character win score *is* the character-level statistic, and the Focus keyboard's heat map *is* its presentation. No separate statistics screen planned.

### Milestone 16 (experimental)

Personal character-speed discovery.

**Status: abandoned, 2026-08-30, at Bill's explicit direction.** Not pursued.

Do not implement everything at once.

Each milestone should produce a runnable/testable application.

---

# 32. Engineering Principles

Use simple, maintainable Dart.

Prefer clear architecture over clever architecture.

Keep platform-specific code isolated.

Do not introduce packages unless there is a concrete need.

Before adding a dependency, explain:

1. Why it is needed.
2. What platforms it supports.
3. Whether it works on current iOS and Android.
4. Whether it introduces CocoaPods, Swift Package Manager, or other native dependencies.

Avoid unnecessary dependencies.

The application should remain usable offline.

---

# 33. Product Principle

The application exists to train the brain to recognize Morse characters as **whole auditory patterns**.

Every design decision should be evaluated against this question:

> **Does this feature reinforce instant auditory character recognition, or does it make conscious decoding easier?**

If a proposed feature encourages the learner to visualize or consciously count dits and dahs, it should be treated skeptically.

---

# 34. Current Development Task

Do NOT immediately implement the entire specification.

First:

1. Inspect the existing Flutter project.
2. Establish a clean Git baseline if not already present.
3. Propose a simple project architecture.
4. Identify the minimum Flutter packages required.
5. Identify any package/platform risks.
6. Implement only the first milestone.
7. Run tests.
8. Build and run on the connected iPhone.
9. Report exactly what was changed and how it was tested.

Do not make broad architectural changes without explaining them first.

The human product owner will make product decisions; the AI coding agent should handle implementation details.

---

# 35. Settings Screen

A dedicated Settings screen should let the learner adjust preferences that don't belong on the main training screen (section 24 keeps that screen minimal) but still affect the training experience.

## Speak "." as: Period or Dot

The learner should be able to choose whether the punctuation character "." (section 14) is announced as:

- "Period"
- "Dot"

## Speak "/" as: Slash or Stroke

The learner should be able to choose whether the punctuation character "/" is announced as:

- "Slash"
- "Stroke"

## Morse: Pitch

Adjusts the CW sidetone frequency (section 4), which section 4 already requires to be internally configurable in anticipation of this preference.

## Morse: Volume

Adjusts the playback volume of the Morse tone, independent of Voice volume.

## Voice: Volume

Adjusts the playback volume of the computer's spoken answer (section 28), independent of Morse volume.

## Persistence

All Settings screen preferences must be persisted across app launches, joining the persisted configuration described in section 23.

---

# 36. Voice Quality Selection

The application automatically selects the highest-quality installed English voice for the computer's spoken answer (section 28), ranking Premium > Enhanced > (plain) Default. This ranking always wins over whichever voice the operating system has marked as its own default for that language -- the OS default is used only as a fallback when no Enhanced/Premium voice is installed at all.

This matters because both iOS and Android ship a low-quality "compact"/basic voice out of the box; Enhanced and Premium voices are optional downloads the learner must install manually to get noticeably clearer, more natural speech. The application cannot download a voice on the learner's behalf -- only detect and prefer one that's already installed.

## How to install a higher-quality voice

### iPhone / iPad

Settings -> Accessibility -> Spoken Content -> Voices -> English -> choose a voice (e.g. Samantha, Ava) -> select an Enhanced or Premium quality option to download it. The application picks it up automatically the next time it launches; no in-app action is required.

**Recommended: Samantha (Enhanced).** On-device testing (Milestone 13, 2026-08-23) found the default "compact" voice's rendering of "M" ("em") and "N" ("en") was audibly indistinguishable, even after trying several alternate spellings for "M" ("emmm", "em-uh", "ehm" -- none fixed it, since the compact voice's synthesis artifacts were the actual cause, not word choice). Switching to Samantha (Enhanced) resolved it immediately, with "M" back at its plain "em" spelling. Treat "the computer's speech sounds unclear/confusable" as a voice-quality question first, not a word-choice or code question.

### Android phone / tablet

Settings -> Accessibility -> Text-to-speech output (exact path varies by manufacturer and Android version) -> select the active TTS engine (commonly Google Text-to-Speech) -> Install voice data, then choose a higher-quality voice for the desired language. The application picks it up automatically the next time it launches.

No specific voice recommendation yet for Android -- untested as of 2026-08-23, to be revisited later.

## Relationship to the Settings screen (section 35)

Section 35's future Settings screen may eventually let the learner pick a specific voice explicitly. Until then, this automatic quality-ranking behavior is the only mechanism, and it already runs on every launch without any user-facing setting.

---

# 37. Lock Screen / Background Media Session (implemented, reverted, reintroduced in reduced form)

**2026-08-18: reverted.** This section originally specified a lock-screen/Control Center/Dynamic Island "Now Playing" card via `package:audio_service`, and it was implemented and shipped. It was removed at Bill's explicit direction -- the lock-screen card wasn't actually needed for the app's real use case (training with wireless headphones, phone in a pocket, screen locked), and `TrainingAudioHandler`'s `.playback` media-session management was found to be fighting `speech_to_text`'s own `.playAndRecord` AVAudioSession category churn (section 27), contributing to several hard-to-diagnose audio bugs during Milestone 8 debugging. Background execution itself (section 3/25 -- training keeps running with the screen locked) is still required and was **not** meant to be given up, but the two platforms aren't symmetric here: on iOS, background playback only ever needed `UIBackgroundModes: audio` declared, not `audio_service`, so it's unaffected by this revert. On Android, `audio_service` was the only thing providing the foreground service (and its permissions/manifest entries) that background execution there actually depends on -- removing it means Android training will **not** survive backgrounding until a foreground service is reintroduced some other way. Given Android hasn't been verified/tested at all yet (a separate open task), this gap is deliberately left unaddressed for now rather than silently masked. The original spec text is preserved below for context; do not re-add `audio_service` without re-evaluating the AVAudioSession conflict it caused.

**2026-08-21: reintroduced, in deliberately reduced form, iOS only.** Bill asked to revisit this with a much narrower goal than the original: no remote app control at all, just an indication of what's producing audio on the lock screen, and a tap to jump back into the app. Before reintroducing `package:audio_service`, its native iOS source (`AudioServicePlugin.m`) was read directly to check whether the 2026-08-18 conflict could recur -- confirmed it never sets `AVAudioSession`'s category or activation itself (only ever reads the shared instance), so `audio_session_setup.dart` remains the sole owner of that lifecycle, unchanged from today. `TrainingAudioHandler` (`lib/audio/training_audio_handler.dart`) shows a "Morse ICR Trainer -- Training in progress" card while a session runs (mirrored from the same Start/Stop path `TrainingScreen` already drives, via `reportTraining()`/`reportIdle()`) and drops it when the session actually stops. Wired only on iOS (`Platform.isIOS` in `main.dart`) -- Android still has no foreground-service plumbing, and that gap remains exactly as described in the note above, deliberately unaddressed for now.

One confirmed iOS quirk worth documenting: `MPRemoteCommandCenter` hard-codes its Play/Pause toggle as always enabled the instant a Now Playing session starts playing -- unlike every other transport control, this one can't be hidden or omitted (confirmed against the native source; every other command respects an empty controls list, this one doesn't). A first pass wired that toggle to the same Start/Stop handler the in-app button uses, but on-device testing showed tapping it stopped training *and* immediately dropped the card itself -- correct behavior (the underlying audio genuinely stopped), but it defeated the actual goal of a card that stays put as a quick way back into the app. The toggle is now a deliberate no-op: tapping it visibly flips its own icon between play and pause but does nothing to the training session -- expected behavior, not a bug. Tapping the card's body (not the toggle) is what opens the app, which iOS provides automatically for any active Now Playing session and needed no code here. A true pause/resume that kept the card alive through a real stop would require `TrainingEngine` to grow a genuine paused state distinct from stopped (keeping the audio session and the keep-alive tone running while only the character-generation loop halts) -- not attempted, since it reopens the state-machine complexity that motivated the original 2026-08-18 revert.

---

Registers the running training session with the OS media session (`package:audio_service`) so a "Morse Training" card appears on the lock screen, in Control Center, and in the iOS Dynamic Island while a session is active, with a Stop control; Android gets the equivalent foreground-service notification.

This is a thin OS-integration layer alongside the section 26 Audio Architecture components, not a replacement for any of them: `TrainingEngine` still owns the character-generation loop and drives the Morse generator, audio engine, and speech engine directly, exactly as section 26 specifies. The media-session layer only mirrors `TrainingEngine.isRunning` into a single session-level `MediaItem` and forwards remote Play/Stop taps back to the training screen -- it never plays audio itself and has no per-character knowledge, since the underlying playback is a rapid stream of short tone/speech bursts rather than one continuous track.

Per section 32's dependency-justification requirement:

1. **Why needed**: without it, an already-running background session (section 3/25) has no lock-screen/Control Center/notification presence, and Android has no foreground service at all -- background playback can be killed by the OS once the app is backgrounded there.
2. **Platforms**: `audio_service` supports iOS, Android, macOS, web, and others; both required platforms (section 3) are covered.
3. **iOS/Android compatibility**: confirmed against iOS 13+ deployment target and current Android `minSdk`/`targetSdk` from the Flutter Gradle config already in use.
4. **Native dependencies added**: pulls in `package:audio_session` (used to configure the shared `AVAudioSession` once, app-wide, replacing the ad hoc per-plugin category calls this project previously made); on Android, requires an `AudioService` foreground-service declaration and a `MediaButtonReceiver` in `AndroidManifest.xml`, plus `MainActivity` extending `AudioServiceActivity` instead of `FlutterActivity`. No CocoaPods/SPM changes beyond what `flutter pub get` already manages.

---

# 38. On-Device, Enrollment-Based Speech Recognition

The speech recognition implemented for this application (section 27) uses a general-purpose, open-vocabulary engine (`package:speech_to_text`). That engine's job -- transcribing arbitrary spoken language -- is much harder than what this application actually needs, and on-device testing surfaced real costs from that mismatch: 700ms-1.5s recognition latency, and no usable per-result confidence signal (on-device recognition reports 0 confidence rather than a real score).

This application only ever needs to recognize one spoken character at a time, from a small, fixed, already-enumerated vocabulary: the letters and digits (section 15), plus the punctuation characters and their spoken-name variants (sections 14, 35). That is a **closed-set isolated-word classification** problem, not open-vocabulary transcription -- the same category as wake-word detection or old touch-tone-replacement digit recognizers, and a substantially lighter computational load than general ASR.

## Enrollment

Rather than a general acoustic model meant to generalize across every speaker, this recognizer is trained on exactly one speaker: the learner using the app. A one-time, guided enrollment session prompts the learner to speak each character in the active vocabulary (A-Z, 0-9, and the punctuation set) aloud, once each, and records the resulting short audio clip as that character's reference "training element."

This sidesteps the hardest part of building a custom recognizer -- collecting enough labeled training data to generalize across accents, dialects, and recording conditions -- by not generalizing at all. The recognizer only ever needs to match the one voice and dialect it was enrolled against.

Re-enrollment (redoing some or all characters) should be supported, since a single bad take, a changed microphone/headphone setup, or a learner wanting to improve accuracy are all plausible.

## Recognition

At recognition time, a newly heard short utterance is compared against the enrolled training elements for the active character set, and matched to whichever element it's closest to, if any element is close enough. The comparison should be cheap enough to run well within the recognition-timing budget established in sections 6 and 29 -- a small fraction of the 700ms-1.5s this application currently pays for general transcription.

The specific matching technique (e.g. dynamic time warping over MFCC/mel-spectrogram features, versus a small trained classifier) needs investigation and testing, the same way section 27 already flags for the general-purpose engine. A pure-Dart template-matching approach is worth trying first, per section 32's preference for avoiding unnecessary dependencies -- it would need no TFLite/Core ML/native ML dependency at all. Whether that reaches usable accuracy, or a small on-device model is needed instead, is an open question for implementation to answer.

## Relationship to the existing speech-recognition engine

This does not replace [`ResponseListener`](section 27's architecture requirement that the speech-recognition implementation be swappable) -- it's a second implementation behind the same interface, so it can be developed, tested, and compared against the existing general-purpose engine without disturbing `TrainingEngine` or the rest of the training loop. Whether it fully replaces the existing engine, or becomes a selectable alternative, is a product decision for after it's built and measured.

This does **not** address the unrelated acoustic self-echo problem (section 27/37: the phone's own microphone re-hearing its own spoken answer through open air) -- that is a property of simultaneous playback and recording on a phone speaker, independent of which recognizer is listening. The headphone requirement established alongside the existing engine (section 27) remains necessary regardless of which recognition engine is in use.

# 39. Problem-Character Entry Flow

Gives sections 11 (Problem Characters) and 12 (Problem Character Keyboard) a concrete entry point and flow, ahead of -- and independent of -- the full three-session training cycle (section 8) and character-level statistics (section 20), neither of which this depends on.

## Entry point

A "Prob" button on the main training screen opens the problem-character entry interface.

## Character keyboard

Per section 12, presents the common Morse character set in one view rather than requiring the standard device keyboard. At minimum:

- A-Z
- 0-9
- `/` `.` `,` `?`

Per section 12, additional common Morse punctuation may also be included; the above is the required minimum.

## Flow

1. The user taps characters to add or remove them from the problem-character set (section 12's one-tap toggle behavior, with a visual indication of what's currently selected).
2. The user taps Done to close the keyboard. The entered set is persisted (section 11).
3. The next training session the user starts trains only the entered problem-character set, in place of whatever character set was previously selected.

This does not yet integrate with the three-session training cycle (section 8, Session B) -- that integration is future work, once the three-session cycle itself is built (Development Strategy, Milestone 9). Until then, entering a problem-character list and tapping Done simply makes it the active training set for the next Start, the same way selecting a character-set chip does today, and it remains active until the user selects a different character set or edits the problem-character list.

---

# 40. Speech Recognition: Accuracy and Getting the Best Results

The current recognition engine is `package:speech_to_text` running fully on-device (section 27; the enrollment-based alternative in section 38 was built, tested, and set aside -- see that section's own notes). This section is user-facing guidance, not architecture: what actually helps recognition work well, and what limitations are inherent to this approach rather than bugs to report.

## For best results

- **Use headphones, not the phone's built-in speaker.** The computer's own spoken answer and the Morse tone play back at the same time the microphone is listening for the next response; on a speaker, that audio can bleed back into the mic. Headphones eliminate this and are the setup all of this feature's on-device tuning was done and verified with.
- **A quiet room helps more than it might seem.** Recognition timing is judged from the moment your speech first crosses above the room's background noise level, not from when the words are fully transcribed. Background noise (fans, TV, other conversation) raises that floor and can both delay genuine onset detection and occasionally trigger a false one.
- **Speak clearly and promptly, at a consistent distance from the mic.** A trailing "umm," breath, or extended pause mid-answer can occasionally be picked up as part of the response window's timing.
- **Faster settings (short recognition time, high WPM) leave less margin for error.** At very tight recognition-time settings (e.g. 500ms), there's very little slack between when speech can physically be detected and when the window closes -- a response that's genuinely on time can still occasionally miss by a few tens of milliseconds. This is an inherent tradeoff of fast settings, not a defect.

## Known accuracy limitations

- **Some letters are inherently harder for any speech recognizer to tell apart**, because they sound alike when spoken as isolated letter names -- B/P, M/N, and similar pairs are classic examples (the same reason the NATO phonetic alphabet exists for radio communication). If a particular letter is consistently misrecognized, it's very unlikely to be fixable through settings; it's a limitation of matching short, isolated spoken letters this way.
- **A spoken letter occasionally gets missed entirely** -- merged into a nearby word, or simply not picked up as its own response -- rather than recognized incorrectly. This happens more often for very short-sounding letters and is a limitation of the underlying recognizer's word-boundary detection, not something a setting can fully prevent.
- **"Beat the computer" credit requires speech to be detected within the response window, not just spoken within it.** There is always some small delay between when you start speaking and when the app can detect that you started -- usually well under a tenth of a second, but nonzero. A response that felt on-time can occasionally be judged just late for this reason.

None of the above should be read as "the feature doesn't work" -- these are the boundaries of what's achievable with on-device, real-time speech recognition on a phone, refined against extensive real-world testing (Milestone 13's several rounds of on-device tuning, 2026-08-26 through 2026-08-28). If recognition suddenly gets *dramatically* worse than this (e.g. it stops responding at all for an entire session), that likely is a bug worth reporting, not one of these inherent limits.

# 41. Pause / Resume

Once a session is running, a Pause button appears on the main screen next to Stop. Tapping it holds the session in place rather than ending it:

- The training engine, response listener, and audio session are torn down exactly the way Stop tears them down -- there is no attempt to freeze mid-character playback, since the pre-mix audio architecture (section 26) plays each character's Morse tone, recognition-time silence, and spoken answer as one continuous buffer with no safe point to suspend and later resume mid-buffer.
- Unlike Stop, the session itself does not end: the active character set, an in-progress countdown Timer, and the elapsed-time display are all frozen in place rather than reset, and nothing is written to the Training Log or the problem-character store.
- While paused, the main screen offers Resume (continue training, generating a fresh character rather than replaying the interrupted one) or Stop (end the session from here, exactly as tapping Stop while running would, including logging whatever time had actually elapsed before Pause was tapped).
- Resuming rebuilds the session using whatever Character Speed, Recognition Time, Extra Gap, and Character Set/Focus values are current at the moment Resume is tapped -- the same "live while training" rule those controls already follow.

# 42. Android Background Audio

A training session must keep advancing accurately once the screen locks, on Android as well as iOS. The two platforms need genuinely different mechanisms to get there, even though the Dart-level architecture (TrainingEngine, the pre-mix audio buffer, TrainingAudioHandler) is shared unchanged between them.

## Why the pre-mix architecture doesn't need to change

Each turn's Morse tone, recognition-time silence, and spoken answer are still rendered into one continuous buffer and handed to the native player with a single `play()` call (section 26) -- once issued, that playback is governed by the OS's own audio pipeline, not by Dart. What *does* depend on the Dart isolate continuing to run is turn-to-turn advancement (`TrainingEngine`'s own `Timer` between turns) and response-window scoring (its open/close `Timer`s) -- pure bookkeeping, not audio content. iOS gets the isolate kept alive via `UIBackgroundModes: audio` plus a continuous near-silent keep-alive tone (`KeepAliveAudioLoop`) to keep that grant satisfied. Android has no equivalent grant from merely playing audio -- it requires a real foreground service.

## What was added

- `AndroidManifest.xml`: `WAKE_LOCK`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, and `POST_NOTIFICATIONS` permissions; `audio_service`'s own `AudioService` (foreground service, `foregroundServiceType="mediaPlayback"`) and `MediaButtonReceiver` declarations.
- `MainActivity.kt`: extends `com.ryanheise.audioservice.AudioServiceActivity` instead of `FlutterActivity` directly, so the Activity shares the same Flutter engine/isolate the foreground service hosts -- that shared engine is what keeps running once the Activity itself is torn down by the screen locking.
- `main.dart`: `AudioService.init(...)` now runs on Android as well as iOS, with `androidStopForegroundOnPause: false` -- a Pause (unlike a Stop) doesn't end the session, so the service stays in the foreground through it rather than dropping to a state Android is free to reclaim.
- `audio_session_setup.dart`: `configureAudioSession()` now also sets `androidAudioAttributes` (content type `music`, usage `media`) alongside the existing iOS-only `avAudioSessionCategory`, so Android requests proper exclusive audio focus.
- `notification_permission.dart` / a small `MainActivity.kt` method channel: requests the Android 13+ runtime `POST_NOTIFICATIONS` permission, best-effort, when Start is tapped. A denial doesn't block training -- the foreground service still runs and the session still advances -- it just means no visible notification/lock-screen card.
- `KeepAliveAudioLoop` is now iOS-only (gated in `TrainingScreen.initState`) -- Android's foreground service keeps the process scheduled regardless of what audio is or isn't playing at a given instant, so the near-silent tone trick is pointless overhead there.

## Notification/lock-screen behavior

Functionally the same as iOS: a persistent media-style card with a working Play/Pause toggle, wired to the same `TrainingAudioHandler.onPlayRequested`/`onPauseRequested` callbacks (themselves forwarding to `TrainingScreen`'s own bidirectional pause/resume toggle) that already drive iOS's Now Playing card. Android's notification is visible in the notification shade at all times while the service is foregrounded, not just on the lock screen.

## A known Android platform quirk: the stale card after Stop

Confirmed on-device (`dumpsys activity services`): once a session has ever started, Android's own "media resumption" system feature independently binds `com.android.systemui` to this app's declared `MediaBrowserService`. Since a bound service stays alive as long as any client holds that binding, this can keep the notification/media card visible for a while after a real Stop, showing stale "Training in progress" text -- even though the app's own state has correctly returned to idle and the Dart-side `stop()` transition fires correctly. This is Android platform behavior for any app exposing a `MediaSession`, not a bug in this app's Stop path, and not something `audio_service`'s Dart API exposes a way to override. `TrainingScreen._togglePause` guards against a stale tap on that lingering card reaching `onPlayRequested`/`onPauseRequested` after the real session has ended (`if (!_isTraining) return;`), so the tap safely no-ops rather than leaving `_isPaused` stuck true while `_isTraining` is false.

## Verified on-device (Android emulator, API 36)

- A session locked mid-run kept generating and playing new turns throughout -- confirmed directly via logcat `AudioTrack: stop()` entries incrementing continuously (~30 distinct turns played over a ~32s locked window), not merely a timestamp that caught up on resume.
- The foreground-service notification appeared correctly, with a functional Play/Pause toggle round-tripping through `TrainingAudioHandler` exactly like iOS's Now Playing card.
- Pause/Resume from both the in-app buttons and the notification control worked correctly, including elapsed-time correctly excluding paused duration.
- The Android 13+ `POST_NOTIFICATIONS` permission prompt fired correctly at Start.

## Needs verification on a physical device

- Real Doze/App Standby and OEM-specific battery-optimization behavior (Samsung, Xiaomi, OnePlus, and similar are notably more aggressive than stock Android or the emulator) over a realistic (many-minutes) locked session, not just the ~30s window verified on the emulator.
- Whether Speech Recognition continues working while locked. Per this feature's own scope, this was never a primary requirement -- Speech Recognition is explicitly experimental (section 40), and no microphone-specific foreground-service type (`FOREGROUND_SERVICE_MICROPHONE`) was added speculatively. If recognition stops working while locked on a real device, that's an acceptable, known limitation, not a regression to chase.

# End of Specification
