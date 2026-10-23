# Lines where the LLM and the engine split differently

For each line, mark which is right: `E` (engine), `L` (LLM), `both`, or `neither` (and how it should split).

### 1. argocd-version line 1

    |  BuildDate: 2026-06-01T10:00:00Z

- E: (not data)
- L: BuildDate: | 2026-06-01T10:00:00Z
- verdict: 

### 2. argocd-version line 2

    |  GoVersion: go1.22.4

- E: (not data)
- L: GoVersion: | go1.22.4
- verdict: 

### 3. arpwatch line 0

    |Jul  7 14:20:01 gateway arpwatch: new station 192.168.1.88 a4:5e:60:c1:2f:9b eth0

- E: Jul  7 14:20:01 | gateway | arpwatch: | new station 192.168.1.88 a4:5e:60:c1:2f:9b eth0
- L: Jul  7 14:20:01 | gateway | arpwatch: | new station | 192.168.1.88 | a4:5e:60:c1:2f:9b | eth0
- verdict: 

### 4. arpwatch line 1

    |Jul  7 14:21:15 gateway arpwatch: changed ethernet address 192.168.1.24 3c:22:fb:88:1d:0a eth0

- E: Jul  7 14:21:15 | gateway | arpwatch: | changed ethernet address 192.168.1.24 3c:22:fb:88:1d:0a eth0
- L: Jul  7 14:21:15 | gateway | arpwatch: | changed ethernet address | 192.168.1.24 | 3c:22:fb:88:1d:0a | eth0
- verdict: 

### 5. arpwatch line 2

    |Jul  7 14:22:47 gateway arpwatch: new activity 192.168.1.90 de:ad:be:ef:00:02 eth0

- E: Jul  7 14:22:47 | gateway | arpwatch: | new activity 192.168.1.90 de:ad:be:ef:00:02 eth0
- L: Jul  7 14:22:47 | gateway | arpwatch: | new activity | 192.168.1.90 | de:ad:be:ef:00:02 | eth0
- verdict: 

### 6. arpwatch line 3

    |Jul  7 14:25:33 gateway arpwatch: flip flop 192.168.1.55 b8:27:eb:44:9f:12 eth0

- E: Jul  7 14:25:33 | gateway | arpwatch: | flip flop 192.168.1.55 b8:27:eb:44:9f:12 eth0
- L: Jul  7 14:25:33 | gateway | arpwatch: | flip flop | 192.168.1.55 | b8:27:eb:44:9f:12 | eth0
- verdict: 

### 7. arpwatch line 4

    |Jul  7 14:30:12 gateway arpwatch: bogon 10.0.0.99 aa:bb:cc:dd:ee:01 eth0

- E: Jul  7 14:30:12 | gateway | arpwatch: | bogon 10.0.0.99 aa:bb:cc:dd:ee:01 eth0
- L: Jul  7 14:30:12 | gateway | arpwatch: | bogon | 10.0.0.99 | aa:bb:cc:dd:ee:01 | eth0
- verdict: 

### 8. brew-info-multi line 0

    |==> git

- E: (not data)
- L: git
- verdict: 

### 9. brew-info-multi line 6

    |==> jq

- E: (not data)
- L: jq
- verdict: 

### 10. brew-info-multi line 12

    |==> ripgrep

- E: (not data)
- L: ripgrep
- verdict: 

### 11. etcdctl-endpoint-health line 0

    |10.0.0.21:2379 is healthy: successfully committed proposal: took = 5.123ms

- E: 10.0.0.21:2379 | is | healthy: | successfully | committed | proposal: | took | = | 5.123ms
- L: 10.0.0.21:2379 is | healthy: | successfully committed proposal: | took = | 5.123ms
- verdict: 

### 12. etcdctl-endpoint-health line 1

    |10.0.0.22:2379 is healthy: successfully committed proposal: took = 4.871ms

