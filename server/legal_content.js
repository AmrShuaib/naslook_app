// نصوص الصفحات القانونية لناس لايف (/privacy و/terms و/support) بالعربية مع قسم إنجليزي في آخر كل صفحة.
// النص مبني على ما يجمعه الكود فعلاً (راجع docs/legal-pages.md). أي تغيير جوهري في النص يرفع LEGAL_VERSION
// فيُطلب من المستخدمين الموافقة من جديد داخل التطبيق. النص يحتاج مراجعة مستشار قانوني قبل الإطلاق التجاري.

export const LEGAL_VERSION = "2026-09-25";
// 6 نوفمبر 2026: تحديث إيضاحي بلا رفع LEGAL_VERSION (فلا تُطلب موافقة جديدة): لا جمع جديداً ولا استخداماً أوسع للبيانات، بل
// تضييق (المحادثات الخاصة لا تصل أي ذكاء اصطناعي بعد إيقاف الردود الذكية) وإفصاح أدق عن معالجتين قائمتين يطلبهما صاحبهما
// صراحة (مساعد صندوق الدعم لفريقنا، وصياغة نص الوظيفة لفريق الدائرة)، وبيانات المنشأة، ونص إقرار العمر الموجود أصلاً (13 و18).
// 13 نوفمبر 2026: أُضيفت حالة ثالثة لـ Anthropic («صوّر المنيو»: صور قائمة يختارها صاحب النشاط بنفسه). التاريخ والنسخة لم يُرفعا هنا:
// harness_age_gate يثبّت التاريخ، ورفع LEGAL_VERSION (موافقة جديدة من الجميع) قرار المالك.
export const LEGAL_UPDATED_AR = "13 نوفمبر 2026";
export const LEGAL_UPDATED_EN = "13 November 2026";
export const COMPANY_AR = "شركة أريب الرقمية";
// الاسم القانوني كما في السجل التجاري؛ «Areeb Digital» اسم تجاري فقط
export const COMPANY_EN = "Areeb Alraqmiah Company (Areeb Digital)";

const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const mail = (e) => `<a href="mailto:${esc(e)}" dir="ltr">${esc(e)}</a>`;

/// بيانات المنشأة النظامية (نظام التجارة الإلكترونية، المادة السادسة) من إعدادات المنصة: كل سطر يظهر فقط حين يُضبط.
/// company = { cr, vat, address } نصوص مُتحقق منها في legal_pages.js (فارغة إن لم تُضبط).
export function companyLines(company = {}) {
  const c = company ?? {};
  const ar = [`الاسم النظامي: ${COMPANY_AR} (<span dir="ltr">Areeb Alraqmiah Company</span>)`];
  const en = ["Legal name: Areeb Alraqmiah Company (trading as Areeb Digital)"];
  if (c.cr) { ar.push(`السجل التجاري رقم <span dir="ltr">${esc(c.cr)}</span>`); en.push(`Commercial registration No. ${esc(c.cr)}`); }
  if (c.vat) { ar.push(`الرقم الضريبي <span dir="ltr">${esc(c.vat)}</span>`); en.push(`VAT No. ${esc(c.vat)}`); }
  if (c.address) { ar.push(`العنوان الوطني: ${esc(c.address)}`); en.push(`National address: ${esc(c.address)}`); }
  return { ar, en };
}
const aboutAr = (company) => `
<h2 id="about">من نحن</h2>
<p>ناس لايف منصة تشغّلها ${COMPANY_AR}، شركة مسجّلة في المملكة العربية السعودية.</p>
<ul>${companyLines(company).ar.map((l) => `<li>${l}</li>`).join("")}</ul>`;
const aboutEn = (company) => `<li><b>About us:</b> ${companyLines(company).en.join(" · ")}</li>`;

