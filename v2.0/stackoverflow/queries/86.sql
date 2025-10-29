-- {"query": "86.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3481}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (
        select date_trunc('month', max(creationdate)) - interval '24 months' from users
    )
),
post_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as total_post_score,
        sum(coalesce(p.viewcount,0)) as total_views,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
post_activity_agg as (
    select
        user_id,
        sum(q_count) as questions,
        sum(a_count) as answers,
        sum(total_post_score) as post_score,
        sum(total_views) as views,
        max(last_post_activity) as last_post_activity
    from post_activity
    group by user_id
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_summaries as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_details as (
    select
        p.owneruserid as user_id,
        count(*) as closed_qs,
        count(*) filter (where p.acceptedanswerid is not null) as accepted_qs,
        avg(nullif(p.answercount,0)) as avg_answers_per_q,
        percentile_disc(0.5) within group (order by coalesce(p.viewcount,0)) as median_views_q,
        min(p.creationdate) as first_q_date,
        max(p.creationdate) as last_q_date
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid
),
answer_details as (
    select
        p.owneruserid as user_id,
        count(*) as answers_total,
        count(*) filter (where p.score > 0) as pos_answers,
        count(*) filter (where p.score < 0) as neg_answers,
        count(*) filter (where p.parentid in (
            select id from posts where posttypeid = 1 and coalesce(viewcount,0) > 1000
        )) as answers_on_popular_qs,
        avg(coalesce(p.score,0)) as avg_answer_score,
        max(p.creationdate) as last_answer_date
    from posts p
    where p.posttypeid = 2
      and p.owneruserid is not null
    group by p.owneruserid
),
linkage as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        pl.creationdate,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
duplicate_graph as (
    select
        p.owneruserid as user_id,
        count(*) filter (where l.is_duplicate = 1) as dup_links_out,
        count(*) filter (where l.is_duplicate = 1 and p.posttypeid = 1) as dup_q_links_out,
        count(*) filter (where l.linktypeid = 1) as links_out
    from posts p
    left join linkage l on l.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
history_flags as (
    select
        ph.postid,
        ph.userid,
        max(ph.creationdate) as last_hist_date,
        max(ph.posthistorytypeid) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as last_moderation_type,
        count(*) filter (where ph.posthistorytypeid = 10) as closes,
        count(*) filter (where ph.posthistorytypeid = 11) as reopens,
        count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_cycle
    from posthistory ph
    where ph.userid is not null
    group by ph.postid, ph.userid
),
user_moderation as (
    select
        h.userid as user_id,
        sum(h.closes) as closes_made,
        sum(h.reopens) as reopens_made,
        sum(h.delete_cycle) as delete_undelete_actions,
        max(h.last_hist_date) as last_moderation_action
    from history_flags h
    group by h.userid
),
tag_exposure as (
    select
        p.owneruserid as user_id,
        count(distinct lower(trim(both '<>' from t))) as distinct_tags_used
    from (
        select
            owneruserid,
            unnest(string_to_array(substring(tags, 2, length(tags)-2), '><')) as t
        from posts
        where posttypeid = 1 and tags is not null and owneruserid is not null
    ) p
    group by p.owneruserid
),
monthly_activity as (
    select
        u.id as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) filter (where p.posttypeid = 1) as q_m,
        count(*) filter (where p.posttypeid = 2) as a_m,
        sum(coalesce(p.score,0)) as score_m
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, date_trunc('month', p.creationdate)
),
-- Replace nested window-in-window with a two-step grouping approach:
activity_streaks_prep as (
    select
        user_id,
        month,
        case when coalesce(q_m,0) + coalesce(a_m,0) > 0 then 0 else 1 end as is_gap
    from monthly_activity
),
activity_streaks_groups as (
    select
        user_id,
        month,
        is_gap,
        sum(is_gap) over (partition by user_id order by month rows unbounded preceding) as grp
    from activity_streaks_prep
),
activity_streaks as (
    select
        user_id,
        max(streak_len) as max_active_month_streak
    from (
        select
            user_id,
            grp,
            count(*) filter (where is_gap = 0) as streak_len
        from activity_streaks_groups
        group by user_id, grp
    ) t
    group by user_id
),
cohort_retention as (
    select
        ru.user_id,
        count(distinct date_trunc('month', p.creationdate)) as active_months,
        min(date_trunc('month', p.creationdate)) as first_active_month,
        max(date_trunc('month', p.creationdate)) as last_active_month
    from recent_users ru
    left join posts p on p.owneruserid = ru.user_id
    group by ru.user_id
),
user_scores as (
    select
        u.id as user_id,
        u.reputation,
        coalesce(pa.questions, 0) as questions,
        coalesce(pa.answers, 0) as answers,
        coalesce(pa.post_score, 0) as post_score,
        coalesce(pa.views, 0) as views,
        coalesce(ca.comment_count, 0) as comments,
        coalesce(ca.comment_score, 0) as comment_score,
        coalesce(vs.upvotes_cast, 0) as upvotes_cast,
        coalesce(vs.downvotes_cast, 0) as downvotes_cast,
        coalesce(vs.bounties_interactions, 0) as bounties_interactions,
        coalesce(vs.bounty_amount_total, 0) as bounty_amount_total,
        coalesce(br.badges_total, 0) as badges_total,
        coalesce(br.gold_badges, 0) as gold_badges,
        coalesce(br.silver_badges, 0) as silver_badges,
        coalesce(br.bronze_badges, 0) as bronze_badges,
        coalesce(br.tag_badges, 0) as tag_badges,
        coalesce(qd.closed_qs, 0) as closed_qs,
        coalesce(qd.accepted_qs, 0) as accepted_qs,
        coalesce(qd.avg_answers_per_q, 0) as avg_answers_per_q,
        coalesce(qd.median_views_q, 0) as median_views_q,
        coalesce(ad.answers_total, 0) as answers_total,
        coalesce(ad.pos_answers, 0) as pos_answers,
        coalesce(ad.neg_answers, 0) as neg_answers,
        coalesce(ad.answers_on_popular_qs, 0) as answers_on_popular_qs,
        coalesce(ad.avg_answer_score, 0) as avg_answer_score,
        coalesce(dg.dup_links_out, 0) as dup_links_out,
        coalesce(dg.dup_q_links_out, 0) as dup_q_links_out,
        coalesce(dg.links_out, 0) as links_out,
        coalesce(um.closes_made, 0) as closes_made,
        coalesce(um.reopens_made, 0) as reopens_made,
        coalesce(um.delete_undelete_actions, 0) as delete_undelete_actions,
        coalesce(te.distinct_tags_used, 0) as distinct_tags_used,
        coalesce(asr.max_active_month_streak, 0) as max_active_month_streak,
        coalesce(cr.active_months, 0) as active_months
    from users u
    left join post_activity_agg pa on pa.user_id = u.id
    left join comment_activity ca on ca.user_id = u.id
    left join vote_summaries vs on vs.user_id = u.id
    left join badge_rollup br on br.user_id = u.id
    left join question_details qd on qd.user_id = u.id
    left join answer_details ad on ad.user_id = u.id
    left join duplicate_graph dg on dg.user_id = u.id
    left join user_moderation um on um.user_id = u.id
    left join tag_exposure te on te.user_id = u.id
    left join activity_streaks asr on asr.user_id = u.id
    left join cohort_retention cr on cr.user_id = u.id
),
ranked as (
    select
        us.*,
        row_number() over (order by reputation desc, post_score desc, answers desc) as rn,
        rank() over (order by (post_score + comment_score + upvotes_cast - downvotes_cast) desc) as engagement_rank,
        dense_rank() over (order by badges_total desc) as badge_rank,
        ntile(20) over (order by coalesce(answers_total,0) desc) as answers_ventile,
        percent_rank() over (order by coalesce(distinct_tags_used,0)) as tag_diversity_pr
    from user_scores us
),
anomalies as (
    select
        r.user_id,
        case
            when r.reputation < 100 and r.post_score > 1000 then 'LOW_REP_HIGH_SCORE'
            when r.answers_total = 0 and r.questions > 50 then 'QUESTION_ONLY'
            when r.upvotes_cast = 0 and r.downvotes_cast > 100 then 'DOWNVOTE_HEAVY'
            when r.badges_total = 0 and (r.questions + r.answers_total) > 100 then 'ACTIVE_NO_BADGES'
            else null
        end as anomaly_type
    from ranked r
),
user_tags as (
    select
        p.owneruserid as user_id,
        lower(trim(both '<>' from t)) as tag
    from (
        select owneruserid, unnest(string_to_array(substring(tags, 2, length(tags)-2), '><')) as t
        from posts
        where posttypeid = 1 and tags is not null and owneruserid is not null
    ) p
),
top_tags as (
    select
        tt.user_id,
        string_agg(tt.tag, ', ' order by tt.cnt desc nulls last) as top_5_tags
    from (
        select user_id, tag, count(*) as cnt,
               row_number() over (partition by user_id order by count(*) desc, tag) as rn
        from user_tags
        group by user_id, tag
    ) tt
    where tt.rn <= 5
    group by tt.user_id
),
final as (
    select
        r.user_id,
        ru.displayname,
        ru.location,
        ru.websiteurl_norm,
        ru.cohort_month,
        r.reputation,
        r.questions,
        r.answers_total as answers,
        r.post_score,
        r.views,
        r.comments,
        r.comment_score,
        r.upvotes_cast,
        r.downvotes_cast,
        r.bounties_interactions,
        r.bounty_amount_total,
        r.badges_total,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.accepted_qs,
        r.avg_answers_per_q,
        r.median_views_q,
        r.pos_answers,
        r.neg_answers,
        r.answers_on_popular_qs,
        r.avg_answer_score,
        r.dup_links_out,
        r.links_out,
        r.closes_made,
        r.reopens_made,
        r.delete_undelete_actions,
        r.distinct_tags_used,
        r.max_active_month_streak,
        r.active_months,
        coalesce(tt.top_5_tags, '(none)') as top_5_tags,
        r.engagement_rank,
        r.badge_rank,
        r.answers_ventile,
        r.tag_diversity_pr,
        count(a.anomaly_type) filter (where a.anomaly_type is not null) as anomaly_flags
    from ranked r
    join recent_users ru on ru.user_id = r.user_id
    left join anomalies a on a.user_id = r.user_id
    left join top_tags tt on tt.user_id = r.user_id
    where (r.questions + r.answers_total + r.comments) > 0
    group by
        r.user_id,
        ru.displayname,
        ru.location,
        ru.websiteurl_norm,
        ru.cohort_month,
        r.reputation,
        r.questions,
        r.answers_total,
        r.post_score,
        r.views,
        r.comments,
        r.comment_score,
        r.upvotes_cast,
        r.downvotes_cast,
        r.bounties_interactions,
        r.bounty_amount_total,
        r.badges_total,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.accepted_qs,
        r.avg_answers_per_q,
        r.median_views_q,
        r.pos_answers,
        r.neg_answers,
        r.answers_on_popular_qs,
        r.avg_answer_score,
        r.dup_links_out,
        r.links_out,
        r.closes_made,
        r.reopens_made,
        r.delete_undelete_actions,
        r.distinct_tags_used,
        r.max_active_month_streak,
        r.active_months,
        tt.top_5_tags,
        r.engagement_rank,
        r.badge_rank,
        r.answers_ventile,
        r.tag_diversity_pr
)
select *
from final
where (
        (reputation > 1000 and answers >= 10)
     or (badges_total >= 10 and engagement_rank <= 1000)
     or (avg_answer_score > 2 and distinct_tags_used >= 5)
     or (anomaly_flags > 0)
     or (tag_diversity_pr between 0.45 and 0.55)
     )
order by engagement_rank, badge_rank, answers desc, post_score desc
limit 500;