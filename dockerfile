# 使用.NET 9.0 SDK作為建置環境
FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src

COPY ["Postgres.Caching/Postgres.Caching.csproj", "Postgres.Caching/"]
COPY ["Postgres.Caching.ServiceDefaults/Postgres.Caching.ServiceDefaults.csproj", "Postgres.Caching.ServiceDefaults/"]

RUN dotnet restore "Postgres.Caching/Postgres.Caching.csproj"

COPY . .

WORKDIR "/src/Postgres.Caching"
RUN dotnet build "Postgres.Caching.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "Postgres.Caching.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS final
WORKDIR /app

EXPOSE 5000

COPY --from=publish /app/publish .

ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://+:5000
ENV ConnectionStrings__redis=redis:6379
ENV ConnectionStrings__caching-db=Host=postgres;Port=5432;Database=caching-db;Username=postgres;Password=postgres

ENTRYPOINT ["dotnet", "Postgres.Caching.dll"]