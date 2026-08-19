import { useLanguage } from "../i18n/LanguageContext";

export default function LanguageToggle() {
  const { locale, setLocale } = useLanguage();

  return (
    <div className="language-toggle" role="group" aria-label="Language">
      <button aria-label="Switch interface language to Traditional Chinese" className={locale === "zh-Hant" ? "active" : ""} type="button" onClick={() => setLocale("zh-Hant")}>中</button>
      <button aria-label="Switch interface language to English" className={locale === "en" ? "active" : ""} type="button" onClick={() => setLocale("en")}>EN</button>
    </div>
  );
}
