with recursive RecursiveBadgeCounts as (
    select
        b.UserId,
        cast(null as integer) as src_user_auth_userid
    from badges b
)
select *
from RecursiveBadgeCounts;