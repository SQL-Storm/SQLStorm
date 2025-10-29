with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        q.Score,
        q.ViewCount,
        q.Title,
        q.Tags,
        array_length(string_to_array(coalesce(substring(q.Tags, 2, nullif(length(q.Tags)-1,0)), ''), '><'), 1) as TagCount,
        coalesce(q.AnswerCount, 0) as AnswerCount
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate,
        u.Location,
        coalesce(nullif(trim(u.DisplayName), ''), '(anonymous)') as DisplayName,
        greatest(u.UpVotes - u.DownVotes, 0) as NetVotesPosOnly
    from Users u
),
question_engagement as (
    select
        q.QuestionId,
        q.OwnerUserId,
        count(distinct c.Id) as CommentCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvoteCount,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvoteCount,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCount,
        count(distinct case when ph.PostHistoryTypeId = 10 then ph.Id end) as CloseEvents,
        bool_or(ph.PostHistoryTypeId = 11) as HasReopenEvent
    from recent_questions q
    left join Comments c on c.PostId = q.QuestionId
    left join Votes v on v.PostId = q.QuestionId
    left join PostHistory ph on ph.PostId = q.QuestionId and ph.PostHistoryTypeId in (10,11)
    group by q.QuestionId, q.OwnerUserId
),
answer_stats as (
    select
        a.QuestionId,
        count(*) as AnswerTotal,
        count(*) filter (where a.AnswerScore > 0) as PositiveAnswers,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(CAST(a.AnswerScore AS numeric)) as AvgAnswerScore,
        count(distinct a.AnswerUserId) as DistinctAnswerers,
        min(a.AnswerCreationDate) as FirstAnswerAt,
        max(a.AnswerCreationDate) as LastAnswerAt
    from answers a
    group by a.QuestionId
),
accepted as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
      and q.AcceptedAnswerId is not null
),
tag_unrolled as (
    select
        q.QuestionId,
        unnest(string_to_array(coalesce(substring(q.Tags, 2, nullif(length(q.Tags)-1,0)), ''), '><')) as TagName
    from recent_questions q
),
tag_quality as (
    select
        t.TagName,
        count(distinct tu.QuestionId) as QuestionsWithTag,
        sum(coalesce(rq.Score,0)) as TotalScoreWithTag,
        avg(CAST(coalesce(rq.ViewCount,0) AS numeric)) as AvgViewsWithTag,
        max(coalesce(rq.AnswerCount,0)) as MaxAnswersWithTag
    from tag_unrolled tu
    join Tags t on lower(t.TagName) = lower(tu.TagName)
    join recent_questions rq on rq.QuestionId = tu.QuestionId
    group by t.TagName
),
duplicates as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
    from PostLinks pl
    group by pl.PostId
),
user_badge_summary as (
    select
        b.UserId,
        count(*) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) filter (where CAST(b.TagBased AS integer) = 1) as TagBadges
    from Badges b
    group by b.UserId
),
recent_hot as (
    select
        ph.PostId as QuestionId,
        max(case when ph.PostHistoryTypeId = 52 then ph.CreationDate end) as BecameHotAt,
        max(case when ph.PostHistoryTypeId = 53 then ph.CreationDate end) as RemovedHotAt
    from PostHistory ph
    where ph.PostHistoryTypeId in (52,53)
    group by ph.PostId
),
ranked_questions as (
    select
        rq.*,
        qe.CommentCount,
        qe.UpvoteCount,
        qe.DownvoteCount,
        qe.FavoriteCount,
        qe.CloseEvents,
        qe.HasReopenEvent,
        coalesce(ans.AnswerTotal, 0) as AnswerTotal,
        coalesce(ans.PositiveAnswers, 0) as PositiveAnswers,
        coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(ans.MinAnswerScore, 0) as MinAnswerScore,
        coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(ans.DistinctAnswerers, 0) as DistinctAnswerers,
        acc.AcceptedAnswerId,
        d.DuplicateLinks,
        d.LinkedLinks,
        rh.BecameHotAt,
        rh.RemovedHotAt,
        ub.BadgeCount as OwnerBadgeCount,
        ub.GoldBadges as OwnerGoldBadges,
        ua.Reputation as OwnerReputation,
        ua.NetVotesPosOnly as OwnerNetVotes,
        case
            when coalesce(ans.AnswerTotal,0) = 0 then null
            else coalesce(ans.FirstAnswerAt, rq.CreationDate) - rq.CreationDate
        end as TimeToFirstAnswer,
        case
            when rq.ViewCount is null or rq.ViewCount = 0 then null
            else (CAST(rq.Score AS numeric) / rq.ViewCount) end as ScorePerView
    from recent_questions rq
    left join question_engagement qe on qe.QuestionId = rq.QuestionId
    left join answer_stats ans on ans.QuestionId = rq.QuestionId
    left join accepted acc on acc.QuestionId = rq.QuestionId
    left join duplicates d on d.QuestionId = rq.QuestionId
    left join recent_hot rh on rh.QuestionId = rq.QuestionId
    left join user_activity ua on ua.UserId = rq.OwnerUserId
    left join user_badge_summary ub on ub.UserId = rq.OwnerUserId
),
score_buckets as (
    select
        rq.QuestionId,
        case
            when rq.Score >= 50 then 'legendary'
            when rq.Score >= 20 then 'great'
            when rq.Score >= 10 then 'good'
            when rq.Score >= 0 then 'ok'
            else 'poor'
        end as ScoreBand
    from recent_questions rq
),
anomalies as (
    select
        rq.QuestionId,
        case when rq.ViewCount > 0 and rq.Score < 0 and rq.ViewCount > 1000 then 1 else 0 end as NegScoreHighView,
        case when rq.AnswerCount = 0 and rq.ViewCount > 5000 then 1 else 0 end as NoAnswersHighView,
        case when rq.Score > 20 and rq.AnswerCount = 0 then 1 else 0 end as HighScoreNoAnswers
    from recent_questions rq
),
user_outliers as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ub.BadgeCount,
        rank() over (order by ua.Reputation desc, coalesce(ub.BadgeCount,0) desc) as RepRank
    from user_activity ua
    left join user_badge_summary ub on ub.UserId = ua.UserId
),
agg_per_user as (
    select
        rq.OwnerUserId as UserId,
        count(*) as UserQuestionCount,
        sum(rq.Score) as UserQuestionScore,
        avg(CAST(rq.ViewCount AS numeric)) as UserAvgViews,
        sum(coalesce(qe.FavoriteCount,0)) as UserTotalFavorites
    from recent_questions rq
    left join question_engagement qe on qe.QuestionId = rq.QuestionId
    group by rq.OwnerUserId
),
question_rank as (
    select
        r.*,
        dense_rank() over (order by coalesce(r.ScorePerView,0) desc nulls last, r.Score desc, r.ViewCount desc) as RankByEfficiency,
        row_number() over (order by r.Score desc, r.ViewCount desc) as RankByScore,
        percent_rank() over (order by r.ViewCount desc) as ViewPercentRank
    from ranked_questions r
),
tag_influence as (
    select
        tu.QuestionId,
        sum(log(1 + tq.QuestionsWithTag)) as TagPopularityIndex,
        avg(tq.AvgViewsWithTag) as AvgTagViews,
        max(tq.TotalScoreWithTag) as PeakTagScore
    from tag_unrolled tu
    join tag_quality tq on tq.TagName = tu.TagName
    group by tu.QuestionId
),
final_scores as (
    select
        qr.QuestionId,
        qr.Title,
        qr.Score,
        qr.ViewCount,
        qr.AnswerCount,
        qr.OwnerUserId,
        coalesce(ti.TagPopularityIndex, 0) as TagPopularityIndex,
        coalesce(ti.AvgTagViews, 0) as AvgTagViews,
        coalesce(ti.PeakTagScore, 0) as PeakTagScore,
        qr.ScorePerView,
        qr.TimeToFirstAnswer,
        qr.RankByEfficiency,
        qr.RankByScore,
        qr.ViewPercentRank,
        coalesce(qr.UpvoteCount,0) - coalesce(qr.DownvoteCount,0) as NetVotes,
        coalesce(qr.FavoriteCount,0) as Favorites,
        coalesce(qr.CloseEvents,0) as CloseEvents,
        qr.HasReopenEvent,
        case when qr.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        coalesce(qr.DuplicateLinks,0) as DuplicateLinks,
        coalesce(qr.LinkedLinks,0) as LinkedLinks,
        coalesce(qr.OwnerReputation,0) as OwnerReputation,
        coalesce(qr.OwnerGoldBadges,0) as OwnerGoldBadges
    from question_rank qr
    left join tag_influence ti on ti.QuestionId = qr.QuestionId
)
select
    f.QuestionId,
    left(coalesce(f.Title,''), 120) as TitleSnippet,
    f.Score,
    f.ViewCount,
    f.AnswerCount,
    f.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    coalesce(ua.Location, '(unknown)') as OwnerLocation,
    coalesce(ua.Reputation,0) as OwnerReputation,
    coalesce(ub.BadgeCount,0) as OwnerBadges,
    s.ScoreBand,
    f.HasAccepted,
    f.NetVotes,
    f.Favorites,
    f.CloseEvents,
    f.HasReopenEvent,
    f.DuplicateLinks,
    f.LinkedLinks,
    f.TagPopularityIndex,
    f.AvgTagViews,
    f.PeakTagScore,
    extract(epoch from f.TimeToFirstAnswer) as TimeToFirstAnswerSeconds,
    round(CAST(coalesce(f.ScorePerView,0) AS numeric), 6) as ScorePerView,
    f.RankByEfficiency,
    f.RankByScore,
    f.ViewPercentRank,
    a.NegScoreHighView,
    a.NoAnswersHighView,
    a.HighScoreNoAnswers,
    au.UserQuestionCount,
    au.UserQuestionScore,
    au.UserAvgViews,
    au.UserTotalFavorites,
    uo.RepRank as OwnerRepRank,
    coalesce(phc.ClosedCommentReason, 'N/A') as LatestCloseReason
from final_scores f
left join score_buckets s on s.QuestionId = f.QuestionId
left join anomalies a on a.QuestionId = f.QuestionId
left join agg_per_user au on au.UserId = f.OwnerUserId
left join user_outliers uo on uo.UserId = f.OwnerUserId
left join Users u on u.Id = f.OwnerUserId
left join user_activity ua on ua.UserId = f.OwnerUserId
left join user_badge_summary ub on ub.UserId = f.OwnerUserId
left join lateral (
    select
        case
            when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+' then (
                select crt.Name from CloseReasonTypes crt
                where crt.Id = CAST(ph.Comment AS integer)
            )
            when ph.PostHistoryTypeId = 10 then 'Closed'
            else null
        end as ClosedCommentReason
    from PostHistory ph
    where ph.PostId = f.QuestionId and ph.PostHistoryTypeId in (10,11)
    order by ph.CreationDate desc
    limit 1
) phc on true
where
    coalesce(f.ScorePerView, 0) >= 0
    and (f.OwnerReputation is null or f.OwnerReputation >= 1)
    and not (a.HighScoreNoAnswers = 1 and f.CloseEvents > 0)
order by
    f.RankByEfficiency nulls last,
    f.RankByScore,
    f.QuestionId
limit 500;