-- {"query": "2948.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1468} 
with RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        p.OwnerUserId,
        p.CreationDate,
        1 as Depth
    from Tags t
    left join Posts p on t.WikiPostId = p.Id
    where t.Count > 1000

    union all

    select 
        t.Id,
        t.TagName,
        t.Count,
        t.WikiPostId,
        p.OwnerUserId,
        p.CreationDate,
        r.Depth + 1
    from Tags t
    inner join Posts p on t.WikiPostId = p.Id
    inner join RecursiveTagHierarchy r on p.OwnerUserId = r.OwnerUserId
    where r.Depth < 3
), UserBadgeCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) over (partition by u.Id) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) over (partition by u.Id) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) over (partition by u.Id) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) over (partition by u.Id) as BronzeBadges,
        max(b.Date) over (partition by u.Id) as LatestBadgeDate
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 500 and u.Location is not null
), TopActivePosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        coalesce(p.Tags, '') as Tags,
        row_number() over (
            partition by p.PostTypeId 
            order by p.Score desc, p.ViewCount desc, p.CreationDate asc
        ) as rn
    from Posts p
    where p.PostTypeId in (1, 2) and p.Score is not null
), PostCommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCountTotal,
        avg(c.Score) as AvgCommentScore,
        bool_or(c.UserId is null) as HasAnonymousComments,
        string_agg(distinct c.UserDisplayName, ', ' order by c.UserDisplayName) as Commenters
    from Comments c
    where c.CreationDate >= now() - interval '1 year'
    group by c.PostId
), PostVotesSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        count(*) as TotalVotes
    from Votes v
    inner join VoteTypes vt on v.VoteTypeId = vt.Id
    group by v.PostId
), UserActivityWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(ph.Id) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenVotes,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        lag(u.Reputation) over (order by u.Reputation desc) as PreviousReputation,
        lead(u.Reputation) over (order by u.Reputation desc) as NextReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
)
select distinct
    p.Id as PostId,
    p.Title,
    p.PostTypeId,
    p.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    pb.TotalBadges,
    pb.GoldBadges,
    pb.SilverBadges,
    pb.BronzeBadges,
    pb.LatestBadgeDate,
    c.CommentCountTotal,
    c.AvgCommentScore,
    c.HasAnonymousComments,
    c.Commenters,
    v.UpVotes,
    v.DownVotes,
    v.Favorites,
    v.TotalVotes,
    RTH.TagName,
    RTH.Depth as TagHierarchyDepth,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.CloseReopenVotes,
    ua.ReputationRank,
    ua.PreviousReputation,
    ua.NextReputation,
    case 
        when p.Score > 100 then 'HighScore'
        when p.Score between 50 and 100 then 'ModerateScore'
        else 'LowScore'
    end as ScoreCategory,
    case 
        when p.ViewCount > 10000 then concat('Popular: ', p.ViewCount)
        else concat('Views: ', p.ViewCount)
    end as ViewInfo,
    coalesce(nullif(p.Tags, ''), '<none>') as CleanTags,
    left(p.Body, 100) as Snippet,
    (select count(*) from PostLinks pl where pl.PostId = p.Id and exists (
        select 1 from Posts p2 where p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    )) as LinkedQuestionCount,
    exists (
        select 1 from PostHistory ph2 
        where ph2.PostId = p.Id and ph2.PostHistoryTypeId = 10 and ph2.CreationDate > (now() - interval '30 days')
    ) as RecentlyClosed,
    (select sum(v2.BountyAmount) from Votes v2 where v2.PostId = p.Id and v2.BountyAmount is not null) as TotalBounty
from TopActivePosts p
left join Users u on p.OwnerUserId = u.Id
left join UserBadgeCTE pb on u.Id = pb.UserId
left join PostCommentsAgg c on c.PostId = p.Id
left join PostVotesSummary v on v.PostId = p.Id
left join RecursiveTagHierarchy RTH on strpos(RTH.TagName, substring(coalesce(p.Tags, ''), 2, 50)) > 0 and RTH.Depth = 1
left join UserActivityWindow ua on ua.Id = u.Id
where p.rn <= 5
  and (pb.TotalBadges is null or pb.TotalBadges > 3 or u.Reputation > 1000)
order by p.PostTypeId, p.Score desc, p.ViewCount desc;