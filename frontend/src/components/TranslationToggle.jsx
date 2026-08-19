import { useEffect, useState } from "react";
import { translateExperience, useLanguage } from "../i18n/LanguageContext";

export default function TranslationToggle({ experience, children }) {
  const { locale, t } = useLanguage();
  const targetLocale = locale === experience.sourceLanguage ? "en" : locale;
  const hasTranslation = Boolean(experience.translations?.[targetLocale]);
  const [showTranslation, setShowTranslation] = useState(locale !== experience.sourceLanguage && hasTranslation);

  useEffect(() => {
    setShowTranslation(locale !== experience.sourceLanguage && hasTranslation);
  }, [experience.id, hasTranslation, locale, experience.sourceLanguage]);

  const content = showTranslation && hasTranslation ? translateExperience(experience, targetLocale) : experience;

  return (
    <>
      {children(content, showTranslation && hasTranslation)}
      {hasTranslation && <button className="translation-toggle" type="button" onClick={() => setShowTranslation((current) => !current)}>{showTranslation ? t("showOriginal") : (locale === experience.sourceLanguage ? t("translate") : t("showTranslation"))}</button>}
    </>
  );
}
