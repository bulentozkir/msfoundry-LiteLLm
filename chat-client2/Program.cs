using ChatClient2.Services;

var builder = WebApplication.CreateBuilder(args);

// The MLflow gateway is now protected by HTTP Basic Auth (mlflow.server.auth -
// see terraform/mlflow-gateway-app.tf), so this client authenticates its own
// calls with the same admin credentials rather than relying on network
// restrictions alone.
builder.Services.AddRazorPages();
builder.Services.AddScoped<MlflowChatService>();

builder.Services.AddHttpClient("Mlflow", client =>
{
    var baseUrl = builder.Configuration["Mlflow:BaseUrl"]
        ?? throw new InvalidOperationException("Mlflow:BaseUrl is not configured.");
    client.BaseAddress = new Uri(baseUrl.TrimEnd('/') + "/");
    client.Timeout = TimeSpan.FromSeconds(25);
    var apiKey = builder.Configuration["Mlflow:ApiKey"];
    if (!string.IsNullOrEmpty(apiKey))
    {
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
    }
    var adminUsername = builder.Configuration["Mlflow:AdminUsername"];
    var adminPassword = builder.Configuration["Mlflow:AdminPassword"];
    if (!string.IsNullOrEmpty(adminUsername) && !string.IsNullOrEmpty(adminPassword))
    {
        var basicAuthValue = Convert.ToBase64String(
            System.Text.Encoding.UTF8.GetBytes($"{adminUsername}:{adminPassword}"));
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Basic", basicAuthValue);
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

