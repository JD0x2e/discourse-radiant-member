# frozen_string_literal: true
module Radiant
  # URIs for different chains
  @radiant_uri_arbitrum = "https://gateway-arbitrum.network.thegraph.com/api/[api-key]/subgraphs/id/E1UTUGaNbTb4XbEYoupJZ5hU62hW9CnadKTXLRSP2hM"
  @radiant_uri_bsc = "https://api.thegraph.com/subgraphs/name/radiantcapitaldevelopment/radiant-bsc"
  @radiant_uri_ethereum = "https://gateway-arbitrum.network.thegraph.com/api/[api-key]/subgraphs/id/683Qhh8TEta6qS5gdTpXCs84xnrp77fPWGQyBmRe6qgo"

  @radiant_uri_dlp_price_arbitrum = "https://gateway-arbitrum.network.thegraph.com/api/[api-key]/subgraphs/id/27aofQwkYx8ZLavxEhUDDsH9gSKSG1E1z9PFDsbzcrog"
  @radiant_uri_dlp_price_ethereum = "https://gateway-arbitrum.network.thegraph.com/api/[api-key]/subgraphs/id/29DtFfTWEyo2WGHVusN9Mq9zuVQo5VwfTweMwx9DWcf2"

  # Token addresses arbitrum
  @rdnt_token_address_arbitrum = '0x3082cc23568ea640225c2467653db90e9250aaa0'
  @dlp_token_address_arbitrum = '0x32dF62dc3aEd2cD6224193052Ce665DC18165841'

  # Token addresses bsc
  @rdnt_token_address_bsc = '0xf7de7e8a6bd59ed41a4b5fe50278b3b7f31384df'
  @dlp_token_address_bsc = '0x346575fC7f07E6994D76199E41D13dC1575322E1'

  # Token addresses ethereum
  @rdnt_token_address_ethereum = '0x137dDB47Ee24EaA998a535Ab00378d6BFa84F893'
  @dlp_token_address_ethereum = '0xcF7b51ce5755513d4bE016b0e28D6EDEffa1d52a'

  # MFD contract address
  @mfd_arbitrum = '0x76ba3eC5f5adBf1C58c91e86502232317EeA72dE'
  @mfd_bsc = '0x4FD9F7C5ca0829A656561486baDA018505dfcB5E'
  @mfd_ethereum = '0x28E395a54a64284DBA39652921Cd99924f4e3797'

  def self.get_siwe_address_by_username(username)
    user = User.find_by_username(username)
    return nil unless user
    get_siwe_address_by_user(user)
  end

  def self.get_siwe_address_by_user(user)
    siwe = user.associated_accounts.filter { |a| a[:name] == "siwe" }.first
    return nil unless siwe
    address_or_ens = siwe[:description].downcase
    puts "Got #{address_or_ens} for #{user.username}"
  
    # Check if the address is an ENS domain (ends with '.eth')
    if address_or_ens.end_with?('.eth')
      # If it's an ENS domain, resolve it to an Ethereum address
      resolved_address = resolve_ens_name(address_or_ens)
      if resolved_address
        resolved_address = resolved_address.downcase
        puts "Resolved #{address_or_ens} to #{resolved_address}"
        return resolved_address
      else
        puts "Failed to resolve #{address_or_ens}. Using original address."
        return address_or_ens
      end
    else
      # If not, return the original value
      return address_or_ens
    end
  end  
  
  def self.resolve_ens_name(ens_name)
    uri = URI.parse("https://api.ensideas.com/ens/resolve/#{ens_name}")
    response = Net::HTTP.get_response(uri)
  
    if response.is_a?(Net::HTTPSuccess)
      parsed_response = JSON.parse(response.body)
      return parsed_response['address'] # or whatever information you need
    else
      # Handle error
      puts "Failed to resolve ENS name: #{response.code} - #{response.message}"
      return nil
    end
  end

  def self.replace_api_key_placeholder(uri)
    return uri unless uri.include?("[api-key]")
    api_key = SiteSetting.radiant_subgraph_api_key
    uri.sub("[api-key]", api_key)
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

    siwe_address = get_siwe_address_by_user(user)
    return nil unless siwe_address
  
    # Define cache key for the total RDNT amount
    name_total = "radiant_user_total-#{user.id}"
    name_address = "siwe_address-#{user.id}"

    # Try fetching the cached values
    cached_total_value = Discourse.cache.read(name_total)
    cached_address_value = Discourse.cache.read(name_address)

    current_address = get_siwe_address_by_user(user)

    # Check if it's the first time (no cache data) or cache has expired, or the siwe address has changed
    if cached_total_value.nil? || cached_total_value == 0 || current_address != cached_address_value
      puts "No cached data, or SIWE address has changed. Fetching fresh data for #{user.username}"
      total_rdnt_amount = fetch_and_cache_rdnt_amount(user, name_total, name_address, current_address)
    else
      # Use the cached value
      puts "Using cached data for #{user.username}"
      total_rdnt_amount = cached_total_value
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

  def self.fetch_and_cache_rdnt_amount(user, cache_key_total, cache_key_address, current_address, force_refresh: false)
    if force_refresh || Discourse.cache.read(cache_key_total).nil? || current_address != Discourse.cache.read(cache_key_address)
        # Get amounts from all chains with the appropriate multipliers
        rdnt_amount_from_locked_and_loose_arbitrum = get_rdnt_amount_from_locked_and_loose_balance(user, @radiant_uri_arbitrum, @radiant_uri_dlp_price_arbitrum, SiteSetting.radiant_quicknode_arb, @rdnt_token_address_arbitrum, @dlp_token_address_arbitrum, 0.8)
        rdnt_amount_from_locked_and_loose_bsc = get_rdnt_amount_from_locked_and_loose_balance_bsc(user, @radiant_uri_bsc, SiteSetting.radiant_quicknode_bsc, @rdnt_token_address_bsc, @dlp_token_address_bsc, 0.5)
        rdnt_amount_from_locked_and_loose_ethereum = get_rdnt_amount_from_locked_and_loose_balance(user, @radiant_uri_ethereum, @radiant_uri_dlp_price_ethereum, SiteSetting.radiant_quicknode_eth, @rdnt_token_address_ethereum, @dlp_token_address_ethereum, 0.8)

        loose_rdnt_in_wallet_arbitrum = get_loose_rdnt_in_wallet_amount(user.username, SiteSetting.radiant_quicknode_arb, @rdnt_token_address_arbitrum)
        loose_rdnt_in_wallet_bsc = get_loose_rdnt_in_wallet_amount(user.username, SiteSetting.radiant_quicknode_bsc, @rdnt_token_address_bsc)
        loose_rdnt_in_wallet_ethereum = get_loose_rdnt_in_wallet_amount(user.username, SiteSetting.radiant_quicknode_eth, @rdnt_token_address_ethereum)

        fully_vested_rdnt_arbitrum = get_fully_vested_rdnt_amount(user.username, SiteSetting.radiant_quicknode_arb, @mfd_arbitrum)
        fully_vested_rdnt_bsc = get_fully_vested_rdnt_amount(user.username, SiteSetting.radiant_quicknode_bsc, @mfd_bsc)
        fully_vested_rdnt_ethereum = get_fully_vested_rdnt_amount(user.username, SiteSetting.radiant_quicknode_eth, @mfd_ethereum)

        # Convert nil to 0
        loose_rdnt_in_wallet_arbitrum = loose_rdnt_in_wallet_arbitrum || 0
        loose_rdnt_in_wallet_bsc = loose_rdnt_in_wallet_bsc || 0
        loose_rdnt_in_wallet_ethereum = loose_rdnt_in_wallet_ethereum || 0
        fully_vested_rdnt_arbitrum = fully_vested_rdnt_arbitrum || 0
        fully_vested_rdnt_bsc = fully_vested_rdnt_bsc || 0
        fully_vested_rdnt_ethereum = fully_vested_rdnt_ethereum || 0

        # Log the amounts fetched from each chain
        puts "rdnt_amount_from_locked_and_loose_arbitrum: #{rdnt_amount_from_locked_and_loose_arbitrum}"
        puts "rdnt_amount_from_locked_and_loose_bsc: #{rdnt_amount_from_locked_and_loose_bsc}"
        puts "rdnt_amount_from_locked_and_loose_ethereum: #{rdnt_amount_from_locked_and_loose_ethereum}"
        puts "loose_rdnt_in_wallet_arbitrum: #{loose_rdnt_in_wallet_arbitrum}"
        puts "loose_rdnt_in_wallet_bsc: #{loose_rdnt_in_wallet_bsc}"
        puts "loose_rdnt_in_wallet_ethereum: #{loose_rdnt_in_wallet_ethereum}"
        puts "fully_vested_rdnt_arbitrum: #{fully_vested_rdnt_arbitrum}"
        puts "fully_vested_rdnt_bsc: #{fully_vested_rdnt_bsc}"
        puts "fully_vested_rdnt_ethereum: #{fully_vested_rdnt_ethereum}"

        # Sum amounts from all chains and the wallet
        total_rdnt_amount = rdnt_amount_from_locked_and_loose_arbitrum.to_f + rdnt_amount_from_locked_and_loose_bsc.to_f + rdnt_amount_from_locked_and_loose_ethereum.to_f + loose_rdnt_in_wallet_arbitrum.to_f + loose_rdnt_in_wallet_bsc.to_f + loose_rdnt_in_wallet_ethereum.to_f + fully_vested_rdnt_arbitrum.to_f + fully_vested_rdnt_bsc.to_f + fully_vested_rdnt_ethereum.to_f

        # Cache the total RDNT amount and the siwe address
        Discourse.cache.write(cache_key_total, total_rdnt_amount, expires_in: SiteSetting.radiant_user_cache_minutes.minutes)
        Discourse.cache.write(cache_key_address, current_address, expires_in: SiteSetting.radiant_user_cache_minutes.minutes)

        total_rdnt_amount
    else
        # Read the cached value
        Discourse.cache.read(cache_key_total)
    end
  end
  
  def self.clear_rdnt_amount_cache_for_user(username)
    user = User.find_by_username(username)
    return unless user

    cache_key_total = "radiant_user_total-#{user.id}"
    cache_key_address = "siwe_address-#{user.id}"
  
    # Clearing the cached values
    Discourse.cache.delete(cache_key_total)
    Discourse.cache.delete(cache_key_address)
  end
  
  def self.get_loose_rdnt_in_wallet_amount(username, network_uri, rdnt_token_address)
    user = User.find_by_username(username)
    return nil unless user
  
    siwe_address = get_siwe_address_by_user(user)
    return nil unless siwe_address
  
    # Remove "0x" from the start of the siwe address
    siwe_address = siwe_address[2..-1] if siwe_address.start_with?("0x")
  
    uri = URI(network_uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
  
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
  
    # The data param should be 0x70a08231 followed by a 64 characters long hash with leading 0s followed by the user's siwe_address
    data_param = "0x70a08231000000000000000000000000#{siwe_address}"
  
    request.body = {
      "jsonrpc": "2.0",
      "method": "eth_call",
      "params": [{
        "to": rdnt_token_address,
        "data": data_param
      }, "latest"],
      "id": 1
    }.to_json
  
    response = http.request(request)
    result = JSON.parse(response.body)
  
    result_string = result['result'][2..-1]  # remove the "0x" from the beginning
  
    # Directly convert the hex to decimal and divide by 1e18
    loose_rdnt_wei = result_string.to_i(16)
    decimals = 10**18
    loose_rdnt_ether = BigDecimal(loose_rdnt_wei) / BigDecimal(decimals)
    loose_rdnt_ether.to_s('F')
  end  

  def self.get_fully_vested_rdnt_amount(username, network_uri, contract_address)
    user = User.find_by_username(username)
    return nil unless user
  
    siwe_address = get_siwe_address_by_user(user)
    return nil unless siwe_address
  
    # Remove "0x" from the start of the siwe address
    siwe_address = siwe_address[2..-1] if siwe_address.start_with?("0x")
  
    uri = URI(network_uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
  
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
  
    request.body = {
      "jsonrpc": "2.0",
      "method": "eth_call",
      "params": [{
        "to": contract_address,
        "data": "0xdf379876000000000000000000000000#{siwe_address}"
      }, "latest"],
      "id": 1
    }.to_json
  
    response = http.request(request)
    result = JSON.parse(response.body)
  
    result_string = result['result'][2..-1]  # remove the "0x" from the beginning
    hex_value = result_string.scan(/.{64}/)[1] # get the second section
  
    # Include the ether formatting within the main function
    unlocked_wei = hex_value.to_i(16)
    decimals = 10**18
    unlocked_ether = BigDecimal(unlocked_wei) / BigDecimal(decimals)
    unlocked_ether.to_s('F')
  end

  def self.get_lp_token_price(radiant_uri_dlp_price)
    radiant_uri_dlp_price = replace_api_key_placeholder(radiant_uri_dlp_price)
    
    uri = URI.parse(radiant_uri_dlp_price)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
  
    request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    request.body = {
      "query" => 'query Lock { lpTokenPrice(id: "1") { price } }'
    }.to_json
  
    response = http.request(request)
  
    # Check for a successful response
    if response.is_a?(Net::HTTPSuccess)
      parsed_body = JSON.parse(response.body)
      puts "got parsed_body: #{parsed_body}"
  
      # Check if the required data is in the response
      if parsed_body['data'] && parsed_body['data']['lpTokenPrice']
        lp_token_price = parsed_body['data']['lpTokenPrice']['price'].to_i
        lp_token_price
      else
        puts "lpTokenPrice not found in the response"
        nil
      end
    else
      # Handle error or return a default value
      puts "Failed to fetch lpTokenPrice: #{response.code} - #{response.message}"
      nil
    end
  end
  
  def self.get_rdnt_amount_from_locked_and_loose_balance(user, radiant_uri, radiant_uri_dlp_price, network_uri, rdnt_token_address, dlp_token_address, multiplier)
    radiant_uri = replace_api_key_placeholder(radiant_uri)
    radiant_uri_dlp_price = replace_api_key_placeholder(radiant_uri_dlp_price)
    
    begin
      puts "Fetching address.."
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
          'query Lock($address: String!) { lockeds(id: $address, where: {user_: {id: $address}}, orderBy: timestamp, orderDirection: desc, first: 1) { lockedBalance timestamp } }',
        "variables" => {
          "address" => address,
        },
      }.to_json
      req_options = { use_ssl: uri.scheme == "https" }
      puts "getting #{req} from #{radiant_uri} with #{address}"
      res = Net::HTTP.start(uri.hostname, uri.port, req_options) { |http| http.request(req) }
      # puts "got something #{res}"
      parsed_body = JSON.parse(res.body)
      puts "got parsed_body: #{parsed_body}"
  
      locked_balance = parsed_body["data"]["lockeds"][0]["lockedBalance"].to_i
      lp_token_price = get_lp_token_price(radiant_uri_dlp_price)
      lp_token_price_in_usd = lp_token_price / 1e8
      locked_balance_formatted = locked_balance / 1e18
      locked_balance_in_usd = locked_balance_formatted * lp_token_price_in_usd
      rdnt_amount_within_locked = (locked_balance_in_usd * multiplier) / price_of_rdnt_token
      puts "got #{rdnt_amount_within_locked} RDNT within locked dLP"
  
      # Now fetch the loose RDNT balance
      address = address[2..-1] if address.start_with?("0x")

      uri = URI(network_uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')

      # The data param should be 0x70a08231 followed by a 64 characters long hash with leading 0s followed by the user's address
      data_param = "0x70a08231000000000000000000000000#{address}"

      request.body = {
        "jsonrpc": "2.0",
        "method": "eth_call",
        "params": [{
          "to": dlp_token_address,
          "data": data_param
        }, "latest"],
        "id": 1
      }.to_json

      response = http.request(request)
      result = JSON.parse(response.body)

      result_string = result['result'][2..-1]  # remove the "0x" from the beginning

      # Directly convert the hex to decimal and divide by 1e18
      unlocked_wei = BigDecimal(result_string.to_i(16).to_s)
      decimals = BigDecimal(10)**18
      unlocked_ether = unlocked_wei / decimals

      loose_balance_in_usd = unlocked_ether * lp_token_price_in_usd
      rdnt_amount_within_loose = (loose_balance_in_usd * multiplier) / price_of_rdnt_token
      puts "got #{rdnt_amount_within_loose} RDNT within loose dLP"

      return (rdnt_amount_within_locked + rdnt_amount_within_loose).to_d.round(2, :truncate).to_f
      rescue => e
      puts "something went wrong getting locked and loose rdnt amounts #{e}"
      return 0
      end
  end
      
  def self.get_rdnt_amount_from_locked_and_loose_balance_bsc(user, radiant_uri, network_uri, rdnt_token_address, dlp_token_address, multiplier)
    # Append the API key if the placeholder is present
    if radiant_uri.include?("[api-key]")
      api_key = SiteSetting.radiant_subgraph_api_key
      radiant_uri = radiant_uri.sub("[api-key]", api_key)
    end
    
    begin
      puts "Fetching address.."
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
      # puts "got something #{res}"
      parsed_body = JSON.parse(res.body)
      puts "got parsed_body: #{parsed_body}"
  
      locked_balance = parsed_body["data"]["lockeds"][0]["lockedBalance"].to_i
      lp_token_price = parsed_body["data"]["lpTokenPrice"]["price"].to_i
      lp_token_price_in_usd = lp_token_price / 1e8
      locked_balance_formatted = locked_balance / 1e18
      locked_balance_in_usd = locked_balance_formatted * lp_token_price_in_usd
      rdnt_amount_within_locked = (locked_balance_in_usd * multiplier) / price_of_rdnt_token
      puts "got #{rdnt_amount_within_locked} RDNT within locked dLP"
  
      # Now fetch the loose RDNT balance
      address = address[2..-1] if address.start_with?("0x")

      uri = URI(network_uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      request = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')

      # The data param should be 0x70a08231 followed by a 64 characters long hash with leading 0s followed by the user's address
      data_param = "0x70a08231000000000000000000000000#{address}"

      request.body = {
        "jsonrpc": "2.0",
        "method": "eth_call",
        "params": [{
          "to": dlp_token_address,
          "data": data_param
        }, "latest"],
        "id": 1
      }.to_json

      response = http.request(request)
      result = JSON.parse(response.body)

      result_string = result['result'][2..-1]  # remove the "0x" from the beginning

      # Directly convert the hex to decimal and divide by 1e18
      unlocked_wei = BigDecimal(result_string.to_i(16).to_s)
      decimals = BigDecimal(10)**18
      unlocked_ether = unlocked_wei / decimals

      loose_balance_in_usd = unlocked_ether * lp_token_price_in_usd
      rdnt_amount_within_loose = (loose_balance_in_usd * multiplier) / price_of_rdnt_token
      puts "got #{rdnt_amount_within_loose} RDNT within loose dLP"

      return (rdnt_amount_within_locked + rdnt_amount_within_loose).to_d.round(2, :truncate).to_f
      rescue => e
      puts "something went wrong getting locked and loose rdnt amounts #{e}"
      return 0
      end
  end
end