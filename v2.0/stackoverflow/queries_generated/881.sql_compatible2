with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.location,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    sum(coalesce(p.viewcount, 0)) as total_views,
    count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
    count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
    row_number() over (order by u.creationdate desc, u.id) as rn_newest
  from users u
  left join posts p
    on p.owneruserid = u.id
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
  group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
user_activity as (
  select
    p.owneruserid as user_id,
    min(p.creationdate) as first_post_at,
    max(p.creationdate) as last_post_at,
    count(*) as total_posts,
    sum(case when p.posttypeid = 1 then 1 else 0 end) as total_questions,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as total_answers,
    sum(coalesce(p.score, 0)) as post_score_sum,
    avg(nullif(p.score, 0)) as avg_nonzero_post_score
  from posts p
  group by p.owneruserid
),
badge_rollup as (
  select
    b.userid as user_id,
    count(*) as badges_total,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    max(b.date) as last_badge_at
  from badges b
  group by b.userid
),
question_metrics as (
  select
    q.owneruserid as user_id,
    count(*) as questions_total,
    avg(coalesce(q.viewcount, 0)) as avg_q_views,
    avg(coalesce(q.score, 0)) as avg_q_score,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_count,
    sum(coalesce(q.answercount, 0)) as answer_count_sum,
    percentile_cont(0.9) within group (order by coalesce(q.viewcount,0)) as p90_q_views
  from posts q
  where q.posttypeid = 1
  group by q.owneruserid
),
answer_metrics as (
  select
    a.owneruserid as user_id,
    count(*) as answers_total,
    avg(coalesce(a.score, 0)) as avg_a_score,
    sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
    sum(case when a.score < 0 then 1 else 0 end) as negative_answers
  from posts a
  where a.posttypeid = 2
  group by a.owneruserid
),
vote_rollup as (
  select
    v.userid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_cast,
    count(*) filter (where v.votetypeid = 3) as downvotes_cast,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount, 0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from votes v
  group by v.userid
),
received_votes as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received
  from posts p
  left join votes v
    on v.postid = p.id
  group by p.owneruserid
),
comment_signal as (
  select
    p.owneruserid as user_id,
    count(c.id) as comments_on_my_posts,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments_on_my_posts,
    sum(case when c.userId = p.owneruserid then 1 else 0 end) as self_comments
  from posts p
  left join comments c
    on c.postid = p.id
  group by p.owneruserid
),
dup_links as (
  select
    pl.postid as dup_post_id,
    pl.relatedpostid as original_post_id
  from postlinks pl
  where pl.linktypeid = 3
),
close_events as (
  select
    ph.postid,
    max(ph.creationdate) as last_closed_at,
    max(case when (ph.comment ~ '^\s*\d+\s*$') and (cast(trim(ph.comment) as integer) between 100 and 200) then cast(trim(ph.comment) as integer) end) as last_close_reason_new,
    max(case when (ph.comment ~ '^\s*\d+\s*$') and (cast(trim(ph.comment) as integer) between 1 and 99) then cast(trim(ph.comment) as integer) end) as last_close_reason_old
  from posthistory ph
  where ph.posthistorytypeid = 10
  group by ph.postid
),
edits_cte as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
    min(ph.creationdate) as first_edit_at,
    max(ph.creationdate) as last_edit_at
  from posthistory ph
  group by ph.postid
),
hot_bumps as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (50,52,53)) as hot_events
  from posthistory ph
  group by ph.postid
),
per_user_flags as (
  select
    p.owneruserid as user_id,
    sum(case when ce.last_closed_at is not null then 1 else 0 end) as closed_posts,
    sum(case when dl.dup_post_id is not null then 1 else 0 end) as duplicates_marked,
    sum(coalesce(e.edit_events,0)) as total_edit_events,
    sum(coalesce(h.hot_events,0)) as total_hot_events
  from posts p
  left join close_events ce on ce.postid = p.id
  left join dup_links dl on dl.dup_post_id = p.id
  left join edits_cte e on e.postid = p.id
  left join hot_bumps h on h.postid = p.id
  group by p.owneruserid
),
tag_inference as (
  select
    p.owneruserid as user_id,
    lower(trim(both ' ' from unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')))) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
),
top_tags as (
  select
    user_id,
    tagname,
    count(*) as tag_uses,
    row_number() over (partition by user_id order by count(*) desc, tagname) as rn
  from tag_inference
  group by user_id, tagname
),
user_last_seen as (
  select
    u.id as user_id,
    max(coalesce(p.lastactivitydate, u.lastaccessdate)) as last_seen
  from users u
  left join posts p on p.owneruserid = u.id
  group by u.id
),
activity_rank as (
  select
    u.user_id,
    dense_rank() over (order by coalesce(ua.total_posts,0) desc, coalesce(rv.upvotes_received,0) desc, u.total_views desc) as activity_dense_rank
  from recent_users u
  left join user_activity ua on ua.user_id = u.user_id
  left join received_votes rv on rv.user_id = u.user_id
)
select
  ru.user_id,
  coalesce(nullif(ru.displayname, ''), '(anonymous)') as displayname,
  ru.reputation,
  ru.creationdate as user_created_at,
  ul.last_seen,
  ru.location,
  ru.websiteurl,
  ru.total_views,
  ru.q_count,
  ru.a_count,
  coalesce(ua.total_posts, 0) as total_posts,
  coalesce(ua.total_questions, 0) as total_questions,
  coalesce(ua.total_answers, 0) as total_answers,
  coalesce(ua.post_score_sum, 0) as post_score_sum,
  ua.avg_nonzero_post_score,
  coalesce(qm.questions_total, 0) as questions_total,
  qm.avg_q_views,
  qm.avg_q_score,
  qm.p90_q_views,
  coalesce(qm.accepted_count, 0) as accepted_questions,
  coalesce(qm.answer_count_sum, 0) as total_answers_on_questions,
  coalesce(am.answers_total, 0) as answers_total,
  am.avg_a_score,
  am.positive_answers,
  am.negative_answers,
  coalesce(br.badges_total, 0) as badges_total,
  coalesce(br.gold_count, 0) as gold_badges,
  coalesce(br.silver_count, 0) as silver_badges,
  coalesce(br.bronze_count, 0) as bronze_badges,
  br.last_badge_at,
  coalesce(vr.upvotes_cast, 0) as upvotes_cast,
  coalesce(vr.downvotes_cast, 0) as downvotes_cast,
  coalesce(vr.bounties_started, 0) as bounties_started,
  coalesce(vr.bounty_amount_total, 0) as bounty_amount_total,
  coalesce(rv.upvotes_received, 0) as upvotes_received,
  coalesce(rv.downvotes_received, 0) as downvotes_received,
  coalesce(cs.comments_on_my_posts, 0) as comments_on_my_posts,
  coalesce(cs.pos_comments_on_my_posts, 0) as pos_comments_on_my_posts,
  coalesce(cs.self_comments, 0) as self_comments,
  coalesce(puf.closed_posts, 0) as closed_posts,
  coalesce(puf.duplicates_marked, 0) as duplicates_marked,
  coalesce(puf.total_edit_events, 0) as total_edit_events,
  coalesce(puf.total_hot_events, 0) as total_hot_events,
  string_agg(tt.tagname, ', ' order by tt.rn) filter (where tt.rn <= 3) as top_3_tags,
  case
    when br.gold_count > 0 then 'gold'
    when br.silver_count > 0 then 'silver'
    when br.bronze_count > 0 then 'bronze'
    else 'none'
  end as highest_badge_class,
  case
    when coalesce(ua.total_answers,0) = 0 then null
    else round(coalesce(1.0 * am.positive_answers / nullif(ua.total_answers,0), 0), 4)
  end as pct_positive_answers,
  case
    when coalesce(qm.questions_total,0) = 0 then null
    else round(coalesce(1.0 * qm.accepted_count / nullif(qm.questions_total,0), 0), 4)
  end as acceptance_ratio_questions,
  case
    when ru.total_views is null or ru.total_views = 0 then 'low'
    when ru.total_views < 1000 then 'medium'
    when ru.total_views < 10000 then 'high'
    else 'very_high'
  end as view_band,
  ar.activity_dense_rank
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join badge_rollup br on br.user_id = ru.user_id
left join question_metrics qm on qm.user_id = ru.user_id
left join answer_metrics am on am.user_id = ru.user_id
left join vote_rollup vr on vr.user_id = ru.user_id
left join received_votes rv on rv.user_id = ru.user_id
left join comment_signal cs on cs.user_id = ru.user_id
left join per_user_flags puf on puf.user_id = ru.user_id
left join (
  select user_id, tagname, rn
  from top_tags
  where rn <= 3
) tt on tt.user_id = ru.user_id
left join user_last_seen ul on ul.user_id = ru.user_id
left join activity_rank ar on ar.user_id = ru.user_id
where (
  (
    coalesce(ua.total_posts,0) >= 10
    and coalesce(qm.questions_total,0) > 0
    and coalesce(am.answers_total,0) > 0
  )
  or ru.total_views >= (
    select percentile_cont(0.95) within group (order by coalesce(total_views,0))
    from recent_users
  )
  or coalesce(br.badges_total,0) >= 5
)
and (
  ru.location is null
  or lower(ru.location) like '%united%'
  or lower(ru.location) similar to '%(^|,|\\s)(eu|usa|canada|india|remote)($|,|\\s)%'
)
group by
  ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ul.last_seen, ru.location, ru.websiteurl,
  ru.total_views, ru.q_count, ru.a_count,
  ua.total_posts, ua.total_questions, ua.total_answers, ua.post_score_sum, ua.avg_nonzero_post_score,
  qm.questions_total, qm.avg_q_views, qm.avg_q_score, qm.p90_q_views, qm.accepted_count, qm.answer_count_sum,
  am.answers_total, am.avg_a_score, am.positive_answers, am.negative_answers,
  br.badges_total, br.gold_count, br.silver_count, br.bronze_count, br.last_badge_at,
  vr.upvotes_cast, vr.downvotes_cast, vr.bounties_started, vr.bounty_amount_total,
  rv.upvotes_received, rv.downvotes_received,
  cs.comments_on_my_posts, cs.pos_comments_on_my_posts, cs.self_comments,
  puf.closed_posts, puf.duplicates_marked, puf.total_edit_events, puf.total_hot_events,
  ar.activity_dense_rank
having
  coalesce(ua.total_posts,0) + coalesce(rv.upvotes_received,0) + coalesce(cs.comments_on_my_posts,0) > 0
order by
  ar.activity_dense_rank,
  coalesce(ua.total_posts,0) desc,
  coalesce(rv.upvotes_received,0) desc,
  ru.total_views desc,
  ru.user_id
limit 500;