/// صفحة سياسة الخصوصية.
export function privacyBody({ supportEmail, company }) {
  const m = mail(supportEmail);
  return `
<h1>سياسة الخصوصية</h1>
<p class="lead">آخر تحديث: ${LEGAL_UPDATED_AR} · <a href="#en">English</a></p>
<p>ناس لايف (naslife.app) منصة اجتماعية وتجارية محلية تشغّلها ${COMPANY_AR} في المملكة العربية السعودية. توضّح هذه السياسة ما نجمعه من بياناتك، ولماذا، ومن يراه، وكيف تحذفه. نلتزم بنظام حماية البيانات الشخصية في المملكة.</p>

<h2>ملخص سريع</h2>
<ul>
<li>لا نعرض إعلانات من أطراف أخرى، ولا نبيع بياناتك، ولا نتتبعك عبر تطبيقات أو مواقع أخرى.</li>
<li>لا نستلم بيانات بطاقتك: الدفع بالبطاقة يتم على صفحة بوابة الدفع المرخّصة «ميسر».</li>
<li>تستطيع حذف حسابك من داخل التطبيق في أي وقت: ماي سبيس ← الحساب ← حذف الحساب.</li>
</ul>

<h2>البيانات التي نجمعها</h2>
<div class="tbl"><table>
<thead><tr><th>الفئة</th><th>ما تشمله</th><th>لماذا</th><th>من يراها</th></tr></thead>
<tbody>
<tr><td>الحساب</td><td>البريد الإلكتروني، اسم المستخدم، كلمة السر (محفوظة بشكل مشفّر)، عبارة الاسترداد (محفوظة مشفّرة)</td><td>إنشاء الحساب وتسجيل الدخول واستعادة كلمة السر</td><td>اسم المستخدم ظاهر للجميع؛ البريد لا يظهر لغيرك</td></tr>
<tr><td>الملف الشخصي</td><td>الصورة، النبذة، المهارات والاهتمامات، التعريف الصوتي</td><td>عرض ملفك للآخرين</td><td>بحسب إعدادك: عام أو خاص</td></tr>
<tr><td>الموقع الدقيق</td><td>موقع جهازك، فقط بعد إذنك وأثناء استخدام التطبيق</td><td>عرض ما حولك على الخريطة، وتحديد مكان منشوراتك وعروضك، وظهورك على الخريطة إن فعّلته</td><td>مكان المنشور يظهر مع المنشور؛ ظهورك الشخصي على الخريطة اختياري ومطفأ ما لم تفعّله</td></tr>
<tr><td>المحتوى</td><td>المنشورات والصور والفيديو والصوت والتعليقات والمراجعات وعروض السوق</td><td>نشر ما تختار نشره</td><td>بحسب مكان النشر (الخريطة، دائرة، السوق)؛ ولحظات الخريطة بحسب الجمهور الذي تختاره لكل لحظة: أصدقاؤك فقط (الافتراضي للحظة الشخصية) أو الجميع ما دام ملفك عاماً</td></tr>
<tr><td>المحادثات</td><td>الرسائل والوسائط والتفاعلات والبطاقات داخل المحادثة</td><td>توصيل الرسائل لأطرافها</td><td>أطراف المحادثة فقط</td></tr>
<tr><td>عناوين التوصيل</td><td>العناوين التي تحفظها في «عناويني»: التسمية والحي والتفاصيل والمدينة، ونقطة على الخريطة ورقم جوال إن أضفتهما</td><td>توصيل طلبات السوق التي تختار لها التوصيل</td><td>أنت وحدك. عند طلب بالتوصيل تُحفظ نسخة من العنوان المختار على الطلب، يراها البائع بعد تأكيد الطلب وما دام قائماً، ومندوب التوصيل ما دام مكلّفاً به، والإدارة عند نزاع فقط؛ وتُمحى من الطلب بعد 30 يوماً من انتهائه، وتُحذف عناوينك مع حسابك</td></tr>
<tr><td>المعاملات</td><td>رصيد المحفظة الداخلية، الطلبات، الحجوزات، التذاكر، عمليات الشحن</td><td>تنفيذ الطلبات والمدفوعات والاسترداد وحفظ السجلات النظامية</td><td>أنت والطرف الآخر في المعاملة</td></tr>
<tr><td>الإشعارات</td><td>رمز اشتراك الإشعارات لجهازك</td><td>إرسال التنبيهات التي تطلبها</td><td>لا أحد</td></tr>
<tr><td>الاستخدام</td><td>مشاهدات ونقرات وإعجابات على المنشورات والعروض</td><td>إحصاءات تظهر لصاحب المنشور أو العرض، وتحسين الخدمة</td><td>أرقام مجمّعة لصاحب المحتوى</td></tr>
<tr><td>الدعم</td><td>رسائلك مع فريق الدعم</td><td>الرد على طلباتك</td><td>فريق الدعم</td></tr>
<tr><td>البيانات التقنية</td><td>عنوان IP ونوع الجهاز في سجلات الخادم</td><td>الأمان ومنع الاحتيال والمحاولات المسيئة</td><td>لا أحد</td></tr>
</tbody></table></div>

<h2>مع من نشارك البيانات</h2>
<p>لا نشارك بياناتك إلا بالقدر اللازم لتشغيل الخدمة، مع مزوّدين ملتزمين بحمايتها:</p>
<ul>
<li><b>ميسر</b> (بوابة دفع مرخّصة): لإتمام الدفع بالبطاقة على صفحتها المستضافة.</li>
<li><b>مزوّد البريد الإلكتروني</b>: لإرسال رموز التأكيد والاستعادة ورسائل الخدمة.</li>
<li><b>مزوّد الاستضافة</b>: خوادم تشغيل المنصة وقاعدة بياناتها.</li>
<li><b>Anthropic</b> (مزوّد نموذج الذكاء الاصطناعي Claude): في ثلاث حالات فقط موضّحة في قسم <a href="#ai">الذكاء الاصطناعي</a>.</li>
<li><b>الجهات الرسمية</b>: عند طلب نظامي ملزم.</li>
</ul>

<h2 id="ai">الذكاء الاصطناعي</h2>
<p><b>محادثاتك الخاصة لا تُرسل إلى أي ذكاء اصطناعي.</b> الردود المقترحة فوق حقل الكتابة تأتي من قواعد ثابتة تعمل على خوادمنا، ولا يقرأ رسائلك أي نموذج.</p>
<p>نستخدم نموذج Claude من شركة Anthropic في ثلاث حالات فقط، ولا تعمل أي منها إلا حين يطلبها موظف الدعم أو فريق الدائرة أو صاحب النشاط بنفسه. تعالج Anthropic ما يُرسل إليها على خوادم خارج المملكة:</p>
<ul>
<li><b>صندوق الدعم</b> (رسائل البريد الإلكتروني التي ترسلها إلى عناويننا، ومنها بريد الدعم): حين يكون المساعد الذكي مفعّلاً ويطلب موظف من فريقنا ملخصاً لمراسلة أو مسودة رد عليها، تُرسل نصوص رسائل تلك المراسلة ووقت كل رسالة واسم مرسلها (أو بريده إن لم يذكر اسماً)، ولا تُرسل الملاحظات الداخلية للفريق. الملخص للفريق وحده، والمسودة لا تصلك إلا بعد أن يراجعها الموظف ويعدّلها إن لزم ثم يرسلها بنفسه.</li>
<li><b>صياغة عرض وظيفي</b>: حين يكون المساعد الذكي مفعّلاً ويضغط فريق دائرة «اكتب لي العرض» تُرسل بيانات العرض التي كتبها فقط: اسم الدائرة وفئتها، المسمّى الوظيفي، القسم، نوع الدوام، المدينة، النقاط التي كتبها، ونطاق الراتب إن حدّده. لا تُحفظ المسودة حتى يراجعها الفريق ويحفظها بنفسه. لا تُرسل أي بيانات عن المرشحين ولا ملفات التوظيف.</li>
<li><b>صوّر المنيو</b>: حين يكون المساعد الذكي مفعّلاً ويضغط صاحب نشاط «صوّر المنيو» تُرسل صور القائمة التي اختارها فقط لقراءة أسماء الأصناف وأسعارها. لا يُرسل معها اسمك ولا حسابك ولا موقعك. تعود الأصناف إليه ليراجعها، ولا يُحفظ منها شيء حتى يؤكدها بنفسه. الصورة نفسها تبقى محفوظة على خوادمنا برابط لا يُخمَّن مثل أي صورة تُرفع إلى المنصة. فلا تصوّر ما فيه بيانات شخصية.</li>
</ul>
<p>إن أضفنا مستقبلاً اقتراحات ذكية في المحادثات فلن تعمل إلا بعد موافقتك الصريحة، ونحدّث هذه السياسة قبلها.</p>

<h2>الاحتفاظ بالبيانات</h2>
<ul>
<li>بيانات الحساب والملف والمحتوى: ما دام حسابك قائماً.</li>
<li>عند حذف الحساب: يُحذف بريدك وملفك وصورتك واشتراكات إشعاراتك فوراً، ويُخفى محتواك ثم يُمسح خلال 30 يوماً.</li>
<li>السجلات المالية (المحفظة والطلبات والمدفوعات): نحتفظ بها المدة التي تفرضها الأنظمة، مرتبطة بمعرّف مجهول لا يدل عليك.</li>
<li>الرسائل التي وصلت لغيرك تبقى عند مستلميها، ويظهر اسمك فيها «مستخدم محذوف».</li>
</ul>

<h2 id="delete-account">حذف الحساب</h2>
<p>من التطبيق: <b>ماي سبيس ← الحساب ← حذف الحساب</b>، ثم أدخل كلمة السر للتأكيد. إن لم تستطع الدخول فراسلنا من بريد حسابك على ${m} ونحذفه خلال 30 يوماً.</p>

<h2>حقوقك</h2>
<p>لك أن تطلع على بياناتك وتصحّحها وتطلب حذفها، وأن تسحب إذن الموقع أو الإشعارات من إعدادات جهازك في أي وقت. لأي طلب يخص بياناتك راسلنا على ${m}.</p>

<h2>الأمان</h2>
<p>نستخدم اتصالاً مشفّراً (HTTPS)، ونحفظ كلمات السر وعبارات الاسترداد مشفّرة، ونقصر الوصول إلى البيانات على من يحتاجه من فريقنا.</p>

<h2>الأعمار</h2>
<p>ناس لايف لمن أعمارهم 13 عاماً فأكثر، ونطلب منك الإقرار بذلك عند التسجيل. شحن المحفظة والشراء والبيع بمقابل للبالغين 18 عاماً فأكثر، ونطلب منك الإقرار بذلك مرة واحدة قبل أول عملية مالية. نحفظ تاريخ الإقرار مع حسابك.</p>

<h2>تعديل السياسة</h2>
<p>ننشر أي تعديل على هذه الصفحة مع تاريخه، ونطلب موافقتك داخل التطبيق إن كان التعديل جوهرياً.</p>

${aboutAr(company)}

<h2>التواصل</h2>
<p>${COMPANY_AR} · البريد: ${m}</p>

<section id="en" lang="en" dir="ltr">
<h1>Privacy Policy</h1>
<p class="lead">Last updated: ${LEGAL_UPDATED_EN}</p>
<p>Naslife (naslife.app) is a local social and marketplace platform operated by ${COMPANY_EN} in Saudi Arabia. We follow the Saudi Personal Data Protection Law.</p>
<ul>
<li><b>No ads, no tracking, no sale of data.</b> We do not track you across other apps or websites.</li>
<li><b>Account:</b> email, username, password and recovery phrase (stored encrypted), used to sign in and recover your account.</li>
<li><b>Profile:</b> photo, bio, skills, interests and voice intro, visible according to your privacy setting.</li>
<li><b>Precise location:</b> only with your permission and while the app is in use, to show what is around you and where your posts are. Appearing on the map yourself is optional and off by default.</li>
<li><b>Content and chats:</b> posts, photos, videos, audio, comments, reviews, listings and messages, shown where you choose to publish them; messages go only to their participants.</li>
<li><b>Delivery addresses:</b> the addresses you save in "My addresses" (label, district, details, city, and optionally a map point and a mobile number) are visible only to you. When you order with delivery, a copy of the chosen address is kept on that order and shown to the seller once the order is confirmed and while it is open, to the courier while assigned, and to our team only in a dispute; it is erased from the order 30 days after the order ends, and your saved addresses are deleted with your account.</li>
<li><b>Transactions:</b> in-app wallet balance, orders, bookings, tickets and top-ups. Card payments happen on the hosted page of Moyasar, a licensed payment gateway; we never receive card data.</li>
<li><b>Usage and technical data:</b> views, clicks and likes shown as statistics to content owners; IP address and device type in server logs for security.</li>
<li><b>Processors:</b> Moyasar (payments), our email provider and our hosting provider.</li>
<li><b>AI:</b> your private chats are never sent to any AI; suggested replies in chat come from fixed rules on our servers. We use Anthropic's Claude, processed outside Saudi Arabia, in three cases only, each run only when a support agent, a circle's team or a business owner asks for it: (1) in the support inbox (emails you send to our addresses, including support), when the assistant is enabled and an agent asks for a summary or a draft reply, the messages of that thread are sent with their times and the sender's name (or email address when no name is given), never the team's internal notes, and an agent reviews (and edits where needed) every draft and sends it personally; (2) when the assistant is enabled and a circle's team taps "Write the job offer for me", only the job details they typed are sent (circle name and category, title, department, job type, city, their bullet points and salary range); no candidate data is sent; (3) when the assistant is enabled and a business owner taps "Photograph the menu", only the menu photos they chose are sent to read item names and prices, without their name, account or location, and nothing is saved until they review and confirm the items; the photo itself stays stored on our servers at an unguessable link, like any image uploaded to the platform. Any future AI feature in chat will require your explicit opt-in first.</li>
<li><b>Retention:</b> while your account exists. On deletion we remove your email, profile, photo and push subscriptions immediately and hide your content, which is erased within 30 days. Financial records are kept as required by law under an anonymous identifier. Messages already delivered stay with their recipients and show "Deleted user".</li>
<li><b>Delete your account</b> in the app: My Space → Account → Delete account. If you cannot sign in, email us from your account address.</li>
<li><b>Ages:</b> 13 and over, declared at sign-up; wallet top-ups, buying and selling for money are for users 18 and over, declared once before the first financial action.</li>
${aboutEn(company)}
<li><b>Contact:</b> ${m}</li>
</ul>
</section>`;
}

