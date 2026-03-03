local charger = peripheral.find("ae2:charger")

while true do
    if charger.items() then
        charger.pushItem("top", "ae2:charged_certus_quartz_crystal", 1)
    end
    while not charger.getEnergy() == charger.getEnergyCapacity() do
        sleep(0.5)
    end
    charger.pullItem("top", "ae2:certus_quartz_crystal", 1)
end