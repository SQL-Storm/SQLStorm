with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.Tags,
        q.Title,
        q.AcceptedAnswerId,
        coalesce(q.AnswerCount, 0) as AnswerCount
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '12 months' from Posts)
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
question_stats as (
    select
        rq.QuestionId,
        rq.CreationDate,
        rq.Score as QuestionScore,
        rq.ViewCount,
        rq.OwnerUserId,
        rq.Tags,
        rq.Title,
        rq.AcceptedAnswerId,
        rq.AnswerCount,
        count(a.AnswerId) as ActualAnswerCount,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as PosAnswerCount,
        sum(case when a.AnswerScore < 0 then 1 else 0 end) as NegAnswerCount,
        min(a.AnswerCreationDate) as FirstAnswerDate,
        max(a.AnswerCreationDate) as LastAnswerDate
    from recent_questions rq
    left join answers a on a.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.CreationDate, rq.Score, rq.ViewCount, rq.OwnerUserId, rq.Tags, rq.Title, rq.AcceptedAnswerId, rq.AnswerCount
),
accepted_answer as (
    select
        q.QuestionId,
        p.Id as AcceptedAnswerId,
        p.Score as AcceptedAnswerScore,
        p.OwnerUserId as AcceptedOwnerId,
        p.CreationDate as AcceptedCreationDate
    from question_stats q
    left join Posts p on p.Id = q.AcceptedAnswerId and p.PostTypeId = 2
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.CreationDate, u.LastAccessDate, LocationNorm
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyAmount
    from Votes v
    group by v.PostId
),
tag_expanded as (
    select
        qs.QuestionId,
        unnest(string_to_array(substring(qs.Tags from 2 for greatest(char_length(qs.Tags)-2,0)), '><')) as TagName
    from question_stats qs
    where qs.Tags is not null
),
tag_rank as (
    select
        te.TagName,
        count(*) as TagQuestionCount,
        sum(qs.ViewCount) as TotalViews,
        avg(cast(qs.QuestionScore as numeric)) as AvgQScore,
        row_number() over (order by count(*) desc, sum(qs.ViewCount) desc) as PopularityRank
    from tag_expanded te
    join question_stats qs on qs.QuestionId = te.QuestionId
    group by te.TagName
),
closed_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as FirstClosedDate,
        max(ph.CreationDate) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonRaw
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
links as (
    select
        pl.PostId as QuestionId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount
    from PostLinks pl
    group by pl.PostId
),
comment_summary as (
    select
        c.PostId as QuestionId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        avg(coalesce(c.Score,0)) as AvgCommentScore,
        max(length(c.Text)) as MaxCommentLen
    from Comments c
    group by c.PostId
),
question_windows as (
    select
        qs.*,
        rank() over (order by qs.ViewCount desc) as RankByViews,
        dense_rank() over (order by qs.QuestionScore desc) as DenseRankByScore,
        percent_rank() over (order by coalesce(qs.ActualAnswerCount,0)) as PctRankByAnswers,
        ntile(10) over (order by qs.CreationDate) as AgeDecile
    from question_stats qs
),
owner_enriched as (
    select
        qw.QuestionId,
        qw.CreationDate,
        qw.QuestionScore,
        qw.ViewCount,
        qw.AnswerCount,
        qw.ActualAnswerCount,
        qw.MaxAnswerScore,
        qw.MinAnswerScore,
        qw.AvgAnswerScore,
        qw.PosAnswerCount,
        qw.NegAnswerCount,
        qw.FirstAnswerDate,
        qw.LastAnswerDate,
        qw.RankByViews,
        qw.DenseRankByScore,
        qw.PctRankByAnswers,
        qw.AgeDecile,
        ua.UserId as OwnerUserId,
        ua.Reputation as OwnerReputation,
        ua.UpVotes as OwnerUpVotes,
        ua.DownVotes as OwnerDownVotes,
        ua.LocationNorm as OwnerLocation,
        ua.TotalBadges as OwnerTotalBadges,
        ua.GoldBadges as OwnerGoldBadges,
        ua.SilverBadges as OwnerSilverBadges,
        ua.BronzeBadges as OwnerBronzeBadges
    from question_windows qw
    left join user_activity ua on ua.UserId = qw.OwnerUserId
),
accepted_enriched as (
    select
        oe.*,
        aa.AcceptedAnswerId,
        aa.AcceptedAnswerScore,
        aa.AcceptedOwnerId,
        ua2.Reputation as AcceptedOwnerReputation,
        ua2.TotalBadges as AcceptedOwnerTotalBadges,
        aa.AcceptedCreationDate
    from owner_enriched oe
    left join accepted_answer aa on aa.QuestionId = oe.QuestionId
    left join user_activity ua2 on ua2.UserId = aa.AcceptedOwnerId
),
final_assembled as (
    select
        ae.QuestionId,
        ae.CreationDate,
        ae.QuestionScore,
        ae.ViewCount,
        ae.AnswerCount,
        ae.ActualAnswerCount,
        coalesce(ae.ActualAnswerCount,0) - coalesce(ae.AnswerCount,0) as AnswerCountDelta,
        ae.MaxAnswerScore,
        ae.MinAnswerScore,
        ae.AvgAnswerScore,
        ae.PosAnswerCount,
        ae.NegAnswerCount,
        ae.FirstAnswerDate,
        ae.LastAnswerDate,
        ae.RankByViews,
        ae.DenseRankByScore,
        ae.PctRankByAnswers,
        ae.AgeDecile,
        ae.OwnerUserId,
        ae.OwnerReputation,
        ae.OwnerUpVotes,
        ae.OwnerDownVotes,
        ae.OwnerLocation,
        ae.OwnerTotalBadges,
        ae.OwnerGoldBadges,
        ae.OwnerSilverBadges,
        ae.OwnerBronzeBadges,
        ae.AcceptedAnswerId,
        ae.AcceptedAnswerScore,
        ae.AcceptedOwnerId,
        ae.AcceptedOwnerReputation,
        ae.AcceptedOwnerTotalBadges,
        ae.AcceptedCreationDate,
        va.UpVotes as VoteUpCount,
        va.DownVotes as VoteDownCount,
        va.Favorites as FavoriteCount,
        va.BountyAmount,
        cs.CommentCount,
        cs.MaxCommentScore,
        cs.AvgCommentScore,
        cs.MaxCommentLen,
        cl.FirstClosedDate,
        cl.LastClosedDate,
        cl.CloseReasonRaw,
        lnk.LinkedCount,
        lnk.DuplicateCount,
        tr.TagName as TopTag,
        tr.TagQuestionCount as TopTagQCount,
        tr.PopularityRank as TopTagRank
    from accepted_enriched ae
    left join vote_agg va on va.PostId = ae.QuestionId
    left join comment_summary cs on cs.QuestionId = ae.QuestionId
    left join closed_events cl on cl.QuestionId = ae.QuestionId
    left join links lnk on lnk.QuestionId = ae.QuestionId
    left join lateral (
        select tr2.*
        from tag_expanded te2
        join tag_rank tr2 on tr2.TagName = te2.TagName
        where te2.QuestionId = ae.QuestionId
        order by tr2.PopularityRank
        limit 1
    ) tr on true
),
quartiles as (
    select
        f.*,
        -- emulate width_bucket: bucket = floor((value - min) / ((max - min)/buckets)) + 1, clamp to [1,buckets]
        case
            when nullif(max(f.ViewCount) over (),0) is null then 1
            else least(greatest(cast(floor( (coalesce(f.ViewCount,0) - 0) * 4.0 / nullif(max(f.ViewCount) over (),0) ) as integer) + 1, 1), 4)
        end as ViewQuartile,
        case
            when (nullif(max(f.QuestionScore) over (),0) is null) then 1
            else least(greatest(cast(floor( (coalesce(f.QuestionScore,0) - min(f.QuestionScore) over ()) * 4.0 / nullif((max(f.QuestionScore) over () - min(f.QuestionScore) over ()),0) ) as integer) + 1, 1), 4)
        end as ScoreQuartile
    from final_assembled f
),
filtered as (
    select *
    from quartiles
    where coalesce(ViewCount,0) >= 0
      and coalesce(QuestionScore,0) >= 0
      and (
            AcceptedAnswerScore is null
         or AcceptedAnswerScore >= 0
         or (AcceptedAnswerScore < 0 and coalesce(VoteUpCount,0) > coalesce(VoteDownCount,0))
      )
      and not exists (
          select 1
          from PostLinks plx
          where plx.PostId = quartiles.QuestionId
            and plx.LinkTypeId = 3
            and plx.RelatedPostId = quartiles.QuestionId
      )
),
ranked_per_owner as (
    select
        f.*,
        row_number() over (
            partition by f.OwnerUserId
            order by coalesce(f.ViewCount,0) desc, coalesce(f.QuestionScore,0) desc, f.CreationDate desc
        ) as rn
    from filtered f
)
select
    f.QuestionId,
    f.CreationDate,
    f.QuestionScore,
    f.ViewCount,
    f.AnswerCount,
    f.ActualAnswerCount,
    f.AnswerCountDelta,
    f.MaxAnswerScore,
    f.MinAnswerScore,
    round(coalesce(f.AvgAnswerScore,0)::numeric, 3) as AvgAnswerScoreRounded,
    f.PosAnswerCount,
    f.NegAnswerCount,
    f.FirstAnswerDate,
    f.LastAnswerDate,
    f.RankByViews,
    f.DenseRankByScore,
    round(coalesce(f.PctRankByAnswers,0)::numeric, 4) as PctRankByAnswers,
    f.AgeDecile,
    f.OwnerUserId,
    f.OwnerReputation,
    f.OwnerUpVotes,
    f.OwnerDownVotes,
    f.OwnerLocation,
    f.OwnerTotalBadges,
    f.OwnerGoldBadges,
    f.OwnerSilverBadges,
    f.OwnerBronzeBadges,
    f.AcceptedAnswerId,
    f.AcceptedAnswerScore,
    f.AcceptedOwnerId,
    f.AcceptedOwnerReputation,
    f.AcceptedOwnerTotalBadges,
    f.AcceptedCreationDate,
    f.VoteUpCount,
    f.VoteDownCount,
    f.FavoriteCount,
    f.BountyAmount,
    f.CommentCount,
    f.MaxCommentScore,
    round(coalesce(f.AvgCommentScore,0)::numeric, 3) as AvgCommentScoreRounded,
    f.MaxCommentLen,
    f.FirstClosedDate,
    f.LastClosedDate,
    f.CloseReasonRaw,
    f.LinkedCount,
    f.DuplicateCount,
    f.TopTag,
    f.TopTagQCount,
    f.TopTagRank,
    f.ViewQuartile,
    f.ScoreQuartile,
    case
        when f.AcceptedAnswerId is not null then 'Accepted'
        when f.ActualAnswerCount > 0 then 'Answered'
        else 'Unanswered'
    end as AnswerStatus,
    case
        when f.ViewCount >= (select percentile_cont(0.99) within group (order by coalesce(ViewCount,0)) from final_assembled) then 'P99+'
        when f.ViewCount >= (select percentile_cont(0.95) within group (order by coalesce(ViewCount,0)) from final_assembled) then 'P95-P99'
        when f.ViewCount >= (select percentile_cont(0.90) within group (order by coalesce(ViewCount,0)) from final_assembled) then 'P90-P95'
        else 'BelowP90'
    end as ViewPopularityBand,
    (coalesce(f.VoteUpCount,0) - coalesce(f.VoteDownCount,0)) as NetVotes,
    case
        when f.OwnerReputation is null then 'AnonymousOrDeleted'
        when f.OwnerReputation >= 100000 then 'Legend'
        when f.OwnerReputation >= 10000 then 'Expert'
        when f.OwnerReputation >= 1000 then 'Seasoned'
        else 'Newbie'
    end as OwnerTier
from ranked_per_owner f
where f.rn <= 5
order by f.ViewCount desc, f.QuestionScore desc, f.CreationDate desc;