-- {"query": "151.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3135} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
        (extract(epoch from now()) - extract(epoch from u.creationdate)) / 86400.0 as days_since_signup
    from users u
    where u.creationdate >= now() - interval '5 years'
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as question_views,
        avg(nullif(p.answercount,0)) filter (where p.posttypeid = 1) as avg_answer_count_on_questions,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
user_comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        avg(coalesce(c.score,0)) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_count,
        sum(coalesce(a.score,0)) as accepted_score_sum
    from posts q
    join posts a
      on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
vote_agg as (
    select
        p.owneruserid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_received,
        count(*) filter (where v.votetypeid = 3) as downvotes_received,
        count(*) filter (where v.votetypeid = 12) as spam_flags_received
    from posts p
    left join votes v
      on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
dup_links as (
    select
        q.owneruserid as user_id,
        count(*) as duplicates_marked_against
    from postlinks pl
    join posts q on q.id = pl.postid and q.posttypeid = 1
    where pl.linktypeid = 3
    group by q.owneruserid
),
hot_bumps as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 52) as first_hot,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 53) as last_hot_removed,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps
    from posthistory ph
    where ph.posthistorytypeid in (50,52,53)
    group by ph.postid
),
recent_question_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as recent_q_count,
        avg(coalesce(p.score,0)) as recent_q_avg_score,
        percentile_disc(0.9) within group (order by coalesce(p.viewcount,0)) as p90_views_recent_q
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= now() - interval '2 years'
      and p.owneruserid is not null
    group by p.owneruserid
),
tag_expertise_sample as (
    select
        p.owneruserid as user_id,
        string_agg(distinct lower(trim(tname)), ', ' order by lower(trim(tname))) as sample_tags
    from (
        select
            p.id,
            p.owneruserid,
            unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tname
        from posts p
        where p.posttypeid = 1
          and p.tags is not null
          and p.owneruserid is not null
          and p.creationdate >= now() - interval '3 years'
    ) x
    group by x.owneruserid
),
per_post_quality as (
    select
        p.id,
        p.owneruserid as user_id,
        p.posttypeid,
        p.score,
        p.viewcount,
        coalesce(vu.upvotes,0) as upvotes,
        coalesce(vd.downvotes,0) as downvotes,
        case
            when p.posttypeid = 1 then
                coalesce(p.score,0) * 2
                + coalesce(p.viewcount,0) * 0.01
                + coalesce(p.favoritecount,0) * 1.5
                - coalesce(vd.downvotes,0) * 1
            when p.posttypeid = 2 then
                coalesce(p.score,0) * 3
                + case when p.id = any(array(select acceptedanswerid from posts where acceptedanswerid is not null)) then 15 else 0 end
                - coalesce(vd.downvotes,0) * 1.5
            else coalesce(p.score,0)
        end as quality_score
    from posts p
    left join lateral (
        select count(*) as upvotes
        from votes v
        where v.postid = p.id and v.votetypeid = 2
    ) vu on true
    left join lateral (
        select count(*) as downvotes
        from votes v
        where v.postid = p.id and v.votetypeid = 3
    ) vd on true
    where p.owneruserid is not null
),
user_quality as (
    select
        user_id,
        avg(quality_score) as avg_quality_score,
        percentile_cont(0.5) within group (order by quality_score) as median_quality_score,
        stddev_pop(quality_score) as std_quality_score,
        count(*) as posts_count_for_quality
    from per_post_quality
    group by user_id
),
ranked_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.days_since_signup,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.post_score_sum,0) as post_score_sum,
        coalesce(ua.question_views,0) as question_views,
        ua.avg_answer_count_on_questions,
        ua.last_post_activity,
        ucs.comment_count,
        ucs.avg_comment_score,
        ucs.last_comment_date,
        ub.badge_count,
        ub.gold_count,
        ub.silver_count,
        ub.bronze_count,
        ub.last_badge_date,
        aa.accepted_count,
        aa.accepted_score_sum,
        va.upvotes_received,
        va.downvotes_received,
        va.spam_flags_received,
        dl.duplicates_marked_against,
        rqm.recent_q_count,
        rqm.recent_q_avg_score,
        rqm.p90_views_recent_q,
        tes.sample_tags,
        uq.avg_quality_score,
        uq.median_quality_score,
        uq.std_quality_score,
        uq.posts_count_for_quality,
        row_number() over (
            order by
                coalesce(aa.accepted_count,0) desc,
                coalesce(va.upvotes_received,0) desc,
                coalesce(ua.post_score_sum,0) desc,
                coalesce(uq.avg_quality_score, -1e9) desc
        ) as perf_rank
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_comment_stats ucs on ucs.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join accepted_answers aa on aa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join dup_links dl on dl.user_id = ru.user_id
    left join recent_question_metrics rqm on rqm.user_id = ru.user_id
    left join tag_expertise_sample tes on tes.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
),
activity_trends as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) filter (where p.posttypeid = 1) as q_monthly,
        count(*) filter (where p.posttypeid = 2) as a_monthly,
        sum(coalesce(p.score,0)) as score_monthly
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= now() - interval '2 years'
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
trend_stats as (
    select
        at.user_id,
        corr(extract(epoch from at.month)::numeric, at.score_monthly::numeric) as score_trend_corr,
        sum(at.a_monthly) as answers_2y,
        sum(at.q_monthly) as questions_2y
    from activity_trends at
    group by at.user_id
),
moderation_events as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid in (10,12,14,19)) as mod_events_count,
        max(ph.creationdate) as last_mod_event
    from posts p
    left join posthistory ph on ph.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
