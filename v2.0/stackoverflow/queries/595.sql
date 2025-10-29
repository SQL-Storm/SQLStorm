-- {"query": "595.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3119}
with
power_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    date_trunc('month', u.creationdate) as created_month,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    case
      when u.reputation >= 100000 then 'Legend'
      when u.reputation >= 50000 then 'Elite'
      when u.reputation >= 10000 then 'Pro'
      when u.reputation >= 1000 then 'Rising'
      else 'New'
    end as rep_band,
    row_number() over (partition by coalesce(nullif(trim(u.location), ''), 'Unknown') order by u.reputation desc, u.id) as loc_rank
  from users u
  where u.reputation >= 1000
),
recent_posts as (
  select p.*
  from posts p
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
    and p.posttypeid in (1,2)
),
question_tags as (
  select
    p.id as question_id,
    p.owneruserid as asker_id,
    p.acceptedanswerid,
    p.score as q_score,
    p.viewcount,
    p.favoritecount,
    p.creationdate as q_created,
    lower(coalesce(p.title, '')) as title_lc,
    string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><') as tag_arr,
    array_length(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'), 1) as tag_count,
    regexp_replace(coalesce(p.tags,''), '[^a-zA-Z0-9><-]', '', 'g') as tags_norm
  from recent_posts p
  where p.posttypeid = 1
),
answers as (
  select
    a.id as answer_id,
    a.parentid as question_id,
    a.owneruserid as answerer_id,
    a.score as a_score,
    a.creationdate as a_created,
    lead(a.score) over (partition by a.parentid order by a.score desc, a.id) as next_best_score,
    dense_rank() over (partition by a.parentid order by a.score desc, a.id) as score_rank
  from recent_posts a
  where a.posttypeid = 2
),
answer_metrics as (
  select
    qt.question_id,
    qt.asker_id,
    an.answer_id,
    an.answerer_id,
    an.a_score,
    an.score_rank,
    cast(extract(epoch from (an.a_created - qt.q_created)) as bigint) as secs_to_answer,
    case when qt.acceptedanswerid = an.answer_id then 1 else 0 end as is_accepted
  from question_tags qt
  join answers an on an.question_id = qt.question_id
),
question_agg as (
  select
    qt.question_id,
    qt.asker_id,
    qt.q_score,
    qt.viewcount,
    qt.favoritecount,
    qt.tag_count,
    coalesce(qt.title_lc, '') as title_lc,
    qt.tag_arr,
    min(am.secs_to_answer) filter (where am.secs_to_answer >= 0) as fastest_answer_secs,
    avg(nullif(am.secs_to_answer,0)) as avg_answer_secs,
    max(am.a_score) as best_answer_score,
    max(am.is_accepted) as has_accepted,
    count(*) as answer_count,
    sum(case when am.score_rank = 1 then 1 else 0 end) as top_scored_answers
  from question_tags qt
  left join answer_metrics am on am.question_id = qt.question_id
  group by qt.question_id, qt.asker_id, qt.q_score, qt.viewcount, qt.favoritecount, qt.tag_count, qt.title_lc, qt.tag_arr
),
post_votes as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 12 then 1 else 0 end) as spam_flags,
    sum(case when v.votetypeid = 10 then 1 else 0 end) as deletions
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by v.postid
),
comment_density as (
  select
    c.postid as question_id,
    count(*) as comment_count,
    cast(avg(nullif(length(c.text),0)) as numeric(18,2)) as avg_comment_len
  from comments c
  join posts p on p.id = c.postid and p.posttypeid = 1
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by c.postid
),
dupe_map as (
  select
    pl.postid as dup_question_id,
    pl.relatedpostid as original_question_id,
    min(pl.creationdate) as first_link_date
  from postlinks pl
  where pl.linktypeid = 3
  group by pl.postid, pl.relatedpostid
),
close_events as (
  select
    ph.postid as question_id,
    max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_raw,
    bool_or(ph.posthistorytypeid = 11) as was_reopened,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
user_stats as (
  select
    u.id as user_id,
    coalesce(sum(case when b.class = 1 then 1 else 0 end),0) as gold_badges,
    coalesce(sum(case when b.class = 2 then 1 else 0 end),0) as silver_badges,
    coalesce(sum(case when b.class = 3 then 1 else 0 end),0) as bronze_badges,
    coalesce(sum(case when vt.votetypeid = 2 then 1 else 0 end),0) as given_upvotes,
    coalesce(sum(case when vt.votetypeid = 3 then 1 else 0 end),0) as given_downvotes
  from users u
  left join badges b on b.userid = u.id
  left join votes vt on vt.userid = u.id and vt.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by u.id
),
tag_popularity as (
  select
    lower(t.tagname) as tagname,
    t.count as global_count,
    row_number() over (order by t.count desc nulls last) as global_rank
  from tags t
),
question_tag_weights as (
  select
    qa.question_id,
    unnest(qa.tag_arr) as tagname
  from question_agg qa
),
weighted_tag_scores as (
  select
    qtw.question_id,
    lower(qtw.tagname) as tagname,
    tp.global_count,
    case when tp.global_rank <= 50 then 1.0
         when tp.global_rank <= 200 then 0.75
         when tp.global_rank <= 1000 then 0.5
         else 0.25 end as popularity_weight
  from question_tag_weights qtw
  left join tag_popularity tp on tp.tagname = lower(qtw.tagname)
),
question_score as (
  select
    qa.question_id,
    0.35 * ln(1 + greatest(qa.viewcount,0)) +
    0.25 * coalesce(qa.q_score,0) +
    0.15 * coalesce(qa.favoritecount,0) +
    0.10 * ln(1 + coalesce(qa.answer_count,0)) +
    0.05 * coalesce(qa.best_answer_score,0) +
    0.10 * coalesce((select sum(popularity_weight) from weighted_tag_scores w where w.question_id = qa.question_id), 0) as composite_score
  from question_agg qa
),
question_enriched as (
  select
    qa.question_id,
    qa.asker_id,
    pu.displayname as asker_name,
    pu.rep_band as asker_band,
    pu.location_norm,
    us.gold_badges,
    us.silver_badges,
    us.bronze_badges,
    qa.q_score,
    qa.viewcount,
    qa.favoritecount,
    qa.tag_count,
    qa.answer_count,
    qa.fastest_answer_secs,
    qa.avg_answer_secs,
    qa.best_answer_score,
    qa.has_accepted,
    pv.upvotes as q_upvotes,
    pv.downvotes as q_downvotes,
    pv.spam_flags as q_spam_flags,
    cd.comment_count,
    cd.avg_comment_len,
    ce.last_close_reason_raw,
    ce.was_reopened,
    dm.original_question_id,
    qs.composite_score,
    case
      when qa.answer_count = 0 and ce.last_close_reason_raw is not null then 'Closed-NoAnswers'
      when qa.answer_count = 0 then 'Open-NoAnswers'
      when qa.has_accepted = 1 then 'Accepted'
      when qa.answer_count > 0 and qa.has_accepted = 0 then 'Answered-Unaccepted'
      else 'Other' end as status_bucket
  from question_agg qa
  left join power_users pu on pu.user_id = qa.asker_id
  left join user_stats us on us.user_id = qa.asker_id
  left join post_votes pv on pv.postid = qa.question_id
  left join comment_density cd on cd.question_id = qa.question_id
  left join close_events ce on ce.question_id = qa.question_id
  left join dupe_map dm on dm.dup_question_id = qa.question_id
  left join question_score qs on qs.question_id = qa.question_id
),
ranked as (
  select
    qe.question_id,
    qe.asker_id,
    qe.asker_name,
    qe.asker_band,
    qe.location_norm,
    qe.gold_badges,
    qe.silver_badges,
    qe.bronze_badges,
    qe.q_score,
    qe.viewcount,
    qe.favoritecount,
    qe.tag_count,
    qe.answer_count,
    qe.fastest_answer_secs,
    qe.avg_answer_secs,
    qe.best_answer_score,
    qe.has_accepted,
    qe.q_upvotes,
    qe.q_downvotes,
    qe.q_spam_flags,
    qe.comment_count,
    qe.avg_comment_len,
    qe.last_close_reason_raw,
    qe.was_reopened,
    qe.original_question_id,
    qe.composite_score,
    qe.status_bucket,
    row_number() over (order by qe.composite_score desc, coalesce(qe.q_upvotes,0) - coalesce(qe.q_downvotes,0) desc, qe.viewcount desc, qe.question_id) as overall_rank,
    percent_rank() over (order by qe.composite_score desc) as score_prank,
    ntile(10) over (order by coalesce(qe.fastest_answer_secs, 1e12)) as speed_decile
  from question_enriched qe
),
top_views as (
  select question_id from ranked order by viewcount desc nulls last limit 500
),
top_score as (
  select question_id from ranked order by composite_score desc nulls last limit 500
),
union_top as (
  select question_id, 'views' as src from top_views
  union
  select question_id, 'score' as src from top_score
),
best_answerer as (
  select
    an.question_id,
    (
      select u.reputation
      from posts pa
      join users u on u.id = pa.owneruserid
      where pa.id = an.answer_id
      order by u.reputation desc nulls last
      limit 1
    ) as best_answerer_rep
  from answers an
  where an.score_rank = 1
  group by an.question_id, an.answer_id
)
select
  r.question_id,
  r.overall_rank,
  round(cast(r.score_prank as numeric), 4) as score_percentile,
  r.speed_decile,
  r.status_bucket,
  coalesce(r.asker_name, '[unknown]') as asker_name,
  coalesce(r.asker_band, 'New') as asker_band,
  r.location_norm,
  coalesce(r.gold_badges,0) as gold_badges,
  coalesce(r.silver_badges,0) as silver_badges,
  coalesce(r.bronze_badges,0) as bronze_badges,
  r.q_score,
  r.q_upvotes,
  r.q_downvotes,
  r.q_spam_flags,
  r.viewcount,
  r.favoritecount,
  r.tag_count,
  r.answer_count,
  r.has_accepted,
  r.fastest_answer_secs,
  r.avg_answer_secs,
  coalesce(ba.best_answerer_rep, 0) as best_answerer_rep,
  r.last_close_reason_raw,
  r.was_reopened,
  r.original_question_id,
  r.composite_score,
  array(
    select lower(w.tagname)
    from weighted_tag_scores w
    where w.question_id = r.question_id
    order by w.popularity_weight desc, w.tagname
    limit 10
  ) as top_weighted_tags,
  count(*) over () as total_returned_rows,
  sum(case when ut.src is not null then 1 else 0 end) over () as in_union_top_count
from ranked r
left join union_top ut on ut.question_id = r.question_id
left join best_answerer ba on ba.question_id = r.question_id
where
  (r.composite_score is not null and r.composite_score > 0)
  and coalesce(r.q_spam_flags,0) = 0
  and (
    r.has_accepted = 1
    or (r.answer_count >= 2 and coalesce(r.q_upvotes,0) - coalesce(r.q_downvotes,0) >= 3)
    or (r.viewcount >= 1000 and r.favoritecount >= 5)
  )
  and not exists (
    select 1 from close_events ce2
    where ce2.question_id = r.question_id
      and coalesce(ce2.last_close_reason_raw, '') like '%opinion%'
  )
order by
  r.overall_rank
limit 200;