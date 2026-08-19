import TranslationToggle from "./TranslationToggle";
import { useState } from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function ExperienceCard({ experience, onOpen }) {
  const { t } = useLanguage();
  const [helpful, setHelpful] = useState(false);

  return (
    <article className="card experience-card">
      <TranslationToggle experience={experience}>
        {(content, isTranslated) => <>
          <div className="experience-meta"><span>{t(content.topicKey)}</span><span>{t(content.identityTypeKey)}</span><span>{t("anonymousShare")}</span></div>
          {isTranslated && <div className="translation-note">{t("translatedFrom")}</div>}
          <p className="experience-voice">「{content.originalVoice}」</p>
          <p className="experience-summary">{t("aiSummary")}：{content.summary}</p>
          <div className="experience-footer">
            <div className="post-feedback"><span>{experience.reactions} {t("reactions")}</span><button className={`helpful-button ${helpful ? "active" : ""}`} type="button" aria-pressed={helpful} onClick={() => setHelpful((current) => !current)}><span aria-hidden="true">{helpful ? "\u2665" : "\u2661"}</span>{experience.helpfulCount + (helpful ? 1 : 0)} {t("foundHelpful")}</button></div>
            <button type="button" onClick={() => onOpen(experience.id)}>{t("similarSituations")}</button>
          </div>
        </>}
      </TranslationToggle>
    </article>
  );
}
