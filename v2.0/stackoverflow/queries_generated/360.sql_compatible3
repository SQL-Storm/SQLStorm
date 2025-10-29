with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
           row_number() over (order by u.creationdate desc, u.id) as rn
    from users u
    where u.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '2 years' from posts p)
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        sum(p.score) as total_post_score,
        coalesce(sum(p.viewcount), 0) as total_views,
        max(p.lastactivitydate) as last_activity
    from users u
    left join posts p
      on p.owneruserid = u.id
     and p.creationdate >= (select date_trunc('year', max(pp.creationdate)) - interval '2 years' from posts pp)
    group by u.id
),
commenters as (
    select c.userid as user_id,
           count(*) as comment_count,
           avg(c.score) as avg_comment_score,
           sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as thanks_count
    from comments c
    where c.creationdate >= (select date_trunc('year', max(p.creationdate)) - interval '2 years' from posts p)
    group by c.userid
),
badge_tally as (
    select b.userid as user_id,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           count(*) filter (where (case when b.tagbased then 1 else 0 end) = 1) as tag_badges,
           min(b.date) as first_badge_date,
           max(b.date) as latest_badge_date
    from badges b
    group by b.userid
),
q_detail as (
    select
        p.owneruserid as user_id,
        count(*) as q_count,
        avg(p.score) as q_avg_score,
        avg(nullif(p.viewcount,0)) as q_avg_views_nonzero,
        sum(case when p.acceptedanswerid is not null then 1 else 0 end) as q_with_accept,
        percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as q_p90_views
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
a_detail as (
    select
        p.owneruserid as user_id,
        count(*) as a_count,
        avg(p.score) as a_avg_score,
        sum(case when p.score > 0 then 1 else 0 end) as a_pos_count,
        sum(case when p.score < 0 then 1 else 0 end) as a_neg_count
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
dup_links as (
    select pl.postid as src_id,
           pl.relatedpostid as target_id,
           pl.linktypeid,
           count(*) as link_count
    from postlinks pl
    where pl.linktypeid in (1,3)
    group by pl.postid, pl.relatedpostid, pl.linktypeid
),
hot_history as (
    select ph.postid,
           min(case when ph.posthistorytypeid = 52 then ph.creationdate end) as first_hot_date,
           max(case when ph.posthistorytypeid = 53 then ph.creationdate end) as last_hot_removed
    from posthistory ph
    where ph.posthistorytypeid in (52,53)
    group by ph.postid
),
vote_agg as (
    select v.postid,
           count(*) filter (where v.votetypeid = 2) as upvotes,
           count(*) filter (where v.votetypeid = 3) as downvotes,
           count(*) filter (where v.votetypeid = 5) as favorites,
           sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
post_metrics as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.score,
        p.viewcount,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.favorites,0) as favorites,
        coalesce(v.bounty_total,0) as bounty_total,
        hh.first_hot_date,
        hh.last_hot_removed,
        greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(hh.first_hot_date, p.creationdate)) as activity_anchor
    from posts p
    left join vote_agg v on v.postid = p.id
    left join hot_history hh on hh.postid = p.id
),
user_post_windows as (
    select
        pm.user_id,
        pm.post_id,
        pm.posttypeid,
        pm.score,
        pm.viewcount,
        pm.upvotes,
        pm.downvotes,
        pm.favorites,
        pm.bounty_total,
        pm.activity_anchor,
        row_number() over (partition by pm.user_id order by pm.activity_anchor desc, pm.post_id desc) as rn_by_user,
        sum(pm.score) over (partition by pm.user_id order by pm.activity_anchor rows between unbounded preceding and current row) as cum_score,
        avg(pm.score) over (partition by pm.user_id rows between 10 preceding and current row) as mov_avg_score_last_11,
        dense_rank() over (partition by pm.user_id order by pm.score desc nulls last) as score_rank
    from post_metrics pm
),
tag_exploded as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        lower(trim(tg.tag)) as tag
    from posts p
    cross join lateral (
        select unnest(
            case
                when p.tags is null then array[]::varchar[]
                else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            end
        ) as tag
    ) tg
    where p.posttypeid = 1
),
top_tags as (
    select user_id,
           tag,
           count(*) as tag_q_count,
           rank() over (partition by user_id order by count(*) desc, tag) as tag_rank
    from tag_exploded
    group by user_id, tag
),
user_closure as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        sum(
            case
                when ph.posthistorytypeid = 10
                then case
                    when ph.comment ~ '^[0-9]+$' then 1
                    when ph.comment ~ '^(101|102|103|104|105)$' then 1
                    else 0 end
                else 0
            end
        ) as close_with_reason
    from posts p
    left join posthistory ph
      on ph.postid = p.id
     and ph.posthistorytypeid in (10,11)
    where p.posttypeid = 1
    group by p.owneruserid
),
user_quality_score as (
    select
        ua.user_id,
        coalesce(ua.answers,0) as answers,
        coalesce(ua.questions,0) as questions,
        coalesce(ua.total_post_score,0) as total_post_score,
        coalesce(ua.total_views,0) as total_views,
        coalesce(ad.a_avg_score,0) as a_avg_score,
        coalesce(qd.q_avg_score,0) as q_avg_score,
        coalesce(qd.q_with_accept,0) as q_with_accept,
        coalesce(ad.a_pos_count,0) as a_pos_count,
        coalesce(ad.a_neg_count,0) as a_neg_count,
        coalesce(qd.q_p90_views,0) as q_p90_views,
        coalesce(b.gold_badges,0) as gold_badges,
        coalesce(b.silver_badges,0) as silver_badges,
        coalesce(b.bronze_badges,0) as bronze_badges,
        coalesce(b.tag_badges,0) as tag_badges,
        coalesce(c.comment_count,0) as comment_count,
        coalesce(c.avg_comment_score,0) as avg_comment_score,
        coalesce(c.thanks_count,0) as thanks_count,
        coalesce(uc.close_events,0) as close_events,
        coalesce(uc.reopen_events,0) as reopen_events,
        case
            when coalesce(ua.answers,0) + coalesce(ua.questions,0) = 0 then null
            else round(
                (
                0.35 * coalesce(ad.a_avg_score,0) +
                0.25 * coalesce(qd.q_avg_score,0) +
                0.10 * greatest(least(coalesce(qd.q_p90_views,0), 5000), 0) / 5000 +
                0.10 * least(coalesce(b.gold_badges,0) * 3 + coalesce(b.silver_badges,0) * 1.5 + coalesce(b.bronze_badges,0) * 0.5, 30) / 30 +
                0.05 * least(coalesce(c.avg_comment_score,0), 5) / 5 +
                0.10 * least(coalesce(ua.total_views,0), 100000) / 100000 -
                0.05 * least(coalesce(uc.close_events,0), 20) / 20
                ), 4)
        end as quality_score
    from user_activity ua
    left join a_detail ad on ad.user_id = ua.user_id
    left join q_detail qd on qd.user_id = ua.user_id
    left join badge_tally b on b.user_id = ua.user_id
    left join commenters c on c.user_id = ua.user_id
    left join user_closure uc on uc.user_id = ua.user_id
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.website_host,
        uq.quality_score,
        row_number() over (
            order by coalesce(uq.quality_score, -1) desc,
                     ru.reputation desc,
                     ru.creationdate desc,
                     ru.user_id
        ) as overall_rank
    from recent_users ru
    left join user_quality_score uq on uq.user_id = ru.user_id
),
activity_span as (
    select
        upw.user_id,
        max(upw.activity_anchor) as last_activity_anchor,
        min(upw.activity_anchor) as first_activity_anchor,
        count(*) as posts_in_window,
        sum(case when upw.score_rank = 1 then 1 else 0 end) as top_scored_posts
    from user_post_windows upw
    where upw.rn_by_user <= 500
    group by upw.user_id
),
best_tag_per_user as (
    select tt.user_id, tt.tag, tt.tag_q_count
    from top_tags tt
    where tt.tag_rank = 1
),
outer_union as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.website_host,
        ru.overall_rank,
        uq.quality_score,
        aspan.posts_in_window,
        aspan.top_scored_posts,
        aspan.first_activity_anchor,
        aspan.last_activity_anchor,
        bt.tag as top_tag,
        bt.tag_q_count
    from ranked_users ru
    left join user_quality_score uq on uq.user_id = ru.user_id
    left join activity_span aspan on aspan.user_id = ru.user_id
    left join best_tag_per_user bt on bt.user_id = ru.user_id
    where ru.overall_rank <= 200

    union all

    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        null as overall_rank,
        null as quality_score,
        null as posts_in_window,
        null as top_scored_posts,
        null as first_activity_anchor,
        null as last_activity_anchor,
        null as top_tag,
        null as tag_q_count
    from users u
    where not exists (select 1 from posts p where p.owneruserid = u.id)
)
select
    ou.user_id,
    ou.displayname,
    ou.reputation,
    ou.creationdate,
    coalesce(nullif(ou.location,''), 'Unknown') as location,
    ou.website_host,
    ou.overall_rank,
    ou.quality_score,
    ou.posts_in_window,
    ou.top_scored_posts,
    cast(extract(epoch from (ou.last_activity_anchor - ou.first_activity_anchor)) as bigint) as active_seconds_span,
    ou.top_tag,
    ou.tag_q_count,
    case
        when ou.overall_rank is null then 'NoPosts'
        when ou.quality_score is null then 'Inactive'
        when ou.quality_score >= 0.8 then 'Elite'
        when ou.quality_score >= 0.6 then 'Great'
        when ou.quality_score >= 0.4 then 'Good'
        when ou.quality_score >= 0.2 then 'Fair'
        else 'New/Low'
    end as cohort_bucket
from outer_union ou
where (
    ou.overall_rank is null
    or ou.overall_rank <= 200
)
order by
    (ou.overall_rank is null) asc,
    ou.overall_rank nulls last,
    ou.quality_score desc nulls last,
    ou.reputation desc nulls last,
    ou.user_id asc;