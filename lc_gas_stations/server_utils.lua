WebhookURL = "WEBHOOK" -- Webhook to send logs to discord

function beforeBuyGasStation(source,gas_station_id,price)
	-- Here you can do any verification when a player is buying a gas station, like if player has the permission to that or anything else you want to check before buy the gas station. return true or false
	return true
end

function afterBuyGasStation(source,gas_station_id,price)
	-- Here you can run any code right after the player purchase a gas station
end

function beforeStartContractImport(source,gas_station_id,total_price,amount)
	-- Here you can do any verification when a player is starting an import contract. return true or false
	return true
end

function afterFinishContractImport(source,gas_station_id,amount,new_stock_amount)
	-- Here you can run any code right after the player finish an import contract
end

function beforeStartContractExport(source,gas_station_id,amount)
	-- Here you can do any verification when a player is starting an export contract. return true or false
	return true
end

function afterFinishContractExport(source,gas_station_id,amount,money_received)
	-- Here you can run any code right after the player finish an export contract
end