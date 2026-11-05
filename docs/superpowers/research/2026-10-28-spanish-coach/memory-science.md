# Memory science for Spanish Coach: findings, implications, and a better scheduler

## Findings

Evidence strength: **MA** = meta-analysis · **Exp** = controlled experiment(s) · **Field** = classroom or app deployment · **Lore** = practitioner claim. `[unverified]` = not confirmed against a primary abstract or full text.

### Spacing and scheduling

**F1. Spacing beats massing, and the best gap grows with how long you need to remember.** (MA + large Exp)
- Cepeda et al. (2006) synthesised verbal-recall spacing studies. Cepeda et al. (2008) tested more than 1,350 people, with gaps up to 3.5 months and final tests up to 1 year later.
- As a share of the test delay, the best gap falls from about 20–40% (1-week retention) to about 5–10% (1-year retention). For one-year retention that means gaps of roughly 18–36 days.
- Sources:
  - Cepeda, Pashler, Vul, Wixted & Rohrer (2006), *Psychol Bull* 132:354. https://doi.org/10.1037/0033-2909.132.3.354
  - Cepeda, Vul, Rohrer, Wixted & Pashler (2008), *Psychol Sci* 19:1095. https://doi.org/10.1111/j.1467-9280.2008.02209.x

**F2. The spacing effect holds for second-language learning.** (MA: 98 effect sizes, 48 experiments, N = 3,411)
- Spacing had a medium-to-large effect.
- Short spacing matched long spacing on immediate tests but lost on delayed tests.
- Equal and expanding spacing were statistically equivalent.
- A secondary source reports g ≈ 0.40 for longer vs. shorter spacing on delayed tests `[unverified]`.
- Source: Kim & Webb (2022), *Language Learning* 72:269. https://doi.org/10.1111/lang.12479

**F3. Total spacing matters; the expanding pattern itself barely matters.** (MA + Exp)
- Latimier et al. (29 studies): spaced vs. massed retrieval g = 0.74; expanding vs. uniform g = 0.034. Expanding gains a little only when items are tested many times.
- Karpicke & Bauernschmidt: long gaps gave about 200% better long-term retention than no gaps. Expanding, equal and contracting schedules did not differ.
- Nakata (2015): a small but significant advantage for expanding spacing in L2 vocabulary; "introducing spacing may have a larger effect."
- Sources:
  - Latimier, Peyre & Ramus (2021), *Educ Psychol Rev* 33:959. https://doi.org/10.1007/s10648-020-09572-8
  - Karpicke & Bauernschmidt (2011), *JEP:LMC* 37:1250. https://doi.org/10.1037/a0023436
  - Nakata (2015), *SSLA* 37:677. https://doi.org/10.1017/S0272263114000825

**F4. Learners misjudge spacing.** (Exp, flashcard software)
- Spacing beat cramming for 90% of participants, yet 72% believed cramming had worked better.
- Source: Kornell (2009), *Appl Cogn Psychol* 23:1297. https://doi.org/10.1002/acp.1537

**F5. Forgetting is steep at first, then flattens, with a bump after sleep.** (single-subject replication of Ebbinghaus, about 70 hours)
- The replicated curve matched the 1885 data closely, with an upward jump at the 24-hour point that the authors attribute to sleep.
- Nonsense syllables, so the exact percentages don't carry over to meaningful phrases.
- Source: Murre & Dros (2015), *PLoS ONE* 10(7):e0120644. https://doi.org/10.1371/journal.pone.0120644

### Spaced-repetition algorithms

**F6. Models that learn per item and per user predict recall much better than fixed Leitner boxes.** (Field log analysis + A/B tests; open benchmark)
- **Duolingo, original system.** Duolingo first used a Leitner variant with 1-2-4-8-16-day boxes, almost exactly Spanish Coach's schedule. Students complained it didn't reflect what they knew.
- **Duolingo, half-life regression (HLR).**
  - On 12.9M practice traces, HLR cut prediction error (MAE) by 45%+ versus Leitner (0.128 vs. 0.235).
  - In an A/B test with about 1M users, practice sessions fell 7.3%: students stopped drilling things they already knew.
  - A version without per-word features raised overall daily retention by 12%. Per-word difficulty weights had overfit and frustrated users.
  - Learned weights for Spanish: easy items included `liberal` (+0.83); hard ones included `quedado` (−0.73).
