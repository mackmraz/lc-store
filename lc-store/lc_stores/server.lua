-----------------------------------------------------------------------------------------------------------------------------------------
-- Versioning
-----------------------------------------------------------------------------------------------------------------------------------------

version = '5.2.9'
subversion = ''
api_response = {}
local utils_required_version = '1.1.4'
local utils_outdated = false
local script_id = 3
local vrp_ready = nil
Citizen.CreateThread(function()
	local connected = false
	local cont = 0
	while not connected do
		cont = cont + 1
		PerformHttpRequest("http://projetocharmoso.com:3000/api/check-ip-v2?script="..script_id.."&version="..version, function(errorCode, resultData, resultHeaders, errorData)
			if errorCode == 200 and resultData then
				connected = true
				api_response = json.decode(resultData)
				if api_response.authenticated == true then
					vrp_ready = true
					print("^2["..GetCurrentResourceName().."] Authenticated! Support discord: https://discord.gg/U5YDgbh^7 ^3[v"..version..subversion.."]^7")
					if api_response.has_update == true then
						print("^4["..GetCurrentResourceName().."] An update is available, download it in your dashboard^7 ^3[v"..api_response.latest_version.."]^7")
						if api_response.update_message then
							print("^4"..api_response.update_message.."^7")
						else
							print("^4["..GetCurrentResourceName().."] For the complete changelog, visit our Discord: https://discord.gg/U5YDgbh^7")
						end
					end
				else
					vrp_ready = false
					Citizen.CreateThreadNow(function()
						local i = 3
						while i > 0 do
							i = i - 1
							print("^8["..GetCurrentResourceName().."] Your IP is not authenticated, use the customer dashboard in my discord to whitelist it: https://discord.gg/U5YDgbh ["..api_response.ip.."]^7\n")
							Wait(10000)
						end
					end)
				end
			end

			if connected == false and cont > 2 then
				print("^8["..GetCurrentResourceName().."] Connection error, retrying... ["..errorCode.."] ^7")
			end
		end, "GET", "", {})
		Wait(10000)
	end
end)

-----------------------------------------------------------------------------------------------------------------------------------------
-- Script global variables
-----------------------------------------------------------------------------------------------------------------------------------------

Utils = Utils or exports['lc_utils']:GetUtils()
local cooldown = {}
local started = {}

-----------------------------------------------------------------------------------------------------------------------------------------
-- Script functions
-----------------------------------------------------------------------------------------------------------------------------------------

-- Confere se o estoque está vazio
function checkLowStockThread()
	Citizen.CreateThreadNow(function()
		Citizen.Wait(10000)
		while Config.clear_stores.active do
			local sql = "SELECT market_id, user_id, stock, timer FROM store_business";
			local data = Utils.Database.fetchAll(sql, {});
			for k,v in pairs(data) do
				if Config.market_locations[v.market_id] then
					local arr_stock = json.decode(v.stock)
					if arr_stock then
						local count_stock = Utils.Table.tableLength(arr_stock)
						local count_items = getItemsCount(v.market_id)
						if count_stock < count_items*(Config.clear_stores.min_stock_variety/100) or getStockAmount(v.stock) < (getConfigMarketType(v.market_id).stock_capacity)*(Config.clear_stores.min_stock_amount/100) then
							if v.timer + (Config.clear_stores.cooldown*60*60) < os.time() then
								deleteStore(v.market_id)
								Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_lost_low_stock'):format(v.market_id,v.stock,os.date("%d/%m/%Y %H:%M:%S", v.timer),v.user_id..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
							end
						else
							local sql = "UPDATE `store_business` SET timer = @timer WHERE market_id = @market_id";
							Utils.Database.execute(sql, {['timer'] = os.time(), ['@market_id'] = v.market_id});
						end
						Citizen.Wait(100)
					end
				end
			end
			Citizen.Wait(1000*60*60) -- 60 minutos
		end
	end)
end

AddEventHandler('playerDropped', function(reason)
	local source = source
	if started[source] and started[source].deliveryman_job_data then
		local sql = "UPDATE `store_jobs` SET progress = 0 WHERE id = @id";
		Utils.Database.execute(sql, {['@id'] = started[source].deliveryman_job_data.id});
	end
	started[source] = nil
end)

RegisterServerEvent("stores:getData")
AddEventHandler("stores:getData",function(key)
	local source = source
	Wrapper(source,key,"getData",false,function(user_id)
		local categories = {}
		for k,v in pairs(getConfigMarketType(key).categories) do
			categories[v] = getMarketCategory(v)
		end
		local market_categories = Utils.Table.deepCopy(categories)
		local sql = "SELECT user_id FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		if query and query[1] then
			if query[1].user_id == user_id then
				openUI(source,key,false)
			else
				local sql = "SELECT role FROM `store_employees` WHERE market_id = @market_id AND user_id = @user_id";
				local query = Utils.Database.fetchAll(sql, {['@market_id'] = key, ['@user_id'] = user_id});
				if query and query[1] then
					openUI(source,key,false)
				else
					TriggerClientEvent("stores:Notify",source,"error",Utils.translate('already_has_owner'))
				end
			end
		else
			local sql = "SELECT market_id FROM `store_business` WHERE user_id = @user_id";
			local query = Utils.Database.fetchAll(sql, {['@user_id'] = user_id});
			if query and query[1] and #query >= Config.max_stores_per_player then
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('already_has_business'))
			else
				TriggerClientEvent("stores:openRequest",source, getConfigMarketLocation(key).buy_price, market_categories)
			end
		end
	end)
end)

RegisterServerEvent("stores:buyMarket")
AddEventHandler("stores:buyMarket",function(key,event,data)
	local source = source
	Wrapper(source,key,event,false,function(user_id)
		local price = getConfigMarketLocation(key).buy_price + getMarketCategory(data.category).category_buy_price
		if beforeBuyMarket(source,key,price) then
			TriggerClientEvent("stores:closeUI",source)
			if Utils.Framework.tryRemoveAccountMoney(source,price,getAccount(key,"store")) then
				local sql = "INSERT INTO `store_business` (user_id,market_id,stock,stock_prices,timer) VALUES (@user_id,@market_id,@stock,@stock_prices,@timer);";
				Utils.Database.execute(sql, {['@market_id'] = key, ['@user_id'] = user_id, ['@stock'] = json.encode({}), ['@stock_prices'] = json.encode({}), ['@timer'] = os.time()});
				local sql = "INSERT INTO `store_categories` (market_id, category) VALUES (@market_id,@category);";
				Utils.Database.execute(sql, {['@market_id'] = key, ['@category'] = data.category});
				TriggerClientEvent("stores:Notify",source,"success",Utils.translate('businnes_bougth'))
				Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_bought'):format(key,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
				afterBuyMarket(source,key,price)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds_store'):format(price))
			end
		end
	end)
end)

RegisterServerEvent("stores:openMarket")
AddEventHandler("stores:openMarket",function(key)
	local source = source
	Wrapper(source,key,"openMarket",false,function(user_id)
		local required_job = getConfigMarketType(key).required_job
		if not required_job or #required_job == 0 or Utils.Framework.hasJobs(source,required_job) or isOwner(key,user_id) then
			local sql = "UPDATE `store_business` SET total_visits = total_visits + 1 WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@market_id'] = key});
			openUI(source,key,false,true)
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('no_permission'))
		end
	end)
end)

RegisterServerEvent("stores:loadJobData")
AddEventHandler("stores:loadJobData",function(key)
	local source = source
	Wrapper(source,key,"loadJobData",false,function(user_id)
		local sql = "SELECT id,name,reward FROM store_jobs WHERE market_id = @market_id AND progress = 0 ORDER BY id ASC";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key})[1];
		if query == nil then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('no_available_jobs'))
			return
		end
		local sql = "SELECT user_id FROM store_business WHERE market_id = @market_id";
		local query_2 = Utils.Database.fetchAll(sql, {['@market_id'] = key})[1];
		if query_2 ~= nil and query_2.user_id == user_id then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cannot_do_own_job'))
			return
		end
		TriggerClientEvent("stores:setJobData",source,key,query)
	end)
end)

RegisterServerEvent("stores:startDeliverymanJob")
AddEventHandler("stores:startDeliverymanJob",function(key,id)
	local source = source
	Wrapper(source,key,"startDeliverymanJob",false,function(user_id)
		if started[source] ~= nil then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('already_has_job'))
			return
		end
		local sql = "SELECT * FROM store_jobs WHERE id = @id ORDER BY id ASC";
		local query = Utils.Database.fetchAll(sql, {['@id'] = id})[1];
		if query.progress == 0 then
			local sql = "UPDATE `store_jobs` SET progress = 1 WHERE id = @id";
			Utils.Database.execute(sql, {['@id'] = id});
			started[source] = {
				['deliveryman_job_data'] = query,
				['job_data'] = {
					item = query.product,
					amount = query.amount
				}
			}
			TriggerClientEvent("stores:startJob",source,0,true)
		else
			TriggerClientEvent("stores:setJobData",source,key,nil)
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('job_already_in_progress'))
		end
	end)
end)

RegisterServerEvent("stores:failed")
AddEventHandler("stores:failed",function()
	local source = source
	if started[source] and started[source].deliveryman_job_data then
		local sql = "UPDATE `store_jobs` SET progress = 0 WHERE id = @id";
		Utils.Database.execute(sql, {['@id'] = started[source].deliveryman_job_data.id});
	end
	started[source] = nil
end)

RegisterServerEvent("stores:storeProductFromInventory")
AddEventHandler("stores:storeProductFromInventory",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		storeProduct(source,key,data.item_id,data.amount)
	end)
