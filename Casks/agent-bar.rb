cask "agent-bar" do
  version "0.3.9"
  sha256 "5d9d2dcc6553fb1dfaeff419922da3d1983f680372f40bff8e7f266fc959486c"

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
