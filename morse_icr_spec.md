# Morse ICR — Product & Technical Specification v0.2

## 1. Product Purpose

Morse ICR is an auditory training application designed to develop **instant character recognition (ICR)** in Morse code.

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

Characters should be randomly selected from the active character set.

Avoid immediately repeating the same character unless intentionally testing it.

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
- Sidetone frequency

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

Microphone/speech recognition.

### Milestone 9

Beat-the-computer scoring.

### Milestone 10

Character-level statistics.

### Milestone 11

Three-session training cycle and persistent countdown timers.

### Milestone 12

Persistent training log, cumulative training time, and session notes.

### Milestone 13

Personal character-speed discovery.

### Milestone 14

Problem-character training.

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

# End of Specification
