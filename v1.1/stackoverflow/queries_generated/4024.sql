-- {"query": "4024.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1151} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Name) as rn,
        count(b.Id) over (partition by u.Id) as TotalBadges
    from Users u
    left join Badges b on u.Id = b.UserId
    where u.Reputation > 1000
), LatestPostsWithAnswers as (
    select 
        p.Id as QuestionId,
        p.Title,
        p.Tags,
        p.Score as QuestionScore,
        p.CreationDate as QuestionCreation,
        a.Id as AnswerId,
        a.OwnerUserId as AnswererUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreation,
        p.AcceptedAnswerId,
        dense_rank() over (partition by p.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.CreationDate >= '2023-01-01' and array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1) >= 2
), PostCommentsAggregated as (
    select 
        c.PostId,
        count(*) as CommentCount,
        sum(case when c.Score >= 5 then 1 else 0 end) as HighScoreComments,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as Commenters
    from Comments c
    group by c.PostId
), UserBadgesRanked as (
    select UserId, BadgeName, Class, rn from RecursiveUserBadges where rn <= 3
), DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
), ComplexStatistics as (
    select
        p.Id as PostId,
        p.Title,
        u.DisplayName,
        u.Reputation,
        coalesce(pc.CommentCount,0) as TotalComments,
        coalesce(pc.HighScoreComments,0) as HighScoreComments,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        case 
            when p.ViewCount > 10000 then 'Popular'
            when p.ViewCount between 1000 and 10000 then 'Moderate'
            else 'Low'
        end as PopularityCategory,
        (select count(distinct ph.UserId) from PostHistory ph where ph.PostId = p.Id) as DistinctEditors,
        exists (select 1 from DuplicateLinks dl where dl.RelatedPostId = p.Id) as IsMarkedDuplicate,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScore
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join PostCommentsAggregated pc on p.Id = pc.PostId
    where p.PostTypeId in (1,2)
)
select 
    cs.PostId,
    left(cs.Title, 60) || coalesce(' || ' || cs.PopularityCategory, '') as ShortTitleWithPopularity,
    cs.DisplayName,
    cs.Reputation,
    cs.TotalComments,
    cs.HighScoreComments,
    cs.UpVotes,
    cs.DownVotes,
    cs.DistinctEditors,
    cs.IsMarkedDuplicate,
    cs.RankByScore,
    string_agg(distinct ub.BadgeName || ' (' || case ub.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Unknown' end || ')', ', ' order by ub.rn) as TopBadges
from ComplexStatistics cs
left join UserBadgesRanked ub on cs.DisplayName = (select u.DisplayName from Users u where u.Id = ub.UserId limit 1)
group by cs.PostId, cs.Title, cs.DisplayName, cs.Reputation, cs.TotalComments, cs.HighScoreComments, cs.UpVotes, cs.DownVotes, cs.DistinctEditors, cs.IsMarkedDuplicate, cs.RankByScore
having cs.PopularityCategory in ('Popular', 'Moderate') and cs.TotalComments > 10 and cs.UpVotes > cs.DownVotes
union
select
    p.Id,
    p.Title,
    u.DisplayName,
    u.Reputation,
    0 as TotalComments,
    0 as HighScoreComments,
    0 as UpVotes,
    0 as DownVotes,
    0 as DistinctEditors,
    false as IsMarkedDuplicate,
    99999 as RankByScore,
    null as TopBadges
from Posts p
left join Users u on p.OwnerUserId = u.Id
where p.PostTypeId = 1 and p.ClosedDate is not null and not exists (
    select 1 from ComplexStatistics cs where cs.PostId = p.Id
)
order by RankByScore, Reputation desc, TotalComments desc
limit 50;