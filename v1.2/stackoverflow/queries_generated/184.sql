-- {"query": "184.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1634} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        coalesce(p.ViewCount, 0) as ViewCount,
        coalesce(p.Score, 0) as Score,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.IsModeratorOnly = 0
),
FilteredTags as (
    select TagId, TagName, Count, AnswerCount, ViewCount, Score
    from RecursiveTagCounts
    where rn = 1
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
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
        p.ParentId,
        p.Title,
        p.ClosedDate,
        p.LastActivityDate,
        dense_rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank,
        count(*) over (partition by p.OwnerUserId) as PostsByUser
    from Posts p
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
        pa.Title,
        pa.ClosedDate,
        pa.LastActivityDate,
        pa.ScoreRank,
        pa.PostsByUser,
        c.CommentCount,
        c.TopCommentText,
        c.TopCommentScore
    from PostActivity pa
    left join lateral (
        select
            count(*) as CommentCount,
            max(coalesce(c.Score, 0)) as TopCommentScore,
            substring(max(c.Text) over (order by c.Score desc nulls last), 1, 100) as TopCommentText
        from Comments c
        where c.PostId = pa.Id
    ) c on true
),
UserPostSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as Questions,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as Answers,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore,
        sum(p.ViewCount) filter (where p.PostTypeId = 1) as TotalQuestionViews,
        sum(p.ViewCount) filter (where p.PostTypeId = 2) as TotalAnswerViews
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as OwnerName,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
    left join Users u on u.Id = p.OwnerUserId
    where pl.LinkTypeId = 3
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        p.Title,
        u.DisplayName as OwnerName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join Posts p on p.Id = ph.PostId
    left join Users u on u.Id = p.OwnerUserId
    where ph.PostHistoryTypeId = 10 and p.PostTypeId = 1
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '365 days' preceding and current row) as PostsLastYear
    from Users u
    join Posts p on p.OwnerUserId = u.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    us.TotalPosts,
    us.Questions,
    us.Answers,
    us.AvgQuestionScore,
    us.AvgAnswerScore,
    us.MaxQuestionScore,
    us.MaxAnswerScore,
    us.TotalQuestionViews,
    us.TotalAnswerViews,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.TagBasedBadges,
    dt.PostId as DuplicatePostId,
    dt.RelatedPostId as DuplicateOfPostId,
    dt.PostTitle as DuplicatePostTitle,
    dt.RelatedPostTitle as DuplicateOfPostTitle,
    cq.CloseDate,
    cq.CloseReason,
    cq.Title as ClosedQuestionTitle,
    cq.OwnerName as ClosedQuestionOwner,
    ua.PostsLast30Days,
    ua.PostsLastYear,
    ft.TagName,
    ft.Count as TagUseCount,
    ft.AnswerCount as TagAnswerCount,
    ft.ViewCount as TagViewCount,
    ft.Score as TagScore
from Users u
left join UserPostSummary us on us.UserId = u.Id
left join UserBadgeStats ub on ub.UserId = u.Id
left join DuplicateLinks dt on dt.OwnerName = u.DisplayName
left join ClosedQuestionsWithReasons cq on cq.OwnerName = u.DisplayName
left join UserActivityWindow ua on ua.UserId = u.Id
left join LATERAL (
    select TagName, Count, AnswerCount, ViewCount, Score
    from FilteredTags ft
    where position(concat('<', ft.TagName, '>') in coalesce((select p.Tags from Posts p where p.OwnerUserId = u.Id limit 1), '')) > 0
    order by ft.Count desc
    limit 1
) ft on true
where u.Reputation > (
    select avg(Reputation) from Users
)
and (us.TotalPosts > 10 or us.TotalPosts is null)
and (ub.GoldBadges > 0 or ub.GoldBadges is null)
order by us.TotalPosts desc nulls last, ub.GoldBadges desc nulls last
limit 100;