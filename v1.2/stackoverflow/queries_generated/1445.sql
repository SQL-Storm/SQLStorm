-- {"query": "1445.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 901} 
with RecursiveUserBadges as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    b.Name as BadgeName,
    b.Class,
    row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
  from Users u
  left join Badges b
    on u.Id = b.UserId
  where u.Reputation > 1000
),
LatestPostsByType as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.ParentId,
    p.CreationDate,
    p.Score,
    pt.Name as PostTypeName,
    count(distinct ph.Id) over (partition by p.Id) as HistoryEditsCount,
    dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank
  from Posts p
  join PostTypes pt on pt.Id = p.PostTypeId
  left join PostHistory ph on ph.PostId = p.Id
  where p.Score >= 0
),
UserAverageAnswerScore as (
  select
    OwnerUserId,
    avg(cast(Score as float)) as AvgAnswerScore,
    count(*) as AnswerCount
  from Posts
  where PostTypeId = 2
  group by OwnerUserId
),
TopAnswerersWithTitles as (
  select
    u.Id,
    u.DisplayName,
    ua.AvgAnswerScore,
    ua.AnswerCount,
    string_agg(
      replace(regexp_replace( coalesce(left(nullif(p.Title,''),40), '(no title)'), '[\n\r]+', ' ', 'g'),'''',''''''), 
      '; '
      order by p.CreationDate desc
    ) filter(where p.Title is not null) as RecentAnswerTitles
  from Users u
  join UserAverageAnswerScore ua on ua.OwnerUserId = u.Id
  left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 2
  where ua.AnswerCount > 3
  group by u.Id, u.DisplayName, ua.AvgAnswerScore, ua.AnswerCount
),
PostsWithDuplicateLinkedData as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.Score,
    l.LinkTypeId,
    lt.Name as LinkTypeName,
    dup.Title as DuplicateOfTitle
  from Posts p
  left join PostLinks l on l.PostId = p.Id and l.LinkTypeId = 3
  left join Posts dup on dup.Id = l.RelatedPostId
  left join LinkTypes lt on lt.Id = l.LinkTypeId
  where p.PostTypeId = 1
),
FinalSelectedData as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    lub.BadgeName,
    lub.Class as BadgeClass,
    TAT.AvgAnswerScore,
    TAT.AnswerCount,
    TAT.RecentAnswerTitles,
    pwpd.Title as QuestionTitle,
    pwpd.Score as QuestionScore,
    pwpd.DuplicateOfTitle,
    pwpd.LinkTypeName,
    row_number() over (partition by u.Id order by pwpd.Score desc nulls last) as QuestionRank
  from Users u
  left join RecursiveUserBadges lub on lub.UserId = u.Id and lub.BadgeRank = 1
  left join TopAnswerersWithTitles TAT on TAT.Id = u.Id
  left join PostsWithDuplicateLinkedData pwpd on pwpd.Id in (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 limit 5
  )
  where u.DisplayName is not null and u.Reputation > 2000
)
select * from FinalSelectedData
where QuestionRank <= 3
union all
select
  cast(null as int),
  'Summary Total',
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  null,
  count(distinct u.Id)
from Users u
where u.Reputation > 2000
order by DisplayName nulls last, QuestionScore desc nulls last;