with
q as (
  select p.Id as QuestionId,
         p.OwnerUserId as AskerId,
         p.CreationDate as QuestionCreation,
         p.Score as QuestionScore,
         p.ViewCount,
         p.Title,
         p.Tags,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreation
  from Posts a
  where a.PostTypeId = 2
),
q_activity as (
  select ph.PostId as QuestionId,
         min(case when ph.PostHistoryTypeId in (10,35) then ph.CreationDate end) as FirstCloseOrMigrate,
         count(case when ph.PostHistoryTypeId in (24) then 1 end) as SuggestedEditsApplied,
         sum(case when ph.PostHistoryTypeId = 10 and (ph.Comment ~ '^[0-9]+$') then 1 else 0 end) as CloseVotesWithReason,
         max(case when ph.PostHistoryTypeId = 52 then ph.CreationDate end) as FirstHot,
         max(case when ph.PostHistoryTypeId = 53 then ph.CreationDate end) as RemovedHot
  from PostHistory ph
  group by ph.PostId
),
q_votes as (
  select v.PostId as QuestionId,
         count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
         count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
         count(case when v.VoteTypeId = 5 then 1 end) as Favorites,
         sum(case when v.VoteTypeId in (8,9) then v.BountyAmount else 0 end) as BountyTotal
  from Votes v
  group by v.PostId
),
a_votes as (
  select v.PostId as AnswerId,
         count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
         count(case when v.VoteTypeId = 3 then 1 end) as DownVotes
  from Votes v
  group by v.PostId
),
accepted as (
  select aa.Id as AnswerId,
         aa.ParentId as QuestionId,
         aa.OwnerUserId as AnswererId,
         aa.Score as AnswerScore,
         aa.CreationDate as AnswerCreation
  from Posts aa
  join q on q.AcceptedAnswerId = aa.Id
),
first_answer as (
  select a.QuestionId,
         a.AnswerId as FirstAnswerId,
         a.AnswererId as FirstAnswererId,
         a.AnswerScore as FirstAnswerScore,
         a.AnswerCreation as FirstAnswerCreation,
         row_number() over (partition by a.QuestionId order by a.AnswerCreation asc, a.AnswerId asc) as rn
  from a
),
answer_stats as (
  select a.QuestionId,
         count(*) as AnswerCount,
         avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore,
         max(a.AnswerScore) as MaxAnswerScore,
         min(a.AnswerScore) as MinAnswerScore
  from a
  group by a.QuestionId
),
commenters as (
  select c.PostId as PostId,
         count(distinct coalesce(c.UserId, -1)) as DistinctCommenters,
         sum(case when lower(c.Text) like '%thanks%' then 1 else 0 end) as ThanksComments,
         sum(case when c.Score > 0 then 1 else 0 end) as UpvotedComments
  from Comments c
  group by c.PostId
),
user_rollup as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate as UserCreated,
         u.Views as ProfileViews,
         coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormalizedLocation,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
         count(b.Id) as TotalBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.Views, coalesce(nullif(trim(u.Location), ''), 'Unknown')
),
tag_expanded as (
  select p.Id as QuestionId,
         unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as tag
  from Posts p
  where p.PostTypeId = 1 and p.Tags is not null and length(p.Tags) > 2
),
hot_tags as (
  select te.tag,
         count(*) as TagQuestionCount,
         sum(coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0)) as NetVotes,
         avg(cast(q.ViewCount as numeric)) as AvgViews
  from tag_expanded te
  join q on q.QuestionId = te.QuestionId
  left join q_votes qv on qv.QuestionId = te.QuestionId
  group by te.tag
  having count(*) >= 10
),
dupe_graph as (
  select pl.PostId as DuplicateId,
         pl.RelatedPostId as CanonicalId,
         pl.CreationDate as LinkCreated
  from PostLinks pl
  where pl.LinkTypeId = 3
),
dupe_clusters as (
  select d.CanonicalId,
         count(distinct d.DuplicateId) as DuplicateCount,
         min(d.LinkCreated) as FirstDuplicateSeen
  from dupe_graph d
  group by d.CanonicalId
),
q_lead_lag as (
  select q.QuestionId,
         q.QuestionCreation,
         lag(q.QuestionCreation) over (order by q.QuestionCreation) as PrevQTime,
         lead(q.QuestionCreation) over (order by q.QuestionCreation) as NextQTime
  from q
),
answer_latency as (
  select q.QuestionId,
         extract(epoch from (fa.FirstAnswerCreation - q.QuestionCreation)) as SecondsToFirstAnswer,
         extract(epoch from (ac.AnswerCreation - q.QuestionCreation)) as SecondsToAcceptedAnswer
  from q
  left join (select * from first_answer where rn = 1) fa on fa.QuestionId = q.QuestionId
  left join accepted ac on ac.QuestionId = q.QuestionId
),
ranked_questions as (
  select q.QuestionId,
         q.Title,
         q.Tags,
         q.QuestionScore,
         q.ViewCount,
         q.QuestionCreation,
         coalesce(qv.UpVotes,0) as UpVotes,
         coalesce(qv.DownVotes,0) as DownVotes,
         coalesce(qv.Favorites,0) as Favorites,
         coalesce(qv.BountyTotal,0) as BountyTotal,
         row_number() over (order by (coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0)) desc, q.ViewCount desc, q.QuestionCreation desc) as PopularityRank
  from q
  left join q_votes qv on qv.QuestionId = q.QuestionId
),
location_stats as (
  select ur.NormalizedLocation,
         count(*) as UserCount,
         avg(cast(ur.Reputation as numeric)) as AvgRep,
         percentile_cont(0.9) within group (order by ur.Reputation) as P90Rep
  from user_rollup ur
  group by ur.NormalizedLocation
),
post_user as (
  select q.QuestionId,
         q.AskerId,
         ur.Reputation as AskerRep,
         ur.TotalBadges as AskerBadges,
         ur.NormalizedLocation as AskerLocation
  from q
  left join user_rollup ur on ur.UserId = q.AskerId
),
answer_user as (
  select ac.QuestionId,
         ac.AnswererId as AcceptedAnswererId,
         ur.Reputation as AcceptedAnswererRep,
         ur.TotalBadges as AcceptedAnswererBadges
  from accepted ac
  left join user_rollup ur on ur.UserId = ac.AnswererId
),
complex_filter as (
  select r.QuestionId
  from ranked_questions r
  left join q_activity qa on qa.QuestionId = r.QuestionId
  left join dupe_clusters dc on dc.CanonicalId = r.QuestionId
  where
    (r.UpVotes - r.DownVotes >= 5 or r.ViewCount >= 1000 or coalesce(r.BountyTotal,0) > 0)
    and not exists (
      select 1
      from PostLinks pl
      where pl.PostId = r.QuestionId and pl.LinkTypeId = 3
    )
    and (qa.FirstCloseOrMigrate is null or qa.FirstCloseOrMigrate > r.QuestionCreation + interval '7 days')
)
select
  r.PopularityRank,
  r.QuestionId,
  coalesce(nullif(trim(r.Title), ''), '[untitled]') as Title,
  r.Tags,
  ht.tag as TopTag,
  ht.TagQuestionCount as TagQuestionCount,
  r.QuestionScore,
  r.UpVotes,
  r.DownVotes,
  r.Favorites,
  r.BountyTotal,
  r.ViewCount,
  pu.AskerId,
  coalesce(pu.AskerRep, 0) as AskerRep,
  coalesce(pu.AskerBadges, 0) as AskerBadges,
  pu.AskerLocation,
  ls.P90Rep as LocationP90Rep,
  au.AcceptedAnswererId,
  coalesce(au.AcceptedAnswererRep, 0) as AcceptedAnswererRep,
  coalesce(au.AcceptedAnswererBadges, 0) as AcceptedAnswererBadges,
  coalesce(ans.AnswerCount, 0) as AnswerCount,
  ans.AvgAnswerScore,
  ans.MaxAnswerScore,
  ans.MinAnswerScore,
  al.SecondsToFirstAnswer,
  al.SecondsToAcceptedAnswer,
  qa.SuggestedEditsApplied,
  qa.CloseVotesWithReason,
  qa.FirstHot,
  qa.RemovedHot,
  dc.DuplicateCount as CanonicalDuplicateCount,
  dc.FirstDuplicateSeen,
  cg.DistinctCommenters,
  cg.ThanksComments,
  cg.UpvotedComments,
  qll.PrevQTime,
  qll.NextQTime
from complex_filter cf
join ranked_questions r on r.QuestionId = cf.QuestionId
left join answer_stats ans on ans.QuestionId = r.QuestionId
left join answer_latency al on al.QuestionId = r.QuestionId
left join q_activity qa on qa.QuestionId = r.QuestionId
left join dupe_clusters dc on dc.CanonicalId = r.QuestionId
left join commenters cg on cg.PostId = r.QuestionId
left join q_lead_lag qll on qll.QuestionId = r.QuestionId
left join post_user pu on pu.QuestionId = r.QuestionId
left join answer_user au on au.QuestionId = r.QuestionId
left join lateral (
  select ht.tag, ht.TagQuestionCount
  from hot_tags ht
  join tag_expanded te on te.tag = ht.tag and te.QuestionId = r.QuestionId
  order by ht.TagQuestionCount desc, ht.NetVotes desc, ht.AvgViews desc, ht.tag
  limit 1
) ht on true
left join location_stats ls on ls.NormalizedLocation = pu.AskerLocation
where r.PopularityRank <= 500
order by r.PopularityRank, r.QuestionId;