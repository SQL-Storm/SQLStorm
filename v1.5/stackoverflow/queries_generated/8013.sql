-- {"query": "8013.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3388} 
with params as (
    select
        now() - interval '365 days' as since_date,
        50 as min_views,
        3 as min_answers
),
-- Normalize tags into rows
question_tags as (
    select
        p.Id as QuestionId,
        lower(trim(tg)) as tag
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId and pt.Name = 'Question'
    cross join lateral unnest(
        case
            when p.Tags is null then array[]::varchar[]
            else string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')
        end
    ) as tg
    where p.CreationDate >= (select since_date from params)
      and coalesce(p.ViewCount, 0) >= (select min_views from params)
      and coalesce(p.AnswerCount, 0) >= (select min_answers from params)
),
-- Score and activity aggregates per question
question_stats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        q.FavoriteCount,
        q.ClosedDate,
        q.AcceptedAnswerId,
        -- recency decay score blends score, views, answers with age penalty
        (
            coalesce(q.Score,0) * 1.0
            + ln(greatest(coalesce(q.ViewCount,0), 1)) * 0.8
            + coalesce(q.AnswerCount,0) * 1.5
        ) / nullif(extract(epoch from (now() - q.CreationDate)) / 86400.0 + 1, 0) as recency_score
    from Posts q
    join PostTypes pt on pt.Id = q.PostTypeId and pt.Name = 'Question'
    where q.CreationDate >= (select since_date from params)
      and coalesce(q.ViewCount, 0) >= (select min_views from params)
      and coalesce(q.AnswerCount, 0) >= (select min_answers from params)
),
-- Find duplicates and their canonical targets (if any)
dup_links as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as CanonicalQuestionId,
        pl.CreationDate as LinkDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
