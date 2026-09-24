// يُحمَّل قبل الحزمة (node --import ./db_env.mjs) عند ضبط NASLIFE_TEST_DB: يوجّه كل pg.Pool إلى قاعدة اختبار مستقلة
// حتى لا تتصادم جلسات تعمل بالتوازي على naslife_test (كل حزمة تحذف جداولها وتعيد إنشاءها).
import pg from 'pg';

const db = process.env.NASLIFE_TEST_DB;
if (db) {
  const Orig = pg.Pool;
  pg.Pool = class extends Orig { constructor(o = {}) { super({ ...o, database: db }); } };
}
