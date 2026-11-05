# Spanish Coach: habits, attention, motivation and brain hacks (research findings)

I couldn't write `local://research-habits.md` because this session has no write tool, so the complete file is below; save it verbatim. It replaces everything in my previous four messages. Nothing in the repo was touched; I only read the Spanish Coach source to check the ideas against it.

**Evidence labels:** **meta-analysis**, **RCT**, **single study** (field or lab, small or not randomized), **practitioner lore**. `[unverified]` means I did not confirm it against the primary source.

**Current behaviour, checked in the code (`VoiceInk/Features/SpanishCoach/`):**
- **Card gating** (`SpanishCardGate`): needs at least 3 words and a 60 s cooldown, and is blocked only in Zoom, Teams (two bundle IDs) and FaceTime. There is no time-of-day check, no daily cap and no check for whether the user is typing.
- **Card timing:** the card appears only after the LLM call returns (`dictationDidPaste` → `performChatCompletion` → `SpanishCardPanel.show`).
- **Card window** (`SpanishCardPanel`): non-activating and never steals keyboard focus. It closes after 8 s, or 3 s after the pointer leaves it. It always shows the Spanish.
- **Example sentence:** `exampleSentence` is the user's own dictated sentence in its original language. The parser checks it is copied exactly from the dictation.
- **Seeing a phrase on a card** (`upsert`) only increases `timesSeen` and updates `lastSeenAt`. Mastery and the next review date don't change.
- **New phrases** start with `nextReviewAt = now`, so they are due in Practice immediately.
- **Reinforcement:** phrases picked for reinforcement are mastery < 3, most recently seen first. The due date is ignored.
- **Two "mastered" thresholds:** the chunk-count ramp counts mastery ≥ 3, while the "avoid" list uses mastery ≥ 5.
- **Review intervals:** `[0,1,2,4,8,16]` days, max mastery 5.

## Findings

### A. Habit formation and cue anchoring

**F1. Habits take about two months, the spread between people is huge, and missing a day doesn't matter.**
- **Evidence:** single study.
- **Design:** 96 volunteers repeated one self-chosen behaviour in a fixed daily context for 12 weeks, rating automaticity daily on the Self-Report Habit Index.
- **The 66 days:** 82 people gave usable data. The curve fitted 62 of them, and fitted well for only 39. The 66 days is the *median* time for those 39 to reach 95% of their own plateau.
- **Range and misses:** 18–254 days. Missing a single opportunity "did not materially affect the habit formation process."
- **The "21 days" myth** comes from Maltz's 1960 anecdote.
- **Sources:** Lally, van Jaarsveld, Potts & Wardle (2010), *How are habits formed*, EJSP 40:998–1009, https://doi.org/10.1002/ejsp.674. The participant counts come from secondary summaries. The myth's origin is from Gardner, Lally & Wardle (2012), BJGP, https://doi.org/10.3399/bjgp12X659466.

**F2. Anchoring to a routine and anchoring to a clock time worked equally well. Repetition is what drives the habit.**
- **Evidence:** RCT, N=192, 84 days.
- **Key numbers:** median 59 days to peak automaticity among people who formed the habit. No difference between the two cue types. Repeatedly carrying out the plan was the key predictor.
- **Source:** Keller et al. (2021), Br J Health Psychol 26(3):807–824, https://doi.org/10.1111/bjhp.12504.

**F3. Habits are learned links between a context and a response, triggered by the context and largely independent of current goals.** Goals mainly drive the early repetition that builds the link.
- **Evidence:** theoretical review.
- **Source:** Wood & Neal (2007), Psych Review 114(4):843–863, https://doi.org/10.1037/0033-295X.114.4.843.

**F4. If-then plans ("If situation Y, then I do X") raise goal attainment substantially.**
- **Evidence:** meta-analysis, 94 tests.
- **Key number:** d = 0.65. The plans help with starting, with shielding a goal from distractions, and with disengaging. They work by making the cue more noticeable and the response more automatic.
- **Source:** Gollwitzer & Sheeran (2006), Adv Exp Soc Psych 38:69–119, https://doi.org/10.1016/S0065-2601(06)38002-1.
- **Caveat:** later estimates are smaller `[unverified]`.

