import PhoneFrame from "./PhoneFrame";
import { screenOrder } from "../data/tabs";

export default function PhoneGrid() {
  return (
    <section className="phone-grid">
      {screenOrder.map((screen) => (
        <PhoneFrame key={screen} initialTab={screen} />
      ))}
    </section>
  );
}
