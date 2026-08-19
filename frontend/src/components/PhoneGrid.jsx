import PhoneFrame from "./PhoneFrame";
import { showcaseScreens } from "../data/tabs";

export default function PhoneGrid() {
  return (
    <section className="phone-grid">
      {showcaseScreens.map((screen) => (
        <PhoneFrame key={screen.route} initialRoute={screen.route} label={screen.label} />
      ))}
    </section>
  );
}
