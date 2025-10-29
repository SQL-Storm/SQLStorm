-- {"query": "2789.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1006} 
with recursive UserBadgeRankings as (
  select 
    u.Id as UserId,
    u.DisplayName,
    b.Class,
    count(b.Id) as BadgeCount,
    row_number() over (partition by b.Class order by count(b.Id) desc, max(b.Date) desc) as RankByClass
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, b.Class
), LatestAnswers as (
  select 
    p.Id,
    p.ParentId,
    p.Score,
    p.CreationDate,
    p.OwnerUserId,
    row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
  from Posts p
  where p.PostTypeId = 2
), QuestionTagExplode as (
  select
    p.Id as QuestionId,
    trim(tag) as Tag
  from Posts p
  cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as tag
  where p.PostTypeId = 1
), DuplicatePosts as (
  select pl.PostId, pl.RelatedPostId, lt.Name LinkTypeName 
  from PostLinks pl 
  inner join LinkTypes lt on pl.LinkTypeId = lt.Id
  where lt.Name = 'Duplicate'
), ClosedQuestions as (
  select ph.PostId, crt.Name as CloseReason, ph.CreationDate as CloseDate
  from PostHistory ph
  left join CloseReasonTypes crt on ph.Comment::int = crt.Id and ph.PostHistoryTypeId = 10
  where ph.PostHistoryTypeId = 10
), UserActivityWindow as (
  select
    u.Id UserId,
    u.DisplayName,
    count(distinct p.Id) over(partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativePosts,
    count(distinct c.Id) over(partition by u.Id order by c.CreationDate rows between unbounded preceding and current row) as CumulativeComments
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
)
select distinct 
  q.Id as QuestionId,
  q.Title,
  q.CreationDate as QuestionDate,
  q.Score as QuestionScore,
  coalesce(cq.CloseReason, 'Open') as Status,
  string_agg(distinct dt.DuplicateId::text, ',') as DuplicateIds,
  string_agg(distinct qt.Tag, ',') as Tags,
  a.Id as TopAnswerId,
  a.Score as TopAnswerScore,
  a.CreationDate as TopAnswerDate,
  u.DisplayName as QuestionOwner,
  ubr.Class as BadgeClass,
  ubr.BadgeCount,
  ua.RankByClass,
  ua.CumulativePosts,
  ua.CumulativeComments,
  avg(vt.VoteWeight) over (partition by q.Id) as AvgVoteWeight,
  case when length(q.Body) > 1000 then substring(q.Body from 1 for 1000) || '...' else q.Body end as Snippet,
  case when q.Title is null then 'No Title' else upper(q.Title) end as TitleUppercase
from Posts q
left join DuplicatePosts dt on dt.PostId = q.Id
left join ClosedQuestions cq on cq.PostId = q.Id
left join QuestionTagExplode qt on qt.QuestionId = q.Id
left join LatestAnswers a on a.ParentId = q.Id and a.AnswerRank = 1
left join Users u on u.Id = q.OwnerUserId
left join UserBadgeRankings ubr on ubr.UserId = u.Id and ubr.Class = 1
left join UserBadgeRankings ua on ua.UserId = u.Id and ua.Class = ubr.Class
left join UserActivityWindow ua on ua.UserId = u.Id
left join Lateral (
  select 
    v.VoteTypeId,
    case 
      when v.VoteTypeId = 2 then 1.0
      when v.VoteTypeId = 3 then -0.75
      when v.VoteTypeId = 5 then 0.5
      else 0 end as VoteWeight
  from Votes v where v.PostId = q.Id
) vt on true
where q.PostTypeId = 1
  and q.Score > (select avg(p2.Score) from Posts p2 where p2.PostTypeId = 1)
  and array_length(string_to_array(q.Tags, '><'),1) > 1
order by q.Score desc, q.CreationDate desc
limit 50;