-- {"query": "610.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3098} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as TagArray
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
question_stats as (
    select
        rq.QuestionId,
        rq.Title,
        rq.OwnerUserId,
        rq.CreationDate,
        rq.Score as QuestionScore,
        rq.ViewCount,
        rq.AnswerCount,
        rq.TagArray,
        count(a.AnswerId) as ActualAnswerCount,
        avg(a.AnswerScore) as AvgAnswerScore,
        min(a.AnswerCreationDate) as FirstAnswerAt,
        max(a.AnswerCreationDate) as LastAnswerAt
    from recent_questions rq
    left join answers a on a.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.Title, rq.OwnerUserId, rq.CreationDate, rq.Score, rq.ViewCount, rq.AnswerCount, rq.TagArray
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreated,
        u.LastAccessDate as LastSeen,
        u.Location,
        u.UpVotes,
        u.DownVotes,
        coalesce(badges_gold,0) as BadgesGold,
        coalesce(badges_silver,0) as BadgesSilver,
        coalesce(badges_bronze,0) as BadgesBronze
    from Users u
    left join lateral (
        select
            sum(case when b.Class = 1 then 1 else 0 end) as badges_gold,
            sum(case when b.Class = 2 then 1 else 0 end) as badges_silver,
            sum(case when b.Class = 3 then 1 else 0 end) as badges_bronze
        from Badges b
        where b.UserId = u.Id
    ) b on true
),
question_votes as (
    select
        v.PostId as QuestionId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyClosed
    from Votes v
    group by v.PostId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        max(pl.CreationDate) as LastLinkAt
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedAt,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastClosedAt,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as FirstReopenedAt,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedAt,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
        max(
            nullif(trim(both from ph.Comment), '')
        ) filter (where ph.PostHistoryTypeId = 10) as LastCloseReasonIdText
    from PostHistory ph
    group by ph.PostId
),
tag_expansion as (
    select
        qs.QuestionId,
        unnest(qs.TagArray) as TagName
    from question_stats qs
),
tag_meta as (
    select
        te.QuestionId,
        te.TagName,
        t.Count as GlobalTagCount,
        t.IsModeratorOnly,
        t.IsRequired
    from tag_expansion te
    left join Tags t on lower(t.TagName) = lower(te.TagName)
),
question_tag_rank as (
    select
        tm.QuestionId,
        tm.TagName,
        tm.GlobalTagCount,
        dense_rank() over (partition by tm.QuestionId order by tm.GlobalTagCount desc nulls last, tm.TagName) as TagPopularityRank
    from tag_meta tm
),
question_quality as (
    select
        qs.QuestionId,
        qs.Title,
        qs.OwnerUserId,
        qs.CreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        qs.AnswerCount,
        coalesce(qv.UpVotes,0) as UpVotes,
        coalesce(qv.DownVotes,0) as DownVotes,
        coalesce(qv.Favorites,0) as Favorites,
        coalesce(qv.BountyStarted,0) as BountyStarted,
        coalesce(qv.BountyClosed,0) as BountyClosed,
        coalesce(dl.DuplicateCount,0) as DuplicateCount,
        coalesce(dl.LinkedCount,0) as LinkedCount,
        dl.LastLinkAt,
        ce.FirstClosedAt,
        ce.LastClosedAt,
        ce.FirstReopenedAt,
        ce.LastReopenedAt,
        ce.CloseEvents,
        ce.ReopenEvents,
        qs.FirstAnswerAt,
        qs.LastAnswerAt,
        qs.ActualAnswerCount,
        -- composite quality score mixing engagement, vote balance, and recency
        (
            (qs.QuestionScore * 2)
            + (coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0))
            + least(coalesce(qv.Favorites,0), 25)
            + case when qs.ViewCount is null then 0 else ln(greatest(qs.ViewCount,1)) end
            - (coalesce(dl.DuplicateCount,0) * 3)
            - (case when ce.LastClosedAt is not null then 5 else 0 end)
            + (case when qs.FirstAnswerAt is not null then 2 else 0 end)
        ) as QualityScoreRaw
    from question_stats qs
    left join question_votes qv on qv.QuestionId = qs.QuestionId
    left join duplicate_links dl on dl.QuestionId = qs.QuestionId
    left join close_events ce on ce.QuestionId = qs.QuestionId
),
normalized as (
    select
        qq.*,
        -- z-score like normalization using window stats
        (QualityScoreRaw - avg(QualityScoreRaw) over ()) / nullif(stddev_pop(QualityScoreRaw) over (), 0) as QualityScoreZ,
        ntile(10) over (order by QualityScoreRaw desc nulls last) as QualityDecile,
        row_number() over (order by QualityScoreRaw desc nulls last, QuestionId) as QualityRank
    from question_quality qq
),
owner_enriched as (
    select
        n.*,
        ua.DisplayName as OwnerName,
        ua.Reputation as OwnerReputation,
        ua.UpVotes as OwnerUpVotes,
        ua.DownVotes as OwnerDownVotes,
        ua.BadgesGold,
        ua.BadgesSilver,
        ua.BadgesBronze,
        (coalesce(ua.BadgesGold,0)*5 + coalesce(ua.BadgesSilver,0)*3 + coalesce(ua.BadgesBronze,0)*1) as BadgeScore
    from normalized n
    left join user_activity ua on ua.UserId = n.OwnerUserId
),
title_signals as (
    select
        oe.QuestionId,
        oe.Title,
        length(coalesce(oe.Title,'')) as TitleLen,
        (regexp_matches(coalesce(oe.Title,''), '[A-Z]{2,}')) is not null as HasAcronym,
        (position('how ' in lower(coalesce(oe.Title,''))) > 0) as IsQuestionHow,
        (position('why ' in lower(coalesce(oe.Title,''))) > 0) as IsQuestionWhy,
        (substring(lower(coalesce(oe.Title,'')) from '(\?|\!|\.)$') is not null) as EndsWithPunc
    from owner_enriched oe
),
tag_agg as (
    select
        qtr.QuestionId,
        array_agg(qtr.TagName order by qtr.TagPopularityRank, qtr.TagName) as TopTagsByPopularity,
        min(qtr.TagPopularityRank) as BestTagRank,
        count(*) as TagCount
    from question_tag_rank qtr
    where qtr.TagPopularityRank <= 3
    group by qtr.QuestionId
),
final_scored as (
    select
        oe.*,
        ts.TitleLen,
        ts.HasAcronym::int as HasAcronymInt,
        ts.IsQuestionHow::int as IsHowInt,
        ts.IsQuestionWhy::int as IsWhyInt,
        ts.EndsWithPunc::int as EndsWithPuncInt,
        ta.TopTagsByPopularity,
        ta.BestTagRank,
        ta.TagCount,
        -- final blended score with owner and title/tag heuristics
        (
            coalesce(oe.QualityScoreZ, 0)
            + least(coalesce(oe.BadgeScore,0)/10.0, 5)
            + case when coalesce(oe.OwnerReputation,0) > 10000 then 0.5 else 0 end
            + case when coalesce(ta.TagCount,0) >= 3 then 0.2 else 0 end
            + (coalesce(ts.IsHowInt,0) + coalesce(ts.IsWhyInt,0)) * 0.1
            - coalesce(ts.HasAcronymInt,0) * 0.05
        ) as FinalScore
    from owner_enriched oe
    left join title_signals ts on ts.QuestionId = oe.QuestionId
    left join tag_agg ta on ta.QuestionId = oe.QuestionId
),
best_answer as (
    select
        p.ParentId as QuestionId,
        p.Id as AnswerId,
        p.Score as AnswerScore,
        p.OwnerUserId as AnswerOwnerId,
        row_number() over (partition by p.ParentId order by p.Score desc nulls last, p.CreationDate asc, p.Id asc) as rn
    from Posts p
    where p.PostTypeId = 2
),
accepted_flags as (
    select
        q.Id as QuestionId,
        case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer
    from Posts q
    where q.PostTypeId = 1
),
topn as (
    select
        fs.*,
        af.HasAcceptedAnswer,
        ba.AnswerId as TopAnswerId,
        ba.AnswerScore as TopAnswerScore,
        ba.AnswerOwnerId as TopAnswerOwnerId
    from final_scored fs
    left join accepted_flags af on af.QuestionId = fs.QuestionId
    left join best_answer ba on ba.QuestionId = fs.QuestionId and ba.rn = 1
),
user_ranks as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        rank() over (order by ua.Reputation desc, ua.UserId) as ReputationRank,
        percent_rank() over (order by ua.Reputation) as ReputationPct,
        cume_dist() over (order by ua.Reputation desc) as ReputationCume
    from user_activity ua
),
final_output as (
    select
        t.QuestionId,
        t.Title,
        t.OwnerUserId,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        ur.ReputationRank as OwnerReputationRank,
        t.QualityRank,
        t.QualityDecile,
        round(t.FinalScore::numeric, 4) as FinalScore,
        t.QuestionScore,
        t.UpVotes,
        t.DownVotes,
        t.Favorites,
        t.ViewCount,
        t.AnswerCount as ReportedAnswerCount,
        t.ActualAnswerCount,
        t.HasAcceptedAnswer,
        t.TopAnswerId,
        t.TopAnswerScore,
        t.TopAnswerOwnerId,
        t.DuplicateCount,
        t.LinkedCount,
        t.CloseEvents,
        t.ReopenEvents,
        t.FirstClosedAt,
        t.LastClosedAt,
        t.FirstReopenedAt,
        t.LastReopenedAt,
        t.FirstAnswerAt,
        t.LastAnswerAt,
        t.TopTagsByPopularity,
        t.BadgesGold,
        t.BadgesSilver,
        t.BadgesBronze
    from topn t
    left join Users u on u.Id = t.OwnerUserId
    left join user_ranks ur on ur.UserId = t.OwnerUserId
)
select *
from final_output
where
    -- complex predicate to exercise optimizer
    (
        (QualityDecile <= 3 and (HasAcceptedAnswer = 0 or TopAnswerScore is null or TopAnswerScore < 1))
        or
        (QualityDecile between 4 and 7 and (Favorites >= 5 or ViewCount >= 1000))
        or
        (QualityDecile >= 8 and DuplicateCount = 0 and coalesce(CloseEvents,0) = 0)
    )
    and coalesce(OwnerReputation, 0) >= 0
    and (TopTagsByPopularity is null or array_length(TopTagsByPopularity, 1) >= 0)
order by FinalScore desc nulls last, QualityRank asc
limit 200;