with
-- basic user metrics
user_base as (
  select u.id,
         u.displayname,
         u.reputation,
         u.creationdate,
         u.lastaccessdate,
         coalesce(u.location,'<no location>') as location,
         greatest(u.upvotes,0) as upvotes,
         greatest(u.downvotes,0) as downvotes,
         u.views,
         (select count(*) from badges b where b.userid = u.id) as badges_total,
         (select count(*) from badges b where b.userid = u.id and b.class = 1) as badges_gold,
         (select count(*) from badges b where b.userid = u.id and b.class = 2) as badges_silver,
         (select count(*) from badges b where b.userid = u.id and b.class = 3) as badges_bronze
  from users u
  where u.reputation is not null
),
-- posts flattened with tag exploded (tags are like '<tag1><tag2>')
post_tag_exploded as (
  select p.id,
         p.owneruserid,
         p.posttypeid,
         p.parentid,
         p.title,
         p.body,
         p.tags,
         p.score,
         p.creationdate,
         p.acceptedanswerid,
         trim(t) as tag
  from posts p
  left join lateral (
    select unnest(string_to_array(substring(coalesce(p.tags,''),2, greatest(length(coalesce(p.tags,''))-2,0)), '><')) as t
  ) s on true
),
-- aggregate per user: counts, scores, avg lengths, tags they interact with
user_post_aggs as (
  select p.owneruserid as userid,
         count(*) filter (where p.posttypeid = 1) as q_count,
         count(*) filter (where p.posttypeid = 2) as a_count,
         coalesce(sum(p.score),0) as total_post_score,
         avg(length(coalesce(p.title,'')) + length(coalesce(p.body,''))) as avg_post_length,
         count(distinct p.id) as distinct_posts,
         string_agg(distinct nullif(pt.tag,''), ',' order by nullif(pt.tag,'')) as all_tags,
         max(p.creationdate) as last_post_date
  from posts p
  left join post_tag_exploded pt on pt.id = p.id
  group by p.owneruserid
),
-- votes and comment activity per user (as owner of the post that received them)
post_interactions as (
  select p.owneruserid as userid,
         count(v.postid) filter (where v.votetypeid = 2) as received_upvotes,
         count(v.postid) filter (where v.votetypeid = 3) as received_downvotes,
         coalesce(sum(v.bountyamount),0) as received_bounty_total,
         count(c.id) as comments_received
  from posts p
  left join votes v on v.postid = p.id
  left join comments c on c.postid = p.id
  group by p.owneruserid
),
-- recent hotness windowed: score velocity and answering efficiency
post_velocity as (
  select p.owneruserid as userid,
         sum(case when p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days' then 1 else 0 end) as posts_30d,
         sum(case when p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '7 days' then 1 else 0 end) as posts_7d,
         avg(case when p.posttypeid = 2 then extract(epoch from (p.creationdate - coalesce((select q.creationdate from posts q where q.id = p.parentid), p.creationdate))) end) filter (where p.posttypeid = 2) as avg_answer_latency_secs,
         sum(coalesce(p.score,0)) filter (where p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as score_30d
  from posts p
  group by p.owneruserid
),
-- nominate "influencers" by combining metrics; include correlated subquery: top accepted answers by user
user_top_answers as (
  select u.id as userid,
         (select count(*) from posts a where a.posttypeid = 2 and a.owneruserid = u.id and a.id in (select p.acceptedanswerid from posts p where p.acceptedanswerid is not null)) as accepted_as_answer_count,
         (select count(*) from posts a where a.posttypeid = 2 and a.owneruserid = u.id and a.score >= 10) as high_score_answers
  from users u
),
-- ranking users by composite score using window functions
user_ranked as (
  select ub.id,
         ub.displayname,
         ub.reputation,
         ub.creationdate,
         ub.lastaccessdate,
         ub.location,
         ub.upvotes,
         ub.downvotes,
         ub.views,
         ub.badges_total,
         ub.badges_gold,
         ub.badges_silver,
         ub.badges_bronze,
         upa.accepted_as_answer_count,
         upa.high_score_answers,
         upg.q_count,
         upg.a_count,
         upg.total_post_score,
         upg.avg_post_length,
         upg.all_tags,
         pi.received_upvotes,
         pi.received_downvotes,
         pi.received_bounty_total,
         pi.comments_received,
         pv.posts_30d,
         pv.posts_7d,
         pv.avg_answer_latency_secs,
         -- composite score (weighted, handling nulls)
         ((coalesce(ub.reputation,0) / NULLIF((select max(reputation) from users),0)) * 40
          + coalesce((upg.total_post_score),0) * 0.6
          + coalesce(upa.accepted_as_answer_count,0) * 5
          + coalesce(pi.received_upvotes,0) * 1.2
          + coalesce(pi.received_bounty_total,0) * 0.5
          + coalesce(pv.posts_30d,0) * 2
          - coalesce(pi.received_downvotes,0) * 0.8
          - coalesce(upa.high_score_answers,0) * 0.01
         ) as composite_score
  from user_base ub
  left join user_post_aggs upg on upg.userid = ub.id
  left join post_interactions pi on pi.userid = ub.id
  left join post_velocity pv on pv.userid = ub.id
  left join user_top_answers upa on upa.userid = ub.id
),
-- pick top 100 by composite_score and enrich with correlated tag-specific aggregates
top_candidates as (
  select ur.*,
         row_number() over (order by ur.composite_score desc NULLS LAST) as rn
  from user_ranked ur
  where ur.composite_score is not null
)
select
  tc.rn,
  tc.id as userid,
  tc.displayname,
  tc.reputation,
  tc.badges_total,
  tc.badges_gold,
  tc.badges_silver,
  tc.badges_bronze,
  tc.q_count,
  tc.a_count,
  tc.total_post_score,
  tc.avg_post_length,
  tc.all_tags,
  tc.received_upvotes,
  tc.received_downvotes,
  tc.posts_30d,
  tc.posts_7d,
  tc.accepted_as_answer_count,
  tc.high_score_answers,
  tc.avg_answer_latency_secs,
  round(tc.composite_score::numeric,3) as composite_score,
  -- correlated subquery: most recent high-scoring answer (title of parent question + snippet)
  (select substring(coalesce(a.body,'') from 1 for 200) || '...' from posts a where a.posttypeid = 2 and a.owneruserid = tc.id and a.score = (select max(a2.score) from posts a2 where a2.posttypeid=2 and a2.owneruserid = tc.id) limit 1) as top_answer_snippet,
  -- correlated: most interacted tag (tag with most posts by this user)
  (select t.tag from (
     select pt.tag, count(*) as cnt
     from posts p2
     left join post_tag_exploded pt on pt.id = p2.id
     where p2.owneruserid = tc.id and pt.tag is not null
     group by pt.tag
     order by cnt desc NULLS LAST
     limit 1
  ) t) as dominant_tag,
  -- boolean flags from set operators: has_recent_badge OR has_recent_high_score
  case when exists (select 1 from badges b where b.userid = tc.id and b.date > cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') then true else false end as got_badge_30d,
  case when exists (select 1 from posts p where p.owneruserid = tc.id and p.score >= 50 and p.creationdate > cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') then true else false end as has_big_score_last_year,
  -- complex NULL/COALESCE expression combining website, aboutme and profile image url
  coalesce(nullif(trim(tc.displayname),''), 'user_'||cast(tc.id as text)) || ' | ' ||
    coalesce(nullif(split_part(nullif(tc.all_tags,''),',',1),''), 'no-tag') ||
    ' ~ ' ||
    coalesce(nullif((select u.websiteurl from users u where u.id = tc.id),'') , 'no-website') as summary_line
from top_candidates tc
where tc.rn <= 100
order by tc.composite_score desc, tc.reputation desc;