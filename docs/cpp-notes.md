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

## `VARIANT_ENUM_CAST` ve `BIND_ENUM_CONSTANT` (Faz 1)
C++ enum'unu GDScript'e açmak için: başlıkta `VARIANT_ENUM_CAST(JSBSimFDM::TrimMode);`, `_bind_methods`'ta
`BIND_ENUM_CONSTANT(TRIM_FULL);`. GDScript'te `JSBSimFDM.TRIM_FULL` olarak görünür.
