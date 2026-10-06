using ChatClient2.Services;

namespace ChatClient2.Pages;

public class ChatDeepSeekModel(MlflowChatService chatService, IConfiguration configuration,
    ILogger<ChatDeepSeekModel> logger) : ChatPageModel(chatService, logger)
{
    protected override string SessionKey => "DeepSeekConversation";
    public override string ModelName => configuration["Mlflow:DeepSeekModel"] ?? "FW-DeepSeek-V4.1-Flash";
    public override string ChatTitle => "DeepSeek";
    public override string PageRoute => "/ChatDeepSeek";
}