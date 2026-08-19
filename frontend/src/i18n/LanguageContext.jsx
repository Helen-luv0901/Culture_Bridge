import { createContext, useContext, useEffect, useState } from "react";

const LanguageContext = createContext(null);

const supportedLocales = ["zh-Hant", "en"];

const messages = {
  "zh-Hant": {
    home: "首頁", explore: "探索", share: "分享", my: "我的", myExperiences: "我的經驗",
    understand: "你正在台灣適應什麼？", startWithSituation: "從情境開始", someoneAlsoFelt: "有人也遇過",
    shareMyExperience: "分享我的經驗", anonymousShare: "匿名分享", similarSituations: "看相似情境",
    aiSummary: "AI 整理", aiSummaryConfirmed: "AI 整理，已由作者確認", sourceLanguage: "原始語言：繁體中文",
    aiTranslated: "AI 翻譯", showOriginal: "查看原文", showTranslation: "查看英文譯文", translate: "翻譯成英文", differentExperiences: "不同學生怎麼說",
    myExperienceDifferent: "我的經驗不同", iAlsoExperienced: "我也遇過", helpful: "這對我有幫助",
    whatHappened: "發生了什麼，讓你有這樣的感受？", oneSentence: "一句話就可以。你可以在發布前確認 AI 的整理。",
    topic: "問題主題", identityType: "身分類型", lifeAdaptation: "生活適應", cultureCommunication: "文化與溝通",
    lifeDescription: "住宿、飲食、交通、醫療與第一次獨自在台灣生活的各種意外。", cultureDescription: "教授、同學、語氣、社交與你不確定怎麼理解的時刻。",
    degreeStudent: "學位生", exchangeStudent: "交換生", languageStudent: "華語生",
    anonymousNote: "你的姓名與學校不會公開。", askAiToOrganize: "請 AI 幫我整理", reviewBeforePublish: "發布前確認",
    reviewTitle: "AI 幫你保留了原話，也整理了情境。", reviewNote: "這不是唯一答案，只是讓下一位學生更容易理解你的經驗。",
    yourOriginalVoice: "你的原話", aiDraft: "AI 整理草稿", situation: "情境", reminder: "可能有幫助的提醒",
    editOriginal: "修改原話", publishAnonymously: "確認並匿名發布", all: "全部",
    exploreNote: "不是誰比較正確，而是不同情境下可能有不同感受與做法。", mySharedExperiences: "已分享的經驗",
    yourImpact: "你的影響", language: "語言", systemLanguage: "跟隨系統", translatedFrom: "由繁體中文翻譯",
    reactions: "則不同經驗", foundHelpful: "人覺得有幫助", originalShare: "原始分享", shownInEnglish: "目前顯示英文譯文",
  },
  en: {
    home: "Home", explore: "Explore", share: "Share", my: "My", myExperiences: "My experiences",
    understand: "What are you adjusting to in Taiwan?", startWithSituation: "Start with a situation", someoneAlsoFelt: "Someone felt this too",
    shareMyExperience: "Share my experience", anonymousShare: "Anonymous share", similarSituations: "See similar situations",
    aiSummary: "AI summary", aiSummaryConfirmed: "AI summary, confirmed by the author", sourceLanguage: "Original language: Traditional Chinese",
    aiTranslated: "AI translation", showOriginal: "Show original", showTranslation: "Show translation", translate: "Translate to English", differentExperiences: "How other students experienced it",
    myExperienceDifferent: "My experience was different", iAlsoExperienced: "I experienced this too", helpful: "This helped me",
    whatHappened: "What happened, and how did it make you feel?", oneSentence: "One sentence is enough. You can review the AI draft before publishing.",
    topic: "Topic", identityType: "Identity type", lifeAdaptation: "Life adaptation", cultureCommunication: "Culture & communication",
    lifeDescription: "Housing, food, transport, healthcare, and the unexpected parts of living in Taiwan for the first time.", cultureDescription: "Professors, classmates, tone, social situations, and moments that are hard to interpret.",
    degreeStudent: "Degree student", exchangeStudent: "Exchange student", languageStudent: "Language student",
    anonymousNote: "Your name and school will not be shown.", askAiToOrganize: "Ask AI to organize", reviewBeforePublish: "Review before publishing",
    reviewTitle: "AI kept your original voice and organized the situation.", reviewNote: "This is not one correct answer. It helps the next student understand your experience.",
    yourOriginalVoice: "Your original voice", aiDraft: "AI draft", situation: "Situation", reminder: "A reminder that may help",
    editOriginal: "Edit original", publishAnonymously: "Confirm and publish anonymously", all: "All",
    exploreNote: "No one is more correct. Different situations can lead to different feelings and choices.", mySharedExperiences: "Shared experiences",
    yourImpact: "Your impact", language: "Language", systemLanguage: "Follow system", translatedFrom: "Translated from Traditional Chinese",
    reactions: "different experiences", foundHelpful: "found this helpful", originalShare: "Original share", shownInEnglish: "Showing English translation",
  },
};

function systemLocale() {
  return navigator.language?.toLowerCase().startsWith("zh") ? "zh-Hant" : "en";
}

export function LanguageProvider({ children }) {
  const [locale, setLocale] = useState(() => {
    const savedLocale = window.localStorage.getItem("culture-bridge-locale");
    return supportedLocales.includes(savedLocale) ? savedLocale : systemLocale();
  });

  useEffect(() => {
    window.localStorage.setItem("culture-bridge-locale", locale);
  }, [locale]);

  function t(key) {
    return messages[locale][key] ?? key;
  }

  return <LanguageContext.Provider value={{ locale, setLocale, t }}>{children}</LanguageContext.Provider>;
}

export function useLanguage() {
  const context = useContext(LanguageContext);
  if (!context) throw new Error("useLanguage must be used inside LanguageProvider");
  return context;
}

export function translateExperience(experience, locale) {
  if (locale === experience.sourceLanguage || !experience.translations?.[locale]) return experience;
  return { ...experience, ...experience.translations[locale], isTranslated: true };
}
