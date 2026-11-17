# 签名与公证

本仓库不包含任何签名私钥、App Store Connect API Key 或公证凭据。下面是在本机构建可分发 DMG 的通用流程。

## 1. 准备证书

需要 **Developer ID Application** 证书。创建证书需要 Apple Developer Account Holder 权限。

```text
Xcode → Settings → Accounts → Manage Certificates
→ + → Developer ID Application
```

如果 Xcode 或 API 报 `This operation can only be performed by the Account Holder`，
可以尝试在 `developer.apple.com/account/resources/certificates/list` 网页端创建，
需要先本地生成一份 CSR：

```bash
openssl req -new -newkey rsa:2048 -nodes \
  -keyout private.key -out request.csr \
  -subj "/CN=<Your Name>/O=<Your Name>/C=US" -sha256
```

然后上传 `request.csr`、下载 `.cer`，并导入钥匙串：

```bash
openssl x509 -inform DER -in developerID_application.cer -out cert.pem
openssl pkcs12 -export -inkey private.key -in cert.pem \
  -out cert.p12 -name "Developer ID Application: <Your Name> (<TEAM_ID>)" \
  -passout pass:<p12-password>
security import cert.p12 -k "$HOME/Library/Keychains/login.keychain-db" \
  -P <p12-password> -T /usr/bin/codesign -T /usr/bin/security -T /usr/bin/productbuild
security find-identity -v -p codesigning
```

## 2. 公证凭据

任选一种：

- App Store Connect API Key：`NOTARY_KEY` / `NOTARY_KEY_ID` / `NOTARY_ISSUER`
- 已保存的 keychain profile：`NOTARY_PROFILE`
- Apple ID + app-specific password：`NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD`

推荐 API Key，不需要把 Apple ID 密码写进脚本。

## 3. 签名 + 公证 + staple

```bash
CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
NOTARIZE=1 \
NOTARY_KEY="$HOME/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8" \
NOTARY_KEY_ID="<KEY_ID>" \
NOTARY_ISSUER="<ISSUER_UUID>" \
./package.sh
```

如果 codesign 在后台打包时卡在钥匙串授权弹窗，可以创建一把专用钥匙串并设置
`apple-tool:,apple:` partition list，然后通过 `CODESIGN_KEYCHAIN` 显式传入：

```bash
CODESIGN_KEYCHAIN="$HOME/Library/Keychains/agentbar-signing.keychain-db" \
CODESIGN_IDENTITY="Developer ID Application: <Your Name> (<TEAM_ID>)" \
NOTARIZE=1 ... ./package.sh
```

## 4. 验收

```bash
hdiutil attach -nobrowse -mountpoint /tmp/agentbar-dmg Agent-Bar-<version>.dmg
codesign --verify --strict --verbose=2 "/tmp/agentbar-dmg/Agent Bar.app"
spctl -a -vv "/tmp/agentbar-dmg/Agent Bar.app"
xcrun stapler validate Agent-Bar-<version>.dmg
hdiutil detach /tmp/agentbar-dmg
```

预期 Gatekeeper 显示：

```text
accepted
source=Notarized Developer ID
```
