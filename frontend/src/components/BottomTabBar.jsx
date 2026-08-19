import { tabs } from "../data/tabs";
import { useLanguage } from "../i18n/LanguageContext";

export default function BottomTabBar({ activeTab, onTabChange }) {
  const { t } = useLanguage();

  return (
    <nav className="tabbar">
      {tabs.map((tab) => (
        <button
          key={tab.id}
          className={`tab ${tab.id === activeTab ? "active" : ""}`}
          type="button"
          onClick={() => onTabChange(tab.id)}
        >
          <span className={`tab-icon icon-${tab.icon}`} />
          <span className="tab-label">{t(tab.id === "profile" ? "my" : tab.id)}</span>
        </button>
      ))}
    </nav>
  );
}
