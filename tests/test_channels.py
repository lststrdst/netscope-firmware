from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / 'firmware/packages/luci-app-netscope-setup/files'

class ChannelsTests(unittest.TestCase):
    def test_routes_are_authenticated_post_and_status_is_read_only(self):
        text = (FILES / 'usr/lib/lua/luci/controller/netscope_setup.lua').read_text()
        for name in ('channel_select', 'channel_import'):
            self.assertIn("post('" + name + "')", text)
        self.assertIn("'pool_status'},call('channels')", text)

    def test_no_client_secret_storage_or_html_injection(self):
        text = (FILES / 'www/luci-static/netscope/channels.js').read_text(encoding='utf-8')
        for forbidden in ('localStorage', 'sessionStorage', 'innerHTML', 'console.log'):
            self.assertNotIn(forbidden, text)
        self.assertIn('token:root.dataset.token', text)
        self.assertIn('NetscopeImport.parse', text)
        self.assertIn('textContent', text)

    def test_pool_drafts_cannot_be_deleted_under_the_controller(self):
        text = (FILES / 'usr/lib/lua/luci/model/netscope_setup.lua').read_text(encoding='utf-8')
        delete = text.split('function M.delete(id)', 1)[1].split('function M.activate(id)', 1)[0]
        self.assertIn("require('luci.model.netscope_channels').pool().nodes", delete)
        self.assertLess(delete.index('need(node.id~=id'), delete.index('fs.unlink'))

    def test_recovery_ownership_and_opt_in(self):
        boot = (FILES / 'usr/libexec/netscope-voice-boot').read_text()
        for check in ('channel-switch.previous', 'user-paused', 'recover_switch', 'flock -w 5 -o'):
            self.assertIn(check, boot)
        manager = (FILES / 'usr/libexec/netscope-vpn-profile').read_text()
        self.assertIn('START_OWNED=1', manager)
        self.assertIn('[ "$START_OWNED" = 0 ] || cleanup', manager)
        makefile = (FILES.parent / 'Makefile').read_text()
        self.assertNotIn('postinst', makefile)
        for forbidden in ('reboot', 'network restart', 'firewall restart'):
            self.assertNotIn(forbidden, boot)

    def test_monitor_is_bounded_and_probes_the_active_transport(self):
        text = (FILES / 'usr/libexec/netscope-channels').read_text()
        for required in ('udp(2083)', 'processing.json', 'sleep(14)', '#s.events>30', 's.metrics[id]=nil'):
            self.assertIn(required, text)
        policy = (FILES / 'usr/lib/lua/luci/model/netscope_channel_policy.lua').read_text()
        self.assertIn('#history>20', policy)
        self.assertIn('>=300', policy)
        self.assertIn('>=2', policy)
        init = (FILES / 'etc/init.d/netscope-channels').read_text()
        self.assertIn('procd_set_param command /usr/libexec/netscope-channels daemon', init)
        self.assertNotIn('flock -n -o', init)
        self.assertIn("guard:lock('tlock')", text)
        self.assertIn('or M.selected()', text)
        self.assertIn('P.sample(s.metrics[id],false,nil,os.time())', text)
        model = (FILES / 'usr/lib/lua/luci/model/netscope_channels.lua').read_text()
        self.assertIn("'/etc/init.d/netscope-channels','running'", model)
