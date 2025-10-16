-- {"query": "1369.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1409} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        coalesce(p.ViewCount,0) as ViewCount,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from
        Users u
    left join
        Posts p on p.OwnerUserId = u.Id and p.PostTypeId in (1,2) -- questions and answers
    where 
        u.Reputation > 1000
),
RecentUserPosts as (
    select * from RecursiveUserPosts where rn <= 5
),
-- Aggregate Badge info with string aggregation and tag logic
UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        string_agg(distinct b.Name, ', ') filter (where b.TagBased <> cast(1 as bit)) as NonTagBadges,
        string_agg(distinct b.Name, ', ') filter (where b.TagBased = cast(1 as bit)) as TagBadges
    from Badges b
    group by b.UserId
),
-- Fetch the number of answer posts linked as accepted answer to question posts for user posts
UserAcceptedAnswerCounts as (
    select
        p.OwnerUserId as UserId,
        count(distinct a.Id) as AcceptedAnswerCount
    from
        Posts p
    join
        Posts a on a.Id = p.AcceptedAnswerId and a.OwnerUserId = p.OwnerUserId and a.PostTypeId=2
    where
        p.PostTypeId = 1
    group by p.OwnerUserId
),
-- Aggregate vote interactions on user's posts with complicated correlated subqueries
UserVoteAggregation as (
    select
        u.Id as UserId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as TotalUpVotesReceived,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as TotalDownVotesReceived,
        coalesce((select count(distinct v2.Id) from Votes v2 join Posts p2 on v2.PostId = p2.Id where p2.OwnerUserId = u.Id and v2.VoteTypeId = 5 and v2.UserId = u.Id),0) as UserFavoritesGiven,
        coalesce((select count(*) from Comments c where c.UserId = u.Id and c.PostId in (select p.Id from Posts p where p.OwnerUserId = u.Id)),0) as UserSelfCommentCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id
),
-- Rank popular tags by total counts but only those appearing in this user subset tags appear once
PopularTagsPerUser as (
    select distinct
        u.Id as UserId,
        tst.tag,
        rank() over (partition by u.Id order by t.Count desc nulls last) as tag_rank,
        t.Count,
        coalesce(t.WikiPostId, -1) as WikiPostId
    from Users u
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(rup.Tags,''), 2, length(coalesce(rup.Tags,''))-2),'><')) as tag
        from RecursiveUserPosts rup
        where rup.UserId = u.Id
          and rup.Tags is not null
    ) as tst
    join Tags t on t.TagName = tst.tag
    where u.Reputation > 1000
),
-- Selected top 3 tags per user
TopTags as (
    select 
        UserId,
        tag,
        Count,
        WikiPostId
    from PopularTagsPerUser
    where tag_rank <= 3
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    coalesce(ub.NonTagBadges, '(none)') as NotTagBadges,
    coalesce(ub.TagBadges, '(none)') as TagBadges,
    ua.AcceptedAnswerCount,
    uv.TotalUpVotesReceived,
    uv.TotalDownVotesReceived,
    uv.UserFavoritesGiven,
    uv.UserSelfCommentCount,
    rt.PostId as LatestPostId,
    rt.Title as LatestPostTitle,
    rt.PostTypeId as LatestPostType,
    rt.ViewCount as LatestPostViewCount,
    ts.tag as TopTag1,
    case when ts2.tag is not null then ts2.tag else '(none)' end as TopTag2,
    case when ts3.tag is not null then ts3.tag else '(none)' end as TopTag3,
    -- Window function: cumulative sum of Views on user recent posts
    sum(rt.ViewCount) over (partition by u.Id order by rt.CreationDate rows between unbounded preceding and current row) as CumViewOnRecentPosts
from Users u
left join UserBadgeStats ub on ub.UserId = u.Id
left join UserAcceptedAnswerCounts ua on ua.UserId = u.Id
left join UserVoteAggregation uv on uv.UserId = u.Id
left join Lateral (
  select 
      Name, PostId, PostTypeId, Title, ViewCount, CreationDate
  from RecursiveUserPosts rup 
  where rup.RoleId is null or rup.UserId = u.Id
  order by rp.CreationDate desc
  limit 1
) rt on true
left join lateral (
    select tag from TopTags tt where tt.UserId = u.Id order by Count desc limit 1
) ts on true
left join lateral (
    select tag from TopTags tt where tt.UserId = u.Id order by Count desc offset 1 limit 1
) ts2 on true
left join lateral (
    select tag from TopTags tt where tt.UserId = u.Id order by Count desc offset 2 limit 1
) ts3 on true
where u.Reputation > 1000
order by u.Reputation desc NULLS LAST
fetch first 100 rows only;