using ChatClientLiteLLM.Services;

namespace ChatClientLiteLLM.Pages;

public class ChatModel(LiteLlmChatService chatService, IConfiguration configuration,
    ILogger<ChatModel> logger) : ChatPageModel(chatService, logger)
{
    protected override string SessionKey => "Conversation:Phi";
    public override string ModelName => configuration["LiteLLm:PhiModel"] ?? "phi-4";
    public override string ChatTitle => "Phi";
    public override string PageRoute => "/Chat";
}