/// صفحة شروط الاستخدام (فيها بند عدم التسامح مع المحتوى المسيء الذي تشترطه متاجر التطبيقات).
export function termsBody({ supportEmail, company }) {
  const m = mail(supportEmail);
  return `
<h1>شروط الاستخدام</h1>
<p class="lead">آخر تحديث: ${LEGAL_UPDATED_AR} · <a href="#en">English</a></p>
<p>باستخدامك ناس لايف أو إنشائك حساباً فيه فإنك توافق على هذه الشروط وعلى <a href="/privacy">سياسة الخصوصية</a>. المنصة تشغّلها ${COMPANY_AR}.</p>

<h2>1. الحساب</h2>
<ul>
<li>أنت مسؤول عن سرية كلمة السر وعن كل ما يتم من حسابك.</li>
<li>تلتزم بتقديم بيانات صحيحة وعدم انتحال شخصية أحد أو جهة.</li>
<li>العمر الأدنى 13 عاماً وتقرّ بذلك عند التسجيل. شحن المحفظة والشراء والبيع بمقابل لمن عمره 18 عاماً فأكثر، وتقرّ بذلك مرة واحدة قبل أول عملية مالية. الإقرار غير الصحيح مخالفة لهذه الشروط تجيز لنا إيقاف الحساب.</li>
</ul>

<h2 id="community">2. قواعد المجتمع</h2>
<p class="strong-note"><b>لا تسامح مطلقاً مع المحتوى المسيء أو المستخدمين المسيئين.</b> أي مخالفة قد تؤدي إلى حذف المحتوى وإيقاف الحساب فوراً ودون إنذار.</p>
<p>يُمنع نشر أو إرسال ما يلي:</p>
<ul>
<li>الكراهية أو التمييز أو الإساءة لأي شخص أو فئة أو دين.</li>
<li>التحرش أو التهديد أو التنمر أو التشهير.</li>
<li>المحتوى الجنسي أو الفاضح أو العنيف أو المروّع.</li>
<li>بيع أو ترويج ما يخالف الأنظمة: الممنوعات، السلاح، المواد المقلّدة، الأدوية دون ترخيص.</li>
<li>الاحتيال والتضليل والرسائل المزعجة والروابط الضارة.</li>
<li>انتهاك خصوصية الآخرين أو نشر بياناتهم أو صورهم دون إذنهم.</li>
<li>انتهاك حقوق الملكية الفكرية لغيرك.</li>
<li>كل ما يخالف أنظمة المملكة العربية السعودية أو الآداب العامة.</li>
</ul>

<h2>3. الإشراف والإبلاغ والحظر</h2>
<ul>
<li>نستخدم تصفية تلقائية للكلمات المسيئة، ويُخفى المحتوى تلقائياً إذا تكررت البلاغات عليه.</li>
<li>تستطيع الإبلاغ عن أي منشور أو تعليق أو عرض أو حساب من قائمة «⋯» ثم «إبلاغ».</li>
<li>تستطيع حظر أي مستخدم من ملفه أو من المحادثة، فلا يصلك منه محتوى ولا رسائل.</li>
<li>نراجع البلاغات خلال 24 ساعة، ونحذف المحتوى المخالف ونوقف حساب ناشره.</li>
</ul>

<h2>4. المحتوى الذي تنشره</h2>
<p>تبقى ملكية محتواك لك، وتمنحنا ترخيصاً غير حصري لعرضه وتخزينه ونقله داخل المنصة بالقدر اللازم لتشغيلها. أنت مسؤول عن محتواك وعن حقك في نشره.</p>

<h2>5. السوق والدوائر التجارية</h2>
<ul>
<li>ناس لايف وسيط يتيح العرض والطلب؛ البائع أو صاحب النشاط مسؤول عن صحة عرضه وجودة ما يقدمه وتسليمه.</li>
<li>السلع المادية والخدمات تُدفع من المحفظة الداخلية، ويُشحن رصيدها بالبطاقة عبر بوابة ميسر المرخّصة.</li>
<li>في حال الخلاف افتح نزاعاً من صفحة الطلب، وتراجعه الإدارة وتقرر الاسترداد وفق هذه الشروط.</li>
</ul>

<h2>6. المحفظة</h2>
<ul>
<li>المحفظة رصيد داخلي لاستخدامه في خدمات ناس لايف، وليست حساباً مصرفياً ولا وديعة ولا تحمل عائداً.</li>
<li>مبلغ الطلب الملغى أو المسترد يعود إلى محفظتك، والرصيد المتبقي عند حذف الحساب يُعاد إلى وسيلة الدفع الأصلية خلال 30 يوماً.</li>
<li>نحتفظ بحق تعليق الرصيد عند الاشتباه في احتيال أو مخالفة لهذه الشروط حتى انتهاء المراجعة.</li>
</ul>

<h2>7. إيقاف الحساب وحذفه</h2>
<p>يمكنك حذف حسابك من التطبيق في أي وقت (ماي سبيس ← الحساب ← حذف الحساب). ويحق لنا إيقاف أي حساب يخالف هذه الشروط.</p>

<h2>8. حدود المسؤولية</h2>
<p>نقدّم المنصة كما هي، ونبذل جهدنا لاستمرارها وأمانها، ولا نتحمل مسؤولية تعاملات المستخدمين فيما بينهم خارج ما تنص عليه هذه الشروط.</p>

<h2>9. النظام الواجب التطبيق</h2>
<p>تخضع هذه الشروط لأنظمة المملكة العربية السعودية، وتختص محاكمها بأي نزاع.</p>

<h2>10. التعديل والتواصل</h2>
<p>قد نعدّل الشروط وننشر التعديل هنا مع تاريخه، ونطلب موافقتك داخل التطبيق عند التعديل الجوهري. للتواصل: ${m}</p>
${aboutAr(company)}

<section id="en" lang="en" dir="ltr">
<h1>Terms of Use</h1>
<p class="lead">Last updated: ${LEGAL_UPDATED_EN}</p>
<p>By using Naslife or creating an account you agree to these terms and to the <a href="/privacy">Privacy Policy</a>. Naslife is operated by ${COMPANY_EN}.</p>
<p class="strong-note"><b>There is zero tolerance for objectionable content or abusive users.</b> Violations may lead to immediate removal of content and suspension of the account without notice.</p>
<ul>
<li><b>Prohibited:</b> hate or discrimination, harassment, threats or bullying, sexual, violent or graphic content, illegal or regulated goods, fraud, spam or harmful links, sharing others' private data or images without consent, intellectual property infringement, and anything unlawful in Saudi Arabia.</li>
<li><b>Moderation:</b> automatic filtering of offensive words, automatic hiding after repeated reports, reporting from the "⋯" menu on any post, comment, listing or profile, and blocking any user from their profile or chat. We review reports within 24 hours, remove violating content and suspend offenders.</li>
<li><b>Your content</b> stays yours; you grant us a non-exclusive licence to display and store it within the service.</li>
<li><b>Marketplace:</b> Naslife is a venue. Sellers are responsible for their listings. Physical goods and services are paid from the in-app wallet, which is topped up by card through Moyasar, a licensed payment gateway. Disputes can be opened from the order page.</li>
<li><b>Wallet:</b> an in-app balance for Naslife services, not a bank account or deposit. Cancelled or refunded orders return to the wallet; any remaining balance on account deletion is refunded to the original payment method within 30 days.</li>
<li><b>Account deletion:</b> My Space → Account → Delete account, at any time.</li>
<li><b>Ages:</b> 13 and over, declared at sign-up; 18 and over for wallet top-ups, buying and selling for money, declared once before the first financial action. A false declaration breaches these terms.</li>
<li><b>Governing law:</b> the laws of the Kingdom of Saudi Arabia.</li>
${aboutEn(company)}
<li><b>Contact:</b> ${m}</li>
</ul>
</section>`;
}