end)

function storeProduct(source,key,item,amount,from_trucker)
	amount = math.floor(tonumber(amount) or 0)
	local source = source
	if amount > 0 then
		local sql = "SELECT stock, truck_upgrade, stock_upgrade FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		if query and query[1] then
			local arr_stock = json.decode(query[1].stock)
			if not arr_stock[item] then arr_stock[item] = 0 end
			local market_type = getConfigMarketType(key)
			if getStockAmount(query[1].stock) + amount <= market_type.stock_capacity + market_type.upgrades.stock.level_reward[query[1].stock_upgrade] then
				arr_stock[item] = arr_stock[item] + amount
			else
				amount = market_type.stock_capacity + market_type.upgrades.stock.level_reward[query[1].stock_upgrade] - getStockAmount(query[1].stock)
				arr_stock[item] = arr_stock[item] + amount
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('stock_full'))
			end
			if amount > 0 then
				local item_data = getItem(key,item)
				if from_trucker or (item_data.is_weapon == true and Utils.Framework.getPlayerWeapon(source,item,amount)) or (item_data.is_weapon ~= true and Utils.Framework.getPlayerItem(source,item,amount)) then
					local sql = "UPDATE `store_business` SET stock = @stock WHERE market_id = @market_id";
					Utils.Database.execute(sql, {['@market_id'] = key, ['@stock'] = json.encode(arr_stock)});
					if not from_trucker then
						openUI(source,key,true)
						TriggerClientEvent("stores:Notify",source,"success",Utils.translate('inserted_on_stock'):format(amount,item_data.name))
					end
				else
					TriggerClientEvent("stores:Notify",source,"error",Utils.translate('not_enought_items'):format(amount,item_data.name))
				end
			end
		end
	else
		TriggerClientEvent("stores:Notify",source,"error",Utils.translate('invalid_value'))
	end
end

function finishTruckerContract(source,external_data,contract_id)
	storeProduct(source,external_data.key,external_data.item,external_data.amount,true)
	local sql = "DELETE FROM `store_jobs` WHERE trucker_contract_id = @id;";
	Utils.Database.execute(sql, {['@id'] = contract_id});
end
exports('finishTruckerContract', finishTruckerContract)

RegisterServerEvent("stores:startImportJob")
AddEventHandler("stores:startImportJob",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		if started[source] ~= nil then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('already_has_job'))
			return
		end
		local item = data.item_id
		local amount = math.floor(tonumber(data.amount) or 0)
		local sql = "SELECT truck_upgrade, relationship_upgrade FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		local item_data = getItem(key,item)
		local market_type = getConfigMarketType(key)
		local max_amount = math.floor(item_data.amount_to_owner + item_data.amount_to_owner * (market_type.upgrades.truck.level_reward[query[1].truck_upgrade]/100))
		if amount > 0 and amount <= max_amount then
			local price = item_data.price_to_owner * amount
			local discount = market_type.upgrades.relationship.level_reward[query[1].relationship_upgrade]
			discount = math.floor((price * discount)/100)
			local total_price = price-discount
			if tryGetMarketMoney(key,total_price) then
				insertBalanceHistory(key,1,Utils.translate('buy_products_expenses'):format(amount,item_data.name),total_price)
				Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_start_import'):format(key,item,amount,total_price,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
				started[source] = {
					['job_data'] = {
						item = item,
						amount = amount
					}
				}
				TriggerClientEvent("stores:startJob",source,query[1].truck_upgrade,true)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('max_job_amount'))
		end
	end)
end)

RegisterServerEvent("stores:startExportJob")
AddEventHandler("stores:startExportJob",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		if started[source] ~= nil then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('already_has_job'))
			return
		end
		local sql = "SELECT truck_upgrade, stock FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		local max_amount = math.floor(getItem(key,data.item_id).amount_to_owner + tonumber(getItem(key, data.item_id).amount_to_owner*(getConfigMarketType(key).upgrades.truck.level_reward[query[1].truck_upgrade]/100)))
		local arr_stock = json.decode(query[1].stock)
		local amount = arr_stock[data.item_id]
		if amount and amount > 0 then
			if amount > max_amount then
				amount = max_amount
				arr_stock[data.item_id] = arr_stock[data.item_id] - amount
			else
				arr_stock[data.item_id] = nil
			end
			
			local sql = "UPDATE `store_business` SET stock = @stock WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@stock'] = json.encode(arr_stock)});

			Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_start_export'):format(key,data.item_id,amount,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))

			started[source] = {
				['job_data'] = {
					item = data.item_id,
					amount = amount
				}
			}
			TriggerClientEvent("stores:startJob",source,query[1].truck_upgrade,false)
		end
	end)
end)

RegisterServerEvent("stores:finishImportJob")
AddEventHandler("stores:finishImportJob",function(key,distance)
	local source = source
	Wrapper(source,key,"finishImportJob",false,function(user_id)
		if started[source] then
			local item = started[source].job_data.item
			local amount = started[source].job_data.amount
			local sql = "SELECT stock, truck_upgrade, stock_upgrade FROM `store_business` WHERE market_id = @market_id";
			local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
			local arr_stock = json.decode(query[1].stock)
			if not arr_stock[item] then arr_stock[item] = 0 end
			if started[source].deliveryman_job_data then
				distance = 0
				amount = tonumber(started[source].deliveryman_job_data.amount) or 0
				local reward = tonumber(started[source].deliveryman_job_data.reward) or 0
				Utils.Framework.giveAccountMoney(source,reward,getAccount(key,"store"))
				local sql = "DELETE FROM `store_jobs` WHERE id = @id;";
				Utils.Database.execute(sql, {['@id'] = started[source].deliveryman_job_data.id});
			end
			local market_type = getConfigMarketType(key)
			if getStockAmount(query[1].stock) + amount <= market_type.stock_capacity + market_type.upgrades.stock.level_reward[query[1].stock_upgrade] then
				arr_stock[item] = arr_stock[item] + amount
			else
				amount = market_type.stock_capacity + market_type.upgrades.stock.level_reward[query[1].stock_upgrade] - getStockAmount(query[1].stock)
				arr_stock[item] = arr_stock[item] + amount
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('stock_full'))
			end
			local sql = "UPDATE `store_employees` SET jobs_done = jobs_done + 1 WHERE market_id = @market_id and user_id = @user_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@user_id'] = user_id});
			local sql = "UPDATE `store_business` SET stock = @stock, goods_bought = goods_bought + @amount, distance_traveled = distance_traveled + @distance WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@stock'] = json.encode(arr_stock), ['@amount'] = amount, ['@distance'] = distance});
			Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_finish_import'):format(key,item,amount,json.encode(arr_stock),Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
			started[source] = nil
		end
	end)
end)

RegisterServerEvent("stores:finishExportJob")
AddEventHandler("stores:finishExportJob",function(key,distance)
	local source = source
	Wrapper(source,key,"finishExportJob",false,function(user_id)
		if started[source] then
			local item = started[source].job_data.item
			local amount = started[source].job_data.amount
			local price = getItem(key,item).price_to_export * amount
			giveMarketMoney(key,price)
			local item_data = getItem(key,item)
			insertBalanceHistory(key,0,Utils.translate('exported_income'):format(amount,item_data.name),price)
			local sql = "UPDATE `store_employees` SET jobs_done = jobs_done + 1 WHERE market_id = @market_id and user_id = @user_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@user_id'] = user_id});
			local sql = "UPDATE `store_business` SET total_money_earned = total_money_earned + @money, distance_traveled = distance_traveled + @distance WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@money'] = price, ['@distance'] = distance});
			Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_finish_export'):format(key,item,amount,price,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
			started[source] = nil
		end
	end)
end)

RegisterServerEvent("stores:setPrice")
AddEventHandler("stores:setPrice",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local item = data.item_id
		local price = math.floor(tonumber(data.price) or 0)
		local item_data = getItem(key, item)
		if not item_data.price_to_customer_min then item_data.price_to_customer_min = 0 end
		if not item_data.price_to_customer_max then item_data.price_to_customer_max = 999999 end
		if price >= item_data.price_to_customer_min and price <= item_data.price_to_customer_max then
			local sql = "SELECT stock_prices FROM `store_business` WHERE market_id = @market_id";
			local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
			local arr_stock = json.decode(query[1].stock_prices)
			arr_stock[item] = price
			local sql = "UPDATE `store_business` SET stock_prices = @stock_prices WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@market_id'] = key, ['@stock_prices'] = json.encode(arr_stock)});
			openUI(source,key,true)
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('invalid_price'):format(item_data.price_to_customer_min, item_data.price_to_customer_max))
		end
	end)
end)

