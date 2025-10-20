with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
),
LatestPostHistoryPerPost as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment
    from (
        select
            ph.*,
            row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
        from PostHistory ph
    ) ph
    where ph.rn = 1
),
HighScoreAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 2 and p.Score > 10
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.CreationDate as QuestionCreation,
        q.Score as QuestionScore,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.Tags, q.CreationDate, q.Score
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
        sum(v.BountyAmount) over (partition by u.Id order by v.CreationDate rows between unbounded preceding and current row) as CumulativeBountyGiven
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Votes v on v.UserId = u.Id and v.VoteTypeId = 8
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    inner join Posts p1 on pl.PostId = p1.Id
    inner join Posts p2 on pl.RelatedPostId = p2.Id
    where pl.LinkTypeId = 3
),
UserBadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges
    from Badges
    group by UserId
)
select
    qas.QuestionId,
    qas.Title,
    qas.Tags,
    qas.QuestionCreation,
    qas.QuestionScore,
    qas.AnswerCount,
    qas.MaxAnswerScore,
    round(cast(qas.AvgAnswerScore as numeric), 2) as AvgAnswerScore,
    lub.BadgeName as LatestBadge,
    lub.Class as LatestBadgeClass,
    lub.DisplayName as BadgeUser,
    hsa.Id as TopAnswerId,
    hsa.Score as TopAnswerScore,
    hsa.OwnerName as TopAnswerOwner,
    ua.CumulativeQuestions,
    ua.CumulativeAnswers,
    ua.CumulativeBountyGiven,
    dpl.RelatedPostId as DuplicateOf,
    dpl.RelatedPostTitle as DuplicateOfTitle,
    case
        when qas.AnswerCount = 0 then 'Unanswered'
        when qas.MaxAnswerScore > 50 then 'Highly Answered'
        else 'Moderately Answered'
    end as AnswerStatus,
    coalesce(phc.Comment, 'No closure') as ClosureReason,
    length(qas.Title) + coalesce((select max(length(Body)) from Posts where ParentId = qas.QuestionId), 0) as TitlePlusLongestAnswerBodyLength
from QuestionAnswerStats qas
left join RecursiveUserBadges lub on lub.UserId = (select OwnerUserId from Posts where Id = qas.QuestionId) and lub.rn = 1
left join HighScoreAnswers hsa on hsa.ParentId = qas.QuestionId and hsa.rn = 1
left join UserActivityWindow ua on ua.Id = (select OwnerUserId from Posts where Id = qas.QuestionId)
left join DuplicateLinks dpl on dpl.PostId = qas.QuestionId
left join LatestPostHistoryPerPost phc on phc.PostId = qas.QuestionId and phc.PostHistoryTypeId = 10
where qas.QuestionCreation > (cast('2024-10-01' as date) - interval '1 year')
  and (qas.AnswerCount > 0 or dpl.PostId is not null)
order by qas.QuestionScore desc
limit 100;