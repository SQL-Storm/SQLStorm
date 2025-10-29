-- {"query": "2248.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1200} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(u.Location, 'Unknown') as Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        1 as Depth
    from Users u
    where u.Reputation > 1000 and u.Location is not null

    union all

    select
        a.UserId,
        a.DisplayName,
        a.Reputation,
        a.CreationDate,
        a.Location,
        a.Views,
        a.UpVotes,
        a.DownVotes,
        r.Depth + 1
    from RecursiveUserActivity r
    join Users a on a.Id = r.UserId + 1
    where r.Depth < 5
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
PostAggregates as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) as AvgPostScore,
        max(p.CreationDate) as LastPostDate,
        sum(p.ViewCount) as TotalViews,
        string_agg(distinct coalesce(p.OwnerDisplayName, 'Anonymous') || ':' || coalesce(p.Title, 'NoTitle'), ' | ') as TitlesSample
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
PostAnswerRates as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        case when q.Score > 0 then 1.0 * coalesce(a.AnswerCount, 0) / q.Score else null end as AnswerToScoreRatio,
        row_number() over (partition by q.OwnerUserId order by q.CreationDate desc) as RecentQuestionRank
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on q.Id = a.ParentId
    where q.PostTypeId = 1
),
CloseReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseVotesCount
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
UserQuestionCloseStats as (
    select
        p.OwnerUserId,
        count(distinct p.Id) as ClosedQuestions,
        sum(coalesce(crs.CloseVotesCount,0)) as TotalCloseVotes,
        string_agg(distinct coalesce(crs.CloseReasonName, 'Unknown'), ',') as CloseReasons
    from Posts p
    left join CloseReasonSummary crs on p.Id = crs.PostId
    where p.PostTypeId = 1
    group by p.OwnerUserId
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Location,
    u.Reputation,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    pg.QuestionCount,
    pg.AnswerCount,
    pg.AvgPostScore,
    pg.TotalViews,
    coalesce(uqcs.ClosedQuestions,0) as ClosedQuestions,
    coalesce(uqcs.TotalCloseVotes,0) as TotalCloseVotes,
    uqcs.CloseReasons,
    avg(par.AnswerToScoreRatio) filter (where par.AnswerToScoreRatio is not null) as AvgAnswerToScoreRatio,
    max(par.Score) filter (where par.RecentQuestionRank = 1) as LatestQuestionScore,
    substring(pg.TitlesSample from 1 for 150) as TitlesSampleShort
from Users u
left join UserBadgeCounts ub on u.Id = ub.UserId
left join PostAggregates pg on u.Id = pg.OwnerUserId
left join UserQuestionCloseStats uqcs on u.Id = uqcs.OwnerUserId
left join PostAnswerRates par on u.Id = par.OwnerUserId
where u.Reputation > 2000 
  and (pg.QuestionCount > 10 or pg.AnswerCount > 20)
group by 
    u.Id, u.DisplayName, u.Location, u.Reputation, 
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    pg.QuestionCount, pg.AnswerCount, pg.AvgPostScore, pg.TotalViews,
    uqcs.ClosedQuestions, uqcs.TotalCloseVotes, uqcs.CloseReasons,
    pg.TitlesSample
having avg(par.AnswerToScoreRatio) filter (where par.AnswerToScoreRatio is not null) > 0.5
order by u.Reputation desc, pg.QuestionCount desc
limit 50;