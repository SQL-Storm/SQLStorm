-- {"query": "906.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3288}
with recent_users as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.location,
    u.creationdate,
    u.upvotes,
    u.downvotes,
    coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365' day from users)
),
user_badge_rollup as (
  select
    b.userid,
    count(*) as total_badges,
    sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
    sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
    sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
    sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
    min(b.date) as first_badge_date,
    max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
questions as (
  select
    p.id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score,
    p.viewcount,
    p.answercount,
    p.title,
    p.tags,
    p.closeddate,
    p.acceptedanswerid
  from posts p
  where p.posttypeid = 1
),
answers as (
  select
    p.id,
    p.parentid as question_id,
    p.owneruserid as user_id,
    p.creationdate,
    p.score
  from posts p
  where p.posttypeid = 2
),
user_post_agg as (
  select
    u.id as user_id,
    count(case when p.posttypeid = 1 then 1 end) as q_count,
    count(case when p.posttypeid = 2 then 1 end) as a_count,
    sum(coalesce(p.score,0)) as post_score_sum,
    avg(nullif(p.score,0)) as avg_nonzero_post_score,
    max(p.creationdate) as last_post_date
  from users u
  left join posts p
    on p.owneruserid = u.id
  group by u.id
),
question_metrics as (
  select
    q.user_id,
    count(*) as questions_total,
    sum(case when q.closeddate is not null then 1 else 0 end) as questions_closed,
    sum(case when q.acceptedanswerid is not null then 1 else 0 end) as questions_with_accept,
    avg(q.viewcount) as avg_q_views,
    percentile_disc(0.9) within group (order by q.viewcount) as p90_q_views,
    avg(q.score) as avg_q_score
  from questions q
  group by q.user_id
),
answer_metrics as (
  select
    a.user_id,
    count(*) as answers_total,
    sum(case when a.score > 0 then 1 else 0 end) as answers_positive,
    sum(case when a.score < 0 then 1 else 0 end) as answers_negative,
    avg(a.score) as avg_a_score
  from answers a
  group by a.user_id
),
qa_interactions as (
  select
    q.user_id as asker_id,
    a.user_id as answerer_id,
    count(*) as qa_pairs,
    sum(case when a.score >= 1 then 1 else 0 end) as qa_pairs_helpful
  from answers a
  join questions q on q.id = a.question_id
  group by q.user_id, a.user_id
),
user_votes as (
  select
    v.userid as user_id,
    count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
    count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
  from votes v
  group by v.userid
),
post_votes as (
  select
    p.owneruserid as user_id,
    count(case when v.votetypeid = 2 then 1 end) as post_upvotes_received,
    count(case when v.votetypeid = 3 then 1 end) as post_downvotes_received
  from posts p
  left join votes v on v.postid = p.id
  group by p.owneruserid
),
tag_exploded as (
  select
    q.id as question_id,
    q.user_id,
    unnest(string_to_array(substring(q.tags from 2 for char_length(q.tags)-2), '><')) as tagname
  from questions q
  where q.tags is not null and char_length(q.tags) > 2
),
top_user_tags as (
  select
    user_id,
    tagname,
    count(*) as tag_count,
    row_number() over (partition by user_id order by count(*) desc, tagname) as rn
  from tag_exploded
  group by user_id, tagname
),
link_dupes as (
  select
    pl.postid as post_id,
    pl.relatedpostid as dup_of_id,
    pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
dup_metrics as (
  select
    p.owneruserid as user_id,
    count(*) as dup_marked_count,
    count(distinct ld.dup_of_id) as distinct_dup_targets
  from link_dupes ld
  join posts p on p.id = ld.post_id
  group by p.owneruserid
),
edits_cte as (
  select
    ph.postid,
    ph.userid,
    count(case when ph.posthistorytypeid in (4,5,6) then 1 end) as edit_count,
    min(case when ph.posthistorytypeid in (4,5,6) then ph.creationdate end) as first_edit,
    max(case when ph.posthistorytypeid in (4,5,6) then ph.creationdate end) as last_edit
  from posthistory ph
  group by ph.postid, ph.userid
),
user_edit_agg as (
  select
    e.userid as user_id,
    sum(e.edit_count) as total_edits,
    count(*) as edited_posts,
    max(e.last_edit) as last_edit_date
  from edits_cte e
  group by e.userid
),
activity_rank as (
  select
    u.id as user_id,
    coalesce(upa.q_count,0) + coalesce(upa.a_count,0) as post_count,
    ntile(10) over (order by coalesce(upa.q_count,0) + coalesce(upa.a_count,0) desc) as activity_decile
  from users u
  left join user_post_agg upa on upa.user_id = u.id
),
recent_commenters as (
  select
    c.userid as user_id,
    count(*) as comments_last_year,
    avg(c.score) as avg_comment_score
  from comments c
  where c.creationdate >= (select max(creationdate) - interval '365' day from comments)
  group by c.userid
),
string_fun as (
  select
    u.id as user_id,
    lower(coalesce(u.displayname, 'anon')) as dn_lower,
    char_length(coalesce(u.displayname, '')) as dn_len,
    case
      when lower(coalesce(u.location, '')) like '%united%states%' or lower(coalesce(u.location, '')) like '%usa%' then 'USA-ish'
      when lower(coalesce(u.location, '')) like '%india%' then 'India'
      when lower(coalesce(u.location, '')) like '%europe%' then 'Europe'
      when u.location is null then 'Unknown'
      else 'Other'
    end as region_bucket
  from users u
),
null_logic as (
  select
    u.id as user_id,
    coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
    coalesce(u.profileimageurl, 'none') as profileimageurl_norm,
    case when u.aboutme is null or char_length(trim(u.aboutme)) = 0 then 0 else 1 end as has_aboutme
  from users u
),
win_post_trends as (
  select
    p.owneruserid as user_id,
    p.id as post_id,
    cast(p.creationdate as date) as d,
    sum(p.score) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_score,
    count(*) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_posts
  from posts p
),
recent_trend as (
  select
    user_id,
    (max(cum_score) - min(cum_score)) as delta_score,
    (max(cum_posts) - min(cum_posts)) as delta_posts
  from win_post_trends
  where d >= (select cast(max(creationdate) as date) - 180 from posts)
  group by user_id
),
user_quality_score as (
  select
    u.id as user_id,
    coalesce(qa.questions_with_accept,0) as q_accepts,
    coalesce(am.answers_total,0) as a_count,
    coalesce(pv.post_upvotes_received,0) as up_rcv,
    coalesce(pv.post_downvotes_received,0) as dn_rcv,
    coalesce(ba.gold_badges,0) as golds,
    coalesce(ba.silver_badges,0) as silvers,
    coalesce(ba.bronze_badges,0) as bronzes,
    1.0 * coalesce(qa.questions_with_accept,0)
    + 0.3 * coalesce(am.answers_total,0)
    + 0.5 * coalesce(pv.post_upvotes_received,0)
    - 0.7 * coalesce(pv.post_downvotes_received,0)
    + 5 * coalesce(ba.gold_badges,0)
    + 2 * coalesce(ba.silver_badges,0)
    + 1 * coalesce(ba.bronze_badges,0) as quality_score
  from users u
  left join question_metrics qa on qa.user_id = u.id
  left join answer_metrics am on am.user_id = u.id
  left join post_votes pv on pv.user_id = u.id
  left join user_badge_rollup ba on ba.userid = u.id
),
user_pairs as (
  select
    r1.user_id as user_id,
    r2.user_id as peer_id,
    abs(r1.reputation - r2.reputation) as rep_gap
  from recent_users r1
  join recent_users r2 on r1.user_id <> r2.user_id
  where abs(r1.reputation - r2.reputation) <= 50
),
peer_similarity as (
  select
    up.user_id,
    count(*) as near_peers,
    avg(up.rep_gap) as avg_rep_gap
  from user_pairs up
  group by up.user_id
),
final_scores as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    s.region_bucket,
    n.location_norm,
    coalesce(ba.total_badges,0) as total_badges,
    coalesce(ba.tag_badges,0) as tag_badges,
    coalesce(qa.questions_total,0) as q_total,
    coalesce(qa.questions_closed,0) as q_closed,
    coalesce(qa.avg_q_views,0) as avg_q_views,
    coalesce(am.answers_total,0) as a_total,
    coalesce(ue.total_edits,0) as total_edits,
    coalesce(rv.comments_last_year,0) as comments_last_year,
    coalesce(pv.post_upvotes_received,0) as up_rcv,
    coalesce(pv.post_downvotes_received,0) as dn_rcv,
    coalesce(uv.upvotes_cast,0) as up_cast,
    coalesce(uv.downvotes_cast,0) as dn_cast,
    coalesce(dm.dup_marked_count,0) as dupes,
    coalesce(dm.distinct_dup_targets,0) as distinct_dupe_targets,
    coalesce(rt.delta_score,0) as delta_score_180d,
    coalesce(rt.delta_posts,0) as delta_posts_180d,
    coalesce(ps.near_peers,0) as near_peers,
    coalesce(ps.avg_rep_gap,0) as avg_rep_gap,
    coalesce(fav.tagname, '(none)') as top_tag,
    uq.quality_score,
    row_number() over (order by uq.quality_score desc, u.reputation desc, u.id) as quality_rank
  from users u
  left join string_fun s on s.user_id = u.id
  left join null_logic n on n.user_id = u.id
  left join user_badge_rollup ba on ba.userid = u.id
  left join question_metrics qa on qa.user_id = u.id
  left join answer_metrics am on am.user_id = u.id
  left join user_edit_agg ue on ue.user_id = u.id
  left join recent_commenters rv on rv.user_id = u.id
  left join post_votes pv on pv.user_id = u.id
  left join user_votes uv on uv.user_id = u.id
  left join dup_metrics dm on dm.user_id = u.id
  left join recent_trend rt on rt.user_id = u.id
  left join peer_similarity ps on ps.user_id = u.id
  left join user_quality_score uq on uq.user_id = u.id
  left join lateral (
    select tagname from top_user_tags tut
    where tut.user_id = u.id and tut.rn = 1
  ) fav on true
),
ranked as (
  select
    f.user_id,
    f.displayname,
    f.reputation,
    f.region_bucket,
    f.location_norm,
    f.total_badges,
    f.tag_badges,
    f.q_total,
    f.q_closed,
    f.avg_q_views,
    f.a_total,
    f.total_edits,
    f.comments_last_year,
    f.up_rcv,
    f.dn_rcv,
    f.up_cast,
    f.dn_cast,
    f.dupes,
    f.distinct_dupe_targets,
    f.delta_score_180d,
    f.delta_posts_180d,
    f.near_peers,
    f.avg_rep_gap,
    f.top_tag,
    f.quality_score,
    f.quality_rank,
    dense_rank() over (
      partition by case when f.q_total + f.a_total >= 10 then 'active' else 'casual' end
      order by f.quality_score desc
    ) as segment_rank
  from final_scores f
)
select
  r.user_id,
  r.displayname,
  r.reputation,
  r.region_bucket,
  r.location_norm,
  r.total_badges,
  r.tag_badges,
  r.q_total,
  r.q_closed,
  r.avg_q_views,
  r.a_total,
  r.total_edits,
  r.comments_last_year,
  r.up_rcv,
  r.dn_rcv,
  r.up_cast,
  r.dn_cast,
  r.dupes,
  r.distinct_dupe_targets,
  r.delta_score_180d,
  r.delta_posts_180d,
  r.near_peers,
  r.avg_rep_gap,
  r.top_tag,
  r.quality_score,
  r.quality_rank,
  r.segment_rank
from ranked r
where (
    r.region_bucket in ('USA-ish','India')
    and r.q_total > 0
    and (r.up_rcv - r.dn_rcv) >= 5
  )
  or (
    r.total_badges >= 10
    and r.delta_score_180d > 0
    and (lower(r.location_norm) like '%remote%' or r.location_norm = 'Unknown')
  )
order by r.quality_rank
limit 200;