-- {"query": "7032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2419} 
with
-- recent activity per post with derived tag array and normalized owner
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.title,
    p.tags,
    coalesce(p.owneruserid, -1) as ownerid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    -- normalize tags into rows via string functions (works in Postgres-style)
    case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags,2,length(p.tags)-2), '><') end as tag_array
  from posts p
  where p.creationdate >= now() - interval '5 years'
),
-- aggregate votes by meaningful categories and most recent vote per post
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    max(v.creationdate) filter (where v.votetypeid in (2,3,5)) as last_interaction
  from votes v
  group by v.postid
),
-- compute per-user reputation velocity and recent badge counts
user_stats as (
  select
    u.id,
    u.reputation,
    -- reputation gained per year since creation (guard against zero)
    case when extract(epoch from (now() - u.creationdate))/86400 < 1 then u.reputation
         else round(u.reputation / greatest(1.0, extract(year from age(now(), u.creationdate))::numeric),2) end as rep_per_year,
    count(b.*) filter (where b.class = 1) as gold_badges,
    count(b.*) filter (where b.class = 2) as silver_badges,
    count(b.*) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.creationdate
),
-- compute windowed answer statistics per question
answer_stats as (
  select
    q.id as question_id,
    count(a.*) filter (where a.score >= 0) as positive_answers,
    count(a.*) filter (where a.score < 0) as negative_answers,
    avg(a.score) filter (where a.posttypeid = 2) over (partition by q.id) as avg_answer_score,
    max(a.creationdate) filter (where a.posttypeid = 2) as last_answer_date,
    -- rank answers by score within each question to find top answers
    array_agg(a.id order by a.score desc, a.creationdate asc) filter (where a.posttypeid = 2) as answer_id_rankings
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
  group by q.id
),
-- correlated subquery heavy CTE: for each post compute nearest linked duplicate distance and count of incoming links
link_metrics as (
  select
    p.id,
    coalesce(sum(case when lt.name = 'Duplicate' then 1 else 0 end),0) as duplicate_outgoing_count,
    coalesce(sum(case when lt.name = 'Linked' then 1 else 0 end),0) as linked_outgoing_count,
    (select count(*) from postlinks pl where pl.relatedpostid = p.id) as incoming_link_count,
    -- find smallest absolute time difference between this post and any related post (expensive correlated subquery)
    (select min(abs(extract(epoch from (p.creationdate - p2.creationdate)))) from posts p2 join postlinks pl2 on (pl2.relatedpostid = p2.id or pl2.postid = p2.id) where (pl2.postid = p.id or pl2.relatedpostid = p.id) and p2.id <> p.id) as min_related_post_seconds
  from posts p
  left join postlinks pl on pl.postid = p.id
  left join linktypes lt on lt.id = pl.linktypeid
  group by p.id, p.creationdate
),
-- tag popularity by aggregating questions that reference them
tag_popularity as (
  select
    t.tagname,
    t.id as tagid,
    t.count as total_count,
    coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as question_count,
    coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answer_count,
    -- top scoring question id for tag via subquery
    (select p2.id from posts p2 where p2.posttypeid = 1 and p2.tags like ('%<'||t.tagname||'>%') order by p2.score desc limit 1) as top_question_for_tag
  from tags t
  left join posts p on p.tags is not null and p.tags like ('%<'||t.tagname||'>%')
  group by t.tagname, t.id, t.count
),
-- heavy-weight combined ranking: score posts by multiple signals, include string manipulations and null logic
scored_posts as (
  select
    rp.id,
    rp.posttypeid,
    rp.parentid,
    rp.title,
    rp.tags,
    rp.tag_array,
    rp.ownerid,
    rp.creationdate,
    rp.lastactivitydate,
    rp.score,
    rp.viewcount,
    vp.upvotes,
    vp.downvotes,
    vp.favorites,
    vs.reputation as owner_reputation,
    us.rep_per_year,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    am.duplicate_outgoing_count,
    am.incoming_link_count,
    am.min_related_post_seconds,
    coalesce(a.avg_answer_score, 0) as avg_answer_score,
    coalesce(a.positive_answers,0) as positive_answers,
    coalesce(a.negative_answers,0) as negative_answers,
    -- textual richness: length of title + length of trimmed body (via correlated subquery)
    (length(coalesce(rp.title,'')) + coalesce( (select max(length(substring(body for 10000))) from posts pbody where pbody.id = rp.id), 0) ) as textual_length,
    -- compute a composite weight with NULL-aware math and some non-linear scaling
    (
      -- base: normalized votes
      (coalesce(vp.upvotes,0) - coalesce(vp.downvotes,0)) * 1.5
      -- view influence (log-scale)
      + ln(nullif(coalesce(rp.viewcount,0),0) + 1) * 2.0
      -- owner reputation influence (sqrt)
      + sqrt(coalesce(us.rep_per_year,0) + 1) * 3.0
      -- badge boost
      + (coalesce(us.gold_badges,0) * 5 + coalesce(us.silver_badges,0) * 2 + coalesce(us.bronze_badges,0) * 0.5)
      -- answer quality penalty/bonus
      + case when rp.posttypeid = 1 then coalesce(a.avg_answer_score,0) * 1.2 else 0 end
      -- duplicate penalty
      - coalesce(am.duplicate_outgoing_count,0) * 4.0
      -- recency decay (days)
      - extract(epoch from (now() - rp.lastactivitydate))/86400 * 0.01
    ) as composite_score
  from recent_posts rp
  left join vote_agg vp on vp.postid = rp.id
  left join users vs on vs.id = rp.ownerid
  left join user_stats us on us.id = rp.ownerid
  left join link_metrics am on am.id = rp.id
  left join answer_stats a on a.question_id = rp.id
)
select
  sp.id,
  sp.posttypeid,
  sp.title,
  -- human-friendly tag list reconstructed, limit to top 3 tags by global popularity (subquery)
  (select string_agg(tp.tagname, ', ') from tag_popularity tp where tp.tagname = any(sp.tag_array) order by tp.total_count desc limit 3) as top_local_tags,
  coalesce(sp.ownerid, -1) as ownerid,
  coalesce(sp.owner_reputation,0) as owner_reputation,
  round(sp.composite_score::numeric,4) as composite_score,
  coalesce(sp.upvotes,0) as upvotes,
  coalesce(sp.downvotes,0) as downvotes,
  coalesce(sp.favorites,0) as favorites,
  coalesce(sp.avg_answer_score,0) as avg_answer_score,
  sp.positive_answers,
  sp.negative_answers,
  -- detect suspicious posts: high composite but low textual_length or very recent floods of links (uses NULL logic)
  case
    when sp.composite_score > 50 and sp.textual_length < 50 then 'Possible low-quality viral'
    when sp.min_related_post_seconds is not null and sp.min_related_post_seconds < 3600 then 'Potential duplicate burst'
    when sp.composite_score > 100 then 'High-signal'
    else 'Normal'
  end as quality_flag,
  -- compute percentile rank across the window of composite scores
  rank() over (order by sp.composite_score desc) as global_rank,
  dense_rank() over (partition by sp.posttypeid order by sp.composite_score desc) as rank_by_type,
  -- show a compact summary string with careful NULL handling and substringing
  (coalesce(left(sp.title,80), '<no title>') || ' | tags: ' || coalesce(
     (select string_agg(tp2.tagname, ', ') from tag_popularity tp2 where tp2.tagname = any(sp.tag_array) order by tp2.total_count desc limit 5),
     '<none>'
  )
  || ' | score=' || coalesce(sp.score::text,'0')
  || ' | votes=' || coalesce(sp.upvotes::text,'0') || '/' || coalesce(sp.downvotes::text,'0')
  ) as compact_summary,
  now() as generated_at
from scored_posts sp
-- filter to interesting candidates (questions or highly scored answers), include correlated subquery to ensure accepted answers are prioritized
where (
  sp.posttypeid = 1
  or (sp.posttypeid = 2 and sp.composite_score > 10)
)
and (
  -- include if owner is active (last access within 2 years) OR post has many incoming links
  exists (select 1 from users u where u.id = sp.ownerid and u.lastaccessdate > now() - interval '2 years')
  or (select coalesce(sum(1),0) from postlinks pl where pl.relatedpostid = sp.id) > 3
)
order by sp.composite_score desc, sp.upvotes desc
limit 250;