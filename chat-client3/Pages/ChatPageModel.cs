using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using ChatClient3.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ChatClient3.Pages;

[ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
[RequestSizeLimit(131_072)]
[RequestFormLimits(ValueLengthLimit = 32_000, ValueCountLimit = 16)]
public abstract class ChatPageModel(ApimChatService chatService, ILogger logger) : PageModel
{
    protected abstract string SessionKey { get; }
    public abstract string ModelName { get; }
    public abstract string ChatTitle { get; }
    public abstract string PageRoute { get; }
    public List<ChatTurn> Conversation { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

    [BindProperty]
    [Required(ErrorMessage = "Enter a message to send.")]
    [StringLength(ApimChatService.MaxMessageLength,
        ErrorMessage = "Keep your message to 8,000 characters or fewer.")]
    public string Message { get; set; } = "";

    public async Task OnGetAsync()
    {
        await LoadConversationAsync();
    }

    public async Task<IActionResult> OnPostAsync()
    {
        await LoadConversationAsync();
        if (!ModelState.IsValid)
        {
            return Page();
        }

        var pending = new List<ChatTurn>(Conversation) { new("user", Message.Trim()) };
        TrimConversation(pending);
        try
        {
            var reply = await chatService.CompleteAsync(ModelName, pending, HttpContext.RequestAborted);
            pending.Add(new ChatTurn("assistant", reply));
            TrimConversation(pending);
            HttpContext.Session.SetString(SessionKey, JsonSerializer.Serialize(pending));
            await HttpContext.Session.CommitAsync(HttpContext.RequestAborted);
            return RedirectToPage(PageRoute);
        }
        catch (OperationCanceledException) when (HttpContext.RequestAborted.IsCancellationRequested)
        {
            // The browser disconnected; do not save a partial conversation.
            return new EmptyResult();
        }
        catch (OperationCanceledException)
        {
            ErrorMessage = "The model took too long to reply. Your message is still here; please try again.";
        }
        catch (ChatServiceException exception)
        {
            ErrorMessage = exception.Message;
        }
        catch (Exception exception) when (exception is HttpRequestException or JsonException
            or InvalidOperationException or ArgumentException or IOException)
        {
            // Log only the exception type, never messages, prompts, keys, or response bodies.
            logger.LogWarning("Chat request failed ({FailureType}).", exception.GetType().Name);
            ErrorMessage = "Chat is temporarily unavailable. Your message has not been sent successfully; please try again later.";
        }

        // Render errors and the draft directly; successful sends use POST/Redirect/GET.
        return Page();
    }

    public async Task<IActionResult> OnPostClearAsync()
    {
        await HttpContext.Session.LoadAsync(HttpContext.RequestAborted);
        HttpContext.Session.Remove(SessionKey);
        await HttpContext.Session.CommitAsync(HttpContext.RequestAborted);
        return RedirectToPage(PageRoute);
    }

    private async Task LoadConversationAsync()
    {
        await HttpContext.Session.LoadAsync(HttpContext.RequestAborted);
        var json = HttpContext.Session.GetString(SessionKey);
        if (string.IsNullOrEmpty(json)) return;

        try
        {
            // Also bounds legacy or malformed session data before deserialization.
            if (json.Length > 1_048_576) throw new JsonException();
            var saved = JsonSerializer.Deserialize<List<ChatTurn?>>(json) ?? [];
            Conversation = saved
                .Where(turn => turn is not null && (turn.Role is "user" or "assistant")
                    && !string.IsNullOrWhiteSpace(turn.Content)
                    && turn.Content.Length <= ApimChatService.MaxReplyLength)
                .Select(turn => turn!)
                .ToList();
            TrimConversation(Conversation);
        }
        catch (JsonException)
        {
            HttpContext.Session.Remove(SessionKey);
            ErrorMessage = "This conversation could not be restored. You can start a new one below.";
        }
    }

    private static void TrimConversation(List<ChatTurn> turns)
    {
        var characters = turns.Sum(turn => turn.Content.Length);
        while (turns.Count > ApimChatService.MaxHistoryTurns ||
            characters > ApimChatService.MaxHistoryCharacters)
        {
            characters -= turns[0].Content.Length;
            turns.RemoveAt(0);
        }
        // Do not send an orphaned assistant reply after removing old turns.
        while (turns.Count > 0 && turns[0].Role != "user") turns.RemoveAt(0);
    }
}