local cooldown_global = {}
RegisterServerEvent("stores:buyItem")
AddEventHandler("stores:buyItem",function(key,event,data)
	local source = source
	Wrapper(source,key,event,false,function(user_id)
		if cooldown_global[key] == nil then
			cooldown_global[key] = true
			local sql = "SELECT stock, stock_prices FROM `store_business` WHERE market_id = @market_id";
			Utils.Database.fetchAllAsync(sql, {['@market_id'] = key}, function(query)
				data.amount = math.floor(tonumber(data.amount) or 0)
				if data.amount > 0 then
					local arr_stock = {}
					local arr_stock_prices = {}
					local item_data = nil
					if query and query[1] then
						arr_stock = json.decode(query[1].stock)
						if not arr_stock[data.item_id] then arr_stock[data.item_id] = 0 end
						arr_stock_prices = json.decode(query[1].stock_prices)
						item_data = getItem(key,data.item_id)
					else
						item_data = getItemNoKey(data.item_id)
						if Config.has_stock_when_unowed then
							arr_stock[data.item_id] = 999
						else
							arr_stock[data.item_id] = 0
						end
					end
					if arr_stock[data.item_id] >= data.amount then
						local total_price = (arr_stock_prices[data.item_id] or item_data.price_to_customer)*data.amount
						if beforeBuyItem(source,key,data.item_id,data.amount,total_price,item_data.metadata) then
							if not item_data.max_amount_to_purchase or data.amount <= item_data.max_amount_to_purchase then
								local account = getConfigMarketLocation(key).account.item[tonumber(data.paymentMethod)].account
								local money = Utils.Framework.getPlayerAccountMoney(source,account)
								if money >= total_price then
									if item_data.requires_license ~= true or Utils.Framework.hasWeaponLicense(source) then
										if (item_data.is_weapon == true and Utils.Framework.givePlayerWeapon(source,data.item_id,data.amount,item_data.metadata)) or (item_data.is_weapon ~= true and Utils.Framework.givePlayerItem(source,data.item_id,data.amount,item_data.metadata)) then
											Utils.Framework.tryRemoveAccountMoney(source,total_price,account)
											if query and query[1] then
												giveMarketMoney(key,total_price)
												arr_stock[data.item_id] = arr_stock[data.item_id] - data.amount
												if arr_stock[data.item_id] == 0 then
													arr_stock[data.item_id] = nil
												end
												insertBalanceHistory(key,0,Utils.translate('bought_item'):format(data.amount,item_data.name),total_price)
												local sql = "UPDATE `store_business` SET stock = @stock, customers = customers + 1, total_money_earned = total_money_earned + @money WHERE market_id = @market_id";
												Utils.Database.execute(sql, {['@market_id'] = key, ['@money'] = total_price, ['@stock'] = json.encode(arr_stock)});
											end
											openUI(source,key,true,true)
											Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_item_bought'):format(key,data.item_id,data.amount,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
											TriggerClientEvent("stores:Notify",source,"success",Utils.translate('bought_item_2'):format(data.amount,item_data.name))
											afterBuyItem(source,key,data.item_id,data.amount,total_price,account)
										else
											TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cant_carry_item'))
										end
									else
										TriggerClientEvent("stores:Notify",source,"error",Utils.translate('dont_have_weapon_license'))
									end
								else
									TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
								end
							else
								TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cant_buy_that_amount'):format(item_data.max_amount_to_purchase))
							end
						end
					else
						TriggerClientEvent("stores:Notify",source,"error",Utils.translate('stock_empty'))
					end
				end
				SetTimeout(500,function()
					cooldown_global[key] = nil
				end)
			end);
		end
	end)
end)

RegisterServerEvent("stores:createJob")
AddEventHandler("stores:createJob",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "SELECT COUNT(id) as qtd FROM store_jobs WHERE market_id = @market_id";
		local count = Utils.Database.fetchAll(sql, {['@market_id'] = key})[1].qtd;
		if tonumber(count) < Config.max_jobs then
			local sql = "SELECT relationship_upgrade FROM `store_business` WHERE market_id = @market_id";
			local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
			local price = getItem(key, data.product).price_to_owner * data.amount
			local discount = getConfigMarketType(key).upgrades.relationship.level_reward[query[1].relationship_upgrade]
			discount = math.floor((price * discount)/100)
			local total_price = data.reward + price-discount
			if tryGetMarketMoney(key,total_price) then
				local last_contract_id = nil
				if Config.trucker_logistics.enable then
					local truck = nil
					local contract_type = 1
					if Config.trucker_logistics.quick_jobs_page == true then
						truck = Config.trucker_logistics.available_trucks[math.random(1, #Config.trucker_logistics.available_trucks)]
						contract_type = 0
					end
					local trailer = Config.trucker_logistics.available_trailers[math.random(1, #Config.trucker_logistics.available_trailers)]
					local truck_parking_location = getConfigMarketLocation(key).truck_parking_location
					local external_data = {
						["x"] = truck_parking_location[1],["y"] = truck_parking_location[2],["z"] = truck_parking_location[3],["h"] = truck_parking_location[4],
						["key"] = key,
						["reward"] = data.reward,
						["item"] = data.product,
						["amount"] = data.amount,
						["export"] = GetCurrentResourceName()
					}
					local sql = "INSERT INTO `trucker_available_contracts` (contract_type, contract_name, coords_index, price_per_km, cargo_type, fragile, valuable, fast, truck, trailer, external_data) VALUES (@contract_type, @contract_name, @coords_index, @price_per_km, @cargo_type, @fragile, @valuable, @fast, @truck, @trailer, @external_data);";
					Utils.Database.execute(sql, {['@contract_type'] = contract_type, ['@contract_name'] = data.name, ['@coords_index'] = 0, ['@price_per_km'] = 0, ['@cargo_type'] = 0, ['@fragile'] = 0, ['@valuable'] = 0, ['@fast'] = 0, ['@truck'] = truck, ['@trailer'] = trailer, ['@external_data'] = json.encode(external_data)});
					
					local sql = "SELECT contract_id FROM `trucker_available_contracts` WHERE progress IS NULL AND contract_name = @name AND coords_index = 0 ORDER BY contract_id DESC LIMIT 1";
					last_contract_id = Utils.Database.fetchAll(sql,{['@name'] = data.name})[1].contract_id;
				end
				
				local sql = "INSERT INTO `store_jobs` (market_id,name,reward,product,amount,trucker_contract_id) VALUES (@market_id,@name,@reward,@product,@amount,@trucker_contract_id);";
				Utils.Database.execute(sql, {['@market_id'] = key, ['@name'] = data.name, ['@reward'] = data.reward, ['@product'] = data.product, ['@amount'] = data.amount, ['@trucker_contract_id'] = last_contract_id});

				insertBalanceHistory(key,1,Utils.translate('create_job_expenses'):format(data.name),total_price)
				openUI(source,key,true)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			end
		end
	end)
end)

RegisterServerEvent("stores:deleteJob")
AddEventHandler("stores:deleteJob",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		if deleteJob(key,data.job_id) then
			openUI(source,key,true)
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cant_delete_job'))
		end
	end)
end)

function deleteJob(key,job_id)
	local sql = "SELECT name,reward,product,amount,progress,trucker_contract_id FROM `store_jobs` WHERE id = @id;";
	local query_jobs = Utils.Database.fetchAll(sql,{['@id'] = job_id});
	if query_jobs[1] then

		if Config.trucker_logistics.enable then
			local sql = "SELECT progress FROM `trucker_available_contracts` WHERE contract_id = @contract_id";
			local query_trucker = Utils.Database.fetchAll(sql,{['@contract_id'] = query_jobs[1].trucker_contract_id});
			if query_trucker and query_trucker[1] then
				if query_trucker[1].progress ~= nil then
					return false
				end
			end
		end

		if query_jobs[1].progress == 0 then
			
			local sql = "SELECT relationship_upgrade FROM `store_business` WHERE market_id = @market_id";
			local query_business = Utils.Database.fetchAll(sql, {['@market_id'] = key});
			local price = getItem(key,query_jobs[1].product).price_to_owner * query_jobs[1].amount
			local discount = getConfigMarketType(key).upgrades.relationship.level_reward[query_business[1].relationship_upgrade]
			discount = math.floor((price * discount)/100)
			local total_price = query_jobs[1].reward + price-discount
			
			local sql = "UPDATE `store_business` SET total_money_spent = total_money_spent - @amount WHERE market_id = @market_id";
			Utils.Database.execute(sql, {['@amount'] = total_price, ['@market_id'] = key});

			local sql = "DELETE FROM `store_jobs` WHERE id = @id;";
			Utils.Database.execute(sql, {['@id'] = job_id});

			if Config.trucker_logistics.enable then
				local sql = "DELETE FROM `trucker_available_contracts` WHERE contract_id = @contract_id;";
				Utils.Database.execute(sql, {['@contract_id'] = query_jobs[1].trucker_contract_id});
			end

			giveMarketMoney(key,total_price)
			insertBalanceHistory(key,0,Utils.translate('create_job_income'):format(query_jobs[1].name),total_price)
			
			return true
		else
			return false
		end
	end
end

RegisterServerEvent("stores:renameMarket")
AddEventHandler("stores:renameMarket",function(key,event,data)
	if not Config.disable_rename_business then
		local source = source
		Wrapper(source,key,event,true,function(user_id)
			if data and data.name and data.color and data.blip then
				local sql = "UPDATE `store_business` SET market_name = @name, market_color = @color, market_blip = @blip WHERE market_id = @market_id";
				Utils.Database.execute(sql, {['@name'] = data.name, ['@color'] = data.color, ['@blip'] = data.blip, ['@market_id'] = key});
				TriggerClientEvent("stores:updateBlip",-1,key,data.name,data.color,data.blip)
				openUI(source,key,true)
			end
		end)
	end
end)

RegisterServerEvent("stores:getBlips")
AddEventHandler("stores:getBlips",function()
	local source = source
	local sql = "SELECT market_id, market_name, market_color, market_blip FROM `store_business`";
	local query = Utils.Database.fetchAll(sql, {});
	local ret_table = {}
	for k,v in pairs(query) do
		ret_table[v.market_id] = {market_name = v.market_name, market_color = v.market_color, market_blip = v.market_blip}
	end
	TriggerClientEvent("stores:setBlips",source,ret_table)
end)

RegisterServerEvent("stores:buyUpgrade")
AddEventHandler("stores:buyUpgrade",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "SELECT "..data.id.."_upgrade FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql,{['@market_id'] = key})[1];
		if query[data.id.."_upgrade"] < 5 then
			local amount = getConfigMarketType(key).upgrades[data.id].price
			if tryGetMarketMoney(key,amount) then
				local sql = "UPDATE `store_business` SET "..data.id.."_upgrade = "..data.id.."_upgrade + 1 WHERE market_id = @market_id";
				Utils.Database.execute(sql, {['@market_id'] = key});

				insertBalanceHistory(key,1,Utils.translate('upgrade_expenses'):format(Utils.translate(data.id..'_upgrade')),amount)
				openUI(source,key,true)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('max_level'))
		end
	end)
end)


