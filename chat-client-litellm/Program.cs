using ChatClientLiteLLM.Services;

var builder = WebApplication.CreateBuilder(args);

// chat1 calls a dedicated LiteLLM proxy (OpenAI-compatible /v1 API) hosted on
// its own Container Apps deployment.
builder.Services.AddRazorPages();
builder.Services.AddScoped<LiteLlmChatService>();

builder.Services.AddHttpClient("LiteLLM", client =>
{
    var baseUrl = builder.Configuration["LiteLLm:BaseUrl"]
        ?? throw new InvalidOperationException("LiteLLm:BaseUrl is not configured.");
    client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(25);
    var apiKey = builder.Configuration["LiteLLm:ApiKey"];
    if (!string.IsNullOrEmpty(apiKey))
    {
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
    }
}).ConfigurePrimaryHttpMessageHandler(() => new HttpClientHandler
{
    AllowAutoRedirect = false
});

builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Error");
    // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
    app.UseHsts();
}

app.UseHttpsRedirection();

app.UseRouting();

app.UseSession();

app.UseAuthorization();

app.MapStaticAssets();
app.MapRazorPages()
   .WithStaticAssets();

app.Run();

