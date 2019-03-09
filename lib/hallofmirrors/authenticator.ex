defmodule Hallofmirrors.Authenticator do
  def create_oauth(instance) do
    query_string =
      %{}
      |> Map.put("client_name", "hall-of-mirrors-#{:random.uniform()}")
      |> Map.put("redirect_uris", "urn:ietf:wg:oauth:2.0:oob")
      |> Map.put("scopes", "read write")
      |> URI.encode_query()

    query_uri =
      instance.url
      |> URI.merge("/api/v1/apps")
      |> URI.to_string()

    headers = %{"Content-Type" => "application/x-www-form-urlencoded"}

    case HTTPoison.post(query_uri, query_string, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body} = Jason.decode(body)
        %{"client_id" => client_id, "client_secret" => client_secret} = body

        {:ok, client_id, client_secret}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, body}
    end
  end

  def login(instance, username, password) do
    query_string =
      %{}
      |> Map.put("client_id", instance.client_id)
      |> Map.put("client_secret", instance.client_secret)
      |> Map.put("username", username)
      |> Map.put("password", password)
      |> Map.put("grant_type", "password")
      |> Map.put("scope", "read write")
      |> URI.encode_query()

    query_uri =
      instance.url
      |> URI.merge("/oauth/token")
      |> URI.to_string()

    headers = %{"Content-Type" => "application/x-www-form-urlencoded"}

    case HTTPoison.post(query_uri, query_string, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body} = Jason.decode(body)
          %{"token_type" => token_type, "access_token" => access_token} = body
          token = "#{token_type} #{access_token}"
          {:ok, token}

      {:ok, %HTTPoison.Response{status_code: code, body: body}} ->
        {:error, body}
    end
  end
end