RegisterServerEvent("stores:hideBalance")
AddEventHandler("stores:hideBalance",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "UPDATE `store_balance` SET hidden = 1 WHERE market_id = @market_id AND id = @id";
		Utils.Database.execute(sql, {['@market_id'] = key, ['@id'] = data.balance_id});
		openUI(source,key,true)
	end)
end)

RegisterServerEvent("stores:showBalance")
AddEventHandler("stores:showBalance",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "UPDATE `store_balance` SET hidden = 0 WHERE market_id = @market_id AND id = @id";
		Utils.Database.execute(sql, {['@market_id'] = key, ['@id'] = data.balance_id});
		openUI(source,key,true)
	end)
end)

RegisterServerEvent("stores:withdrawMoney")
AddEventHandler("stores:withdrawMoney",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local amount = math.floor(tonumber(data.amount) or 0)
		if amount and amount > 0 then
			local sql = "SELECT money FROM `store_business` WHERE market_id = @market_id";
			local query = Utils.Database.fetchAll(sql,{['@market_id'] = key})[1];
			if query and tonumber(query.money) >= amount then
				local sql = "UPDATE `store_business` SET money = money - @amount WHERE market_id = @market_id";
				Utils.Database.execute(sql, {['@market_id'] = key, ['@amount'] = amount});
				Utils.Framework.giveAccountMoney(source,amount,getAccount(key,"store"))
				insertBalanceHistory(key,1,Utils.translate('money_withdrawn'),amount)
				TriggerClientEvent("stores:Notify",source,"success",Utils.translate('money_withdrawn'))
				Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_money_withdrawn'):format(key,amount,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
				openUI(source,key,true)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('invalid_value'))
		end
	end)
end)

RegisterServerEvent("stores:depositMoney")
AddEventHandler("stores:depositMoney",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local amount = math.floor(tonumber(data.amount) or 0)
		if amount and amount > 0 then
			if Utils.Framework.tryRemoveAccountMoney(source,amount,getAccount(key,"store")) then
				giveMarketMoney(key,amount)
				insertBalanceHistory(key,0,Utils.translate('money_deposited'),amount)
				TriggerClientEvent("stores:Notify",source,"success",Utils.translate('money_deposited'))
				Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_money_deposited'):format(key,amount,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
				openUI(source,key,true)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('invalid_value'))
		end
	end)
end)

Utils.Callback.RegisterServerCallback('stores:loadBalanceHistory', function(source,cb,key,data)
	local sql = "SELECT * FROM `store_balance` WHERE market_id = @market_id AND id < @last_balance_id ORDER BY id DESC LIMIT 50";
	local store_balance = Utils.Database.fetchAll(sql,{['@market_id'] = key, ['@last_balance_id'] = data.last_balance_id});
	cb(store_balance)
end)

RegisterServerEvent("stores:hirePlayer")
AddEventHandler("stores:hirePlayer",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local user = data.user
		-- Check if reached the max employee amount
		local sql = "SELECT COUNT(user_id) as qtd FROM `store_employees` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql,{['@market_id'] = key});
		local max_employees = getConfigMarketType(key).max_employees or 0
		if query[1].qtd < max_employees then
			local name = Utils.Framework.getPlayerName(user)
			if name then
				-- Check if player is not already a employee
				local sql = "SELECT market_id, user_id FROM `store_employees` WHERE user_id = @user_id";
				local query = Utils.Database.fetchAll(sql,{['@user_id'] = user});
				for _, v in pairs(query) do
					if v.user_id == user and v.market_id == key then
						TriggerClientEvent("stores:Notify",source,"error",Utils.translate('user_employed'))
						return
					end
				end
				if #query < Config.max_stores_employed then
					-- Insert new employee
					local sql = "INSERT INTO `store_employees` (`user_id`, `market_id`, `role`, `timer`) VALUES (@user_id, @market_id, @role, @timer);";
					Utils.Database.execute(sql, {['@user_id'] = user, ['@market_id'] = key, ['@role'] = 1, ['@timer'] = os.time()});
					openUI(source,key,true)
					TriggerClientEvent("stores:Notify",source,"success",Utils.translate('hired_user'):format(name))
				else
					TriggerClientEvent("stores:Notify",source,"error",Utils.translate('user_employed'))
				end
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('user_not_found'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('max_employees'))
		end
	end)
end)

RegisterServerEvent("stores:firePlayer")
AddEventHandler("stores:firePlayer",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "DELETE FROM `store_employees` WHERE user_id = @user_id AND market_id = @market_id";
		Utils.Database.execute(sql, {['@user_id'] = data.user, ['@market_id'] = key});
		TriggerClientEvent("stores:Notify",source,"success",Utils.translate('fired_user'))
		openUI(source,key,true)
	end)
end)

RegisterServerEvent("stores:changeRole")
AddEventHandler("stores:changeRole",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "UPDATE `store_employees` SET role = @role WHERE market_id = @market_id AND user_id = @user_id";
		Utils.Database.execute(sql, {['@market_id'] = key, ['@user_id'] = data.user_id, ['@role'] = data.role});
		TriggerClientEvent("stores:Notify",source,"success",Utils.translate('role_changed'))
	end)
end)

RegisterServerEvent("stores:giveComission")
AddEventHandler("stores:giveComission",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local user = data.user
		local amount = math.floor(tonumber(data.amount) or 0)
		if amount > 0 then
			local tPlayer_source = Utils.Framework.getPlayerSource(user)
			if tPlayer_source then
				if tryGetMarketMoney(key,amount) then
					Utils.Framework.giveAccountMoney(tPlayer_source,amount,getAccount(key,"store"))
					TriggerClientEvent("stores:Notify",tPlayer_source,"success",Utils.translate('comission_received'))
					TriggerClientEvent("stores:Notify",source,"success",Utils.translate('comission_sent'))
					insertBalanceHistory(key,1,Utils.translate('give_comission_expenses'):format(Utils.Framework.getPlayerName(user)),amount)
					Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_comission'):format(key,amount,Utils.Framework.getPlayerIdLog(tPlayer_source),Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
					openUI(source,key,true)
				else
					TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
				end
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cant_find_user'))
			end
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('invalid_value'))
		end
	end)
end)

RegisterServerEvent("stores:buyCategory")
AddEventHandler("stores:buyCategory",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "SELECT COUNT(*) as category_count FROM store_categories WHERE market_id = @market_id"
		local categoriesCount = Utils.Database.fetchAll(sql, { ['@market_id'] = key })[1]

		if categoriesCount.category_count >= getConfigMarketType(key).max_purchasable_categories then
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('category_max_amount'))
			return
		end

		local market_category = getMarketCategory(data.category)
		if not tryGetMarketMoney(key,market_category.category_buy_price) then 
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_funds'))
			return
		end

		local sql = "INSERT INTO store_categories (market_id, category) VALUES (@market_id,@category)";
		Utils.Database.execute(sql, {['@market_id'] = key,['@category'] = data.category});
		TriggerClientEvent("stores:Notify",source,"success",Utils.translate('category_bought'))
		insertBalanceHistory(key,1,Utils.translate('category_bought_balance'):format(market_category.page_name),market_category.category_buy_price)
		openUI(source,key,true)
	end)
end)

RegisterServerEvent("stores:sellCategory")
AddEventHandler("stores:sellCategory", function(key, event, data)
	local source = source
	Wrapper(source, key, event, true, function(user_id)
		local market_category = getMarketCategory(data.category)
		local price = market_category.category_sell_price
		local sql = "SELECT id FROM store_categories WHERE market_id = @market_id AND category = @category"
		local rows = Utils.Database.fetchAll(sql, { ['@market_id'] = key, ['@category'] = data.category })

		if #rows == 0 then
			TriggerClientEvent("stores:Notify", source, "error", Utils.translate('category_not_found'))
			return
		end

		local remainingCategoriesSql = "SELECT COUNT(*) as category_count FROM store_categories WHERE market_id = @market_id"
		local remainingCategories = Utils.Database.fetchAll(remainingCategoriesSql, { ['@market_id'] = key })[1]

		if remainingCategories.category_count == 1 then
			TriggerClientEvent("stores:Notify", source, "error", Utils.translate('cannot_sell_last_category'))
			return
		end

		local sql = "SELECT * FROM `store_jobs` WHERE market_id = @market_id";
		local query_jobs = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		for k, v in pairs(query_jobs) do
			if market_category.items[v.product] then
				if not deleteJob(key,v.id) then
					TriggerClientEvent("stores:Notify",source,"error",Utils.translate('cant_delete_category'))
					return
				end
			end
		end
		
		local sql = "SELECT stock, stock_prices FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		local arr_stock = json.decode(query[1].stock)
		local arr_stock_prices = json.decode(query[1].stock_prices)

		for k, v in pairs(market_category.items) do
			arr_stock[k] = nil
			arr_stock_prices[k] = nil
		end

		local sql = "UPDATE `store_business` SET stock = @stock, stock_prices = @stock_prices WHERE market_id = @market_id";
		Utils.Database.execute(sql, {['@market_id'] = key, ['@stock'] = json.encode(arr_stock), ['@stock_prices'] = json.encode(arr_stock_prices)});

		local deleteSql = "DELETE FROM store_categories WHERE market_id = @market_id AND category = @category"
		Utils.Database.execute(deleteSql, { ['@market_id'] = key, ['@category'] = data.category })
		giveMarketMoney(key, price)
		insertBalanceHistory(key, 0, Utils.translate('category_sold_balance'):format(market_category.page_name), price)
		TriggerClientEvent("stores:Notify", source, "success", Utils.translate('category_sold'))
		openUI(source, key, true)
	end)
end)

