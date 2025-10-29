-- {"query": "733.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3153} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '18 months' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(greatest(p.score, 0)) as nonneg_score_sum,
    avg(nullif(p.viewcount, 0)) as avg_viewcount_nonzero,
    max(p.lastactivitydate) as last_post_activity,
    min(p.creationdate) as first_post_created,
    sum(case when p.closeddate is not null then 1 else 0 end) as closed_count,
    count(distinct case when p.posttypeid = 1 then p.id end) as distinct_questions,
    count(distinct case when p.posttypeid = 2 then p.parentid end) as distinct_answered_questions
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
user_badges as (
  select
    b.userid as user_id,
    count(*) as badge_count,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
recent_comments as (
  select
    c.userid as user_id,
    count(*) as comment_count,
    sum(greatest(c.score, 0)) as up_com_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.creationdate >= (select coalesce(max(creationdate), now() - interval '10 years') - interval '12 months' from comments)
  group by c.userid
),
q_with_dup_info as (
  select
    q.id as question_id,
    q.owneruserid as user_id,
    q.score,
    q.viewcount,
    q.title,
    q.tags,
    q.creationdate,
    q.acceptedanswerid,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links_count,
    bool_or(pl.linktypeid = 3) as has_dup_link,
    bool_or(ph.posthistorytypeid = 10 and coalesce(ph.comment ~ '^(101|1)$', false)) as has_dup_close_history
  from posts q
  left join postlinks pl
    on pl.postid = q.id
  left join posthistory ph
    on ph.postid = q.id
  where q.posttypeid = 1
  group by q.id, q.owneruserid, q.score, q.viewcount, q.title, q.tags, q.creationdate, q.acceptedanswerid
),
answer_quality as (
  select
    a.parentid as question_id,
    a.owneruserid as user_id,
    count(*) as answers_by_user_to_q,
    max(a.score) as max_answer_score_to_q,
    sum(case when a.score > 0 then 1 else 0 end) as pos_answers_to_q,
    max(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted
  from posts a
  join posts q on q.id = a.parentid and q.posttypeid = 1
  where a.posttypeid = 2
  group by a.parentid, a.owneruserid
),
user_votes as (
  select
    v.userid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_cast,
    max(v.creationdate) as last_vote_date
  from votes v
  group by v.userid
),
tag_exploded as (
  select
    q.user_id,
    unnest(string_to_array(substring(coalesce(q.tags, ''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tag
  from q_with_dup_info q
),
user_top_tags as (
  select
    te.user_id,
    array_agg(t.tagname order by sum(t.count) desc nulls last) filter (where count(distinct te.tag) > 0) as top_tags_by_popularity,
    count(distinct te.tag) as distinct_tags_used
  from tag_exploded te
  left join tags t on lower(t.tagname) = lower(te.tag)
  group by te.user_id
),
user_recent_hot as (
  select
    ph.userId as user_id,
    count(*) filter (where ph.posthistorytypeid = 52) as hot_selected_count,
    count(*) filter (where ph.posthistorytypeid = 53) as hot_removed_count,
    max(ph.creationdate) as last_hot_event
  from posthistory ph
  where ph.posthistorytypeid in (52,53)
  group by ph.userid
),
user_closure_patterns as (
  select
    q.user_id,
    count(*) filter (where q.has_dup_close_history) as closed_as_duplicate_count,
    count(*) filter (where q.has_dup_link) as linked_as_duplicate_count,
    count(*) filter (where q.has_dup_close_history or q.has_dup_link) as any_duplicate_signal_count
  from q_with_dup_info q
  group by q.user_id
),
per_user_time_buckets as (
  select
    p.owneruserid as user_id,
    date_trunc('month', p.creationdate) as month_bucket,
    count(*) filter (where p.posttypeid = 1) as q_in_month,
    count(*) filter (where p.posttypeid = 2) as a_in_month,
    sum(p.score) as score_in_month
  from posts p
  where p.creationdate is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
per_user_monthly_trend as (
  select
    user_id,
    month_bucket,
    q_in_month,
    a_in_month,
    score_in_month,
    avg(score_in_month) over (partition by user_id order by month_bucket rows between 2 preceding and current row) as rolling3_score_avg,
    sum(a_in_month) over (partition by user_id order by month_bucket rows between unbounded preceding and current row) as cum_answers
  from per_user_time_buckets
),
top_recent_users as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.websiteurl,
    ru.creationdate,
    dense_rank() over (order by coalesce(ua.nonneg_score_sum,0) + coalesce(ub.badge_count,0)*10 + coalesce(rc.comment_count,0) desc) as perf_rank
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.user_id
  left join user_badges ub on ub.user_id = ru.user_id
  left join recent_comments rc on rc.user_id = ru.user_id
  where ru.rn <= 5000
),
final_scores as (
  select
    tru.user_id,
    tru.displayname,
    tru.reputation,
    tru.location,
    tru.websiteurl,
    tru.creationdate,
    ua.q_count,
    ua.a_count,
    ua.nonneg_score_sum,
    ua.avg_viewcount_nonzero,
    ua.last_post_activity,
    ua.first_post_created,
    ub.badge_count,
    ub.gold_count,
    ub.silver_count,
    ub.bronze_count,
    rc.comment_count,
    rc.up_com_score,
    rc.last_comment_date,
    uv.upvotes_cast,
    uv.downvotes_cast,
    uv.bounty_total_cast,
    uv.last_vote_date,
    uht.hot_selected_count,
    uht.hot_removed_count,
    uht.last_hot_event,
    ucp.closed_as_duplicate_count,
    ucp.linked_as_duplicate_count,
    ucp.any_duplicate_signal_count,
    utt.top_tags_by_popularity,
    utt.distinct_tags_used,
    tru.perf_rank,
    /* composite score with NULL-safe arithmetic and mixed weights */
    (
      coalesce(ua.nonneg_score_sum,0) * 1.0
      + coalesce(ua.a_count,0) * 2.0
      + coalesce(ua.q_count,0) * 1.5
      + coalesce(ub.gold_count,0) * 50.0
      + coalesce(ub.silver_count,0) * 15.0
      + coalesce(ub.bronze_count,0) * 5.0
      + coalesce(rc.up_com_score,0) * 0.5
      + greatest(coalesce(uv.upvotes_cast,0) - coalesce(uv.downvotes_cast,0), 0) * 1.0
      + least(coalesce(ucp.any_duplicate_signal_count,0) * -2.0, 0)
      + coalesce(uht.hot_selected_count,0) * 10.0
      - coalesce(uht.hot_removed_count,0) * 8.0
      + coalesce(utt.distinct_tags_used,0) * 0.25
    ) as composite_score
  from top_recent_users tru
  left join user_activity ua on ua.user_id = tru.user_id
  left join user_badges ub on ub.user_id = tru.user_id
  left join recent_comments rc on rc.user_id = tru.user_id
  left join user_votes uv on uv.user_id = tru.user_id
  left join user_recent_hot uht on uht.user_id = tru.user_id
  left join user_closure_patterns ucp on ucp.user_id = tru.user_id
  left join user_top_tags utt on utt.user_id = tru.user_id
),
ranked as (
  select
    fs.*,
    ntile(20) over (order by fs.composite_score desc nulls last) as vt_quantile,
    row_number() over (order by fs.composite_score desc nulls last, fs.reputation desc, fs.user_id) as global_rownum
  from final_scores fs
),
question_sample as (
  select
    q.user_id,
    q.question_id,
    q.score,
    q.viewcount,
    q.title,
    q.tags,
    q.creationdate,
    row_number() over (partition by q.user_id order by q.score desc nulls last, q.viewcount desc nulls last, q.creationdate desc, q.question_id desc) as rn_best,
    row_number() over (partition by q.user_id order by q.creationdate desc, q.question_id desc) as rn_recent
  from q_with_dup_info q
),
answer_interactions as (
  select
    aq.user_id,
    sum(aq.answers_by_user_to_q) as answers_to_own_qs,
    sum(aq.pos_answers_to_q) as positive_answers_to_own_qs,
    sum(aq.has_accepted) as accepted_on_own_qs
  from answer_quality aq
  group by aq.user_id
),
final_assembled as (
  select
    r.global_rownum,
    r.vt_quantile,
    r.user_id,
    r.displayname,
    r.reputation,
    r.location,
    r.websiteurl,
    r.creationdate,
    r.q_count,
    r.a_count,
    r.nonneg_score_sum,
    r.avg_viewcount_nonzero,
    r.last_post_activity,
    r.first_post_created,
    r.badge_count,
    r.gold_count,
    r.silver_count,
    r.bronze_count,
    r.comment_count,
    r.up_com_score,
    r.last_comment_date,
    r.upvotes_cast,
    r.downvotes_cast,
    r.bounty_total_cast,
    r.last_vote_date,
    r.hot_selected_count,
    r.hot_removed_count,
    r.last_hot_event,
    r.closed_as_duplicate_count,
    r.linked_as_duplicate_count,
    r.any_duplicate_signal_count,
    r.top_tags_by_popularity,
    r.distinct_tags_used,
    r.composite_score,
    qi_best.question_id as best_question_id,
    qi_best.title as best_question_title,
    qi_best.score as best_question_score,
    qi_recent.question_id as recent_question_id,
    qi_recent.title as recent_question_title,
    qi_recent.creationdate as recent_question_date,
    ai.answers_to_own_qs,
    ai.positive_answers_to_own_qs,
    ai.accepted_on_own_qs,
    case
      when r.composite_score is null then 'unknown'
      when r.composite_score >= percentile_disc(0.9) within group (order by r.composite_score) over () then 'elite'
      when r.composite_score >= percentile_disc(0.75) within group (order by r.composite_score) over () then 'excellent'
      when r.composite_score >= percentile_disc(0.5) within group (order by r.composite_score) over () then 'good'
      else 'emerging'
    end as performance_band
  from ranked r
  left join question_sample qi_best on qi_best.user_id = r.user_id and qi_best.rn_best = 1
  left join question_sample qi_recent on qi_recent.user_id = r.user_id and qi_recent.rn_recent = 1
  left join answer_interactions ai on ai.user_id = r.user_id
)
select *
from final_assembled fa
where fa.vt_quantile <= 10
  and (
    fa.best_question_title is not null
    or fa.recent_question_title is not null
    or fa.badge_count > 0
  )
  and (
    fa.location is null
    or fa.location ilike any (array[
      '%United%',
      '%India%',
      '%Europe%',
      '%Remote%',
      '%US%',
      '%Canada%'
    ])
    or position(',' in coalesce(fa.location,'')) > 0
  )
order by fa.global_rownum
limit 250;