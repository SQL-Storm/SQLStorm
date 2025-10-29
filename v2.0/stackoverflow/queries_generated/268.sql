-- {"query": "268.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2815} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), '(none)') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
),
q_posts as (
    select
        p.id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        p.closeddate,
        p.acceptedanswerid,
        p.posttypeid
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select
        p.id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
first_answer as (
    select
        ap.question_id,
        min(ap.creationdate) as first_answer_date
    from a_posts ap
    group by ap.question_id
),
accepted_answer as (
    select
        q.id as question_id,
        ap.id as answer_id,
        ap.creationdate as accepted_date
    from q_posts q
    join a_posts ap on ap.id = q.acceptedanswerid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) as total_votes
    from votes v
    where v.creationdate >= (select max(p.creationdate) - interval '365 days' from posts p)
    group by v.postid
),
tag_exploded as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from q_posts q
    where q.tags is not null and q.tags like '<%>'
),
tag_rank as (
    select
        te.tagname,
        count(*) as tag_q_count,
        dense_rank() over (order by count(*) desc) as tag_rank_overall
    from tag_exploded te
    group by te.tagname
),
user_q as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        q.id as question_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.closeddate,
        q.acceptedanswerid
    from recent_users ru
    left join q_posts q on q.owneruserid = ru.user_id
),
q_metrics as (
    select
        uq.user_id,
        uq.question_id,
        uq.creationdate as q_created,
        uq.viewcount,
        uq.score as q_score,
        coalesce(va.upvotes,0) as q_upvotes,
        coalesce(va.downvotes,0) as q_downvotes,
        coalesce(va.favorites,0) as q_favorites,
        coalesce(va.total_votes,0) as q_total_votes,
        fa.first_answer_date,
        aa.accepted_date,
        extract(epoch from (aa.accepted_date - uq.creationdate)) / 3600.0 as hours_to_accept,
        extract(epoch from (fa.first_answer_date - uq.creationdate)) / 3600.0 as hours_to_first_answer,
        case
            when uq.closeddate is not null then 1
            when exists (
                select 1
                from posthistory ph
                where ph.postid = uq.question_id
                  and ph.posthistorytypeid = 10
            ) then 1
            else 0
        end as was_closed
    from user_q uq
    left join vote_agg va on va.postid = uq.question_id
    left join first_answer fa on fa.question_id = uq.question_id
    left join accepted_answer aa on aa.question_id = uq.question_id
),
q_tag_focus as (
    select
        te.question_id,
        min(tr.tag_rank_overall) as best_tag_rank,
        string_agg(te.tagname, ',' order by tr.tag_rank_overall nulls last, te.tagname) filter (where tr.tag_rank_overall <= 25) as top_tags_joined
    from tag_exploded te
    left join tag_rank tr on tr.tagname = te.tagname
    group by te.question_id
),
user_comment_engagement as (
    select
        u.id as user_id,
        count(*) filter (where c.score > 0) as pos_comments,
        count(*) filter (where c.score <= 0 or c.score is null) as nonpos_comments,
        max(c.creationdate) as last_comment_date
    from users u
    left join comments c on c.userid = u.id
    group by u.id
),
user_badges as (
    select
        b.userid as user_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_links_summary as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
question_quality as (
    select
        qm.*,
        coalesce(pls.linked_count,0) as linked_count,
        coalesce(pls.duplicate_count,0) as duplicate_count,
        case
            when qm.was_closed = 1 then -5
            else 0
        end
        + least(coalesce(qm.q_upvotes,0) - coalesce(qm.q_downvotes,0), 50)
        + greatest(least(coalesce(qm.viewcount,0) / 100, 50), 0)
        + case when qm.accepted_date is not null then 10 else 0 end
        - case when coalesce(pls.duplicate_count,0) > 0 then 15 else 0 end
        + case when coalesce(qt.best_tag_rank,99999) <= 25 then 5 else 0 end
        + case when coalesce(qm.q_favorites,0) > 0 then 3 else 0 end
        as quality_score
    from q_metrics qm
    left join post_links_summary pls on pls.postid = qm.question_id
    left join q_tag_focus qt on qt.question_id = qm.question_id
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        count(q.question_id) as questions_count,
        avg(nullif(q.quality_score,0)) filter (where q.quality_score is not null) as avg_quality_score,
        percentile_cont(0.5) within group (order by q.quality_score) as median_quality_score,
        avg(q.hours_to_first_answer) as avg_hours_to_first_answer,
        avg(q.hours_to_accept) as avg_hours_to_accept,
        sum(case when q.was_closed = 1 then 1 else 0 end) as closed_questions,
        sum(q.q_upvotes) as total_upvotes_on_q,
        sum(q.q_downvotes) as total_downvotes_on_q,
        sum(q.q_favorites) as total_favorites_on_q,
        max(q.q_created) as last_question_date
    from recent_users ru
    left join question_quality q on q.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.cohort_month
),
activity_window as (
    select
        ur.*,
        row_number() over (order by ur.avg_quality_score desc nulls last, ur.questions_count desc, ur.user_id) as rn_quality_desc,
        row_number() over (order by ur.questions_count desc, ur.user_id) as rn_volume_desc,
        row_number() over (order by ur.avg_hours_to_first_answer asc nulls last, ur.user_id) as rn_fast_answers
    from user_rollup ur
),
top_users as (
    select
        aw.*
    from activity_window aw
    where aw.rn_quality_desc <= 200
       or aw.rn_volume_desc <= 200
       or aw.rn_fast_answers <= 200
),
final_enriched as (
    select
        tu.*,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(ub.total_badges,0) as total_badges,
        uce.pos_comments,
        uce.nonpos_comments,
        greatest(coalesce(uce.last_comment_date, timestamp 'epoch'), coalesce(tu.last_question_date, timestamp 'epoch')) as last_activity_at,
        case
            when tu.reputation >= 20000 then 'legend'
            when tu.reputation >= 10000 then 'expert'
            when tu.reputation >= 3000 then 'advanced'
            when tu.reputation >= 1000 then 'intermediate'
            else 'novice'
        end as rep_bucket
    from top_users tu
    left join user_badges ub on ub.user_id = tu.user_id
    left join user_comment_engagement uce on uce.user_id = tu.user_id
),
cohorts as (
    select
        rep_bucket,
        cohort_month,
        count(*) as users_in_cohort,
        avg(questions_count) as avg_qs,
        avg(coalesce(avg_quality_score,0)) as avg_quality,
        avg(closed_questions) as avg_closed,
        percentile_cont(0.9) within group (order by coalesce(median_quality_score,0)) as p90_median_quality
    from final_enriched
    group by rep_bucket, cohort_month
),
null_safety as (
    select
        fe.*,
        case when fe.avg_quality_score is null and fe.median_quality_score is null and fe.questions_count = 0 then 1 else 0 end as inactive_flag
    from final_enriched fe
)
select
    fe.user_id,
    fe.displayname,
    fe.rep_bucket,
    fe.reputation,
    fe.cohort_month,
    fe.questions_count,
    fe.avg_quality_score,
    fe.median_quality_score,
    fe.avg_hours_to_first_answer,
    fe.avg_hours_to_accept,
    fe.closed_questions,
    fe.total_upvotes_on_q,
    fe.total_downvotes_on_q,
    fe.total_favorites_on_q,
    fe.gold_badges,
    fe.silver_badges,
    fe.bronze_badges,
    fe.total_badges,
    fe.pos_comments,
    fe.nonpos_comments,
    fe.last_activity_at,
    c.users_in_cohort,
    c.avg_qs as cohort_avg_qs,
    c.avg_quality as cohort_avg_quality,
    c.avg_closed as cohort_avg_closed,
    c.p90_median_quality,
    ns.inactive_flag,
    case
        when fe.questions_count > greatest(1, c.avg_qs) * 5 then 'outlier-high-volume'
        when coalesce(fe.avg_quality_score,0) > coalesce(c.avg_quality,0) * 2 then 'outlier-high-quality'
        when fe.closed_questions > greatest(1, c.avg_closed) * 5 then 'outlier-high-closed'
        when ns.inactive_flag = 1 then 'inactive'
        else 'normal'
    end as cohort_outlier_class
from null_safety ns
join final_enriched fe on fe.user_id = ns.user_id
left join cohorts c
  on c.rep_bucket = fe.rep_bucket
 and c.cohort_month = fe.cohort_month
where (fe.last_activity_at >= (select max(p.creationdate) - interval '365 days' from posts p)
    or fe.questions_count > 0)
order by
    cohort_outlier_class,
    coalesce(fe.avg_quality_score, -1) desc,
    fe.questions_count desc,
    fe.reputation desc,
    fe.user_id
limit 500;