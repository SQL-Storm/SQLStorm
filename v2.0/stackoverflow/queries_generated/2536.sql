-- {"query": "2536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1652} 
with RecursiveBadgeCte as (
    select
        b.UserId,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by b.UserId order by b.Date) as BadgeRank
    from Badges b
    where b.TagBased = cast(0 as bit)
),
LatestUserDesc as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.AboutMe,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as TotalQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as TotalAnswers,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        min(coalesce(ph.CreationDate, u.CreationDate)) as FirstActivityDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    left join PostHistory ph on ph.PostId = p.Id and ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.AboutMe
), UserBadgeRanks as (
    select
        l.UserId,
        l.DisplayName,
        l.Reputation,
        l.TotalQuestions,
        l.TotalAnswers,
        l.MaxPostScore,
        l.AvgPostScore,
        l.TotalUpVotes,
        l.TotalDownVotes,
        l.FirstActivityDate,
        b.BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        b.BadgeRank
    from LatestUserDesc l
    left join RecursiveBadgeCte b on l.UserId = b.UserId
), QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.OwnerUserId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        string_agg(distinct substring(t.TagName from 1 for 30), ',' order by t.TagName) as TagsAggregated
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
        select
            unnest(string_to_array(substring(Tags, 2, length(Tags) - 2), '><')) as TagName
        from Posts
        where PostTypeId = 1
    ) t on true and q.Id in (
        select p2.Id from Posts p2 where p2.PostTypeId = 1 and p2.Tags like concat('%<', t.TagName, '>%')
    )
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.OwnerUserId
), QuestionLinkSummary as (
    select
        pl.PostId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount,
        count(*) as TotalLinks
    from PostLinks pl
    group by pl.PostId
), PostCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as CloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate else null end) as ReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
), WindowedUserRanking as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        row_number() over (order by u.Reputation desc nulls last, u.Id) as ReputationRank,
        dense_rank() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocationRepRank,
        count(*) over (partition by coalesce(u.Location, 'Unknown')) as LocationUserCount
    from Users u
    where u.Reputation is not null
)
select
    qas.QuestionId,
    qas.Title,
    qas.QuestionCreationDate,
    qas.QuestionScore,
    qas.QuestionViews,
    coalesce(u.DisplayName, 'anonymous') as QuestionOwner,
    u.Reputation as OwnerReputation,
    qas.AnswerCount,
    qas.MaxAnswerScore,
    round(coalesce(qas.AvgAnswerScore,0)::numeric,2) as AvgAnswerScore,
    qls.LinkedCount,
    qls.DuplicateCount,
    qls.TotalLinks,
    pci.CloseDate,
    pci.ReopenDate,
    crt.Name as CloseReasonName,
    ub.BadgeName,
    ub.BadgeClass,
    ub.BadgeDate,
    wur.LocationRepRank,
    wur.LocationUserCount,
    coalesce(nullif(u.Location, ''), 'Unknown') as UserLocation,
    concat_ws(' - ', substr(qas.Title, 1, 50), 'Tags:', coalesce(qas.TagsAggregated, 'None')) as TitleWithTags,
    -- Complex calculations and null-safe expressions
    case
        when qas.Score > 0 and qas.AnswerCount > 0 then
            (qas.QuestionScore * 1.0) / qas.AnswerCount + coalesce(qas.AvgAnswerScore, 0) + coalesce(u.Reputation, 0) / 1000.0
        else 0 end as CompositeScore,
    -- Correlated subquery: get count of distinct users who answered this question
    (
        select count(distinct a.OwnerUserId)
        from Posts a
        where a.ParentId = qas.QuestionId and a.PostTypeId = 2 and a.OwnerUserId is not null
    ) as DistinctAnswerUsers,
    -- Window function: rank posts by score within all posts
    rank() over (order by qas.QuestionScore desc nulls last) as QuestionScoreRank
from QuestionAnswerStats qas
left join Users u on u.Id = qas.OwnerUserId
left join QuestionLinkSummary qls on qls.PostId = qas.QuestionId
left join PostCloseInfo pci on pci.PostId = qas.QuestionId
left join CloseReasonTypes crt on crt.Id = pci.CloseReasonId
left join (
    select ub1.UserId, ub1.BadgeName, ub1.BadgeClass, ub1.Date as BadgeDate
    from RecursiveBadgeCte ub1
    where ub1.BadgeRank = 1
) ub on ub.UserId = qas.OwnerUserId
left join WindowedUserRanking wur on wur.Id = qas.OwnerUserId
where qas.QuestionScore > -5
and (
    pci.CloseDate is null or pci.ReopenDate is not null and pci.ReopenDate > pci.CloseDate
)
order by CompositeScore desc nulls last, qas.QuestionCreationDate desc
limit 100;