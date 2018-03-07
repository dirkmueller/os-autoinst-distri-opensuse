# SUSE's openQA tests
#
# Copyright © 2009-2013 Bernhard M. Wiedemann
# Copyright © 2012-2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

use strict;
use warnings;
use testapi qw(check_var get_var get_required_var set_var);
use lockapi;
use needle;
use version_utils qw(is_opensuse is_sle);
use File::Find;
use File::Basename;

BEGIN {
    unshift @INC, dirname(__FILE__) . '/../../lib';
}
use utils;
use version_utils qw(is_jeos is_gnome_next is_krypton_argon is_leap is_tumbleweed is_rescuesystem is_desktop_installed is_opensuse is_sle is_staging);
use main_common;

init_main();

sub cleanup_needles {
    remove_common_needles;
    if (!get_var("LIVECD")) {
        unregister_needle_tags("ENV-LIVECD-1");
    }
    else {
        unregister_needle_tags("ENV-LIVECD-0");
    }
    if (!check_var("DE_PATTERN", "mate")) {
        remove_desktop_needles("mate");
    }
    if (!check_var("DE_PATTERN", "lxqt")) {
        remove_desktop_needles("lxqt");
    }
    if (!check_var("DE_PATTERN", "enlightenment")) {
        remove_desktop_needles("enlightenment");
    }
    if (!check_var("DE_PATTERN", "awesome")) {
        remove_desktop_needles("awesome");
    }
    if (!is_jeos) {
        unregister_needle_tags('ENV-FLAVOR-JeOS-for-kvm');
    }
    if (!is_leap) {
        unregister_needle_tags('ENV-LEAP-1');
    }
    if (!is_tumbleweed) {
        unregister_needle_tags('ENV-VERSION-Tumbleweed');
    }
    for my $flavor (qw(Krypton-Live Argon-Live)) {
        if (!check_var('FLAVOR', $flavor)) {
            unregister_needle_tags("ENV-FLAVOR-$flavor");
        }
    }
    # unregister christmas needles unless it is December where they should
    # appear. Unused needles should be disregarded by admin delete then
    unregister_needle_tags('CHRISTMAS') unless get_var('WINTER_IS_THERE');
}

# we need some special handling for the openSUSE winter needles
my @time = localtime();
set_var('WINTER_IS_THERE', 1) if ($time[4] == 11 || $time[4] == 0);

my $distri = testapi::get_required_var('CASEDIR') . '/lib/susedistribution.pm';
require $distri;
testapi::set_distribution(susedistribution->new());

unless (get_var("DESKTOP")) {
    if (check_var("VIDEOMODE", "text")) {
        set_var("DESKTOP", "textmode");
    }
    else {
        set_var("DESKTOP", "kde");
    }
}

if (check_var('DESKTOP', 'minimalx')) {
    set_var("NOAUTOLOGIN", 1);
    set_var("XDMUSED",     1);
}

# openSUSE specific variables
set_var('LEAP', '1') if is_leap;
set_var("WALLPAPER", '/usr/share/wallpapers/openSUSEdefault/contents/images/1280x1024.jpg');

# set KDE and GNOME, ...
set_var(uc(get_var('DESKTOP')), 1);

# for GNOME pressing enter is enough to login bernhard
if (check_var('DESKTOP', 'minimalx')) {
    set_var('DM_NEEDS_USERNAME', 1);
}

# now Plasma 5 is default KDE desktop
# openSUSE version less than or equal to 13.2 have to set KDE4 variable as 1
if (check_var('DESKTOP', 'kde') && !get_var('KDE4')) {
    set_var("PLASMA5", 1);
}

# ZDUP_IN_X imply ZDUP
if (get_var('ZDUP_IN_X')) {
    set_var('ZDUP', 1);
}

if (   get_var("WITH_UPDATE_REPO")
    || get_var("WITH_MAIN_REPO")
    || get_var("WITH_DEBUG_REPO")
    || get_var("WITH_SOURCE_REPO")
    || get_var("WITH_UNTESTED_REPO"))
{
    set_var('HAVE_ADDON_REPOS', 1);
}

$needle::cleanuphandler = \&cleanup_needles;

# dump other important ENV:
logcurrentenv(
    qw(ADDONURL BTRFS DESKTOP LIVETEST LVM
      MOZILLATEST NOINSTALL UPGRADE USBBOOT ZDUP
      ZDUPREPOS TEXTMODE DISTRI NOAUTOLOGIN QEMUCPU QEMUCPUS RAIDLEVEL
      ENCRYPT INSTLANG QEMUVGA DOCRUN UEFI DVD GNOME KDE ISO ISO_MAXSIZE
      LIVECD NETBOOT NOIMAGES QEMUVGA SPLITUSR VIDEOMODE)
);

