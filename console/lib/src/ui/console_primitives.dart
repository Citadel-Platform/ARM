import 'package:flutter/material.dart';

class ConsolePageBody extends StatelessWidget {
  const ConsolePageBody({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: child,
        ),
      ),
    );
  }
}

class ConsoleSectionHeader extends StatelessWidget {
  const ConsoleSectionHeader({
    required this.eyebrow,
    required this.title,
    required this.description,
    this.actions,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          eyebrow.toUpperCase(),
          style: textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          description,
          style: textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );

    if (actions == null || actions!.isEmpty) {
      return content;
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Widget actionWrap = Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions!,
        );

        if (constraints.maxWidth < 960) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              content,
              const SizedBox(height: 16),
              actionWrap,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: content),
            const SizedBox(width: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
              child: actionWrap,
            ),
          ],
        );
      },
    );
  }
}

class ConsoleFilterBar extends StatelessWidget {
  const ConsoleFilterBar({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.tune_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Filters',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          ...children,
        ],
      ),
    );
  }
}

enum ConsoleMetricTone { standard, attention, critical, positive }

class ConsoleMetricCard extends StatelessWidget {
  const ConsoleMetricCard({
    required this.label,
    required this.value,
    required this.supportingText,
    required this.icon,
    this.tone = ConsoleMetricTone.standard,
    super.key,
  });

  final String label;
  final String value;
  final String supportingText;
  final IconData icon;
  final ConsoleMetricTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ({Color background, Color foreground}) palette = switch (tone) {
      ConsoleMetricTone.critical => (
        background: const Color(0xFFFDECEA),
        foreground: const Color(0xFFB3261E),
      ),
      ConsoleMetricTone.attention => (
        background: const Color(0xFFFFF4E5),
        foreground: const Color(0xFF8D5C00),
      ),
      ConsoleMetricTone.positive => (
        background: const Color(0xFFE9F6EC),
        foreground: const Color(0xFF1F6A37),
      ),
      ConsoleMetricTone.standard => (
        background: colorScheme.primaryContainer,
        foreground: colorScheme.onPrimaryContainer,
      ),
    };

    return ConsoleSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.background,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: palette.foreground),
              ),
              const Spacer(),
              Icon(
                Icons.north_east_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            value,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            supportingText,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class ConsoleSurface extends StatelessWidget {
  const ConsoleSurface({
    required this.child,
    this.title,
    this.description,
    this.padding = const EdgeInsets.all(20),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? description;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (title != null) ...<Widget>[
              Text(
                title!,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (description != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class ConsoleFormSection extends StatelessWidget {
  const ConsoleFormSection({
    required this.title,
    required this.description,
    required this.child,
    super.key,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(title: title, description: description, child: child);
  }
}

class ConsoleDataTableCard extends StatelessWidget {
  const ConsoleDataTableCard({
    required this.title,
    required this.description,
    required this.columns,
    required this.rows,
    super.key,
  });

  final String title;
  final String description;
  final List<String> columns;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    return ConsoleSurface(
      title: title,
      description: description,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 52,
          dataRowMinHeight: 56,
          dataRowMaxHeight: 56,
          columns: columns
              .map(
                (String label) => DataColumn(
                  label: Text(
                    label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              )
              .toList(),
          rows: rows
              .map(
                (List<String> row) => DataRow(
                  cells: row
                      .map((String value) => DataCell(Text(value)))
                      .toList(),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class ConsoleStateView extends StatelessWidget {
  const ConsoleStateView.loading({
    this.title = 'Loading data',
    this.message = 'Preparing the latest telemetry and investigation context.',
    this.actionLabel,
    this.onAction,
    super.key,
  }) : icon = Icons.sync_rounded;

  const ConsoleStateView.empty({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : icon = Icons.inbox_outlined;

  const ConsoleStateView.error({
    required this.title,
    required this.message,
    this.actionLabel = 'Retry',
    this.onAction,
    super.key,
  }) : icon = Icons.error_outline_rounded;

  const ConsoleStateView.noAccess({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    super.key,
  }) : icon = Icons.lock_outline_rounded;

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                icon,
                color: colorScheme.onPrimaryContainer,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
