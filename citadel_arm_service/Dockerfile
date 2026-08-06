FROM dart:stable AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/citadel_arm_service.dart -o /app/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /app/server /app/server
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/server"]
