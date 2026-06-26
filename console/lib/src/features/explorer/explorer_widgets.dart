import 'package:flutter/material.dart';

class ExplorerMenuChip<T> extends StatelessWidget {
  const ExplorerMenuChip({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onSelected,
    this.enabled = true,
    super.key,
  });

  final String label;
  final String value;
  final List<T> items;
  final String Function(T item) itemLabel;
  final ValueChanged<T> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final Widget child = _ExplorerChipFrame(
      label: label,
      value: value,
      enabled: enabled,
      trailingIcon: enabled ? Icons.arrow_drop_down_rounded : Icons.lock_rounded,
    );

    if (!enabled) {
      return child;
    }

    return PopupMenuButton<T>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return items
            .map(
              (T item) => PopupMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              ),
            )
            .toList();
      },
      child: child,
    );
  }
}

class ExplorerSearchField extends StatelessWidget {
  const ExplorerSearchField({
    required this.search,
    required this.hintText,
    required this.onSubmitted,
    required this.onClear,
    super.key,
  });

  final String search;
  final String hintText;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 360),
      child: TextFormField(
        key: ValueKey<String>('search-$search'),
        initialValue: search,
        textInputAction: TextInputAction.search,
        onFieldSubmitted: onSubmitted,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: search.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded),
                ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class ExplorerPaginationFooter extends StatelessWidget {
  const ExplorerPaginationFooter({
    required this.totalCount,
    required this.currentPage,
    required this.totalPages,
    required this.onPrevious,
    required this.onNext,
    super.key,
  });

  final int totalCount;
  final int currentPage;
  final int totalPages;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool compact = constraints.maxWidth < 700;
        final Widget countLabel = Text(
          '$totalCount matching record${totalCount == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.bodyMedium,
        );
        final Widget pager = Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            OutlinedButton.icon(
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
              label: const Text('Previous'),
            ),
            const SizedBox(width: 12),
            Text('Page $currentPage of $totalPages'),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onNext,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.chevron_right_rounded),
              label: const Text('Next'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              countLabel,
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: onPrevious,
                    icon: const Icon(Icons.chevron_left_rounded),
                    label: const Text('Previous'),
                  ),
                  Text('Page $currentPage of $totalPages'),
                  OutlinedButton.icon(
                    onPressed: onNext,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.chevron_right_rounded),
                    label: const Text('Next'),
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          children: <Widget>[
            Expanded(child: countLabel),
            pager,
          ],
        );
      },
    );
  }
}

class _ExplorerChipFrame extends StatelessWidget {
  const _ExplorerChipFrame({
    required this.label,
    required this.value,
    required this.enabled,
    required this.trailingIcon,
  });

  final String label;
  final String value;
  final bool enabled;
  final IconData trailingIcon;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: enabled ? colorScheme.surface : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Icon(
            trailingIcon,
            size: 18,
            color: enabled
                ? colorScheme.onSurfaceVariant
                : colorScheme.outline,
          ),
        ],
      ),
    );
  }
}
