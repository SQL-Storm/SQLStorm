-- {"query": "7070.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2140} 
with
-- recent active questions with tag parsing and score normalization
questions as (
  select
    p.Id,
    p.Title,
    p.OwnerUserId,
    p.CreationDate,
    p.Score,
    coalesce(p.ViewCount,0) as ViewCount,
    coalesce(p.AnswerCount,0) as AnswerCount,
    p.Tags,
    -- array of tags parsed from '<tag1><tag2>' format (Postgres-style); fallback to empty array
    case
      when p.Tags is null or p.Tags = '' then array[]::text[]
      else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')
    end as tag_list,
    -- normalized score penalizing low views and age
    round( (p.Score::numeric + coalesce(p.FavoriteCount,0)/5.0) / nullif(1 + extract(epoch from now()-p.CreationDate)/86400.0,0), 6 ) as normalized_score
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),

-- windowed aggregates per user for questions and answers
user_activity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(distinct q.Id) filter (where q.Id is not null) as QuestionsAsked,
    count(distinct a.Id) filter (where a.Id is not null) as AnswersProvided,
    sum(coalesce(a.Score,0)) filter (where a.Id is not null) as AnswerScoreSum,
    avg(nullif(q.normalized_score,0)) filter (where q.Id is not null) as AvgQuestionNormScore,
    max(q.normalized_score) filter (where q.Id is not null) as MaxQuestionNormScore,
    -- recency weight: last activity among posts/comments
    greatest(coalesce(max(p.LastActivityDate), '1970-01-01'::timestamp), coalesce(max(c.CreationDate), '1970-01-01'::timestamp)) as LastActivity
  from Users u
  left join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
  left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),

-- identify posts that are heavily cross-linked and their link diversity
post_links_stats as (
  select
    p.Id as PostId,
    p.Title,
    count(pl.Id) as LinksOut,
    count(distinct pl.RelatedPostId) as DistinctRelated,
    count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DuplicatesPointed,
    count(distinct case when pl.LinkTypeId = 1 then pl.RelatedPostId end) as GenericLinksPointed
  from Posts p
  left join PostLinks pl on pl.PostId = p.Id
  group by p.Id, p.Title
),

-- compute per-question top answers with window functions and correlated subqueries for acceptance and quality heuristics
answers_ranked as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.CreationDate,
    a.Score,
    a.Body,
    -- length heuristics and code density (rudimentary: count '<code>' tags)
    length(a.Body) as BodyLength,
    greatest(0, strpos(a.Body,'<code>') ) as HasCode,
    regexp_count(coalesce(a.Body,''), '<code') as CodeTags,
    -- window rank: by score desc, then by CreationDate asc
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as RankByScore,
    dense_rank() over (partition by a.ParentId order by a.Score desc nulls last) as DenseRankScore,
    -- relative score to question
    a.Score::numeric / nullif((select greatest(1,sum(s.Score)) from Posts s where s.Id = a.ParentId),1) as RelativeToQuestion
  from Posts a
  where a.PostTypeId = 2
),

-- fused dataset: questions enriched with user, link and top answer info
enriched_questions as (
  select
    q.*,
    ua.DisplayName as OwnerName,
    ua.Reputation as OwnerReputation,
    pls.LinksOut,
    pls.DistinctRelated,
    pls.DuplicatesPointed,
    pls.GenericLinksPointed,
    ta.AnswerId as TopAnswerId,
    ta.Score as TopAnswerScore,
    ta.OwnerUserId as TopAnswerOwner,
    ta.CodeTags as TopAnswerCodeTags,
    -- average score of first 3 answers
    ( select avg(x.Score) from (
        select Score from Posts pa where pa.ParentId = q.Id and pa.PostTypeId = 2 order by Score desc nulls last limit 3
      ) x
    ) as AvgTop3AnswerScore,
    -- count of distinct users who answered the question (correlated subquery)
    ( select count(distinct pa.OwnerUserId) from Posts pa where pa.ParentId = q.Id and pa.PostTypeId = 2 ) as DistinctAnswerers,
    -- detect if question has been linked as duplicate elsewhere or is duplicate of another
    exists (select 1 from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 3) as PointsToDuplicate,
    exists (select 1 from PostLinks pl where pl.RelatedPostId = q.Id and pl.LinkTypeId = 3) as IsTargetOfDuplicate
  from questions q
  left join user_activity ua on ua.UserId = q.OwnerUserId
  left join post_links_stats pls on pls.PostId = q.Id
  left join lateral (
    select ar.AnswerId, ar.Score, ar.OwnerUserId, ar.CodeTags
    from answers_ranked ar
    where ar.QuestionId = q.Id
    order by ar.RankByScore asc
    limit 1
  ) ta on true
)