final_scores as (
    select
        ru.*,
        ts.score_trend_corr,
        ts.answers_2y,
        ts.questions_2y,
        me.mod_events_count,
        me.last_mod_event,
        -- composite performance score with various weights and null handling
        (
            coalesce(aa.accepted_count,0) * 5
            + coalesce(va.upvotes_received,0) * 0.5
            - coalesce(va.downvotes_received,0) * 1.0
            - coalesce(va.spam_flags_received,0) * 2.0
            + coalesce(ub.gold_count,0) * 8
            + coalesce(ub.silver_count,0) * 3
            + coalesce(ub.bronze_count,0) * 1
            + coalesce(uq.avg_quality_score,0) * 0.8
            + coalesce(rqm.recent_q_avg_score,0) * 2
            + greatest(coalesce(ts.score_trend_corr,0), -1) * 10
            - least(coalesce(me.mod_events_count,0), 50) * 0.5
            + coalesce(uq.posts_count_for_quality,0) * 0.1
        ) as composite_score
    from ranked_users ru
    left join accepted_answers aa on aa.user_id = ru.user_id
    left join vote_agg va on va.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join recent_question_metrics rqm on rqm.user_id = ru.user_id
    left join trend_stats ts on ts.user_id = ru.user_id
    left join moderation_events me on me.user_id = ru.user_id
),
top_users as (
    select
        fs.*,
        dense_rank() over (order by fs.composite_score desc, fs.perf_rank) as overall_rank
    from final_scores fs
)
select
    tu.overall_rank,
    tu.user_id,
    tu.displayname,
    tu.reputation,
    tu.days_since_signup,
    tu.q_count,
    tu.a_count,
    tu.accepted_count,
    tu.upvotes_received,
    tu.downvotes_received,
    tu.badge_count,
    tu.gold_count,
    tu.silver_count,
    tu.bronze_count,
    tu.avg_quality_score,
    tu.median_quality_score,
    tu.std_quality_score,
    tu.posts_count_for_quality,
    tu.recent_q_count,
    tu.recent_q_avg_score,
    tu.p90_views_recent_q,
    tu.score_trend_corr,
    tu.mod_events_count,
    tu.sample_tags,
    tu.websiteurl_norm,
    coalesce(to_char(tu.last_post_activity, 'YYYY-MM-DD'), 'N/A') as last_post_activity,
    coalesce(to_char(tu.last_comment_date, 'YYYY-MM-DD'), 'N/A') as last_comment_date,
    coalesce(to_char(tu.last_badge_date, 'YYYY-MM-DD'), 'N/A') as last_badge_date,
    coalesce(to_char(tu.last_mod_event, 'YYYY-MM-DD'), 'N/A') as last_mod_event,
    tu.composite_score,
    case
        when tu.accepted_count is null or tu.accepted_count = 0 then 'NOVICE'
        when tu.accepted_count < 5 then 'INTERMEDIATE'
        when tu.accepted_count < 20 then 'ADVANCED'
        else 'EXPERT'
    end as accepted_tier,
    case
        when tu.sample_tags is null then 'No primary tags'
        when length(tu.sample_tags) > 120 then substring(tu.sample_tags from 1 for 117) || '...'
        else tu.sample_tags
    end as primary_tags_sample
from top_users tu
where (
        tu.q_count + tu.a_count
     ) > 0
  and (
        tu.downvotes_received is null
        or tu.downvotes_received < tu.upvotes_received
      )
  and (
        tu.avg_quality_score is null
        or tu.avg_quality_score >= (
            select avg(avg_quality_score)
            from user_quality
        )
      )
order by tu.overall_rank
limit 200;