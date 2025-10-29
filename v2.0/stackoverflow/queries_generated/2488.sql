-- {"query": "2488.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1495} 
with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.AcceptedAnswerId,
        1 as Level,
        cast(p.Id as varchar) as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
        and p.Score > 5
        and p.Tags like '%<sql>%'

    union all

    select
        c.Id,
        c.PostTypeId,
        c.OwnerUserId,
        c.Title,
        c.Score,
        c.ViewCount,
        c.CreationDate,
        c.AcceptedAnswerId,
        r.Level + 1,
        r.Path || '->' || cast(c.Id as varchar)
    from Posts c
    join RecursiveCTE r on c.ParentId = r.Id
    where c.Score > 0
),
RankedPosts as (
    select
        r.*,
        row_number() over(partition by r.OwnerUserId order by r.Score desc, r.CreationDate desc) as rn,
        count(*) over(partition by r.OwnerUserId) as total_posts,
        avg(r.Score) over(partition by r.OwnerUserId) as avg_score,
        min(r.CreationDate) over(partition by r.OwnerUserId) as first_post_date,
        max(r.CreationDate) over(partition by r.OwnerUserId) as last_post_date
    from RecursiveCTE r
),
UserBadgesCount as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.Class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.Class = 3 then 1 else 0 end) as bronze_badges
    from Badges b
    group by b.UserId
),
UserVotesAgg as (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as upvotes_cast,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as downvotes_cast,
        coalesce(sum(v.BountyAmount), 0) as total_bounty_given
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    where v.UserId is not null
    group by v.UserId
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        count(distinct c.Id) as comment_count,
        string_agg(
            case 
                when c.UserDisplayName is not null then concat(c.UserDisplayName, ': ', substring(c.Text,1,30))
                else substring(c.Text,1,30)
            end, ' | ' order by c.CreationDate desc
        ) as recent_comments_snippet
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1 and p.Score > 10
    group by p.Id, p.Title, p.Score, p.ViewCount
    having count(c.Id) > 2
),
DuplicateAndLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        p1.Score as PostScore,
        p2.Score as RelatedPostScore
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where lt.Name in ('Duplicate','Linked')
),
UserSummary as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bc.gold_badges,0) as gold_badges,
        coalesce(bc.silver_badges,0) as silver_badges,
        coalesce(bc.bronze_badges,0) as bronze_badges,
        coalesce(uv.upvotes_cast,0) as upvotes_cast,
        coalesce(uv.downvotes_cast,0) as downvotes_cast,
        coalesce(uv.total_bounty_given, 0) as total_bounty_given,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as question_count,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as answer_count,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as max_post_score,
        max(p.CreationDate) filter (where p.PostTypeId in (1,2)) as last_post_date
    from Users u
    left join Badges bc on bc.UserId = u.Id
    left join UserBadgesCount bcount on bcount.UserId = u.Id
    left join UserVotesAgg uv on uv.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        bc.gold_badges, bc.silver_badges, bc.bronze_badges,
        bcount.gold_badges, bcount.silver_badges, bcount.bronze_badges,
        uv.upvotes_cast, uv.downvotes_cast, uv.total_bounty_given
    order by u.Reputation desc
    limit 100
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.gold_badges,
    u.silver_badges,
    u.bronze_badges,
    u.upvotes_cast,
    u.downvotes_cast,
    u.total_bounty_given,
    u.question_count,
    u.answer_count,
    u.max_post_score,
    u.last_post_date,
    rp.Id as PostId,
    rp.Title as PostTitle,
    rp.Score as PostScore,
    rp.ViewCount as PostViewCount,
    rp.Level as PostThreadLevel,
    rp.Path as PostPath,
    topc.comment_count,
    topc.recent_comments_snippet,
    dl.PostId as DuplicatePostId,
    dl.RelatedPostId,
    dl.LinkTypeName,
    dl.PostScore as DuplicatePostScore,
    dl.RelatedPostScore
from UserSummary u
left join RankedPosts rp on rp.OwnerUserId = u.Id and rp.rn = 1
left join TopPostsWithComments topc on topc.Id = rp.Id
left join DuplicateAndLinkInfo dl on dl.PostId = rp.Id
where (u.gold_badges + u.silver_badges + u.bronze_badges) > 10
  and (rp.Score > 10 or rp.ViewCount > 5000)
order by u.Reputation desc, rp.Score desc
limit 50;