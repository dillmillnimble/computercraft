monitor = peripheral.find("monitor")
function printToMonitor(text)
    if monitor then
        monitor.clear()
        monitor.setCursorPos(1, 1)
        monitor.write(text)
    else
        print("No monitor found.")
    end
end

