-- {"query": "199.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3306}
with recent_questions as (
    select
        q.Id as QuestionId,
        q.CreationDate,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        q.Title,
        q.Tags,
        q.AcceptedAnswerId,
        coalesce(q.FavoriteCount, 0) as FavoriteCount,
        date_trunc('month', q.CreationDate) as MonthBucket
    from Posts q
    where q.PostTypeId = 1
      and q.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        case when a.Id = rq.AcceptedAnswerId then 1 else 0 end as IsAccepted
    from Posts a
    join recent_questions rq on rq.QuestionId = a.ParentId
    where a.PostTypeId = 2
),
first_answer as (
    select
        QuestionId,
        AnswerId,
        AnswerOwnerId,
        AnswerScore,
        AnswerCreationDate,
        IsAccepted
    from (
        select
            QuestionId,
            AnswerId,
            AnswerOwnerId,
            AnswerScore,
            AnswerCreationDate,
            IsAccepted,
            row_number() over (partition by QuestionId order by AnswerCreationDate asc, AnswerScore desc) as rn
        from answers
    ) t
    where rn = 1
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
    from Votes v
    where v.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreComments
    from Comments c
    where c.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by c.PostId
),
tag_expansion as (
    select
        rq.QuestionId,
        unnest(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><')) as tag
    from recent_questions rq
    where rq.Tags is not null
),
tag_quality as (
    select
        te.tag,
        count(distinct te.QuestionId) as TaggedQuestions,
        avg(rq.QuestionScore) as AvgQScore,
        percentile_disc(0.9) within group (order by rq.ViewCount) as P90Views,
        sum(case when rq.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAccepted
    from tag_expansion te
    join recent_questions rq on rq.QuestionId = te.QuestionId
    group by te.tag
),
user_activity as (
    select
        u.Id as UserId,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        coalesce(u.DisplayName, '') as DisplayName,
        coalesce(u.WebsiteUrl, '') as WebsiteUrl,
        u.UpVotes as LifetimeUpVotes,
        u.DownVotes as LifetimeDownVotes,
        date_trunc('month', u.CreationDate) as UserCohort
    from Users u
),
badge_agg as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as Gold,
        sum(case when b.Class = 2 then 1 else 0 end) as Silver,
        sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
        sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
close_events as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedAt,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedAt,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseCount,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenCount,
        -- emulate array_remove(array_agg(distinct ...), null) by aggregating distinct non-null reasons into an array via string aggregation then splitting
        (case
            when count(distinct case when ph.PostHistoryTypeId = 10 then nullif(trim(ph.Comment), '') end) = 0 then null
            else string_to_array(string_agg(distinct case when ph.PostHistoryTypeId = 10 then nullif(trim(ph.Comment), '') end, '||SEP||'), '||SEP||')
         end) as CloseReasonsRaw
    from PostHistory ph
    join recent_questions rq on rq.QuestionId = ph.PostId
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOf,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks
    from PostLinks pl
    join recent_questions rq on rq.QuestionId = pl.PostId
    group by pl.PostId
),
question_features as (
    select
        rq.QuestionId,
        rq.MonthBucket,
        rq.OwnerUserId,
        rq.QuestionScore,
        rq.ViewCount,
        rq.FavoriteCount,
        coalesce(v.UpVotes, 0) as VoteUps,
        coalesce(v.DownVotes, 0) as VoteDowns,
        coalesce(v.Favorites, 0) as VoteFavorites,
        coalesce(v.BountyTotal, 0) as BountyTotal,
        coalesce(ca.CommentCount, 0) as CommentCount,
        ca.LastCommentDate,
        coalesce(ca.HighScoreComments, 0) as HighScoreComments,
        fe.AnswerId as FirstAnswerId,
        fe.AnswerOwnerId,
        fe.AnswerScore as FirstAnswerScore,
        fe.AnswerCreationDate,
        fe.IsAccepted,
        ce.FirstClosedAt,
        ce.LastReopenedAt,
        ce.CloseCount,
        ce.ReopenCount,
        dl.DuplicateLinks,
        case
            when rq.Tags is null then 0
            when length(rq.Tags) <= 2 then 0
            else array_length(string_to_array(substring(rq.Tags, 2, length(rq.Tags)-2), '><'), 1)
        end as TagCount,
        case
            when rq.Title is null then 0
            else length(regexp_replace(rq.Title, '\s+', '', 'g'))
        end as TitleCharNoSpace,
        case when rq.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
        extract(epoch from (coalesce(fe.AnswerCreationDate, cast('2024-10-01 12:34:56' as timestamp)) - rq.CreationDate))/3600.0 as HoursToFirstAnswer,
        extract(epoch from (coalesce(ce.FirstClosedAt, cast('2024-10-01 12:34:56' as timestamp)) - rq.CreationDate))/3600.0 as HoursToClose
    from recent_questions rq
    left join votes_agg v on v.PostId = rq.QuestionId
    left join comment_agg ca on ca.PostId = rq.QuestionId
    left join first_answer fe on fe.QuestionId = rq.QuestionId
    left join close_events ce on ce.PostId = rq.QuestionId
    left join dup_links dl on dl.DuplicateOf = rq.QuestionId
),
user_enriched as (
    select
        ua.UserId,
        ua.Reputation,
        ua.UserCreationDate,
        ua.Location,
        ua.DisplayName,
        ua.WebsiteUrl,
        ua.LifetimeUpVotes,
        ua.LifetimeDownVotes,
        ua.UserCohort,
        coalesce(ba.Gold, 0) as GoldBadges,
        coalesce(ba.Silver, 0) as SilverBadges,
        coalesce(ba.Bronze, 0) as BronzeBadges,
        coalesce(ba.TagBadges, 0) as TagBadges,
        ba.FirstBadgeDate,
        ba.LastBadgeDate
    from user_activity ua
    left join badge_agg ba on ba.UserId = ua.UserId
),
tag_rank as (
    select
        tq.tag,
        tq.TaggedQuestions,
        tq.AvgQScore,
        tq.P90Views,
        tq.QuestionsWithAccepted,
        dense_rank() over (order by tq.TaggedQuestions desc, tq.AvgQScore desc) as PopularityRank
    from tag_quality tq
),
question_tag_features as (
    select
        te.QuestionId,
        max(case when tr.PopularityRank <= 50 then tr.PopularityRank end) as BestTop50Rank,
        avg(tr.AvgQScore) as AvgTagQScore,
        max(tr.P90Views) as MaxTagP90Views,
        sum(tr.QuestionsWithAccepted) as SumTagAcceptedCount
    from tag_expansion te
    join tag_rank tr on tr.tag = te.tag
    group by te.QuestionId
),
accepted_answerer_stats as (
    select
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswererId,
        sum(case when a.Id = p.AcceptedAnswerId then 1 else 0 end) as AcceptedByUserOnThisQ,
        avg(a.Score) as AvgAnswerScoreByUserOnThisQ
    from Posts a
    join Posts p on p.Id = a.ParentId and p.PostTypeId = 1
    where a.PostTypeId = 2
    group by a.ParentId, a.OwnerUserId
),
final as (
    select
        qf.QuestionId,
        qf.MonthBucket,
        u.DisplayName as AskerName,
        u.Reputation as AskerReputation,
        coalesce(u.Location, 'Unknown') as AskerLocation,
        u.GoldBadges + u.SilverBadges + u.BronzeBadges as AskerBadgeCount,
        qf.QuestionScore,
        qf.ViewCount,
        qf.FavoriteCount + qf.VoteFavorites as TotalFavorites,
        qf.VoteUps - qf.VoteDowns as NetVotes,
        qf.BountyTotal,
        qf.CommentCount,
        qf.HighScoreComments,
        qf.TagCount,
        qf.TitleCharNoSpace,
        qf.HasAccepted,
        qf.HoursToFirstAnswer,
        qf.HoursToClose,
        qf.FirstAnswerId,
        qf.AnswerOwnerId,
        qf.FirstAnswerScore,
        qf.AnswerCreationDate,
        aa.AcceptedByUserOnThisQ,
        aa.AvgAnswerScoreByUserOnThisQ,
        qtf.BestTop50Rank,
        qtf.AvgTagQScore,
        qtf.MaxTagP90Views,
        qtf.SumTagAcceptedCount,
        case
            when qf.FirstClosedAt is not null and qf.LastReopenedAt is null then 'Closed'
            when qf.FirstClosedAt is not null and qf.LastReopenedAt is not null and qf.LastReopenedAt > qf.FirstClosedAt then 'Reopened'
            else 'OpenOrUnknown'
        end as CloseState,
        case
            when (qf.VoteUps - qf.VoteDowns) >= 50 and qf.ViewCount >= 10000 then 'HighlyEngaged'
            when (qf.VoteUps - qf.VoteDowns) between 10 and 49 then 'Moderate'
            when (qf.VoteUps - qf.VoteDowns) between 1 and 9 then 'Low'
            when (qf.VoteUps - qf.VoteDowns) = 0 then 'Neutral'
            else 'Negative'
        end as EngagementBucket,
        coalesce(dl.DuplicateLinks, 0) as DuplicateLinks,
        array_length(regexp_split_to_array(coalesce(replace(lower(u.WebsiteUrl), 'http://', ''), ''), '/'), 1) as WebsitePathDepth,
        case when lower(coalesce(u.WebsiteUrl, '')) like '%github.com%' then 1 else 0 end as IsGitHubLinked,
        case when coalesce(u.WebsiteUrl, '') ~* 'https?://(www\\.)?[a-z0-9\\-]+\\.[a-z]{2,}(/.*)?$' then 1 else 0 end as WebsiteLooksValid
    from question_features qf
    left join user_enriched u on u.UserId = qf.OwnerUserId
    left join question_tag_features qtf on qtf.QuestionId = qf.QuestionId
    left join dup_links dl on dl.DuplicateOf = qf.QuestionId
    left join accepted_answerer_stats aa on aa.QuestionId = qf.QuestionId and aa.AnswererId = qf.AnswerOwnerId
),
ranked as (
    select
        f.MonthBucket,
        f.QuestionId,
        f.AskerName,
        f.AskerReputation,
        f.AskerLocation,
        f.AskerBadgeCount,
        f.QuestionScore,
        f.ViewCount,
        f.TotalFavorites,
        f.NetVotes,
        f.BountyTotal,
        f.CommentCount,
        f.HighScoreComments,
        f.TagCount,
        f.TitleCharNoSpace,
        f.HasAccepted,
        f.HoursToFirstAnswer,
        f.HoursToClose,
        f.FirstAnswerId,
        f.AnswerOwnerId,
        f.FirstAnswerScore,
        f.AnswerCreationDate,
        f.AcceptedByUserOnThisQ,
        f.AvgAnswerScoreByUserOnThisQ,
        f.BestTop50Rank,
        f.AvgTagQScore,
        f.MaxTagP90Views,
        f.SumTagAcceptedCount,
        f.CloseState,
        f.EngagementBucket,
        f.DuplicateLinks,
        f.WebsitePathDepth,
        f.IsGitHubLinked,
        f.WebsiteLooksValid,
        row_number() over (partition by f.MonthBucket order by f.NetVotes desc nulls last, f.ViewCount desc nulls last) as rn_netvotes,
        row_number() over (partition by f.MonthBucket order by f.ViewCount desc nulls last, f.TotalFavorites desc nulls last) as rn_views,
        dense_rank() over (order by f.NetVotes desc nulls last, f.ViewCount desc nulls last) as global_rank,
        percent_rank() over (order by f.ViewCount) as pct_view,
        ntile(10) over (order by f.NetVotes) as decile_netvotes
    from final f
)
select
    r.MonthBucket,
    r.QuestionId,
    r.AskerName,
    r.AskerReputation,
    r.AskerLocation,
    r.AskerBadgeCount,
    r.QuestionScore,
    r.ViewCount,
    r.TotalFavorites,
    r.NetVotes,
    r.BountyTotal,
    r.CommentCount,
    r.HighScoreComments,
    r.TagCount,
    r.TitleCharNoSpace,
    r.HasAccepted,
    r.HoursToFirstAnswer,
    r.HoursToClose,
    r.FirstAnswerId,
    r.AnswerOwnerId,
    r.FirstAnswerScore,
    r.AnswerCreationDate,
    r.AcceptedByUserOnThisQ,
    r.AvgAnswerScoreByUserOnThisQ,
    r.BestTop50Rank,
    r.AvgTagQScore,
    r.MaxTagP90Views,
    r.SumTagAcceptedCount,
    r.CloseState,
    r.EngagementBucket,
    r.DuplicateLinks,
    r.WebsitePathDepth,
    r.IsGitHubLinked,
    r.WebsiteLooksValid,
    r.rn_netvotes,
    r.rn_views,
    r.global_rank,
    r.pct_view,
    r.decile_netvotes
from ranked r
where (
        (r.rn_netvotes <= 50 and r.EngagementBucket in ('HighlyEngaged','Moderate'))
     or (r.rn_views <= 50 and r.HasAccepted = 1)
     or (r.global_rank <= 100 and r.pct_view >= 0.9)
     )
  and (
        coalesce(r.AvgTagQScore, 0) >= 0
        or r.BestTop50Rank is not null
      )
order by r.MonthBucket desc, r.global_rank asc, r.rn_views asc, r.QuestionId asc;