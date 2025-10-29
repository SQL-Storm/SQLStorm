-- {"query": "435.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3010}
with
q_posts as (
    select
        p.Id as QuestionId,
        p.CreationDate as QuestionCreation,
        p.OwnerUserId as QuestionOwnerId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ClosedDate,
        p.LastActivityDate
    from Posts p
    where p.PostTypeId = 1
),
a_posts as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation
    from Posts a
    where a.PostTypeId = 2
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreation,
        coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
        case
            when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 0
            when position('http' in lower(u.WebsiteUrl)) = 1 then 1
            else 1
        end as HasWebsite
    from Users u
),
tag_expand as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) as Tag
    from q_posts q
    where q.Tags is not null and q.Tags like '<%>'
),
recent_activity as (
    select
        ph.PostId,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36,50,52,53)) as LastModEvent,
        count(*) filter (where ph.PostHistoryTypeId in (24)) as SuggestedEditsApplied,
        count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseEvents
    from PostHistory ph
    group by ph.PostId
),
vote_agg as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        count(*) filter (where v.VoteTypeId = 8) as BountiesStarted,
        sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as BountyAmountTotal,
        min(v.CreationDate) as FirstVoteAt,
        max(v.CreationDate) as LastVoteAt
    from Votes v
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.CreationDate) as LastCommentAt,
        sum(c.Score) as CommentScoreSum
    from Comments c
    group by c.PostId
),
answer_stats as (
    select
        ap.QuestionId,
        count(*) as AnswerCount,
        max(ap.AnswerScore) as MaxAnswerScore,
        avg(cast(ap.AnswerScore as numeric)) as AvgAnswerScore,
        min(ap.AnswerCreation) as FirstAnswerAt,
        max(ap.AnswerCreation) as LastAnswerAt
    from a_posts ap
    group by ap.QuestionId
),
accepted_answer as (
    select
        q.QuestionId,
        a.AnswerId,
        a.AnswerOwnerId,
        a.AnswerScore,
        a.AnswerCreation
    from q_posts q
    left join a_posts a
      on a.AnswerId = q.AcceptedAnswerId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
        max(pl.CreationDate) as LastLinkAt
    from PostLinks pl
    group by pl.PostId
),
quality_bucket as (
    select
        q.QuestionId,
        case
            when coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) >= 50 then 'A'
            when coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) between 10 and 49 then 'B'
            when coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) between 0 and 9 then 'C'
            else 'D'
        end as ScoreBucket
    from q_posts q
    left join vote_agg va on va.PostId = q.QuestionId
),
user_badge_tally as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeAt
    from Badges b
    group by b.UserId
),
question_owner as (
    select
        q.QuestionId,
        u.UserId as OwnerUserId,
        u.Reputation as OwnerReputation,
        u.LocationNorm as OwnerLocation,
        ub.TotalBadges as OwnerTotalBadges,
        ub.GoldBadges as OwnerGoldBadges
    from q_posts q
    left join user_stats u on u.UserId = q.QuestionOwnerId
    left join user_badge_tally ub on ub.UserId = q.QuestionOwnerId
),
answer_owner as (
    select
        aa.QuestionId,
        u.UserId as AcceptedOwnerId,
        u.Reputation as AcceptedOwnerReputation,
        ub.TotalBadges as AcceptedOwnerTotalBadges
    from accepted_answer aa
    left join user_stats u on u.UserId = aa.AnswerOwnerId
    left join user_badge_tally ub on ub.UserId = aa.AnswerOwnerId
),
time_metrics as (
    select
        q.QuestionId,
        extract(epoch from (coalesce(aa.AnswerCreation, q.QuestionCreation) - q.QuestionCreation)) as SecsToFirstResolution,
        extract(epoch from (coalesce(ra.LastModEvent, q.LastActivityDate) - q.QuestionCreation)) as SecsToLastModFromCreate,
        extract(epoch from (coalesce(ans.FirstAnswerAt, q.LastActivityDate) - q.QuestionCreation)) as SecsToFirstAnswer,
        extract(epoch from (coalesce(ans.LastAnswerAt, q.LastActivityDate) - q.QuestionCreation)) as SecsToLastAnswer
    from q_posts q
    left join accepted_answer aa on aa.QuestionId = q.QuestionId
    left join recent_activity ra on ra.PostId = q.QuestionId
    left join answer_stats ans on ans.QuestionId = q.QuestionId
),
tagged_focus as (
    select
        QuestionId,
        count(*) as TagCount,
        max(case when lower(Tag) in ('sql','postgresql','tsql','mysql') then 1 else 0 end) as HasSQLTag,
        string_agg(Tag, ',' order by Tag) as TagList
    from tag_expand
    group by QuestionId
),
score_rankings as (
    select
        q.QuestionId,
        q.QuestionScore,
        rank() over (order by q.QuestionScore desc, q.ViewCount desc, q.QuestionId) as ScoreRank,
        dense_rank() over (partition by qb.ScoreBucket order by q.QuestionScore desc) as BucketDenseRank,
        percent_rank() over (order by q.QuestionScore) as ScorePercentRank
    from q_posts q
    left join quality_bucket qb on qb.QuestionId = q.QuestionId
),
view_windows as (
    select
        q.QuestionId,
        q.ViewCount,
        avg(q.ViewCount) over () as AvgViewsAll,
        avg(q.ViewCount) over (order by q.ViewCount rows between 10 preceding and 10 following) as AvgViewsWindow,
        sum(q.ViewCount) over (order by q.QuestionCreation rows between unbounded preceding and current row) as CumViewsByTime
    from q_posts q
),
close_reasons as (
    select
        ph.PostId as QuestionId,
        min(ph.CreationDate) as FirstCloseAt,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as AnyCloseReasonId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseCount
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
close_reason_names as (
    select
        cr.QuestionId,
        case
            when cr.AnyCloseReasonId ~ '^[0-9]+$' then crt.Name
            else null
        end as CloseReasonName
    from close_reasons cr
    left join CloseReasonTypes crt
      on cast(crt.Id as text) = cr.AnyCloseReasonId
),
final_set as (
    select
        q.QuestionId,
        q.Title,
        q.QuestionCreation,
        q.QuestionScore,
        q.ViewCount,
        coalesce(va.UpVotes,0) as UpVotes,
        coalesce(va.DownVotes,0) as DownVotes,
        coalesce(va.Favorites,0) as Favorites,
        coalesce(ca.CommentCount,0) as CommentCount,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
        coalesce(aa.AnswerId, -1) as AcceptedAnswerId,
        coalesce(aa.AnswerScore, 0) as AcceptedAnswerScore,
        qb.ScoreBucket,
        sr.ScoreRank,
        sr.BucketDenseRank,
        round(cast(sr.ScorePercentRank as numeric), 4) as ScorePercentRank,
        vw.ViewCount as ViewCountEcho,
        round(coalesce(vw.AvgViewsWindow, vw.AvgViewsAll), 2) as LocalAvgViews,
        tm.SecsToFirstResolution,
        tm.SecsToFirstAnswer,
        tm.SecsToLastAnswer,
        tm.SecsToLastModFromCreate,
        tf.TagCount,
        tf.HasSQLTag,
        tf.TagList,
        qo.OwnerUserId,
        qo.OwnerReputation,
        qo.OwnerLocation,
        qo.OwnerTotalBadges,
        qo.OwnerGoldBadges,
        ao.AcceptedOwnerId,
        ao.AcceptedOwnerReputation,
        ao.AcceptedOwnerTotalBadges,
        dr.DuplicateLinks,
        dr.LinkedLinks,
        crn.CloseReasonName,
        cr.FirstCloseAt,
        ra.SuggestedEditsApplied,
        ra.CloseEvents,
        coalesce(va.BountyAmountTotal,0) as BountyAmountTotal,
        case
            when q.ClosedDate is not null then 'Closed'
            when coalesce(ans.AnswerCount,0) = 0 then 'Unanswered'
            when aa.AnswerId is not null then 'Answered (Accepted)'
            else 'Answered'
        end as ResolutionStatus
    from q_posts q
    left join vote_agg va on va.PostId = q.QuestionId
    left join comment_agg ca on ca.PostId = q.QuestionId
    left join answer_stats ans on ans.QuestionId = q.QuestionId
    left join accepted_answer aa on aa.QuestionId = q.QuestionId
    left join quality_bucket qb on qb.QuestionId = q.QuestionId
    left join score_rankings sr on sr.QuestionId = q.QuestionId
    left join view_windows vw on vw.QuestionId = q.QuestionId
    left join time_metrics tm on tm.QuestionId = q.QuestionId
    left join tagged_focus tf on tf.QuestionId = q.QuestionId
    left join question_owner qo on qo.QuestionId = q.QuestionId
    left join answer_owner ao on ao.QuestionId = q.QuestionId
    left join duplicate_links dr on dr.QuestionId = q.QuestionId
    left join close_reasons cr on cr.QuestionId = q.QuestionId
    left join close_reason_names crn on crn.QuestionId = q.QuestionId
    left join recent_activity ra on ra.PostId = q.QuestionId
),
with_corr as (
    select
        f.*,
        (
            select count(*)
            from a_posts ap
            where ap.QuestionId = f.QuestionId
              and ap.AnswerScore > coalesce(f.AcceptedAnswerScore, -9999)
        ) as AnswersAboveAccepted,
        (
            select avg(cast(length(c.Text) as numeric))
            from Comments c
            where c.PostId = f.QuestionId
        ) as AvgCommentLen
    from final_set f
),
ranked as (
    select
        wc.*,
        row_number() over (order by
            (coalesce(wc.UpVotes,0) - coalesce(wc.DownVotes,0)) desc,
            wc.ViewCount desc,
            wc.AnswerCount desc,
            wc.QuestionCreation desc
        ) as GlobalRowNum
    from with_corr wc
)
select *
from ranked
where
    (
        (HasSQLTag = 1 and coalesce(OwnerLocation,'') not ilike '%unknown%')
        or (TagList ilike '%performance%' and coalesce(CloseReasonName,'') = '')
        or (AcceptedAnswerId is null and coalesce(AnswersAboveAccepted,0) > 0)
    )
    and (QuestionScore >= 0 or (Favorites > 0 and AvgCommentLen > 40))
    and (coalesce(BountyAmountTotal,0) >= 0)
    and (QuestionCreation is not null)
    and (ViewCount > 0)
order by
    GlobalRowNum
fetch first 250 rows only;