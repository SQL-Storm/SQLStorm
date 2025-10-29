-- {"query": "861.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2814} 
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as host_domain,
    row_number() over (order by u.creationdate desc, u.id desc) as rn
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as post_score_sum,
    avg(nullif(p.viewcount, 0)) as avg_views_nonzero,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
tag_exploded as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    lower(trim(t)) as tag
  from posts p
  cross join lateral unnest(
    case
      when p.tags is null then array[]::varchar[]
      else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
    end
  ) as t
  where p.posttypeid = 1
),
top_user_tags as (
  select
    te.user_id,
    te.tag,
    count(*) as tag_count,
    row_number() over (partition by te.user_id order by count(*) desc, te.tag) as tag_rank
  from tag_exploded te
  group by te.user_id, te.tag
),
vote_summaries as (
  select
    p.owneruserid as user_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from posts p
  left join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_metrics as (
  select
    p.owneruserid as user_id,
    count(c.id) as comment_count_on_posts,
    avg(c.score) as avg_comment_score_on_posts
  from posts p
  left join comments c on c.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
accepted_answerers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1 and a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
badge_pivots as (
  select
    b.userid as user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    count(*) filter (where b.tagbased = 1) as tag_badges
  from badges b
  group by b.userid
),
post_closures as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    max(ph.creationdate) as last_close_date,
    count(*) as close_events,
    max(case when ph.comment ~ '^\d+$' then ph.comment::int end) as last_close_reason_id
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
question_quality as (
  select
    q.owneruserid as user_id,
    count(*) as q_total,
    sum(case when q.closeddate is not null then 1 else 0 end) as q_closed,
    avg(coalesce(q.score,0)) as q_avg_score,
    percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) as q_p90_views,
    sum(case when qc.close_events >= 2 then 1 else 0 end) as q_multi_closed
  from posts q
  left join post_closures qc on qc.postid = q.id
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
answer_quality as (
  select
    a.owneruserid as user_id,
    count(*) as a_total,
    avg(coalesce(a.score,0)) as a_avg_score,
    sum(case when a.score >= 5 then 1 else 0 end) as a_high_score,
    sum(case when a.creationdate >= current_date - interval '30 days' then 1 else 0 end) as a_last30
  from posts a
  where a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
link_graph as (
  select
    p.owneruserid as user_id,
    count(*) filter (where pl.linktypeid = 1) as linked_refs,
    count(*) filter (where pl.linktypeid = 3) as duplicate_marks
  from posts p
  left join postlinks pl on pl.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
edit_activity as (
  select
    ph.userid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
    min(ph.creationdate) as first_edit,
    max(ph.creationdate) as last_edit
  from posthistory ph
  where ph.userid is not null
  group by ph.userid
),
recent_dupes as (
  select
    q.owneruserid as user_id,
    count(*) as recent_dup_closes
  from posts q
  join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
  where q.posttypeid = 1
    and q.creationdate >= current_date - interval '90 days'
    and q.owneruserid is not null
  group by q.owneruserid
),
user_baseline as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(u.location, 'Unknown') as location,
    u.upvotes,
    u.downvotes,
    u.views
  from users u
),
aggregate as (
  select
    ub.user_id,
    ub.displayname,
    ub.reputation,
    ub.creationdate,
    ub.location,
    ub.upvotes,
    ub.downvotes,
    ub.views,
    ua.q_count,
    ua.a_count,
    ua.post_score_sum,
    ua.avg_views_nonzero,
    ua.last_post_activity,
    vs.upvotes_received,
    vs.downvotes_received,
    vs.bounty_started,
    vs.bounty_awarded,
    cm.comment_count_on_posts,
    cm.avg_comment_score_on_posts,
    aa.accepted_answers,
    b.gold_badges,
    b.silver_badges,
    b.bronze_badges,
    b.tag_badges,
    qq.q_total,
    qq.q_closed,
    qq.q_avg_score,
    qq.q_p90_views,
    qq.q_multi_closed,
    aq.a_total,
    aq.a_avg_score,
    aq.a_high_score,
    aq.a_last30,
    lg.linked_refs,
    lg.duplicate_marks,
    ea.edits_made,
    ea.first_edit,
    ea.last_edit,
    rd.recent_dup_closes
  from user_baseline ub
  left join user_activity ua on ua.user_id = ub.user_id
  left join vote_summaries vs on vs.user_id = ub.user_id
  left join comment_metrics cm on cm.user_id = ub.user_id
  left join accepted_answerers aa on aa.user_id = ub.user_id
  left join badge_pivots b on b.user_id = ub.user_id
  left join question_quality qq on qq.user_id = ub.user_id
  left join answer_quality aq on aq.user_id = ub.user_id
  left join link_graph lg on lg.user_id = ub.user_id
  left join edit_activity ea on ea.user_id = ub.user_id
  left join recent_dupes rd on rd.user_id = ub.user_id
),
ranked as (
  select
    a.*,
    coalesce(a.q_count,0) + coalesce(a.a_count,0) as total_posts,
    coalesce(a.upvotes_received,0) - coalesce(a.downvotes_received,0) as net_votes_received,
    coalesce(a.bounty_awarded,0) - coalesce(a.bounty_started,0) as net_bounty,
    case when coalesce(a.q_total,0) = 0 then null else (a.q_closed::numeric / nullif(a.q_total,0)) end as q_close_rate,
    case when coalesce(a.a_total,0) = 0 then null else (a.a_high_score::numeric / nullif(a.a_total,0)) end as a_high_score_rate,
    greatest(coalesce(a.post_score_sum,0), 0) as clamped_post_score_sum,
    row_number() over (order by coalesce(a.post_score_sum,0) desc, coalesce(a.accepted_answers,0) desc, a.user_id) as overall_rank,
    dense_rank() over (order by coalesce(a.q_avg_score, -1000) desc) as q_avg_score_rank,
    percent_rank() over (order by coalesce(a.a_avg_score, -1000)) as a_avg_score_prank,
    ntile(10) over (order by coalesce(a.upvotes_received,0) desc) as upvote_decile
  from aggregate a
),
best_tags as (
  select
    tut.user_id,
    string_agg(tut.tag || ':' || tut.tag_count::text, ', ' order by tut.tag_count desc, tut.tag) as top3_tags
  from top_user_tags tut
  where tut.tag_rank <= 3
  group by tut.user_id
),
domain_activity as (
  select
    ru.user_id,
    ru.host_domain,
    count(*) as appearances
  from recent_users ru
  group by ru.user_id, ru.host_domain
),
domain_rank as (
  select
    da.user_id,
    da.host_domain,
    da.appearances,
    row_number() over (partition by da.user_id order by da.appearances desc, da.host_domain) as rnk
  from domain_activity da
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.location,
  r.total_posts,
  r.q_count,
  r.a_count,
  r.accepted_answers,
  r.clamped_post_score_sum as post_score_sum,
  r.net_votes_received,
  r.net_bounty,
  coalesce(bt.top3_tags, '(no tags)') as top_tags,
  coalesce(r.q_close_rate, 0.0) as q_close_rate,
  coalesce(r.a_high_score_rate, 0.0) as a_high_score_rate,
  r.q_avg_score_rank,
  r.a_avg_score_prank,
  r.upvote_decile,
  r.q_p90_views,
  r.q_multi_closed,
  r.duplicate_marks,
  r.linked_refs,
  r.comment_count_on_posts,
  r.avg_comment_score_on_posts,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.tag_badges,
  r.first_edit,
  r.last_edit,
  r.last_post_activity,
  coalesce(dd.host_domain, 'unknown.host') as primary_domain,
  r.overall_rank
from ranked r
left join best_tags bt on bt.user_id = r.user_id
left join domain_rank dd on dd.user_id = r.user_id and dd.rnk = 1
where
  (
    r.total_posts >= 10
    or r.reputation >= 1000
    or (r.gold_badges is not null and r.gold_badges >= 1)
  )
  and coalesce(r.q_close_rate, 0) <= 0.5
  and (
    r.last_post_activity is null
    or r.last_post_activity >= current_date - interval '365 days'
  )
  and (
    r.displayname is null
    or lower(r.displayname) not like any (array['%test%','%bot%','%dummy%'])
  )
order by
  r.overall_rank,
  r.user_id
limit 500;