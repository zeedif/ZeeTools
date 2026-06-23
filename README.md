# ZeeTools

Esta es una aplicación multiplataforma desarrollada en Flutter que implementa una arquitectura limpia y modular orientada a características (*Feature-First*). Sigue las mejores prácticas en la separación de responsabilidades para una mayor escalabilidad y mantenibilidad. Utiliza `freezed` para la generación de modelos inmutables y `json_serializable` para la serialización de datos.

ZeeTools es un conjunto de herramientas enfocadas en la gestión y creación de archivos EPUB, incluyendo:
- Búsqueda y reemplazo con soporte avanzado para Regex y grupos de captura.
- Catálogo de Expresiones Regulares predefinidas para validaciones, búsquedas y correcciones tipográficas.
- Generación de plantillas EPUB 3.4 con edición de roles Aria y metadatos.
- Extracción y edición de metadatos mediante arrastrar y soltar (Drag & Drop).
- Conversión automatizada de formatos DOCX/Markdown a EPUB integrando Pandoc y filtros Lua.
- Optimización y compresión de imágenes sin pérdida (JPG, PNG a JXL y AVIF) apoyado por binarios como `optipng` y `jpegoptim`.
- *Flavor* dedicado para funcionar como cliente de sincronización con ZeePubs Server.

### Requisitos Previos

Asegúrate de tener instalado lo siguiente en tu sistema:

