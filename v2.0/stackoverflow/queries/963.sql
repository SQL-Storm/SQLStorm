with
q_posts as (
    select p.Id as QuestionId,
           p.CreationDate as QCreated,
           p.Score as QScore,
           p.ViewCount as QViews,
           p.OwnerUserId as QOwnerId,
           p.Title,
           p.Tags,
           p.AcceptedAnswerId
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select date_trunc('year', min(CreationDate)) from Posts where PostTypeId = 1)
),
a_posts as (
    select a.Id as AnswerId,
           a.ParentId as QuestionId,
           a.OwnerUserId as AOwnerId,
           a.Score as AScore,
           a.CreationDate as ACreated
    from Posts a
    where a.PostTypeId = 2
),
user_activity as (
    select u.Id as UserId,
           u.Reputation,
           u.UpVotes,
           u.DownVotes,
           u.Views as ProfileViews,
           coalesce(u.Location, 'Unknown') as Location,
           cast(date_part('year', age(cast('2024-10-01 12:34:56' as timestamp), u.CreationDate)) as int) as AccountAgeYears,
           count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
           count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
           count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
           count(distinct p.Id) as TotalPostsAuthored
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.Location, u.CreationDate
),
question_metrics as (
    select q.QuestionId,
           q.QCreated,
           q.QScore,
           q.QViews,
           q.QOwnerId,
           q.Title,
           q.Tags,
           q.AcceptedAnswerId,
           count(a.AnswerId) as TotalAnswers,
           sum(case when a.AnswerId = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted,
           min(a.ACreated) as FirstAnswerAt,
           max(a.ACreated) as LastAnswerAt,
           avg(a.AScore) as AvgAnswerScore,
           percentile_cont(0.5) within group (order by a.AScore) as MedianAnswerScore
    from q_posts q
    left join a_posts a on a.QuestionId = q.QuestionId
    group by q.QuestionId, q.QCreated, q.QScore, q.QViews, q.QOwnerId, q.Title, q.Tags, q.AcceptedAnswerId
),
comment_stats as (
    select c.PostId,
           count(*) as CommentCount,
           sum((length(c.Text) - length(replace(c.Text, ' ', ''))) + 1) as ApproxWordCount,
           max(c.CreationDate) as LastCommentAt,
           count(*) filter (where c.Score > 0) as UpvotedComments
    from Comments c
    group by c.PostId
),
vote_rollup as (
    select v.PostId,
           count(*) filter (where v.VoteTypeId = 2) as UpVotes,
           count(*) filter (where v.VoteTypeId = 3) as DownVotes,
           count(*) filter (where v.VoteTypeId = 5) as Favorites,
           sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as BountyTotal
    from Votes v
    group by v.PostId
),
closure_info as (
    select ph.PostId,
           min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedAt,
           max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedAt,
           max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 12) as LastDeletedAt,
           string_agg(distinct crt.Name, ', ' order by crt.Name) as CloseReasons
    from PostHistory ph
    left join CloseReasonTypes crt
      on ph.PostHistoryTypeId = 10
     and cast(crt.Id as varchar) = nullif(ph.Comment, '')
    group by ph.PostId
),
dupe_links as (
    select pl.PostId as DuplicateOf,
           count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
           count(*) filter (where pl.LinkTypeId = 1) as RelatedLinks
    from PostLinks pl
    group by pl.PostId
),
tag_explode as (
    select q.QuestionId,
           unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as Tag
    from q_posts q
    where q.Tags is not null
),
tag_rank as (
    select te.QuestionId,
           te.Tag,
           dense_rank() over (partition by te.QuestionId order by lower(te.Tag)) as TagRankAlpha,
           row_number() over (partition by te.QuestionId order by length(te.Tag) desc, te.Tag) as TagRankLengthDesc
    from tag_explode te
),
owner_rank as (
    select qm.*,
           ua.Reputation as OwnerReputation,
           ua.GoldBadges,
           ua.SilverBadges,
           ua.BronzeBadges,
           ua.AccountAgeYears,
           ua.Location as OwnerLocation,
           ua.TotalPostsAuthored as OwnerPostCount
    from question_metrics qm
    left join user_activity ua on ua.UserId = qm.QOwnerId
),
answers_ranked as (
    select a.QuestionId,
           a.AnswerId,
           a.AOwnerId,
           a.AScore,
           a.ACreated,
           row_number() over (partition by a.QuestionId order by a.AScore desc nulls last, a.ACreated asc) as RN_ByScoreDesc,
           row_number() over (partition by a.QuestionId order by a.ACreated asc) as RN_ByFirst
    from a_posts a
),
top_answers as (
    select ar.QuestionId,
           max(ar.AnswerId) filter (where ar.RN_ByScoreDesc = 1) as TopAnswerId,
           max(ar.AOwnerId) filter (where ar.RN_ByScoreDesc = 1) as TopAnswerOwnerId,
           max(ar.AScore) filter (where ar.RN_ByScoreDesc = 1) as TopAnswerScore,
           max(ar.AnswerId) filter (where ar.RN_ByFirst = 1) as FirstAnswerId,
           max(ar.ACreated) filter (where ar.RN_ByFirst = 1) as FirstAnswerCreated
    from answers_ranked ar
    group by ar.QuestionId
),
owner_vs_top_answerer as (
    select ta.QuestionId,
           ta.TopAnswerOwnerId,
           ua.Reputation as TopAnswererReputation,
           ua.AccountAgeYears as TopAnswererAgeYears,
           ua.Location as TopAnswererLocation,
           case when ta.TopAnswerOwnerId is not null and ta.TopAnswerOwnerId = oq.QOwnerId then 1 else 0 end as OwnerIsTopAnswerer
    from top_answers ta
    left join owner_rank oq on oq.QuestionId = ta.QuestionId
    left join user_activity ua on ua.UserId = ta.TopAnswerOwnerId
),
activity_windows as (
    select p.Id as PostId,
           p.PostTypeId,
           p.CreationDate,
           p.LastActivityDate,
           extract(epoch from (coalesce(p.LastActivityDate, p.CreationDate) - p.CreationDate)) as LifetimeSeconds,
           sum(p.Score) over (partition by p.PostTypeId order by p.CreationDate rows between unbounded preceding and current row) as CumScoreByType,
           avg(p.ViewCount) over (partition by p.PostTypeId) as AvgViewsByType
    from Posts p
),
question_activity as (
    select aw.PostId as QuestionId,
           aw.LifetimeSeconds,
           aw.CumScoreByType,
           aw.AvgViewsByType
    from activity_windows aw
    where aw.PostTypeId = 1
),
complex_pred as (
    select qm.QuestionId,
           (coalesce(qm.QScore, 0) * 1.0 / nullif(qm.TotalAnswers, 0)) as ScorePerAnswer,
           (case
               when qm.TotalAnswers = 0 then 0
               when qm.HasAccepted = 1 then 1
               else 0.5
            end) as AcceptanceSignal,
           (length(coalesce(qm.Title,'')) + coalesce(position('?' in qm.Title), 0)) as TitleComplexity,
           (case when qm.QViews is null or qm.QViews = 0 then 1 else ln(qm.QViews + 1) end) as LogViewsPlus1
    from question_metrics qm
),
final_agg as (
    select
        oq.QuestionId,
        oq.QCreated,
        oq.QScore,
        oq.QViews,
        oq.Title,
        oq.Tags,
        oq.TotalAnswers,
        oq.HasAccepted,
        oq.FirstAnswerAt,
        oq.LastAnswerAt,
        oq.AvgAnswerScore,
        oq.MedianAnswerScore,
        coalesce(cs.CommentCount, 0) as CommentCount,
        coalesce(cs.ApproxWordCount, 0) as CommentApproxWords,
        cs.LastCommentAt,
        coalesce(vr.UpVotes, 0) as UpVotes,
        coalesce(vr.DownVotes, 0) as DownVotes,
        coalesce(vr.Favorites, 0) as Favorites,
        coalesce(vr.BountyTotal, 0) as BountyTotal,
        ci.FirstClosedAt,
        ci.LastReopenedAt,
        ci.LastDeletedAt,
        ci.CloseReasons,
        coalesce(dl.DuplicateLinks, 0) as DuplicateLinks,
        coalesce(dl.RelatedLinks, 0) as RelatedLinks,
        orq.OwnerReputation,
        orq.GoldBadges,
        orq.SilverBadges,
        orq.BronzeBadges,
        orq.AccountAgeYears,
        orq.OwnerLocation,
        orq.OwnerPostCount,
        ta.TopAnswerId,
        ta.TopAnswerScore,
        ta.FirstAnswerId,
        ta.FirstAnswerCreated,
        oxta.TopAnswererReputation,
        oxta.TopAnswererAgeYears,
        oxta.TopAnswererLocation,
        oxta.OwnerIsTopAnswerer,
        qa.LifetimeSeconds,
        qa.CumScoreByType,
        qa.AvgViewsByType,
        cp.ScorePerAnswer,
        cp.AcceptanceSignal,
        cp.TitleComplexity,
        cp.LogViewsPlus1
    from owner_rank orq
    join question_metrics oq on oq.QuestionId = orq.QuestionId
    left join comment_stats cs on cs.PostId = oq.QuestionId
    left join vote_rollup vr on vr.PostId = oq.QuestionId
    left join closure_info ci on ci.PostId = oq.QuestionId
    left join dupe_links dl on dl.DuplicateOf = oq.QuestionId
    left join top_answers ta on ta.QuestionId = oq.QuestionId
    left join owner_vs_top_answerer oxta on oxta.QuestionId = oq.QuestionId
    left join question_activity qa on qa.QuestionId = oq.QuestionId
    left join complex_pred cp on cp.QuestionId = oq.QuestionId
),
tag_pivots as (
    select
        tr.QuestionId,
        max(case when tr.TagRankAlpha = 1 then tr.Tag end) as TagAlpha1,
        max(case when tr.TagRankAlpha = 2 then tr.Tag end) as TagAlpha2,
        max(case when tr.TagRankAlpha = 3 then tr.Tag end) as TagAlpha3,
        max(case when tr.TagRankLengthDesc = 1 then tr.Tag end) as LongestTag
    from tag_rank tr
    group by tr.QuestionId
),
scored as (
    select
        fa.*,
        tp.TagAlpha1,
        tp.TagAlpha2,
        tp.TagAlpha3,
        tp.LongestTag,
        (
            coalesce(fa.UpVotes,0) - coalesce(fa.DownVotes,0)
            + coalesce(fa.Favorites,0) * 0.25
            + coalesce(fa.BountyTotal,0) * 0.001
            + coalesce(fa.QScore,0) * 0.5
            + coalesce(fa.ScorePerAnswer,0) * 2
            + coalesce(fa.AcceptanceSignal,0) * 5
            + case when fa.HasAccepted = 1 then 1 else 0 end
            + case when fa.DuplicateLinks > 0 then -2 else 0 end
            + case when fa.FirstClosedAt is not null then -3 else 0 end
            - coalesce(fa.CommentCount,0) * 0.02
            + greatest(least(fa.LogViewsPlus1, 10), 0)
        ) as CompositeScore
    from final_agg fa
    left join tag_pivots tp on tp.QuestionId = fa.QuestionId
),
ranked AS (
    select
        s.QuestionId,
        s.QCreated,
        s.Title,
        coalesce(s.Tags, '[]') as TagsRaw,
        s.TagAlpha1,
        s.TagAlpha2,
        s.TagAlpha3,
        s.LongestTag,
        s.QScore,
        s.QViews,
        s.UpVotes,
        s.DownVotes,
        s.Favorites,
        s.BountyTotal,
        s.TotalAnswers,
        s.HasAccepted,
        s.FirstAnswerAt,
        s.LastAnswerAt,
        s.AvgAnswerScore,
        s.MedianAnswerScore,
        s.CommentCount,
        s.CommentApproxWords,
        s.LastCommentAt,
        s.OwnerReputation,
        s.GoldBadges,
        s.SilverBadges,
        s.BronzeBadges,
        s.AccountAgeYears,
        s.OwnerLocation,
        s.OwnerPostCount,
        s.TopAnswerId,
        s.TopAnswerScore,
        s.FirstAnswerId,
        s.FirstAnswerCreated,
        s.TopAnswererReputation,
        s.TopAnswererAgeYears,
        s.TopAnswererLocation,
        s.OwnerIsTopAnswerer,
        s.LifetimeSeconds,
        s.CumScoreByType,
        s.AvgViewsByType,
        s.ScorePerAnswer,
        s.AcceptanceSignal,
        s.TitleComplexity,
        s.LogViewsPlus1,
        s.CompositeScore,
        rank() over (order by s.CompositeScore desc nulls last, s.QViews desc nulls last, s.QCreated desc) as RankByComposite,
        ntile(10) over (order by s.CompositeScore desc nulls last) as DecileByComposite,
        row_number() over (order by s.CompositeScore desc nulls last, s.QCreated desc) as rn_for_limit
    from scored s
    where (
        s.CompositeScore is not null
        or s.TotalAnswers > 0
        or (s.UpVotes + s.DownVotes) is not null
    )
)
select
    QuestionId,
    QCreated,
    Title,
    TagsRaw,
    TagAlpha1,
    TagAlpha2,
    TagAlpha3,
    LongestTag,
    QScore,
    QViews,
    UpVotes,
    DownVotes,
    Favorites,
    BountyTotal,
    TotalAnswers,
    HasAccepted,
    FirstAnswerAt,
    LastAnswerAt,
    AvgAnswerScore,
    MedianAnswerScore,
    CommentCount,
    CommentApproxWords,
    LastCommentAt,
    OwnerReputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AccountAgeYears,
    OwnerLocation,
    OwnerPostCount,
    TopAnswerId,
    TopAnswerScore,
    FirstAnswerId,
    FirstAnswerCreated,
    TopAnswererReputation,
    TopAnswererAgeYears,
    TopAnswererLocation,
    OwnerIsTopAnswerer,
    LifetimeSeconds,
    CumScoreByType,
    AvgViewsByType,
    ScorePerAnswer,
    AcceptanceSignal,
    TitleComplexity,
    LogViewsPlus1,
    CompositeScore,
    RankByComposite,
    DecileByComposite
from ranked
where rn_for_limit <= 1000
order by CompositeScore desc nulls last, QCreated desc;