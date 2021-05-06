begin
    -- Remove ACE privilege for connect to Datadog API
    dbms_network_acl_admin.remove_host_ace(
        host => '&3',
        lower_port => 443,
        upper_port => 443,
        ace => xs$ace_type(
        privilege_list => xs$name_list('connect'),
        principal_name => '&1',
        principal_type => xs_acl.ptype_db));

    -- Remove ACE privilege for resolve on Datadog API
    dbms_network_acl_admin.remove_host_ace(
        host => '&3',
        ace => xs$ace_type(
        privilege_list => xs$name_list('resolve'),
        principal_name => '&1',
        principal_type => xs_acl.ptype_db));

    -- Remove ACE privilege for connect to Datadog logs ingest
    dbms_network_acl_admin.remove_host_ace(
        host => '&4',
        lower_port => 443,
        upper_port => 443,
        ace => xs$ace_type(
        privilege_list => xs$name_list('connect'),
        principal_name => '&1',
        principal_type => xs_acl.ptype_db));

    -- Remove ACE privilege for resolve on Datadog logs ingest
    dbms_network_acl_admin.remove_host_ace(
        host => '&4',
        ace => xs$ace_type(
        privilege_list => xs$name_list('resolve'),
        principal_name => '&1',
        principal_type => xs_acl.ptype_db));

    -- Remove ACE privilege for access to the wallet with the Datadog root certificate
    dbms_network_acl_admin.remove_wallet_ace(
        wallet_path => 'file:&2',
        ace => xs$ace_type(
        privilege_list => xs$name_list('use_client_certificates'),
        principal_name => '&1',
        principal_type => xs_acl.ptype_db));
end;
/