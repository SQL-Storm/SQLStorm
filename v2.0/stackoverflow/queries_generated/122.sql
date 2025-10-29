-- {"query": "122.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3089} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        row_number() over (order by u.creationdate desc, u.id) as rn_desc,
        dense_rank() over (order by coalesce(nullif(u.location, ''), 'Unknown')) as loc_rank
    from users u
    where u.creationdate >= (select date_trunc('year', max(creationdate)) - interval '2 years' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as post_count,
        count(distinct c.id) as comment_count,
        sum(vote_up) as upvotes_cast,
        sum(vote_down) as downvotes_cast,
        sum(bounty_amt) as bounty_spent
    from recent_users u
    left join posts p
        on p.owneruserid = u.user_id
       and p.creationdate >= u.creationdate
    left join comments c
        on c.userid = u.user_id
       and c.creationdate >= u.creationdate
    left join lateral (
        select
            v.userid,
            sum(case when v.votetypeid = 2 then 1 else 0 end) as vote_up,
            sum(case when v.votetypeid = 3 then 1 else 0 end) as vote_down,
            sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_amt
        from votes v
        where v.userid = u.user_id
          and v.creationdate >= u.creationdate
        group by v.userid
    ) vv on true
    group by u.user_id
),
posts_enriched as (
    select
        p.id,
        p.posttypeid,
        p.parentid,
        p.acceptedanswerid,
        p.owneruserid,
        p.creationdate,
        p.lastactivitydate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.commentcount,
        p.closeddate,
        p.contentlicense,
        array_length(string_to_array(coalesce(nullif(substring(p.tags, 2, length(p.tags)-2), ''), ''), '><'), 1) as tag_count,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        lead(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as next_post_time,
        lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_post_time
    from posts p
    where p.posttypeid in (1,2)
),
question_answer_link as (
    select
        q.id as question_id,
        a.id as answer_id,
        a.owneruserid as answer_user_id,
        q.owneruserid as question_user_id,
        a.creationdate as answer_time,
        q.creationdate as question_time,
        extract(epoch from (a.creationdate - q.creationdate)) as answer_latency_sec,
        case when a.id = q.acceptedanswerid then 1 else 0 end as is_accepted
    from posts_enriched q
    join posts_enriched a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
),
dup_and_linked as (
    select
        pl.postid as src_post_id,
        pl.relatedpostid as dst_post_id,
        pl.linktypeid,
        min(pl.creationdate) as first_link_date,
        count(*) as link_events
    from postlinks pl
    group by pl.postid, pl.relatedpostid, pl.linktypeid
),
history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid in (12,10) then 1 else 0 end) as had_moderation,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_events
    from posthistory ph
    group by ph.postid
),
tag_activity as (
    select
        t.tagname,
        t.count as tag_count_total,
        coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as questions_with_tag,
        coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as answers_with_tag
    from tags t
    left join posts p
      on p.posttypeid in (1,2)
     and p.tags like '%<' || t.tagname || '>%'
    group by t.tagname, t.count
),
user_badges as (
    select
        b.userid,
        count(*) as badges_total,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
user_last_seen as (
    select
        u.id as user_id,
        u.lastaccessdate,
        max(p.lastactivitydate) as last_post_activity,
        greatest(u.lastaccessdate, coalesce(max(p.lastactivitydate), u.lastaccessdate)) as last_seen_any
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, u.lastaccessdate
),
question_metrics as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_time,
        q.score as question_score,
        q.viewcount,
        q.tag_count,
        q.is_closed,
        coalesce(hf.was_closed, 0) as ever_closed,
        coalesce(hf.was_reopened, 0) as ever_reopened,
        coalesce(hf.edit_events, 0) as edit_events,
        count(*) filter (where qal.is_accepted = 1) as accepted_answers,
        count(qal.answer_id) as total_answers,
        min(qal.answer_latency_sec) as fastest_answer_sec,
        avg(qal.answer_latency_sec) as avg_answer_sec
    from posts_enriched q
    left join question_answer_link qal on qal.question_id = q.id
    left join history_flags hf on hf.postid = q.id
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.tag_count, q.is_closed, hf.was_closed, hf.was_reopened, hf.edit_events
),
user_quality as (
    select
        u.user_id,
        percentile_cont(0.5) within group (order by q.question_score) as median_q_score,
        avg(q.question_score) as avg_q_score,
        coalesce(sum(q.total_answers),0) as answers_to_questions,
        coalesce(sum(q.accepted_answers),0) as accepted_on_questions,
        avg(case when q.total_answers > 0 then q.accepted_answers::numeric / q.total_answers else null end) as acceptance_ratio_avg,
        count(*) as questions_asked
    from recent_users u
    left join question_metrics q on q.asker_id = u.user_id
    group by u.user_id
),
activity_windows as (
    select
        p.owneruserid as user_id,
        p.posttypeid,
        p.creationdate::date as day_bucket,
        count(*) as posts_on_day,
        sum(p.score) as score_on_day,
        rank() over (partition by p.owneruserid order by count(*) desc, sum(p.score) desc) as busiest_day_rank
    from posts_enriched p
    group by p.owneruserid, p.posttypeid, p.creationdate::date
),
power_users as (
    select
        u.user_id,
        u.displayname,
        u.reputation,
        u.location,
        ua.post_count,
        ua.comment_count,
        ua.upvotes_cast,
        ua.downvotes_cast,
        ua.bounty_spent,
        coalesce(ub.badges_total,0) as badges_total,
        coalesce(ub.gold_count,0) as gold_count,
        coalesce(ub.silver_count,0) as silver_count,
        coalesce(ub.bronze_count,0) as bronze_count,
        coalesce(ub.tag_badges,0) as tag_badges,
        uq.median_q_score,
        uq.avg_q_score,
        uq.answers_to_questions,
        uq.accepted_on_questions,
        uq.acceptance_ratio_avg,
        uq.questions_asked,
        ul.last_seen_any,
        u.website_host
    from recent_users u
    left join user_activity ua on ua.user_id = u.user_id
    left join user_badges ub on ub.userid = u.user_id
    left join user_quality uq on uq.user_id = u.user_id
    left join user_last_seen ul on ul.user_id = u.user_id
),
ranked_power as (
    select
        pu.*,
        row_number() over (
            order by
                coalesce(pu.reputation,0) desc,
                coalesce(pu.post_count,0) desc,
                coalesce(pu.badges_total,0) desc,
                coalesce(pu.upvotes_cast,0) desc
        ) as global_rank,
        ntile(10) over (order by coalesce(pu.reputation,0) desc) as rep_decile
    from power_users pu
),
cross_tag_pairs as (
    select
        q1.id as qid1,
        q2.id as qid2,
        q1.tags as tags1,
        q2.tags as tags2
    from posts q1
    join posts q2
      on q1.posttypeid = 1 and q2.posttypeid = 1
     and q1.id < q2.id
     and q1.creationdate >= q2.creationdate - interval '7 days'
     and q1.creationdate <= q2.creationdate + interval '7 days'
     and q1.tags is not null and q2.tags is not null
     and q1.tags <> q2.tags
    where exists (
        select 1
        from postlinks pl
        where pl.linktypeid in (1,3)
          and ((pl.postid = q1.id and pl.relatedpostid = q2.id) or (pl.postid = q2.id and pl.relatedpostid = q1.id))
    )
),
pair_overlap as (
    select
        ct.qid1,
        ct.qid2,
        (
            select count(*)
            from (
                select unnest(string_to_array(substring(ct.tags1, 2, length(ct.tags1)-2), '><')) intersect
                select unnest(string_to_array(substring(ct.tags2, 2, length(ct.tags2)-2), '><'))
            ) s(x)
        ) as shared_tag_count
    from cross_tag_pairs ct
),
final_candidates as (
    select
        rp.*,
        case
            when coalesce(rp.questions_asked,0) = 0 then null
            else rp.accepted_on_questions::numeric / nullif(rp.answers_to_questions,0)
        end as acceptance_ratio_overall,
        case when coalesce(rp.downvotes_cast,0) > 0 then rp.upvotes_cast::numeric / rp.downvotes_cast else null end as up_down_ratio
    from ranked_power rp
    where rp.rep_decile in (1,2,3)
)
select
    fc.global_rank,
    fc.user_id,
    coalesce(fc.displayname, '(unknown)') as displayname,
    fc.reputation,
    fc.location,
    fc.website_host,
    fc.post_count,
    fc.comment_count,
    fc.upvotes_cast,
    fc.downvotes_cast,
    fc.up_down_ratio,
    fc.badges_total,
    fc.gold_count,
    fc.silver_count,
    fc.bronze_count,
    fc.tag_badges,
    round(coalesce(fc.median_q_score, fc.avg_q_score, 0), 2) as median_q_score,
    round(coalesce(fc.avg_q_score, 0), 2) as avg_q_score,
    fc.questions_asked,
    round(coalesce(fc.acceptance_ratio_avg, fc.acceptance_ratio_overall, 0), 4) as acceptance_ratio,
    ul.last_post_activity,
    qm.viewcount as sample_q_views,
    qm.total_answers as sample_q_answers,
    qm.fastest_answer_sec as sample_q_fastest_sec,
    d.linktypeid as sample_link_type,
    d.link_events as sample_link_events,
    po.shared_tag_count as sample_shared_tags
from final_candidates fc
left join user_last_seen ul on ul.user_id = fc.user_id
left join lateral (
    select qm.*
    from question_metrics qm
    where qm.asker_id = fc.user_id
    order by qm.viewcount desc nulls last, qm.question_score desc nulls last
    limit 1
) qm on true
left join lateral (
    select d.*
    from dup_and_linked d
    join posts p on p.id = d.src_post_id and p.owneruserid = fc.user_id
    where d.linktypeid in (1,3)
    order by d.link_events desc, d.first_link_date desc
    limit 1
) d on true
left join lateral (
    select po.*
    from pair_overlap po
    join posts q on q.id = po.qid1 and q.owneruserid = fc.user_id
    order by po.shared_tag_count desc
    limit 1
) po on true
where
    (fc.post_count + coalesce(fc.comment_count,0)) > 0
    and coalesce(fc.upvotes_cast,0) + coalesce(fc.downvotes_cast,0) >= 1
order by
    fc.global_rank asc,
    fc.user_id
limit 200;