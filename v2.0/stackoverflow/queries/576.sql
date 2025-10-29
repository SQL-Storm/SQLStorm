-- {"query": "576.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3073}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by date_trunc('month', u.creationdate) order by u.reputation desc, u.id) as rn_in_cohort
    from users u
    where u.creationdate >= (select max(creationdate) - interval '2 years' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as q_count,
        count(case when p.posttypeid = 2 then 1 end) as a_count,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as views,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
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
vote_activity as (
    select
        v.userid as user_id,
        count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
        count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
        count(case when v.votetypeid = 5 then 1 end) as favorites_cast,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
badges_ranked as (
    select
        b.userid as user_id,
        b.name,
        b.class,
        b.date,
        row_number() over (partition by b.userid order by b.class asc, b.date desc, b.id desc) as rn_best,
        count(*) over (partition by b.userid) as total_badges
    from badges b
),
best_badge as (
    select user_id,
           name as best_badge_name,
           class as best_badge_class
    from badges_ranked
    where rn_best = 1
),
tags_from_questions as (
    select
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
      and p.owneruserid is not null
),
top_tags as (
    select
        user_id,
        tag,
        count(*) as tag_uses,
        row_number() over (partition by user_id order by count(*) desc, tag) as rn_tag
    from tags_from_questions
    group by user_id, tag
),
dup_closures as (
    select
        ph.postid,
        ph.creationdate as closed_at,
        ph.userid as closer_user_id,
        ph.comment as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
),
post_link_dupes as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.creationdate,
        pl.linktypeid
    from postlinks pl
    where pl.linktypeid = 3
),
question_stats as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.acceptedanswerid,
        case
            when q.tags is null then 0
            else cardinality(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><'))
        end as tag_count,
        exists (
            select 1 from post_link_dupes d where d.postid = q.id
        ) as has_duplicate_link,
        exists (
            select 1 from dup_closures dc where dc.postid = q.id and coalesce(dc.close_reason_id,'') in ('1','101')
        ) as closed_as_duplicate
    from posts q
    where q.posttypeid = 1
),
answer_lags as (
    select
        a.parentid as question_id,
        min(a.creationdate) - q.creationdate as first_answer_lag
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
    group by a.parentid, q.creationdate
),
accepted_answer_score as (
    select
        q.id as question_id,
        aa.score as accepted_score
    from posts q
    left join posts aa on aa.id = q.acceptedanswerid
    where q.posttypeid = 1
),
hot_questions as (
    select
        q.user_id,
        count(case when q.viewcount >= 10000 or q.score >= 10 then 1 end) as hot_q_count,
        avg(nullif(q.viewcount,0)) filter (where q.viewcount is not null) as avg_views_q,
        avg(cast(q.score as numeric)) as avg_q_score,
        sum(case when q.closed_as_duplicate then 1 else 0 end) as dup_closed_q,
        sum(case when q.has_duplicate_link then 1 else 0 end) as dup_linked_q
    from question_stats q
    group by q.user_id
),
post_edit_events as (
    select
        ph.postid,
        count(case when ph.posthistorytypeid in (4,5,6) then 1 end) as edits,
        max(case when ph.posthistorytypeid in (4,5,6) then ph.creationdate end) as last_edit_date
    from posthistory ph
    group by ph.postid
),
user_post_edit_agg as (
    select
        p.owneruserid as user_id,
        sum(coalesce(e.edits,0)) as total_edits_on_owned_posts,
        max(e.last_edit_date) as last_edit_on_owned_post
    from posts p
    left join post_edit_events e on e.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_union as (
    select ua.user_id,
           cast(ua.q_count as bigint) as metric_value,
           'Q_COUNT' as metric_name
    from user_activity ua
    union all
    select ua.user_id,
           cast(ua.a_count as bigint),
           'A_COUNT'
    from user_activity ua
    union all
    select ca.user_id,
           cast(ca.comment_count as bigint),
           'C_COUNT'
    from comment_activity ca
),
activity_rank as (
    select
        user_id,
        metric_name,
        metric_value,
        dense_rank() over (partition by metric_name order by metric_value desc nulls last, user_id) as rnk
    from activity_union
),
eligible_recent_users as (
    select ru.*
    from recent_users ru
    where ru.rn_in_cohort <= 200
),
final_agg as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ru.websiteurl_norm,
        coalesce(ua.q_count,0) as q_count,
        coalesce(ua.a_count,0) as a_count,
        coalesce(ua.post_score,0) as total_post_score,
        coalesce(ua.views,0) as total_views,
        ua.last_post_activity,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.comment_score,0) as comment_score,
        ca.last_comment_date,
        coalesce(va.upvotes_cast,0) as upvotes_cast,
        coalesce(va.downvotes_cast,0) as downvotes_cast,
        coalesce(va.favorites_cast,0) as favorites_cast,
        va.last_vote_date,
        coalesce(bb.best_badge_name, 'None') as best_badge_name,
        coalesce(bb.best_badge_class, 999) as best_badge_class,
        coalesce(br.total_badges,0) as total_badges,
        tt.tag as top_tag,
        coalesce(tt.tag_uses,0) as top_tag_uses,
        coalesce(hq.hot_q_count,0) as hot_q_count,
        coalesce(hq.avg_views_q,0) as avg_q_views,
        coalesce(hq.avg_q_score,0) as avg_q_score,
        coalesce(hq.dup_closed_q,0) as dup_closed_q,
        coalesce(hq.dup_linked_q,0) as dup_linked_q,
        coalesce(ue.total_edits_on_owned_posts,0) as total_edits_on_owned_posts,
        ue.last_edit_on_owned_post,
        max(qs.creationdate) over (partition by ru.user_id) as last_question_date,
        min(al.first_answer_lag) as fastest_answer_lag,
        sum(case when qs.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted,
        avg(cast(coalesce(aas.accepted_score,0) as numeric)) as avg_accepted_answer_score
    from eligible_recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join vote_activity va on va.user_id = ru.user_id
    left join best_badge bb on bb.user_id = ru.user_id
    left join (select user_id, max(total_badges) as total_badges from badges_ranked group by user_id) br on br.user_id = ru.user_id
    left join (
        select user_id, tag, tag_uses
        from top_tags
        where rn_tag = 1
    ) tt on tt.user_id = ru.user_id
    left join hot_questions hq on hq.user_id = ru.user_id
    left join user_post_edit_agg ue on ue.user_id = ru.user_id
    left join question_stats qs on qs.user_id = ru.user_id
    left join answer_lags al on al.question_id = qs.question_id
    left join accepted_answer_score aas on aas.question_id = qs.question_id
    group by
        ru.user_id, ru.displayname, ru.reputation, ru.cohort_month, ru.websiteurl_norm,
        ua.q_count, ua.a_count, ua.post_score, ua.views, ua.last_post_activity,
        ca.comment_count, ca.comment_score, ca.last_comment_date,
        va.upvotes_cast, va.downvotes_cast, va.favorites_cast, va.last_vote_date,
        bb.best_badge_name, bb.best_badge_class, br.total_badges,
        tt.tag, tt.tag_uses,
        hq.hot_q_count, hq.avg_views_q, hq.avg_q_score, hq.dup_closed_q, hq.dup_linked_q,
        ue.total_edits_on_owned_posts, ue.last_edit_on_owned_post,
        qs.user_id, qs.creationdate, qs.question_id, qs.score, qs.viewcount, qs.answercount, qs.acceptedanswerid, qs.tag_count, qs.has_duplicate_link, qs.closed_as_duplicate,
        al.first_answer_lag,
        aas.accepted_score
),
cohort_summary as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        avg(cast(reputation as numeric)) as avg_rep,
        percentile_cont(0.5) within group (order by reputation) as p50_rep,
        avg(cast(q_count as numeric)) as avg_q,
        avg(cast(a_count as numeric)) as avg_a,
        avg(cast(comment_count as numeric)) as avg_c,
        avg(coalesce(avg_q_views,0)) as avg_views_over_users
    from final_agg
    group by cohort_month
),
ranked_users as (
    select
        f.*,
        dense_rank() over (order by coalesce(f.total_post_score,0) + coalesce(f.comment_score,0) + coalesce(f.upvotes_cast,0) - coalesce(f.downvotes_cast,0) desc, f.reputation desc) as global_rnk,
        row_number() over (partition by f.cohort_month order by f.reputation desc, f.total_post_score desc) as cohort_rnk
    from final_agg f
)
select
    r.user_id,
    r.displayname,
    r.cohort_month,
    r.reputation,
    r.q_count,
    r.a_count,
    r.comment_count,
    r.total_post_score,
    r.total_views,
    r.hot_q_count,
    r.top_tag,
    r.top_tag_uses,
    r.best_badge_name,
    r.best_badge_class,
    r.total_badges,
    cast(r.avg_q_views as numeric(18,2)) as avg_q_views,
    cast(r.avg_q_score as numeric(18,2)) as avg_q_score,
    r.dup_closed_q,
    r.dup_linked_q,
    r.total_edits_on_owned_posts,
    r.fastest_answer_lag,
    r.questions_with_accepted,
    r.avg_accepted_answer_score,
    r.global_rnk,
    r.cohort_rnk,
    cs.users_in_cohort,
    cast(cs.avg_rep as numeric(18,2)) as cohort_avg_rep,
    cs.p50_rep as cohort_p50_rep,
    cast(cs.avg_q as numeric(18,2)) as cohort_avg_q,
    cast(cs.avg_a as numeric(18,2)) as cohort_avg_a,
    cast(cs.avg_c as numeric(18,2)) as cohort_avg_c,
    cast(cs.avg_views_over_users as numeric(18,2)) as cohort_avg_views_over_users
from ranked_users r
left join cohort_summary cs on cs.cohort_month = r.cohort_month
where
    (
        (r.q_count + r.a_count + r.comment_count) > 0
        and (coalesce(r.avg_q_views,0) > 500 or coalesce(r.hot_q_count,0) >= 1)
    )
    or (
        r.best_badge_class = 1
        and (r.top_tag is not null or r.total_edits_on_owned_posts > 5)
    )
    or (
        r.dup_closed_q > r.dup_linked_q
        and r.reputation between 100 and 100000
    )
order by
    r.global_rnk,
    r.cohort_rnk,
    r.user_id
limit 500;