-- {"query": "2568.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1236} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
), LatestUserBadges as (
    select UserId, DisplayName, BadgeName, BadgeClass from RecursiveUserBadges where rn = 1
), PostWithBadges as (
    select 
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        lub.BadgeName,
        lub.BadgeClass,
        p.CreationDate,
        p.Score,
        -- number of comments on post
        coalesce(c.CommentCount,0) as CommentCount,
        -- number of edits by distinct editors
        (select count(distinct ph.UserId) from PostHistory ph where ph.PostId = p.Id and ph.UserId is not null) as EditorCount,
        -- calculate length of tag string, null-safe
        length(coalesce(p.Tags, '')) as TagStringLength
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join LatestUserBadges lub on p.OwnerUserId = lub.UserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on p.Id = c.PostId
    where p.PostTypeId in (1, 2) -- questions or answers
), AggPostStats as (
    select
        OwnerUserId,
        count(*) as TotalPosts,
        sum(case when PostTypeId=1 then 1 else 0 end) as QuestionsCount,
        sum(case when PostTypeId=2 then 1 else 0 end) as AnswersCount,
        avg(Score) as AvgPostScore,
        avg(CommentCount) as AvgComments,
        avg(EditorCount) as AvgEditors,
        avg(TagStringLength) as AvgTagLength
    from PostWithBadges
    group by OwnerUserId
), UserScores as (
    select 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        aps.TotalPosts, aps.QuestionsCount, aps.AnswersCount,
        aps.AvgPostScore, aps.AvgComments, aps.AvgEditors, aps.AvgTagLength,
        -- Calculate user activity score based on weighted sum of posts, badges and reputation
        (coalesce(aps.TotalPosts,0) * 3) + 
        (coalesce((select count(b.Id) from Badges b where b.UserId = u.Id and b.Class=1),0) * 20) +
        (coalesce((select count(b.Id) from Badges b where b.UserId = u.Id and b.Class=2),0) * 10) +
        (coalesce((select count(b.Id) from Badges b where b.UserId = u.Id and b.Class=3),0) * 5) +
        (u.Reputation / 100.0) as ActivityScore
    from Users u
    left join AggPostStats aps on u.Id = aps.OwnerUserId
), UserRanked as (
    select 
        *,
        rank() over (order by ActivityScore desc nulls last) as Rank,
        dense_rank() over (order by ActivityScore desc nulls last) as DenseRank,
        ntile(10) over (order by ActivityScore desc nulls last) as Decile 
    from UserScores
), TopUsersPosts as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn_post
    from Posts p
    join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- questions only
), TopRankedUsersWithPosts as (
    select
        ur.Id as UserId, ur.DisplayName, ur.Reputation, ur.ActivityScore, ur.Rank, ur.Decile,
        tup.PostId, tup.Title, tup.Score as PostScore, tup.ViewCount,
        -- Extract first tag from Tags xml-like string, null safe
        case 
            when tup.Tags is not null and tup.Tags like '%><%' then 
                substring(
                    tup.Tags from 
                    position('><' in tup.Tags) + 2 for 
                    position('>' in substring(tup.Tags from position('><' in tup.Tags) + 2)) - 1
                )
            else null
        end as FirstTag
    from UserRanked ur
    left join TopUsersPosts tup on ur.Id = tup.OwnerUserId and tup.rn_post = 1
    where ur.Rank <= 100
)
select *
from TopRankedUsersWithPosts
where
    -- Users with reputation between 500 and 50k and ActivityScore in top 100
    Reputation between 500 and 50000
    and 
    (
        -- Filter by presence of FirstTag that is not null and contains letters 'sql' case insensitive OR user has >=1 gold badge
        (
            FirstTag is not null and lower(FirstTag) like '%sql%'
        )
        or
        (
            (select count(*) from Badges b where b.UserId = UserId and b.Class = 1) >= 1
        )
    )
order by Decile, ActivityScore desc, Reputation desc;