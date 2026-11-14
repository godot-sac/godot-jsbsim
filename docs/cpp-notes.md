# C++ notları

godot-jsbsim'de ilk kez kullanılan C++ ve GDExtension kavramları, kısa açıklamalarla. Temel kavramlar (derleme
zinciri, başlık/kaynak, namespace, `static`, referans) godot-dis'in `docs/cpp-notes.md` dosyasında; burada yalnızca
yeniler var. Örnekler bu repodaki dosyalardan.

## İki kütüphane: statik ve dinamik bağlama (Faz 0)

**Statik bağlama:** kütüphanenin kodu bizim DLL'imizin *içine* kopyalanır (godot-cpp böyle: `.lib` → bizim DLL).
**Dinamik bağlama:** kütüphane ayrı bir dosya olarak kalır (`JSBSim.dll`); bizim DLL'imiz yalnızca "şu fonksiyonu
`JSBSim.dll`'den al" diye bir kayıt taşır. Program açılırken işletim sistemi ikisini birden yükler ve bağlar.

**Neden önemli?** JSBSim LGPL-2.1 lisanslı. LGPL, kullanıcının kütüphaneyi kendi derlediği bir sürümle
*değiştirebilmesini* ister. Dinamik bağlamada bu kolay: `JSBSim.dll` dosyasını değiştirmek yeterli. Bu yüzden
JSBSim'i statik bağlamıyoruz; bizim kodumuz MIT kalıyor.

**İçe aktarma kütüphanesi (import library, `JSBSim.lib`):** Windows'ta bağlayıcı, DLL'deki fonksiyonların
listesini bu küçük `.lib` dosyasından öğrenir. (Statik `.lib` ile aynı uzantı, ama içinde kod yok, yalnızca liste.)
Linux'ta bağlayıcı doğrudan `.so` dosyasını okur.

**`__declspec(dllexport)` / `dllimport`:** Windows'ta bir DLL varsayılan olarak hiçbir şeyi dışarı açmaz. JSBSim'in
`JSBSim_API.h` başlığındaki `JSBSIM_API` makrosu, JSBSim derlenirken `dllexport` ("bunu dışarı aç"), bizim
tarafımızda `dllimport` ("bunu DLL'den al") olur. `class JSBSIM_API FGFDMExec` → tüm sınıf dışarı açık.
Linux'ta semboller varsayılan olarak açık, makro boş.

**DLL nasıl bulunur?** Windows bağımlı DLL'i normalde programın (Godot'un) klasöründe ya da `PATH`'te arar. Godot
GDExtension'ı yüklerken eklentinin kendi klasörünü de arama yoluna ekliyor; bu yüzden `JSBSim.dll` bizim DLL'in
yanında olunca bulunuyor. Linux'ta bunu `RUNPATH=$ORIGIN` sağlıyor ("yanımdaki klasöre de bak"), `SConstruct`'ta
`-Wl,-rpath,'$ORIGIN'`. `SONAME` (`libJSBSim.so.1`): Linux'ta kütüphanenin "ana sürüm adı"; bizim `.so` bu adı ister.

