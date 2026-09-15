using ChatClient3.Services;

namespace ChatClient3.Pages;

public class ChatModel(ApimChatService chatService, IConfiguration configuration,
    ILogger<ChatModel> logger) : ChatPageModel(chatService, logger)
{
    protected override string SessionKey => "Conversation:Phi";
    public override string ModelName => configuration["Apim:PhiModel"] ?? "phi-4";
    public override string ChatTitle => "Phi";
    public override string PageRoute => "/Chat";
}
