#!/bin/bash

# .NET DevContainer Project Creation Script
# Creates a new .NET project with development container setup

set -e

PROJECT_NAME=$1
TARGET_DIR=$2

# Validate project name is provided
if [ -z "$PROJECT_NAME" ]; then
    echo "Usage: ./new-dotnet-project.sh <project-name> [target-directory]"
    echo "Examples:"
    echo "  ./new-dotnet-project.sh myapp                    # Creates ~/projects/myapp"
    echo "  ./new-dotnet-project.sh myapp ../../MyProjects  # Creates ../../MyProjects/myapp"
    echo ""
    echo "This script will:"
    echo "  1. Create a new .NET Web API project"
    echo "  2. Copy DevContainer and VS Code configurations"
    echo "  3. Set up project structure and dependencies"
    echo "  4. Configure Docker for development"
    echo ""
    exit 1
fi

# If no target directory specified, default to ~/projects/<project-name>
if [ -z "$TARGET_DIR" ]; then
    TARGET_DIR="$HOME/projects"
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
    
    # Create the target directory if it doesn't exist
    if [ ! -d "$TARGET_DIR" ]; then
        echo "📁 Creating projects directory: $TARGET_DIR"
        mkdir -p "$TARGET_DIR"
    fi
else
    PROJECT_PATH="$TARGET_DIR/$PROJECT_NAME"
    
    # Check if project already exists in specified directory
    if [ -d "$PROJECT_PATH" ]; then
        echo "❌ Error: Project already exists at $PROJECT_PATH"
        echo "Please choose a different project name or remove the existing project."
        exit 1
    fi
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_HELPER="$SCRIPT_DIR/../../../scripts/metadata-helper.sh"

# Load metadata helper functions
if [ -f "$METADATA_HELPER" ]; then
    source "$METADATA_HELPER"
else
    echo "⚠️  Warning: Metadata helper not found at $METADATA_HELPER"
fi

echo "🟣 Creating .NET Web API project: $PROJECT_NAME"
echo "📍 Project path: $PROJECT_PATH"

# Create project directory
mkdir -p "$PROJECT_PATH"
cd "$PROJECT_PATH"

# Check if dotnet CLI is available
if command -v dotnet &> /dev/null; then
    echo "📋 Creating .NET project using dotnet CLI..."
    dotnet new webapi -n "$PROJECT_NAME" -o . --framework net8.0
else
    echo "📋 Creating .NET project structure manually..."
    
    # Create basic project structure
    mkdir -p Controllers Models Services
    
    # Create project file
    cat > "${PROJECT_NAME}.csproj" << EOF
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Swashbuckle.AspNetCore" Version="6.4.0" />
  </ItemGroup>

</Project>
EOF

    # Create Program.cs
    cat > Program.cs << EOF
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(c =>
{
    c.SwaggerDoc("v1", new OpenApiInfo { Title = "$PROJECT_NAME API", Version = "v1" });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

app.Run();
EOF

    # Create a sample controller
    cat > Controllers/WeatherForecastController.cs << EOF
using Microsoft.AspNetCore.Mvc;

namespace $PROJECT_NAME.Controllers;

[ApiController]
[Route("[controller]")]
public class WeatherForecastController : ControllerBase
{
    private static readonly string[] Summaries = new[]
    {
        "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
    };

    [HttpGet(Name = "GetWeatherForecast")]
    public IEnumerable<WeatherForecast> Get()
    {
        return Enumerable.Range(1, 5).Select(index => new WeatherForecast
        {
            Date = DateOnly.FromDateTime(DateTime.Now.AddDays(index)),
            TemperatureC = Random.Shared.Next(-20, 55),
            Summary = Summaries[Random.Shared.Next(Summaries.Length)]
        })
        .ToArray();
    }
}
EOF

    # Create WeatherForecast model
    cat > Models/WeatherForecast.cs << EOF
namespace $PROJECT_NAME;

public class WeatherForecast
{
    public DateOnly Date { get; set; }

    public int TemperatureC { get; set; }

    public int TemperatureF => 32 + (int)(TemperatureC / 0.5556);

    public string? Summary { get; set; }
}
EOF

    # Create appsettings.json
    cat > appsettings.json << EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  },
  "AllowedHosts": "*"
}
EOF

    # Create appsettings.Development.json
    cat > appsettings.Development.json << EOF
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.AspNetCore": "Warning"
    }
  }
}
EOF
fi

