-- {"query": "2339.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1519} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, cast(t.TagName as varchar(1000)) as FullPath, 1 as Level
    from Tags t
    where t.IsRequired = 1 or t.IsModeratorOnly = 1
  union all
    select c.Id, c.TagName, c.Count,
      r.FullPath || ' > ' || c.TagName, r.Level + 1
    from Tags c
    inner join RecursiveTagHierarchy r on c.ExcerptPostId = r.Id
    where r.Level < 3
),
UserBadgeCounts as (
    select b.UserId,
      count(case when b.Class = 1 then 1 end) as GoldBadges,
      count(case when b.Class = 2 then 1 end) as SilverBadges,
      count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
PostScoreStats as (
    select p.OwnerUserId,
      count(*) filter (where p.PostTypeId=1) as QuestionCount,
      count(*) filter (where p.PostTypeId=2) as AnswerCount,
      avg(p.Score) filter (where p.PostTypeId=1) as AvgQuestionScore,
      avg(p.Score) filter (where p.PostTypeId=2) as AvgAnswerScore,
      max(p.Score) filter (where p.PostTypeId=1) as MaxQuestionScore,
      max(p.Score) filter (where p.PostTypeId=2) as MaxAnswerScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserRecentActivity as (
    select u.Id as UserId,
      max(post_last_activity) as LastActivity,
      min(post_creation) as FirstPostDate
    from Users u
    left join (
      select OwnerUserId,
        max(LastActivityDate) as post_last_activity,
        min(CreationDate) as post_creation
      from Posts
      group by OwnerUserId
    ) pa on pa.OwnerUserId = u.Id
    group by u.Id
),
CloseVotesWithin30Days as (
    select ph.PostId,
      count(*) as CloseVoteCount30Days
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
      and ph.CreationDate >= current_date - interval '30 days'
    group by ph.PostId
),
QuestionAnswerDetails as (
    select q.Id as QuestionId, q.Title, q.CreationDate, q.Score as QuestionScore, q.ViewCount,
      a.Id as AnswerId, a.Score as AnswerScore, a.CreationDate as AnswerCreationDate,
      u.DisplayName as AnswerUserName,
      row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Users u on u.Id = a.OwnerUserId
    where q.PostTypeId = 1
),
FilteredTopAnswers as (
    select *
    from QuestionAnswerDetails
    where AnswerRank <= 3
),
FinalUserStats as (
    select u.Id as UserId, u.DisplayName,
      coalesce(ub.GoldBadges,0) as GoldBadges,
      coalesce(ub.SilverBadges,0) as SilverBadges,
      coalesce(ub.BronzeBadges,0) as BronzeBadges,
      coalesce(pss.QuestionCount,0) as QuestionCount,
      coalesce(pss.AnswerCount,0) as AnswerCount,
      coalesce(pss.AvgQuestionScore,0) as AvgQuestionScore,
      coalesce(pss.AvgAnswerScore,0) as AvgAnswerScore,
      ur.LastActivity, ur.FirstPostDate,
      case when u.LastAccessDate > current_timestamp - interval '60 days' then 1 else 0 end as ActiveRecently,
      case when u.Reputation > 10000 then 1 else 0 end as IsHighRep
    from Users u
    left join UserBadgeCounts ub on ub.UserId = u.Id
    left join PostScoreStats pss on pss.OwnerUserId = u.Id
    left join UserRecentActivity ur on ur.UserId = u.Id
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, count(*) as NumDuplicates
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
PostsWithTagInfo as (
    select p.Id, p.Title, p.Tags, p.PostTypeId,
      string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><') as TagArray,
      array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1) as TagCount
    from Posts p
    where p.PostTypeId = 1
)
select fst.UserId, fst.DisplayName, fst.GoldBadges, fst.SilverBadges, fst.BronzeBadges,
  fst.QuestionCount, fst.AnswerCount, fst.AvgQuestionScore, fst.AvgAnswerScore,
  fst.LastActivity, fst.FirstPostDate, fst.ActiveRecently, fst.IsHighRep,
  count(distinct dtqh.QuestionId) as QuestionsWithTopAnswers,
  avg(dtqh.AnswerScore) as AvgTopAnswerScore,
  max(dtqh.AnswerScore) as MaxTopAnswerScore,
  count(distinct dtqh.AnswerId) as TotalTopAnswersCount,
  coalesce(sum(clv.CloseVoteCount30Days), 0) as TotalCloseVotesLast30Days,
  count(distinct dl.RelatedPostId) as DuplicateLinksCount,
  array_to_string(array_agg(distinct case when rt.Level = 1 then rt.TagName else null end), ',') as Level1Tags,
  array_to_string(array_agg(distinct case when rt.Level = 2 then rt.TagName else null end), ',') as Level2Tags,
  array_to_string(array_agg(distinct case when rt.Level = 3 then rt.TagName else null end), ',') as Level3Tags
from FinalUserStats fst
left join FilteredTopAnswers dtqh on dtqh.AnswerUserName = fst.DisplayName
left join CloseVotesWithin30Days clv on clv.PostId = dtqh.QuestionId
left join DuplicateLinks dl on dl.PostId = dtqh.QuestionId
left join RecursiveTagHierarchy rt on rt.TagName = any(dtqh.Tags)
group by fst.UserId, fst.DisplayName, fst.GoldBadges, fst.SilverBadges, fst.BronzeBadges,
  fst.QuestionCount, fst.AnswerCount, fst.AvgQuestionScore, fst.AvgAnswerScore,
  fst.LastActivity, fst.FirstPostDate, fst.ActiveRecently, fst.IsHighRep
having count(distinct dtqh.QuestionId) > 5
order by fst.GoldBadges desc, AvgTopAnswerScore desc, fst.Reputation desc
limit 50;