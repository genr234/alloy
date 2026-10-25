-- Make gamescope treat every display as plain sRGB SDR.
--
-- The PS5 drives HDMI through an internal DP-to-HDMI bridge that cannot
-- translate BT.2020 signalling; if gamescope sets BT2020_RGB colorimetry the
-- screen goes black. Workaround found by the ps5-linux-image CachyOS session.

gamescope.config.known_displays.alloy_ps5_srgb = {
    pretty_name = "PS5 (sRGB override)",
    hdr = {
        supported = false,
        force_enabled = false,
        eotf = gamescope.eotf.gamma22,
        max_content_light_level = 400,
        max_frame_average_luminance = 400,
        min_content_light_level = 0.5,
    },
    -- sRGB / Rec.709 primaries, D65 white point
    colorimetry = {
        r = { x = 0.640, y = 0.330 },
        g = { x = 0.300, y = 0.600 },
        b = { x = 0.150, y = 0.060 },
        w = { x = 0.3127, y = 0.3290 },
    },
    matches = function(display)
        -- Higher than any stock entry, so it wins for every display.
        return 100
    end,
}

debug("[alloy] registered PS5 sRGB display override")
