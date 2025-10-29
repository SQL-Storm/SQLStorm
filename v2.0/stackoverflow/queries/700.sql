-- {"query": "700.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4011}
with
-- Active users with activity windows and ranking
active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.location,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        u.upvotes,
        u.downvotes,
        u.views,
        dense_rank() over (order by u.reputation desc) as rep_rank,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.reputation > 100
      and u.lastaccessdate >= u.creationdate
),
-- Questions with parsed tags and engagement metrics
questions as (
    select
        p.id as q_id,
        p.owneruserid,
        p.creationdate as q_created,
        p.title,
        p.tags,
        p.viewcount,
        p.score as q_score,
        p.answercount,
        p.favoritecount,
        p.closeddate,
        p.acceptedanswerid,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        string_to_array(substring(p.tags from 2 for greatest(length(p.tags)-2,0)), '><') as tag_arr
    from posts p
    where p.posttypeid = 1
),
-- Answers joined to questions; compute time-to-answer and engagement
answers as (
    select
        a.id as a_id,
        a.parentid as q_id,
        a.owneruserid as a_owner,
        a.creationdate as a_created,
        a.score as a_score,
        extract(epoch from (a.creationdate - q.q_created))/60.0 as minutes_to_answer,
        case when q.acceptedanswerid = a.id then 1 else 0 end as is_accepted
    from posts a
    join questions q on q.q_id = a.parentid
    where a.posttypeid = 2
),
-- First answer per question (for latency)
first_answer as (
    select distinct on (q_id)
        q_id,
        a_id,
        a_owner,
        a_created,
        minutes_to_answer
    from answers
    order by q_id, a_created asc, a_id
),
-- Votes summary by post and type
vote_summary as (
    select
        v.postid,
        v.votetypeid,
        count(*) as vote_count,
        sum(coalesce(v.bountyamount,0)) as total_bounty
    from votes v
    group by v.postid, v.votetypeid
),
-- Comments sentiment-ish proxy (length/score)
comment_metrics as (
    select
        c.postid,
        count(*) as comment_count,
        coalesce(sum(c.score),0) as comment_score_sum,
        avg(nullif(length(c.text),0)) as avg_comment_len
    from comments c
    group by c.postid
),
-- Post history close reasons per question
close_reasons as (
    select
        ph.postid as q_id,
        max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) end) as last_close_reason_id,
        sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_events
    from posthistory ph
    where ph.posthistorytypeid in (10,11,12,13,14,15)
    group by ph.postid
),
-- Duplicate links
dupe_links as (
    select
        pl.postid as q_id,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as duplicate_links,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as related_links
    from postlinks pl
    group by pl.postid
),
-- Tag popularity slice
tag_popularity as (
    select
        lower(t.tagname) as tagname,
        t.count as tag_count
    from tags t
),
-- Expand tags per question and annotate with popularity
question_tags as (
    select
        q.q_id,
        unnest(q.tag_arr) as tagname
    from questions q
),
question_tag_stats as (
    select
        qt.q_id,
        lower(qt.tagname) as tagname,
        coalesce(tp.tag_count, 0) as global_tag_count
    from question_tags qt
    left join tag_popularity tp on lower(qt.tagname) = tp.tagname
),
-- Aggregate per question across answers, votes, comments, and tags
question_agg as (
    select
        q.q_id,
        q.owneruserid as q_owner,
        q.q_created,
        q.viewcount,
        q.q_score,
        q.answercount,
        q.favoritecount,
        q.is_closed,
        fa.minutes_to_answer as minutes_to_first_answer,
        avg(a.minutes_to_answer) as avg_minutes_to_answer,
        sum(a.is_accepted) as accepted_answers,
        sum(a.a_score) as sum_answer_scores,
        max(a.a_score) as max_answer_score,
        coalesce(vu.vote_count, 0) as upvotes,
        coalesce(vd.vote_count, 0) as downvotes,
        coalesce(vf.vote_count, 0) as favorites_votes,
        coalesce(vb.total_bounty, 0) as bounties_total,
        coalesce(cm.comment_count,0) as comment_count,
        coalesce(cm.comment_score_sum,0) as comment_score_sum,
        coalesce(cm.avg_comment_len,0) as avg_comment_len,
        coalesce(cr.last_close_reason_id, null) as last_close_reason_id,
        coalesce(cr.close_events,0) as close_events,
        coalesce(dl.duplicate_links,0) as duplicate_links,
        coalesce(dl.related_links,0) as related_links,
        max(coalesce(qts.global_tag_count, 0)) as max_tag_popularity,
        avg(nullif(qts.global_tag_count,0)) as avg_nonzero_tag_popularity
    from questions q
    left join first_answer fa on fa.q_id = q.q_id
    left join answers a on a.q_id = q.q_id
    left join vote_summary vu on vu.postid = q.q_id and vu.votetypeid = 2
    left join vote_summary vd on vd.postid = q.q_id and vd.votetypeid = 3
    left join vote_summary vf on vf.postid = q.q_id and vf.votetypeid = 5
    left join vote_summary vb on vb.postid = q.q_id and vb.votetypeid in (8,9)
    left join comment_metrics cm on cm.postid = q.q_id
    left join close_reasons cr on cr.q_id = q.q_id
    left join dupe_links dl on dl.q_id = q.q_id
    left join question_tag_stats qts on qts.q_id = q.q_id
    group by
        q.q_id, q.owneruserid, q.q_created, q.viewcount, q.q_score, q.answercount, q.favoritecount,
        q.is_closed, fa.minutes_to_answer, vu.vote_count, vd.vote_count, vf.vote_count, vb.total_bounty,
        cm.comment_count, cm.comment_score_sum, cm.avg_comment_len, cr.last_close_reason_id, cr.close_events,
        dl.duplicate_links, dl.related_links
),
-- User level aggregates across their questions and answers
user_q_agg as (
    select
        au.user_id,
        count(*) as q_count,
        avg(qa.viewcount) as avg_q_views,
        avg(qa.q_score) as avg_q_score,
        avg(coalesce(qa.minutes_to_first_answer, 1440.0)) as avg_minutes_to_first_answer,
        sum(qa.bounties_total) as total_bounty_on_questions,
        sum(qa.upvotes - qa.downvotes) as net_votes_on_questions,
        sum(qa.favoritecount) as sum_favorites_on_questions,
        sum(case when qa.is_closed = 1 then 1 else 0 end) as closed_questions
    from active_users au
    left join question_agg qa on qa.q_owner = au.user_id
    group by au.user_id
),
user_a_agg as (
    select
        au.user_id,
        count(a.a_id) as a_count,
        avg(a.a_score) as avg_a_score,
        sum(a.is_accepted) as accepted_count,
        avg(a.minutes_to_answer) as avg_answer_latency_min
    from active_users au
    left join answers a on a.a_owner = au.user_id
    group by au.user_id
),
-- Compute monthly cohorts of questions for each user for window analysis
user_monthly as (
    select
        q.q_owner as user_id,
        date_trunc('month', q.q_created) as month_bucket,
        count(*) as q_in_month,
        sum(q.q_score) as q_score_in_month,
        sum(q.viewcount) as views_in_month
    from question_agg q
    group by q.q_owner, date_trunc('month', q.q_created)
),
-- Windows to compute rolling metrics
user_monthly_windows as (
    select
        um.user_id,
        um.month_bucket,
        q_in_month,
        q_score_in_month,
        views_in_month,
        sum(q_in_month) over (partition by um.user_id order by um.month_bucket rows between 2 preceding and current row) as rolling_3mo_q_count,
        avg(cast(q_score_in_month as numeric)) over (partition by um.user_id order by um.month_bucket rows between 2 preceding and current row) as rolling_3mo_avg_q_score
    from user_monthly um
),
-- Normalize display name and derive simple flags
user_flags as (
    select
        au.user_id,
        coalesce(nullif(trim(au.displayname), ''), '(anonymous)') as norm_displayname,
        case when au.websiteurl ilike '%github%' then 1 else 0 end as has_github,
        case when au.location ilike '%remote%' or au.location ilike '%world%' then 1 else 0 end as likely_remote,
        au.rep_rank,
        au.cohort_month
    from active_users au
),
-- Badge mix
badge_mix as (
    select
        b.userid as user_id,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = true then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
-- Outlier detection using z-scores for question scores and views
question_zscores as (
    select
        qa.q_id,
        qa.q_owner,
        qa.q_score,
        qa.viewcount,
        (qa.q_score - avg(qa.q_score) over ()) / nullif(stddev_pop(qa.q_score) over (),0) as z_q_score,
        (qa.viewcount - avg(qa.viewcount) over ()) / nullif(stddev_pop(qa.viewcount) over (),0) as z_views
    from question_agg qa
),
-- Combine everything at user level
user_final as (
    select
        uf.user_id,
        uf.norm_displayname,
        uf.rep_rank,
        uf.cohort_month,
        uf.has_github,
        uf.likely_remote,
        au.reputation,
        au.views as profile_views,
        au.upvotes - au.downvotes as net_votes,
        coalesce(bm.gold_badges,0) as gold_badges,
        coalesce(bm.silver_badges,0) as silver_badges,
        coalesce(bm.bronze_badges,0) as bronze_badges,
        coalesce(bm.tag_badges,0) as tag_badges,
        coalesce(qa.q_count,0) as q_count,
        coalesce(qa.avg_q_views,0) as avg_q_views,
        coalesce(qa.avg_q_score,0) as avg_q_score,
        coalesce(qa.avg_minutes_to_first_answer,0) as avg_minutes_to_first_answer,
        coalesce(qa.total_bounty_on_questions,0) as total_bounty_on_questions,
        coalesce(qa.net_votes_on_questions,0) as net_votes_on_questions,
        coalesce(qa.closed_questions,0) as closed_questions,
        coalesce(aa.a_count,0) as a_count,
        coalesce(aa.avg_a_score,0) as avg_a_score,
        coalesce(aa.accepted_count,0) as accepted_count,
        coalesce(aa.avg_answer_latency_min,0) as avg_answer_latency_min,
        percent_rank() over (order by coalesce(qa.avg_q_score,0)) as pr_avg_q_score,
        cume_dist() over (order by coalesce(aa.accepted_count,0) desc) as cd_accepted_answers_desc
    from user_flags uf
    join active_users au on au.user_id = uf.user_id
    left join badge_mix bm on bm.user_id = uf.user_id
    left join user_q_agg qa on qa.user_id = uf.user_id
    left join user_a_agg aa on aa.user_id = uf.user_id
),
-- Correlated subquery example: last 5 questions per user with high engagement
recent_hot_questions as (
    select
        qa.q_id,
        qa.q_owner,
        qa.q_score,
        qa.viewcount,
        qa.minutes_to_first_answer,
        qa.avg_minutes_to_answer,
        qa.max_answer_score,
        qa.duplicate_links,
        qa.related_links,
        qa.comment_count,
        qa.comment_score_sum,
        row_number() over (partition by qa.q_owner order by (qa.q_score*2 + coalesce(qa.viewcount,0)/100.0 + coalesce(qa.favoritecount,0)) desc, qa.q_id desc) as rn
    from question_agg qa
    where qa.q_score is not null
),
-- Choose top N recent hot Q per user
top5_hot_q as (
    select * from recent_hot_questions where rn <= 5
),
-- Summarize z-score outliers per user
user_outliers as (
    select
        qz.q_owner as user_id,
        sum(case when qz.z_q_score >= 2 then 1 else 0 end) as hi_score_outliers,
        sum(case when qz.z_views >= 2 then 1 else 0 end) as hi_view_outliers
    from question_zscores qz
    group by qz.q_owner
)
select
    uf.user_id,
    uf.norm_displayname as display_name,
    uf.reputation,
    uf.rep_rank,
    uf.cohort_month,
    uf.has_github,
    uf.likely_remote,
    uf.profile_views,
    uf.net_votes,
    uf.gold_badges,
    uf.silver_badges,
    uf.bronze_badges,
    uf.tag_badges,
    uf.q_count,
    uf.a_count,
    uf.avg_q_views,
    uf.avg_q_score,
    uf.avg_minutes_to_first_answer,
    uf.total_bounty_on_questions,
    uf.net_votes_on_questions,
    uf.closed_questions,
    uf.avg_a_score,
    uf.accepted_count,
    uf.avg_answer_latency_min,
    uf.pr_avg_q_score,
    uf.cd_accepted_answers_desc,
    coalesce(uo.hi_score_outliers,0) as hi_score_outliers,
    coalesce(uo.hi_view_outliers,0) as hi_view_outliers,
    round(
        0.30 * coalesce(uf.avg_q_score,0) +
        0.20 * coalesce(uf.avg_a_score,0) +
        0.15 * coalesce(uf.accepted_count,0) +
        0.10 * least(coalesce(uf.avg_minutes_to_first_answer,1440.0), 1440.0) * -0.001 +
        0.10 * coalesce(uf.total_bounty_on_questions,0) * 0.01 +
        0.05 * coalesce(uf.net_votes_on_questions,0) * 0.02 +
        0.10 * (case when uf.has_github = 1 then 1 else 0 end),
        4
    ) as performance_index,
    concat_ws(
        ' | ',
        concat('Badges G/S/B: ', coalesce(uf.gold_badges,0), '/', coalesce(uf.silver_badges,0), '/', coalesce(uf.bronze_badges,0)),
        concat('Q/A: ', coalesce(uf.q_count,0), '/', coalesce(uf.a_count,0))
    ) as summary,
    (
        select p.title
        from top5_hot_q t5
        join posts p on p.id = t5.q_id
        where t5.q_owner = uf.user_id
        order by t5.rn, p.id
        limit 1
    ) as top_question_title,
    (
        select count(distinct qts.tagname)
        from question_tag_stats qts
        join questions q on q.q_id = qts.q_id
        where q.owneruserid = uf.user_id
          and qts.tagname in (
              select tagname
              from (
                  select tagname,
                         ntile(10) over (order by tag_count desc) as decile
                  from tag_popularity
              ) tpd
              where decile = 1
          )
    ) as top_decile_tags_used
from user_final uf
left join user_outliers uo on uo.user_id = uf.user_id
where
    (
        coalesce(uf.q_count,0) + coalesce(uf.a_count,0) >= 5
        or (uf.gold_badges >= 1 and uf.rep_rank <= 1000)
    )
    and not (uf.closed_questions is null and uf.q_count is null)
    and (uf.norm_displayname is not null and length(uf.norm_displayname) between 3 and 40)
    and (uf.avg_q_score is null or uf.avg_q_score >= -5)
order by performance_index desc, uf.rep_rank asc, uf.user_id
limit 200;