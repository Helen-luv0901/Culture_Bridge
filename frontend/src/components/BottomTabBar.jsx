import { tabs } from "../data/tabs";

export default function BottomTabBar({ activeTab, onTabChange }) {
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
          <span className="tab-label">{tab.label}</span>
        </button>
      ))}
    </nav>
  );
}
