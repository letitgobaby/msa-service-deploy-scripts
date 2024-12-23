package com.service.sample;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProfileController {

    @Value("${app.profile}")
    private String activeProfile;

    @GetMapping("/profile")
    public String getProfile() {
        return "Current active profile: " + activeProfile;
    }
}