- E: 10.0.0.22:2379 | is | healthy: | successfully | committed | proposal: | took | = | 4.871ms
- L: 10.0.0.22:2379 is | healthy: | successfully committed proposal: | took = | 4.871ms
- verdict: 

### 13. etcdctl-endpoint-health line 2

    |10.0.0.23:2379 is healthy: successfully committed proposal: took = 6.402ms

- E: 10.0.0.23:2379 | is | healthy: | successfully | committed | proposal: | took | = | 6.402ms
- L: 10.0.0.23:2379 is | healthy: | successfully committed proposal: | took = | 6.402ms
- verdict: 

### 14. etcdctl-endpoint-health line 3

    |10.0.0.24:2379 is healthy: successfully committed proposal: took = 5.998ms

- E: 10.0.0.24:2379 | is | healthy: | successfully | committed | proposal: | took | = | 5.998ms
- L: 10.0.0.24:2379 is | healthy: | successfully committed proposal: | took = | 5.998ms
- verdict: 

### 15. etcdctl-endpoint-health line 4

    |10.0.0.25:2379 is healthy: successfully committed proposal: took = 7.115ms

- E: 10.0.0.25:2379 | is | healthy: | successfully | committed | proposal: | took | = | 7.115ms
- L: 10.0.0.25:2379 is | healthy: | successfully committed proposal: | took = | 7.115ms
- verdict: 

### 16. fail2ban-jail-sshd line 0

    |Status for the jail: sshd

- E: Status | for | the | jail: | sshd
- L: Status for the jail: | sshd
- verdict: 

### 17. fail2ban-jail-sshd line 1

    ||- Filter

- E: |- | Filter
- L: Filter
- verdict: 

### 18. fail2ban-jail-sshd line 2

    ||  |- Currently failed:	4

- E: | | |- | Currently | failed: | 4
- L: Currently failed: | 4
- verdict: 

### 19. fail2ban-jail-sshd line 3

    ||  |- Total failed:	8821

- E: | | |- | Total | failed: | 8821
- L: Total failed: | 8821
- verdict: 

### 20. fail2ban-jail-sshd line 4

    ||  `- File list:	/var/log/auth.log

- E: | | `- | File | list: | /var/log/auth.log
- L: File list: | /var/log/auth.log
- verdict: 

### 21. fail2ban-jail-sshd line 5

    |`- Actions

- E: `- | Actions
- L: Actions
- verdict: 

### 22. fail2ban-jail-sshd line 6

    |   |- Currently banned:	2

- E: |- | Currently | banned: | 2
- L: Currently banned: | 2
- verdict: 

### 23. fail2ban-jail-sshd line 7

    |   `- Total banned:	441

- E: `- | Total | banned: | 441
- L: Total banned: | 441
- verdict: 

### 24. git-ls-tree line 0

    |100644 blob a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0	.gitignore

- E: 100644 blob a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 | .gitignore
- L: 100644 | blob | a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0 | .gitignore
- verdict: 

### 25. git-ls-tree line 1

    |100644 blob b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1	README.md

- E: 100644 blob b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1 | README.md
- L: 100644 | blob | b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1 | README.md
- verdict: 

### 26. git-ls-tree line 2

    |040000 tree c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2	src

- E: 040000 tree c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2 | src
- L: 040000 | tree | c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2 | src
- verdict: 

### 27. git-ls-tree line 3

    |040000 tree d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3	tests

- E: 040000 tree d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3 | tests
- L: 040000 | tree | d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3 | tests
- verdict: 

### 28. git-ls-tree line 4

    |100644 blob e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4	Makefile

- E: 100644 blob e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4 | Makefile
- L: 100644 | blob | e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4 | Makefile
- verdict: 

### 29. git-ls-tree line 5

    |120000 blob f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5	latest

- E: 120000 blob f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5 | latest
- L: 120000 | blob | f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5 | latest
- verdict: 

### 30. git-shortlog-email line 0

    |    42	Alice Smith <alice@example.com>

