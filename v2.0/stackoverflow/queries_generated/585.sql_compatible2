with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_hint,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '2 years' from posts p)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as post_score,
    sum(coalesce(p.viewcount, 0)) as views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_activity as (
  select
    c.userid as user_id,
    count(*) as c_count,
    sum(coalesce(c.score, 0)) as c_score,
    max(c.creationdate) as last_comment_activity
  from comments c
  where c.userid is not null
  group by c.userid
),
vote_activity as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 5) as favorites_cast,
    sum(coalesce(v.bountyamount, 0)) as bounty_spent,
    max(v.creationdate) as last_vote_activity
  from votes v
  where v.userid is not null
  group by v.userid
),
badge_activity as (
  select
    b.userid as user_id,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(*) filter (where b.tagbased = true) as tag_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_metrics as (
  select
    p.owneruserid as user_id,
    count(*) as questions_total,
    count(*) filter (where p.acceptedanswerid is not null) as questions_with_accept,
    avg(nullif(p.answercount, 0)) as avg_answers_per_q,
    avg(nullif(p.viewcount, 0)) as avg_views_per_q,
    percentile_cont(0.9) within group (order by coalesce(p.viewcount, 0)) as p90_views_per_q
  from posts p
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid
),
answer_metrics as (
  select
    p.owneruserid as user_id,
    count(*) as answers_total,
    avg(coalesce(p.score, 0)) as avg_answer_score,
    count(*) filter (
      where exists (
        select 1
        from posts q
        where q.id = p.parentid
          and q.acceptedanswerid = p.id
      )
    ) as accepted_answers
  from posts p
  where p.posttypeid = 2 and p.owneruserid is not null
  group by p.owneruserid
),
close_events as (
  select
    ph.userid as user_id,
    count(*) as closes_cast,
    count(*) filter (where ph.comment in ('101','102','103','104','105')) as closes_with_reason,
    max(ph.creationdate) as last_close_vote
  from posthistory ph
  where ph.posthistorytypeid = 10 and ph.userid is not null
  group by ph.userid
),
dupe_links as (
  select
    pl.postid as source_post_id,
    pl.relatedpostid as target_post_id,
    pl.creationdate,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
user_dupe_profile as (
  select
    coalesce(ps.owneruserid, pt.owneruserid) as user_id,
    count(*) as dupe_events_involving_user,
    count(*) filter (where ps.id is not null) as dupe_as_source_author,
    count(*) filter (where pt.id is not null) as dupe_as_target_author,
    max(dl.creationdate) as last_dupe_event
  from dupe_links dl
  left join posts ps on ps.id = dl.source_post_id
  left join posts pt on pt.id = dl.target_post_id
  where coalesce(ps.owneruserid, pt.owneruserid) is not null
  group by coalesce(ps.owneruserid, pt.owneruserid)
),
tag_engagement as (
  select
    p.owneruserid as user_id,
    t.tagname,
    count(*) as tag_posts,
    sum(coalesce(p.score, 0)) as tag_score,
    row_number() over (partition by p.owneruserid order by count(*) desc, sum(coalesce(p.score,0)) desc, t.tagname) as rn
  from posts p
  join lateral unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag(tagname)
    on p.posttypeid = 1 and p.tags is not null
  left join tags t on t.tagname = tag.tagname
  where p.owneruserid is not null
  group by p.owneruserid, t.tagname
),
top3_tags as (
  select
    te.user_id,
    string_agg(te.tagname, ', ' order by te.rn) as top_tags
  from tag_engagement te
  where te.rn <= 3
  group by te.user_id
),
user_last_activity as (
  select
    ua.user_id,
    greatest(
      coalesce(ua.last_post_activity, timestamp 'epoch'),
      coalesce(ca.last_comment_activity, timestamp 'epoch'),
      coalesce(va.last_vote_activity, timestamp 'epoch'),
      coalesce(ba.last_badge_date, timestamp 'epoch'),
      coalesce(ce.last_close_vote, timestamp 'epoch'),
      coalesce(udp.last_dupe_event, timestamp 'epoch')
    ) as last_activity
  from user_activity ua
  left join comment_activity ca on ca.user_id = ua.user_id
  left join vote_activity va on va.user_id = ua.user_id
  left join badge_activity ba on ba.user_id = ua.user_id
  left join close_events ce on ce.user_id = ua.user_id
  left join user_dupe_profile udp on udp.user_id = ua.user_id
),
power_users as (
  select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.country_hint,
    ru.cohort_month,
    coalesce(ua.q_count, 0) as q_count,
    coalesce(ua.a_count, 0) as a_count,
    coalesce(ua.post_score, 0) as post_score,
    coalesce(ua.views, 0) as views,
    coalesce(ca.c_count, 0) as c_count,
    coalesce(ca.c_score, 0) as c_score,
    coalesce(va.upvotes_cast, 0) as upvotes_cast,
    coalesce(va.downvotes_cast, 0) as downvotes_cast,
    coalesce(va.favorites_cast, 0) as favorites_cast,
    coalesce(va.bounty_spent, 0) as bounty_spent,
    coalesce(ba.gold_badges, 0) as gold_badges,
    coalesce(ba.silver_badges, 0) as silver_badges,
    coalesce(ba.bronze_badges, 0) as bronze_badges,
    coalesce(ba.tag_badges, 0) as tag_badges,
    coalesce(qm.questions_total, 0) as questions_total,
    coalesce(qm.questions_with_accept, 0) as questions_with_accept,
    coalesce(qm.avg_answers_per_q, 0) as avg_answers_per_q,
    coalesce(qm.avg_views_per_q, 0) as avg_views_per_q,
    coalesce(qm.p90_views_per_q, 0) as p90_views_per_q,
    coalesce(am.answers_total, 0) as answers_total,
    coalesce(am.avg_answer_score, 0) as avg_answer_score,
    coalesce(am.accepted_answers, 0) as accepted_answers,
    coalesce(ce.closes_cast, 0) as closes_cast,
    coalesce(ce.closes_with_reason, 0) as closes_with_reason,
    coalesce(udp.dupe_events_involving_user, 0) as dupe_events,
    coalesce(udp.dupe_as_source_author, 0) as dupe_as_source_author,
    coalesce(udp.dupe_as_target_author, 0) as dupe_as_target_author,
    tla.last_activity,
    tt.top_tags
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.id
  left join comment_activity ca on ca.user_id = ru.id
  left join vote_activity va on va.user_id = ru.id
  left join badge_activity ba on ba.user_id = ru.id
  left join question_metrics qm on qm.user_id = ru.id
  left join answer_metrics am on am.user_id = ru.id
  left join close_events ce on ce.user_id = ru.id
  left join user_dupe_profile udp on udp.user_id = ru.id
  left join user_last_activity tla on tla.user_id = ru.id
  left join top3_tags tt on tt.user_id = ru.id
),
ranked as (
  select
    pu.*,
    row_number() over (
      partition by pu.cohort_month
      order by
        (pu.q_count + pu.a_count) desc,
        (pu.post_score + pu.c_score) desc,
        pu.reputation desc,
        pu.last_activity desc
    ) as cohort_rank,
    dense_rank() over (
      order by
        (pu.gold_badges * 100 + pu.silver_badges * 10 + pu.bronze_badges) desc,
        pu.accepted_answers desc,
        pu.questions_with_accept desc
    ) as global_badge_rank
  from power_users pu
),
thresholds as (
  select
    percentile_cont(0.95) within group (order by q_count + a_count) as p95_posts,
    percentile_cont(0.95) within group (order by post_score + c_score) as p95_score,
    percentile_cont(0.95) within group (order by reputation) as p95_rep
  from power_users
),
final as (
  select
    r.user_id,
    r.displayname,
    r.country_hint,
    r.cohort_month,
    r.reputation,
    r.q_count,
    r.a_count,
    r.post_score,
    r.views,
    r.c_count,
    r.c_score,
    r.upvotes_cast,
    r.downvotes_cast,
    r.favorites_cast,
    r.bounty_spent,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.tag_badges,
    r.questions_total,
    r.questions_with_accept,
    r.avg_answers_per_q,
    r.avg_views_per_q,
    r.p90_views_per_q,
    r.answers_total,
    r.avg_answer_score,
    r.accepted_answers,
    r.closes_cast,
    r.closes_with_reason,
    r.dupe_events,
    r.dupe_as_source_author,
    r.dupe_as_target_author,
    r.last_activity,
    r.top_tags,
    r.cohort_rank,
    r.global_badge_rank,
    case
      when (r.q_count + r.a_count) >= t.p95_posts then 'Ultra Active'
      when (r.post_score + r.c_score) >= t.p95_score then 'High Scorer'
      when r.reputation >= t.p95_rep then 'High Rep'
      when coalesce(r.top_tags, '') like '%sql%' then 'SQL Enthusiast'
      when r.gold_badges > 0 then 'Gold Holder'
      when r.accepted_answers > 0 and r.answers_total > 0 and (coalesce(r.accepted_answers,0) * 1.0) / nullif(r.answers_total,0) >= 0.5 then 'High Acceptance'
      else 'Regular'
    end as segment,
    case
      when r.last_activity is null then NULL
      else cast('2024-10-01 12:34:56' as timestamp) - r.last_activity
    end as inactivity_interval
  from ranked r
  cross join thresholds t
)
select *
from final
where
  (
    segment in ('Ultra Active','High Scorer','High Rep','SQL Enthusiast','Gold Holder','High Acceptance')
    or (coalesce(top_tags, '') <> '' and position(lower('python') in lower(top_tags)) > 0)
  )
  and (
    (q_count + a_count) > 0
    and coalesce(avg_views_per_q, 0) >= 0
    and (favorites_cast is null or favorites_cast >= 0)
  )
  and (
    last_activity is not null
    or (reputation > 0 and (gold_badges + silver_badges + bronze_badges) > 0)
  )
order by
  segment,
  cohort_month desc,
  cohort_rank
limit 200;