**F5. Temporal landmarks trigger goal pursuit (the "fresh start" effect).**
- **Evidence:** archival field studies.
- **Key result:** "diet" searches, gym visits and goal commitments rise after landmarks such as Mondays, month starts and birthdays.
- **Source:** Dai, Milkman & Riis (2014), Management Science 60(10), https://doi.org/10.1287/mnsc.2014.1901.

### B. Micro-learning, wait-learning and context

**F6. Learning in idle moments works. The best moment is right after the user sends something.**
- **Evidence:** single field study, 20 users, 2 weeks.
- **Design:** WaitChatter showed vocabulary in a Gmail chat panel while users waited for replies.
- **Learning:** about 57 new words (around 4 per day). 66% were translated correctly into the new language and 92% back into the native one. 40–60% of the words were cognates.
- **Response rate by timing:** 49.1% right after sending, 44.5% at random times with the chat box focused, 41.2% while the partner was typing, and 31.2% at random times when the chat box wasn't focused (significantly lower). Prompts right after sending were answered fastest (3.6 s vs 4.0 s).
- **What users said:** prompts felt harmless because they could be ignored. Users were frustrated when a prompt faded (after 10 s) while they were still typing. They wanted mastered words to come back later, and wanted phrases, not only single words.
- **The paper's design rules:** deliver before the user's attention shifts, sit alongside the main task, and offer optional continuations.
- **Source:** Cai, Guo, Glass & Miller (2015), *Wait-Learning*, CHI '15, https://doi.org/10.1145/2702123.2702267.
- **Extension:** WaitSuite (other kinds of waiting), Cai, Ren & Miller (2017), TOCHI 24(1), https://doi.org/10.1145/3044534 (results not read).

**F7. Vocabulary matched to the user's current place felt more relevant but taught fewer words than vocabulary ordered by frequency. Beginners were fine with frequency order.**
- **Evidence:** single field study, 23 learners, 4 weeks.
- **Key numbers:**
  - Context-matched cards were more often new to the user: 75% vs 55%.
  - Sessions were shorter: 10.7 vs 23.6 cards, with the same number of sessions.
  - Frequency order meant more cards seen (176 vs 119) and learned (41 vs 19).
  - Preference split 12 to 10 in favour of the context-matched version.
  - The "used today!" button was barely used (84 of 2,736 cards).
  - Users asked for language for what *they* want to say, not generic vocabulary for the place.
- **Source:** Edge, Searle, Chiu, Zhao & Landay (2011), *MicroMandarin*, CHI '11, https://doi.org/10.1145/1978942.1979413.

