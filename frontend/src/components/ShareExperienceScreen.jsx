import { useState } from "react";
import { useLanguage } from "../i18n/LanguageContext";

export default function ShareExperienceScreen({ onReview }) {
  const { t } = useLanguage();
  const [voice, setVoice] = useState("第一次和教授討論報告時，我不知道怎麼判斷他的語氣是不是不滿意。");
  const [topic, setTopic] = useState("cultureCommunication");
  const [identityType, setIdentityType] = useState("degreeStudent");

  return (
    <div className="share-flow">
      <section className="share-intro"><p>{t("anonymousShare")}</p><h3 id="experience-prompt">{t("whatHappened")}</h3><span id="experience-guidance">{t("oneSentence")}</span></section>
      <textarea name="experience" autoComplete="off" value={voice} onChange={(event) => setVoice(event.target.value)} aria-labelledby="experience-prompt" aria-describedby="experience-guidance" />
      <div className="share-field"><p>{t("topic")}</p><div><button className={topic === "lifeAdaptation" ? "selected" : ""} type="button" onClick={() => setTopic("lifeAdaptation")}>{t("lifeAdaptation")}</button><button className={topic === "cultureCommunication" ? "selected" : ""} type="button" onClick={() => setTopic("cultureCommunication")}>{t("cultureCommunication")}</button></div></div>
      <div className="share-field"><p>{t("identityType")}</p><div><button className={identityType === "degreeStudent" ? "selected" : ""} type="button" onClick={() => setIdentityType("degreeStudent")}>{t("degreeStudent")}</button><button className={identityType === "exchangeStudent" ? "selected" : ""} type="button" onClick={() => setIdentityType("exchangeStudent")}>{t("exchangeStudent")}</button><button className={identityType === "languageStudent" ? "selected" : ""} type="button" onClick={() => setIdentityType("languageStudent")}>{t("languageStudent")}</button></div></div>
      <div className="anonymous-note">{t("anonymousNote")}</div>
      <button className="primary-button" type="button" onClick={() => onReview({ voice, topic, identityType })}>{t("askAiToOrganize")}</button>
    </div>
  );
}