- E: 42 | Alice Smith <alice@example.com>
- L: 42 | Alice Smith | <alice@example.com>
- verdict: 

### 31. git-shortlog-email line 1

    |    17	Bob Jones, Jr. <bob@example.com>

- E: 17 | Bob Jones, Jr. <bob@example.com>
- L: 17 | Bob Jones, Jr. | <bob@example.com>
- verdict: 

### 32. git-shortlog-email line 2

    |     3	Carlos Ruiz <carlos@example.com>

- E: 3 | Carlos Ruiz <carlos@example.com>
- L: 3 | Carlos Ruiz | <carlos@example.com>
- verdict: 

### 33. glmark2-run line 3

    |    OpenGL Information

- E: (not data)
- L: OpenGL Information
- verdict: 

### 34. glmark2-run line 8

    |[build] use-vbo=false: FPS: 4821 FrameTime: 0.207 ms

- E: [build] use-vbo=false: | FPS: 4821 FrameTime: 0.207 ms
- L: build] | use-vbo= | false: | FPS: | 4821 | FrameTime: | 0.207 ms
- verdict: 

### 35. glmark2-run line 9

    |[build] use-vbo=true: FPS: 5210 FrameTime: 0.192 ms

- E: [build] use-vbo=true: | FPS: 5210 FrameTime: 0.192 ms
- L: build] | use-vbo= | true: | FPS: | 5210 | FrameTime: | 0.192 ms
- verdict: 

### 36. glmark2-run line 10

    |[texture] texture-filter=nearest: FPS: 4482 FrameTime: 0.223 ms

- E: [texture] texture-filter=nearest: | FPS: 4482 FrameTime: 0.223 ms
- L: texture] | texture-filter= | nearest: | FPS: | 4482 | FrameTime: | 0.223 ms
- verdict: 

### 37. groups line 0

    |alice : alice sudo users docker

- E: alice : | alice sudo users docker
- L: alice : | alice | sudo | users | docker
- verdict: 

### 38. host_a line 1

    |;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 5

- E: (not data)
- L: opcode: | QUERY, | status: | NOERROR, | id: | 5
- verdict: 

### 39. host_a line 2

    |;; flags: qr aa rd ra; QUERY: 1, ANSWER: 5, AUTHORITY: 0, ADDITIONAL: 0

- E: (not data)
- L: flags: | qr aa rd ra; | QUERY: | 1, | ANSWER: | 5, | AUTHORITY: | 0, | ADDITIONAL: | 0
- verdict: 

### 40. host_a line 4

    |;; QUESTION SECTION:

- E: (not data)
- L: QUESTION SECTION:
- verdict: 

### 41. host_a line 5

    |;example.com.			IN	ANY

- E: (not data)
- L: ;example.com. | IN | ANY
- verdict: 

### 42. host_a line 7

    |;; ANSWER SECTION:

- E: (not data)
- L: ANSWER SECTION:
- verdict: 

### 43. httpie-headers line 0

    |HTTP/1.1 200 OK

- E: (not data)
- L: HTTP/1.1 | 200 | OK
- verdict: 

### 44. ip-neigh line 0

    |192.168.1.1 dev eth0 lladdr 00:1a:2b:3c:4d:5e REACHABLE

- E: 192.168.1.1 dev | eth0 lladdr | 00:1a:2b:3c:4d:5e | REACHABLE
- L: 192.168.1.1 | dev | eth0 | lladdr | 00:1a:2b:3c:4d:5e | REACHABLE
- verdict: 

### 45. ip-neigh line 1

    |192.168.1.12 dev eth0 lladdr a4:5e:60:c1:2f:9b STALE

- E: 192.168.1.12 dev | eth0 lladdr | a4:5e:60:c1:2f:9b | STALE
- L: 192.168.1.12 | dev | eth0 | lladdr | a4:5e:60:c1:2f:9b | STALE
- verdict: 

### 46. ip-neigh line 2

    |192.168.1.24 dev eth0 lladdr 3c:22:fb:88:1d:0a REACHABLE

