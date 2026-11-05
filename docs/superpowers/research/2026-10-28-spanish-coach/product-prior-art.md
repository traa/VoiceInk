# Spanish Coach: product survey (learning from your own dictations)

**Evidence labels:** meta-analysis · RCT · field study · single study (pre/post test, no control group) · vendor/commissioned · product doc · practitioner lore. `[unverified]` means I couldn't reach the primary source.

## Findings

### 1. Toucan (Babbel), the closest analogue
- **What it does:** A browser extension that swaps some words on web pages into the target language, with a translation on hover. It also adds Extra Practice mini-quizzes inside Google, Twitter and Reddit, and lets you save words. Babbel bought it in 2023. ([store](https://chromewebstore.google.com/detail/toucan-by-babbel-language/lokjgaehpcnlmkebpmjiofccpklbmoci); [press](https://www.babbel.com/press/en-us/releases/keep-learning-while-browsing-babbel-to-integrate-toucan-browser-extension))
- **Evidence:** I found no efficacy study.
  - It has 3.5★ from about 1.4K ratings and about 200,000 users.
  - User reviews complain about translations that ignore context, learned words that keep reappearing, and heavy resource use. ([reviews](https://chromewebstore.google.com/detail/toucan-by-babbel-language/lokjgaehpcnlmkebpmjiofccpklbmoci/reviews); [Extpose](https://extpose.com/ext/99937/en))
  - A word reportedly counts as "learned" after about 100 views. ([blog](https://letterstobarbara.com/toucan-review-tutorial-learn-language-travel/); `[unverified]`)
  - Its dashboard counts "words translated" (exposure), not words known. ([Flying Penguins](https://www.flyingpenguins.io/p/toucan-effortless-language-learning); practitioner)
- **What transfers:** Mixing target-language words into L1 text with a gloss on hover. VoiceInk already does this, and its LLM sees the surrounding context.
- **Remaining gaps for VoiceInk:** Toucan has no recall step, measures progress only by exposure, and never retires words the user has learned.

### 2. ALOE (Trusty & Truong, CHI '11, pp. 3179–3188)
- **What it does:** Firefox add-on that replaced English words on web pages with French ones.
- **Evidence:** A two-month field study found "most participants… learn[ed] an average of 50 new French vocabulary words". ([DOI 10.1145/1978942.1979414](https://dl.acm.org/doi/10.1145/1978942.1979414); abstract only)
  - A later paper notes that some users switched it off because it slowed down their tasks. ([WaitSuite, TOCHI 2017](http://up.csail.mit.edu/other-pubs/tochi16-waitsuite.pdf))
- **What this means for VoiceInk:** Never alter the text the user pastes. The current design keeps the paste unchanged and shows the Spanish on a separate card, which is correct.

### 3. VocabEncounter (Arakawa et al., CHI 2022)
- **What it does:** Starts from the learner's list of target words, finds places on web pages where they fit, and uses machine translation constrained to include the target word.
- **Evidence:** Crowdworkers rated the translations comparable to human ones, and the user studies showed vocabulary learning. ([DOI 10.1145/3491102.3501839](https://dl.acm.org/doi/10.1145/3491102.3501839)) Effect sizes `[unverified]`.
- **What transfers:** "Which due word can I fit here?" Today VoiceInk only reuses a phrase when the dictation contains its exact English source.

### 4. WaitChatter / WaitSuite (MIT, CHI 2015; TOCHI 2017)
- **What it does:** A vocabulary card appears in Google Chat right after the user sends a message.
  - Words come from the conversation itself.
  - Each word starts in study mode and later switches to quiz mode, on a Leitner schedule.
  - Words the user has seen before get priority when they come up again.
  - Cards fade after 10 s, with a "fetch more" button.
- **Evidence:** Field study with 20 users over 2 weeks. ([PDF](http://people.csail.mit.edu/ccai/publications/Cai_WaitLearningFull.pdf))
  - Users learned 57 words on average (about 4 per day).
  - Recall was 66% from English into the new language and 92% the other way.
  - A card shown 1.5 s after the user sent a message got 49.1% responses, versus 41.2% while the other person was typing and 44.5% at random times. Median response time was 1.83 s.
  - Users disliked cards disappearing too early and wanted mastered words to come back later.
  - Engagement was lowest in work-related conversations.
  - In the follow-up WaitSuite study, how long the user waited, how easy the card was to reach, and competing demands predicted engagement.
- **Fit for VoiceInk:** The moment after a paste is like the moment after sending a chat message. But a dictating user isn't waiting for a reply, so expect lower engagement.

### 5. Duolingo: half-life regression (HLR) and Birdbrain
- **What it does:**
  - HLR models the chance of remembering a word as $p = 2^{-\Delta/h}$, where $\Delta$ is the time since last practice and $h$ is the word's estimated half-life. The half-life is fitted from square-root counts of times seen, right and wrong, plus optional per-word features.
  - Birdbrain predicts whether a learner will get a given exercise right.
- **Evidence:** ([ACL 2016](https://aclanthology.org/P16-1174.pdf))
  - Prediction error (mean absolute error) fell by at least 45% compared with Leitner: 0.128 vs 0.235.
  - In an A/B test with about 1M users, daily retention for practice sessions dropped 7.3%. Duolingo shipped HLR anyway, partly because learners had complained that Leitner reviews didn't target what they needed.
  - In a second A/B test with 3.3M users, removing the per-word features raised daily retention by 12.0%, because those features overfit.
  - Duolingo's blog says Birdbrain helped learners "learn more" but gives no numbers. ([blog](https://blog.duolingo.com/learning-how-to-help-you-learn-introducing-birdbrain/); vendor)
- **Lessons for VoiceInk:**
  - HLR is outdated; FSRS beats it (see #7).
  - Fixed Leitner boxes don't match what learners feel they need to review.
  - Per-word features overfit.

### 6. Duolingo efficacy studies
- **Vesselinov & Grego 2012** (commissioned, no control group): learners gained 8.1 placement-test points per hour (95% CI 5.6–10.7), which the authors equate to "34 hours ≈ one college semester". Motivation was the strongest factor. ([report](https://www.vesselinov.com/RV_Duolingo.pdf))
- **Jiang et al. 2021/22** (*Foreign Language Annals*, mostly Duolingo authors, n=225): learners who finished the beginner course reached Intermediate Low in reading and Novice High in listening, comparable to 4 university semesters. Speaking and writing were not tested. ([DOI 10.1111/flan.12600](https://onlinelibrary.wiley.com/doi/10.1111/flan.12600))
- **Takeaway:** Time on task and motivation drive results.

### 7. Anki + FSRS
- **What it does:** Flashcards graded Again/Hard/Good/Easy. FSRS models each card's difficulty, memory stability and current chance of recall, and schedules the next review to hit a target recall rate.
- **Evidence:**
  - FSRS comes from Ye, Su & Cao, KDD 2022. ([DOI 10.1145/3534678.3539081](https://dl.acm.org/doi/10.1145/3534678.3539081))
  - An open benchmark over about 10,000 users and about 350M reviews reports prediction error (log loss, lower is better): FSRS-6 0.346, FSRS-7 with default settings 0.362, a constant baseline 0.395, HLR 0.469. ([srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark/blob/main/README.md); not peer reviewed)
  - [`swift-fsrs`](https://github.com/open-spaced-repetition/swift-fsrs) is an MIT-licensed Swift implementation of FSRS-6.
- **Fit for VoiceInk:** Strong. It works out of the box with default settings, and VoiceInk's grades map cleanly: correct → Good, close → Hard, wrong → Again.

### 8. Pimsleur, and research on review spacing
- **What it does:** Audio-only drills where the learner hears a prompt in their own language, pauses, says it in the target language, then hears the answer. Reviews come back at fixed, growing intervals. The exact intervals are `[unverified]`.
- **Evidence:**
  - I found no independent efficacy study of Pimsleur.
  - Karpicke & Roediger 2007 ([DOI 10.1037/0278-7393.33.4.704](https://pubmed.ncbi.nlm.nih.gov/17576148)): growing intervals helped at 10 minutes, but equal intervals did better at 2 days. "Delaying the first test improved long-term retention, regardless of how the repeated tests were spaced."
  - Nakata 2015 (n=128): growing intervals had a small advantage, but the total amount of spacing had large effects.
- **Fit for VoiceInk:** The prompt-pause-answer drill transfers well. Today, a phrase at mastery 0 has a 0-day interval, so it is due immediately.

### 9. LingQ
- **What it does:** Words have statuses 1 New → 2 Recognized → 3 Familiar → 4 Learned → Known.
  - The status controls how often a word is reviewed; Known words are never reviewed.
  - LingQ itself describes the statuses as "subjective". ([help](https://forum.lingq.com/t/how-lingq-statuses-work/6841))
  - Words the user doesn't click are marked Known when they turn the page.
- **Evidence:** None found.
- **What transfers:** A one-tap "knew it / new to me". Don't copy "untouched = Known": in VoiceInk the app chooses the words, so not tapping one says nothing about knowing it.

### 10. Readlang
- **What it does:** Click to translate any word. It saves every sentence where the word appeared, shows a random one on each flashcard, and picks practice words by frequency. ([about](https://readlang.com/about); [blog](https://blog.readlang.com/2013/07/22/multiple-contexts.html))
- **Evidence:** None found; 4.2★.
- **Fit for VoiceInk:** VoiceInk keeps only the first example sentence. Keeping several would vary the reviews.

### 11. Language Reactor
- **What it does:** Dual subtitles, hover lookups, and saved words with their surrounding context. Its Learn tab shows vocabulary coverage and suggests words in batches. ([site](https://www.languagereactor.com/); [updates](https://www.languagereactor.com/help/updates))
- **Evidence:** None found.
- **What transfers:** Coverage as a progress measure.

### 12. Clozemaster
- **What it does:** Fill-in-the-blank sentences (mostly from Tatoeba), ordered by word frequency. ([site](https://www.clozemaster.com/))
- **Evidence:** None. Refold users complain the sentences often contain more than one unknown word. ([Refold](https://refold.la/blog/srs-that-isnt-anki-clozemaster))
- **Fit for VoiceInk:** Strong. The user's own dictated sentence with the Spanish chunk blanked out is a ready-made, personally relevant cloze.

### 13. Glossika
- **What it does:** The learner hears the sentence in their own language, then native audio in the target language, then repeats it aloud, with spaced reviews of sentences. ([help](https://help.glossika.com/en/articles/6611459-step-4-the-most-effective-way-to-train-on-glossika-legacy-app))
- **Evidence:** No independent study.
- **Fit for VoiceInk:** The Practice screen currently has no model audio. macOS has Spain-Spanish voices: `AVSpeechSynthesisVoice(language: "es-ES")` gives Mónica or Jorge. ([gist](https://gist.github.com/myrickchow32/6027dd79b4499daeed91367c0afad11b); [code2care](https://code2care.org/macos/say-command-svoices-and-languages-macos-speech/); practitioner sources)

### 14. Sentence mining / "i+1" (Refold, AJATT)
- **What it is:** Practitioner lore: save sentences that have exactly one unknown word (maybe two), never three or more. ([Refold](https://refold.la/roadmap/library/sentence-mining); [Tatsumoto](https://tatsumoto-ren.github.io/blog/sentence-mining.html))
- **Evidence:**
  - The famous "you need to know 98% of the words" figure (Hu & Nation 2000) was inferred, not directly measured.
  - Kremmel et al. 2023 found comprehension rises roughly linearly with known words, with no fixed threshold. ([DOI 10.1111/lang.12622](https://onlinelibrary.wiley.com/doi/10.1111/lang.12622))
- **Fit for VoiceInk:** A card with 2–5 chunks can introduce several new items at once for a beginner.

### 15. Lingvist
- **What it does:** Frequency-ordered vocabulary, taught with cloze sentences and adaptive spaced repetition.
- **Evidence:** Wild et al. 2024 analysed app data at scale (observational). ([DOI 10.1017/S0142716424000304](https://www.cambridge.org/core/journals/applied-psycholinguistics/article/word-learning-in-the-wild-appbased-evidence-for-valence-and-concreteness-effects/CE06F035484CAB8E72F96467502862C4))
  - Words with emotional tone (positive or negative) were learned better than neutral ones, especially in sentences of the same tone.
  - The effect was strongest on the second encounter.
  - Whether a word was concrete made no difference.

### 16. Memrise
- **What it does:** Videos of native speakers, plus an AI chat partner (MemBot). ([help](https://memrisebeta.zendesk.com/hc/en-us/articles/4437047561745-The-New-Memrise-Experience); [MemBot](https://www.memrise.com/blog/introducing-membot))
- **Evidence:** None found.
- **Fit for VoiceInk:** Use an es-ES voice to model Spain-specific features: the /θ/ sound (as in "cerveza") and vosotros forms.

### 17. Babbel efficacy studies
- **Vesselinov & Grego 2016** (commissioned, no control group): beginners covered about one college semester in 15 hours. ([press](https://www.babbel.com/press/en-us/releases/2016-09-29-Efficacy_Study.html))
- **Loewen, Isbell & Sporn 2020** (n=54, 12 weeks, no control group): learners improved, and "study time was the strongest predictor for all three measures". ([ERIC](https://eric.ed.gov/?id=EJ1258413))

### 18. Duolingo Max: Explain My Answer, Roleplay, Video Call
- **What it does:**
  - Roleplay gives feedback on accuracy and complexity after the conversation.
  - Video Call remembers earlier conversations. ([blog](https://blog.duolingo.com/duolingo-max/))
  - Explain My Answer has been free for everyone since January 2026. ([GamesBeat](https://gamesbeat.com/duolingo-makes-its-ai-powered-explain-my-answer-feature-free-for-all-users-in-2026/); secondary)
- **Evidence:** Kittredge et al. 2025 (Duolingo authors, n=385, 1 month, self-report only): confidence went up and 91–97% of learners said the features helped. No proficiency test. ([DOI 10.3389/feduc.2025.1499497](https://www.frontiersin.org/journals/education/articles/10.3389/feduc.2025.1499497/full))

### 19. AI chatbots / tutors (e.g. ChatGPT voice)
- **Evidence for:**
  - Wang, Cheung, Neitzel & Chai, *Review of Educational Research* 95(4), 2025: 28 studies; chatbot conditions beat non-chatbot ones with an effect of $g$ = 0.484. Learner level, interface design and how interactive the chatbot was all changed the effect. ([ERIC](https://eric.ed.gov/?id=EJ1476911))
  - Zhang et al. 2023: $g$ = .527. ([CityU](https://scholars.cityu.edu.hk/en/publications/effect-ofchatbotassisted-language-learning-ametaanalysis/))
  - Lyu 2025: $g$ = 0.608, with larger effects when the chatbot took voice input, and 0.323 when compared against non-interactive tools. ([DOI 10.1111/ijal.12668](https://onlinelibrary.wiley.com/doi/full/10.1111/ijal.12668); `[unverified]`)
  - Zhang & Huang 2024 (RCT, n=52): an LLM chatbot improved vocabulary, and learners kept more of their productive vocabulary two weeks later. ([DOI 10.1016/j.heliyon.2024.e25370](https://pubmed.ncbi.nlm.nih.gov/38333802/))
- **Evidence against:**
  - Storyfier (n=28): users liked the AI help but recalled words worse. ([arXiv 2308.03864](https://arxiv.org/abs/2308.03864))
  - Leong 2024 (n=272): personalized examples raised motivation but made no difference to learning. ([MIT](https://www.media.mit.edu/publications/putting-things-into-context/))

### 20. Speak and ELSA
- **What they do:** Speak runs phrase-based speaking loops on OpenAI models. ELSA scores pronunciation sound by sound. ([OpenAI](https://openai.com/index/speak-connor-zwick))
- **Evidence:** No independent study of Speak. ELSA's evidence is weak. ([PLOS One 2025](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0317378); [LLT 2025](https://www.lltjournal.org/item/10125-73658/))
- **Fit for VoiceInk:** Checking speech against a transcript only shows the right words were said, not how they were pronounced.

### 21. Grammarly / Apple-style inline suggestions
- **What they do:** Unobtrusive underlines the user can accept or dismiss.
- **Evidence:**
  - Mohsen 2022, meta-analysis of 14 studies (n=1220): computer-mediated corrective feedback had a large effect ($d$ = 1.21). Automated writing evaluation tools had a medium effect. Effects were large for beginners and intermediates, small for advanced learners. ([ERIC](https://eric.ed.gov/?id=EJ1349071))
  - Lyster & Saito 2010, meta-analysis of 15 studies (n=827): corrective feedback had "significant and durable" effects, and was larger when the teacher prompted the learner to self-correct than when the teacher just repeated the correct form. ([ERIC](https://eric.ed.gov/?id=EJ892626))
  - The idea that correcting a few errors at a time beats correcting all of them is `[unverified primary]`.

### 22. Google Translate Practice (beta, 2025)
- **What it does:** Listening and speaking sessions tailored to the user's level and goals. ([blog](https://blog.google/products-and-platforms/products/translate/language-learning-live-translate/))
- **Evidence:** None.
- **Fit for VoiceInk:** VoiceInk can infer goals from what the user dictates instead of asking.

### 23. Learning from passive exposure takes many encounters
- **Evidence:** Uchihara, Webb & Yanagisawa 2019, meta-analysis of 26 studies (n=1918): the number of times a word was encountered correlated with learning it at $r$ = .34. ([DOI 10.1111/lang.12343](https://onlinelibrary.wiley.com/doi/abs/10.1111/lang.12343))

## Implications for Spanish Coach
Numbers in parentheses point to the findings above. ⚠ marks ideas that conflict with the current design.

1. ⚠ **Replace Leitner with FSRS** (#5, #7, #8): use `swift-fsrs` and keep a review log. Map correct/close/wrong/"show me" to Good/Hard/Again/Again. Show `mastery` as a bucket derived from FSRS stability. This needs a data migration.
2. ⚠ **Delay the first review** (#8): don't make a new phrase due the moment it's created.
3. ⚠ **At most one new chunk per card** (#14, #23): fill the other slots with phrases that are due or already known.
4. **Fit due phrases into the dictation** (#3, #4): send the LLM the phrases due for review and let it use paraphrase slots. Today `reinforcementCandidates` sorts by recency rather than due date and needs an exact text match.
5. **Turn due chunks into quick recall on the card** (#4, #12, #19): blank out the Spanish and reveal it on hover or when spoken. New chunks stay as bold Spanish. ⚠ This makes the card take a moment of effort.
6. **One-tap "knew it / new to me"** (#4, #9, #21).
7. **Card persistence** (#4): add "show last card" to the menu bar and a "→ one more" button.
8. **Prioritise by how often the user says something** (#10, #12, #15): count English phrases across dictations, on device.
9. **Keep several example sentences per phrase** (#10).
10. **Use emotional tone as a tie-breaker** when choosing chunks (#15).
11. **Prompt → speak → hear the es-ES model → repeat** (#8, #13, #16).
12. **Hint, retry, then reveal** on a "close" answer (#21).
13. **"Why?" button per chunk** (#18): e.g. "vosotros is Spain-only", "ordenador vs computadora".
14. ⚠ **Optional weekly voice roleplay seeded from the user's dictations** (#18, #19, #22): has privacy implications.
15. **Per-app gating** based on whether the user engages with cards in that app (#4, #2).
16. **Progress as coverage** (#1, #9, #11): e.g. "you can say 34 of your 100 most-dictated phrases".
17. **Never put Spanish into the pasted text** (#2): keep current behaviour.
18. ⚠ **Spanish-dictation feedback**: when the user dictates in Spanish, offer one focused correction as an opt-in card (#21).
19. **Export to CSV / Anki** (#7, #14).

## Myths / weak evidence to avoid
- **"You'll learn effortlessly":** measured gains are small, the tools that report them include quizzes, passive encounters correlate only $r$ = .34 with learning, and personalisation raised motivation but not learning.
- **"34 h / 15 h = one semester":** commissioned studies without a control group.
- **"Growing review intervals are essential":** the delay before the first test and the total spacing matter more.
- **"98% known words" or strict "i+1":** an inferred figure, not a measured threshold.
- **"More AI help or personalisation means more learning":** Storyfier and Leong found it doesn't.
- **"Speaking apps are proven":** the evidence is self-report or small uncontrolled studies.
- **"Per-word difficulty features help scheduling":** at Duolingo they overfit.
- **"Known-word counts measure proficiency":** they are self-marked and subjective.
- **"Seen 100 times = learned":** exposure isn't recall.
- **"A transcript match means good pronunciation":** it only shows the words were recognised.

**Still unverified:** the full texts of the ALOE and VocabEncounter papers, Lyu 2025's moderator results, Pimsleur's exact review intervals, and Apple's official documentation of the Mónica/Jorge voices.

### Critical Files for Implementation
- `VoiceInk/Features/SpanishCoach/Logic/SpanishMastery.swift`: the Leitner schedule that FSRS would replace (ideas 1–2).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishPhraseStore.swift`: `reinforcementCandidates` sorts by recency, not due date. "Mastered" is defined inconsistently: ≥3 in `masteredCount`, ≥5 in `masteredPhrases` (ideas 4, 8).
- `VoiceInk/Features/SpanishCoach/Workflows/SpanishCoachService.swift`: the LLM payload in `encodePayload` (ideas 3, 4, 10, 15).
- `VoiceInk/Features/SpanishCoach/Models/SpanishPhrase.swift`: needs a review log, FSRS state, and multiple example sentences (ideas 1, 9).
- `VoiceInk/Features/SpanishCoach/Views/SpanishPracticeView.swift`: es-ES voice, hint-then-retry, and cloze practice (ideas 5, 11, 12).