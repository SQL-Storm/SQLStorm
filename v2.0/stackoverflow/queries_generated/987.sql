-- {"query": "987.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3800} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           u.websiteurl,
           u.upvotes,
           u.downvotes,
           u.views
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select p.id as post_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.closeddate,
           p.contentlicense
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.id as post_id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score as answer_score
    from posts p
    where p.posttypeid = 2
),
user_q_activity as (
    select q.user_id,
           count(*) filter (where q.closeddate is null) as open_q_count,
           count(*) filter (where q.closeddate is not null) as closed_q_count,
           coalesce(sum(q.score),0) as total_q_score,
           coalesce(sum(q.viewcount),0) as total_q_views,
           percentile_cont(0.5) within group (order by q.viewcount) as median_q_views,
           max(q.creationdate) as last_q_date
    from question_posts q
    group by q.user_id
),
user_a_activity as (
    select a.user_id,
           count(*) as answer_count,
           coalesce(sum(a.answer_score),0) as total_a_score,
           max(a.creationdate) as last_a_date
    from answer_posts a
    group by a.user_id
),
user_comment_stats as (
    select c.userid as user_id,
           count(*) as comment_count,
           coalesce(sum(c.score),0) as comment_score_sum,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
user_badge_stats as (
    select b.userid as user_id,
           count(*) as badge_count,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
dup_links as (
    select pl.postid as post_id,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links,
           count(*) filter (where pl.linktypeid = 1) as linked_links
    from postlinks pl
    group by pl.postid
),
q_vote_breakdown as (
    select v.postid as post_id,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           count(distinct case when v.votetypeid in (8,9) then v.userid end) as bounty_actors,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
q_edit_events as (
    select ph.postid as post_id,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9)) as edit_events,
           count(*) filter (where ph.posthistorytypeid in (10)) as close_events,
           count(*) filter (where ph.posthistorytypeid in (11)) as reopen_events,
           count(*) filter (where ph.posthistorytypeid in (12)) as delete_events,
           count(*) filter (where ph.posthistorytypeid in (13)) as undelete_events,
           max(ph.creationdate) as last_event_date,
           max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_close_date,
           max(case when ph.posthistorytypeid = 11 then ph.creationdate end) as last_reopen_date
    from posthistory ph
    group by ph.postid
),
q_tag_unpacked as (
    select q.post_id,
           trim(both from t.tag) as tag
    from question_posts q
         left join lateral (
             select unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
         ) t on true
),
user_tag_focus as (
    select q.owneruserid as user_id,
           lower(ut.tag) as tag,
           count(*) as tag_q_count
    from posts q
    join q_tag_unpacked ut on ut.post_id = q.id
    where q.posttypeid = 1
    group by q.owneruserid, lower(ut.tag)
),
top_tag_per_user as (
    select user_id, tag, tag_q_count,
           row_number() over (partition by user_id order by tag_q_count desc, tag asc) as rn
    from user_tag_focus
),
user_recent_activity as (
    select ru.user_id,
           greatest(
               coalesce(uq.last_q_date, timestamp 'epoch'),
               coalesce(ua.last_a_date, timestamp 'epoch'),
               coalesce(uc.last_comment_date, timestamp 'epoch'),
               coalesce(ub.last_badge_date, timestamp 'epoch')
           ) as last_activity_date
    from recent_users ru
    left join user_q_activity uq on uq.user_id = ru.user_id
    left join user_a_activity ua on ua.user_id = ru.user_id
    left join user_comment_stats uc on uc.user_id = ru.user_id
    left join user_badge_stats ub on ub.user_id = ru.user_id
),
scored_questions as (
    select q.post_id,
           q.user_id,
           q.title,
           q.creationdate,
           q.score,
           q.viewcount,
           coalesce(vb.upvotes,0) as upvotes,
           coalesce(vb.downvotes,0) as downvotes,
           coalesce(vb.favorites,0) as favorites,
           coalesce(vb.bounty_actors,0) as bounty_actors,
           coalesce(vb.bounty_awarded,0) as bounty_awarded,
           coalesce(de.duplicate_links,0) as duplicate_links,
           coalesce(de.linked_links,0) as linked_links,
           coalesce(ee.edit_events,0) as edit_events,
           coalesce(ee.close_events,0) as close_events,
           coalesce(ee.reopen_events,0) as reopen_events,
           q.answercount,
           q.closeddate
    from question_posts q
    left join q_vote_breakdown vb on vb.post_id = q.post_id
    left join dup_links de on de.post_id = q.post_id
    left join q_edit_events ee on ee.post_id = q.post_id
),
q_quality_metrics as (
    select sq.*,
           case
               when coalesce(sq.downvotes,0) = 0 then coalesce(sq.upvotes,0)
               else sq.upvotes::numeric / nullif(sq.downvotes,0)
           end as uv_dv_ratio,
           (coalesce(sq.upvotes,0) * 3 + coalesce(sq.favorites,0) * 2 + coalesce(sq.bounty_awarded,0) / 50
             - coalesce(sq.downvotes,0) * 2 - coalesce(sq.duplicate_links,0) * 5 - case when sq.closeddate is not null then 10 else 0 end
           )::numeric as quality_score
    from scored_questions sq
),
user_rollup as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.creationdate as user_created,
           ru.location,
           ru.websiteurl,
           ru.upvotes as user_upvotes,
           ru.downvotes as user_downvotes,
           ru.views as profile_views,
           coalesce(uq.open_q_count,0) as open_q_count,
           coalesce(uq.closed_q_count,0) as closed_q_count,
           coalesce(uq.total_q_score,0) as total_q_score,
           coalesce(uq.total_q_views,0) as total_q_views,
           uq.median_q_views,
           coalesce(ua.answer_count,0) as answer_count,
           coalesce(ua.total_a_score,0) as total_a_score,
           coalesce(uc.comment_count,0) as comment_count,
           coalesce(uc.comment_score_sum,0) as comment_score_sum,
           coalesce(ub.badge_count,0) as badge_count,
           coalesce(ub.gold_badges,0) as gold_badges,
           coalesce(ub.silver_badges,0) as silver_badges,
           coalesce(ub.bronze_badges,0) as bronze_badges,
           coalesce(ub.tag_badges,0) as tag_badges
    from recent_users ru
    left join user_q_activity uq on uq.user_id = ru.user_id
    left join user_a_activity ua on ua.user_id = ru.user_id
    left join user_comment_stats uc on uc.user_id = ru.user_id
    left join user_badge_stats ub on ub.user_id = ru.user_id
),
user_question_window as (
    select qq.user_id,
           qq.post_id,
           qq.creationdate,
           qq.score,
           qq.quality_score,
           row_number() over (partition by qq.user_id order by qq.quality_score desc nulls last, qq.creationdate desc) as rn_best,
           row_number() over (partition by qq.user_id order by qq.creationdate desc, qq.post_id desc) as rn_recent,
           avg(qq.quality_score) over (partition by qq.user_id) as avg_quality_score,
           percentile_cont(0.9) within group (order by qq.quality_score) over (partition by qq.user_id) as p90_quality_score
    from q_quality_metrics qq
),
best_and_recent_questions as (
    select uw.user_id,
           max(case when uw.rn_best = 1 then uw.post_id end) as best_q_id,
           max(case when uw.rn_best = 1 then uw.quality_score end) as best_q_quality,
           max(case when uw.rn_recent = 1 then uw.post_id end) as recent_q_id,
           max(case when uw.rn_recent = 1 then uw.quality_score end) as recent_q_quality,
           max(uw.avg_quality_score) as avg_quality_score,
           max(uw.p90_quality_score) as p90_quality_score
    from user_question_window uw
    group by uw.user_id
),
user_engagement_tiers as (
    select ur.user_id,
           case
               when coalesce(ur.answer_count,0) >= 100 or coalesce(ur.total_q_views,0) >= 100000 then 'Platinum'
               when coalesce(ur.answer_count,0) >= 25 or coalesce(ur.total_q_views,0) >= 25000 then 'Gold'
               when coalesce(ur.answer_count,0) >= 10 or coalesce(ur.total_q_views,0) >= 10000 then 'Silver'
               when coalesce(ur.answer_count,0) >= 3 or coalesce(ur.total_q_views,0) >= 3000 then 'Bronze'
               else 'New'
           end as engagement_tier
    from user_rollup ur
),
normalized_names as (
    select u.id as user_id,
           regexp_replace(coalesce(u.displayname, 'Unknown'), '\s+', ' ', 'g') as displayname_norm,
           lower(coalesce(u.location,'')) as location_norm,
           case when u.websiteurl similar to 'https?://%' then u.websiteurl else null end as website_norm
    from users u
),
dup_vs_reopen as (
    select q.user_id,
           sum(case when ee.close_events > 0 and sq.duplicate_links > 0 then 1 else 0 end) as dup_closed,
           sum(coalesce(ee.reopen_events,0)) as reopened
    from scored_questions sq
    left join q_edit_events ee on ee.post_id = sq.post_id
    group by q.user_id
),
post_type_map as (
    select pt.id, pt.name from posttypes pt
),
final_metrics as (
    select ur.user_id,
           nn.displayname_norm as displayname,
           ur.reputation,
           ur.user_created,
           nn.location_norm as location,
           nn.website_norm as websiteurl,
           ur.user_upvotes,
           ur.user_downvotes,
           ur.profile_views,
           ur.open_q_count,
           ur.closed_q_count,
           ur.total_q_score,
           ur.total_q_views,
           ur.median_q_views,
           ur.answer_count,
           ur.total_a_score,
           ur.comment_count,
           ur.comment_score_sum,
           ur.badge_count,
           ur.gold_badges,
           ur.silver_badges,
           ur.bronze_badges,
           ur.tag_badges,
           coalesce(ba.best_q_id, -1) as best_q_id,
           ba.best_q_quality,
           coalesce(ba.recent_q_id, -1) as recent_q_id,
           ba.recent_q_quality,
           ba.avg_quality_score,
           ba.p90_quality_score,
           et.engagement_tier,
           coalesce(dvr.dup_closed,0) as dup_closed,
           coalesce(dvr.reopened,0) as reopened
    from user_rollup ur
    left join best_and_recent_questions ba on ba.user_id = ur.user_id
    left join user_engagement_tiers et on et.user_id = ur.user_id
    left join normalized_names nn on nn.user_id = ur.user_id
    left join dup_vs_reopen dvr on dvr.user_id = ur.user_id
),
ranked as (
    select fm.*,
           row_number() over (
               order by
                 (fm.reputation/100.0 + coalesce(fm.avg_quality_score,0) + fm.gold_badges*5 + fm.silver_badges*2 + fm.bronze_badges) desc,
                 fm.total_q_views desc
           ) as overall_rank
    from final_metrics fm
),
tag_focus as (
    select ttu.user_id,
           ttu.tag,
           ttu.tag_q_count,
           dense_rank() over (partition by ttu.user_id order by ttu.tag_q_count desc, ttu.tag asc) as tag_rank
    from top_tag_per_user ttu
    where ttu.rn <= 5
),
best_q_details as (
    select qq.post_id,
           qq.title,
           qq.viewcount,
           qq.upvotes,
           qq.downvotes,
           qq.favorites,
           qq.answercount,
           qq.quality_score
    from q_quality_metrics qq
),
recent_q_details as (
    select qq.post_id,
           qq.title,
           qq.viewcount,
           qq.upvotes,
           qq.downvotes,
           qq.favorites,
           qq.answercount,
           qq.quality_score
    from q_quality_metrics qq
)
select r.overall_rank,
       r.user_id,
       r.displayname,
       r.reputation,
       r.engagement_tier,
       r.total_q_views,
       r.total_q_score,
       r.answer_count,
       r.total_a_score,
       r.badge_count,
       r.gold_badges,
       r.silver_badges,
       r.bronze_badges,
       r.open_q_count,
       r.closed_q_count,
       r.dup_closed,
       r.reopened,
       r.avg_quality_score,
       r.p90_quality_score,
       r.best_q_id,
       bqd.title as best_q_title,
       bqd.quality_score as best_q_quality_score,
       bqd.viewcount as best_q_views,
       r.recent_q_id,
       rqd.title as recent_q_title,
       rqd.quality_score as recent_q_quality_score,
       rqd.viewcount as recent_q_views,
       string_agg(case when tf.tag_rank <= 3 then tf.tag || ':' || tf.tag_q_count::text end, ', ' order by tf.tag_rank) as top3_tags,
       coalesce(r.location,'') as location_norm,
       coalesce(r.websiteurl,'') as website_norm
from ranked r
left join best_q_details bqd on bqd.post_id = r.best_q_id
left join recent_q_details rqd on rqd.post_id = r.recent_q_id
left join tag_focus tf on tf.user_id = r.user_id and tf.tag_rank <= 3
where r.user_id in (
    select user_id
    from user_recent_activity ura
    where ura.last_activity_date >= (select max(creationdate) - interval '180 days' from posts)
)
group by r.overall_rank, r.user_id, r.displayname, r.reputation, r.engagement_tier, r.total_q_views, r.total_q_score, r.answer_count, r.total_a_score, r.badge_count, r.gold_badges, r.silver_badges, r.bronze_badges, r.open_q_count, r.closed_q_count, r.dup_closed, r.reopened, r.avg_quality_score, r.p90_quality_score, r.best_q_id, bqd.title, bqd.quality_score, bqd.viewcount, r.recent_q_id, rqd.title, rqd.quality_score, rqd.viewcount, r.location, r.websiteurl
order by r.overall_rank
limit 200;