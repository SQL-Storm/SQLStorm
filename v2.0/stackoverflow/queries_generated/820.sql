-- {"query": "820.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3321} 
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.Score,
        coalesce(q.ViewCount, 0) as ViewCount,
        q.OwnerUserId,
        q.AcceptedAnswerId,
        q.Title,
        q.Tags,
        q.FavoriteCount,
        q.CommentCount
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '12 months' from Posts where PostTypeId = 1)
), tag_expansion as (
    select
        rq.QuestionId,
        lower(trim(tg)) as tag
    from recent_questions rq
    cross join lateral unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><')) as tg
), tag_rank as (
    select
        te.QuestionId,
        te.tag,
        dense_rank() over (partition by te.QuestionId order by case when te.tag ~ '^(sql|postgres|mysql|sqlite|tsql)$' then 0 else 1 end, te.tag) as tag_rank
    from tag_expansion te
), primary_tag as (
    select QuestionId, tag as PrimaryTag
    from tag_rank
    where tag_rank = 1
), answer_stats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore,
        max(a.CreationDate) as LastAnswerDate
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
), votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
        count(*) filter (where v.VoteTypeId in (8,9)) as BountyEvents
    from Votes v
    group by v.PostId
), dup_links as (
    select
        pl.PostId as DuplicateOf,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    group by pl.PostId
), closures as (
    select
        ph.PostId,
        min(ph.CreationDate) as FirstClosedDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11)) as LastCloseOrReopen,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
        max(
            nullif(
                case
                    when ph.PostHistoryTypeId = 10 then
                        nullif(regexp_replace(ph.Comment, '[^0-9]', '', 'g'), '')
                    else null
                end, ''
            )::int
        ) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
), owners as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.UpVotes as UserUpVotes,
        u.DownVotes as UserDownVotes,
        u.Views as UserViews,
        coalesce(nullif(trim(u.Location),''), 'Unknown') as LocationNorm
    from Users u
), badges_agg as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) filter (where b.TagBased = 1) as TagBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), question_activity as (
    select
        rq.QuestionId,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.OwnerUserId,
        rq.AcceptedAnswerId,
        rq.Title,
        rq.FavoriteCount,
        rq.CommentCount,
        row_number() over (partition by rq.OwnerUserId order by rq.CreationDate desc, rq.Score desc, rq.ViewCount desc) as rn_owner_recent,
        rank() over (order by rq.Score desc, rq.ViewCount desc) as r_overall_score,
        dense_rank() over (order by rq.ViewCount desc) as dr_overall_views
    from recent_questions rq
), accepted_answerers as (
    select
        q.Id as QuestionId,
        aa.OwnerUserId as AcceptedAnswererId,
        aa.Score as AcceptedAnswerScore
    from Posts q
    join Posts aa on aa.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
), comment_agg as (
    select
        c.PostId,
        count(*) as CommentCountAll,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        sum(case when c.Score < 0 then 1 else 0 end) as NegativeComments
    from Comments c
    group by c.PostId
), quality_flags as (
    select
        rq.QuestionId,
        case
            when rq.Score >= 10 and coalesce(vv.UpVotes,0) - coalesce(vv.DownVotes,0) >= 10 and coalesce(asg.AnswerCount,0) >= 2 then 1
            when rq.ViewCount >= 10000 and coalesce(asg.MaxAnswerScore,0) >= 5 then 1
            else 0
        end as IsHighQuality,
        case
            when coalesce(clo.CloseEvents,0) > 0 and coalesce(clo.ReopenEvents,0) = 0 then 1
            else 0
        end as IsClosedAndNotReopened,
        case
            when coalesce(dl.DuplicateCount,0) > 0 then 1 else 0
        end as IsMarkedDuplicate
    from recent_questions rq
    left join votes_agg vv on vv.PostId = rq.QuestionId
    left join answer_stats asg on asg.QuestionId = rq.QuestionId
    left join dup_links dl on dl.DuplicateOf = rq.QuestionId
    left join closures clo on clo.PostId = rq.QuestionId
), user_enrichment as (
    select
        o.UserId,
        o.DisplayName,
        o.Reputation,
        o.UserCreationDate,
        o.UserUpVotes,
        o.UserDownVotes,
        o.UserViews,
        o.LocationNorm,
        coalesce(b.TotalBadges,0) as TotalBadges,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.TagBadges,0) as TagBadges,
        b.LastBadgeDate
    from owners o
    left join badges_agg b on b.UserId = o.UserId
), candidate as (
    select
        qa.QuestionId,
        qa.CreationDate,
        qa.Score,
        qa.ViewCount,
        qa.OwnerUserId,
        ue.DisplayName as OwnerName,
        ue.Reputation as OwnerReputation,
        ue.TotalBadges,
        ue.GoldBadges,
        ue.SilverBadges,
        ue.BronzeBadges,
        ue.TagBadges,
        ue.LocationNorm,
        ue.UserViews,
        ue.UserUpVotes,
        ue.UserDownVotes,
        qa.AcceptedAnswerId,
        aa.AcceptedAnswererId,
        aa.AcceptedAnswerScore,
        pa.PrimaryTag,
        va.UpVotes,
        va.DownVotes,
        va.Favorites,
        va.BountyTotal,
        va.BountyEvents,
        asg.AnswerCount,
        asg.MaxAnswerScore,
        asg.AvgAnswerScore,
        asg.LastAnswerDate,
        cm.CommentCountAll as CommentCountAllPosts,
        cm.LastCommentDate,
        cm.PositiveComments,
        cm.NegativeComments,
        dl.DuplicateCount,
        dl.LinkedCount,
        cl.FirstClosedDate,
        cl.LastCloseOrReopen,
        cl.CloseEvents,
        cl.ReopenEvents,
        cl.LastCloseReasonId,
        qa.Title,
        qa.FavoriteCount as LegacyFavoriteCount,
        qa.CommentCount as LegacyCommentCount,
        qa.rn_owner_recent,
        qa.r_overall_score,
        qa.dr_overall_views,
        qf.IsHighQuality,
        qf.IsClosedAndNotReopened,
        qf.IsMarkedDuplicate
    from question_activity qa
    left join user_enrichment ue on ue.UserId = qa.OwnerUserId
    left join accepted_answerers aa on aa.QuestionId = qa.QuestionId
    left join primary_tag pa on pa.QuestionId = qa.QuestionId
    left join votes_agg va on va.PostId = qa.QuestionId
    left join answer_stats asg on asg.QuestionId = qa.QuestionId
    left join comment_agg cm on cm.PostId = qa.QuestionId
    left join dup_links dl on dl.DuplicateOf = qa.QuestionId
    left join closures cl on cl.PostId = qa.QuestionId
    left join quality_flags qf on qf.QuestionId = qa.QuestionId
), scoring as (
    select
        c.*,
        coalesce(va_ratio, 0) as va_ratio,
        coalesce(ans_quality, 0) as ans_quality,
        coalesce(discussion_signal, 0) as discussion_signal,
        coalesce(user_trust, 0) as user_trust,
        coalesce(bounty_signal, 0) as bounty_signal,
        coalesce(penalty, 0) as penalty
    from (
        select
            c.*,
            case
                when coalesce(c.DownVotes,0) = 0 and coalesce(c.UpVotes,0) > 0 then least(c.UpVotes, 100)
                else greatest((coalesce(c.UpVotes,0)::numeric / nullif(c.DownVotes,0)), 0)
            end as va_ratio,
            (coalesce(c.AvgAnswerScore,0) * 0.6 + coalesce(c.MaxAnswerScore,0) * 0.4) as ans_quality,
            (coalesce(c.CommentCountAllPosts,0) * 0.1 + coalesce(c.PositiveComments,0) * 0.2 - coalesce(c.NegativeComments,0) * 0.3) as discussion_signal,
            (coalesce(c.OwnerReputation,0) * 0.002 + coalesce(c.GoldBadges,0) * 1.5 + coalesce(c.SilverBadges,0) * 0.6 + coalesce(c.BronzeBadges,0) * 0.2) as user_trust,
            (coalesce(c.BountyTotal,0) * 0.05 + coalesce(c.BountyEvents,0) * 1.0) as bounty_signal,
            (
                case when c.IsClosedAndNotReopened = 1 then 15 else 0 end +
                case when c.IsMarkedDuplicate = 1 then 10 else 0 end +
                case when c.ViewCount < 50 and c.Score <= 0 then 5 else 0 end
            ) as penalty
        from candidate c
    ) s
), ranked as (
    select
        s.*,
        (
            0.25 * greatest(0, s.Score) +
            0.20 * ln(1 + greatest(0, s.ViewCount)) +
            0.15 * s.va_ratio +
            0.15 * s.ans_quality +
            0.10 * s.discussion_signal +
            0.10 * s.user_trust +
            0.05 * s.bounty_signal -
            0.15 * s.penalty
        ) as composite_score,
        row_number() over (order by
            (
                0.25 * greatest(0, s.Score) +
                0.20 * ln(1 + greatest(0, s.ViewCount)) +
                0.15 * s.va_ratio +
                0.15 * s.ans_quality +
                0.10 * s.discussion_signal +
                0.10 * s.user_trust +
                0.05 * s.bounty_signal -
                0.15 * s.penalty
            ) desc,
            s.r_overall_score,
            s.dr_overall_views,
            s.CreationDate desc
        ) as rn_global
    from scoring s
), topn as (
    select *
    from ranked
    where rn_global <= 200
), outliers as (
    select
        t.QuestionId,
        avg(t.composite_score) over () as avg_score,
        stddev_pop(t.composite_score) over () as stddev_score,
        case when t.composite_score > avg(t.composite_score) over () + 2 * stddev_pop(t.composite_score) over ()
             then 1 else 0 end as is_high_outlier
    from topn t
), final as (
    select
        t.QuestionId,
        t.Title,
        coalesce(t.PrimaryTag, '(none)') as PrimaryTag,
        t.OwnerUserId,
        nullif(trim(t.OwnerName), '') as OwnerName,
        t.OwnerReputation,
        t.TotalBadges,
        t.Score,
        t.ViewCount,
        t.UpVotes,
        t.DownVotes,
        t.AnswerCount,
        t.AvgAnswerScore,
        t.MaxAnswerScore,
        t.AcceptedAnswerId,
        t.AcceptedAnswererId,
        t.AcceptedAnswerScore,
        t.BountyTotal,
        t.BountyEvents,
        t.DuplicateCount,
        t.CloseEvents,
        t.ReopenEvents,
        t.LastCloseReasonId,
        t.IsHighQuality,
        t.IsClosedAndNotReopened,
        t.IsMarkedDuplicate,
        t.CreationDate,
        t.LastAnswerDate,
        t.LastCloseOrReopen,
        t.LastCommentDate,
        t.Favorites,
        t.LegacyFavoriteCount,
        t.CommentCountAllPosts,
        t.LegacyCommentCount,
        t.LocationNorm,
        t.UserViews,
        t.UserUpVotes,
        t.UserDownVotes,
        t.r_overall_score,
        t.dr_overall_views,
        t.composite_score,
        o.is_high_outlier
    from topn t
    left join outliers o on o.QuestionId = t.QuestionId
)
select *
from final
order by composite_score desc, Score desc, ViewCount desc, CreationDate desc;