using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace ChatClient2.Services;

// Property names intentionally match the original session JSON for mini history.
public record ChatTurn(string Role, string Content);

public sealed class ChatServiceException(string message) : Exception(message);

public sealed class MlflowChatService(IHttpClientFactory httpClientFactory,
    ILogger<MlflowChatService> logger)
{
    public const int MaxMessageLength = 8_000;
    public const int MaxReplyLength = 16_000;
    public const int MaxHistoryCharacters = 64_000;
    public const int MaxHistoryTurns = 20;

    public async Task<string> CompleteAsync(string model, IReadOnlyList<ChatTurn> conversation,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(model))
        {
            throw new ChatServiceException("This chat is not configured yet. Please try again later.");
        }

        var client = httpClientFactory.CreateClient("Mlflow");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        // Covers response-body reads as well as the initial HTTP request.
        timeout.CancelAfter(TimeSpan.FromSeconds(25));
        using var request = new HttpRequestMessage(HttpMethod.Post, "chat/completions")
        {
            Content = JsonContent.Create(new
            {
                model,
                messages = conversation.Select(turn => new { role = turn.Role, content = turn.Content }),
                max_completion_tokens = 4096,
                stream = false
            })
        };

        using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead,
            timeout.Token);
        if (!response.IsSuccessStatusCode)
        {
            // Never read, display, or log upstream error bodies (may contain secrets).
            logger.LogWarning("Chat upstream returned HTTP {StatusCode}.", (int)response.StatusCode);
            throw new ChatServiceException(response.StatusCode == HttpStatusCode.TooManyRequests
                ? "This model is busy right now. Please wait a moment and try again."
                : "The model is temporarily unavailable. Please try again later.");
        }

        // Bound untrusted responses before parsing, including chunked bodies.
        await response.Content.LoadIntoBufferAsync(1_048_576, timeout.Token);
        await using var stream = await response.Content.ReadAsStreamAsync(timeout.Token);
        using var document = await JsonDocument.ParseAsync(stream,
            new JsonDocumentOptions { MaxDepth = 32 }, timeout.Token);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object ||
            !root.TryGetProperty("choices", out var choices) ||
            choices.ValueKind != JsonValueKind.Array || choices.GetArrayLength() == 0 ||
            choices[0].ValueKind != JsonValueKind.Object ||
            !choices[0].TryGetProperty("message", out var message) ||
            message.ValueKind != JsonValueKind.Object ||
            !message.TryGetProperty("content", out var content) ||
            content.ValueKind != JsonValueKind.String)
        {
            throw new ChatServiceException("The model did not return a text reply. Please try again.");
        }

        var reply = content.GetString();
        if (string.IsNullOrWhiteSpace(reply) || reply.Length > MaxReplyLength)
        {
            throw new ChatServiceException("The reply was empty or too long. Please try a shorter request.");
        }

        return reply;
    }
}