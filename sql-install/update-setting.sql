merge into &1..datadog_settings
using (select '&2' as key, '&3' as value from dual) input
on (datadog_settings.key = input.key)
when matched then
    update set value = '&3'
when not matched then
    insert (key, value)
    values ('&2', '&3');