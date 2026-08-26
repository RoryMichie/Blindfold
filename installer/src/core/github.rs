use serde::Deserialize;

use super::paths::{GITHUB_API_URL, GITHUB_MAIN_COMMIT_URL, GITHUB_RELEASES_URL, USER_AGENT};

#[derive(Debug, Deserialize, Clone)]
pub struct ReleaseInfo {
    pub tag_name: String,
    #[serde(default)]
    pub body: String,
    #[serde(default)]
    pub prerelease: bool,
    #[serde(default)]
    pub assets: Vec<Asset>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Asset {
    pub name: String,
    pub browser_download_url: String,
}

fn client() -> Result<reqwest::blocking::Client, String> {
    reqwest::blocking::Client::builder()
        .user_agent(USER_AGENT)
        .timeout(std::time::Duration::from_secs(15))
        .build()
        .map_err(|e| format!("Failed to create HTTP client: {}", e))
}

pub fn fetch_latest_release() -> Result<ReleaseInfo, String> {
    let resp = client()?
        .get(GITHUB_API_URL)
        .send()
        .map_err(|e| format!("Failed to connect to GitHub: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API returned status {}", resp.status()));
    }

    resp.json::<ReleaseInfo>()
        .map_err(|e| format!("Failed to parse release info: {}", e))
}

pub fn fetch_all_releases() -> Result<Vec<ReleaseInfo>, String> {
    let resp = client()?
        .get(GITHUB_RELEASES_URL)
        .send()
        .map_err(|e| format!("Failed to connect to GitHub: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API returned status {}", resp.status()));
    }

    resp.json::<Vec<ReleaseInfo>>()
        .map_err(|e| format!("Failed to parse releases: {}", e))
}

#[derive(Debug, Deserialize)]
struct CommitInfo {
    sha: String,
}

/// Short SHA of the latest commit on main, for labeling development installs.
pub fn fetch_main_commit_sha() -> Result<String, String> {
    let resp = client()?
        .get(GITHUB_MAIN_COMMIT_URL)
        .send()
        .map_err(|e| format!("Failed to connect to GitHub: {}", e))?;

    if !resp.status().is_success() {
        return Err(format!("GitHub API returned status {}", resp.status()));
    }

    let info = resp
        .json::<CommitInfo>()
        .map_err(|e| format!("Failed to parse commit info: {}", e))?;
    Ok(info.sha.chars().take(7).collect())
}

/// The mod's release zip, by EXACT name (super::paths::MOD_ZIP_NAME).
/// Releases carry other zips too as the mod-manager tooling lands, so
/// "first .zip" is no longer a safe rule.
pub fn find_zip_asset(assets: &[Asset]) -> Option<&Asset> {
    assets.iter().find(|a| a.name == super::paths::MOD_ZIP_NAME)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn find_zip_asset_exact_name() {
        // Other zips ahead of it in the asset list must not win.
        let assets = vec![
            Asset {
                name: "ModManagerBundle.zip".to_string(),
                browser_download_url: "https://example.com/bundle.zip".to_string(),
            },
            Asset {
                name: "Blindfold.zip".to_string(),
                browser_download_url: "https://example.com/mod.zip".to_string(),
            },
        ];
        let result = find_zip_asset(&assets);
        assert!(result.is_some());
        assert_eq!(result.unwrap().name, "Blindfold.zip");
        assert_eq!(result.unwrap().browser_download_url, "https://example.com/mod.zip");
    }

    #[test]
    fn find_zip_asset_rejects_other_zips() {
        // A .zip that is not the exact mod asset is not a fallback.
        let assets = vec![Asset {
            name: "Blindfold-v0.1.0.zip".to_string(),
            browser_download_url: "https://example.com/mod.zip".to_string(),
        }];
        assert!(find_zip_asset(&assets).is_none());
    }

    #[test]
    fn find_zip_asset_no_zip() {
        let assets = vec![Asset {
            name: "source.tar.gz".to_string(),
            browser_download_url: "https://example.com/source.tar.gz".to_string(),
        }];
        assert!(find_zip_asset(&assets).is_none());
    }

    #[test]
    fn find_zip_asset_empty() {
        let assets: Vec<Asset> = vec![];
        assert!(find_zip_asset(&assets).is_none());
    }

    #[test]
    fn deserialize_release_info() {
        let json = r#"{
            "tag_name": "v0.1.0",
            "body": "Some release notes",
            "assets": [
                {
                    "name": "Blindfold.zip",
                    "browser_download_url": "https://example.com/Blindfold.zip"
                }
            ]
        }"#;
        let info: ReleaseInfo = serde_json::from_str(json).unwrap();
        assert_eq!(info.tag_name, "v0.1.0");
        assert_eq!(info.assets.len(), 1);
    }

    #[test]
    fn deserialize_release_info_missing_optional_fields() {
        let json = r#"{"tag_name": "v0.1.0"}"#;
        let info: ReleaseInfo = serde_json::from_str(json).unwrap();
        assert_eq!(info.tag_name, "v0.1.0");
        assert_eq!(info.body, "");
        assert!(info.assets.is_empty());
    }
}
