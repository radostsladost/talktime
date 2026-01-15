FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /source

# Copy everything. This is less efficient
COPY --link . .
# Publish app - will get a warning if there is a .sln file in the directory.
# -c Release is now the default for dotnet publish, but if you are using .NET < 8.0, you should include it.
# A full restore is done as part of the publish.
RUN dotnet publish -c Release -o /app

# Change to the runtime image
FROM mcr.microsoft.com/dotnet/aspnet:9.0
WORKDIR /app
COPY --link --from=build /app .

ENTRYPOINT ["./TalkTime.Api"]
