import { useState } from "react";
import BottomTabBar from "./BottomTabBar";
import ScreenHeader from "./ScreenHeader";
import HomeScreen from "./HomeScreen";
import VideoScreen from "./VideoScreen";
import CommunityScreen from "./CommunityScreen";
import AiScreen from "./AiScreen";
import { tabs } from "../data/tabs";

function screenTitle(tabId) {
  return tabs.find((tab) => tab.id === tabId)?.label ?? "首頁";
}

function Page({ active, children }) {
  return <section className={`screen-page ${active ? "active" : ""}`}>{children}</section>;
}

export default function PhoneFrame({ initialTab }) {
  const [activeTab, setActiveTab] = useState(initialTab);

  return (
    <div className="phone-shell">
      <div className="phone-label">{screenTitle(activeTab)}</div>
      <div className="phone">
        <div className="screen">
          <div className="island" />
          <div className="status-bar">
            <span>9:41</span>
            <span>▮▮▮ 􀛨</span>
          </div>
          <div className="phone-body">
            <ScreenHeader title={screenTitle(activeTab)} />
            <div className="scroll-area">
              <Page active={activeTab === "home"}>
                <HomeScreen />
              </Page>
              <Page active={activeTab === "video"}>
                <VideoScreen />
              </Page>
              <Page active={activeTab === "community"}>
                <CommunityScreen />
              </Page>
              <Page active={activeTab === "ai"}>
                <AiScreen />
              </Page>
            </div>
            <BottomTabBar activeTab={activeTab} onTabChange={setActiveTab} />
          </div>
        </div>
      </div>
    </div>
  );
}
