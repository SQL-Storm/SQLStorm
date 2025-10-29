-- {"query": "2749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1282}
with recursive UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as Rnk,
        rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
FilteredPosts as (
    select * from RankedPosts
    where Rnk <= 5
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes,
        pl.DuplicateCount,
        rank() over (order by count(a.Id) desc) as AnswerCountRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join (
        select PostId, count(*) as DuplicateCount
        from PostLinks pl
        where LinkTypeId = 3
        group by PostId
    ) pl on pl.PostId = q.Id
    where q.PostTypeId = 1
    group by q.Id, q.Title, pl.DuplicateCount
),
LatestPostHistoryEdits as (
    select ph.PostId, max(ph.CreationDate) as LastEdit
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6)
    group by ph.PostId
),
PostsWithLastEdit as (
    select p.*, lph.LastEdit
    from Posts p
    left join LatestPostHistoryEdits lph on p.Id = lph.PostId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswerCount,
        sum(coalesce(p.Score,0)) as TotalScore,
        max(p.CreationDate) as LastPostDate,
        avg(p.Score) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
HighImpactQuestions as (
    select q.Id, q.Title, q.Score, q.ViewCount, q.AnswerCount,
           case when q.ViewCount > 0 then round(cast(q.Score as numeric)/q.ViewCount,6) else 0 end as ScoreToViewRatio,
           replace(replace(substring(q.Tags from 2 for length(q.Tags)-2), '><', ','), ' ', '') as TagList,
           q.Tags
    from Posts q
    where q.PostTypeId = 1 and q.AnswerCount > 10 and q.Score > 100
),
UserReputationPercentiles AS (
    -- Compute percentiles without ordered-set WITHIN GROUP OVER (not supported in some dialects)
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        p25.pctl as Q1,
        p50.pctl as Median,
        p75.pctl as Q3
    from Users u
    cross join lateral (
        select percentile_cont(0.25) within group (order by Reputation) as pctl from Users
    ) p25
    cross join lateral (
        select percentile_cont(0.5) within group (order by Reputation) as pctl from Users
    ) p50
    cross join lateral (
        select percentile_cont(0.75) within group (order by Reputation) as pctl from Users
    ) p75
),
ComplexUserBadgeRank as (
    select 
        ubc.UserId,
        ubc.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        dense_rank() over (order by ubc.GoldBadges desc, ubc.SilverBadges desc, ubc.BronzeBadges desc) as BadgeRank
    from UserBadgeCounts ubc
)
select 
    uas.DisplayName as User,
    uas.TotalPosts,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalScore,
    hrs.Title as PopularQuestionTitle,
    hrs.Score as PopularQuestionScore,
    hrs.ViewCount as PopularQuestionViews,
    hrs.AnswerCount as PopularQuestionAnswers,
    hrs.ScoreToViewRatio,
    hrs.Tags as PopularQuestionTags,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    ubr.BadgeRank,
    urp.Reputation,
    urp.Q1 as ReputationQ1,
    urp.Median as ReputationMedian,
    urp.Q3 as ReputationQ3
from UserActivitySummary uas
left join HighImpactQuestions hrs on hrs.Id = (
    select p.Id from Posts p 
    where p.OwnerUserId = uas.Id and p.PostTypeId = 1 
    order by p.Score desc 
    limit 1
)
left join UserBadgeCounts ubc on ubc.UserId = uas.Id
left join ComplexUserBadgeRank ubr on ubr.UserId = uas.Id
left join UserReputationPercentiles urp on urp.Id = uas.Id
where uas.TotalPosts > 50
order by ubr.BadgeRank, uas.TotalScore desc
limit 100;