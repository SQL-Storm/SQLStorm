-- {"query": "474.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1244} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t.Id,
        t.TagName,
        t.Count,
        r.Level + 1,
        r.Path || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and not t.TagName = any(r.Path)
    where t.Count > r.Count / 2
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        coalesce(sum(case when b.TagBased = 1 then 1 else 0 end),0) as TagBasedBadges,
        row_number() over (partition by u.Id order by max(b.Date) desc nulls last) as LatestBadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
PostComplexStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
        max(ph.CreationDate) as LastEditDate,
        count(distinct c.Id) as CommentCount,
        sum(v.VoteTypeId = 2::smallint)::int as UpVotes,
        sum(v.VoteTypeId = 3::smallint)::int as DownVotes,
        case when p.PostTypeId = 1 then
            (select count(1) from Posts ans where ans.ParentId = p.Id and ans.Score > 0)
        else null end as PositiveAnswerCount,
        case when p.PostTypeId = 1 then
            (select count(1) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3)
        else null end as DuplicateCount
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.Tags, p.AcceptedAnswerId, p.ParentId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PostsLast30Days,
        sum(case when p.Score > 0 then 1 else 0 end) over (partition by u.Id order by p.CreationDate range between interval '30 days' preceding and current row) as PositivePostsLast30Days,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
TopUsersByActivity as (
    select
        ua.UserId,
        ua.DisplayName,
        max(ua.PostsLast30Days) as MaxPostsIn30Days,
        max(ua.PositivePostsLast30Days) as MaxPositivePostsIn30Days
    from UserActivityWindow ua
    group by ua.UserId, ua.DisplayName
    having max(ua.PostsLast30Days) > 10
),
FinalResult as (
    select
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.EditCount,
        p.CommentCount,
        p.UpVotes,
        p.DownVotes,
        p.PositiveAnswerCount,
        p.DuplicateCount,
        u.DisplayName as OwnerName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        ubs.TagBasedBadges,
        tu.MaxPostsIn30Days,
        tu.MaxPositivePostsIn30Days,
        array_to_string(string_to_array(coalesce(p.Tags, ''), '><'), ', ') as ParsedTags,
        case
            when p.Score > 100 and p.ViewCount > 10000 then 'Hot'
            when p.Score between 50 and 100 then 'Warm'
            else 'Cold'
        end as PopularityCategory,
        row_number() over (partition by p.PostTypeId order by p.Score desc nulls last) as ScoreRankWithinType
    from PostComplexStats p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    left join TopUsersByActivity tu on tu.UserId = u.Id
    where p.PostTypeId in (1, 2)
      and (p.Score > 10 or p.ViewCount > 1000)
      and (u.Reputation is not null and u.Reputation > 100)
)
select *
from FinalResult
where PopularityCategory = 'Hot'
order by ScoreRankWithinType, Score desc, ViewCount desc
limit 100;