-- {"query": "961.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3300} 
with recent_users as (
  select
    u.id,
    u.displayname,
    u.reputation,
    u.creationdate,
    coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region,
    date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= (select max(p.creationdate) - interval '2 years' from posts p)
),
user_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where p.posttypeid = 1) as q_count,
    count(*) filter (where p.posttypeid = 2) as a_count,
    sum(coalesce(p.score, 0)) as total_post_score,
    sum(coalesce(p.viewcount, 0)) as total_views,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
vote_agg as (
  select
    v.userid as user_id,
    sum(case when vt.name = 'UpMod' then 1 else 0 end) as upvotes_cast,
    sum(case when vt.name = 'DownMod' then 1 else 0 end) as downvotes_cast,
    sum(case when vt.name = 'Favorite' then 1 else 0 end) as favorites_cast,
    sum(case when vt.name in ('BountyStart','BountyClose') then coalesce(v.bountyamount,0) else 0 end) as bounty_total_cast
  from votes v
  join votetypes vt on vt.id = v.votetypeid
  group by v.userid
),
badge_agg as (
  select
    b.userid as user_id,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
comment_agg as (
  select
    c.userid as user_id,
    count(*) as comments_count,
    sum(coalesce(c.score,0)) as comments_score,
    max(c.creationdate) as last_comment_date
  from comments c
  where c.userid is not null
  group by c.userid
),
accepted_answers as (
  select
    a.owneruserid as user_id,
    count(*) as accepted_answers_count,
    sum(coalesce(a.score,0)) as accepted_answers_score
  from posts q
  join posts a on a.id = q.acceptedanswerid
  where q.posttypeid = 1 and a.posttypeid = 2 and a.owneruserid is not null
  group by a.owneruserid
),
postlinks_graph as (
  select
    pl.postid,
    count(*) filter (where lt.name = 'Linked') as linked_edges,
    count(*) filter (where lt.name = 'Duplicate') as duplicate_edges
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid
  group by pl.postid
),
question_tag_counts as (
  select
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1 and p.owneruserid is not null and p.tags is not null and length(p.tags) > 2
),
top_tags as (
  select
    user_id,
    tagname,
    cnt,
    row_number() over (partition by user_id order by cnt desc, tagname) as rn
  from (
    select user_id, lower(tagname) as tagname, count(*) as cnt
    from question_tag_counts
    group by user_id, lower(tagname)
  ) s
),
user_top3_tags as (
  select user_id,
         array_agg(tagname order by rn) filter (where rn <= 3) as top3_tags
  from top_tags
  where rn <= 3
  group by user_id
),
post_edits as (
  select
    ph.userid as user_id,
    count(*) filter (where pht.name in ('Edit Title','Edit Body','Edit Tags','Rollback Title','Rollback Body','Rollback Tags','Suggested Edit Applied')) as edits_made,
    count(*) filter (where pht.name in ('Post Closed','Post Reopened','Post Deleted','Post Undeleted','Post Locked','Post Unlocked','Question Protected','Question Unprotected')) as modlike_actions,
    max(ph.creationdate) as last_edit_date,
    sum(
      case
        when ph.posthistorytypeid = 10 then 1
        else 0
      end
    ) as close_events
  from posthistory ph
  left join posthistorytypes pht on pht.id = ph.posthistorytypeid
  group by ph.userid
),
question_quality as (
  select
    p.owneruserid as user_id,
    count(*) as q_total,
    avg(coalesce(p.score,0)) as q_avg_score,
    percentile_cont(0.5) within group (order by coalesce(p.score,0)) as q_median_score,
    avg(case when p.viewcount is null or p.viewcount = 0 then null else p.score::numeric / nullif(p.viewcount,0) end) as q_score_per_view,
    sum(case when p.closeddate is not null then 1 else 0 end) as q_closed
  from posts p
  where p.posttypeid = 1 and p.owneruserid is not null
  group by p.owneruserid
),
answer_quality as (
  select
    p.owneruserid as user_id,
    count(*) as a_total,
    avg(coalesce(p.score,0)) as a_avg_score,
    percentile_cont(0.5) within group (order by coalesce(p.score,0)) as a_median_score
  from posts p
  where p.posttypeid = 2 and p.owneruserid is not null
  group by p.owneruserid
),
activity_windows as (
  select
    p.owneruserid as user_id,
    p.creationdate,
    count(*) over (partition by p.owneruserid order by p.creationdate range between interval '30 days' preceding and current row) as posts_last_30d,
    count(*) over (partition by p.owneruserid order by p.creationdate range between interval '7 days' preceding and current row) as posts_last_7d
  from posts p
  where p.owneruserid is not null
),
activity_snapshot as (
  select
    user_id,
    max(posts_last_30d) as max_posts_30d,
    max(posts_last_7d) as max_posts_7d,
    max(creationdate) as last_post_date
  from activity_windows
  group by user_id
),
recent_dupes as (
  select
    q.owneruserid as user_id,
    count(*) as duplicate_marks
  from postlinks pl
  join linktypes lt on lt.id = pl.linktypeid and lt.name = 'Duplicate'
  join posts q on q.id = pl.postid and q.posttypeid = 1 and q.owneruserid is not null
  where pl.creationdate >= (select coalesce(max(ph.creationdate), now() - interval '10 years') from posthistory ph)
  group by q.owneruserid
),
user_posts_ranked as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    p.score,
    row_number() over (partition by p.owneruserid order by p.score desc nulls last) as rn_by_score,
    row_number() over (partition by p.owneruserid order by p.creationdate desc nulls last) as rn_by_recency
  from posts p
  where p.owneruserid is not null
),
user_best_posts as (
  select
    upr.user_id,
    max(case when upr.rn_by_score = 1 then upr.post_id end) as best_post_id,
    max(case when upr.rn_by_recency = 1 then upr.post_id end) as latest_post_id
  from user_posts_ranked upr
  group by upr.user_id
),
normalized_user_stats as (
  select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.region,
    coalesce(ua.q_count,0) as q_count,
    coalesce(ua.a_count,0) as a_count,
    coalesce(ua.total_post_score,0) as total_post_score,
    coalesce(ua.total_views,0) as total_views,
    ua.last_post_activity,
    coalesce(va.upvotes_cast,0) as upvotes_cast,
    coalesce(va.downvotes_cast,0) as downvotes_cast,
    coalesce(va.favorites_cast,0) as favorites_cast,
    coalesce(va.bounty_total_cast,0) as bounty_total_cast,
    coalesce(ba.gold_badges,0) as gold_badges,
    coalesce(ba.silver_badges,0) as silver_badges,
    coalesce(ba.bronze_badges,0) as bronze_badges,
    coalesce(ba.tag_badges,0) as tag_badges,
    ba.last_badge_date,
    coalesce(ca.comments_count,0) as comments_count,
    coalesce(ca.comments_score,0) as comments_score,
    ca.last_comment_date,
    coalesce(aa.accepted_answers_count,0) as accepted_answers_count,
    coalesce(aa.accepted_answers_score,0) as accepted_answers_score,
    pq.q_total,
    pq.q_avg_score,
    pq.q_median_score,
    pq.q_score_per_view,
    pq.q_closed,
    aq.a_total,
    aq.a_avg_score,
    aq.a_median_score,
    pe.edits_made,
    pe.modlike_actions,
    pe.last_edit_date,
    pe.close_events,
    plg.linked_edges,
    plg.duplicate_edges,
    an.max_posts_30d,
    an.max_posts_7d,
    an.last_post_date,
    rd.duplicate_marks,
    ut.top3_tags,
    ubp.best_post_id,
    ubp.latest_post_id
  from recent_users ru
  left join user_activity ua on ua.user_id = ru.id
  left join vote_agg va on va.user_id = ru.id
  left join badge_agg ba on ba.user_id = ru.id
  left join comment_agg ca on ca.user_id = ru.id
  left join accepted_answers aa on aa.user_id = ru.id
  left join question_quality pq on pq.user_id = ru.id
  left join answer_quality aq on aq.user_id = ru.id
  left join post_edits pe on pe.user_id = ru.id
  left join activity_snapshot an on an.user_id = ru.id
  left join recent_dupes rd on rd.user_id = ru.id
  left join user_top3_tags ut on ut.user_id = ru.id
  left join user_best_posts ubp on ubp.user_id = ru.id
  left join (
    select p.owneruserid as user_id,
           sum(coalesce(pg.linked_edges,0)) as linked_edges,
           sum(coalesce(pg.duplicate_edges,0)) as duplicate_edges
    from posts p
    left join postlinks_graph pg on pg.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
  ) plg on plg.user_id = ru.id
),
scored as (
  select
    nus.*,
    case
      when coalesce(nus.q_count,0) + coalesce(nus.a_count,0) = 0 then null
      else round(
        (
          coalesce(nus.total_post_score,0)
          + 2 * coalesce(nus.accepted_answers_count,0)
          + 0.5 * coalesce(nus.upvotes_cast,0)
          - 0.7 * coalesce(nus.downvotes_cast,0)
          + 0.1 * coalesce(nus.comments_score,0)
          + 3 * coalesce(nus.gold_badges,0)
          + 2 * coalesce(nus.silver_badges,0)
          + 1 * coalesce(nus.bronze_badges,0)
        )::numeric
        / greatest(1, coalesce(nus.q_count,0) + coalesce(nus.a_count,0))
      , 3)
    end as engagement_score,
    case
      when nus.q_total is null then null
      when nus.q_total = 0 then null
      else round(100.0 * coalesce(nus.q_closed,0)::numeric / nullif(nus.q_total,0), 2)
    end as close_rate_pct
  from normalized_user_stats nus
),
ranked as (
  select
    s.*,
    dense_rank() over (order by engagement_score desc nulls last, reputation desc) as rank_overall,
    dense_rank() over (partition by region order by engagement_score desc nulls last) as rank_by_region,
    row_number() over (partition by cohort_month order by engagement_score desc nulls last) as rank_by_cohort,
    ntile(10) over (order by coalesce(engagement_score,0)) as engagement_decile
  from scored s
),
dedup as (
  select r.*,
         row_number() over (
           partition by lower(coalesce(nullif(trim(r.displayname), ''), 'anon'))
           order by r.reputation desc, r.engagement_score desc nulls last, r.user_id
         ) as name_row
  from ranked r
)
select
  d.user_id,
  d.displayname,
  d.reputation,
  d.cohort_month,
  d.region,
  d.q_count,
  d.a_count,
  d.total_post_score,
  d.accepted_answers_count,
  d.engagement_score,
  d.close_rate_pct,
  d.rank_overall,
  d.rank_by_region,
  d.rank_by_cohort,
  d.engagement_decile,
  coalesce(array_to_string(d.top3_tags, ', '), '(none)') as top_tags,
  d.best_post_id,
  d.latest_post_id,
  d.last_post_activity,
  d.last_post_date,
  d.last_comment_date,
  d.last_badge_date,
  case
    when d.engagement_score is null then 'new'
    when d.engagement_decile >= 9 then 'elite'
    when d.engagement_decile between 6 and 8 then 'active'
    when d.engagement_decile between 3 and 5 then 'casual'
    else 'inactive'
  end as activity_bucket
from dedup d
where d.name_row = 1
  and (
    d.engagement_score is not null
    or (d.q_count + d.a_count) > 0
    or coalesce(d.comments_count,0) > 0
  )
order by d.engagement_score desc nulls last, d.reputation desc, d.user_id
limit 500;