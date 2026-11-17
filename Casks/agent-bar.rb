cask "agent-bar" do
  version "0.3.4"
  sha256 "3c72074c99ce5790aa189b3d40ef34949d13505dd45e6d917757e6799fbb1269"

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
