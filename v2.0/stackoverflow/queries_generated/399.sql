-- {"query": "399.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3177} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= now() - interval '5 years'
),
user_badge_agg as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as gold_cnt,
    count(*) filter (where b.class = 2) as silver_cnt,
    count(*) filter (where b.class = 3) as bronze_cnt,
    count(*) as total_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
questions as (
  select
    p.id,
    p.owneruserid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.commentcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate,
    p.contentlicense
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    a.id,
    a.parentid as question_id,
    a.owneruserid,
    a.creationdate,
    a.score,
    a.commentcount
  from posts a
  where a.posttypeid = 2
),
q_activity as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as q_created,
    q.score as q_score,
    q.viewcount as q_views,
    q.answercount as q_answercount,
    q.favoritecount as q_fav,
    q.commentcount as q_comments,
    q.acceptedanswerid,
    q.closeddate,
    regexp_split_to_table(coalesce(nullif(q.tags, ''), '<untagged>'), '><') as raw_tag
  from questions q
),
q_tags as (
  select
    question_id,
    lower(replace(replace(replace(raw_tag, '<', ''), '>', ''), ' ', '')) as tag_clean
  from q_activity
),
tag_meta as (
  select
    t.tagname,
    t.count as tag_total_count,
    coalesce(t.ismoderatoronly::int, 0) as is_mod_only,
    coalesce(t.isrequired::int, 0) as is_required
  from tags t
),
q_tag_enriched as (
  select
    qt.question_id,
    qt.tag_clean,
    tm.tag_total_count,
    tm.is_mod_only,
    tm.is_required
  from q_tags qt
  left join tag_meta tm
    on tm.tagname = qt.tag_clean
),
q_tag_rollup as (
  select
    question_id,
    count(*) as tag_count,
    sum(case when is_mod_only = 1 then 1 else 0 end) as mod_only_tags,
    sum(case when is_required = 1 then 1 else 0 end) as required_tags,
    min(tag_total_count) as min_tag_popularity,
    max(tag_total_count) as max_tag_popularity
  from q_tag_enriched
  group by question_id
),
first_answer as (
  select
    a.question_id,
    a.id as answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as answer_created,
    a.score as answer_score,
    row_number() over (partition by a.question_id order by a.creationdate asc, a.id asc) as rn
  from answers a
),
accepted_answer as (
  select
    q.id as question_id,
    q.acceptedanswerid as answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as accepted_created,
    a.score as accepted_score
  from questions q
  left join posts a
    on a.id = q.acceptedanswerid
),
votes_rollup as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    count(*) filter (where v.votetypeid = 12) as spamvotes,
    count(*) filter (where v.votetypeid = 10) as deletionvotes,
    max(v.creationdate) as last_vote_at
  from votes v
  group by v.postid
),
comments_rollup as (
  select
    c.postid,
    count(*) as comments_count,
    max(c.score) as max_comment_score,
    min(c.creationdate) as first_comment_at,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_closed_at,
    max(ph.creationdate) as last_closed_at,
    count(*) as close_events,
    count(*) filter (where ph.comment in ('101','102','103','104','105')) as close_events_current_reasons
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
reopen_events as (
  select
    ph.postid,
    count(*) as reopen_events,
    min(ph.creationdate) as first_reopen_at,
    max(ph.creationdate) as last_reopen_at
  from posthistory ph
  where ph.posthistorytypeid = 11
  group by ph.postid
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as canonical_post_id,
    min(pl.creationdate) as first_dup_link_at,
    count(*) as dup_link_count
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
q_core as (
  select
    qa.question_id,
    qa.asker_id,
    qa.q_created,
    qa.q_score,
    qa.q_views,
    qa.q_answercount,
    qa.q_fav,
    qa.q_comments,
    qa.acceptedanswerid,
    qa.closeddate,
    qtr.tag_count,
    qtr.mod_only_tags,
    qtr.required_tags,
    qtr.min_tag_popularity,
    qtr.max_tag_popularity
  from q_activity qa
  left join q_tag_rollup qtr
    on qtr.question_id = qa.question_id
),
q_with_answers as (
  select
    qc.*,
    fa.answer_id as first_answer_id,
    fa.answerer_id as first_answerer_id,
    fa.answer_created as first_answer_created,
    fa.answer_score as first_answer_score,
    aa.answer_id as accepted_answer_id,
    aa.answerer_id as accepted_answerer_id,
    aa.accepted_created,
    aa.accepted_score
  from q_core qc
  left join lateral (
    select answer_id, answerer_id, answer_created, answer_score
    from first_answer
    where first_answer.question_id = qc.question_id and rn = 1
  ) fa on true
  left join accepted_answer aa
    on aa.question_id = qc.question_id
),
user_quality as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    uba.gold_cnt,
    uba.silver_cnt,
    uba.bronze_cnt,
    uba.total_badges,
    uba.first_badge_date,
    uba.last_badge_date,
    case
      when uba.total_badges is null or uba.total_badges = 0 then 0.0
      else round((coalesce(uba.gold_cnt,0) * 3 + coalesce(uba.silver_cnt,0) * 2 + coalesce(uba.bronze_cnt,0) * 1)::numeric / uba.total_badges, 3)
    end as badge_weighted_score
  from recent_users ru
  left join user_badge_agg uba
    on uba.userid = ru.user_id
),
answerer_metrics as (
  select
    a.owneruserid as answerer_id,
    count(*) as answers_given,
    count(*) filter (where a.score > 0) as pos_answer_cnt,
    avg(a.score)::numeric(12,4) as avg_answer_score,
    percentile_cont(0.5) within group (order by a.score) as median_answer_score
  from answers a
  group by a.owneruserid
),
question_metrics as (
  select
    p.owneruserid as asker_id,
    count(*) filter (where p.posttypeid = 1) as questions_asked,
    avg(p.score)::numeric(12,4) filter (where p.posttypeid = 1) as avg_q_score,
    avg(nullif(p.viewcount,0))::numeric(12,4) filter (where p.posttypeid = 1) as avg_q_views
  from posts p
  group by p.owneruserid
),
q_metrics_enriched as (
  select
    qwa.*,
    vr.upvotes as q_upvotes,
    vr.downvotes as q_downvotes,
    vr.spamvotes as q_spamvotes,
    vr.last_vote_at as q_last_vote_at,
    cr.comments_count as q_comments_count,
    cr.max_comment_score as q_max_comment_score,
    cr.first_comment_at as q_first_comment_at,
    cr.last_comment_at as q_last_comment_at,
    ce.first_closed_at,
    ce.last_closed_at,
    ce.close_events,
    ce.close_events_current_reasons,
    re.reopen_events,
    re.first_reopen_at,
    re.last_reopen_at,
    dl.canonical_post_id,
    dl.first_dup_link_at,
    dl.dup_link_count
  from q_with_answers qwa
  left join votes_rollup vr on vr.postid = qwa.question_id
  left join comments_rollup cr on cr.postid = qwa.question_id
  left join close_events ce on ce.postid = qwa.question_id
  left join reopen_events re on re.postid = qwa.question_id
  left join dup_links dl on dl.dup_post_id = qwa.question_id
),
latencies as (
  select
    qme.*,
    extract(epoch from (qme.first_answer_created - qme.q_created)) as secs_to_first_answer,
    extract(epoch from (qme.accepted_created - qme.q_created)) as secs_to_accept,
    extract(epoch from (coalesce(qme.first_closed_at, qme.last_reopen_at) - qme.q_created)) as secs_to_close_or_reopen
  from q_metrics_enriched qme
),
final_scored as (
  select
    l.*,
    uq_asker.badge_weighted_score as asker_badge_score,
    uq_answerer.badge_weighted_score as first_answerer_badge_score,
    am.answers_given as first_answerer_answers_given,
    am.avg_answer_score as first_answerer_avg_score,
    qm.questions_asked as asker_questions_asked,
    qm.avg_q_score as asker_avg_q_score,
    case
      when l.q_views is null or l.q_views = 0 then null
      else round((l.q_upvotes - coalesce(l.q_downvotes,0))::numeric / nullif(l.q_views,0), 6)
    end as net_vote_per_view,
    case
      when l.q_answercount is null or l.q_answercount = 0 then 0
      else round(coalesce(l.q_comments_count,0)::numeric / nullif(l.q_answercount,0), 6)
    end as comments_per_answer,
    case
      when l.tag_count is null or l.tag_count = 0 then 'untagged'
      when l.mod_only_tags > 0 then 'mod-heavy'
      when l.required_tags > 0 then 'required-mix'
      else 'normal'
    end as tag_profile_bucket
  from latencies l
  left join user_quality uq_asker on uq_asker.user_id = l.asker_id
  left join user_quality uq_answerer on uq_answerer.user_id = l.first_answerer_id
  left join answerer_metrics am on am.answerer_id = l.first_answerer_id
  left join question_metrics qm on qm.asker_id = l.asker_id
),
ranked as (
  select
    fs.*,
    row_number() over (
      partition by date_trunc('month', fs.q_created)
      order by
        coalesce(fs.secs_to_first_answer, 1e15) asc,
        coalesce(fs.q_score, -999999) desc
    ) as speed_rank_in_month,
    dense_rank() over (
      order by
        coalesce(fs.net_vote_per_view, -1e9) desc,
        coalesce(fs.q_views, 0) desc
    ) as popularity_dense_rank
  from final_scored fs
),
filtered as (
  select *
  from ranked
  where
    q_created >= now() - interval '2 years'
    and (q_upvotes + coalesce(q_downvotes,0)) >= 5
    and coalesce(q_views, 0) > 0
    and (
      secs_to_first_answer is not null
      or (accepted_answer_id is not null and secs_to_accept is not null)
      or close_events > 0
    )
)
select
  f.question_id,
  f.asker_id,
  f.q_created,
  f.q_score,
  f.q_views,
  f.tag_count,
  f.tag_profile_bucket,
  f.min_tag_popularity,
  f.max_tag_popularity,
  f.q_upvotes,
  f.q_downvotes,
  f.q_comments_count,
  f.close_events,
  f.reopen_events,
  f.first_answer_id,
  f.first_answer_created,
  f.accepted_answer_id,
  f.accepted_created,
  f.secs_to_first_answer,
  f.secs_to_accept,
  f.secs_to_close_or_reopen,
  f.asker_badge_score,
  f.first_answerer_badge_score,
  f.first_answerer_answers_given,
  f.first_answerer_avg_score,
  f.net_vote_per_view,
  f.comments_per_answer,
  f.speed_rank_in_month,
  f.popularity_dense_rank,
  case
    when f.closeddate is not null then 'closed'
    when f.accepted_answer_id is not null then 'answered'
    when f.first_answer_id is not null then 'answered-no-accept'
    when f.canonical_post_id is not null then 'duplicate'
    else 'open'
  end as terminal_state,
  coalesce(f.canonical_post_id, f.question_id) as canonical_or_self_id
from filtered f
order by
  f.popularity_dense_rank,
  f.speed_rank_in_month
limit 500;