# Create README.md
cat > README.md << EOF
# $PROJECT_NAME

A .NET Web API project with development container setup.

## Getting Started

This project uses VS Code DevContainers for a consistent development environment.

### Prerequisites

- Docker Desktop
- VS Code with Remote-Containers extension

### Development Setup

1. Open this project in VS Code
2. When prompted, click "Reopen in Container"
3. Wait for the container to build (first time: ~5-10 minutes)
4. Start developing!

### Project Structure

\`\`\`
├── Controllers/         # API controllers
├── Models/             # Data models
├── Services/           # Business logic services
├── appsettings.json    # Configuration
├── Program.cs          # Application entry point
├── $PROJECT_NAME.csproj # Project file
└── README.md           # This file
\`\`\`

### Available Commands

- \`dotnet run\` - Run the application
- \`dotnet build\` - Build the project
- \`dotnet test\` - Run tests (when tests are added)
- \`dotnet restore\` - Restore NuGet packages

### API Documentation

When running in development mode, Swagger UI is available at:
- http://localhost:5000/swagger
- https://localhost:5001/swagger

### Sample Endpoints

- \`GET /WeatherForecast\` - Get weather forecast data

## Development

This project uses:

- .NET 8.0
- ASP.NET Core Web API
- Swagger/OpenAPI for documentation
- Built-in dependency injection

## License

This project is licensed under the MIT License.
EOF

# Create basic .gitignore
cat > .gitignore << EOF
## Ignore Visual Studio temporary files, build results, and
## files generated by popular Visual Studio add-ons.
##
## Get latest from https://github.com/github/gitignore/blob/master/VisualStudio.gitignore

# User-specific files
*.rsuser
*.suo
*.user
*.userosscache
*.sln.docstates

# Build results
[Dd]ebug/
[Dd]ebugPublic/
[Rr]elease/
[Rr]eleases/
x64/
x86/
[Aa][Rr][Mm]/
[Aa][Rr][Mm]64/
bld/
[Bb]in/
[Oo]bj/
[Ll]og/

# Visual Studio cache files
*.VC.db
*.VC.VC.opendb

# ASP.NET Scaffolding
ScaffoldingReadMe.txt

# NuGet Packages
*.nupkg
**/[Pp]ackages/*
!**/[Pp]ackages/build/

# Backup & report files from converting an old project file
_UpgradeReport_Files/
Backup*/
UpgradeLog*.XML
UpgradeLog*.htm

# SQL Server files
*.mdf
*.ldf
*.ndf

# JetBrains Rider
.idea/

# DevContainer
.devcontainer/docker-compose.override.yml
EOF

# Initialize project metadata
echo "📊 Initializing project metadata..."
if command -v initialize_project_metadata >/dev/null 2>&1; then
    if initialize_project_metadata "$PROJECT_PATH" "dotNetBench" "devBenches"; then
        echo "✅ Project metadata initialized successfully"
    else
        echo "⚠️  Warning: Failed to initialize project metadata"
    fi
else
    echo "⚠️  Warning: Metadata helper functions not available"
    echo "   Creating basic .workbench file..."
    cat > .workbench <<EOF
# WorkBench Project Metadata
bench_category=devBenches
bench_type=dotNetBench
created_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
created_by_user=$(whoami)
EOF
    echo "✅ Basic metadata file created"
fi

echo ""
echo "✅ .NET Web API project created successfully: $PROJECT_PATH"
echo ""
echo "📝 Next steps:"
echo "   1. cd $PROJECT_PATH"
echo "   2. code ."
echo "   3. When prompted, click 'Reopen in Container'"
echo "   4. Wait for container build (first time: ~5-10 minutes)"
echo "   5. Container will automatically:"
echo "      - Install .NET 8.0 SDK"
echo "      - Restore NuGet packages"
echo "      - Set up development environment"
echo ""
echo "🟣 Development commands:"
echo "   - dotnet run            : Run application"
echo "   - dotnet build          : Build project"
echo "   - dotnet test           : Run tests"
echo ""
echo "🌐 Application will be available at:"
echo "   - HTTP:  http://localhost:5000"
echo "   - HTTPS: https://localhost:5001"
echo "   - Swagger: http://localhost:5000/swagger"
echo ""
echo "🎯 Happy .NET Development with Spec-Driven Development!"