-- {"query": "828.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1958} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        cast(t.TagName as varchar(4000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id > r.Id and t.IsModeratorOnly = 0 and t.IsRequired = 0
    where r.Level < 2
),

UserActivityStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        count(distinct c.Id) as CommentCount,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        row_number() over (order by coalesce(sum(p.Score),0) desc) as RankByScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),

TopScoredPostsWithDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        u.DisplayName as OwnerName,
        coalesce(a.AcceptedAnswerScore, -1) as AcceptedAnswerScore,
        coalesce(b.BadgeCount, 0) as OwnerBadgeCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    inner join PostTypes pt on p.PostTypeId = pt.Id
    left join Users u on p.OwnerUserId = u.Id
    left join (
        select p.Id, p.Score as AcceptedAnswerScore
        from Posts p
        where p.PostTypeId = 2
    ) a on a.Id = p.AcceptedAnswerId
    left join (
        select b.UserId, count(distinct b.Id) as BadgeCount
        from Badges b
        group by b.UserId
    ) b on b.UserId = p.OwnerUserId
    where p.PostTypeId in (1,2)
),

UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
    from Badges b
    group by b.UserId
),

DuplicateLinkDetails as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate,
        u.DisplayName as LinkCreatorName
    from PostLinks pl
    inner join Posts p1 on pl.PostId = p1.Id
    inner join Posts p2 on pl.RelatedPostId = p2.Id
    left join Users u on p1.OwnerUserId = u.Id
    where pl.LinkTypeId = 3
),

FilteredPostHistory as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as EditorName,
        ph.Comment,
        ph.Text,
        row_number() over (partition by ph.PostId, ph.PostHistoryTypeId order by ph.CreationDate desc) as rn
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId in (10,11,12,13,14,15)
),

PostScoresWithWindow as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        dense_rank() over (order by p.Score desc) as ScoreRank,
        avg(p.Score) over (partition by p.PostTypeId) as AvgScoreByType,
        count(*) over (partition by p.PostTypeId) as TotalPostsByType,
        lag(p.Score) over (order by p.Score desc) as PrevScore,
        lead(p.Score) over (order by p.Score desc) as NextScore
    from Posts p
    where p.PostTypeId = 1
),

TagNameExploded as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
)

select
    uas.UserId,
    uas.DisplayName,
    uas.QuestionCount,
    uas.AnswerCount,
    uas.TotalPostScore,
    coalesce(ubs.GoldBadges,0) as GoldBadges,
    coalesce(ubs.SilverBadges,0) as SilverBadges,
    coalesce(ubs.BronzeBadges,0) as BronzeBadges,
    coalesce(ubs.TagBasedBadges,0) as TagBasedBadges,
    coalesce(dld.DuplicateCount,0) as DuplicateLinksMade,
    coalesce(uas.CommentCount,0) as CommentsMade,
    coalesce(uas.LastPostDate, uas.LastCommentDate) as LastActivity,
    tsp.PostTypeName,
    tsp.Title as TopPostTitle,
    tsp.Score as TopPostScore,
    tsp.ViewCount as TopPostViews,
    tsp.AcceptedAnswerScore,
    tsp.OwnerBadgeCount,
    psh.HistoryTypeName as LatestPostHistoryType,
    psh.CreationDate as LatestPostHistoryDate,
    psh.EditorName as LatestEditor,
    psh.Comment as LatestHistoryComment,
    psh.Text as LatestHistoryText,
    rth.Level as TagHierarchyLevel,
    rth.Path as TagHierarchyPath,
    psww.ScoreRank,
    psww.AvgScoreByType,
    psww.TotalPostsByType,
    psww.PrevScore,
    psww.NextScore
from UserActivityStats uas

left join UserBadgeSummary ubs on ubs.UserId = uas.UserId

left join (
    select
        pl.PostId,
        count(*) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
) dld on dld.PostId = (
    select min(p.Id)
    from Posts p
    where p.OwnerUserId = uas.UserId
    limit 1
)

left join TopScoredPostsWithDetails tsp on tsp.OwnerName = uas.DisplayName and tsp.PostRank = 1

left join (
    select ph.PostId, ph.PostHistoryTypeId, ph.CreationDate, ph.UserId, ph.Comment, ph.Text, pht.Name as HistoryTypeName, u.DisplayName as EditorName
    from (
        select *, row_number() over (partition by PostId order by CreationDate desc) as rn
        from PostHistory
        where PostHistoryTypeId in (10,11,12,13,14,15)
    ) ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    where ph.rn = 1
) psh on psh.PostId = (
    select min(p.Id)
    from Posts p
    where p.OwnerUserId = uas.UserId
    limit 1
)

left join RecursiveTagHierarchy rth on rth.TagName = (
    select TagName
    from TagNameExploded
    where PostId = (
        select min(p.Id)
        from Posts p
        where p.OwnerUserId = uas.UserId and p.PostTypeId = 1
        limit 1
    )
    limit 1
)

left join PostScoresWithWindow psww on psww.Id = (
    select min(p.Id)
    from Posts p
    where p.OwnerUserId = uas.UserId and p.PostTypeId = 1
    limit 1
)

where uas.TotalPostScore > 100
  and (ubs.GoldBadges > 0 or ubs.SilverBadges > 3)
  and (psww.ScoreRank is not null and psww.ScoreRank < 100)
order by uas.TotalPostScore desc, uas.UserId
limit 50;