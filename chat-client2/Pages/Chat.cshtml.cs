using ChatClient2.Services;

namespace ChatClient2.Pages;

public class ChatModel(MlflowChatService chatService, IConfiguration configuration,
    ILogger<ChatModel> logger) : ChatPageModel(chatService, logger)
{
    protected override string SessionKey => "Conversation:Phi";
    public override string ModelName => configuration["Mlflow:PhiModel"] ?? "phi-4";
    public override string ChatTitle => "Phi";
    public override string PageRoute => "/Chat";
}
