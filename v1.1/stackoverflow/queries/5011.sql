with RecentBadges as (
  select
    b.UserId,
    b.Name as BadgeName,
    b.Date as BadgeDate,
    dense_rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
  from Badges b
  where b.Date >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
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
    qclose.CloseReason
  from Posts p
  left join (
    select ph.PostId, ph.CreationDate, cr.Name as CloseReason
    from PostHistory ph
    join CloseReasonTypes cr on (case when ph.Comment ~ '^\d+$' then cast(ph.Comment as integer) else null end) = cr.Id
    where ph.PostHistoryTypeId = 10
  ) qclose on p.Id = qclose.PostId
  where p.PostTypeId = 1
    and p.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
    and (qclose.CreationDate is null or qclose.CreationDate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days')
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
  (coalesce(qa.ViewCount,0) / nullif(greatest(extract(day from cast('2024-10-01 12:34:56' as timestamp) - qa.CreationDate),1),0)) as AvgViewsPerDay,
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
    when coalesce(apq.AnswerCount,0) > 5 and qa.Score > 5 then 'Popular'
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
group by
  qa.QuestionId,
  qa.Title,
  qa.Tags,
  qa.CreationDate,
  qa.Score,
  qa.ViewCount,
  qa.AnswerCount,
  apq.AnswerCount,
  apq.AvgAnswerScore,
  uagg.UserId,
  uagg.DisplayName,
  uagg.Reputation,
  uagg.Location,
  uagg.TotalPostScore,
  badge.BadgeName,
  badge.BadgeDate,
  qa.ClosedDate,
  qa.CloseReason,
  qa.OwnerUserId
order by coalesce(apq.AnswerCount,0) desc, AvgViewsPerDay desc
limit 100;