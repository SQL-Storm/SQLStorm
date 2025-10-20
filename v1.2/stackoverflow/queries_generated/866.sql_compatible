with recursive UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        cast(b.Class as integer) as Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName, cast(b.Class as integer)

    union all

    select 
        ubc.UserId,
        ubc.DisplayName,
        ubc.Class + 1 as Class,
        ubc.BadgeCount + 1 as BadgeCount
    from UserBadgeCounts ubc
    where ubc.Class < 3
),
HighRepUsers as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotes,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        max(p.Score) as MaxPostScore,
        min(p.Score) as MinPostScore,
        avg(p.Score) as AvgPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    where u.Reputation > 10000
    group by u.Id, u.DisplayName, u.Reputation
),
RecentActivePosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.DisplayName as OwnerName,
        count(c.Id) as CommentCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate > (cast('2024-10-01 12:34:56' as timestamp) - interval '30' day)
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, u.DisplayName
),
DuplicateQuestionLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
QuestionWithDuplicates as (
    select
        q.Id,
        q.Title,
        q.CreationDate,
        q.Score,
        dq.RelatedPostId as DuplicateOf,
        dq.CreationDate as DuplicateDate
    from Posts q
    left join DuplicateQuestionLinks dq on q.Id = dq.PostId
    where q.PostTypeId = 1
),
QuestionCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        ph.CreationDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    join CloseReasonTypes cr on cr.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10
),
LatestCloseReasons as (
    select PostId, CloseReason, CreationDate
    from QuestionCloseReasons
    where rn = 1
),
TopTags as (
    select
        t.TagName,
        t.Count,
        tp.Id as TagWikiPostId,
        p.Title as TagWikiTitle
    from Tags t
    left join Posts p on p.Id = t.WikiPostId
    left join Posts tp on tp.Id = t.ExcerptPostId
    where t.Count > 1000
)
select 
    hru.DisplayName as UserName,
    hru.Reputation,
    hru.QuestionCount,
    hru.AnswerCount,
    hru.UpVotes,
    hru.DownVotes,
    hru.MaxPostScore,
    hru.MinPostScore,
    hru.AvgPostScore,
    rap.Id as RecentPostId,
    rap.PostTypeId,
    rap.Title as RecentPostTitle,
    rap.CreationDate as RecentPostDate,
    rap.Score as RecentPostScore,
    rap.ViewCount as RecentPostViewCount,
    rap.Tags as RecentPostTags,
    rap.OwnerName as RecentPostOwner,
    rap.CommentCount as RecentPostCommentCount,
    qwd.DuplicateOf,
    qwd.DuplicateDate,
    lcr.CloseReason,
    lcr.CreationDate as CloseDate,
    tb.TagName,
    tb.Count as TagUsageCount,
    tb.TagWikiTitle
from HighRepUsers hru
left join RecentActivePosts rap on rap.OwnerName = hru.DisplayName and rap.rn = 1
left join QuestionWithDuplicates qwd on qwd.Id = rap.Id and rap.PostTypeId = 1
left join LatestCloseReasons lcr on lcr.PostId = rap.Id
left join TopTags tb on rap.Tags is not null and tb.TagName = (
    -- split tags like "<tag1><tag2>" into rows; use a standard-compatible approach: replace angle brackets and split on whitespace
    -- many SQL dialects don't have regexp_split_to_table; emulate with simple replace and a LIKE join
    replace(replace(rap.Tags,'<',''),' >','')  -- fallback expression for comparison
)
where hru.Reputation > 20000
order by hru.Reputation desc, rap.Score desc
limit 100;