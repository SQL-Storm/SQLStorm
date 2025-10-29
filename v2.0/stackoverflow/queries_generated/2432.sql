-- {"query": "2432.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1272} 
with RecursiveTagHierarchy as (
  select t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, 0 as Level,
         array[t.TagName] as Path
  from Tags t
  where t.Id in (select distinct p.Id from Posts p where p.PostTypeId = 1 and p.Tags is not null)
  union all
  select child.Id, child.TagName, child.Count, child.IsModeratorOnly, child.IsRequired, parent.Level + 1,
         parent.Path || child.TagName
  from Tags child
  join RecursiveTagHierarchy parent on child.Id <> parent.Id and child.Id > parent.Id
  where not child.TagName = any(parent.Path)
),
UserActivity AS (
  select 
    u.Id as UserId,
    u.DisplayName,
    count(distinct p.Id) as TotalPosts,
    count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
    count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersGiven,
    coalesce(sum(vb.UpVotes),0) as TotalUpVotesReceived,
    coalesce(sum(vb.DownVotes),0) as TotalDownVotesReceived,
    row_number() over (order by count(distinct p.Id) desc) as ActivityRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join (
    select p.OwnerUserId, 
           sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
           sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v 
    join Posts p on p.Id = v.PostId
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where p.OwnerUserId is not null
    group by p.OwnerUserId
  ) vb on vb.OwnerUserId = u.Id
  group by u.Id, u.DisplayName
),
QuestionAnswerStats AS (
  select 
      q.Id as QuestionId,
      q.Title,
      q.CreationDate as QuestionDate,
      q.Score as QuestionScore,
      q.ViewCount,
      (select count(*)
       from Posts a
       where a.ParentId = q.Id and a.PostTypeId = 2) as AnswerCount,
      (select count(*)
       from Comments c
       where c.PostId = q.Id) as CommentCount,
      coalesce(a_stats.TopAnswerScore,0) as TopAnswerScore,
      a_stats.TopAnswerBody,
      u.DisplayName as QuestionOwnerName
  from Posts q
  left join lateral (
      select a.Score as TopAnswerScore,
             substring(a.Body from 1 for 200) as TopAnswerBody
      from Posts a
      where a.ParentId = q.Id and a.PostTypeId = 2
      order by a.Score desc nulls last
      limit 1
  ) a_stats on true
  left join Users u on u.Id = q.OwnerUserId
  where q.PostTypeId = 1
),
BadgeSummary AS (
  select 
    b.UserId,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    bool_or(b.TagBased) as HasTagBasedBadges
  from Badges b
  group by b.UserId
),
UserReputationWindow AS (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    avg(u.Reputation) over () as AvgReputation,
    percentile_cont(0.5) within group (order by u.Reputation) over () as MedianReputation,
    rank() over (order by u.Reputation desc) as ReputationRank
  from Users u
),
DistinctTagQuestions as (
  select distinct unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag, p.Id as QuestionId
  from Posts p
  where p.PostTypeId = 1 and p.Tags is not null
)
select 
  ua.UserId,
  ua.DisplayName as User,
  ua.TotalPosts,
  ua.QuestionsAsked,
  ua.AnswersGiven,
  ua.TotalUpVotesReceived,
  ua.TotalDownVotesReceived,
  bs.BadgeCount,
  bs.GoldBadges,
  bs.SilverBadges,
  bs.BronzeBadges,
  urw.Reputation,
  urw.AvgReputation,
  urw.MedianReputation,
  qa.QuestionId,
  qa.Title,
  qa.QuestionDate,
  qa.QuestionScore,
  qa.ViewCount,
  qa.AnswerCount,
  qa.CommentCount,
  qa.TopAnswerScore,
  qa.TopAnswerBody,
  dtq.Tag,
  rt.Level as TagHierarchyLevel,
  rt.Path as TagHierarchyPath
from UserActivity ua
left join BadgeSummary bs on bs.UserId = ua.UserId
left join UserReputationWindow urw on urw.UserId = ua.UserId
left join LATERAL (
  select q.*
  from QuestionAnswerStats q
  where q.QuestionOwnerName = ua.DisplayName
  order by q.QuestionScore desc nulls last
  limit 1
) qa on true
left join DistinctTagQuestions dtq on dtq.QuestionId = qa.QuestionId
left join RecursiveTagHierarchy rt on rt.TagName = dtq.Tag
where ua.TotalPosts > 10
  and (bs.BadgeCount > 0 or bs.BadgeCount is null)
  and qa.QuestionScore > coalesce((select avg(Score) from Posts where PostTypeId = 1), 0)
order by ua.TotalPosts desc, qa.QuestionScore desc
limit 100;