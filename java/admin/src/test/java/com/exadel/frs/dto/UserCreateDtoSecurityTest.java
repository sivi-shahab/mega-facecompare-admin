package com.exadel.frs.dto;

import static org.junit.jupiter.api.Assertions.assertFalse;

import org.junit.jupiter.api.Test;

/** Regression test for security audit MFC-02: passwords must never appear in toString (and therefore logs). */
class UserCreateDtoSecurityTest {

    @Test
    void toStringDoesNotContainPassword() {
        UserCreateDto dto = UserCreateDto.builder()
                .email("dummy@example.invalid").firstName("Dummy").lastName("User").password("DummyPass-7f3a91").build();
        assertFalse(dto.toString().contains("DummyPass-7f3a91"));
        ChangePasswordDto change = new ChangePasswordDto("OldDummy-1", "NewDummy-2");
        assertFalse(change.toString().contains("OldDummy-1") || change.toString().contains("NewDummy-2"));
    }
}
