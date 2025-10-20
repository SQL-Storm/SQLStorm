with recursive RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 1 as Level
    from Tags t
    where t.IsModeratorOnly = false and t.IsRequired = false
    union all
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, r.Level + 1
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id and r.Level < 3
),
UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score as QuestionScore,
        p.ViewCount,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        (select count(*) from Posts a where a.ParentId = p.Id and a.Score > 0) as PositiveAnswerCount,
        (select avg(a.Score) from Posts a where a.ParentId = p.Id) as AvgAnswerScore,
        (select max(a.Score) from Posts a where a.ParentId = p.Id) as MaxAnswerScore,
        (select count(distinct v.UserId) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as QuestionUpvoters,
        (select count(distinct v.UserId) from Votes v join Posts a on a.Id = v.PostId where a.ParentId = p.Id and v.VoteTypeId = 2) as AnswerUpvoters
    from Posts p
    where p.PostTypeId = 1
),
PostWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.ViewCount,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Title, p.Tags, p.AnswerCount, p.ViewCount
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 30 preceding and current row) as PostsLast30Days,
        rank() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
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
ComplexPostSearch as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        case 
            when p.ClosedDate is not null then 'Closed'
            when p.AcceptedAnswerId is not null then 'Answered'
            else 'Open'
        end as PostStatus,
        string_agg(distinct ph.Name, ', ') as HistoryTypes,
        count(distinct ph.Id) as HistoryCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostHistory phx on phx.PostId = p.Id
    left join PostHistoryTypes ph on ph.Id = phx.PostHistoryTypeId
    where p.PostTypeId = 1
    group by p.Id, p.Title, p.Tags, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, p.ClosedDate, p.AcceptedAnswerId
),
FinalSelection as (
    select
        cps.Id,
        cps.Title,
        cps.OwnerName,
        cps.PostStatus,
        cps.Score,
        cps.ViewCount,
        cps.HistoryCount,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        pas.AnswerCount,
        pas.PositiveAnswerCount,
        pas.AvgAnswerScore,
        pas.MaxAnswerScore,
        pas.QuestionUpvoters,
        pas.AnswerUpvoters,
        uw.PostsLast30Days,
        uw.RecentPostRank,
        dl.RelatedPostId as DuplicateOfPostId,
        dl.RelatedPostTitle as DuplicateOfPostTitle
    from ComplexPostSearch cps
    left join UserBadgeCounts ubc on ubc.UserId = (select OwnerUserId from Posts where Id = cps.Id)
    left join PostAnswerStats pas on pas.QuestionId = cps.Id
    left join UserActivityWindow uw on uw.PostId = cps.Id
    left join DuplicateLinks dl on dl.PostId = cps.Id
    where (cps.Score > 5 or cps.ViewCount > 1000)
      and (coalesce(ubc.GoldBadges, 0) > 0 or coalesce(pas.PositiveAnswerCount, 0) > 0)
      and (uw.PostsLast30Days is null or uw.PostsLast30Days < 10)
)
select
    Id,
    Title,
    OwnerName,
    PostStatus,
    Score,
    ViewCount,
    HistoryCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    AnswerCount,
    PositiveAnswerCount,
    coalesce(round(cast(AvgAnswerScore as numeric), 2), 0) as AvgAnswerScore,
    MaxAnswerScore,
    QuestionUpvoters,
    AnswerUpvoters,
    coalesce(PostsLast30Days, 0) as PostsLast30Days,
    RecentPostRank,
    DuplicateOfPostId,
    DuplicateOfPostTitle
from FinalSelection
order by Score desc, ViewCount desc
limit 100;