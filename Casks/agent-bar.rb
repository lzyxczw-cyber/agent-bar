cask "agent-bar" do
  version "0.3.6"
  sha256 "0187d42dd9908e706000deaad528810b561e395b50169232504cf5f1ad2cae5f"

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