- **Open SRS benchmark** (about 10,000 Anki users, about 350M reviews), log loss, lower is better:

  | Model | Log loss |
  |---|---|
  | FSRS-7 | 0.340 |
  | FSRS-6 | 0.346 |
  | Constant "average retention" baseline | 0.395 |
  | HLR | 0.469 |

  FSRS-7 with default parameters, untrained: 0.362.
- **FSRS model.** It tracks three numbers per card:
  - Stability $S$: days until recall probability falls to 90%.
  - Difficulty $D \in [1,10]$.
  - Retrievability $R$: current recall probability.

  Stability grows more when the item is easier, when stability is still small, and when recall succeeds at low $R$ (the spacing effect, built into the model).
- **SM-2.** Intervals go 1 day, 6 days, then multiply by an easiness factor (start 2.5, floor 1.3). A failure restarts the item.
- Sources:
  - Settles & Meeder (2016), ACL. https://doi.org/10.18653/v1/P16-1174
  - Ye, Su & Cao (2022), KDD. https://doi.org/10.1145/3534678.3539081
  - SRS benchmark: https://github.com/open-spaced-repetition/srs-benchmark
  - FSRS formulas: https://github.com/open-spaced-repetition/awesome-fsrs/wiki/The-Algorithm
  - SM-2: https://www.super-memory.com/english/ol/sm2.htm

**F7. Personalised review beats one-size-fits-all spacing in a real foreign-language course.** (Field experiment, semester-long middle-school course)
- With study time held equal, personalised review improved end-of-course retention by 16.5% over massed study and by 10.0% over generic spaced review.
- Source: Lindsey, Shroyer, Pashler & Mozer (2014), *Psychol Sci* 25:639. https://doi.org/10.1177/0956797613504302

### Retrieval practice

**F8. Testing beats restudying, and it partly transfers.** (MA)
- Rowland: g = 0.50 (95% CI 0.42–0.58).
- Pan & Rickard (transfer to new formats or cues): d = 0.40 (CI 0.31–0.50). Transfer is strongest with elaborated retrieval and good initial performance. After correcting for publication bias, transfer is often near zero without those conditions.
- Sources:
  - Rowland (2014), *Psychol Bull* 140:1432. https://doi.org/10.1037/a0037559
  - Pan & Rickard (2018), *Psychol Bull* 144:710. https://doi.org/10.1037/bul0000151

**F9. Once you can recall an item, dropping it from tests is what causes forgetting.** (Exp, Swahili–English pairs)
- About 80% recall after one week when items stayed in test cycles, versus about 35% when correctly recalled items were dropped from testing.
- Dropping them from restudy cost nothing.
- Learners' predictions of their own performance didn't correlate with actual results.
- Source: Karpicke & Roediger (2008), *Science* 319:966. https://doi.org/10.1126/science.1152408

**F10. Saying the L2 word from memory beats repeating after a native speaker.** (Exp, 2 experiments)
- Retrieving the word before hearing it gave better comprehension and production than imitation, with no loss of pronunciation quality.
- Source: Kang, Gollan & Pashler (2013), *Psychon Bull Rev* 20:1259. https://doi.org/10.3758/s13423-013-0450-z

**F11. Harder successful retrievals produce more learning.** (Exp)
- Final test performance rose as retrieval during practice got harder.
- Source: Pyc & Rawson (2009), *J Mem Lang* 60:437. https://doi.org/10.1016/j.jml.2009.01.004

