import 'package:flutter/material.dart';
import 'package:talktime/core/navigation_manager.dart';
import 'package:talktime/features/auth/data/auth_service.dart';
import 'package:talktime/features/chat/data/conversation_service.dart';
import 'package:talktime/features/chat/presentation/pages/message_list_page.dart';
import 'package:talktime/shared/models/user.dart';
import 'package:logger/logger.dart';

class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}

class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  final Logger _logger = Logger(output: ConsoleOutput());
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _groupNameController = TextEditingController();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _groupNameFocus = FocusNode();

  String? _errorText;
  bool _isLoading = false;
  bool _isSearching = false;
  final List<User> _selectedUsers = [];
  List<User> _searchResults = [];
  String? _currentUserId;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final auth = AuthService();
    final user = await auth.getCurrentUser();
    setState(() {
      _currentUserId = user.id;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _groupNameController.dispose();
    _emailFocus.dispose();
    _groupNameFocus.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final query = _emailController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _errorText = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorText = null;
    });

    try {
      final apiClient = ConversationService();
      final users = await apiClient.searchUser(query);

      // Filter out current user and already selected users
      final filteredUsers = users.where((user) {
        if (user.id == _currentUserId) return false;
        if (_selectedUsers.any((selected) => selected.id == user.id)) {
          return false;
        }
        return true;
      }).toList();
      print("${filteredUsers.length} users found");

      setState(() {
        _searchResults = filteredUsers;
        if (filteredUsers.isEmpty && users.isEmpty) {
          _errorText = 'No users found';
        }
      });
    } catch (e) {
      _logger.e('User search failed: $e');
      setState(() {
        _errorText = 'Failed to search users. Please try again.';
        _searchResults = [];
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  void _addUser(User user) {
    setState(() {
      _selectedUsers.add(user);
      _searchResults.remove(user);
      _emailController.clear();
      _errorText = null;
    });
  }

  void _removeUser(User user) {
    setState(() {
      _selectedUsers.remove(user);
    });
  }

  Future<void> _createGroupChat() async {
    if (_selectedUsers.isEmpty) {
      setState(() {
        _errorText = 'Please add at least one member to the group';
      });
      return;
    }

    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      setState(() {
        _errorText = 'Please enter a group name';
      });
      _groupNameFocus.requestFocus();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      final apiClient = ConversationService();
      final userIds = _selectedUsers.map((user) => user.id).toList();
      final conversation = await apiClient.createGroup(userIds, groupName);
      await apiClient.syncConversations();

      if (!mounted) return;

      NavigationManager().openMessagesList(conversation);
      // Navigate to the new group chat
    } catch (e) {
      _logger.e('Create group chat failed: $e');
      setState(() {
        _errorText = 'Could not create group. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group Chat'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Group Name Field
                  TextField(
                    controller: _groupNameController,
                    focusNode: _groupNameFocus,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'Enter a name for your group',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.group),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Selected Users Chips
                  if (_selectedUsers.isNotEmpty) ...[
                    Text(
                      'Members (${_selectedUsers.length})',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedUsers.map((user) {
                        return Chip(
                          avatar: user.avatarUrl != null
                              ? CircleAvatar(
                                  backgroundImage: NetworkImage(
                                    user.avatarUrl!,
                                  ),
                                )
                              : CircleAvatar(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withOpacity(0.2),
                                  child: Text(
                                    user.username.isNotEmpty
                                        ? user.username[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                          label: Text(user.username),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeUser(user),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Search User Field
                  Text(
                    'Add Members',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _searchUsers(),
                    onChanged: (value) {
                      // Debounce search
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (_emailController.text == value) {
                          _searchUsers();
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: 'Search by email',
                      hintText: 'Enter email to search',
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : _emailController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _emailController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _errorText = null;
                                });
                              },
                            )
                          : null,
                    ),
                  ),

                  // Error Text
                  if (_errorText != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorText!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 14,
                      ),
                    ),
                  ],

                  // Search Results
                  if (_searchResults.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Card(
                      clipBehavior: Clip.hardEdge,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _searchResults.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = _searchResults[index];
                          return ListTile(
                            leading: user.avatarUrl != null
                                ? CircleAvatar(
                                    backgroundImage: NetworkImage(
                                      user.avatarUrl!,
                                    ),
                                  )
                                : CircleAvatar(
                                    backgroundColor: Theme.of(
                                      context,
                                    ).colorScheme.primary.withOpacity(0.1),
                                    child: Text(
                                      user.username.isNotEmpty
                                          ? user.username[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                            title: Text(user.username),
                            subtitle: user.username != null
                                ? Text(
                                    user.username,
                                    style: const TextStyle(color: Colors.grey),
                                  )
                                : null,
                            trailing: IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              color: Theme.of(context).colorScheme.primary,
                              onPressed: () => _addUser(user),
                            ),
                            onTap: () => _addUser(user),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Create Button at Bottom
          Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading || _selectedUsers.isEmpty
                      ? null
                      : _createGroupChat,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.group_add, size: 18),
                  label: Text(
                    _isLoading
                        ? 'Creating...'
                        : 'Create Group (${_selectedUsers.length} members)',
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
