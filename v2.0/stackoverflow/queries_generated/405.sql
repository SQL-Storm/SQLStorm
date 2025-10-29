-- {"query": "405.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2712} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.ownseruserid,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        p.commentcount,
        p.closeddate,
        p.lastactivitydate,
        p.acceptedanswerid
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
    select
        rp.id as post_id,
        lower(trim(t.tag)) as tag
    from recent_posts rp
    cross join lateral unnest(
        case
            when rp.tags is null then array[]::varchar[]
            else string_to_array(substring(rp.tags, 2, greatest(length(rp.tags)-2,0)), '><')
        end
    ) as t(tag)
),
post_quality as (
    select
        rp.id,
        rp.posttypeid,
        rp.creationdate,
        rp.score,
        rp.viewcount,
        coalesce(rp.answercount, 0) as answers,
        coalesce(rp.commentcount, 0) as comments,
        coalesce(rp.favoritecount, 0) as favorites,
        case when rp.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        case when rp.closeddate is not null then 1 else 0 end as is_closed,
        -- composite quality metric with varied weights and non-linear bits
        (coalesce(rp.viewcount,0) / nullif(date_part('day', now() - rp.creationdate) + 1,0)) * 0.15
        + ln(greatest(coalesce(rp.score,0) + 5, 1)) * 1.2
        + sqrt(greatest(coalesce(rp.answercount,0), 0)) * 0.9
        + least(coalesce(rp.commentcount,0), 10) * 0.1
        + case when rp.acceptedanswerid is not null then 2.5 else 0 end
        - case when rp.closeddate is not null then 3.0 else 0 end
        as quality_score
    from recent_posts rp
),
user_enrichment as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        u.upvotes,
        u.downvotes,
        u.views as profile_views,
        row_number() over (order by u.reputation desc, u.id) as user_rank_global
    from users u
),
post_authors as (
    select
        p.id as post_id,
        u.user_id,
        u.displayname,
        u.reputation,
        u.user_rank_global,
        u.upvotes,
        u.downvotes,
        u.profile_views
    from posts p
    left join user_enrichment u
      on u.user_id = p.owneruserid
),
badges_agg as (
    select
        b.userid,
        count(*) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_count,
        sum(case when b.class = 2 then 1 else 0 end) as silver_count,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
        sum(case when b.tagbased then 1 else 0 end) as tagbadges
    from badges b
    where b.date >= (select max(date) - interval '730 days' from badges)
    group by b.userid
),
votes_recent as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid in (8,9)) as bounties,
        sum(coalesce(v.bountyamount,0)) as bounty_amount
    from votes v
    where v.creationdate >= (select max(creationdate) - interval '365 days' from votes)
    group by v.postid
),
dupe_links as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_count,
        count(*) filter (where pl.linktypeid = 1) as linked_count
    from postlinks pl
    group by pl.postid
),
edits_cte as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit,
        max(ph.creationdate) as last_event,
        count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_events,
        count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_undelete_events
    from posthistory ph
    group by ph.postid
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_at,
        avg(coalesce(c.score,0)) as avg_comment_score,
        max(coalesce(c.score,0)) as max_comment_score
    from comments c
    where c.creationdate >= (select max(creationdate) - interval '365 days' from comments)
    group by c.postid
),
question_core as (
    select
        pq.id as post_id,
        pq.creationdate,
        pq.quality_score,
        pq.score,
        pq.viewcount,
        pq.answers,
        pq.comments,
        pq.favorites,
        pq.has_accepted,
        pq.is_closed,
        pa.user_id,
        pa.displayname,
        pa.reputation,
        pa.user_rank_global,
        coalesce(b.badge_count, 0) as badge_count,
        coalesce(b.gold_count, 0) as gold_count,
        coalesce(b.silver_count, 0) as silver_count,
        coalesce(b.bronze_count, 0) as bronze_count,
        coalesce(b.tagbadges, 0) as tagbadges,
        coalesce(v.upvotes,0) as v_up,
        coalesce(v.downvotes,0) as v_down,
        coalesce(v.bounties,0) as v_bounty_events,
        coalesce(v.bounty_amount,0) as v_bounty_amount,
        coalesce(d.dup_count,0) as dup_count,
        coalesce(d.linked_count,0) as linked_count,
        coalesce(e.edit_events,0) as edit_events,
        e.first_edit,
        e.last_event,
        coalesce(e.close_reopen_events,0) as close_reopen_events,
        coalesce(e.delete_undelete_events,0) as delete_undelete_events,
        coalesce(ca.comment_count,0) as recent_comments,
        ca.last_comment_at,
        coalesce(ca.avg_comment_score,0) as avg_comment_score,
        coalesce(ca.max_comment_score,0) as max_comment_score
    from post_quality pq
    left join post_authors pa on pa.post_id = pq.id
    left join badges_agg b on b.userid = pa.user_id
    left join votes_recent v on v.postid = pq.id
    left join dupe_links d on d.postid = pq.id
    left join edits_cte e on e.postid = pq.id
    left join comments_agg ca on ca.postid = pq.id
    where pq.posttypeid = 1
),
tag_rollup as (
    select
        te.post_id,
        array_agg(distinct te.tag order by te.tag) as tags,
        count(*) as tag_count,
        sum(case when te.tag ~ '(^how|help|issue|error$)' then 1 else 0 end) as problem_tags
    from tag_expanded te
    group by te.post_id
),
answer_latency as (
    select
        q.id as question_id,
        min(a.creationdate) - q.creationdate as first_answer_latency,
        percentile_disc(0.5) within group (order by a.creationdate - q.creationdate) as p50_latency,
        count(a.id) as total_answers
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
      and q.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by q.id, q.creationdate
),
ranked as (
    select
        qc.*,
        tr.tags,
        tr.tag_count,
        tr.problem_tags,
        al.first_answer_latency,
        al.p50_latency,
        al.total_answers,
        row_number() over (
            partition by case when qc.is_closed = 1 then 'closed' else 'open' end
            order by qc.quality_score desc, qc.viewcount desc, qc.score desc
        ) as rn_by_status,
        rank() over (order by qc.quality_score desc) as quality_rank,
        dense_rank() over (order by coalesce(qc.v_up - qc.v_down,0) desc) as netvote_rank,
        avg(qc.quality_score) over () as avg_quality_overall,
        avg(qc.quality_score) over (partition by case when qc.is_closed = 1 then 'closed' else 'open' end) as avg_quality_by_status,
        sum(qc.viewcount) over (order by qc.creationdate rows between unbounded preceding and current row) as running_views,
        count(*) over () as total_considered
    from question_core qc
    left join tag_rollup tr on tr.post_id = qc.post_id
    left join answer_latency al on al.question_id = qc.post_id
),
null_logic_demo as (
    select
        r.*,
        case
            when coalesce(r.tag_count,0) = 0 then 'untagged'
            when r.tag_count >= 5 then 'broad'
            when r.tag_count between 3 and 4 then 'normal'
            else 'narrow'
        end as tag_breadth,
        coalesce(r.tags, array['<none>']) as tags_normalized,
        case when r.first_answer_latency is null then interval '99999 hours' else r.first_answer_latency end as fal_norm
    from ranked r
),
final_set as (
    select
        'top_open' as bucket,
        n.*
    from null_logic_demo n
    where n.is_closed = 0 and n.rn_by_status <= 100

    union all

    select
        'top_closed' as bucket,
        n.*
    from null_logic_demo n
    where n.is_closed = 1 and n.rn_by_status <= 100

    union all

    select
        'outliers' as bucket,
        n.*
    from null_logic_demo n
    where (n.quality_score > n.avg_quality_overall * 2.5 or n.quality_score < n.avg_quality_overall * 0.4)
)
select
    f.bucket,
    f.post_id,
    f.creationdate,
    f.displayname,
    f.reputation,
    f.user_rank_global,
    coalesce(f.tags_normalized::text, '{<none>}') as tags_text,
    f.tag_breadth,
    f.tag_count,
    f.problem_tags,
    f.quality_score,
    f.quality_rank,
    f.netvote_rank,
    f.viewcount,
    f.score,
    f.answers,
    f.has_accepted,
    f.is_closed,
    f.v_up,
    f.v_down,
    f.v_bounty_events,
    f.v_bounty_amount,
    f.edit_events,
    f.close_reopen_events,
    f.delete_undelete_events,
    f.dup_count,
    f.linked_count,
    extract(epoch from f.fal_norm) as first_answer_latency_seconds,
    extract(epoch from f.p50_latency) as median_answer_latency_seconds,
    f.recent_comments,
    f.avg_comment_score,
    f.max_comment_score,
    f.running_views,
    f.total_considered
from final_set f
where (
    f.problem_tags > 0
    or (f.v_up - f.v_down) >= 5
    or (f.dup_count = 0 and f.answers >= 2 and f.has_accepted = 0)
)
order by f.bucket, f.quality_rank, f.post_id
limit 500;