**F12. Successive relearning: learn to a criterion, then relearn in several widely spaced sessions.** (Exp: 533 students, more than 100,000 responses; classroom replications)
- The effects of the initial criterion and of relearning are subadditive: relearning swamps the initial criterion.
- Prescription: reach 3 correct recalls in the first session, then relearn to 1 correct recall in 3 widely spaced sessions.
- Sources:
  - Rawson & Dunlosky (2011), *JEP:General* 140:283. https://doi.org/10.1037/a0023956
  - Rawson, Dunlosky & Sciartelli (2013), *Educ Psychol Rev* 25:523. https://doi.org/10.1007/s10648-013-9240-4

**F13. More retrievals within a session help L2 words, and the benefit lasts.** (Exp: 98 learners, 16 word pairs)
- 5 or 7 retrievals beat 1 or 3, immediately and at a delay (four weeks per a secondary summary `[unverified]`).
- Source: Nakata (2017), *SSLA* 39:653. https://www.cambridge.org/core/journals/studies-in-second-language-acquisition/article/abs/does-repeated-practice-make-perfect-the-effects-of-withinsession-repeated-retrieval-on-second-language-vocabulary-learning/F14BA8A576CD2563D14CEA46E35D842E

**F14. Overlearning in one sitting gives short-term gains that fade.** (Exp: 218 students, word definitions and facts)
- Overlearners were far ahead at 1 week; the gap "decreased dramatically" by weeks 3–9.
- Source: Rohrer, Taylor, Pashler, Wixted & Cepeda (2005), *Appl Cogn Psychol* 19:361. https://doi.org/10.1002/acp.1083

### Generation, errors and feedback

**F15. Generating an answer beats reading it.** (MA: 86 studies, 445 effect sizes)
- d ≈ 0.40.
- Source: Bertsch, Pesta, Wiscott & McDaniel (2007), *Mem Cognit* 35:201. https://doi.org/10.3758/BF03193441

**F16. Guessing before seeing the answer helps, even for unknown foreign words, though learners believe it hurts.** (Exp)
- Kornell, Hays & Bjork: failed retrieval attempts improved later learning.
- Potts & Shanks (2014), as reported by Bjork & Kroll: guessing the meaning of unknown Euskara (Basque) words before seeing the translation gave the best later recall, while learners predicted it would give the worst.
- Sources:
  - Kornell, Hays & Bjork (2009), *JEP:LMC* 35:989. https://doi.org/10.1037/a0015729
  - Bjork & Kroll (2015), *Am J Psychol* 128:241. https://doi.org/10.5406/amerjpsyc.128.2.0241

**F17. Hypercorrection: confident errors are the easiest to fix once you get feedback.** (Exp, replicated in children)
- Source: Butterfield & Metcalfe (2001), *JEP:LMC* 27:1491. https://doi.org/10.1037/0278-7393.27.6.1491 `[effect sizes not extracted]`

**F18. Feedback timing barely matters for adults; feedback itself matters a lot.** (Exp)
- For adults, delayed and immediate feedback didn't differ once time to the final test was controlled.
- Both beat no feedback.
- Children benefited from delayed feedback.
- Source: Metcalfe, Kornell & Finn (2009), *Mem Cognit* 37:1077. https://doi.org/10.3758/MC.37.8.1077

### Retrieval direction and interference

**F19. Each direction trains its own skill. The harder L1→L2 direction pays off later; beginners may need L2→L1 first.** (Exp)
- Schneider, Healy & Bourne: English→French practice was worse immediately but better one week later, and it transferred to the reverse direction.
- Steinel, Hulstijn & Steinel (129 learners, 20 idioms, tests immediately and at 3 weeks):
  - Productive learners had "a sizable advantage" on production tests; receptive learners did better on recognition.
  - Imageability predicted performance (dual coding).
  - Receptive learning was especially poor for idioms that were hard to picture.
- Terai, Yamashita & Pasich: lower-proficiency learners learned better L2→L1; higher-proficiency learners learned better L1→L2.
- Sources:
  - Schneider, Healy & Bourne (2002), *J Mem Lang* 46:419. https://doi.org/10.1006/jmla.2001.2813
  - Steinel, Hulstijn & Steinel (2007), *SSLA* 29:449. https://doi.org/10.1017/S0272263107070271
  - Terai, Yamashita & Pasich (2021), *SSLA* 43:1116. https://doi.org/10.1017/S0272263121000346

