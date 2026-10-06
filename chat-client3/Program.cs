using ChatClient3.Services;

var builder = WebApplication.CreateBuilder(args);

// Chat3 calls the APIM AI Gateway, which routes to Foundry model deployments.
builder.Services.AddRazorPages();
builder.Services.AddScoped<ApimChatService>();

builder.Services.AddHttpClient("Apim", client =>
{
    var baseUrl = builder.Configuration["Apim:BaseUrl"]
        ?? throw new InvalidOperationException("Apim:BaseUrl is not configured.");
    client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(25);

    var gatewayKey = builder.Configuration["Apim:GatewayKey"];
    if (!string.IsNullOrEmpty(gatewayKey))
    {
        client.DefaultRequestHeaders.Remove("api-key");
        client.DefaultRequestHeaders.TryAddWithoutValidation(
            "api-key", gatewayKey);
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