RegisterServerEvent("stores:changeTheme")
AddEventHandler("stores:changeTheme", function(key, event, data)
	local source = source
	cooldown[source] = nil
	Wrapper(source, key, event, false, function(user_id)
		local sql = "SELECT * FROM `store_users_theme` WHERE user_id = @user_id";
		local user_data = Utils.Database.fetchAll(sql,{['@user_id'] = user_id})[1];
		if user_data == nil then
			local sql = "INSERT INTO `store_users_theme` (user_id,dark_theme) VALUES (@user_id,@dark_theme);";
			Utils.Database.execute(sql, {['@dark_theme'] = data.dark_theme, ['@user_id'] = user_id});
		else
			local sql = "UPDATE `store_users_theme` SET dark_theme = @dark_theme WHERE user_id = @user_id";
			Utils.Database.execute(sql, {['@dark_theme'] = data.dark_theme, ['@user_id'] = user_id});
		end
	end)
end)


RegisterServerEvent("stores:sellMarket")
AddEventHandler("stores:sellMarket",function(key,event,data)
	local source = source
	Wrapper(source,key,event,true,function(user_id)
		local sql = "SELECT user_id FROM `store_business` WHERE market_id = @market_id";
		local query = Utils.Database.fetchAll(sql,{['@market_id'] = key})[1];
		if query.user_id == user_id then
			TriggerClientEvent("stores:closeUI",source)
			deleteStore(key)
			Utils.Framework.giveAccountMoney(source,getConfigMarketLocation(key).sell_price,getAccount(key,"store"))
			TriggerClientEvent("stores:Notify",source,"success",Utils.translate('store_sold'))
			local blips = getConfigMarketType(key).blips
			TriggerClientEvent("stores:updateBlip",-1,key,blips.name,blips.color,blips.id)
			Utils.Webhook.sendWebhookMessage(WebhookURL,Utils.translate('logs_close'):format(key,Utils.Framework.getPlayerIdLog(source)..os.date("\n["..Utils.translate('logs_date').."]: %d/%m/%Y ["..Utils.translate('logs_hour').."]: %H:%M:%S")))
		else
			TriggerClientEvent("stores:Notify",source,"error",Utils.translate('sell_error'))
		end
	end)
end)

function deleteStore(key)
	if Config.trucker_logistics.enable then
		local sql = "SELECT * FROM `store_jobs` WHERE market_id = @market_id";
		local query_jobs = Utils.Database.fetchAll(sql, {['@market_id'] = key});
		for k, v in pairs(query_jobs) do
			deleteJob(key,v.id)
		end
	end
	local sql = "DELETE FROM `store_business` WHERE market_id = @market_id;";
	Utils.Database.execute(sql, {['@market_id'] = key});
	local sql = "DELETE FROM `store_balance` WHERE market_id = @market_id;";
	Utils.Database.execute(sql, {['@market_id'] = key});
	local sql = "DELETE FROM `store_jobs` WHERE market_id = @market_id;";
	Utils.Database.execute(sql, {['@market_id'] = key});
	local sql = "DELETE FROM `store_employees` WHERE market_id = @market_id;";
	Utils.Database.execute(sql, {['@market_id'] = key});
	local sql = "DELETE FROM `store_categories` WHERE market_id = @market_id;";
	Utils.Database.execute(sql, {['@market_id'] = key});
end

function getDefaultCategories(key)
	local defaultCategories = {}
	for k,v in pairs(getConfigMarketType(key).default_categories) do
		for a,b in pairs(Config.market_categories) do
			if a == v then
				defaultCategories[a] = b
			end
		end
	end
	return defaultCategories
end

function getDefaultItems(key)
	local items = {}
	for k,v in pairs(getConfigMarketType(key).default_categories) do
		for a,b in pairs(getMarketCategory(v).items) do
			items[a] = b
		end
	end
	return items
end

function getItemsCount(market_id)
	local count_items = 0
	local sql = "SELECT * FROM `store_categories` WHERE market_id = @market_id";
	local query = Utils.Database.fetchAll(sql,{['@market_id'] = market_id});
	if query and query[1] then
		for k,v in pairs(query) do
			count_items = count_items + Utils.Table.tableLength(getMarketCategory(v.category).items)
		end
	end
	return count_items
end

function getItems(market_id)
	local sql = "SELECT * FROM `store_categories` WHERE market_id = @market_id";
	local query = Utils.Database.fetchAll(sql, {['@market_id'] = market_id});
	local items = {}
	if query and query[1] then
		for _, v in ipairs(query) do
			local category_items = getMarketCategory(v.category).items
			for a, b in pairs(category_items) do
				items[a] = b
			end
		end
	end
	return items
end

function getItem(market_id, item)
	local sql = "SELECT * FROM `store_categories` WHERE market_id = @market_id";
	local query = Utils.Database.fetchAll(sql, {['@market_id'] = market_id});
	if query and query[1] then
		for _, v in ipairs(query) do
			local category_items = getMarketCategory(v.category).items
			if category_items[item] then
				return category_items[item]
			end
		end
	end
	error(("Item %s not found in the store %s category config"):format(item, market_id))
end

function getItemNoKey(item)
	for _, v in pairs(Config.market_categories) do
		if v.items[item] then
			return v.items[item]
		end
	end
	error(("Item %s not found in config"):format(item))
end

function isOwner(key,user_id)
	local sql = "SELECT 1 FROM `store_business` WHERE market_id = @market_id AND user_id = @user_id";
	local query = Utils.Database.fetchAll(sql, {['@market_id'] = key, ['@user_id'] = user_id});
	if query and query[1] then
		return true
	else
		return false
	end
end

function hasRole(key,user_id,class)
	local role = Config.roles_permissions.functions[class]
	if not role then
		print("^8["..GetCurrentResourceName().."] Role '"..class.."' not found in Config.roles_permissions^7")
		return false
	end
	local sql = "SELECT 1 FROM `store_employees` WHERE market_id = @market_id AND user_id = @user_id AND role >= @role";
	local query = Utils.Database.fetchAll(sql, {['@market_id'] = key, ['@user_id'] = user_id, ['@role'] = role});
	if query and query[1] then
		return true
	else
		return false
	end
end

function giveMarketMoney(market_id,amount)
	local sql = "UPDATE `store_business` SET money = money + @amount WHERE market_id = @market_id";
	Utils.Database.executeAsync(sql, {['@amount'] = amount, ['@market_id'] = market_id});
end

function tryGetMarketMoney(market_id,amount)
	local sql = "SELECT money FROM `store_business` WHERE market_id = @market_id";
	local query = Utils.Database.fetchAll(sql,{['@market_id'] = market_id})[1];
	if tonumber(query.money) >= amount then
		local sql = "UPDATE `store_business` SET money = @money, total_money_spent = total_money_spent + @amount WHERE market_id = @market_id";
		Utils.Database.execute(sql, {['@money'] = (tonumber(query.money) - amount), ['@amount'] = amount, ['@market_id'] = market_id});
		return true
	else
		return false
	end
end

function getStockAmount(stock)
	local arr_stock = json.decode(stock)
	local count = 0
	for k,v in pairs(arr_stock) do
		count = count + v
	end
	return count
end

function insertBalanceHistory(market_id,income,title,amount)
	local sql = "INSERT INTO `store_balance` (market_id,income,title,amount,date) VALUES (@market_id,@income,@title,@amount,@date)";
	Utils.Database.executeAsync(sql, {['@market_id'] = market_id, ['@income'] = income, ['@title'] = title, ['@amount'] = amount, ['@date'] = os.time()});
end

function getAccount(key,account_type)
	local market_location = getConfigMarketLocation(key)
	if account_type == "item" then
		if market_location.account then
			return market_location.account.item
		else
			return "bank"
		end
	elseif account_type == "store" then
		if market_location.account then
			return market_location.account.store
		else
			return "bank"
		end
	end
end

local cached_configs = {
	['market_locations'] = {},
	['market_categories'] = {},
	['market_types'] = {},
}

