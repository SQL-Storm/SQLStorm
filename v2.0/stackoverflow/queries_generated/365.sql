-- {"query": "365.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3177} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as website_host,
        date_trunc('month', u.creationdate) as signup_month,
        count(*) over (partition by date_trunc('month', u.creationdate)) as cohort_size,
        row_number() over (partition by u.location order by u.reputation desc, u.id) as loc_rep_rank
    from users u
    where u.lastaccessdate >= now() - interval '365 days'
),
user_badge_summary as (
    select
        b.userid,
        count(*) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
questions as (
    select
        p.id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.favoritecount
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        p.id,
        p.parentid as question_id,
        p.owneruserid,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
dup_links as (
    select pl.postid as question_id, pl.relatedpostid as canonical_id
    from postlinks pl
    where pl.linktypeid = 3
),
tag_counts as (
    select
        q.id as question_id,
        unnest(string_to_array(substring(coalesce(q.tags,''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tag
    from questions q
),
top_tags as (
    select tag, count(*) as tag_q_count,
           row_number() over (order by count(*) desc, tag) as tag_rank
    from tag_counts
    group by tag
    having count(*) > 10
),
q_activity as (
    select
        q.id as question_id,
        q.owneruserid,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.favoritecount,
        q.acceptedanswerid,
        q.closeddate,
        avg(a.score) filter (where a.id is not null) as avg_answer_score,
        count(a.id) as total_answers,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted_answer,
        max(a.creationdate) as last_answer_date
    from questions q
    left join answers a on a.question_id = q.id
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.favoritecount, q.acceptedanswerid, q.closeddate
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        sum(c.score) as comment_score_sum,
        max(c.creationdate) as last_comment_date,
        avg(length(c.text)) as avg_comment_len
    from comments c
    group by c.postid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_legacy,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from votes v
    group by v.postid
),
close_events as (
    select
        ph.postid as question_id,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_count,
        array_agg(distinct ph.comment) filter (where ph.posthistorytypeid = 10 and ph.comment ~ '^[0-9]+$') as close_reason_ids
    from posthistory ph
    where ph.posthistorytypeid in (10,11,35)
    group by ph.postid
),
close_reason_map as (
    select
        crt.id::text as reason_id_text,
        crt.name as reason_name
    from closereasontypes crt
),
q_tag_enriched as (
    select
        qc.question_id,
        qc.tag,
        tt.tag_rank
    from tag_counts qc
    left join top_tags tt on tt.tag = qc.tag
),
user_posting_pace as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        min(p.creationdate) as first_post_date,
        max(p.creationdate) as last_post_date,
        extract(epoch from (max(p.creationdate) - min(p.creationdate))) / nullif(greatest(count(*),1),0) as avg_seconds_between_posts
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
accepted_answer_latency as (
    select
        q.id as question_id,
        q.creationdate as q_created,
        a.creationdate as accepted_created,
        extract(epoch from (a.creationdate - q.creationdate)) as seconds_to_accept
    from questions q
    join posts a on a.id = q.acceptedanswerid
),
ranked_questions as (
    select
        qa.question_id,
        qa.owneruserid,
        qa.creationdate,
        qa.score,
        qa.viewcount,
        qa.answercount,
        qa.favoritecount,
        qa.has_accepted_answer,
        qa.last_answer_date,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes,
        coalesce(va.bounty_total,0) as bounty_total,
        coalesce(cs.comment_count,0) as comment_count,
        coalesce(cs.comment_score_sum,0) as comment_score_sum,
        coalesce(aa.seconds_to_accept, null) as seconds_to_accept,
        case
            when qa.closeddate is not null then 'Closed'
            when qa.has_accepted_answer > 0 then 'Answered'
            when qa.answercount > 0 then 'Has Answers'
            else 'Open'
        end as q_status,
        row_number() over (
            partition by date_trunc('month', qa.creationdate)
            order by (coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) desc, qa.viewcount desc, qa.score desc, qa.id
        ) as monthly_rank
    from q_activity qa
    left join vote_agg va on va.postid = qa.question_id
    left join comment_stats cs on cs.postid = qa.question_id
    left join accepted_answer_latency aa on aa.question_id = qa.question_id
),
canonical_map as (
    select
        q.id as question_id,
        coalesce(d.canonical_id, q.id) as canonical_id
    from questions q
    left join dup_links d on d.question_id = q.id
),
canonical_rollup as (
    select
        cm.canonical_id,
        count(*) as dup_group_size,
        sum(rq.net_votes) as group_net_votes,
        sum(rq.viewcount) as group_views,
        max(rq.creationdate) as latest_question_date
    from canonical_map cm
    join ranked_questions rq on rq.question_id = cm.question_id
    group by cm.canonical_id
),
user_quality as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.website_host,
        u.signup_month,
        u.cohort_size,
        u.loc_rep_rank,
        up.q_count,
        up.a_count,
        up.avg_seconds_between_posts,
        coalesce(ubs.badge_count,0) as badge_count,
        coalesce(ubs.gold_count,0) as gold_count,
        coalesce(ubs.silver_count,0) as silver_count,
        coalesce(ubs.bronze_count,0) as bronze_count,
        ubs.first_badge_date,
        ubs.last_badge_date
    from recent_active_users u
    left join user_badge_summary ubs on ubs.userid = u.user_id
    left join user_posting_pace up on up.user_id = u.user_id
),
q_final as (
    select
        rq.question_id,
        rq.owneruserid as user_id,
        rq.creationdate,
        rq.score,
        rq.viewcount,
        rq.answercount,
        rq.favoritecount,
        rq.net_votes,
        rq.bounty_total,
        rq.comment_count,
        rq.comment_score_sum,
        rq.seconds_to_accept,
        rq.q_status,
        rq.monthly_rank,
        coalesce(cr.first_close_date, null) as first_close_date,
        coalesce(cr.last_close_date, null) as last_close_date,
        coalesce(cr.close_count, 0) as close_count,
        array_remove(array_agg(distinct crm.reason_name) filter (
            where cr.close_reason_ids is not null and crm.reason_id_text = any(cr.close_reason_ids)
        ), null) as close_reasons,
        cm.canonical_id,
        coalesce(cru.dup_group_size,1) as dup_group_size,
        coalesce(cru.group_net_votes, rq.net_votes) as group_net_votes,
        coalesce(cru.group_views, rq.viewcount) as group_views
    from ranked_questions rq
    left join close_events cr on cr.question_id = rq.question_id
    left join lateral (
        select crm.*
        from close_reason_map crm
    ) crm on true
    left join canonical_map cm on cm.question_id = rq.question_id
    left join canonical_rollup cru on cru.canonical_id = cm.canonical_id
    group by
        rq.question_id, rq.owneruserid, rq.creationdate, rq.score, rq.viewcount, rq.answercount,
        rq.favoritecount, rq.net_votes, rq.bounty_total, rq.comment_count, rq.comment_score_sum,
        rq.seconds_to_accept, rq.q_status, rq.monthly_rank, cr.first_close_date, cr.last_close_date,
        cr.close_count, cm.canonical_id, cru.dup_group_size, cru.group_net_votes, cru.group_views
),
user_rollup as (
    select
        qf.user_id,
        count(*) as total_questions,
        count(*) filter (where qf.q_status = 'Closed') as closed_questions,
        count(*) filter (where qf.q_status = 'Answered') as answered_questions,
        avg(qf.net_votes) as avg_q_net_votes,
        percentile_cont(0.5) within group (order by qf.viewcount) as median_q_views,
        sum(case when qf.seconds_to_accept is not null then 1 else 0 end) as accepted_count,
        avg(qf.seconds_to_accept) filter (where qf.seconds_to_accept is not null) as avg_seconds_to_accept
    from q_final qf
    group by qf.user_id
),
tag_influence as (
    select
        qf.question_id,
        string_agg(qte.tag, ',' order by qte.tag) as tags_csv,
        min(qte.tag_rank) filter (where qte.tag_rank is not null) as best_tag_rank,
        count(*) filter (where qte.tag_rank is not null) as top_tag_hits
    from q_final qf
    left join q_tag_enriched qte on qte.question_id = qf.question_id
    group by qf.question_id
)
select
    uq.user_id,
    uq.displayname,
    uq.reputation,
    uq.location,
    uq.website_host,
    uq.signup_month,
    uq.cohort_size,
    uq.loc_rep_rank,
    uq.q_count,
    uq.a_count,
    uq.avg_seconds_between_posts,
    uq.badge_count,
    uq.gold_count,
    uq.silver_count,
    uq.bronze_count,
    uq.first_badge_date,
    uq.last_badge_date,
    ur.total_questions,
    ur.closed_questions,
    ur.answered_questions,
    ur.avg_q_net_votes,
    ur.median_q_views,
    ur.accepted_count,
    ur.avg_seconds_to_accept,
    qf.question_id,
    qf.creationdate as question_created,
    qf.score as question_score,
    qf.viewcount as question_views,
    qf.answercount as question_answers,
    qf.favoritecount as question_favs,
    qf.net_votes as question_net_votes,
    qf.bounty_total,
    qf.comment_count,
    qf.comment_score_sum,
    qf.seconds_to_accept,
    qf.q_status,
    qf.monthly_rank,
    qf.first_close_date,
    qf.last_close_date,
    qf.close_count,
    coalesce(array_to_string(qf.close_reasons, ', '), 'n/a') as close_reasons,
    ti.tags_csv,
    ti.best_tag_rank,
    ti.top_tag_hits,
    qf.canonical_id,
    qf.dup_group_size,
    qf.group_net_votes,
    qf.group_views
from q_final qf
join user_quality uq on uq.user_id = qf.user_id
left join user_rollup ur on ur.user_id = uq.user_id
left join tag_influence ti on ti.question_id = qf.question_id
where
    coalesce(uq.location, '') not ilike '%test%'
    and (
        qf.net_votes > 0
        or (qf.viewcount > 1000 and coalesce(qf.seconds_to_accept, 1e18) < 86400)
        or (qf.close_count > 0 and qf.group_views > 10000)
    )
    and coalesce(ti.top_tag_hits, 0) >= 0
    and (
        uq.reputation >= 1000
        or uq.gold_count > 0
        or (uq.q_count + uq.a_count) >= 10
    )
order by
    uq.reputation desc nulls last,
    qf.monthly_rank asc nulls last,
    qf.net_votes desc,
    qf.viewcount desc
limit 500;