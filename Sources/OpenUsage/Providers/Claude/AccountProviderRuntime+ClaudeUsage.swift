import Foundation

struct ClaudeAccountState {
    let sessions: ClaudeSessions
    var session: ClaudeSession?
    var forcedReadsPending = false
    var restoredPlan: String?
    var restoredResets: MetricLine?
    var lastLines: [MetricLine] = []
}

extension AccountProviderRuntime {
    /// One usage read per pass, shared with any other card on the same login and never sent inside its
    /// 429 window. The profile and the reset grants are read in the secondary-reads slot instead, apart
    /// from it: Anthropic answers a grants read sent right after a usage read with a 429. A hub account
    /// reads its profile with its first usage read, so it shows its plan as soon as it appears.
    func refreshClaude(_ credential: AccountCredential) async throws -> ProviderUsage {
        let session = claudeSession(for: credential)
        let forced = claude.forcedReadsPending
        claude.forcedReadsPending = false
        let feed = isCheckingNewSignIn ? nil : claudeFeedLines()
        if let feed, !forced, session.wait(at: now()) != nil || !claude.lastLines.isEmpty && !claudeTopUpDue(session) {
            return claudeUsage(session, lines: ClaudeFeed.merge(feed, over: claude.lastLines))
        }
        if let wait = session.wait(at: now()) { throw ProviderError.rateLimited(retryAfter: wait) }
        let client = ClaudeUsageClient(httpClient: http)
        let tokens: OAuthTokens
        let response: HTTPResponse
        do {
            (tokens, response) = try await authorizedRead(credential, grant: ClaudeLogin.refresh) { tokens in
                let request: @MainActor () async throws -> HTTPResponse = { try await client.fetchUsage(accessToken: tokens.accessToken) }
                // Cards on one login share a request to save its budget, but a new sign-in must prove itself.
                return try await isCheckingNewSignIn ? session.send(at: now(), request) : session.usage(at: now(), request)
            }
        } catch ProviderError.rateLimited where feed != nil {
            return claudeUsage(session, lines: ClaudeFeed.merge(feed ?? [], over: claude.lastLines))
        }
        let lines = try ClaudeUsageMapper.mapUsageResponse(response)
        claude.lastLines = lines
        if forced {
            if session.resetGrants.isOlder(than: RefreshSetting.forcedResetGrantsMinimumAge, at: now()) {
                await readClaudeResetGrants(session, accessToken: tokens.accessToken)
            }
            try? await readClaudeProfile(session, tokens: tokens)
        } else if account.hub != nil, session.planRead.value == nil, session.planRead.isDue(at: now()) {
            try? await readClaudeProfile(session, tokens: tokens)
        }
        return claudeUsage(session, lines: lines)
    }

    private func claudeUsage(_ session: ClaudeSession, lines: [MetricLine]) -> ProviderUsage {
        var lines = lines
        if let resets = claudeResetsLine(session) { lines.append(resets) }
        let plan = session.planRead.value
        return ProviderUsage(plan: plan, lines: lines, lineTitles: ClaudeUsageMapper.lineTitles(plan: plan))
    }

    private func claudeFeedLines() -> [MetricLine]? {
        guard account.kind == .claude, account.hub == nil, claude.sessions.hasOneLogin else { return nil }
        return ClaudeFeed.liveLines(now: now())
    }

    private func claudeTopUpDue(_ session: ClaudeSession) -> Bool {
        guard let last = session.lastReadAt else { return true }
        return now().timeIntervalSince(last) >= ClaudeSession.feedTopUpInterval
    }

    /// A Claude pause doesn't stop the logs: the refresh still runs, and sends nothing inside the window.
    var hasLiveLocalData: Bool { account.kind == .claude && (localUsage != nil || (claude.session != nil && claudeFeedLines() != nil)) }

    var rereadsHourlyOnManualRefresh: Bool { account.kind != .claude }

    func holdsRead(forced: Bool) -> Bool {
        guard account.kind == .claude, claudeFeedLines() == nil, let session = claude.session else { return false }
        return session.readIsHeld(forced: forced, at: now())
    }

    func restoreClaude(_ snapshot: ProviderSnapshot) {
        let historyTitles = Set(widgetDescriptors.compactMap { $0.historyRow?.title })
        claude.lastLines = snapshot.lines.filter { $0.label != ClaudeResetGrantStatus.lineLabel && !historyTitles.contains($0.label) }
        claude.restoredPlan = snapshot.plan
        claude.restoredResets = snapshot.line(label: ClaudeResetGrantStatus.lineLabel)
    }

    func refreshHourlyReads(of snapshot: ProviderSnapshot) async -> ProviderSnapshot? {
        guard account.kind == .claude else { return nil }
        let launched = claude.session == nil ? try? await loadCredential() : nil
        guard let session = claude.session ?? launched.map({ claudeSession(for: $0) }) else { return nil }
        let profileDue = session.planRead.isDue(at: now())
        let grantsDue = session.resetGrants.isOlder(than: RefreshSetting.secondaryReadInterval, at: now())
        guard profileDue || grantsDue, session.wait(at: now()) == nil,
              let tokens = try? await freshTokens(try await loadCredential(), grant: ClaudeLogin.refresh)
        else { return nil }
        if profileDue { try? await readClaudeProfile(session, tokens: tokens) }
        if grantsDue { await readClaudeResetGrants(session, accessToken: tokens.accessToken) }
        var updated = snapshot
        updated.plan = session.planRead.value
        let titles = ClaudeUsageMapper.lineTitles(plan: updated.plan)
        updated.lineTitles = titles.isEmpty ? nil : titles
        updated.lines.removeAll { $0.label == ClaudeResetGrantStatus.lineLabel }
        if let resets = claudeResetsLine(session) { updated.lines.append(resets) }
        return updated == snapshot ? nil : updated
    }

    func readClaudeProfile(_ session: ClaudeSession, tokens: OAuthTokens) async throws {
        do {
            let client = ClaudeUsageClient(httpClient: http)
            let response = try await session.send(at: now()) { try await client.fetchProfile(accessToken: tokens.accessToken) }
            if ProviderError.isAuthFailure(response) { throw ProviderError.signInExpired(.claude) }
            let profile = try ClaudeUsageClient.decodeProfile(response)
            if tokens.extras[OAuthTokens.identityKey] == nil {
                if case .oauth(var stored)? = try? await loadCredential() {
                    stored.extras[OAuthTokens.identityKey] = profile.identity
                    try? await replaceCredential(.oauth(stored))
                }
                claude.sessions.rekey(session, to: profile.identity)
            }
            if let uuid = profile.organization?.uuid, UUID(uuidString: uuid) != nil { session.organizationUUID = uuid }
            session.planRead.record(ClaudeUsageMapper.formatLivePlan(profile: profile), at: now())
        } catch {
            guard !Task.isCancelled else { throw error }
            AppLog.warn(LogTag.plugin("claude"), "plan lookup failed; retrying in an hour: \(error.localizedDescription)")
            session.planRead.record(nil, at: now())
            throw error
        }
    }

    private func claudeSession(for credential: AccountCredential) -> ClaudeSession {
        let session = claude.sessions.session(for: credential.identity ?? "card:\(account.cardID)")
        if session.planRead.value == nil, let plan = claude.restoredPlan {
            session.planRead.record(plan, at: now())
            session.planRead.forget()
        }
        claude.session = session
        return session
    }

    func claudeResetsLine(_ session: ClaudeSession) -> MetricLine? {
        guard let check = session.resetGrants.check else { return claude.restoredResets }
        return check.status?.line(now: now())
    }
}
