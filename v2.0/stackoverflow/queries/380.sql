-- {"query": "380.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2911}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
        case when u.location is null or trim(u.location) = '' then 1 else 0 end as is_loc_null
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.posttypeid
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select
        p.id as post_id,
        p.parentid as question_id,
        p.owneruserid as user_id,
        p.creationdate,
        p.score
    from posts p
    where p.posttypeid = 2
),
tag_explode as (
    select
        qp.post_id,
        unnest(string_to_array(substring(qp.tags, 2, length(qp.tags) - 2), '><')) as tagname
    from question_posts qp
    where qp.tags is not null and length(qp.tags) > 2
),
tag_stats as (
    select
        te.tagname,
        count(*) as q_count,
        count(*) filter (where qp.closeddate is not null) as closed_q_count,
        avg(qp.score) as avg_q_score
    from tag_explode te
    join question_posts qp on qp.post_id = te.post_id
    group by te.tagname
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
post_vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (10,12)) as delete_or_spam_votes
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_date,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments
    from comments c
    group by c.postid
),
question_metrics as (
    select
        qp.post_id,
        qp.user_id,
        qp.creationdate,
        qp.score,
        qp.viewcount,
        qp.answercount,
        qp.title,
        qp.tags,
        qp.acceptedanswerid,
        qp.closeddate,
        coalesce(pva.upvotes,0) as upvotes,
        coalesce(pva.downvotes,0) as downvotes,
        coalesce(pva.bounty_started,0) as bounty_started,
        coalesce(pva.bounty_awarded,0) as bounty_awarded,
        coalesce(pva.delete_or_spam_votes,0) as delete_or_spam_votes,
        coalesce(ca.comment_count,0) as comment_count,
        ca.last_comment_date
    from question_posts qp
    left join post_vote_agg pva on pva.postid = qp.post_id
    left join comment_agg ca on ca.postid = qp.post_id
),
answer_metrics as (
    select
        ap.post_id,
        ap.question_id,
        ap.user_id,
        ap.creationdate,
        ap.score,
        coalesce(pva.upvotes,0) as upvotes,
        coalesce(pva.downvotes,0) as downvotes,
        coalesce(ca.comment_count,0) as comment_count
    from answer_posts ap
    left join post_vote_agg pva on pva.postid = ap.post_id
    left join comment_agg ca on ca.postid = ap.post_id
),
answer_ranked as (
    select
        am.post_id,
        am.question_id,
        am.user_id,
        am.creationdate,
        am.score,
        am.upvotes,
        am.downvotes,
        am.comment_count,
        row_number() over (partition by am.question_id order by am.score desc nulls last, am.upvotes desc, am.post_id) as rn_score,
        row_number() over (partition by am.question_id order by am.creationdate asc, am.post_id) as rn_fastest
    from answer_metrics am
),
accepted_answer_stats as (
    select
        qm.post_id,
        aa.post_id as accepted_answer_id,
        aa.score as accepted_score,
        aa.upvotes as accepted_upvotes,
        aa.downvotes as accepted_downvotes,
        aa.comment_count as accepted_comment_count
    from question_metrics qm
    left join answer_metrics aa on aa.post_id = qm.acceptedanswerid
),
top_answer_stats as (
    select
        ar.question_id,
        max(ar.score) as best_answer_score,
        sum(case when ar.rn_score = 1 then 1 else 0 end) as has_top_answer,
        min(case when ar.rn_fastest = 1 then extract(epoch from (ar.creationdate - q.creationdate)) end) as first_answer_secs
    from answer_ranked ar
    join posts q on q.id = ar.question_id
    group by ar.question_id
),
posthistory_close as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
        min(case when ph.posthistorytypeid = 11 then ph.creationdate end) as first_reopened_at,
        count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_undelete_events
    from posthistory ph
    group by ph.postid
),
user_activity as (
    select
        ru.user_id,
        count(distinct qm.post_id) as q_count,
        count(distinct am.post_id) as a_count,
        sum(qm.score) as q_score_sum,
        sum(am.score) as a_score_sum,
        avg(qm.viewcount) as avg_q_views,
        max(qm.creationdate) as last_q_date,
        max(am.creationdate) as last_a_date
    from recent_users ru
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    group by ru.user_id
),
cross_tag_pairs as (
    select
        q1.post_id as post_id,
        least(t1.tagname, t2.tagname) as tag_a,
        greatest(t1.tagname, t2.tagname) as tag_b
    from tag_explode t1
    join tag_explode t2
      on t1.post_id = t2.post_id
     and t1.tagname < t2.tagname
    join question_posts q1 on q1.post_id = t1.post_id
),
co_tag_stats as (
    select
        tag_a, tag_b,
        count(*) as pair_count,
        avg(qm.score) as avg_pair_q_score
    from cross_tag_pairs ctp
    join question_metrics qm on qm.post_id = ctp.post_id
    group by tag_a, tag_b
),
dupe_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate,
        lt.name as link_type_name
    from postlinks pl
    join linktypes lt on lt.id = pl.linktypeid
    where pl.linktypeid = 3
),
dupe_chains as (
    select
        d1.dup_post_id,
        d1.original_post_id,
        d1.creationdate as dup_created,
        d2.original_post_id as root_original_post_id
    from dupe_links d1
    left join dupe_links d2 on d2.dup_post_id = d1.original_post_id
),
question_quality as (
    select
        qm.post_id,
        case
            when qm.score >= 10 and qm.viewcount >= 10000 then 'stellar'
            when qm.score >= 3 and qm.viewcount >= 1000 then 'good'
            when qm.score <= 0 and qm.viewcount < 200 then 'poor'
            else 'average'
        end as quality_bucket,
        (qm.upvotes - qm.downvotes) as net_votes,
        case when qm.closeddate is not null then 1 else 0 end as is_closed
    from question_metrics qm
),
user_rank as (
    select
        ua.user_id,
        rank() over (order by coalesce(ua.q_score_sum,0) + coalesce(ua.a_score_sum,0) desc, ua.q_count desc, ua.a_count desc) as activity_rank
    from user_activity ua
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.creationdate as user_created,
    ru.location,
    ru.websiteurl_norm,
    ru.is_loc_null,
    ur.activity_rank,
    coalesce(ub.total_badges,0) as total_badges,
    coalesce(ub.gold_badges,0) as gold_badges,
    coalesce(ub.silver_badges,0) as silver_badges,
    coalesce(ub.bronze_badges,0) as bronze_badges,
    ua.q_count,
    ua.a_count,
    ua.q_score_sum,
    ua.a_score_sum,
    ua.avg_q_views,
    qa.quality_bucket,
    qa.net_votes,
    qa.is_closed,
    ts.tagname as dominant_tag,
    ts.q_count as dominant_tag_q_count,
    ts.closed_q_count as dominant_tag_closed_qs,
    ts.avg_q_score as dominant_tag_avg_score,
    cts.pair_count as top_cotag_pair_count,
    cts.avg_pair_q_score as top_cotag_pair_avg_score,
    aas.accepted_answer_id,
    aas.accepted_score,
    tas.best_answer_score,
    tas.first_answer_secs,
    phc.close_events,
    phc.reopen_events,
    phc.last_closed_at,
    phc.first_reopened_at,
    phc.delete_undelete_events,
    dl.original_post_id as dupe_of,
    dc.root_original_post_id as dupe_root
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join user_rank ur on ur.user_id = ru.user_id
left join user_badge_agg ub on ub.userid = ru.user_id
left join lateral (
    select te.tagname, ts2.q_count, ts2.closed_q_count, ts2.avg_q_score
    from tag_explode te
    join tag_stats ts2 on ts2.tagname = te.tagname
    join question_posts qp on qp.post_id = te.post_id and qp.user_id = ru.user_id
    group by te.tagname, ts2.q_count, ts2.closed_q_count, ts2.avg_q_score
    order by count(*) desc, ts2.q_count desc
    limit 1
) ts on true
left join lateral (
    select cts.tag_a, cts.tag_b, cts.pair_count, cts.avg_pair_q_score
    from cross_tag_pairs ctp
    join co_tag_stats cts on cts.tag_a = ctp.tag_a and cts.tag_b = ctp.tag_b
    join question_posts qp on qp.post_id = ctp.post_id and qp.user_id = ru.user_id
    order by cts.pair_count desc, cts.avg_pair_q_score desc nulls last
    limit 1
) cts on true
left join lateral (
    select qm.post_id
    from question_metrics qm
    where qm.user_id = ru.user_id
    order by (qm.upvotes - qm.downvotes) desc, qm.viewcount desc, qm.post_id
    limit 1
) best_q on true
left join question_quality qa on qa.post_id = best_q.post_id
left join accepted_answer_stats aas on aas.post_id = best_q.post_id
left join top_answer_stats tas on tas.question_id = best_q.post_id
left join posthistory_close phc on phc.postid = best_q.post_id
left join dupe_links dl on dl.dup_post_id = best_q.post_id
left join dupe_chains dc on dc.dup_post_id = best_q.post_id
where coalesce(ua.q_count,0) + coalesce(ua.a_count,0) > 0
order by ur.activity_rank nulls last, ru.reputation desc, ru.user_id
limit 200;