function getConfigMarketLocation(market_id)
	if cached_configs.market_locations[market_id] then return Config.market_locations[market_id] end

	-- Assert that Config.market_locations exists
	assert(Config.market_locations, "^3The config '^1Config.market_locations^3' entry is missing. Please re-add it in the config")

	-- Assert that market_id is not nil
	assert(market_id, "^3The parameter '^1market_id^3' is missing. Please provide a valid market ID")

	-- Assert that market_id is a valid key in Config.market_locations
	assert(Config.market_locations[market_id], "^3The market ID '^1" .. tostring(market_id) .. "^3' does not exist in ^1Config.market_locations^3. Please provide a valid market ID")

	-- Assert that the required fields exist in the specified market location
	local location = Config.market_locations[market_id]
	assert(location.buy_price, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1buy_price^3' field. Please ensure each market location has a '^1buy_price^3' field")
	assert(location.sell_price, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1sell_price^3' field. Please ensure each market location has a '^1sell_price^3' field")
	assert(location.coord, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1coord^3' field. Please ensure each market location has a '^1coord^3' field")
	assert(#location.coord == 3, "^3The '^1coord^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must contain three values (x, y, z). Review your config file to correct it")
	assert(location.garage_coord, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1garage_coord^3' field. Please ensure each market location has a '^1garage_coord^3' field")
	assert(#location.garage_coord == 4, "^3The '^1garage_coord^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must contain four values (x, y, z, heading). Review your config file to correct it")
	assert(location.truck_parking_location, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1truck_parking_location^3' field. Please ensure each market location has a '^1truck_parking_location^3' field")
	assert(#location.truck_parking_location == 4, "^3The '^1truck_parking_location^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must contain four values (x, y, z, heading). Review your config file to correct it")
	assert(location.map_blip_coord, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1map_blip_coord^3' field. Please ensure each market location has a '^1map_blip_coord^3' field")
	assert(#location.map_blip_coord == 3, "^3The '^1map_blip_coord^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must contain three values (x, y, z). Review your config file to correct it")
	assert(location.sell_blip_coords, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1sell_blip_coords^3' field. Please ensure each market location has a '^1sell_blip_coords^3' field")
	assert(type(location.sell_blip_coords) == "table", "^3The '^1sell_blip_coords^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must be a table. Review your config file to correct it")
	for i, coord in ipairs(location.sell_blip_coords) do
		assert(#coord == 3, "^3Each coordinate in '^1sell_blip_coords^3' for market location ID '^1" .. tostring(market_id) .. "^3' must contain three values (x, y, z). Review your config file to correct it")
	end
	assert(location.deliveryman_coord, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1deliveryman_coord^3' field. Please ensure each market location has a '^1deliveryman_coord^3' field")
	assert(#location.deliveryman_coord == 3, "^3The '^1deliveryman_coord^3' field for market location ID '^1" .. tostring(market_id) .. "^3' must contain three values (x, y, z). Review your config file to correct it")
	assert(location.type, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1type^3' field. Please ensure each market location has a '^1type^3' field")
	assert(location.account, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have an '^1account^3' field. Please ensure each market location has an '^1account^3' field")
	assert(location.account.item, "^3The '^1account^3' field for market location ID '^1" .. tostring(market_id) .. "^3' does not have an '^1item^3' field. Please ensure each account field has an '^1item^3' field")
	assert(type(location.account.item) == "table", "^3The '^1item^3' field in '^1account^3' for market location ID '^1" .. tostring(market_id) .. "^3' must be a table. Review your config file to correct it")
	for i, item in ipairs(location.account.item) do
		assert(item.icon, "^3Each '^1item^3' in '^1account^3' for market location ID '^1" .. tostring(market_id) .. "^3' must have an '^1icon^3' field. Review your config file to correct it")
		assert(item.account, "^3Each '^1item^3' in '^1account^3' for market location ID '^1" .. tostring(market_id) .. "^3' must have an '^1account^3' field. Review your config file to correct it")
	end
	assert(location.account.store, "^3The '^1account^3' field for market location ID '^1" .. tostring(market_id) .. "^3' does not have a '^1store^3' field. Please ensure each account field has a '^1store^3' field")

	-- Mark it in cache that have been read and its correct
	cached_configs.market_locations[market_id] = true

	-- Return the market location
	return location
end

function getMarketCategory(category_id)
	if cached_configs.market_categories[category_id] then return Config.market_categories[category_id] end

	-- Assert that Config.market_categories exists
	assert(Config.market_categories, "^3The config '^1Config.market_categories^3' entry is missing. Please re-add it in the config")

	-- Assert that category_id is not nil
	assert(category_id, "^3The parameter '^1category_id^3' is missing. Please provide a valid category ID")

	-- Assert that category_id is a valid key in Config.market_categories
	assert(Config.market_categories[category_id], "^3The category ID '^1" .. tostring(category_id) .. "^3' does not exist in ^1Config.market_categories^3. Please provide a valid category ID")

	-- Assert that the required fields exist in the specified market category
	local category = Config.market_categories[category_id]
	assert(category.category_buy_price, "^3The category ID '^1" .. tostring(category_id) .. "^3' does not contain a valid '^1category_buy_price^3'. Review your config file to add it back")
	assert(category.category_sell_price, "^3The category ID '^1" .. tostring(category_id) .. "^3' does not contain a valid '^1category_sell_price^3'. Review your config file to add it back")
	assert(category.items, "^3The category ID '^1" .. tostring(category_id) .. "^3' does not contain a valid '^1items^3' field. Review your config file to add it back")
	assert(type(category.items) == "table", "^3The '^1items^3' field for category ID '^1" .. tostring(category_id) .. "^3' must be a table. Review your config file to correct it")

	-- Assert that each item in the category has the required fields
	for item_id, item in pairs(category.items) do
		assert(item.name, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1name^3' field. Review your config file to add it back")
		assert(item.price_to_customer, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1price_to_customer^3' field. Review your config file to add it back")
		assert(item.price_to_customer_min, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1price_to_customer_min^3' field. Review your config file to add it back")
		assert(item.price_to_customer_max, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1price_to_customer_max^3' field. Review your config file to add it back")
		assert(item.price_to_export, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1price_to_export^3' field. Review your config file to add it back")
		assert(item.price_to_owner, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have a '^1price_to_owner^3' field. Review your config file to add it back")
		assert(item.amount_to_owner, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have an '^1amount_to_owner^3' field. Review your config file to add it back")
		assert(item.amount_to_delivery, "^3The item ID '^1" .. tostring(item_id) .. "^3' in category ID '^1" .. tostring(category_id) .. "^3' does not have an '^1amount_to_delivery^3' field. Review your config file to add it back")
	end

	-- Mark it in cache that have been read and its correct
	cached_configs.market_categories[category_id] = true

	-- Return the market category
	return category
end

function getConfigMarketType(market_id)
	if cached_configs.market_types[market_id] then return Config.market_types[Config.market_locations[market_id].type] end

	-- Assert that Config.market_locations exists
	assert(Config.market_locations, "^3The config '^1Config.market_locations^3' entry is missing. Please re-add it in the config")

	-- Assert that Config.market_types exists
	assert(Config.market_types, "^3The config '^1Config.market_types^3' entry is missing. Please re-add it in the config")

	-- Assert that market_id is not nil
	assert(market_id, "^3The parameter '^1market_id^3' is missing. Please provide a valid market ID")

	-- Assert that market_id is a valid key in Config.market_locations
	assert(Config.market_locations[market_id], "^3The market ID '^1" .. tostring(market_id) .. "^3' does not exist in ^1Config.market_locations^3. Please provide a valid market ID")

	-- Assert that the type field exists in the specified market location
	local location = Config.market_locations[market_id]
	assert(location.type, "^3The market location for ID '^1" .. tostring(market_id) .. "^3' does not have a '^1type^3' field. Please ensure each market location has a '^1type^3' field")

	-- Assert that the type field value exists in Config.market_types
	local market_type = Config.market_types[location.type]
	assert(market_type, "^3The market type '^1" .. tostring(location.type) .. "^3' does not exist in ^1Config.market_types^3. Please provide a valid market type")

	-- Assert that the required fields exist in the specified market type
	assert(market_type.stock_capacity, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1stock_capacity^3' field. Please ensure each market type has a '^1stock_capacity^3' field")
	assert(market_type.upgrades, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have an '^1upgrades^3' field. Please ensure each market type has an '^1upgrades^3' field")
	assert(type(market_type.upgrades) == "table", "^3The '^1upgrades^3' field for market type '^1" .. tostring(location.type) .. "^3' must be a table. Review your config file to correct it")
	assert(market_type.max_employees, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1max_employees^3' field. Please ensure each market type has a '^1max_employees^3' field")
	assert(market_type.trucks, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1trucks^3' field. Please ensure each market type has a '^1trucks^3' field")
	assert(type(market_type.trucks) == "table", "^3The '^1trucks^3' field for market type '^1" .. tostring(location.type) .. "^3' must be a table. Review your config file to correct it")
	assert(market_type.max_purchasable_categories, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1max_purchasable_categories^3' field. Please ensure each market type has a '^1max_purchasable_categories^3' field")
	assert(market_type.categories, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1categories^3' field. Please ensure each market type has a '^1categories^3' field")
	assert(type(market_type.categories) == "table", "^3The '^1categories^3' field for market type '^1" .. tostring(location.type) .. "^3' must be a table. Review your config file to correct it")
	assert(market_type.default_categories, "^3The market type '^1" .. tostring(location.type) .. "^3' does not have a '^1default_categories^3' field. Please ensure each market type has a '^1default_categories^3' field")
	assert(type(market_type.default_categories) == "table", "^3The '^1default_categories^3' field for market type '^1" .. tostring(location.type) .. "^3' must be a table. Review your config file to correct it")

	-- Mark it in cache that have been read and its correct
	cached_configs.market_types[market_id] = true

	-- Return the market type
	return market_type
end

function Wrapper(source,key,event,check_permission,cb)
	if not vrp_ready or utils_outdated then
		if utils_outdated then
			TriggerClientEvent("stores:Notify",source,"error","The script requires 'lc_utils' in version "..utils_required_version..", but you currently have version "..Utils.Version..". Please update your 'lc_utils' script to the latest version: https://github.com/LeonardoSoares98/lc_utils/releases/latest/download/lc_utils.zip")
		end
		return
	end

	assert(source, "Source is nil at Wrapper")
	assert(key, "Key is nil at Wrapper")
	assert(event, "Event is nil at Wrapper")

	if cooldown[source] == nil then
		cooldown[source] = true
		local user_id = Utils.Framework.getPlayerId(source)
		if user_id then
			if check_permission == false or isOwner(key,user_id) or hasRole(key,user_id,event) then
				cb(user_id)
			else
				TriggerClientEvent("stores:Notify",source,"error",Utils.translate('insufficient_permission'))
			end
		else
			print("^8["..GetCurrentResourceName().."] ^3User not found: ^1"..(source or "nil").."^7")
		end
		SetTimeout(100,function()
			cooldown[source] = nil
		end)
	end
end

function openUI(source, key, reset, isMarket)
	local query = {}
	query.config = {}
	local user_id = Utils.Framework.getPlayerId(source)
	if user_id then
		-- Busca os dados do usuário
		local sql = "SELECT * FROM `store_business` WHERE market_id = @market_id";
		query.store_business = Utils.Database.fetchAll(sql,{['@market_id'] = key})[1];

		-- Busta tema do usuário
		local sql = "SELECT * FROM `store_users_theme` WHERE user_id = @user_id";
		query.store_users_theme = Utils.Database.fetchAll(sql,{['@user_id'] = user_id})[1];
		if query.store_users_theme == nil then
			local sql = "INSERT INTO `store_users_theme` (user_id,dark_theme) VALUES (@user_id,@dark_theme);";
			Utils.Database.execute(sql, {['@dark_theme'] = 1, ['@user_id'] = user_id});
			query.store_users_theme = { ['dark_theme'] = 1 }
		end
		
		-- Se não tiver dono se o usuário estiver abrindo o menu
		if isMarket and query.store_business == nil then
			query.store_business = {}
			query.store_business.stock = not Config.has_stock_when_unowed
			query.market_items = getDefaultItems(key)
			query.config.market_categories = getDefaultCategories(key);
			query.store_business.stock_prices = false

			-- Gera as default categories
			query.store_categories = {}
			for k, v in pairs(getConfigMarketType(key).default_categories) do
				table.insert(query.store_categories,{category=v})
			end
		else
			query.market_items = getItems(key)

			-- Busca a categoria que o mercado possui
			local sql = "SELECT * FROM `store_categories` WHERE market_id = @market_id";
			query.store_categories = Utils.Database.fetchAll(sql,{['@market_id'] = query.store_business.market_id})

			local count_stock = Utils.Table.tableLength(json.decode(query.store_business.stock))
			local count_items = getItemsCount(key)
			if count_items == 0 then 
				query.store_business.stock_variety = 0
			else
				query.store_business.stock_variety = (100*count_stock)/count_items
			end
		end

		if not isMarket then
			-- Busca os dados dos trabalhos
			local sql = "SELECT * FROM `store_jobs` WHERE market_id = @market_id";
			query.store_jobs = Utils.Database.fetchAll(sql,{['@market_id'] = query.store_business.market_id});

			-- Busca os dados dos historicos bancários
			local sql = "SELECT * FROM `store_balance` WHERE market_id = @market_id ORDER BY id DESC LIMIT 50";
			query.store_balance = Utils.Database.fetchAll(sql,{['@market_id'] = query.store_business.market_id});

			-- Busca os funcionarios
			local sql = "SELECT * FROM `store_employees` WHERE market_id = @market_id ORDER BY timer DESC";
			query.store_employees = Utils.Database.fetchAll(sql,{['@market_id'] = query.store_business.market_id});
			for k,v in pairs(query.store_employees) do
				v.name = Utils.Framework.getPlayerName(v.user_id)
			end

			-- Busca a categoria que o mercado possui
			local sql = "SELECT * FROM `store_categories` WHERE market_id = @market_id";
			query.store_categories = Utils.Database.fetchAll(sql,{['@market_id'] = query.store_business.market_id})

			-- busca os items que o mercado possui baseado nas categorias
			query.market_items = getItems(query.store_business.market_id)

			-- Busca o acesso do usuário
			local sql = "SELECT role FROM `store_employees` WHERE market_id = @market_id AND user_id = @user_id";
			local user_query = Utils.Database.fetchAll(sql, {['@market_id'] = query.store_business.market_id, ['@user_id'] = user_id});
			if user_query and user_query[1] then
				if isOwner(key, user_id) then
					query.role = 4
				else
					query.role = user_query[1].role
				end
			else
				query.role = 4
			end

			-- Busca os players online
			if not reset then
				query.players = Utils.Framework.getOnlinePlayers()
			end
			
			query.store_business.stock_amount = getStockAmount(query.store_business.stock)
		end

		-- Dinheiro do personagem
		query.available_money = Utils.Framework.getPlayerAccountMoney(source,getAccount(key,"store"))

		-- Busca as configs necessárias
		query.config.market_locations = Utils.Table.deepCopy(getConfigMarketLocation(key))
		query.config.market_types = Utils.Table.deepCopy(getConfigMarketType(key))
		query.config.market_categories = Utils.Table.deepCopy(Config.market_categories)
		query.config.roles_permissions = Utils.Table.deepCopy(Config.roles_permissions.ui_pages)
		query.config.disable_rename_business = Utils.Table.deepCopy(Config.disable_rename_business)
		query.config.warning = 0

		-- Gera o tipo de aviso pro dono
		if not isMarket and Config.clear_stores.active then
			local arr_stock = json.decode(query.store_business.stock)
			local count_stock = Utils.Table.tableLength(arr_stock)
			local count_items = getItemsCount(key)
			if query.store_business.stock_amount < (getConfigMarketType(key).stock_capacity)*(Config.clear_stores.min_stock_amount/100) then
				query.config.warning = 1
			elseif count_stock < count_items*(Config.clear_stores.min_stock_variety/100) then
				query.config.warning = 2
			else 
				local sql = "UPDATE `store_business` SET timer = @timer WHERE market_id = @market_id";
				Utils.Database.execute(sql, {['timer'] = os.time(), ['@market_id'] = key});
			end
		end
		-- Envia pro front-end
		TriggerClientEvent("stores:open",source, query, reset, isMarket or false)
	end
end

Citizen.CreateThread(function()
	Wait(1000)
	while not vrp_ready do Wait(100) end
	-- Config checker
	assert(Config.market_locations, "^3You have errors in your config file, consider fixing it or redownload the original config.^7")

	-- Check lc_utils dependency
	assert(GetResourceState('lc_utils') == 'started', "^3The '^1lc_utils^3' file is missing. Please refer to the documentation for installation instructions: ^7https://docs.lixeirocharmoso.com/owned_stores/installation^7")

	if Utils.Math.checkIfCurrentVersionisOutdated(utils_required_version, Utils.Version) then
		utils_outdated = true
		error("^3The script requires 'lc_utils' in version ^1"..utils_required_version.."^3, but you currently have version ^1"..Utils.Version.."^3. Please update your 'lc_utils' script to the latest version: https://github.com/LeonardoSoares98/lc_utils/releases/latest/download/lc_utils.zip^7")
	end

	-- Load langs
	Utils.loadLanguageFile(Lang)

	-- Startup queries
	runCreateTableQueries()
	Utils.Database.execute("UPDATE `store_jobs` SET progress = 0", {});

	-- Config validator
	local configs_to_validate = {
		{ config_path = {"group_map_blips"}, default_value = true }
	}
	Config = Utils.validateConfig(Config, configs_to_validate)

	Wait(1000)
	-- Check if all the columns exist in database
	local tables = {
		['store_business'] = {
			"market_id",
			"user_id",
			"stock",
			"stock_prices",
			"stock_upgrade",
			"truck_upgrade",
			"relationship_upgrade",
			"money",
			"total_money_earned",
			"total_money_spent",
			"goods_bought",
			"distance_traveled",
			"total_visits",
			"customers",
			"market_name",
			"market_color",
			"market_blip",
			"timer"
		},
		['store_balance'] = {
			"id",
			"market_id",
			"income",
			"title",
			"amount",
			"date",
			"hidden"
		},
		['store_jobs'] = {
			"id",
			"market_id",
			"name",
			"reward",
			"product",
			"amount",
			"progress",
			"trucker_contract_id"
		},
		['store_employees'] = {
			"market_id",
			"user_id",
			"jobs_done",
			"role",
			"timer",
		},
		['store_categories'] = {
			"id",
			"market_id",
			"category"
		},
		['store_users_theme'] = {
			"user_id",
			"dark_theme"
		}
	}
	local add_column_sqls = {
		['store_jobs'] = {
			['trucker_contract_id'] = "ALTER TABLE `store_jobs` ADD COLUMN `trucker_contract_id` INT UNSIGNED NULL DEFAULT NULL AFTER `progress`;",
		},
	}
	--[[
		SELECT COLUMN_TYPE, DATA_TYPE, COLUMN_NAME, COLUMN_DEFAULT, IS_NULLABLE FROM `information_schema`.`COLUMNS` 
		WHERE TABLE_SCHEMA = (SELECT DATABASE() AS default_schema) 
		AND TABLE_NAME='nome_tabela' 
		AND COLUMN_NAME='nome_coluna'
		ORDER BY ORDINAL_POSITION;
	]]
	local change_table_sqls = {}
	Utils.Database.validateTableColumns(tables,add_column_sqls,change_table_sqls)

	checkIfFrameworkWasLoaded()
	checkScriptName()

	searchForErrorsInConfig()
	searchForDataIssuesInDatabase()

	-- Start script threads
	checkLowStockThread()
end)

function checkIfFrameworkWasLoaded()
	assert(Utils.Framework.getPlayerId, "^3The framework wasn't loaded in the '^1lc_utils^3' resource. Please check if the '^1Config.framework^3' is correctly set to your framework, and make sure there are no errors in your file. For more information, refer to the documentation at '^7https://docs.lixeirocharmoso.com/^3'.^7")
end

function checkScriptName()
	assert(GetCurrentResourceName() == "lc_stores", "^3The script name does not match the expected resource name. Please ensure that the current resource name is set to '^1lc_stores^7'.")
end

function searchForErrorsInConfig()
	for _,v in pairs(Config.market_locations) do
		if not Config.market_types[v.type] then
			print("^1Error in your config:^3 Type '^1"..v.type .."^3' is not registered in Config.market_types^7")
		end
	end

	-- Iterate over all market locations to cache their configurations
	for market_id, _ in pairs(Config.market_locations) do
		getConfigMarketLocation(market_id)
	end

	-- Iterate over all market categories to cache their configurations
	for category_id, _ in pairs(Config.market_categories) do
		getMarketCategory(category_id)
	end

	-- Iterate over all market locations again to cache market types based on their type field
	for market_id, _ in pairs(Config.market_locations) do
		getConfigMarketType(market_id)
	end
end

function searchForDataIssuesInDatabase()
	-- Update the trucker data to the new name of the script folder
	if Config.trucker_logistics.enable then
		local update_5_2_0_sql_qb = [[
			UPDATE trucker_available_contracts
			SET external_data = REPLACE(external_data, 'qb_stores', 'lc_stores')
			WHERE external_data LIKE '%qb_stores%';]]
		Utils.Database.execute(update_5_2_0_sql_qb)
		local update_5_2_0_sql_esx = [[
			UPDATE trucker_available_contracts
			SET external_data = REPLACE(external_data, 'esx_stores', 'lc_stores')
			WHERE external_data LIKE '%esx_stores%';]]
		Utils.Database.execute(update_5_2_0_sql_esx)
	end

	-- Locations check
	local location_ids = {}
	for k, _ in pairs(Config.market_locations) do
		table.insert(location_ids, k)
	end
	local location_sql = string.format("SELECT market_id FROM `store_business` WHERE market_id NOT IN ('%s')", table.concat(location_ids, "','"))
	local query_locations = Utils.Database.fetchAll(location_sql, {})

	-- Categories check
	local categories_ids = {}
	for k, _ in pairs(Config.market_categories) do
		table.insert(categories_ids, k)
	end
	local categories_sql = string.format("SELECT id, category FROM `store_categories` WHERE category NOT IN ('%s')", table.concat(categories_ids, "','"))
	local query_categories = Utils.Database.fetchAll(categories_sql, {})

	-- Stock check
	local stock_sql = "SELECT market_id, stock, stock_prices FROM `store_business`"
	local query_stock = Utils.Database.fetchAll(stock_sql, {})

	-- Error messages
	local resourceName = GetCurrentResourceName()
	if #query_locations > 0 or #query_categories > 0 then
		print("^8[" ..resourceName.. "] DATABASE ISSUES:^3 The following issues were found in your database:^7")
	end

	for _, v in pairs(query_locations) do
		print(string.format("^8[%s]^3 Store ^1%s^3 is in your ^1store^3 tables but not in your config.^7", resourceName, v.market_id))
	end

	for _, v in pairs(query_categories) do
		print(string.format("^8[%s]^3 Category ^1%s^3 (ID %d) is in your ^1store_categories^3 table but not in your config.^7", resourceName, v.category, v.id))
	end

	for _, v in pairs(query_stock) do
		local function handleStockError(tableName, columnKey, errorMessage)
			print(string.format("^8[%s]^3 The %s ^1%s^3 has the following error '^1%s^3'. The %s of this store will be automatically reset.^7", resourceName, tableName, v.market_id, errorMessage, columnKey))
			local sql = string.format("UPDATE `%s` SET %s = '[]' WHERE market_id = @market_id", tableName, columnKey)
			Utils.Database.execute(sql, {["@market_id"] = v.market_id})
		end

		local stock, _, stockErrMessage = json.decode(v.stock)
		local stockPrices, _, stockPricesErrMessage = json.decode(v.stock_prices)

		if not stock then
			handleStockError("store_business", "stock", stockErrMessage)
		else
			local allowed_items = getItems(v.market_id)
			for item_id, _ in pairs(stock) do
				if not allowed_items[item_id] then
					print(string.format("^8[%s]^3 The store stock ^1%s^3 has the item '^1%s^3' that is not part of any of its categories. This item will be automatically removed from the stock.^7", resourceName, v.market_id, item_id))
					stock[item_id] = nil
				end
			end
			local sql = "UPDATE `store_business` SET stock = @stock WHERE market_id = @market_id"
			Utils.Database.execute(sql, {["@stock"] = json.encode(stock), ["@market_id"] = v.market_id})
		end

		if not stockPrices then
			handleStockError("store_business", "stock_prices", stockPricesErrMessage)
		else
			local allowed_items = getItems(v.market_id)
			for item_id, _ in pairs(stockPrices) do
				if not allowed_items[item_id] then
					print(string.format("^8[%s]^3 The store stock prices ^1%s^3 has the item '^1%s^3' that is not part of any of its categories. This item will be automatically removed from the stock prices.^7", resourceName, v.market_id, item_id))
					stockPrices[item_id] = nil
				end
			end
			local sql = "UPDATE `store_business` SET stock_prices = @stock WHERE market_id = @market_id"
			Utils.Database.execute(sql, {["@stock"] = json.encode(stockPrices), ["@market_id"] = v.market_id})
		end
	end

	if #query_locations > 0 or #query_categories > 0 then
		print("^8[" ..resourceName.. "] HOW TO RESOLVE ISSUES:^3 You can add missing data to the config or manually remove them from your database.^7")
	end
end

function runCreateTableQueries()
	if Config.create_table ~= false then
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_business` (
				`market_id` VARCHAR(50) NOT NULL DEFAULT '' COLLATE 'utf8mb4_general_ci',
				`user_id` VARCHAR(50) NOT NULL,
				`stock` LONGTEXT NOT NULL COLLATE 'utf8mb4_general_ci',
				`stock_prices` LONGTEXT NOT NULL COLLATE 'utf8mb4_general_ci',
				`stock_upgrade` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				`truck_upgrade` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				`relationship_upgrade` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				`money` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`total_money_earned` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`total_money_spent` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`goods_bought` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`distance_traveled` DOUBLE UNSIGNED NOT NULL DEFAULT '0',
				`total_visits` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`customers` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`market_name` VARCHAR(50) NULL DEFAULT NULL COLLATE 'utf8mb4_general_ci',
				`market_color` INT(10) UNSIGNED NULL DEFAULT NULL,
				`market_blip` INT(10) UNSIGNED NULL DEFAULT NULL,
				`timer` INT(10) UNSIGNED NOT NULL,
				PRIMARY KEY (`market_id`) USING BTREE
			)
			COLLATE='utf8mb4_general_ci'
			ENGINE=InnoDB
			;
		]])
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_balance` (
				`id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
				`market_id` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				`income` TINYINT(3) UNSIGNED NOT NULL,
				`title` VARCHAR(255) NOT NULL COLLATE 'utf8mb4_general_ci',
				`amount` INT(10) UNSIGNED NOT NULL,
				`date` INT(10) UNSIGNED NOT NULL,
				`hidden` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				PRIMARY KEY (`id`) USING BTREE
			)
			COLLATE='utf8mb4_general_ci'
			ENGINE=InnoDB
			;
		]])
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_categories` (
				`id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
				`market_id` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				`category` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				PRIMARY KEY (`id`) USING BTREE
			)
			COLLATE='utf8mb4_general_ci'
			ENGINE=InnoDB
			;
		]])
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_jobs` (
				`id` INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
				`market_id` VARCHAR(50) NOT NULL DEFAULT '' COLLATE 'utf8mb4_general_ci',
				`name` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				`reward` INT(10) UNSIGNED NOT NULL DEFAULT '0',
				`product` VARCHAR(50) NOT NULL DEFAULT '0' COLLATE 'utf8mb4_general_ci',
				`amount` INT(11) NOT NULL DEFAULT '0',
				`progress` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				`trucker_contract_id` INT(10) UNSIGNED NULL DEFAULT NULL,
				PRIMARY KEY (`id`) USING BTREE
			)
			COLLATE='utf8mb4_general_ci'
			ENGINE=InnoDB
			;
		]])
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_employees` (
				`market_id` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				`user_id` VARCHAR(50) NOT NULL COLLATE 'utf8mb4_general_ci',
				`jobs_done` INT(11) UNSIGNED NOT NULL DEFAULT '0',
				`role` TINYINT(3) UNSIGNED NOT NULL DEFAULT '0',
				`timer` INT(11) UNSIGNED NOT NULL,
				PRIMARY KEY (`market_id`, `user_id`) USING BTREE
			)
			COLLATE='utf8mb4_general_ci'
			ENGINE=InnoDB
			;
		]])
		Utils.Database.execute([[
			CREATE TABLE IF NOT EXISTS `store_users_theme` (
				`user_id` VARCHAR(50) NOT NULL COLLATE 'utf8_general_ci',
				`dark_theme` TINYINT(3) UNSIGNED NOT NULL DEFAULT '1',
				PRIMARY KEY (`user_id`) USING BTREE
			)
			COLLATE='utf8_general_ci'
			ENGINE=InnoDB
			;
		]])
	end
end