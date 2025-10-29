-- {"query": "2240.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1367} 
with RecursivePostTree as (
    select p.Id, p.ParentId, 1 as Level, p.CreationDate, p.Score, p.OwnerUserId, p.Title,
        case when p.PostTypeId = 1 then 1 else 0 end as IsQuestion,
        case when p.PostTypeId = 2 then 1 else 0 end as IsAnswer
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ClosedDate is null
    union all
    select c.Id, c.ParentId, rpt.Level + 1, c.CreationDate, c.Score, c.OwnerUserId, c.Title,
        case when c.PostTypeId = 1 then 1 else 0 end,
        case when c.PostTypeId = 2 then 1 else 0 end
    from Posts c
    inner join RecursivePostTree rpt on c.ParentId = rpt.Id
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgesCount,
        sum(v.VoteCount) as TotalVotes,
        first_value(u.Reputation) over (partition by u.Id order by u.CreationDate) as ReputationAtFirstActivity,
        case 
            when u.Location is null or length(trim(u.Location)) = 0 then 'Unknown'
            else u.Location end as CleanLocation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= u.CreationDate and p.Score > 0
    left join Badges b on b.UserId = u.Id
    left join (
        select PostId, count(*) as VoteCount from Votes
        where VoteTypeId in (2,3) -- UpMod(2), DownMod(3)
        group by PostId
    ) v on v.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
RecentCommentsAgg as (
    select
        c.PostId,
        string_agg(coalesce(c.UserDisplayName,'[anon]') || ': ' || left(replace(replace(replace(c.Text, E'\n', ' '), E'\r', ' '), '\t', ' '), 100), ' | ') as RecentComments
    from Comments c
    where c.CreationDate > now() - interval '30 days'
    group by c.PostId
),
TopLinkedPosts as (
    select pl.PostId, count(*) as LinkCount
    from PostLinks pl
    where pl.LinkTypeId = 1
    group by pl.PostId
    having count(*) > 3
),
PostsWithHistories as (
    select p.Id, p.Title, p.ViewCount, p.Score, p.CreationDate, p.OwnerUserId, p.PostTypeId,
        coalesce(ph.PostHistoryTypesName, 'N/A') as LastHistoryType,
        phh.LastHistoryDate,
        row_number() over (partition by p.Id order by phh.LastHistoryDate desc nulls last) as rn
    from Posts p
    left join (
        select ph.PostId, pht.Name as PostHistoryTypesName, max(ph.CreationDate) as LastHistoryDate
        from PostHistory ph
        join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
        group by ph.PostId, pht.Name
    ) phh on phh.PostId = p.Id
    left join PostHistoryTypes pht on pht.Name = phh.PostHistoryTypesName
),
ComplexFilteredPosts as (
    select p.Id, p.Title, p.Score, p.ViewCount, p.Tags, p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1
    and p.Score > (
        select avg(score)*1.5 from Posts where PostTypeId = 1
    )
    and exists (
        select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 2 and v.CreationDate > p.CreationDate - interval '180 day'
    )
    and (p.ClosedDate is null or p.ClosedDate > now() - interval '365 day')
    and regexp_replace(p.Tags, '<[^>]*>', '', 'g') ~* 'sql|performance|optimization'
),
WindowedPosts as (
    select
        p.Id, p.Title, p.Score, p.ViewCount, p.Tags,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank,
        dense_rank() over (order by p.ViewCount desc) as ViewRank,
        ntile(4) over (order by p.CreationDate) as CreationQuartile
    from Posts p
    where p.PostTypeId = 1
)
select
    u.UserId,
    u.DisplayName,
    u.ReputationAtFirstActivity,
    u.QuestionCount,
    u.AnswerCount,
    u.BadgesCount,
    coalesce(u.TotalVotes,0) as TotalVotes,
    u.CleanLocation,
    p.Id as PostId,
    p.Title as PostTitle,
    p.Score as PostScore,
    p.ViewCount as PostViewCount,
    p.Tags as PostTags,
    c.RecentComments,
    ph.LastHistoryType,
    ph.LastHistoryDate,
    rpt.Level as PostDepthLevel,
    rpt.IsQuestion,
    rpt.IsAnswer,
    lp.LinkCount,
    wp.ScoreRank,
    wp.ViewRank,
    wp.CreationQuartile
from UserActivity u
left join PostsWithHistories ph on ph.OwnerUserId = u.UserId and ph.rn = 1
left join ComplexFilteredPosts p on p.OwnerUserId = u.UserId
left join RecursivePostTree rpt on rpt.Id = p.Id
left join RecentCommentsAgg c on c.PostId = p.Id
left join TopLinkedPosts lp on lp.PostId = p.Id
left join WindowedPosts wp on wp.Id = p.Id
where u.QuestionCount >= 5 and u.ReputationAtFirstActivity > 1000
order by u.TotalVotes desc, p.Score desc
limit 100;