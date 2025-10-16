-- {"query": "7042.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2238} 
with
-- recent activity per user with exponential recency weight
user_activity as (
  select
    u.id as user_id,
    count(distinct p.id) filter (where p.posttypeid = 1) as questions_posted,
    count(distinct p.id) filter (where p.posttypeid = 2) as answers_posted,
    count(distinct c.id) as comments_posted,
    coalesce(sum(
      exp(-extract(epoch from (now() - greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(c.creationdate, '1970-01-01'::timestamp))))/ (60*60*24*30))
    ),0) as recency_score,
    max(u.reputation) as reputation,
    min(u.creationdate) as user_created
  from users u
  left join posts p on p.owneruserid = u.id
  left join comments c on c.userid = u.id
  group by u.id
),
-- compute per-question tag exploded rows
question_tags as (
  select
    q.id as question_id,
    trim(tag) as tag
  from posts q
  cross join lateral (
    select unnest(string_to_array(substring(q.tags from 2 for char_length(q.tags)-2), '><')) as tag
  ) t
  where q.posttypeid = 1 and q.tags is not null
),
-- aggregated tag popularity and quality metrics
tag_stats as (
  select
    qt.tag,
    count(distinct qt.question_id) as question_count,
    sum(coalesce(p.viewcount,0)) as total_views,
    avg(coalesce(p.score,0)) as avg_question_score,
    sum(coalesce(a.answer_count,0)) as total_answers,
    sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_count
  from question_tags qt
  join posts p on p.id = qt.question_id
  left join lateral (
    select count(*) as answer_count
    from posts a
    where a.parentid = p.id and a.posttypeid = 2
  ) a on true
  group by qt.tag
),
-- heavy window ranking of questions by combined metrics
question_rankings as (
  select
    q.id,
    q.title,
    q.creationdate,
    q.viewcount,
    q.score,
    q.answercount,
    q.acceptedanswerid,
    coalesce(array_agg(distinct qt.tag) filter (where qt.tag is not null), array[]::varchar[]) as tags,
    -- composite popularity metric: views * log(1+answers) + score*50 + accepted bonus
    (coalesce(q.viewcount,0) * ln(1 + coalesce(q.answercount,0) + 1)
     + coalesce(q.score,0) * 50
     + case when q.acceptedanswerid is not null then 1000 else 0 end
    ) as popularity_score,
    row_number() over (order by (coalesce(q.viewcount,0) * ln(1 + coalesce(q.answercount,0) + 1) + coalesce(q.score,0) * 50) desc, q.creationdate desc) as global_pop_rank,
    dense_rank() over (partition by date_trunc('month', q.creationdate) order by coalesce(q.viewcount,0) desc, coalesce(q.score,0) desc) as monthly_pop_rank
  from posts q
  left join question_tags qt on qt.question_id = q.id
  where q.posttypeid = 1
  group by q.id, q.title, q.creationdate, q.viewcount, q.score, q.answercount, q.acceptedanswerid
),
-- find suspicious duplicate links via postlinks and content similarity heuristic
duplicate_candidates as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.creationdate as link_date,
    p1.title as t1,
    p2.title as t2,
    length(p1.title) as l1,
    length(p2.title) as l2,
    levenshtein(lower(coalesce(p1.title,'')), lower(coalesce(p2.title,''))) as title_dist,
    similarity(lower(coalesce(p1.body,'')), lower(coalesce(p2.body,''))) as body_sim,
    pl.linktypeid
  from postlinks pl
  join posts p1 on p1.id = pl.postid
  join posts p2 on p2.id = pl.relatedpostid
  where pl.linktypeid = 3 -- duplicates
    and p1.posttypeid = 1 and p2.posttypeid = 1
),
-- user-level temporal badge-like bursts: detect users who got many answers accepted in short window
acceptance_bursts as (
  select
    a.owneruserid as answerer_id,
    date_trunc('day', p.creationdate) as day,
    count(*) as accepted_answers_that_day,
    sum(a.score) as sum_answer_scores
  from posts a
  join posts p on p.id = a.parentid and p.posttypeid = 1
  where a.posttypeid = 2 and p.acceptedanswerid = a.id
  group by a.owneruserid, date_trunc('day', p.creationdate)
  having count(*) >= 3
),
-- correlate votes with post age for decay analysis
vote_decay as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    min(v.creationdate) as first_vote,
    max(v.creationdate) as last_vote,
    age(max(v.creationdate), min(v.creationdate)) as vote_span
  from votes v
  group by v.postid
),
-- final selection combining a bunch of metrics and subqueries (including correlated)
candidate_questions as (
  select
    qr.*,
    ts.tag as primary_tag,
    ts.question_count,
    ts.total_views as tag_total_views,
    ts.avg_question_score as tag_avg_score,
    uc.recency_score,
    uc.reputation,
    vc.upvotes,
    vc.downvotes,
    vc.vote_span,
    dc.title_dist,
    dc.body_sim,
    ab.accepted_answers_that_day,
    -- correlated subquery: ratio of answerers who have >1000 rep among answerers to this question
    (
      select count(distinct a.owneruserid) filter (where u2.reputation > 1000)
      from posts a
      join users u2 on u2.id = a.owneruserid
      where a.parentid = qr.id and a.posttypeid = 2
    )::float
      /
    nullif((
      select count(distinct a2.owneruserid)
      from posts a2
      where a2.parentid = qr.id and a2.posttypeid = 2
    ),0) as highrep_answerer_ratio,
    -- string expression: headline for quick UI
    ('Q#' || qr.id || ': ' || coalesce(substr(qr.title,1,120),'')) as headline
  from question_rankings qr
  left join lateral (
    select tag
    from tag_stats ts
    join question_tags qt on qt.tag = ts.tag
    where qt.question_id = qr.id
    order by ts.question_count desc nulls last
    limit 1
  ) ts on true
  left join user_activity uc on uc.user_id = (select owneruserid from posts p where p.id = qr.id)
  left join vote_decay vc on vc.postid = qr.id
  left join lateral (
    select title_dist, body_sim
    from duplicate_candidates dc
    where dc.postid = qr.id
    order by dc.body_sim desc nulls last
    limit 1
  ) dc on true
  left join acceptance_bursts ab on ab.answerer_id = (select owneruserid from posts p2 where p2.id = qr.acceptedanswerid)
)
select
  cq.id,
  cq.headline,
  cq.creationdate,
  cq.tags,
  cq.popularity_score,
  cq.global_pop_rank,
  cq.monthly_pop_rank,
  cq.primary_tag,
  cq.question_count,
  round(cq.tag_total_views::numeric,0) as tag_total_views,
  round(cq.tag_avg_score::numeric,2) as tag_avg_score,
  round(cq.recency_score::numeric,4) as recency_score,
  cq.reputation,
  coalesce(cq.upvotes,0) as upvotes,
  coalesce(cq.downvotes,0) as downvotes,
  cq.vote_span,
  cq.title_dist,
  round(coalesce(cq.body_sim,0)::numeric,4) as body_similarity,
  round(coalesce(cq.highrep_answerer_ratio,0)::numeric,3) as highrep_answerer_ratio,
  coalesce(cq.accepted_answers_that_day,0) as accepted_burst_count,
  -- complex predicate label
  case
    when cq.popularity_score > 100000 and coalesce(cq.body_sim,0) > 0.6 then 'Hot-Duplicate-Likely'
    when cq.popularity_score > 50000 and coalesce(cq.highrep_answerer_ratio,0) > 0.5 then 'HighQualityHot'
    when cq.monthly_pop_rank <= 10 then 'Monthly-Top10'
    when cq.global_pop_rank <= 100 then 'Global-Top100'
    else 'Normal'
  end as classification,
  -- set operator example: union of tags for tag cluster (as text)
  (select string_agg(distinct t.tag, ',' order by t.tag)
   from (
     select tag from question_tags qta where qta.tag = cq.primary_tag
     union
     select tag from question_tags qtb where qtb.question_id in (
       select id from posts p where p.title ilike '%' || split_part(cq.primary_tag,'-',1) || '%'
     )
   ) t
  ) as cluster_tags
from candidate_questions cq
where
  -- complex predicate with null logic and inequalities
  (cq.popularity_score > 1000 or cq.tag_total_views > 5000 or coalesce(cq.upvotes,0) > 10)
  and (cq.reputation is null or cq.reputation > 50)
  and (cq.body_similarity is null or cq.body_similarity < 0.95)
order by cq.popularity_score desc nulls last
limit 200;