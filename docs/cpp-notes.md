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
`try/catch` ile sarılı: hiçbir exception Godot'a kaçmamalı. Örnek: `src/jsbsim_probe.cpp`.

## Akıllı işaretçi: `std::shared_ptr`
`fdm.GetIC()` bir `std::shared_ptr<FGInitialCondition>` döndürür: nesneyi işaret eden, kaç kişinin onu tuttuğunu
sayan bir işaretçi; son tutan bırakınca nesne silinir. Godot'taki `Ref<>` / `RefCounted` ile aynı fikir. `->` ile
üyeye erişilir: `ic->SetPsiDegIC(0.0)`. `auto` derleyiciye tipi kendisi çıkarmasını söyler.

## Yığında nesne (stack) ve RAII
`JSBSim::FGFDMExec fdm;` → nesne fonksiyonun yerel değişkeni; fonksiyon bitince (normal dönüş ya da exception)
otomatik olarak yok edilir ve tüm JSBSim belleği serbest kalır. Bu C++'ın RAII ilkesi: kaynak, onu tutan nesnenin
ömrüne bağlıdır; `delete` yazmaya gerek yok.

## `bind_static_method`
`ClassDB::bind_static_method("JSBSimProbe", D_METHOD("fly_test", ...), &JSBSimProbe::fly_test)` → GDScript'ten nesne
oluşturmadan çağrılır: `JSBSimProbe.fly_test(...)`. (Normal metotlar `bind_method` ile bağlanır.)
