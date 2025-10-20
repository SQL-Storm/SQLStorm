with RecursiveUserWLCTE as (
    select
        Id,
        DisplayName,
        Knockout
    from (
        values
            (1, 'User A', 0),
            (2, 'User B', 1)
    ) as t(Id, DisplayName, Knockout)
)
select
    Id,
    DisplayName,
    Knockout
from RecursiveUserWLCTE
group by
    Id,
    DisplayName,
    Knockout;