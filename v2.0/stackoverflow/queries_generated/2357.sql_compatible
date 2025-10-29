with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate as PostCreation,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as HistRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    where u.Reputation > 1000
),
LatestPostHistory as (
    select
        UserId,
        PostId,
        PostHistoryTypeId,
        HistoryDate
    from RecursiveUserActivity
    where HistRank = 1
),
BadgeAggregates as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Name) as DistinctBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserTagActivity as (
    select
        u.Id as UserId,
        t.TagName,
        count(p.Id) as PostsWithTag,
        sum(coalesce(p.Score,0)) as TotalScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.Tags is not null
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as t(TagName)
    join Tags tg on tg.TagName = t.TagName
    where u.Reputation > 2000
    group by u.Id, t.TagName
),
TopTagsPerUser as (
    select distinct on (UserId)
        UserId, TagName, PostsWithTag, TotalScore
    from UserTagActivity
    order by UserId, TotalScore desc
),
QuestionAnswerRatio as (
    select
        u.Id as UserId,
        count(distinct case when p.PostTypeId=1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId=2 then p.Id end) as AnswerCount,
        case
            when count(distinct case when p.PostTypeId=1 then p.Id end) = 0 then null
            else 1.0 * count(distinct case when p.PostTypeId=2 then p.Id end) / count(distinct case when p.PostTypeId=1 then p.Id end)
        end as AnswerToQuestionRatio
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id
),
CommentInsight as (
    select
        c.UserId,
        count(*) as TotalComments,
        avg(c.Score) as AvgCommentScore,
        sum(case when c.Text ilike '%error%' or c.Text ilike '%fail%' then 1 else 0 end) as NegativeCommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
UserPostLinkStats as (
    select
        p.OwnerUserId as UserId,
        count(distinct pl.Id) filter (where pl.LinkTypeId=1) as LinkedPostsCount,
        count(distinct pl.Id) filter (where pl.LinkTypeId=3) as DuplicatePostsCount
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    group by p.OwnerUserId
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    b.DistinctBadges,
    cast(b.LastBadgeDate as date) as LastBadgeDate,
    q.QuestionCount,
    q.AnswerCount,
    round(cast(q.AnswerToQuestionRatio as numeric), 2) as AnswerToQuestionRatio,
    tsi.TotalComments,
    round(cast(tsi.AvgCommentScore as numeric),2) as AvgCommentScore,
    tsi.NegativeCommentCount,
    cast(tsi.LastCommentDate as date) as LastCommentDate,
    tpl.TagName as TopTag,
    tpl.PostsWithTag,
    tpl.TotalScore as TopTagScore,
    upl.LinkedPostsCount,
    upl.DuplicatePostsCount,
    case
        when u.WebsiteUrl is null then 'No website'
        when u.WebsiteUrl ilike '%stackoverflow%' then 'SO related'
        else 'Other website'
    end as WebsiteCategory,
    case
        when u.Location is null then 'Unknown'
        when u.Location ilike '%USA%' then 'USA'
        else 'Other'
    end as UserLocationCategory
from Users u
left join BadgeAggregates b on b.UserId = u.Id
left join QuestionAnswerRatio q on q.UserId = u.Id
left join CommentInsight tsi on tsi.UserId = u.Id
left join TopTagsPerUser tpl on tpl.UserId = u.Id
left join UserPostLinkStats upl on upl.UserId = u.Id
where u.Reputation > 5000
group by
    u.Id,
    u.DisplayName,
    u.Reputation,
    b.GoldBadges,
    b.SilverBadges,
    b.BronzeBadges,
    b.DistinctBadges,
    b.LastBadgeDate,
    q.QuestionCount,
    q.AnswerCount,
    q.AnswerToQuestionRatio,
    tsi.TotalComments,
    tsi.AvgCommentScore,
    tsi.NegativeCommentCount,
    tsi.LastCommentDate,
    tpl.TagName,
    tpl.PostsWithTag,
    tpl.TotalScore,
    upl.LinkedPostsCount,
    upl.DuplicatePostsCount,
    u.WebsiteUrl,
    u.Location
order by u.Reputation desc nulls last, b.GoldBadges desc nulls last
limit 100;