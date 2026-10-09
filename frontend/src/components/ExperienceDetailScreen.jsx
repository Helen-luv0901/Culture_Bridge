import { useState } from "react";
import TranslationToggle from "./TranslationToggle";
import { useLanguage } from "../i18n/LanguageContext";

export default function ExperienceDetailScreen({ experience, onShareDifferent }) {
  const [responded, setResponded] = useState(false);
  const [experienced, setExperienced] = useState(false);
  const [helpful, setHelpful] = useState(false);
  const { locale, t } = useLanguage();

  return (
    <div className="experience-detail">
      <TranslationToggle experience={experience}>
        {(content, isTranslated) => <>
          <div className="experience-meta"><span>{t(content.topicKey)}</span><span>{t(content.identityTypeKey)}</span><span>{t("anonymousShare")}</span></div>
          {isTranslated && <div className="translation-banner"><span>{t("aiTranslated")}</span>{t("translatedFrom")}</div>}
          <section className="detail-voice">
            <p>{t("originalShare")}</p>
            <h3>「{content.originalVoice}」</h3>
          </section>
          <section className="ai-experience-summary">
            <span>{t("aiSummaryConfirmed")}</span>
            <h4>{t("situation")}</h4>
            <p>{content.summary}</p>
            <h4>{t("reminder")}</h4>
            <p>{content.reminder}</p>
          </section>
        </>}
      </TranslationToggle>
      <section className="different-experiences">
        <h4>{t("differentExperiences")}</h4>
        <article><strong>{t("exchangeStudent")}</strong><p>{locale === "en" ? "My professor usually says directly when they disagree, so I now confirm their meaning by email." : "我的教授通常會直接說不同意，所以我後來會用郵件確認他的意思。"}</p></article>
        <article><strong>{t("degreeStudent")}</strong><p>{locale === "en" ? "For me, it often means that I need to add more information, not necessarily that I am being rejected." : "對我來說，這常代表還要補資料，不一定是拒絕。"}</p></article>
      </section>
      <button className="primary-button" type="button" onClick={() => { setResponded(true); onShareDifferent(); }}>
        {responded ? t("shareMyExperience") : t("myExperienceDifferent")}
      </button>
      <div className="secondary-experience-actions"><button type="button" aria-pressed={experienced} onClick={() => setExperienced(value => !value)}>{experienced && "✓ "}{t("iAlsoExperienced")}</button><button type="button" aria-pressed={helpful} onClick={() => setHelpful(value => !value)}>{helpful && "✓ "}{t("helpful")}</button></div>
    </div>
  );
}
