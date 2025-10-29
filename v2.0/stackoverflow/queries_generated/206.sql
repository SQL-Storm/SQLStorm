-- {"query": "206.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4124} 
with
recent_users as (
    select u.id as user_id,
           u.displayname,
           u.creationdate,
           u.location,
           u.reputation,
           u.upvotes,
           u.downvotes,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from users)
),
posts_last_2y as (
    select p.*
    from posts p
    where p.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
),
user_activity as (
    select
        ru.user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) as view_sum,
        max(p.lastactivitydate) as last_post_activity
    from recent_users ru
    left join posts_last_2y p
      on p.owneruserid = ru.user_id
    group by ru.user_id
),
comment_activity as (
    select
        ru.user_id,
        count(c.id) as c_count,
        sum(coalesce(c.score,0)) as c_score_sum,
        max(c.creationdate) as last_comment_activity
    from recent_users ru
    left join comments c
      on c.userid = ru.user_id
     and c.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from comments)
    group by ru.user_id
),
vote_activity as (
    select
        ru.user_id,
        count(v.id) filter (where v.votetypeid = 2) as upmods_given,
        count(v.id) filter (where v.votetypeid = 3) as downmods_given,
        count(v.id) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(case when v.votetypeid in (8,9) then v.bountyamount end,0)) as bounty_amount_total,
        max(v.creationdate) as last_vote_activity
    from recent_users ru
    left join votes v
      on v.userid = ru.user_id
     and v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from votes)
    group by ru.user_id
),
badges_ranked as (
    select
        b.userid,
        b.name,
        b.class,
        b.date,
        row_number() over (partition by b.userid order by b.class, b.date desc, b.id desc) as rn_most_recent_by_class,
        dense_rank() over (partition by b.userid order by b.date desc) as dr_all
    from badges b
),
user_badge_summary as (
    select
        ru.user_id,
        count(*) as badge_count,
        count(*) filter (where class = 1) as gold_count,
        count(*) filter (where class = 2) as silver_count,
        count(*) filter (where class = 3) as bronze_count,
        max(date) as last_badge_date,
        string_agg(distinct case when rn_most_recent_by_class = 1 then name end, ', ' order by class nulls last) as recent_badges_by_class
    from recent_users ru
    left join badges_ranked br on br.userid = ru.user_id
    group by ru.user_id
),
tag_usage as (
    select
        p.owneruserid as user_id,
        lower(tn.tag) as tag,
        count(*) as tag_uses,
        sum(p.score) as tag_score_sum
    from posts_last_2y p
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(p.tags,''), 2, greatest(length(coalesce(p.tags,''))-2,0)), '><')) as tag
    ) as tn
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid, lower(tn.tag)
),
top_tags as (
    select tu.user_id,
           string_agg(tu.tag || ':' || tu.tag_uses::text, ', ' order by tu.tag_uses desc, tu.tag asc) filter (where seq <= 5) as top5_tags
    from (
        select
            tu.*,
            row_number() over (partition by tu.user_id order by tu.tag_uses desc, tu.tag asc) as seq
        from tag_usage tu
    ) tu
    where seq <= 5
    group by tu.user_id
),
question_answer_latency as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        min(a.creationdate) filter (where a.posttypeid = 2) as first_answer_time,
        q.creationdate as question_time,
        extract(epoch from (min(a.creationdate) filter (where a.posttypeid = 2) - q.creationdate)) / 3600.0 as hours_to_first_answer
    from posts_last_2y q
    left join posts a on a.parentid = q.id
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate
),
user_latency_stats as (
    select
        ru.user_id,
        avg(hours_to_first_answer) as avg_hours_to_first_answer,
        percentile_cont(0.5) within group (order by hours_to_first_answer) as median_hours_to_first_answer,
        count(*) filter (where hours_to_first_answer is not null) as answered_questions_count
    from recent_users ru
    left join question_answer_latency qal on qal.asker_id = ru.user_id
    group by ru.user_id
),
postlink_stats as (
    select
        ru.user_id,
        count(pl.id) filter (where pl.linktypeid = 1) as linked_posts,
        count(pl.id) filter (where pl.linktypeid = 3) as duplicate_links
    from recent_users ru
    left join posts p on p.owneruserid = ru.user_id
    left join postlinks pl on pl.postid = p.id
    group by ru.user_id
),
posthistory_closed as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_time,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 11) as first_reopen_time,
        max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
