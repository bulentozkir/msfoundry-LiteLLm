using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ChatClient2.Pages;

public class ChatModel : PageModel
{
    private const string SessionKey = "Conversation";

    private readonly IHttpClientFactory _httpClientFactory;
    private readonly IConfiguration _configuration;
    private readonly ILogger<ChatModel> _logger;

    public ChatModel(IHttpClientFactory httpClientFactory, IConfiguration configuration, ILogger<ChatModel> logger)
    {
        _httpClientFactory = httpClientFactory;
        _configuration = configuration;
        _logger = logger;
    }

    public List<ChatTurn> Conversation { get; private set; } = new();

    public string ModelName => _configuration["LiteLLm:Model"] ?? "assistant";

    [TempData]
    public string? ErrorMessage { get; set; }

    public void OnGet()
    {
        Conversation = LoadConversation();
    }

    public async Task<IActionResult> OnPostAsync(string message)
    {
        Conversation = LoadConversation();

        if (string.IsNullOrWhiteSpace(message))
        {
            return RedirectToPage();
        }

        Conversation.Add(new ChatTurn("user", message));

        try
        {
            var reply = await CallLiteLlmAsync(Conversation);
            Conversation.Add(new ChatTurn("assistant", reply));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Call to LiteLLM failed");
            ErrorMessage = $"Could not reach LiteLLM: {ex.Message}";
        }

        SaveConversation(Conversation);
        return RedirectToPage();
    }

    private async Task<string> CallLiteLlmAsync(List<ChatTurn> conversation)
    {
        var client = _httpClientFactory.CreateClient("LiteLLM");

        var payload = new
        {
            model = ModelName,
            messages = conversation.Select(t => new { role = t.Role, content = t.Content })
        };

        using var response = await client.PostAsync(
            "chat/completions",
            new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json"));

        var body = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
        {
            throw new InvalidOperationException($"LiteLLM returned {(int)response.StatusCode}: {body}");
        }

        using var doc = JsonDocument.Parse(body);
        return doc.RootElement
            .GetProperty("choices")[0]
            .GetProperty("message")
            .GetProperty("content")
            .GetString() ?? "(empty response)";
    }

    private List<ChatTurn> LoadConversation()
    {
        var json = HttpContext.Session.GetString(SessionKey);
        if (string.IsNullOrEmpty(json))
        {
            return new List<ChatTurn>();
        }

        return JsonSerializer.Deserialize<List<ChatTurn>>(json) ?? new List<ChatTurn>();
    }

    private void SaveConversation(List<ChatTurn> conversation)
    {
        HttpContext.Session.SetString(SessionKey, JsonSerializer.Serialize(conversation));
    }

    public record ChatTurn(string Role, string Content);
}
