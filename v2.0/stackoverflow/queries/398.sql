-- {"query": "398.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3057}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.lastaccessdate,
    coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    count(distinct date_trunc('day', b.date)) as badge_days,
    max(b.date) as last_badge_date
  from users u
  left join badges b
    on b.userid = u.id
  where u.creationdate >= (select max(creationdate) - interval '365' day from users)
  group by u.id, u.displayname, u.reputation, u.location, u.creationdate, u.lastaccessdate, coalesce(nullif(trim(u.websiteurl), ''), 'n/a')
),
user_posts as (
  select
    p.owneruserid as user_id,
    p.posttypeid,
    p.id as post_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.commentcount,
    p.favoritecount,
    p.closeddate,
    p.title,
    p.tags,
    case when p.posttypeid = 1 then 1 else 0 end as is_question,
    case when p.posttypeid = 2 then 1 else 0 end as is_answer
  from posts p
  where p.owneruserid is not null
    and p.owneruserid > 0
    and p.creationdate >= (select max(creationdate) - interval '365' day from posts)
),
question_metrics as (
  select
    up.owneruserid as user_id,
    count(*) filter (where up.posttypeid = 1) as q_count,
    sum(up.score) filter (where up.posttypeid = 1) as q_score,
    avg(nullif(up.viewcount,0)) filter (where up.posttypeid = 1) as avg_q_views,
    sum(case when up.closeddate is not null then 1 else 0 end) as q_closed,
    count(distinct up.id) filter (where up.posttypeid = 1 and up.acceptedanswerid is not null) as q_with_accepted
  from posts up
  where up.posttypeid = 1
    and up.owneruserid is not null and up.owneruserid > 0
    and up.creationdate >= (select max(creationdate) - interval '365' day from posts)
  group by up.owneruserid
),
answer_metrics as (
  select
    up.user_id,
    count(*) filter (where up.is_answer = 1) as a_count,
    sum(up.score) filter (where up.is_answer = 1) as a_score
  from user_posts up
  group by up.user_id
),
first_last_post as (
  select
    up.user_id,
    min(up.creationdate) as first_post_date,
    max(up.creationdate) as last_post_date
  from user_posts up
  group by up.user_id
),
comment_stats as (
  select
    p.owneruserid as user_id,
    count(c.id) as c_count,
    avg(c.score) as avg_c_score,
    max(c.creationdate) as last_comment_date
  from posts p
  join comments c on c.postid = p.id
  where p.owneruserid is not null and p.owneruserid > 0
    and c.creationdate >= (select max(creationdate) - interval '365' day from comments)
  group by p.owneruserid
),
vote_breakdown as (
  select
    p.owneruserid as user_id,
    count(*) filter (where v.votetypeid = 2) as upmods,
    count(*) filter (where v.votetypeid = 3) as downmods,
    count(*) filter (where v.votetypeid = 8) as bountystarts,
    sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
  from posts p
  join votes v on v.postid = p.id
  where p.owneruserid is not null and p.owneruserid > 0
    and v.creationdate >= (select max(creationdate) - interval '365' day from votes)
  group by p.owneruserid
),
dup_links as (
  select
    pl.relatedpostid as canonical_qid,
    count(*) as dup_count
  from postlinks pl
  join posts pq on pq.id = pl.relatedpostid and pq.posttypeid = 1
  where pl.linktypeid = 3
    and pl.creationdate >= (select max(creationdate) - interval '365' day from postlinks)
  group by pl.relatedpostid
),
user_dup_influence as (
  select
    p.owneruserid as user_id,
    sum(coalesce(d.dup_count,0)) as dup_influence
  from posts p
  left join dup_links d on d.canonical_qid = p.id
  where p.posttypeid = 1
    and p.owneruserid is not null and p.owneruserid > 0
  group by p.owneruserid
),
tag_explode as (
  select
    p.id as post_id,
    p.owneruserid as user_id,
    unnest(string_to_array(substring(p.tags from 2 for char_length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and p.owneruserid is not null and p.owneruserid > 0
    and p.creationdate >= (select max(creationdate) - interval '365' day from posts)
),
top_tags as (
  select
    te.user_id,
    substring(
      array_to_string(
        array_agg(t.tagname order by t.count desc NULLS LAST), ','
      ) from 1 for 1000
    ) as top5_tags
  from tag_explode te
  left join tags t on lower(t.tagname) = lower(te.tagname)
  group by te.user_id
),
edit_activity as (
  select
    p.owneruserid as user_id,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits_made,
    count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_events_on_posts,
    max(ph.creationdate) as last_edit_event
  from posts p
  left join posthistory ph on ph.postid = p.id
  where p.owneruserid is not null and p.owneruserid > 0
    and ph.creationdate >= (select max(creationdate) - interval '365' day from posthistory)
  group by p.owneruserid
),
user_baseline as (
  select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.location,
    ru.creationdate,
    ru.lastaccessdate,
    ru.websiteurl,
    ru.gold_badges, ru.silver_badges, ru.bronze_badges,
    ru.badge_days, ru.last_badge_date,
    coalesce(qm.q_count,0) as q_count,
    coalesce(qm.q_score,0) as q_score,
    coalesce(qm.avg_q_views,0) as avg_q_views,
    coalesce(qm.q_closed,0) as q_closed,
    coalesce(qm.q_with_accepted,0) as q_with_accepted,
    coalesce(am.a_count,0) as a_count,
    coalesce(am.a_score,0) as a_score,
    coalesce(cs.c_count,0) as c_count,
    coalesce(cs.avg_c_score,0) as avg_c_score,
    cs.last_comment_date,
    coalesce(vb.upmods,0) as upmods,
    coalesce(vb.downmods,0) as downmods,
    coalesce(vb.bountystarts,0) as bountystarts,
    coalesce(vb.bounty_total,0) as bounty_total,
    coalesce(ud.dup_influence,0) as dup_influence,
    tt.top5_tags,
    ea.edits_made, ea.mod_events_on_posts, ea.last_edit_event,
    fl.first_post_date, fl.last_post_date
  from recent_users ru
  left join question_metrics qm on qm.user_id = ru.user_id
  left join answer_metrics am on am.user_id = ru.user_id
  left join comment_stats cs on cs.user_id = ru.user_id
  left join vote_breakdown vb on vb.user_id = ru.user_id
  left join user_dup_influence ud on ud.user_id = ru.user_id
  left join top_tags tt on tt.user_id = ru.user_id
  left join edit_activity ea on ea.user_id = ru.user_id
  left join first_last_post fl on fl.user_id = ru.user_id
),
activity_windows as (
  select
    ub.*,
    row_number() over (order by coalesce(q_count + a_count,0) desc NULLS LAST) as rn_activity,
    ntile(10) over (order by coalesce(q_score + a_score + upmods - downmods,0) desc NULLS LAST) as decile_quality,
    avg(coalesce(q_score + a_score,0)) over () as avg_net_score_overall,
    stddev_pop(coalesce(q_score + a_score,0)) over () as std_net_score_overall,
    sum(coalesce(c_count,0)) over () as total_comments_overall,
    sum(coalesce(bounty_total,0)) over () as total_bounties_overall
  from user_baseline ub
),
ranked as (
  select
    aw.*,
    case
      when aw.std_net_score_overall > 0 then
        (coalesce(q_score + a_score,0) - aw.avg_net_score_overall) / aw.std_net_score_overall
      else 0
    end as z_net_score,
    coalesce(q_count,0) + coalesce(a_count,0) + greatest(coalesce(c_count,0)/10.0, 0) as activity_score,
    case when (coalesce(q_count,0) + coalesce(a_count,0)) <> 0
      then (coalesce(upmods,0) - coalesce(downmods,0)) / (coalesce(q_count,0) + coalesce(a_count,0))
      else 0 end as vote_margin_per_post,
    case when coalesce(q_closed,0) > 0 then 1 else 0 end as has_closed_q,
    case when position('sql' in coalesce(top5_tags, '')) > 0 then 1 else 0 end as is_sql_inclined
  from activity_windows aw
),
-- Replace ordered-set percentile_cont with percentile approximation using percentile_disc via subqueries per metric
outliers as (
  select
    r.*,
    pct_act.p95_activity,
    pct_z.p95_znet
  from ranked r
  left join (
    select
      percentile_disc(0.95) within group (order by activity_score) as p95_activity
    from ranked
  ) pct_act on 1=1
  left join (
    select
      percentile_disc(0.95) within group (order by z_net_score) as p95_znet
    from ranked
  ) pct_z on 1=1
),
dupe_suspects as (
  select
    ub.user_id,
    count(*) as suspected_dupe_events
  from posts q
  join posthistory ph
    on ph.postid = q.id
   and ph.posthistorytypeid = 10
   and (cast(ph.comment as varchar) similar to '%(1|101)%')
  join user_baseline ub on ub.user_id = q.owneruserid
  group by ub.user_id
),
final as (
  select
    o.user_id,
    o.displayname,
    o.reputation,
    coalesce(nullif(trim(o.location), ''), 'Unknown') as location,
    date_trunc('day', o.creationdate) as joined_on,
    coalesce(o.top5_tags, '') as top5_tags,
    o.q_count, o.a_count, o.c_count,
    o.q_score, o.a_score, (o.q_score + o.a_score) as total_score,
    o.upmods, o.downmods, (o.upmods - o.downmods) as net_votes,
    o.bounty_total,
    o.avg_q_views,
    o.q_closed, o.q_with_accepted,
    o.gold_badges, o.silver_badges, o.bronze_badges,
    o.badge_days,
    o.dup_influence,
    o.edits_made, o.mod_events_on_posts,
    o.first_post_date, o.last_post_date, o.last_comment_date, o.last_edit_event,
    o.activity_score,
    o.z_net_score,
    o.vote_margin_per_post,
    o.decile_quality,
    o.has_closed_q,
    o.is_sql_inclined,
    coalesce(ds.suspected_dupe_events,0) as suspected_dupe_events,
    case
      when o.activity_score >= o.p95_activity or o.z_net_score >= o.p95_znet then 'OUTLIER'
      when o.decile_quality >= 9 and o.vote_margin_per_post > 0.5 then 'ELITE'
      when o.decile_quality <= 2 and (o.has_closed_q = 1 or coalesce(ds.suspected_dupe_events,0) > 0) then 'RISK'
      else 'NORMAL'
    end as cohort,
    o.p95_activity,
    o.p95_znet
  from outliers o
  left join dupe_suspects ds on ds.user_id = o.user_id
)
select *
from final f
where
  (
    f.activity_score >
    coalesce((
      select percentile_disc(0.50) within group (order by fb.activity_score)
      from final fb
      where coalesce(nullif(trim(fb.location), ''), 'Unknown') = coalesce(nullif(trim(f.location), ''), 'Unknown')
    ), 0)
  )
  and (
    (f.q_count + f.a_count + f.c_count) > 0
    or f.cohort in ('ELITE','OUTLIER')
  )
order by
  cohort asc,
  z_net_score desc NULLS LAST,
  activity_score desc NULLS LAST,
  total_score desc NULLS LAST,
  user_id asc
limit 500;