-- Extract close events and reasons from PostHistory
close_events as (
    select
        ph.PostId as QuestionId,
        ph.CreationDate as CloseDate,
        nullif(trim(ph.Comment), '') as CloseReasonId_text,
        try_cast(nullif(trim(ph.Comment), '') as int) as CloseReasonId_int,
        ph.Text as CloseVotersJson
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
),
close_reasons as (
    select
        ce.QuestionId,
        ce.CloseDate,
        coalesce(crt.Name, concat('Reason#', ce.CloseReasonId_int::text)) as CloseReasonName
    from close_events ce
    left join CloseReasonTypes crt on crt.Id = ce.CloseReasonId_int
),
-- Answer metrics per question using window functions
answer_metrics as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCountActual,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore,
        percentile_cont(0.5) within group (order by a.Score) as MedianAnswerScore,
        min(a.CreationDate) as FirstAnswerDate,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    join PostTypes pt on pt.Id = a.PostTypeId and pt.Name = 'Answer'
    join Posts q on q.Id = a.ParentId
    where q.CreationDate >= (select since_date from params)
    group by a.ParentId
),
-- Comment sentiment proxy and activity per question
comment_metrics as (
    select
        c.PostId as QuestionId,
        count(*) as CommentCount,
        sum(coalesce(c.Score,0)) as CommentScoreSum,
        avg(coalesce(c.Score,0)) as CommentScoreAvg,
        sum(case when c.Text ~* '\b(thanks|great|helpful|nice|awesome)\b' then 1 else 0 end) as PositiveHints,
        sum(case when c.Text ~* '\b(bad|wrong|terrible|awful|useless)\b' then 1 else 0 end) as NegativeHints,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
-- Votes per question
vote_metrics as (
    select
        v.PostId as QuestionId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotesCount,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotesCount,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as FavoriteVotesCount,
        sum(case when vt.Name in ('UpMod','DownMod') then 1 else 0 end) as TotalVotesCount,
        sum(case when vt.Name = 'BountyStart' then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when vt.Name = 'BountyClose' then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
-- User reputation snapshot at question time using a correlated subquery
asker_rep_at_post as (
    select
        q.QuestionId,
        (
            select u.Reputation
            from Users u
            where u.Id = qs.OwnerUserId
        ) as ReputationAtNow,
        -- proxy for rep at post time: current rep minus downvotes since then (cannot compute exactly without history)
        greatest(0,
            coalesce((
                select u2.UpVotes - u2.DownVotes
                from Users u2
                where u2.Id = qs.OwnerUserId
            ),0)
        ) as VotesBalanceProxy
    from question_stats qs
    join LATERAL (select qs.QuestionId) q on true
),
-- Tag popularity and diversity per question
question_tag_profile as (
    select
        qt.QuestionId,
        count(*) as TagCount,
        sum(coalesce(t.Count,0)) as TagAggregateCount,
        avg(coalesce(t.Count,0)) as TagAvgPopularity,
        min(coalesce(t.Count,0)) as TagMinPopularity,
        max(coalesce(t.Count,0)) as TagMaxPopularity,
        string_agg(qt.tag, '|' order by qt.tag) as TagsConcat
    from question_tags qt
    left join Tags t on t.TagName = qt.tag
    group by qt.QuestionId
),
-- Identify "hotness" using window ranking within day buckets
daily_rank as (
    select
        qs.QuestionId,
        date_trunc('day', qs.CreationDate) as DayBucket,
        qs.recency_score,
        row_number() over (partition by date_trunc('day', qs.CreationDate) order by qs.recency_score desc, qs.Score desc, qs.ViewCount desc, qs.AnswerCount desc, qs.QuestionId) as RankInDay
    from question_stats qs
),
-- Merge all metrics
all_metrics as (
    select
        qs.QuestionId,
        qs.OwnerUserId,
        qs.CreationDate,
        qs.Score as QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        qs.FavoriteCount,
        qs.ClosedDate,
        qs.AcceptedAnswerId,
        qs.recency_score,
        dr.DayBucket,
        dr.RankInDay,
        am.AnswerCountActual,
        am.HasAccepted,
        am.MaxAnswerScore,
        am.AvgAnswerScore,
        am.MedianAnswerScore,
        am.FirstAnswerDate,
        am.LastAnswerDate,
        cm.CommentCount,
        cm.CommentScoreSum,
        cm.CommentScoreAvg,
        cm.PositiveHints,
        cm.NegativeHints,
        cm.LastCommentDate,
        vm.UpVotesCount,
        vm.DownVotesCount,
        vm.FavoriteVotesCount,
        vm.TotalVotesCount,
        vm.BountyStarted,
        vm.BountyAwarded,
        vm.LastVoteDate,
        arp.ReputationAtNow,
        arp.VotesBalanceProxy,
        qtp.TagCount,
        qtp.TagAggregateCount,
        qtp.TagAvgPopularity,
        qtp.TagMinPopularity,
        qtp.TagMaxPopularity,
        qtp.TagsConcat,
        cr.CloseReasonName,
        dl.CanonicalQuestionId,
        case when dl.CanonicalQuestionId is not null then 1 else 0 end as IsDuplicate,
        -- string manipulation: generate a synthetic slug
        lower(regexp_replace(coalesce(p.Title, 'untitled'), '\s+', '-', 'g')) as TitleSlug,
        -- null/zero-safe engagement score
        (
            coalesce(qs.Score,0) * 2.0
            + coalesce(vm.UpVotesCount,0) * 1.5
            - coalesce(vm.DownVotesCount,0) * 1.2
            + ln(greatest(coalesce(qs.ViewCount,0),1)) * 0.9
            + coalesce(am.AnswerCountActual,0) * 1.7
            + coalesce(cm.CommentCount,0) * 0.3
            + case when am.HasAccepted > 0 then 3 else 0 end
            + case when qs.ClosedDate is not null then -2 else 0 end
            - case when dl.CanonicalQuestionId is not null then 4 else 0 end
        ) as EngagementScore
    from question_stats qs
    join Posts p on p.Id = qs.QuestionId
    left join daily_rank dr on dr.QuestionId = qs.QuestionId
    left join answer_metrics am on am.QuestionId = qs.QuestionId
    left join comment_metrics cm on cm.QuestionId = qs.QuestionId
    left join vote_metrics vm on vm.QuestionId = qs.QuestionId
    left join asker_rep_at_post arp on arp.QuestionId = qs.QuestionId
    left join question_tag_profile qtp on qtp.QuestionId = qs.QuestionId
    left join close_reasons cr on cr.QuestionId = qs.QuestionId
    left join dup_links dl on dl.DuplicateQuestionId = qs.QuestionId
),
-- Outlier detection using z-scores for EngagementScore
scored as (
    select
        a.*,
        avg(EngagementScore) over () as EngMean,
        stddev_pop(EngagementScore) over () as EngStd,
        case
            when stddev_pop(EngagementScore) over () > 0
                then (EngagementScore - avg(EngagementScore) over ()) / nullif(stddev_pop(EngagementScore) over (), 0)
            else 0
        end as EngagementZ
    from all_metrics a
),
-- Top N per tag by EngagementZ using set operations and window
per_tag_rank as (
    select
        s.*,
        qt.tag,
        row_number() over (partition by qt.tag order by s.EngagementZ desc, s.EngagementScore desc, s.QuestionId) as RankInTag
    from scored s
    join question_tags qt on qt.QuestionId = s.QuestionId
),
-- Create a synthetic cohort: duplicates vs non-duplicates
cohorts as (
    select QuestionId, 'duplicate'::text as cohort from all_metrics where IsDuplicate = 1
    union all
    select QuestionId, 'unique'::text as cohort from all_metrics where IsDuplicate = 0
),
-- Aggregate cohort stats
cohort_stats as (
    select
        c.cohort,
        count(*) as q_count,
        avg(a.EngagementScore) as avg_engagement,
        avg(a.recency_score) as avg_recency,
        avg(a.TagAvgPopularity) as avg_tag_pop,
        avg(a.AvgAnswerScore) as avg_answer_score,
        avg(a.UpVotesCount) as avg_upvotes,
        sum(case when a.HasAccepted > 0 then 1 else 0 end)::float / nullif(count(*),0) as accepted_rate
    from cohorts c
    join all_metrics a on a.QuestionId = c.QuestionId
    group by c.cohort
),
-- Final selection with complex predicates and NULL-safe logic
final as (
    select
        pt.QuestionId,
        pt.tag,
        pt.RankInTag,
        s.EngagementScore,
        s.EngagementZ,
        s.QuestionScore,
        s.ViewCount,
        s.AnswerCount,
        s.TagCount,
        s.TagAvgPopularity,
        s.CloseReasonName,
        s.IsDuplicate,
        s.CanonicalQuestionId,
        s.TitleSlug,
        s.CreationDate,
        s.DayBucket,
        s.RankInDay,
        -- derived booleans
        case when s.HasAccepted > 0 then true else false end as has_accepted,
        case when s.ClosedDate is not null then true else false end as is_closed,
        -- freshness bucket
        case
            when s.CreationDate >= now() - interval '7 days' then '7d'
            when s.CreationDate >= now() - interval '30 days' then '30d'
            when s.CreationDate >= now() - interval '90 days' then '90d'
            else '365d'
        end as freshness_bucket
    from per_tag_rank pt
    join scored s on s.QuestionId = pt.QuestionId
    where coalesce(pt.RankInTag, 0) between 1 and 5
      and (
            (s.IsDuplicate = 0 and coalesce(s.EngagementScore, -1e9) > 0)
         or (s.IsDuplicate = 1 and s.EngagementZ > 0)
      )
      and (
            s.CloseReasonName is null
         or s.CloseReasonName not ilike any (array['%off-topic%','%opinion%'])
      )
)
select
    f.*,
    cs_unique.avg_engagement as cohort_unique_avg_engagement,
    cs_dup.avg_engagement as cohort_duplicate_avg_engagement,
    -- normalized score vs cohort
    case when f.IsDuplicate = 1
        then (f.EngagementScore - coalesce(cs_dup.avg_engagement,0))
        else (f.EngagementScore - coalesce(cs_unique.avg_engagement,0))
    end as CohortDelta,
    -- complicated expression combining multiple signals
    round(
        (coalesce(f.EngagementZ,0) * 0.6
         + case when f.has_accepted then 0.3 else 0 end
         + case when f.is_closed then -0.5 else 0 end
         + least(2.0, greatest(-2.0, coalesce(f.TagAvgPopularity,0) / nullif(f.ViewCount,0))) * 0.1
        )::numeric
    , 3) as CompositeSignal
from final f
left join cohort_stats cs_unique on cs_unique.cohort = 'unique'
left join cohort_stats cs_dup on cs_dup.cohort = 'duplicate'
order by f.tag, f.RankInTag, f.EngagementZ desc, f.QuestionId
limit 500;