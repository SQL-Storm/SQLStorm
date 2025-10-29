-- {"query": "426.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3039}
with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.title,
    p.tags,
    p.owneruserid,
    p.score,
    p.viewcount,
    p.creationdate,
    p.lastactivitydate,
    u.displayname as owner_name,
    coalesce(u.location, 'Unknown') as owner_location,
    u.reputation,
    row_number() over (partition by p.owneruserid order by p.score desc, p.viewcount desc, p.creationdate desc) as rn_owner_top
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_count,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comment_count,
    max(c.creationdate) as last_comment_at,
    min(c.creationdate) as first_comment_at
  from comments c
  where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by c.postid
),
vote_stats as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by v.postid
),
ph_close as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
    max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopened_at,
    max(case when ph.posthistorytypeid in (35,36) then ph.creationdate end) as last_migration_at,
    max(ph.creationdate) as last_ph_at
  from posthistory ph
  where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by ph.postid
),
duplicates as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 3) as dup_mark_count,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    max(pl.creationdate) as last_link_at
  from postlinks pl
  where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
  group by pl.postid
),
tag_unpivot as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    and p.tags is not null
),
tag_top as (
  select
    t.tagname,
    count(distinct tu.post_id) as q_posts,
    sum(case when p.score >= 5 then 1 else 0 end) as hot_q,
    sum(p.viewcount) as total_views
  from tag_unpivot tu
  join posts p on p.id = tu.post_id
  join tags t on lower(t.tagname) = lower(tu.tagname)
  group by t.tagname
  having count(distinct tu.post_id) >= 10
),
user_badge_rank as (
  select
    b.userid,
    count(*) filter (where b.class = 1) as golds,
    count(*) filter (where b.class = 2) as silvers,
    count(*) filter (where b.class = 3) as bronzes,
    max(b.date) as last_badge_at,
    dense_rank() over (order by count(*) filter (where b.class = 1) desc, count(*) filter (where b.class = 2) desc, count(*) filter (where b.class = 3) desc) as badge_rank
  from badges b
  where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
  group by b.userid
),
owner_activity as (
  select
    ra.owneruserid as userid,
    count(*) as posts_count,
    count(*) filter (where ra.posttypeid = 1) as q_count,
    count(*) filter (where ra.posttypeid = 2) as a_count,
    avg(ra.score) as avg_score,
    sum(coalesce(vs.upvotes,0) - coalesce(vs.downvotes,0)) as net_votes_year,
    max(ra.lastactivitydate) as last_seen_post_at
  from recent_activity ra
  left join vote_stats vs on vs.postid = ra.post_id
  group by ra.owneruserid
),
owner_window as (
  select
    oa.*,
    sum(posts_count) over (order by coalesce(oa.avg_score,0) desc, oa.net_votes_year desc rows between unbounded preceding and current row) as cum_posts_by_avgscore,
    ntile(5) over (order by coalesce(oa.net_votes_year,0) desc) as net_vote_quintile
  from owner_activity oa
),
post_scored as (
  select
    ra.post_id,
    ra.posttypeid,
    ra.title,
    ra.tags,
    ra.owneruserid,
    ra.owner_name,
    ra.owner_location,
    ra.reputation,
    ra.score,
    ra.viewcount,
    ra.creationdate,
    ra.lastactivitydate,
    cs.comment_count,
    cs.pos_comment_count,
    vs.upvotes,
    vs.downvotes,
    vs.favorites,
    vs.bounty_started,
    vs.bounty_awarded,
    ph.close_events,
    ph.reopen_events,
    du.dup_mark_count,
    du.linked_count,
    greatest(coalesce(vs.last_vote_at, timestamp '1970-01-01 00:00:00'),
             coalesce(cs.last_comment_at, timestamp '1970-01-01 00:00:00'),
             coalesce(ph.last_ph_at, timestamp '1970-01-01 00:00:00'),
             coalesce(du.last_link_at, timestamp '1970-01-01 00:00:00'),
             coalesce(ra.lastactivitydate, timestamp '1970-01-01 00:00:00')) as last_signal_at,
    (case
      when ra.posttypeid = 1 then 1
      when ra.posttypeid = 2 then 0.8
      else 0.5
    end
    * (1 + ln(1 + greatest(ra.viewcount,0)))
    * (1 + coalesce(vs.upvotes,0) - 0.5 * coalesce(vs.downvotes,0))
    * (1 + 0.2 * coalesce(cs.comment_count,0))
    * (1 + 0.05 * coalesce(du.linked_count,0))
    * (1 + 0.1 * coalesce(vs.favorites,0))
    * (1 + 0.0005 * coalesce(vs.bounty_awarded,0))
    * (case when coalesce(ph.close_events,0) > coalesce(ph.reopen_events,0) then 0.6 else 1.0 end)) as engagement_score
  from recent_activity ra
  left join comment_stats cs on cs.postid = ra.post_id
  left join vote_stats vs on vs.postid = ra.post_id
  left join ph_close ph on ph.postid = ra.post_id
  left join duplicates du on du.postid = ra.post_id
),
ranked_posts as (
  select
    ps.*,
    dense_rank() over (order by ps.engagement_score desc, ps.score desc) as erank,
    row_number() over (partition by coalesce(ps.owneruserid, -1) order by ps.engagement_score desc, ps.creationdate desc) as rn_per_owner,
    sum(case when ps.posttypeid = 1 then 1 else 0 end) over () as total_questions,
    sum(case when ps.posttypeid = 2 then 1 else 0 end) over () as total_answers
  from post_scored ps
),
owner_enriched as (
  select
    ow.userid,
    ow.posts_count,
    ow.q_count,
    ow.a_count,
    ow.avg_score,
    ow.net_votes_year,
    ow.last_seen_post_at,
    ow.cum_posts_by_avgscore,
    ow.net_vote_quintile,
    u.displayname,
    u.reputation,
    coalesce(u.websiteurl, '') as websiteurl,
    case
      when u.location is null or trim(u.location) = '' then 'Unspecified'
      when position(',' in u.location) > 0 then split_part(u.location, ',', 1)
      else u.location
    end as location_norm,
    ubr.golds,
    ubr.silvers,
    ubr.bronzes,
    ubr.badge_rank
  from owner_window ow
  left join users u on u.id = ow.userid
  left join user_badge_rank ubr on ubr.userid = ow.userid
),
final_posts as (
  select
    rp.post_id,
    rp.posttypeid,
    rp.title,
    rp.tags,
    rp.owneruserid,
    rp.owner_name,
    rp.owner_location,
    rp.reputation as owner_rep_snapshot,
    rp.score,
    rp.viewcount,
    rp.creationdate,
    rp.lastactivitydate,
    rp.comment_count,
    rp.pos_comment_count,
    rp.upvotes,
    rp.downvotes,
    rp.favorites,
    rp.bounty_started,
    rp.bounty_awarded,
    rp.close_events,
    rp.reopen_events,
    rp.dup_mark_count,
    rp.linked_count,
    rp.last_signal_at,
    rp.engagement_score,
    rp.erank,
    rp.rn_per_owner,
    oe.net_vote_quintile,
    oe.badge_rank,
    case when rp.tags is null then 0 else 1 end as has_tags,
    case
      when rp.title is null then null
      else length(trim(regexp_replace(rp.title, '\s+', ' ', 'g')))
    end as title_len_norm
  from ranked_posts rp
  left join owner_enriched oe on oe.userid = rp.owneruserid
),
top_per_tag as (
  select
    tu.tagname,
    fp.post_id,
    fp.engagement_score,
    row_number() over (partition by tu.tagname order by fp.engagement_score desc, fp.creationdate desc) as rn_tag
  from tag_unpivot tu
  join final_posts fp on fp.post_id = tu.post_id
),
unioned as (
  select
    'TOP_OWNERS' as bucket,
    fp.*
  from final_posts fp
  where fp.rn_per_owner <= 3
  union all
  select
    'TOP_TAGS' as bucket,
    fp.*
  from final_posts fp
  where exists (
    select 1
    from top_per_tag tt
    where tt.post_id = fp.post_id
      and tt.rn_tag <= 2
  )
),
dedup as (
  select
    bucket,
    post_id,
    posttypeid,
    title,
    tags,
    owneruserid,
    owner_name,
    owner_location,
    owner_rep_snapshot,
    score,
    viewcount,
    creationdate,
    lastactivitydate,
    comment_count,
    pos_comment_count,
    upvotes,
    downvotes,
    favorites,
    bounty_started,
    bounty_awarded,
    close_events,
    reopen_events,
    dup_mark_count,
    linked_count,
    last_signal_at,
    engagement_score,
    erank,
    rn_per_owner,
    net_vote_quintile,
    badge_rank,
    has_tags,
    title_len_norm,
    row_number() over (partition by post_id order by case when bucket = 'TOP_OWNERS' then 1 else 2 end, engagement_score desc) as keep_one
  from unioned
)
select
  d.bucket,
  d.post_id,
  d.posttypeid,
  coalesce(d.title, '[no title]') as title,
  coalesce(d.tags, '[]') as tags,
  d.owneruserid,
  coalesce(d.owner_name, '[anonymous]') as owner_name,
  d.owner_location,
  d.owner_rep_snapshot,
  d.score,
  d.viewcount,
  d.creationdate,
  d.lastactivitydate,
  d.comment_count,
  d.pos_comment_count,
  d.upvotes,
  d.downvotes,
  d.favorites,
  d.bounty_started,
  d.bounty_awarded,
  d.close_events,
  d.reopen_events,
  d.dup_mark_count,
  d.linked_count,
  d.last_signal_at,
  round(cast(d.engagement_score as numeric), 2) as engagement_score,
  d.erank,
  d.rn_per_owner,
  d.net_vote_quintile,
  d.badge_rank,
  d.has_tags,
  d.title_len_norm,
  tt.tagname as sample_tag,
  coalesce(ts.q_posts, 0) as tag_q_posts,
  coalesce(ts.hot_q, 0) as tag_hot_q,
  coalesce(ts.total_views, 0) as tag_total_views
from dedup d
left join lateral (
  select tu.tagname
  from tag_unpivot tu
  where tu.post_id = d.post_id
  order by tu.tagname
  limit 1
) tt on true
left join tag_top ts on ts.tagname = tt.tagname
where d.keep_one = 1
order by d.engagement_score desc, d.creationdate desc
limit 250;