user_close_stats as (
    select
        ru.user_id,
        count(*) filter (where pcs.first_close_time is not null) as questions_closed,
        count(*) filter (where pcs.first_reopen_time is not null) as questions_reopened,
        count(*) filter (where pcs.close_reason_id = 101) as closed_as_duplicate
    from recent_users ru
    left join posts p on p.owneruserid = ru.user_id and p.posttypeid = 1
    left join posthistory_closed pcs on pcs.postid = p.id
    group by ru.user_id
),
engagement_window as (
    select
        ru.user_id,
        generate_series(date_trunc('month', (select max(creationdate) from posts) - interval '11 months'),
                        date_trunc('month', (select max(creationdate) from posts)),
                        interval '1 month') as month_start
    from recent_users ru
),
monthly_post_counts as (
    select
        ew.user_id,
        ew.month_start,
        count(p.id) filter (where p.posttypeid = 1) as q_cnt,
        count(p.id) filter (where p.posttypeid = 2) as a_cnt,
        sum(coalesce(p.score,0)) as score_sum
    from engagement_window ew
    left join posts p
      on p.owneruserid = ew.user_id
     and p.creationdate >= ew.month_start
     and p.creationdate < ew.month_start + interval '1 month'
    group by ew.user_id, ew.month_start
),
monthly_trends as (
    select
        m.user_id,
        m.month_start,
        m.q_cnt,
        m.a_cnt,
        m.score_sum,
        sum(m.q_cnt) over (partition by m.user_id order by m.month_start rows between 2 preceding and current row) as q_3mo_sum,
        sum(m.a_cnt) over (partition by m.user_id order by m.month_start rows between 2 preceding and current row) as a_3mo_sum,
        avg(m.score_sum) over (partition by m.user_id order by m.month_start rows between 5 preceding and current row) as score_6mo_avg
    from monthly_post_counts m
),
user_rank as (
    select
        ru.user_id,
        dense_rank() over (order by ua.a_count desc, ua.q_count desc, ru.reputation desc) as activity_rank,
        ntile(10) over (order by coalesce(ua.post_score_sum,0) + coalesce(ca.c_score_sum,0) desc) as score_decile
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
),
domain_activity as (
    select
        ru.domain,
        count(distinct ru.user_id) as users_from_domain,
        sum(ua.q_count + ua.a_count) as posts_from_domain
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    group by ru.domain
),
domain_flags as (
    select
        ru.user_id,
        case
            when da.users_from_domain >= 50 and da.posts_from_domain::numeric / nullif(da.users_from_domain,0) > 20 then 'high-activity-domain'
            when da.users_from_domain <= 2 then 'rare-domain'
            else 'normal-domain'
        end as domain_activity_bucket
    from recent_users ru
    left join domain_activity da on da.domain = ru.domain
),
accepted_answer_rate as (
    select
        ru.user_id,
        avg(case when q.acceptedanswerid is not null then 1.0 else 0.0 end) as accept_rate_as_asker
    from recent_users ru
    left join posts q on q.posttypeid = 1 and q.owneruserid = ru.user_id
    group by ru.user_id
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as answers_total,
        count(*) filter (where q.acceptedanswerid = a.id) as answers_accepted
    from posts a
    join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
    where a.creationdate >= (select date_trunc('month', max(creationdate)) - interval '24 months' from posts)
    group by a.owneruserid
),
answer_accept_rate as (
    select
        ru.user_id,
        case when aa.answers_total > 0 then aa.answers_accepted::numeric / aa.answers_total else null end as accept_rate_as_answerer
    from recent_users ru
    left join answer_accepts aa on aa.user_id = ru.user_id
),
activity_summary as (
    select
        ru.user_id,
        ru.displayname,
        ru.location,
        ru.reputation,
        ru.upvotes,
        ru.downvotes,
        ru.domain,
        ua.q_count,
        ua.a_count,
        ua.post_score_sum,
        ua.view_sum,
        ua.last_post_activity,
        ca.c_count,
        ca.c_score_sum,
        ca.last_comment_activity,
        va.upmods_given,
        va.downmods_given,
        va.bounties_interactions,
        va.bounty_amount_total,
        va.last_vote_activity,
        ubs.badge_count,
        ubs.gold_count,
        ubs.silver_count,
        ubs.bronze_count,
        ubs.last_badge_date,
        coalesce(nullif(ubs.recent_badges_by_class, ''), 'none') as recent_badges_by_class,
        tt.top5_tags,
        uls.avg_hours_to_first_answer,
        uls.median_hours_to_first_answer,
        uls.answered_questions_count,
        pls.linked_posts,
        pls.duplicate_links,
        ucs.questions_closed,
        ucs.questions_reopened,
        ucs.closed_as_duplicate,
        dflags.domain_activity_bucket,
        aar.accept_rate_as_asker,
        aarr.accept_rate_as_answerer
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join user_badge_summary ubs on ubs.user_id = ru.user_id
    left join top_tags tt on tt.user_id = ru.user_id
    left join user_latency_stats uls on uls.user_id = ru.user_id
    left join postlink_stats pls on pls.user_id = ru.user_id
    left join user_close_stats ucs on ucs.user_id = ru.user_id
    left join domain_flags dflags on dflags.user_id = ru.user_id
    left join accepted_answer_rate aar on aar.user_id = ru.user_id
    left join answer_accept_rate aarr on aarr.user_id = ru.user_id
),
anomalies as (
    select
        a.user_id,
        case
            when coalesce(a.a_count,0) = 0 and coalesce(a.q_count,0) = 0 and a.reputation > 10000 then 'high-rep-inactive'
            when coalesce(a.post_score_sum,0) < -50 and coalesce(a.downmods_given,0) > coalesce(a.upmods_given,0) * 2 then 'neg-score-and-heavy-downvoter'
            when coalesce(a.view_sum,0) > 100000 and coalesce(a.q_count,0) + coalesce(a.a_count,0) < 5 then 'few-posts-many-views'
            when a.avg_hours_to_first_answer is not null and a.avg_hours_to_first_answer > 720 then 'slow-answers'
            when a.accept_rate_as_answerer is not null and a.accept_rate_as_answerer > 0.9 and coalesce(a.a_count,0) >= 10 then 'very-high-answer-accept-rate'
            else null
        end as anomaly_flag
    from activity_summary a
),
final_scores as (
    select
        a.*,
        case
            when coalesce(a.a_count,0) + coalesce(a.q_count,0) = 0 then 0
            else
                greatest(0,
                    (coalesce(a.post_score_sum,0) + coalesce(a.c_score_sum,0))::numeric
                    + 0.5 * coalesce(a.view_sum,0)
                    + 50 * coalesce(a.gold_count,0)
                    + 20 * coalesce(a.silver_count,0)
                    + 10 * coalesce(a.bronze_count,0)
                    + 100 * coalesce(a.accept_rate_as_answerer,0)
                    + 20 * coalesce(a.answered_questions_count,0)
                    - 5 * coalesce(a.downmods_given,0)
                )
        end as performance_score
    from activity_summary a
)
select
    fs.user_id,
    fs.displayname,
    fs.location,
    fs.domain,
    fs.reputation,
    fs.q_count,
    fs.a_count,
    fs.post_score_sum,
    fs.view_sum,
    fs.c_count,
    fs.c_score_sum,
    coalesce(fs.top5_tags, 'none') as top5_tags,
    round(coalesce(fs.avg_hours_to_first_answer, 0)::numeric, 2) as avg_hours_to_first_answer,
    round(coalesce(fs.median_hours_to_first_answer, 0)::numeric, 2) as median_hours_to_first_answer,
    round(coalesce(fs.accept_rate_as_asker, 0)::numeric, 3) as accept_rate_as_asker,
    round(coalesce(fs.accept_rate_as_answerer, 0)::numeric, 3) as accept_rate_as_answerer,
    fs.badge_count,
    fs.gold_count,
    fs.silver_count,
    fs.bronze_count,
    fs.last_badge_date,
    fs.recent_badges_by_class,
    fs.linked_posts,
    fs.duplicate_links,
    fs.questions_closed,
    fs.questions_reopened,
    fs.closed_as_duplicate,
    fs.domain_activity_bucket,
    ur.activity_rank,
    ur.score_decile,
    array_remove(array_agg(distinct an.anomaly_flag) filter (where an.anomaly_flag is not null), null) as anomalies,
    round(fs.performance_score::numeric, 2) as performance_score,
    jsonb_build_object(
        'last_post_activity', fs.last_post_activity,
        'last_comment_activity', fs.last_comment_activity,
        'last_vote_activity', fs.last_vote_activity
    ) as last_activity_summary,
    jsonb_agg(
        jsonb_build_object(
            'month', mt.month_start,
            'q', mt.q_cnt,
            'a', mt.a_cnt,
            'score', mt.score_sum,
            'q3', mt.q_3mo_sum,
            'a3', mt.a_3mo_sum,
            'score6avg', round(coalesce(mt.score_6mo_avg,0)::numeric,2)
        )
        order by mt.month_start
    ) filter (where mt.user_id is not null) as monthly_trend
