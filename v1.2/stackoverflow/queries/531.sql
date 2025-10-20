with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date is not null
),
TopBadges as (
    select UserId, BadgeName, Class, Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        coalesce(a.AverageAnswerScore, 0) as AverageAnswerScore
    from Posts p
    left join (
        select
            ParentId,
            count(*) as AnswerCount,
            max(Score) as MaxAnswerScore,
            avg(Score) as AverageAnswerScore
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on p.Id = a.ParentId
    where p.PostTypeId = 1
),
RankedQuestions as (
    select
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.MaxAnswerScore,
        q.AverageAnswerScore,
        row_number() over (order by q.QuestionScore desc, q.ViewCount desc) as QuestionRank
    from QuestionAnswerStats q
),
-- Replace DISTINCT-in-window by counting distinct values in an aggregated subquery per user and then joining.
UserActivityCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(qs.QuestionsAsked, 0) as QuestionsAsked,
        coalesce(asg.AnswersGiven, 0) as AnswersGiven,
        coalesce(cs.CommentsMade, 0) as CommentsMade
    from Users u
    left join (
        select OwnerUserId, count(distinct Id) as QuestionsAsked
        from Posts
        where PostTypeId = 1
        group by OwnerUserId
    ) qs on u.Id = qs.OwnerUserId
    left join (
        select OwnerUserId, count(distinct Id) as AnswersGiven
        from Posts
        where PostTypeId = 2
        group by OwnerUserId
    ) asg on u.Id = asg.OwnerUserId
    left join (
        select UserId, count(distinct Id) as CommentsMade
        from Comments
        group by UserId
    ) cs on u.Id = cs.UserId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    join Posts p1 on pl.PostId = p1.Id
    join Posts p2 on pl.RelatedPostId = p2.Id
    where pl.LinkTypeId = 3
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        ph.CreationDate as ClosedDate,
        crt.Name as CloseReason,
        ph.UserId as CloserUserId,
        u.DisplayName as CloserDisplayName
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    join Posts p on ph.PostId = p.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId = 10
),
UserReputationRank as (
    select
        Id,
        DisplayName,
        Reputation,
        rank() over (order by Reputation desc) as ReputationRank
    from Users
),
AnswerWithAcceptedFlag as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
        u.DisplayName as AnswerOwner,
        u.Reputation as AnswerOwnerReputation
    from Posts a
    join Posts q on a.ParentId = q.Id
    left join Users u on a.OwnerUserId = u.Id
    where a.PostTypeId = 2
),
FinalResult as (
    select
        rq.QuestionRank,
        rq.QuestionId,
        rq.Title as QuestionTitle,
        rq.OwnerUserId,
        u.DisplayName as QuestionOwner,
        rq.CreationDate as QuestionCreationDate,
        rq.QuestionScore,
        rq.ViewCount,
        rq.AnswerCount,
        rq.MaxAnswerScore,
        rq.AverageAnswerScore,
        ab.AnswerId,
        ab.Score as AnswerScore,
        ab.IsAccepted,
        ab.AnswerOwner,
        ab.AnswerOwnerReputation,
        cb.ClosedDate,
        cb.CloseReason,
        cb.CloserDisplayName,
        string_agg(tb.BadgeName || ' (' || case tb.Class when 1 then 'Gold' when 2 then 'Silver' else 'Bronze' end || ')', ', ') filter (where tb.BadgeName is not null) as TopBadges,
        ur.ReputationRank,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        dl.DuplicateTitle,
        dl.LinkCreationDate as DuplicateLinkDate
    from RankedQuestions rq
    left join Users u on rq.OwnerUserId = u.Id
    left join AnswerWithAcceptedFlag ab on rq.QuestionId = ab.QuestionId
    left join ClosedQuestionsWithReasons cb on rq.QuestionId = cb.PostId
    left join TopBadges tb on u.Id = tb.UserId
    left join UserReputationRank ur on u.Id = ur.Id
    left join UserActivityCounts ua on u.Id = ua.UserId
    left join DuplicateLinks dl on rq.QuestionId = dl.PostId
    group by
        rq.QuestionRank, rq.QuestionId, rq.Title, rq.OwnerUserId, u.DisplayName, rq.CreationDate, rq.QuestionScore, rq.ViewCount, rq.AnswerCount, rq.MaxAnswerScore, rq.AverageAnswerScore,
        ab.AnswerId, ab.Score, ab.IsAccepted, ab.AnswerOwner, ab.AnswerOwnerReputation,
        cb.ClosedDate, cb.CloseReason, cb.CloserDisplayName,
        ur.ReputationRank,
        ua.QuestionsAsked, ua.AnswersGiven, ua.CommentsMade,
        dl.DuplicateTitle, dl.LinkCreationDate
)
select
    QuestionRank,
    QuestionId,
    QuestionTitle,
    QuestionOwner,
    QuestionCreationDate,
    QuestionScore,
    ViewCount,
    AnswerCount,
    MaxAnswerScore,
    AverageAnswerScore,
    AnswerId,
    AnswerScore,
    IsAccepted,
    AnswerOwner,
    AnswerOwnerReputation,
    ClosedDate,
    CloseReason,
    CloserDisplayName,
    coalesce(TopBadges, 'No Badges') as TopBadges,
    ReputationRank,
    QuestionsAsked,
    AnswersGiven,
    CommentsMade,
    DuplicateTitle,
    DuplicateLinkDate,
    length(QuestionTitle) + coalesce(AnswerScore, 0) * 10 - coalesce(AnswerOwnerReputation, 0)/1000.0 as ComplexScore,
    case when ClosedDate is not null then 'Closed' else 'Open' end as PostStatus,
    case when AnswerScore is null then 'No Answers' when IsAccepted = 1 then 'Accepted Answer' else 'Unaccepted Answer' end as AnswerStatus
from FinalResult
where QuestionRank <= 100
order by ComplexScore desc, QuestionRank asc
limit 100;