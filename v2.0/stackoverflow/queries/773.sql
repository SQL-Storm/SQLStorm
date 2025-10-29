-- {"query": "773.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3147}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    dense_rank() over (order by date_trunc('month', u.creationdate)) as cohort_rank
  from users u
  where u.creationdate >= (select max(creationdate) - interval '5 years' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as questions,
    count(*) filter (where p.posttypeid = 2) as answers,
    sum(coalesce(p.score, 0)) as post_score,
    sum(coalesce(p.viewcount, 0)) filter (where p.posttypeid = 1) as question_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_stats as (
  select
    c.userid as user_id,
    count(*) as comments,
    sum(coalesce(c.score, 0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
badge_pivot as (
  select
    b.userid as user_id,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
vote_pivot as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total,
    max(v.creationdate) as last_vote_date
  from votes v
  where v.userid is not null
  group by v.userid
),
qa_pairs as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as question_date,
    q.acceptedanswerid,
    q.tags,
    q.score as q_score,
    q.viewcount as q_views,
    a.id as answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as answer_date,
    a.score as a_score,
    case when a.id = q.acceptedanswerid then 1 else 0 end as is_accepted
  from posts q
  left join posts a
    on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
first_answers as (
  select
    answerer_id as user_id,
    min(answer_date) as first_answer_date
  from qa_pairs
  where answerer_id is not null
  group by answerer_id
),
tag_exploded as (
  select
    qp.question_id,
    unnest(string_to_array(substring(qp.tags, 2, greatest(length(qp.tags)-2,0)), '><')) as tagname
  from qa_pairs qp
  where qp.tags is not null and qp.tags like '<%>'
),
user_tag_stats as (
  select
    qp.answerer_id as user_id,
    te.tagname,
    count(*) as answers_in_tag,
    avg(qp.a_score) as avg_answer_score_in_tag,
    sum(qp.is_accepted) as accepted_in_tag
  from qa_pairs qp
  join tag_exploded te on te.question_id = qp.question_id
  where qp.answerer_id is not null
  group by qp.answerer_id, te.tagname
),
top_tag_per_user as (
  select distinct on (uts.user_id)
    uts.user_id,
    uts.tagname,
    uts.answers_in_tag,
    uts.avg_answer_score_in_tag,
    uts.accepted_in_tag
  from user_tag_stats uts
  order by uts.user_id, uts.answers_in_tag desc, uts.avg_answer_score_in_tag desc, uts.tagname
),
duplicates_and_links as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as related_links,
    max(pl.creationdate) as last_link_date
  from postlinks pl
  group by pl.postid
),
close_events as (
  select
    ph.postid,
    count(*) as close_events,
    max(ph.creationdate) as last_close_date,
    sum(case when ph.comment ~ '^[0-9]+' then 1 else 0 end) as close_with_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
question_health as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    coalesce(da.duplicate_links,0) as duplicate_links,
    coalesce(da.related_links,0) as related_links,
    coalesce(ce.close_events,0) as close_events,
    q.score,
    q.viewcount,
    q.answercount,
    q.creationdate,
    greatest(coalesce(da.last_link_date, q.creationdate), coalesce(ce.last_close_date, q.creationdate), coalesce(q.lastactivitydate, q.creationdate)) as last_event_date
  from posts q
  left join duplicates_and_links da on da.postid = q.id
  left join close_events ce on ce.postid = q.id
  where q.posttypeid = 1
),
user_question_health as (
  select
    qh.user_id,
    count(*) as total_questions,
    sum(case when qh.duplicate_links > 0 then 1 else 0 end) as questions_flagged_duplicate,
    avg(coalesce(qh.score,0)) as avg_q_score,
    avg(coalesce(qh.viewcount,0)) as avg_q_views,
    avg(coalesce(qh.answercount,0)) as avg_q_answers,
    max(qh.last_event_date) as last_q_event
  from question_health qh
  where qh.user_id is not null
  group by qh.user_id
),
user_accept_stats as (
  select
    qp.answerer_id as user_id,
    count(*) as answers_total,
    sum(qp.is_accepted) as answers_accepted,
    100.0 * sum(qp.is_accepted) / nullif(count(*),0) as accept_rate_pct,
    percentile_cont(0.5) within group (order by qp.a_score) as median_answer_score
  from qa_pairs qp
  where qp.answerer_id is not null
  group by qp.answerer_id
),
ranked_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.cohort_rank,
    ua.questions,
    ua.answers,
    ua.post_score,
    cs.comments,
    cs.comment_score,
    bp.gold_badges,
    bp.silver_badges,
    bp.bronze_badges,
    vp.upvotes_cast,
    vp.downvotes_cast,
    vp.favorites_cast,
    coalesce(vp.bounty_amount_total,0) as bounty_amount_total,
    coalesce(uqs.total_questions,0) as total_questions,
    coalesce(uqs.questions_flagged_duplicate,0) as questions_flagged_duplicate,
    coalesce(uqs.avg_q_score,0) as avg_q_score,
    coalesce(uqs.avg_q_views,0) as avg_q_views,
    coalesce(uqs.avg_q_answers,0) as avg_q_answers,
    coalesce(uas.answers_total,0) as answers_total,
    coalesce(uas.answers_accepted,0) as answers_accepted,
    coalesce(uas.accept_rate_pct,0) as accept_rate_pct,
    coalesce(uas.median_answer_score,0) as median_answer_score,
    tt.tagname as top_tag,
    coalesce(tt.answers_in_tag,0) as top_tag_answers,
    coalesce(tt.avg_answer_score_in_tag,0) as top_tag_avg_answer_score,
    coalesce(tt.accepted_in_tag,0) as top_tag_accepts,
    fa.first_answer_date,
    greatest(coalesce(ua.last_post_activity, ru.creationdate), coalesce(cs.last_comment_date, ru.creationdate), coalesce(vp.last_vote_date, ru.creationdate), coalesce(bp.last_badge_date, ru.creationdate)) as last_user_activity
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join badge_pivot bp on bp.user_id = ru.user_id
  left join vote_pivot vp on vp.user_id = ru.user_id
  left join user_question_health uqs on uqs.user_id = ru.user_id
  left join user_accept_stats uas on uas.user_id = ru.user_id
  left join top_tag_per_user tt on tt.user_id = ru.user_id
  left join first_answers fa on fa.user_id = ru.user_id
),
score_components as (
  select
    ru.*,
    ln(1 + coalesce(answers,0)) as comp_answers,
    ln(1 + coalesce(questions,0)) as comp_questions,
    ln(1 + greatest(coalesce(post_score,0),0)) as comp_post_score,
    ln(1 + greatest(coalesce(comment_score,0),0)) as comp_comment_score,
    ln(1 + coalesce(gold_badges,0)*9 + coalesce(silver_badges,0)*3 + coalesce(bronze_badges,0)) as comp_badges,
    ln(1 + greatest(coalesce(avg_q_views,0),0)) as comp_avg_q_views,
    ln(1 + greatest(coalesce(median_answer_score,0),0)) as comp_median_a,
    ln(1 + greatest(coalesce(accept_rate_pct,0),0)) as comp_accept_rate,
    ln(1 + greatest(coalesce(top_tag_answers,0),0)) as comp_top_tag_answers,
    ln(1 + greatest(coalesce(bounty_amount_total,0),0)) as comp_bounty
  from ranked_users ru
),
scored as (
  select
    sc.*,
    1.5*comp_answers
    + 1.0*comp_questions
    + 1.8*comp_post_score
    + 0.8*comp_comment_score
    + 1.2*comp_badges
    + 0.7*comp_avg_q_views
    + 0.9*comp_median_a
    + 1.3*comp_accept_rate
    + 0.6*comp_top_tag_answers
    + 0.4*comp_bounty
    - 0.5*ln(1 + coalesce(questions_flagged_duplicate,0)) as performance_score
  from score_components sc
),
peer_stats as (
  select
    s.*,
    avg(performance_score) over (partition by cohort_rank) as cohort_avg_score,
    stddev_pop(performance_score) over (partition by cohort_rank) as cohort_stddev,
    rank() over (order by performance_score desc, reputation desc, user_id) as global_rank,
    rank() over (partition by cohort_rank order by performance_score desc) as cohort_rank_score
  from scored s
),
activity_summary as (
  select
    p.owneruserid as user_id,
    min(p.creationdate) as first_post_date,
    max(p.lastactivitydate) as last_post_activity,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
finalized as (
  select
    ps.user_id,
    ps.displayname,
    ps.reputation,
    ps.cohort_month,
    ps.global_rank,
    ps.cohort_rank_score,
    round(cast(ps.performance_score as numeric), 3) as performance_score,
    round(cast(ps.cohort_avg_score as numeric), 3) as cohort_avg_score,
    round(cast(ps.cohort_stddev as numeric), 3) as cohort_stddev,
    ps.answers_total,
    ps.answers_accepted,
    round(cast(ps.accept_rate_pct as numeric), 2) as accept_rate_pct,
    ps.questions as total_questions_posted,
    ps.answers as total_answers_posted,
    ps.comments as total_comments_posted,
    ps.gold_badges,
    ps.silver_badges,
    ps.bronze_badges,
    coalesce(ps.top_tag, 'unclassified') as top_tag,
    ps.top_tag_answers,
    ps.top_tag_avg_answer_score,
    ps.last_user_activity,
    a.first_post_date,
    a.last_post_activity,
    case when ps.last_user_activity >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' then 'Active'
         when ps.last_user_activity >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days' then 'Dormant'
         else 'Inactive' end as activity_bucket
  from peer_stats ps
  left join activity_summary a on a.user_id = ps.user_id
)
select f.*
from finalized f
where
  (coalesce(f.answers_total,0) + coalesce(f.total_answers_posted,0)) > 0
  and (
    f.performance_score > coalesce(f.cohort_avg_score, 0)
    or (f.accept_rate_pct is not null and f.accept_rate_pct >= 50)
  )
  and (
    f.top_tag != 'meta' or f.top_tag is null
  )
  and extract(year from f.cohort_month) >= extract(year from cast('2024-10-01 12:34:56' as timestamp)) - 5
union all
select f.*
from finalized f
where
  f.activity_bucket = 'Active'
  and f.performance_score = (
    select max(ff.performance_score)
    from finalized ff
    where ff.activity_bucket = 'Active'
  )
order by performance_score desc, global_rank, user_id
limit 500;