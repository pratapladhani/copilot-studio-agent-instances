// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

using Microsoft.Agents.Builder;
using Microsoft.Agents.Hosting.AspNetCore;
using Microsoft.Agents.Storage;
using Microsoft.Agents.Storage.Transcript;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using OBOAuthorization;
using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

// Add Application Insights telemetry
builder.Services.AddApplicationInsightsTelemetry();

builder.Services.AddHttpClient();

// Add AgentApplicationOptions from appsettings section "AgentApplication".
builder.AddAgentApplicationOptions();

// Add the AgentApplication, which contains the logic for responding to
// user messages.
builder.AddAgent<AgenticRelay>();

// Register IStorage.  For development, MemoryStorage is suitable.
// For production Agents, persisted storage should be used so
// that state survives Agent restarts, and operates correctly
// in a cluster of Agent instances.
builder.Services.AddSingleton<IStorage, MemoryStorage>();

// Configure the HTTP request pipeline.

// Add AspNet token validation for Azure Bot Service and Entra.  Authentication is
// configured in the appsettings.json "TokenValidation" section.
builder.Services.AddControllers();
builder.Services.AddAgentAspNetAuthentication(builder.Configuration);
builder.Services.AddSingleton<Microsoft.Agents.Builder.IMiddleware[]>([new TranscriptLoggerMiddleware(new FileTranscriptLogger())]);

WebApplication app = builder.Build();

// Add request logging middleware - only log /api/messages requests
app.Use(async (context, next) =>
{
    var logger = context.RequestServices.GetRequiredService<ILogger<Program>>();

    // Only log POST to /api/messages (skip health checks and GET requests)
    if (context.Request.Method == "POST" && context.Request.Path.StartsWithSegments("/api/messages"))
    {
        logger.LogInformation("========================================");
        logger.LogInformation(">>> BOT MESSAGE RECEIVED <<<");
        logger.LogInformation("========================================");

        // Read and log the body
        context.Request.EnableBuffering();
        using var reader = new StreamReader(context.Request.Body, Encoding.UTF8, leaveOpen: true);
        var body = await reader.ReadToEndAsync();
        context.Request.Body.Position = 0;

        if (!string.IsNullOrEmpty(body))
        {
            // Parse and show key fields
            try
            {
                var json = System.Text.Json.JsonDocument.Parse(body);
                var root = json.RootElement;
                var type = root.TryGetProperty("type", out var t) ? t.GetString() : "unknown";
                var text = root.TryGetProperty("text", out var tx) ? tx.GetString() : "";
                var channelId = root.TryGetProperty("channelId", out var ch) ? ch.GetString() : "unknown";
                var from = root.TryGetProperty("from", out var f) && f.TryGetProperty("name", out var fn) ? fn.GetString() : "unknown";

                logger.LogInformation("  Channel: {Channel}", channelId);
                logger.LogInformation("  Type: {Type}", type);
                logger.LogInformation("  From: {From}", from);
                logger.LogInformation("  Text: {Text}", text);
            }
            catch
            {
                var logBody = body.Length > 300 ? body.Substring(0, 300) + "..." : body;
                logger.LogInformation("  Body: {Body}", logBody);
            }
        }
    }

    await next();

    if (context.Request.Method == "POST" && context.Request.Path.StartsWithSegments("/api/messages"))
    {
        logger.LogInformation("<<< Response: {StatusCode}", context.Response.StatusCode);
        logger.LogInformation("========================================");
    }
});

// Enable AspNet authentication and authorization
app.UseAuthentication();
app.UseAuthorization();

app.MapGet("/", () => "Microsoft Agents SDK Sample");

// This receives incoming messages from Azure Bot Service or other SDK Agents
var incomingRoute = app.MapPost("/api/messages", async (HttpRequest request, HttpResponse response, IAgentHttpAdapter adapter, IAgent agent, CancellationToken cancellationToken) =>
{
    await adapter.ProcessAsync(request, response, agent, cancellationToken);
});

if (!app.Environment.IsDevelopment())
{
    incomingRoute.RequireAuthorization();
}
else
{
    // Hardcoded for brevity and ease of testing. 
    // In production, this should be set in configuration.
    app.Urls.Add($"http://localhost:3978");
}

app.Run();
