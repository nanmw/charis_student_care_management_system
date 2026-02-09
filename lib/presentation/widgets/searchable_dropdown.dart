import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';

/// A searchable dropdown widget that combines a search field with a dropdown list.
/// 
/// This widget allows users to search through a list of items and select one.
/// It matches the project's styling with AppColors and Questrial font.
/// 
/// Example usage:
/// ```dart
/// SearchableDropdown<String>(
///   label: 'Select Student',
///   items: ['John Doe', 'Jane Smith', 'Bob Johnson'],
///   selectedValue: selectedStudent,
///   hint: 'Search or select a student',
///   onChanged: (value) {
///     setState(() => selectedStudent = value);
///   },
/// )
/// ```
class SearchableDropdown<T> extends StatefulWidget {
  const SearchableDropdown({
    super.key,
    this.label,
    required this.items,
    this.selectedValue,
    required this.hint,
    required this.onChanged,
    this.searchHint = 'Search...',
    this.itemBuilder,
    this.displayTextBuilder,
    this.searchFilter,
    this.enabled = true,
    this.allowClear = false,
  });

  /// Optional label displayed above the dropdown
  final String? label;

  /// List of items to display in the dropdown
  final List<T> items;

  /// Currently selected value
  final T? selectedValue;

  /// Hint text displayed when no value is selected
  final String hint;

  /// Hint text for the search field
  final String searchHint;

  /// Callback when a value is selected
  final ValueChanged<T?> onChanged;

  /// Optional custom builder for displaying items
  /// If not provided, items will be converted to string using toString()
  final Widget Function(BuildContext context, T item)? itemBuilder;

  /// Optional function to convert selected value to display text
  /// If not provided, selectedValue.toString() will be used
  final String Function(T value)? displayTextBuilder;

  /// Optional custom search filter function
  /// If not provided, uses case-insensitive string matching
  final bool Function(T item, String query)? searchFilter;

  /// Whether the dropdown is enabled
  final bool enabled;

  /// Whether to show a "Clear" option when a value is selected
  final bool allowClear;

  @override
  State<SearchableDropdown<T>> createState() => _SearchableDropdownState<T>();
}

