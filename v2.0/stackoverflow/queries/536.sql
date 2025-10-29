-- {"query": "536.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2798}
with
q_posts as (
    select
        p.Id as QuestionId,
        p.OwnerUserId as QuestionOwnerId,
        p.CreationDate as QuestionCreated,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as tag_array,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
),
a_posts as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.CreationDate as AnswerCreated,
        a.Score as AnswerScore
    from Posts a
    where a.PostTypeId = 2
),
q_activity as (
    select
        ph.PostId as QuestionId,
        max(case when ph.PostHistoryTypeId in (10,35) then ph.CreationDate end) as LastClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenDate,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35)) as ModEventCount
    from PostHistory ph
    join Posts qp on qp.Id = ph.PostId and qp.PostTypeId = 1
    group by ph.PostId
),
c_counts as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as CommentScoreSum,
        avg(c.Score) as AvgCommentScore,
        count(*) filter (where c.UserId is null) as AnonymousComments
    from Comments c
    group by c.PostId
),
v_votes as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        max(case when v.VoteTypeId in (8,9) then v.BountyAmount end) as MaxBounty
    from Votes v
    group by v.PostId
),
u_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes as UserUpVotes,
        u.DownVotes as UserDownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreated,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as CleanLocation,
        count(b.Id) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, coalesce(nullif(trim(u.Location), ''), 'Unknown')
),
dupes as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateOfCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        min(pl.CreationDate) as FirstLinkDate
    from PostLinks pl
    group by pl.PostId
),
q_ans_stats as (
    select
        ap.QuestionId,
        count(*) as TotalAnswers,
        count(*) filter (where ap.AnswerScore > 0) as PositiveAnswers,
        avg(CAST(ap.AnswerScore AS numeric)) as AvgAnswerScore,
        min(ap.AnswerCreated) as FirstAnswerDate,
        max(ap.AnswerCreated) as LastAnswerDate
    from a_posts ap
    group by ap.QuestionId
),
tag_explode as (
    select
        qp.QuestionId,
        unnest(qp.tag_array) as tag_name
    from q_posts qp
),
tag_rank as (
    select
        te.QuestionId,
        te.tag_name,
        t.Count as GlobalTagCount,
        row_number() over (partition by te.QuestionId order by coalesce(t.Count,0) desc, te.tag_name) as tag_pop_rank
    from tag_explode te
    left join Tags t on lower(t.TagName) = lower(te.tag_name)
),
best_tag as (
    select QuestionId, tag_name as DominantTag, GlobalTagCount
    from tag_rank
    where tag_pop_rank = 1
),
accepted_delta as (
    select
        q.Id as QuestionId,
        q.CreationDate as QuestionCreated,
        a.CreationDate as AcceptedCreated,
        extract(epoch from (a.CreationDate - q.CreationDate)) as SecondsToAccept
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
slow_accept as (
    select
        ad.QuestionId,
        ad.SecondsToAccept,
        ntile(4) over (order by ad.SecondsToAccept nulls last) as AcceptSpeedQuartile
    from accepted_delta ad
),
owner_mix as (
    select
        qp.QuestionId,
        qp.QuestionOwnerId,
        ap.AnswerOwnerId,
        case
            when qp.QuestionOwnerId is null then 'anon'
            when ap.AnswerOwnerId is null then 'anon-ans'
            when qp.QuestionOwnerId = ap.AnswerOwnerId then 'self-answered'
            else 'other-answered'
        end as AnswerOwnership
    from q_posts qp
    left join a_posts ap on ap.QuestionId = qp.QuestionId
),
owner_agg as (
    select
        QuestionId,
        count(*) as AnswersSeen,
        count(*) filter (where AnswerOwnership = 'self-answered') as SelfAnswers,
        count(distinct AnswerOwnerId) as DistinctAnswerers
    from owner_mix
    group by QuestionId
),
hotness as (
    select
        qp.QuestionId,
        qp.QuestionScore,
        qp.ViewCount,
        coalesce(vv.UpVotes,0) - coalesce(vv.DownVotes,0) as NetVotes,
        coalesce(vv.Favorites,0) as Favorites,
        coalesce(vv.MaxBounty,0) as MaxBounty,
        0.6*log(1+coalesce(qp.ViewCount,0))
        + 0.3*coalesce(qp.QuestionScore,0)
        + 0.1*(coalesce(vv.UpVotes,0) - coalesce(vv.DownVotes,0))
        + case when coalesce(vv.MaxBounty,0) > 0 then 5 else 0 end
        as HotScore
    from q_posts qp
    left join v_votes vv on vv.PostId = qp.QuestionId
),
recent_questions as (
    select
        qp.*,
        qa.EditCount,
        qa.ModEventCount,
        qa.LastClosedDate,
        qa.LastReopenDate,
        cc.CommentCount,
        cc.CommentScoreSum,
        vs.UpVotes,
        vs.DownVotes,
        vs.Favorites,
        vs.MaxBounty,
        qa2.TotalAnswers,
        qa2.PositiveAnswers,
        qa2.AvgAnswerScore,
        qa2.FirstAnswerDate,
        qa2.LastAnswerDate
    from q_posts qp
    left join q_activity qa on qa.QuestionId = qp.QuestionId
    left join c_counts cc on cc.PostId = qp.QuestionId
    left join v_votes vs on vs.PostId = qp.QuestionId
    left join q_ans_stats qa2 on qa2.QuestionId = qp.QuestionId
),
user_enriched as (
    select
        rq.*,
        qu.DisplayName as QuestionOwnerName,
        qs.Reputation as QuestionOwnerRep,
        qs.CleanLocation as QuestionOwnerLoc,
        qs.BadgeCount as QuestionOwnerBadges,
        qs.GoldBadges as QGold,
        qs.SilverBadges as QSilver,
        qs.BronzeBadges as QBronze
    from recent_questions rq
    left join Users qu on qu.Id = rq.QuestionOwnerId
    left join u_stats qs on qs.UserId = rq.QuestionOwnerId
),
final_rank as (
    select
        ue.*,
        bt.DominantTag,
        bt.GlobalTagCount as DominantTagGlobalCount,
        sa.SecondsToAccept,
        sa.AcceptSpeedQuartile,
        oa.AnswersSeen,
        oa.SelfAnswers,
        oa.DistinctAnswerers,
        h.HotScore,
        rank() over (
            partition by coalesce(bt.DominantTag, '__none__')
            order by h.HotScore desc nulls last, ue.ViewCount desc nulls last, ue.QuestionCreated desc
        ) as RankWithinTag,
        row_number() over (order by h.HotScore desc nulls last, ue.ViewCount desc nulls last, ue.QuestionCreated desc) as GlobalRowNum,
        sum(coalesce(ue.ViewCount,0)) over (order by ue.QuestionCreated rows between unbounded preceding and current row) as RunningViewsByTime,
        count(*) over () as TotalQuestions
    from user_enriched ue
    left join best_tag bt on bt.QuestionId = ue.QuestionId
    left join slow_accept sa on sa.QuestionId = ue.QuestionId
    left join owner_agg oa on oa.QuestionId = ue.QuestionId
    left join hotness h on h.QuestionId = ue.QuestionId
),
hot_cutoff as (
    select percentile_disc(0.1) within group (order by HotScore) as HotScoreP10
    from final_rank
),
filtered as (
    select fr.*
    from final_rank fr
    left join hot_cutoff hc on true
    where
        (coalesce(fr.TotalAnswers,0) >= 1 or fr.EditCount > 0 or fr.CommentCount > 0)
        and (
            fr.LastClosedDate is null
            or (fr.LastReopenDate is not null and fr.LastReopenDate > fr.LastClosedDate)
        )
        and (
            fr.DominantTag is null
            or fr.DominantTag NOT LIKE '%discussion%' -- approximate regex portability
        )
        and (
            fr.HotScore is null
            or fr.HotScore > hc.HotScoreP10
        )
)
select
    f.QuestionId,
    coalesce(f.Title, '(no title)') as Title,
    f.QuestionCreated,
    f.QuestionOwnerId,
    coalesce(f.QuestionOwnerName, '(community)') as QuestionOwnerName,
    f.QuestionOwnerRep,
    f.QuestionOwnerLoc,
    f.QGold || '/' || f.QSilver || '/' || f.QBronze as OwnerBadgeBreakdown,
    f.ViewCount,
    f.QuestionScore,
    coalesce(f.UpVotes,0) as UpVotes,
    coalesce(f.DownVotes,0) as DownVotes,
    coalesce(f.Favorites,0) as Favorites,
    coalesce(f.MaxBounty,0) as MaxBounty,
    coalesce(f.CommentCount,0) as CommentCount,
    coalesce(f.CommentScoreSum,0) as CommentScoreSum,
    coalesce(f.TotalAnswers,0) as TotalAnswers,
    coalesce(f.PositiveAnswers,0) as PositiveAnswers,
    round(CAST(coalesce(f.AvgAnswerScore,0) AS numeric), 2) as AvgAnswerScore,
    f.FirstAnswerDate,
    f.LastAnswerDate,
    f.DominantTag,
    f.DominantTagGlobalCount,
    f.SecondsToAccept,
    f.AcceptSpeedQuartile,
    f.AnswersSeen,
    f.SelfAnswers,
    f.DistinctAnswerers,
    f.EditCount,
    f.ModEventCount,
    f.LastClosedDate,
    f.LastReopenDate,
    round(CAST(coalesce(f.HotScore,0) AS numeric), 2) as HotScore,
    f.RankWithinTag,
    f.GlobalRowNum,
    f.RunningViewsByTime,
    f.TotalQuestions,
    case
        when f.SecondsToAccept is null then 'unaccepted'
        when f.SecondsToAccept <= 3600 then 'fast-accept'
        when f.SecondsToAccept <= 86400 then 'same-day'
        when f.SecondsToAccept <= 604800 then 'within-week'
        else 'slow-accept'
    end as AcceptBucket
from filtered f
where
    (
        f.QuestionOwnerRep is null
        or f.QuestionOwnerRep >= (
            select percentile_disc(0.75) within group (order by Reputation)
            from Users
        )
    )
    and (
        f.ViewCount is null
        or f.ViewCount > (
            select avg(ViewCount)
            from Posts
            where PostTypeId = 1 and ViewCount is not null
        )
    )
order by f.HotScore desc nulls last, f.ViewCount desc nulls last, f.QuestionCreated desc
limit 200;