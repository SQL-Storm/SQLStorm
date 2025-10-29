-- {"query": "665.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3435}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where c.id is not null) as total_comments,
        sum(v.score_delta) as net_votes,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcvd,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcvd,
        max(greatest(coalesce(p.lastactivitydate, p.creationdate), coalesce(c.creationdate, cast('1970-01-01' as timestamp)))) as last_activity
    from recent_users u
    left join posts p
      on p.owneruserid = u.user_id
     and p.creationdate >= u.creationdate
    left join lateral (
        select v2.votetypeid,
               case when v2.votetypeid = 2 then 1 when v2.votetypeid = 3 then -1 else 0 end as score_delta
        from votes v2
        join votetypes vt on vt.id = v2.votetypeid
        where v2.postid = p.id
    ) v on true
    left join comments c
      on c.userid = u.user_id
     and c.creationdate >= u.creationdate
    group by u.user_id
),
post_detail as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid as user_id,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.acceptedanswerid,
        case
            when p.posttypeid = 1 then 1
            when p.posttypeid = 2 then 0
            else null
        end as is_question,
        exists (
            select 1
            from posthistory ph
            where ph.postid = p.id
              and ph.posthistorytypeid in (10,35)
        ) as was_closed_or_migrated,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
question_enrichment as (
    select
        q.post_id,
        q.user_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.acceptedanswerid,
        q.was_closed_or_migrated,
        q.is_closed,
        lower(nullif(split_part(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><', 1), '')) as tag1,
        lower(nullif(split_part(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><', 2), '')) as tag2,
        lower(nullif(split_part(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><', 3), '')) as tag3
    from post_detail q
    where q.is_question = 1
),
tag_stats as (
    select
        t.tagname,
        t.count as total_tag_usage,
        coalesce(case when t.ismoderatoronly then 1 else 0 end, 0) as is_mod_only,
        coalesce(case when t.isrequired then 1 else 0 end, 0) as is_required
    from tags t
),
duplicates_cte as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           min(pl.creationdate) as first_dup_link_at
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
answer_metrics as (
    select
        a.parentid as question_id,
        count(*) as answers_count,
        avg(cast(a.score as numeric)) as avg_answer_score,
        max(a.score) as max_answer_score,
        count(*) filter (where a.owneruserid is null) as answers_by_unknown
    from posts a
    where a.posttypeid = 2
      and a.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    group by a.parentid
),
accept_latency as (
    select
        q.id as question_id,
        case
            when q.acceptedanswerid is null then null
            else (select a.creationdate from posts a where a.id = q.acceptedanswerid)
        end as accepted_at,
        q.creationdate as asked_at
    from posts q
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
question_quality as (
    select
        qe.post_id,
        qe.user_id,
        qe.creationdate,
        qe.score,
        qe.viewcount,
        qe.title,
        qe.tags,
        qe.answercount,
        qe.acceptedanswerid,
        qe.was_closed_or_migrated,
        qe.is_closed,
        am.answers_count,
        am.avg_answer_score,
        am.max_answer_score,
        dl.original_post_id,
        dl.first_dup_link_at,
        extract(epoch from (al.accepted_at - al.asked_at)) / 3600.0 as hours_to_accept,
        cast(
        (
          coalesce(qe.score,0)*2
          + coalesce(am.avg_answer_score,0)
          + case when qe.acceptedanswerid is not null then 5 else 0 end
          - case when qe.is_closed = 1 then 3 else 0 end
          - case when dl.original_post_id is not null then 4 else 0 end
          + least(coalesce(qe.viewcount,0)/1000.0, 10)
        ) as numeric(12,2)
        ) as quality_score
    from question_enrichment qe
    left join answer_metrics am on am.question_id = qe.post_id
    left join duplicates_cte dl on dl.dup_post_id = qe.post_id
    left join accept_latency al on al.question_id = qe.post_id
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badges_total,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
user_vote_behavior as (
    select
        u.id as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_flow
    from users u
    left join votes v on v.userid = u.id
    group by u.id
),
user_title_norm as (
    select
        qq.post_id,
        qq.user_id,
        qq.quality_score,
        regexp_replace(lower(coalesce(qq.title,'')), '^\W+|\s+', ' ', 'g') as title_norm
    from question_quality qq
),
title_rank as (
    select
        ut.user_id,
        ut.post_id,
        ut.title_norm,
        ut.quality_score,
        row_number() over (partition by ut.user_id order by ut.quality_score desc nulls last, ut.post_id) as rn_best,
        row_number() over (partition by ut.user_id order by ut.quality_score asc nulls last, ut.post_id) as rn_worst
    from user_title_norm ut
),
tag_expansion as (
    select
        qq.post_id,
        unnest(string_to_array(substring(qq.tags, 2, greatest(length(qq.tags)-2,0)), '><')) as tagname
    from question_quality qq
    where qq.tags is not null and qq.tags <> ''
),
user_tag_profile as (
    select
        p.owneruserid as user_id,
        lower(t.tagname) as tagname,
        count(*) as posts_in_tag,
        avg(cast(p.score as numeric)) as avg_score_in_tag,
        percentile_cont(0.5) within group (order by p.score) as median_score_in_tag
    from posts p
    join tag_expansion t on t.post_id = p.id
    where p.posttypeid = 1
    group by p.owneruserid, lower(t.tagname)
),
tag_rollup as (
    select
        utp.user_id,
        count(*) as distinct_tags_used,
        max(utp.avg_score_in_tag) as best_tag_avg,
        min(utp.avg_score_in_tag) as worst_tag_avg
    from user_tag_profile utp
    group by utp.user_id
),
user_summary as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        ua.total_posts,
        ua.total_comments,
        ua.net_votes,
        ua.upvotes_rcvd,
        ua.downvotes_rcvd,
        ua.last_activity,
        coalesce(ub.badges_total,0) as badges_total,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(uv.upvotes_cast,0) as upvotes_cast,
        coalesce(uv.downvotes_cast,0) as downvotes_cast,
        coalesce(uv.favorites_cast,0) as favorites_cast,
        coalesce(uv.bounty_flow,0) as bounty_flow,
        coalesce(tr.distinct_tags_used,0) as distinct_tags_used,
        tr.best_tag_avg,
        tr.worst_tag_avg,
        ru.websiteurl_norm
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join user_vote_behavior uv on uv.user_id = ru.user_id
    left join tag_rollup tr on tr.user_id = ru.user_id
),
best_worst_titles as (
    select
        tr.user_id,
        max(case when tr.rn_best = 1 then tr.title_norm end) as best_title_norm,
        max(case when tr.rn_best = 1 then tr.quality_score end) as best_title_score,
        max(case when tr.rn_worst = 1 then tr.title_norm end) as worst_title_norm,
        max(case when tr.rn_worst = 1 then tr.quality_score end) as worst_title_score
    from title_rank tr
    group by tr.user_id
),
closed_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_closed_at,
        min(
            case
                when ph.posthistorytypeid = 10
                     and ph.comment ~ '^[0-9]+$'
                then cast(ph.comment as integer)
                else null
            end
        ) as close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10)
    group by ph.postid
),
reason_labels as (
    select
        crt.id as reason_id,
        crt.name as reason_name
    from closereasontypes crt
),
user_closed_mix as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.closeddate is not null) as closed_count,
        count(*) filter (where cr.close_reason_id = 101) as duplicate_count,
        count(*) filter (where cr.close_reason_id = 102) as offtopic_count
    from posts p
    left join closed_reasons cr on cr.postid = p.id
    where p.posttypeid = 1
    group by p.owneruserid
),
final_scores as (
    select
        us.*,
        coalesce(ucm.closed_count,0) as closed_count,
        coalesce(ucm.duplicate_count,0) as duplicate_count,
        coalesce(ucm.offtopic_count,0) as offtopic_count,
        coalesce(bwt.best_title_norm,'') as best_title_norm,
        coalesce(bwt.worst_title_norm,'') as worst_title_norm,
        coalesce(bwt.best_title_score,0) as best_title_score,
        coalesce(bwt.worst_title_score,0) as worst_title_score,
        cast(
        (
          least(greatest(us.reputation, 1), 100000) / 500.0
          + coalesce(us.badges_total,0) * 0.2
          + coalesce(us.upvotes_rcvd,0) * 0.1
          - coalesce(us.downvotes_rcvd,0) * 0.2
          + coalesce(us.total_posts,0) * 0.05
          + coalesce(us.distinct_tags_used,0) * 0.3
          - coalesce(ucm.closed_count,0) * 0.5
          - coalesce(ucm.duplicate_count,0) * 0.25
        ) as numeric(12,2)
        ) as perf_score
    from user_summary us
    left join user_closed_mix ucm on ucm.user_id = us.user_id
    left join best_worst_titles bwt on bwt.user_id = us.user_id
),
ranked as (
    select
        f.*,
        ntile(10) over (order by f.perf_score desc nulls last) as decile,
        rank() over (order by f.perf_score desc nulls last) as global_rank,
        row_number() over (partition by f.cohort_month order by f.perf_score desc nulls last) as cohort_rank
    from final_scores f
)
select
    r.global_rank,
    r.cohort_month,
    r.cohort_rank,
    r.user_id,
    r.displayname,
    r.reputation,
    r.perf_score,
    r.decile,
    r.total_posts,
    r.total_comments,
    r.upvotes_rcvd,
    r.downvotes_rcvd,
    r.badges_total,
    r.gold_badges,
    r.silver_badges,
    r.bronze_badges,
    r.upvotes_cast,
    r.downvotes_cast,
    r.favorites_cast,
    r.bounty_flow,
    r.distinct_tags_used,
    r.best_tag_avg,
    r.worst_tag_avg,
    r.closed_count,
    r.duplicate_count,
    r.offtopic_count,
    case when length(r.best_title_norm) > 120 then substr(r.best_title_norm,1,117) || '...' else r.best_title_norm end as best_title_norm_trunc,
    case when length(r.worst_title_norm) > 120 then substr(r.worst_title_norm,1,117) || '...' else r.worst_title_norm end as worst_title_norm_trunc,
    r.best_title_score,
    r.worst_title_score,
    r.last_activity
from ranked r
where coalesce(r.perf_score,0) > 0
  and (r.websiteurl_norm is null or r.websiteurl_norm not like '%spam%')
order by r.global_rank
limit 200;