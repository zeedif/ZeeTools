# ZeeTools

Esta es una aplicación de escritorio desarrollada en Flutter que implementa una arquitectura limpia y modular orientada a características (*Feature-First*). Sigue las mejores prácticas en la separación de responsabilidades para una mayor escalabilidad y mantenibilidad. Utiliza `freezed` para la generación de modelos inmutables y `json_serializable` para la serialización de datos.

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

**Linux**

Instala las dependencias de compilación de Flutter para escritorio:

```bash
sudo apt-get update
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

**macOS**

Instala las herramientas de línea de comandos de Xcode:

```bash
xcode-select --install
```

Acepta la licencia de Xcode antes de compilar:

```bash
sudo xcodebuild -license
```

**Windows**

Instala [Visual Studio 2022](https://visualstudio.microsoft.com/) con la carga de trabajo **"Desarrollo de escritorio con C++"**. Flutter requiere este toolchain para compilar aplicaciones de escritorio en Windows.

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

### Ejecución y Compilación

Esta sección describe cómo ejecutar el proyecto en modo de desarrollo y generar versiones de producción.

**Variables de Entorno y Flavors**

Este proyecto requiere un archivo de variables de entorno para gestionar configuraciones sensibles como URLs de APIs y claves. Estas variables se inyectan en tiempo de compilación mediante el flag `--dart-define-from-file`.

Por seguridad, **este archivo no se encuentra en el repositorio y se excluye en el .gitignore**. Sin embargo, se incluyen archivos de ejemplo en la carpeta `lib/` para facilitar las pruebas, incluyendo activadores para el Flavor de conexión con ZeePubs Server:

- **`lib/.env.dev`**: Contiene la configuración para el entorno de desarrollo local.
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

Selecciona el dispositivo de destino según tu sistema operativo:

```bash
# Windows
flutter run -d windows --dart-define-from-file=lib/.env.dev

# Linux
flutter run -d linux --dart-define-from-file=lib/.env.dev

# macOS
flutter run -d macos --dart-define-from-file=lib/.env.dev
```

**Compilación para Producción**

```bash
# Windows
flutter build windows --dart-define-from-file=lib/.env

# Linux
flutter build linux --dart-define-from-file=lib/.env

# macOS
flutter build macos --dart-define-from-file=lib/.env
```

Los artefactos de salida se generan en `build/<platform>/release/`.

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
│   ├── epub/                           # Infraestructura EPUB compartida entre features
│   │   ├── models/                     # EpubManifestItem, EpubFailure
│   │   ├── utils/                      # EpubMediaTypes, EpubPathUtils
│   │   └── repositories/              # EpubRepository (interfaz + impl)
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
│   │   ├── core/                       # Entidades (SearchOptions, MatchResult)
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
- `xml`: Para el parseo de los documentos `container.xml` y OPF del estándar EPUB 3.
- `file_picker`: Para los diálogos nativos de apertura y guardado de archivos en cada plataforma de escritorio.

### Añadiendo Pantallas

Para añadir nuevas pantallas a tu aplicación, puedes utilizar la biblioteca **Go Router**, que simplifica la gestión de rutas en Flutter. 

Ejemplo de configuración de rutas:

```dart
import 'package:go_router/go_router.dart';

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
