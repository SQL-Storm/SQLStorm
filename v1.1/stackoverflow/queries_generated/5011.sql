-- {"query": "5011.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1010} 
with RecentBadges as (
  select
    b.UserId,
    b.Name as BadgeName,
    b.Date as BadgeDate,
    dense_rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
  from Badges b
  where b.Date >= now() - interval '90 days'
),
ActiveQuestions as (
  select
    p.Id as QuestionId,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Title,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    qclose.CreationDate as ClosedDate,
    qclose.Comment as CloseReason
  from Posts p
  left join (
    select ph.PostId, ph.CreationDate, cr.Name as Comment
    from PostHistory ph
    join CloseReasonTypes cr on try_cast(ph.Comment as int)=cr.Id
    where ph.PostHistoryTypeId = 10
  ) qclose on p.Id = qclose.PostId
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '180 days'
    and (qclose.CreationDate is null or qclose.CreationDate >= now() - interval '180 days')
),
AnswersPerQuestion as (
  select
    a.ParentId as QuestionId,
    count(*) as AnswerCount,
    avg(a.Score) as AvgAnswerScore
  from Posts a
  where a.PostTypeId = 2
  group by a.ParentId
),
UserAggregates as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.Location,
    coalesce(sum(p.Score), 0) as TotalPostScore,
    count(distinct p.Id) as TotalPosts,
    max(p.CreationDate) as LastPostDate
  from Users u
  left join Posts p on u.Id = p.OwnerUserId
  where u.Reputation > 1000
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
)
select
  qa.QuestionId,
  qa.Title,
  qa.Tags,
  qa.CreationDate as QuestionCreationDate,
  qa.Score as QuestionScore,
  (coalesce(qa.ViewCount,0)::float / greatest(extract(day from now()-qa.CreationDate),1)) as AvgViewsPerDay,
  substring(qa.Title from 1 for 100) as TitleSample,
  qa.AnswerCount as UndeletedAnswerCount,
  apq.AnswerCount as TotalAnswerCount,
  coalesce(apq.AvgAnswerScore,0) as AvgAnswerScore,
  uagg.UserId,
  uagg.DisplayName as Author,
  uagg.Reputation as AuthorReputation,
  uagg.Location as AuthorLocation,
  uagg.TotalPostScore as AuthorTotalPostScore,
  badge.BadgeName as RecentBadge,
  badge.BadgeDate as BadgeAwardedDate,
  qa.ClosedDate,
  qa.CloseReason,
  case
    when qa.ClosedDate is not null then 'Closed'
    when apq.AnswerCount > 5 and qa.Score > 5 then 'Popular'
    when qa.Score < 0 then 'Controversial'
    else 'Active'
  end as QuestionStatus,
  lead(qa.CreationDate) over (order by qa.CreationDate) as NextQuestionDate,
  (select count(1) from Comments c where c.PostId = qa.QuestionId) as CommentCount,
  (select string_agg(distinct t.TagName, ', ') 
   from Tags t
   where t.TagName = any (string_to_array(substring(qa.Tags,2,length(qa.Tags)-2), '><'))) as TagNames,
  case
    when exists (
      select 1 from PostLinks pl 
      where (pl.PostId = qa.QuestionId or pl.RelatedPostId = qa.QuestionId)
        and pl.LinkTypeId = 3
    ) then 'Duplicate'
    else 'Unique'
  end as DupStatus
from ActiveQuestions qa
left join AnswersPerQuestion apq on qa.QuestionId = apq.QuestionId
left join UserAggregates uagg on qa.OwnerUserId = uagg.UserId
left join RecentBadges badge on badge.UserId = qa.OwnerUserId and badge.BadgeRank = 1
where qa.Score >= (
    select percentile_disc(0.75) within group (order by Score) 
    from ActiveQuestions
  )
  and (uagg.UserId is not null or qa.OwnerUserId is null)
order by coalesce(apq.AnswerCount,0) desc, AvgViewsPerDay desc
limit 100;