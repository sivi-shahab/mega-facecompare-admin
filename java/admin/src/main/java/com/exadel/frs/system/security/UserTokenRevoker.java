package com.exadel.frs.system.security;

import com.exadel.frs.system.security.client.OAuthClientProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.oauth2.common.OAuth2AccessToken;
import org.springframework.security.oauth2.provider.token.store.JdbcTokenStore;
import org.springframework.stereotype.Component;

/**
 * Security fix (audit MFC-01): revokes every OAuth2 access and refresh token of a user, so that a password
 * change, password reset or account deletion really ends all existing sessions (including sessions held by
 * someone who stole a cookie or the old password).
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class UserTokenRevoker {

    private final JdbcTokenStore tokenStore;
    private final OAuthClientProperties oAuthClientProperties;

    public int revokeAllTokens(final String username) {
        if (username == null) {
            return 0;
        }
        int revoked = 0;
        for (var client : oAuthClientProperties.getClients().values()) {
            for (OAuth2AccessToken token : tokenStore.findTokensByClientIdAndUserName(client.getClientId(), username)) {
                if (token.getRefreshToken() != null) {
                    tokenStore.removeRefreshToken(token.getRefreshToken());
                }
                tokenStore.removeAccessToken(token);
                revoked++;
            }
        }
        log.info("Revoked {} token(s) after a credential change", revoked);
        return revoked;
    }
}
