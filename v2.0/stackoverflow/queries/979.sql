-- {"query": "979.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2872}
with
recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as country_guess
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
q_posts as (
    select p.*
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select p.*
    from posts p
    where p.posttypeid = 2
),
activity as (
    select
        p.id as post_id,
        p.owneruserid as owner_user_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.tags,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        count(*) filter (where v.votetypeid = 5) as favorites,
        count(distinct c.id) as comment_count
    from posts p
    left join votes v on v.postid = p.id
    left join comments c on c.postid = p.id
    group by p.id, p.owneruserid, p.posttypeid, p.creationdate, p.score, p.viewcount, p.tags
),
dup_links as (
    select pl.postid as dup_post_id, pl.relatedpostid as canonical_id
    from postlinks pl
    where pl.linktypeid = 3
),
question_enriched as (
    select
        q.id,
        q.owneruserid,
        q.creationdate,
        q.score,
        q.viewcount,
        a.activity_count,
        a.first_answer_date,
        a.accepted_latency_sec,
        a.answerer_diversity,
        a.top_answer_score,
        a.latest_activity,
        a.answer_count,
        a.total_comment_count,
        a.total_net_votes,
        regexp_replace(coalesce(q.title, ''), '\s+', ' ', 'g') as normalized_title,
        string_agg_tag.tags_array,
        coalesce(dl.canonical_id, q.id) as canonical_id
    from q_posts q
    left join dup_links dl on dl.dup_post_id = q.id
    left join lateral (
        select
            count(*) as answer_count,
            count(*) filter (where a.owneruserid is not null) as answer_count_with_owner,
            count(distinct a.owneruserid) filter (where a.owneruserid is not null) as answerer_diversity,
            min(a.creationdate) as first_answer_date,
            max(a.lastactivitydate) as latest_activity,
            max(a.score) as top_answer_score,
            sum(coalesce(aa.comment_count,0)) as total_comment_count,
            sum(coalesce(aa.net_votes,0)) as total_net_votes,
            CAST(extract(epoch from (min(a.creationdate) - q.creationdate)) AS bigint) as first_answer_latency_sec,
            case when q.acceptedanswerid is not null
                 then CAST(extract(epoch from ((select a2.creationdate from a_posts a2 where a2.id = q.acceptedanswerid) - q.creationdate)) AS bigint)
                 else null end as accepted_latency_sec,
            count(*) as activity_count
        from a_posts a
        left join activity aa on aa.post_id = a.id
        where a.parentid = q.id
    ) a on true
    left join lateral (
        select string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') as tags_array
    ) string_agg_tag on true
),
user_stats as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.upvotes,
        u.downvotes,
        u.views,
        coalesce(b.badge_gold,0) as badge_gold,
        coalesce(b.badge_silver,0) as badge_silver,
        coalesce(b.badge_bronze,0) as badge_bronze,
        case
            when u.reputation >= 20000 then 'Legend'
            when u.reputation >= 10000 then 'Expert'
            when u.reputation >= 3000 then 'Advanced'
            when u.reputation >= 500 then 'Intermediate'
            else 'Beginner'
        end as rep_tier
    from users u
    left join (
        select userid,
               count(*) filter (where class = 1) as badge_gold,
               count(*) filter (where class = 2) as badge_silver,
               count(*) filter (where class = 3) as badge_bronze
        from badges
        group by userid
    ) b on b.userid = u.id
),
ph_events as (
    select
        ph.postid,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as last_moderation_event,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        count(*) filter (where ph.posthistorytypeid = 12) as delete_events,
        count(*) filter (where ph.posthistorytypeid = 13) as undelete_events
    from posthistory ph
    group by ph.postid
),
tag_popularity as (
    select
        t.tagname,
        t.count as post_count,
        row_number() over (order by t.count desc nulls last) as tag_rank_by_count
    from tags t
),
question_quality as (
    select
        qe.id as question_id,
        qe.owneruserid as owner_user_id,
        qe.creationdate,
        qe.score,
        qe.viewcount,
        qe.answer_count,
        qe.total_net_votes,
        qe.total_comment_count,
        qe.answerer_diversity,
        qe.top_answer_score,
        qe.accepted_latency_sec,
        qe.first_answer_date,
        qe.latest_activity,
        qe.canonical_id,
        qe.tags_array,
        case
            when qe.viewcount is null or qe.viewcount = 0 then null
            else round((coalesce(qe.total_net_votes,0) / nullif(qe.viewcount,0)) * 1000, 4)
        end as votes_per_k_view,
        case
            when qe.answer_count is null or qe.answer_count = 0 then null
            else round((coalesce(qe.total_net_votes,0) / nullif(qe.answer_count,0)), 4)
        end as votes_per_answer,
        round(
            coalesce(qe.score,0) * 0.25
          + coalesce(qe.total_net_votes,0) * 0.35
          + coalesce(qe.answerer_diversity,0) * 0.2
          + coalesce( (case when qe.accepted_latency_sec is null then 0 else greatest(0, 86400 - qe.accepted_latency_sec) end) / 86400.0, 0) * 0.2
        , 4) as quality_score
    from question_enriched qe
),
tag_expansion as (
    select
        qq.question_id,
        lower(tn) as tag,
        qq.quality_score,
        tn as original_tn
    from question_quality qq
    left join lateral (
        select unnest(coalesce(qq.tags_array, array[]::text[])) as tn
    ) u on true
),
tag_rollup as (
    select
        te.tag,
        count(*) as questions_with_tag,
        avg(qq.quality_score) as avg_quality_for_tag,
        percentile_cont(0.9) within group (order by qq.quality_score) as p90_quality_for_tag
    from tag_expansion te
    join question_quality qq on qq.question_id = te.question_id
    group by te.tag
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(p.score) as total_post_score,
        sum(coalesce(a.net_votes,0)) as total_net_votes,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    left join activity a on a.post_id = p.id
    group by p.owneruserid
),
recent_quality as (
    select
        qq.question_id,
        qq.owner_user_id,
        qq.quality_score,
        qq.votes_per_k_view,
        qq.creationdate,
        row_number() over (partition by qq.owner_user_id order by qq.quality_score desc nulls last, qq.creationdate desc) as rn_best,
        row_number() over (partition by qq.owner_user_id order by qq.creationdate desc) as rn_new
    from question_quality qq
    where qq.creationdate >= (select max(creationdate) - interval '365 days' from posts)
),
user_dim as (
    select
        us.user_id,
        us.displayname,
        us.rep_tier,
        us.reputation,
        coalesce(ra.q_recent_best, 0) as q_recent_best,
        coalesce(ra.q_recent_new, 0) as q_recent_new
    from user_stats us
    left join (
        select
            owner_user_id as user_id,
            count(*) filter (where rn_best <= 3) as q_recent_best,
            count(*) filter (where rn_new <= 5) as q_recent_new
        from recent_quality
        group by owner_user_id
    ) ra on ra.user_id = us.user_id
),
answer_response as (
    select
        q.id as question_id,
        q.owneruserid as owner_user_id,
        min(a.creationdate) as first_answer_time,
        CAST(extract(epoch from (min(a.creationdate) - q.creationdate)) AS bigint) as first_answer_latency_sec
    from q_posts q
    left join a_posts a on a.parentid = q.id
    group by q.id, q.owneruserid, q.creationdate
),
null_diagnostics as (
    select
        qq.question_id,
        case when qq.votes_per_k_view is null then 1 else 0 end as null_vpkv,
        case when qq.votes_per_answer is null then 1 else 0 end as null_vpa,
        case when qq.accepted_latency_sec is null then 1 else 0 end as null_accept_latency
    from question_quality qq
),
final_rank as (
    select
        qq.question_id,
        qq.owner_user_id,
        qq.quality_score,
        dense_rank() over (order by qq.quality_score desc nulls last) as quality_dense_rank,
        row_number() over (order by qq.quality_score desc nulls last, qq.votes_per_k_view desc nulls last) as quality_rownum
    from question_quality qq
)
select
    fr.quality_rownum as global_rank,
    qq.question_id,
    coalesce(ud.displayname, 'user#' || CAST(ud.user_id AS text)) as owner_display,
    ud.rep_tier,
    ud.reputation,
    ua.q_count,
    ua.a_count,
    ua.total_post_score,
    ua.total_net_votes,
    qq.quality_score,
    qq.votes_per_k_view,
    qq.votes_per_answer,
    qq.answerer_diversity,
    qq.top_answer_score,
    qq.accepted_latency_sec,
    ar.first_answer_latency_sec,
    ph.close_events,
    ph.reopen_events,
    ph.delete_events,
    ph.undelete_events,
    coalesce(tp.tagname, (select tr.tag from tag_rollup tr order by tr.avg_quality_for_tag desc nulls last limit 1)) as top_tag_by_count_or_quality,
    tr.avg_quality_for_tag as tag_avg_quality,
    tr.p90_quality_for_tag as tag_p90_quality,
    nd.null_vpkv + nd.null_vpa + nd.null_accept_latency as null_metric_count,
    qq.creationdate,
    greatest(coalesce(qq.latest_activity, qq.creationdate), coalesce(ua.last_post_activity, qq.creationdate)) as latest_related_activity
from final_rank fr
join question_quality qq on qq.question_id = fr.question_id
left join user_activity ua on ua.user_id = qq.owner_user_id
left join user_dim ud on ud.user_id = qq.owner_user_id
left join answer_response ar on ar.question_id = qq.question_id
left join ph_events ph on ph.postid = qq.question_id
left join lateral (
    select t2.tagname
    from tags t2
    where exists (
        select 1
        from tag_expansion te
        where te.question_id = qq.question_id
          and te.tag = t2.tagname
    )
    order by t2.count desc nulls last
    limit 1
) tp on true
left join lateral (
    select tr2.tag, tr2.questions_with_tag, tr2.avg_quality_for_tag, tr2.p90_quality_for_tag
    from tag_rollup tr2
    where tr2.tag = lower(coalesce(tp.tagname, ''))
) tr on true
left join null_diagnostics nd on nd.question_id = qq.question_id
where (ua.q_count is not null or ua.a_count is not null)
  and (qq.quality_score is not null or qq.votes_per_k_view is not null)
order by fr.quality_rownum
limit 500;