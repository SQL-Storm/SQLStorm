-- {"query": "606.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2892} 
with recent_activity as (
  select
    p.id as post_id,
    p.posttypeid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid,
    p.tags,
    p.title,
    p.lastactivitydate,
    coalesce(p.answercount, 0) as answercount,
    coalesce(p.commentcount, 0) as commentcount
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '180 days' from posts)
),
user_enrichment as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate as user_created,
    u.lastaccessdate,
    u.location,
    u.websiteurl,
    u.upvotes,
    u.downvotes,
    u.views as profile_views,
    row_number() over (order by reputation desc, id) as reputation_rank
  from users u
),
post_votes as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
    sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded,
    count(*) filter (where v.votetypeid in (10,12)) as destructive_votes
  from votes v
  where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
  group by v.postid
),
comment_aggs as (
  select
    c.postid,
    count(*) as comment_count,
    max(c.creationdate) as last_comment_date,
    sum(c.score) as comment_score_sum,
    avg(c.score) as comment_score_avg
  from comments c
  group by c.postid
),
link_graph as (
  select
    pl.postid,
    count(*) filter (where pl.linktypeid = 1) as linked_count,
    count(*) filter (where pl.linktypeid = 3) as duplicate_count,
    count(distinct pl.relatedpostid) as unique_related
  from postlinks pl
  where pl.creationdate >= (select max(creationdate) - interval '365 days' from postlinks)
  group by pl.postid
),
close_events as (
  select
    ph.postid,
    min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
    count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_undelete_events
  from posthistory ph
  group by ph.postid
),
tag_xplode as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
),
tag_stats as (
  select
    tx.post_id,
    array_agg(tx.tagname order by tx.tagname) as tag_array,
    min(t.count) as min_tag_popularity,
    max(t.count) as max_tag_popularity,
    avg(t.count) as avg_tag_popularity,
    count(*) as tag_count
  from tag_xplode tx
  left join tags t on lower(t.tagname) = lower(tx.tagname)
  group by tx.post_id
),
accepted_answer_age as (
  select
    q.id as question_id,
    a.id as answer_id,
    a.creationdate - q.creationdate as time_to_first_answer,
    aa.creationdate - q.creationdate as time_to_accepted_answer
  from posts q
  left join posts a
    on a.parentid = q.id
    and a.posttypeid = 2
  left join posts aa
    on aa.id = q.acceptedanswerid
  where q.posttypeid = 1
),
user_badge_brief as (
  select
    b.userid,
    count(*) as total_badges,
    count(*) filter (where b.class = 1) as gold_badges,
    count(*) filter (where b.class = 2) as silver_badges,
    count(*) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
recent_hot as (
  select
    ph.postid,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 52) as became_hot_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid = 53) as removed_hot_at,
    count(*) filter (where ph.posthistorytypeid = 52) as hot_entries
  from posthistory ph
  group by ph.postid
),
owner_activity as (
  select
    p.owneruserid as user_id,
    count(*) as posts_count,
    count(*) filter (where p.posttypeid = 1) as questions_count,
    count(*) filter (where p.posttypeid = 2) as answers_count,
    sum(coalesce(p.viewcount,0)) as total_views,
    sum(coalesce(p.score,0)) as total_post_score,
    max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
ranked_questions as (
  select
    q.id as question_id,
    q.title,
    q.creationdate,
    q.viewcount,
    q.score,
    q.answercount,
    q.commentcount,
    dense_rank() over (order by coalesce(q.viewcount,0) desc) as view_rank,
    dense_rank() over (order by coalesce(q.score,0) desc) as score_rank,
    ntile(10) over (order by coalesce(q.viewcount,0) desc) as view_decile,
    row_number() over (partition by date_trunc('month', q.creationdate) order by q.score desc nulls last) as monthly_top_rank
  from posts q
  where q.posttypeid = 1
),
question_quality as (
  select
    q.id as question_id,
    (coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0)) as net_votes,
    coalesce(pv.bounty_started,0) as bounty_started,
    coalesce(pv.bounty_awarded,0) as bounty_awarded,
    coalesce(ca.comment_score_sum,0) as comment_score_sum,
    coalesce(ca.comment_count,0) as comment_count,
    coalesce(lg.linked_count,0) as linked_count,
    coalesce(lg.duplicate_count,0) as duplicate_count,
    greatest(0, coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0))::numeric
      + least(10, coalesce(ca.comment_count,0))::numeric
      + log(1 + coalesce(q.viewcount,0))::numeric
      - 5 * (case when coalesce(lg.duplicate_count,0) > 0 then 1 else 0 end)
      + case when q.acceptedanswerid is not null then 3 else 0 end
      + least(10, coalesce(pv.bounty_awarded,0)/50.0)
      as quality_score
  from posts q
  left join post_votes pv on pv.postid = q.id
  left join comment_aggs ca on ca.postid = q.id
  left join link_graph lg on lg.postid = q.id
  where q.posttypeid = 1
),
recent_questions as (
  select
    ra.*,
    qs.quality_score,
    rs.view_rank,
    rs.score_rank,
    rs.view_decile
  from recent_activity ra
  join question_quality qs on qs.question_id = ra.id
  join ranked_questions rs on rs.question_id = ra.id
  where ra.posttypeid = 1
),
owner_context as (
  select
    rq.id as question_id,
    ue.user_id,
    ue.displayname,
    ue.reputation,
    ue.reputation_rank,
    ob.total_badges,
    ob.gold_badges,
    ob.silver_badges,
    ob.bronze_badges,
    oa.posts_count,
    oa.questions_count,
    oa.answers_count,
    oa.total_views as owner_total_views,
    oa.total_post_score as owner_total_post_score
  from recent_questions rq
  left join user_enrichment ue on ue.user_id = rq.owneruserid
  left join user_badge_brief ob on ob.userid = rq.owneruserid
  left join owner_activity oa on oa.user_id = rq.owneruserid
),
final_scored as (
  select
    rq.id as question_id,
    rq.title,
    rq.creationdate,
    rq.viewcount,
    rq.score,
    rq.answercount,
    rq.commentcount,
    rq.quality_score,
    oc.user_id as owner_user_id,
    oc.displayname as owner_displayname,
    coalesce(oc.reputation, 0) as owner_reputation,
    coalesce(oc.total_badges, 0) as owner_badges,
    rq.view_rank,
    rq.score_rank,
    rq.view_decile,
    ts.tag_array,
    ts.tag_count,
    ts.avg_tag_popularity,
    ce.first_closed_at,
    ce.last_reopened_at,
    rh.became_hot_at,
    rh.removed_hot_at,
    (case
      when ce.first_closed_at is not null and rh.became_hot_at is not null and ce.first_closed_at < rh.became_hot_at then 'ClosedBeforeHot'
      when rh.became_hot_at is not null then 'Hot'
      when ce.first_closed_at is not null then 'Closed'
      else 'Normal'
    end) as lifecycle_bucket,
    coalesce((select avg(aq.time_to_accepted_answer) from accepted_answer_age aq where aq.question_id = rq.id), interval '0') as time_to_accept,
    (select count(distinct pl.relatedpostid) from postlinks pl where pl.postid = rq.id) as distinct_links,
    (select sum(v2.bountyamount) from votes v2 where v2.postid = rq.id and v2.votetypeid in (8,9)) as total_bounty_flow
  from recent_questions rq
  left join owner_context oc on oc.question_id = rq.id
  left join tag_stats ts on ts.post_id = rq.id
  left join close_events ce on ce.postid = rq.id
  left join recent_hot rh on rh.postid = rq.id
),
ranked as (
  select
    fs.*,
    dense_rank() over (order by fs.quality_score desc, fs.viewcount desc nulls last, fs.score desc nulls last) as overall_rank,
    row_number() over (partition by fs.view_decile order by fs.quality_score desc, fs.viewcount desc nulls last) as decile_rank
  from final_scored fs
),
outliers as (
  select
    r.*,
    case
      when r.quality_score > (select avg(quality_score) + 2*stddev_pop(quality_score) from ranked) then 'HighOutlier'
      when r.quality_score < (select avg(quality_score) - 2*stddev_pop(quality_score) from ranked) then 'LowOutlier'
      else 'Normal'
    end as outlier_flag
  from ranked r
)
select
  o.question_id,
  coalesce(o.title, '[no title]') as title,
  o.owner_user_id,
  coalesce(o.owner_displayname, '[anonymous]') as owner_displayname,
  o.owner_reputation,
  o.owner_badges,
  o.creationdate,
  o.viewcount,
  o.score,
  o.answercount,
  o.commentcount,
  o.tag_array,
  o.tag_count,
  round(coalesce(o.avg_tag_popularity, 0)::numeric, 2) as avg_tag_popularity,
  o.quality_score,
  o.view_rank,
  o.score_rank,
  o.view_decile,
  o.overall_rank,
  o.decile_rank,
  o.lifecycle_bucket,
  o.first_closed_at,
  o.last_reopened_at,
  o.became_hot_at,
  o.removed_hot_at,
  o.time_to_accept,
  o.distinct_links,
  o.total_bounty_flow,
  o.outlier_flag
from outliers o
where (
    o.view_decile in (1,2,3,10)
    or o.lifecycle_bucket <> 'Normal'
    or o.outlier_flag <> 'Normal'
  )
  and (
    o.tag_array is null
    or exists (
      select 1
      from unnest(o.tag_array) t(tag)
      where lower(t.tag) similar to '(?i)(sql|postgres|performance|index|query|join)%'
    )
  )
order by o.overall_rank
limit 250;