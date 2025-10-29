with recent_q as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        coalesce(nullif(trim(p.Title), ''), '(no title)') as SafeTitle
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
answer_stats as (
    select
        q.QuestionId,
        count(a.Id) filter (where a.PostTypeId = 2) as AnswerCount,
        max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
        avg(a.Score) filter (where a.PostTypeId = 2) as AvgAnswerScore,
        max(a.CreationDate) filter (where a.PostTypeId = 2) as LastAnswerDate
    from recent_q q
    left join Posts a
      on a.ParentId = q.QuestionId
    group by q.QuestionId
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        count(*) as TotalVotes,
        sum(coalesce(v.BountyAmount,0)) filter (where v.VoteTypeId in (8,9)) as BountyTotal
    from Votes v
    group by v.PostId
),
comment_activity as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments
    from Comments c
    group by c.PostId
),
tag_expansion as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as TagName
    from recent_q q
    where q.Tags is not null and q.Tags like '<%>'
),
tag_rank as (
    select
        te.QuestionId,
        te.TagName,
        t.Count as GlobalTagCount,
        dense_rank() over (partition by te.QuestionId order by t.Count desc nulls last, te.TagName) as TagPopularityRank
    from tag_expansion te
    left join Tags t
      on lower(t.TagName) = lower(te.TagName)
),
owner_profile as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.DisplayName,
        u.Location,
        u.UpVotes as GivenUpVotes,
        u.DownVotes as GivenDownVotes,
        u.Views as ProfileViews
    from Users u
),
badge_rollup as (
    select
        b.UserId,
        count(*) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
closure_info as (
    select
        ph.PostId,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) end) as LastCloseReasonId,
        bool_or(ph.PostHistoryTypeId = 19) as WasProtected
    from PostHistory ph
    where ph.PostId is not null
    group by ph.PostId
),
linkage as (
    select
        pl.PostId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCount,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCount,
        count(*) as TotalLinks,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
),
hot_bumps as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 52) as BecameHot,
        count(*) filter (where ph.PostHistoryTypeId = 53) as RemovedHot,
        count(*) filter (where ph.PostHistoryTypeId = 50) as CommunityBumps
    from PostHistory ph
    group by ph.PostId
),
user_activity_window as (
    select
        u.Id as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsAuthored,
        count(*) filter (where p.PostTypeId = 2) as AnswersAuthored,
        max(p.CreationDate) as LastPostDate,
        row_number() over (partition by u.Id order by coalesce(u.LastAccessDate, u.CreationDate) desc, u.Id) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.LastAccessDate, u.CreationDate
),
volatility as (
    select
        q.QuestionId,
        stddev_pop(coalesce(a.Score,0)) as AnswerScoreStdDev,
        stddev_pop(extract(epoch from coalesce(a.CreationDate, q.CreationDate))) as AnswerTimingStdDev
    from recent_q q
    left join Posts a on a.ParentId = q.QuestionId and a.PostTypeId = 2
    group by q.QuestionId
),
accepted_answer as (
    select
        q.QuestionId,
        aa.Id as AcceptedId,
        aa.Score as AcceptedScore,
        aa.CreationDate as AcceptedDate
    from recent_q q
    left join Posts aa on aa.Id = (select p.AcceptedAnswerId from Posts p where p.Id = q.QuestionId)
),
owner_baseline as (
    select
        q.QuestionId,
        op.UserId,
        op.Reputation,
        op.DisplayName,
        op.Location,
        br.BadgeCount,
        br.GoldCount,
        br.SilverCount,
        br.BronzeCount
    from recent_q q
    left join owner_profile op on op.UserId = q.OwnerUserId
    left join badge_rollup br on br.UserId = q.OwnerUserId
),
metric_calc as (
    select
        q.QuestionId,
        q.CreationDate,
        q.SafeTitle,
        q.ViewCount,
        q.Score as QuestionScore,
        a.AnswerCount,
        a.AvgAnswerScore,
        a.MaxAnswerScore,
        v.UpVotes,
        v.DownVotes,
        v.Favorites,
        v.BountyTotal,
        c.CommentCount,
        c.PositiveComments,
        coalesce(nullif(log(nullif(q.ViewCount,0)), 'NaN'), 0.0) as LnViews,
        case when a.AnswerCount > 0 then cast(q.Score as numeric) / a.AnswerCount else null end as ScorePerAnswer,
        case when v.UpVotes + v.DownVotes > 0 then cast(v.UpVotes as numeric) / (v.UpVotes + v.DownVotes) else null end as UpvoteRatio,
        case when v.TotalVotes > 0 then v.TotalVotes else 0 end as TotalVotes,
        case when q.ViewCount > 0 then cast(v.Favorites as numeric) / q.ViewCount else null end as FavoriteViewRate,
        case when c.CommentCount > 0 then cast(q.Score as numeric) / c.CommentCount else null end as ScorePerComment
    from recent_q q
    left join answer_stats a on a.QuestionId = q.QuestionId
    left join vote_agg v on v.PostId = q.QuestionId
    left join comment_activity c on c.PostId = q.QuestionId
),
rankings as (
    select
        m.QuestionId,
        m.CreationDate,
        m.SafeTitle,
        m.ViewCount,
        m.QuestionScore,
        m.AnswerCount,
        m.AvgAnswerScore,
        m.MaxAnswerScore,
        m.UpVotes,
        m.DownVotes,
        m.Favorites,
        m.BountyTotal,
        m.TotalVotes,
        m.LnViews,
        m.ScorePerAnswer,
        m.UpvoteRatio,
        m.FavoriteViewRate,
        m.ScorePerComment,
        row_number() over (order by coalesce(m.ScorePerAnswer, -1) desc nulls last, m.TotalVotes desc, m.ViewCount desc) as rn_score_per_answer,
        dense_rank() over (order by m.UpvoteRatio desc nulls last) as dr_upvote_ratio,
        percent_rank() over (order by m.ViewCount) as pr_viewcount,
        ntile(10) over (order by coalesce(m.LnViews,0)) as decile_lnviews
    from metric_calc m
    group by
        m.QuestionId, m.CreationDate, m.SafeTitle, m.ViewCount, m.QuestionScore, m.AnswerCount, m.AvgAnswerScore, m.MaxAnswerScore,
        m.UpVotes, m.DownVotes, m.Favorites, m.BountyTotal, m.TotalVotes, m.LnViews, m.ScorePerAnswer, m.UpvoteRatio, m.FavoriteViewRate, m.ScorePerComment
),
tag_pivot as (
    select
        tr.QuestionId,
        max(case when tr.TagPopularityRank = 1 then tr.TagName end) as TopTag,
        max(case when tr.TagPopularityRank = 2 then tr.TagName end) as SecondTag
    from tag_rank tr
    group by tr.QuestionId
),
labeling as (
    select
        r.QuestionId,
        case
            when r.AnswerCount is null or r.AnswerCount = 0 then 'Unanswered'
            when r.AnswerCount between 1 and 2 then 'Lightly Answered'
            when r.AnswerCount between 3 and 5 then 'Moderately Answered'
            else 'Heavily Answered'
        end as AnswerBand,
        case
            when r.UpvoteRatio is null then 'NoVotes'
            when r.UpvoteRatio >= 0.9 then 'Loved'
            when r.UpvoteRatio >= 0.75 then 'Liked'
            when r.UpvoteRatio >= 0.5 then 'Mixed'
            when r.UpvoteRatio > 0 then 'Controversial'
            else 'Hated'
        end as SentimentLabel
    from rankings r
    group by r.QuestionId, r.AnswerCount, r.UpvoteRatio
),
final as (
    select
        r.QuestionId,
        r.CreationDate,
        r.SafeTitle as Title,
        tb.TopTag,
        tb.SecondTag,
        ob.DisplayName as OwnerName,
        ob.Location as OwnerLocation,
        ob.Reputation as OwnerReputation,
        ob.BadgeCount,
        ob.GoldCount,
        ob.SilverCount,
        ob.BronzeCount,
        r.ViewCount,
        r.QuestionScore,
        r.AnswerCount,
        r.AvgAnswerScore,
        r.MaxAnswerScore,
        r.UpVotes,
        r.DownVotes,
        r.Favorites,
        r.BountyTotal,
        r.TotalVotes,
        r.LnViews,
        r.ScorePerAnswer,
        r.UpvoteRatio,
        r.FavoriteViewRate,
        r.ScorePerComment,
        r.rn_score_per_answer,
        r.dr_upvote_ratio,
        r.pr_viewcount,
        r.decile_lnviews,
        ci.FirstClosedDate,
        ci.LastReopenDate,
        ci.LastCloseReasonId,
        ci.WasProtected,
        l.LinkedCount,
        l.DuplicateCount,
        l.TotalLinks,
        hb.BecameHot,
        hb.RemovedHot,
        hb.CommunityBumps,
        va.AnswerScoreStdDev,
        va.AnswerTimingStdDev,
        aa.AcceptedId,
        aa.AcceptedScore,
        aa.AcceptedDate,
        la.AnswerBand,
        la.SentimentLabel,
        greatest(
            coalesce(r.CreationDate, timestamp 'epoch'),
            coalesce(aa.AcceptedDate, timestamp 'epoch'),
            coalesce(ci.FirstClosedDate, timestamp 'epoch'),
            -- convert BecameHot (an integer) to a timestamp by treating as epoch seconds if present; else epoch
            coalesce(
              case when hb.BecameHot is not null then to_timestamp(hb.BecameHot) end,
              timestamp 'epoch'
            )
        ) as LastKeyEventApprox
    from rankings r
    left join tag_pivot tb on tb.QuestionId = r.QuestionId
    left join owner_baseline ob on ob.QuestionId = r.QuestionId
    left join closure_info ci on ci.PostId = r.QuestionId
    left join linkage l on l.PostId = r.QuestionId
    left join hot_bumps hb on hb.PostId = r.QuestionId
    left join volatility va on va.QuestionId = r.QuestionId
    left join accepted_answer aa on aa.QuestionId = r.QuestionId
    left join labeling la on la.QuestionId = r.QuestionId
)
select *
from final f
where
    (
        (f.AnswerCount is null and f.ViewCount > 0)
        or (f.AnswerCount >= 2 and f.UpvoteRatio is not null and f.UpvoteRatio >= 0.6)
        or (f.DuplicateCount > 0 and coalesce(f.QuestionScore,0) <= 0)
    )
    and coalesce(f.BadgeCount, 0) >= 0
    and (
        f.TopTag is null
        or lower(f.TopTag) <> lower(coalesce(f.SecondTag, ''))
        or (f.SecondTag is null and f.TopTag is not null)
    )
    and (
        f.FirstClosedDate is null
        or (f.LastReopenDate is not null and f.LastReopenDate >= f.FirstClosedDate)
        or (f.LastCloseReasonId in (101,102,103,104,105) and f.QuestionScore >= 0)
    )
    and (
        f.AcceptedId is null
        or (f.AcceptedScore >= coalesce(f.AvgAnswerScore, f.AcceptedScore))
    )
order by
    f.decile_lnviews desc,
    f.rn_score_per_answer asc,
    f.dr_upvote_ratio asc nulls last,
    f.CreationDate desc
limit 500;