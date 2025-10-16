-- {"query": "1119.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1459} 
with RecursivePostChildren as (
    select p.Id, p.ParentId, p.CreationDate, 0 as Depth
    from Posts p
    where p.PostTypeId = 2 and p.ParentId is not null
    union all
    select p.Id, p.ParentId, p.CreationDate, rpc.Depth + 1
    from Posts p
    inner join RecursivePostChildren rpc on p.ParentId = rpc.Id
    where p.PostTypeId = 2
),
UserBadgeCounts as (
    select UserId,
           sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
           count(*) as TotalBadges
    from Badges
    group by UserId
),
PostVoteSummary as (
    select PostId,
           sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
           sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes,
           sum(case when VoteTypeId = 8 then BountyAmount else 0 end) as TotalBounty
    from Votes
    group by PostId
),
LatestUserAccess as (
    select Id, DisplayName, LastAccessDate,
           row_number() over (partition by Location order by LastAccessDate desc) as LocationRank
    from Users
    where Location is not null
),
ClosedPostReasons as (
    select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = try_cast(ph.Comment as smallint)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
),
QuestionAnswerStats as (
    select q.Id as QuestionId, q.Title, q.CreationDate as QuestionCreation,
           count(a.Id) as AnswersCount,
           avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
           max(a.Score) filter (where a.Score is not null) as MaxAnswerScore,
           max(a.CreationDate) filter (where a.CreationDate is not null) as LastAnswerDate
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
)
select
    qas.QuestionId,
    qas.Title,
    quarter, year,
    qas.AnswersCount,
    coalesce(qas.AvgAnswerScore,0) as AvgAnswerScore,
    coalesce(qas.MaxAnswerScore,0) as MaxAnswerScore,
    coalesce(qas.LastAnswerDate, timestamp '1970-01-01') as LastAnswerDate,
    u.DisplayName as OwnerDisplayName,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    pvs.UpVotes as QuestionUpVotes,
    pvs.DownVotes as QuestionDownVotes,
    pvs.TotalBounty,
    cr.CloseReason,
    -- Window function over Questions per quarter/year
    rank() over (partition by year, quarter order by qas.AnswersCount desc, AvgAnswerScore desc) as RankInQuarter,
    -- String manipulation example: extract top 3 tags concatenated into single string
    (select string_agg(tn.TagName, ', ') from (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
        order by TagName
        limit 3
    ) tn) as Top3Tags,
    -- Complex NULL logic and case
    case
        when p.ClosedDate is not null then 'Closed'
        when p.CommunityOwnedDate is not null then 'Community Owned'
        else 'Open'
    end as PostStatus,
    -- Correlated subquery: count of comments by user for question
    (select count(1) from Comments c where c.PostId = qas.QuestionId and c.UserId = u.Id) as CommentsByOwner,
    -- Nested arithmetic expression example
    (score_formula.ScoreWeighted / nullif(score_formula.ScoreDivisor,0)) as NormalizedScore
from QuestionAnswerStats qas
left join Posts p on p.Id = qas.QuestionId
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeCounts ubc on ubc.UserId = u.Id
left join PostVoteSummary pvs on pvs.PostId = p.Id
left join ClosedPostReasons cr on cr.PostId = p.Id
left join lateral (
    select
        (coalesce(p.Score,0) * 0.7 + coalesce(qas.AvgAnswerScore,0) * 0.2 + GREATEST(0, coalesce(pvs.UpVotes,0) - coalesce(pvs.DownVotes,0)) * 0.1) as ScoreWeighted,
        (case when p.Score is null then 0 else 1 end) +
        (case when qas.AvgAnswerScore is null then 0 else 1 end) +
        (case when pvs.UpVotes is null and pvs.DownVotes is null then 0 else 1 end) as ScoreDivisor
) score_formula on true
cross join lateral (
    select
        extract(quarter from qas.QuestionCreation) as quarter,
        extract(year from qas.QuestionCreation) as year
) qtime
where qas.AnswersCount > 0 and u.Id is not null
union
select
    Id as QuestionId,
    Title,
    0 as quarter,
    0 as year,
    0 as AnswersCount,
    0 as AvgAnswerScore,
    0 as MaxAnswerScore,
    timestamp '1970-01-01' as LastAnswerDate,
    DisplayName,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as QuestionUpVotes,
    0 as QuestionDownVotes,
    0 as TotalBounty,
    NULL as CloseReason,
    999999 as RankInQuarter,
    NULL as Top3Tags,
    case
        when ClosedDate is not null then 'Closed'
        when CommunityOwnedDate is not null then 'Community Owned'
        else 'Open'
    end as PostStatus,
    0 as CommentsByOwner,
    0 as NormalizedScore
from Posts
where PostTypeId = 1 and Id not in (select QuestionId from QuestionAnswerStats)
order by year desc, quarter desc, RankInQuarter asc, NormalizedScore desc
limit 100;