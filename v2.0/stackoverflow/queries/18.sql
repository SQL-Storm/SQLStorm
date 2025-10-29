with recent_users as (
  select u.id as user_id,
         u.displayname,
         u.reputation,
         u.creationdate,
         coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_guess,
         date_trunc('month', u.creationdate) as cohort_month
  from users u
  where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
posts_enriched as (
  select p.id,
         p.posttypeid,
         p.owneruserid,
         p.creationdate,
         p.score,
         p.viewcount,
         p.title,
         p.tags,
         p.acceptedanswerid,
         p.parentid,
         p.closeddate,
         p.lastactivitydate,
         case when p.posttypeid = 1 then 'Question'
              when p.posttypeid = 2 then 'Answer'
              else 'Other' end as post_type_name
  from posts p
  where p.creationdate >= (select min(creationdate) from recent_users)
),
user_posts as (
  select ru.user_id,
         pe.id,
         pe.posttypeid,
         pe.owneruserid,
         pe.creationdate,
         pe.score,
         pe.viewcount,
         pe.title,
         pe.tags,
         pe.acceptedanswerid,
         pe.parentid,
         pe.closeddate,
         pe.lastactivitydate,
         pe.post_type_name
  from recent_users ru
  left join posts_enriched pe
    on pe.owneruserid = ru.user_id
),
votes_agg as (
  select v.postid,
         sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
         sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
         sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
         sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount, 0) else 0 end) as bounty_total,
         count(*) as total_votes
  from votes v
  where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
  group by v.postid
),
comments_agg as (
  select c.postid,
         count(*) as comment_count,
         sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
         max(c.creationdate) as last_comment_at
  from comments c
  group by c.postid
),
postlinks_dupes as (
  select pl.postid,
         sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
         sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_links
  from postlinks pl
  group by pl.postid
),
posthistory_close as (
  select ph.postid,
         count(*) filter (where ph.posthistorytypeid = 10) as close_events,
         count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
         max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen_at,
         min(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as first_close_or_reopen_at,
         max(case when ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$' then 1 else 0 end) as has_close_reason_id_numeric
  from posthistory ph
  group by ph.postid
),
tag_explode as (
  select p.id as post_id,
         unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags) - 2, 0)), '><')) as tagname
  from posts p
  where p.posttypeid = 1
    and p.tags is not null
),
user_tag_prefs as (
  select up.owneruserid as user_id,
         lower(te.tagname) as tagname,
         count(*) as posts_with_tag,
         avg(up.score) as avg_score_in_tag
  from posts up
  join tag_explode te on te.post_id = up.id
  where up.owneruserid is not null
  group by up.owneruserid, lower(te.tagname)
),
ranked_user_tags as (
  select utp.user_id,
         utp.tagname,
         utp.posts_with_tag,
         utp.avg_score_in_tag,
         row_number() over (partition by utp.user_id order by utp.posts_with_tag desc, utp.avg_score_in_tag desc, utp.tagname) as rn
  from user_tag_prefs utp
),
user_top_tag as (
  select user_id,
         tagname as top_tag,
         posts_with_tag as top_tag_posts,
         avg_score_in_tag as top_tag_avg_score
  from ranked_user_tags
  where rn = 1
),
badge_agg as (
  select b.userid,
         count(*) as total_badges,
         sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
         sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
         sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
         sum(case when coalesce(b.tagbased, false) = true then 1 else 0 end) as tag_badges
  from badges b
  where b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '10 years'
  group by b.userid
),
question_answer_pair as (
  select q.id as question_id,
         q.owneruserid as asker_id,
         q.creationdate as question_created,
         q.viewcount as question_views,
         q.score as question_score,
         a.id as answer_id,
         a.owneruserid as answerer_id,
         a.creationdate as answer_created,
         a.score as answer_score,
         case when a.id = q.acceptedanswerid then 1 else 0 end as is_accepted
  from posts q
  left join posts a
    on a.parentid = q.id and a.posttypeid = 2
  where q.posttypeid = 1
),
answerer_response as (
  select qa.question_id,
         min(qa.answer_created) as first_answer_at,
         sum(case when qa.is_accepted = 1 then 1 else 0 end) as accepted_answers_count,
         count(*) filter (where qa.answer_id is not null) as answers_count
  from question_answer_pair qa
  group by qa.question_id
),
user_activity_rollup as (
  select up.user_id,
         count(*) filter (where up.posttypeid = 1) as questions_authored,
         count(*) filter (where up.posttypeid = 2) as answers_authored,
         sum(coalesce(va.upvotes, 0)) as total_upvotes_received,
         sum(coalesce(va.downvotes, 0)) as total_downvotes_received,
         sum(coalesce(va.favorites, 0)) as total_favorites_received,
         sum(coalesce(va.bounty_total, 0)) as total_bounty_earned_on_posts,
         sum(case when up.posttypeid = 1 then coalesce(up.viewcount, 0) else 0 end) as question_views_sum,
         avg(nullif(up.score, 0)) as avg_nonzero_post_score,
         max(up.creationdate) as last_post_at,
         min(up.creationdate) as first_post_at,
         count(*) filter (where up.closeddate is not null) as closed_posts,
         sum(coalesce(phc.close_events, 0)) as close_events,
         sum(coalesce(phc.reopen_events, 0)) as reopen_events,
         sum(coalesce(pla.duplicate_links, 0)) as duplicate_links,
         sum(coalesce(pla.linked_links, 0)) as linked_links,
         sum(coalesce(ca.comment_count, 0)) as comments_received
  from user_posts up
  left join votes_agg va on va.postid = up.id
  left join comments_agg ca on ca.postid = up.id
  left join postlinks_dupes pla on pla.postid = up.id
  left join posthistory_close phc on phc.postid = up.id
  group by up.user_id
),
cohort_baselines as (
  select ru.cohort_month,
         percentile_disc(0.5) within group (order by ua.questions_authored) as p50_questions,
         percentile_disc(0.5) within group (order by ua.answers_authored) as p50_answers,
         percentile_disc(0.9) within group (order by ua.total_upvotes_received) as p90_upvotes,
         avg(ua.avg_nonzero_post_score) as avg_of_avg_scores
  from recent_users ru
  join user_activity_rollup ua on ua.user_id = ru.user_id
  group by ru.cohort_month
),
joined as (
  select ru.user_id,
         ru.displayname,
         ru.reputation,
         ru.country_guess,
         ru.cohort_month,
         ua.questions_authored,
         ua.answers_authored,
         ua.total_upvotes_received,
         ua.total_downvotes_received,
         ua.total_favorites_received,
         ua.total_bounty_earned_on_posts,
         ua.question_views_sum,
         ua.avg_nonzero_post_score,
         ua.last_post_at,
         ua.first_post_at,
         ua.closed_posts,
         ua.close_events,
         ua.reopen_events,
         ua.duplicate_links,
         ua.linked_links,
         ua.comments_received,
         coalesce(ba.total_badges, 0) as total_badges,
         coalesce(ba.gold_badges, 0) as gold_badges,
         coalesce(ba.silver_badges, 0) as silver_badges,
         coalesce(ba.bronze_badges, 0) as bronze_badges,
         coalesce(ba.tag_badges, 0) as tag_badges,
         utt.top_tag,
         utt.top_tag_posts,
         utt.top_tag_avg_score,
         cb.p50_questions,
         cb.p50_answers,
         cb.p90_upvotes,
         cb.avg_of_avg_scores
  from recent_users ru
  left join user_activity_rollup ua on ua.user_id = ru.user_id
  left join badge_agg ba on ba.userid = ru.user_id
  left join user_top_tag utt on utt.user_id = ru.user_id
  left join cohort_baselines cb on cb.cohort_month = ru.cohort_month
),
bench as (
  select j.user_id,
         j.displayname,
         j.reputation,
         j.country_guess,
         j.cohort_month,
         j.questions_authored,
         j.answers_authored,
         j.total_upvotes_received,
         j.total_downvotes_received,
         j.total_favorites_received,
         j.total_bounty_earned_on_posts,
         j.question_views_sum,
         j.avg_nonzero_post_score,
         j.last_post_at,
         j.first_post_at,
         j.closed_posts,
         j.close_events,
         j.reopen_events,
         j.duplicate_links,
         j.linked_links,
         j.comments_received,
         j.total_badges,
         j.gold_badges,
         j.silver_badges,
         j.bronze_badges,
         j.tag_badges,
         j.top_tag,
         j.top_tag_posts,
         j.top_tag_avg_score,
         j.p50_questions,
         j.p50_answers,
         j.p90_upvotes,
         j.avg_of_avg_scores,
         (case when j.answers_authored > coalesce(j.p50_answers, 0) and j.total_upvotes_received >= coalesce(j.p90_upvotes, 0) then 1 else 0 end) as is_power_answerer,
         (case when j.questions_authored > coalesce(j.p50_questions, 0) and (j.closed_posts * 1.0) / nullif(j.questions_authored, 0) > 0.2 then 1 else 0 end) as asks_many_and_closed,
         (case when j.top_tag is not null and j.top_tag_avg_score > coalesce(j.avg_of_avg_scores, 0) then 1 else 0 end) as excels_in_top_tag,
         (case when j.total_downvotes_received > j.total_upvotes_received then 1 else 0 end) as more_downs_than_ups,
         greatest(coalesce(j.total_upvotes_received, 0) - coalesce(j.total_downvotes_received, 0), 0) as net_upvotes_clamped,
         coalesce(j.total_favorites_received, 0) + coalesce(j.total_bounty_earned_on_posts, 0) as saves_plus_bounty,
         extract(epoch from coalesce(j.last_post_at, cast('2024-10-01 12:34:56' as timestamp)) - coalesce(j.first_post_at, cast('2024-10-01 12:34:56' as timestamp))) / 86400.0 as days_active_window
  from joined j
),
ranked as (
  select b.user_id,
         b.displayname,
         b.reputation,
         b.country_guess,
         b.cohort_month,
         b.questions_authored,
         b.answers_authored,
         b.total_upvotes_received,
         b.total_downvotes_received,
         b.total_favorites_received,
         b.total_bounty_earned_on_posts,
         b.question_views_sum,
         b.avg_nonzero_post_score,
         b.last_post_at,
         b.first_post_at,
         b.closed_posts,
         b.close_events,
         b.reopen_events,
         b.duplicate_links,
         b.linked_links,
         b.comments_received,
         b.total_badges,
         b.gold_badges,
         b.silver_badges,
         b.bronze_badges,
         b.tag_badges,
         b.top_tag,
         b.top_tag_posts,
         b.top_tag_avg_score,
         b.p50_questions,
         b.p50_answers,
         b.p90_upvotes,
         b.avg_of_avg_scores,
         b.is_power_answerer,
         b.asks_many_and_closed,
         b.excels_in_top_tag,
         b.more_downs_than_ups,
         b.net_upvotes_clamped,
         b.saves_plus_bounty,
         b.days_active_window,
         rank() over (order by b.net_upvotes_clamped desc, b.total_badges desc, b.saves_plus_bounty desc, b.answers_authored desc) as r_overall,
         dense_rank() over (partition by b.country_guess order by b.net_upvotes_clamped desc) as r_by_country,
         row_number() over (partition by b.cohort_month order by b.saves_plus_bounty desc, b.total_badges desc) as r_by_cohort_saves,
         ntile(10) over (order by coalesce(b.avg_nonzero_post_score, 0)) as decile_avgscore,
         percent_rank() over (order by coalesce(b.question_views_sum, 0)) as pr_view_sum
  from bench b
),
final_users as (
  select *
  from ranked
  where (is_power_answerer = 1 or excels_in_top_tag = 1)
     or (asks_many_and_closed = 1 and more_downs_than_ups = 0)
)
select
  fu.user_id,
  coalesce(nullif(fu.displayname, ''), concat('user-', cast(fu.user_id as varchar))) as display_name_norm,
  fu.country_guess,
  fu.cohort_month,
  fu.reputation,
  fu.questions_authored,
  fu.answers_authored,
  fu.total_upvotes_received,
  fu.total_downvotes_received,
  fu.net_upvotes_clamped,
  fu.total_badges,
  fu.gold_badges,
  fu.silver_badges,
  fu.bronze_badges,
  fu.tag_badges,
  fu.top_tag,
  fu.top_tag_posts,
  round(coalesce(fu.top_tag_avg_score, 0), 2) as top_tag_avg_score,
  fu.saves_plus_bounty,
  round(coalesce(fu.avg_nonzero_post_score, 0), 2) as avg_nonzero_post_score,
  fu.closed_posts,
  fu.close_events,
  fu.reopen_events,
  fu.duplicate_links,
  fu.linked_links,
  fu.comments_received,
  round(fu.days_active_window, 1) as days_active_window,
  fu.r_overall,
  fu.r_by_country,
  fu.r_by_cohort_saves,
  fu.decile_avgscore,
  round(fu.pr_view_sum, 4) as pr_view_sum,
  case when fu.user_id in (
    select user_id from ranked order by net_upvotes_clamped desc, total_badges desc limit 100
  ) and fu.user_id in (
    select user_id from ranked where decile_avgscore = 10
  ) then 1 else 0 end as in_elite_set
from final_users fu
order by fu.r_overall, fu.user_id
limit 500;