**F8. Spacing beats cramming, and the best gap depends on how long the material must be remembered.**
- **Evidence:** meta-analysis of 839 assessments in 317 experiments (Cepeda et al. 2006, Psych Bull 132(3):354–380, https://doi.org/10.1037/0033-2909.132.3.354).
- **Optimal gap:** in a study of more than 1,350 people, the best gap was about 20–40% of a 1-week test delay, falling to about 5–10% of a 1-year delay (Cepeda, Vul, Rohrer, Wixted & Pashler 2008, Psych Sci 19(11):1095–1102, https://doi.org/10.1111/j.1467-9280.2008.02209.x).

**F9. Saying a word aloud helps memory only when it makes that word stand out from words studied silently.**
- **Evidence:** 8 lab experiments.
- **Key result:** the benefit appeared only in mixed lists where *some* words were spoken. It comes from those words being distinctive, and mouthing them worked too.
- **Source:** MacLeod et al. (2010), JEP:LMC 36(3):671–685, https://doi.org/10.1037/a0018785.
- **Implication:** this does *not* support "speak every item".

### C. Attention, interruptions and notifications

**F10. Holding notifications until the user reaches a natural break reduces frustration and speeds up responses.**
- **Evidence:** single lab study, n=16.
- **Key results:**
  - Lower frustration than immediate delivery. Larger breaks (between activities) and medium ones were better than small ones.
  - The average wait was under 90 s.
  - Content relevant to the current task is tolerated at small or medium breaks. General-interest content should wait for large breaks, such as switching apps.
  - General-interest content caused more frustration (4.98 vs 3.59 on a 7-point scale) and sometimes led to "chains of diversion".
  - Software could detect *that* a break happened (52–59% recall) but not what kind. Useful signals included "switch to mail or chat app" and "window minimized".
- **Source:** Iqbal & Bailey (2008), CHI '08, https://doi.org/10.1145/1357054.1357070.

**F11. Interrupted people work faster but feel more stress, frustration, time pressure and effort. Whether the interruption matched the task made no difference.**
- **Evidence:** single lab experiment.
- **Source:** Mark, Gudith & Klocke (2008), CHI '08, https://doi.org/10.1145/1357054.1357072.

**F12. Knowledge work is already fragmented.**
- **Evidence:** single study, 24 workers, about 700 hours of observation.
- **Key numbers:**
  - About 11 minutes per stretch of work before switching.
  - 57% of stretches were interrupted.
  - 77% of interrupted work was resumed the same day, after about 25 min 26 s on average, with more than two other activities in between.
  - Interruptions about the same work were sometimes seen as helpful.
- **Note:** "23 minutes to refocus" is a distortion of this resumption figure.
- **Source:** Mark, Gonzalez & Harris (2005), CHI '05, https://doi.org/10.1145/1054972.1055017.

**F13. Leaving phone notifications on increases inattention and hyperactivity symptoms.**
- **Evidence:** within-person RCT, N=221, one week with alerts on vs one week off.
- **Key result:** inattention in turn predicted lower productivity and well-being.
- **Source:** Kushlev, Proulx & Dunn (2016), CHI '16, https://doi.org/10.1145/2858036.2858359.

**F14. Simply *receiving* a notification disrupts sustained attention about as much as using the phone.**
- **Evidence:** single lab study.
- **Source:** Stothart, Mitchum & Yehnert (2015), JEP:HPP 41(4):893–897, https://doi.org/10.1037/xhp0000100.

**F15. Repeated reminders lose their effect; fresh ones work better.**
- **Evidence:** Duolingo industry experiment, peer-reviewed at KDD.
- **Key numbers:**
  - Reusing the same notification template cut the response rate by 0.5%.
  - The novelty penalty was modelled with a 15-day half-life.
  - The algorithm that rotates templates gained +0.5% daily active users and +0.4% lessons.
- **Source:** Yancey & Settles (2020), KDD '20, https://doi.org/10.1145/3394486.3403351.

### D. Gamification, streaks and rewards

**F16. Gamification in education has small positive effects, and the motivational effects are fragile.**
- **Evidence:** meta-analysis.
- **Key numbers:** cognitive g=0.49 (k=19), motivational g=0.36 (k=16), behavioural g=0.25 (k=9). Only the cognitive effect held up in the high-rigor subset. Game fiction and competition combined with collaboration boosted the behavioural effects.
- **Source:** Sailer & Homner (2020), Educ Psych Review 32:77–112, https://doi.org/10.1007/s10648-019-09498-w.

**F17. Showing an intact streak increases engagement; showing a broken one reduces it. Letting users repair the streak removes most of the damage.**
- **Evidence:** 7 studies.
- **Key results:** the effect depends on how the log *shows* past behaviour, not on the behaviour itself. It is larger when users blame themselves for the break.
- **Source:** Silverman & Barasch (2023), J Consumer Research 49(6):1095–1117, https://doi.org/10.1093/jcr/ucac029.

**F18. Academic evidence for Duolingo's streak is weak.**
- **Huynh & Iida (2017):** a correlational, model-based analysis using "game refinement theory". Asia-Pacific J IT & Multimedia 6(2):23–29, https://dspace.jaist.ac.jp/dspace/bitstream/10119/15292/1/24026.pdf.
- **Duolingo's loss-aversion claims:** company blog, i.e. practitioner lore. https://blog.duolingo.com/how-duolingo-streak-builds-habit.
- **Downside:** "gamification misuse", where users chase points, leagues and streaks instead of learning. Qualitative study: Mogavi et al. (2022), L@S '22, https://doi.org/10.1145/3491140.3528274.

**F19. Expected tangible rewards undermine intrinsic motivation; informative positive feedback increases it.**
- **Deci, Koestner & Ryan (1999), meta-analysis of 128 studies:** rewards contingent on taking part, completing or performing reduced voluntary engagement (d = −0.40, −0.36, −0.28). Positive feedback increased voluntary engagement (d = +0.33) and interest (d = +0.31). Psych Bull 125(6):627–668, https://doi.org/10.1037/0033-2909.125.6.627.
- **Cerasoli, Nicklin & Ford (2014), 183 studies, N=212,468:**
  - Intrinsic motivation predicts performance (ρ = .21–.45), with or without incentives.
  - It matters less when incentives are tied directly to performance.
  - Intrinsic motivation predicts the quality of performance; incentives predict quantity.
  - Psych Bull 140(4):980–1008, https://doi.org/10.1037/a0035661.

**F20. People speed up as they approach a goal, even when the head start is artificial (the goal-gradient effect).**
- **Evidence:** field and lab studies.
- **Key result:** a 12-stamp coffee card with 2 stamps pre-filled was completed faster than a 10-stamp card.
- **Source:** Kivetz, Urminsky & Zheng (2006), J Marketing Research 43(1):39–58, https://doi.org/10.1509/jmkr.43.1.39.

### E. Language-learning motivation

**F21. In self-determination theory, learning for your own reasons goes with persistence and the intention to continue.** "Your own reasons" means enjoyment, or because it matters to you.
- **Evidence:** a validated scale plus correlational studies; the specific numbers are `[unverified]`.
- **Source:** Noels, Pelletier, Clément & Vallerand (2000), Language Learning 50(1):57–85, https://doi.org/10.1111/0023-8333.00111.

**F22. A vivid picture of yourself as a future speaker (the "ideal L2 self") predicts how much effort you intend to put in far better than what you achieve.**
- **Evidence:** meta-analysis.
- **Key numbers:** r=.61 with intended effort and r=.20 with achievement. The achievement link drops further after correcting for publication bias. The "ought-to" self (what others expect) r=.38; the learning experience itself r=.41.
- **Source:** Al-Hoorie (2018), SSLLT 8(4), https://doi.org/10.14746/ssllt.2018.8.4.2.

### F. Self-relevance and curiosity

**F23. Material related to yourself is remembered better (the self-reference effect).**
- **Evidence:** meta-analysis, about 129 studies.
- **Source:** Symons & Johnson (1997), Psych Bull 121(3):371–394, https://doi.org/10.1037/0033-2909.121.3.371.

**F24. Curiosity improves memory for the answer. Spillover to other material seen at the same time is fragile.**
- **Gruber, Gelman & Ranganath (2014):** better memory for answers and for unrelated faces during high curiosity, on immediate and one-day tests. Neuron 84(2):486–496, https://doi.org/10.1016/j.neuron.2014.08.060.
- **Stare et al. (2018):** replicated; the effect lasts, but sleep after learning adds nothing. https://doi.org/10.1080/17588928.2018.1513399.
- **Kang et al. (2009):** curiosity predicted recall of answers. Psych Sci 20(8):963–973, https://doi.org/10.1111/j.1467-9280.2009.02402.x.
- **Counter-evidence (2024):** curiosity *interfered* with memory for unrelated school facts. npj Science of Learning, https://doi.org/10.1038/s41539-024-00234-w.

**F25. The Zeigarnik effect (unfinished tasks are remembered better) doesn't hold up; the tendency to go back to unfinished tasks (Ovsiankina effect) does.**
- **Evidence:** meta-analysis.
- **Source:** Ghibellini & Meier (2025), HSS Communications 12:962, https://doi.org/10.1057/s41599-025-05000-w.

### G. Body-based "brain hacks"

**F26. Sleep soon after learning helps memory; sleeping between two study sessions helps relearning.**
- **Berres & Erdfelder (2021), meta-analysis:** g≈0.44 (this number is from a secondary summary). The benefit is larger for material studied more than once and for free recall. The median study had 16 people per group. Psych Bull 147(12):1309–1353, https://doi.org/10.1037/bul0000350.
- **Gais, Lucas & Born (2006):** students who slept soon after learning vocabulary did better than those with a long day awake first. Learn Mem 13(3):259–262, https://doi.org/10.1101/lm.132106.
- **Mazza et al. (2016):** 40 adults, two sessions 12 h apart. With sleep in between, relearning took fewer trials and retention was better at one week and six months. Psych Sci 27(10):1321–1330, https://doi.org/10.1177/0956797616659930.
- **Counter-evidence:** no relearning benefit from sleep in one study, https://doi.org/10.1093/sleep/zsaa210.

**F27. Exercise raises BDNF in the blood, but its effect on thinking in healthy adults is small and close to zero after correcting for publication bias.**
- **Szuhany, Bugatti & Otto (2015), meta-analysis of 29 studies, N=1,111:** BDNF rose after a single session (g=0.46), more after a session for people who exercise regularly (g=0.59), and slightly at rest after a training programme (g=0.27). The rise was smaller in studies with more women. J Psychiatr Res 60:56–64, https://doi.org/10.1016/j.jpsychires.2014.10.003.
- **Roig et al. (2013):** a single bout of exercise improved long-term memory (SMD=0.52, N=20) and short-term memory (0.26). Long-term training improved short-term memory slightly (0.15) and long-term memory not at all (0.07). Neurosci Biobehav Rev 37(8):1645–1666, https://doi.org/10.1016/j.neubiorev.2013.06.012.
- **Ciria et al. (2023), umbrella review of 24 meta-analyses of RCTs:** d≈0.22, falling to d≈0.05 after bias correction. Nat Hum Behav 7:928–941, https://doi.org/10.1038/s41562-023-01554-4.

**F28. There is no Mozart effect. "Listen and sing" helped verbatim recall of short foreign phrases in one small study.**
- **Pietschnig, Voracek & Formann (2010), meta-analysis of 39 studies:** no Mozart effect. Intelligence 38(3):314–323, https://doi.org/10.1016/j.intell.2010.03.001.
- **Ludke, Ferreira & Overy (2014), RCT, n=60, 15 minutes of learning:** singing beat speaking and rhythmic speaking for recalling Hungarian phrases. Mem Cogn 42(1):41–52, https://doi.org/10.3758/s13421-013-0342-5.

## Implications for Spanish Coach

**I1. Keep showing the card right after paste, but measure and shorten the delay. (F6, F10, F11)**
- Paste is the desktop equivalent of "right after sending": the user has just finished a piece of work and the content is their own. The non-activating panel already avoids the stress of a forced switch.
- The problem: the card appears only after the LLM call returns, so by then the user may have moved on.
- Log the time from paste to display. If it exceeds about 2–3 s, either drop the card or show it when the user next switches apps.

**I2. Don't let the card disappear while the user is busy. This conflicts with the current 8 s auto-close. (F6)**
- Pause the close timer while the user keeps typing in the app in front.
- When the card closes, add its chunks to a "today's Spanish" list in the menu bar (a badge, no sound).

**I3. Show the full answer the first time, and quiz on later sightings. This conflicts with the current always-show-the-answer card. (F6, F8)**
- For a stored phrase with mastery ≥ 1, show the original-language chunk with a blank and reveal the Spanish on hover.
- This needs the card data to mark which chunks are returning phrases.
- Optionally, count a correct reveal toward mastery, since sightings currently never change mastery or the next review date.

**I4. Add an optional one-tap "say it" on the card, reusing the existing speech recognition and LLM grader. (F6, F8)**
- Its value is as a recall attempt. F9 does not support speaking every item; at most, speak only the weak chunks while the rest are just read.

**I5. During onboarding, have the user make one if-then plan, and detect the cue. (F4, F2, F3)**
- Example: "When I first dictate after 9:00", or "When I open Slack", → "3 reviews."
- Offer routine cues and clock-time cues as equal options, and keep one stable cue per day.
- The gate doesn't track time of day yet, so this needs new code.

**I6. Be honest about habit timescales and forgive misses. (F1, F2, F17)**
- Tell users it takes about two months on average and that a missed day is fine.
- Track consistency weekly, or use a streak that can be repaired. Auto-freeze days with no dictation or heavy call use, so a gap reads as caused by the day, not the user.
- No loss-aversion nagging, and no "habit formed at 21 days" badges.

**I7. Treat proactive prompts as expensive. (F10, F13, F14, F15)**
- At most one proactive prompt per day, shown only at a natural break: switching apps after an idle period, unlocking the screen, or the first dictation after a long gap. Show it as a menu-bar badge, never a system banner or sound.
- Rotate the wording with the LLM.
- Gating gap: the call-app block list misses Meet in the browser, Webex, Slack huddles, Discord and screen sharing. Add a daily cap and time windows to the gate.

**I8. Choose chunks using the app in front, frequency, and what's due. (F7, F8, F23)**
- Pass the app's bundle ID in the LLM request and keep the prompt's existing preference for high-frequency phrases.
- Make reinforcement pick due phrases first (mastery < 3 and due now or earlier), so cards respect spacing.

**I9. Keep using the user's own sentence as the Practice example. It already does this correctly. (F23)**

**I10. Make feedback informative, and keep any reward only loosely tied to performance. (F19)**
- Keep the grader's one-line "what to fix" feedback.
- No points or gems per completed review or correct answer.
- Don't present the 2→5 chunk ramp as an unlock.
- Make the mastery ≥ 3 vs ≥ 5 split consistent in any progress UI.

**I11. Show genuine progress, without fake head starts. (F20, F16)** For example, a menu-bar count of phrases at mastery ≥ 4 toward a goal the user chose, plus "N due".

**I12. Ask once why the user wants Spain Spanish, and use the answer. (F21, F22)**
- The LLM can favour chunks relevant to that goal, and a rare card can say "you can now say 12 café phrases."
- Add autonomy controls: topic choice, "less often", "pause today", and a choice between exposure and quiz mode.
- Expect this to raise effort rather than proficiency.

**I13. Occasionally lead with a curiosity question for a target phrase, with the answer on hover. (F24)** For example: "How would a madrileño say 'I'm swamped'?" Don't expect it to help memory for anything else on screen.

**I14. Schedule the first review for the next morning. This conflicts with the current `nextReviewAt = now`. (F26)**
- Set new phrases' first review to the user's first dictation window the next day, so sleep falls between the first sighting and the first review.
- Optionally, offer a one-time review of today's phrases if the user dictates after about 21:00. The evidence is moderate and the studies are small.

**I15. Show unfinished review sets ("2 of 5 left") in the menu bar, cleared at the end of the day. (F25)** This uses the tendency to resume unfinished tasks, not a memory claim.

**I16. Offer a fresh start after 7 or more inactive days, on the next Monday or 1st of the month, by re-running I5. (F5)**

**I17. Extend the review ladder beyond 16 days. (F8, F6)**
- At a 5–10% optimal gap for one-year retention, 16 days is too short. Add 32, 64 and 128 days and raise the maximum mastery to match.
- The thresholds at mastery ≥ 3 and ≥ 5 and the existing interval tests would need updating.

**I18. Optional experiment, low priority: a "chant it" button that plays the phrase rhythmically via text-to-speech for fixed expressions. (F28)**

## Myths / weak evidence to avoid

- **"Habits form in 21 days":** it's a 1960 anecdote. The real median is 59–66 days, with a range of 18–254 (F1, F2).
- **"Habit stacking beats other cues":** a practitioner term. In the RCT, a routine cue was no better than a clock-time cue (F2).
- **Zeigarnik memory advantage:** fails meta-analysis (F25).
- **"23 minutes to refocus":** misreads a resumption-time statistic (F12).
- **Loss-aversion streaks:** supported only by company blogs and a correlational paper. Broken streaks reduce engagement, and streaks can lead users to chase points over learning (F17, F18).
- **Variable "slot machine" rewards (Eyal's *Hooked*):** practitioner lore, and they conflict with F19. Fresh *content* (F15) is a different thing and is fine.
- **"Gamification makes learning effective":** its effects are small and unstable (F16).
- **"Speak everything aloud for memory":** the production effect needs a mix of spoken and silent items (F9).
- **Mozart effect / background music:** not supported (F28).
- **Exercise or "BDNF boosting" as a learning hack:** the effect on thinking is near zero after bias correction (F27).
- **Brain training:** gains don't transfer far beyond the trained task. Simons et al. (2016), PSPI 17(3):103–186, https://doi.org/10.1177/1529100616661983.
- **Learning styles:** no sound evidence. Pashler, McDaniel, Rohrer & Bjork (2008), PSPI 9(3):105–119, https://doi.org/10.1111/j.1539-6053.2009.01038.x.
- **"Curiosity boosts everything nearby":** the spillover is fragile (F24).
- **Vision boards as an achievement driver:** an ideal-self picture drives effort, not results (F22).

**Still unverified:**
- the Noels et al. (2000) correlations;
- smaller later estimates for if-then plans;
- the Dearman & Truong (2012) live-wallpaper results (https://doi.org/10.1145/2207676.2208598) and the WaitSuite details;
- the Berres g=0.44, which is from a secondary summary.

### Critical Files for Implementation
- `VoiceInk/Features/SpanishCoach/Logic/SpanishCardGate.swift`: call-app list and cooldown; where a daily cap, time windows and a "busy" check would go (I5, I7, I14).
- `VoiceInk/Features/SpanishCoach/Presentation/SpanishCardPanel.swift`: the 8 s / 3 s auto-close, hover expand, inline Spanish (I2, I3, I13).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishCoachService.swift`: the card waits for the LLM call; request contents (I1, I8).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishPhraseStore.swift`: sightings don't change mastery; reinforcement ignores due dates (I3, I8, I10).
- `VoiceInk/Features/SpanishCoach/Logic/SpanishMastery.swift` and `Models/SpanishPhrase.swift`: the interval ladder and `nextReviewAt = now` for new phrases (I14, I17).

## Replacement findings (supersede the same-numbered findings above)

**F21 (replace).** Learning a language for your own reasons goes with feeling free to choose, feeling competent, and intending to keep going.
- **Design:** a scale study of 159 university L2 learners. It is correlational, not causal.
- **Personal importance:** learning because it matters to you ("identified regulation") correlated with freedom of choice r=.58, perceived competence r=.35, intention to continue r=.55 and anxiety r=−.31.
- **Enjoyment:** intrinsic motivation correlated with intention to continue at r=.34–.49.
- **Pressure:** learning out of external pressure ("external regulation") was unrelated to freedom of choice (r=−.01) and only weakly related to intention to continue (r=.19).
- **Amotivation:** not seeing the point correlated with intention to continue r=−.57.
- **Source:** Noels, Pelletier, Clément & Vallerand (2000), Language Learning 50(1):57–85, https://doi.org/10.1111/0023-8333.00111 (Tables 2–3).
- **What it adds:** it supports I12's choice and pause controls. It also suggests autonomy and visible competence matter more than reminders or obligation.

**New F7b (add after F7).** Showing vocabulary during routine phone use led to learning, and vocabulary matched to the situation was learned faster than unrelated vocabulary.
- **Design:** "Vocabulary Wallpaper", a live phone wallpaper showing words while people navigated their home screens. Field study with very few participants. For two of them, the reported figures were: one recalled 158 of 274 phrases he had seen (and guessed 65 of 126 he hadn't), the other recalled 79 of 178 (guessing 26 of 92).
- **Evidence:** a very small single study. Because people could guess many phrases they had never seen, the real learning effect is uncertain.
- **Source:** Dearman & Truong (2012), CHI '12, pp. 1391–1400, https://doi.org/10.1145/2207676.2208598.
- **What it adds:** weak support for passive exposure on a peripheral display and for matching vocabulary to context (I8). It's weaker than WaitChatter's evidence that well-timed recall prompts work (F6).

That clears every unverified tag except two:
- **Berres & Erdfelder (2021):** the sleep effect size g≈0.44 came from a secondary summary; the DOI and the other numbers are confirmed.
- **Gollwitzer & Sheeran (2006):** I didn't fetch the later replications that report smaller effects for if-then plans.

**F4 (replace). If-then plans ("If situation Y, then I do X") reliably help, but in the newer evidence the effect is small.**
- **2006 meta-analysis:** 94 tests, d = 0.65. Gollwitzer & Sheeran (2006), Adv Exp Soc Psych 38:69–119, https://doi.org/10.1016/S0065-2601(06)38002-1.
- **2025 meta-analysis:** 642 tests. Sheeran, Listrom & Gollwitzer (2025), *The when and how of planning*, European Review of Social Psychology 36(1):162–194, https://doi.org/10.1080/10463283.2024.2334563.
  - **Overall:** the benefit is robust (Bayes factor ≈ 319 against "no effect"). It is *small* by convention and varies a lot between studies (τ = 0.27).
  - **Publication bias:** substantial (Egger b = 1.06), and correcting for it shrinks the estimates.
  - **Where it helps:** prospective memory (remembering to do something), with a small-to-medium effect, 62 tests and little variation. Studying and other academic behaviour shows only a small effect.
  - **Where it doesn't:** vaccination and voting, with confidence intervals that include zero.
  - **What makes plans work better:** a genuine "if … then" form, high motivation, and rehearsing the plan.
- **Implication for I5:** the plan's value is in reliably *remembering* to review at the chosen cue, not in motivation. Keep the cue concrete and let the user rehearse it once during setup, for example by confirming "When X, I'll do 3 reviews." Expect a modest effect.

**F26 (replace the Berres entry).** Berres & Erdfelder (2021), Psychological Bulletin 147(12):1309–1353, https://doi.org/10.1037/bul0000350.
- **Scale:** 823 effect sizes from 271 samples in 177 articles (1967–2019).
- **Effect:** sleep benefits memory, g = 0.44, falling to g = 0.28 after correcting for selective reporting.
- **When it's larger:** for material studied more than once and for free recall.
- **Caveat:** the median sample was 16 per group.
- The Gais (2006), Mazza (2016) and SLEEP 2021 counter-evidence lines stay as they are.
- **Implication for I14:** keep scheduling the first review the next morning. Present the benefit as small-to-moderate.

### Critical Files for Implementation
These are the same as in my earlier message:
- `VoiceInk/Features/SpanishCoach/Logic/SpanishCardGate.swift`: call-app list and 60 s cooldown; where a daily cap, time windows and a "user is busy" check would go (I5, I7, I14).
- `VoiceInk/Features/SpanishCoach/Presentation/SpanishCardPanel.swift`: 8 s / 3 s auto-close, hover expand, inline Spanish (I2, I3, I13).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishCoachService.swift`: the card waits for the LLM call before appearing; request contents (I1, I8).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishPhraseStore.swift`: seeing a phrase on a card doesn't change its mastery; reinforcement ignores due dates (I3, I8, I10).
- `VoiceInk/Features/SpanishCoach/Logic/SpanishMastery.swift` and `Models/SpanishPhrase.swift`: the review-interval ladder, and `nextReviewAt = now` on insert (I14, I17).