sub updates_is_applicable {
    # we don't want live systems to run out of memory or virtual disk space.
    # Applying updates on a live system would not be persistent anyway.
    # Also, applying updates on BOOT_TO_SNAPSHOT is useless.
    # Also, updates on INSTALLONLY do not match the meaning
    return !get_var('INSTALLONLY') && !get_var('BOOT_TO_SNAPSHOT') && !get_var('DUALBOOT') && !get_var('UPGRADE') && !is_livesystem;
}

sub guiupdates_is_applicable {
    return get_var("DESKTOP") =~ /gnome|kde|xfce|lxde/ && !check_var("FLAVOR", "Rescue-CD");
}

sub have_addn_repos {
    return !get_var("NET") && !get_var("EVERGREEN") && get_var("SUSEMIRROR") && !is_staging();
}

sub load_fixup_network {
    # openSUSE 13.2's (and earlier) systemd has broken rules for virtio-net, not applying predictable names (despite being configured)
    # A maintenance update breaking networking names sounds worse than just accepting that 13.2 -> TW breaks with virtio-net
    # At this point, the system has been updated, but our network interface changed name (thus we lost network connection)
    my @old_hdds = qw(openSUSE-13.1-gnome openSUSE-13.2);
    return unless grep { check_var('HDDVERSION', $_) } @old_hdds;

    loadtest "fixup/network_configuration";

}

sub load_fixup_firewall {
    # The openSUSE 13.1 GNOME disk image has the firewall disabled
    # Upon upgrading to a new system the service state is supposed to remain as pre-configured
    # If the service is disabled here, we enable it here
    # For the older openSUSE base images we also see a problem with the
    # firewall being disabled since
    # https://build.opensuse.org/request/show/483163
    # which seems to be in openSUSE Tumbleweed since 20170413
    return unless get_var('HDDVERSION', '') =~ /openSUSE-(13.1-gnome)/;
    loadtest 'fixup/enable_firewall';
}

sub load_consoletests_minimal {
    return unless (is_staging() && get_var('UEFI') || is_gnome_next || is_krypton_argon);
    # Stagings should test yast2-bootloader in miniuefi at least but not all
    loadtest "console/consoletest_setup";
    loadtest "console/textinfo";
    loadtest "console/hostname";
    if (!get_var("LIVETEST")) {
        loadtest "console/yast2_bootloader";
    }
    loadtest "console/consoletest_finish";
}

sub load_otherDE_tests {
    if (get_var("DE_PATTERN")) {
        my $de = get_var("DE_PATTERN");
        loadtest "console/consoletest_setup";
        loadtest "console/hostname";
        loadtest "update/zypper_clear_repos";
        loadtest "console/install_otherDE_pattern";
        loadtest "console/consoletest_finish";
        loadtest "x11/${de}_reconfigure_openqa";
        loadtest "x11/reboot_icewm";
        # here comes the actual desktop specific test
        if ($de =~ /^awesome$/)       { load_awesome_tests(); }
        if ($de =~ /^enlightenment$/) { load_enlightenment_tests(); }
        if ($de =~ /^mate$/)          { load_mate_tests(); }
        if ($de =~ /^lxqt$/)          { load_lxqt_tests(); }
        loadtest "x11/shutdown";
        return 1;
    }
    return 0;
}

sub load_awesome_tests {
    loadtest "x11/awesome_menu";
    loadtest "x11/awesome_xterm";
}

sub load_enlightenment_tests {
    loadtest "x11/enlightenment_first_start";
    loadtest "x11/terminology";
}

sub load_lxqt_tests {
}

sub load_mate_tests {
    loadtest "x11/mate_terminal";
}

sub install_online_updates {
    return 0 unless get_var('INSTALL_ONLINE_UPDATES');

    my @tests = qw(
      console/zypper_disable_deltarpm
      console/zypper_add_repos
      update/zypper_up
      console/console_reboot
      shutdown/shutdown
    );

    for my $test (@tests) {
        loadtest "$test";
    }

    return 1;
}

sub load_system_update_tests {
    return unless updates_is_applicable;
    if (need_clear_repos) {
        loadtest "update/zypper_clear_repos";
    }

    if (guiupdates_is_applicable()) {
        loadtest "update/prepare_system_for_update_tests";
        if (check_var("DESKTOP", "kde")) {
            loadtest "update/updates_packagekit_kde";
        }
        else {
            loadtest "update/updates_packagekit_gpk";
        }
        loadtest "update/check_system_is_updated";
    }
    else {
        loadtest "update/zypper_up";
    }
}

