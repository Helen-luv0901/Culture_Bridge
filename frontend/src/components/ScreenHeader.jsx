export default function ScreenHeader({ title }) {
  return (
    <header className="screen-header">
      <div className="brand">Culture Bridge</div>
      <div className="screen-title">{title}</div>
    </header>
  );
}
