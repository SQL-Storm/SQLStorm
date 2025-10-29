with RecursiveUserBadgeCounts as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
    count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName
),
TopContributors as (
  select
    u.UserId,
    u.DisplayName,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    coalesce(p.TotalPosts, 0) as TotalPosts,
    coalesce(p.TotalScore, 0) as TotalScore,
    row_number() over (order by coalesce(p.TotalScore, 0) desc) as Rank
  from RecursiveUserBadgeCounts u
  left join (
    select
      OwnerUserId,
      count(*) as TotalPosts,
      sum(Score) as TotalScore
    from Posts
    where OwnerUserId is not null
    group by OwnerUserId
  ) p on p.OwnerUserId = u.UserId
),
RecentAnswersWindow as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate,
    q.Title as QuestionTitle,
    q.Tags as QuestionTags,
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
  from Posts a
  inner join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
),
BestRecentAnswers as (
  select *
  from RecentAnswersWindow
  where AnswerRank <= 3
),
PostsWithCloseInfo as (
  select p.Id as PostId, p.Title, p.PostTypeId, p.CreationDate, p.ClosedDate,
    cr.Name as CloseReason,
    ph.ClosingUser,
    ph.ClosingDate
  from Posts p
  left join (
    select ph.PostId,
      max(ph.CreationDate) as ClosingDate,
      u.DisplayName as ClosingUser,
      crt.Name
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, u.DisplayName, crt.Name
  ) ph on ph.PostId = p.Id
  left join CloseReasonTypes cr on cr.Name = ph.Name
)
select
  tc.Rank,
  tc.UserId,
  tc.DisplayName,
  concat(tc.GoldBadges, 'G / ', tc.SilverBadges, 'S / ', tc.BronzeBadges, 'B') as BadgeSummary,
  tc.TotalPosts,
  tc.TotalScore,
  pwi.PostId as ClosedPostId,
  pwi.Title as ClosedPostTitle,
  pwi.CloseReason,
  pwi.ClosingUser,
  pwi.ClosingDate,
  bra.AnswerId,
  bra.AnswerScore,
  bra.AnswerCreationDate,
  bra.QuestionTitle,
  bra.QuestionTags,
  length(coalesce(bra.QuestionTags, '')) as TagsLength,
  case
    when bra.QuestionTags is null or bra.QuestionTags = '' then 0
    else array_length(string_to_array(substring(bra.QuestionTags from 2 for length(bra.QuestionTags)-2), '><'), 1)
  end as NumberOfTags,
  round(
    cast(bra.AnswerScore as numeric) /
    greatest(
      extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - bra.AnswerCreationDate)) / 86400,
      1
    ),
    4
  ) as ScorePerDay,
  case
    when pwi.PostId IS NULL THEN 'Open'
    when pwi.CloseReason IS NULL THEN 'Closed (unknown reason)'
    else pwi.CloseReason
  end as CloseStatus
from TopContributors tc
left join PostsWithCloseInfo pwi on pwi.PostId = (
  select p.Id from Posts p
  where p.OwnerUserId = tc.UserId and p.PostTypeId = 1 and p.ClosedDate is not null
  order by p.ClosedDate desc
  limit 1
)
left join BestRecentAnswers bra on bra.AnswerId = (
  select p2.Id from Posts p2
  where p2.OwnerUserId = tc.UserId and p2.PostTypeId = 2
  order by p2.Score desc, p2.CreationDate asc
  limit 1
)
where tc.TotalPosts > 20

union all

select
  9999 as Rank,
  null as UserId,
  'Community' as DisplayName,
  '0G / 0S / 0B' as BadgeSummary,
  0 as TotalPosts,
  0 as TotalScore,
  null as ClosedPostId,
  null as ClosedPostTitle,
  null as CloseReason,
  null as ClosingUser,
  null as ClosingDate,
  null as AnswerId,
  null as AnswerScore,
  null as AnswerCreationDate,
  null as QuestionTitle,
  null as QuestionTags,
  0 as TagsLength,
  0 as NumberOfTags,
  0.0 as ScorePerDay,
  'Special user record' as CloseStatus

order by Rank, TotalScore desc
limit 100;