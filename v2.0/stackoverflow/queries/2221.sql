with RankedAnswers as (
  select 
    a.Id,
    a.ParentId,
    a.Score,
    a.CreationDate,
    a.OwnerUserId,
    u.Reputation as OwnerReputation,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
    count(*) over (partition by a.ParentId) as AnswerCountForQuestion
  from Posts a
  left join Users u on a.OwnerUserId = u.Id
  where a.PostTypeId = 2
),
QuestionInfo as (
  select
    q.Id as QuestionId,
    q.Title,
    q.ViewCount,
    q.Score as QuestionScore,
    q.OwnerUserId,
    q.AcceptedAnswerId,
    u.DisplayName as QuestionOwnerName,
    u.Reputation as QuestionOwnerReputation,
    q.Tags,
    coalesce(q.AnswerCount, 0) as AnswerCount,
    q.CreationDate,
    q.ClosedDate
  from Posts q
  left join Users u on q.OwnerUserId = u.Id
  where q.PostTypeId = 1
),
TopAnswerDetails as (
  select
    ra.ParentId as QuestionId,
    ra.Id as AnswerId,
    ra.Score as AnswerScore,
    ra.CreationDate as AnswerCreationDate,
    ra.OwnerUserId as AnswerOwnerUserId,
    ra.OwnerReputation as AnswerOwnerReputation,
    ra.AnswerRank
  from RankedAnswers ra
  where ra.AnswerRank = 1
),
BadgeSummary as (
  select
    UserId,
    sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
  from Badges
  group by UserId
),
RecentComments as (
  select
    c.PostId,
    string_agg(
      concat_ws(': ', coalesce(c.UserDisplayName, 'Anonymous'), left(replace(replace(c.Text, chr(10), ' '), chr(13), ' '), 50)),
      ' || '
      order by c.CreationDate desc
    ) as CommentsPreview
  from Comments c
  where c.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
  group by c.PostId
),
ClosedReasons as (
  select
    ph.PostId,
    string_agg(distinct crt.Name, ', ') as CloseReasons
  from PostHistory ph
  left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id and ph.PostHistoryTypeId = 10
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
)
select
  qi.QuestionId,
  left(qi.Title, 120) as QuestionTitleSnippet,
  qi.ViewCount,
  qi.QuestionScore,
  qi.QuestionOwnerName,
  bq.GoldBadges as QuestionOwnerGoldBadges,
  bq.SilverBadges as QuestionOwnerSilverBadges,
  bq.BronzeBadges as QuestionOwnerBronzeBadges,
  ta.AnswerId as TopAnswerId,
  ta.AnswerScore,
  ta.AnswerCreationDate,
  uans.DisplayName as TopAnswerOwnerName,
  bu.GoldBadges as AnswerOwnerGoldBadges,
  bu.SilverBadges as AnswerOwnerSilverBadges,
  bu.BronzeBadges as AnswerOwnerBronzeBadges,
  rc.CommentsPreview,
  cr.CloseReasons,
  case 
    when qi.ClosedDate is not null then 'Closed' 
    else 'Open' 
  end as QuestionStatus,
  -- popularity score expressed as numeric using standard cast
  cast((coalesce(qi.ViewCount,0) * 0.1 + coalesce(qi.QuestionScore,0) * 2 + coalesce(ta.AnswerScore,0) * 3 + coalesce(bq.GoldBadges,0)*5) as numeric(10,2)) as PopularityScore,
  -- window function for ranking within all questions by popularity
  rank() over (
    order by (coalesce(qi.ViewCount,0) * 0.1 + coalesce(qi.QuestionScore,0) * 2 + coalesce(ta.AnswerScore,0) * 3 + coalesce(bq.GoldBadges,0)*5) desc
  ) as PopularityRank
from QuestionInfo qi
left join TopAnswerDetails ta on qi.QuestionId = ta.QuestionId
left join Users uans on ta.AnswerOwnerUserId = uans.Id
left join BadgeSummary bq on qi.OwnerUserId = bq.UserId
left join BadgeSummary bu on ta.AnswerOwnerUserId = bu.UserId
left join RecentComments rc on qi.QuestionId = rc.PostId
left join ClosedReasons cr on qi.QuestionId = cr.PostId
where 
  qi.CreationDate > cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
  and (qi.AnswerCount >= 2 or qi.AcceptedAnswerId is not null)
  and (qi.Tags is not null and qi.Tags <> '')
  and (
    position(lower('<sql>') in lower(qi.Tags)) > 0 
    or position(lower('<database>') in lower(qi.Tags)) > 0
  )
group by
  qi.QuestionId,
  qi.Title,
  qi.ViewCount,
  qi.QuestionScore,
  qi.QuestionOwnerName,
  bq.GoldBadges,
  bq.SilverBadges,
  bq.BronzeBadges,
  ta.AnswerId,
  ta.AnswerScore,
  ta.AnswerCreationDate,
  uans.DisplayName,
  bu.GoldBadges,
  bu.SilverBadges,
  bu.BronzeBadges,
  rc.CommentsPreview,
  cr.CloseReasons,
  qi.ClosedDate,
  qi.CreationDate,
  qi.Tags,
  qi.AnswerCount,
  qi.AcceptedAnswerId
order by PopularityRank
limit 100;