**F20. Mixing practice beats blocking for L2; studying related words together causes confusion.** (Exp)
- Nakata & Suzuki (Modern Language Journal, 115 learners): interleaved grammar practice beat blocked practice at a 1-week delay.
- Nakata & Suzuki (SSLA, 133 learners): semantically related word sets didn't lower scores but caused more interference errors. Spacing helped unrelated items more than related ones.
- Sources:
  - Nakata & Suzuki (2019), *Mod Lang J*. https://doi.org/10.1111/modl.12581
  - Nakata & Suzuki (2019), *SSLA* 41:287. https://doi.org/10.1017/S0272263118000219

### Encoding: context, self, emotion, images, body

**F21. Varied contexts help meanings generalise; identical contexts help reuse in that same context.** (Exp, mixed findings)
- Johns et al. (2016) and Norman et al. (2023): diverse contexts help generalisation to new contexts; non-diverse contexts help use in familiar contexts.
- A 2025 study found spacing plus varied contexts did not help recall. One report says varied contexts may hurt low-proficiency learners. `[unverified: search summary]`
- Sources:
  - Norman et al. (2023), *QJEP*. https://doi.org/10.1177/17470218221126976
  - Johns et al. (2016), *Psychon Bull Rev*. https://doi.org/10.3758/s13423-015-0980-7

**F22. Relating material to yourself improves memory.** (MA, 129 studies)
- Source: Symons & Johnson (1997), *Psychol Bull* 121:371. https://doi.org/10.1037/0033-2909.121.3.371 `[effect size not extracted]`

**F23. Emotional words are remembered better in a second language too.** (Exp, highly proficient Catalan–Spanish bilinguals)
- The advantage held even when the encoding task ignored emotion. Evidence for beginners is weak `[unverified]`.
- Source: Ferré, Sánchez-Casas & Fraga (2013), *Biling Lang Cogn* 16:495. https://doi.org/10.1017/S1366728912000314

**F24. Pictures don't beat translations for learning foreign words, but learners think they do.** (Exp, 3 experiments, Swahili words)
- Source: Carpenter & Olson (2012), *JEP:LMC* 38:92. https://doi.org/10.1037/a0024828

**F25. Meaningful (iconic) gestures help retention; meaningless ones don't.** (Exp + fMRI)
- Words learned with iconic gestures were better retained over time. The benefit comes from a motor image that matches the meaning, not from movement as such.
- Sources:
  - Macedonia, Müller & Friederici (2011), *Hum Brain Mapp* 32:982. https://doi.org/10.1002/hbm.21084
  - Macedonia & Knösche (2011), *Mind Brain Educ* 5:196. https://doi.org/10.1111/j.1751-228X.2011.01129.x

**F26. Keyword mnemonics help immediately but are forgotten faster without retrieval practice.** (Exp series)
- Keyword learners win on immediate tests; "the reverse is true after a delay."
- Wang et al. (1992): a delayed-test keyword group did worse than rote repetition. They argue that an immediate test, acting as a retrieval event, is what rescues long-term retention.
- A separate Wang & Thomas paper reports keyword learners forgot almost twice as much within 2 days `[abstract snippet]`.
- A 2024 study: keywords plus retrieval practice beat keywords plus restudy.
- Sources:
  - Wang, Thomas & Ouellette (1992), *J Educ Psychol* 84:520–528
  - Wang & Thomas (1995), *J Educ Psychol* 87:468
  - Thomas & Wang (1996), *JEP:Applied* 2:330
  - "Long-term retention under conditions of intentional learning and the keyword mnemonic." https://doi.org/10.3758/BF03337348
  - Keyword + retrieval (2024): https://pmc.ncbi.nlm.nih.gov/articles/PMC10839596

### Sleep and reconsolidation

