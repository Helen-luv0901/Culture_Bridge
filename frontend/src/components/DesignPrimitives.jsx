import symbols from '../assets/design-symbols.svg?raw';
export function DesignSymbols() { return <div aria-hidden="true" dangerouslySetInnerHTML={{ __html: symbols }} />; }
export function InkIcon({ name }) { return <svg className="ink-icon" viewBox="0 0 24 24" aria-hidden="true"><use href={`#i-${name}`} /></svg>; }
export function PaperPanel({ className = '', children }) { return <section className={`paper-panel ${className}`}><span className="paper-back" aria-hidden="true" /><span className="paper-face" aria-hidden="true" /><span className="paper-tape" aria-hidden="true" /><div className="paper-content">{children}</div></section>; }
