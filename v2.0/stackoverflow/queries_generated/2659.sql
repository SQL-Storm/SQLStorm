-- {"query": "2659.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1556} 
with RecursiveTagHierarchy as (
  select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, 0 as Level
  from Tags t
  where t.IsRequired = 1
  union all
  select t.Id, t.TagName, t.Count, t.ExcerptPostId, t.WikiPostId, r.Level + 1
  from Tags t
  join RecursiveTagHierarchy r on t.Id = r.Id and r.Level < 3
),
TopUsers as (
  select u.Id, u.DisplayName, u.Reputation,
    row_number() over (order by u.Reputation desc) as rn
  from Users u
  where u.Reputation > 1000
),
PostScoreStats as (
  select p.OwnerUserId,
    count(*) as total_posts,
    sum(coalesce(p.Score,0)) as total_score,
    avg(coalesce(p.Score, 0)) as avg_score,
    max(coalesce(p.Score, 0)) as max_score,
    min(coalesce(p.Score, 0)) as min_score
  from Posts p
  where p.PostTypeId in (1,2)
  group by p.OwnerUserId
),
UserBadgeSummary as (
  select b.UserId,
    count(*) filter (where b.Class = 1) as gold_badges,
    count(*) filter (where b.Class = 2) as silver_badges,
    count(*) filter (where b.Class = 3) as bronze_badges,
    count(distinct b.Name) as distinct_badge_names
  from Badges b
  group by b.UserId
),
UserActivityWindow as (
  select 
    p.OwnerUserId,
    p.Id as PostId,
    p.CreationDate,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as cumulative_upvotes,
    row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn_desc
  from Posts p
  left join Votes v on v.PostId = p.Id
  where p.PostTypeId in (1,2)
),
ClosedQuestionsWithReason as (
  select distinct p.Id, p.Title, ph.Comment, crt.Name as CloseReasonName, p.OwnerUserId, p.CreationDate
  from Posts p
  left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
  left join CloseReasonTypes crt on crt.Id::int = ph.Comment::int -- assuming Comment holds close reason id
  where p.PostTypeId = 1 and p.ClosedDate is not null
),
UserQuestionsWithAcceptedAnswers as (
  select q.Id as QuestionId, q.OwnerUserId, q.Title, a.Id as AcceptedAnswerId, a.Score as AcceptedAnswerScore,
    coalesce((select count(*) from Comments c where c.PostId = q.Id), 0) as QuestionComments,
    coalesce((select count(*) from Comments c where c.PostId = a.Id), 0) as AcceptedAnswerComments
  from Posts q
  left join Posts a on a.Id = q.AcceptedAnswerId
  where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserDuplicateLinkCount as (
  select p.OwnerUserId, count(distinct pl.Id) as DuplicateLinkCount
  from Posts p
  join PostLinks pl on pl.PostId = p.Id
  where pl.LinkTypeId = 3
  group by p.OwnerUserId
  having count(distinct pl.Id) > 0
),
UserAggregatedStats AS (
  select u.Id as UserId, u.DisplayName,
    coalesce(pss.total_posts,0) as TotalPosts,
    coalesce(pss.total_score,0) as TotalScore,
    coalesce(pss.avg_score,0) as AvgScore,
    coalesce(ubs.gold_badges,0) as GoldBadges,
    coalesce(ubs.silver_badges,0) as SilverBadges,
    coalesce(ubs.bronze_badges,0) as BronzeBadges,
    coalesce(ubs.distinct_badge_names,0) as DistinctBadges,
    coalesce(udlc.DuplicateLinkCount, 0) as DuplicateLinks,
    case when u.WebsiteUrl is not null and length(u.WebsiteUrl) > 0 then
      regexp_replace(lower(u.WebsiteUrl), '^https?://(www\.)?', '')
    else 'no website'
    end as NormalizedWebsite,
    count(distinct ph.PostHistoryTypeId) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenCounts
  from Users u
  left join PostScoreStats pss on pss.OwnerUserId = u.Id
  left join UserBadgeSummary ubs on ubs.UserId = u.Id
  left join UserDuplicateLinkCount udlc on udlc.OwnerUserId = u.Id
  left join PostHistory ph on ph.UserId = u.Id
  group by u.Id, u.DisplayName, pss.total_posts, pss.total_score, pss.avg_score, ubs.gold_badges,
    ubs.silver_badges, ubs.bronze_badges, ubs.distinct_badge_names, udlc.DuplicateLinkCount, u.WebsiteUrl
)
select uas.UserId, uas.DisplayName, uas.TotalPosts, uas.TotalScore, uas.AvgScore,
  uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.DistinctBadges, uas.DuplicateLinks,
  uas.NormalizedWebsite, uas.CloseReopenCounts,
  row_number() over (order by uas.TotalScore desc, uas.TotalPosts desc) as UserRank,
  (select count(*) from UserQuestionsWithAcceptedAnswers uq where uq.OwnerUserId = uas.UserId) as QuestionsWithAcceptedAnswers,
  (select avg(uq.AcceptedAnswerScore) from UserQuestionsWithAcceptedAnswers uq where uq.OwnerUserId = uas.UserId) as AvgAcceptedAnswerScore,
  (select string_agg(distinct ph.Name, ', ') from PostHistoryTypes ph where ph.Id in (
    select distinct ph2.PostHistoryTypeId from PostHistory ph2 where ph2.UserId = uas.UserId and ph2.PostHistoryTypeId in (10,11,12)
  )) as HistoryTypesInvolved,
  (select count(*) from ClosedQuestionsWithReason cqr where cqr.OwnerUserId = uas.UserId) as ClosedQuestions,
  (select string_agg(distinct cqr.CloseReasonName, ', ') from ClosedQuestionsWithReason cqr where cqr.OwnerUserId = uas.UserId) as CloseReasons,
  (select count(distinct c.Id) from Comments c where c.UserId = uas.UserId) as TotalComments,
  (select max(p.CreationDate) from Posts p where p.OwnerUserId = uas.UserId) as LastPostDate,
  (select count(*) from Posts p2 where p2.OwnerUserId = uas.UserId and p2.Tags like '%<sql>%') as SqlTaggedPosts
from UserAggregatedStats uas
where uas.TotalPosts > 50
order by UserRank
limit 100;