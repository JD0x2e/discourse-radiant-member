# frozen_string_literal: true
module Radiant
  # URIs for different chains
  @radiant_uri_arbitrum = "https://api.thegraph.com/subgraphs/name/radiantcapitaldevelopment/radiantcapital"
  @radiant_uri_bsc = "https://api.thegraph.com/subgraphs/name/radiantcapitaldevelopment/radiant-bsc"

  # Covalent API URL
  @covalent_api_url_arbitrum = "https://api.covalenthq.com/v1/42161/address"
  @covalent_api_url_bsc = "https://api.covalenthq.com/v1/56/address"

  # Token addresses
  @rdnt_token_address_arbitrum = '0x3082cc23568ea640225c2467653db90e9250aaa0'
  @rdnt_token_address_bsc = '0xf7de7e8a6bd59ed41a4b5fe50278b3b7f31384df'

  def self.get_siwe_address_by_username(username)
    user = User.find_by_username(username)
    return nil unless user
    get_siwe_address_by_user(user)
  end

  def self.get_siwe_address_by_user(user)
    siwe = user.associated_accounts.filter { |a| a[:name] == "siwe" }.first
    return nil unless siwe
    address = siwe[:description].downcase
    puts "Got #{address} for #{user.username}"
    address
  end

  def self.price_of_rdnt_token
    name = "radiant_dollar_value"
    Discourse
      .cache
      .fetch(name, expires_in: SiteSetting.radiant_dollar_cache_minutes.minutes) do
        begin
          result =
            Excon.get(
              "https://api.coingecko.com/api/v3/simple/price?ids=radiant-capital&vs_currencies=usd&include_last_updated_at=true&precision=3",
              connect_timeout: 3,
            )
          parsed = JSON.parse(result.body)
          price = parsed["radiant-capital"]["usd"]
        rescue => e
          puts "problem getting dollar amount"
        end
        price
      end
  end

  def self.get_rdnt_amount_by_username(username)
    user = User.find_by_username(username)
    return nil unless user
    get_rdnt_amount(user)
  end

  def self.get_rdnt_amount(user)
    puts "now getting amount for #{user.username}"
  
    # Define cache key for the total RDNT amount
    name_total = "radiant_user_total-#{user.id}"

    # Try fetching the cached value
    cached_value = Discourse.cache.read(name_total)

    # Check if it's the first time (no cache data) or cache has expired
    if cached_value.nil? || cached_value == 0
      puts "No cached data, fetching fresh data for #{user.username}"
      total_rdnt_amount = fetch_and_cache_rdnt_amount(user, name_total)
    else
      # Use the cached value
      puts "Using cached data for #{user.username}"
      total_rdnt_amount = cached_value
    end

    # Update groups
    SiteSetting.radiant_group_values.split("|").each do |g|
      group_name, required_amount = g.split(":")
      group = Group.find_by_name(group_name)
      next unless group
      puts "Processing group #{group.name}"
      if total_rdnt_amount > required_amount.to_i
        puts "adding #{user.username} to #{group.name}"
        group.add(user)
      else
        puts "removing #{user.username} from #{group.name}"
        group.remove(user)
      end
    end
  
    # Log the final total RDNT amount
    puts "now returning #{total_rdnt_amount} for #{user.username}"
    total_rdnt_amount.to_d.round(2, :truncate).to_f
  end

  def self.fetch_and_cache_rdnt_amount(user, cache_key)
    # Get amounts from both chains with the appropriate multipliers
    rdnt_amount_arbitrum = get_rdnt_amount_from_chain(user, @radiant_uri_arbitrum, 0.8)
    rdnt_amount_bsc = get_rdnt_amount_from_chain(user, @radiant_uri_bsc, 0.5)
    loose_rdnt_in_wallet_arbitrum = get_loose_rdnt_in_wallet_amount(user.username, @covalent_api_url_arbitrum, @rdnt_token_address_arbitrum)
    loose_rdnt_in_wallet_bsc = get_loose_rdnt_in_wallet_amount(user.username, @covalent_api_url_bsc, @rdnt_token_address_bsc)

    # Check if the RDNT token was found or not
    if loose_rdnt_in_wallet_arbitrum == "RDNT token not found in wallet"
      puts "RDNT token not found in Arbitrum wallet for #{user.username}"
      loose_rdnt_in_wallet_arbitrum = 0
    end

    if loose_rdnt_in_wallet_bsc == "RDNT token not found in BSC wallet for #{user.username}"
      puts "RDNT token not found in BSC wallet for #{user.username}"
      loose_rdnt_in_wallet_bsc = 0
    end

    # Log the amounts fetched from each chain
    puts "rdnt_amount_arbitrum: #{rdnt_amount_arbitrum}"
    puts "rdnt_amount_bsc: #{rdnt_amount_bsc}"
    puts "loose_rdnt_in_wallet_arbitrum: #{loose_rdnt_in_wallet_arbitrum}"
    puts "loose_rdnt_in_wallet_bsc: #{loose_rdnt_in_wallet_bsc}"

    # Sum amounts from both chains and the wallet
    total_rdnt_amount = rdnt_amount_arbitrum + rdnt_amount_bsc + loose_rdnt_in_wallet_arbitrum + loose_rdnt_in_wallet_bsc

    # Cache the total RDNT amount
    Discourse.cache.write(cache_key, total_rdnt_amount, expires_in: SiteSetting.radiant_user_cache_minutes.minutes)

    total_rdnt_amount
  end

  def self.get_loose_rdnt_in_wallet_amount(username, covalent_api_url, rdnt_token_address)
    user = User.find_by_username(username)
    return nil unless user
    
    siwe_address = get_siwe_address_by_user(user)
    return nil unless siwe_address

    # Get the API key from the site settings
    api_key = SiteSetting.radiant_covalent_api_key

    # Make sure you have a valid API key before proceeding
    return nil if api_key.empty?
    
    url = "#{covalent_api_url}/#{siwe_address}/balances_v2/?&key=#{api_key}"
    uri = URI(url)
    response = Net::HTTP.get(uri)
    data = JSON.parse(response)
    items = data['data']['items']
    
    rdnt_token = items.find { |item| item['contract_address'].downcase == rdnt_token_address.downcase }
    if rdnt_token
      balance_in_wei = rdnt_token['balance'].to_i
      balance_in_token = balance_in_wei / 1.0e18
      balance_in_token
    else
      0
    end
  end
    
  def self.get_rdnt_amount_from_chain(user, radiant_uri, multiplier)
    begin
      puts "getting address"
      address = get_siwe_address_by_user(user)
      if address.nil?
        puts "User has not connected their wallet."
        return 0
      end
      uri = URI(radiant_uri)
      req = Net::HTTP::Post.new(uri)
      req.content_type = "application/json"
      req.body = {
        "query" =>
          'query Lock($address: String!) { lockeds(id: $address, where: {user_: {id: $address}}, orderBy: timestamp, orderDirection: desc, first: 1) { lockedBalance timestamp } lpTokenPrice(id: "1") { price } }',
        "variables" => {
          "address" => address,
        },
      }.to_json
      req_options = { use_ssl: uri.scheme == "https" }
      puts "getting #{req} from #{radiant_uri} with #{address}"
      res = Net::HTTP.start(uri.hostname, uri.port, req_options) { |http| http.request(req) }
      puts "got something #{res}"
      parsed_body = JSON.parse(res.body)
      puts "got parsed_body: #{parsed_body}"
  
      locked_balance = parsed_body["data"]["lockeds"][0]["lockedBalance"].to_i
      lp_token_price = parsed_body["data"]["lpTokenPrice"]["price"].to_i
      lp_token_price_in_usd = lp_token_price / 1e8
      locked_balance_formatted = locked_balance / 1e18
      locked_balance_in_usd = locked_balance_formatted * lp_token_price_in_usd
      rdnt_amount = (locked_balance_in_usd * multiplier) / price_of_rdnt_token
      puts "got #{rdnt_amount}"
    rescue => e
      puts "something went wrong getting rdnt amount #{e}"
      return 0
    end
    rdnt_amount.to_d.round(2, :truncate).to_f
  end
end