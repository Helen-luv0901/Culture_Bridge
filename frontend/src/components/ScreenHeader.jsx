import LanguageToggle from "./LanguageToggle";

export default function ScreenHeader({ title }) {
  return (
    <header className="screen-header">
      <div className="header-top"><div className="brand">Culture Bridge</div><LanguageToggle /></div>
      <div className="screen-title">{title}</div>
    </header>
  );
}
