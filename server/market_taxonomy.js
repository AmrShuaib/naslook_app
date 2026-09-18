// تصنيفات السوق وتصنيفاتها الفرعية: مشتركة بين commerce.js وmarket_plus.js والتطبيق (lib/api/commerce_models.dart)
export const CATEGORIES = ["coffee", "food", "photo", "gifts", "handmade", "delivery", "services", "other"];
export const SUBCATEGORIES = {
  coffee: { beans: "حبوب ومحاصيل", tools: "أدوات تخمير", drinks: "مشروبات جاهزة", workshops: "ورش وتدريب" },
  food: { meals: "وجبات وولائم", sweets: "حلويات وكيك", pastries: "معجنات", dates: "تمور", subscriptions: "اشتراكات وجبات", catering: "ضيافة ومناسبات" },
  photo: { products: "تصوير منتجات", events: "مناسبات وأعراس", portraits: "بورتريه وعائلي", editing: "تعديل ومونتاج", prints: "طباعة ولوحات", drone: "تصوير جوي" },
  gifts: { boxes: "بوكسات", flowers: "ورد", perfume: "عطور وعود", personalized: "هدايا بالاسم", corporate: "هدايا شركات" },
  handmade: { crochet: "كروشيه وتطريز", candles: "شموع", resin: "ريزن", pottery: "فخار وسيراميك", jewelry: "إكسسوارات", art: "لوحات وفن" },
  delivery: { parcels: "طرود ومشاوير", groceries: "بقالة وصيدلية", airport: "مطار وسفر", moving: "نقل أثاث", pets: "حيوانات أليفة" },
  services: { maintenance: "صيانة منزلية", education: "تعليم ودروس", beauty: "تجميل وحناء", design: "تصميم وسوشيال", cars: "سيارات", fitness: "لياقة وتغذية", tech: "أجهزة وتقنية", cleaning: "تنظيف", tailoring: "خياطة", events: "تنظيم مناسبات" },
  other: { clothing: "ملابس وعبايات", plants: "نباتات", books: "كتب", electronics: "إلكترونيات", furniture: "أثاث", misc: "متنوع" },
};
export const CATEGORY_SET = new Set(CATEGORIES);
export const subOk = (cat, sub) => !!(sub && SUBCATEGORIES[cat] && SUBCATEGORIES[cat][sub]);
export const CONDITIONS = new Set(["new", "used"]);
export const SORTS = new Set(["near", "new", "cheap", "expensive", "popular", "rated"]);
// مراحل الطلب بالترتيب: مدفوع (مؤكَّد) → قيد التحضير → في الطريق → تم التسليم (بانتظار تأكيد المشتري) → مكتمل
export const ORDER_STAGES = ["paid", "preparing", "on_the_way", "delivered", "completed"];
export const OPEN_STATUSES = new Set(["paid", "preparing", "on_the_way", "delivered", "disputed"]);
