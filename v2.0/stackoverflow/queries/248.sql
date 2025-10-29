-- {"query": "248.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3679}
with
active_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(cast(u.location as varchar)), ''), 'Unknown') as location_norm,
    case when lower(coalesce(cast(u.websiteurl as varchar), '')) like '%github%' then 1 else 0 end as has_github,
    row_number() over (order by (u.upvotes - u.downvotes) desc, u.reputation desc, u.id) as rn_up_minus_down
  from users u
  where u.reputation > 100
    and u.lastaccessdate >= (select max(p.creationdate) from posts p) - interval '365 days'
),
user_posts as (
  select
    p.id as post_id,
    p.posttypeid,
    pt.name as post_type_name,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.title,
    p.tags,
    p.acceptedanswerid,
    p.parentid,
    p.closeddate,
    p.contentlicense,
    case
      when p.tags is null then array[]::text[]
      else string_to_array(substring(p.tags from 2 for greatest(char_length(p.tags)-2,0)), '><')
    end as tag_array
  from posts p
  join posttypes pt on pt.id = p.posttypeid
  where p.owneruserid in (select user_id from active_users)
),
post_tags as (
  select
    up.post_id,
    lower(trim(cast(tname as varchar))) as tagname
  from user_posts up,
  unnest(up.tag_array) as tname
),
tag_stats as (
  select
    pt.post_id,
    count(*) as tag_count,
    sum(case when t.count > 1000 then 1 else 0 end) as popular_tag_hits,
    min(t.count) filter (where t.count is not null) as min_tag_global_count,
    max(t.count) filter (where t.count is not null) as max_tag_global_count
  from post_tags pt
  left join tags t on t.tagname = pt.tagname
  group by pt.post_id
),
vote_agg as (
  select
    v.postid as post_id,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    sum(case when v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' and v.votetypeid = 2 then 1 else 0 end) as up_last_90d,
    sum(case when v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days' and v.votetypeid = 3 then 1 else 0 end) as down_last_90d
  from votes v
  where v.postid in (select post_id from user_posts)
  group by v.postid
),
comment_agg as (
  select
    c.postid as post_id,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_date,
    max(char_length(c.text)) as max_comment_len,
    avg(case when char_length(c.text) > 0 then least(char_length(c.text), 600) * 1.0 else null end) as avg_comment_len
  from comments c
  where c.postid in (select post_id from user_posts)
  group by c.postid
),
history_flags as (
  select
    ph.postid as post_id,
    max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as ever_closed,
    max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as ever_reopened,
    max(case when ph.posthistorytypeid in (4,5,6) then 1 else 0 end) as ever_edited,
    max(case when ph.posthistorytypeid in (35,36,17) then 1 else 0 end) as ever_migrated,
    max(case when ph.posthistorytypeid = 50 then 1 else 0 end) as community_bump,
    min(case when ph.posthistorytypeid = 10 then ph.creationdate end) as first_close_date
  from posthistory ph
  where ph.postid in (select post_id from user_posts)
  group by ph.postid
),
qa_metrics as (
  select
    q.id as question_id,
    q.owneruserid as asker_id,
    q.creationdate as question_date,
    a.id as accepted_answer_id,
    a.owneruserid as answerer_id,
    a.creationdate as accepted_answer_date,
    extract(epoch from (a.creationdate - q.creationdate))/3600.0 as hours_to_accept
  from posts q
  left join posts a on a.id = q.acceptedanswerid
  where q.id in (select post_id from user_posts where posttypeid = 1)
),
link_agg as (
  select
    pl.postid as post_id,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links_out,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links_out,
    sum(case when pl.linktypeid = 3 then 0 else 0 end) as dummy_zero
  from postlinks pl
  where pl.postid in (select post_id from user_posts)
  group by pl.postid
),
post_scores as (
  select
    up.post_id,
    up.user_id,
    up.post_type_name,
    up.creationdate,
    up.score,
    coalesce(va.upvotes,0) as upvotes,
    coalesce(va.downvotes,0) as downvotes,
    coalesce(va.bounty_total,0) as bounty_total,
    coalesce(ca.comment_count,0) as comments,
    coalesce(ts.tag_count,0) as tag_count,
    coalesce(ts.popular_tag_hits,0) as popular_tag_hits,
    coalesce(la.dup_links_out,0) as dup_links_out,
    coalesce(la.related_links_out,0) as related_links_out,
    coalesce(hf.ever_closed,0) as ever_closed,
    coalesce(hf.ever_reopened,0) as ever_reopened,
    coalesce(hf.ever_edited,0) as ever_edited,
    coalesce(hf.community_bump,0) as community_bump,
    case
      when up.viewcount is null or up.viewcount = 0 then null
      else (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) * 1.0 / nullif(up.viewcount,0)
    end as net_per_view,
    (
      1.0 * coalesce(va.upvotes,0)
      - 0.7 * coalesce(va.downvotes,0)
      + 0.2 * coalesce(ca.comment_count,0)
      + 0.5 * coalesce(ts.popular_tag_hits,0)
      + 0.8 * case when up.posttypeid = 1 then coalesce(up.answercount,0) else 0 end
      + 0.3 * coalesce(la.related_links_out,0)
      - 0.4 * coalesce(la.dup_links_out,0)
      + 0.6 * case when coalesce(hf.ever_edited,0) = 1 then 1 else 0 end
      - 0.9 * case when coalesce(hf.ever_closed,0) = 1 then 1 else 0 end
      + 0.1 * coalesce(va.bounty_total,0)
      + 0.05 * coalesce(up.viewcount,0)
    ) as composite_score
  from user_posts up
  left join vote_agg va on va.post_id = up.post_id
  left join comment_agg ca on ca.post_id = up.post_id
  left join tag_stats ts on ts.post_id = up.post_id
  left join link_agg la on la.post_id = up.post_id
  left join history_flags hf on hf.post_id = up.post_id
),
ranked_posts as (
  select
    ps.post_id,
    ps.user_id,
    ps.post_type_name,
    ps.creationdate,
    ps.score,
    ps.upvotes,
    ps.downvotes,
    ps.bounty_total,
    ps.comments,
    ps.tag_count,
    ps.popular_tag_hits,
    ps.dup_links_out,
    ps.related_links_out,
    ps.ever_closed,
    ps.ever_reopened,
    ps.ever_edited,
    ps.community_bump,
    ps.net_per_view,
    ps.composite_score,
    row_number() over (partition by ps.user_id order by ps.composite_score desc, ps.creationdate desc, ps.post_id) as rn_by_user,
    rank() over (order by ps.composite_score desc) as global_rank,
    dense_rank() over (partition by ps.post_type_name order by ps.composite_score desc) as type_rank
  from post_scores ps
),
user_rollup as (
  select
    au.user_id,
    au.displayname,
    au.location_norm,
    au.has_github,
    au.reputation,
    count(rp.post_id) as posts_considered,
    sum(case when rp.post_type_name = 'Question' then 1 else 0 end) as questions_cnt,
    sum(case when rp.post_type_name = 'Answer' then 1 else 0 end) as answers_cnt,
    avg(nullif(rp.net_per_view,0)) as avg_net_per_view,
    percentile_cont(0.5) within group (order by rp.composite_score) as median_composite,
    max(rp.composite_score) as max_composite,
    min(rp.composite_score) as min_composite,
    sum(case when rp.rn_by_user <= 3 then 1 else 0 end) as top3_post_count,
    sum(coalesce(rp.upvotes,0)) as total_upvotes_on_posts,
    sum(coalesce(rp.downvotes,0)) as total_downvotes_on_posts
  from active_users au
  left join ranked_posts rp on rp.user_id = au.user_id
  group by au.user_id, au.displayname, au.location_norm, au.has_github, au.reputation
),
anomalies as (
  select
    rp.post_id,
    rp.user_id,
    rp.post_type_name,
    rp.creationdate,
    rp.score,
    rp.upvotes,
    rp.downvotes,
    rp.comments,
    rp.tag_count,
    rp.popular_tag_hits,
    rp.dup_links_out,
    rp.related_links_out,
    rp.ever_closed,
    rp.ever_reopened,
    rp.ever_edited,
    rp.community_bump,
    rp.net_per_view,
    rp.composite_score,
    case
      when coalesce(rp.upvotes,0) = 0 and coalesce(rp.downvotes,0) >= 5 and coalesce(rp.comments,0) >= 10 then 'Controversial'
      when rp.post_type_name = 'Question' and coalesce(rp.tag_count,0) >= 5 and coalesce(rp.dup_links_out,0) >= 1 then 'OvertaggedDuplicate'
      when rp.post_type_name = 'Answer' and coalesce(rp.upvotes,0) >= 20 and coalesce(rp.downvotes,0) = 0 then 'HighQualityAnswer'
      when coalesce(rp.net_per_view,0) < 0 then 'NegativeEngagement'
      when coalesce(rp.ever_closed,0) = 1 and coalesce(rp.ever_reopened,0) = 1 then 'ClosedThenReopened'
      else null
    end as anomaly_label
  from ranked_posts rp
  where
    (
      (coalesce(rp.upvotes,0) = 0 and coalesce(rp.downvotes,0) >= 5 and coalesce(rp.comments,0) >= 10)
      or (rp.post_type_name = 'Question' and coalesce(rp.tag_count,0) >= 5 and coalesce(rp.dup_links_out,0) >= 1)
      or (rp.post_type_name = 'Answer' and coalesce(rp.upvotes,0) >= 20 and coalesce(rp.downvotes,0) = 0)
      or (coalesce(rp.net_per_view,0) < 0)
      or (coalesce(rp.ever_closed,0) = 1 and coalesce(rp.ever_reopened,0) = 1)
    )
),
top_posts as (
  select rp.*
  from ranked_posts rp
  where rp.rn_by_user <= 5
  union all
  select rp.*
  from ranked_posts rp
  where rp.global_rank <= 100
),
first_tag as (
  select
    up.post_id,
    (
      select min(lower(trim(cast(tname as varchar))))
      from unnest(up.tag_array) as tname
    ) as first_tag_alpha
  from user_posts up
)
select
  rp.post_id,
  rp.user_id,
  au.displayname,
  ur.location_norm,
  ur.has_github,
  rp.post_type_name,
  rp.creationdate,
  rp.score,
  rp.upvotes,
  rp.downvotes,
  rp.comments,
  rp.tag_count,
  rp.popular_tag_hits,
  rp.dup_links_out,
  rp.related_links_out,
  rp.ever_closed,
  rp.ever_reopened,
  rp.ever_edited,
  rp.community_bump,
  rp.net_per_view,
  rp.composite_score,
  rp.rn_by_user,
  rp.global_rank,
  rp.type_rank,
  coalesce(a.anomaly_label, 'Normal') as anomaly_label,
  ft.first_tag_alpha,
  coalesce(nullif(trim(cast(up.title as varchar)), ''), ('[' || rp.post_type_name || ' #' || rp.post_id || ']')) as safe_title,
  case
    when up.tags is null then '(no tags)'
    else replace(replace(up.tags, '<', '['), '>', ']')
  end as tags_bracketed,
  (rp.composite_score - avg(rp.composite_score) over (partition by rp.post_type_name))
    / nullif(stddev_pop(rp.composite_score) over (partition by rp.post_type_name), 0) as composite_z_by_type,
  (select count(*) from badges b where b.userid = rp.user_id and b.class = 1) as gold_badges,
  (select count(*) from badges b where b.userid = rp.user_id and b.class = 2) as silver_badges,
  (select count(*) from badges b where b.userid = rp.user_id and b.class = 3) as bronze_badges,
  ur.posts_considered,
  ur.questions_cnt,
  ur.answers_cnt,
  ur.avg_net_per_view,
  ur.median_composite,
  ur.max_composite,
  ur.min_composite,
  qm.accepted_answer_id,
  qm.hours_to_accept
from top_posts rp
join active_users au on au.user_id = rp.user_id
left join user_rollup ur on ur.user_id = rp.user_id
left join anomalies a on a.post_id = rp.post_id
left join user_posts up on up.post_id = rp.post_id
left join first_tag ft on ft.post_id = rp.post_id
left join qa_metrics qm on qm.question_id = rp.post_id
where
  coalesce(rp.composite_score, -1e9) > (
    select coalesce(percentile_cont(0.25) within group (order by composite_score), -1e9)
    from ranked_posts
  )
  and (
    ur.has_github = 1
    or (rp.post_type_name = 'Question' and coalesce(rp.tag_count,0) between 2 and 6)
    or (rp.post_type_name <> 'Question' and coalesce(rp.upvotes,0) >= coalesce(rp.downvotes,0))
  )
order by
  rp.global_rank,
  rp.composite_score desc,
  rp.creationdate desc,
  rp.post_id
limit 500;