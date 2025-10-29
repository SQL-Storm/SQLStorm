-- {"query": "548.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2939} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    date_trunc('month', u.creationdate) as cohort_month,
    row_number() over (order by u.reputation desc, u.id) as rn_global
  from users u
  where u.creationdate >= now() - interval '5 years'
),
tag_universe as (
  select
    t.id as tag_id,
    t.tagname,
    t.count,
    t.ismoderatoronly,
    t.isrequired
  from tags t
  where t.count > 0
),
q_posts as (
  select p.*
  from posts p
  where p.posttypeid = 1
),
a_posts as (
  select p.*
  from posts p
  where p.posttypeid = 2
),
question_tags as (
  select
    q.id as question_id,
    unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
  from q_posts q
  where q.tags is not null and q.tags like '<%>'
),
user_activity as (
  select
    u.user_id,
    count(distinct q.id) filter (where q.id is not null) as questions_count,
    count(distinct a.id) filter (where a.id is not null) as answers_count,
    count(distinct c.id) filter (where c.id is not null) as comments_count,
    sum(greatest(q.score,0)) filter (where q.id is not null) as q_up_score,
    sum(greatest(a.score,0)) filter (where a.id is not null) as a_up_score,
    sum(greatest(-q.score,0)) filter (where q.id is not null) as q_down_score,
    sum(greatest(-a.score,0)) filter (where a.id is not null) as a_down_score,
    max(coalesce(q.lastactivitydate, a.lastactivitydate)) as last_post_activity
  from recent_users u
  left join posts q on q.owneruserid = u.user_id and q.posttypeid = 1
  left join posts a on a.owneruserid = u.user_id and a.posttypeid = 2
  left join comments c on c.userid = u.user_id
  group by u.user_id
),
vote_aggs as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) filter (where v.votetypeid = 5) as favorites_legacy
  from posts p
  join votes v on v.postid = p.id
  group by p.owneruserid
),
dup_clusters as (
  select
    pl.relatedpostid as canonical_id,
    count(*) filter (where pl.linktypeid = 3) as dup_inbound,
    count(*) filter (where pl.linktypeid = 1) as linked_inbound
  from postlinks pl
  group by pl.relatedpostid
),
accept_rates as (
  select
    u.user_id,
    count(*) filter (where q.acceptedanswerid is not null) as accepted_questions,
    count(*) as total_questions,
    1.0 * count(*) filter (where q.acceptedanswerid is not null) / nullif(count(*),0) as accept_rate
  from recent_users u
  left join q_posts q on q.owneruserid = u.user_id
  group by u.user_id
),
answer_latency as (
  select
    q.owneruserid as user_id,
    percentile_cont(0.5) within group (order by a.creationdate - q.creationdate) as p50_answer_latency,
    avg(extract(epoch from (a.creationdate - q.creationdate))/3600.0) as avg_answer_latency_hours
  from q_posts q
  join a_posts a on a.parentid = q.id
  where q.creationdate >= now() - interval '5 years'
  group by q.owneruserid
),
tag_participation as (
  select
    u.user_id,
    t.tagname,
    count(distinct q.id) as questions_with_tag,
    count(distinct a.id) as answers_on_tagged_questions
  from recent_users u
  left join q_posts q on q.owneruserid = u.user_id
  left join question_tags qt on qt.question_id = q.id
  left join tag_universe t on t.tagname = qt.tagname
  left join a_posts a on a.parentid = q.id and a.owneruserid = u.user_id
  group by u.user_id, t.tagname
),
top_tags as (
  select user_id, tagname, questions_with_tag, answers_on_tagged_questions,
         row_number() over (partition by user_id order by (questions_with_tag + answers_on_tagged_questions) desc nulls last, tagname) as rn
  from tag_participation
),
post_edits as (
  select
    u.user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_events_seen
  from recent_users u
  left join posthistory ph on ph.userid = u.user_id
  group by u.user_id
),
badge_aggs as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    sum(case when b.class = 1 then 1 else 0 end) as gold,
    sum(case when b.class = 2 then 1 else 0 end) as silver,
    sum(case when b.class = 3 then 1 else 0 end) as bronze,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