sub load_applicationstests {
    return 0 unless get_var("APPTESTS");

    my @tests;

    my %testsuites = (
        chromium           => ['x11/chromium'],
        evolution          => ['x11/evolution'],
        gimp               => ['x11/gimp'],
        hexchat            => ['x11/hexchat'],
        libzypp            => ['console/zypper_in', 'console/yast2_i'],
        MozillaFirefox     => [qw(x11/firefox x11/firefox_audio)],
        MozillaThunderbird => ['x11/thunderbird'],
        vlc                => ['x11/vlc'],
        xchat              => ['x11/xchat'],
        xterm              => ['x11/xterm'],
    );

    # adjust $pos below if you modify the position of
    # consoletest_finish!
    if (get_var('BOOT_HDD_IMAGE')) {
        if (get_var('MM_CLIENT')) {
            @tests = split(/,/, get_var('APPTESTS'));
        }
        else {
            @tests = (
                'console/consoletest_setup',
                'console/import_gpg_keys',
                'update/zypper_up',
                'console/install_packages',
                'console/zypper_add_repos',
                'console/qam_zypper_patch',
                'console/qam_verify_package_install',
                'console/console_reboot',
                # position -2
                'console/consoletest_finish',
                # position -1
                'x11/shutdown'
            );
        }
    }
    else {
        @tests = (
            'console/consoletest_setup',
            'update/zypper_up',
            'console/qam_verify_package_install',
            # position -2
            'console/consoletest_finish',
            # position -1
            'x11/shutdown'
        );
    }

    if (my $val = get_var("INSTALL_PACKAGES", '')) {
        for my $pkg (split(/ /, $val)) {
            next unless exists $testsuites{$pkg};
            # yeah, pretty crappy method. insert
            # consoletests before consoletest_finish and x11
            # tests before shutdown
            for my $t (@{$testsuites{$pkg}}) {
                my $pos = -1;
                $pos = -2 if ($t =~ /^console\//);
                splice @tests, $pos, 0, $t;
            }
        }
    }

    for my $test (@tests) {
        loadtest "$test";
    }

    return 1;
}

sub load_slenkins_tests {
    if (get_var("SLENKINS_CONTROL")) {
        unless (get_var("SUPPORT_SERVER")) {
            loadtest "slenkins/login";
            loadtest "slenkins/slenkins_control_network";
        }
        loadtest "slenkins/slenkins_control";
        return 1;
    }
    elsif (get_var("SLENKINS_NODE")) {
        loadtest "slenkins/login";
        loadtest "slenkins/slenkins_node";
        return 1;
    }
    return 0;
}

sub load_default_tests {
    load_boot_tests();
    load_inst_tests();
    return 1 if get_var('EXIT_AFTER_START_INSTALL');
    load_reboot_tests();
}

# load the tests in the right order
if (is_kernel_test()) {
    load_kernel_tests();
}
elsif (get_var("NETWORKD")) {
    boot_hdd_image();
    load_networkd_tests();
}
elsif (get_var("WICKED")) {
    boot_hdd_image();
    load_wicked_tests();
}
elsif (get_var('NFV')) {
    load_nfv_tests();
}
elsif (get_var("REGRESSION")) {
    load_common_x11;
}
elsif (is_mediacheck) {
    load_svirt_vm_setup_tests;
    loadtest "installation/mediacheck";
}
elsif (is_memtest) {
    if (!get_var("OFW")) {    #no memtest on PPC
        load_svirt_vm_setup_tests;
        loadtest "installation/memtest";
    }
}
elsif (get_var("FILESYSTEM_TEST")) {
    boot_hdd_image;
    load_filesystem_tests();
}
elsif (get_var("SYSCONTAINER_IMAGE_TEST")) {
    boot_hdd_image;
    load_syscontainer_tests();
}
elsif (get_var('GNUHEALTH')) {
    boot_hdd_image;
    loadtest 'gnuhealth/gnuhealth_install';
    loadtest 'gnuhealth/gnuhealth_setup';
    loadtest 'gnuhealth/tryton_install';
    loadtest 'gnuhealth/tryton_preconfigure';
    loadtest 'gnuhealth/tryton_first_time';
}

elsif (is_rescuesystem) {
    loadtest "installation/rescuesystem";
    loadtest "installation/rescuesystem_validate_131";
}
elsif (get_var("LINUXRC")) {
    loadtest "linuxrc/system_boot";
}
elsif (get_var('Y2UITEST_NCURSES')) {
    load_yast2_ncurses_tests;
}
elsif (get_var('Y2UITEST_GUI')) {
    load_yast2_gui_tests;
}
elsif (get_var("SUPPORT_SERVER")) {
    loadtest "support_server/boot";
    loadtest "support_server/login";
    loadtest "support_server/setup";
    unless (load_slenkins_tests()) {    # either run the slenkins control node or just wait for connections
        loadtest "support_server/wait_children";
    }
}
elsif (get_var("WINDOWS")) {
    loadtest "installation/win10_installation";
    loadtest "installation/win10_firstboot";
    loadtest "installation/win10_reboot";
    loadtest "installation/win10_shutdown";
}
elsif (ssh_key_import) {
    load_ssh_key_import_tests;
}
elsif (get_var("ISO_IN_EXTERNAL_DRIVE")) {
    load_iso_in_external_tests();
    load_inst_tests();
    load_reboot_tests();
}
elsif (get_var('MM_CLIENT')) {
    boot_hdd_image;
    load_applicationstests;
}
elsif (get_var('SECURITYTEST')) {
    boot_hdd_image;
    loadtest "console/consoletest_setup";
    loadtest "console/hostname";
    if (check_var('SECURITYTEST', 'core')) {
        load_security_tests_core;
    }
    elsif (check_var('SECURITYTEST', 'web')) {
        load_security_tests_web;
    }
    elsif (check_var('SECURITYTEST', 'misc')) {
        load_security_tests_misc;
    }
    elsif (check_var('SECURITYTEST', 'crypt')) {
        load_security_tests_crypt;
    }
}
elsif (get_var('SYSTEMD_TESTSUITE')) {
    load_systemd_patches_tests;
}
elsif (get_var('DOCKER_IMAGE_TEST')) {
    boot_hdd_image;
    load_docker_tests;
    loadtest 'console/docker_image';
}
else {
    if (get_var("LIVETEST") || get_var('LIVE_INSTALLATION')) {
        load_boot_tests();
        loadtest "installation/finish_desktop";
        if (get_var('LIVE_INSTALLATION')) {
            loadtest "installation/live_installation";
            load_inst_tests();
            load_reboot_tests();
            return 1;
        }
    }
    elsif (get_var("AUTOYAST")) {
        load_boot_tests();
        load_autoyast_tests();
        load_reboot_tests();
    }
    elsif (installzdupstep_is_applicable()) {
        load_boot_tests();
        load_zdup_tests();
    }
    elsif (get_var("BOOT_HDD_IMAGE")) {
        boot_hdd_image;
        if (get_var("ISCSI_SERVER")) {
            set_var('INSTALLONLY', 1);
            loadtest "iscsi/iscsi_server";
        }
        if (get_var("ISCSI_CLIENT")) {
            set_var('INSTALLONLY', 1);
            loadtest "iscsi/iscsi_client";
        }
        if (get_var("REMOTE_CONTROLLER")) {
            loadtest "remote/remote_controller";
            load_inst_tests();
        }
    }
    elsif (get_var("REMOTE_TARGET")) {
        load_boot_tests();
        loadtest "remote/remote_target";
        load_reboot_tests();
    }
    elsif (is_jeos) {
        load_boot_tests();
        loadtest "jeos/firstrun";
        loadtest "console/force_cron_run";
        loadtest "jeos/diskusage";
        loadtest "jeos/root_fs_size";
        loadtest "jeos/mount_by_label";
        if (get_var("SCC_EMAIL") && get_var("SCC_REGCODE")) {
            loadtest "jeos/sccreg";
        }
    }
    else {
        return 1 if load_default_tests;
    }

    unless (install_online_updates()
        || load_applicationstests()
        || load_extra_tests()
        || load_virtualization_tests()
        || load_otherDE_tests()
        || load_slenkins_tests())
    {
        load_fixup_network();
        load_fixup_firewall();
        load_system_update_tests();
        load_rescuecd_tests();
        if (consolestep_is_applicable) {
            load_consoletests();
        }
        elsif (is_staging() && get_var('UEFI') || is_gnome_next || is_krypton_argon) {
            load_consoletests_minimal();
        }
        load_x11tests();
        if (get_var('ROLLBACK_AFTER_MIGRATION') && (snapper_is_applicable())) {
            load_rollback_tests();
        }
    }
}

load_common_opensuse_sle_tests;

1;
# vim: set sw=4 et:
