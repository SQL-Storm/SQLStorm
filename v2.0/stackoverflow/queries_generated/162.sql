-- {"query": "162.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3094} 
with
recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
         date_trunc('month', u.creationdate) as created_month
  from users u
  where u.creationdate >= now() - interval '5 years'
),
user_badge_rollup as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
user_post_activity as (
  select p.owneruserid as user_id,
         sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
         sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
         sum(coalesce(p.score,0)) as total_post_score,
         sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as total_question_views,
         max(p.lastactivitydate) as last_post_activity
  from posts p
  where p.owneruserid is not null
  group by p.owneruserid
),
qa_ratio as (
  select user_id,
         q_count,
         a_count,
         case when q_count = 0 then null else a_count::numeric / nullif(q_count,0) end as a_per_q
  from user_post_activity
),
post_votes as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  group by v.postid
),
user_vote_rollup as (
  select p.owneruserid as user_id,
         sum(coalesce(pv.upvotes,0)) as recv_upvotes,
         sum(coalesce(pv.downvotes,0)) as recv_downvotes,
         sum(coalesce(pv.bounty_awarded,0)) as recv_bounty
  from posts p
  left join post_votes pv on pv.postid = p.id
  where p.owneruserid is not null
  group by p.owneruserid
),
question_quality as (
  select q.id as question_id,
         q.owneruserid as user_id,
         q.score as q_score,
         q.viewcount as q_views,
         q.answercount as q_answers,
         (select count(*) from comments c where c.postid = q.id) as q_comments,
         (select count(*) from postlinks pl where pl.postid = q.id and pl.linktypeid = 3) as dup_marks,
         coalesce((select 1 from posts a where a.id = q.acceptedanswerid), 0) as has_accepted,
         greatest(1, coalesce(q.viewcount,0)) as view_guard
  from posts q
  where q.posttypeid = 1
),
user_question_metrics as (
  select user_id,
         count(*) as questions,
         avg(q_score) as avg_q_score,
         avg(q_views) as avg_q_views,
         avg(q_answers) as avg_q_answers,
         avg(q_comments) as avg_q_comments,
         avg(case when dup_marks > 0 then 1 else 0 end)::numeric as dup_rate,
         avg(case when has_accepted = 1 then 1 else 0 end)::numeric as accepted_rate,
         sum(q_score)::numeric / sum(view_guard) as score_per_view
  from question_quality
  group by user_id
),
commenter_engagement as (
  select coalesce(c.userid, -1) as user_id,
         count(*) as comments_made,
         avg(coalesce(c.score,0)) as avg_comment_score,
         min(c.creationdate) as first_comment_date,
         max(c.creationdate) as last_comment_date
  from comments c
  group by coalesce(c.userid, -1)
),
edit_events as (
  select ph.userid as user_id,
         count(*) filter (where ph.posthistorytypeid in (5,24)) as edits_made,
         count(*) filter (where ph.posthistorytypeid in (10)) as closes_involved,
         count(*) filter (where ph.posthistorytypeid in (11)) as reopens_involved,
         max(ph.creationdate) as last_history_action
  from posthistory ph
  group by ph.userid
),
tag_expertise as (
  select p.owneruserid as user_id,
         unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag_name,
         count(*) as tag_posts,
         avg(coalesce(p.score,0)) as tag_avg_score
  from posts p
  where p.posttypeid in (1,2) and p.owneruserid is not null and p.tags is not null
  group by p.owneruserid, unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))
),
top_tag_per_user as (
  select user_id, tag_name, tag_posts, tag_avg_score,
         row_number() over (partition by user_id order by tag_posts desc, tag_avg_score desc, tag_name) as rn
  from tag_expertise
),
user_dupe_network as (
  select q.owneruserid as user_id,
         count(distinct pl.relatedpostid) as distinct_dupe_targets,
         count(*) as dupe_links
  from posts q
  join postlinks pl on pl.postid = q.id and pl.linktypeid = 3
  where q.posttypeid = 1 and q.owneruserid is not null
  group by q.owneruserid
),
location_rollup as (
  select ru.location_norm,
         count(*) as users_in_loc,
         percentile_cont(0.5) within group (order by ru.reputation) as median_rep
  from recent_users ru
  group by ru.location_norm
),
activity_window as (
  select p.owneruserid as user_id,
         p.id as post_id,
         p.posttypeid,
         p.creationdate,
         sum(case when p.posttypeid = 2 then 1 else 0 end) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_answers,
         sum(case when p.posttypeid = 1 then 1 else 0 end) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cum_questions,
         row_number() over (partition by p.owneruserid order by p.creationdate desc) as recency_rank
  from posts p
  where p.owneruserid is not null
),
recent_activity as (
  select aw.user_id,
         max(case when aw.recency_rank = 1 then aw.post_id end) as last_post_id,
         max(case when aw.recency_rank = 1 then aw.posttypeid end) as last_post_type,
         max(case when aw.recency_rank = 1 then aw.creationdate end) as last_post_date,
         max(aw.cum_answers) as cum_answers_latest,
         max(aw.cum_questions) as cum_questions_latest
  from activity_window aw
  group by aw.user_id
),
final_users as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location_norm,
         coalesce(upar.q_count,0) as q_count,
         coalesce(upar.a_count,0) as a_count,
         qa.a_per_q,
         uvr.recv_upvotes,
         uvr.recv_downvotes,
         uvr.recv_bounty,
         uqm.questions as q_total,
         uqm.avg_q_score,
         uqm.avg_q_views,
         uqm.avg_q_answers,
         uqm.avg_q_comments,
         uqm.dup_rate,
         uqm.accepted_rate,
         uqm.score_per_view,
         ce.comments_made,
         ce.avg_comment_score,
         ee.edits_made,
         ee.closes_involved,
         ee.reopens_involved,
         tt.tag_name as top_tag,
         tt.tag_posts as top_tag_posts,
         tt.tag_avg_score as top_tag_avg_score,
         udn.distinct_dupe_targets,
         udn.dupe_links,
         la.users_in_loc,
         la.median_rep,
         ra.last_post_id,
         ra.last_post_type,
         ra.last_post_date,
         ra.cum_answers_latest,
         ra.cum_questions_latest,
         ubr.total_badges,
         ubr.gold_badges,
         ubr.silver_badges,
         ubr.bronze_badges,
         ubr.last_badge_date
  from recent_users ru
  left join user_post_activity upar on upar.user_id = ru.user_id
  left join qa_ratio qa on qa.user_id = ru.user_id
  left join user_vote_rollup uvr on uvr.user_id = ru.user_id
  left join user_question_metrics uqm on uqm.user_id = ru.user_id
  left join commenter_engagement ce on ce.user_id = ru.user_id
  left join edit_events ee on ee.user_id = ru.user_id
  left join top_tag_per_user tt on tt.user_id = ru.user_id and tt.rn = 1
  left join user_dupe_network udn on udn.user_id = ru.user_id
  left join location_rollup la on la.location_norm = ru.location_norm
  left join recent_activity ra on ra.user_id = ru.user_id
  left join user_badge_rollup ubr on ubr.userid = ru.user_id
),
scored as (
  select f.*,
         -- composite engagement score
         (
           coalesce(f.recv_upvotes,0) * 1.0
           - coalesce(f.recv_downvotes,0) * 0.6
           + coalesce(f.recv_bounty,0) * 0.2
           + coalesce(f.a_count,0) * 1.5
           + coalesce(f.q_count,0) * 0.8
           + coalesce(f.edits_made,0) * 0.4
           + coalesce(f.comments_made,0) * 0.1
           + coalesce(f.gold_badges,0) * 5
           + coalesce(f.silver_badges,0) * 2
           + coalesce(f.bronze_badges,0) * 1
           + coalesce(f.accepted_rate,0) * 20
           - coalesce(f.dup_rate,0) * 15
         ) as engagement_score,
         -- normalized location influence
         case
           when coalesce(f.users_in_loc,0) = 0 then 0
           else (coalesce(f.median_rep,0)::numeric / nullif(f.users_in_loc,0)) end as loc_influence,
         -- freshness decay factor
         exp(-extract(epoch from (now() - coalesce(f.last_post_date, f.creationdate))) / 86400.0 / 365.0) as freshness_decay
  from final_users f
),
ranked as (
  select s.*,
         dense_rank() over (order by (s.engagement_score * s.freshness_decay) desc nulls last) as activity_rank_desc,
         dense_rank() over (order by coalesce(s.a_per_q, -1) asc nulls last) as balance_rank_asc,
         ntile(10) over (order by coalesce(s.avg_q_score, -1000) desc nulls last) as qscore_decile,
         row_number() over (partition by s.location_norm order by s.engagement_score desc nulls last) as loc_rownum
  from scored s
),
dupe_pairs as (
  select pl.postid, pl.relatedpostid,
         p.owneruserid as src_user,
         r.owneruserid as dst_user
  from postlinks pl
  join posts p on p.id = pl.postid
  join posts r on r.id = pl.relatedpostid
  where pl.linktypeid = 3
),
user_cross_dupes as (
  select dp.src_user as user_id,
         count(*) filter (where dp.dst_user is not distinct from dp.src_user) as self_dupes,
         count(*) filter (where dp.dst_user is distinct from dp.src_user) as cross_dupes
  from dupe_pairs dp
  group by dp.src_user
)
select
  r.user_id,
  coalesce(r.displayname, concat('User#', r.user_id::text)) as display_name,
  r.reputation,
  r.location_norm as location,
  r.activity_rank_desc,
  r.balance_rank_asc,
  r.qscore_decile,
  r.engagement_score,
  round(coalesce(r.a_per_q,0)::numeric, 3) as answers_per_question,
  r.q_count,
  r.a_count,
  r.recv_upvotes,
  r.recv_downvotes,
  r.recv_bounty,
  r.avg_q_score,
  r.avg_q_views,
  r.accepted_rate,
  r.dup_rate,
  r.top_tag,
  r.top_tag_posts,
  r.last_post_date,
  r.total_badges,
  r.gold_badges,
  r.silver_badges,
  r.bronze_badges,
  r.loc_influence,
  r.freshness_decay,
  coalesce(ucd.self_dupes,0) as self_dupes,
  coalesce(ucd.cross_dupes,0) as cross_dupes
from ranked r
left join user_cross_dupes ucd on ucd.user_id = r.user_id
where
  (r.loc_rownum <= 50 or r.activity_rank_desc <= 200)
  and (r.q_count + r.a_count) > 0
  and (
    r.top_tag is null
    or lower(r.top_tag) not in ('discussion', 'off-topic')
  )
order by (r.engagement_score * r.freshness_decay) desc nulls last, r.user_id
limit 500;