-- {"query": "237.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2585}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'no-domain') as website_domain,
    row_number() over (partition by lower(coalesce(u.displayname, '')) order by u.reputation desc, u.id) as rn_name_rep
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
active_questions as (
  select
    p.id as question_id,
    p.owneruserid,
    p.creationdate as q_created,
    p.score as q_score,
    p.viewcount as q_views,
    p.title,
    p.tags,
    p.acceptedanswerid,
    date_trunc('month', p.creationdate) as q_month,
    coalesce(p.answercount, 0) as answercount_reported
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answer_owner_id,
    a.creationdate as a_created,
    a.score as a_score
  from posts a
  where a.posttypeid = 2
),
first_answer_per_question as (
  select
    a.question_id,
    min(a.a_created) as first_answer_time,
    count(*) as total_answers
  from answers a
  group by a.question_id
),
accepted_answer_latency as (
  select
    q.question_id,
    q.q_created,
    q.acceptedanswerid,
    a.creationdate as accepted_created,
    extract(epoch from (a.creationdate - q.q_created)) / 3600.0 as accepted_latency_hours
  from active_questions q
  left join posts a on a.id = q.acceptedanswerid
),
question_votes as (
  select
    v.postid as question_id,
    sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as vote_delta,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  inner join posts p on p.id = v.postid and p.posttypeid = 1
  group by v.postid
),
comment_activity as (
  select
    c.postid as post_id,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
duplicates as (
  select
    pl.postid as dup_question_id,
    pl.relatedpostid as original_question_id,
    min(pl.creationdate) as first_dup_link_at
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
tag_expansion as (
  select
    q.question_id,
    unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tagname
  from active_questions q
),
tag_stats as (
  select
    te.question_id,
    count(*) as tag_count,
    string_agg(te.tagname, '|' order by te.tagname) as tags_flat,
    sum(case when t.isrequired then 1 else 0 end) as required_tag_count,
    sum(case when t.ismoderatoronly then 1 else 0 end) as mod_only_tag_count
  from tag_expansion te
  left join tags t on lower(t.tagname) = lower(te.tagname)
  group by te.question_id
),
owner_badges as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
post_history_flags as (
  select
    ph.postid,
    bool_or(ph.posthistorytypeid in (10,35)) as ever_closed_or_migrated,
    max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    max(case when ph.posthistorytypeid in (50,52) then ph.creationdate end) as last_bumped_or_hot_at,
    count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits_applied
  from posthistory ph
  group by ph.postid
),
question_activity_window as (
  select
    q.question_id,
    q.q_created,
    q.q_score,
    q.q_views,
    q.title,
    q.owneruserid,
    q.acceptedanswerid,
    q.answercount_reported,
    fv.vote_delta,
    fv.bounty_started,
    fv.bounty_awarded,
    fa.total_answers,
    fa.first_answer_time,
    aal.accepted_latency_hours,
    cs.comment_count,
    cs.last_comment_at,
    ts.tag_count,
    ts.tags_flat,
    ts.required_tag_count,
    ts.mod_only_tag_count,
    phf.ever_closed_or_migrated,
    phf.last_closed_at,
    phf.last_reopened_at,
    phf.last_bumped_or_hot_at,
    phf.suggested_edits_applied,
    d.original_question_id,
    d.first_dup_link_at,
    coalesce(q.q_score,0) + coalesce(fv.vote_delta,0) as score_with_votes,
    coalesce(fa.total_answers,0) - coalesce(case when q.answercount_reported is null then 0 else q.answercount_reported end, 0) as answer_count_delta
  from active_questions q
  left join question_votes fv on fv.question_id = q.question_id
  left join first_answer_per_question fa on fa.question_id = q.question_id
  left join accepted_answer_latency aal on aal.question_id = q.question_id
  left join comment_activity cs on cs.post_id = q.question_id
  left join tag_stats ts on ts.question_id = q.question_id
  left join post_history_flags phf on phf.postid = q.question_id
  left join duplicates d on d.dup_question_id = q.question_id
),
user_rollup as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.website_domain,
    ob.gold_count,
    ob.silver_count,
    ob.bronze_count,
    ob.last_badge_at,
    count(*) over (partition by ru.website_domain) as peers_same_domain,
    dense_rank() over (order by coalesce(ob.gold_count,0) desc, coalesce(ob.silver_count,0) desc, coalesce(ob.bronze_count,0) desc, ru.reputation desc) as badge_rep_rank
  from recent_users ru
  left join owner_badges ob on ob.userid = ru.user_id
  where ru.rn_name_rep = 1
),
question_quality as (
  select
    qaw.question_id,
    qaw.title,
    qaw.tags_flat,
    qaw.q_views,
    qaw.score_with_votes,
    qaw.total_answers,
    qaw.accepted_latency_hours,
    qaw.suggested_edits_applied,
    qaw.tag_count,
    qaw.required_tag_count,
    qaw.mod_only_tag_count,
    qaw.ever_closed_or_migrated,
    qaw.answer_count_delta,
    case
      when qaw.ever_closed_or_migrated then 0
      else greatest(0,
        (coalesce(qaw.score_with_votes,0) * 2)
        + (least(coalesce(qaw.q_views,0), 10000) / 200)
        + (coalesce(qaw.total_answers,0) * 5)
        - (case when qaw.accepted_latency_hours is null then 10 when qaw.accepted_latency_hours > 168 then 15 else qaw.accepted_latency_hours / 24 end)
        - (coalesce(qaw.mod_only_tag_count,0) * 3)
        + (case when qaw.required_tag_count > 0 then 2 else 0 end)
        + (case when qaw.suggested_edits_applied > 0 then 1 else 0 end)
      )
    end as quality_score
  from question_activity_window qaw
),
domain_health as (
  select
    ur.website_domain,
    count(*) as users_count,
    avg(ur.reputation) as avg_rep,
    sum(coalesce(ur.gold_count,0)) as total_gold,
    sum(coalesce(ur.silver_count,0)) as total_silver,
    sum(coalesce(ur.bronze_count,0)) as total_bronze,
    max(ur.last_badge_at) as last_badge_at
  from user_rollup ur
  group by ur.website_domain
),
question_owner as (
  select
    qaw.question_id,
    qaw.owneruserid,
    ur.displayname as owner_name,
    ur.reputation as owner_rep,
    ur.website_domain as owner_domain,
    ur.badge_rep_rank as owner_rank
  from question_activity_window qaw
  left join user_rollup ur on ur.user_id = qaw.owneruserid
),
final_rank as (
  select
    qq.question_id,
    qq.quality_score,
    qo.owneruserid,
    qo.owner_name,
    qo.owner_rep,
    qo.owner_domain,
    qo.owner_rank,
    dense_rank() over (
      order by
        qq.quality_score desc nulls last,
        coalesce(qo.owner_rep, 0) desc,
        qq.question_id
    ) as q_rank
  from question_quality qq
  left join question_owner qo on qo.question_id = qq.question_id
)
select
  fr.q_rank,
  fr.question_id,
  left(coalesce(qa.title,''), 120) as title_snippet,
  qa.tags_flat,
  qa.q_views,
  qa.score_with_votes,
  qa.total_answers,
  round(cast(qa.accepted_latency_hours as numeric), 2) as accepted_latency_hours,
  qa.suggested_edits_applied,
  qa.ever_closed_or_migrated,
  fr.owneruserid as owner_user_id,
  fr.owner_name,
  fr.owner_rep,
  fr.owner_domain,
  dh.users_count as domain_users,
  dh.avg_rep as domain_avg_rep,
  dh.total_gold,
  dh.total_silver,
  dh.total_bronze,
  qq.quality_score,
  case when qa.answer_count_delta <> 0 then 'MISMATCH' else 'OK' end as answer_count_check,
  qa.last_bumped_or_hot_at,
  qa.last_closed_at,
  qa.last_reopened_at,
  qa.first_dup_link_at,
  qa.original_question_id
from final_rank fr
join question_activity_window qa on qa.question_id = fr.question_id
join question_quality qq on qq.question_id = fr.question_id
left join domain_health dh on dh.website_domain = fr.owner_domain
where
  (qa.q_views is null or qa.q_views >= 100)
  and (
    qa.tags_flat is null
    or qa.tags_flat ilike '%python%'
    or qa.tags_flat ilike '%java%'
    or qa.tags_flat ilike '%sql%'
    or qa.tags_flat ilike '%c%'
  )
  and (
    qa.ever_closed_or_migrated is distinct from true
    or qa.suggested_edits_applied > 0
  )
  and coalesce(fr.owner_rep, 0) >= 0
order by fr.q_rank
limit 250;