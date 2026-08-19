export const topics = [
  { id: "life", titleKey: "lifeAdaptation", descriptionKey: "lifeDescription", icon: "生" },
  { id: "culture", titleKey: "cultureCommunication", descriptionKey: "cultureDescription", icon: "語" },
];

export const experiences = [
  {
    id: "professor-see",
    sourceLanguage: "zh-Hant",
    topicKey: "cultureCommunication",
    identityTypeKey: "degreeStudent",
    originalVoice: "教授說「再看看」，我不知道這是不是代表他其實拒絕了我的想法。",
    summary: "這位學位生在和教授討論時，因為模糊的回應感到不確定。她後來先整理問題，再寄信確認下一步。",
    reminder: "如果你不確定意思，可以禮貌地確認下一步，不必把模糊回應直接理解成拒絕。",
    reactions: 8,
    helpfulCount: 24,
    translations: {
      en: {
        originalVoice: "My professor said, ‘Let's see.’ I could not tell whether that meant they were actually rejecting my idea.",
        summary: "This degree student felt uncertain after receiving an ambiguous response in a discussion with their professor. They later organized their questions and sent an email to confirm the next step.",
        reminder: "If you are unsure what something means, it is okay to politely confirm the next step instead of reading an ambiguous answer as rejection.",
      },
    },
  },
  {
    id: "first-rental",
    sourceLanguage: "zh-Hant",
    topicKey: "lifeAdaptation",
    identityTypeKey: "exchangeStudent",
    originalVoice: "第一次看房時我只注意房租，後來才發現電費和垃圾處理方式讓我很困擾。",
    summary: "這位交換生租屋後才發現生活費用和垃圾規則比租金更影響適應。",
    reminder: "看房前可以先問清楚電費、垃圾和合約結束方式。",
    reactions: 12,
    helpfulCount: 38,
    translations: {
      en: {
        originalVoice: "When I viewed my first rental, I only noticed the rent. Later, electricity charges and garbage rules became much more difficult than I expected.",
        summary: "This exchange student realized after moving in that living costs and garbage rules affected their adjustment more than the rent itself.",
        reminder: "Before viewing a place, ask about electricity charges, garbage disposal, and how the contract ends.",
      },
    },
  },
  {
    id: "class-invitation",
    sourceLanguage: "zh-Hant",
    topicKey: "cultureCommunication",
    identityTypeKey: "languageStudent",
    originalVoice: "同學一直說下次一起吃飯，但我不知道這是真正的邀請，還是只是客氣。",
    summary: "這位華語生正在理解日常客套與真正邀約之間的差異。",
    reminder: "可以先用一個具體時間回應，觀察對方是否願意繼續安排。",
    reactions: 5,
    helpfulCount: 17,
    translations: {
      en: {
        originalVoice: "My classmates keep saying, ‘Let's eat together next time,’ but I cannot tell whether it is a real invitation or just politeness.",
        summary: "This language student is learning the difference between everyday courtesy and a concrete invitation.",
        reminder: "Try replying with a specific time and see whether the other person wants to continue making plans.",
      },
    },
  },
];

export const featuredExperience = experiences[0];
