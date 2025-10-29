-- {"query": "67.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4245} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        u.lastaccessdate,
        coalesce(u.websiteurl, 'N/A') as websiteurl,
        date_trunc('month', u.lastaccessdate) as active_month,
        row_number() over (partition by u.id order by u.lastaccessdate desc) as rn_last_access
    from users u
    where u.lastaccessdate >= now() - interval '2 years'
),
user_badge_aggs as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= (select min(creationdate) from recent_active_users)
    group by b.userid
),
question_posts as (
    select p.*
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.*
    from posts p
    where p.posttypeid = 2
),
user_post_stats as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(case when p.posttypeid = 1 then coalesce(p.score,0) else 0 end) as q_score_sum,
        sum(case when p.posttypeid = 2 then coalesce(p.score,0) else 0 end) as a_score_sum,
        sum(coalesce(p.viewcount,0)) as total_views,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
post_link_dups as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        min(v.creationdate) as first_vote_date,
        max(v.creationdate) as last_vote_date
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
question_enriched as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.acceptedanswerid,
        q.creationdate as question_date,
        q.score as question_score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.closeddate,
        q.title,
        q.tags,
        pla.dup_links,
        pla.linked_links,
        va.upvotes as q_upvotes,
        va.downvotes as q_downvotes,
        va.bounty_started,
        va.bounty_awarded,
        ca.comment_count as q_comment_count,
        ca.comment_score_sum as q_comment_score_sum,
        coalesce(pla.last_link_date, q.lastactivitydate) as last_link_or_activity
    from question_posts q
    left join post_link_dups pla on pla.postid = q.id
    left join vote_agg va on va.postid = q.id
    left join comment_agg ca on ca.postid = q.id
),
answer_enriched as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score,
        va.upvotes as a_upvotes,
        va.downvotes as a_downvotes,
        ca.comment_count as a_comment_count,
        ca.comment_score_sum as a_comment_score_sum
    from answer_posts a
    left join vote_agg va on va.postid = a.id
    left join comment_agg ca on ca.postid = a.id
),
best_answer_per_question as (
    select
        ae.question_id,
        ae.answer_id,
        ae.answerer_id,
        ae.answer_score,
        ae.a_upvotes,
        ae.a_downvotes,
        ae.answer_date,
        row_number() over (
            partition by ae.question_id
            order by ae.answer_score desc nulls last, ae.a_upvotes desc nulls last, ae.answer_date asc
        ) as rn_best
    from answer_enriched ae
),
accepted_answer_flag as (
    select
        qe.question_id,
        case when qe.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        qe.acceptedanswerid
    from question_enriched qe
),
question_tag_expanded as (
    select
        qe.question_id,
        unnest(string_to_array(substring(qe.tags, 2, length(qe.tags)-2), '><')) as tag_name
    from question_enriched qe
    where qe.tags is not null and qe.tags like '<%>'
),
tag_rank as (
    select
        qte.tag_name,
        count(*) as tag_q_count,
        rank() over (order by count(*) desc) as popularity_rank
    from question_tag_expanded qte
    group by qte.tag_name
),
user_recent_activity as (
    select
        rau.user_id,
        rau.displayname,
        rau.reputation,
        rau.location,
        rau.creationdate,
        rau.lastaccessdate,
        rau.websiteurl,
        rau.active_month
    from recent_active_users rau
    where rau.rn_last_access = 1
),
question_closure_info as (
    select
        ph.postid as question_id,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
        max(case when ph.posthistorytypeid = 10 then ph.comment end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
close_reason_map as (
    select
        crt.id::varchar as close_reason_id,
        crt.name as close_reason_name
    from closereasontypes crt
),
user_quality_scores as (
    select
        urs.user_id,
        1.0 * coalesce(ups.q_score_sum,0) as q_score_sum,
        1.0 * coalesce(ups.a_score_sum,0) as a_score_sum,
        0.1 * coalesce(ups.total_views,0) as view_points,
        5.0 * coalesce(uba.gold_badges,0) + 2.0 * coalesce(uba.silver_badges,0) + 1.0 * coalesce(uba.bronze_badges,0) as badge_points,
        (case when coalesce(ups.a_count,0) > 0 then 2.0 * coalesce(ups.q_count,0) / greatest(coalesce(ups.a_count,0),1) else 0 end) as q_to_a_ratio_points
    from user_recent_activity urs
    left join user_post_stats ups on ups.user_id = urs.user_id
    left join user_badge_aggs uba on uba.userid = urs.user_id
),
user_quality_rank as (
    select
        uqs.user_id,
        (uqs.q_score_sum + uqs.a_score_sum + uqs.view_points + uqs.badge_points + uqs.q_to_a_ratio_points) as total_points,
        dense_rank() over (order by (uqs.q_score_sum + uqs.a_score_sum + uqs.view_points + uqs.badge_points + uqs.q_to_a_ratio_points) desc) as quality_rank
    from user_quality_scores uqs
),
question_answer_summary as (
    select
        qe.question_id,
        qe.asker_id,
        qe.question_date,
        qe.question_score,
        qe.viewcount,
        qe.answercount,
        qe.favoritecount,
        qe.title,
        qe.tags,
        coalesce(crm.close_reason_name, 'Open') as last_close_reason_name,
        case
            when qci.last_closed_date is not null and (qci.last_reopen_date is null or qci.last_closed_date > qci.last_reopen_date) then 1
            else 0
        end as is_currently_closed,
        coalesce(qci.last_closed_date, qe.closeddate) as last_closed_on,
        ba.answer_id as best_answer_id,
        ba.answerer_id as best_answerer_id,
        ba.answer_score as best_answer_score,
        aa.has_accepted,
        case when aa.has_accepted = 1 and aa.acceptedanswerid = ba.answer_id then 1 else 0 end as best_is_accepted
    from question_enriched qe
    left join accepted_answer_flag aa on aa.question_id = qe.question_id
    left join best_answer_per_question ba on ba.question_id = qe.question_id and ba.rn_best = 1
    left join question_closure_info qci on qci.question_id = qe.question_id
    left join close_reason_map crm on crm.close_reason_id = qci.last_close_reason_id
),
tagged_question_metrics as (
    select
        qas.question_id,
        qas.asker_id,
        qas.best_answerer_id,
        qas.question_score,
        qas.viewcount,
        qas.answercount,
        qas.best_is_accepted,
        qas.has_accepted,
        tr.tag_name,
        tr.popularity_rank
    from question_answer_summary qas
    left join question_tag_expanded qte on qte.question_id = qas.question_id
    left join tag_rank tr on tr.tag_name = qte.tag_name
),
user_pair_interactions as (
    select
        t.asker_id,
        t.best_answerer_id,
        count(*) as pair_count,
        sum(case when t.best_is_accepted = 1 then 1 else 0 end) as pair_accepted_count,
        avg(coalesce(t.question_score,0)) as avg_q_score,
        avg(coalesce(t.viewcount,0)) as avg_views
    from tagged_question_metrics t
    where t.best_answerer_id is not null and t.asker_id is not null
    group by t.asker_id, t.best_answerer_id
),
user_activity_window as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month_bucket,
        count(*) as posts_in_month,
        sum(coalesce(p.score,0)) as score_in_month,
        sum(coalesce(p.viewcount,0)) as views_in_month
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
user_activity_trend as (
    select
        uaw.user_id,
        uaw.month_bucket,
        uaw.posts_in_month,
        uaw.score_in_month,
        uaw.views_in_month,
        sum(uaw.posts_in_month) over (partition by uaw.user_id order by uaw.month_bucket rows between 3 preceding and current row) as posts_4mo_window,
        sum(uaw.score_in_month) over (partition by uaw.user_id order by uaw.month_bucket rows between 5 preceding and current row) as score_6mo_window,
        avg(nullif(uaw.views_in_month,0)) over (partition by uaw.user_id order by uaw.month_bucket rows between 11 preceding and current row) as avg_views_12mo
    from user_activity_window uaw
),
final_user_profile as (
    select
        ura.user_id,
        ura.displayname,
        ura.reputation,
        ura.location,
        ura.creationdate,
        ura.lastaccessdate,
        ura.websiteurl,
        coalesce(uba.total_badges,0) as total_badges,
        coalesce(uba.gold_badges,0) as gold_badges,
        coalesce(uba.silver_badges,0) as silver_badges,
        coalesce(uba.bronze_badges,0) as bronze_badges,
        coalesce(ups.q_count,0) as q_count,
        coalesce(ups.a_count,0) as a_count,
        coalesce(ups.q_score_sum,0) as q_score_sum,
        coalesce(ups.a_score_sum,0) as a_score_sum,
        coalesce(ups.total_views,0) as total_views,
        coalesce(ups.last_post_date, ura.creationdate) as last_post_date,
        coalesce(uqr.total_points,0) as total_points,
        uqr.quality_rank
    from user_recent_activity ura
    left join user_badge_aggs uba on uba.userid = ura.user_id
    left join user_post_stats ups on ups.user_id = ura.user_id
    left join user_quality_rank uqr on uqr.user_id = ura.user_id
),
-- introduce a correlated subquery with null-sensitive logic
user_null_sensitivity as (
    select
        fup.user_id,
        (
            select avg(coalesce(p2.score, 0))
            from posts p2
            where p2.owneruserid = fup.user_id
              and (p2.title is null or length(trim(coalesce(p2.title,''))) = 0 or p2.title ilike any (array['%how to%','%why%','%help%']))
        ) as avg_score_title_nullish_or_help,
        (
            select count(*)
            from comments c2
            where c2.userid = fup.user_id
              and c2.text is not null
              and length(c2.text) > 200
        ) as long_comments_count
    from final_user_profile fup
),
-- set operator to create a synthetic cohort for users with similar names or locations
name_location_cohort as (
    select u1.id as user_id, u2.id as cohort_user_id
    from users u1
    join users u2
      on u1.id <> u2.id
     and (
         lower(coalesce(u1.location,'')) = lower(coalesce(u2.location,'')) and u1.location is not null and u2.location is not null
         or similarity(lower(coalesce(u1.displayname,'')), lower(coalesce(u2.displayname,''))) > 0.6
     )
    union
    select u1.id as user_id, u1.id as cohort_user_id
    from users u1
),
cohort_scores as (
    select
        nlc.user_id,
        avg(fup.total_points) as cohort_avg_points,
        percentile_cont(0.5) within group (order by fup.total_points) as cohort_median_points,
        count(*) as cohort_size
    from name_location_cohort nlc
    join final_user_profile fup on fup.user_id = nlc.cohort_user_id
    group by nlc.user_id
),
-- compile per-question complexity metric
question_complexity as (
    select
        qe.question_id,
        1.0 * coalesce(qe.answercount,0)
        + 0.5 * coalesce(qe.q_comment_count,0)
        + 0.2 * coalesce(qe.linked_links,0)
        + 0.8 * coalesce(qe.dup_links,0)
        + case when qe.tags is null then 0 else least(5, array_length(string_to_array(substring(qe.tags, 2, length(qe.tags)-2), '><'),1)) end
        + case when qe.closeddate is not null then 2 else 0 end
        as complexity_score
    from question_enriched qe
),
-- bring it all together
final as (
    select
        fup.user_id,
        fup.displayname,
        fup.reputation,
        fup.location,
        fup.total_points,
        fup.quality_rank,
        uqs.q_score_sum + uqs.a_score_sum as qa_score_total,
        coalesce(uqs.view_points,0) as view_points,
        coalesce(uqs.badge_points,0) as badge_points,
        coalesce(uqs.q_to_a_ratio_points,0) as q_to_a_ratio_points,
        uns.avg_score_title_nullish_or_help,
        uns.long_comments_count,
        cs.cohort_avg_points,
        cs.cohort_median_points,
        cs.cohort_size,
        coalesce(ut.score_6mo_window, 0) as score_6mo_window,
        coalesce(ut.posts_4mo_window, 0) as posts_4mo_window,
        coalesce(ut.avg_views_12mo, 0) as avg_views_12mo
    from final_user_profile fup
    left join user_quality_scores uqs on uqs.user_id = fup.user_id
    left join user_null_sensitivity uns on uns.user_id = fup.user_id
    left join cohort_scores cs on cs.user_id = fup.user_id
    left join lateral (
        select *
        from user_activity_trend ut
        where ut.user_id = fup.user_id
        order by ut.month_bucket desc
        limit 1
    ) ut on true
)
select
    fin.*,
    -- sprinkle in some string and null logic for additional workload
    trim(both from coalesce(fin.displayname, 'Anonymous')) as displayname_trimmed,
    case
        when fin.reputation >= 100000 then 'Legend'
        when fin.reputation >= 20000 then 'Expert'
        when fin.reputation >= 5000 then 'Advanced'
        when fin.reputation >= 1000 then 'Intermediate'
        when fin.reputation is null then 'Unknown'
        else 'Beginner'
    end as reputation_tier,
    -- apply window functions over the final results
    ntile(10) over (order by fin.total_points desc nulls last) as decile_total_points,
    rank() over (order by fin.qa_score_total desc nulls last) as rank_qa_score,
    dense_rank() over (order by fin.cohort_avg_points desc nulls last) as rank_vs_cohort_avg,
    avg(fin.total_points) over () as global_avg_points,
    stddev_pop(fin.total_points) over () as global_stddev_points
from final fin
where
    (
        fin.total_points > coalesce(fin.cohort_avg_points, 0)
        or fin.qa_score_total > coalesce(fin.cohort_median_points, 0)
    )
    and coalesce(fin.long_comments_count, 0) >= 0
order by fin.total_points desc nulls last, fin.quality_rank asc
limit 500;