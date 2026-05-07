# lib/commands/config.sh - cmd_config: show / get / set the config file.
#
# Usage shapes:
#   phonectl config                  # print all loaded values (key=value)
#   phonectl config <key>            # print one value
#   phonectl config <key> <value>    # write the value to the on-disk config

cmd_config() {
    case "$#" in
        0) config_print ;;
        1) config_get "$1" ;;
        2) config_set "$1" "$2" ;;
        *)
            error "usage: phonectl config [<key> [<value>]]"
            return 1 ;;
    esac
}
