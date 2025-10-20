with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date >= date '2023-01-01' or b.Date is null
),
TopBadges as (
    select UserId, BadgeName, Class, BadgeRank
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostScores as (
    select 
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.FavoriteCount, 0) as FavoriteCount,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as UserPostRank
    from Posts p
    where p.PostTypeId in (1, 2)
),
UserActivity as (
    select 
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(coalesce(p.Score,0)) as TotalScore,
        sum(coalesce(p.ViewCount,0)) as TotalViews,
        max(p.CreationDate) as LastPostDate,
        count(distinct c.Id) as TotalComments,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.Score, q.ViewCount, q.AcceptedAnswerId
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserReputationWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        sum(case when b.Class = 1 then 100 else 0 end) over (order by u.Reputation desc rows between unbounded preceding and current row) as GoldBadgeSum,
        sum(case when b.Class = 2 then 10 else 0 end) over (order by u.Reputation desc rows between unbounded preceding and current row) as SilverBadgeSum,
        sum(case when b.Class = 3 then 1 else 0 end) over (order by u.Reputation desc rows between unbounded preceding and current row) as BronzeBadgeSum
    from Users u
    left join Badges b on u.Id = b.UserId
),
ClosedQuestionsWithReasons as (
    select 
        p.Id,
        p.Title,
        p.ClosedDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where p.PostTypeId = 1 and p.ClosedDate is not null
),
UserCommentActivity as (
    select 
        c.UserId,
        u.DisplayName,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct substring(c.Text from 1 for 20), ' | ') as SampleComments
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
)
select 
    ua.Id as UserId,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    ua.TotalViews,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ts.BadgeName as TopBadge1,
    ts2.BadgeName as TopBadge2,
    ts3.BadgeName as TopBadge3,
    qa.QuestionId,
    qa.Title as QuestionTitle,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    qa.HasAcceptedAnswer,
    dup.PostTitle as DuplicatePostTitle,
    dup.RelatedPostTitle as DuplicateRelatedPostTitle,
    cr.CloseReasonName,
    uca.CommentCount,
    uca.LastCommentDate,
    uca.SampleComments,
    urw.GoldBadgeSum,
    urw.SilverBadgeSum,
    urw.BronzeBadgeSum
from UserActivity ua
left join TopBadges ts on ts.UserId = ua.Id and ts.BadgeRank = 1
left join TopBadges ts2 on ts2.UserId = ua.Id and ts2.BadgeRank = 2
left join TopBadges ts3 on ts3.UserId = ua.Id and ts3.BadgeRank = 3
left join QuestionAnswerStats qa on qa.QuestionOwner = ua.Id
left join DuplicateLinks dup on dup.PostId = qa.QuestionId
left join ClosedQuestionsWithReasons cr on cr.Id = qa.QuestionId
left join UserCommentActivity uca on uca.UserId = ua.Id
left join UserReputationWindow urw on urw.Id = ua.Id
where ua.TotalPosts > 10 and (qa.AnswerCount > 5 or qa.HasAcceptedAnswer = 1)
group by
    ua.Id,
    ua.DisplayName,
    ua.TotalPosts,
    ua.TotalScore,
    ua.TotalViews,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ts.BadgeName,
    ts2.BadgeName,
    ts3.BadgeName,
    qa.QuestionId,
    qa.Title,
    qa.AnswerCount,
    qa.AvgAnswerScore,
    qa.MaxAnswerScore,
    qa.HasAcceptedAnswer,
    dup.PostTitle,
    dup.RelatedPostTitle,
    cr.CloseReasonName,
    uca.CommentCount,
    uca.LastCommentDate,
    uca.SampleComments,
    urw.GoldBadgeSum,
    urw.SilverBadgeSum,
    urw.BronzeBadgeSum
order by ua.TotalScore desc, qa.AnswerCount desc
limit 100;