using ChatClient3.Services;

namespace ChatClient3.Pages;

public class ChatDeepSeekModel(ApimChatService chatService, IConfiguration configuration,
    ILogger<ChatDeepSeekModel> logger) : ChatPageModel(chatService, logger)
{
    protected override string SessionKey => "Conversation:DeepSeek";
    public override string ModelName => configuration["Apim:DeepSeekModel"] ?? "FW-DeepSeek-V4.1-Flash";
    public override string ChatTitle => "DeepSeek";
    public override string PageRoute => "/ChatDeepSeek";
}