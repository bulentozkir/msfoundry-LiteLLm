using ChatClient3.Services;

var builder = WebApplication.CreateBuilder(args);

// Chat3 calls APIM Developer, which then routes to Foundry model endpoints.
builder.Services.AddRazorPages();
builder.Services.AddScoped<ApimChatService>();

builder.Services.AddHttpClient("Apim", client =>
{
    var baseUrl = builder.Configuration["Apim:BaseUrl"]
        ?? throw new InvalidOperationException("Apim:BaseUrl is not configured.");
    client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(25);

    var subscriptionKey = builder.Configuration["Apim:SubscriptionKey"];
    if (!string.IsNullOrEmpty(subscriptionKey))
    {
        client.DefaultRequestHeaders.Remove("Ocp-Apim-Subscription-Key");
        client.DefaultRequestHeaders.TryAddWithoutValidation(
            "Ocp-Apim-Subscription-Key", subscriptionKey);
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

