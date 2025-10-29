-- {"query": "722.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2918}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as website_clean,
    date_trunc('month', u.creationdate) as cohort_month,
    dense_rank() over (order by date_trunc('month', u.creationdate)) as cohort_rank
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    coalesce(sum(p.score) filter (where p.posttypeid in (1,2)), 0) as post_score,
    coalesce(sum(p.viewcount) filter (where p.posttypeid = 1), 0) as question_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
badge_rollup as (
  select
    b.userid,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
vote_summary as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.postid
),
question_metrics as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as question_date,
    q.score as question_score,
    q.viewcount,
    q.answercount,
    q.tags,
    vs.upvotes,
    vs.downvotes,
    vs.favorites,
    vs.bounty_total,
    case
      when q.tags is null then array[]::text[]
      else string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')
    end as tag_array
  from posts q
  left join vote_summary vs on vs.postid = q.id
  where q.posttypeid = 1
),
first_answer_times as (
  select
    q.question_id,
    min(a.creationdate) as first_answer_date,
    count(a.id) as total_answers
  from question_metrics q
  left join posts a
    on a.parentid = q.question_id
    and a.posttypeid = 2
  group by q.question_id
),
accepted_answer_info as (
  select
    q.question_id,
    q.question_date,
    q.asker_id,
    q.answercount,
    q.viewcount,
    q.question_score,
    q.upvotes,
    q.downvotes,
    q.favorites,
    q.bounty_total,
    fa.first_answer_date,
    p2.id as accepted_answer_id,
    p2.owneruserid as accepted_answerer_id,
    p2.score as accepted_answer_score,
    p2.creationdate as accepted_answer_date,
    extract(epoch from (p2.creationdate - q.question_date)) / 3600.0 as hours_to_accept,
    extract(epoch from (fa.first_answer_date - q.question_date)) / 3600.0 as hours_to_first_answer,
    q.tag_array
  from question_metrics q
  left join first_answer_times fa on fa.question_id = q.question_id
  left join posts p2 on p2.id = (select pq.acceptedanswerid from posts pq where pq.id = q.question_id)
),
tag_popularity as (
  select
    tag_name,
    count(*) as tag_q_count,
    avg(t.viewcount) as avg_views,
    avg(coalesce(t.question_score,0)) as avg_q_score
  from (
    select q.*, unnest(q.tag_array) as tag_name
    from question_metrics q
  ) t
  group by tag_name
),
duplicates as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as canonical_id,
    min(pl.creationdate) as first_dup_date,
    count(*) as dup_links
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
edit_bursts as (
  select
    ph.postid,
    ph.userid,
    date_trunc('day', ph.creationdate) as edit_day,
    count(*) as edits_in_day,
    row_number() over (partition by ph.postid order by date_trunc('day', ph.creationdate)) as day_seq
  from posthistory ph
  where ph.posthistorytypeid in (4,5,6,7,8,9,24)
  group by ph.postid, ph.userid, date_trunc('day', ph.creationdate)
),
user_quality as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.post_score,0) as post_score,
    coalesce(ua.question_views,0) as question_views,
    coalesce(br.badge_count,0) as badge_count,
    coalesce(br.gold_count,0) as gold_count,
    coalesce(br.silver_count,0) as silver_count,
    coalesce(br.bronze_count,0) as bronze_count,
    greatest(ru.reputation, 1) as rep_nonzero
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join badge_rollup br on br.userid = ru.user_id
),
comment_toxicity as (
  select
    c.postid,
    avg(case when c.score < 0 then 1.0 else 0.0 end) as neg_ratio,
    sum(case when position('http' in lower(c.text)) > 0 then 1 else 0 end) as link_comments,
    count(*) as total_comments
  from comments c
  group by c.postid
),
question_enrichment as (
  select
    aa.question_id,
    aa.asker_id,
    aa.question_date,
    aa.answercount,
    aa.viewcount,
    aa.question_score,
    aa.upvotes,
    aa.downvotes,
    aa.favorites,
    aa.bounty_total,
    aa.first_answer_date,
    aa.accepted_answer_id,
    aa.accepted_answerer_id,
    aa.accepted_answer_score,
    aa.accepted_answer_date,
    aa.hours_to_accept,
    aa.hours_to_first_answer,
    array_to_string(aa.tag_array, ',') as tags_csv,
    tp.tag_q_count as primary_tag_qcount,
    tp.avg_views as primary_tag_avg_views,
    tp.avg_q_score as primary_tag_avg_qscore,
    ds.dup_links,
    ct.neg_ratio,
    ct.link_comments,
    ct.total_comments
  from accepted_answer_info aa
  left join lateral (
    select tpn.tag_q_count, tpn.avg_views, tpn.avg_q_score
    from tag_popularity tpn
    where tpn.tag_name = coalesce(aa.tag_array[1], '')
  ) tp on true
  left join duplicates ds on ds.dup_post_id = aa.question_id
  left join comment_toxicity ct on ct.postid = aa.question_id
),
rankings as (
  select
    qe.question_id,
    qe.asker_id,
    qe.question_date,
    qe.answercount,
    qe.viewcount,
    qe.question_score,
    qe.upvotes,
    qe.downvotes,
    qe.favorites,
    qe.bounty_total,
    qe.first_answer_date,
    qe.accepted_answer_id,
    qe.accepted_answerer_id,
    qe.accepted_answer_score,
    qe.accepted_answer_date,
    qe.hours_to_accept,
    qe.hours_to_first_answer,
    qe.tags_csv,
    qe.primary_tag_qcount,
    qe.primary_tag_avg_views,
    qe.primary_tag_avg_qscore,
    qe.dup_links,
    qe.neg_ratio,
    qe.link_comments,
    qe.total_comments,
    row_number() over (order by coalesce(qe.viewcount,0) desc, coalesce(qe.question_score,0) desc) as rn_views,
    dense_rank() over (order by coalesce(qe.answercount,0) desc) as dr_answers,
    percent_rank() over (order by coalesce(qe.hours_to_first_answer, 1e9)) as pr_first_answer_speed,
    ntile(10) over (order by coalesce(qe.favorites,0) desc) as decile_favorites
  from question_enrichment qe
  group by
    qe.question_id,
    qe.asker_id,
    qe.question_date,
    qe.answercount,
    qe.viewcount,
    qe.question_score,
    qe.upvotes,
    qe.downvotes,
    qe.favorites,
    qe.bounty_total,
    qe.first_answer_date,
    qe.accepted_answer_id,
    qe.accepted_answerer_id,
    qe.accepted_answer_score,
    qe.accepted_answer_date,
    qe.hours_to_accept,
    qe.hours_to_first_answer,
    qe.tags_csv,
    qe.primary_tag_qcount,
    qe.primary_tag_avg_views,
    qe.primary_tag_avg_qscore,
    qe.dup_links,
    qe.neg_ratio,
    qe.link_comments,
    qe.total_comments
),
user_peer as (
  select
    uq.user_id,
    uq.displayname,
    uq.reputation,
    uq.q_count,
    uq.a_count,
    uq.post_score,
    uq.badge_count,
    uq.gold_count,
    uq.silver_count,
    uq.bronze_count,
    (cast(uq.post_score as numeric) / uq.rep_nonzero) as score_per_rep,
    case
      when uq.a_count + uq.q_count = 0 then null
      else (cast(uq.post_score as numeric) / nullif(uq.a_count + uq.q_count,0))
    end as avg_score_per_post
  from user_quality uq
),
final_agg as (
  select
    r.question_id,
    r.asker_id,
    uask.displayname as asker_name,
    uask.reputation as asker_rep,
    coalesce(up.score_per_rep, 0) as asker_score_per_rep,
    coalesce(up.avg_score_per_post, 0) as asker_avg_score_per_post,
    r.accepted_answer_id,
    r.accepted_answerer_id,
    uans.displayname as answerer_name,
    uans.reputation as answerer_rep,
    r.question_date,
    r.accepted_answer_date,
    r.hours_to_accept,
    r.hours_to_first_answer,
    r.answercount,
    r.viewcount,
    r.question_score,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.bounty_total,
    r.tags_csv,
    r.primary_tag_qcount,
    r.primary_tag_avg_views,
    r.primary_tag_avg_qscore,
    r.dup_links,
    r.neg_ratio,
    r.link_comments,
    r.total_comments,
    r.rn_views,
    r.dr_answers,
    r.pr_first_answer_speed,
    r.decile_favorites,
    case
      when r.downvotes is null or r.upvotes is null or (r.upvotes + r.downvotes) = 0 then null
      else (cast(r.upvotes as numeric) / nullif(r.upvotes + r.downvotes, 0))
    end as upvote_ratio,
    case
      when r.viewcount is null or r.viewcount = 0 then null
      else (cast(r.favorites as numeric) / nullif(r.viewcount,0))
    end as favorite_rate,
    case
      when r.neg_ratio is null then 0
      when r.neg_ratio > 0.4 and r.total_comments >= 5 then 1
      else 0
    end as toxic_comment_flag,
    coalesce(r.dup_links, 0) > 0 as is_marked_duplicate
  from rankings r
  left join users uask on uask.id = r.asker_id
  left join users uans on uans.id = r.accepted_answerer_id
  left join user_peer up on up.user_id = r.asker_id
)
select
  fa.question_id,
  fa.asker_id,
  fa.asker_name,
  fa.asker_rep,
  fa.asker_score_per_rep,
  fa.asker_avg_score_per_post,
  fa.accepted_answer_id,
  fa.accepted_answerer_id,
  fa.answerer_name,
  fa.answerer_rep,
  fa.question_date,
  fa.accepted_answer_date,
  round(coalesce(fa.hours_to_accept, 0), 2) as hours_to_accept,
  round(coalesce(fa.hours_to_first_answer, 0), 2) as hours_to_first_answer,
  fa.answercount,
  fa.viewcount,
  fa.question_score,
  fa.upvotes,
  fa.downvotes,
  fa.favorites,
  fa.bounty_total,
  fa.tags_csv,
  fa.primary_tag_qcount,
  fa.primary_tag_avg_views,
  fa.primary_tag_avg_qscore,
  fa.is_marked_duplicate,
  fa.toxic_comment_flag,
  fa.rn_views,
  fa.dr_answers,
  fa.pr_first_answer_speed,
  fa.decile_favorites,
  fa.upvote_ratio,
  fa.favorite_rate
from final_agg fa
where
  coalesce(fa.bounty_total,0) >= (
    select percentile_disc(0.9) within group (order by coalesce(bounty_total,0))
    from rankings
  )
  or (
    fa.pr_first_answer_speed <= 0.1
    and coalesce(fa.viewcount,0) > (
      select avg(viewcount) + stddev_pop(viewcount)
      from rankings
      where viewcount is not null
    )
  )
  or (
    fa.toxic_comment_flag = 1
    and fa.upvote_ratio is not null
    and fa.upvote_ratio < 0.5
  )
order by
  fa.bounty_total desc nulls last,
  fa.rn_views asc,
  fa.hours_to_accept asc nulls last
limit 250;