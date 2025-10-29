with
recent_posts as (
  select
    p.id,
    p.posttypeid,
    p.parentid,
    p.acceptedanswerid,
    p.creationdate,
    p.score,
    p.viewcount,
    p.owneruserid,
    p.title,
    p.tags,
    coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, 'anonymous') as owner_name,
    u.reputation as owner_rep
  from posts p
  left join users u on u.id = p.owneruserid
  where p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '6 months' from posts)
),
user_activity as (
  select
    u.id as user_id,
    u.displayname,
    u.reputation,
    u.creationdate,
    u.lastaccessdate,
    coalesce(u.upvotes, 0) - coalesce(u.downvotes, 0) as net_votes,
    count(distinct b.id) filter (where b.class = 1) as gold_badges,
    count(distinct b.id) filter (where b.class = 2) as silver_badges,
    count(distinct b.id) filter (where b.class = 3) as bronze_badges,
    max(b.date) as last_badge_date
  from users u
  left join badges b on b.userid = u.id
  group by u.id, u.displayname, u.reputation, u.creationdate, u.lastaccessdate, u.upvotes, u.downvotes
),
post_votes as (
  select
    v.postid,
    sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
    sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
    sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
    sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
    count(*) as total_votes,
    min(v.creationdate) as first_vote_at,
    max(v.creationdate) as last_vote_at
  from votes v
  where v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from votes)
  group by v.postid
),
comment_stats as (
  select
    c.postid,
    count(*) as comment_count,
    avg(c.score) as avg_comment_score,
    max(c.creationdate) as last_comment_at,
    sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
    sum(case when c.score < 0 then 1 else 0 end) as neg_comments
  from comments c
  group by c.postid
),
post_linkage as (
  select
    pl.postid,
    sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
    sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_count,
    count(*) as all_links
  from postlinks pl
  group by pl.postid
),
question_answer_pairs as (
  select
    q.id as question_id,
    q.title as question_title,
    q.tags as question_tags,
    q.owneruserid as question_owner_id,
    q.score as question_score,
    q.viewcount as question_views,
    q.acceptedanswerid,
    a.id as answer_id,
    a.owneruserid as answer_owner_id,
    a.score as answer_score,
    a.creationdate as answer_created
  from posts q
  left join posts a on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
accepted_answer_latency as (
  select
    qap.question_id,
    min(case when a.id = qap.acceptedanswerid then a.creationdate end) as accepted_at,
    min(q.creationdate) as question_created,
    extract(epoch from (min(case when a.id = qap.acceptedanswerid then a.creationdate end) - min(q.creationdate)))/3600.0 as accept_latency_hours
  from question_answer_pairs qap
  join posts q on q.id = qap.question_id
  left join posts a on a.id = qap.answer_id
  group by qap.question_id
),
edits_cte as (
  select
    ph.postid,
    count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
    min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
    max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
    count(*) filter (where ph.posthistorytypeid = 10) as close_events,
    max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) end) as last_close_reason_id
  from posthistory ph
  group by ph.postid
),
close_reason_names as (
  select crt.id as reason_id, crt.name as reason_name from closereasontypes crt
),
tag_expansion as (
  select
    p.id as post_id,
    unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
    and length(p.tags) > 2
),
tag_rank as (
  select
    te.post_id,
    te.tag,
    rank() over (partition by te.post_id order by t.count desc nulls last, te.tag) as tag_popularity_rank,
    t.count as global_tag_count
  from tag_expansion te
  left join tags t on t.tagname = te.tag
),
post_quality as (
  select
    rp.id as post_id,
    rp.posttypeid,
    rp.creationdate,
    rp.owneruserid,
    rp.owner_name,
    rp.owner_rep,
    coalesce(pv.upvotes,0) as upvotes,
    coalesce(pv.downvotes,0) as downvotes,
    coalesce(pv.favorites,0) as favorites,
    coalesce(pv.bounty_total,0) as bounty_total,
    coalesce(cs.comment_count,0) as comment_count,
    coalesce(cs.avg_comment_score,0) as avg_comment_score,
    coalesce(pl.duplicate_count,0) as dup_count,
    coalesce(pl.linked_count,0) as link_count,
    coalesce(ec.edit_count,0) as edit_count,
    case when rp.viewcount is null or rp.viewcount = 0 then null
         else round((coalesce(pv.upvotes,0) - coalesce(pv.downvotes,0)) / nullif(rp.viewcount,0), 6)
    end as score_per_view,
    round(
      coalesce(pv.upvotes,0) * 2
      - coalesce(pv.downvotes,0) * 1.5
      + coalesce(pv.favorites,0) * 0.5
      + least(coalesce(cs.comment_count,0), 20) * 0.1
      - least(coalesce(ec.edit_count,0), 10) * 0.2
      + case when rp.posttypeid = 1 then 1 else 0 end * 0.3
      + case when rp.owner_rep >= 10000 then 0.2 else 0 end
    , 4) as quality_score,
    ec.close_events,
    ec.last_close_reason_id,
    crn.reason_name as last_close_reason_name
  from recent_posts rp
  left join post_votes pv on pv.postid = rp.id
  left join comment_stats cs on cs.postid = rp.id
  left join post_linkage pl on pl.postid = rp.id
  left join edits_cte ec on ec.postid = rp.id
  left join close_reason_names crn on crn.reason_id = ec.last_close_reason_id
),
user_rollup as (
  select
    pq.owneruserid as user_id,
    count(*) as posts_count,
    avg(pq.quality_score) as avg_quality_score,
    sum(case when pq.posttypeid = 1 then 1 else 0 end) as question_count,
    sum(case when pq.posttypeid = 2 then 1 else 0 end) as answer_count,
    max(pq.creationdate) as last_post_at
  from post_quality pq
  group by pq.owneruserid
),
-- compute p90 without ordered-set aggregate with OVER: use percentile_disc on aggregated set per whole table
overall_p90 as (
  select
    percentile_disc(0.9) within group (order by quality_score) as p90_quality
  from post_quality
  where quality_score is not null
),
post_ranked as (
  select
    pq.*,
    row_number() over (partition by pq.posttypeid order by pq.quality_score desc nulls last, pq.creationdate desc) as rn_by_type,
    op.p90_quality,
    dense_rank() over (order by pq.quality_score desc nulls last) as dense_rnk
  from post_quality pq
  cross join overall_p90 op
),
top_tags as (
  select
    tr.post_id,
    string_agg(tr.tag, ',' order by tr.tag) filter (where tr.tag_popularity_rank <= 3) as top3_tags,
    max(tr.global_tag_count) filter (where tr.tag_popularity_rank = 1) as top_tag_global_count
  from tag_rank tr
  group by tr.post_id
),
accepted_latency_join as (
  select
    a.question_id,
    a.accept_latency_hours
  from accepted_answer_latency a
)
select
  pr.id as post_id,
  pr.posttypeid,
  coalesce(pr.title, '(no title)') as title,
  pr.owner_name,
  pr.owner_rep,
  pr.score,
  pr.viewcount,
  pq.upvotes,
  pq.downvotes,
  pq.favorites,
  pq.bounty_total,
  pq.comment_count,
  pq.avg_comment_score,
  pq.link_count,
  pq.dup_count,
  pq.edit_count,
  coalesce(tt.top3_tags, '') as top3_tags,
  coalesce(al.accept_latency_hours, null) as accept_latency_hours,
  pq.score_per_view,
  pq.quality_score,
  ua.displayname as user_displayname,
  ua.net_votes as user_net_votes,
  ua.gold_badges,
  ua.silver_badges,
  ua.bronze_badges,
  ur.posts_count as user_posts_in_window,
  ur.avg_quality_score as user_avg_quality_in_window,
  pq.close_events,
  pq.last_close_reason_name,
  pr.creationdate,
  pr.acceptedanswerid,
  pr.parentid,
  pr.owneruserid,
  pr.tags,
  pr.title as raw_title,
  cast(pr.id as text) || ':' || coalesce(replace(lower(pr.title), ' ', '_'), 'untitled') as synthetic_key,
  case
    when pq.quality_score >= pq.p90_quality then 'top_10_percent'
    when pq.quality_score is null then 'no_signal'
    else 'normal'
  end as quality_bucket
from post_ranked pq
join recent_posts pr on pr.id = pq.post_id
left join user_activity ua on ua.user_id = pr.owneruserid
left join user_rollup ur on ur.user_id = pr.owneruserid
left join top_tags tt on tt.post_id = pr.id
left join accepted_latency_join al on al.question_id = pr.id
where (
    pq.rn_by_type <= 100
    or (pq.quality_score is not null and pq.quality_score >= pq.p90_quality)
    or (pq.downvotes > pq.upvotes and coalesce(pq.score_per_view, -1) < 0)
  )
and not exists (
  select 1
  from posts pchild
  where pchild.parentid = pr.id
    and pchild.posttypeid = 2
    and coalesce(pchild.score, 0) > 1000
)
and (
  pr.tags is null
  or position('java' in lower(pr.tags)) > 0
  or position('python' in lower(pr.tags)) > 0
)
order by
  case when pq.quality_score is null then 1 else 0 end,
  pq.dense_rnk,
  pr.creationdate desc
limit 500;