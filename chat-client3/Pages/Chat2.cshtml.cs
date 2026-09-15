using ChatClient3.Services;

namespace ChatClient3.Pages;

public class Chat2Model(ApimChatService chatService, IConfiguration configuration,
    ILogger<Chat2Model> logger) : ChatPageModel(chatService, logger)
{
    // Preserve the original mini conversation's JSON shape and session key.
    protected override string SessionKey => "Conversation";
    public override string ModelName => configuration["Apim:Model"] ?? "gpt-5.4-mini";
    public override string ChatTitle => "Mini";
    public override string PageRoute => "/Chat2";
}