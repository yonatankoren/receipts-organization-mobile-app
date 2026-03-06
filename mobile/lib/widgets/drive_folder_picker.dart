/// Drive Folder Picker — native Flutter UI backed by the Drive API.
///
/// Uses the full `drive` OAuth scope to list ALL folders in the user's
/// Google Drive (not just those created by this app).
///
/// Returns [DriveFolderPickResult] on selection, or null on cancel.

import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import '../services/auth_service.dart';

/// Result from the folder picker.
class DriveFolderPickResult {
  final String folderId;
  final String folderName;

  const DriveFolderPickResult({
    required this.folderId,
    required this.folderName,
  });
}

/// Shows a full-screen page with a folder browser.
/// Returns null if cancelled.
Future<DriveFolderPickResult?> showDriveFolderPicker(BuildContext context) {
  return Navigator.of(context).push<DriveFolderPickResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const _FolderBrowserPage(),
    ),
  );
}

/// A simple breadcrumb entry for the navigation stack.
class _FolderEntry {
  final String id;
  final String name;
  const _FolderEntry(this.id, this.name);
}

class _FolderBrowserPage extends StatefulWidget {
  const _FolderBrowserPage();

  @override
  State<_FolderBrowserPage> createState() => _FolderBrowserPageState();
}

class _FolderBrowserPageState extends State<_FolderBrowserPage> {
  /// Navigation stack — the last entry is the current folder.
  final List<_FolderEntry> _breadcrumbs = [
    const _FolderEntry('root', 'האחסון שלי'),
  ];

  List<drive.File>? _folders;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  String get _currentFolderId => _breadcrumbs.last.id;
  String get _currentFolderName => _breadcrumbs.last.name;

  Future<void> _loadFolders() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _folders = null;
    });

    try {
      final client = await AuthService.instance.getAuthenticatedClient();
      if (client == null) {
        throw Exception('לא מחובר לחשבון Google');
      }

      try {
        final driveApi = drive.DriveApi(client);

        // List all folders inside the current parent.
        // With the `drive` scope this returns ALL folders, not just app-created.
        final result = await driveApi.files.list(
          q: "'$_currentFolderId' in parents "
              "and mimeType = 'application/vnd.google-apps.folder' "
              "and trashed = false",
          spaces: 'drive',
          orderBy: 'name',
          pageSize: 100,
          $fields: 'files(id, name)',
        );

        if (mounted) {
          setState(() {
            _folders = result.files ?? [];
            _isLoading = false;
          });
        }
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('FolderPicker: error loading folders: $e');
      if (mounted) {
        setState(() {
          _error = 'שגיאה בטעינת תיקיות: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openFolder(drive.File folder) {
    _breadcrumbs.add(_FolderEntry(folder.id!, folder.name!));
    _loadFolders();
  }

  void _goBack() {
    if (_breadcrumbs.length > 1) {
      _breadcrumbs.removeLast();
      _loadFolders();
    }
  }

  void _navigateToBreadcrumb(int index) {
    if (index < _breadcrumbs.length - 1) {
      _breadcrumbs.removeRange(index + 1, _breadcrumbs.length);
      _loadFolders();
    }
  }

  void _selectCurrent() {
    Navigator.of(context).pop(
      DriveFolderPickResult(
        folderId: _currentFolderId,
        folderName: _currentFolderName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('בחירת תיקייה'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Breadcrumb trail
          _buildBreadcrumbs(theme),
          const Divider(height: 1),

          // Folder list
          Expanded(child: _buildBody(theme)),

          // Bottom bar: back + select this folder
          const Divider(height: 1),
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbs(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true, // So the current folder is always visible
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _breadcrumbs.length; i++) ...[
              if (i > 0)
                Icon(Icons.chevron_left,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
              InkWell(
                onTap: i < _breadcrumbs.length - 1
                    ? () => _navigateToBreadcrumb(i)
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    _breadcrumbs[i].name,
                    style: TextStyle(
                      color: i == _breadcrumbs.length - 1
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: i == _breadcrumbs.length - 1
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline,
                  size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadFolders,
                child: const Text('נסה שוב'),
              ),
            ],
          ),
        ),
      );
    }

    if (_folders == null || _folders!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_open,
                  size: 48, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'אין תיקיות משנה כאן',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ניתן לבחור את התיקייה הנוכחית',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _folders!.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        final folder = _folders![index];
        return ListTile(
          leading: Icon(Icons.folder,
              color: theme.colorScheme.primary, size: 28),
          title: Text(
            folder.name ?? '',
            style: const TextStyle(fontSize: 15),
          ),
          trailing: Icon(Icons.chevron_left,
              color: theme.colorScheme.onSurfaceVariant),
          onTap: () => _openFolder(folder),
        );
      },
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Back button (only if not at root)
            if (_breadcrumbs.length > 1)
              TextButton.icon(
                onPressed: _goBack,
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: const Text('חזרה'),
              ),
            const Spacer(),
            // Select current folder
            ElevatedButton.icon(
              onPressed: _selectCurrent,
              icon: const Icon(Icons.check, size: 18),
              label: Text('בחר: $_currentFolderName'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
