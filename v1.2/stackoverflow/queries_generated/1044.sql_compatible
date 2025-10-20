with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Name) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date > date '2020-01-01'
),
TopBadges as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        count(distinct a.Id) as AnswersCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        min(a.Score) as MinAnswerScore,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoreAnswers
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.OwnerUserId
),
RecentCommentsOnTopQuestions as (
    select
        c.Id as CommentId,
        c.PostId,
        c.UserId,
        u.DisplayName,
        c.CreationDate,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as RecentCommentRank
    from Comments c
    inner join Posts p on p.Id = c.PostId and p.PostTypeId = 1
    left join Users u on u.Id = c.UserId
    where p.Score > 50
),
PostHistoryEdits as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        max(ph.CreationDate) as LastEditDate,
        bool_or(ph.PostHistoryTypeId = 10) as WasClosed,
        bool_or(ph.PostHistoryTypeId = 11) as WasReopened
    from PostHistory ph
    group by ph.PostId
),
LinkedDuplicates as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where p1.PostTypeId = 1 and p2.PostTypeId = 1
),
HighReputationActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) as PostsCount,
        row_number() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate > (date '2024-10-01' - interval '1 year')
    where u.Reputation > 5000
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(p.PostsCount,0) as PostsLastYear,
        coalesce(b.BadgesCount,0) as BadgesCount,
        coalesce(c.CommentsCount,0) as CommentsCount,
        case when u.LastAccessDate > (date '2024-10-01' - interval '30 day') then 'Active' else 'Inactive' end as ActivityStatus
    from Users u
    left join (
        select OwnerUserId, count(*) as PostsCount
        from Posts
        where CreationDate > (date '2024-10-01' - interval '1 year')
        group by OwnerUserId
    ) p on p.OwnerUserId = u.Id
    left join (
        select UserId, count(*) as BadgesCount
        from Badges
        group by UserId
    ) b on b.UserId = u.Id
    left join (
        select UserId, count(*) as CommentsCount
        from Comments
        group by UserId
    ) c on c.UserId = u.Id
)
select
    qas.QuestionId,
    qas.Title as QuestionTitle,
    u.DisplayName as QuestionOwner,
    u.Reputation as OwnerReputation,
    qas.AnswersCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    qas.HighScoreAnswers,
    phe.EditCount,
    phe.LastEditDate,
    phe.WasClosed,
    phe.WasReopened,
    string_agg(concat_ws(' (Class:', tb.Class, ') ', tb.BadgeName), '; ' ORDER BY tb.Class, tb.BadgeName) as TopBadges,
    du.RelatedPostId as DuplicateOfQuestionId,
    du.RelatedPostTitle as DuplicateOfQuestionTitle,
    coalesce(rc.RecentCommentCount, 0) as RecentCommentsCount,
    ua.PostsLastYear,
    ua.BadgesCount,
    ua.CommentsCount,
    ua.ActivityStatus
from QuestionAnswerStats qas
left join Users u on u.Id = qas.OwnerUserId
left join PostHistoryEdits phe on phe.PostId = qas.QuestionId
left join TopBadges tb on tb.UserId = qas.OwnerUserId
left join LinkedDuplicates du on du.PostId = qas.QuestionId
left join (
    select PostId, count(*) as RecentCommentCount
    from RecentCommentsOnTopQuestions
    where RecentCommentRank <= 3
    group by PostId
) rc on rc.PostId = qas.QuestionId
left join UserActivitySummary ua on ua.UserId = qas.OwnerUserId
where qas.AnswersCount > 5
and (phe.EditCount > 2 or phe.WasClosed = true)
group by
    qas.QuestionId,
    qas.Title,
    u.DisplayName,
    u.Reputation,
    qas.AnswersCount,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.MinAnswerScore,
    qas.HighScoreAnswers,
    phe.EditCount,
    phe.LastEditDate,
    phe.WasClosed,
    phe.WasReopened,
    du.RelatedPostId,
    du.RelatedPostTitle,
    rc.RecentCommentCount,
    ua.PostsLastYear,
    ua.BadgesCount,
    ua.CommentsCount,
    ua.ActivityStatus
order by qas.AnswersCount desc, qas.MaxAnswerScore desc
limit 50;