with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    extract(year from u.creationdate) as signup_year,
    date_trunc('month', u.creationdate) as signup_month
  from users u
  where u.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '2 years' from posts p)
),
badge_rollup as (
  select
    b.userid,
    sum(case when b.class = 1 then 1 else 0 end) as gold_count,
    sum(case when b.class = 2 then 1 else 0 end) as silver_count,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
    count(*) as total_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_posts as (
  select
    p.owneruserid as userid,
    sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
    sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
    sum(coalesce(p.score, 0)) as total_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.creationdate) as last_post_date,
    count(*) as post_count
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
accepted_stats as (
  select
    q.owneruserid as userid,
    count(*) filter (where a.id is not null) as answers_accepted_to_others,
    count(*) filter (where q.acceptedanswerid is not null) as questions_with_accepted
  from posts q
  left join posts a
    on a.id = q.acceptedanswerid
  where q.posttypeid = 1
  group by q.owneruserid
),
vote_agg as (
  select
    v.userid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_cast
  from votes v
  where v.userid is not null
  group by v.userid
),
received_votes as (
  select
    p.owneruserid as userid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started_on_posts,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded_on_posts
  from posts p
  join votes v on v.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
comment_agg as (
  select
    coalesce(c.userid, -1) as userid,
    count(*) as comments_made,
    sum(coalesce(c.score,0)) as comment_score,
    max(c.creationdate) as last_comment_date
  from comments c
  group by coalesce(c.userid, -1)
),
tag_activity as (
  select
    p.owneruserid as userid,
    lower(trim(regexp_replace(t, '\s+', ' '))) as tag,
    count(*) as tag_use_count,
    sum(coalesce(p.score,0)) as tag_score_sum
  from posts p
  cross join lateral unnest(
    case
      when p.posttypeid = 1 and p.tags is not null then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
      else cast(array[] as text[])
    end
  ) as t(t)
  where p.owneruserid is not null
  group by p.owneruserid, lower(trim(regexp_replace(t, '\s+', ' ')))
),
top_tag_per_user as (
  select distinct on (userid)
    userid,
    tag,
    tag_use_count,
    tag_score_sum
  from (
    select
      ta.*,
      row_number() over (partition by userid order by tag_use_count desc, tag_score_sum desc, tag asc) as rn
    from tag_activity ta
  ) x
  where rn = 1
  order by userid, tag_use_count desc, tag_score_sum desc, tag
),
postlink_agg as (
  select
    p.owneruserid as userid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_out,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as marked_duplicate
  from posts p
  left join postlinks pl on pl.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
close_events as (
  select
    ph.postid,
    min(ph.creationdate) as first_close_date,
    count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events
  from posthistory ph
  where ph.posthistorytypeid in (10,11)
  group by ph.postid
),
closed_post_agg as (
  select
    p.owneruserid as userid,
    count(*) as closed_count,
    min(ce.first_close_date) as earliest_close,
    sum(ce.close_votes_events) as close_events_total
  from posts p
  join close_events ce on ce.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
activity_calendar as (
  select
    p.owneruserid as userid,
    date_trunc('month', p.creationdate) as month_bucket,
    count(*) as posts_in_month
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_stats as (
  select
    userid,
    avg(posts_in_month) as avg_posts_per_month,
    stddev_pop(posts_in_month) as std_posts_per_month,
    max(posts_in_month) as peak_posts_per_month
  from activity_calendar
  group by userid
),
user_rank as (
  select
    ru.id as userid,
    dense_rank() over (order by coalesce(up.total_score,0) + coalesce(rv.upvotes_received,0) * 2 - coalesce(rv.downvotes_received,0) desc, coalesce(up.post_count,0) desc) as perf_rank
  from recent_users ru
  left join user_posts up on up.userid = ru.id
  left join received_votes rv on rv.userid = ru.id
),
norms as (
  select
    1.0 / nullif(max(coalesce(up.total_score,0)),0) as inv_max_score,
    1.0 / nullif(max(coalesce(rv.upvotes_received,0)),0) as inv_max_uprec,
    1.0 / nullif(max(coalesce(up.post_count,0)),0) as inv_max_posts
  from user_posts up
  full join received_votes rv on rv.userid = up.userid
),
scorecard as (
  select
    ru.id as userid,
    ru.displayname,
    ru.location_norm,
    coalesce(up.q_count,0) as questions,
    coalesce(up.a_count,0) as answers,
    coalesce(up.post_count,0) as posts,
    coalesce(up.total_score,0) as post_score,
    coalesce(rv.upvotes_received,0) as uprec,
    coalesce(rv.downvotes_received,0) as downrec,
    coalesce(va.upvotes_cast,0) as upcast,
    coalesce(va.downvotes_cast,0) as downcast,
    coalesce(va.favorites_cast,0) as favcast,
    coalesce(va.bounty_total_cast,0) as bounty_cast,
    coalesce(rv.bounty_started_on_posts,0) as bounty_started_on_posts,
    coalesce(rv.bounty_awarded_on_posts,0) as bounty_awarded_on_posts,
    coalesce(br.total_badges,0) as badges,
    coalesce(br.gold_count,0) as gold,
    coalesce(br.silver_count,0) as silver,
    coalesce(br.bronze_count,0) as bronze,
    coalesce(tp.tag, '(none)') as top_tag,
    coalesce(tp.tag_use_count,0) as top_tag_uses,
    coalesce(tp.tag_score_sum,0) as top_tag_score,
    coalesce(pa.linked_out,0) as linked_out,
    coalesce(pa.marked_duplicate,0) as marked_duplicate,
    coalesce(cpa.closed_count,0) as posts_closed,
    coalesce(asx.questions_with_accepted,0) as q_with_accept,
    coalesce(asx.answers_accepted_to_others,0) as a_marked_accepted,
    coalesce(cs.comments_made,0) as comments_made,
    coalesce(cs.comment_score,0) as comment_score,
    coalesce(act.avg_posts_per_month,0) as avg_ppm,
    coalesce(act.std_posts_per_month,0) as std_ppm,
    coalesce(act.peak_posts_per_month,0) as peak_ppm,
    ru.signup_year,
    ru.signup_month,
    ru.reputation,
    ru.creationdate,
    ru.lastaccessdate
  from recent_users ru
  left join user_posts up on up.userid = ru.id
  left join received_votes rv on rv.userid = ru.id
  left join vote_agg va on va.userid = ru.id
  left join badge_rollup br on br.userid = ru.id
  left join top_tag_per_user tp on tp.userid = ru.id
  left join postlink_agg pa on pa.userid = ru.id
  left join closed_post_agg cpa on cpa.userid = ru.id
  left join accepted_stats asx on asx.userid = ru.id
  left join comment_agg cs on cs.userid = ru.id
  left join activity_stats act on act.userid = ru.id
),
scored as (
  select
    s.*,
    (
      coalesce(n.inv_max_score, 0) * greatest(s.post_score, 0)
      + 2.0 * coalesce(n.inv_max_uprec, 0) * greatest(s.uprec, 0)
      + 0.5 * coalesce(n.inv_max_posts, 0) * greatest(s.posts, 0)
      + 0.1 * coalesce(s.badges, 0)
      - 0.25 * coalesce(s.downrec, 0)
      - 0.1 * coalesce(s.posts_closed, 0)
    ) as composite_score,
    case
      when s.reputation >= 100000 then 'Legend'
      when s.reputation >= 50000 then 'Elite'
      when s.reputation >= 20000 then 'Expert'
      when s.reputation >= 5000 then 'Advanced'
      when s.reputation >= 1000 then 'Intermediate'
      else 'Newbie'
    end as rep_band,
    case when lower(s.top_tag) like '%sql%' then 1 else 0 end as is_sql_inclined
  from scorecard s
  cross join norms n
),
ranked as (
  select
    sc.*,
    row_number() over (order by composite_score desc nulls last, reputation desc, lastaccessdate desc) as overall_rank,
    rank() over (partition by rep_band order by composite_score desc nulls last) as rank_in_band,
    percent_rank() over (order by composite_score) as pct_rank,
    ntile(10) over (order by composite_score desc nulls last) as decile
  from scored sc
),
band_summaries as (
  select
    rep_band,
    count(*) as users_in_band,
    avg(composite_score) as avg_comp,
    percentile_cont(0.5) within group (order by composite_score) as median_comp
  from ranked
  group by rep_band
),
final_set as (
  select
    r.userid,
    r.displayname,
    r.location_norm,
    r.rep_band,
    r.is_sql_inclined,
    r.overall_rank,
    r.rank_in_band,
    r.decile,
    r.pct_rank,
    r.composite_score,
    r.reputation,
    r.questions,
    r.answers,
    r.posts,
    r.post_score,
    r.uprec,
    r.downrec,
    r.upcast,
    r.downcast,
    r.favcast,
    r.badges,
    r.gold,
    r.silver,
    r.bronze,
    r.top_tag,
    r.top_tag_uses,
    r.top_tag_score,
    r.linked_out,
    r.marked_duplicate,
    r.posts_closed,
    r.q_with_accept,
    r.a_marked_accepted,
    r.comments_made,
    r.comment_score,
    r.avg_ppm,
    r.std_ppm,
    r.peak_ppm,
    r.signup_year,
    r.signup_month,
    r.creationdate,
    r.lastaccessdate
  from ranked r
  where (r.is_sql_inclined = 1 or r.rep_band in ('Elite','Legend'))
),
other_active as (
  select
    u.id as userid,
    u.displayname,
    coalesce(up.post_count,0) as posts,
    row_number() over (partition by coalesce(u.location, 'Unknown') order by coalesce(up.post_count,0) desc, u.reputation desc) as rn_loc
  from users u
  left join user_posts up on up.userid = u.id
  where u.lastaccessdate > cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
)
select *
from final_set
union all
select
  oa.userid,
  oa.displayname,
  coalesce(nullif(trim((select location from users where id = oa.userid)), ''), 'Unknown') as location_norm,
  'ActiveRecent' as rep_band,
  case when lower(coalesce((select tags from posts where owneruserid = oa.userid and posttypeid = 1 order by creationdate desc limit 1), '')) like '%sql%' then 1 else 0 end as is_sql_inclined,
  cast(null as bigint) as overall_rank,
  cast(null as bigint) as rank_in_band,
  cast(null as bigint) as decile,
  cast(null as double precision) as pct_rank,
  cast(null as double precision) as composite_score,
  (select reputation from users where id = oa.userid) as reputation,
  cast(null as integer) as questions,
  cast(null as integer) as answers,
  oa.posts as posts,
  cast(null as bigint) as post_score,
  cast(null as integer) as uprec,
  cast(null as integer) as downrec,
  cast(null as integer) as upcast,
  cast(null as integer) as downcast,
  cast(null as integer) as favcast,
  cast(null as integer) as badges,
  cast(null as integer) as gold,
  cast(null as integer) as silver,
  cast(null as integer) as bronze,
  cast(null as text) as top_tag,
  cast(null as integer) as top_tag_uses,
  cast(null as bigint) as top_tag_score,
  cast(null as integer) as linked_out,
  cast(null as integer) as marked_duplicate,
  cast(null as integer) as posts_closed,
  cast(null as integer) as q_with_accept,
  cast(null as integer) as a_marked_accepted,
  cast(null as integer) as comments_made,
  cast(null as bigint) as comment_score,
  cast(null as double precision) as avg_ppm,
  cast(null as double precision) as std_ppm,
  cast(null as bigint) as peak_ppm,
  extract(year from (select creationdate from users where id = oa.userid)) as signup_year,
  date_trunc('month', (select creationdate from users where id = oa.userid)) as signup_month,
  (select creationdate from users where id = oa.userid) as creationdate,
  (select lastaccessdate from users where id = oa.userid) as lastaccessdate
from other_active oa
where oa.rn_loc <= 3
order by rep_band desc, composite_score desc nulls last, overall_rank nulls last, reputation desc, lastaccessdate desc
limit 500;