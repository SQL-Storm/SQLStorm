-- {"query": "48.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2289} 
with
-- recent high-impact questions with tag arrays and normalized score metrics
recent_q as (
  select
    p.id,
    p.title,
    p.tags,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.owneruserid,
    coalesce(p.favoritecount,0) as favoritecount,
    -- extract tags into array-like set (postgres style)
    case when p.tags is null then array[]::text[] else string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><') end as tag_list
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '1 year'
    and (p.score >= 5 or p.viewcount >= 1000 or p.answercount >= 3)
),
-- compute user aggregates and recency-weighted reputation
user_stats as (
  select
    u.id as userid,
    u.displayname,
    u.reputation,
    u.creationdate,
    count(b.id) filter (where b.class = 1) as gold_badges,
    count(b.id) filter (where b.class = 2) as silver_badges,
    count(b.id) filter (where b.class = 3) as bronze_badges,
    count(distinct p.id) as posts_count,
    -- recency score: reputation decays with account age, boosted by recent access
    (u.reputation::numeric / greatest(1, date_part('year', age(now(), u.creationdate)))) *
      (1 + least(1, age(now(), u.lastaccessdate) < interval '30 days')::int * 0.25) as recency_reputation
  from users u
  left join badges b on b.userid = u.id
  left join posts p on p.owneruserid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate
),
-- answer metrics joined to parent questions, including accepted and score windows
answers_extended as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid,
    a.creationdate as answer_creation,
    a.score as answer_score,
    a.body,
    a.commentcount,
    a.communityowneddate,
    -- is accepted by question
    case when q.acceptedanswerid = a.id then true else false end as is_accepted,
    -- rank answers per question by score, tiebreaker by creationdate
    row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as answer_rank,
    dense_rank() over (partition by a.parentid order by a.score desc nulls last) as answer_dense_rank,
    -- relative score: answer score divided by max score for that question
    a.score::numeric / nullif(max(a.score) over (partition by a.parentid),0) as relative_score
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
),
-- compute for each question a synthetic difficulty metric using views, answer count, tags, and recent edits
question_complexity as (
  select
    rq.*,
    us.displayname as owner_name,
    us.reputation as owner_reputation,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    (coalesce(rq.viewcount,0) * 0.4 + coalesce(rq.answercount,0) * 30 + coalesce(rq.score,0) * 20 + coalesce(rq.favoritecount,0) * 50) *
      greatest(1, least(5, array_length(rq.tag_list,1))) as raw_complexity,
    -- flag if any posthistory entries indicate closure or heavy edits
    exists(
      select 1 from posthistory ph
      where ph.postid = rq.id
        and ph.posthistorytypeid in (10,12,17,35,36)
        and ph.creationdate >= rq.creationdate - interval '30 days'
    ) as recently_flagged_or_migrated
  from recent_q rq
  left join user_stats us on us.userid = rq.owneruserid
),
-- collect link graph metrics: inbound/outbound links and duplicates
link_graph as (
  select
    p.id as postid,
    count(pl.id) filter (where pl.postid = p.id) as outbound_links,
    count(pl.id) filter (where pl.relatedpostid = p.id) as inbound_links,
    count(pl.id) filter (where pl.linktypeid = 3) as duplicates_of_others,
    count(pl.id) filter (where pl.linktypeid = 3 and pl.postid = p.id) as marked_duplicate_count
  from posts p
  left join postlinks pl on (pl.postid = p.id or pl.relatedpostid = p.id)
  group by p.id
),
-- tag popularity snapshot (top N tags in recent questions)
tag_pop as (
  select t.tag as tagname, count(*) as cnt
  from (
    select unnest(tag_list) as tag from recent_q
  ) t
  group by t.tag
),
-- candidate set: join complex questions with links, answers, and compute ranking score
candidates as (
  select
    qc.id,
    qc.title,
    qc.creationdate,
    qc.score,
    qc.viewcount,
    qc.answercount,
    qc.tag_list,
    qc.owneruserid,
    qc.owner_name,
    qc.owner_reputation,
    qc.gold_badges,
    qc.silver_badges,
    qc.bronze_badges,
    qc.raw_complexity,
    qc.recently_flagged_or_migrated,
    lg.outbound_links,
    lg.inbound_links,
    lg.duplicates_of_others,
    -- aggregate top answers info
    (select json_agg(row_to_json(r)) from (
       select ae.answer_id, ae.answer_score, ae.is_accepted, ae.answer_rank
       from answers_extended ae
       where ae.question_id = qc.id
       order by ae.answer_score desc nulls last, ae.answer_creation asc
       limit 5
    ) r) as top_answers,
    -- recent comment sentiment-ish: length and count heuristics (synthetic)
    (select count(*) from comments c where c.postid = qc.id and c.creationdate >= qc.creationdate - interval '30 days') as recent_comments_count,
    (select avg(char_length(coalesce(c.text,''))) from comments c where c.postid = qc.id) as avg_comment_length
  from question_complexity qc
  left join link_graph lg on lg.postid = qc.id
),
-- score normalization and final rank, including correlated subquery for duplicate/linked question score penalty
ranked as (
  select
    c.*,
    -- penalty if linked to many duplicates
    greatest(0, (coalesce(c.duplicates_of_others,0) - 0) * 10) as duplicate_penalty,
    -- boost for owner reputation and badges (log-scaled)
    (ln(greatest(1, coalesce(c.owner_reputation,1))) * 2.0 + ln(1 + coalesce(c.gold_badges,0)) * 5 + ln(1 + coalesce(c.silver_badges,0)) * 2.5) as author_influence,
    -- tag popularity penalty: sum of inverse popularity (rare tags increase complexity)
    (select sum(1.0 / nullif(tp.cnt,1)) from (select unnest(c.tag_list) as tag) t join tag_pop tp on tp.tagname = t.tag) as tag_rarity_score,
    -- correlated: count distinct answers by users with > 1000 rep (as quality signal)
    (select count(distinct a.owneruserid) from posts a join users u on u.id = a.owneruserid where a.parentid = c.id and a.posttypeid = 2 and u.reputation > 1000) as highrep_answerers,
    -- combine into composite score
    (
      (coalesce(c.raw_complexity,0) * 0.6)
      + (coalesce(c.viewcount,0) / greatest(1, nullif(coalesce(c.answercount,0),0) + 1) * 0.1)
      + (coalesce(c.author_influence,0) * 5)
      + (coalesce(c.tag_rarity_score,0) * 20)
      + (coalesce(c.highrep_answerers,0) * 15)
      - greatest(0, coalesce(c.duplicate_penalty,0))
      - (case when c.recently_flagged_or_migrated then 100 else 0 end)
    ) as composite_score
  from candidates c
),
-- final selection ordering with ties broken by nuanced window functions
final_pick as (
  select
    r.*,
    row_number() over (order by r.composite_score desc nulls last, r.raw_complexity desc nulls last, r.creationdate asc) as global_rank,
    rank() over (partition by (select min(tag) from (select unnest(r.tag_list) as tag) t) order by r.composite_score desc) as per_tag_rank,
    -- compute z-score of composite_score among all candidates
    (r.composite_score - avg(r.composite_score) over ()) / nullif(stddev_samp(r.composite_score) over (),0) as composite_z
  from ranked r
)
select
  fp.global_rank,
  fp.id as question_id,
  left(fp.title,200) as title_snippet,
  fp.creationdate,
  fp.score as question_score,
  fp.viewcount,
  fp.answercount,
  fp.tag_list,
  fp.owneruserid,
  fp.owner_name,
  round(fp.owner_reputation::numeric,2) as owner_reputation,
  fp.gold_badges,
  fp.silver_badges,
  fp.bronze_badges,
  coalesce(fp.top_answers::text,'[]') as top_answers_json,
  fp.recent_comments_count,
  round(coalesce(fp.avg_comment_length,0),1) as avg_comment_length,
  round(fp.raw_complexity,2) as raw_complexity,
  round(fp.composite_score,4) as composite_score,
  round(fp.composite_z::numeric,3) as composite_z,
  fp.recently_flagged_or_migrated,
  fp.inbound_links,
  fp.outbound_links,
  fp.duplicates_of_others
from final_pick fp
where fp.global_rank <= 50
order by fp.composite_score desc, fp.raw_complexity desc, fp.global_rank asc;