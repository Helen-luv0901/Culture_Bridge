# Culture Bridge Experience-Led MVP

## Product Definition

Culture Bridge helps international students in Taiwan understand unfamiliar living, cultural, and campus situations through real student experiences.

It is not a procedure tutorial product and not a general AI chat product. Its value is making differences in lived experience visible without pretending that there is one correct answer.

## MVP Focus

### Primary topics

- Life adaptation
- Culture and communication

Administrative procedures remain searchable supporting information. They are not the primary home-page experience in this MVP.

### Primary user need

"I am in an unfamiliar situation. How have students with similar concerns experienced it?"

## Core Loop

```text
Student encounters an unfamiliar situation
        ->
Explores similar anonymous experiences
        ->
Understands common patterns and meaningful differences
        ->
Shares one sentence about their own situation and feeling
        ->
AI prepares an experience summary without replacing the original voice
        ->
Author confirms the summary
        ->
The next student can understand a richer range of experiences
```

## Core Objects

### Experience Card

An Experience Card is the primary MVP content unit.

```text
ExperienceCard
├── original_voice
├── topic
├── identity_type
├── anonymous_author
├── AI_summary
├── author_confirmed_at
├── related_experiences
└── difference_responses
```

The original voice is always visible. AI summaries must be clearly labeled as summaries and must not turn experience into fact.

### Context Tags

Required tags should stay low-friction:

- Topic
- Identity type

Location, school, arrival time, and cultural background are optional only when the author wants to add them.

## User Flow

### 1. Explore

The home page asks: "What are you trying to understand in Taiwan?"

It presents Life Adaptation and Culture & Communication, then shows relevant situation cards.

### 2. Read Differences

An experience detail page shows the original anonymous story, an AI-generated summary, context tags, and different student responses.

The primary reader response is: "My experience was different."

"I experienced this too" and "Helpful" are secondary actions.

### 3. Share

The share flow starts with one prompt:

```text
What happened, and how did it make you feel?
```

The author writes one short sentence. The product defaults to anonymous sharing.

### 4. Review AI Summary

AI returns a draft with:

- Original voice
- Situation
- What the student felt or tried
- A reminder for the next student

The author can edit, confirm, or discard the draft. Nothing is published until confirmation.

## MVP Navigation

```text
Home
Explore
Share
My Experiences
```

AI belongs inside search, discovery, and sharing. It is not a standalone ChatGPT-style destination.

## Non-Goals

- Do not use likes as a truth signal.
- Do not convert experience into verified fact.
- Do not make an AI chatbot the main entry point.
- Do not require long-form posts or public identity.
- Do not make procedure tutorials the home-page focus.

## MVP Success Signals

- Similar-situation view rate
- Experience share rate
- AI summary confirmation rate
- "My experience was different" response rate
- Return usage rate

## Later Supporting Layer

Verified procedure and Action Card content can support students when they need formal, current information. It should remain explicitly separate from experience content and should only grow after the experience loop is useful.
