-- {"query": "794.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2942} 
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        coalesce(q.Score, 0) as Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        q.ClosedDate,
        case when q.ClosedDate is not null then 1 else 0 end as IsClosed
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select a.Id as AnswerId, a.ParentId as QuestionId, a.OwnerUserId as AnswererId, a.Score as AnswerScore, a.CreationDate as AnswerDate
    from Posts a
    where a.PostTypeId = 2
),
question_stats as (
    select
        rq.QuestionId,
        rq.OwnerUserId,
        rq.CreationDate,
        rq.Score,
        rq.ViewCount,
        rq.Title,
        rq.Tags,
        rq.AcceptedAnswerId,
        rq.IsClosed,
        count(a.AnswerId) as AnswerCount,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerDate) as FirstAnswerDate,
        max(a.AnswerDate) as LastAnswerDate
    from recent_questions rq
    left join answers a on a.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.OwnerUserId, rq.CreationDate, rq.Score, rq.ViewCount, rq.Title, rq.Tags, rq.AcceptedAnswerId, rq.IsClosed
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
    from Votes v
    group by v.PostId
),
tag_expanded as (
    select
        qs.QuestionId,
        unnest(string_to_array(substring(qs.Tags, 2, length(qs.Tags)-2), '><')) as Tag
    from question_stats qs
    where qs.Tags is not null and length(qs.Tags) > 2
),
top_tags as (
    select
        te.Tag,
        count(*) as TagFreq,
        dense_rank() over (order by count(*) desc, Tag) as TagRank
    from tag_expanded te
    group by te.Tag
),
user_quality as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(avg(case when b.TagBased = 1 then 1.0 else 0.0 end), 0.0) as TagBadgeRatio
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views
),
dup_links as (
    select
        pl.PostId as DuplicateId,
        pl.RelatedPostId as CanonicalId,
        min(pl.CreationDate) as FirstDupLinkDate,
        count(*) as DupLinkCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
closure as (
    select
        ph.PostId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
        count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
        count(*) filter (where ph.PostHistoryTypeId in (12,13)) as DeletionUndelEvents,
        max(case
                when ph.PostHistoryTypeId = 10
                     and coalesce(nullif(trim(ph.Comment), ''), '0') ~ '^[0-9]+$'
                then cast(ph.Comment as int)
                else null
            end) as AnyCloseReasonId
    from PostHistory ph
    group by ph.PostId
),
engagement as (
    select
        c.PostId,
        count(*) as CommentCount,
        coalesce(sum(case when c.Score > 0 then 1 else 0 end),0) as PosComments,
        coalesce(sum(case when c.Score < 0 then 1 else 0 end),0) as NegComments,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
question_enriched as (
    select
        qs.*,
        va.UpVotes,
        va.DownVotes,
        va.Favorites,
        va.BountyTotal,
        co.CommentCount,
        co.PosComments,
        co.NegComments,
        co.LastCommentDate,
        cl.FirstCloseDate,
        cl.LastReopenDate,
        cl.CloseEvents,
        cl.ReopenEvents,
        cl.DeletionUndelEvents,
        cl.AnyCloseReasonId,
        dl.CanonicalId as DuplicateOf,
        dl.FirstDupLinkDate,
        dl.DupLinkCount
    from question_stats qs
    left join vote_agg va on va.PostId = qs.QuestionId
    left join engagement co on co.PostId = qs.QuestionId
    left join closure cl on cl.PostId = qs.QuestionId
    left join dup_links dl on dl.DuplicateId = qs.QuestionId
),
accepted_answerers as (
    select
        qe.QuestionId,
        a.AnswererId as AcceptedAnswererId
    from question_enriched qe
    join answers a on a.AnswerId = qe.AcceptedAnswerId
),
owner_vs_accept as (
    select
        qe.QuestionId,
        qe.OwnerUserId,
        aa.AcceptedAnswererId,
        case when aa.AcceptedAnswererId is not null and aa.AcceptedAnswererId = qe.OwnerUserId then 1 else 0 end as SelfAccepted
    from question_enriched qe
    left join accepted_answerers aa on aa.QuestionId = qe.QuestionId
),
owner_metrics as (
    select
        ov.QuestionId,
        uq.Reputation as OwnerRep,
        (uq.UpVotes - uq.DownVotes) as OwnerVoteDelta,
        uq.GoldBadges,
        uq.SilverBadges,
        uq.BronzeBadges,
        uq.TagBadgeRatio
    from owner_vs_accept ov
    left join user_quality uq on uq.UserId = ov.OwnerUserId
),
accept_metrics as (
    select
        ov.QuestionId,
        uq.Reputation as AccUserRep,
        uq.GoldBadges as AccGoldBadges
    from owner_vs_accept ov
    left join user_quality uq on uq.UserId = ov.AcceptedAnswererId
),
ranked_questions as (
    select
        qe.*,
        ov.SelfAccepted,
        om.OwnerRep,
        om.OwnerVoteDelta,
        om.GoldBadges,
        om.SilverBadges,
        om.BronzeBadges,
        om.TagBadgeRatio,
        am.AccUserRep,
        am.AccGoldBadges,
        tt.Tag as AnyTopTag,
        tt.TagRank,
        row_number() over (order by
            coalesce(qe.UpVotes,0) - coalesce(qe.DownVotes,0) desc,
            coalesce(qe.ViewCount,0) desc,
            qe.CreationDate desc
        ) as GlobalRowNum,
        dense_rank() over (partition by coalesce(tt.TagRank, 999999) order by coalesce(qe.Favorites,0) desc nulls last, qe.CreationDate desc) as RankWithinTopTag,
        percentile_disc(0.5) within group (order by coalesce(qe.ViewCount,0)) over () as MedianViewCount
    from question_enriched qe
    left join owner_vs_accept ov on ov.QuestionId = qe.QuestionId
    left join owner_metrics om on om.QuestionId = qe.QuestionId
    left join accept_metrics am on am.QuestionId = qe.QuestionId
    left join lateral (
        select tt.Tag, tt.TagRank
        from top_tags tt
        join tag_expanded te on te.Tag = tt.Tag and te.QuestionId = qe.QuestionId
        where tt.TagRank <= 50
        order by tt.TagRank, tt.Tag
        limit 1
    ) tt on true
),
anomaly as (
    select
        rq.*,
        case
            when rq.AnswerCount = 0 and coalesce(rq.UpVotes,0) >= 10 and rq.IsClosed = 0 then 'high-vote-unanswered'
            when rq.AnswerCount >= 5 and coalesce(rq.UpVotes,0) <= 0 then 'many-answers-low-votes'
            when rq.IsClosed = 1 and rq.ReopenEvents > 0 then 'closed-then-reopened'
            when rq.DuplicateOf is not null and rq.AcceptedAnswerId is not null then 'dup-with-accepted'
            else null
        end as AnomalyFlag,
        case when coalesce(rq.ViewCount,0) > 0
             then round( (coalesce(rq.UpVotes,0)::numeric - coalesce(rq.DownVotes,0)::numeric) / nullif(rq.ViewCount::numeric,0), 6)
             else null end as NetVotesPerView,
        case when rq.FirstAnswerDate is not null
             then extract(epoch from (rq.FirstAnswerDate - rq.CreationDate)) / 60.0
             else null end as MinutesToFirstAnswer
    from ranked_questions rq
)
select
    a.QuestionId,
    coalesce(u.DisplayName, 'anonymous') as OwnerDisplayName,
    a.Title,
    a.AnyTopTag,
    a.TagRank,
    a.Score,
    a.UpVotes,
    a.DownVotes,
    a.Favorites,
    a.ViewCount,
    a.AnswerCount,
    a.MaxAnswerScore,
    a.NetVotesPerView,
    a.MinutesToFirstAnswer,
    a.IsClosed,
    a.FirstCloseDate,
    a.LastReopenDate,
    a.CloseEvents,
    a.ReopenEvents,
    a.DeletionUndelEvents,
    a.AnyCloseReasonId,
    a.DuplicateOf,
    a.SelfAccepted,
    a.OwnerRep,
    a.OwnerVoteDelta,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    a.TagBadgeRatio,
    a.AccUserRep,
    a.AccGoldBadges,
    a.MedianViewCount,
    a.GlobalRowNum,
    a.RankWithinTopTag,
    coalesce(a.AnomalyFlag, case when a.TagRank is null then 'no-top-tag' else null end) as AnomalyFlag,
    -- complicated predicate-based label
    case
        when (a.UpVotes is null and a.DownVotes is null) or (coalesce(a.UpVotes,0)+coalesce(a.DownVotes,0) = 0) then 'no-votes'
        when coalesce(a.UpVotes,0) >= 50 and coalesce(a.ViewCount,0) >= 10000 then 'highly-engaged'
        when a.BountyTotal > 0 then 'bountied'
        when a.AcceptedAnswerId is not null then 'accepted'
        else 'normal'
    end as EngagementLabel,
    -- string expressions
    trim(both ' ' from coalesce(a.Title, '')) || ' [' || coalesce(a.AnyTopTag, 'misc') || ']' as DecoratedTitle,
    -- correlated subquery example: top commenter name
    (
        select coalesce(max(c.UserDisplayName), 'n/a')
        from Comments c
        where c.PostId = a.QuestionId
        and c.Score = (
            select max(c2.Score) from Comments c2 where c2.PostId = a.QuestionId
        )
    ) as TopCommenter,
    -- set-operator based count: unique voters
    (
        select count(*) from (
            select v.UserId from Votes v where v.PostId = a.QuestionId and v.UserId is not null
            union
            select c.UserId from Comments c where c.PostId = a.QuestionId and c.UserId is not null
        ) uv
    ) as DistinctParticipants
from anomaly a
left join Users u on u.Id = a.OwnerUserId
where
    -- complex filter combining nulls and expressions
    coalesce(a.ViewCount, 0) >= 0
    and (a.TagRank is null or a.TagRank <= 50)
    and (
        a.AnomalyFlag is not null
        or (a.NetVotesPerView is not null and a.NetVotesPerView > 0.0005)
        or (a.MedianViewCount is not null and a.ViewCount > a.MedianViewCount)
    )
order by
    coalesce(a.TagRank, 999999),
    a.RankWithinTopTag,
    a.GlobalRowNum
limit 500;