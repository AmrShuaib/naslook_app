#!/usr/bin/env bash
# فحص مرئي لشاشات العروض على الخادم الوهمي: صفحة الدائرة → العروض → الانضمام؛ المحفظة → عروضي؛ لوحة المالك → العروض
S="${NASLIFE_SCRATCH:-$(git rev-parse --show-toplevel)/.scratch}"; mkdir -p "$S"
mkdir -p $S/shots/offers
cd $S
node probe2.mjs "http://127.0.0.1:8091/#/c/biz-brew92" $S/shots/offers/circle "$1" 2>&1 | tail -12
