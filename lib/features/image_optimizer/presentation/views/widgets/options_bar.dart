import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '/common/widgets/selection_pill.dart';
import '../../../domain/image_format.dart';
import '../../../domain/optimization_options.dart';
import '../../cubit/image_optimizer_cubit.dart';

typedef _OptionsData = ({
  List<ImageFormat> allowedFormats,
  bool allowConversion,
  QualityMode qualityMode,
  bool isProcessing,
  bool cancelRequested,
  int progressDone,
  int progressTotal,
  String? statusMessage,
});

class OptionsBar extends StatelessWidget {
  const OptionsBar({super.key});

  static String _formatTooltip(ImageFormat f) => switch (f) {
    ImageFormat.webp => 'Core desde EPUB 3.3',
    ImageFormat.avif || ImageFormat.jxl => 'Core desde EPUB 3.4; muchos lectores aún no lo muestran',
    _ => 'Compatible con cualquier lector EPUB',
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ImageOptimizerCubit>();
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return BlocSelector<ImageOptimizerCubit, ImageOptimizerState, _OptionsData?>(
      selector: (state) => state.mapOrNull(
        ready: (s) => (
          allowedFormats: s.allowedFormats,
          allowConversion: s.allowConversion,
          qualityMode: s.qualityMode,
          isProcessing: s.isProcessing,
          cancelRequested: s.cancelRequested,
          progressDone: s.progressDone,
          progressTotal: s.progressTotal,
          statusMessage: s.statusMessage,
        ),
      ),
      builder: (context, s) {
        if (s == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: 'Apagado, cada imagen solo se optimiza dentro de su propio formato',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(value: s.allowConversion, onChanged: s.isProcessing ? null : (_) => cubit.toggleConversion()),
                        const SizedBox(width: 4),
                        Text('Convertir a', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  for (final format in ImageFormat.outputs)
                    IgnorePointer(
                      ignoring: !s.allowConversion || s.isProcessing,
                      child: Opacity(
                        opacity: s.allowConversion ? 1 : 0.4,
                        child: SelectionPill(
                          dense: true,
                          selected: s.allowConversion && s.allowedFormats.contains(format),
                          tooltip: _formatTooltip(format),
                          onTap: () => cubit.toggleFormat(format),
                          child: Text(format.label),
                        ),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  s.allowConversion ? 'El formato original siempre se conserva como opción y nunca se elige algo más pesado. Las imágenes con transparencia nunca se convierten a JPEG.' : 'Sin conversión: cada imagen se optimiza dentro de su propio formato (GIF, BMP y TIFF se omiten).',
                  style: tt.labelSmall?.copyWith(color: cs.outline),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<QualityMode>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: const [
                      ButtonSegment(
                        value: QualityMode.lossless,
                        label: Text('Sin pérdida'),
                        tooltip: 'Solo resultados con píxeles idénticos al original',
                      ),
                      ButtonSegment(
                        value: QualityMode.visuallyLossless,
                        label: Text('Visualmente sin pérdida'),
                        tooltip: 'Acepta pérdida si SSIMULACRA2 ≥ 90: indistinguible del original a 1:1',
                      ),
                    ],
                    selected: {s.qualityMode},
                    onSelectionChanged: s.isProcessing ? null : (selection) => cubit.setQualityMode(selection.first),
                  ),
                  if (s.isProcessing)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: Text(s.cancelRequested ? 'Deteniendo…' : 'Detener'),
                      onPressed: s.cancelRequested ? null : cubit.cancelProcessing,
                    )
                  else
                    FilledButton.icon(
                      icon: const Icon(Icons.auto_fix_high),
                      label: const Text('Optimizar'),
                      onPressed: cubit.process,
                    ),
                  if (s.isProcessing) Text(s.statusMessage ?? '${s.progressDone}/${s.progressTotal}', style: tt.labelMedium),
                ],
              ),
              if (s.isProcessing) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(value: s.statusMessage == null && s.progressTotal > 0 ? s.progressDone / s.progressTotal : null),
              ],
            ],
          ),
        );
      },
    );
  }
}