## C çalışma zamanı (CRT): `/MD` ve `/MT`
MSVC'de her DLL C/C++ çalışma zamanını (bellek ayırma, `std::string`, ...) ya kendi içine gömer (`/MT`, statik) ya da
ortak `vcruntime140.dll`/`msvcp140.dll`'den kullanır (`/MD`, paylaşımlı). İki DLL farklı CRT kullanırsa, birinin
ayırdığı belleği diğeri serbest bırakınca program çöker. JSBSim'in API'si `std::string` döndürüyor
(`GetVersion()`), yani bellek DLL'ler arasında el değiştiriyor. Bu yüzden ikisi de `/MD` ile derleniyor
(`SConstruct`'ta `use_static_cpp=no`).

## Exception'lar
**Exception:** bir hata olduğunda fonksiyonun normal dönüşü yerine "fırlatılan" (`throw`) bir nesne; yakalanana
(`catch`) kadar çağrı zincirinde yukarı çıkar. Yakalanmazsa program kapanır.
```cpp
try {
	fdm.LoadModel(...);              // JSBSim burada throw edebilir
} catch (const std::exception &e) {  // her standart exception'ı yakalar; e.what() = mesaj
	result["error"] = ...;
} catch (...) {                      // geri kalan her şey
}
```
Godot exception kullanmaz; godot-cpp de onları varsayılan olarak kapatır. JSBSim ise hata için exception fırlatır.
Bu yüzden bizim eklenti exception desteğiyle derleniyor (`disable_exceptions=no`) ve JSBSim'i çağıran her fonksiyon
`try/catch` ile sarılı: hiçbir exception Godot'a kaçmamalı. `src/fdm/jsbsim_fdm.cpp`'deki `guarded()` bunu tek
yerde yapar. JSBSim'in eski kodu bazen `std::exception` değil düz `std::string` fırlatır; bu yüzden üç `catch` var:
`std::exception`, `std::string` ve her şeyi yakalayan `catch (...)`.

## Akıllı işaretçi: `std::shared_ptr`
`fdm.GetIC()` bir `std::shared_ptr<FGInitialCondition>` döndürür: nesneyi işaret eden, kaç kişinin onu tuttuğunu
sayan bir işaretçi; son tutan bırakınca nesne silinir. Godot'taki `Ref<>` / `RefCounted` ile aynı fikir. `->` ile
üyeye erişilir: `ic->SetPsiDegIC(0.0)`. `auto` derleyiciye tipi kendisi çıkarmasını söyler.

## Yığında nesne (stack) ve RAII
`JSBSim::FGFDMExec fdm;` → nesne fonksiyonun yerel değişkeni; fonksiyon bitince (normal dönüş ya da exception)
otomatik olarak yok edilir ve tüm JSBSim belleği serbest kalır. Bu C++'ın RAII ilkesi: kaynak, onu tutan nesnenin
ömrüne bağlıdır; `delete` yazmaya gerek yok.

## `bind_static_method`
`ClassDB::bind_static_method("JSBSimFDM", D_METHOD("get_jsbsim_version"), &JSBSimFDM::get_jsbsim_version)` →
GDScript'ten nesne oluşturmadan çağrılır: `JSBSimFDM.get_jsbsim_version()`. (Normal metotlar `bind_method` ile
bağlanır; `DEFVAL(...)` varsayılan argüman verir.)

## Sahiplik: `std::unique_ptr` ve `std::move` (Faz 1)
`JSBSimFDM` içindeki `std::unique_ptr<FGFDMExec> fdm` nesnenin **tek sahibidir**: `JSBSimFDM` silinince ya da yeni
model yüklenince (`fdm.reset()`) FGFDMExec otomatik silinir (RAII). `shared_ptr`'dan farkı: kopyalanamaz, sayaç yok.
Sahipliği devretmek için `fdm = std::move(exec);` yazılır; `exec` boş kalır. Başlık dosyasında yalnızca
`class FGFDMExec;` diye **ileri bildirim** var (JSBSim başlıklarını her yere taşımamak için); bu yüzden yıkıcı
(`~JSBSimFDM() = default;`) `.cpp`'de tanımlı: `unique_ptr` nesneyi silerken tipin tam tanımını görmeli.

## Lambda ve şablon (template) (Faz 1)
`guarded([&]() { ok = fdm->RunIC(); }, error)` → `[&]() { ... }` yerinde yazılmış isimsiz bir fonksiyon (lambda);
`[&]` dışarıdaki değişkenlere (`ok`, `fdm`) başvuruyla erişir. `guarded` bir şablon: `template <typename F>` her
lambda tipi için derleyicinin ayrı bir kopya üretmesini sağlar. GDScript'teki `func(): ...` + `call()` gibi.

