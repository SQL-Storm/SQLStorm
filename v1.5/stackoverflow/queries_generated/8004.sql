-- {"query": "8004.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4113} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    date_trunc('month', u.creationdate) as cohort_month,
    coalesce(nullif(trim(lower(u.location)), ''), 'unknown') as norm_location
  from users u
  where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '3 years' from users)
),
question_posts as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.favoritecount,
    p.commentcount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.closeddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score
  from posts p
  where p.posttypeid = 2
),
first_answer_per_q as (
  select
    a.question_id,
    min(a.creationdate) as first_answer_date
  from answer_posts a
  group by a.question_id
),
q_activity as (
  select
    q.id as question_id,
    q.user_id,
    q.creationdate as q_created,
    q.closeddate,
    q.score as q_score,
    q.viewcount,
    q.favoritecount,
    q.commentcount,
    case when q.tags is not null then cardinality(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) else 0 end as tag_count,
    fa.first_answer_date,
    extract(epoch from (fa.first_answer_date - q.creationdate))::bigint as secs_to_first_answer
  from question_posts q
  left join first_answer_per_q fa on fa.question_id = q.id
),
user_vote_agg as (
  select
    v.userid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
    count(*) as total_votes_cast,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.userid is not null
  group by v.userid
),
post_vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  group by v.postid
),
user_badges as (
  select
    b.userid as user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) as total_badges,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