- Flutter SDK (versión 3.44 o superior), puedes seguir la guía de instalación en [Flutter Installation](https://flutter.dev/docs/get-started/install).
- Dart SDK (versión 3.12 o superior), que se incluye con Flutter.
- Un editor de código compatible como Visual Studio Code o Android Studio.
- *Dependencias del sistema:* Pandoc, 7zip, OptiPNG, JpegOptim.

### Preparación del Proyecto

1. **Clona el repositorio**:
   ```bash
   git clone https://github.com/zeedif/zeetools
   ```

2. **Navega a la carpeta del proyecto**:
   ```bash
   cd zeetools
   ```

3. **Instala las dependencias**:
   ```bash
   flutter pub get
   ```

4. **Genera los archivos de código necesarios** (modelos, serialización, etc.):
   ```bash
   dart run build_runner build --enable-experiment=primary-constructors
   ```

### Configuración de Firmado para Android (Release)

Para compilar y publicar la aplicación en Google Play, es obligatorio firmarla digitalmente. Sigue estos pasos para generar tu clave de firma.

**Paso 1: Generar la Clave de Firma (Keystore)**

Este comando creará un archivo `upload-keystore.jks`, que es tu clave privada. Guárdalo en un lugar seguro y *nunca lo subas a un repositorio de código*.

Abre una terminal en la raíz de tu proyecto y ejecuta el siguiente comando:

```bash
"C:\Program Files\Android Studio\jbr\bin\keytool" -genkey -v -keystore android/app/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

La terminal te pedirá varios datos:
-   **Contraseña del almacén de claves**: Ingresa una contraseña segura y anótala. No verás los caracteres al escribir.
-   **Datos personales**: Rellena tu nombre, organización, ciudad, etc.
-   **Confirmación**: Escribe `si` o `yes` para confirmar.
-   **Contraseña para el alias `<upload>`**: *Vuelve a introducir la misma contraseña del primer paso* para simplificar la configuración.

Al finalizar, se creará el archivo en `zeetools/android/app/upload-keystore.jks`.

**Paso 2: Configurar las Credenciales**

Crea un archivo llamado `key.properties` dentro de la carpeta `android/` con el siguiente contenido:

```properties
# ¡ADVERTENCIA! No subas este archivo a repositorios públicos.

storePassword=la_contraseña_que_creaste
keyPassword=la_misma_contraseña_de_arriba
keyAlias=upload
storeFile=app/upload-keystore.jks
```
-   Reemplaza `la_contraseña_que_creaste` con la contraseña que definiste en el paso anterior.
-   `keyAlias` debe ser `upload` para coincidir con el comando.
-   La ruta `storeFile` es relativa a la carpeta `android/`.

**Paso 3: Configurar Gradle**

El archivo `android/app/build.gradle.kts` ya incluye la configuración `signingConfigs.create("release")` que lee las propiedades del archivo `key.properties`. Solo necesitas cambiar `signingConfigs.getByName("debug")` por `signingConfigs.getByName("release")` en la sección buildTypes:

```kotlin
buildTypes {
    release {
        // Cambia "debug" por "release" para usar tu keystore de producción
        signingConfig = signingConfigs.getByName("release")
    }
}
```

### Ejecución y Compilación

Esta sección describe cómo ejecutar el proyecto en modo de desarrollo y generar versiones de producción.

**Variables de Entorno y Flavors**

Este proyecto requiere un archivo de variables de entorno para gestionar configuraciones sensibles como URLs de APIs y claves. Estas variables se inyectan en tiempo de compilación mediante el flag `--dart-define-from-file`.

Por seguridad, **este archivo no se encuentra en el repositorio y se excluye en el .gitignore**. Sin embargo, se incluyen archivos de ejemplo en la carpeta `lib/` para facilitar las pruebas, incluyendo activadores para el Flavor de conexión con ZeePubs Server:

-   **`lib/.env.dev`**: Contiene la configuración para el entorno de desarrollo local.
    ```json
    {
      "IS_ZEEPUBS_CLIENT": "true",
      "BASE_URL_API": "http://127.0.0.1:8080",
      "CLIENT_ID": "099153c2625149bc8ecb3e85e03f0022",
      "ENCRYPTION_KEY": "my32lengthsupersecretnooneknows1"
    }
    ```

**Importante:** Para compilar una versión de producción (`release`), **debes crear tu propio archivo `lib/.env`** con los datos correctos.

**Ejecución en Modo Desarrollo**

Para ejecutar la aplicación con las configuraciones de desarrollo, utiliza el archivo `.env.dev`:
```bash
flutter run --dart-define-from-file=lib/.env.dev
```

**Compilación para Producción**

Dependiendo de las necesidades (Escritorio, Web o Móvil), se puede compilar la aplicación asegurando inyectar las variables de entorno especificadas en el archivo `.env`:

- **Escritorio (Windows / Linux / macOS)**:
```bash
flutter build windows --dart-define-from-file=lib/.env
flutter build linux --dart-define-from-file=lib/.env
flutter build macos --dart-define-from-file=lib/.env
```

- **Móvil (APK / App Bundle)**:
```bash
flutter build apk --dart-define-from-file=lib/.env
flutter build appbundle --dart-define-from-file=lib/.env
```

**Ofuscación del Código**

Para mayor seguridad en producción, es recomendable ofuscar el código de la aplicación. La ofuscación renombra las funciones y clases en el código compilado, lo que dificulta el proceso de ingeniería inversa. **Nota:** Este proceso no encripta los recursos ni protege completamente contra la ingeniería inversa, pero sí aumenta la seguridad al hacer el código más difícil de interpretar.

```bash
flutter build windows --obfuscate --split-debug-info=build/debug-info
```

El parámetro `--obfuscate` aplica la ofuscación y `--split-debug-info` especifica la carpeta en la que se generarán los archivos de símbolos para interpretación futura de errores. **Importante:** Asegúrate de guardar los archivos de símbolos generados en `build/debug-info`, ya que son necesarios para descifrar los rastros de errores y excepciones en los registros de una aplicación en producción ofuscada.

Si necesitas revisar un rastro de errores obfuscado, usa el archivo de símbolos generado al momento de la compilación para obtener un rastro legible, de la siguiente forma:

```bash
flutter symbolize -i <archivo_de_trazo> -d build/debug-info/app.windows-x64.symbols
```

### Estructura del Proyecto

La arquitectura del proyecto se orienta a **características (*Feature-First*)**, donde cada funcionalidad principal es un módulo independiente que contiene sus propias capas (`core`, `data`, `presentation`). La carpeta `common` aloja todo lo transversal. Las capas se organizan de la siguiente manera:

- **common**: Contiene utilidades y componentes compartidos entre las capas de todas las características (inyección de dependencias, envoltorios para manipulación de archivos y procesos de terminal nativos).

- **core**: Define las entidades (Modelos de datos generados con `freezed`) y las clases abstractas de los repositorios (contratos). Dart no tiene interfaces como en otros lenguajes, pero se utilizan clases abstractas para separar la lógica de negocio de los detalles de implementación.

- **data**: Contiene las implementaciones de los repositorios definidos en `core`. Aquí se integran los *datasources*, la ejecución de scripts (Lua/Pandoc), la lectura de sistemas de archivos, catálogos locales y peticiones HTTP.

- **presentation**: Contiene la lógica de la interfaz de usuario. Al tratarse de una aplicación Frontend, **no se utiliza una subcapa de Casos de Uso (Use Cases / CQRS)**. En su lugar, los **BLoCs** operan directamente sobre los repositorios consumiendo su información y aplicando la lógica necesaria, centralizando el estado de forma eficiente y directa hacia la UI.

```text
lib/
├── common/                             # Infraestructura transversal y compartida
│   ├── config/                         # Configuraciones (flavors, entornos)
│   ├── constants/                      # Constantes globales de la app
│   ├── file/                           # Wrappers para file_picker o manipulación de I/O
│   ├── process/                        # Wrappers para ejecutar binarios (Pandoc, 7zip, OptiPNG, JpegOptim)
│   ├── theme/                          # Temas, tipografías y colores
│   └── utils/                          # Utilidades (conversores, debounce, helpers)
│
├── features/                           # Módulos funcionales del sistema
│   │
│   ├── home/                           # Dashboard, Layout Base y Splash
│   │   ├── core/                       # Entidades de navegación (MenuItems)
│   │   ├── data/                       # Proveedores de estado inicial
│   │   └── presentation/               # UI (Splash, MainLayout, Sidebar, BottomBar)
│   │
│   ├── settings/                       # Preferencias de la aplicación
│   │   ├── core/                       # Entidades (AppPreferences)
│   │   ├── data/                       # Implementación (SharedPreferences / Local DB)
│   │   └── presentation/               # BLoCs (Theme, Lang), UI de Ajustes
│   │
│   ├── search_replace/                 # Herramienta: Búsqueda y Reemplazo (Regex)
│   │   ├── core/                       # Entidades (Log, MatchResult), Repositorios Abstractos
│   │   ├── data/                       # Implementación (Lógica de Regex, I/O de archivos)
│   │   └── presentation/               # BLoCs, UI (Coloreado Regex, Visor de Logs), Widgets
│   │
│   ├── regex_library/                  # Catálogo de Expresiones Regulares útiles
│   │   ├── core/                       # Entidades (RegexItem, RegexCategory)
│   │   ├── data/                       # Repositorio (Carga de JSON local con el catálogo de expresiones)
│   │   └── presentation/               # BLoCs, UI (Lista, visor, botones para insertar en Search&Replace)
│   │
│   ├── epub_templater/                 # Herramienta: Generador EPUB 3.4
│   │   ├── core/                       # Entidades (Template, Section, AriaRoles), Contratos
│   │   ├── data/                       # Lógica de estructuración y generación de archivos XML/HTML
│   │   └── presentation/               # BLoCs, Formularios de metadatos, UI de secciones
│   │
│   ├── epub_metadata/                  # Herramienta: Editor de Metadatos EPUB
│   │   ├── core/                       # Entidades (EpubMetadata), Interfaces
│   │   ├── data/                       # Implementación (Descompresión, parser XML, reempaquetado)
│   │   └── presentation/               # BLoCs, UI (Drag & Drop), Formularios
│   │
│   ├── format_converter/               # Herramienta: DOCX/MD a EPUB (con Lua/Pandoc)
│   │   ├── core/                       # Entidades (ConversionJob, Configs), Contratos
│   │   ├── data/                       # Ejecución de scripts locales (pandoc, filtros lua, 7z, CSS)
│   │   └── presentation/               # BLoCs (Manejo de estado de conversión), UI de progreso
│   │
│   ├── image_optimizer/                # Herramienta: Compresión de Imágenes (JXL, AVIF, JPG)
│   │   ├── core/                       # Entidades (ImageTask, Formats), Interfaces
│   │   ├── data/                       # Implementación (Llamadas a CLI/librerías: optipng, jpegoptim)
│   │   └── presentation/               # BLoCs, UI de lote de imágenes, selectores de formato
│   │
│   └── zeepubs_client/                 # Flavor: Cliente para ZeePubs Server (Opcional)
│       ├── core/                       # Modelos de usuario, tokens, repositorios abstractos
│       ├── data/                       # API Services (http), almacenamiento local seguro
│       └── presentation/               # BLoCs de Autenticación, Vistas de Login/Sincronización
│
├── inject_dependencies.dart            # Registro de GetIt (Service Locator)
└── main.dart                           # Punto de entrada de la aplicación
```

### Paquetes y Herramientas Utilizadas

- `freezed`: Utilizado para generar modelos inmutables. Trabaja en conjunto con json_serializable para facilitar la serialización y deserialización de datos.
- `json_serializable`: Permite la generación automática de código para convertir JSON en modelos de Dart.
- `flutter_bloc`: Facilita la gestión de estado de la aplicación mediante el patrón Bloc, centralizando la lógica de negocio y promoviendo una arquitectura más escalable.
- `go_router`: Simplifica la navegación en la aplicación, permitiendo gestionar rutas dinámicas de forma clara y estructurada.
- `archive`: Para la manipulación local de compresión/descompresión de archivos EPUB.
- `extended_text`: Para habilitar el coloreado sintáctico de Regex en los campos de texto de la interfaz.

### Añadiendo Pantallas

Para añadir nuevas pantallas a tu aplicación, puedes utilizar la biblioteca **Go Router**, que simplifica la gestión de rutas en Flutter. 

Ejemplo de configuración de rutas:

```dart
import 'package:go_router/go_router.dart';

// Definición de rutas
final GoRouter router = GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => MainDashboardScreen(),
    ),
    GoRoute(
      path: '/search-replace',
      builder: (context, state) => SearchReplaceScreen(),
    ),
  ],
);
```

### Licencia

Este proyecto está bajo la licencia **GNU General Public License v3.0**. Consulta el archivo `LICENSE` para más detalles.
