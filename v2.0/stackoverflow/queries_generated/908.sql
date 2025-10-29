-- {"query": "908.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2838} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as TagArray
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId, a.Score, a.CreationDate
    from Posts a
    where a.PostTypeId = 2
),
accepted as (
    select q.QuestionId, case when q.QuestionId = p.Id then 1 else 0 end as HasAccepted
    from recent_questions q
    left join Posts p on p.Id = q.QuestionId and p.AcceptedAnswerId is not null
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
    from Votes v
    group by v.PostId
),
comment_sentiment as (
    select
        c.PostId,
        avg(nullif(case
            when position('thanks' in lower(c.Text)) > 0 then 0.2
            when position('great' in lower(c.Text)) > 0 then 0.3
            when position('bad' in lower(c.Text)) > 0 then -0.2
            when position('hate' in lower(c.Text)) > 0 then -0.4
            when position('helpful' in lower(c.Text)) > 0 then 0.4
            else 0
        end, 0)) as AvgSentiment,
        count(*) as CommentCount
    from Comments c
    group by c.PostId
),
tag_expansion as (
    select
        q.QuestionId,
        lower(trim(t)) as tag
    from recent_questions q
    cross join lateral unnest(q.TagArray) as t
),
tag_stats as (
    select te.tag, count(*) as TagQCount, avg(q.Score) as AvgTagScore
    from tag_expansion te
    join recent_questions q on q.QuestionId = te.QuestionId
    group by te.tag
),
user_quality as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(sum(case when b.Class = 1 then 5 when b.Class = 2 then 2 when b.Class = 3 then 1 end),0) as BadgeScore,
        count(distinct b.Id) as BadgeCount,
        avg(extract(epoch from (now() - least(u.LastAccessDate, now()))) / 86400.0) filter (where u.LastAccessDate is not null) over () as GlobalInactivityDaysAvg
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
dup_links as (
    select pl.PostId, count(*) as DuplicateLinks
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
close_events as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as ClosedCount,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as LastCloseReasonId,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedAt
    from PostHistory ph
    group by ph.PostId
),
question_answer_latency as (
    select
        q.QuestionId,
        min(a.CreationDate) as FirstAnswerAt,
        extract(epoch from (min(a.CreationDate) - q.CreationDate))/60.0 as MinutesToFirstAnswer
    from recent_questions q
    left join answers a on a.QuestionId = q.QuestionId
    group by q.QuestionId, q.CreationDate
),
owner_last_activity as (
    select
        u.Id as UserId,
        u.LastAccessDate,
        row_number() over (order by u.LastAccessDate desc) as ActivityRank
    from Users u
),
question_rank as (
    select
        q.QuestionId,
        q.Title,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        va.UpVotes,
        va.DownVotes,
        va.Favorites,
        va.BountyTotal,
        cs.AvgSentiment,
        cs.CommentCount,
        coalesce(dl.DuplicateLinks,0) as DuplicateLinks,
        coalesce(ce.ClosedCount,0) as ClosedCount,
        ce.LastCloseReasonId,
        ce.LastClosedAt,
        qal.MinutesToFirstAnswer,
        sum(coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0)) over (order by q.CreationDate rows between unbounded preceding and current row) as CumNetVotes,
        dense_rank() over (order by q.Score desc, q.ViewCount desc) as ScoreDenseRank,
        percent_rank() over (order by q.ViewCount) as ViewPercentile
    from recent_questions q
    left join votes_agg va on va.PostId = q.QuestionId
    left join comment_sentiment cs on cs.PostId = q.QuestionId
    left join dup_links dl on dl.PostId = q.QuestionId
    left join close_events ce on ce.PostId = q.QuestionId
    left join question_answer_latency qal on qal.QuestionId = q.QuestionId
),
tagged_quality as (
    select
        qr.*,
        array_agg(distinct te.tag) as Tags,
        avg(ts.AvgTagScore) as AvgTagScoreAcrossTags,
        max(ts.TagQCount) as MaxTagQCount
    from question_rank qr
    left join tag_expansion te on te.QuestionId = qr.QuestionId
    left join tag_stats ts on ts.tag = te.tag
    group by qr.QuestionId, qr.Title, qr.CreationDate, qr.OwnerUserId, qr.Score, qr.ViewCount, qr.AnswerCount,
             qr.UpVotes, qr.DownVotes, qr.Favorites, qr.BountyTotal, qr.AvgSentiment, qr.CommentCount,
             qr.DuplicateLinks, qr.ClosedCount, qr.LastCloseReasonId, qr.LastClosedAt, qr.MinutesToFirstAnswer,
             qr.CumNetVotes, qr.ScoreDenseRank, qr.ViewPercentile
),
owner_enriched as (
    select
        tq.*,
        u.DisplayName as OwnerDisplayName,
        u.Location,
        uq.Reputation,
        uq.BadgeScore,
        uq.BadgeCount,
        uq.UpVotes as OwnerUpVotes,
        uq.DownVotes as OwnerDownVotes,
        uq.ProfileViews,
        ola.LastAccessDate as OwnerLastAccess,
        ola.ActivityRank as OwnerActivityRank
    from tagged_quality tq
    left join Users u on u.Id = tq.OwnerUserId
    left join user_quality uq on uq.UserId = tq.OwnerUserId
    left join owner_last_activity ola on ola.UserId = tq.OwnerUserId
),
predicted_engagement as (
    select
        oe.*,
        /* Composite score blending various signals, with NULL-safe logic */
        (
            coalesce(oe.Score,0) * 1.5
          + coalesce(oe.ViewCount,0) * 0.01
          + coalesce(oe.AnswerCount,0) * 2.0
          + coalesce(oe.Favorites,0) * 0.8
          + coalesce(oe.BountyTotal,0) * 0.05
          + coalesce(oe.AvgSentiment, 0) * 10
          - coalesce(oe.DuplicateLinks,0) * 3
          - case when coalesce(oe.ClosedCount,0) > 0 then 5 else 0 end
          - greatest(0, coalesce(oe.DownVotes,0) - coalesce(oe.UpVotes,0)) * 0.5
          + coalesce(oe.AvgTagScoreAcrossTags, 0) * 0.7
          + coalesce(oe.Reputation,0) * 0.002
          + least(10, greatest(0, 100 - coalesce(oe.MinutesToFirstAnswer, 10000)/10.0))
        ) as EngagementScore
    from owner_enriched oe
),
benchmarked as (
    select
        *,
        ntile(10) over (order by EngagementScore desc) as Decile,
        row_number() over (order by EngagementScore desc, Score desc, ViewCount desc) as GlobalRank,
        case
            when coalesce(ClosedCount,0) > 0 then 'Closed'
            when coalesce(DuplicateLinks,0) > 0 then 'Dup'
            when Favorites is not null and Favorites > 50 then 'Favored'
            else 'Normal'
        end as StatusBucket
    from predicted_engagement
),
complex_null_logic as (
    select
        b.*,
        /* exercise different NULL handling expressions */
        nullif(trim(coalesce(OwnerDisplayName, '')), '') as NormalizedOwnerName,
        coalesce(LastCloseReasonId::varchar, 'N/A') as LastCloseReasonText,
        case
            when AvgSentiment is distinct from null and AvgSentiment > 0.25 then 'Positive'
            when AvgSentiment is null then 'Unknown'
            else 'NeutralOrNegative'
        end as SentimentBucket
    from benchmarked b
)
select
    c.QuestionId,
    c.Title,
    c.OwnerUserId,
    c.NormalizedOwnerName as OwnerDisplayName,
    c.Reputation,
    c.BadgeScore,
    c.Score,
    c.ViewCount,
    c.AnswerCount,
    c.UpVotes,
    c.DownVotes,
    c.Favorites,
    c.BountyTotal,
    c.CommentCount,
    c.AvgSentiment,
    c.SentimentBucket,
    c.DuplicateLinks,
    c.ClosedCount,
    c.LastCloseReasonText,
    c.MinutesToFirstAnswer,
    c.AvgTagScoreAcrossTags,
    c.MaxTagQCount,
    c.Tags,
    c.EngagementScore,
    c.Decile,
    c.GlobalRank,
    c.StatusBucket,
    c.ViewPercentile,
    c.CreationDate,
    c.OwnerLastAccess,
    c.OwnerActivityRank,
    /* Correlated subquery: last editor name or fallback to owner */
    coalesce(
        (select ue.DisplayName from Users ue where ue.Id = (select p.LastEditorUserId from Posts p where p.Id = c.QuestionId)),
        c.OwnerDisplayName
    ) as LastEditorOrOwner,
    /* Set operator example: number of intersecting tags with top 5 tags by count */
    (
        select count(*)
        from (
            select lower(t.TagName) as tag
            from Tags t
            order by t.Count desc
            limit 5
        ) top5
        where top5.tag = any(c.Tags)
    ) as IntersectTopTags,
    /* Outer apply-like lateral subquery to compute moving average by owner */
    (
        select avg(sub.Score::numeric)
        from (
            select qr2.Score
            from question_rank qr2
            where qr2.OwnerUserId = c.OwnerUserId
            order by qr2.CreationDate desc
            limit 20
        ) sub
    ) as OwnerRecentScoreAvg20
from complex_null_logic c
where
    /* complicated predicate */
    (
        (c.Decile <= 3 and c.ScoreDenseRank <= 1000)
        or (c.StatusBucket in ('Normal','Favored') and coalesce(c.MinutesToFirstAnswer, 1e9) < 1440)
        or (c.SentimentBucket = 'Positive' and c.ViewPercentile >= 0.5)
    )
    and not (c.ClosedCount > 0 and c.DuplicateLinks > 0)
    and (
        exists (
            select 1
            from tag_expansion te
            where te.QuestionId = c.QuestionId
              and te.tag in ('sql','database','postgresql','mysql','sqlite')
        )
        or c.Favorites >= 10
    )
order by
    c.Decile asc,
    c.EngagementScore desc,
    c.GlobalRank asc
limit 500;