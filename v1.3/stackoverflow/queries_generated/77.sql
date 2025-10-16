-- {"query": "77.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1973} 
with
-- user aggregate: recent activity window and badge influence
user_activity as (
  select
    u.id as user_id,
    u.reputation,
    count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
    count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
    max(p.lastactivitydate) as last_activity,
    count(b.id) as badge_count,
    sum(case when b.class = 1 then 3 when b.class = 2 then 2 else 1 end) as badge_score,
    (extract(epoch from now() - coalesce(max(p.lastactivitydate), u.creationdate)) / 86400) as days_since_activity
  from users u
  left join posts p on p.owneruserid = u.id
  left join badges b on b.userid = u.id
  group by u.id, u.reputation, u.creationdate
),
-- posts with heavy computations: tag parsing, title fingerprint, answer stats
post_features as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    -- normalized tag list (split tags like '<tag1><tag2>' into rows later)
    p.tags,
    -- crude title fingerprint (length + words + uppercase ratio)
    length(coalesce(p.title,'')) as title_len,
    (length(coalesce(regexp_replace(p.title,'[^A-Za-z]+','','g'),'') )::float / nullif(greatest(length(coalesce(p.title,'')),1),0)) as title_alpha_ratio,
    (length(coalesce(regexp_replace(p.title,'[^A-Z]+','','g'),'') )::float / nullif(greatest(length(coalesce(p.title,'')),1),0)) as title_upper_ratio,
    -- heuristics: content density
    (length(coalesce(p.body,''))::float / nullif(greatest(nullif(p.viewcount,0),1),1)) as body_per_view,
    -- calculate accepted answer age if applicable (correlated subquery)
    (select extract(epoch from (a.creationdate - p.creationdate))/3600.0
       from posts a where a.id = p.acceptedanswerid
    ) as hours_to_accept
  from posts p
  where p.posttypeid in (1,2)
),
-- explode tags into rows for tag-level analytics
post_tags as (
  select
    pf.*,
    trim(both ' ' from t) as tag
  from post_features pf
  cross join lateral (
    select regexp_split_to_table(
      coalesce(substring(pf.tags from 2 for greatest(char_length(coalesce(pf.tags,'')) - 2,0)),''),
      '><'
    ) as t
  ) s
),
-- windowed ranking: within each tag, rank questions by a composite hotness score
tag_hotness as (
  select
    pt.tag,
    pt.id as question_id,
    pt.owneruserid,
    pt.title,
    pt.score,
    pt.viewcount,
    pt.answercount,
    coalesce(pt.hours_to_accept, 999999) as hours_to_accept,
    -- composite hotness: recent activity, score per view, badge boost of owner, inverse accept time
    ( (rank() over (partition by pt.tag order by pt.lastactivitydate desc))::float * -1
      + (pt.score::float * 2)
      + (log(greatest(pt.viewcount,1)) * 1.5)
      - (coalesce(pt.hours_to_accept,100000)::float / 24.0)
    ) as raw_hot_score,
    dense_rank() over (partition by pt.tag order by ( (pt.score::float * 2) + log(greatest(pt.viewcount,1)) ) desc) as popularity_rank
  from post_tags pt
  where pt.posttypeid = 1
),
-- deduplicate and compute tag co-occurrence and cross-tag influence
tag_graph as (
  select
    t1.tag as tag_a,
    t2.tag as tag_b,
    count(distinct t1.id) as co_question_count,
    sum(t1.score + t2.score) as co_score_sum,
    avg(t1.viewcount + t2.viewcount) as co_view_avg
  from post_tags t1
  join post_tags t2 on t1.id = t2.id and t1.tag < t2.tag
  group by t1.tag, t2.tag
),
-- compute per-user answer effectiveness via correlated subqueries and window functions
user_answer_stats as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    count(a.id) filter (where a.posttypeid = 2) as total_answers,
    count(a.id) filter (where a.posttypeid = 2 and a.id = q.acceptedanswerid) as accepted_count,
    avg(a.score) filter (where a.posttypeid = 2) as avg_answer_score,
    min(a.creationdate) filter (where a.posttypeid = 2) as first_answer,
    max(a.creationdate) filter (where a.posttypeid = 2) as last_answer,
    -- median answer length using percentile_disc
    percentile_disc(0.5) within group (order by length(coalesce(a.body,''))) filter (where a.posttypeid = 2) as median_answer_len,
    -- ratio accepted per answers with null-safe logic
    case when count(a.id) filter (where a.posttypeid = 2) = 0 then 0
         else (count(a.id) filter (where a.posttypeid = 2 and a.id = q.acceptedanswerid))::float / nullif(count(a.id) filter (where a.posttypeid = 2),0)
    end as accept_ratio
  from users u
  left join posts a on a.owneruserid = u.id and a.posttypeid = 2
  left join posts q on q.acceptedanswerid = a.id
  group by u.id, u.displayname, u.reputation
),
-- select interesting candidates: top tags by distinct question count, exclude low-activity tags
top_tags as (
  select tag, count(distinct id) as qcount, sum(score) as total_score
  from post_tags
  where tag is not null and tag <> ''
  group by tag
  having count(distinct id) > 50
  order by qcount desc
  limit 50
),
-- combine everything for final benchmarking projection
final_candidates as (
  select
    th.tag,
    th.question_id,
    th.title,
    th.score,
    th.viewcount,
    th.answercount,
    th.raw_hot_score,
    tg.co_question_count,
    tg.co_score_sum,
    tg.co_view_avg,
    ua.user_id,
    ua.reputation as owner_reputation,
    ua.accept_ratio as owner_accept_ratio,
    ua.total_answers as owner_total_answers,
    ua.median_answer_len,
    ua.avg_answer_score,
    -- enrich with user_activity heuristics
    uact.badge_score,
    uact.days_since_activity,
    -- string expression: compact title summary
    left(regexp_replace(coalesce(th.title,''), '\s+', ' ', 'g'), 120) || case when length(coalesce(th.title,'')) > 120 then '...' else '' end as title_snippet,
    -- null logic example: compute urgency score protecting against nulls
    (coalesce(th.raw_hot_score,0) * (1 + least(1.0, greatest(coalesce(uact.badge_score,0) / 10.0, 0)))) / nullif(1 + (coalesce(ua.accept_ratio,0)), 0.0001) as urgency_score
  from tag_hotness th
  left join tag_graph tg on (tg.tag_a = th.tag or tg.tag_b = th.tag)
  left join users ua_user on ua_user.id = th.owneruserid
  left join user_answer_stats ua on ua.user_id = th.owneruserid
  left join user_activity uact on uact.user_id = th.owneruserid
  join top_tags tt on tt.tag = th.tag
)
select
  fc.tag,
  fc.question_id,
  fc.title_snippet,
  fc.score,
  fc.viewcount,
  fc.answercount,
  fc.raw_hot_score,
  fc.urgency_score,
  fc.co_question_count,
  fc.co_score_sum,
  fc.co_view_avg,
  fc.owner_reputation,
  fc.owner_total_answers,
  fc.owner_accept_ratio,
  fc.median_answer_len,
  fc.avg_answer_score,
  fc.badge_score,
  fc.days_since_activity,
  -- window: rank questions globally by urgency within each tag
  rank() over (partition by fc.tag order by fc.urgency_score desc) as urgency_rank_within_tag,
  dense_rank() over (order by fc.urgency_score desc) as global_urgency_rank
from final_candidates fc
where fc.urgency_score is not null
order by fc.tag, fc.urgency_score desc
limit 500;