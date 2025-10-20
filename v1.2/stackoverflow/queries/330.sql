with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (order by t.Count desc, t.TagName) as TagRank,
        t.ExcerptPostId
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserPostStats as (
    select
        u.Id as UserId,
        count(case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(case when p.PostTypeId = 2 then p.Id end) as Answers,
        avg(case when p.PostTypeId in (1,2) then p.Score end) as AvgPostScore,
        max(case when p.PostTypeId in (1,2) then p.Score end) as MaxPostScore,
        sum(case when p.PostTypeId = 1 then p.ViewCount else 0 end) as TotalQuestionViews,
        count(distinct case when p.AcceptedAnswerId is not null then p.Id end) as QuestionsWithAcceptedAnswer,
        u.Reputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.Reputation
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        count(c.Id) as CommentCount,
        string_agg(distinct u.DisplayName, ', ') filter (where u.DisplayName is not null) as Commenters,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = c.UserId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(case when p.PostTypeId = 1 then p.Id end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(case when p.PostTypeId = 2 then p.Id end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        sum(case when p.PostTypeId in (1,2) then p.Score else 0 end) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        u.DisplayName as OwnerName
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    left join Users u on u.Id = p1.OwnerUserId
    where pl.LinkTypeId = 3
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        p.Title,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId,
        u.DisplayName as CloserName
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    inner join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
QuestionsWithAcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        a.Id as AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerOwner,
        u.DisplayName as AcceptedAnswerOwnerName,
        (select count(*) from Comments c where c.PostId = a.Id) as AcceptedAnswerCommentCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
)
select
    rtc.TagRank,
    rtc.TagName,
    rtc.Count as TagUsageCount,
    rtc.AnswerCount,
    rtc.ViewCount,
    rtc.Score as TagExcerptScore,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    coalesce(ups.Questions, 0) as UserQuestions,
    coalesce(ups.Answers, 0) as UserAnswers,
    coalesce(ups.AvgPostScore, 0) as UserAvgPostScore,
    coalesce(ups.MaxPostScore, 0) as UserMaxPostScore,
    coalesce(ups.TotalQuestionViews, 0) as UserTotalQuestionViews,
    coalesce(ups.QuestionsWithAcceptedAnswer, 0) as UserQuestionsWithAcceptedAnswer,
    tpc.Title as TopQuestionTitle,
    tpc.Score as TopQuestionScore,
    tpc.ViewCount as TopQuestionViews,
    tpc.CommentCount as TopQuestionComments,
    tpc.Commenters as TopQuestionCommenters,
    da.PostTitle as DuplicatePostTitle,
    da.RelatedPostTitle as DuplicateOf,
    da.CreationDate as DuplicateLinkDate,
    da.OwnerName as DuplicatePostOwner,
    cqwr.Title as ClosedQuestionTitle,
    cqwr.CloseDate,
    cqwr.CloseReason,
    cqwr.CloserName,
    qaas.AcceptedAnswerScore,
    qaas.AcceptedAnswerOwnerName,
    qaas.AcceptedAnswerCommentCount
from RecursiveTagCounts rtc
left join UserBadgeStats ubs on ubs.UserId = (
    select p.OwnerUserId from Posts p where p.Id = rtc.ExcerptPostId limit 1
)
left join UserPostStats ups on ups.UserId = (
    select p.OwnerUserId from Posts p where p.Id = rtc.ExcerptPostId limit 1
)
left join TopPostsWithComments tpc on tpc.OwnerUserId = ups.UserId and tpc.PostRank = 1
left join DuplicateLinks da on da.PostId = rtc.ExcerptPostId
left join ClosedQuestionsWithReasons cqwr on cqwr.PostId = rtc.ExcerptPostId
left join QuestionsWithAcceptedAnswerStats qaas on qaas.QuestionId = rtc.ExcerptPostId
where rtc.TagRank <= 50
order by rtc.TagRank, ups.Reputation desc
limit 100;