class _SearchableDropdownState<T> extends State<SearchableDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _buttonFocusNode = FocusNode();
  final ScrollController _listScrollController = ScrollController();
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;
  List<T> _filteredItems = [];
  int? _highlightedIndex;

  @override
  void initState() {
    super.initState();
    _filteredItems = widget.items;
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(SearchableDropdown<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _filterItems(_searchController.text);
      // Fix 3: Mark overlay for rebuild when items change
      if (_isOpen) {
        _overlayEntry?.markNeedsBuild();
      }
    }
    // Handle selectedValue changes - close overlay if it's open and value changed externally
    if (oldWidget.selectedValue != widget.selectedValue) {
      if (_isOpen) {
        // If dropdown is open and selectedValue changed externally, close it
        _removeOverlay();
      }
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _buttonFocusNode.dispose();
    _listScrollController.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onSearchChanged() {
    _filterItems(_searchController.text);
  }

  void _filterItems(String query) {
    if (!mounted) return;
    
    setState(() {
      if (query.isEmpty) {
        _filteredItems = widget.items;
      } else {
        if (widget.searchFilter != null) {
          // Fix 5: Add error handling in searchFilter
          try {
            _filteredItems = widget.items
                .where((item) => widget.searchFilter!(item, query))
                .toList();
          } catch (e) {
            // On error, show no items
            _filteredItems = [];
          }
        } else {
          final queryLower = query.toLowerCase();
          _filteredItems = widget.items
              .where((item) => item.toString().toLowerCase().contains(queryLower))
              .toList();
        }
      }
      // Reset highlighted index when filtering
      _highlightedIndex = null;
    });
    
    // Fix 1: Mark overlay for rebuild so filtered items are shown
    _overlayEntry?.markNeedsBuild();
    
    // Restore focus after state update to prevent focus loss
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _isOpen) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _toggleDropdown() {
    if (!widget.enabled) return;

    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    // Fix 4: Add enabled check and fix state sync
    if (_isOpen || !mounted || !widget.enabled) return;

    try {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
      if (mounted) {
        setState(() {
          _isOpen = true;
          _highlightedIndex = null;
        });
        // Fix 8: Scroll to selected item when overlay opens
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isOpen) {
            _searchFocusNode.requestFocus();
            // Find and scroll to selected item
            if (widget.selectedValue != null && _filteredItems.isNotEmpty) {
              final selectedIndex = _filteredItems.indexOf(widget.selectedValue as T);
              if (selectedIndex >= 0) {
                final hasClearOption = widget.allowClear && widget.selectedValue != null;
                final scrollIndex = hasClearOption ? selectedIndex + 1 : selectedIndex;
                if (_listScrollController.hasClients) {
                  _listScrollController.animateTo(
                    scrollIndex * 56.0, // Approximate ListTile height
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              }
            }
          }
        });
      }
    } catch (e) {
      // Fix 4: Reset state on error
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) {
        setState(() {
          _isOpen = false;
        });
      }
    }
  }

  void _removeOverlay() {
    // Fix 4: Improve state check
    if (!_isOpen && _overlayEntry == null) return;

    _overlayEntry?.remove();
    _overlayEntry = null;
    _highlightedIndex = null;
    if (mounted) {
      setState(() {
        _isOpen = false;
        _searchController.clear();
      });
      // Fix 9: Return focus to button
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _buttonFocusNode.requestFocus();
        }
      });
    }
  }

  void _handleKeyboardEvent(KeyEvent event) {
    if (!_isOpen) return;

    final totalItems = _filteredItems.length + (widget.allowClear && widget.selectedValue != null ? 1 : 0);
    if (totalItems == 0) return;

    // Fix 6: Handle Escape key
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      _removeOverlay();
      return;
    }

    // Fix 7: Handle arrow keys and Enter
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        setState(() {
          if (_highlightedIndex == null) {
            _highlightedIndex = 0;
          } else {
            _highlightedIndex = (_highlightedIndex! + 1) % totalItems;
          }
        });
        _scrollToHighlighted();
        _overlayEntry?.markNeedsBuild();
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        setState(() {
          if (_highlightedIndex == null) {
            _highlightedIndex = totalItems - 1;
          } else {
            _highlightedIndex = (_highlightedIndex! - 1 + totalItems) % totalItems;
          }
        });
        _scrollToHighlighted();
        _overlayEntry?.markNeedsBuild();
      } else if (event.logicalKey == LogicalKeyboardKey.enter && _highlightedIndex != null) {
        _selectHighlightedItem();
      }
    }
  }

  void _scrollToHighlighted() {
    if (_highlightedIndex == null || !_listScrollController.hasClients) return;
    
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_highlightedIndex != null && _listScrollController.hasClients) {
        _listScrollController.animateTo(
          _highlightedIndex! * 56.0, // Approximate ListTile height
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _selectHighlightedItem() {
    if (_highlightedIndex == null) return;

    final totalItems = _filteredItems.length + (widget.allowClear && widget.selectedValue != null ? 1 : 0);
    if (_highlightedIndex! >= totalItems) return;

    // Handle Clear option
    if (widget.allowClear && widget.selectedValue != null && _highlightedIndex == 0) {
      widget.onChanged(null);
      _removeOverlay();
      return;
    }

    // Handle regular item
    final itemIndex = widget.allowClear && widget.selectedValue != null
        ? _highlightedIndex! - 1
        : _highlightedIndex!;
    
    if (itemIndex >= 0 && itemIndex < _filteredItems.length) {
      widget.onChanged(_filteredItems[itemIndex]);
      _removeOverlay();
    }
  }

  OverlayEntry _createOverlayEntry() {
    if (!mounted) {
      throw StateError('Widget not mounted');
    }
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) {
      throw StateError('RenderBox not attached');
    }
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKeyboardEvent,
        child: Stack(
          children: [
            // Barrier to catch clicks outside
            Positioned.fill(
              child: GestureDetector(
                onTap: _removeOverlay,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            // Dropdown content
            Positioned(
              width: size.width,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: Offset(0.0, size.height + 4.0),
                child: Material(
                    elevation: 8,
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.charisWhite,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 300),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.charisMidGray),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Search field
                          Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Semantics(
                              // Fix 11: Add accessibility
                              label: 'Search ${widget.searchHint}',
                              hint: 'Type to filter items',
                              child: TextField(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                autofocus: true,
                                style: const TextStyle(
                                  color: AppColors.charisBlack,
                                  fontSize: 14,
                                  fontFamily: 'Questrial',
                                ),
                                decoration: InputDecoration(
                                  hintText: widget.searchHint,
                                  hintStyle: const TextStyle(
                                    color: AppColors.charisMidGray,
                                    fontSize: 14,
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search,
                                    color: AppColors.charisMidGray,
                                    size: 20,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(color: AppColors.charisMidGray),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                      color: AppColors.primaryActionRed,
                                      width: 2,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  filled: true,
                                  fillColor: AppColors.charisWhite,
                                ),
                                // Fix 6: Handle Escape key in TextField
                                onSubmitted: (value) {
                                  if (_highlightedIndex != null) {
                                    _selectHighlightedItem();
                                  }
                                },
                              ),
                            ),
                          ),
                          // Divider
                          const Divider(height: 1, color: AppColors.charisLightGray),
                          // Items list
                          Flexible(
                            child: _filteredItems.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(16.0),
                                    child: Text(
                                      'No items found',
                                      style: TextStyle(
                                        color: AppColors.charisMidGray,
                                        fontSize: 14,
                                        fontFamily: 'Questrial',
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    // Fix 12: Performance optimization - add controller and cacheExtent
                                    controller: _listScrollController,
                                    cacheExtent: 200,
                                    shrinkWrap: true,
                                    padding: EdgeInsets.zero,
                                    itemCount: _filteredItems.length + (widget.allowClear && widget.selectedValue != null ? 1 : 0),
                                    itemBuilder: (context, index) {
                                      // Clear option
                                      if (widget.allowClear && widget.selectedValue != null && index == 0) {
                                        final isHighlighted = _highlightedIndex == 0;
                                        return Semantics(
                                          // Fix 11: Add accessibility
                                          label: 'Clear selection',
                                          button: true,
                                          child: ListTile(
                                            title: const Text(
                                              'Clear',
                                              style: TextStyle(
                                                color: AppColors.charisMidGray,
                                                fontSize: 14,
                                                fontFamily: 'Questrial',
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                            tileColor: isHighlighted
                                                ? AppColors.charisLightGray.withValues(alpha: 0.5)
                                                : null,
                                            onTap: () {
                                              widget.onChanged(null);
                                              _removeOverlay();
                                            },
                                          ),
                                        );
                                      }

                                      final itemIndex = widget.allowClear && widget.selectedValue != null
                                          ? index - 1
                                          : index;
                                      final item = _filteredItems[itemIndex];
                                      final isSelected = item == widget.selectedValue;
                                      final isHighlighted = _highlightedIndex == index;

                                      // Fix 5: Add error handling in itemBuilder
                                      Widget titleWidget;
                                      if (widget.itemBuilder != null) {
                                        try {
                                          titleWidget = widget.itemBuilder!(context, item);
                                        } catch (e) {
                                          titleWidget = Text(
                                            item.toString(),
                                            style: const TextStyle(
                                              color: AppColors.charisBlack,
                                              fontSize: 14,
                                              fontFamily: 'Questrial',
                                            ),
                                          );
                                        }
                                      } else {
                                        titleWidget = Text(
                                          item.toString(),
                                          style: const TextStyle(
                                            color: AppColors.charisBlack,
                                            fontSize: 14,
                                            fontFamily: 'Questrial',
                                          ),
                                        );
                                      }

                                      return Semantics(
                                        // Fix 11: Add accessibility
                                        label: isSelected ? '${item.toString()}, selected' : item.toString(),
                                        selected: isSelected,
                                        button: true,
                                        child: ListTile(
                                          title: titleWidget,
                                          selected: isSelected,
                                          selectedTileColor: AppColors.charisLightGray.withValues(alpha: 0.3),
                                          tileColor: isHighlighted && !isSelected
                                              ? AppColors.charisLightGray.withValues(alpha: 0.5)
                                              : null,
                                          onTap: () {
                                            widget.onChanged(item);
                                            _removeOverlay();
                                          },
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getDisplayText() {
    if (widget.selectedValue == null) {
      return widget.hint;
    }
    
    // Fix 10: Add error handling and validation
    if (!widget.items.contains(widget.selectedValue)) {
      // If selectedValue is not in items, try to display it anyway
      if (widget.displayTextBuilder != null) {
        try {
          return widget.displayTextBuilder!(widget.selectedValue as T);
        } catch (e) {
          return widget.hint; // Fallback to hint if displayTextBuilder fails
        }
      }
      return widget.selectedValue.toString();
    }
    
    if (widget.displayTextBuilder != null) {
      try {
        return widget.displayTextBuilder!(widget.selectedValue as T);
      } catch (e) {
        return widget.selectedValue.toString(); // Fallback to toString
      }
    }
    return widget.selectedValue.toString();
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're in a constrained height context (like DataGrid cells)
    final hasLabel = widget.label != null;
    final verticalPadding = hasLabel ? 10.0 : 6.0; // Reduce padding when no label
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: const TextStyle(
              color: AppColors.charisBlack,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 6),
        ],
        CompositedTransformTarget(
          link: _layerLink,
          child: Focus(
            focusNode: _buttonFocusNode,
            child: Semantics(
              // Fix 11: Add accessibility
              label: widget.label ?? 'Dropdown',
              hint: 'Tap to open dropdown menu',
              value: _getDisplayText(),
              button: true,
              child: InkWell(
                onTap: _toggleDropdown,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _isOpen
                          ? AppColors.primaryActionRed
                          : AppColors.charisMidGray,
                      width: _isOpen ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: widget.enabled
                        ? AppColors.charisWhite
                        : AppColors.charisLightGray,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 14, vertical: verticalPadding),
                  constraints: hasLabel ? null : const BoxConstraints(maxHeight: 32),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          _getDisplayText(),
                          style: TextStyle(
                            color: widget.selectedValue == null
                                ? AppColors.charisMidGray
                                : AppColors.charisBlack,
                            fontSize: 14,
                            fontFamily: 'Questrial',
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      Icon(
                        _isOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        color: AppColors.charisMidGray,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
