-- {"query": "101.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2274} 
with
RecentPosts as (
  select p.*
  from Posts p
  where p.CreationDate >= now() - interval '365 days'
),
UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    coalesce(sum(case when p.PostTypeId = 1 then 1 end),0) as QuestionsAsked,
    coalesce(sum(case when p.PostTypeId = 2 then 1 end),0) as AnswersGiven,
    coalesce(avg(case when p.PostTypeId in (1,2) then p.Score end),0)::numeric(12,4) as AvgPostScore,
    coalesce(sum(case when p.PostTypeId in (1,2) and p.CreationDate >= now() - interval '30 days' then 1 end),0) as RecentContributions,
    max(p.LastActivityDate) as LastActivityDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
TagExplode as (
  select
    p.Id as PostId,
    u.Id as OwnerUserId,
    trim(t.tag) as Tag
  from Posts p
  join Users u on u.Id = p.OwnerUserId
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,'')) - 2,0)),'><')) as tag
  ) t
  where p.Tags is not null and p.Tags <> ''
),
UserTagStats as (
  select
    te.OwnerUserId as UserId,
    count(distinct te.Tag) as DistinctTagCount,
    count(*) as TagOccurrences,
    array_agg(distinct te.Tag order by te.Tag) filter (where te.Tag is not null) as TagsList
  from TagExplode te
  group by te.OwnerUserId
),
AcceptedAnswerTimes as (
  select
    q.Id as QuestionId,
    q.OwnerUserId as QuestionOwner,
    q.CreationDate as QuestionCreated,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwner,
    a.CreationDate as AnswerCreated,
    extract(epoch from (a.CreationDate - q.CreationDate))/3600.0 as HoursToAnswer,
    extract(epoch from (coalesce((select p2.CreationDate from Posts p2 where p2.Id = q.AcceptedAnswerId), a.CreationDate) - q.CreationDate))/3600.0 as HoursToAccepted
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
    and (q.AcceptedAnswerId is not null or a.Id is not null)
),
UserAcceptedAgg as (
  select
    coalesce(qat.QuestionOwner, a.OwnerUserId, q.OwnerUserId) as UserId,
    count(distinct qat.QuestionId) filter (where qat.AnswerId is not null) as AnswersContributing,
    avg(qat.HoursToAnswer) filter (where qat.HoursToAnswer is not null) as AvgHoursToAnswer,
    avg(qat.HoursToAccepted) filter (where qat.HoursToAccepted is not null) as AvgHoursToAccepted,
    percentile_cont(0.5) within group (order by qat.HoursToAnswer) filter (where qat.HoursToAnswer is not null) as MedianHoursToAnswer
  from AcceptedAnswerTimes qat
  left join Posts a on a.Id = qat.AnswerId
  left join Posts q on q.Id = qat.QuestionId
  group by coalesce(qat.QuestionOwner, a.OwnerUserId, q.OwnerUserId)
),
BadgeWeight as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 10 when b.Class = 2 then 3 when b.Class = 3 then 1 else 0 end) as BadgeScore,
    count(*) as TotalBadges,
    count(distinct b.Name) as DistinctBadges
  from Badges b
  group by b.UserId
),
VoteSignals as (
  select
    v.PostId,
    p.OwnerUserId,
    sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCount,
    count(*) as VoteEvents
  from Votes v
  join Posts p on p.Id = v.PostId
  group by v.PostId, p.OwnerUserId
),
UserVoteAgg as (
  select
    OwnerUserId as UserId,
    sum(NetVotes) as UserNetVotes,
    sum(FavoriteCount) as UserFavorites,
    sum(VoteEvents) as UserVoteEvents
  from VoteSignals
  group by OwnerUserId
),
UserCombined as (
  select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.AvgPostScore,
    ua.RecentContributions,
    uts.DistinctTagCount,
    uts.TagOccurrences,
    coalesce(bw.BadgeScore,0) as BadgeScore,
    coalesce(uv.UserNetVotes,0) as UserNetVotes,
    coalesce(ua.RecentContributions,0) + coalesce(bw.BadgeScore,0) * 0.1 + coalesce(uv.UserNetVotes,0) * 0.05 as HeuristicActivityScore,
    uat.AvgHoursToAnswer,
    uat.MedianHoursToAnswer,
    ua.LastActivityDate,
    coalesce(uts.TagsList, array[]::varchar[]) as TagsList
  from UserActivity ua
  left join UserTagStats uts on uts.UserId = ua.UserId
  left join BadgeWeight bw on bw.UserId = ua.UserId
  left join UserVoteAgg uv on uv.UserId = ua.UserId
  left join UserAcceptedAgg uat on uat.UserId = ua.UserId
),
TopCandidates as (
  select *,
    row_number() over (order by HeuristicActivityScore desc nulls last, Reputation desc) as rn
  from UserCombined
),
-- suspicious set built via set operators (union/intersect/except)
HighReputation as (
  select Id from Users where Reputation >= 10000
),
HighBadges as (
  select UserId as Id from Badges group by UserId having count(*) >= 50
),
RecentlyActive as (
  select Id from Users where LastAccessDate >= now() - interval '90 days'
),
SuspiciousUsers as (
  -- users who are high rep and high badges but not recently active, plus some who have high net votes without badges
  (select Id from HighReputation intersect select Id from HighBadges)
  except
  (select Id from RecentlyActive)
  union
  (select UserId from UserVoteAgg where UserNetVotes > 1000 and UserId not in (select Id from HighBadges))
),
-- final selection with correlated subqueries and complex expressions
FinalSelection as (
  select
    tc.UserId,
    tc.DisplayName,
    tc.Reputation,
    tc.QuestionsAsked,
    tc.AnswersGiven,
    tc.AvgPostScore,
    tc.DistinctTagCount,
    tc.TagOccurrences,
    tc.BadgeScore,
    tc.UserNetVotes,
    tc.AvgHoursToAnswer,
    tc.MedianHoursToAnswer,
    tc.HeuristicActivityScore,
    tc.TagsList,
    case when s.Id is not null then true else false end as IsSuspicious,
    -- correlated subquery: most recent comment on any of user's posts
    (select c.Text from Comments c join Posts p on p.Id = c.PostId where p.OwnerUserId = tc.UserId order by c.CreationDate desc limit 1) as LatestCommentText,
    -- string expression: concat top 5 tags
    (select string_agg(distinct t.tag, ', ' order by t.tag) from (
        select unnest(tc.TagsList) as tag
     ) t limit 5) as TopTags,
    -- complex null logic & arithmetic
    coalesce(tc.AvgHoursToAnswer, 99999) / nullif(coalesce(tc.MedianHoursToAnswer, tc.AvgHoursToAnswer, 1),0) as AnswerDispersion,
    -- window function: rank by heuristic within suspicious flag groups
    rank() over (partition by case when s.Id is not null then 1 else 0 end order by tc.HeuristicActivityScore desc) as PartitionRank
  from TopCandidates tc
  left join SuspiciousUsers s on s.Id = tc.UserId
  where tc.rn <= 200
)
select
  fs.*,
  -- enrich with an existence correlated boolean and a final classification
  case
    when fs.IsSuspicious and fs.AnswerDispersion > 10 then 'HighRisk'
    when fs.IsSuspicious then 'Watch'
    when fs.HeuristicActivityScore > 50 then 'Champion'
    when fs.HeuristicActivityScore between 10 and 50 then 'Active'
    else 'Occasional'
  end as Classification
from FinalSelection fs
order by Classification desc, HeuristicActivityScore desc, Reputation desc
limit 100;