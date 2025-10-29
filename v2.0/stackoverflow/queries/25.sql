with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        coalesce(nullif(trim(p.ownerdisplayname), ''), u.displayname, '(anonymous)') as owner_name,
        u.reputation,
        date_trunc('month', p.creationdate) as month_bucket
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
),
user_activity as (
    select
        u.id as user_id,
        count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
        count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
        sum(greatest(p.score, 0)) as nonneg_score_sum,
        sum(p.viewcount) as total_views,
        count(distinct date_trunc('day', p.creationdate)) as active_days,
        max(p.creationdate) as last_post_at
    from users u
    left join posts p on p.owneruserid = u.id
        and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by u.id
),
tag_expansion as (
    select
        rp.id as post_id,
        unnest(string_to_array(substring(rp.tags, 2, greatest(length(rp.tags)-2,0)), '><')) as tag_name
    from recent_posts rp
    where rp.tags is not null
),
tag_rank as (
    select
        te.tag_name,
        rp.month_bucket,
        count(*) as tag_posts,
        dense_rank() over (partition by rp.month_bucket order by count(*) desc, te.tag_name) as tag_rnk
    from tag_expansion te
    join recent_posts rp on rp.id = te.post_id
    group by te.tag_name, rp.month_bucket
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        count(*) filter (where v.votetypeid in (10,12)) as mod_actions
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        min(c.creationdate) as first_comment_at
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by c.postid
),
history_flags as (
    select
        ph.postid,
        bool_or(ph.posthistorytypeid in (10,35)) as was_closed_or_migrated,
        bool_or(ph.posthistorytypeid in (12)) as was_deleted,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as last_moderation_event_at,
        count(*) filter (where ph.posthistorytypeid in (24)) as suggested_edits
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by ph.postid
),
link_dupes as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '24 months'
    group by pl.postid
),
post_metrics as (
    select
        rp.*,
        va.net_votes,
        va.favorites,
        va.bounty_total,
        va.mod_actions,
        ca.comment_count,
        ca.max_comment_score,
        ca.first_comment_at,
        hf.was_closed_or_migrated,
        hf.was_deleted,
        hf.last_moderation_event_at,
        hf.suggested_edits,
        ld.duplicate_links,
        ld.related_links,
        case
            when rp.viewcount is null then null
            when rp.viewcount = 0 then 0
            else round((coalesce(va.net_votes,0) / nullif(rp.viewcount,0)) * 1000, 3)
        end as votes_per_kview,
        case
            when rp.answercount is null or rp.answercount = 0 then 0
            else round(coalesce(va.favorites,0) / rp.answercount, 3)
        end as fav_per_answer,
        coalesce(va.net_votes,0) + coalesce(ca.comment_count,0) * 0.1 + coalesce(va.favorites,0) * 0.5 + coalesce(bounty_total,0) / 100.0
            - case when coalesce(hf.was_deleted,false) then 5 else 0 end
            - coalesce(ld.duplicate_links,0) * 0.2 as engagement_score
    from recent_posts rp
    left join votes_agg va on va.postid = rp.id
    left join comments_agg ca on ca.postid = rp.id
    left join history_flags hf on hf.postid = rp.id
    left join link_dupes ld on ld.postid = rp.id
),
author_quality as (
    select
        rp.owneruserid as user_id,
        count(*) as posts_24m,
        avg(pm.engagement_score) as avg_engagement,
        percentile_cont(0.9) within group (order by pm.engagement_score) as p90_engagement,
        sum(case when pm.was_closed_or_migrated then 1 else 0 end) as closed_or_migrated_cnt,
        sum(case when pm.was_deleted then 1 else 0 end) as deleted_cnt,
        sum(coalesce(pm.duplicate_links,0)) as dup_links_cnt
    from post_metrics pm
    join recent_posts rp on rp.id = pm.id
    group by rp.owneruserid
),
question_answer_mix as (
    select
        rp.owneruserid as user_id,
        count(*) filter (where rp.posttypeid = 1) as q_cnt,
        count(*) filter (where rp.posttypeid = 2) as a_cnt,
        case
            when count(*) filter (where rp.posttypeid = 2) = 0 then null
            else round(cast(count(*) filter (where rp.posttypeid = 1) as numeric) / nullif(count(*) filter (where rp.posttypeid = 2),0), 3)
        end as q_to_a_ratio
    from recent_posts rp
    group by rp.owneruserid
),
user_badges as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
user_rollup as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        ua.q_count,
        ua.a_count,
        ua.nonneg_score_sum,
        ua.total_views,
        ua.active_days,
        ua.last_post_at,
        aq.posts_24m,
        aq.avg_engagement,
        aq.p90_engagement,
        aq.closed_or_migrated_cnt,
        aq.deleted_cnt,
        aq.dup_links_cnt,
        qam.q_cnt as recent_q_cnt,
        qam.a_cnt as recent_a_cnt,
        qam.q_to_a_ratio,
        ub.total_badges,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.tag_badges,
        ub.last_badge_at
    from users u
    left join user_activity ua on ua.user_id = u.id
    left join author_quality aq on aq.user_id = u.id
    left join question_answer_mix qam on qam.user_id = u.id
    left join user_badges ub on ub.userid = u.id
),
monthly_summary as (
    select
        pm.month_bucket,
        count(*) as posts_in_month,
        avg(pm.engagement_score) as avg_engagement_month,
        sum(case when pm.posttypeid = 1 then 1 else 0 end) as questions_in_month,
        sum(case when pm.posttypeid = 2 then 1 else 0 end) as answers_in_month,
        sum(coalesce(pm.viewcount,0)) as views_in_month
    from post_metrics pm
    group by pm.month_bucket
),
top_tags_per_month as (
    select
        tr.month_bucket,
        tr.tag_name,
        tr.tag_posts
    from tag_rank tr
    where tr.tag_rnk <= 5
),
post_ranked as (
    select
        pm.*,
        row_number() over (partition by pm.month_bucket order by pm.engagement_score desc NULLS LAST, pm.viewcount desc NULLS LAST, pm.id) as rn_month_engagement,
        rank() over (order by pm.engagement_score desc NULLS LAST) as rk_global_engagement
    from post_metrics pm
),
cross_user_compare as (
    select
        ur1.user_id as user_id,
        ur2.user_id as peer_user_id,
        case
            when greatest(coalesce(ur1.avg_engagement,0), coalesce(ur2.avg_engagement,0)) = 0 then null
            else abs(coalesce(ur1.avg_engagement,0) - coalesce(ur2.avg_engagement,0)) / greatest(coalesce(ur1.avg_engagement,0), coalesce(ur2.avg_engagement,0))
        end as engagement_diff_ratio
    from user_rollup ur1
    join user_rollup ur2
      on ur1.user_id < ur2.user_id
      and abs(coalesce(ur1.reputation,0) - coalesce(ur2.reputation,0)) <= 50
),
peer_gap as (
    select
        user_id,
        min(engagement_diff_ratio) as best_peer_gap
    from cross_user_compare
    group by user_id
)
select
    pm.id as post_id,
    pm.posttypeid,
    pm.creationdate,
    pm.title,
    pm.owneruserid,
    pm.owner_name,
    pm.reputation,
    pm.viewcount,
    pm.score,
    pm.answercount,
    pm.votes_per_kview,
    pm.fav_per_answer,
    pm.engagement_score,
    pm.net_votes,
    pm.favorites,
    pm.bounty_total,
    pm.mod_actions,
    pm.comment_count,
    pm.max_comment_score,
    pm.first_comment_at,
    pm.was_closed_or_migrated,
    pm.was_deleted,
    pm.last_moderation_event_at,
    pm.duplicate_links,
    pm.related_links,
    ms.posts_in_month,
    ms.avg_engagement_month,
    ms.questions_in_month,
    ms.answers_in_month,
    ms.views_in_month,
    string_agg(tt.tag_name || ':' || cast(tt.tag_posts as text), ', ' ORDER BY tt.tag_posts desc, tt.tag_name) as top_tags_in_month,
    ur.displayname as author_displayname,
    ur.q_count,
    ur.a_count,
    ur.nonneg_score_sum,
    ur.total_views,
    ur.active_days,
    ur.last_post_at,
    ur.posts_24m,
    ur.avg_engagement as author_avg_engagement,
    ur.p90_engagement as author_p90_engagement,
    ur.closed_or_migrated_cnt as author_closed_or_migrated_cnt,
    ur.deleted_cnt as author_deleted_cnt,
    ur.dup_links_cnt as author_dup_links_cnt,
    ur.recent_q_cnt,
    ur.recent_a_cnt,
    ur.q_to_a_ratio,
    ur.total_badges,
    ur.gold_badges,
    ur.silver_badges,
    ur.bronze_badges,
    ur.tag_badges,
    ur.last_badge_at,
    pr.rn_month_engagement,
    pr.rk_global_engagement,
    pg.best_peer_gap,
    case
        when pm.tags is null then null
        else (select count(*) from tag_expansion te where te.post_id = pm.id)
    end as tag_count,
    coalesce(nullif(btrim(regexp_replace(coalesce(pm.title,''), '\s+', ' ', 'g')), ''), '(no title)') as normalized_title,
    pm.month_bucket,
    tt.tag_name,
    tt.tag_posts