- E: 192.168.1.24 dev | eth0 lladdr | 3c:22:fb:88:1d:0a | REACHABLE
- L: 192.168.1.24 | dev | eth0 | lladdr | 3c:22:fb:88:1d:0a | REACHABLE
- verdict: 

### 47. ip-neigh line 3

    |192.168.1.55 dev wlan0 lladdr b8:27:eb:44:9f:12 DELAY

- E: 192.168.1.55 dev | wlan0 lladdr | b8:27:eb:44:9f:12 | DELAY
- L: 192.168.1.55 | dev | wlan0 | lladdr | b8:27:eb:44:9f:12 | DELAY
- verdict: 

### 48. ip-neigh line 4

    |10.0.0.1 dev eth0 lladdr 52:54:00:aa:bb:cc STALE

- E: 10.0.0.1 dev | eth0 lladdr | 52:54:00:aa:bb:cc | STALE
- L: 10.0.0.1 | dev | eth0 | lladdr | 52:54:00:aa:bb:cc | STALE
- verdict: 

### 49. journalctl-short-gaps line 0

    |Jul 11 07:55:01 dev-box systemd[1]: Starting Daily apt download activities...

- E: Jul 11 07:55:01 | dev-box | systemd[ | 1]: | Starting Daily apt download activities...
- L: Jul 11 07:55:01 | dev-box | systemd[1]: | Starting Daily apt download activities...
- verdict: 

### 50. journalctl-short-gaps line 3

    |Jul 11 08:00:14 dev-box sshd[812]: Accepted publickey for mgallag from 192.168.1.10 port 51224 ssh2

- E: Jul 11 08:00:14 | dev-box | sshd[ | 812]: | Accepted publickey for mgallag from 192.168.1.10 port 51224 ssh2
- L: Jul 11 08:00:14 | dev-box | sshd[812]: | Accepted publickey for mgallag from 192.168.1.10 port 51224 ssh2
- verdict: 

### 51. journalctl-short-gaps line 4

    |Jul 11 08:01:00 dev-box CRON[1442]: pam_unix(cron:session): session opened for user root

- E: Jul 11 08:01:00 | dev-box | CRON[ | 1442]: | pam_unix(cron:session): session opened for user root
- L: Jul 11 08:01:00 | dev-box | CRON[1442]: | pam_unix(cron:session): session opened for user root
- verdict: 

### 52. journalctl-short-gaps line 5

    |Jul 11 08:01:00 dev-box CRON[1442]:

- E: Jul 11 08:01:00 | dev-box | CRON[ | 1442]:
- L: Jul 11 08:01:00 | dev-box | CRON[1442]:
- verdict: 

### 53. kubectl-get-pv line 0

    |NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                          STORAGECLASS   REASON   AGE

- E: NAME | CAPACITY | ACCESS MODES | RECLAIM POLICY | STATUS | CLAIM | STORAGECLASS   REASON | AGE
- L: NAME | CAPACITY | ACCESS MODES | RECLAIM POLICY | STATUS | CLAIM | STORAGECLASS | REASON | AGE
- verdict: 

### 54. ls-l line 0

    |total 48

- E: (not data)
- L: total | 48
- verdict: 

### 55. ls-l line 1

    |drwxr-xr-x 2 root root 4096 Jul  6 09:12 bin

- E: drwxr-xr-x | 2 | root | root | 4096 | Jul | 6 | 09:12 | bin
- L: drwxr-xr-x | 2 | root | root | 4096 | Jul  6 09:12 | bin
- verdict: 

### 56. ls-l line 2

    |-rw-r--r-- 1 alice users 1024 Jul  5 18:03 notes.txt

- E: -rw-r--r-- | 1 | alice | users | 1024 | Jul | 5 | 18:03 | notes.txt
- L: -rw-r--r-- | 1 | alice | users | 1024 | Jul  5 18:03 | notes.txt
- verdict: 