from final_scores fs
left join user_rank ur on ur.user_id = fs.user_id
left join anomalies an on an.user_id = fs.user_id
left join monthly_trends mt on mt.user_id = fs.user_id
group by
    fs.user_id, fs.displayname, fs.location, fs.domain, fs.reputation,
    fs.q_count, fs.a_count, fs.post_score_sum, fs.view_sum,
    fs.c_count, fs.c_score_sum, fs.top5_tags,
    fs.avg_hours_to_first_answer, fs.median_hours_to_first_answer,
    fs.accept_rate_as_asker, fs.accept_rate_as_answerer,
    fs.badge_count, fs.gold_count, fs.silver_count, fs.bronze_count,
    fs.last_badge_date, fs.recent_badges_by_class,
    fs.linked_posts, fs.duplicate_links,
    fs.questions_closed, fs.questions_reopened, fs.closed_as_duplicate,
    fs.domain_activity_bucket, ur.activity_rank, ur.score_decile,
    fs.last_post_activity, fs.last_comment_activity, fs.last_vote_activity,
    fs.performance_score
having
    coalesce(fs.q_count,0) + coalesce(fs.a_count,0) + coalesce(fs.c_count,0) > 0
order by fs.performance_score desc nulls last, ur.activity_rank asc
limit 200;