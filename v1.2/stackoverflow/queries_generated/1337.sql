-- {"query": "1337.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1059} 

with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc) rn
    from Users u
    join Badges b on u.Id = b.UserId
    where b.Name ilike '%gold%' or b.Class = 1
),
RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        coalesce(p.Score,0) as Score,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as PostRankDesc
    from Posts p
    where p.OwnerUserId is not null
),
AcceptedAnswerDetails as (
    select 
        a.Id as AnswerId,
        coalesce(a.Score,0) as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        p.Id as QuestionId,
        p.Tags as QuestionTags,
        p.OwnerUserId as QuestionOwnerId,
        p.CreationDate as QuestionCreationDate
    from Posts p
    join Posts a on a.Id = p.AcceptedAnswerId and a.PostTypeId = 2 -- Answers only
    where p.PostTypeId = 1
),
CloseReasonCounts as (
    select 
        pst.Comment as CloseReasonId,
        crc.Name as CloseReasonName,
        count(distinct ph.PostId) as CloseCount
    from PostHistory ph
    left join CloseReasonTypes crc on cast(pst.Comment as smallint) = crc.Id
    cross apply (select ph.Comment) as pst -- hack to reference inside from
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.Comment, crc.Name
),
UserReputationWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank,
        percentile_cont(0.5) within group (order by coalesce(v.Score,0)) over (partition by u.Id) as MedianVoteScore
    from Users u
    left join Votes v on v.UserId = u.Id
),
PostsWithLinkInfo as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.OwnerUserId,
        pl.Id as LinkId,
        pl.RelatedPostId,
        plt.Name as LinkTypeName
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes plt on plt.Id = pl.LinkTypeId
)
select
    u.Id as UserId,
    u.DisplayName,
    count(distinct p.Id) as TotalPosts,
    sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
    sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
    avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
    count(distinct rb.Id) as GoldBadgesOwned,
    max(rank_pts.BadgeClass) as HighestBadgeClass,
    coalesce(cra.AnswerScore, 0) as AcceptedAnswerScore,
    rac.CloseCount,
    wm.MedianVoteScore,
    string_agg(distinct trim(both '<>' from unnest(string_to_array(coalesce(p.Tags,''), '><')))::text, ',') as UserTagList,
    substring(ab.BadgeName from 1 for 20) as SampleGoldBadgeName,
    case 
      when p.AcceptedAnswerId is not null then 'Has Accepted Answer'
      else 'No Accepted Answer'
    end as AcceptanceStatus
from Users u
left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1, 2)
left join RecursiveUserBadges rb on rb.UserId = u.Id and rb.rn = 1 -- most recent gold badge or badge named gold%
left join AcceptedAnswerDetails cra on cra.QuestionOwnerId = u.Id
left join CloseReasonCounts rac on rac.CloseReasonName ilike '%duplicate%' -- example filter for close reason duplicates mittigating perf
left join UserReputationWindow wm on wm.UserId = u.Id
left join RecursiveUserBadges ab on ab.UserId = u.Id and ab.rn = 2 -- second gold badge to show substring example
group by 
    u.Id, u.DisplayName, cra.AnswerScore, rac.CloseCount, wm.MedianVoteScore, ab.BadgeName, p.AcceptedAnswerId
having count(distinct p.Id) > 5 and avg(p.Score) > 0 -- filter only active good posters
order by AvgPostScore desc nulls last, TotalPosts desc
limit 50;
