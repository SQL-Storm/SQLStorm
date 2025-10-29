-- {"query": "936.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3526} 
with
-- recent active users with weighted activity and name shards
active_users as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.displayname), ''), concat('user#', u.id::varchar)) as display_name,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    u.location,
    u.websiteurl,
    greatest(date_part('epoch', now() - u.creationdate), 1) as account_age_sec,
    (u.upvotes - coalesce(u.downvotes, 0)) as net_votes,
    u.views,
    -- derive a stable shard for join skew tests
    mod(u.id, 16) as user_shard,
    -- recentness weight: newer activity higher, older accounts slightly discounted
    exp(-least(3650, extract(epoch from (now() - u.lastaccessdate)) / 86400.0) / 180.0) *
    (1.0 + ln(1 + greatest(u.reputation, 0))) /
    (1.0 + ln(1 + greatest(date_part('epoch', now() - u.creationdate) / 86400.0, 1))) as recency_weight
  from users u
  where u.reputation >= 1
),
-- posts in the last N years with derived metrics and tag parsing
recent_posts as (
  select
    p.id as post_id,
    p.posttypeid,
    p.owneruserid,
    p.parentid,
    p.acceptedanswerid,
    p.creationdate,
    p.lastactivitydate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    split_part(t, '>', 1) as tag_item
  from posts p
  left join lateral unnest(
      case
        when p.tags is null then array[]::varchar[]
        when length(p.tags) <= 2 then array[]::varchar[]
        else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      end
  ) as t on true
  where p.creationdate >= now() - interval '5 years'
),
-- correlate votes with posts, compute vote intensities
vote_agg as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    count(*) as total_votes,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= now() - interval '5 years'
  group by v.postid
),
-- comments density per post
comment_agg as (
  select
    c.postid,
    count(*) as comment_count,
    avg(nullif(c.score, 0)) filter (where c.score is not null) as avg_comment_score,
    max(c.creationdate) as last_comment_at
  from comments c
  where c.creationdate >= now() - interval '5 years'
  group by c.postid
),
-- tag popularity with window ranking
tag_stats as (
  select
    rp.tag_item as tagname,
    count(distinct rp.post_id) as posts_with_tag,
    sum(coalesce(rp.viewcount,0)) as views_with_tag,
    sum(coalesce(rp.score,0)) as score_with_tag,
    dense_rank() over (order by count(distinct rp.post_id) desc nulls last, sum(coalesce(rp.score,0)) desc) as tag_rank_by_posts
  from recent_posts rp
  where rp.tag_item is not null
  group by rp.tag_item
),
-- join recent posts to owners, votes, comments
post_enriched as (
  select
    rp.post_id,
    rp.posttypeid,
    rp.owneruserid,
    rp.parentid,
    rp.acceptedanswerid,
    rp.creationdate,
    rp.lastactivitydate,
    rp.score,
    rp.viewcount,
    rp.answercount,
    rp.commentcount,
    rp.favoritecount,
    rp.closeddate,
    rp.title,
    rp.tag_item,
    au.display_name as owner_display_name,
    au.reputation as owner_reputation,
    au.user_shard,
    au.recency_weight,
    va.upvotes,
    va.downvotes,
    va.total_votes,
    va.bounty_started,
    va.bounty_awarded,
    ca.comment_count as recent_comment_count,
    ca.avg_comment_score,
    coalesce(va.last_vote_at, ca.last_comment_at, rp.lastactivitydate, rp.creationdate) as last_interaction_at
  from recent_posts rp
  left join active_users au on au.user_id = rp.owneruserid
  left join vote_agg va on va.postid = rp.post_id
  left join comment_agg ca on ca.postid = rp.post_id
),
-- compute per-user contribution stats with window functions
user_post_rollup as (
  select
    pe.owneruserid as user_id,
    count(*) filter (where pe.posttypeid = 1) as q_count,
    count(*) filter (where pe.posttypeid = 2) as a_count,
    sum(coalesce(pe.score,0)) as total_post_score,
    sum(coalesce(pe.viewcount,0)) as total_post_views,
    count(*) as total_posts,
    max(pe.last_interaction_at) as last_interaction_at,
    percentile_cont(0.5) within group (order by coalesce(pe.score,0)) as median_post_score,
    avg(coalesce(pe.score,0)) as avg_post_score,
    avg(greatest(0, extract(epoch from (now() - pe.creationdate))/86400.0)) as avg_post_age_days,
    -- "engagement" as combination of votes, comments, and answers for questions
    avg(
      coalesce(pe.total_votes,0) * 0.6 +
      coalesce(pe.recent_comment_count,0) * 0.3 +
      case when pe.posttypeid = 1 then coalesce(pe.answercount,0) * 0.5 else 0 end
    ) as engagement_score
  from post_enriched pe
  group by pe.owneruserid
),
-- determine duplicate/linked relationships and closure reasons
link_dupe as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as dupe_links,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links,
    count(*) as total_links,
    min(pl.creationdate) as first_link_at
  from postlinks pl
  where pl.creationdate >= now() - interval '5 years'
  group by pl.postid
),
closed_reasons as (
  select
    ph.postid,
    -- extract numeric from comment when stored as reason id
    max(
      nullif(
        regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'),
        ''
      )::int
    ) filter (where ph.posthistorytypeid = 10) as last_close_reason_id,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
    and ph.creationdate >= now() - interval '5 years'
  group by ph.postid
),
-- synthesize tag-level performance deciles
tag_perf as (
  select
    pe.tag_item as tagname,
    ntile(10) over (partition by pe.tag_item order by coalesce(pe.score,0) desc nulls last) as score_decile,
    ntile(10) over (partition by pe.tag_item order by coalesce(pe.viewcount,0) desc nulls last) as view_decile,
    pe.post_id,
    pe.score,
    pe.viewcount
  from post_enriched pe
  where pe.tag_item is not null
),
-- correlate accepted answers per user (correlated subquery)
user_accepts as (
  select
    u.id as user_id,
    (
      select count(*) 
      from posts a
      where a.posttypeid = 2
        and a.owneruserid = u.id
        and exists (
          select 1
          from posts q
          where q.posttypeid = 1
            and q.acceptedanswerid = a.id
        )
    ) as accepted_answers
  from users u
),
-- compute a normalized activity score per user with window normalization
user_activity as (
  select
    au.user_id,
    up.total_posts,
    coalesce(up.engagement_score, 0) as engagement_score,
    coalesce(ua.accepted_answers, 0) as accepted_answers,
    coalesce(up.total_post_score, 0) as total_post_score,
    coalesce(up.total_post_views, 0) as total_post_views,
    au.recency_weight,
    row_number() over (order by coalesce(up.total_post_score,0) desc nulls last) as rn_by_score,
    dense_rank() over (order by coalesce(up.total_post_views,0) desc nulls last) as dr_by_views
  from active_users au
  left join user_post_rollup up on up.user_id = au.user_id
  left join user_accepts ua on ua.user_id = au.user_id
),
-- final assembly of post-centric metrics with user and tag context
final_posts as (
  select
    pe.post_id,
    pe.posttypeid,
    pe.creationdate,
    pe.lastactivitydate,
    pe.title,
    pe.tag_item as tagname,
    pe.score,
    pe.viewcount,
    pe.answercount,
    pe.recent_comment_count,
    coalesce(ta.tag_rank_by_posts, 999999) as tag_rank_by_posts,
    ld.dupe_links,
    ld.related_links,
    cr.last_close_reason_id,
    cr.last_closed_at,
    cr.last_reopened_at,
    pe.owneruserid,
    pe.owner_display_name,
    pe.owner_reputation,
    ua.total_posts as owner_total_posts,
    ua.engagement_score as owner_engagement_score,
    ua.accepted_answers as owner_accepted_answers,
    ua.total_post_score as owner_total_post_score,
    ua.total_post_views as owner_total_post_views,
    ua.recency_weight as owner_recency_weight,
    -- composite post quality score
    (
      0.35 * coalesce(pe.score,0) +
      0.20 * coalesce(pe.viewcount,0) / nullif(1 + extract(epoch from (now() - pe.creationdate))/86400.0, 0) +
      0.15 * coalesce(pe.total_votes,0) +
      0.10 * coalesce(pe.recent_comment_count,0) +
      0.10 * coalesce(pe.answercount,0) +
      0.10 * coalesce(ua.engagement_score,0)
    ) as quality_score
  from post_enriched pe
  left join tag_stats ta on ta.tagname = pe.tag_item
  left join link_dupe ld on ld.postid = pe.post_id
  left join closed_reasons cr on cr.postid = pe.post_id
  left join user_activity ua on ua.user_id = pe.owneruserid
),
-- identify top posts per tag and user shard for set operations
top_posts as (
  select
    fp.*,
    row_number() over (
      partition by coalesce(fp.tagname, '_no_tag_'), coalesce(pe.user_shard, -1)
      order by fp.quality_score desc nulls last, fp.creationdate desc
    ) as rn_tag_shard
  from final_posts fp
  left join post_enriched pe on pe.post_id = fp.post_id
),
-- bottom posts for contrast using set operator
bottom_posts as (
  select
    fp.*,
    row_number() over (
      partition by coalesce(fp.tagname, '_no_tag_'), coalesce(pe.user_shard, -1)
      order by fp.quality_score asc nulls last, fp.creationdate asc
    ) as rn_tag_shard
  from final_posts fp
  left join post_enriched pe on pe.post_id = fp.post_id
),
-- union top and bottom extremes for benchmarking joins/set ops
extremes as (
  select * from top_posts where rn_tag_shard <= 3
  union all
  select * from bottom_posts where rn_tag_shard <= 3
),
-- deduplicate extreme posts and compute cross-extreme stats
extreme_rollup as (
  select
    e.tagname,
    count(*) as extreme_posts,
    avg(e.quality_score) as avg_extreme_quality,
    min(e.quality_score) as min_extreme_quality,
    max(e.quality_score) as max_extreme_quality,
    sum(case when e.posttypeid = 1 then 1 else 0 end) as questions,
    sum(case when e.posttypeid = 2 then 1 else 0 end) as answers
  from extremes e
  group by e.tagname
),
-- produce a synthetic category for close reasons
close_reason_dim as (
  select crt.id as close_reason_id, crt.name as close_reason_name
  from closereasontypes crt
)
select
  fp.post_id,
  fp.posttypeid,
  fp.creationdate,
  fp.lastactivitydate,
  fp.title,
  fp.tagname,
  fp.score,
  fp.viewcount,
  fp.answercount,
  fp.recent_comment_count,
  fp.tag_rank_by_posts,
  fp.dupe_links,
  fp.related_links,
  fp.last_close_reason_id,
  coalesce(crd.close_reason_name, case when fp.last_close_reason_id is null then 'Not Closed' else 'Unknown' end) as last_close_reason_name,
  fp.last_closed_at,
  fp.last_reopened_at,
  fp.owneruserid,
  fp.owner_display_name,
  fp.owner_reputation,
  fp.owner_total_posts,
  fp.owner_engagement_score,
  fp.owner_accepted_answers,
  fp.owner_total_post_score,
  fp.owner_total_post_views,
  round(fp.owner_recency_weight::numeric, 6) as owner_recency_weight,
  round(fp.quality_score::numeric, 4) as quality_score,
  er.extreme_posts,
  er.avg_extreme_quality,
  er.min_extreme_quality,
  er.max_extreme_quality,
  er.questions,
  er.answers,
  -- NULL logic and string expressions
  case
    when fp.tagname is null then '[untagged]'
    when length(fp.tagname) > 20 then substring(fp.tagname, 1, 17) || '...'
    else fp.tagname
  end as tag_display,
  coalesce(nullif(trim(fp.owner_display_name), ''), '[anonymous]') as owner_display
from final_posts fp
left join extreme_rollup er on er.tagname is not distinct from fp.tagname
left join close_reason_dim crd on crd.close_reason_id = fp.last_close_reason_id
where
  -- complicated predicates
  (fp.score >= 0 or fp.viewcount > 100)
  and coalesce(fp.owner_reputation, 0) >= 1
  and (
    fp.last_closed_at is null
    or (fp.last_reopened_at is not null and fp.last_reopened_at >= fp.last_closed_at)
  )
  and (
    fp.tag_rank_by_posts <= 100
    or (fp.tagname is null and fp.viewcount >= 1000)
  )
  and (
    -- correlated subquery: ensure owner has at least one bronze badge if they exist
    not exists (
      select 1 from users u2
      where u2.id = fp.owneruserid
        and not exists (
          select 1 from badges b where b.userid = u2.id and b.class = 3
        )
    )
  )
order by
  fp.quality_score desc nulls last,
  fp.viewcount desc nulls last,
  fp.creationdate desc
limit 500;