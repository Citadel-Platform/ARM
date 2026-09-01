# Build context is `citadel_core/arm`, not `citadel_arm_service`: the service
# gained a path dependency on `arm_tooling_core` with the ticket codec, and a
# context of the service directory alone cannot see `../tooling_core`, so
# `dart pub get` failed at resolution. Paths here mirror the repository layout
# so the `path: ../tooling_core` in the service pubspec resolves unchanged.
FROM dart:stable AS build
WORKDIR /app

# Pubspecs first, for layer caching: the dependency graph changes far less
# often than the source.
COPY tooling_core/pubspec.* ./tooling_core/
COPY citadel_arm_service/pubspec.* ./citadel_arm_service/
WORKDIR /app/citadel_arm_service
RUN dart pub get

WORKDIR /app
COPY tooling_core/ ./tooling_core/
COPY citadel_arm_service/ ./citadel_arm_service/

WORKDIR /app/citadel_arm_service
RUN dart pub get --offline
# Generated sources (`*.freezed.dart`) are gitignored, so they are not in the
# context and must be produced here — the ticket models use freezed.
RUN dart run build_runner build --delete-conflicting-outputs
RUN dart compile exe bin/citadel_arm_service.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/server"]