select
  eq.Id as QuestionId,
  coalesce(eq.Title, '<no title>') as Title,
  eq.OwnerUserId,
  coalesce(eq.OwnerName, '<anon>') as OwnerName,
  eq.OwnerReputation,
  eq.CreationDate,
  eq.Score as QuestionScore,
  eq.normalized_score as QuestionNormalizedScore,
  eq.ViewCount,
  eq.AnswerCount,
  eq.DistinctAnswerers,
  eq.AvgTop3AnswerScore,
  coalesce(eq.TopAnswerId, -1) as TopAnswerId,
  eq.TopAnswerScore,
  eq.TopAnswerCodeTags,
  eq.LinksOut,
  eq.DistinctRelated,
  eq.PointsToDuplicate,
  eq.IsTargetOfDuplicate,
  -- composite quality metric with NULL-safe arithmetic and string-based heuristics
  round(
    (
      coalesce(eq.normalized_score,0) * 0.4
      + coalesce(eq.AvgTop3AnswerScore, coalesce(eq.TopAnswerScore,0)) * 0.25
      + ln(1 + coalesce(eq.ViewCount,0)) * 0.15
      + greatest(0, least(1, (coalesce(eq.OwnerReputation,0)::numeric / nullif(10000,0)))) * 0.1
      + (case when eq.TopAnswerCodeTags > 0 then 0.05 else 0 end)
      - (case when eq.PointsToDuplicate then 0.2 else 0 end)
    )::numeric, 6
  ) as CompositeQualityScore,
  -- tag explosion expression: take up to 3 tags concatenated with lengths and null logic
  (case when array_length(eq.tag_list,1) is null then '<no-tags>'
        else
          (select string_agg(t || ':' || length(t)::text, ' | ')
           from unnest(eq.tag_list) with ordinality ut(t,ord)
           where ord <= 3)
   end) as Top3TagsWithLengths,
  -- recent activity recency bucket using window function over all questions
  ntile(10) over (order by eq.CreationDate desc) as RecencyDecile,
  -- rank across enriched questions by composite metric
  rank() over (order by (
     coalesce(eq.normalized_score,0) * 0.4
     + coalesce(eq.AvgTop3AnswerScore, coalesce(eq.TopAnswerScore,0)) * 0.25
     + ln(1 + coalesce(eq.ViewCount,0)) * 0.15
     + greatest(0, least(1, (coalesce(eq.OwnerReputation,0)::numeric / nullif(10000,0)))) * 0.1
     + (case when eq.TopAnswerCodeTags > 0 then 0.05 else 0 end)
     - (case when eq.PointsToDuplicate then 0.2 else 0 end)
  ) desc) as RankByComposite
from enriched_questions eq
where
  -- complicated predicate combining null logic, string patterns, existence and arithmetic
  ( (eq.AvgTop3AnswerScore is not null and eq.AvgTop3AnswerScore >= 2)
    or (eq.TopAnswerScore is not null and eq.TopAnswerScore >= 5)
    or (eq.ViewCount > 1000)
    or (eq.tag_list is not null and exists (select 1 from unnest(eq.tag_list) t where lower(t) like any (array['%sql%','%performance%','%benchmark%'])) )
  )
  and not (eq.IsTargetOfDuplicate is true and eq.PointsToDuplicate is true) -- avoid mutual duplicates
order by RankByComposite asc
limit 250;