-- {"query": "2409.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1492} 
with RankedAnswers as (
  select 
    a.Id,
    a.ParentId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    a.Body,
    
    row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as RankByScoreDate,
    dense_rank() over (partition by a.ParentId order by a.OwnerUserId) as RankByUser

  from Posts a
  where a.PostTypeId = 2
),
QuestionStats as (
  select 
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.Score as QuestionScore,
    coalesce(q.ViewCount,0) as Views,
    coalesce(q.AnswerCount,0) as AnswerCount,
    q.CreationDate,
    q.Tags,
    u.Reputation as OwnerReputation,
    coalesce(bc.GoldBadges, 0) as GoldBadges,
    coalesce(bc.SilverBadges, 0) as SilverBadges,
    coalesce(bc.BronzeBadges, 0) as BronzeBadges,
    EXISTS (
      select 1 from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    ) as IsClosed,
    
    -- Number of comments on question
    (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,

    -- Number of distinct users who answered this question
    (select count(distinct OwnerUserId) from Posts p2 where p2.ParentId = q.Id and p2.PostTypeId = 2 and p2.OwnerUserId is not null) as DistinctAnswerers
    
  from Posts q
  left join Users u on u.Id = q.OwnerUserId
  left join (
    select 
      UserId,
      sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
      sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
      sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
  ) bc on bc.UserId = q.OwnerUserId
  where q.PostTypeId = 1
  and q.CreationDate >= current_date - interval '1 year'
),
AnswerDetails as (
  select 
    ra.Id,
    ra.ParentId,
    ra.OwnerUserId,
    ra.Score,
    ra.CreationDate,
    ra.Body,
    u.Reputation as AnswererReputation,
    row_number() over (partition by ra.ParentId order by ra.Score desc nulls last, ra.CreationDate asc nulls last) as SeqNum,
    
    -- Correlated subquery: count comments on this answer
    (select count(*) from Comments c where c.PostId = ra.Id) as AnswerCommentCount,

    -- Correlated subquery: count up votes minus down votes on this answer
    (
      select 
        coalesce(sum(case v.VoteTypeId when 2 then 1 when 3 then -1 else 0 end),0) 
      from Votes v 
      where v.PostId = ra.Id
    ) as NetVotes

  from RankedAnswers ra
  left join Users u on u.Id = ra.OwnerUserId
),
TagExploded as (
  select 
    qs.Id as QuestionId,
    unnest(string_to_array(substring(qs.Tags from 2 for length(qs.Tags) - 2), '><')) as TagName
  from QuestionStats qs
),
TagAggregates as (
  select 
    te.TagName,
    count(distinct te.QuestionId) as QuestionsWithTag,
    avg(qs.QuestionScore) as AvgQuestionScore,
    avg(qs.Views) as AvgViews,
    sum(qs.AnswerCount) as TotalAnswers
  from TagExploded te
  join QuestionStats qs on qs.Id = te.QuestionId
  group by te.TagName
),
CloseReasonClassification as (
  select 
    ph.PostId,
    crt.Name as CloseReasonName,
    count(*) as CloseCount
  from PostHistory ph
  join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
  where ph.PostHistoryTypeId = 10
  group by ph.PostId, crt.Name
),
CombinedSet as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.OwnerUserId,
    q.Views,
    q.AnswerCount,
    q.IsClosed,
    cr.CloseReasonName,
    cr.CloseCount
  from QuestionStats q
  left join CloseReasonClassification cr on cr.PostId = q.Id

  union

  select 
    a.ParentId,
    null,
    null,
    null,
    null,
    null,
    null,
    null
  from AnswerDetails a
  where a.NetVotes < 0
),
FinalOutput as (
  select 
    cs.QuestionId,
    cs.Title,
    cs.OwnerUserId,
    u.DisplayName,
    cs.Views,
    cs.AnswerCount,
    cs.IsClosed,
    cs.CloseReasonName,
    cs.CloseCount,
    
    -- Window function: ranking questions by views within each CloseReasonName partition
    rank() over (partition by cs.CloseReasonName order by cs.Views desc nulls last) as RankByViewsWithinCloseReason,

    -- String expression combining nullable fields
    coalesce(cs.CloseReasonName, 'Open') || ' - ' || coalesce(u.DisplayName, 'Unknown') as ReasonAndOwner,

    -- Complex predicate with NULL logic
    case 
      when cs.IsClosed = true then 'Closed Question'
      when cs.AnswerCount > 5 and cs.Views > 10000 then 'Popular Open Question'
      when cs.Views is null then 'Unviewed Question'
      else 'Normal Open Question'
    end as QuestionClass

  from CombinedSet cs
  left join Users u on u.Id = cs.OwnerUserId
)
select 
  fo.QuestionId,
  fo.Title,
  fo.DisplayName as OwnerName,
  fo.Views,
  fo.AnswerCount,
  fo.IsClosed,
  fo.CloseReasonName,
  fo.CloseCount,
  fo.RankByViewsWithinCloseReason,
  fo.ReasonAndOwner,
  fo.QuestionClass,
  
  -- Include highest scoring answer's score and user reputation via correlated subqueries
  (
    select max(a.Score) from Posts a where a.PostTypeId=2 and a.ParentId=fo.QuestionId
  ) as HighestAnswerScore,
  
  (
    select u2.Reputation from Posts a2 join Users u2 on u2.Id = a2.OwnerUserId where a2.PostTypeId=2 and a2.ParentId=fo.QuestionId order by a2.Score desc limit 1
  ) as HighestAnswerUserReputation

from FinalOutput fo
where fo.Views > 5000 or fo.IsClosed = true
order by fo.IsClosed desc nulls last, fo.Views desc nulls last
limit 100;