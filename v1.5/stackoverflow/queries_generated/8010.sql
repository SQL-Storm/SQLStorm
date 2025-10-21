-- {"query": "8010.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2602} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.title,
        p.tags,
        p.creationdate,
        p.score,
        p.viewcount,
        p.own eruserid,
        coalesce(p.own erdisplayname, u.displayname) as owner_name,
        u.reputation,
        u.location,
        row_number() over (partition by p.posttypeid order by p.creationdate desc, p.id desc) as rn
    from posts p
    left join users u on u.id = p.owneruserid
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
    select
        rp.id as post_id,
        rp.title,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        rp.owner_name,
        rp.reputation,
        lower(trim(tg)) as tag,
        rp.posttypeid
    from recent_posts rp
    cross join lateral unnest(
        case
            when rp.tags is null then array[]::varchar[]
            when length(rp.tags) <= 2 then array[]::varchar[]
            else string_to_array(substring(rp.tags, 2, length(rp.tags)-2), '><')
        end
    ) as tg
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_closed,
        count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by v.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_at,
        sum(case when c.score > 0 then 1 else 0 end) as positive_comments
    from comments c
    group by c.postid
),
links_agg as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 1) as linked_count,
        count(*) filter (where pl.linktypeid = 3) as duplicate_count,
        count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
    from postlinks pl
    group by pl.postid
),
history_flags as (
    select
        ph.postid,
        max(case when ph.posthistorytypeid in (10,11) then ph.creationdate end) as last_close_or_reopen,
        bool_or(ph.posthistorytypeid = 19) as ever_protected,
        count(*) filter (where ph.posthistorytypeid in (24,50,52,53)) as visibility_events,
        count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_events
    from posthistory ph
    group by ph.postid
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        count(distinct p.id) filter (where p.posttypeid = 1) as q_count,
        count(distinct p.id) filter (where p.posttypeid = 2) as a_count,
        coalesce(sum(v2.count_up),0) as total_upvotes_given,
        coalesce(sum(v2.count_down),0) as total_downvotes_given,
        rank() over (order by u.reputation desc, u.id) as rep_rank
    from users u
    left join posts p on p.owneruserid = u.id
    left join (
        select userid, 
               count(*) filter (where votetypeid = 2) as count_up,
               count(*) filter (where votetypeid = 3) as count_down
        from votes
        group by userid
    ) v2 on v2.userid = u.id
    group by u.id, u.displayname, u.reputation, u.location
),
answers_per_question as (
    select
        q.id as question_id,
        count(a.id) as answer_count,
        max(a.score) as max_answer_score,
        avg(a.score) filter (where a.score is not null) as avg_answer_score
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id
),
tag_popularity as (
    select
        te.tag,
        count(distinct te.post_id) as tag_post_count,
        sum(te.viewcount) as tag_views,
        avg(te.score) as tag_avg_score,
        percentile_cont(0.9) within group (order by te.viewcount) as p90_views
    from tag_expanded te
    group by te.tag
),
question_quality as (
    select
        te.post_id,
        te.title,
        te.creationdate,
        te.owner_name,
        te.reputation,
        te.viewcount,
        te.score,
        apq.answer_count,
        apq.max_answer_score,
        apq.avg_answer_score,
        va.upvotes,
        va.downvotes,
        va.mod_actions,
        la.linked_count,
        la.duplicate_count,
        la.distinct_dupe_targets,
        hf.last_close_or_reopen,
        hf.ever_protected,
        hf.visibility_events,
        hf.delete_events,
        array_agg(distinct te.tag) filter (where te.tag is not null) as tags_array,
        count(*) over () as total_rows_window,
        row_number() over (order by te.score desc nulls last, te.viewcount desc nulls last, te.post_id) as quality_rank
    from tag_expanded te
    join posts q on q.id = te.post_id and q.posttypeid = 1
    left join answers_per_question apq on apq.question_id = te.post_id
    left join votes_agg va on va.postid = te.post_id
    left join links_agg la on la.postid = te.post_id
    left join history_flags hf on hf.postid = te.post_id
    group by
        te.post_id, te.title, te.creationdate, te.owner_name, te.reputation, te.viewcount, te.score,
        apq.answer_count, apq.max_answer_score, apq.avg_answer_score,
        va.upvotes, va.downvotes, va.mod_actions,
        la.linked_count, la.duplicate_count, la.distinct_dupe_targets,
        hf.last_close_or_reopen, hf.ever_protected, hf.visibility_events, hf.delete_events
),
post_anomalies as (
    select
        q.post_id,
        q.title,
        q.score,
        q.viewcount,
        q.answer_count,
        q.upvotes,
        q.downvotes,
        q.duplicate_count,
        case 
            when q.viewcount > greatest(100, coalesce(tp.p90_views, 0)) and coalesce(q.answer_count,0) = 0 then 'high_views_no_answers'
            when coalesce(q.downvotes,0) > coalesce(q.upvotes,0) and coalesce(q.score,0) > 0 then 'score_up_despite_downvotes'
            when q.duplicate_count >= 3 then 'many_duplicates'
            else null
        end as anomaly_type
    from question_quality q
    left join lateral (
        select max(tp.p90_views) as p90_views
        from unnest(q.tags_array) t(tag)
        join tag_popularity tp on tp.tag = t.tag
    ) tp on true
    where
        (
            q.viewcount > greatest(100, coalesce(tp.p90_views, 0)) and coalesce(q.answer_count,0) = 0
        ) or (
            coalesce(q.downvotes,0) > coalesce(q.upvotes,0) and coalesce(q.score,0) > 0
        ) or (
            q.duplicate_count >= 3
        )
),
top_users as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.location,
        ua.q_count,
        ua.a_count,
        ua.total_upvotes_given,
        ua.total_downvotes_given
    from user_activity ua
    where ua.rep_rank <= 100
),
final_union as (
    select
        'high_quality' as bucket,
        q.post_id,
        q.title,
        q.owner_name,
        q.reputation,
        q.score,
        q.viewcount,
        q.answer_count,
        q.upvotes,
        q.downvotes,
        q.duplicate_count,
        q.tags_array,
        q.quality_rank,
        null::varchar as anomaly_type
    from question_quality q
    where q.quality_rank <= 200

    union all

    select
        'anomalies' as bucket,
        pa.post_id,
        pa.title,
        null as owner_name,
        null as reputation,
        pa.score,
        pa.viewcount,
        pa.answer_count,
        pa.upvotes,
        pa.downvotes,
        pa.duplicate_count,
        null::varchar[] as tags_array,
        null::bigint as quality_rank,
        pa.anomaly_type
    from post_anomalies pa
),
user_contrib as (
    select
        tu.user_id,
        tu.displayname,
        tu.reputation,
        tu.location,
        tu.q_count,
        tu.a_count,
        tu.total_upvotes_given,
        tu.total_downvotes_given,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as recent_questions,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as recent_answers
    from top_users tu
    left join posts p on p.owneruserid = tu.user_id and p.creationdate >= (select max(creationdate) - interval '90 days' from posts)
    group by tu.user_id, tu.displayname, tu.reputation, tu.location, tu.q_count, tu.a_count, tu.total_upvotes_given, tu.total_downvotes_given
)
select
    fu.bucket,
    fu.post_id,
    fu.title,
    fu.owner_name,
    fu.reputation,
    fu.score,
    fu.viewcount,
    fu.answer_count,
    fu.upvotes,
    fu.downvotes,
    fu.duplicate_count,
    fu.tags_array,
    fu.quality_rank,
    fu.anomaly_type,
    uc.user_id as sample_top_user_id,
    uc.displayname as sample_top_user_name,
    uc.reputation as sample_top_user_rep,
    uc.location as sample_top_user_location,
    uc.q_count as sample_total_q,
    uc.a_count as sample_total_a,
    uc.recent_questions as sample_recent_q_90d,
    uc.recent_answers as sample_recent_a_90d
from final_union fu
left join lateral (
    select uc.*
    from user_contrib uc
    where (uc.location is not null and fu.bucket = 'high_quality') or (uc.total_downvotes_given <= uc.total_upvotes_given)
    order by uc.reputation desc, uc.user_id
    limit 1
) uc on true
where
    (
        fu.bucket = 'high_quality'
        and (
            coalesce(fu.score,0) >= 5
            or coalesce(fu.viewcount,0) >= 1000
            or (fu.tags_array is not null and cardinality(fu.tags_array) >= 3)
        )
    )
    or (fu.bucket = 'anomalies')
order by
    case fu.bucket when 'anomalies' then 0 else 1 end,
    coalesce(fu.quality_rank, 9223372036854775807),
    fu.post_id nulls last;