# SUSE's openQA tests
#
# Copyright © 2018 SUSE LLC
#
# Copying and distribution of this file, with or without modification,
# are permitted in any medium without royalty provided the copyright
# notice and this notice are preserved.  This file is offered as-is,
# without any warranty.

package qam;

use strict;

use base "Exporter";
use Exporter;

use testapi;
use utils;

our @EXPORT = qw(capture_state check_automounter is_patch_needed add_test_repositories remove_test_repositories advance_installer_window);

sub capture_state {
    my ($state, $y2logs) = @_;
    if ($y2logs) {    #save y2logs if needed
        assert_script_run "save_y2logs /tmp/y2logs_$state.tar.bz2";
        upload_logs "/tmp/y2logs_$state.tar.bz2";
        save_screenshot();
    }
    #upload ip status
    script_run("ip a | tee /tmp/ip_a_$state.log");
    upload_logs("/tmp/ip_a_$state.log");
    save_screenshot();
    script_run("ip r | tee /tmp/ip_r_$state.log");
    upload_logs("/tmp/ip_r_$state.log");
    save_screenshot();
    #upload dmesg
    script_run("dmesg > /tmp/dmesg_$state.log");
    upload_logs("/tmp/dmesg_$state.log");
    #upload journal
    script_run("journalctl -b > /tmp/journal_$state.log");
    upload_logs("/tmp/journal_$state.log");
}

sub check_automounter {
    my $ret = 1;
    while ($ret) {
        script_run(qq{[ \$(ls -ld /mounts | cut -d" " -f2) -gt 20 ]; echo automount-\$?- > /dev/$serialdev}, 0);
        $ret = wait_serial(qr/automount-\d-/);
        ($ret) = $ret =~ /automount-(\d)/;
        if ($ret) {
            script_run("rcypbind restart");
            script_run("rcautofs restart");
            sleep 5;
        }
    }
}

sub is_patch_needed {
    my $patch   = shift;
    my $install = shift // 0;

    my $patch_status = script_output("zypper -n info -t patch $patch");
    if ($patch_status =~ /Status\s*:\s+[nN]ot\s[nN]eeded/) {
        return $install ? $patch_status : 1;
    }
}

# Function that will add all test repos
sub add_test_repositories {
    my $counter = 0;

    my $oldrepo = get_var('PATCH_TEST_REPO');
    my @repos = split(/,/, get_var('MAINT_TEST_REPO', ''));
    # Be carefull. If you have defined both variables, the PATCH_TEST_REPO variable will always
    # have precedence over MAINT_TEST_REPO. So if MAINT_TEST_REPO is required to be installed
    # please be sure that the PATCH_TEST_REPO is empty.
    @repos = split(',', $oldrepo) if ($oldrepo);

    for my $var (@repos) {
        zypper_call("--no-gpg-check ar -f -n 'TEST_$counter' $var 'TEST_$counter'");
        $counter++;
    }
    # refresh repositories, inf 106 is accepted because repositories with test
    # can be removed before test start
    zypper_call('ref', exitcode => [0, 106]);
}

# Function that will remove all test repos
sub remove_test_repositories {

    type_string 'repos=($(zypper lr -e - | grep name=TEST | cut -d= -f2)); if [ ${#repos[@]} -ne 0 ]; then zypper rr ${repos[@]}; fi';
    type_string "\n";
}

sub advance_installer_window {
    my ($screenName) = @_;

    send_key $cmd{next};
    assert_screen $screenName;
}

1;
