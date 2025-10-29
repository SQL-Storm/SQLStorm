with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.websiteurl,
        u.creationdate,
        date_trunc('month', u.lastaccessdate) as last_access_month,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(b.id) as total_badges,
        max(b.date) as last_badge_at
    from users u
    left join badges b
      on b.userid = u.id
    where u.lastaccessdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days'
    group by u.id, u.displayname, u.reputation, u.location, u.websiteurl, u.creationdate, date_trunc('month', u.lastaccessdate)
),
user_activity as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.viewcount,0)) as total_views,
        sum(coalesce(p.score,0)) as total_score,
        sum(coalesce(p.commentcount,0)) as total_comments,
        min(p.creationdate) as first_post_at,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p
      on p.owneruserid = u.id
    group by u.id
),
question_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as questions,
        avg(nullif(p.viewcount,0)) as avg_q_views,
        avg(nullif(p.score,0)) as avg_q_score,
        sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_qs,
        percentile_cont(0.5) within group (order by coalesce(p.viewcount,0)) as q_views_p50,
        percentile_cont(0.9) within group (order by coalesce(p.viewcount,0)) as q_views_p90
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as answers,
        avg(nullif(p.score,0)) as avg_a_score,
        sum(case when p.score > 0 then 1 else 0 end) as positive_answers,
        sum(case when p.score < 0 then 1 else 0 end) as negative_answers
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
comment_reactions as (
    select
        c.userid as user_id,
        count(*) as comments_made,
        avg(coalesce(c.score,0)) as avg_comment_score,
        sum(case when coalesce(c.score,0) > 0 then 1 else 0 end) as upvoted_comments
    from comments c
    group by c.userid
),
vote_breakdown as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from posts p
    left join votes v
      on v.postid = p.id
    group by p.owneruserid
),
tag_usage as (
    select
        q.owneruserid as user_id,
        lower(trim(both '<>' from unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')))) as tagname
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
),
top_tags as (
    select
        user_id,
        tagname,
        count(*) as tag_count,
        row_number() over (partition by user_id order by count(*) desc, tagname) as rn
    from tag_usage
    group by user_id, tagname
),
duplicates_and_links as (
    select
        p.owneruserid as user_id,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as dup_links,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as normal_links
    from posts p
    left join postlinks pl
      on pl.postid = p.id
    group by p.owneruserid
),
closures as (
    select
        ph.postid,
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopened_events,
        count(*) filter (where ph.posthistorytypeid in (35,36)) as migrations
    from posthistory ph
    join posts p on p.id = ph.postid
    group by ph.postid, p.owneruserid
),
user_levels as (
    select
        r.user_id,
        case
            when r.reputation >= 100000 then 'legend'
            when r.reputation >= 20000 then 'expert'
            when r.reputation >= 5000 then 'advanced'
            when r.reputation >= 500 then 'intermediate'
            else 'beginner'
        end as level
    from recent_active_users r
),
post_streaks as (
    select
        s2.owneruserid as user_id,
        max(streak_len) as max_daily_streak
    from (
        select
            owneruserid,
            creation_day,
            count(*) over (partition by owneruserid, grp) as streak_len
        from (
            select
                owneruserid,
                date_trunc('day', creationdate) as creation_day,
                date_trunc('day', creationdate) - (row_number() over (partition by owneruserid order by date_trunc('day', creationdate)) * interval '1 day') as grp
            from posts
            where owneruserid is not null
        ) s1
        group by owneruserid, creation_day, grp
    ) s2
    group by s2.owneruserid
),
recent_hot_questions as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        1 as is_hot
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
      and p.score >= 10
      and coalesce(p.viewcount,0) >= 1000
),
user_hot_summary as (
    select
        rhq.user_id,
        count(*) as hot_q_count_30d,
        avg(rhq.score) as hot_q_avg_score,
        avg(rhq.viewcount) as hot_q_avg_views
    from recent_hot_questions rhq
    group by rhq.user_id
),
activity_window as (
    select
        u.id as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) as posts_in_month,
        sum(coalesce(p.score,0)) as score_in_month
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, date_trunc('month', p.creationdate)
),
activity_rank as (
    select
        user_id,
        month,
        posts_in_month,
        score_in_month,
        rank() over (partition by month order by posts_in_month desc nulls last, score_in_month desc nulls last) as rank_in_month
    from activity_window
),
user_null_variations as (
    select
        u.id as user_id,
        coalesce(nullif(trim(u.displayname), ''), '(anonymous)') as norm_displayname,
        nullif(trim(u.location), '') as norm_location,
        case when u.websiteurl ilike 'http%' then u.websiteurl else null end as norm_website
    from users u
),
final_scores as (
    select
        r.user_id,
        r.displayname,
        r.reputation,
        r.location,
        r.websiteurl,
        r.creationdate,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        ua.q_count,
        ua.a_count,
        ua.total_views,
        ua.total_score,
        ua.total_comments,
        um.questions,
        um.avg_q_views,
        um.avg_q_score,
        um.accepted_qs,
        am.answers,
        am.avg_a_score,
        am.positive_answers,
        am.negative_answers,
        vr.upvotes_received,
        vr.downvotes_received,
        vr.bounty_started,
        vr.bounty_awarded,
        coalesce(dal.dup_links,0) as dup_links,
        coalesce(dal.normal_links,0) as normal_links,
        coalesce(c.closed_events,0) as closed_events,
        coalesce(c.reopened_events,0) as reopened_events,
        coalesce(c.migrations,0) as migrations,
        coalesce(ps.max_daily_streak,0) as max_daily_streak,
        uhs.hot_q_count_30d,
        uhs.hot_q_avg_score,
        uhs.hot_q_avg_views,
        lv.level,
        tt.tagname as top_tag,
        aw.rank_in_month as current_month_rank,
        case
            when ua.a_count > 0 then cast(ua.total_score as numeric) / ua.a_count
            else null
        end as avg_score_per_answer,
        case
            when ua.q_count > 0 then cast(ua.total_views as numeric) / ua.q_count
            else null
        end as avg_views_per_question,
        least(greatest(coalesce(ua.total_score,0), -10000), 10000) as clipped_total_score,
        coalesce(nullif(r.displayname,''), '(unknown)') || ' [' || r.user_id || ']' as labeled_user,
        coalesce(ua.total_score,0) as total_score_for_ordering
    from recent_active_users r
    left join user_activity ua on ua.user_id = r.user_id
    left join question_metrics um on um.user_id = r.user_id
    left join answer_metrics am on am.user_id = r.user_id
    left join vote_breakdown vr on vr.user_id = r.user_id
    left join duplicates_and_links dal on dal.user_id = r.user_id
    left join closures c on c.user_id = r.user_id
    left join user_hot_summary uhs on uhs.user_id = r.user_id
    left join user_levels lv on lv.user_id = r.user_id
    left join post_streaks ps on ps.user_id = r.user_id
    left join (
        select user_id, tagname from top_tags where rn = 1
    ) tt on tt.user_id = r.user_id
    left join activity_rank aw on aw.user_id = r.user_id and aw.month = date_trunc('month', cast('2024-10-01 12:34:56' as timestamp))
)
select
    fs.user_id,
    fs.labeled_user,
    fs.level,
    coalesce(fs.top_tag, '(none)') as top_tag,
    fs.reputation,
    fs.total_badges,
    fs.gold_badges,
    fs.silver_badges,
    fs.bronze_badges,
    fs.q_count,
    fs.a_count,
    fs.accepted_qs,
    fs.upvotes_received,
    fs.downvotes_received,
    fs.bounty_started,
    fs.bounty_awarded,
    fs.dup_links,
    fs.normal_links,
    fs.closed_events,
    fs.reopened_events,
    fs.migrations,
    fs.max_daily_streak,
    fs.hot_q_count_30d,
    round(cast(fs.hot_q_avg_score as numeric), 2) as hot_q_avg_score,
    round(cast(fs.hot_q_avg_views as numeric), 2) as hot_q_avg_views,
    fs.current_month_rank,
    round(cast(fs.avg_score_per_answer as numeric), 2) as avg_score_per_answer,
    round(cast(fs.avg_views_per_question as numeric), 2) as avg_views_per_question,
    fs.clipped_total_score,
    (
        select count(*)
        from posts p
        where p.owneruserid = fs.user_id
          and p.posttypeid = 1
          and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    ) as questions_last_90d,
    (
        select count(*)
        from posts p
        where p.owneruserid = fs.user_id
          and p.posttypeid = 2
          and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
    ) as answers_last_90d,
    (
        select coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end),0)
        from votes v
        join posts p on p.id = v.postid
        where p.owneruserid = fs.user_id
          and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days'
    ) as net_votes_30d,
    (
        select string_agg(t.tagname, ', ' order by t.tagname)
        from (
            select tagname
            from top_tags
            where user_id = fs.user_id and rn <= 3
            order by tag_count desc, tagname
        ) t
    ) as top3_tags,
    case
        when coalesce(fs.q_count,0) + coalesce(fs.a_count,0) = 0 then 'inactive'
        when fs.q_count > 0 and fs.a_count = 0 then 'asker-only'
        when fs.a_count > 0 and fs.q_count = 0 then 'answerer-only'
        when fs.a_count > fs.q_count then 'answer-heavy'
        else 'balanced'
    end as participation_mix
from final_scores fs
where
    coalesce(fs.reputation,0) >= 100
    and (
        fs.hot_q_count_30d is not null
        or coalesce(fs.q_count,0) + coalesce(fs.a_count,0) >= 10
        or coalesce(fs.total_badges,0) >= 5
    )
    and not (coalesce(fs.closed_events,0) > coalesce(fs.reopened_events,0) * 10)
order by
    fs.level desc,
    coalesce(fs.hot_q_count_30d, 0) desc,
    coalesce(fs.total_score_for_ordering, 0) desc,
    fs.reputation desc,
    fs.user_id
limit 200;