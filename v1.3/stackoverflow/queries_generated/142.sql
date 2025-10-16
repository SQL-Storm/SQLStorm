-- {"query": "142.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2581} 
with
-- recent questions with parsed tags
questions as (
  select p.*, 
         coalesce(p.Tags,'') as raw_tags,
         -- extract individual tags into an array (Postgres)
         case when p.Tags is null then array[]::text[] 
              else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as tag_array
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '2 years'
),
-- answers and aggregated answer metrics per question
answers as (
  select a.*,
         row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate) as answer_rank,
         count(*) over (partition by a.ParentId) as answers_per_question
  from Posts a
  where a.PostTypeId = 2
),
answer_aggs as (
  select 
    a.ParentId as QuestionId,
    count(*) filter (where a.Score >= 0) as positive_answers,
    count(*) filter (where a.Score < 0) as negative_answers,
    avg(a.Score) as avg_answer_score,
    max(a.Score) as max_answer_score,
    min(a.Score) as min_answer_score,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as has_accepted,
    avg(extract(epoch from (a.CreationDate - q.CreationDate))/3600) filter (where q.AcceptedAnswerId is not null and a.Id = q.AcceptedAnswerId) as hours_to_accepted
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  group by a.ParentId
),
-- top contributors for each question: compute weighted reputation score based on answer acceptance/score
top_contributors as (
  select
    a.ParentId as QuestionId,
    u.Id as UserId,
    u.Reputation,
    sum(
      (case when a.Id = q.AcceptedAnswerId then 5.0 else 1.0 end) * coalesce(a.Score,0)
    ) as reputation_weighted_score,
    count(*) as answers_by_user
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Users u on u.Id = a.OwnerUserId
  where u.Id is not null
  group by a.ParentId, u.Id, u.Reputation
),
-- pick the best contributor per question
best_contributor as (
  select distinct on (tc.QuestionId)
    tc.QuestionId, tc.UserId as BestUserId, tc.Reputation as BestUserReputation, tc.reputation_weighted_score
  from top_contributors tc
  order by tc.QuestionId, tc.reputation_weighted_score desc, tc.Reputation desc nulls last
),
-- comments density and avg comment length per post
comment_stats as (
  select c.PostId,
         count(*) as comment_count,
         avg(char_length(c.Text)) as avg_comment_len,
         max(char_length(c.Text)) as max_comment_len
  from Comments c
  group by c.PostId
),
-- badge pressure: count badges for question owner prior to question creation (correlated)
owner_badges as (
  select q.Id as QuestionId,
         (select count(*) from Badges b where b.UserId = q.OwnerUserId and b.Date < q.CreationDate) as badges_before
  from Posts q
  where q.PostTypeId = 1
),
-- tag popularity via tag table join (unnest tag arrays)
tag_popularity as (
  select t.TagName, t.Id as TagId, t.Count as TagCount
  from Tags t
),
question_tags as (
  select q.Id as QuestionId, trim(tg) as TagName
  from questions q
  cross join unnest(q.tag_array) as tg
),
-- explode questions by tag and join metrics
q_metrics as (
  select 
    q.Id as question_id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score as question_score,
    q.ViewCount,
    coalesce(aa.avg_answer_score,0) as avg_answer_score,
    coalesce(aa.max_answer_score,0) as max_answer_score,
    coalesce(aa.hours_to_accepted, null) as hours_to_accepted,
    coalesce(cs.comment_count,0) as comment_count,
    coalesce(cs.avg_comment_len,0) as avg_comment_len,
    coalesce(ob.badges_before,0) as owner_badges_before,
    bc.BestUserId,
    bc.BestUserReputation,
    jt.TagName,
    tp.TagCount
  from questions q
  left join answer_aggs aa on aa.QuestionId = q.Id
  left join comment_stats cs on cs.PostId = q.Id
  left join owner_badges ob on ob.QuestionId = q.Id
  left join best_contributor bc on bc.QuestionId = q.Id
  left join question_tags jt on jt.QuestionId = q.Id
  left join tag_popularity tp on tp.TagName = jt.TagName
),
-- rank questions within each tag by a composite score with null-safe arithmetic and non-linear terms
tag_ranks as (
  select qm.*,
    -- composite score: weighted combination with logarithms and null-safe coalesce
    (
      (coalesce(qm.question_score,0) * 1.5)
      + (log(coalesce(qm.ViewCount,1)+1) * 2.0)
      + (coalesce(qm.avg_answer_score,0) * 3.0)
      - (coalesce(qm.hours_to_accepted,1000) / nullif((coalesce(qm.comment_count,0)+1),0) )
      + (coalesce(qm.owner_badges_before,0) * 0.25)
      + (coalesce(qm.BestUserReputation,0) / 1000.0)
      + (case when qm.TagCount is null then 0 else (-ln(qm.TagCount+1)+5) end)
    ) as composite_score,
    row_number() over (partition by qm.TagName order by 
        (
          (coalesce(qm.question_score,0) * 1.5)
          + (log(coalesce(qm.ViewCount,1)+1) * 2.0)
          + (coalesce(qm.avg_answer_score,0) * 3.0)
          - (coalesce(qm.hours_to_accepted,1000) / nullif((coalesce(qm.comment_count,0)+1),0) )
          + (coalesce(qm.owner_badges_before,0) * 0.25)
          + (coalesce(qm.BestUserReputation,0) / 1000.0)
          + (case when qm.TagCount is null then 0 else (-ln(qm.TagCount+1)+5) end)
        ) desc, qm.CreationDate desc
    ) as tag_rank
  from q_metrics qm
  where qm.TagName is not null and qm.TagName <> ''
),
-- pick top N per tag and compute additional analytics via correlated subqueries
top_per_tag as (
  select tr.*,
    -- existence checks and correlated scalar subqueries
    exists (
      select 1 from Posts p2 
      where p2.ParentId = tr.question_id and p2.Score > tr.max_answer_score
    ) as has_stronger_answer_elsewhere,
    (
      select count(*) from PostLinks pl
      where pl.PostId = tr.question_id and pl.LinkTypeId = 1
    ) as outbound_links,
    (
      select count(*) from PostLinks pl
      where pl.RelatedPostId = tr.question_id and pl.LinkTypeId = 1
    ) as inbound_links,
    -- string expression: abbreviated title with NULL logic
    case when tr.Title is null then '[no title]' 
         when char_length(tr.Title) <= 80 then tr.Title
         else substr(tr.Title,1,77) || '...'
    end as short_title
  from tag_ranks tr
  where tr.tag_rank <= 5
)
-- final union: combine top_per_tag with a complementary set of globally top questions (set operator)
select
  t.TagName,
  t.question_id,
  t.short_title,
  t.CreationDate,
  round(t.composite_score::numeric,4) as composite_score,
  t.question_score,
  t.ViewCount,
  t.avg_answer_score,
  t.hours_to_accepted,
  t.comment_count,
  t.avg_comment_len,
  t.BestUserId,
  t.BestUserReputation,
  t.owner_badges_before,
  t.outbound_links,
  t.inbound_links,
  t.has_stronger_answer_elsewhere