## `thread_local` ve `std::atomic` (Faz 1)
JSBSim'in günlükçüsü (logger) iş parçacığı başına bir tane: `SetLogger` yalnızca çağıran iş parçacığını etkiler.
`thread_local bool installed` her iş parçacığında ayrı bir değişkendir, böylece kurulumu her iş parçacığında bir kez
yaparız. Günlük seviyesini tüm iş parçacıkları okur; `std::atomic<int>` aynı anda okuma/yazmayı güvenli kılar.

## Sanal fonksiyon ve `override` (Faz 1)
`FGLogger` JSBSim'in soyut sınıfı (`virtual void Message(...) = 0;`). `GodotLogger` ondan türer ve fonksiyonları
`override` ile yeniden tanımlar; JSBSim `FGLogger` işaretçisi üzerinden çağırır ama bizim kodumuz çalışır. GDScript'te
bir sınıfı `extends` edip metodunu yeniden yazmaya benzer. `override`, imza tutmazsa derleyicinin hata vermesini
sağlar.

## Düğüm yazmak: `_ready`, `_physics_process`, özellikler ve sinyaller (Faz 2)
`JSBSimAircraft`, `Node3D`'den türer ve Godot'un sanal fonksiyonlarını `override` eder: `void _ready() override;`,
`void _physics_process(double delta) override;`. godot-cpp bunları GDScript'teki `_ready()` gibi çağırır.
Editörde çalışmasın diye `Engine::get_singleton()->is_editor_hint()` kontrol edilir (GDScript'te `@tool` olmayan betik
zaten editörde çalışmaz; C++ sınıfı ise her zaman çalışır).
Denetçide görünen özellik = getter + setter + `ADD_PROPERTY(PropertyInfo(...), "set_x", "get_x")`. Hepsini tek tek
yazmamak için `jsbsim_aircraft.cpp`'de küçük bir makro (`BIND_PROPERTY`) var; `#` makro argümanını metne, `##` iki
parçayı tek isme çevirir (`set_##m_name` → `set_aileron`). Sinyal: `ADD_SIGNAL(MethodInfo("failed", ...))` ve
`emit_signal("failed", reason)`.

## JSBSim'in vektör ve matrisleri 1'den başlar (Faz 2)
`FGColumnVector3` ve `FGMatrix33` Fortran/matematik geleneğiyle 1 tabanlı: `v(1)`, `m(1, 1)`. Bizim `Vec3`/`Mat3`
ise 0 tabanlı. Dönüşüm `to_vec3`/`to_mat3` içinde tek yerde yapılır; karıştırmak sessiz bir eksen kaymasıdır.
`tests/cpp/test_jsbsim_frame.cpp` bunu JSBSim'in kendi Euler açılarıyla karşılaştırarak yakalar.

## Kütüphanenin bizi çağırması: geri çağırma (callback) sınıfı (Faz 3)
JSBSim zemini kendisi bilmez; her iniş takımı noktası için `FGGroundCallback::GetAGLevel(...)` sanal fonksiyonunu
çağırır. `JSBSimGroundCallback` bundan türer, `override` eder ve sahnedeki zemini (`height_at`) döndürür. Nesneyi
`new` ile yaratıp `SetGroundCallback(...)`'a veririz; sahipliği JSBSim alır ve modelle birlikte siler (`delete`'i biz
yazmayız). Bu, DLL sınırında bellek ayırıp başka tarafta silmek demek: iki kütüphane aynı CRT'yi (`/MD`) kullandığı
için güvenli (Faz 0 notu).
Geri çağırma `JSBSimAircraft`'ın özel (private) üyelerine erişmeli; bunun için başlıkta `friend class
JSBSimGroundCallback;` var: "bu sınıf benim özel üyelerimi görebilir".

## `ObjectID`: düğüme güvenli işaret (Faz 3)
Zemin düğümünü ham işaretçi (`Node *`) olarak saklamak tehlikeli: düğüm silinirse işaretçi boşluğa bakar ve çökme
olur. Bunun yerine `ObjectID` saklanır; her kullanımda `ObjectDB::get_instance(id)` nesne hâlâ varsa onu, yoksa
`nullptr` döndürür. GDScript'teki `is_instance_valid()` / `weakref` ile aynı fikir.

## Başka bir eklentinin sınıfını derleme bağımlılığı olmadan kullanmak (Faz 4)
`DisEntity` godot-dis'te tanımlı; onun başlığını `#include` edersek godot-jsbsim godot-dis olmadan derlenmez. Bunun
yerine Godot'un çalışma zamanı tip bilgisini kullanırız: `child->is_class("DisEntity")` sınıfı adıyla sorar (miras
zinciri dahil), `child->set("linear_velocity", v)` / `child->get("appearance")` özelliklere adlarıyla erişir. Bu
GDScript'teki ördek tiplemenin C++ karşılığı: biraz daha yavaş (ad araması) ama kare başına birkaç çağrı için önemsiz,
ve godot-dis yoksa hiçbir şey olmaz.

