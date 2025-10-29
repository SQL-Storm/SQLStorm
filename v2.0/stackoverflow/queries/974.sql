-- {"query": "974.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3770}
with
recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region_hint,
    greatest(1, date_part('day', cast('2024-10-01 12:34:56' as timestamp) - u.creationdate)) as days_on_site,
    case when u.websiteurl ~* 'github|gitlab|bitbucket' then 1 else 0 end as has_dev_site
  from users u
  where u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
badge_rollup as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_cnt,
    sum(case when b.class = 2 then 1 else 0 end) as silver_cnt,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_cnt,
    -- tagbased is boolean in some schemas; normalize to integer via CASE
    sum(case when (case when b.tagbased then 1 else 0 end) = 1 then 1 else 0 end) as tag_badge_cnt,
    min(b.date) as first_badge_at,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
recent_questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2,0)), '><') as tag_arr,
    p.closeddate
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
),
question_enrichment as (
  select
    q.*,
    coalesce((cast(q.viewcount as numeric) / nullif(extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.creationdate))/3600,0)), 0) as views_per_hour,
    coalesce((cast(q.score as numeric) / nullif(q.viewcount,0)), 0) as score_view_ratio,
    case when q.closeddate is null then 0 else 1 end as is_closed,
    cardinality(q.tag_arr) as tag_count
  from recent_questions q
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_cnt,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
    sum(case when c.score < 0 then 1 else 0 end) as neg_comments,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
  group by c.postid
),
vote_timeline as (
  select
    v.postid,
    v.votetypeid,
    v.userid,
    v.creationdate,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end)
      over (partition by v.postid order by v.creationdate rows between unbounded preceding and current row) as running_score_delta
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
),
link_graph as (
  select
    l.postid,
    sum(case when l.linktypeid = 3 then 1 else 0 end) as dup_links,
    sum(case when l.linktypeid = 1 then 1 else 0 end) as ref_links,
    count(*) as all_links
  from postlinks l
  group by l.postid
),
closing_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_at,
    max(ph.creationdate) as last_close_at,
    max(case when ph.comment ~ '^[0-9]+' then cast(ph.comment as integer) else null end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
accepted_answers as (
  select
    q.id as question_id,
    a.id as accepted_answer_id,
    a.owneruserid as answerer_id,
    a.score as accepted_score,
    a.creationdate as accepted_at
  from posts q
  join posts a on a.id = q.acceptedanswerid
),
tag_rank as (
  select
    t.tagname,
    t.count as tag_total_count,
    percent_rank() over (order by t.count) as tag_pop_percentile
  from tags t
),
question_tag_pop as (
  select
    qe.id as post_id,
    lower(trim(tg)) as tagname
  from question_enrichment qe
  cross join unnest(qe.tag_arr) as tg
),
question_tag_stats as (
  select
    qtp.post_id,
    avg(tr.tag_pop_percentile) as avg_tag_popularity,
    max(tr.tag_pop_percentile) as max_tag_popularity,
    min(tr.tag_pop_percentile) as min_tag_popularity
  from question_tag_pop qtp
  left join tag_rank tr on tr.tagname = qtp.tagname
  group by qtp.post_id
),
user_activity as (
  select
    ru.user_id,
    count(qe.id) filter (where qe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as q_30d,
    count(qe.id) filter (where qe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as q_90d,
    count(qe.id) as q_2y
  from recent_users ru
  left join question_enrichment qe on qe.owneruserid = ru.user_id
  group by ru.user_id
),
difficulty_proxy as (
  select
    qe.id as post_id,
    (
      select coalesce(avg(a.score), 0)
      from posts a
      where a.parentid = qe.id
        and a.posttypeid = 2
    ) as avg_answer_score,
    (
      select count(*)
      from posts a
      where a.parentid = qe.id
        and a.posttypeid = 2
        and a.score >= 1
    ) as helpful_answers,
    (
      select min(a.creationdate)
      from posts a
      where a.parentid = qe.id
        and a.posttypeid = 2
    ) as first_answer_at
  from question_enrichment qe
),
answer_latency as (
  select
    d.post_id,
    extract(epoch from (d.first_answer_at - q.creationdate))/3600.0 as hours_to_first_answer
  from difficulty_proxy d
  join question_enrichment q on q.id = d.post_id
),
user_bands as (
  select
    ru.user_id,
    case
      when ru.reputation >= 100000 then 'legend'
      when ru.reputation >= 25000 then 'elite'
      when ru.reputation >= 5000 then 'pro'
      when ru.reputation >= 1000 then 'regular'
      when ru.reputation >= 100 then 'novice'
      else 'newbie'
    end as rep_band
  from recent_users ru
),
askers as (
  select distinct owneruserid as user_id
  from recent_questions
  where owneruserid is not null
),
answerers as (
  select distinct owneruserid as user_id
  from posts
  where posttypeid = 2
    and creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '730 days'
    and owneruserid is not null
),
cross_roles as (
  (select user_id, 'asker_only' as role from askers except select user_id, 'asker_only' from answerers)
  union all
  (select user_id, 'answerer_only' as role from answerers except select user_id, 'answerer_only' from askers)
  union all
  (select a.user_id, 'both' as role from askers a inner join answerers b using (user_id))
),
question_features as (
  select
    qe.id as post_id,
    qe.owneruserid as user_id,
    qe.creationdate,
    qe.lastactivitydate,
    qe.score,
    qe.viewcount,
    qe.answercount,
    qe.favoritecount,
    qe.commentcount,
    qe.views_per_hour,
    qe.score_view_ratio,
    qe.is_closed,
    qe.tag_count,
    cs.comment_cnt,
    cs.pos_comments,
    cs.neg_comments,
    lt.all_links,
    lt.dup_links,
    lt.ref_links,
    coalesce(qts.avg_tag_popularity, 0) as avg_tag_popularity,
    coalesce(qts.max_tag_popularity, 0) as max_tag_popularity,
    coalesce(qts.min_tag_popularity, 0) as min_tag_popularity,
    dp.avg_answer_score,
    dp.helpful_answers,
    al.hours_to_first_answer,
    ce.first_close_at,
    ce.last_close_at,
    ce.last_close_reason_id,
    aa.accepted_answer_id,
    aa.accepted_score
  from question_enrichment qe
  left join comment_stats cs on cs.postid = qe.id
  left join link_graph lt on lt.postid = qe.id
  left join question_tag_stats qts on qts.post_id = qe.id
  left join difficulty_proxy dp on dp.post_id = qe.id
  left join answer_latency al on al.post_id = qe.id
  left join closing_events ce on ce.postid = qe.id
  left join accepted_answers aa on aa.question_id = qe.id
),
user_agg as (
  select
    qf.user_id,
    count(*) as questions_count,
    avg(qf.views_per_hour) as avg_views_per_hour,
    avg(nullif(qf.score,0)) as avg_score_nonzero,
    sum(case when qf.is_closed = 1 then 1 else 0 end) as closes,
    avg(coalesce(qf.hours_to_first_answer, 24*14)) as avg_hours_to_first_answer_capped,
    percentile_cont(0.5) within group (order by coalesce(qf.hours_to_first_answer, 24*14)) as p50_answer_latency,
    max(qf.viewcount) as max_views,
    sum(coalesce(qf.helpful_answers,0)) as helpful_answers_total
  from question_features qf
  group by qf.user_id
),
user_norm as (
  select
    ua.user_id,
    ua.questions_count,
    ua.avg_views_per_hour,
    ua.avg_score_nonzero,
    ua.closes,
    ua.avg_hours_to_first_answer_capped,
    ua.p50_answer_latency,
    ua.max_views,
    ua.helpful_answers_total,
    rank() over (order by ua.questions_count desc) as r_qs,
    ntile(10) over (order by ua.avg_views_per_hour desc nulls last) as ntile_views_per_hour
  from user_agg ua
),
final_assembly as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ub.rep_band,
    ru.days_on_site,
    ru.has_dev_site,
    coalesce(b.gold_cnt,0) as gold_cnt,
    coalesce(b.silver_cnt,0) as silver_cnt,
    coalesce(b.bronze_cnt,0) as bronze_cnt,
    coalesce(b.tag_badge_cnt,0) as tag_badge_cnt,
    b.first_badge_at,
    b.last_badge_at,
    ua.q_30d,
    ua.q_90d,
    ua.q_2y,
    un.questions_count,
    un.avg_views_per_hour,
    un.avg_score_nonzero,
    un.closes,
    un.avg_hours_to_first_answer_capped,
    un.p50_answer_latency,
    un.max_views,
    un.helpful_answers_total,
    un.r_qs,
    un.ntile_views_per_hour,
    cr.role as cross_role,
    (
      select u2.displayname
      from accepted_answers aa2
      join users u2 on u2.id = aa2.answerer_id
      where aa2.question_id in (
        select qf.post_id from question_features qf where qf.user_id = ru.user_id and qf.accepted_answer_id is not null
      )
      order by aa2.accepted_score desc nulls last, aa2.accepted_at desc
      limit 1
    ) as top_answerer_peer
  from recent_users ru
  left join badge_rollup b on b.userid = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_norm un on un.user_id = ru.user_id
  left join user_bands ub on ub.user_id = ru.user_id
  left join cross_roles cr on cr.user_id = ru.user_id
),
scored as (
  select
    qf.*,
    case when max(reputation) over () = min(reputation) over () then 0
         else (qf.reputation - min(reputation) over ()) * 1.0 / nullif(max(reputation) over () - min(reputation) over (),0) end as rep_norm,
    case when max(questions_count) over () = min(questions_count) over () then 0
         else (coalesce(qf.questions_count,0) - min(coalesce(questions_count,0)) over ()) * 1.0
              / nullif(max(coalesce(questions_count,0)) over () - min(coalesce(questions_count,0)) over (),0) end as q_norm,
    case when max(avg_views_per_hour) over () = min(avg_views_per_hour) over () then 0
         else (coalesce(qf.avg_views_per_hour,0) - min(coalesce(avg_views_per_hour,0)) over ()) * 1.0
              / nullif(max(coalesce(avg_views_per_hour,0)) over () - min(coalesce(avg_views_per_hour,0)) over (),0) end as vph_norm,
    case when max(avg_hours_to_first_answer_capped) over () = min(avg_hours_to_first_answer_capped) over () then 0
         else 1 - (coalesce(qf.avg_hours_to_first_answer_capped,0) - min(coalesce(avg_hours_to_first_answer_capped,0)) over ()) * 1.0
              / nullif(max(coalesce(avg_hours_to_first_answer_capped,0)) over () - min(coalesce(avg_hours_to_first_answer_capped,0)) over (),0) end as latency_norm
  from final_assembly qf
),
ranked as (
  select
    s.*,
    coalesce(0.4*coalesce(rep_norm,0) + 0.3*coalesce(q_norm,0) + 0.2*coalesce(vph_norm,0) + 0.1*coalesce(latency_norm,0), 0) as rarity_score,
    row_number() over (order by coalesce(0.4*coalesce(rep_norm,0) + 0.3*coalesce(q_norm,0) + 0.2*coalesce(vph_norm,0) + 0.1*coalesce(latency_norm,0),0) desc,
                               coalesce(questions_count,0) desc,
                               reputation desc) as rn
  from scored s
)
select
  r.user_id,
  coalesce(r.displayname, concat('user-', cast(r.user_id as text))) as displayname,
  r.rep_band,
  r.reputation,
  r.days_on_site,
  r.has_dev_site,
  r.gold_cnt,
  r.silver_cnt,
  r.bronze_cnt,
  r.tag_badge_cnt,
  r.q_30d,
  r.q_90d,
  r.q_2y,
  r.questions_count,
  round(cast(r.avg_views_per_hour as numeric), 3) as avg_views_per_hour,
  round(cast(r.avg_score_nonzero as numeric), 3) as avg_score_nonzero,
  r.closes,
  round(cast(r.avg_hours_to_first_answer_capped as numeric), 2) as avg_hours_to_first_answer_hours,
  round(cast(r.p50_answer_latency as numeric), 2) as p50_answer_latency_hours,
  r.max_views,
  r.helpful_answers_total,
  r.rarity_score,
  r.cross_role,
  r.top_answerer_peer
from ranked r
where (r.cross_role is distinct from 'answerer_only' or r.reputation >= 10000)
  and (r.q_2y is not null and r.q_2y >= 1)
  and (r.rarity_score is not null or r.reputation > 0)
order by r.rn
limit 200;