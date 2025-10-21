-- {"query": "4082.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1363} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        u.Reputation,
        ROW_NUMBER() OVER (PARTITION BY t.Id ORDER BY p.Score DESC, p.CreationDate DESC) as PostRank
    from Tags t
    left join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    left join Users u on p.OwnerUserId = u.Id
),
TopQuestionAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerUserId,
        u.DisplayName as AnswerOwnerName,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1
),
BadgeSummary as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
),
UserReputationStats as (
    select
        Id,
        DisplayName,
        Reputation,
        Coalesce(Location, 'Unknown') as UserLocation,
        case
            when Reputation >= 100000 then 'Legendary'
            when Reputation >= 10000 then 'Expert'
            when Reputation >= 1000 then 'Intermediate'
            else 'Beginner'
        end as ReputationLevel,
        row_number() over (order by Reputation desc) as ReputationRank
    from Users
),
DuplicateLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        l.Name as LinkTypeName
    from PostLinks pl
    inner join Posts p1 on pl.PostId = p1.Id
    inner join Posts p2 on pl.RelatedPostId = p2.Id
    inner join LinkTypes l on pl.LinkTypeId = l.Id
    where pl.LinkTypeId = 3
)
select
    rt.TagName,
    rt.PostRank,
    rt.PostId,
    rt.Score as PostScore,
    rt.Reputation as OwnerReputation,
    u.DisplayName as OwnerName,
    tq.Title as TopQuestionTitle,
    tqa.AnswerId,
    tqa.AnswerScore,
    tqa.AnswerOwnerName,
    tqa.AnswerCreationDate,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    ur.UserLocation,
    ur.ReputationLevel,
    dl.PostTitle as DuplicatePostTitle,
    dl.RelatedPostTitle as DuplicateRelatedTitle,
    dl.LinkTypeName as DuplicateLinkType,
    -- complicated string expression handling NULLs and concatenation
    concat(
        coalesce(u.DisplayName, 'Anonymous'),
        ' [', ur.ReputationLevel, '] - ',
        case when bs.TotalBadges > 0 then concat('🏅 ', bs.TotalBadges, ' badges') else 'No badges' end,
        ' | Answer top score: ',
        coalesce(cast(tqa.AnswerScore as varchar), 'N/A'),
        ' | Tag usage count: ',
        cast(rt.Count as varchar)
    ) as SummaryDescription,
    -- window function with partition and NULL handling (e.g. latest comment text on post)
    (select Text from Comments c where c.PostId = rt.PostId order by c.CreationDate desc limit 1) as LatestComment,
    -- correlated subquery with NULL logic and date diff in days
    (select min(ph.CreationDate)
     from PostHistory ph
     where ph.PostId = rt.PostId and ph.PostHistoryTypeId in (10,11)
    ) as CloseOrReopenDate,
    coalesce(
        (select count(*) from Votes v where v.PostId = rt.PostId and v.VoteTypeId = 2),
        0
    ) as UpVotesCount,
    coalesce(
        (select count(*) from Votes v where v.PostId = rt.PostId and v.VoteTypeId = 3),
        0
    ) as DownVotesCount
from RecursiveTagCounts rt
inner join Users u on u.Id = (
    select OwnerUserId from Posts p where p.Id = rt.PostId limit 1
)
left join TopQuestionAnswers tqa on tqa.QuestionId = rt.PostId and tqa.AnswerRank = 1
left join Posts tq on tq.Id = rt.PostId
left join BadgeSummary bs on bs.UserId = u.Id
left join UserReputationStats ur on ur.Id = u.Id
left join DuplicateLinks dl on dl.PostId = rt.PostId
where rt.PostRank <= 3
  and rt.Count > 100
  and (tqa.AnswerScore is null or tqa.AnswerScore > 5)
union
select
    TagName,
    0 as PostRank,
    null as PostId,
    null as PostScore,
    null as OwnerReputation,
    null as OwnerName,
    null as TopQuestionTitle,
    null as AnswerId,
    null as AnswerScore,
    null as AnswerOwnerName,
    null as AnswerCreationDate,
    null as GoldBadges,
    null as SilverBadges,
    null as BronzeBadges,
    'Global' as UserLocation,
    null as ReputationLevel,
    null as DuplicatePostTitle,
    null as DuplicateRelatedTitle,
    null as DuplicateLinkType,
    concat('Global stats for tag ', TagName, ': ', Count, ' posts') as SummaryDescription,
    null as LatestComment,
    null as CloseOrReopenDate,
    null as UpVotesCount,
    null as DownVotesCount
from Tags
where Count > 1000
order by TagName, PostRank
limit 100;