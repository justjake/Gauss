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

struct AppSettingsView: View {
    @AppStorage("modelDownloadSource") private var modelDownloadSource: ModelDownloadSource = .githubRelease

    // Github setings
    @AppStorage("githubOwner") private var owner = DEFAULT_GITHUB_OWNER
    @AppStorage("githubRepo") private var repo = DEFAULT_GITHUB_REPO
    @AppStorage("githubReleaseType") private var releaseType = GithubReleaseSetting.compatible
    @AppStorage("githubTag") private var tag = ""

    // Custom URL settings
    @AppStorage("customURL") private var customURL = URL(string: "http://localhost:8080")!
    @AppStorage("customNamespace") private var customNamespace = "custom"

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

    var body: some View {
        Group {
            Form {
                Picker("Download models from", selection: $modelDownloadSource) {
                    Text("Github (default)").tag(ModelDownloadSource.githubRelease)
                    Text("Custom host").tag(ModelDownloadSource.custom)
                }

                switch modelDownloadSource {
                case .githubRelease:
                    GithubReleaseForm(owner: $owner, repo: $repo, releaseType: $releaseType, tag: $tag)
                case .custom:
                    CustomSourceForm(url: $customURL, namespace: $customNamespace)
                }
            }

            Text("Models")

            Text("TODO: show list of installed models here and allow deleting / re-installing")
        }.padding()

        List {
            ModelInstallView(model: .sd1_4, assetHost: assetHost)
            ModelInstallView(model: .sd1_5, assetHost: assetHost)
            ModelInstallView(model: .sd2_0, assetHost: assetHost)
        }

        Button("Download and install models") {
            Task {
                let rule = DownloadAllModelsRule(assetHost: assetHost)
                try! await RuleScheduler.executeInOrder(rule.rules)
            }
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
        }.padding()
    }
}

struct CustomSourceForm: View {
    @Binding var url: URL
    @Binding var namespace: String

    var body: some View {
        Form {
            TextField("URL", text: .constant(url.description)).disabled(true)
            TextField("Namespace", text: $namespace)
        }.padding()
    }
}

struct ModelInstallView: View {
    var model: GaussModel
    var assetHost: AssetHost
    var downloadRule: DownloadModelRule {
        DownloadModelRule(model: model, assetHost: assetHost)
    }

    var body: some View {
        VStack {
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
        }.multilineTextAlignment(.leading)
    }
}

struct AppSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AppSettingsView()
    }
}