**F27. Sleep is when new words become part of your vocabulary.** (Exp)
- New spoken words start competing with similar known words (a sign of integration) only after sleep, not after 12 hours awake.
- Source: Dumay & Gaskell (2007), *Psychol Sci* 18:35. https://doi.org/10.1111/j.1467-9280.2007.01845.x

**F28. Sleeping between a learning session and a relearning session halves relearning effort and improves 6-month retention.** (Exp: 40 people, foreign vocabulary)
- Source: Mazza et al. (2016), *Psychol Sci* 27:1321. https://doi.org/10.1177/0956797616659930

**F29. Replaying already-learned words during sleep gives a small boost; it doesn't teach new words.** (Exp)
- About 10% better recall for cued Dutch words (figure from a news summary). Playing feedback after the cue blocked the benefit.
- Sources:
  - Schreiner & Rasch (2015), *Cereb Cortex* 25:4169. https://doi.org/10.1093/cercor/bhu139
  - Schreiner, Lehmann & Rasch (2015), *Nat Commun* 6:8729. https://doi.org/10.1038/ncomms9729

**F30. A brief reminder reopens a memory so new information gets merged into it.** (Exp, episodic memory, not vocabulary)
- Weak basis for any vocabulary feature.
- Source: Hupbach, Gomez, Hardt & Nadel (2007), *Learn Mem* 14:47. https://doi.org/10.1101/lm.365707

### Exposure-based learning

**F31. Mixed-language (code-switched) reading helps; full word knowledge needs many encounters.** (one RCT + weak small studies)
- Ong & Zhang (2018, N = 154): a mostly-L1 passage with five L2 target words beat a graded L2 reader.
  - Immediate recall: 9.76 vs. 6.95.
  - One-week delayed recall: 8.21 vs. 3.18.
- Webb (2007): knowledge kept growing from 1 to 3 to 7 to 10 encounters; more than 10 are needed for full word knowledge `[secondary summary]`.
- Classic "diglot weave" claims are mostly practitioner literature (Lore).
- Sources:
  - Ong & Zhang (2018), *System* 72:13. https://doi.org/10.1016/j.system.2017.10.008
  - Webb (2007), *Applied Linguistics* 28:46. https://doi.org/10.1093/applin/aml048

**F32. A spaced-repetition supplement roughly tripled retention for Russian-speaking learners.** (double-blind field RCT, small: 22 learners, 112 words)
- About 3 minutes a day raised long-term recall from 16.9% to 50.1%.
- Source: Chukharev-Hudilainen & Klepikova (2016), *CALICO J* 33:334. https://doi.org/10.1558/cj.v33i3.26055

## Is the current [0,1,2,4,8,16] Leitner schedule with +1/−1 sound?

It gets the basics right: it spaces reviews (F1–F3), the practice screen makes the learner speak the phrase from memory (F8, F10), and every answer gets feedback (F18). Its problems:

1. **The 16-day ceiling is too short.** For retention over a year, gaps should be about 18–36 days and keep growing (F1). Mastered phrases come back every 16 days forever, which is wasted effort; Duolingo saw practice volume drop 7.3% after replacing Leitner (F6). If mastered phrases are effectively retired instead, expect retention to fall from about 80% to about 35% (F9).
2. **Lapses are barely penalised.** A failure at mastery 5 drops to mastery 4, still an 8-day interval. Classic Leitner sends a failed card back to box 1, SM-2 restarts it, and FSRS post-lapse stability is about 0.3–3 days.
3. **It ignores how late a review was.** A correct answer after 30 days earns the same +1 as one on time, although recall at low retrievability is worth more (FSRS; F11).
4. **Every phrase is treated as equally hard.** Cognates and irregular participles decay at very different rates (F6).
5. **There's one mastery score per phrase.** Recognition and production are separate skills (F19).
6. **"Close" changes nothing.** It should count as a *Hard* success: a small stability gain and a nudge up in difficulty.
7. **Being shown a phrase in the card is restudy, not retrieval** (F8, F9). It must not advance the schedule.
8. **There's no cap on new phrases.** Up to 5 new chunks per dictation with a 60-second cooldown means the review queue can grow without limit.

