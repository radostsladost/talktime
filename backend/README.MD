# TalkTime Backend

## Setup instructions

### Firebase (Only if you need notifications for mobile and web)

1. Create a Firebase project from [here](https://console.firebase.google.com/).
2. Enable Firebase Authentication and Firestore.
3. Generate private key, rename it to `firebase-admin.json` and place it in the `TalkTime.Api` directory.

### Preparation

1. Rename the TalkTime.Api/appsettings.Development.json file to TalkTime.Api/appsettings.json.
2. Change the values in the `appsettings.json` file if you need.

### Docker

1. Install Docker Desktop from [here](https://www.docker.com/products/docker-desktop).
2. Open a terminal and navigate to the `backend` directory.
3. Run `docker-compose up` to start the backend services.
4. Use port 9999 (or change both in docker_compose.yml and TalkTime.Api/appsettings.json) for accessing the backend service.

OR:

### Standalone

1. Install ASP.NET Core Runtime or SDK 9+ from [here](https://dotnet.microsoft.com/ru-ru/download/dotnet/9.0).
2. Open a terminal and navigate to the `backend` directory.
3. Run `dotnet publish -c Release -o ./publish` to build the backend services.
4. Run `cd publish && dotnet TalkTime.Api.dll` to start the backend services.
5. Use port 9999 (or change both in TalkTime.Api/appsettings.json) for accessing the backend service.


## Development

- Add migration with: `dotnet ef migrations add <migration_name> --project TalkTime.Infrastructure --startup-project TalkTime.Api`