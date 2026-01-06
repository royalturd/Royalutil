#!/usr/bin/expect -f

set timeout 30

# Spawn the script
spawn ./royalutil.sh

# Wait for the clear/header (it might take a moment)
# Then wait for the fzf prompt or the fallback menu
expect {
    "Select a module to run:" {
        # Fallback menu detected
        send "0\r"
        expect "Exiting" { exit 0 }
    }
    "Select modules" {
        # fzf TUI detected
        # Send 'ESC' to exit fzf
        send "\x1b" 
        expect "No modules selected. Exiting." { exit 0 }
    }
    timeout {
        send_user "Timed out waiting for menu\n"
        exit 1
    }
}

expect eof
