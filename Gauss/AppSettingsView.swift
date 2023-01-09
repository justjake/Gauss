//
//  AppSettingsView.swift
//  Gauss
//
//  Created by Jake Teton-Landis on 12/15/22.
//

import SwiftUI

enum ModelDownloadSource: String, Identifiable, CaseIterable {
    case githubRelease
    case custom

    var id: String { rawValue }
}

enum GithubReleaseSetting: String, Identifiable, CaseIterable {
    case compatible
    case tag

    var id: String { rawValue }
}

let DEFAULT_GITHUB_OWNER = "justjake"
let DEFAULT_GITHUB_REPO = "Gauss"
let DEFAULT_GITHUB_TAG = "models-v1.0.0"

class AppSettingsModel: ObservableObject {
    static var inst = AppSettingsModel()

    @AppStorage("modelDownloadSource") var modelDownloadSource: ModelDownloadSource = .githubRelease

    // Github setings
    @AppStorage("githubOwner") var owner = DEFAULT_GITHUB_OWNER
    @AppStorage("githubRepo") var repo = DEFAULT_GITHUB_REPO
    @AppStorage("githubReleaseType") var releaseType = GithubReleaseSetting.compatible
    @AppStorage("githubTag") var tag = ""

    // Custom URL settings
    @AppStorage("customURL") var customURL = URL(string: "http://localhost:8080")!
    @AppStorage("customNamespace") var customNamespace = "custom"

    var assetHost: AssetHost {
        switch modelDownloadSource {
        case .githubRelease:
            let selectedTag = {
                switch releaseType {
                case .compatible: return DEFAULT_GITHUB_TAG
                case .tag:
                    if tag.isEmpty {
                        return DEFAULT_GITHUB_TAG
                    }
                    return tag
                }
            }()
            return GithubRelease(owner: owner, repo: repo, tag: selectedTag)
        case .custom:
            return TestAssetHost(baseURL: customURL, localPrefix: customNamespace)
        }
    }
}

struct AppSettingsView: View {
    @ObservedObject var appSettings = AppSettingsModel.inst

    var assetHost: AssetHost {
        switch appSettings.modelDownloadSource {
        case .githubRelease:
            let selectedTag = {
                switch appSettings.releaseType {
                case .compatible: return DEFAULT_GITHUB_TAG
                case .tag:
                    if appSettings.tag.isEmpty {
                        return DEFAULT_GITHUB_TAG
                    }
                    return appSettings.tag
                }
            }()
            return GithubRelease(owner: appSettings.owner, repo: appSettings.repo, tag: selectedTag)
        case .custom:
            return TestAssetHost(baseURL: appSettings.customURL, localPrefix: appSettings.customNamespace)
        }
    }

    var body: some View {
        VStack {
            List {
                ForEach(GaussModel.allCases, id: \.self) { model in
                    ModelInstallView(model: model, assetHost: assetHost, scheduler: GaussKernel.inst)
                }
            }

            DisclosureGroup("Advanced") {
                Form {
                    Picker("Download models from", selection: appSettings.$modelDownloadSource) {
                        Text("Github (default)").tag(ModelDownloadSource.githubRelease)
                        Text("Custom host").tag(ModelDownloadSource.custom)
                    }

                    switch appSettings.modelDownloadSource {
                    case .githubRelease:
                        GithubReleaseForm(owner: appSettings.$owner, repo: appSettings.$repo, releaseType: appSettings.$releaseType, tag: appSettings.$tag)
                    case .custom:
                        CustomSourceForm(url: appSettings.$customURL, namespace: appSettings.$customNamespace)
                    }
                }
            }.padding(.horizontal)

            Button("Download and install models") {
                Task {
                    let rule = DownloadAllModelsRule(assetHost: assetHost)
                    let job = GaussKernel.inst.schedule(rule: rule)
                    await job.wait()
                    await AssetManager.inst.refreshAvailableModels()
                }
            }.padding(.bottom)
        }
    }
}

struct GithubReleaseForm: View {
    @Binding var owner: String
    @Binding var repo: String
    @Binding var releaseType: GithubReleaseSetting
    @Binding var tag: String

    var body: some View {
        Form {
            TextField("Owner", text: $owner)
            TextField("Repo", text: $repo)
            Picker("Release", selection: $releaseType) {
                Text("Default").tag(GithubReleaseSetting.compatible)
                Text("Tag").tag(GithubReleaseSetting.tag)
            }
            if releaseType == .tag {
                TextField("Tag", text: $tag)
            } else {
                TextField("Tag", text: .constant(DEFAULT_GITHUB_TAG)).disabled(true)
            }

            Button("Reset to defaults") {
                owner = DEFAULT_GITHUB_OWNER
                repo = DEFAULT_GITHUB_REPO
                releaseType = .compatible
            }
        }
    }
}

struct CustomSourceForm: View {
    @Binding var url: URL
    @Binding var namespace: String

    var body: some View {
        Form {
            TextField("URL", text: .constant(url.description)).disabled(true)
            TextField("Namespace", text: $namespace)
        }
    }
}

struct ModelInstallView: View {
    var model: GaussModel
    var assetHost: AssetHost
    var downloadRule: DownloadModelRule {
        DownloadModelRule(model: model, assetHost: assetHost)
    }

    @ObservedObject var assetManager = AssetManager.inst
    var scheduler: RuleScheduler?

    var hasModel: Bool {
        assetManager.cachedModelLocations.keys.contains(model)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(model.description).font(.title3)

                ForEach(downloadRule.inputs, id: \.self) { url in
                    Text("Input: \(url)")
                }

                ForEach(downloadRule.intermediateOutputs, id: \.self) { url in
                    Text("Intermediate: \(url)")
                }

                ForEach(downloadRule.outputs, id: \.self) { url in
                    Text("Output: \(url)")
                }

                // TODO: show model status
                // TODO: if present, allow re-intalling
                // TODO: if absent, allow installing
                Divider()
            }.multilineTextAlignment(.leading)

            if scheduler != nil {
                if hasModel {
                    Button("Reinstall") { Task { await reinstall() } }
                } else {
                    Button("Install") { Task { await install() } }
                }
            }
        }
    }

    func reinstall() async {
        do {
            try downloadRule.removeOutputs()
            try downloadRule.removeIntermediateOutputs()
            await assetManager.refreshAvailableModels()
        } catch {
            print("Re-install error:", error)
        }
        await install()
    }

    func install() async {
        await scheduler?.schedule(rule: downloadRule).wait()
        await assetManager.refreshAvailableModels()
    }
}

struct AppSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AppSettingsView()
    }
}