### Proposed scheduler: FSRS-6 per (phrase, direction)

Start with default parameters and fit them to this user once enough reviews are logged.

**State.** Keep one memory state for each phrase in each direction, `recv` (Spanish→meaning) and `prod` (meaning→Spanish): stability $S$ in days, difficulty $D$, `lastReviewAt`, `reps`, `lapses`. Add a review log table (timestamp, phrase, direction, grade, latency_ms, source) so parameters can be fitted later.

**Default parameters**, indexed $w_0 \dots w_{20}$:
`[0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542]`

**Forgetting curve.** With $t$ = days since the last review:
$$R(t,S)=\left(1+F\tfrac{t}{S}\right)^{-w_{20}},\quad F=0.9^{-1/w_{20}}-1$$

**Next interval** for desired retention $r$:
$$I=\tfrac{S}{F}\left(r^{-1/w_{20}}-1\right)$$
At $r=0.9$ this gives $I=S$. Default $r=0.90$; clamp $I$ to $[1, 365]$ days.

**Grades** $G \in \{1,2,3,4\}$:
- LLM verdict `wrong` → 1 (Again)
- `close` → 2 (Hard)
- `correct` → 3 (Good)
- `correct`, no hint, speech onset under about 2.5 s → 4 (Easy). The threshold is my heuristic, based on F11.
- "Just show me", then self-grade: "didn't know" → 1, "knew it" → at most 3

**First review:**
- $S_0=w_{G-1}$: Again 0.21, Hard 1.29, Good 2.31, Easy 8.30 days.
- $D_0(G)=w_4-e^{w_5(G-1)}+1$, clamped to $[1,10]$.

**Difficulty update:**
- $D'=D-w_6(G-3)\tfrac{10-D}{9}$
- then $D''=w_7D_0(4)+(1-w_7)D'$, clamped to $[1,10]$.

**Successful review** ($G\ge2$):
$$S'=S\Big(e^{w_8}(11-D)S^{-w_9}\big(e^{w_{10}(1-R)}-1\big)\cdot[w_{15}\text{ if }G{=}2]\cdot[w_{16}\text{ if }G{=}4]+1\Big)$$

**Lapse** ($G=1$):
$$S'=\min\Big(S,\;w_{11}D^{-w_{12}}\big((S+1)^{w_{13}}-1\big)e^{w_{14}(1-R)}\Big)$$
The $\min$ cap is applied by mainstream FSRS implementations `[not seen in the wiki excerpt I read]`.

**Same-day re-test:**
$$S'=S\,e^{w_{17}(G-3+w_{18})}S^{-w_{19}}$$

**Worked example.**
- A new phrase graded Good starts at $S\approx2.3$ days with $D\approx2.1$.
- Good again on day 2.3 gives a stability multiplier of about 5.2, so $S\approx12$ days.
- The next Good lands at about 6–7 weeks, reaching Cepeda's one-year ridgeline instead of stopping at 16 days.

