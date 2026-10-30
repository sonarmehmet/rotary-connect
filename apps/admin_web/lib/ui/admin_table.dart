import 'package:flutter/material.dart';

import '../core/format.dart';
import 'state_views.dart';
import 'table_logic.dart';

/// Tablo sütunu. `text` hem görüntü (özel `cell` yoksa) hem de dışa aktarım/arama
/// için kullanılır.
class AdminColumn<T> {
  const AdminColumn({
    required this.label,
    required this.text,
    this.numeric = false,
    this.compare,
    this.cell,
  });

  final String label;
  final String Function(T row) text;
  final bool numeric;

  /// Verilirse sütun başlığına tıklayarak sıralanır.
  final int Function(T a, T b)? compare;

  /// Özel hücre (rozet, ilerleme çubuğu vb.).
  final Widget Function(BuildContext context, T row)? cell;
}

class FilterOption<T> {
  const FilterOption(this.label, this.test);

  final String label;
  final bool Function(T row) test;
}

/// Seçenekli filtre grubu ("Tümü" her zaman vardır).
class TableFilter<T> {
  const TableFilter({required this.label, required this.options});

  final String label;
  final List<FilterOption<T>> options;
}

/// Ortak yönetim tablosu: arama, filtre, tarih aralığı, sıralama, sayfalama,
/// boş/filtre-sonucu-yok durumu. Yatay taşmada kayar (800 px ve üstü).
class AdminTable<T> extends StatefulWidget {
  const AdminTable({
    super.key,
    required this.columns,
    required this.rows,
    required this.searchText,
    this.filters,
    this.dateOf,
    this.dateLabel = 'Tarih aralığı',
    this.initialSortColumn,
    this.initialAscending = true,
    this.onRowTap,
    this.emptyMessage = 'Henüz kayıt yok.',
    this.pageSizes = const [10, 25, 50],
  });

  final List<AdminColumn<T>> columns;
  final List<T> rows;
  final String Function(T row) searchText;
  final List<TableFilter<T>>? filters;
  final DateTime? Function(T row)? dateOf;
  final String dateLabel;
  final int? initialSortColumn;
  final bool initialAscending;
  final void Function(T row)? onRowTap;
  final String emptyMessage;
  final List<int> pageSizes;

  @override
  State<AdminTable<T>> createState() => _AdminTableState<T>();
}

class _AdminTableState<T> extends State<AdminTable<T>> {
  final TextEditingController _search = TextEditingController();
  final Map<int, int> _selected = {};
  DateRange? _range;
  int? _sortColumn;
  bool _ascending = true;
  int _page = 0;
  late int _pageSize;

  @override
  void initState() {
    super.initState();
    _sortColumn = widget.initialSortColumn;
    _ascending = widget.initialAscending;
    _pageSize = widget.pageSizes.first;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  bool get _hasActiveFilter =>
      _selected.isNotEmpty || _range != null || _search.text.isNotEmpty;

  void _reset() {
    setState(() {
      _search.clear();
      _selected.clear();
      _range = null;
      _page = 0;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final current = _range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 5, 12, 31),
      initialDateRange: current == null
          ? null
          : DateTimeRange(start: current.start, end: current.end),
      helpText: 'Tarih aralığı seçin',
      saveText: 'Uygula',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = DateRange(picked.start, picked.end);
      _page = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = widget.filters ?? <TableFilter<T>>[];
    final predicates = <bool Function(T row)>[];
    for (final entry in _selected.entries) {
      if (entry.key < filters.length &&
          entry.value < filters[entry.key].options.length) {
        predicates.add(filters[entry.key].options[entry.value].test);
      }
    }
    final sortColumn = _sortColumn;
    final compare =
        sortColumn == null ? null : widget.columns[sortColumn].compare;
    final result = queryRows<T>(
      rows: widget.rows,
      search: _search.text,
      searchText: widget.searchText,
      predicates: predicates,
      range: _range,
      dateOf: widget.dateOf,
      compare: compare,
      ascending: _ascending,
    );
    final pages = pageCount(result.length, _pageSize);
    final page = _page >= pages ? pages - 1 : _page;
    final start = page * _pageSize;
    final end =
        start + _pageSize > result.length ? result.length : start + _pageSize;
    final visible = result.sublist(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _toolbar(filters),
        const SizedBox(height: 8),
        Expanded(
          child: result.isEmpty
              ? EmptyView(
                  message: widget.rows.isEmpty
                      ? widget.emptyMessage
                      : 'Filtrelere uyan kayıt bulunamadı.',
                )
              : _table(visible),
        ),
        _footer(result.length, start, end, page, pages),
      ],
    );
  }

  Widget _toolbar(List<TableFilter<T>> filters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 300,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Ara…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
            ),
            if (widget.dateOf != null)
              OutlinedButton.icon(
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_range?.label ?? widget.dateLabel),
              ),
            if (_hasActiveFilter)
              TextButton.icon(
                onPressed: _reset,
                icon: const Icon(Icons.filter_alt_off_outlined),
                label: const Text('Filtreleri temizle'),
              ),
          ],
        ),
        for (var i = 0; i < filters.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _filterGroup(i, filters[i]),
          ),
      ],
    );
  }

  Widget _filterGroup(int index, TableFilter<T> filter) {
    final selected = _selected[index];
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${filter.label}:'),
        ChoiceChip(
          label: const Text('Tümü'),
          selected: selected == null,
          onSelected: (_) => setState(() {
            _selected.remove(index);
            _page = 0;
          }),
        ),
        for (var i = 0; i < filter.options.length; i++)
          ChoiceChip(
            label: Text(filter.options[i].label),
            selected: selected == i,
            onSelected: (_) => setState(() {
              _selected[index] = i;
              _page = 0;
            }),
          ),
      ],
    );
  }

  Widget _table(List<T> visible) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                showCheckboxColumn: false,
                sortColumnIndex: _sortColumn,
                sortAscending: _ascending,
                columns: [
                  for (final c in widget.columns)
                    DataColumn(
                      label: Text(c.label),
                      numeric: c.numeric,
                      onSort: c.compare == null
                          ? null
                          : (index, ascending) => setState(() {
                                _sortColumn = index;
                                _ascending = ascending;
                                _page = 0;
                              }),
                    ),
                ],
                rows: [
                  for (final row in visible)
                    DataRow(
                      onSelectChanged: widget.onRowTap == null
                          ? null
                          : (_) => widget.onRowTap!(row),
                      cells: [
                        for (final c in widget.columns)
                          DataCell(
                            c.cell != null
                                ? c.cell!(context, row)
                                : _textCell(c.text(row)),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _textCell(String text) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _footer(int total, int start, int end, int page, int pages) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Text('${total == 0 ? 0 : start + 1}–$end / $total kayıt'),
          const Spacer(),
          const Text('Sayfa başına:'),
          PopupMenuButton<int>(
            tooltip: 'Sayfa başına kayıt',
            initialValue: _pageSize,
            onSelected: (size) => setState(() {
              _pageSize = size;
              _page = 0;
            }),
            itemBuilder: (_) => [
              for (final size in widget.pageSizes)
                PopupMenuItem<int>(value: size, child: Text('$size')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Text(
                '$_pageSize',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Önceki sayfa',
            onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: 'Sonraki sayfa',
            onPressed:
                page < pages - 1 ? () => setState(() => _page = page + 1) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