from post_metrics pm
left join monthly_summary ms on ms.month_bucket = pm.month_bucket
left join top_tags_per_month tt on tt.month_bucket = pm.month_bucket
left join user_rollup ur on ur.user_id = pm.owneruserid
left join post_ranked pr on pr.id = pm.id
left join peer_gap pg on pg.user_id = pm.owneruserid
where (pm.posttypeid in (1,2))
  and (pm.engagement_score is not null and pm.engagement_score > (
        select avg(engagement_score) from post_metrics pm2
        where pm2.month_bucket = pm.month_bucket and pm2.posttypeid = pm.posttypeid
      ))
  and (pm.was_deleted is distinct from true)
  and (pm.owner_name is not null or pm.owneruserid is null)
group by
    pm.id, pm.posttypeid, pm.creationdate, pm.title, pm.owneruserid, pm.owner_name, pm.reputation, pm.viewcount, pm.score, pm.answercount,
    pm.votes_per_kview, pm.fav_per_answer, pm.engagement_score, pm.net_votes, pm.favorites, pm.bounty_total, pm.mod_actions, pm.comment_count,
    pm.max_comment_score, pm.first_comment_at, pm.was_closed_or_migrated, pm.was_deleted, pm.last_moderation_event_at, pm.duplicate_links, pm.related_links,
    ms.posts_in_month, ms.avg_engagement_month, ms.questions_in_month, ms.answers_in_month, ms.views_in_month,
    ur.displayname, ur.q_count, ur.a_count, ur.nonneg_score_sum, ur.total_views, ur.active_days, ur.last_post_at, ur.posts_24m, ur.avg_engagement,
    ur.p90_engagement, ur.closed_or_migrated_cnt, ur.deleted_cnt, ur.dup_links_cnt, ur.recent_q_cnt, ur.recent_a_cnt, ur.q_to_a_ratio, ur.total_badges,
    ur.gold_badges, ur.silver_badges, ur.bronze_badges, ur.tag_badges, ur.last_badge_at, pr.rn_month_engagement, pr.rk_global_engagement, pg.best_peer_gap,
    pm.tags,
    tt.tag_name, tt.tag_posts,
    pm.month_bucket
order by pm.month_bucket desc, pr.rn_month_engagement asc, pm.id
limit 500;