activity_rank as (
  select
    u.user_id,
    dense_rank() over (order by ua.questions_count desc nulls last, ua.answers_count desc nulls last) as rank_by_posts,
    dense_rank() over (order by coalesce(va.upvotes_received,0) - coalesce(va.downvotes_received,0) desc) as rank_by_net_votes,
    dense_rank() over (order by coalesce(va.bounty_total,0) desc) as rank_by_bounty
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join vote_aggs va on va.user_id = u.user_id
),
user_summary as (
  select
    u.user_id,
    u.displayname,
    u.reputation,
    u.cohort_month,
    u.location,
    u.websiteurl,
    ua.questions_count,
    ua.answers_count,
    ua.comments_count,
    coalesce(va.upvotes_received,0) as upvotes_received,
    coalesce(va.downvotes_received,0) as downvotes_received,
    coalesce(va.bounty_total,0) as bounty_total,
    ar.accept_rate,
    al.p50_answer_latency,
    al.avg_answer_latency_hours,
    pe.edits_made,
    pe.mod_events_seen,
    ba.badges_total,
    ba.gold, ba.silver, ba.bronze,
    ba.first_badge_date, ba.last_badge_date,
    ar2.rank_by_posts,
    ar2.rank_by_net_votes,
    ar2.rank_by_bounty,
    du.dup_inbound,
    du.linked_inbound,
    greatest(coalesce(ua.questions_count,0), coalesce(ua.answers_count,0)) as max_post_count,
    case
      when u.websiteurl ilike 'http%' then 1
      when u.websiteurl = 'n/a' then 0
      else null
    end as has_website
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join vote_aggs va on va.user_id = u.user_id
  left join accept_rates ar on ar.user_id = u.user_id
  left join answer_latency al on al.user_id = u.user_id
  left join post_edits pe on pe.user_id = u.user_id
  left join badge_aggs ba on ba.user_id = u.user_id
  left join activity_rank ar2 on ar2.user_id = u.user_id
  left join dup_clusters du on du.canonical_id = u.user_id -- intentionally mismatched to force outer join behavior
),
cross_tag_metrics as (
  select
    us.user_id,
    tt1.tagname as top_tag_1,
    tt2.tagname as top_tag_2,
    coalesce(tt1.questions_with_tag,0) + coalesce(tt1.answers_on_tagged_questions,0) as top_tag_1_activity,
    coalesce(tt2.questions_with_tag,0) + coalesce(tt2.answers_on_tagged_questions,0) as top_tag_2_activity
  from user_summary us
  left join top_tags tt1 on tt1.user_id = us.user_id and tt1.rn = 1
  left join top_tags tt2 on tt2.user_id = us.user_id and tt2.rn = 2
),
final_scores as (
  select
    us.*,
    ct.top_tag_1,
    ct.top_tag_2,
    ct.top_tag_1_activity,
    ct.top_tag_2_activity,
    (
      0.35 * coalesce(us.upvotes_received - us.downvotes_received,0) +
      0.25 * coalesce(us.answers_count,0) +
      0.20 * coalesce(us.questions_count,0) +
      0.10 * coalesce(us.badges_total,0) +
      0.05 * coalesce(us.bounty_total,0) -
      0.05 * coalesce(us.avg_answer_latency_hours,0)
    ) as activity_score,
    case
      when us.accept_rate is null then 'unknown'
      when us.accept_rate >= 0.8 then 'excellent'
      when us.accept_rate >= 0.5 then 'good'
      else 'low'
    end as accept_tier
  from user_summary us
  left join cross_tag_metrics ct on ct.user_id = us.user_id
),
ranked as (
  select
    f.*,
    row_number() over (
      partition by f.cohort_month
      order by f.activity_score desc nulls last, f.reputation desc, f.user_id
    ) as rn_cohort,
    ntile(10) over (order by f.activity_score desc nulls last) as decile_global
  from final_scores f
),
cohort_stats as (
  select
    cohort_month,
    count(*) as users_in_cohort,
    avg(activity_score) as avg_score,
    percentile_cont(0.5) within group (order by activity_score) as median_score
  from ranked
  group by cohort_month
),
anomalies as (
  select
    r.user_id,
    r.activity_score,
    r.accept_rate,
    r.answers_count,
    r.questions_count,
    r.upvotes_received,
    r.downvotes_received,
    case
      when r.activity_score is null then 'missing'
      when r.activity_score > (cs.avg_score + 3 * stddev_pop(r.activity_score) over ()) then 'high'
      when r.activity_score < (cs.avg_score - 3 * stddev_pop(r.activity_score) over ()) then 'low'
      else 'normal'
    end as zflag
  from ranked r
  join cohort_stats cs on cs.cohort_month = r.cohort_month
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.cohort_month,
  r.location,
  r.websiteurl,
  r.questions_count,
  r.answers_count,
  r.comments_count,
  r.upvotes_received,
  r.downvotes_received,
  r.bounty_total,
  r.accept_rate,
  r.accept_tier,
  r.p50_answer_latency,
  r.avg_answer_latency_hours,
  r.edits_made,
  r.mod_events_seen,
  r.badges_total,
  r.gold, r.silver, r.bronze,
  r.rank_by_posts,
  r.rank_by_net_votes,
  r.rank_by_bounty,
  r.activity_score,
  r.decile_global,
  r.rn_cohort,
  coalesce(r.top_tag_1, '(none)') as top_tag_1,
  coalesce(r.top_tag_2, '(none)') as top_tag_2,
  r.top_tag_1_activity,
  r.top_tag_2_activity,
  cs.users_in_cohort,
  cs.avg_score,
  cs.median_score,
  a.zflag as anomaly_flag
from ranked r
left join cohort_stats cs on cs.cohort_month = r.cohort_month
left join anomalies a on a.user_id = r.user_id
where
  (r.has_website is distinct from 0)
  and (
    r.activity_score is null
    or r.activity_score > coalesce(cs.median_score, 0) - 1
  )
order by
  r.decile_global asc,
  r.rn_cohort asc,
  r.user_id
limit 500;