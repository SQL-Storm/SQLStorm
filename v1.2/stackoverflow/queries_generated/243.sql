-- {"query": "243.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1586} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id = r.Id + 1
    where r.Level < 3
),
UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScoreRanks as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as UserPostRecencyRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.CreationDate,
        c.CommentCount,
        coalesce(c.LatestCommentDate, timestamp '1970-01-01') as LatestCommentDate
    from Posts p
    left join (
        select
            PostId,
            count(*) as CommentCount,
            max(CreationDate) as LatestCommentDate
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
),
DuplicatePostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        count(distinct c.Id) as CommentsCount,
        sum(vt.UpVotes) as TotalUpVotes,
        sum(vt.DownVotes) as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        ph.PostId,
        ph.PostHistoryTypeId,
        p.Title,
        ph.CreationDate,
        row_number() over (partition by u.Id order by ph.CreationDate desc) as rn
    from Users u
    join PostHistory ph on ph.UserId = u.Id
    join Posts p on p.Id = ph.PostId
    where ph.PostHistoryTypeId in (4,5,6,10,11)
)
select
    uac.UserId,
    uac.DisplayName,
    uac.QuestionsCount,
    uac.AnswersCount,
    uac.CommentsCount,
    coalesce(ubc.GoldBadges,0) as GoldBadges,
    coalesce(ubc.SilverBadges,0) as SilverBadges,
    coalesce(ubc.BronzeBadges,0) as BronzeBadges,
    coalesce(uac.TotalUpVotes,0) as TotalUpVotes,
    coalesce(uac.TotalDownVotes,0) as TotalDownVotes,
    uac.LastPostDate,
    phcr.CloseReasonName,
    phcr.CloseDate,
    pt.Title as RecentPostTitle,
    pt.Score as RecentPostScore,
    pt.ViewCount as RecentPostViews,
    dt.PostTitle as DuplicateOfTitle,
    dt.RelatedPostTitle as DuplicateTargetTitle,
    rth.Path as TagHierarchyPath,
    case
        when uac.QuestionsCount > 100 then 'Expert'
        when uac.QuestionsCount between 50 and 100 then 'Intermediate'
        else 'Beginner'
    end as UserLevel,
    concat_ws(' | ',
        coalesce(pt.Title, 'No Recent Post'),
        coalesce(dt.PostTitle, 'No Duplicate Link'),
        coalesce(phcr.CloseReasonName, 'No Close Reason')
    ) as SummaryInfo
from UserActivitySummary uac
left join UserBadgeCounts ubc on ubc.UserId = uac.UserId
left join PostHistoryCloseReasons phcr on phcr.PostId = (
    select ph.PostId from PostHistory ph where ph.UserId = uac.UserId and ph.PostHistoryTypeId = 10 order by ph.CreationDate desc limit 1
)
left join Posts pt on pt.Id = (
    select p.Id from Posts p where p.OwnerUserId = uac.UserId order by p.CreationDate desc limit 1
)
left join DuplicatePostLinks dt on dt.PostId = pt.Id
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(pt.Tags, ''), '><'))
where uac.QuestionsCount > 10
order by uac.TotalUpVotes desc, uac.QuestionsCount desc
limit 100;