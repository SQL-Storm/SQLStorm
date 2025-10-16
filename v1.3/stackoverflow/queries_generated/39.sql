-- {"query": "39.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2147} 
with
-- recent active questions with parsed tag counts and normalized title
RecentQuestions as (
  select
    p.Id,
    p.CreationDate,
    p.OwnerUserId,
    p.Title,
    coalesce(p.ViewCount,0) as Views,
    coalesce(p.Score,0) as Score,
    p.AnswerCount,
    p.CommentCount,
    -- split tags like '<sql><postgres>' into array; emulate by trimming and replacing: DBs differ, assume Postgres-style string_to_array
    case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray,
    -- derive a simple normalized title for heavy string ops
    lower(regexp_replace(coalesce(p.Title,''), '[^a-z0-9]+', ' ', 'g')) as NormTitle
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),
-- compute per-question aggregated vote breakdown and last vote time using window/conditional aggregation
QuestionVotes as (
  select
    q.Id as QuestionId,
    count(v.Id) filter (where v.VoteTypeId = 2) as UpVotes,
    count(v.Id) filter (where v.VoteTypeId = 3) as DownVotes,
    count(v.Id) filter (where v.VoteTypeId = 5) as Favorites,
    max(v.CreationDate) as LastVoteAt
  from RecentQuestions q
  left join Votes v on v.PostId = q.Id
  group by q.Id
),
-- compute per-question recent activity signatures (last edit, last comment, last answer)
QuestionActivity as (
  select
    q.Id as QuestionId,
    max(ph.CreationDate) as LastHistoryAt,
    max(c.CreationDate) as LastCommentAt,
    max(a.CreationDate) as LastAnswerAt,
    -- number of distinct editors including community (-1 treated as null)
    count(distinct nullif(ph.UserId,-1)) as DistinctEditors
  from RecentQuestions q
  left join PostHistory ph on ph.PostId = q.Id
  left join Comments c on c.PostId = q.Id
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  group by q.Id
),
-- top answerer stats for each question (correlated subquery style via lateral)
TopAnswerers as (
  select
    q.Id as QuestionId,
    ta.UserId,
    ta.AnswerCount,
    ta.AvgScore,
    ta.LatestAnswerAt
  from RecentQuestions q
  left join lateral (
    select
      a.OwnerUserId as UserId,
      count(*) as AnswerCount,
      avg(coalesce(a.Score,0)) as AvgScore,
      max(a.CreationDate) as LatestAnswerAt
    from Posts a
    where a.ParentId = q.Id and a.PostTypeId = 2
      and a.OwnerUserId is not null
    group by a.OwnerUserId
    order by AnswerCount desc, AvgScore desc nulls last
    limit 3
  ) ta on true
),
-- compute badge-weighted reputation deltas for owners
OwnerBadgeReputation as (
  select
    u.Id as UserId,
    u.Reputation,
    coalesce(sum(
      case
        when b.Class = 1 then 50
        when b.Class = 2 then 20
        when b.Class = 3 then 5
        else 0 end
    ),0) as BadgeWeight,
    -- last badge date
    max(b.Date) as LastBadgeDate
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation
),
-- identify potential duplicate links and compute graph metrics
DuplicateLinks as (
  select
    pl.PostId,
    pl.RelatedPostId,
    pl.CreationDate,
    row_number() over (partition by pl.PostId order by pl.CreationDate desc) as rn
  from PostLinks pl
  where pl.LinkTypeId = 3
),
-- tag popularity expansion (unnest tags)
QuestionTags as (
  select
    q.Id as QuestionId,
    unnest(q.TagArray) as TagName
  from RecentQuestions q
),
TagStats as (
  select
    t.TagName,
    count(distinct qt.QuestionId) as QuestionsWithTag,
    sum(q.Views) as TotalViews,
    avg(q.Score) as AvgScore
  from QuestionTags qt
  join RecentQuestions q on q.Id = qt.QuestionId
  group by t.TagName
),
-- complexity: union set operator to combine recent hot questions with older but resurging ones
HotCandidates as (
  select rq.Id, rq.Title, rq.Views, rq.Score, rq.AnswerCount, 'recent' as Source
  from RecentQuestions rq
  where rq.Views > 1000 or rq.Score > 50
  union
  select p.Id, p.Title, p.ViewCount, p.Score, p.AnswerCount, 'resurged' as Source
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate < now() - interval '2 years'
    and (p.ViewCount > 20000 and p.LastActivityDate > now() - interval '6 months')
),
-- final scoring combining many signals with NULL-aware math and window functions
FinalScore as (
  select
    h.Id,
    h.Title,
    h.Views,
    h.Score as BaseScore,
    h.AnswerCount,
    coalesce(qv.UpVotes,0) as UpVotes,
    coalesce(qv.DownVotes,0) as DownVotes,
    coalesce(qv.Favorites,0) as Favorites,
    coalesce(qa.DistinctEditors,0) as DistinctEditors,
    coalesce(oa.Reputation,0) as OwnerReputation,
    coalesce(oa.BadgeWeight,0) as OwnerBadgeWeight,
    -- freshness: min days since last activity across multiple sources
    least(
      coalesce(date_part('day', now() - qa.LastHistoryAt), 3650),
      coalesce(date_part('day', now() - qa.LastCommentAt), 3650),
      coalesce(date_part('day', now() - qa.LastAnswerAt), 3650),
      coalesce(date_part('day', now() - qv.LastVoteAt), 3650)
    ) as DaysSinceActivity,
    -- tag diversity (approx)
    (select count(distinct TagName) from QuestionTags qt where qt.QuestionId = h.Id) as TagDiversity,
    -- weighted composite: base plus interaction, penalize downvotes and staleness, boost owner rep and badges
    (
      (coalesce(h.Score,0) * 5)
      + (coalesce(qv.UpVotes,0) * 3)
      - (coalesce(qv.DownVotes,0) * 6)
      + (coalesce(qv.Favorites,0) * 7)
      + (coalesce(h.Views,0) / 100.0)
      + (coalesce(oa.BadgeWeight,0) * 0.5)
      + (coalesce(oa.Reputation,0) / 1000.0)
      + (coalesce(qa.DistinctEditors,0) * 2)
      - greatest(0, least(365, coalesce(
          (coalesce(date_part('day', now() - qa.LastHistoryAt), 3650) +
           coalesce(date_part('day', now() - qa.LastCommentAt), 3650) +
           coalesce(date_part('day', now() - qa.LastAnswerAt), 3650)
          )/3.0, 365
        ))) * 0.8
    ) as CompositeScore
  from HotCandidates h
  left join QuestionVotes qv on qv.QuestionId = h.Id
  left join QuestionActivity qa on qa.QuestionId = h.Id
  left join Posts p_owner on p_owner.Id = h.Id
  left join OwnerBadgeReputation oa on oa.UserId = p_owner.OwnerUserId
)
select
  fs.Id,
  fs.Title,
  fs.Views,
  fs.BaseScore,
  fs.AnswerCount,
  fs.UpVotes,
  fs.DownVotes,
  fs.Favorites,
  fs.DistinctEditors,
  fs.OwnerReputation,
  fs.OwnerBadgeWeight,
  fs.DaysSinceActivity,
  fs.TagDiversity,
  fs.CompositeScore,
  -- top 3 tags for this question by TagStats popularity, concatenated
  (select string_agg(ts.TagName || ':' || ts.QuestionsWithTag, ',' order by ts.QuestionsWithTag desc nulls last)
   from (
     select qt.TagName, ts.QuestionsWithTag
     from QuestionTags qt
     left join TagStats ts on ts.TagName = qt.TagName
     where qt.QuestionId = fs.Id
     order by ts.QuestionsWithTag desc nulls last
     limit 3
   ) ts) as TopTagsSummary,
  -- correlated subquery to list up to 2 top answerers by answers for this question as JSON-like text
  (select string_agg('u' || coalesce(ta.UserId::text,'anon') || '=(' || coalesce(ta.AnswerCount::text,'0') || ',' || coalesce(round(ta.AvgScore::numeric,2)::text,'0') || ')', ';' order by ta.AnswerCount desc nulls last)
   from (
     select UserId, AnswerCount, AvgScore
     from TopAnswerers ta
     where ta.QuestionId = fs.Id
     order by AnswerCount desc nulls last
     limit 2
   ) ta) as TopAnswerersSummary
from FinalScore fs
order by fs.CompositeScore desc nulls last, fs.Views desc
limit 100;