/// صفحة الدعم والتواصل (رابط الدعم المطلوب في متجر التطبيقات).
export function supportBody({ supportEmail, supportHandle, company }) {
  const m = mail(supportEmail);
  const chat = supportHandle ? `<li>داخل التطبيق: راسل حساب الدعم <b dir="ltr">@${esc(supportHandle)}</b> من المحادثات.</li>` : "";
  return `
<h1>الدعم والمساعدة</h1>
<p class="lead"><a href="#en">English</a></p>

<h2>تواصل معنا</h2>
<ul>
<li>البريد: ${m}</li>
${chat}
<li>نرد على البلاغات خلال 24 ساعة، وعلى بقية الطلبات خلال يومي عمل.</li>
</ul>
${aboutAr(company)}

<h2 id="report">الإبلاغ عن محتوى أو مستخدم</h2>
<ol>
<li>افتح المنشور أو التعليق أو العرض أو الملف الشخصي.</li>
<li>اضغط «⋯» ثم «إبلاغ» واختر السبب.</li>
<li>يصل البلاغ لفريق الإشراف فوراً، ويُخفى المحتوى تلقائياً إن تكررت البلاغات عليه.</li>
</ol>

<h2 id="block">حظر مستخدم</h2>
<p>من ملف المستخدم أو من قائمة المحادثة اختر «حظر». لن تصلك رسائله ولن ترى محتواه، وتستطيع إلغاء الحظر من ماي سبيس.</p>

<h2 id="delete-account">حذف الحساب</h2>
<ol>
<li>افتح <b>ماي سبيس</b> ثم قسم <b>الحساب</b>.</li>
<li>اختر <b>حذف الحساب</b> واقرأ ما سيُحذف وما يُحفظ نظاماً.</li>
<li>اكتب كلمة «حذف» وكلمة السر ثم أكّد.</li>
</ol>
<p>إن لم تستطع الدخول فراسلنا من بريد حسابك على ${m} ونحذفه خلال 30 يوماً.</p>

<h2>المدفوعات والاسترداد</h2>
<p>الدفع بالبطاقة يتم عبر ميسر. لأي مشكلة في طلب افتح نزاعاً من صفحة الطلب، أو راسلنا مع رقم الطلب.</p>

<h2>روابط</h2>
<ul><li><a href="/privacy">سياسة الخصوصية</a></li><li><a href="/terms">شروط الاستخدام</a></li></ul>

<section id="en" lang="en" dir="ltr">
<h1>Support</h1>
<ul>
<li><b>Email:</b> ${m}. Reports are answered within 24 hours, other requests within 2 business days.</li>
<li><b>Report content or a user:</b> open the post, comment, listing or profile, tap "⋯", then "Report".</li>
<li><b>Block a user:</b> from their profile or the chat menu, choose "Block".</li>
<li><b>Delete your account:</b> My Space → Account → Delete account, then type the confirmation word and your password. If you cannot sign in, email us from your account address.</li>
<li><b>Payments:</b> card payments are processed by Moyasar. Open a dispute from the order page or email us with the order number.</li>
${aboutEn(company)}
<li><a href="/privacy">Privacy Policy</a> · <a href="/terms">Terms of Use</a></li>
</ul>
</section>`;
}
