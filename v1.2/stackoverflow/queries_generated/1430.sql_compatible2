with RankedAnswers as (
    select 
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        a.OwnerUserId,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    where a.PostTypeId = 2
), QuestionDetails as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        u.Reputation,
        coalesce(q.ViewCount, 0) as ViewCount,
        case 
            when q.ClosedDate is null then extract(epoch from (timestamp '2024-10-01 12:34:56' - q.CreationDate))/86400.0 
            else extract(epoch from (q.ClosedDate - q.CreationDate))/86400.0 
        end as DaysOpen,
        q.Tags,
        q.AcceptedAnswerId,
        q.AnswerCount
    from Posts q
    left join Users u on q.OwnerUserId = u.Id
    where q.PostTypeId = 1
), CloseReasonsSummary as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
), AcceptedAnswersWithUser AS (
    select 
        p.Id as AnswerId,
        p.ParentId as QuestionId,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        p.Score as AnswerScore,
        p.CreationDate as AnswerCreationDate
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2
), BadgeCounts as (
    select
        UserId,
        count(case when Class = 1 then 1 end) as GoldBadges,
        count(case when Class = 2 then 1 end) as SilverBadges,
        count(case when Class = 3 then 1 end) as BronzeBadges
    from Badges
    group by UserId
), RecentCommentsRanked as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        c.Text as CommentText,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as RecentRank
    from Comments c
    where c.PostId is not null
), PostsWithLatestComment as (
    select
        p.Id,
        p.Title,
        p.Tags,
        rc.CommentText as LatestCommentText,
        rc.CommentDate as LatestCommentDate
    from Posts p
    left join RecentCommentsRanked rc on p.Id = rc.PostId and rc.RecentRank = 1
), HighActivityQuestions AS (
    select q.QuestionId, q.ViewCount, q.AnswerCount
    from QuestionDetails q
    where q.ViewCount > 10000 and q.AnswerCount >= 5
), ActiveButNoAccepted as (
    select q.QuestionId, q.Title, q.AnswerCount, q.ViewCount, q.DaysOpen, q.OwnerName, q.Reputation, q.OwnerUserId
    from QuestionDetails q
    left join Posts acc on q.AcceptedAnswerId = acc.Id
    where acc.Id is null and q.AnswerCount > 3 and q.ViewCount > 5000
)
select
    q.QuestionId,
    q.Title,
    q.OwnerName,
    coalesce(b.GoldBadges,0) as GoldBadges,
    coalesce(b.SilverBadges,0) as SilverBadges,
    coalesce(b.BronzeBadges,0) as BronzeBadges,
    q.Reputation as OwnerReputation,
    q.QuestionCreationDate as QuestionCreatedAt,
    q.Tags,
    q.AnswerCount,
    q.ViewCount,
    round(q.DaysOpen, 2) as DaysOpen,
    crs.CloseReason,
    aa.AnswerId as AcceptedAnswerId,
    aa.AnswerOwnerName,
    aa.AnswerOwnerReputation,
    aa.AnswerScore,
    aa.AnswerCreationDate,
    ra.AnswerId as TopAnswerId,
    ra.AnswerScore as TopAnswerScore,
    ra.AnswerCreationDate as TopAnswerDate,
    lc.LatestCommentText,
    lc.LatestCommentDate
from QuestionDetails q
left join BadgeCounts b on q.OwnerUserId = b.UserId
left join CloseReasonsSummary crs on q.QuestionId = crs.PostId
left join AcceptedAnswersWithUser aa on q.AcceptedAnswerId = aa.AnswerId
left join RankedAnswers ra on ra.QuestionId = q.QuestionId and ra.AnswerRank = 1
left join PostsWithLatestComment lc on q.QuestionId = lc.Id 
where q.Reputation > (
    select avg(u.Reputation)*0.8 from Users u where u.Reputation is not null
)
and (
    ra.AnswerScore is not null and ra.AnswerScore > 5
)
and (coalesce(q.Tags, '') || ' ') like '%<sql>%'
and (
    coalesce(b.GoldBadges,0) + coalesce(b.SilverBadges,0) + coalesce(b.BronzeBadges,0)
) > 3
and not exists (
    select 1 
    from Votes v
    where v.PostId = q.QuestionId 
    and v.VoteTypeId = 4
    and v.CreationDate > q.QuestionCreationDate
)
union
select
    a.QuestionId,
    '[Unaccepted but Active Hot Question]' as Title,
    'N/A' as OwnerName,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as OwnerReputation,
    (timestamp '2024-10-01 12:34:56' - interval '365 years') as QuestionCreatedAt,
    '' as Tags,
    a.AnswerCount,
    a.ViewCount,
    0.0 as DaysOpen,
    null as CloseReason,
    null as AcceptedAnswerId,
    null as AnswerOwnerName,
    null as AnswerOwnerReputation,
    null as AnswerScore,
    null as AnswerCreationDate,
    null as TopAnswerId,
    null as TopAnswerScore,
    null as TopAnswerDate,
    null as LatestCommentText,
    null as LatestCommentDate
from ActiveButNoAccepted a
order by DaysOpen desc NULLS LAST, AnswerCount desc, ViewCount desc
limit 100;