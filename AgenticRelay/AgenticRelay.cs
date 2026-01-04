using AgentNotification;
using Microsoft.Agents.A365.Notifications.Models;
using Microsoft.Agents.Builder;
using Microsoft.Agents.Builder.App;
using Microsoft.Agents.Builder.State;
using Microsoft.Agents.CopilotStudio.Client;
using Microsoft.Agents.Core.Models;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace OBOAuthorization
{
    public class AgenticRelay : AgentApplication
    {
        private readonly IConfiguration _configuration;
        private readonly IServiceProvider _serviceProvider;
        private readonly ILogger<AgenticRelay> _logger;
        private const string MCSConversationPropertyName = "MCSConversationId8";

        public AgenticRelay(AgentApplicationOptions options, IServiceProvider service, IConfiguration configuration, ILogger<AgenticRelay> logger) : base(options)
        {
            _configuration = configuration;
            _serviceProvider = service;
            _logger = logger;
            RegisterExtension(new AgentNotification.AgentNotification(this), a365 =>
            {
                a365.OnAgentNotification("*", OnAgentNotification, autoSignInHandlers: ["agentic"]);
            });
            // isAgenticOnly: true means only Agent User messages are processed
            OnActivity(ActivityTypes.Message, OnGeneralActivity, isAgenticOnly: true, autoSignInHandlers: ["agentic"]);
        }

        private async Task OnAgentNotification(ITurnContext turnContext, ITurnState turnState, AgentNotificationActivity agentNotificationActivity, CancellationToken cancellationToken)
        {
            string response = string.Empty;
            switch (agentNotificationActivity.NotificationType)
            {
                case NotificationTypeEnum.WpxComment:
                    // handle Word/PowerPoint/Excel comment notification - relay to MCS. 
                    response = await RelayToMCS(turnContext, turnState, agentNotificationActivity.WpxCommentNotification, cancellationToken);
                    await turnContext.SendActivityAsync(MessageFactory.CreateMessageActivity(response));
                    break;
                case NotificationTypeEnum.EmailNotification:
                    response = await RelayToMCS(turnContext, turnState, agentNotificationActivity.EmailNotification, cancellationToken);
                    if (!string.IsNullOrEmpty(response))
                    {
                        await turnContext.SendActivityAsync(EmailResponse.CreateEmailResponseActivity(response));
                    }
                    break;
                case NotificationTypeEnum.Unknown:
                case NotificationTypeEnum.FederatedKnowledgeServiceNotification:
                case NotificationTypeEnum.AgentLifecycleNotification:
                default:
                    // Not supported notification types.
                    break;
            }
        }

        private async Task OnGeneralActivity(ITurnContext turnContext, ITurnState turnState, CancellationToken cancellationToken)
        {
            _logger.LogInformation("[RELAY] OnGeneralActivity started - Channel: {Channel}, From: {From}",
                turnContext.Activity.ChannelId, turnContext.Activity.From?.Name);

            try
            {
                // relaying teams messages to MCS Agent
                var responseText = await RelayToMCS(turnContext, turnState, turnContext.Activity.Attachments, cancellationToken);

                _logger.LogInformation("[RELAY] RelayToMCS completed - Response length: {Length}", responseText?.Length ?? 0);

                if (!string.IsNullOrEmpty(responseText))
                {
                    var messageActivity = MessageFactory.CreateMessageActivity(responseText);
                    messageActivity.TextFormat = "markdown";
                    _logger.LogInformation("[RELAY] Sending response back to Teams: {Response}", responseText.Substring(0, Math.Min(100, responseText.Length)));
                    await turnContext.SendActivityAsync(messageActivity, cancellationToken);
                    _logger.LogInformation("[RELAY] Response sent successfully to Teams");
                }
                else
                {
                    _logger.LogWarning("[RELAY] No response received from Copilot Studio");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[RELAY] Error in OnGeneralActivity: {Message}", ex.Message);
                throw;
            }
        }

        private async Task<string> RelayToMCS(ITurnContext context, ITurnState turnState, Object? notificationMetadata, CancellationToken cancellationToken)
        {
            _logger.LogInformation("[MCS] RelayToMCS started");

            var mcsConversationId = turnState.Conversation.GetValue<string>(MCSConversationPropertyName);
            _logger.LogInformation("[MCS] Existing conversation ID: {ConversationId}", mcsConversationId ?? "null");

            CopilotClient cpsClient;
            try
            {
                cpsClient = GetClient(context, "agentic");
                _logger.LogInformation("[MCS] CopilotClient created successfully");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[MCS] Failed to create CopilotClient: {Message}", ex.Message);
                throw;
            }

            StringBuilder responseText = new();

            if (string.IsNullOrEmpty(mcsConversationId))
            {
                _logger.LogInformation("[MCS] Starting new conversation with Copilot Studio...");
                try
                {
                    // Regardless of the Activity Type, start the conversation.
                    await foreach (IActivity activity in cpsClient.StartConversationAsync(emitStartConversationEvent: false, cancellationToken: cancellationToken))
                    {
                        _logger.LogInformation("[MCS] StartConversation received activity type: {Type}", activity.Type);
                        if (activity.IsType(ActivityTypes.Message))
                        {
                            responseText.AppendLine(activity.Text);
                        }
                        if (activity.Conversation != null && !string.IsNullOrEmpty(activity.Conversation.Id))
                        {
                            mcsConversationId = activity.Conversation.Id;
                            turnState.Conversation.SetValue(MCSConversationPropertyName, mcsConversationId);
                            _logger.LogInformation("[MCS] Got conversation ID: {ConversationId}", mcsConversationId);
                        }
                    }
                    _logger.LogInformation("[MCS] StartConversation completed");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "[MCS] StartConversation failed: {Message}", ex.Message);
                    throw;
                }
            }

            if (context.Activity.IsType(ActivityTypes.Message))
            {
                _logger.LogInformation("[MCS] Sending message to Copilot Studio: {Text}", context.Activity.Text?.Substring(0, Math.Min(50, context.Activity.Text?.Length ?? 0)));

                // Set the conversation ID. 
                IActivity activityToSend = context.Activity.Clone();
                activityToSend.Conversation = new ConversationAccount(id: mcsConversationId);

                //serialize and prepend notification metadata if any; wrap the notification metadata in <info></info> tags to indicate it's system info
                if (notificationMetadata != null)
                {
                    var serializedMetadata = System.Text.Json.JsonSerializer.Serialize(notificationMetadata);
                    activityToSend.Text = $"<info>notification metadata:{serializedMetadata}</info>\n{activityToSend.Text}";
                }

                // now do the same for the sender info in the activity by adding it as <info></info> tags
                var serializedSender = System.Text.Json.JsonSerializer.Serialize(context.Activity.From);
                activityToSend.Text = $"<info>sender:{serializedSender}</info>\n{activityToSend.Text}";

                try
                {
                    // Send the Copilot Studio Agent whatever the sent and send the responses back.
                    int activityCount = 0;
                    await foreach (IActivity activity in cpsClient.SendActivityAsync(activityToSend, cancellationToken))
                    {
                        activityCount++;
                        _logger.LogInformation("[MCS] SendActivity received activity #{Count} type: {Type}", activityCount, activity.Type);

                        if (activity.IsType(ActivityTypes.Message))
                        {
                            if (activity.Text != null)
                            {
                                _logger.LogInformation("[MCS] Got message response: {Text}", activity.Text.Substring(0, Math.Min(100, activity.Text.Length)));
                                responseText.AppendLine(activity.Text);
                            }
                        }

                        if (activity.Conversation != null && !string.IsNullOrEmpty(activity.Conversation.Id))
                        {
                            // Update the conversation ID in case it has changed.
                            turnState.Conversation.SetValue(MCSConversationPropertyName, activity.Conversation.Id);
                        }
                    }
                    _logger.LogInformation("[MCS] SendActivity completed - received {Count} activities", activityCount);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "[MCS] SendActivity failed: {Message}", ex.Message);
                    throw;
                }
            }

            _logger.LogInformation("[MCS] RelayToMCS completed - total response length: {Length}", responseText.Length);
            return responseText.ToString();
        }

        private CopilotClient GetClient(ITurnContext turnContext, string authHandlerName)
        {
            var settings = new ConnectionSettings(_configuration.GetSection("CopilotStudioAgent"));
            _logger.LogInformation("[MCS] ConnectionSettings - DirectConnectUrl: {Url}", settings.DirectConnectUrl);

            string[] scopes = [CopilotClient.ScopeFromSettings(settings)];
            _logger.LogInformation("[MCS] Scopes for token exchange: {Scopes}", string.Join(", ", scopes));

            return new CopilotClient(
                settings,
                _serviceProvider.GetService<IHttpClientFactory>()!,
                tokenProviderFunction: async (s) =>
                {
                    _logger.LogInformation("[MCS] Token provider called - exchanging token for scopes: {Scopes}", string.Join(", ", scopes));
                    try
                    {
                        var token = await UserAuthorization.ExchangeTurnTokenAsync(turnContext, authHandlerName, exchangeScopes: scopes);
                        _logger.LogInformation("[MCS] Token exchange successful - token length: {Length}", token?.Length ?? 0);
                        return token ?? throw new InvalidOperationException("Token exchange returned null");
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "[MCS] Token exchange failed: {Message}", ex.Message);
                        throw;
                    }
                },
                _serviceProvider.GetService<ILogger<CopilotClient>>()!,
                "mcs");
        }

    }
}
