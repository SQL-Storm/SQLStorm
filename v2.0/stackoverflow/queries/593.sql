with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           u.websiteurl,
           u.upvotes,
           u.downvotes,
           coalesce(nullif(trim(u.location), ''), 'Unknown') as norm_location
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.favoritecount,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id,
           p.parentid,
           p.owneruserid,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
user_activity as (
    select ru.user_id,
           count(distinct qp.id) as q_count,
           count(distinct ap.id) as a_count,
           sum(coalesce(qp.viewcount,0)) as q_views,
           sum(case when qp.closeddate is not null then 1 else 0 end) as q_closed,
           sum(greatest(coalesce(qp.score,0),0)) as q_pos_score,
           sum(least(coalesce(qp.score,0),0)) as q_neg_score,
           sum(greatest(coalesce(ap.score,0),0)) as a_pos_score,
           sum(least(coalesce(ap.score,0),0)) as a_neg_score,
           max(qp.creationdate) as last_q_date,
           max(ap.creationdate) as last_a_date
    from recent_users ru
    left join question_posts qp on qp.owneruserid = ru.user_id
    left join answer_posts ap on ap.owneruserid = ru.user_id
    group by ru.user_id
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_start,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_close,
           count(*) as total_votes
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
comment_agg as (
    select c.postid,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as pos_comments,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
post_link_agg as (
    select pl.postid,
           sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_count,
           sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_count
    from postlinks pl
    group by pl.postid
),
badge_agg as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           count(*) as total_badges,
           sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
    from badges b
    where b.date >= (select max(date) - interval '365 days' from badges)
    group by b.userid
),
accepted_answerers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
    group by a.owneruserid
),
post_quality as (
    select p.id,
           p.owneruserid,
           coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
           coalesce(va.total_votes,0) as total_votes,
           coalesce(ca.comment_count,0) as comment_count,
           coalesce(pla.linked_count,0) as linked_count,
           coalesce(pla.dup_count,0) as dup_count,
           case
             when p.viewcount is null or p.viewcount = 0 then null
             else round(coalesce(va.upvotes,0) / nullif(p.viewcount,0), 6)
           end as up_per_view,
           case when p.score is null then 0 else p.score end as post_score,
           case when p.closeddate is null then 0 else 1 end as is_closed
    from posts p
    left join vote_agg va on va.postid = p.id
    left join comment_agg ca on ca.postid = p.id
    left join post_link_agg pla on pla.postid = p.id
),
user_post_rank as (
    select pq.owneruserid as user_id,
           pq.id as post_id,
           pq.post_score,
           pq.net_votes,
           pq.total_votes,
           row_number() over (partition by pq.owneruserid order by pq.net_votes desc, pq.total_votes desc, pq.id) as rn_best,
           row_number() over (partition by pq.owneruserid order by pq.net_votes asc, pq.total_votes asc, pq.id) as rn_worst
    from post_quality pq
),
question_tags as (
    select qp.id as post_id,
           unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as tag
    from question_posts qp
    where qp.tags is not null and length(qp.tags) > 2
),
top_tags as (
    select qt.tag,
           count(*) as usage_count,
           dense_rank() over (order by count(*) desc, qt.tag) as rnk
    from question_tags qt
    group by qt.tag
),
user_tag_affinity as (
    select qp.owneruserid as user_id,
           qt.tag,
           count(*) as q_with_tag,
           avg(coalesce(pq.net_votes,0)) as avg_net_votes_tag,
           row_number() over (partition by qp.owneruserid order by count(*) desc, avg(coalesce(pq.net_votes,0)) desc) as rn
    from question_posts qp
    join question_tags qt on qt.post_id = qp.id
    left join post_quality pq on pq.id = qp.id
    group by qp.owneruserid, qt.tag
),
closed_reasons as (
    select ph.postid,
           max(ph.creationdate) as last_close_date,
           max(case when ph.posthistorytypeid = 10 then NULLIF(trim(ph.comment), '') end) as last_close_reason_text
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
close_reason_names as (
    select cr.postid,
           coalesce(crn.name, 'Unknown') as close_reason_name
    from closed_reasons cr
    left join closereasontypes crn on crn.id = (case when cr.last_close_reason_text ~ '^[0-9]+$' then cast(cr.last_close_reason_text as integer) else null end)
),
activity_calendar as (
    select ru.user_id,
           cast(date_trunc('month', p.creationdate) as date) as month,
           count(*) as posts_in_month
    from recent_users ru
    join posts p on p.owneruserid = ru.user_id
    group by ru.user_id, cast(date_trunc('month', p.creationdate) as date)
),
activity_stats as (
    select ac.user_id,
           avg(posts_in_month) as avg_posts_per_month,
           stddev_samp(posts_in_month) as std_posts_per_month,
           count(*) as months_active
    from activity_calendar ac
    group by ac.user_id
),
dupe_graph as (
    select qp.id as question_id,
           coalesce(sum(case when pla.dup_count > 0 then 1 else 0 end),0) as has_dupe_links
    from question_posts qp
    left join post_link_agg pla on pla.postid = qp.id
    group by qp.id
),
user_dupe_impact as (
    select qp.owneruserid as user_id,
           sum(case when dg.has_dupe_links > 0 then 1 else 0 end) as duped_questions,
           count(*) as total_questions,
           case when count(*) = 0 then null else round(100.0 * sum(case when dg.has_dupe_links > 0 then 1 else 0 end) / count(*), 2) end as duped_pct
    from question_posts qp
    left join dupe_graph dg on dg.question_id = qp.id
    group by qp.owneruserid
),
norm_users as (
    select ru.*,
           case
             when ru.websiteurl ilike '%github%' then 'Github'
             when ru.websiteurl ilike '%stack%overflow%' then 'StackOverflow'
             when ru.websiteurl is null then 'None'
             else 'Other'
           end as site_hint
    from recent_users ru
),
user_core as (
    select nu.user_id,
           nu.displayname,
           nu.reputation,
           nu.norm_location,
           nu.site_hint,
           ua.q_count,
           ua.a_count,
           ua.q_views,
           ua.q_closed,
           ua.q_pos_score,
           ua.q_neg_score,
           ua.a_pos_score,
           ua.a_neg_score,
           ua.last_q_date,
           ua.last_a_date,
           coalesce(aa.accepted_answers, 0) as accepted_answers,
           coalesce(ba.gold_badges, 0) as gold_badges,
           coalesce(ba.silver_badges, 0) as silver_badges,
           coalesce(ba.bronze_badges, 0) as bronze_badges,
           coalesce(ba.total_badges, 0) as total_badges,
           coalesce(ba.tag_badges, 0) as tag_badges,
           as1.avg_posts_per_month,
           as1.std_posts_per_month,
           as1.months_active,
           udi.duped_questions,
           udi.total_questions,
           udi.duped_pct
    from norm_users nu
    left join user_activity ua on ua.user_id = nu.user_id
    left join accepted_answerers aa on aa.user_id = nu.user_id
    left join badge_agg ba on ba.userid = nu.user_id
    left join activity_stats as1 on as1.user_id = nu.user_id
    left join user_dupe_impact udi on udi.user_id = nu.user_id
),
best_posts as (
    select upr.user_id, upr.post_id as best_post_id
    from user_post_rank upr
    where upr.rn_best = 1
),
worst_posts as (
    select upr.user_id, upr.post_id as worst_post_id
    from user_post_rank upr
    where upr.rn_worst = 1
),
post_summaries as (
    select p.id,
           p.title,
           coalesce(p.title, left(regexp_replace(p.body, '<[^>]+>', '', 'g'), 80)) as display_title,
           pq.net_votes,
           pq.total_votes,
           pq.comment_count,
           coalesce(crn.close_reason_name, 'Open') as close_reason_name
    from posts p
    left join post_quality pq on pq.id = p.id
    left join close_reason_names crn on crn.postid = p.id
)
select uc.user_id,
       uc.displayname,
       uc.reputation,
       uc.norm_location,
       uc.site_hint,
       uc.q_count,
       uc.a_count,
       uc.q_views,
       uc.q_closed,
       uc.q_pos_score + uc.a_pos_score as total_pos_score,
       uc.q_neg_score + uc.a_neg_score as total_neg_score,
       coalesce(uc.accepted_answers,0) as accepted_answers,
       coalesce(uc.gold_badges,0) as gold_badges,
       coalesce(uc.silver_badges,0) as silver_badges,
       coalesce(uc.bronze_badges,0) as bronze_badges,
       coalesce(uc.total_badges,0) as total_badges,
       coalesce(uc.tag_badges,0) as tag_badges,
       cast(coalesce(uc.avg_posts_per_month,0) as numeric(10,2)) as avg_posts_per_month,
       cast(coalesce(uc.std_posts_per_month,0) as numeric(10,2)) as std_posts_per_month,
       coalesce(uc.months_active,0) as months_active,
       cast(coalesce(uc.duped_pct,0) as numeric(5,2)) as duped_pct,
       bt.tag as top_tag,
       cast(uta.avg_net_votes_tag as numeric(10,3)) as tag_avg_net_votes,
       ps_b.display_title as best_post_title,
       ps_b.net_votes as best_post_net_votes,
       ps_b.total_votes as best_post_total_votes,
       ps_b.comment_count as best_post_comments,
       ps_w.display_title as worst_post_title,
       ps_w.net_votes as worst_post_net_votes,
       ps_w.total_votes as worst_post_total_votes,
       ps_w.comment_count as worst_post_comments,
       case
         when coalesce(uc.a_count,0) + coalesce(uc.q_count,0) = 0 then null
         else round( (coalesce(uc.q_pos_score,0) + coalesce(uc.a_pos_score,0) + 0.0001) / (coalesce(uc.q_count,0) + coalesce(uc.a_count,0)), 4)
       end as avg_positive_score_per_post,
       case
         when coalesce(uc.q_views,0) = 0 then null
         else round(coalesce(uc.q_pos_score,0) / nullif(uc.q_views,0), 6)
       end as q_pos_score_per_view,
       case
         when uc.last_q_date is null and uc.last_a_date is null then null
         else greatest(coalesce(uc.last_q_date, timestamp '1970-01-01'), coalesce(uc.last_a_date, timestamp '1970-01-01'))
       end as last_activity_date
from user_core uc
left join best_posts bp on bp.user_id = uc.user_id
left join worst_posts wp on wp.user_id = uc.user_id
left join post_summaries ps_b on ps_b.id = bp.best_post_id
left join post_summaries ps_w on ps_w.id = wp.worst_post_id
left join user_tag_affinity uta on uta.user_id = uc.user_id and uta.rn = 1
left join top_tags bt on bt.tag = uta.tag and bt.rnk <= 50
where coalesce(uc.q_count,0) + coalesce(uc.a_count,0) > 0
  and (uc.reputation > 100 or coalesce(uc.gold_badges,0) > 0)
order by (coalesce(uc.q_pos_score,0) + coalesce(uc.a_pos_score,0)) desc, uc.reputation desc, uc.user_id
limit 250;