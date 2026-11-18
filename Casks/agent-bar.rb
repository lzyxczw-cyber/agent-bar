cask "agent-bar" do
  version "0.3.8"
  sha256 "4dc759c05247cee06297339331b169ec501d71b5508dd6e250b8a90b5afb52ee"

  url "https://github.com/lzyxczw-cyber/agent-bar/releases/download/v#{version}/Agent-Bar-#{version}.dmg"
  name "Agent Bar"
  desc "Notch/menu-bar dashboard for local AI agent tasks and approvals"
  homepage "https://github.com/lzyxczw-cyber/agent-bar"

  depends_on macos: ">= :sonoma"

  app "Agent Bar.app"

  zap trash: [
    "~/Library/Application Support/AgentBar",
    "~/Library/Preferences/com.lzy.agentbar.plist",
  ]
end