### 57. ls-l line 3

    |-rwxr-xr-x 1 alice users 8192 Jul  4 11:20 run.sh

- E: -rwxr-xr-x | 1 | alice | users | 8192 | Jul | 4 | 11:20 | run.sh
- L: -rwxr-xr-x | 1 | alice | users | 8192 | Jul  4 11:20 | run.sh
- verdict: 

### 58. ls-l line 4

    |lrwxrwxrwx 1 root root    7 Jul  1 00:00 sh -> busybox

- E: lrwxrwxrwx | 1 | root | root | 7 | Jul | 1 | 00:00 | sh -> busybox
- L: lrwxrwxrwx | 1 | root | root | 7 | Jul  1 00:00 | sh -> | busybox
- verdict: 

### 59. lspci-nn line 0

    |00:00.0 Host bridge [0600]: Intel Corporation Comet Lake Host Bridge/DRAM Registers [8086:9b54] (rev 05)

- E: 00:00.0 | Host bridge [0600]: | Intel Corporation Comet Lake Host Bridge/DRAM Registers [8086:9b54] (rev 05)
- L: 00:00.0 | Host bridge | [0600]: | Intel Corporation Comet Lake Host Bridge/DRAM Registers | [8086:9b54] ( | rev 05)
- verdict: 

### 60. lspci-nn line 1

    |00:02.0 VGA compatible controller [0300]: Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05)

- E: 00:02.0 | VGA compatible controller [0300]: | Intel Corporation CometLake-H GT2 [UHD Graphics] [8086:9bc4] (rev 05)
- L: 00:02.0 | VGA compatible controller | [0300]: | Intel Corporation CometLake-H GT2 [UHD Graphics] | [8086:9bc4] ( | rev 05)
- verdict: 

### 61. lspci-nn line 2

    |00:14.0 USB controller [0c03]: Intel Corporation Comet Lake USB 3.1 xHCI Host Controller [8086:06ed]

- E: 00:14.0 | USB controller [0c03]: | Intel Corporation Comet Lake USB 3.1 xHCI Host Controller [8086:06ed]
- L: 00:14.0 | USB controller | [0c03]: | Intel Corporation Comet Lake USB 3.1 xHCI Host Controller | [8086:06ed]
- verdict: 

### 62. lspci-nn line 3

    |00:16.0 Communication controller [0780]: Intel Corporation Comet Lake HECI Controller [8086:06e0]

- E: 00:16.0 | Communication controller [0780]: | Intel Corporation Comet Lake HECI Controller [8086:06e0]
- L: 00:16.0 | Communication controller | [0780]: | Intel Corporation Comet Lake HECI Controller | [8086:06e0]
- verdict: 

### 63. lspci-nn line 4

    |00:1c.0 PCI bridge [0604]: Intel Corporation Comet Lake PCI Express Root Port [8086:06b8] (rev f0)

- E: 00:1c.0 | PCI bridge [0604]: | Intel Corporation Comet Lake PCI Express Root Port [8086:06b8] (rev f0)
- L: 00:1c.0 | PCI bridge | [0604]: | Intel Corporation Comet Lake PCI Express Root Port | [8086:06b8] ( | rev f0)
- verdict: 

### 64. lspci-nn line 5

    |00:1f.0 ISA bridge [0601]: Intel Corporation Comet Lake LPC Controller [8086:068e]

- E: 00:1f.0 | ISA bridge [0601]: | Intel Corporation Comet Lake LPC Controller [8086:068e]
- L: 00:1f.0 | ISA bridge | [0601]: | Intel Corporation Comet Lake LPC Controller | [8086:068e]
- verdict: 

### 65. lspci-nn line 6

    |01:00.0 Non-Volatile memory controller [0108]: Samsung Electronics NVMe SSD Controller [144d:a808]

- E: 01:00.0 | Non-Volatile memory controller [0108]: | Samsung Electronics NVMe SSD Controller [144d:a808]
- L: 01:00.0 | Non-Volatile memory controller | [0108]: | Samsung Electronics NVMe SSD Controller | [144d:a808]
- verdict: 

