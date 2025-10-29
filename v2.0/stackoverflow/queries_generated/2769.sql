-- {"query": "2769.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1382} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        t.WikiPostId,
        row_number() over (order by t.Count desc nulls last, t.TagName) as Rank
    from Tags t
    where t.TagName is not null
    union all
    select
        r.TagId,
        r.TagName,
        r.Count,
        r.WikiPostId,
        r.Rank
    from RecursiveTagCounts r
    where r.Count > 1000
),
UserBadgeSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct b.Id) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityRank as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        coalesce(p.Score, 0) as Score,
        coalesce(p.ViewCount, 0) as Views,
        p.Tags,
        rank() over (partition by p.OwnerUserId order by p.CreationDate desc nulls last) as RecentRank,
        row_number() over (partition by p.OwnerUserId, p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last) as ScoreRank,
        sum(coalesce(p.Score,0)) over (partition by p.OwnerUserId) as TotalUserScore
    from Posts p
    where p.OwnerUserId is not null
),
UserRecentPosts as (
    select par.OwnerUserId, par.Id as PostId, par.PostTypeId, par.CreationDate, par.Score, par.Views, par.Tags
    from PostActivityRank par
    where par.RecentRank <= 5
),
DuplicatesWithDetails as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId
    inner join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
TopDuplicateUsers as (
    select
        u.Id,
        u.DisplayName,
        count(distinct dup.DuplicatePostId) as DupPostsCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    join DuplicatesWithDetails dup on dup.DuplicatePostId = p.Id
    group by u.Id, u.DisplayName
    having count(distinct dup.DuplicatePostId) > 2
),
UserScoreWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        rank() over (order by u.Reputation desc nulls last) as RepRank,
        dense_rank() over (partition by u.Location order by u.Reputation desc nulls last) as LocationRepRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.TotalPostScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    case
        when ub.GoldBadges > 10 then 'Elite'
        when ub.SilverBadges > 20 then 'Experienced'
        when ub.BronzeBadges > 50 then 'Contributor'
        else 'Novice'
    end as UserLevel,
    t.Tags as RecentTopTags,
    dt.DupPostsCount as DuplicatePostsByUser,
    -- Correlated subquery to find count of closed posts per user
    (
        select count(distinct ph.PostId)
        from PostHistory ph
        where ph.PostHistoryTypeId = 10 -- Post Closed
          and ph.UserId = u.Id
    ) as ClosedPostsCount,
    -- Most recent Post with highest score for the user including null logic and string expressions
    (
        select p.Title || ' [' || coalesce(p.Tags, 'no-tags') || ']'
        from Posts p
        where p.OwnerUserId = u.Id
        order by p.Score desc nulls last, p.CreationDate desc nulls last
        limit 1
    ) as TopScoredPostTitle,
    urp.RecentRank,
    urp.PostTypeId as RecentPostTypeId,
    urp.Score as RecentPostScore,
    urp.Views as RecentPostViews,
    size(array_remove(string_to_array(coalesce(urp.Tags,''), '><'), '')) as RecentPostTagCount
from UserScoreWindow u
left join UserBadgeSummary ub on ub.UserId = u.Id
left join TopDuplicateUsers dt on dt.Id = u.Id
left join lateral (
    select par.RecentRank, par.PostTypeId, par.Score, par.Views, par.Tags
    from PostActivityRank par
    where par.OwnerUserId = u.Id
    order by par.CreationDate desc nulls last
    limit 1
) urp on true
left join (
    select
        PostId,
        array_agg(distinct unnest(string_to_array(substring(Tags from 2 for length(Tags)-2), '><'))) as Tags
    from Posts
    where Tags is not null
    group by PostId
) t on t.PostId = urp.Id
where u.Reputation > 1000
order by u.Reputation desc nulls last
limit 100;