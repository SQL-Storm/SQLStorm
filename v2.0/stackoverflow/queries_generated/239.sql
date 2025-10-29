-- {"query": "239.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3600} 
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
q_posts as (
  select
    p.id as question_id,
    p.creationdate,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.answercount,
    p.favoritecount,
    p.tags,
    p.title,
    p.acceptedanswerid,
    case when p.closeddate is null then 0 else 1 end as is_closed
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select
    p.id as answer_id,
    p.parentid as question_id,
    p.owneruserid,
    p.score as answer_score,
    p.creationdate as answer_creationdate
  from posts p
  where p.posttypeid = 2
),
edits as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_date,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (10)) as last_closed_vote,
    count(*) filter (where ph.posthistorytypeid in (10)) as close_votes
  from posthistory ph
  group by ph.postid
),
votes_agg as (
  select
    v.postid,
    count(*) filter (where v.votetypeid = 2) as upvotes,
    count(*) filter (where v.votetypeid = 3) as downvotes,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total,
    min(v.creationdate) filter (where v.votetypeid in (2)) as first_upvote_at,
    max(v.creationdate) filter (where v.votetypeid in (2)) as last_upvote_at
  from votes v
  group by v.postid
),
comments_agg as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.score) as max_comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
dup_links as (
  select
    pl.postid as duplicate_id,
    pl.relatedpostid as original_id,
    pl.creationdate as dup_link_date
  from postlinks pl
  where pl.linktypeid = 3
),
linked_pairs as (
  select
    pl.postid,
    pl.relatedpostid,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid in (1,3)
),
tags_expanded as (
  select
    qp.question_id,
    unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as tag
  from q_posts qp
  where qp.tags is not null and length(qp.tags) >= 2
),
tag_density as (
  select
    te.tag,
    count(*) as tag_q_count,
    approx_percentile(count(*)) over () as approx_global // placeholder for engines without approx, ignored by most
  from tags_expanded te
  group by te.tag
),
answer_ranks as (
  select
    ap.question_id,
    ap.answer_id,
    ap.owneruserid,
    ap.answer_score,
    ap.answer_creationdate,
    rank() over (partition by ap.question_id order by ap.answer_score desc nulls last, ap.answer_creationdate asc) as score_rank,
    row_number() over (partition by ap.question_id order by ap.answer_creationdate asc) as time_rank
  from a_posts ap
),
first_response as (
  select distinct on (ar.question_id)
    ar.question_id,
    ar.answer_id as first_answer_id,
    ar.owneruserid as first_answerer_id,
    ar.answer_creationdate as first_answer_date,
    ar.answer_score as first_answer_score
  from answer_ranks ar
  order by ar.question_id, ar.time_rank
),
accepted_vs_rank as (
  select
    qp.question_id,
    case when qp.acceptedanswerid is not null then 1 else 0 end as has_accepted,
    ar.score_rank as accepted_score_rank,
    ar.time_rank as accepted_time_rank
  from q_posts qp
  left join answer_ranks ar
    on qp.acceptedanswerid = ar.answer_id
),
user_activity as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    count(distinct qp.question_id) as questions_asked,
    count(distinct ap.answer_id) as answers_given,
    sum(coalesce(va.upvotes,0)) as total_post_upvotes,
    sum(coalesce(va.downvotes,0)) as total_post_downvotes
  from recent_users ru
  left join q_posts qp on qp.owneruserid = ru.user_id
  left join a_posts ap on ap.owneruserid = ru.user_id
  left join votes_agg va on va.postid in (
    select id from posts p where p.owneruserid = ru.user_id
  )
  group by ru.user_id, ru.displayname, ru.reputation, ru.cohort_month
),
question_quality as (
  select
    qp.question_id,
    qp.owneruserid,
    qp.creationdate,
    qp.score,
    qp.viewcount,
    qp.answercount,
    qp.favoritecount,
    qp.is_closed,
    coalesce(va.upvotes,0) as q_upvotes,
    coalesce(va.downvotes,0) as q_downvotes,
    coalesce(va.bounty_total,0) as q_bounty,
    coalesce(ca.comment_count,0) as q_comment_count,
    ed.edit_count,
    ed.first_edit_date,
    ed.close_votes,
    fp.first_answer_date,
    extract(epoch from (fp.first_answer_date - qp.creationdate)) as seconds_to_first_answer,
    case
      when qp.viewcount is null or qp.viewcount = 0 then null
      else round( (qp.score::numeric) / nullif(qp.viewcount,0), 6)
    end as score_per_view,
    case
      when qp.answercount is null or qp.answercount = 0 then 0
      else qp.favoritecount::numeric / qp.answercount
    end as fav_per_answer
  from q_posts qp
  left join votes_agg va on va.postid = qp.question_id
  left join comments_agg ca on ca.postid = qp.question_id
  left join edits ed on ed.postid = qp.question_id
  left join first_response fp on fp.question_id = qp.question_id
),
dup_enrichment as (
  select
    qq.question_id,
    d.duplicate_id,
    d.original_id,
    d.dup_link_date,
    case when d.duplicate_id is not null then 1 else 0 end as is_marked_duplicate
  from question_quality qq
  left join dup_links d
    on d.duplicate_id = qq.question_id
),
tag_scored as (
  select
    qq.question_id,
    te.tag,
    dense_rank() over (partition by qq.question_id order by coalesce(ts.tag_q_count,0) desc, te.tag) as tag_pop_rank
  from question_quality qq
  left join tags_expanded te on te.question_id = qq.question_id
  left join (
    select te2.tag, count(*) as tag_q_count
    from tags_expanded te2
    group by te2.tag
  ) ts on ts.tag = te.tag
),
question_norms as (
  select
    qq.question_id,
    qq.owneruserid,
    qq.creationdate,
    qq.score,
    qq.viewcount,
    qq.answercount,
    qq.favoritecount,
    qq.q_upvotes,
    qq.q_downvotes,
    qq.q_bounty,
    qq.q_comment_count,
    qq.edit_count,
    qq.seconds_to_first_answer,
    qq.score_per_view,
    qq.fav_per_answer,
    de.is_marked_duplicate,
    coalesce(avg(qq.score) over (partition by date_trunc('month', qq.creationdate)), 0) as month_avg_score,
    coalesce(percent_rank() over (order by qq.score), 0) as score_percentile,
    coalesce(ntile(10) over (order by coalesce(qq.score,0) desc), 10) as score_decile
  from question_quality qq
  left join dup_enrichment de on de.question_id = qq.question_id
),
complex_predicates as (
  select
    qn.*,
    case
      when qn.is_marked_duplicate = 1 and coalesce(qn.answercount,0) = 0 then 'dup_no_answers'
      when qn.score >= 5 and qn.viewcount >= 1000 and coalesce(qn.seconds_to_first_answer,999999) < 3600 then 'fast_popular'
      when qn.score < 0 and qn.q_downvotes > qn.q_upvotes then 'controversial_negative'
      when qn.edit_count >= 3 and qn.fav_per_answer is not null and qn.fav_per_answer > 2 then 'heavily_edited_faved'
      else 'other'
    end as bucket,
    case
      when qn.score_per_view is null then 'unknown'
      when qn.score_per_view >= 0.01 then 'high_efficiency'
      when qn.score_per_view >= 0 then 'moderate_efficiency'
      else 'low_efficiency'
    end as efficiency_band
  from question_norms qn
),
top_tags_per_q as (
  select
    ts.question_id,
    string_agg(ts.tag, ',' order by ts.tag_pop_rank asc) filter (where ts.tag_pop_rank <= 3) as top3_tags
  from tag_scored ts
  group by ts.question_id
),
user_badge_stats as (
  select
    u.id as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id
),
final_union as (
  select
    qn.owneruserid as user_id,
    qn.question_id as entity_id,
    'question' as entity_type,
    qn.creationdate as activity_date,
    qn.score as primary_score,
    qn.score_decile,
    qn.score_percentile,
    qn.viewcount,
    qn.answercount,
    qn.q_upvotes as upvotes,
    qn.q_downvotes as downvotes,
    qn.q_bounty as bounty_total,
    qn.q_comment_count as comment_count,
    qn.seconds_to_first_answer,
    qn.bucket,
    qn.efficiency_band,
    coalesce(tt.top3_tags, '') as tags_summary
  from complex_predicates qn
  left join top_tags_per_q tt on tt.question_id = qn.question_id

  union all

  select
    ap.owneruserid as user_id,
    ap.answer_id as entity_id,
    'answer' as entity_type,
    ap.answer_creationdate as activity_date,
    ap.answer_score as primary_score,
    ntile(10) over (order by coalesce(ap.answer_score,0) desc) as score_decile,
    percent_rank() over (order by coalesce(ap.answer_score,0)) as score_percentile,
    null::int as viewcount,
    null::int as answercount,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(ca.comment_count,0) as comment_count,
    null::numeric as seconds_to_first_answer,
    case when ar.score_rank = 1 then 'top_answer' else 'other_answer' end as bucket,
    case when ap.answer_score >= 5 then 'efficient' else 'normal' end as efficiency_band,
    '' as tags_summary
  from a_posts ap
  left join votes_agg va on va.postid = ap.answer_id
  left join comments_agg ca on ca.postid = ap.answer_id
  left join answer_ranks ar on ar.answer_id = ap.answer_id
),
user_rollup as (
  select
    fu.user_id,
    min(fu.activity_date) as first_activity,
    max(fu.activity_date) as last_activity,
    count(*) as total_activities,
    count(*) filter (where fu.entity_type = 'question') as questions_count,
    count(*) filter (where fu.entity_type = 'answer') as answers_count,
    sum(coalesce(fu.primary_score,0)) as sum_scores,
    avg(coalesce(fu.primary_score,0)) as avg_score,
    sum(coalesce(fu.upvotes,0)) as sum_upvotes,
    sum(coalesce(fu.downvotes,0)) as sum_downvotes,
    sum(coalesce(fu.bounty_total,0)) as sum_bounty,
    max(fu.comment_count) as max_comment_count,
    count(*) filter (where fu.bucket in ('fast_popular','top_answer')) as high_perf_events
  from final_union fu
  group by fu.user_id
),
cohort_vs_perf as (
  select
    ra.user_id,
    ra.displayname,
    ra.reputation,
    ra.cohort_month,
    ua.first_activity,
    ua.last_activity,
    ua.total_activities,
    ua.questions_count,
    ua.answers_count,
    ua.sum_scores,
    ua.avg_score,
    ua.sum_upvotes,
    ua.sum_downvotes,
    ua.sum_bounty,
    ua.max_comment_count,
    ua.high_perf_events,
    ubs.badges_total,
    ubs.gold_badges,
    ubs.silver_badges,
    ubs.bronze_badges
  from recent_users ra
  left join user_rollup ua on ua.user_id = ra.user_id
  left join user_badge_stats ubs on ubs.user_id = ra.user_id
),
ranked_users as (
  select
    cvp.*,
    row_number() over (partition by cvp.cohort_month order by coalesce(cvp.sum_scores,0) desc, coalesce(cvp.sum_upvotes,0) desc) as cohort_rank_by_score,
    dense_rank() over (order by coalesce(cvp.high_perf_events,0) desc, coalesce(cvp.sum_bounty,0) desc) as global_rank_high_perf
  from cohort_vs_perf cvp
)
select
  ru.cohort_month,
  ru.cohort_rank_by_score,
  ru.global_rank_high_perf,
  ru.user_id,
  ru.displayname,
  ru.reputation,
  ru.badges_total,
  ru.gold_badges,
  ru.silver_badges,
  ru.bronze_badges,
  coalesce(ru.total_activities,0) as total_activities,
  coalesce(ru.questions_count,0) as questions_count,
  coalesce(ru.answers_count,0) as answers_count,
  coalesce(ru.sum_scores,0) as sum_scores,
  coalesce(ru.avg_score,0) as avg_score,
  coalesce(ru.sum_upvotes,0) as sum_upvotes,
  coalesce(ru.sum_downvotes,0) as sum_downvotes,
  coalesce(ru.sum_bounty,0) as sum_bounty,
  coalesce(ru.max_comment_count,0) as max_comment_count,
  ru.first_activity,
  ru.last_activity
from ranked_users ru
where
  (
    ru.cohort_rank_by_score <= 50
    or ru.global_rank_high_perf <= 200
    or (ru.badges_total is not null and ru.badges_total >= 10)
  )
  and (
    ru.sum_downvotes is null
    or ru.sum_upvotes is null
    or (ru.sum_upvotes - ru.sum_downvotes) >= 0
  )
order by ru.cohort_month desc, ru.cohort_rank_by_score asc, ru.global_rank_high_perf asc, ru.user_id
limit 1000;