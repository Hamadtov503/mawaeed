# تفعيل تسجيل الدخول

تدعم صفحة البداية Google وApple عبر Supabase Auth بتدفق PKCE ومتصفح النظام.
الأزرار غير مفعلة إلى أن تُضبط الخدمة؛ المتابعة على الجهاز تعمل دون حساب.

1. أنشئ مشروع Supabase خاصًا بك.
2. من Authentication / Providers فعّل Google وApple وأدخل بيانات المزود في لوحة Supabase فقط.
3. عند إعداد كل مزود استخدم رابط العودة الذي تعرضه لوحة Supabase: `https://PROJECT.supabase.co/auth/v1/callback`.
4. أضف `com.hamad.mawaeed://auth/callback` إلى Redirect URLs في إعدادات Supabase Auth.
5. اضبط قيمتي البناء في `project.yml`:
   - `MAWAEED_AUTH_URL`: عنوان المشروع `https://PROJECT.supabase.co`.
   - `MAWAEED_AUTH_PUBLIC_KEY`: المفتاح العام anon أو publishable فقط.
6. ابنِ التطبيق واختبر المزودين على جهاز فعلي: نجاح الدخول، إلغاء المتصفح، انقطاع الإنترنت، إعادة فتح التطبيق، والخروج.

لا تضع مفتاح service_role أو مفاتيح Apple أو سر Google داخل التطبيق أو المستودع.
تحتاج Apple إعداد Service ID وبيانات المزود في حساب المطور؛ لا يكفي تفعيل iCloud Drive.
اختبر دعم العودة للتطبيق على طريقة التثبيت المستخدمة، خصوصًا نسخ TrollStore.

## حدود النسخة

الدخول يثبت هوية الحساب ويحفظ الجلسة في Keychain؛ لا ينقل بيانات المواعيد إلى Supabase.
المواعيد والممتلكات محفوظة محليًا، ومتاحة لأي مستخدم يتابع على نفس الجهاز.
المزامنة الحالية عبر مجلد iCloud Drive الذي تختاره، ولا تتغير بتسجيل الدخول أو الخروج.
الخروج محلي من التطبيق؛ لا يسجل خروجك من Google أو Apple في المتصفح.
قبل تقديم حسابات منفصلة ببيانات خاصة، يلزم بناء تخزين سحابي بعزل المستخدمين وسياسات RLS وترحيل البيانات المحلية.

المراجع:
- https://supabase.com/docs/guides/auth/native-mobile-deep-linking
- https://supabase.com/docs/guides/auth/sessions/pkce-flow

