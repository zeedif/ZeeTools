import 'package:flutter/material.dart';

/// Envoltorio de aislamiento de errores para complementos de ZeeTools.
///
/// Si cualquier widget dentro de [child] lanza una excepción durante su fase de
/// construcción (`build`) o renderizado en tiempo de ejecución, esta barrera
/// aísla el fallo y muestra una pantalla amigable de recuperación en lugar de la
/// pantalla roja de error de Flutter. ZeeTools continúa operando con normalidad.
///
/// Pulsar **Reintentar** reinicia la barrera y vuelve a montar el subárbol del [child].
class PluginErrorBoundary extends StatefulWidget {
  /// Nombre del complemento mostrado en la interfaz de recuperación.
  final String pluginName;

  /// El subárbol del complemento a proteger.
  final Widget child;

  /// Callback opcional invocado cuando se captura un error.
  final void Function(Object error, StackTrace? stack)? onError;

  const PluginErrorBoundary({
    super.key,
    required this.pluginName,
    required this.child,
    this.onError,
  });

  @override
  State<PluginErrorBoundary> createState() => PluginErrorBoundaryState();
}

class PluginErrorBoundaryState extends State<PluginErrorBoundary> {
  static int _mountedBoundaries = 0;
  static ErrorWidgetBuilder? _originalErrorWidgetBuilder;

  Key _retryKey = UniqueKey();
  Object? _caughtError;

  /// Indica si esta barrera está mostrando actualmente un estado de error.
  bool get hasError => _caughtError != null;

  /// El error capturado actualmente, o `null` si opera normalmente.
  Object? get error => _caughtError;

  @override
  void initState() {
    super.initState();
    _hookErrorWidgetBuilder();
  }

  @override
  void dispose() {
    _unhookErrorWidgetBuilder();
    super.dispose();
  }

  static void _hookErrorWidgetBuilder() {
    if (_mountedBoundaries == 0) {
      _originalErrorWidgetBuilder = ErrorWidget.builder;
      ErrorWidget.builder = (details) {
        return _PluginErrorDisplayWidget(
          details: details,
          fallbackBuilder: _originalErrorWidgetBuilder ?? _defaultFallback,
        );
      };
    }
    _mountedBoundaries++;
  }

  static void _unhookErrorWidgetBuilder() {
    _mountedBoundaries--;
    if (_mountedBoundaries <= 0) {
      _mountedBoundaries = 0;
      if (_originalErrorWidgetBuilder != null) {
        ErrorWidget.builder = _originalErrorWidgetBuilder!;
        _originalErrorWidgetBuilder = null;
      }
    }
  }

  static Widget _defaultFallback(FlutterErrorDetails details) {
    return ErrorWidget(details.exception);
  }

  /// Expuesto para pruebas o para forzar programáticamente el estado de error.
  @visibleForTesting
  void simulateError(Object err) => reportError(err);

  /// Notifica un error a la barrera, activando la pantalla de recuperación.
  void reportError(Object err, [StackTrace? stack]) {
    widget.onError?.call(err, stack);
    if (mounted) {
      setState(() => _caughtError = err);
    }
  }

  /// Limpia cualquier error capturado y vuelve a montar el subárbol con una nueva clave.
  void retry() {
    setState(() {
      _caughtError = null;
      _retryKey = UniqueKey();
    });
  }

  /// Construye la interfaz amigable de recuperación de error.
  Widget buildRecoveryUI(BuildContext context, Object errorObj) {
    final cs = Theme.of(context).colorScheme;
    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          color: cs.errorContainer.withValues(alpha: 0.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.error.withValues(alpha: 0.4)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, size: 48, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  'Problema en el complemento "${widget.pluginName}"',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Este complemento se aisló para evitar interrumpir ZeeTools.\n'
                  'Puede que el servicio no esté disponible o haya ocurrido un fallo temporal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onErrorContainer),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                  onPressed: retry,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (Scaffold.maybeOf(context) != null) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.pluginName)),
      body: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_caughtError != null) {
      return buildRecoveryUI(context, _caughtError!);
    }

    return KeyedSubtree(
      key: _retryKey,
      child: widget.child,
    );
  }
}

class _PluginErrorDisplayWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  final ErrorWidgetBuilder fallbackBuilder;

  const _PluginErrorDisplayWidget({
    required this.details,
    required this.fallbackBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final boundary = context.findAncestorStateOfType<PluginErrorBoundaryState>();
    if (boundary != null) {
      boundary.widget.onError?.call(details.exception, details.stack);
      return boundary.buildRecoveryUI(context, details.exception);
    }
    return fallbackBuilder(details);
  }
}
