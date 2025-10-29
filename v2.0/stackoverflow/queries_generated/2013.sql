-- {"query": "2013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412} 
with RecursivePostsCTE as (
    select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.OwnerUserId,
           1 as Level,
           coalesce(p.Score * 1.0 / nullif(p.ViewCount, 0), 0) as ScoreViewRatio
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select p.Id, p.PostTypeId, p.AcceptedAnswerId, p.ParentId, p.CreationDate, p.Score, p.ViewCount, p.Title, p.OwnerUserId,
           rp.Level + 1 as Level,
           coalesce(p.Score * 1.0 / nullif(p.ViewCount, 0), 0) as ScoreViewRatio
    from Posts p
    inner join RecursivePostsCTE rp on p.ParentId = rp.Id
    where p.PostTypeId = 2 -- answers only
),
RankedAnswers as (
    select rp.*, 
           row_number() over (partition by rp.ParentId order by rp.Score desc, rp.CreationDate asc) as AnswerRank,
           count(*) over (partition by rp.ParentId) as TotalAnswers
    from RecursivePostsCTE rp
    where rp.PostTypeId = 2
),
UserPostStats as (
    select u.Id as UserId, u.DisplayName,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
           avg(coalesce(p.Score, 0)) as AvgPostScore,
           max(p.Score) as MaxPostScore,
           min(p.Score) as MinPostScore,
           bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
TopCommenters as (
    select c.UserId, u.DisplayName, count(*) as CommentCount
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
    having count(*) > 10
),
PostWithLatestHistory as (
    select ph.PostId, ph.UserId, ph.PostHistoryTypeId, ph.CreationDate,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
),
LatestPostHistoryFiltered as (
    select ph.PostId, ph.UserId, ph.PostHistoryTypeId, ph.CreationDate
    from PostWithLatestHistory ph
    where ph.rn = 1
),
PostsWithLinks as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkTypeName,
           p1.CreationDate as PostCreation,
           p2.CreationDate as RelatedPostCreation
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
),
QuestionsWithDuplicateAnswers as (
    select p.Id as QuestionId, p.Title, count(distinct la.Id) as DuplicateAnswerCount
    from Posts p
    left join Posts la on la.ParentId = p.Id and la.Score > 10
    where p.PostTypeId = 1 and p.ClosedDate is null
    group by p.Id, p.Title
    having count(distinct la.Id) > 2
)
select u.DisplayName as UserDisplayName,
       ups.QuestionCount,
       ups.AnswerCount,
       ups.UpVotesCount,
       ups.DownVotesCount,
       ups.AvgPostScore,
       ups.MaxPostScore,
       ups.MinPostScore,
       case when ups.HasClosedPosts then 'Yes' else 'No' end as HasClosedPosts,
       coalesce(tc.CommentCount, 0) as CommentsMade,
       qwa.DuplicateAnswerCount,
       string_agg(distinct case when pt.Name is not null then pt.Name else 'Unknown' end, ', ' order by pt.Name) as PostTypesOwned,
       avg(rp.ScoreViewRatio) as AverageScoreViewRatio,
       lmph.PostHistoryTypeId as LatestPostHistoryType,
       limt.Name as LatestPostHistoryTypeName,
       coalesce(pl.LinkTypeName, 'No Link') as SampleLinkTypeName,
       coalesce(pl.Name, 'No Link') as LinkTypeFullName
from UserPostStats ups
join Users u on u.Id = ups.UserId
left join TopCommenters tc on tc.UserId = u.Id
left join (
    select OwnerUserId, count(distinct PostTypeId) as DistinctPostTypesCount, string_agg(distinct Pt.Name, ', ') as Name
    from Posts p
    join PostTypes Pt on Pt.Id = p.PostTypeId
    where OwnerUserId is not null and OwnerUserId > 0
    group by OwnerUserId
) pt on pt.OwnerUserId = u.Id
left join RecursivePostsCTE rp on rp.OwnerUserId = u.Id and rp.Level = 1
left join LatestPostHistoryFiltered lmph on lmph.UserId = u.Id
left join PostHistoryTypes limt on limt.Id = lmph.PostHistoryTypeId
left join PostsWithLinks pl on pl.PostId = (select min(Id) from Posts where OwnerUserId = u.Id and Id is not null)
left join QuestionsWithDuplicateAnswers qwa on qwa.QuestionId = (select min(Id) from Posts where OwnerUserId = u.Id and PostTypeId = 1)
where ups.QuestionCount + ups.AnswerCount > 5
group by u.DisplayName, ups.QuestionCount, ups.AnswerCount, ups.UpVotesCount, ups.DownVotesCount,
         ups.AvgPostScore, ups.MaxPostScore, ups.MinPostScore, ups.HasClosedPosts,
         tc.CommentCount, qwa.DuplicateAnswerCount, lmph.PostHistoryTypeId, limt.Name,
         coalesce(pl.LinkTypeName, 'No Link'), coalesce(pl.Name, 'No Link')
order by ups.UpVotesCount desc, AverageScoreViewRatio desc
limit 50;