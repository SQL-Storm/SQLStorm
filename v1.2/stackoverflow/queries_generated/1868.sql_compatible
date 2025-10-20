with RECs as (
    select 
        ph.PostId, ph.PostHistoryTypeId, ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate) as rn
    from PostHistory ph 
    where ph.PostHistoryTypeId in (1,4,10)
),
RankedBadges as (
    select *,
        row_number() over (partition by UserId order by Date desc) as badge_rank
    from Badges
    where Name like '%er%'
),
TopAnswerersCTE as (
    select OwnerUserId,
      count(*) as total_answers,
      sum(case when Score > 10 then 1 else 0 end) as high_score_answers
    from Posts
    where PostTypeId = 2 and OwnerUserId is not null
    group by OwnerUserId
    having min(CreationDate) < DATE '2020-01-01' and count(*) > 20
),
HighReputeQuestions as (
    select p.*,
        (select min(ph.CreationDate) from PostHistory ph 
         where ph.PostId = p.Id and ph.PostHistoryTypeId = 10) as close_date_zero,
        COALESCE(v_ups.all_upvotes, 0) as total_upvotes
    from Posts p
    left join (
      -- assuming v_ups is a derived table of upvote counts per post; replace with actual source if different
      select PostId, count(*) as all_upvotes
      from Votes
      where VoteTypeId = 2
      group by PostId
    ) v_ups on v_ups.PostId = p.Id
)
select *
from HighReputeQuestions;