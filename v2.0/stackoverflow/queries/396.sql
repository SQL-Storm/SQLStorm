-- {"query": "396.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2643}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (
          select date_trunc('month', max(CreationDate)) - interval '12 months'
          from Posts where PostTypeId = 1
      )
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
latest_activity as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastHistoryDate,
        max(case when ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36) then ph.CreationDate end) as LastModEventDate
    from PostHistory ph
    group by ph.PostId
),
question_dupe_groups as (
    select
        pl.PostId as QuestionId,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks,
        count(case when pl.LinkTypeId = 1 then 1 end) as LinkedLinks,
        array_agg(distinct pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) as DupeTargets
    from PostLinks pl
    group by pl.PostId
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.CreationDate, u.Location, u.UpVotes, u.DownVotes, u.Views
),
tag_unpacked as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as TagName
    from recent_questions q
    where q.Tags is not null and q.Tags like '<%>'
),
tag_stats as (
    select
        t.TagName,
        count(distinct tu.QuestionId) as TaggedQuestions,
        sum(rq.ViewCount) as TaggedViews,
        avg(rq.Score) as AvgScoreForTag
    from tag_unpacked tu
    join recent_questions rq on rq.QuestionId = tu.QuestionId
    join Tags t on lower(t.TagName) = lower(tu.TagName)
    group by t.TagName
),
answer_latency as (
    select
        rq.QuestionId,
        min(extract(epoch from (a.AnswerCreationDate - rq.CreationDate))) as FirstAnswerLatencySeconds,
        avg(a.AnswerScore) as AvgAnswerScore,
        count(a.AnswerId) as AnswerCountObserved
    from recent_questions rq
    left join answers a on a.QuestionId = rq.QuestionId
    group by rq.QuestionId
),
vote_agg as (
    select
        v.PostId,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        count(case when v.VoteTypeId = 5 then 1 end) as Favorites,
        coalesce(sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end),0) as BountyAmountTotal
    from Votes v
    group by v.PostId
),
question_quality as (
    select
        rq.QuestionId,
        rq.Title,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        ua.Reputation as OwnerReputation,
        ua.TotalBadges,
        va.UpVotes as QUp,
        va.DownVotes as QDown,
        va.Favorites as QFavs,
        va.BountyAmountTotal as QBounty,
        al.FirstAnswerLatencySeconds,
        al.AvgAnswerScore,
        al.AnswerCountObserved,
        lg.LastHistoryDate,
        lg.LastModEventDate,
        qdg.DuplicateLinks,
        qdg.LinkedLinks,
        case
            when rq.Title is null or trim(rq.Title) = '' then 1
            when length(regexp_replace(rq.Title, '\s+', '', 'g')) < 10 then 1
            else 0
        end as IsSuspiciousTitle,
        case
            when rq.Tags is null then 1
            when array_length(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'),1) < 1 then 1
            else 0
        end as IsMissingTags
    from recent_questions rq
    left join user_activity ua on ua.UserId = rq.OwnerUserId
    left join vote_agg va on va.PostId = rq.QuestionId
    left join answer_latency al on al.QuestionId = rq.QuestionId
    left join latest_activity lg on lg.PostId = rq.QuestionId
    left join question_dupe_groups qdg on qdg.QuestionId = rq.QuestionId
),
dup_reason as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastCloseEvent,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Text end) as CloseEventPayload
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
owner_norm as (
    select
        ua.UserId,
        avg(q.Score) as AvgQScore,
        stddev_pop(q.Score) as StdQScore,
        avg(q.ViewCount) as AvgQViews
    from Users u
    join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
    join user_activity ua on ua.UserId = u.Id
    group by ua.UserId
),
ranked_questions as (
    select
        qq.QuestionId,
        qq.Title,
        qq.CreationDate,
        qq.Score,
        qq.ViewCount,
        qq.AnswerCount,
        qq.OwnerReputation,
        qq.TotalBadges,
        qq.QUp,
        qq.QDown,
        qq.QFavs,
        qq.QBounty,
        qq.FirstAnswerLatencySeconds,
        qq.AvgAnswerScore,
        qq.AnswerCountObserved,
        qq.LastHistoryDate,
        qq.LastModEventDate,
        qq.DuplicateLinks,
        qq.LinkedLinks,
        qq.IsSuspiciousTitle,
        qq.IsMissingTags,
        dr.LastCloseEvent,
        dr.LastCloseReasonId,
        dr.CloseEventPayload,
        onm.AvgQScore,
        onm.StdQScore,
        onm.AvgQViews,
        dense_rank() over (order by coalesce(qq.Score,0) desc, coalesce(qq.ViewCount,0) desc, qq.CreationDate desc) as RankByScoreViews,
        row_number() over (partition by date_trunc('month', qq.CreationDate) order by coalesce(qq.ViewCount,0) desc) as MonthlyTopByViews,
        sum(coalesce(qq.QUp,0) - coalesce(qq.QDown,0)) over (partition by (case when qq.OwnerReputation is not null then 1 else 0 end) order by qq.CreationDate rows between unbounded preceding and current row) as RunningNetVotesByKnownOwner,
        lag(qq.Score) over (order by qq.CreationDate) as PrevScore,
        lead(qq.Score) over (order by qq.CreationDate) as NextScore
    from question_quality qq
    left join dup_reason dr on dr.PostId = qq.QuestionId
    left join owner_norm onm on onm.UserId = qq.OwnerReputation
),
scored as (
    select
        r.QuestionId,
        r.Title,
        r.CreationDate,
        r.Score,
        r.ViewCount,
        r.AnswerCount,
        r.OwnerReputation,
        r.TotalBadges,
        r.QUp,
        r.QDown,
        r.QFavs,
        r.QBounty,
        r.FirstAnswerLatencySeconds,
        r.AvgAnswerScore,
        r.AnswerCountObserved,
        r.LastHistoryDate,
        r.LastModEventDate,
        r.DuplicateLinks,
        r.LinkedLinks,
        r.LastCloseEvent,
        r.LastCloseReasonId,
        r.CloseEventPayload,
        r.RankByScoreViews,
        r.MonthlyTopByViews,
        r.RunningNetVotesByKnownOwner,
        r.PrevScore,
        r.NextScore,
        r.IsSuspiciousTitle,
        r.IsMissingTags,
        (
            coalesce(r.Score,0)*2
            + coalesce(r.QUp,0)
            - coalesce(r.QDown,0)
            + coalesce(r.QFavs,0)/2.0
            + greatest(0, 100 - coalesce(r.FirstAnswerLatencySeconds, 86400)/864.0)
            + least(coalesce(r.ViewCount,0)/100.0, 50)
            + coalesce(r.AvgAnswerScore,0)
            + coalesce(r.TotalBadges,0)/10.0
            + case when coalesce(r.DuplicateLinks,0) > 0 then -10 else 0 end
            + case when r.LastCloseEvent is not null then -20 else 0 end
            - case when r.IsSuspiciousTitle = 1 then 5 else 0 end
            - case when r.IsMissingTags = 1 then 3 else 0 end
        ) as CompositeScore
    from ranked_questions r
),
top_and_bottom_union as (
    select s.*,
           'TOP' as Bucket,
           dense_rank() over (order by s.CompositeScore desc, s.CreationDate desc) as dr_top,
           cast(null as integer) as dr_bottom
    from scored s
    union all
    select s.*,
           'BOTTOM' as Bucket,
           cast(null as integer) as dr_top,
           dense_rank() over (order by s.CompositeScore asc, s.CreationDate asc) as dr_bottom
    from scored s
),
top_and_bottom as (
    select *
    from top_and_bottom_union
    where (Bucket = 'TOP' and dr_top <= 100)
       or (Bucket = 'BOTTOM' and dr_bottom <= 100)
),
tag_rollup as (
    select
        tu.QuestionId,
        string_agg(distinct tu.TagName, ',' order by tu.TagName) as TagsCsv
    from tag_unpacked tu
    group by tu.QuestionId
)
select
    tb.Bucket,
    tb.QuestionId,
    coalesce(tb.Title, '(no title)') as Title,
    tb.CreationDate,
    tb.Score,
    tb.ViewCount,
    tb.AnswerCount,
    tb.CompositeScore,
    tb.QUp, tb.QDown, tb.QFavs, tb.QBounty,
    tb.FirstAnswerLatencySeconds,
    tb.AvgAnswerScore,
    tb.AnswerCountObserved,
    tb.DuplicateLinks,
    tb.LinkedLinks,
    tb.LastCloseEvent,
    tb.LastCloseReasonId,
    case
        when tb.LastCloseReasonId ~ '^[0-9]+$' then
            (select crt.Name from CloseReasonTypes crt where crt.Id = cast(tb.LastCloseReasonId as integer))
        else null
    end as LastCloseReasonName,
    ts.TaggedQuestions as TagPopularityCount,
    ts.TaggedViews as TagPopularityViews,
    ts.AvgScoreForTag,
    tr.TagsCsv,
    tb.OwnerReputation,
    tb.TotalBadges,
    tb.RankByScoreViews,
    tb.MonthlyTopByViews,
    tb.RunningNetVotesByKnownOwner,
    tb.PrevScore,
    tb.NextScore
from top_and_bottom tb
left join (
    select tu.QuestionId,
           max(ts.TaggedQuestions) as TaggedQuestions,
           max(ts.TaggedViews) as TaggedViews,
           avg(ts.AvgScoreForTag) as AvgScoreForTag
    from tag_unpacked tu
    join tag_stats ts on lower(ts.TagName) = lower(tu.TagName)
    group by tu.QuestionId
) ts on ts.QuestionId = tb.QuestionId
left join tag_rollup tr on tr.QuestionId = tb.QuestionId
order by tb.Bucket, tb.CompositeScore desc, tb.CreationDate desc;