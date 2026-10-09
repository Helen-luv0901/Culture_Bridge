import PhoneFrame from "./PhoneFrame";

export default function PhoneGrid() {
  return (
    <section className="phone-grid single-phone-preview" aria-label="Culture Bridge 手機預覽">
      <PhoneFrame initialRoute="home" label="點選底部分頁，試用 Culture Bridge" />
    </section>
  );
}
