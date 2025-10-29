-- {"query": "294.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3645}
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as website_norm,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '3 years'
),
posts_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        case when p.posttypeid = 1 then 1 else 0 end as is_question,
        case when p.posttypeid = 2 then 1 else 0 end as is_answer
    from posts p
    where p.creationdate >= (select min(creationdate) from recent_users)
),
user_post_activity as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.cohort_month,
        count(*) filter (where pe.is_question = 1) as questions,
        count(*) filter (where pe.is_answer = 1) as answers,
        sum(pe.score) as total_post_score,
        sum(pe.viewcount) as total_views,
        avg(nullif(pe.score, 0)) as avg_nonzero_score,
        max(pe.creationdate) as last_post_at
    from recent_users ru
    left join posts_enriched pe
        on pe.owneruserid = ru.id
    group by ru.id, ru.displayname, ru.cohort_month
),
comment_stats as (
    select
        ru.id as user_id,
        count(c.id) as comments_made,
        sum(c.score) as comment_score,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_at
    from recent_users ru
    left join comments c
        on c.userid = ru.id
       and c.creationdate >= ru.creationdate
    group by ru.id
),
vote_breakdown as (
    select
        ru.id as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from recent_users ru
    left join votes v
        on v.userid = ru.id
    group by ru.id
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = true) as tag_badges,
        max(b.date) as last_badge_at
    from badges b
    where b.date >= (select min(creationdate) from recent_users)
    group by b.userid
),
question_close_events as (
    select
        ph.postid as question_id,
        count(*) filter (where ph.posthistorytypeid = 10) as closes,
        count(*) filter (where ph.posthistorytypeid = 11) as reopens,
        max(ph.creationdate) as last_close_event_at,
        count(*) filter (
            where ph.posthistorytypeid = 10
              and (ph.comment ~ '^[0-9]+$')
              and cast(ph.comment as integer) in (101,102,103,104,105)
        ) as modern_close_reasons
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        count(*) as dup_links_count,
        min(pl.creationdate) as first_dup_link_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
question_tag_explode as (
    select
        p.id as post_id,
        lower(trim(t)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
            then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            else array[]::varchar[] -- placeholder kept for clarity; not used further
        end
    ) as t
    where p.posttypeid = 1
),
question_tag_explode_fixed as (
    select
        p.id as post_id,
        lower(trim(t)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
            then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            else cast(array[] as varchar[])
        end
    ) as t
    where p.posttypeid = 1
),
tag_selectivity as (
    select
        qte.tag,
        count(distinct qte.post_id) as questions_with_tag,
        avg(p.score) as avg_score_for_tag,
        percentile_cont(0.9) within group (order by p.viewcount) as p90_views_for_tag
    from question_tag_explode_fixed qte
    join posts p on p.id = qte.post_id
    group by qte.tag
    having count(distinct qte.post_id) >= 10
),
user_recent_quality as (
    select
        ru.id as user_id,
        avg(pe.score) filter (where pe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days') as avg_score_180d,
        avg(pe.viewcount) filter (where pe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days') as avg_views_180d,
        count(*) filter (where pe.posttypeid = 1 and pe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days') as q_180d,
        count(*) filter (where pe.posttypeid = 2 and pe.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '180 days') as a_180d
    from recent_users ru
    left join posts_enriched pe on pe.owneruserid = ru.id
    group by ru.id
),
answer_accept_rate as (
    select
        a.owneruserid as user_id,
        sum(case when q.acceptedanswerid = a.id then 1 else 0 end) as accepted_answers,
        count(*) as answers_posted,
        sum(case when q.acceptedanswerid = a.id then 1 else 0 end) * 1.0 / nullif(count(*),0) as accept_rate
    from posts a
    join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
    group by a.owneruserid
),
post_edit_counts as (
    select
        p.id as post_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edits,
        min(ph.creationdate) as first_edit_at,
        max(ph.creationdate) as last_edit_at
    from posts p
    left join posthistory ph on ph.postid = p.id
    group by p.id
),
user_post_edit_density as (
    select
        ru.id as user_id,
        avg(pec.edits) as avg_edits_per_post,
        max(pec.edits) as max_edits_on_any_post
    from recent_users ru
    left join posts_enriched pe on pe.owneruserid = ru.id
    left join post_edit_counts pec on pec.post_id = pe.id
    group by ru.id
),
user_activity_timeline as (
    select
        ru.id as user_id,
        generate_series(date_trunc('month', ru.creationdate), date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)), interval '1 month') as month_bucket
    from recent_users ru
),
user_monthly_posts as (
    select
        uat.user_id,
        uat.month_bucket,
        count(p.id) filter (where p.posttypeid = 1) as q_count,
        count(p.id) filter (where p.posttypeid = 2) as a_count,
        sum(p.score) as month_score
    from user_activity_timeline uat
    left join posts p
      on p.owneruserid = uat.user_id
     and date_trunc('month', p.creationdate) = uat.month_bucket
    group by uat.user_id, uat.month_bucket
),
user_growth as (
    select
        ump.user_id,
        percentile_cont(0.5) within group (order by coalesce(ump.month_score,0)) as p50_month_score,
        sum(ump.q_count + ump.a_count) as total_posts_timeline,
        stddev_pop(coalesce(ump.q_count + ump.a_count,0)) as post_count_volatility,
        max(case when ump.month_bucket >= date_trunc('month', cast('2024-10-01 12:34:56' as timestamp)) - interval '2 months' then coalesce(ump.q_count + ump.a_count,0) end) as recent_2mo_posts
    from user_monthly_posts ump
    group by ump.user_id
),
user_flagged_behavior as (
    select
        ru.id as user_id,
        count(*) filter (where v.votetypeid in (4,12,10)) as negative_moderation_events_on_posts,
        count(*) filter (where v.votetypeid = 10) as deletions_on_posts
    from recent_users ru
    left join votes v
      on v.postid in (select id from posts where owneruserid = ru.id)
    group by ru.id
),
question_quality as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        q.score,
        q.viewcount,
        q.title,
        qc.closes,
        qc.reopens,
        dl.dup_links_count,
        case
            when qc.closes > 0 then 'closed'
            when dl.dup_links_count > 0 then 'duplicate'
            else 'open'
        end as status_label
    from posts q
    left join question_close_events qc on qc.question_id = q.id
    left join (
        select dup_post_id, sum(dup_links_count) as dup_links_count
        from dup_links
        group by dup_post_id
    ) dl on dl.dup_post_id = q.id
    where q.posttypeid = 1
),
user_question_metrics as (
    select
        qq.user_id,
        count(*) as questions_total,
        avg(qq.score) as avg_q_score,
        avg(qq.viewcount) as avg_q_views,
        sum(case when qq.status_label = 'closed' then 1 else 0 end) as closed_q,
        sum(case when qq.status_label = 'duplicate' then 1 else 0 end) as dup_q
    from question_quality qq
    group by qq.user_id
),
top_tags_per_user as (
    select
        qte.tag,
        p.owneruserid as user_id,
        count(*) as tag_uses,
        row_number() over (partition by p.owneruserid order by count(*) desc, lower(qte.tag)) as rn
    from question_tag_explode_fixed qte
    join posts p on p.id = qte.post_id
    group by qte.tag, p.owneruserid
),
final as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.cohort_month,
        ru.reputation,
        coalesce(upa.questions,0) as questions,
        coalesce(upa.answers,0) as answers,
        coalesce(upa.total_post_score,0) as total_post_score,
        coalesce(upa.total_views,0) as total_views,
        upa.avg_nonzero_score,
        upa.last_post_at,
        cs.comments_made,
        cs.comment_score,
        cs.avg_comment_score,
        cs.last_comment_at,
        vb.upvotes_cast,
        vb.downvotes_cast,
        vb.bounties_started,
        vb.bounty_total,
        br.badges_total,
        br.gold_badges,
        br.silver_badges,
        br.bronze_badges,
        br.tag_badges,
        br.last_badge_at,
        urq.avg_score_180d,
        urq.avg_views_180d,
        urq.q_180d,
        urq.a_180d,
        aar.accept_rate,
        aar.accepted_answers,
        aar.answers_posted,
        uped.avg_edits_per_post,
        uped.max_edits_on_any_post,
        ug.p50_month_score,
        ug.total_posts_timeline,
        ug.post_count_volatility,
        ug.recent_2mo_posts,
        ufb.negative_moderation_events_on_posts,
        ufb.deletions_on_posts,
        uqm.questions_total,
        uqm.avg_q_score,
        uqm.avg_q_views,
        uqm.closed_q,
        uqm.dup_q,
        tt1.tag as top_tag_1,
        tt2.tag as top_tag_2,
        ts1.avg_score_for_tag as top_tag_1_avgscore,
        ts2.avg_score_for_tag as top_tag_2_avgscore,
        case
            when coalesce(upa.answers,0) + coalesce(upa.questions,0) = 0 then 'new'
            when coalesce(aar.accept_rate,0) >= 0.6 and coalesce(upa.answers,0) >= 10 then 'answerer'
            when coalesce(uqm.questions_total,0) >= 10 and coalesce(uqm.avg_q_score,0) >= 2 then 'questioner'
            when coalesce(br.gold_badges,0) >= 1 then 'expert'
            else 'regular'
        end as user_archetype
    from recent_users ru
    left join user_post_activity upa on upa.user_id = ru.id
    left join comment_stats cs on cs.user_id = ru.id
    left join vote_breakdown vb on vb.user_id = ru.id
    left join badge_rollup br on br.user_id = ru.id
    left join user_recent_quality urq on urq.user_id = ru.id
    left join answer_accept_rate aar on aar.user_id = ru.id
    left join user_post_edit_density uped on uped.user_id = ru.id
    left join user_growth ug on ug.user_id = ru.id
    left join user_flagged_behavior ufb on ufb.user_id = ru.id
    left join user_question_metrics uqm on uqm.user_id = ru.id
    left join top_tags_per_user tt1 on tt1.user_id = ru.id and tt1.rn = 1
    left join top_tags_per_user tt2 on tt2.user_id = ru.id and tt2.rn = 2
    left join tag_selectivity ts1 on ts1.tag = tt1.tag
    left join tag_selectivity ts2 on ts2.tag = tt2.tag
),
ranked as (
    select
        f.user_id,
        f.displayname,
        f.cohort_month,
        f.user_archetype,
        f.reputation,
        f.questions,
        f.answers,
        f.accept_rate,
        f.total_post_score,
        f.total_views,
        f.avg_nonzero_score,
        f.last_post_at,
        f.comments_made,
        f.comment_score,
        f.avg_comment_score,
        f.last_comment_at,
        f.upvotes_cast,
        f.downvotes_cast,
        f.bounties_started,
        f.bounty_total,
        f.badges_total,
        f.gold_badges,
        f.silver_badges,
        f.bronze_badges,
        f.tag_badges,
        f.last_badge_at,
        f.avg_score_180d,
        f.avg_views_180d,
        f.q_180d,
        f.a_180d,
        f.accepted_answers,
        f.answers_posted,
        f.avg_edits_per_post,
        f.max_edits_on_any_post,
        f.p50_month_score,
        f.total_posts_timeline,
        f.post_count_volatility,
        f.recent_2mo_posts,
        f.negative_moderation_events_on_posts,
        f.deletions_on_posts,
        f.questions_total,
        f.avg_q_score,
        f.avg_q_views,
        f.closed_q,
        f.dup_q,
        f.top_tag_1,
        f.top_tag_2,
        f.top_tag_1_avgscore,
        f.top_tag_2_avgscore,
        rank() over (order by coalesce(f.reputation,0) desc, coalesce(f.total_post_score,0) desc) as rep_rank,
        dense_rank() over (partition by f.cohort_month order by coalesce(f.total_post_score,0) desc) as cohort_performance_rank,
        ntile(20) over (order by coalesce(f.total_views,0) desc) as views_ventile,
        row_number() over (order by coalesce(f.accept_rate,0) desc nulls last) as accept_rate_rn
    from final f
)
select
    r.user_id,
    r.displayname,
    r.cohort_month,
    r.user_archetype,
    r.rep_rank,
    r.cohort_performance_rank,
    r.views_ventile,
    r.accept_rate_rn,
    r.reputation,
    r.questions,
    r.answers,
    r.accept_rate,
    r.total_post_score,
    r.total_views,
    r.avg_nonzero_score,
    r.comments_made,
    r.comment_score,
    r.badges_total,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.avg_edits_per_post,
    r.max_edits_on_any_post,
    r.p50_month_score,
    r.post_count_volatility,
    r.recent_2mo_posts,
    r.questions_total,
    r.avg_q_score,
    r.closed_q,
    r.dup_q,
    r.top_tag_1,
    r.top_tag_1_avgscore,
    r.top_tag_2,
    r.top_tag_2_avgscore
from ranked r
where
    (
        r.user_archetype = 'expert'
        or (r.accept_rate >= 0.5 and r.answers >= 5)
        or (r.questions_total >= 5 and r.avg_q_score >= 1)
    )
    and coalesce(r.negative_moderation_events_on_posts,0) < 10
    and (
        r.top_tag_1 is null
        or not (lower(r.top_tag_1) like '%regex%' or lower(r.top_tag_1) like '%homework%')
    )
order by r.rep_rank, r.cohort_performance_rank, r.user_id
limit 500;