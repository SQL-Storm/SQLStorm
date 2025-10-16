-- {"query": "7094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2290} 
with
-- recent active questions with tag arrays and normalized owner info
recent_qs as (
  select
    p.id,
    p.title,
    p.creationdate,
    p.lastactivitydate,
    p.viewcount,
    p.score,
    p.answercount,
    p.owneruserid,
    nullif(p.tags,'') as raw_tags,
    -- parse tags like '<sql><performance>' -> array ['sql','performance']
    case when p.tags is null then null
         else regexp_split_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '\>\<')
    end as tag_array
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= now() - interval '365 days'
),
-- best answer metrics per question (including accepted)
answers_agg as (
  select
    a.parentid as questionid,
    count(*) filter (where a.score >= 0) as pos_answer_count,
    count(*) filter (where a.score < 0) as neg_answer_count,
    max(a.score) as top_answer_score,
    avg(a.score) as avg_answer_score,
    sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted
  from posts a
  join posts q on q.id = a.parentid
  where a.posttypeid = 2
    and a.creationdate >= now() - interval '730 days' -- only recent answers
  group by a.parentid, q.acceptedanswerid
),
-- heavy hitters: users with many contributions and mixed reputation
user_stats as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.viewcount,
    coalesce(b.badge_gold,0) as gold_badges,
    coalesce(b.badge_silver,0) as silver_badges,
    coalesce(b.badge_bronze,0) as bronze_badges,
    -- recent activity: last access and most recent post
    u.lastaccessdate,
    (select max(p.creationdate) from posts p where p.owneruserid = u.id) as last_post_date,
    -- variance-ish: ratio of up/down votes if available
    case when u.downvotes is null or u.upvotes is null then null
         when u.downvotes = 0 then null
         else (1.0 * u.upvotes) / nullif(u.downvotes,0)
    end as up_down_ratio
  from users u
  left join (
    select userId,
      sum(case when class = 1 then 1 else 0 end) as badge_gold,
      sum(case when class = 2 then 1 else 0 end) as badge_silver,
      sum(case when class = 3 then 1 else 0 end) as badge_bronze
    from badges
    group by userid
  ) b on b.userid = u.id
),
-- correlated per-question expensive calculations
question_enrichment as (
  select
    q.*,
    ua.top_answer_score,
    ua.pos_answer_count,
    ua.neg_answer_count,
    ua.avg_answer_score,
    ua.has_accepted,
    -- compute number of distinct commenters (excluding post owner)
    (select count(distinct c.userid)
     from comments c
     where c.postid = q.id
       and c.userid is not null
       and c.userid <> q.owneruserid) as distinct_commenters,
    -- count incoming links (other posts linking to this question)
    (select count(*) from postlinks pl where pl.relatedpostid = q.id) as inbound_links,
    -- count duplicates (LinkTypeId = 3 means duplicate)
    (select count(*) from postlinks pl where pl.relatedpostid = q.id and pl.linktypeid = 3) as duplicate_count,
    -- most recent edit summary (from posthistory) and number of edits
    ph.last_edit_date,
    ph.edit_count,
    -- lightweight tag score: sum of tag popularity (tag count) for tags on question
    (select coalesce(sum(t.count),0)
     from tags t
     where exists (
       select 1 from unnest(q.tag_array) as tagname where tagname = t.tagname
     )
    ) as tag_popularity_sum
  from recent_qs q
  left join (
    select ph.postid,
      max(ph.creationdate) as last_edit_date,
      count(*) as edit_count
    from posthistory ph
    where ph.posthistorytypeid in (4,5,6,7,8,9,24,66) -- edits and suggestions and wizard
    group by ph.postid
  ) ph on ph.postid = q.id
  left join answers_agg ua on ua.questionid = q.id
),
-- window to rank questions by a composite "hotness" score
hotness as (
  select
    qe.*,
    -- composite score mixing views, score, recent activity, answers, tag popularity, inbound links, edits
    (
      coalesce(qe.viewcount,0) * 0.001
      + coalesce(qe.score,0) * 5
      + coalesce(qe.answercount,0) * 10
      + coalesce(qe.pos_answer_count,0) * 3
      - coalesce(qe.neg_answer_count,0) * 5
      + coalesce(qe.top_answer_score,0) * 2
      + coalesce(qe.tag_popularity_sum,0) * 0.02
      + coalesce(qe.inbound_links,0) * 1.5
      + coalesce(qe.edit_count,0) * 0.5
      + case when qe.has_accepted > 0 then -20 else 0 end
      + case when qe.distinct_commenters > 5 then 15 else qe.distinct_commenters * 2 end
    ) as hot_score,
    row_number() over (order by 
      (coalesce(qe.viewcount,0) * 0.001
      + coalesce(qe.score,0) * 5
      + coalesce(qe.answercount,0) * 10
      + coalesce(qe.pos_answer_count,0) * 3
      - coalesce(qe.neg_answer_count,0) * 5
      + coalesce(qe.top_answer_score,0) * 2
      + coalesce(qe.tag_popularity_sum,0) * 0.02
      + coalesce(qe.inbound_links,0) * 1.5
      + coalesce(qe.edit_count,0) * 0.5
      + case when qe.has_accepted > 0 then -20 else 0 end
      + case when qe.distinct_commenters > 5 then 15 else qe.distinct_commenters * 2 end) desc) as hot_rank
  from question_enrichment qe
),
-- tag co-occurrence sample for top N hot questions
tag_pairs as (
  select
    h.id as questionid,
    lower(trim(t1.tagname)) as tag1,
    lower(trim(t2.tagname)) as tag2,
    -- pair weight based on question hot_score and inverse tag popularity to favor niche pairs
    (h.hot_score * (1 / nullif(1 + greatest(1,
       (select coalesce(sum(count),0) from tags tt where tt.tagname = lower(t1.tagname))
    ),1))) as pair_weight
  from hotness h
  cross join lateral unnest(h.tag_array) with ordinality as t1(tagname, ord1)
  cross join lateral unnest(h.tag_array) with ordinality as t2(tagname, ord2)
  where t1.ord1 < t2.ord2
    and h.hot_rank <= 200
),
-- aggregate tag pair weights
tag_pair_agg as (
  select tag1, tag2, count(distinct questionid) as cooccurrence_count, sum(pair_weight) as total_weight
  from tag_pairs
  group by tag1, tag2
  order by total_weight desc
  limit 100
)
select
  h.hot_rank,
  h.id as question_id,
  h.title,
  -- show a shortened snippet of body length estimation and normalized title
  substr(coalesce(regexp_replace((select body from posts p where p.id = h.id limit 1), '<[^>]+>',' ','g'), ''),1,240) as excerpt_plaintext,
  h.creationdate,
  h.lastactivitydate,
  h.viewcount,
  h.score as question_score,
  h.answercount,
  h.pos_answer_count,
  h.neg_answer_count,
  h.top_answer_score,
  h.avg_answer_score,
  h.has_accepted > 0 as has_accepted,
  h.distinct_commenters,
  h.inbound_links,
  h.duplicate_count,
  h.edit_count,
  h.tag_popularity_sum,
  round(h.hot_score::numeric,2) as hot_score,
  -- owner enrichment (may be null if community-owned)
  us.displayname as owner_displayname,
  us.reputation as owner_reputation,
  us.gold_badges,
  us.silver_badges,
  us.bronze_badges,
  -- correlated: best answer excerpt (if exists) using lateral correlated subquery with NULL logic
  ba.best_answer_id,
  ba.best_answer_score,
  substr(coalesce(regexp_replace(ba.body,'<[^>]+>',' ','g'), ''),1,200) as best_answer_excerpt,
  -- JSON-ish aggregation of top co-occurring tag pairs for this question
  (select string_agg(tp.tag1 || '|' || tp.tag2 || ':' || tp.cooccurrence_count || '/' || round(tp.total_weight::numeric,2), ', ')
   from tag_pair_agg tp
   where tp.tag1 = any(h.tag_array) or tp.tag2 = any(h.tag_array)
   limit 5
  ) as related_tag_pairs
from hotness h
left join lateral (
  select a.id as best_answer_id, a.score as best_answer_score, a.body
  from posts a
  where a.posttypeid = 2
    and a.parentid = h.id
  order by
    -- heuristic: accepted first, then score desc, then newest
    case when a.id = (select acceptedanswerid from posts where id = h.id) then 0 else 1 end,
    a.score desc nulls last,
    a.creationdate desc
  limit 1
) ba on true
left join users us on us.id = h.owneruserid
where h.hot_rank between 1 and 200
order by h.hot_score desc, h.lastactivitydate desc;