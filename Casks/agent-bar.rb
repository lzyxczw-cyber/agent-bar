cask "agent-bar" do
  version "0.3.3"
  sha256 "1ba6f24e94f2d36b0ca0a7de81551013ac16abbcc1f8dcca81ef9c127065ffb7"

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
