-- {"query": "2.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2920} 
with
-- recent user activity and derived reputation changes
UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(BadgesCnt,0) as BadgeCount,
    coalesce(AnsCount,0) as AnswerCount,
    coalesce(QuesCount,0) as QuestionCount,
    coalesce(CommPosts,0) as CommunityPosts,
    greatest(0, u.Reputation - coalesce(PrevRep.PrevReputation,0)) as ReputationDeltaLastPeriod
  from Users u
  left join (
    select UserId, count(*) as BadgesCnt
    from Badges
    where Date >= current_date - interval '180 day'
    group by UserId
  ) b on b.UserId = u.Id
  left join (
    select OwnerUserId, count(*) as AnsCount
    from Posts
    where PostTypeId = 2 and CreationDate >= current_date - interval '365 day'
    group by OwnerUserId
  ) a on a.OwnerUserId = u.Id
  left join (
    select OwnerUserId, count(*) as QuesCount
    from Posts
    where PostTypeId = 1 and CreationDate >= current_date - interval '365 day'
    group by OwnerUserId
  ) q on q.OwnerUserId = u.Id
  left join (
    select OwnerUserId, count(*) as CommPosts
    from Posts
    where CommunityOwnedDate is not null and CommunityOwnedDate >= current_date - interval '365 day'
    group by OwnerUserId
  ) c on c.OwnerUserId = u.Id
  left join (
    select Id as UserId, Reputation as PrevReputation
    from Users
    where CreationDate < current_date - interval '365 day'
  ) PrevRep on PrevRep.UserId = u.Id
),
-- heavy posts: questions with answers, views, and tag explosion metrics
QuestionMetrics as (
  select
    p.Id as QuestionId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.FavoriteCount,
    p.Tags,
    -- number of tags parsed from the Tags field like '<tag1><tag2>'
    case when p.Tags is null then 0 else array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'),1) end as TagCount,
    -- longest word in title (approx)
    (select max(length(word)) from unnest(string_to_array(regexp_replace(coalesce(p.Title,''),'[^A-Za-z0-9 ]',' ','g'),' ')) as word) as LongestTitleWordLen,
    -- average answer score for its answers
    (select avg(coalesce(a.Score,0)) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2) as AvgAnswerScore,
    -- number of distinct answerers
    (select count(distinct a.OwnerUserId) from Posts a where a.ParentId = p.Id and a.PostTypeId = 2 and a.OwnerUserId is not null) as DistinctAnswerers
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= current_date - interval '730 day'
),
-- answers enriched with owner reputation windows and backlink info
AnswerEnrichment as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    a.Body,
    u.Reputation as OwnerReputation,
    -- rolling avg score of last 5 answers by same user prior to this answer (correlated subquery)
    (select avg(coalesce(s.Score,0))
     from Posts s
     where s.PostTypeId = 2
       and s.OwnerUserId = a.OwnerUserId
       and s.CreationDate < a.CreationDate
     order by s.CreationDate desc
     limit 5) as RollingAvgPrev5Answers,
    -- is this answer accepted?
    case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAccepted,
    -- number of comments on this answer
    (select count(*) from Comments c where c.PostId = a.Id) as CommentCount,
    -- backlinks: how many posts link to this answer (PostLinks where RelatedPostId = a.Id)
    (select count(*) from PostLinks pl where pl.RelatedPostId = a.Id) as InboundLinks
  from Posts a
  left join Posts q on q.Id = a.ParentId
  left join Users u on u.Id = a.OwnerUserId
  where a.PostTypeId = 2
    and a.CreationDate >= current_date - interval '730 day'
),
-- tag popularity and co-occurrence (explode tags)
TagExplode as (
  select
    t.TagName,
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount
  from Posts p
  join lateral (
    select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as TagName
  ) t on true
  where p.PostTypeId = 1
),
TagStats as (
  select
    te.TagName,
    count(*) as QuestionCount,
    avg(te.Score) as AvgScore,
    avg(te.ViewCount) as AvgViews,
    row_number() over (order by count(*) desc) as PopularityRank
  from TagExplode te
  where te.CreationDate >= current_date - interval '365 day'
  group by te.TagName
),
-- assemble a set of "problematic" posts via complex predicate and NULL logic
ProblematicPosts as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.OwnerUserId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Body,
    p.Tags,
    -- heuristic: low score high views but no accepted answer and many reopen/close in history
    case
      when p.PostTypeId = 1 and p.ViewCount > 1000 and coalesce(p.Score,0) < 0 and (p.AcceptedAnswerId is null) then 1
      when p.PostTypeId = 2 and coalesce(p.Score,0) < -2 and (select count(*) from Comments c where c.PostId = p.Id) > 5 then 1
      else 0
    end as IsProblematic,
    -- count of close/reopen history events (using PostHistory types 10/11 and 35/36, etc)
    (select count(*) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId in (10,11,35,36)) as CloseReopenEvents,
    -- text-based signal: presence of 'plz' or 'urgent' or 'help' ignoring case
    case when p.Body ~* '\\y(plz|pls|urgent|help)\\y' then 1 else 0 end as BeggingSignal
  from Posts p
  where p.CreationDate >= current_date - interval '1095 day'
),
-- windowed ranking combining many metrics
UserComposite as (
  select
    ua.*,
    sum(case when pm.IsProblematic = 1 then 1 else 0 end) over (partition by ua.UserId) as UserProblemPosts,
    dense_rank() over (order by ua.Reputation desc, ua.BadgeCount desc, ua.AnswerCount desc) as GlobalExpertRank,
    percent_rank() over (order by ua.Reputation) as ReputationPercentile
  from UserActivity ua
  left join Posts pm on pm.OwnerUserId = ua.UserId
),
-- final heavy join set for benchmarking involving set ops and correlated filters
SelectedQuestions as (
  select qm.*
  from QuestionMetrics qm
  where qm.TagCount >= 3
    and qm.ViewCount > (select avg(ViewCount) from QuestionMetrics) * 1.5
    and qm.LongestTitleWordLen > 8
    and (qm.AvgAnswerScore is null or qm.AvgAnswerScore < 1)
    and exists (
      select 1
      from TagStats ts
      where ts.TagName in (
        select unnest(string_to_array(substring(qm.Tags from 2 for char_length(qm.Tags)-2), '><'))
      )
      and ts.PopularityRank <= 50
    )
),
-- top answers to selected questions with unioned synthetic rows and complex expressions
TopAnswersUnion as (
  select
    ae.*,
    qm.Title as QuestionTitle,
    qm.TagCount,
    -- complexity: compute a weighted usefulness score
    (coalesce(ae.Score,0) * 2 + coalesce(ae.RollingAvgPrev5Answers,0) * 1.2 + coalesce(ae.InboundLinks,0) * 0.8
      - coalesce(ae.CommentCount,0) * 0.5 + (case when ae.IsAccepted = 1 then 10 else 0 end)
      + log(greatest(1, coalesce(ae.OwnerReputation,0))::numeric)
    ) as UsefulnessScore,
    -- string manipulation: snippet of answer body sanitized
    left(regexp_replace(coalesce(ae.Body,''),'\\s+',' ','g'),200) as Snippet
  from AnswerEnrichment ae
  join SelectedQuestions qm on qm.QuestionId = ae.QuestionId
  where ae.Score >= (select percentile_cont(0.75) within group (order by Score) from AnswerEnrichment)
  union all
  -- synthetic row to force planner to handle constants and nulls
  select
    null::int as AnswerId,
    sq.QuestionId as QuestionId,
    null::int as OwnerUserId,
    current_timestamp as CreationDate,
    0 as Score,
    null::text as Body,
    null::int as OwnerReputation,
    null::numeric as RollingAvgPrev5Answers,
    0 as IsAccepted,
    0 as CommentCount,
    0 as InboundLinks,
    sq.Title as QuestionTitle,
    sq.TagCount,
    0.0 as UsefulnessScore,
    '<<SYNTHETIC>>' as Snippet
  from SelectedQuestions sq
),
-- final aggregation with correlated subquery for per-question sentiment like metric and set operator example
FinalAgg as (
  select
    ta.QuestionId,
    ta.QuestionTitle,
    ta.TagCount,
    count(*) filter (where ta.AnswerId is not null) as RealAnswerCount,
    sum(case when ta.IsAccepted = 1 then 1 else 0 end) as AcceptedAnswers,
    max(ta.UsefulnessScore) as MaxUsefulness,
    avg(ta.UsefulnessScore) as AvgUsefulness,
    -- correlated subquery: count distinct answerers with reputation above question owner
    (select count(distinct a.OwnerUserId)
     from Posts a
     join Users uu on uu.Id = a.OwnerUserId
     where a.PostTypeId = 2 and a.ParentId = ta.QuestionId
       and uu.Reputation > coalesce((select OwnerReputation from AnswerEnrichment where AnswerEnrichment.AnswerId = ta.AnswerId), 0)
    ) as HigherReputationAnswerers,
    -- mixed set operator: symmetric difference between tag sets of top two answers (approx)
    (
      select array_to_string(array(
        select distinct t from (
          select unnest(string_to_array(substring(p1.Tags from 2 for char_length(p1.Tags)-2), '><')) t
          except
          select unnest(string_to_array(substring(p2.Tags from 2 for char_length(p2.Tags)-2), '><')) t
        ) x
      ), ',')
      from Posts p1
      join Posts p2 on p2.Id = (select min(AnswerId) from TopAnswersUnion where QuestionId = ta.QuestionId and AnswerId is not null)
      where p1.Id = (select max(AnswerId) from TopAnswersUnion where QuestionId = ta.QuestionId and AnswerId is not null)
    ) as SymmetricTagDiff
  from TopAnswersUnion ta
  group by ta.QuestionId, ta.QuestionTitle, ta.TagCount
)
select
  f.*,
  us.DisplayName as QuestionOwner,
  us.GlobalExpertRank,
  us.ReputationPercentile,
  -- join on the original question to show view/score
  q.Score as QuestionScore,
  q.ViewCount as QuestionViews,
  -- join to tag stats for dominant tag
  (select ts.TagName from TagStats ts where ts.TagName = (select unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags)-2), '><')) limit 1) limit 1) as DominantTag,
  -- approximate engagement metric using window over related users
  (f.RealAnswerCount * 1.3 + f.AcceptedAnswers * 5 + f.MaxUsefulness / nullif(greatest(f.AvgUsefulness,0.1),0) ) as EngagementScore
from FinalAgg f
left join Posts q on q.Id = f.QuestionId
left join Users us on us.Id = q.OwnerUserId
where (f.RealAnswerCount > 0 or f.AcceptedAnswers > 0)
  and (f.EngagementScore is null or f.EngagementScore > 0)
order by EngagementScore desc nulls last
limit 250;