with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        row_number() over (partition by t.TagName order by t.Count desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsModeratorOnly = false
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivity as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1, 2)
),
TopPostsWithComments as (
    select
        pa.Id as PostId,
        pa.PostTypeId,
        pa.OwnerUserId,
        pa.CreationDate,
        pa.Score,
        pa.ViewCount,
        pa.Tags,
        pa.AcceptedAnswerId,
        pa.AnswerCount,
        pa.CommentCount,
        pa.FavoriteCount,
        pa.ClosedDate,
        pa.OwnerName,
        c.CommentCountPerPost,
        c.MaxCommentLength,
        c.AvgCommentLength
    from PostActivity pa
    left join (
        select
            PostId,
            count(*) as CommentCountPerPost,
            max(length(Text)) as MaxCommentLength,
            avg(length(Text)) as AvgCommentLength
        from Comments
        group by PostId
    ) c on c.PostId = pa.Id
    where pa.rn <= 100
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Score as QuestionScore,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        row_number() over (partition by q.Id order by a.Score desc nulls last) as AnswerRank
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as PostOwnerName,
        u2.DisplayName as RelatedPostOwnerName
    from PostLinks pl
    left join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    left join Posts pr on pr.Id = pl.RelatedPostId
    left join Users u2 on u2.Id = pr.OwnerUserId
    where pl.LinkTypeId = 3
),
UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (
            partition by u.Id
            order by extract(epoch from p.CreationDate)
            range between 30 * 24 * 60 * 60 preceding and current row
        ) as PostsLast30Days
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
ComplexUserStats as (
    select
        ua.Id as UserId,
        ua.DisplayName,
        ua.PostsLast30Days,
        coalesce(ub.GoldBadges, 0) as GoldBadges,
        coalesce(ub.SilverBadges, 0) as SilverBadges,
        coalesce(ub.BronzeBadges, 0) as BronzeBadges,
        case 
            when ua.PostsLast30Days > 10 then 'Highly Active'
            when ua.PostsLast30Days between 1 and 10 then 'Moderately Active'
            else 'Inactive'
        end as ActivityLevel,
        case
            when coalesce(ub.GoldBadges, 0) > 5 then 'Elite'
            when coalesce(ub.SilverBadges, 0) > 10 then 'Experienced'
            else 'Novice'
        end as BadgeLevel
    from UserActivityWindow ua
    left join UserBadgeSummary ub on ub.UserId = ua.Id
    where ua.PostsLast30Days is not null
)
select
    t.TagName,
    t.Count as TagUsageCount,
    t.AnswerCount,
    t.ViewCount,
    coalesce(aas.QuestionScore, 0) as AvgQuestionScore,
    coalesce(aas.AnswerScore, 0) as AcceptedAnswerScore,
    coalesce(dupl.PostId, -1) as DuplicatePostId,
    coalesce(dupl.RelatedPostId, -1) as DuplicateRelatedPostId,
    coalesce(dupl.PostOwnerName, 'Unknown') as DuplicatePostOwner,
    coalesce(dupl.RelatedPostOwnerName, 'Unknown') as DuplicateRelatedPostOwner,
    cus.DisplayName as UserName,
    cus.PostsLast30Days,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.ActivityLevel,
    cus.BadgeLevel,
    case when t.Count > 1000 then 'Popular' else 'Niche' end as PopularityCategory,
    length(coalesce(t.TagName, '')) + coalesce(t.Count, 0) as ComplexCalcExample,
    case when t.TagName is null then 'NoTag' else substring(t.TagName from 1 for 3) end as TagNamePrefix,
    coalesce(tp.CommentCountPerPost, 0) as CommentCount,
    coalesce(tp.MaxCommentLength, 0) as MaxCommentLength,
    coalesce(tp.AvgCommentLength, 0) as AvgCommentLength
from RecursiveTagCounts t
left join AcceptedAnswerStats aas on aas.QuestionId = t.TagId
left join DuplicateLinks dupl on dupl.PostId = aas.AnswerId
left join ComplexUserStats cus on cus.UserId = aas.AnswerOwnerId
left join TopPostsWithComments tp on tp.PostId = aas.QuestionId
where t.rn = 1
group by
    t.TagName,
    t.Count,
    t.AnswerCount,
    t.ViewCount,
    aas.QuestionScore,
    aas.AnswerScore,
    dupl.PostId,
    dupl.RelatedPostId,
    dupl.PostOwnerName,
    dupl.RelatedPostOwnerName,
    cus.DisplayName,
    cus.PostsLast30Days,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.ActivityLevel,
    cus.BadgeLevel,
    tp.CommentCountPerPost,
    tp.MaxCommentLength,
    tp.AvgCommentLength,
    t.rn
order by t.Count desc, cus.GoldBadges desc
limit 50;