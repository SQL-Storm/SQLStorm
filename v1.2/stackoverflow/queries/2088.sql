with TopContributors as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct b.Id) as total_badges,
        sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges,
        row_number() over (order by count(distinct b.Id) desc, u.Reputation desc) as rn,
        u.Reputation
    from Users u
    left join Badges b
        on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct b.Id) > 5
),
UpVotingBehavior as (
    select
        v.UserId,
        count(*) as cnt_elected_after_str
    from Votes v
    where v.VoteTypeId = 2
    group by v.UserId
)
select
    tc.Id,
    tc.DisplayName,
    tc.total_badges,
    tc.gold_badges,
    tc.silver_badges,
    tc.bronze_badges,
    tc.rn,
    uv.cnt_elected_after_str,
    tc.Reputation
from TopContributors tc
left join UpVotingBehavior uv
    on uv.UserId = tc.Id
order by tc.total_badges desc, tc.Reputation desc;