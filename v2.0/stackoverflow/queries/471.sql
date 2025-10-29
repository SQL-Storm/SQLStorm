-- {"query": "471.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2761}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region_hint,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select coalesce(max(creationdate), timestamp '2024-10-01 12:34:56') - interval '5 years' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        sum(p.score) filter (where p.posttypeid in (1,2)) as total_post_score,
        sum(p.viewcount) filter (where p.posttypeid = 1) as question_views,
        count(c.id) as total_comments,
        sum(c.score) as comment_score,
        count(b.id) as badges_earned,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(c.creationdate, u.creationdate), coalesce(b.date, u.creationdate))) as last_seen_activity
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
     and p.creationdate >= u.creationdate
    left join comments c
      on c.userid = u.user_id
     and c.creationdate >= u.creationdate
    left join badges b
      on b.userid = u.user_id
     and b.date >= u.creationdate
    group by u.user_id
),
post_enrichment as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.parentid,
        p.acceptedanswerid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.closeddate,
        string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2, 0)), '><') as tag_arr,
        array_length(string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2, 0)), '><'), 1) as tag_count
    from posts p
    where p.creationdate >= (select min(creationdate) from recent_users)
),
q_metrics as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_created,
        q.score as question_score,
        q.viewcount as question_views,
        q.answercount,
        q.closeddate,
        min(a.creationdate) as first_answer_date,
        extract(epoch from (min(a.creationdate) - q.creationdate)) as secs_to_first_answer,
        sum(case when a.id = q.acceptedanswerid then 1 else 0 end) as has_accepted,
        count(a.id) as answers_total,
        avg(a.score) as avg_answer_score,
        max(a.score) as max_answer_score
    from post_enrichment q
    left join posts a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.closeddate
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        min(pl.creationdate) as first_dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_time,
        cast(max(case
                when ph.posthistorytypeid = 10 then
                    nullif(trim(split_part(coalesce(ph.comment, ''), ' ', 1)), '')
             end) as integer) as sample_close_reason_code
    from posthistory ph
    where ph.posthistorytypeid in (10, 11)
    group by ph.postid
),
vote_rollup as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 1) as accepted_by_originator,
        count(*) filter (where v.votetypeid = 8) as bounty_starts,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    group by v.postid
),
tag_popularity as (
    select
        lower(t.tagname) as tagname,
        t.count as tag_usage_count
    from tags t
),
question_tag_expanded as (
    select
        q.id as question_id,
        unnest(pe.tag_arr) as tagname
    from post_enrichment pe
    join posts q on q.id = pe.id and pe.posttypeid = 1
),
tag_rank as (
    select
        qte.question_id,
        qte.tagname,
        tp.tag_usage_count,
        dense_rank() over (partition by qte.question_id order by tp.tag_usage_count desc nulls last, qte.tagname) as tag_pop_rank
    from question_tag_expanded qte
    left join tag_popularity tp on tp.tagname = lower(qte.tagname)
),
question_quality as (
    select
        qm.question_id,
        (coalesce(vr.upvotes, 0) - coalesce(vr.downvotes, 0)) * 2
        + coalesce(qm.answers_total, 0) * 1.5
        + least(coalesce(qm.question_views, 0) / 100.0, 50)
        + case when exists (
            select 1 from tag_rank tr
            where tr.question_id = qm.question_id and tr.tag_pop_rank >= 3
        ) then 2 else 0 end
        - case when ce.first_close_time is not null then 10 else 0 end
        as quality_score,
        coalesce(vr.upvotes,0) as upvotes,
        coalesce(vr.downvotes,0) as downvotes,
        coalesce(vr.bounty_total,0) as bounty_total,
        ce.sample_close_reason_code,
        ce.first_close_time,
        dl.original_post_id as marked_duplicate_of
    from q_metrics qm
    left join vote_rollup vr on vr.postid = qm.question_id
    left join close_events ce on ce.postid = qm.question_id
    left join dup_links dl on dl.dup_post_id = qm.question_id
),
user_post_windows as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        row_number() over (partition by p.owneruserid order by p.creationdate) as post_seq,
        avg(p.score) over (partition by p.owneruserid order by p.creationdate rows between 9 preceding and current row) as rolling_avg_score_last_10,
        sum(case when p.posttypeid = 1 then 1 else 0 end) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as cumulative_questions
    from posts p
    where p.owneruserid is not null
),
answered_own_question as (
    select
        q.id as question_id,
        case when exists (
            select 1
            from posts a
            where a.parentid = q.id
              and a.posttypeid = 2
              and a.owneruserid = q.owneruserid
        ) then 1 else 0 end as self_answered
    from posts q
    where q.posttypeid = 1
),
top_recent_questions as (
    select
        qm.question_id,
        qm.asker_id,
        qm.question_created,
        qq.quality_score,
        rank() over (order by qq.quality_score desc, qm.question_created desc) as global_quality_rank
    from q_metrics qm
    join question_quality qq on qq.question_id = qm.question_id
    where qm.question_created >= (select max(cohort_month) - interval '18 months' from recent_users)
),
cohort_percentiles as (
    select
        user_id,
        cohort_month,
        reputation,
        percent_rank() over (partition by cohort_month order by reputation) as cohort_rep_percentile
    from recent_users
)
select
    ru.user_id,
    ru.displayname,
    ru.reputation,
    ru.region_hint,
    ru.cohort_month,
    ua.total_posts,
    ua.total_post_score,
    ua.question_views,
    ua.total_comments,
    ua.comment_score,
    ua.badges_earned,
    ua.gold_badges,
    ua.silver_badges,
    ua.bronze_badges,
    ua.last_seen_activity,
    count(distinct trq.question_id) as top_q_count,
    avg(trq.quality_score) as avg_top_q_quality,
    min(trq.global_quality_rank) as best_quality_rank,
    string_agg(distinct case when tr.tag_pop_rank = 1 then lower(tr.tagname) end, ',') filter (where tr.tag_pop_rank = 1) as primary_tags,
    coalesce(max(case when qq.sample_close_reason_code is not null then 1 end), 0) as had_any_closure,
    sum(aq.self_answered) as self_answered_questions,
    (
        select p2.title
        from posts p2
        where p2.owneruserid = ru.user_id and p2.posttypeid = 1
        order by coalesce(p2.viewcount, 0) desc, p2.creationdate desc
        limit 1
    ) as top_question_title,
    cp.cohort_rep_percentile,
    (
        select count(distinct lower(tname))
        from (
            select unnest(string_to_array(substring(coalesce(p.tags, ''), 2, greatest(length(coalesce(p.tags, ''))-2, 0)), '><')) as tname
            from posts p
            where p.owneruserid = ru.user_id and p.posttypeid = 1
            union
            select unnest(string_to_array(substring(coalesce(q.tags, ''), 2, greatest(length(coalesce(q.tags, ''))-2, 0)), '><'))
            from posts a
            join posts q on q.id = a.parentid
            where a.owneruserid = ru.user_id and a.posttypeid = 2
        ) s
    ) as distinct_tags_touchpoints
from recent_users ru
left join user_activity ua on ua.user_id = ru.user_id
left join top_recent_questions trq on trq.asker_id = ru.user_id
left join question_quality qq on qq.question_id = trq.question_id
left join tag_rank tr on tr.question_id = trq.question_id and tr.tag_pop_rank = 1
left join answered_own_question aq on aq.question_id = trq.question_id
left join cohort_percentiles cp on cp.user_id = ru.user_id
where coalesce(ua.total_posts, 0) + coalesce(ua.total_comments, 0) + coalesce(ua.badges_earned, 0) > 0
group by
    ru.user_id, ru.displayname, ru.reputation, ru.region_hint, ru.cohort_month,
    ua.total_posts, ua.total_post_score, ua.question_views, ua.total_comments, ua.comment_score,
    ua.badges_earned, ua.gold_badges, ua.silver_badges, ua.bronze_badges, ua.last_seen_activity,
    cp.cohort_rep_percentile
having
    coalesce(sum(trq.quality_score), 0) + coalesce(ua.total_post_score, 0) + coalesce(ua.question_views, 0) > 0
order by
    avg(trq.quality_score) desc nulls last,
    ua.last_seen_activity desc nulls last,
    ru.reputation desc
limit 200;