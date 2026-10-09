import { InkIcon } from "./DesignPrimitives";
import { tabs } from "../data/tabs";
import { useLanguage } from "../i18n/LanguageContext";

export default function BottomTabBar({ activeTab, onTabChange }) {
  const { t } = useLanguage();

  return (
    <nav className="tabbar" aria-label={t("home")}>
      {tabs.map((tab) => (
        <a
          key={tab.id}
          className={`tab ${tab.id === activeTab ? "active" : ""}`}
          href={`#${tab.id}`}
          onClick={(event) => { if (onTabChange) { event.preventDefault(); onTabChange(tab.id); } }} aria-current={tab.id === activeTab ? "page" : undefined}
        >
          <InkIcon name={{home: "home", explore: "compass", share: "feather", profile: "user"}[tab.id]} />
          <span className="tab-label">{t(tab.id === "profile" ? "my" : tab.id)}</span>
        </a>
      ))}
    </nav>
  );
}