### 66. lspci-nn line 7

    |02:00.0 Ethernet controller [0200]: Realtek Semiconductor RTL8111/8168/8411 Gigabit Ethernet [10ec:8168] (rev 15)

- E: 02:00.0 | Ethernet controller [0200]: | Realtek Semiconductor RTL8111/8168/8411 Gigabit Ethernet [10ec:8168] (rev 15)
- L: 02:00.0 | Ethernet controller | [0200]: | Realtek Semiconductor RTL8111/8168/8411 Gigabit Ethernet | [10ec:8168] ( | rev 15)
- verdict: 

### 67. mongosh-db-currentop line 1

    |  inprog: [

- E: inprog: | [
- L: inprog: [
- verdict: 

### 68. mongosh-db-currentop line 13

    |      type: 'op',

- E: (not data)
- L: type: ' | op',
- verdict: 

### 69. mongosh-db-currentop line 15

    |      active: true,

- E: (not data)
- L: active: | true,
- verdict: 

### 70. mpstat-all line 2

    |10:14:52     CPU    %usr   %nice    %sys %iowait    %irq   %soft  %steal  %guest  %gnice   %idle

- E: 10:14:52 | CPU | %usr | %nice | %sys | %iowait | %irq | %soft | %steal | %guest | %gnice | %idle
- L: CPU | %usr | %nice | %sys | %iowait | %irq | %soft | %steal | %guest | %gnice | %idle
- verdict: 

### 71. multipathd-show-paths line 0

    |hcil     dev  dev_t  dm_st   dev_st  chk_st  next_check

- E: hcil     dev  dev_t  dm_st   dev_st  chk_st  next_check
- L: hcil | dev | dev_t | dm_st | dev_st | chk_st | next_check
- verdict: 

### 72. multipathd-show-paths line 1

    |1:0:0:0  sda  8:0    active  running ready   XXXXXXXX.. 16/20

- E: 1: | 0: | 0: | 0  sda  8: | 0    active  running ready   XXXXXXXX.. 16/20
- L: 1:0:0:0 | sda | 8:0 | active | running | ready   XXXXXXXX.. | 16/20
- verdict: 

### 73. multipathd-show-paths line 2

    |1:0:1:0  sdb  8:16   active  running ready   XXXXXX.... 12/20

- E: 1: | 0: | 1: | 0  sdb  8: | 16   active  running ready   XXXXXX.... 12/20
- L: 1:0:1:0 | sdb | 8:16 | active | running | ready   XXXXXX.... | 12/20
- verdict: 

### 74. multipathd-show-paths line 3

    |2:0:0:0  sdc  8:32   active  running ready   XXXXXXXXX. 18/20

- E: 2: | 0: | 0: | 0  sdc  8: | 32   active  running ready   XXXXXXXXX. 18/20
- L: 2:0:0:0 | sdc | 8:32 | active | running | ready   XXXXXXXXX. | 18/20
- verdict: 

### 75. multipathd-show-paths line 4

    |2:0:1:0  sdd  8:48   failed   faulty  shaky   X......... 2/20

- E: 2: | 0: | 1: | 0  sdd  8: | 48   failed   faulty  shaky   X......... 2/20
- L: 2:0:1:0 | sdd | 8:48 | failed | faulty | shaky   X......... | 2/20
- verdict: 

### 76. nst-ip-route-per-table line 1

    |default via 10.0.0.1 dev eth0 proto dhcp metric 100

- E: default via 10.0.0.1 dev eth0 proto dhcp metric 100
- L: default | via | 10.0.0.1 | dev | eth0 | proto | dhcp | metric | 100
- verdict: 

### 77. nst-ip-route-per-table line 2

    |10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.11

- E: 10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.11
- L: 10.0.0.0/24 | dev | eth0 | proto | kernel | scope | link | src | 10.0.0.11
- verdict: 

### 78. nst-ip-route-per-table line 3

    |169.254.0.0/16 dev eth0 scope link metric 1000

- E: 169.254.0.0/16 dev eth0 scope link metric 1000
- L: 169.254.0.0/16 | dev | eth0 | scope | link | metric | 1000
- verdict: 

### 79. nst-ip-route-per-table line 6

    |default via 10.8.0.1 dev tun0

- E: default via 10.8.0.1 dev tun0
- L: default | via | 10.8.0.1 | dev | tun0
- verdict: 

### 80. nst-ip-route-per-table line 7

    |10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.6

- E: 10.8.0.0/24 dev tun0 proto kernel scope link src 10.8.0.6
- L: 10.8.0.0/24 | dev | tun0 | proto | kernel | scope | link | src | 10.8.0.6
- verdict: 

### 81. nst-ip-route-per-table line 10

    |broadcast 10.0.0.0 dev eth0 proto kernel scope link src 10.0.0.11

- E: broadcast 10.0.0.0 dev eth0 proto kernel scope link src 10.0.0.11
- L: broadcast | 10.0.0.0 | dev | eth0 | proto | kernel | scope | link | src | 10.0.0.11
- verdict: 

### 82. nst-ip-route-per-table line 11

    |local 10.0.0.11 dev eth0 proto kernel scope host src 10.0.0.11

- E: local 10.0.0.11 dev eth0 proto kernel scope host src 10.0.0.11
- L: local | 10.0.0.11 | dev | eth0 | proto | kernel | scope | host | src | 10.0.0.11
- verdict: 

### 83. perf-stat-scientific line 0

    |      1,234,567,890      cycles                    #    3.456 GHz

- E: 1,234,567,890 | cycles | # | 3.456 | GHz
- L: 1,234,567,890 | cycles                    # | 3.456 GHz
- verdict: 

### 84. perf-stat-scientific line 1

    |        987,654,321      instructions              #    0.80  insn per cycle

- E: 987,654,321 | instructions | # | 0.80 | insn per cycle
- L: 987,654,321 | instructions              # | 0.80  insn per cycle
- verdict: 

### 85. perf-stat-scientific line 2

    |           1.24e+06      cache-misses              #    2.34 %

- E: 1.24e+06 | cache-misses | # | 2.34 | %
- L: 1.24e+06 | cache-misses              # | 2.34 %
- verdict: 

### 86. proc-interrupts-smp line 1

    |  0:         12          0          0          0          0          0          0          0   IO-APIC   2-edge      timer

- E: 0: | 12 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | IO-APIC   2-edge      timer
- L: 0: | 12 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | IO-APIC | 2-edge | timer
- verdict: 

### 87. proc-interrupts-smp line 2

    |  8:          0          1          0          0          0          0          0          0   IO-APIC   8-edge      rtc0

- E: 8: | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | IO-APIC   8-edge      rtc0
- L: 8: | 0 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | IO-APIC | 8-edge | rtc0
- verdict: 

### 88. proc-interrupts-smp line 3

    |  9:          0          0      18442          0          0          0          0          0   IO-APIC   9-fasteoi   acpi

- E: 9: | 0 | 0 | 18442 | 0 | 0 | 0 | 0 | 0 | IO-APIC   9-fasteoi   acpi
- L: 9: | 0 | 0 | 18442 | 0 | 0 | 0 | 0 | 0 | IO-APIC | 9-fasteoi | acpi
- verdict: 

### 89. proc-interrupts-smp line 4

    | 16:      88201          0          0          0     120044          0          0          0   IO-APIC  16-fasteoi    ehci_hcd:usb1

- E: 16: | 88201 | 0 | 0 | 0 | 120044 | 0 | 0 | 0 | IO-APIC  16-fasteoi    ehci_hcd:usb1
- L: 16: | 88201 | 0 | 0 | 0 | 120044 | 0 | 0 | 0 | IO-APIC | 16-fasteoi | ehci_hcd:usb1
- verdict: 

### 90. proc-interrupts-smp line 5

    | 24:          0          0          0          0          0     442018          0     338290   PCI-MSI 524288-edge   nvme0q0

- E: 24: | 0 | 0 | 0 | 0 | 0 | 442018 | 0 | 338290 | PCI-MSI 524288-edge   nvme0q0
- L: 24: | 0 | 0 | 0 | 0 | 0 | 442018 | 0 | 338290 | PCI-MSI | 524288-edge | nvme0q0
- verdict: 

### 91. proc-stat line 0

    |cpu  402103 1203 180234 12403201 8923 0 4021 0 0 0

- E: cpu | 402103 1203 180234 12403201 8923 0 4021 0 0 0
- L: cpu | 402103 | 1203 | 180234 | 12403201 | 8923 | 0 | 4021 | 0 | 0 | 0
- verdict: 

### 92. proc-stat line 1

    |cpu0 102301 320 45012 3100801 2203 0 1203 0 0 0

- E: cpu0 | 102301 320 45012 3100801 2203 0 1203 0 0 0
- L: cpu0 | 102301 | 320 | 45012 | 3100801 | 2203 | 0 | 1203 | 0 | 0 | 0
- verdict: 

### 93. proc-stat line 2

    |cpu1 100234 298 44890 3101203 2103 0 980 0 0 0

- E: cpu1 | 100234 298 44890 3101203 2103 0 980 0 0 0
- L: cpu1 | 100234 | 298 | 44890 | 3101203 | 2103 | 0 | 980 | 0 | 0 | 0
- verdict: 

### 94. proc-stat line 3

    |cpu2 99823 290 45102 3100923 2301 0 920 0 0 0

- E: cpu2 | 99823 290 45102 3100923 2301 0 920 0 0 0
- L: cpu2 | 99823 | 290 | 45102 | 3100923 | 2301 | 0 | 920 | 0 | 0 | 0
- verdict: 

### 95. proc-stat line 4

    |cpu3 99745 295 45230 3100274 2316 0 918 0 0 0

- E: cpu3 | 99745 295 45230 3100274 2316 0 918 0 0 0
- L: cpu3 | 99745 | 295 | 45230 | 3100274 | 2316 | 0 | 918 | 0 | 0 | 0
- verdict: 

### 96. proc-stat line 5

    |intr 12043201 42 9 0 0 30124 0 0 0 1 0 0 0 402103

- E: intr | 12043201 42 9 0 0 30124 0 0 0 1 0 0 0 402103
- L: intr | 12043201 | 42 | 9 | 0 | 0 | 30124 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 402103
- verdict: 

### 97. proc-stat line 11

    |softirq 3402103 2 402103 120 88203 30124 0 412 804203 0 602103

- E: softirq | 3402103 2 402103 120 88203 30124 0 412 804203 0 602103
- L: softirq | 3402103 | 2 | 402103 | 120 | 88203 | 30124 | 0 | 412 | 804203 | 0 | 602103
- verdict: 

### 98. pueue-status line 0

    |Group "default" (2 parallel):

- E: (not data)
- L: Group "default" (2 parallel):
- verdict: 

### 99. tbl-header-embedded-gap line 0

    |Ticket   Assigned  To         Priority

- E: Ticket | Assigned | To | Priority
- L: Ticket | Assigned  To | Priority
- verdict: 

### 100. tbl-header-embedded-gap line 1

    |T-101    Alice Ray            high

- E: T-101 | Alice | Ray | high
- L: T-101 | Alice Ray | high
- verdict: 

### 101. tbl-header-embedded-gap line 2

    |T-102    Bob Chen             medium

- E: T-102 | Bob | Chen | medium
- L: T-102 | Bob Chen | medium
- verdict: 

### 102. tbl-header-embedded-gap line 3

    |T-103    Carol Diaz           low

- E: T-103 | Carol | Diaz | low
- L: T-103 | Carol Diaz | low
- verdict: 

