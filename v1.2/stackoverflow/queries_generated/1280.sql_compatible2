with RecursiveUserBadges as (
    select u.Id as UserId, u.DisplayName,
        b.Id as BadgeId, b.Name as BadgeName, b.Class as BadgeClass, b.Date as AwardedDate,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where b.Class is not null
),
TopBadgesPerUser as (
    select UserId, DisplayName, BadgeId, BadgeName, BadgeClass, AwardedDate
    from RecursiveUserBadges
    where BadgeRank <= 3
),
QuestionAnswerStats as (
    select p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        coalesce(avg(p.Score),0) as AvgScore,
        coalesce(max(p.ViewCount),0) as MaxViews
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
LatestPostActivity as (
    select p.Id as PostId, p.OwnerUserId, p.PostTypeId, p.Title,
        p.Score, p.ViewCount, p.CreationDate, p.LastActivityDate,
        row_number() over (partition by p.OwnerUserId order by p.LastActivityDate desc) as rn
    from Posts p
    where p.OwnerUserId is not null and p.PostTypeId in (1,2)
),
UserTagsUsage as (
    select u.Id as UserId, 
        tag,
        count(*) as TagUsageCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join lateral unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as tag
    group by u.Id, tag
),
UserCommentsCount as (
    select c.UserId,
        count(c.Id) as CommentsCount,
        sum(case when c.Score > 0 then c.Score else 0 end) as PositiveCommentScore,
        sum(case when c.Score < 0 then c.Score else 0 end) as NegativeCommentScore
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
PostCloseReasons as (
    select ph.PostId, crt.Name as CloseReasonName, count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on crt.Id = cast(nullif(ph.Comment, '') as smallint)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null
    group by ph.PostId, crt.Name
),
UserDuplicateLinks as (
    select p.OwnerUserId, count(distinct pl.RelatedPostId) as DuplicateLinkedPosts
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id and pl.LinkTypeId = 3
    where p.PostTypeId = 1 and p.OwnerUserId is not null
    group by p.OwnerUserId
)
select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(qu.QuestionCount,0) as TotalQuestions,
    coalesce(qu.AnswerCount,0) as TotalAnswers,
    round(coalesce(qu.AvgScore, 0), 2) as AvgPostScore,
    coalesce(qu.MaxViews,0) as MaxPostViews,
    coalesce(uc.CommentsCount, 0) as TotalComments,
    coalesce(uc.PositiveCommentScore, 0) as PositiveCommentScore,
    coalesce(uc.NegativeCommentScore, 0) as NegativeCommentScore,
    du.DuplicateLinkedPosts,
    (
        select string_agg(t.TagName, ', ')
        from Tags t
        join UserTagsUsage usa on usa.UserId = u.Id and usa.tag = t.TagName
        group by usa.UserId
        order by max(usa.TagUsageCount) desc
        limit 3
    ) as TopTags,
    (
        select string_agg(distinct b2.BadgeName || '(' || 
                    case b2.BadgeClass when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', '; ')
        from TopBadgesPerUser b2
        where b2.UserId = u.Id
    ) as TopBadges,
    la.PostId as LatestPostId,
    la.Title as LatestPostTitle,
    la.PostTypeId as LatestPostType,
    la.Score as LatestPostScore,
    la.ViewCount as LatestPostViews,
    la.LastActivityDate as LatestPostActivity,
    array_agg(distinct pcr.CloseReasonName) filter (where pcr.CloseReasonName is not null) as CloseReasons
from Users u
left join QuestionAnswerStats qu on u.Id = qu.OwnerUserId
left join UserCommentsCount uc on u.Id = uc.UserId
left join UserDuplicateLinks du on u.Id = du.OwnerUserId
left join LatestPostActivity la on u.Id = la.OwnerUserId and la.rn = 1
left join PostCloseReasons pcr on pcr.PostId = la.PostId
where u.Reputation > 1000
  and (coalesce(qu.QuestionCount,0) > 10 or coalesce(qu.AnswerCount,0) > 10)
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(qu.QuestionCount,0),
    coalesce(qu.AnswerCount,0),
    round(coalesce(qu.AvgScore, 0), 2),
    coalesce(qu.MaxViews,0),
    coalesce(uc.CommentsCount, 0),
    coalesce(uc.PositiveCommentScore, 0),
    coalesce(uc.NegativeCommentScore, 0),
    du.DuplicateLinkedPosts,
    la.PostId,
    la.Title,
    la.PostTypeId,
    la.Score,
    la.ViewCount,
    la.LastActivityDate
order by u.Reputation desc, TotalAnswers desc
limit 50;