comments_agg as (
  select
    c.userid as user_id,
    count(*) as comments_made,
    sum(c.score) as comment_score_sum,
    avg(c.score) filter (where c.score is not null) as comment_score_avg,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.userid is not null
  group by c.userid
),
q_closure as (
  select
    ph.postid as question_id,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
    min(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as close_reason_id,
    min(crt.name) as close_reason_name
  from posthistory ph
  left join closerreasontypes crt on crt.id = try_cast(ph.comment as int)
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
dupe_links as (
  select
    pl.postid as question_id,
    count(*) filter (where pl.linktypeid = 3) as duplicate_links,
    count(*) filter (where pl.linktypeid = 1) as linked_links,
    min(pl.creationdate) as first_link_at
  from postlinks pl
  group by pl.postid
),
q_tagset as (
  select
    q.id as question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
  from posts q
  where q.posttypeid = 1 and q.tags is not null
),
top_tags as (
  select
    tag,
    count(*) as tag_q_count,
    row_number() over (order by count(*) desc, tag) as tag_rank
  from q_tagset
  group by tag
),
user_q_stats as (
  select
    qa.user_id,
    count(*) as questions_posted,
    avg(qa.q_score) as avg_q_score,
    percentile_cont(0.5) within group (order by qa.q_score) as median_q_score,
    avg(qa.viewcount) as avg_views,
    avg(qa.favoritecount) as avg_favs,
    avg(qa.commentcount) as avg_comments,
    avg(qa.tag_count) as avg_tag_count,
    avg(qa.secs_to_first_answer) filter (where qa.secs_to_first_answer is not null) as avg_secs_to_first_answer,
    sum(case when qa.closeddate is not null then 1 else 0 end) as closed_q_count,
    sum(case when qa.secs_to_first_answer is null then 1 else 0 end) as unanswered_q_count,
    min(qa.q_created) as first_q_at,
    max(qa.q_created) as last_q_at
  from q_activity qa
  group by qa.user_id
),
user_a_stats as (
  select
    a.user_id,
    count(*) as answers_posted,
    avg(a.score) as avg_a_score,
    percentile_cont(0.5) within group (order by a.score) as median_a_score,
    min(a.creationdate) as first_a_at,
    max(a.creationdate) as last_a_at
  from answer_posts a
  group by a.user_id
),
user_recent_tag_pref as (
  select
    q.user_id,
    t.tag,
    count(*) as cnt,
    row_number() over (partition by q.user_id order by count(*) desc, t.tag) as rn
  from q_activity q
  join q_tagset t on t.question_id = q.question_id
  where q.q_created >= now() - interval '365 days'
  group by q.user_id, t.tag
),
user_top_tag as (
  select user_id, tag as favorite_recent_tag
  from user_recent_tag_pref
  where rn = 1
),
user_cohort as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.norm_location,
    dense_rank() over (order by ru.cohort_month) as cohort_rank
  from recent_users ru
),
user_engagement as (
  select
    uc.user_id,
    coalesce(uqs.questions_posted, 0) as questions_posted,
    coalesce(uas.answers_posted, 0) as answers_posted,
    coalesce(ua.total_votes_cast, 0) as votes_cast,
    coalesce(cb.comments_made, 0) as comments_made,
    greatest(
      coalesce(date_part('epoch', now() - nullif(uc.cohort_month, null)), 0),
      1
    ) as secs_since_cohort
  from user_cohort uc
  left join user_q_stats uqs on uqs.user_id = uc.user_id
  left join user_a_stats uas on uas.user_id = uc.user_id
  left join user_vote_agg ua on ua.user_id = uc.user_id
  left join comments_agg cb on cb.user_id = uc.user_id
),
scored_users as (
  select
    ue.user_id,
    0.40 * ln(1 + ue.questions_posted) +
    0.45 * ln(1 + ue.answers_posted) +
    0.10 * ln(1 + ue.votes_cast) +
    0.05 * ln(1 + ue.comments_made) as activity_score
  from user_engagement ue
),
q_enriched as (
  select
    qa.*,
    pva.upvotes,
    pva.downvotes,
    pva.bounty_started,
    pva.bounty_awarded,
    qc.first_closed_at,
    coalesce(qc.close_reason_name, 'n/a') as close_reason_name,
    dl.duplicate_links,
    dl.linked_links
  from q_activity qa
  left join post_vote_agg pva on pva.postid = qa.question_id
  left join q_closure qc on qc.question_id = qa.question_id
  left join dupe_links dl on dl.question_id = qa.question_id
),
location_norm as (
  select
    uc.user_id,
    case
      when uc.norm_location ~* '(us|usa|united states|san francisco|new york|seattle|austin|boston)' then 'USA'
      when uc.norm_location ~* '(uk|united kingdom|england|scotland|wales|london|manchester)' then 'UK'
      when uc.norm_location ~* '(india|bangalore|mumbai|delhi|hyderabad|pune|chennai)' then 'India'
      when uc.norm_location ~* '(germany|deutschland|berlin|munich|munchen|hamburg)' then 'Germany'
      when uc.norm_location ~* '(canada|toronto|vancouver|montreal|ottawa)' then 'Canada'
      when uc.norm_location ~* '(australia|sydney|melbourne|brisbane|perth)' then 'Australia'
      when uc.norm_location ~* '(france|paris|lyon|marseille)' then 'France'
      when uc.norm_location ~* '(brazil|brasil|sao paulo|rio de janeiro)' then 'Brazil'
      when uc.norm_location ~* '(russia|moscow|saint petersburg)' then 'Russia'
      when uc.norm_location ~* '(china|beijing|shanghai|shenzhen)' then 'China'
      when uc.norm_location = 'unknown' then 'Unknown'
      else 'Other'
    end as country_bucket
  from user_cohort uc
),
user_summary as (
  select
    uc.user_id,
    uc.displayname,
    uc.reputation,
    uc.cohort_month,
    ln(greatest(1, uc.reputation)) as ln_reputation,
    coalesce(lb.gold_badges,0) as gold_badges,
    coalesce(lb.silver_badges,0) as silver_badges,
    coalesce(lb.bronze_badges,0) as bronze_badges,
    coalesce(lb.total_badges,0) as total_badges,
    ua.upvotes_cast,
    ua.downvotes_cast,
    ua.favorites_cast,
    ua.total_votes_cast,
    cb.comments_made,
    cb.comment_score_sum,
    uqs.questions_posted,
    uqs.avg_q_score,
    uqs.median_q_score,
    uqs.avg_views,
    uqs.avg_favs,
    uqs.avg_comments,
    uqs.avg_tag_count,
    uqs.avg_secs_to_first_answer,
    uqs.closed_q_count,
    uqs.unanswered_q_count,
    uas.answers_posted,
    uas.avg_a_score,
    ut.favorite_recent_tag,
    ln(1 + coalesce(uqs.questions_posted,0) + 2*coalesce(uas.answers_posted,0)) as ln_activity,
    coalesce(ln(1 + ua.upvotes_cast - ua.downvotes_cast), 0) as ln_net_votes,
    ln(1 + coalesce(cb.comments_made,0)) as ln_comments
  from user_cohort uc
  left join user_badges lb on lb.user_id = uc.user_id
  left join user_vote_agg ua on ua.user_id = uc.user_id
  left join comments_agg cb on cb.user_id = uc.user_id
  left join user_q_stats uqs on uqs.user_id = uc.user_id
  left join user_a_stats uas on uas.user_id = uc.user_id
  left join user_top_tag ut on ut.user_id = uc.user_id
),
q_ranked as (
  select
    qe.*,
    row_number() over (partition by qe.user_id order by coalesce(qe.q_score, -9999) desc, qe.viewcount desc, qe.q_created desc) as rn_best,
    row_number() over (partition by qe.user_id order by coalesce(qe.q_score, 9999) asc, qe.viewcount asc, qe.q_created asc) as rn_worst
  from q_enriched qe
),
best_worst_q as (
  select
    q1.user_id,
    max(q1.q_score) filter (where q1.rn_best = 1) as best_q_score,
    min(q1.q_score) filter (where q1.rn_worst = 1) as worst_q_score,
    max(q1.viewcount) filter (where q1.rn_best = 1) as best_q_views,
    min(q1.viewcount) filter (where q1.rn_worst = 1) as worst_q_views
  from q_ranked q1
  group by q1.user_id
),
user_country_activity as (
  select
    ln.country_bucket,
    count(distinct us.user_id) as users_in_bucket,
    avg(us.ln_activity) as avg_ln_activity,
    avg(us.ln_reputation) as avg_ln_reputation
  from user_summary us
  join location_norm ln on ln.user_id = us.user_id
  group by ln.country_bucket
),
cohort_metrics as (
  select
    us.cohort_month,
    count(*) as users_in_cohort,
    avg(us.ln_reputation) as avg_ln_rep,
    percentile_cont(0.5) within group (order by us.ln_activity) as p50_ln_activity,
    percentile_cont(0.9) within group (order by us.ln_activity) as p90_ln_activity
  from user_summary us
  group by us.cohort_month
),
heavy_join as (
  select
    us.user_id,
    us.displayname,
    us.reputation,
    us.cohort_month,
    us.favorite_recent_tag,
    co.country_bucket,
    su.activity_score,
    coalesce(bw.best_q_score, 0) as best_q_score,
    coalesce(bw.worst_q_score, 0) as worst_q_score,
    us.ln_reputation + us.ln_activity + coalesce(su.activity_score,0) as composite_score,
    cm.users_in_cohort,
    cm.p50_ln_activity,
    cm.p90_ln_activity,
    uca.avg_ln_activity as country_avg_ln_activity
  from user_summary us
  left join location_norm co on co.user_id = us.user_id
  left join scored_users su on su.user_id = us.user_id
  left join best_worst_q bw on bw.user_id = us.user_id
  left join cohort_metrics cm on cm.cohort_month = us.cohort_month
  left join user_country_activity uca on uca.country_bucket = co.country_bucket
),
-- create a synthetic workload using set operators to stress planner
synthetic as (
  select * from heavy_join
  union all
  select * from heavy_join where composite_score > (select avg(composite_score) from heavy_join)
  union
  select * from heavy_join where country_bucket is distinct from 'Unknown'
),
ranked as (
  select
    s.*,
    dense_rank() over (order by composite_score desc, users_in_cohort desc, p90_ln_activity desc) as global_rank,
    dense_rank() over (partition by country_bucket order by composite_score desc) as country_rank
  from synthetic s
),
with_flags as (
  select
    r.*,
    case
      when favorite_recent_tag is null then 'NoRecentTag'
      when favorite_recent_tag ~* '^(c|c\+\+|java|python|javascript)$' then 'CoreLang'
      when favorite_recent_tag like any (array['sql%', 'postgres%', 'tsql%', 'mysql%']) then 'DBLang'
      else 'OtherTag'
    end as tag_bucket,
    case when reputation >= 10000 and coalesce(best_q_score,0) >= 10 then true else false end as is_power_user
  from ranked r
),
-- correlated subquery to fetch user's most-viewed question title
most_viewed_q as (
  select
    q.user_id,
    (
      select p.title
      from posts p
      where p.posttypeid = 1 and p.owneruserid = q.user_id
      order by p.viewcount desc nulls last, p.score desc nulls last
      limit 1
    ) as top_q_title
  from (select distinct user_id from q_activity) q
)
select
  wf.user_id,
  wf.displayname,
  wf.country_bucket,
  wf.cohort_month,
  wf.global_rank,
  wf.country_rank,
  round(wf.composite_score::numeric, 4) as composite_score,
  wf.users_in_cohort,
  wf.p50_ln_activity,
  wf.p90_ln_activity,
  wf.country_avg_ln_activity,
  wf.tag_bucket,
  wf.is_power_user,
  coalesce(mvq.top_q_title, '(none)') as top_q_title
from with_flags wf
left join most_viewed_q mvq on mvq.user_id = wf.user_id
where
  -- complicated predicate mixing nulls, pattern, and bounds
  (
    wf.country_bucket is not null
    and (
      wf.country_bucket <> 'Unknown'
      or (wf.favorite_recent_tag is null and wf.users_in_cohort >= 1)
    )
  )
  and not (wf.favorite_recent_tag ilike '%test%' or wf.favorite_recent_tag ilike '%foo%')
  and (wf.composite_score > 0 or wf.is_power_user is true)
order by wf.global_rank, wf.country_rank, wf.user_id
limit 500;