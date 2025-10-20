with recursive RecursiveUserBadgeCounts as (
  select
    u.Id as UserId,
    u.DisplayName,
    b.Class,
    count(*) as BadgeCount
  from Users u
  left join Badges b on u.Id = b.UserId
  group by u.Id, u.DisplayName, b.Class
  union all
  select
    r.UserId,
    r.DisplayName,
    r.Class,
    r.BadgeCount + 1
  from RecursiveUserBadgeCounts r
  where r.BadgeCount < 3
),
QuestionAnswerStats as (
  select
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.CreationDate as QuestionCreation,
    coalesce(q.AnswerCount,0) as TotalAnswers,
    coalesce(max(a.Score),0) as MaxAnswerScore,
    avg(a.Score) as AvgAnswerScore,
    count(a.Id) filter (where a.Score > 0) as PosAnswerCount,
    count(pv.Id) as ViewsRecorded
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Votes pv on pv.PostId = q.Id and pv.VoteTypeId = 2
  where q.PostTypeId = 1 and q.ClosedDate is null
  group by q.Id, q.Title, q.OwnerUserId, q.CreationDate, q.AnswerCount
),
RankedQuestions as (
  select
    QuestionId,
    Title,
    OwnerUserId,
    QuestionCreation,
    TotalAnswers,
    MaxAnswerScore,
    coalesce(AvgAnswerScore,0) as AvgAnswerScore,
    PosAnswerCount,
    ViewsRecorded,
    row_number() over (partition by OwnerUserId order by TotalAnswers desc, MaxAnswerScore desc, ViewsRecorded desc) as OwnerTopQuestionRank
  from QuestionAnswerStats
),
RecentHighlyVotedQuestions as (
  select *
  from RankedQuestions
  where OwnerTopQuestionRank = 1
    and QuestionCreation > (timestamp '2024-10-01 12:34:56' - interval '180 days')
    and ViewsRecorded > 10
),
CorrelatedAnswerUsers as (
  select distinct
    r.QuestionId,
    a.OwnerUserId as AnswerUserId,
    u.Reputation,
    u.Location,
    u.CreationDate as UserCreated,
    (select count(*) from Badges b2 where b2.UserId = a.OwnerUserId and b2.Class = 1) as GoldBadges,
    (select count(*) from Badges b3 where b3.UserId = a.OwnerUserId and b3.Class = 2) as SilverBadges,
    (select count(*) from Badges b4 where b4.UserId = a.OwnerUserId and b4.Class = 3) as BronzeBadges
  from RecentHighlyVotedQuestions r
  join Posts a on a.ParentId = r.QuestionId and a.PostTypeId = 2
  join Users u on u.Id = a.OwnerUserId
),
WindowedAnswerDistribution as (
  select
    a.QuestionId,
    a.AnswerUserId,
    a.Reputation,
    a.Location,
    a.UserCreated,
    a.GoldBadges,
    a.SilverBadges,
    a.BronzeBadges,
    dense_rank() over (partition by a.QuestionId order by a.Reputation desc) as ReputationRank,
    count(*) over (partition by a.QuestionId) as AnswerCountPerQuestion
  from CorrelatedAnswerUsers a
),
UniqueTagPairs as (
  select distinct
    lower(trim(first_tags.Tag1)) as Tag1,
    lower(trim(second_tags.t2)) as Tag2
  from (
    select unnest(string_to_array(substring(pt.Tags from 2 for length(pt.Tags) - 2), '><')) as Tag1,
           pt.Id as pt_id
    from Posts pt
    where pt.PostTypeId = 1 and pt.Tags is not null
  ) first_tags
  cross join lateral (
    select unnest(string_to_array(substring(pt2.Tags from 2 for length(pt2.Tags) - 2), '><')) as t2
    from Posts pt2
    where pt2.PostTypeId = 1 and pt2.Tags is not null
  ) second_tags
  where first_tags.Tag1 < second_tags.t2 and second_tags.t2 is not null
),
ActiveUserQuestionLinkCount as (
  select
    u.Id as UserId,
    count(pl.Id) filter (where pl.LinkTypeId = 1) as LinkedPostsCount,
    count(pl.Id) filter (where pl.LinkTypeId = 3) as DuplicatePostsCount,
    max(pl.CreationDate) as LastLinkDate
  from Users u
  left join Posts p1 on p1.OwnerUserId = u.Id and p1.PostTypeId = 1
  left join PostLinks pl on pl.PostId = p1.Id or pl.RelatedPostId = p1.Id
  where u.Reputation > 5000
  group by u.Id
)
select
  rqt.QuestionId,
  rqt.Title,
  u.DisplayName as QuestionOwner,
  rqt.TotalAnswers,
  rqt.MaxAnswerScore,
  round(rqt.AvgAnswerScore::numeric,2) as AvgAnswerScore,
  rqt.PosAnswerCount,
  rqt.ViewsRecorded,
  string_agg(distinct c.Location, ', ' order by c.Location) as AnswererLocations,
  count(distinct c.AnswerUserId) as DistinctAnswerers,
  sum(case when c.GoldBadges > 0 then 1 else 0 end) as AnswerersWithGolds,
  sum(case when c.SilverBadges > 0 then 1 else 0 end) as AnswerersWithSilvers,
  max(wad.ReputationRank) as MaxAnswererReputationRank,
  coalesce(auc.LinkedPostsCount, 0) as UserLinkedPosts,
  coalesce(auc.DuplicatePostsCount, 0) as UserDuplicates,
  auc.LastLinkDate
from RecentHighlyVotedQuestions rqt
join Users u on u.Id = rqt.OwnerUserId
left join WindowedAnswerDistribution wad on wad.QuestionId = rqt.QuestionId
left join CorrelatedAnswerUsers c on c.AnswerUserId = wad.AnswerUserId and c.QuestionId = rqt.QuestionId
left join ActiveUserQuestionLinkCount auc on auc.UserId = rqt.OwnerUserId
group by rqt.QuestionId, rqt.Title, u.DisplayName, rqt.TotalAnswers, rqt.MaxAnswerScore, rqt.AvgAnswerScore, rqt.PosAnswerCount, rqt.ViewsRecorded, auc.LinkedPostsCount, auc.DuplicatePostsCount, auc.LastLinkDate
having count(distinct c.AnswerUserId) > 3 and max(wad.ReputationRank) <= 10
order by rqt.ViewsRecorded desc NULLS LAST, rqt.TotalAnswers desc
limit 25;