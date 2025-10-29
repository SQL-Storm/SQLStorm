with
active_users as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.displayname), ''), concat('user#', cast(u.id as varchar))) as norm_displayname,
    nullif(trim(u.location), '') as location,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    row_number() over (order by u.reputation desc, u.id) as rn_global,
    row_number() over (partition by (case when nullif(trim(u.location), '') is null then 'Unknown' else lower(u.location) end)
                       order by u.reputation desc, u.id) as rn_by_loc
  from users u
  where u.reputation > 0
    and u.lastaccessdate > cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
top_users as (
  select * from active_users where rn_by_loc <= 50
  union all
  select * from active_users where rn_global <= 500
),
tu_posts as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    p.posttypeid,
    pt.name as post_type_name,
    p.creationdate,
    p.score,
    p.viewcount,
    p.commentcount,
    p.favoritecount,
    p.tags,
    case
      when p.tags is not null and length(p.tags) >= 2
        then string_to_array(substring(p.tags from 2 for greatest(length(p.tags)-2,0)), '><')
      else null
    end as tag_arr
  from posts p
  join posttypes pt on pt.id = p.posttypeid
  join top_users tu on tu.user_id = p.owneruserid
  where p.creationdate > tu.creationdate
),
user_post_stats as (
  select
    tu.user_id,
    count(*) filter (where tp.posttypeid = 1) as q_count,
    count(*) filter (where tp.posttypeid = 2) as a_count,
    avg(nullif(tp.score,0)) filter (where tp.posttypeid in (1,2)) as avg_score_nonzero,
    sum(greatest(tp.viewcount,0)) as total_views,
    sum(greatest(tp.commentcount,0)) as total_comments,
    sum(greatest(tp.favoritecount,0)) as total_favs,
    max(tp.creationdate) as last_post_date,
    min(tp.creationdate) as first_post_date
  from top_users tu
  left join tu_posts tp on tp.user_id = tu.user_id
  group by tu.user_id
),
user_vote_stats as (
  select
    tu.user_id,
    count(*) filter (where v.votetypeid = 2) as upvotes_received,
    count(*) filter (where v.votetypeid = 3) as downvotes_received,
    count(*) filter (where v.votetypeid = 8) as bounties_started,
    sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
  from top_users tu
  left join posts p on p.owneruserid = tu.user_id
  left join votes v on v.postid = p.id
  group by tu.user_id
),
user_badges as (
  select
    tu.user_id,
    count(*) as badge_count,
    count(*) filter (where b.class = 1) as gold_count,
    count(*) filter (where b.class = 2) as silver_count,
    count(*) filter (where b.class = 3) as bronze_count,
    count(distinct b.name) as distinct_badges,
    max(b.date) as last_badge_date
  from top_users tu
  left join badges b on b.userid = tu.user_id
  group by tu.user_id
),
user_top_tags as (
  select
    s.user_id,
    s.tname,
    s.cnt,
    row_number() over (partition by s.user_id order by s.cnt desc, s.tname) as rn
  from (
    select
      tp.user_id,
      lower(trim(tag)) as tname,
      count(*) as cnt
    from tu_posts tp
    join lateral unnest(tp.tag_arr) as tag on true
    where tp.posttypeid = 1
    group by tp.user_id, lower(trim(tag))
  ) s
),
user_link_graph as (
  select
    tu.user_id,
    count(distinct case when pl.linktypeid = 1 then pl.relatedpostid end) as linked_out,
    count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as duplicates_of,
    count(distinct case when rpl.linktypeid = 3 then rpl.postid end) as duplicates_to_me
  from top_users tu
  left join posts p on p.owneruserid = tu.user_id
  left join postlinks pl on pl.postid = p.id
  left join postlinks rpl on rpl.relatedpostid = p.id and rpl.linktypeid = 3
  group by tu.user_id
),
user_close_events as (
  select
    tu.user_id,
    count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopened_events,
    count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_undelete_events,
    count(*) filter (where ph.posthistorytypeid = 35) as migrated_away,
    count(*) filter (where ph.posthistorytypeid = 36) as migrated_here,
    count(*) filter (
      where ph.posthistorytypeid = 10
        and (ph.comment ~ '(^|\\D)(101|102|103|104|105)(\\D|$)' or ph.comment ~ '(^|\\D)(1|2|3|4|7|10|20)(\\D|$)')
    ) as closed_with_reason_hint
  from top_users tu
  left join posts p on p.owneruserid = tu.user_id
  left join posthistory ph on ph.postid = p.id
  group by tu.user_id
),
user_comment_profile as (
  select
    tu.user_id,
    count(*) as comment_count,
    avg(coalesce(c.score,0)) as avg_comment_score,
    percentile_cont(0.5) within group (order by length(c.text)) as p50_comment_len,
    max(length(c.text)) as max_comment_len
  from top_users tu
  left join comments c on c.userid = tu.user_id
  group by tu.user_id
),
user_activity_windows as (
  select
    tu.user_id,
    x.posts_last_30d,
    x.posts_last_365d,
    x.edits_last_90d
  from top_users tu
  left join lateral (
    select
      count(*) filter (where p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as posts_last_30d,
      count(*) filter (where p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') as posts_last_365d,
      count(*) filter (where ph.posthistorytypeid in (4,5,6,24) and ph.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days') as edits_last_90d
    from posts p
    left join posthistory ph on ph.postid = p.id
    where p.owneruserid = tu.user_id
  ) x on true
),
user_ranks as (
  select
    tu.user_id,
    ntile(100) over (order by coalesce(uvs.upvotes_received,0) - coalesce(uvs.downvotes_received,0) desc, tu.user_id) as ntile_net_votes,
    ntile(100) over (order by coalesce(ups.total_views,0) desc, tu.user_id) as ntile_views,
    ntile(100) over (order by coalesce(ubs.gold_count,0) desc, coalesce(ubs.silver_count,0) desc, coalesce(ubs.bronze_count,0) desc, tu.user_id) as ntile_badges
  from top_users tu
  left join user_vote_stats uvs on uvs.user_id = tu.user_id
  left join (
    select user_id, sum(total_views) as total_views
    from user_post_stats
    group by user_id
  ) ups on ups.user_id = tu.user_id
  left join user_badges ubs on ubs.user_id = tu.user_id
),
profile as (
  select
    tu.user_id,
    tu.norm_displayname,
    coalesce(nullif(tu.location,''), 'Unknown') as location,
    tu.reputation,
    tu.creationdate,
    tu.lastaccessdate,
    ups.q_count,
    ups.a_count,
    ups.avg_score_nonzero,
    ups.total_views,
    ups.total_comments,
    ups.total_favs,
    ups.first_post_date,
    ups.last_post_date,
    uvs.upvotes_received,
    uvs.downvotes_received,
    uvs.bounties_started,
    uvs.bounty_amount_total,
    ub.badge_count,
    ub.gold_count,
    ub.silver_count,
    ub.bronze_count,
    ub.distinct_badges,
    ub.last_badge_date,
    ulg.linked_out,
    ulg.duplicates_of,
    ulg.duplicates_to_me,
    uce.closed_events,
    uce.reopened_events,
    uce.delete_undelete_events,
    uce.migrated_away,
    uce.migrated_here,
    uce.closed_with_reason_hint,
    ucp.comment_count,
    ucp.avg_comment_score,
    ucp.p50_comment_len,
    ucp.max_comment_len,
    uaw.posts_last_30d,
    uaw.posts_last_365d,
    uaw.edits_last_90d,
    ur.ntile_net_votes,
    ur.ntile_views,
    ur.ntile_badges
  from top_users tu
  left join user_post_stats ups on ups.user_id = tu.user_id
  left join user_vote_stats uvs on uvs.user_id = tu.user_id
  left join user_badges ub on ub.user_id = tu.user_id
  left join user_link_graph ulg on ulg.user_id = tu.user_id
  left join user_close_events uce on uce.user_id = tu.user_id
  left join user_comment_profile ucp on ucp.user_id = tu.user_id
  left join user_activity_windows uaw on uaw.user_id = tu.user_id
  left join user_ranks ur on ur.user_id = tu.user_id
),
profile_top_tags as (
  select
    utt.user_id,
    string_agg(concat(utt.tname, ':', cast(utt.cnt as varchar)), ', ' order by utt.cnt desc, utt.tname) as top3_tags
  from user_top_tags utt
  where utt.rn <= 3
  group by utt.user_id
),
scored as (
  select
    p.*,
    ptt.top3_tags,
    (
      0.30 * ln(1 + coalesce(p.total_views,0)) +
      0.25 * ln(1 + greatest(coalesce(p.q_count,0) + coalesce(p.a_count,0), 0)) +
      0.15 * (coalesce(p.upvotes_received,0) - coalesce(p.downvotes_received,0)) / nullif(10 + coalesce(p.comment_count,0),0) +
      0.10 * (coalesce(p.gold_count,0) * 5 + coalesce(p.silver_count,0) * 2 + coalesce(p.bronze_count,0)) +
      0.05 * coalesce(p.edits_last_90d,0) +
      0.05 * coalesce(p.posts_last_30d,0) +
      0.05 * coalesce(p.posts_last_365d,0) / 12.0
    ) as composite_score
  from profile p
  left join profile_top_tags ptt on ptt.user_id = p.user_id
),
ranked as (
  select
    s.*,
    row_number() over (order by composite_score desc, reputation desc, user_id) as rank_global,
    row_number() over (partition by location order by composite_score desc, reputation desc, user_id) as rank_by_location
  from scored s
)
select
  r.user_id,
  r.norm_displayname as display_name,
  r.location,
  r.reputation,
  r.q_count,
  r.a_count,
  r.total_views,
  r.upvotes_received,
  r.downvotes_received,
  r.gold_count,
  r.silver_count,
  r.bronze_count,
  r.top3_tags,
  r.composite_score,
  r.rank_global,
  r.rank_by_location,
  case
    when coalesce(r.q_count,0) = 0 and coalesce(r.a_count,0) = 0 then 'Lurker'
    when coalesce(r.q_count,0) > 0 and coalesce(r.a_count,0) = 0 then 'Questioner'
    when coalesce(r.q_count,0) = 0 and coalesce(r.a_count,0) > 0 then 'Answerer'
    else 'All-rounder'
  end as contributor_archetype
from ranked r
left join (
  select user_id from user_post_stats where coalesce(q_count,0) + coalesce(a_count,0) > 0
  union
  select user_id from user_vote_stats where coalesce(upvotes_received,0) + coalesce(downvotes_received,0) > 0
) ok on ok.user_id = r.user_id
where ok.user_id is not null
  and (
    r.composite_score > -0.1
    or coalesce(r.gold_count,0) > 0
  )
order by r.rank_global
limit 500;