-- {"query": "652.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2962}
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        case when p.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select
        QuestionId,
        AnswerId,
        AnswerUserId,
        AnswerScore,
        AnswerCreationDate
    from (
        select
            a.*,
            row_number() over (partition by QuestionId order by AnswerCreationDate) as rn
        from answers a
    ) t
    where rn = 1
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
        count(*) as TotalVotes
    from Votes v
    group by v.PostId
),
commenter_diversity as (
    select
        c.PostId,
        count(*) as CommentCount,
        count(distinct coalesce(cast(c.UserId as varchar), c.UserDisplayName)) as DistinctCommenters
    from Comments c
    group by c.PostId
),
close_events as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstCloseDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as AnyReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as HasCloseVote
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateId,
        pl.RelatedPostId as OriginalId,
        min(pl.CreationDate) as FirstDupLinkDate
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.UpVotes as UUp,
        u.DownVotes as UDown,
        u.Views as UViews,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormLocation
    from Users u
),
tag_expansion as (
    select
        rq.QuestionId,
        unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><')) as TagName
    from recent_questions rq
    where rq.Tags is not null
),
tag_rank as (
    select
        te.QuestionId,
        te.TagName,
        t.Count as GlobalTagCount,
        row_number() over (partition by te.QuestionId order by t.Count desc nulls last, te.TagName) as TagPopularityRank
    from tag_expansion te
    left join Tags t on t.TagName = te.TagName
),
question_baseline as (
    select
        rq.QuestionId,
        rq.CreationDate,
        rq.OwnerUserId,
        rq.Score,
        rq.ViewCount,
        rq.AnswerCount,
        rq.IsClosed,
        coalesce(va.UpVotes,0) as UpVotes,
        coalesce(va.DownVotes,0) as DownVotes,
        coalesce(va.TotalVotes,0) as TotalVotes,
        coalesce(va.BountyStarted,0) as BountyStarted,
        coalesce(va.BountyAwarded,0) as BountyAwarded,
        coalesce(cd.CommentCount,0) as CommentCount,
        coalesce(cd.DistinctCommenters,0) as DistinctCommenters,
        ce.FirstCloseDate,
        ce.AnyReopenDate,
        ce.HasCloseVote,
        fa.AnswerId as FirstAnswerId,
        fa.AnswerUserId,
        fa.AnswerScore,
        fa.AnswerCreationDate,
        max(case when tr.TagPopularityRank = 1 then tr.TagName end) as TopTag,
        max(case when tr.TagPopularityRank = 1 then tr.GlobalTagCount end) as TopTagGlobalCount,
        count(tr.TagName) as TagCount
    from recent_questions rq
    left join votes_agg va on va.PostId = rq.QuestionId
    left join commenter_diversity cd on cd.PostId = rq.QuestionId
    left join close_events ce on ce.PostId = rq.QuestionId
    left join first_answer fa on fa.QuestionId = rq.QuestionId
    left join tag_rank tr on tr.QuestionId = rq.QuestionId
    group by
        rq.QuestionId, rq.CreationDate, rq.OwnerUserId, rq.Score, rq.ViewCount, rq.AnswerCount, rq.IsClosed,
        va.UpVotes, va.DownVotes, va.TotalVotes, va.BountyStarted, va.BountyAwarded,
        cd.CommentCount, cd.DistinctCommenters,
        ce.FirstCloseDate, ce.AnyReopenDate, ce.HasCloseVote,
        fa.AnswerId, fa.AnswerUserId, fa.AnswerScore, fa.AnswerCreationDate
),
user_enriched as (
    select
        qb.*,
        us.Reputation as OwnerReputation,
        us.NormLocation as OwnerLocation,
        us.UViews as OwnerProfileViews,
        us.UUp as OwnerUpVotes,
        us.UDown as OwnerDownVotes
    from question_baseline qb
    left join user_stats us on us.UserId = qb.OwnerUserId
),
answer_user_enriched as (
    select
        ue.*,
        aus.Reputation as AnswererReputation,
        aus.NormLocation as AnswererLocation
    from user_enriched ue
    left join user_stats aus on aus.UserId = ue.AnswerUserId
),
activity_windows as (
    select
        aue.*,
        extract(epoch from (aue.AnswerCreationDate - aue.CreationDate)) / 60.0 as MinutesToFirstAnswer,
        extract(epoch from (aue.FirstCloseDate - aue.CreationDate)) / 3600.0 as HoursToFirstClose,
        count(*) over (
            partition by aue.OwnerUserId
            order by extract(epoch from aue.CreationDate)
            range between (7 * 24 * 3600) preceding and current row
        ) as OwnerRolling7dQuestions,
        percent_rank() over (order by coalesce(aue.Score,0)) as ScorePercentile,
        dense_rank() over (partition by aue.TopTag order by coalesce(aue.ViewCount,0) desc) as RankWithinTopTagByViews
    from answer_user_enriched aue
),
question_quality as (
    select
        aw.*,
        case
            when coalesce(aw.UpVotes,0) + coalesce(aw.DownVotes,0) = 0 then null
            else round(100.0 * coalesce(aw.UpVotes,0) / nullif(coalesce(aw.UpVotes,0) + coalesce(aw.DownVotes,0),0), 2)
        end as UpvoteRatioPct,
        case
            when aw.BountyAwarded > 0 then 'BountyAwarded'
            when aw.BountyStarted > 0 then 'BountyStarted'
            else 'NoBounty'
        end as BountyStatus,
        case
            when aw.IsClosed = 1 and aw.AnyReopenDate is not null then 'ClosedThenReopened'
            when aw.IsClosed = 1 then 'Closed'
            else 'Open'
        end as CloseStateBucket,
        case
            when aw.AnswerCount = 0 then 'Unanswered'
            when aw.AnswerScore is null or aw.AnswerScore <= 0 then 'AnsweredLowScore'
            when aw.AnswerScore between 1 and 2 then 'AnsweredMedScore'
            else 'AnsweredHighScore'
        end as AnswerQualityBucket
    from activity_windows aw
),
owner_baseline as (
    select
        OwnerUserId,
        count(*) as OwnerQuestionCount,
        avg(coalesce(ViewCount,0)) as OwnerAvgViews,
        avg(coalesce(Score,0)) as OwnerAvgScore
    from question_quality
    group by OwnerUserId
),
final_rank as (
    select
        qq.*,
        ob.OwnerQuestionCount,
        ob.OwnerAvgViews,
        ob.OwnerAvgScore,
        (
            coalesce(qq.ScorePercentile,0) * 0.4 +
            coalesce(qq.UpvoteRatioPct,0) / 100.0 * 0.3 +
            least(coalesce(qq.ViewCount,0) / nullif(ob.OwnerAvgViews,0), 5.0) * 0.2 +
            case when qq.MinutesToFirstAnswer is null then 0.0
                 when qq.MinutesToFirstAnswer <= 30 then 0.1
                 when qq.MinutesToFirstAnswer <= 180 then 0.05
                 else 0.02 end
        ) as CompositeScore
    from question_quality qq
    left join owner_baseline ob on ob.OwnerUserId = qq.OwnerUserId
),
tag_histogram as (
    select
        tr.TagName,
        count(distinct tr.QuestionId) as QuestionsWithTag,
        avg(fr.CompositeScore) as AvgCompositeByTag
    from tag_rank tr
    join final_rank fr on fr.QuestionId = tr.QuestionId
    where tr.TagPopularityRank <= 3
    group by tr.TagName
),
scored as (
    select
        fr.*,
        ntile(10) over (order by fr.CompositeScore desc nulls last) as CompositeDecile
    from final_rank fr
),
filtered as (
    select *
    from scored
    where
        (
            (UpVotes - DownVotes >= 5 and ViewCount >= 1000)
            or (BountyStatus in ('BountyStarted','BountyAwarded'))
            or (CloseStateBucket = 'ClosedThenReopened')
            or (AnswerQualityBucket in ('AnsweredHighScore') and MinutesToFirstAnswer <= 60)
        )
        and (coalesce(TopTag, '') not ilike '%homework%' and coalesce(TopTag, '') not ilike '%survey%')
        and (OwnerReputation is null or OwnerReputation >= 1000 or OwnerRolling7dQuestions <= 10)
        and (TagCount between 1 and 5 or TagCount is null)
)
select
    f.QuestionId,
    f.CreationDate,
    coalesce(f.TopTag, 'untagged') as TopTag,
    tgh.AvgCompositeByTag,
    f.CompositeScore,
    f.CompositeDecile,
    f.Score,
    f.ViewCount,
    f.UpVotes,
    f.DownVotes,
    f.UpvoteRatioPct,
    f.AnswerCount,
    f.MinutesToFirstAnswer,
    f.HoursToFirstClose,
    f.CloseStateBucket,
    f.BountyStatus,
    f.AnswerQualityBucket,
    f.OwnerUserId,
    coalesce(f.OwnerReputation, -1) as OwnerReputation,
    coalesce(f.OwnerLocation, 'Unknown') as OwnerLocation,
    f.AnswerUserId,
    coalesce(f.AnswererReputation, -1) as AnswererReputation,
    f.RankWithinTopTagByViews,
    (
        select case when q.AcceptedAnswerId = f.FirstAnswerId then 1 else 0 end
        from Posts q
        where q.Id = f.QuestionId and q.PostTypeId = 1
    ) as AcceptedWasFirstAnswer,
    (
        'Q' || cast(f.QuestionId as varchar) ||
        ' [' || coalesce(f.TopTag,'untagged') || '] ' ||
        case when f.IsClosed = 1 then '(closed)' else '(open)' end ||
        ' score=' || cast(coalesce(f.Score,0) as varchar) ||
        ' views=' || cast(coalesce(f.ViewCount,0) as varchar)
    ) as Summary
from filtered f
left join tag_histogram tgh on tgh.TagName = f.TopTag
where
    coalesce(f.CompositeScore, 0) > 0
    and not (f.AnyReopenDate is null and f.IsClosed = 1 and f.UpVotes < 0)
order by
    f.CompositeDecile asc,
    f.CompositeScore desc,
    f.ViewCount desc
limit 200;