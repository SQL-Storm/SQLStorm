-- {"query": "1.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2381} 
with
-- active users with a weighted score from reputation, badges, and recent activity
active_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.views,0) as views,
    (
      u.reputation * 0.6
      + coalesce((select count(*) from badges b where b.userid = u.id and b.class = 1),0) * 200
      + coalesce((select count(*) from badges b where b.userid = u.id and b.class = 2),0) * 50
      + coalesce((select count(*) from badges b where b.userid = u.id and b.class = 3),0) * 10
      + least(1000, coalesce(u.upvotes,0) - coalesce(u.downvotes,0)) * 0.1
      + greatest(0, date_part('epoch', now() - u.lastaccessdate)/86400 * -0.05)
    ) as activity_score
  from users u
  where u.reputation > 0
),

-- questions with parsed tag arrays, tag counts, and body summary
questions as (
  select
    p.id,
    p.title,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.tags,
    -- try to split tags stored like '<tag1><tag2>' into array; tolerate nulls
    case when p.tags is null then array[]::varchar[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_array,
    left(trim(regexp_replace(coalesce(p.body,''), '<[^>]*>',' ','g')), 400) as body_snippet
  from posts p
  where p.posttypeid = 1
),

-- compute per-question aggregated signals: top answer, accepted, median answer score, comment stats
question_signals as (
  select
    q.*,
    -- accepted answer score and id (nullable)
    a_accepted.id as accepted_answer_id,
    a_accepted.score as accepted_answer_score,
    -- best answer by score among answers (ties broken by earliest creation)
    (select id from posts a where a.parentid = q.id order by a.score desc nulls last, a.creationdate asc limit 1) as best_answer_id,
    -- median answer score using percentile_cont
    (select cast(percentile_cont(0.5) within group (order by coalesce(a.score,0)) as numeric) from posts a where a.parentid = q.id) as median_answer_score,
    -- comments count on question
    (select count(*) from comments c where c.postid = q.id) as q_comment_count,
    -- total comments on answers to the question
    (select count(*) from comments c join posts a on c.postid = a.id where a.parentid = q.id) as a_comment_count,
    -- link counts (incoming/outgoing)
    (select count(*) from postlinks pl where pl.postid = q.id) as outgoing_links,
    (select count(*) from postlinks pl where pl.relatedpostid = q.id) as incoming_links
  from questions q
  left join posts a_accepted on a_accepted.id = q.acceptedanswerid
),

-- rank tags by many dimensions: popularity, avg question score, avg viewcount, distinct askers
tag_metrics as (
  select
    t.tagname,
    t.id as tagid,
    t.count as tag_count,
    coalesce(avg(q.score),0) as avg_q_score,
    coalesce(avg(q.viewcount),0) as avg_q_views,
    count(distinct q.owneruserid) as distinct_askers,
    -- proportion of questions with accepted answers
    coalesce(sum(case when q.acceptedanswerid is not null then 1 else 0 end)::numeric / nullif(count(q.id),0),0) as accepted_rate,
    -- textual richness: avg length of body_snippet
    coalesce(avg(char_length(coalesce(q.body_snippet,''))),0) as avg_body_len,
    -- trending proxy: questions in last 30 days
    sum(case when q.creationdate > now() - interval '30 days' then 1 else 0 end) as recent_q_count
  from tags t
  left join posts p on p.posttypeid = 1 and (p.tags is not null and position('<' || t.tagname || '>' in p.tags) > 0)
  left join questions q on q.id = p.id
  group by t.id, t.tagname, t.count
),

-- top active users per tag based on answers and score (complex correlated aggregates)
tag_top_contributors as (
  select distinct on (tm.tagid)
    tm.tagid,
    tm.tagname,
    u.id as userid,
    u.displayname,
    -- contributor score: weighted sum of answers to tag, avg answer score, badges with tag in name (heuristic), recent activity
    (
      coalesce(sub.answers_to_tag,0) * 3.0
      + coalesce(sub.avg_answer_score,0) * 2.0
      + coalesce(sub.badge_tag_matches,0) * 5.0
      + coalesce(sub.recent_answers,0) * 1.5
    ) as contributor_score,
    sub.answers_to_tag,
    sub.avg_answer_score,
    sub.badge_tag_matches,
    sub.recent_answers
  from tag_metrics tm
  left join lateral (
    select
      ua.id,
      ua.displayname,
      count(a.id) filter (where a.posttypeid = 2) as answers_to_tag,
      coalesce(avg(a.score) filter (where a.posttypeid = 2),0) as avg_answer_score,
      sum(case when b.tagbased = 1 and b.name ilike '%' || tm.tagname || '%' then 1 else 0 end) as badge_tag_matches,
      count(a.id) filter (where a.posttypeid = 2 and a.creationdate > now() - interval '90 days') as recent_answers
    from users ua
    join posts a on a.owneruserid = ua.id
    where a.posttypeid = 2
      and exists (
        select 1 from posts q where q.id = a.parentid and q.tags is not null and position('<' || tm.tagname || '>' in q.tags) > 0
      )
    group by ua.id, ua.displayname
    order by answers_to_tag desc nulls last, avg_answer_score desc nulls last
    limit 5
  ) sub on true
  join users u on u.id = sub.id
  order by tm.tagid, contributor_score desc
),

-- combine everything into per-question diagnostic rows with heavy expressions
question_diagnostics as (
  select
    qs.id as question_id,
    qs.title,
    qs.owneruserid,
    au.displayname as owner_name,
    qs.creationdate,
    qs.score,
    qs.viewcount,
    qs.answercount,
    qs.tag_array,
    tm.tagname as primary_tag,
    tm.tag_count,
    tm.avg_q_score,
    tm.accepted_rate,
    qs.accepted_answer_id,
    qs.accepted_answer_score,
    qs.best_answer_id,
    qs.median_answer_score,
    qs.q_comment_count,
    qs.a_comment_count,
    qs.outgoing_links,
    qs.incoming_links,
    -- complexity metric: normalize combination of ops, protecting against null and zeros
    (
      greatest(0, coalesce(qs.score,0)) * 0.3
      + log(1 + greatest(0,coalesce(qs.viewcount,0))) * 0.25
      + coalesce(qs.answercount,0) * 0.2
      + coalesce(qs.q_comment_count,0) * 0.1
      + coalesce(tm.recent_q_count,0) * 0.05
      + (case when qs.accepted_answer_id is not null then 5 else 0 end)
    ) as complexity_score,
    -- fuzzy relevance: similarity of title to tagname and body (uses simple position/length heuristics)
    (case
       when qs.title is null then 0
       when tm.tagname is null then 0
       when position(lower(tm.tagname) in lower(coalesce(qs.title,''))) > 0 then 1
       else 0
     end) as tag_in_title,
    -- generate a synthetic summary string mixing fields
    left(
      concat(
        'Q:', qs.id, ' | ',
        coalesce(substr(qs.title,1,120),''), ' | tags:', coalesce(array_to_string(qs.tag_array,','),''), ' | owner:', coalesce(au.displayname,'[anon]'),
        ' | cs=', round((
          greatest(0, coalesce(qs.score,0)) * 0.3
          + log(1 + greatest(0,coalesce(qs.viewcount,0))) * 0.25
          + coalesce(qs.answercount,0) * 0.2
        )::numeric,2)
      ), 300
    ) as synthetic_summary
  from question_signals qs
  left join lateral (
    -- pick primary tag as the most frequent tag among tag_array based on tag_metrics.tag_count
    select tm.tagname, tm.tag_count, tm.avg_q_score, tm.accepted_rate, tm.recent_q_count
    from unnest(qs.tag_array) with ordinality as ta(tagname,ord)
    left join tag_metrics tm on tm.tagname = ta.tagname
    order by coalesce(tm.tag_count,0) desc nulls last
    limit 1
  ) tm on true
  left join users au on au.id = qs.owneruserid
)

select
  qd.*,
  -- include top contributors for the primary tag (if any)
  tc.userid as top_contributor_id,
  tc.displayname as top_contributor_name,
  tc.contributor_score,
  tc.answers_to_tag,
  tc.avg_answer_score,
  -- windowed rank of question within primary tag by complexity_score desc
  row_number() over (partition by qd.primary_tag order by qd.complexity_score desc) as rank_within_tag,
  dense_rank() over (order by qd.complexity_score desc) as global_complexity_rank
from question_diagnostics qd
left join lateral (
  select *
  from tag_top_contributors ttc
  where ttc.tagid = (select id from tags where tagname = qd.primary_tag limit 1)
  order by ttc.contributor_score desc
  limit 1
) tc on true
where qd.creationdate > now() - interval '365 days'
  and qd.viewcount is not null
  and (qd.accepted_answer_id is null or qd.accepted_answer_score < coalesce(qd.median_answer_score,0) * 0.5)
order by qd.complexity_score desc nulls last
limit 250;