**Session policy** (F12–F14, F28):
- A new phrase is practised until 1–2 correct recalls in its first session, interleaved with other phrases (not 3 recalls, given the user's time; F12).
- The first relearning should come after a night's sleep.
- Never drill an item past success within a session.

**Migration.** Map the current mastery $m$ to $S=[0.2,1,2,4,8,16][m]$ with $D=5$ for both directions, and keep `nextReviewAt` as is. Fit parameters once the log holds a few hundred reviews `[threshold unverified]`. FSRS ports exist for Rust, Python and TypeScript; a Swift port is `[unverified]`, so in-app this may mean porting about 100 lines.

**Why FSRS rather than the alternatives.**
- It beats HLR on the open benchmark: log loss 0.346 vs. 0.469 (F6).
- It works without training data.
- HLR's per-word features overfit even at Duolingo's scale.
- SM-2 has fixed multipliers and restarts from scratch after any failure.

## Implications for Spanish Coach

Each idea lists the findings it rests on and the app signals it uses. ⚠ marks ideas that conflict with the current design.

1. **Replace Leitner with the FSRS scheduler above, with separate recognition and production tracks.**
   - Basis: F1, F3, F6, F7, F9, F19.
   - Signals: practice grades, ASR timing.
   - ⚠ This changes the `mastery` 0–5 field. Keep a derived mastery value for display and for the "chunk count grows with mastered count" logic (e.g. bucketed $S$).

2. **Make the floating card a retrieval prompt for phrases that are due.**
   - Basis: F8, F9, F15, F16.
   - Signals: hover events.
   - Recognition track: for a due phrase that appears in the dictation, show the Spanish without the gloss. Showing the gloss on hover counts as a recognition lapse. Reading the card without hovering is weak evidence of success `[INFERENCE: the user may simply have ignored the card]`.
   - Production track: show the source chunk in brackets (`[my laptop]`) and reveal `mi ordenador` on hover or after about 2 s. That's a pretest, and pretests help even when the guess fails (F16).
   - ⚠ The current inline bold Spanish is pure exposure. Keep it for a phrase's first encounter only.

3. **Exposure is not review.** Card appearances of new phrases update `timesSeen` only, never $S$ or `nextReviewAt`.
   - Basis: F8, F9.

4. **Choose which phrases to weave by recall probability.**
   - Basis: F6, F7, F9.
   - Signals: dictation text, scheduler state.
   - When several stored phrases match the dictation, the LLM should favour the ones whose recall probability is at or below target.
   - Mastered phrases (S > 60 days) may reappear in the card when due.
   - ⚠ This replaces the "avoid mastered" rule, which currently starves mastered phrases of further retrieval.

5. **Cap new phrases per day** (e.g. 10, configurable), and prefer turning existing chunks into review chunks over minting new ones.
   - Basis: F6, F12, F14.
   - ⚠ The current design mints phrases on every eligible dictation, so the queue grows without bound.

6. **Score productive recall from real-world use.**
   - Basis: F10, F19.
   - Signals: dictation text.
   - When the user dictates a stored Spanish phrase themselves, log a production Good (or Easy). This is the strongest evidence the app can collect, at zero cost to the user.

7. **Practice order: recognition first, production once recognition is stable.**
   - Basis: F19, F10, F11.
   - For a beginner, start with Spanish→meaning; switch to the current "How do you say…" once recognition stability passes about 7 days `[threshold is my heuristic]`.
   - Keep spoken production rather than imitation (F10). Present "Just show me" as a lower-credit path.

8. **Use response latency and confidence.**
   - Basis: F11, F17.
   - Signals: microphone timing.
   - Use the delay before speech starts to separate Easy from Good.
   - Optionally add one tap, "sure / guessing", before revealing the answer. Confident wrong answers get a prominent contrast, e.g. `ordenador ≠ computadora` in Spain, where hypercorrection makes the correction stick.

9. **Generate a new context sentence at each review, ideally from the user's own past dictations.**
   - Basis: F21, F22, F8 (Pan & Rickard: elaborated retrieval aids transfer).
   - Signals: dictation history, LLM.
   - Keep the original `exampleSentence` for the first 1–2 reviews, then vary it. For a beginner, varied contexts may hurt early learning (F21).
   - Drawing sentences from the user's own dictations is the self-reference effect for free; it needs a privacy toggle.

10. **Interleave reviews and keep near-synonyms apart.**
    - Basis: F20.
    - Don't review móvil, ordenador and portátil back to back; spread related phrases across sessions.

11. **Schedule around sleep.**
    - Basis: F27, F28, F5.
    - Signals: time of day, macOS notifications.
    - Phrases introduced after about 6 pm get their first review the next morning (menu bar or notification nudge). Don't count same-evening repeats as relearning.

12. **Offer keyword mnemonics only for stubborn phrases.**
    - Basis: F26.
    - Signals: lapse count, LLM.
    - After 3 or more lapses, the LLM proposes an English or Russian keyword image, which the LLM must check for fit. Keep the phrase in retrieval practice; never let the mnemonic replace it.

13. **Lean toward emotionally or personally meaningful chunks.**
    - Basis: F22, F23 (weak for beginners).
    - Low priority. Never surface sensitive personal content.

14. **Optional "say it and mime it" cue for action verbs** (`abrir`, `coger`).
    - Basis: F25.
    - Low priority and awkward at a desk; only iconic gestures help.

15. **No stock images in cards** expecting retention gains.
    - Basis: F24.

16. **Show the user their actual retention** and each phrase's predicted recall curve.
    - Basis: F4, F9, F16.
    - Learners rate retrieval and guessing as worse even when they work better. Real numbers counter the "this feels harder" reaction before it leads to switching the feature off.

## Myths / weak evidence to avoid

- **"Intervals must expand in a fixed pattern."** Total spacing is what matters; expanding vs. uniform is g ≈ 0.03 (F3).
- **"Seeing a word many times means learning it."** Re-exposure is restudy; dropping retrieval cuts week-later retention from about 80% to about 35% (F9). The inline weave alone won't build recall.
- **"Drill until perfect."** Within-session overlearning fades (F14). Relearning across sessions beats a higher first-session criterion (F12).
- **"Errorless learning is best."** Failed guesses followed by feedback improve learning (F16), and confident errors are corrected best (F17).
- **"Listen and repeat (shadowing) builds vocabulary."** Retrieving from memory beats imitation, with no cost to pronunciation (F10).
- **"Learning styles."** No credible evidence for matching instruction to style. Source: Pashler, McDaniel, Rohrer & Bjork (2008), *PSPI* 9:105. https://doi.org/10.1111/j.1539-6053.2009.01038.x
- **"Pictures always help."** Not better than translations; mostly overconfidence (F24).
- **"Keyword mnemonics are a universal shortcut."** Forgetting is faster without retrieval practice (F26).
- **"Learn while you sleep."** Cueing during sleep slightly strengthens words learned while awake, and feedback during sleep blocks it (F29). Sleep's real value is consolidation between sessions (F27, F28).
- **"Ebbinghaus's exact percentages."** They come from nonsense syllables and one subject (F5). Real phrases decay at item-specific rates (F6).
- **"A magic number of exposures."** Different parts of word knowledge need different numbers of encounters, often more than 10 (F31). Schedule by modelled recall, not fixed counts.
- **"Diglot weave triples vocabulary."** The strong claims come from small, non-blind studies and marketing (F31). Treat the weave as a way to expose and select phrases; the learning happens in scheduled retrieval.
- **"Reconsolidation tricks for vocabulary."** The evidence is from episodic memory only (F30).

### Critical Files for Implementation
I didn't open repo code; these are the components the ground-truth description implies. Find their paths with grep:
- **The `SpanishPhrase` model:** add per-direction S, D and review timestamps, plus a review log table.
- **The Leitner scheduler** (intervals `[0,1,2,4,8,16]`, +1/−1): replace with FSRS-6.
- **The practice-screen grading flow** (correct/close/wrong, "Just show me"): map verdicts to grades 1–4 and capture speech-onset latency.
- **The weave LLM prompt and chunk selection:** choose phrases by recall probability, add bracketed prompts for due phrases, add the daily new-phrase cap.
- **The floating card view:** use hover-to-gloss as a recognition signal and add the reveal-on-hover prompt.

## Corrections (applied after review)

**1. F22 (self-reference effect).** Replace the `[effect size not extracted]` tag with:
> Self-referent encoding beat semantic encoding by about **d = 0.65** (129 studies, mostly undergraduates; average 39 participants per study). This figure comes from a power analysis in a later PLOS ONE paper (https://doi.org/10.1371/journal.pone.0176611), not from the meta-analysis abstract.

**2. FSRS lapse formula.** The FSRS wiki states the post-lapse stability formula for v3/v4 but says nothing about capping it at the previous stability. Keep the `min(S, ·)` cap in the proposed algorithm, but its source is still unconfirmed. It stops a lapse on a very new card from giving it *more* stability than it had; check it against whichever FSRS implementation gets ported.

