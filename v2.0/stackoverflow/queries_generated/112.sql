-- {"query": "112.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2669} 
with recent_posts as (
    select
        p.id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.owneruserid,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid
    from posts p
    where p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
tag_expanded as (
    select
        rp.id as post_id,
        unnest(string_to_array(coalesce(substring(rp.tags, 2, length(rp.tags)-2), ''), '><')) as tagname
    from recent_posts rp
    where rp.posttypeid = 1
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate as user_created,
        coalesce(sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end), 0) as vote_delta_given,
        coalesce(sum(case when v.votetypeid = 5 then 1 else 0 end), 0) as favorites_given,
        count(distinct b.id) filter (where b.class = 1) as gold_badges,
        count(distinct b.id) filter (where b.class = 2) as silver_badges,
        count(distinct b.id) filter (where b.class = 3) as bronze_badges
    from users u
    left join votes v on v.userid = u.id
    left join badges b on b.userid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate
),
post_stats as (
    select
        rp.id as post_id,
        rp.posttypeid,
        rp.owneruserid,
        rp.score,
        rp.viewcount,
        rp.creationdate,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        count(c.id) as comment_count,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total
    from recent_posts rp
    left join votes v on v.postid = rp.id
    left join comments c on c.postid = rp.id
    group by rp.id, rp.posttypeid, rp.owneruserid, rp.score, rp.viewcount, rp.creationdate
),
dup_clusters as (
    select
        pl.relatedpostid as canonical_id,
        count(*) filter (where pl.linktypeid = 3) as dup_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
edit_bursts as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        min(ph.creationdate) as first_edit,
        max(ph.creationdate) as last_edit
    from posthistory ph
    where ph.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by ph.postid
),
question_answer_rollup as (
    select
        q.id as question_id,
        q.creationdate as question_created,
        q.owneruserid as asker_id,
        ps_q.upvotes as q_up,
        ps_q.downvotes as q_down,
        ps_q.favorites as q_fav,
        count(a.id) as answers_count,
        sum(ps_a.upvotes) as a_up_total,
        sum(ps_a.downvotes) as a_down_total,
        max(case when a.id = q.acceptedanswerid then ps_a.upvotes - ps_a.downvotes else null end) as accepted_score,
        max(ps_a.score) as best_answer_score
    from recent_posts q
    join post_stats ps_q on ps_q.post_id = q.id and q.posttypeid = 1
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    left join post_stats ps_a on ps_a.post_id = a.id
    group by q.id, q.creationdate, q.owneruserid, ps_q.upvotes, ps_q.downvotes, ps_q.favorites
),
windowed as (
    select
        qr.question_id,
        qr.question_created,
        qr.asker_id,
        qr.answers_count,
        qr.q_up,
        qr.q_down,
        qr.q_fav,
        qr.a_up_total,
        qr.a_down_total,
        qr.accepted_score,
        qr.best_answer_score,
        rank() over (order by coalesce(qr.a_up_total,0) - coalesce(qr.a_down_total,0) desc nulls last, qr.answers_count desc, qr.q_fav desc) as rank_by_answer_engagement,
        percentile_disc(0.5) within group (order by coalesce(qr.best_answer_score, -1000)) over () as median_best_answer_score
    from question_answer_rollup qr
),
tag_agg as (
    select
        te.post_id,
        string_agg(distinct te.tagname, ',') as tags_csv,
        count(*) as tag_count,
        max(case when te.tagname ilike '%sql%' then 1 else 0 end) as has_sql
    from tag_expanded te
    group by te.post_id
),
user_rollup as (
    select
        ua.user_id,
        ua.displayname,
        ua.reputation,
        ua.user_created,
        ua.vote_delta_given,
        ua.favorites_given,
        ua.gold_badges,
        ua.silver_badges,
        ua.bronze_badges,
        row_number() over (order by ua.reputation desc, ua.gold_badges desc, ua.silver_badges desc) as rep_rank
    from user_activity ua
),
close_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes,
        max(case when ph.posthistorytypeid = 10 then nullif(ph.comment, '') end) as last_close_reason_id,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_at
    from posthistory ph
    group by ph.postid
),
close_reasons as (
    select
        ce.postid,
        crt.name as close_reason_name
    from close_events ce
    left join closereasontypes crt
      on cast(ce.last_close_reason_id as int) = crt.id
),
joined as (
    select
        w.question_id,
        p.title,
        coalesce(ta.tags_csv, '') as tags_csv,
        coalesce(ta.tag_count, 0) as tag_count,
        coalesce(ta.has_sql, 0) as has_sql_tag,
        w.answers_count,
        w.q_up - w.q_down as q_score_net,
        w.q_fav,
        w.a_up_total - w.a_down_total as a_score_net,
        w.accepted_score,
        w.best_answer_score,
        w.rank_by_answer_engagement,
        w.median_best_answer_score,
        u.displayname as asker_name,
        u.reputation as asker_rep,
        u.rep_rank as asker_rep_rank,
        coalesce(ec.edit_events, 0) as edit_events,
        ec.first_edit,
        ec.last_edit,
        coalesce(dc.dup_count, 0) as duplicate_reports,
        ce.close_votes,
        coalesce(cr.close_reason_name, 'Open') as close_reason_name,
        p.viewcount,
        p.score as raw_q_score,
        case
            when p.viewcount is null or p.viewcount = 0 then null
            else round((w.a_up_total - w.a_down_total)::numeric / nullif(p.viewcount,0), 6)
        end as engagement_per_view,
        case when w.best_answer_score is null then 'NoBest' else 'HasBest' end as best_answer_flag
    from windowed w
    join posts p on p.id = w.question_id
    left join tag_agg ta on ta.post_id = w.question_id
    left join user_rollup u on u.user_id = (select owneruserid from posts x where x.id = w.question_id)
    left join edit_bursts ec on ec.postid = w.question_id
    left join dup_clusters dc on dc.canonical_id = w.question_id
    left join close_events ce on ce.postid = w.question_id
    left join close_reasons cr on cr.postid = w.question_id
),
anomalies as (
    select
        j.*,
        avg(q_score_net) over () as avg_q_net,
        stddev_pop(q_score_net) over () as std_q_net,
        avg(a_score_net) over () as avg_a_net,
        stddev_pop(a_score_net) over () as std_a_net,
        avg(edit_events) over () as avg_edits,
        stddev_pop(edit_events) over () as std_edits
    from joined j
),
flagged as (
    select
        a.*,
        case when a.q_score_net > a.avg_q_net + 2 * coalesce(a.std_q_net, 0) then 1 else 0 end as q_outlier_high,
        case when a.q_score_net < a.avg_q_net - 2 * coalesce(a.std_q_net, 0) then 1 else 0 end as q_outlier_low,
        case when a.a_score_net > a.avg_a_net + 2 * coalesce(a.std_a_net, 0) then 1 else 0 end as a_outlier_high,
        case when a.a_score_net < a.avg_a_net - 2 * coalesce(a.std_a_net, 0) then 1 else 0 end as a_outlier_low,
        case when a.edit_events > a.avg_edits + 3 * coalesce(a.std_edits, 0) then 1 else 0 end as edit_spike
    from anomalies a
),
final_set as (
    select
        'TOP_ENGAGEMENT' as bucket,
        f.*
    from flagged f
    where f.rank_by_answer_engagement <= 100

    union all

    select
        'SQL_TAGGED_HOT' as bucket,
        f.*
    from flagged f
    where f.has_sql_tag = 1
      and coalesce(f.engagement_per_view, 0) > (
          select coalesce(avg(nullif(a.engagement_per_view,0)), 0)
          from anomalies a
      )

    union all

    select
        'ANOMALIES' as bucket,
        f.*
    from flagged f
    where f.q_outlier_high = 1
       or f.a_outlier_high = 1
       or f.edit_spike = 1

    union all

    select
        'DUPLICATES_WITH_CLOSE' as bucket,
        f.*
    from flagged f
    where f.duplicate_reports > 0
      and coalesce(f.close_votes,0) > 0
)
select
    bucket,
    question_id,
    title,
    tags_csv,
    tag_count,
    has_sql_tag,
    answers_count,
    q_score_net,
    q_fav,
    a_score_net,
    accepted_score,
    best_answer_score,
    rank_by_answer_engagement,
    median_best_answer_score,
    asker_name,
    asker_rep,
    asker_rep_rank,
    edit_events,
    first_edit,
    last_edit,
    duplicate_reports,
    close_votes,
    close_reason_name,
    viewcount,
    raw_q_score,
    engagement_per_view,
    best_answer_flag,
    q_outlier_high,
    q_outlier_low,
    a_outlier_high,
    a_outlier_low,
    edit_spike
from final_set
order by
    case bucket
        when 'TOP_ENGAGEMENT' then 1
        when 'SQL_TAGGED_HOT' then 2
        when 'ANOMALIES' then 3
        when 'DUPLICATES_WITH_CLOSE' then 4
        else 5
    end,
    rank_by_answer_engagement nulls last,
    q_score_net desc,
    a_score_net desc,
    answers_count desc
limit 500;