from top_per_tag t

union

-- global top questions by different metric (to stress set operator and different ordering)
select
  null as TagName,
  q.Id as question_id,
  case when q.Title is null then '[no title]' 
       when char_length(q.Title) <= 80 then q.Title
       else substr(q.Title,1,77) || '...' end as short_title,
  q.CreationDate,
  round(
    (
      (coalesce(q.Score,0) * 2.0)
      + (log(coalesce(q.ViewCount,1)+1) * 1.5)
      + coalesce((select avg(a.Score) from Posts a where a.ParentId = q.Id),0) * 2.5
      - coalesce((select extract(epoch from (min(a.CreationDate) - q.CreationDate))/3600 from Posts a where a.ParentId = q.Id and a.Id = q.AcceptedAnswerId),0)
    )::numeric,4) as composite_score,
  q.Score as question_score,
  q.ViewCount,
  coalesce((select avg(a.Score) from Posts a where a.ParentId = q.Id),0) as avg_answer_score,
  coalesce((select extract(epoch from (a.CreationDate - q.CreationDate))/3600 from Posts a where a.ParentId = q.Id and a.Id = q.AcceptedAnswerId limit 1), null) as hours_to_accepted,
  coalesce((select count(*) from Comments c where c.PostId = q.Id),0) as comment_count,
  coalesce((select avg(char_length(c.Text)) from Comments c where c.PostId = q.Id),0) as avg_comment_len,
  (select bc.UserId from best_contributor bc where bc.QuestionId = q.Id) as BestUserId,
  (select bc.BestUserReputation from best_contributor bc where bc.QuestionId = q.Id) as BestUserReputation,
  (select ob.badges_before from owner_badges ob where ob.QuestionId = q.Id) as owner_badges_before,
  (select count(*) from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 1) as outbound_links,
  (select count(*) from PostLinks pl where pl.RelatedPostId = q.Id and pl.LinkTypeId = 1) as inbound_links,
  false as has_stronger_answer_elsewhere
from Posts q
where q.PostTypeId = 1
  and q.CreationDate >= now() - interval '90 days'
order by composite_score desc, comment_count desc
limit 100;