## `VARIANT_ENUM_CAST` ve `BIND_ENUM_CONSTANT` (Faz 1)
C++ enum'unu GDScript'e açmak için: başlıkta `VARIANT_ENUM_CAST(JSBSimFDM::TrimMode);`, `_bind_methods`'ta
`BIND_ENUM_CONSTANT(TRIM_FULL);`. GDScript'te `JSBSimFDM.TRIM_FULL` olarak görünür.

## Godot hatasına geçici çözüm: `CallableCustom` ve yıkıcıyı kanca olarak kullanmak
`src/editor_first_load_guard.cpp`. Godot 4.7'de yeni bir projenin ilk `--headless --import`'u eklentimizi tarama
sırasında keşfedince çıkışta çöküyordu (godotengine/godot#111048): editör sınıf belgelerini ertelenmiş bir çağrıyla
üretiyor, editör hemen kapanırsa bu çağrı belge verisi silindikten sonra çalışıp boş işaretçiye (`nullptr`) erişiyor.
Hatayı minimal bir C eklentisiyle (godot-cpp'siz) yeniden üretip motorda olduğunu ayırdık; `is_exposed` kapalı bir
sınıfla çökmediğini görmek nedeni kesinleştirdi.

- **`CallableCustom`**: Godot'nun `Callable`'ını kendi C++ sınıfımızla doldurmak. Godot callable'ı bir sinyal
  bağlantısında tutar; bağlantı (ya da sinyalin sahibi olan nesne) yok olunca callable'ı siler ve bizim yıkıcımız
  çalışır. Burada çağrının kendisi önemsiz: kök pencerenin `renamed` sinyaline bağlıyoruz ki kök pencere silinince,
  yani editör düğümü ve belge verisi gittikten sonra, yıkıcı çalışsın ve sınıflarımızı erkenden kaldırsın.
- **Yıkıcı = "silinme olayı"**: RAII'nin tersten kullanımı; bir nesnenin ömrünü başka bir nesneye bağlayıp onun
  silinişinden haberdar olmak.
- **Anonim ad alanı (`namespace { ... }`)**: içindekiler yalnızca o `.cpp` dosyasında görünür (C'deki `static` gibi);
  başka dosyalarla isim çakışması olmaz.
- **`is_valid()` dersi**: hedef nesnesi olmayan callable varsayılan olarak "geçersiz" sayılıyor, `connect()` onu
  reddedip hemen siliyor. İlk denemede bu yüzden sahte bir başarı gördük; günlükte kancanın ne zaman çalıştığına bakmak
  ortaya çıkardı. Ders: düzeltmenin *neden* çalıştığını doğrula.

## İki düğümün birbirini bulması: ham işaretçi ve ağaç olayları (Faz 8)
`JSBSimAutopilot`, `JSBSimAircraft`'ın çocuğu. Uçak her JSBSim adımından önce otopilotu çağırmalı; her adımda
çocukları taramak yerine otopilot ağaca girince kendini uçağa kaydediyor (`_enter_tree` → `set_autopilot_node(this)`),
çıkınca siliyor (`_exit_tree` → `nullptr`).

- **Ham (sahiplenmeyen) işaretçi** `JSBSimAutopilot *`: nesnenin sahibi Godot'nun ağacı; işaretçi yalnızca "şu an
  orada" bilgisini taşıyor. Güvenli olması, kaydı silen `_exit_tree`'nin düğüm ağaçtan ayrılmadan önce mutlaka
  çalışmasına dayanıyor. Ömrü bizim kontrolümüzde olmayan bir düğüme uzun süre işaret edeceksek `ObjectID` (Faz 3)
  daha güvenli.
- **İleri bildirim** (`class JSBSimAutopilot;`): başlık dosyası yalnızca işaretçi tuttuğu için sınıfın tamamını
  bilmesine gerek yok; `#include` döngüsü (iki başlığın birbirini içermesi) böyle önlenir. Tam tanım `.cpp`'de
  içerilir.

## Makro ile tekrar eden kod (Faz 8)
Otopilotun 40'a yakın ayarı var; her biri için alan + `set_` + `get_` yazmak yerine `AP_PROPERTY(tür, ad, varsayılan)`
makrosu üçünü birden üretiyor. `##` ön işlemcide ad birleştirme (`set_##m_name` → `set_roll_kp`), `#` ise adı dizeye
çeviriyor (`#m_name` → `"roll_kp"`, `BIND_AP_PROPERTY`'de). Makro dosyanın sonunda `#undef` ile kaldırılıyor ki başka
dosyalara sızmasın. Dezavantaj: hata ayıklayıcıda ve hata mesajlarında makronun açılmış hâli görünür; yalnızca gerçekten
mekanik tekrar için kullan.

## Süre ölçmek: `std::chrono::steady_clock` (Faz 9)
`advance()` kendi süresini ölçüyor: `steady_clock::now()` farkı `duration<double, std::micro>` ile mikrosaniyeye
çevriliyor. `steady_clock` hiç geri gitmeyen saattir (sistem saati değişse de); süre ölçmek için doğru seçim
(`system_clock` takvim saatidir).

## Editörde sınıf belgesi (F1): `doc_classes/` (v0.2, 2026-11-08)
`doc_classes/*.xml` (Godot'nun kendi sınıf belgeleriyle aynı biçim) `SConstruct`'taki küçük bir fonksiyonla zlib'le
sıkıştırılıp `build/gen/class_reference.gen.cpp` içine bayt dizisi olarak yazılıyor; yalnızca debug kütüphanesinde
(`CLASS_REFERENCE` tanımı). `src/class_reference.cpp` diziyi açıp editöre veriyor. İsim alanı düzeyindeki `const`
değişkenler yalnızca kendi `.cpp` dosyasında görünür; başlıktaki `extern` bildirimleri onları dışarıya açıyor.
godot-cpp'nin hazır `GodotCPPDocData`'sı kullanılmadı: belgeleri her zaman yüklüyor ve o zaman yeni projenin ilk
başsız `--import`'u yine çöküyordu (godotengine/godot#111048); elle yükleyince `install_editor_first_load_guard()`
koruma devredeyken belgeler atlanıyor. Ayrıntılı (İngilizce) not godot-dis `docs/cpp-notes.md`'de. API değişince:
`<godot> --headless --path . --doctool . --gdextension-docs` (kardeş bağlantılı godot-dis'in `Dis*.xml`'lerini sil),
sonra `python tools/check_docs.py`.


## Per-engine throttles (2026-11-14)
- **NaN as "not set"** (`engine_throttles` in `jsbsim_aircraft.h`): a `std::vector<double>` holds one value per
  engine, and `NaN` means "follow `throttle`". `std::isnan(x)` is the only reliable test: `NaN == NaN` is false.
  A separate `std::vector<bool>` would work too; one array keeps the two facts from drifting apart.
- **`resize(n, value)`** grows a vector to `n` elements and fills the new ones with `value`
  (`engine_throttles.resize(engine + 1, std::nan(""))`); existing elements are kept.
- **A `static` free function in a `.cpp`** (`read_property`) is visible only in that file: a small helper that does
  not belong to the class's interface and cannot clash with a function of the same name elsewhere.
