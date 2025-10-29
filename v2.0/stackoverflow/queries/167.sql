with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.location,
         u.creationdate,
         u.upvotes,
         u.downvotes,
         coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm
  from users u
  where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
  select p.id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.answercount,
         p.favoritecount,
         p.closeddate
  from posts p
  where p.posttypeid = 1
),
answer_posts as (
  select p.id,
         p.parentid as question_id,
         p.owneruserid as user_id,
         p.creationdate,
         p.score
  from posts p
  where p.posttypeid = 2
),
badge_counts as (
  select b.userid,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
         count(*) as total_badges,
         max(b.date) as last_badge_date
  from badges b
  group by b.userid
),
question_metrics as (
  select q.user_id,
         count(*) as q_count,
         avg(q.score) as avg_q_score,
         avg(nullif(q.viewcount,0)) as avg_q_views_nonzero,
         sum(case when q.closeddate is not null then 1 else 0 end) as q_closed,
         sum(coalesce(q.favoritecount,0)) as total_favorites,
         count(*) filter (where position('><' in coalesce(q.tags,'')) >= 1) as multi_tag_q,
         count(*) filter (where q.answercount = 0) as unanswered_q
  from question_posts q
  group by q.user_id
),
answer_metrics as (
  select a.user_id,
         count(*) as a_count,
         avg(a.score) as avg_a_score,
         sum(case when a.score > 0 then 1 else 0 end) as a_pos,
         sum(case when a.score < 0 then 1 else 0 end) as a_neg
  from answer_posts a
  group by a.user_id
),
comment_metrics as (
  select c.userid as user_id,
         count(*) as c_count,
         avg(c.score) as avg_c_score,
         sum(case when c.score > 0 then 1 else 0 end) as c_pos,
         sum(case when c.score < 0 then 1 else 0 end) as c_neg,
         max(c.creationdate) as last_comment_date
  from comments c
  group by c.userid
),
vote_breakdown as (
  select v.userid as user_id,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upmods_cast,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downmods_cast,
         sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
         sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
  from votes v
  group by v.userid
),
dupe_links as (
  select pl.postid as dup_post_id,
         pl.relatedpostid as original_post_id,
         pl.creationdate,
         pl.linktypeid
  from postlinks pl
  where pl.linktypeid = 3
),
accepted_answers as (
  select p.acceptedanswerid as answer_id, p.id as question_id, p.owneruserid as asker_id
  from posts p
  where p.posttypeid = 1 and p.acceptedanswerid is not null
),
accepted_by_user as (
  select a.user_id,
         count(*) as accepted_given
  from answer_posts ap
  join accepted_answers aa on aa.answer_id = ap.id
  join answer_posts a on a.id = ap.id
  group by a.user_id
),
hot_bumps as (
  select ph.postid,
         sum(case when ph.posthistorytypeid = 50 then 1 else 0 end) as community_bumps,
         sum(case when ph.posthistorytypeid = 52 then 1 else 0 end) as selected_hot,
         sum(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot,
         max(ph.creationdate) as last_hist_date
  from posthistory ph
  where ph.posthistorytypeid in (50,52,53)
  group by ph.postid
),
user_activity as (
  select ru.user_id,
         coalesce(qm.q_count,0) as q_count,
         coalesce(am.a_count,0) as a_count,
         coalesce(cm.c_count,0) as c_count,
         coalesce(qm.avg_q_score,0) as avg_q_score,
         coalesce(am.avg_a_score,0) as avg_a_score,
         coalesce(cm.avg_c_score,0) as avg_c_score,
         coalesce(qm.q_closed,0) as q_closed,
         coalesce(qm.total_favorites,0) as total_favorites,
         coalesce(qm.multi_tag_q,0) as multi_tag_q,
         coalesce(qm.unanswered_q,0) as unanswered_q,
         coalesce(am.a_pos,0) as a_pos,
         coalesce(am.a_neg,0) as a_neg,
         coalesce(cm.c_pos,0) as c_pos,
         coalesce(cm.c_neg,0) as c_neg
  from recent_users ru
  left join question_metrics qm on qm.user_id = ru.user_id
  left join answer_metrics am on am.user_id = ru.user_id
  left join comment_metrics cm on cm.user_id = ru.user_id
),
string_flags as (
  select ru.user_id,
         case when lower(coalesce(ru.displayname,'')) similar to '%(bot|automaton|ci|build)%' then 1 else 0 end as likely_bot_name,
         case when lower(coalesce(ru.location,'')) like '%remote%' or lower(coalesce(ru.location,'')) like '%world%' then 1 else 0 end as remoteish,
         length(coalesce(ru.websiteurl_norm,'')) as website_len,
         case when position('.' in coalesce(ru.websiteurl_norm,'')) > 0 then 1 else 0 end as has_domain
  from recent_users ru
),
dupe_participation as (
  select u.id as user_id,
         count(distinct d.dup_post_id) filter (where p.owneruserid = u.id) as dup_questions_authored,
         count(distinct d.original_post_id) filter (where p2.owneruserid = u.id) as dup_originals_authored
  from users u
  left join dupe_links d on true
  left join posts p on p.id = d.dup_post_id
  left join posts p2 on p2.id = d.original_post_id
  group by u.id
),
activity_windows as (
  select p.owneruserid as user_id,
         count(*) as posts_last_30d,
         avg(p.score) as avg_score_last_30d,
         sum(case when p.posttypeid = 1 then 1 else 0 end) as q_last_30d,
         sum(case when p.posttypeid = 2 then 1 else 0 end) as a_last_30d
  from posts p
  where p.creationdate >= (select max(creationdate) - interval '30 days' from posts)
  group by p.owneruserid
),
user_ranked as (
  select ua.user_id,
         rank() over (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0) + coalesce(ua.c_count,0) desc) as activity_rank,
         dense_rank() over (order by coalesce(ua.avg_q_score,0) desc) as q_quality_rank,
         dense_rank() over (order by coalesce(ua.avg_a_score,0) desc) as a_quality_rank,
         ntile(10) over (order by coalesce(ua.q_closed,0)) as closed_ntile
  from user_activity ua
),
user_summary as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.creationdate,
         ru.location,
         ru.upvotes,
         ru.downvotes,
         bc.gold_badges,
         bc.silver_badges,
         bc.bronze_badges,
         bc.tag_badges,
         bc.total_badges,
         bc.last_badge_date,
         ua.q_count,
         ua.a_count,
         ua.c_count,
         ua.avg_q_score,
         ua.avg_a_score,
         ua.avg_c_score,
         ua.q_closed,
         ua.total_favorites,
         ua.multi_tag_q,
         ua.unanswered_q,
         ua.a_pos,
         ua.a_neg,
         ua.c_pos,
         ua.c_neg,
         sf.likely_bot_name,
         sf.remoteish,
         sf.website_len,
         sf.has_domain,
         coalesce(vb.upmods_cast,0) as upmods_cast,
         coalesce(vb.downmods_cast,0) as downmods_cast,
         coalesce(vb.bounty_started,0) as bounty_started,
         coalesce(vb.bounty_awarded,0) as bounty_awarded,
         coalesce(dp.dup_questions_authored,0) as dup_questions_authored,
         coalesce(dp.dup_originals_authored,0) as dup_originals_authored,
         coalesce(aw.posts_last_30d,0) as posts_last_30d,
         coalesce(aw.avg_score_last_30d,0) as avg_score_last_30d,
         coalesce(aw.q_last_30d,0) as q_last_30d,
         coalesce(aw.a_last_30d,0) as a_last_30d,
         ur.activity_rank,
         ur.q_quality_rank,
         ur.a_quality_rank,
         ur.closed_ntile
  from recent_users ru
  left join badge_counts bc on bc.userid = ru.user_id
  left join user_activity ua on ua.user_id = ru.user_id
  left join string_flags sf on sf.user_id = ru.user_id
  left join vote_breakdown vb on vb.user_id = ru.user_id
  left join dupe_participation dp on dp.user_id = ru.user_id
  left join activity_windows aw on aw.user_id = ru.user_id
  left join user_ranked ur on ur.user_id = ru.user_id
),
quality_flags as (
  select us.*,
         case
           when coalesce(us.avg_a_score,0) >= 2 and coalesce(us.avg_q_score,0) >= 1 then 'high'
           when coalesce(us.avg_a_score,0) >= 1 or coalesce(us.avg_q_score,0) >= 0.5 then 'medium'
           else 'low'
         end as quality_band,
         case when coalesce(us.downmods_cast,0) > coalesce(us.upmods_cast,0) then 1 else 0 end as downvote_heavy,
         case when us.likely_bot_name = 1 and us.website_len > 0 and us.has_domain = 0 then 1 else 0 end as suspicious_profile
  from user_summary us
),
ranked_output as (
  select qf.*,
         sum(coalesce(qf.q_count,0) + coalesce(qf.a_count,0) + coalesce(qf.c_count,0))
           over (order by qf.activity_rank rows between unbounded preceding and current row) as running_activity_sum,
         avg(coalesce(qf.avg_a_score,0))
           over (partition by qf.quality_band order by qf.activity_rank rows between unbounded preceding and current row) as running_avg_a_score_by_band
  from quality_flags qf
)
select ro.user_id,
       ro.displayname,
       ro.reputation,
       ro.location,
       ro.quality_band,
       ro.activity_rank,
       ro.q_quality_rank,
       ro.a_quality_rank,
       ro.closed_ntile,
       ro.q_count,
       ro.a_count,
       ro.c_count,
       ro.avg_q_score,
       ro.avg_a_score,
       ro.avg_c_score,
       ro.q_closed,
       ro.total_favorites,
       ro.a_pos,
       ro.a_neg,
       ro.upmods_cast,
       ro.downmods_cast,
       ro.bounty_started,
       ro.bounty_awarded,
       ro.gold_badges,
       ro.silver_badges,
       ro.bronze_badges,
       ro.tag_badges,
       ro.total_badges,
       ro.posts_last_30d,
       ro.avg_score_last_30d,
       ro.dup_questions_authored,
       ro.dup_originals_authored,
       ro.suspicious_profile,
       ro.downvote_heavy,
       ro.running_activity_sum,
       ro.running_avg_a_score_by_band,
       case
         when ro.reputation = 0 then null
         else round(100.0 * (coalesce(ro.upvotes,0) - coalesce(ro.downvotes,0)) / nullif(cast(ro.reputation as numeric),0), 2)
       end as vote_efficiency_pct,
       case
         when coalesce(ro.q_count,0) + coalesce(ro.a_count,0) + coalesce(ro.c_count,0) = 0 then 'inactive'
         when coalesce(ro.posts_last_30d,0) >= 5 then 'active_30d'
         when coalesce(ro.posts_last_30d,0) between 1 and 4 then 'sporadic_30d'
         else 'lurker'
       end as activity_label
from ranked_output ro
where (
        ro.quality_band <> 'low'
        or (ro.posts_last_30d >= 3 and ro.avg_score_last_30d > 0)
      )
  and (coalesce(ro.dup_questions_authored,0) + coalesce(ro.dup_originals_authored,0)) between 0 and 50
  and not (ro.suspicious_profile = 1 and ro.downvote_heavy = 1)
order by ro.activity_rank, ro.q_quality_rank, ro.a_quality_rank
limit 250;