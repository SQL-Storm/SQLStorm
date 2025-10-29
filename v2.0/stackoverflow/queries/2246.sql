with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
LatestUserPosts as (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        case when p.PostTypeId = 1 then 'Question'
             when p.PostTypeId = 2 then 'Answer'
             when p.PostTypeId = 3 then 'Wiki'
             else 'Other'
        end as PostTypeName
    from Posts p
    where p.OwnerUserId is not null
    order by p.OwnerUserId, p.CreationDate desc
),
UserActivityScores as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(sum(case when p.PostTypeId = 1 then p.Score else 0 end), 0) as TotalQuestionScore,
        coalesce(sum(case when p.PostTypeId = 2 then p.Score else 0 end), 0) as TotalAnswerScore,
        coalesce(sum(case when ph.PostId = p.Id then 1 else 0 end), 0) as EditCount,
        coalesce(sum(case when c.PostId = p.Id then 1 else 0 end), 0) as CommentCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as UpVotesOnPosts,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as DownVotesOnPosts
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId in (4,5,6)
    left join Comments c on p.Id = c.PostId
    left join Votes v on p.Id = v.PostId
    group by u.Id, u.DisplayName
),
DuplicateQuestionLinks as (
    select 
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle
    from PostLinks pl
    inner join Posts p1 on pl.PostId = p1.Id and p1.PostTypeId = 1
    inner join Posts p2 on pl.RelatedPostId = p2.Id and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
AnswerWindowStats as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score,
        a.CreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
        count(*) over (partition by a.ParentId) as TotalAnswers
    from Posts a
    where a.PostTypeId = 2
),
HighActivityUsers as (
    select ua.UserId, ua.DisplayName, ua.TotalAnswerScore + ua.TotalQuestionScore as TotalScore,
        ua.EditCount, ua.CommentCount, ua.UpVotesOnPosts, ua.DownVotesOnPosts,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges
    from UserActivityScores ua
    left join Badges b on ua.UserId = b.UserId
    group by ua.UserId, ua.DisplayName, ua.TotalAnswerScore, ua.TotalQuestionScore, ua.EditCount, ua.CommentCount, ua.UpVotesOnPosts, ua.DownVotesOnPosts
    having (ua.TotalAnswerScore + ua.TotalQuestionScore) > 1000 and count(distinct b.Id) filter (where b.Class = 1) >= 1
)
select
    hu.UserId,
    hu.DisplayName,
    hu.TotalScore,
    hu.EditCount,
    hu.CommentCount,
    hu.UpVotesOnPosts,
    hu.DownVotesOnPosts,
    hu.GoldBadges,
    hu.SilverBadges,
    hu.BronzeBadges,
    lup.PostId as LatestPostId,
    lup.PostTypeName as LatestPostType,
    lup.Title as LatestPostTitle,
    lup.Tags,
    dup.DuplicateQuestionId,
    dup.OriginalQuestionId,
    dup.DuplicateTitle,
    dup.OriginalTitle,
    aws.AnswerId,
    aws.QuestionId,
    aws.Score as AnswerScore,
    aws.AnswerRank,
    aws.TotalAnswers,
    case
        when strpos(lower(lup.Title), 'error') > 0 then 'Contains keyword error'
        when lup.CreationDate < cast('2024-10-01 12:34:56' as timestamp) - interval '365 days' then 'Old Post'
        when aws.AnswerRank = 1 then 'Top Answer'
        else 'Standard'
    end as PostClassification,
    coalesce((select max(p2.Score) from Posts p2 where p2.OwnerUserId = hu.UserId and p2.CreationDate > lup.CreationDate), 0) as MaxLaterPostScore,
    coalesce((select count(*) from Posts p3 where p3.OwnerUserId = hu.UserId and p3.Tags like '%<sql>%'),0) as SqlTagPostCount
from HighActivityUsers hu
left join LatestUserPosts lup on hu.UserId = lup.OwnerUserId
left join DuplicateQuestionLinks dup on lup.PostId = dup.DuplicateQuestionId
left join AnswerWindowStats aws on aws.QuestionId = lup.PostId and aws.AnswerRank = 1
where 
    (lup.Tags is not null and lup.Tags like '%<sql>%')
    or dup.DuplicateQuestionId is not null
order by hu.TotalScore desc, hu.GoldBadges desc, lup.CreationDate desc
limit 100;