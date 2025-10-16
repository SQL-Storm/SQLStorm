-- {"query": "1475.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1313} 
with RecursiveTagHierarchy(tagid, parentid, depth) as (
    select t.Id, pt.WikiPostId, 1
    from Tags t
    left join Posts pt on t.WikiPostId = pt.Id
    where pt.Id is not null
    union all
    select r.tagid, pt.WikiPostId, depth + 1
    from RecursiveTagHierarchy r
    join Posts pt on r.parentid = pt.Id
    where r.depth < 3
),
UserBadgesSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 else null end) gold_badges,
        count(case when b.Class = 2 then 1 else null end) silver_badges,
        count(case when b.Class = 3 then 1 else null end) bronze_badges,
        coalesce(u.Reputation,0) as reputation,
        coalesce(u.UpVotes,0) as ups,
        coalesce(u.DownVotes,0) as downs,
        rank() over (order by u.Reputation desc, gold_badges desc) as reputation_rank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
),
PostVoteAggregates as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as up_votes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as down_votes,
        coalesce(count(distinct v.UserId),0) as voters_count
    from Posts p
    left join Votes v on p.Id = v.PostId
    where p.PostTypeId in (1,2) -- Only questions and answers
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score
),
ClosedQuestions as (
    select ph.PostId, min(ph.CreationDate) as CloseDate, ph.Comment as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId = 10 and ph.PostId is not null
    group by ph.PostId, ph.Comment
),
UserTopActiveDays as (
    select
        u.Id as UserId,
        CAST(ph.CreationDate AS date) as ActivityDate,
        count(ph.Id) as EditsCount
    from Users u
    join PostHistory ph on u.Id = ph.UserId
    group by u.Id, CAST(ph.CreationDate AS date)
),
UserLastFiveEditSummaries as (
    select
        ph.UserId,
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment,
        row_number() over (partition by ph.UserId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.UserId is not null
)
select
    p.Id as PostId,
    case p.PostTypeId
        when 1 then 'Question'
        when 2 then 'Answer'
        when 3 then 'Wiki'
        else 'Other'
    end as PostType,
    p.Title,
    u.DisplayName as OwnerName,
    uh.depth as TagHierarchyDepth,
    concat_ws(', ',
       'Score: ' || pva.Score,
       'UpVotes: ' || pva.up_votes,
       'DownVotes: ' || pva.down_votes,
       'Voters: ' || pva.voters_count
    ) as VoteInfo,
    case
        when cq.PostId is not null then
          'Closed on ' || to_char(cq.CloseDate, 'YYYY-MM-DD') || ' (Reason ID: ' || coalesce(cq.CloseReasonId, 'Unknown') || ')'
        else 'Open'
    end as ClosedStatus,
    cnt BadgeCounts,
    UTA.TopActiveDayCount,
    RecentEdits.EditCommentsSummary,
    sum(pb.Class) filter (where pb.Class = 1) over (partition by p.OwnerUserId) as TotalGoldBadgesOfUser,
    sum(pb.Class) filter (where pb.Class = 2) over (partition by p.OwnerUserId) as TotalSilverBadgesOfUser,
    sum(pb.Class) filter (where pb.Class = 3) over (partition by p.OwnerUserId) as TotalBronzeBadgesOfUser
from Posts p
left join Users u on p.OwnerUserId = u.Id
left join PostVoteAggregates pva on p.Id = pva.Id
left join ClosedQuestions cq on p.Id = cq.PostId
left join recursiveTagHierarchy uh on exists (
    select 1 from Tags t where '<' || t.TagName || '>' = any(string_to_array(coalesce(p.Tags,''), '><')) and uh.tagid = t.Id
)
left join (
    select UserId, count(1) as BadgeCounts
    from Badges
    group by UserId
) cnt on cnt.UserId = p.OwnerUserId
left join (
    select UserId, count(*) as TopActiveDayCount
    from UserTopActiveDays
    where EditsCount > 10
    group by UserId
) UTA on UTA.UserId = p.OwnerUserId
left join (
    select UserId,
        string_agg(
          substring(coalesce(Comment, 'No comment'), 1, 50), '| ' order by CreationDate desc
        ) as EditCommentsSummary
    from UserLastFiveEditSummaries
    where rn <= 5
    group by UserId
) RecentEdits on RecentEdits.UserId = p.OwnerUserId
left join Badges pb on pb.UserId = p.OwnerUserId
where (p.Score > (select avg(Score) from Posts where PostTypeId = p.PostTypeId) or p.Score is null)
and p.CreationDate > current_date - interval '3 years'
order by u.Reputation desc nulls last, p.Score desc nulls last
limit 50;