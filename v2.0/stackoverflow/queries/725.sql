-- {"query": "725.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2906}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(u.location), ''), 'Unknown') as normalized_location,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as question_count,
        count(*) filter (where p.posttypeid = 2) as answer_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) as total_views,
        max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
post_metrics as (
    select
        p.id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        case
            when p.posttypeid = 1 then p.answercount
            else null
        end as answer_count,
        case
            when p.posttypeid = 1 and p.acceptedanswerid is not null then 1
            else 0
        end as has_accepted_answer
    from posts p
    left join votes_agg va on va.postid = p.id
),
tag_counts as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
),
user_tag_pref as (
    select
        p.owneruserid as user_id,
        tc.tagname,
        count(*) as tag_uses,
        avg(p.score) as avg_score_in_tag
    from posts p
    join tag_counts tc on tc.question_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, tc.tagname
),
best_tag_per_user as (
    select distinct on (user_id)
        user_id,
        tagname,
        tag_uses,
        avg_score_in_tag
    from user_tag_pref
    order by user_id, tag_uses desc, avg_score_in_tag desc, tagname
),
badges_agg as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_closures as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen,
        max(
            case
                when ph.posthistorytypeid = 10 then cast(nullif(ph.comment, '') as integer)
                else null
            end
        ) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
dup_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
question_quality as (
    select
        pm.id as post_id,
        pm.user_id,
        pm.score,
        pm.viewcount,
        pm.has_accepted_answer,
        coalesce(pc.close_events,0) as close_events,
        coalesce(pc.reopen_events,0) as reopen_events,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.linked_links,0) as linked_links,
        case
            when pm.viewcount is null or pm.viewcount = 0 then null
            else (cast(pm.score as numeric) / greatest(pm.viewcount,1))
        end as score_per_view,
        case
            when coalesce(pc.close_events,0) > 0 then 1
            else 0
        end as was_closed_flag
    from post_metrics pm
    left join post_closures pc on pc.postid = pm.id
    left join dup_links dl on dl.postid = pm.id
    where pm.posttypeid = 1
),
answer_quality as (
    select
        pm.id as post_id,
        pm.user_id,
        pm.score,
        pm.upvotes,
        pm.downvotes,
        coalesce(pm.bounty_awarded,0) as bounty_awarded
    from post_metrics pm
    where pm.posttypeid = 2
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created,
        ru.normalized_location,
        ua.question_count,
        ua.answer_count,
        ua.total_post_score,
        ua.total_views,
        ua.last_activity,
        ba.gold_badges,
        ba.silver_badges,
        ba.bronze_badges,
        ba.total_badges,
        ba.last_badge_date,
        btp.tagname as favorite_tag,
        btp.tag_uses as favorite_tag_uses,
        btp.avg_score_in_tag as favorite_tag_avg_score
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join badges_agg ba on ba.user_id = ru.user_id
    left join best_tag_per_user btp on btp.user_id = ru.user_id
    where ru.rn <= 2000
),
post_level_scores as (
    select
        qq.user_id,
        percentile_cont(0.5) within group (order by coalesce(qq.score,0)) as q_score_p50,
        avg(coalesce(qq.score,0)) as q_score_avg,
        avg(coalesce(qq.score_per_view,0)) as q_score_per_view_avg,
        sum(qq.was_closed_flag) as q_closed_count,
        sum(qq.duplicate_links) as q_dup_links
    from question_quality qq
    group by qq.user_id
),
answer_level_scores as (
    select
        aq.user_id,
        percentile_cont(0.5) within group (order by coalesce(aq.score,0)) as a_score_p50,
        avg(coalesce(aq.score,0)) as a_score_avg,
        sum(coalesce(aq.bounty_awarded,0)) as a_bounty_total
    from answer_quality aq
    group by aq.user_id
),
location_stats as (
    select
        normalized_location,
        count(*) as users_in_location,
        avg(reputation) as avg_rep_location
    from (
        select
            coalesce(nullif(trim(u.location), ''), 'Unknown') as normalized_location,
            u.reputation
        from users u
    ) t
    group by normalized_location
),
activity_streaks as (
    select
        p.owneruserid as user_id,
        count(*) as active_days,
        max(p.last_active) as last_active
    from (
        select distinct
            owneruserid,
            date_trunc('day', lastactivitydate) as active_day,
            max(lastactivitydate) over (partition by owneruserid, date_trunc('day', lastactivitydate)) as last_active
        from posts
        where owneruserid is not null
          and lastactivitydate is not null
    ) p
    group by p.owneruserid
),
ranked_users as (
    select
        ur.user_id,
        ur.displayname,
        ur.reputation,
        ur.user_created,
        ur.normalized_location,
        ls.users_in_location,
        ls.avg_rep_location,
        pls.q_score_p50,
        pls.q_score_avg,
        pls.q_score_per_view_avg,
        pls.q_closed_count,
        pls.q_dup_links,
        als.a_score_p50,
        als.a_score_avg,
        als.a_bounty_total,
        ast.active_days,
        ast.last_active,
        ur.question_count,
        ur.answer_count,
        ur.total_post_score,
        ur.total_views,
        ur.last_activity,
        ur.gold_badges,
        ur.silver_badges,
        ur.bronze_badges,
        ur.total_badges,
        ur.last_badge_date,
        ur.favorite_tag,
        ur.favorite_tag_uses,
        ur.favorite_tag_avg_score,
        row_number() over (
            order by
                coalesce(ur.total_post_score,0) desc,
                coalesce(ur.answer_count,0) desc,
                coalesce(ur.question_count,0) desc,
                ur.reputation desc,
                ur.user_id
        ) as perf_rank
    from user_rollup ur
    left join location_stats ls on ls.normalized_location = ur.normalized_location
    left join post_level_scores pls on pls.user_id = ur.user_id
    left join answer_level_scores als on als.user_id = ur.user_id
    left join activity_streaks ast on ast.user_id = ur.user_id
),
dup_question_pairs as (
    select
        pl.postid as dup_id,
        pl.relatedpostid as canonical_id,
        p1.owneruserid as dup_owner,
        p2.owneruserid as canonical_owner,
        case when p1.owneruserid = p2.owneruserid then 1 else 0 end as same_owner
    from postlinks pl
    join posts p1 on p1.id = pl.postid and p1.posttypeid = 1
    join posts p2 on p2.id = pl.relatedpostid and p2.posttypeid = 1
    where pl.linktypeid = 3
),
user_dup_stats as (
    select
        dqp.dup_owner as user_id,
        count(*) as dup_made,
        sum(same_owner) as dup_same_owner
    from dup_question_pairs dqp
    group by dqp.dup_owner
),
final as (
    select
        r.perf_rank,
        r.user_id,
        r.displayname,
        r.reputation,
        r.normalized_location,
        r.users_in_location,
        r.avg_rep_location,
        r.question_count,
        r.answer_count,
        r.total_post_score,
        r.total_views,
        r.last_activity,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.total_badges,
        r.last_badge_date,
        r.favorite_tag,
        r.favorite_tag_uses,
        r.favorite_tag_avg_score,
        r.q_score_p50,
        r.q_score_avg,
        r.q_score_per_view_avg,
        r.q_closed_count,
        r.q_dup_links,
        r.a_score_p50,
        r.a_score_avg,
        r.a_bounty_total,
        r.active_days,
        r.last_active,
        coalesce(uds.dup_made,0) as duplicates_made,
        coalesce(uds.dup_same_owner,0) as duplicates_same_owner,
        case
            when r.total_views is null or r.total_views = 0 then null
            else round((cast(r.total_post_score as numeric) / greatest(r.total_views,1)), 6)
        end as user_score_per_view,
        case
            when r.total_badges > 0 then round((cast(r.gold_badges as numeric) / r.total_badges) * 100, 2)
            else null
        end as pct_gold_badges,
        case
            when r.answer_count > 0 then round((cast(r.a_bounty_total as numeric) / r.answer_count), 2)
            else null
        end as avg_bounty_per_answer,
        case
            when r.question_count > 0 then round((cast(r.q_closed_count as numeric) / r.question_count) * 100, 2)
            else 0
        end as pct_questions_closed
    from ranked_users r
    left join user_dup_stats uds on uds.user_id = r.user_id
)
select *
from final
where (
    (coalesce(a_score_avg, 0) + coalesce(q_score_avg, 0)) >= 5
    or (pct_gold_badges is not null and pct_gold_badges > 5)
    or (user_score_per_view is not null and user_score_per_view > 0.01)
)
and (
    favorite_tag is null
    or length(favorite_tag) > 1
)
and (
    last_activity is null
    or last_activity >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
)
order by perf_rank
limit 200;