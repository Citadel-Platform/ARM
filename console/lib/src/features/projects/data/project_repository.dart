import 'dart:async';
import 'dart:collection';

import 'package:arm_console/src/features/projects/domain/project_models.dart';

abstract interface class ProjectRepository {
  Stream<List<ConsoleProject>> watchProjects({Set<String>? projectIds});

  Future<List<ConsoleProject>> listProjects({Set<String>? projectIds});

  Future<void> upsertProject(
    ConsoleProject project, {
    required String actorEmail,
  });
}

class InMemoryProjectRepository implements ProjectRepository {
  InMemoryProjectRepository({List<ConsoleProject> initialProjects = const []})
    : _projects = List<ConsoleProject>.from(initialProjects) {
    _emit();
  }

  final List<ConsoleProject> _projects;
  final StreamController<List<ConsoleProject>> _controller =
      StreamController<List<ConsoleProject>>.broadcast();

  @override
  Future<List<ConsoleProject>> listProjects({Set<String>? projectIds}) async {
    return UnmodifiableListView<ConsoleProject>(
      _sortedProjects(projectIds: projectIds),
    );
  }

  @override
  Stream<List<ConsoleProject>> watchProjects({Set<String>? projectIds}) async* {
    yield UnmodifiableListView<ConsoleProject>(
      _sortedProjects(projectIds: projectIds),
    );
    yield* _controller.stream.map(
      (List<ConsoleProject> _) => UnmodifiableListView<ConsoleProject>(
        _sortedProjects(projectIds: projectIds),
      ),
    );
  }

  @override
  Future<void> upsertProject(
    ConsoleProject project, {
    required String actorEmail,
  }) async {
    final int existingIndex = _projects.indexWhere(
      (ConsoleProject item) => item.id == project.id,
    );
    final DateTime now = DateTime.now();
    final ConsoleProject nextProject;

    if (existingIndex >= 0) {
      final ConsoleProject existing = _projects[existingIndex];
      nextProject = project.copyWith(
        createdAt: existing.createdAt ?? now,
        createdBy: existing.createdBy ?? actorEmail,
        updatedAt: now,
        updatedBy: actorEmail,
      );
      _projects[existingIndex] = nextProject;
    } else {
      nextProject = project.copyWith(
        createdAt: now,
        createdBy: actorEmail,
        updatedAt: now,
        updatedBy: actorEmail,
      );
      _projects.add(nextProject);
    }

    _emit();
  }

  void dispose() {
    _controller.close();
  }

  void _emit() {
    _controller.add(UnmodifiableListView<ConsoleProject>(_sortedProjects()));
  }

  List<ConsoleProject> _sortedProjects({Set<String>? projectIds}) {
    final Iterable<ConsoleProject> scopedProjects = switch (projectIds) {
      null => _projects,
      _ => _projects.where(
        (ConsoleProject project) => projectIds.contains(project.id),
      ),
    };
    return List<ConsoleProject>.from(scopedProjects)..sort(
      (ConsoleProject left, ConsoleProject right) =>
          left.name.toLowerCase().compareTo(right.name.toLowerCase()),
    );
  }
}
