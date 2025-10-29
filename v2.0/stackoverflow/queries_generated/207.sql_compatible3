with
params as (
    select
        interval '365 days' as recent_window,
        10 as top_k_tags,
        50 as min_views,
        5 as min_answers
),
recent_questions as (
    select p.*
    from posts p
    cross join params
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - params.recent_window
),
tag_tokens as (
    select
        q.id as post_id,
        lower(trim(t)) as tag
    from recent_questions q,
    lateral (
        select unnest_tokens
        from (
            -- normalize tags string like '<tag1><tag2>' into array of tag texts
            select
                case
                    when q.tags is null then array[]::varchar[]  -- replaced below with standard literal in outer dialects if needed
                    when length(q.tags) <= 2 then array[]::varchar[]
                    else string_to_array(substring(q.tags from 2 for length(q.tags)-2), '><')
                end as toks
        ) s,
        unnest(s.toks) as unnest_tokens
    ) u(t)
),
/* Replace the explicit :: casts above with standard SQL arrays for wider compatibility.
   Some SQL engines do not accept array[]::varchar[]; for those engines you may need to
   replace array[]::varchar[] with CAST(ARRAY[] AS VARCHAR[]) or an equivalent. */
tag_rank as (
    select
        tag,
        count(*) as tag_use_cnt,
        row_number() over (order by count(*) desc, tag asc) as rn
    from tag_tokens
    group by tag
),
top_tags as (
    select tag
    from tag_rank tr
    cross join params
    where tr.rn <= params.top_k_tags
),
question_metrics as (
    select
        q.id,
        q.title,
        q.owneruserid,
        q.creationdate,
        q.score,
        q.viewcount,
        q.answercount,
        q.acceptedanswerid,
        coalesce((select count(*) from votes v where v.postid = q.id and v.votetypeid = 2), 0) as upvotes,
        coalesce((select count(*) from votes v where v.postid = q.id and v.votetypeid = 3), 0) as downvotes,
        coalesce((select count(*) from votes v where v.postid = q.id and v.votetypeid = 5), 0) as favorites,
        coalesce((select count(*) from posthistory ph where ph.postid = q.id and ph.posthistorytypeid in (4,5,6,7,8,9,24)), 0) as edit_events,
        max(case when ph2.posthistorytypeid = 10 then ph2.creationdate end) as closed_at,
        max(case when ph2.posthistorytypeid = 11 then ph2.creationdate end) as reopened_at
    from recent_questions q
    left join posthistory ph2
      on ph2.postid = q.id
      and ph2.posthistorytypeid in (10,11)
    group by q.id, q.title, q.owneruserid, q.creationdate, q.score, q.viewcount, q.answercount, q.acceptedanswerid
),
answer_metrics as (
    select
        a.parentid as question_id,
        count(*) as answers,
        sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
        max(a.creationdate) as last_answer_created,
        max(a.lastactivitydate) as last_answer_activity,
        max(a.score) as best_answer_score,
        avg(case when u.reputation >= 10000 then 1.0 else 0.0 end) as pct_highrep_answers
    from posts a
    left join users u on u.id = a.owneruserid
    where a.posttypeid = 2
      and a.parentid in (select id from recent_questions)
    group by a.parentid
),
question_tag_bridge as (
    select
        t.post_id as question_id,
        t.tag
    from tag_tokens t
    join top_tags tt on tt.tag = t.tag
),
user_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        coalesce(sum(case when p.posttypeid = 1 then 1 else 0 end),0) as q_count,
        coalesce(sum(case when p.posttypeid = 2 then 1 else 0 end),0) as a_count,
        coalesce(sum(coalesce(p.viewcount,0)),0) as total_views,
        max(p.lastactivitydate) as last_post_activity,
        percentile_cont(0.5) within group (order by coalesce(p.score,0)) as median_post_score
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id, u.displayname, u.reputation, u.creationdate
),
question_quality as (
    select
        qm.id as question_id,
        (
            0.30 * ln(1 + greatest(qm.viewcount,0)) +
            0.35 * coalesce(qm.upvotes - qm.downvotes, 0) +
            0.25 * coalesce(am.best_answer_score, 0) +
            0.10 * case when qm.acceptedanswerid is not null then 5 else 0 end
        ) as raw_quality,
        case
            when qm.closed_at is not null and (qm.reopened_at is null or qm.reopened_at < qm.closed_at) then -2.0
            else 0.0
        end as closure_penalty,
        (least(qm.edit_events, 20) * 0.05) as edit_bonus,
        exp(-extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - qm.creationdate)) / (60*60*24*90.0)) as recency_decay
    from question_metrics qm
    left join answer_metrics am on am.question_id = qm.id
),
dup_clusters as (
    select
        least(pl.postid, pl.relatedpostid) as cluster_min_id,
        greatest(pl.postid, pl.relatedpostid) as cluster_max_id
    from postlinks pl
    where pl.linktypeid = 3
),
dup_groups as (
    select cluster_min_id as representative, cluster_min_id as member from dup_clusters
    union
    select cluster_min_id as representative, cluster_max_id as member from dup_clusters
),
accepted_answerers as (
    select
        q.id as question_id,
        a.owneruserid as user_id
    from question_metrics q
    join posts a on a.id = q.acceptedanswerid
),
owner_reputation_band as (
    select
        qm.id as question_id,
        case
            when u.reputation >= 20000 then '20k+'
            when u.reputation >= 10000 then '10k-19k'
            when u.reputation >= 3000 then '3k-9k'
            when u.reputation >= 1000 then '1k-2k'
            when u.reputation is null then 'deleted/unknown'
            else '<1k'
        end as owner_rep_band
    from question_metrics qm
    left join users u on u.id = qm.owneruserid
),
final_scored as (
    select
        qm.id as question_id,
        qm.title,
        qm.creationdate,
        qm.viewcount,
        qm.answercount,
        qm.score as q_score,
        coalesce(am.answers,0) as answers,
        coalesce(am.positive_answers,0) as pos_answers,
        am.last_answer_created,
        am.last_answer_activity,
        am.best_answer_score,
        am.pct_highrep_answers,
        qm.upvotes,
        qm.downvotes,
        qm.favorites,
        qq.raw_quality + qq.closure_penalty + qq.edit_bonus as base_quality,
        (qq.raw_quality + qq.closure_penalty + qq.edit_bonus) * qq.recency_decay as decayed_quality,
        orp.owner_rep_band,
        aa.user_id as accepted_answerer_id
    from question_metrics qm
    left join answer_metrics am on am.question_id = qm.id
    left join question_quality qq on qq.question_id = qm.id
    left join owner_reputation_band orp on orp.question_id = qm.id
    left join accepted_answerers aa on aa.question_id = qm.id
),
filtered as (
    select f.*
    from final_scored f
    cross join params
    where coalesce(f.viewcount,0) >= params.min_views
      and coalesce(f.answers,0) >= params.min_answers
      and (f.accepted_answerer_id is not null or f.best_answer_score >= 1 or f.pct_highrep_answers >= 0.25)
),
tagged_final as (
    select
        f.*,
        qt.tag
    from filtered f
    left join question_tag_bridge qt
      on qt.question_id = f.question_id
),
ranked as (
    select
        t.*,
        dense_rank() over (order by t.decayed_quality desc, t.q_score desc, t.question_id asc) as global_rank,
        row_number() over (partition by coalesce(t.tag,'(untagged-top)') order by t.decayed_quality desc, t.q_score desc, t.question_id asc) as rank_within_tag
    from tagged_final t
),
owner_rollup as (
    select
        qm.owneruserid as owner_id,
        count(*) as recent_qs,
        avg(case when f.question_id is not null then f.decayed_quality end) as avg_decayed_quality_in_filtered
    from question_metrics qm
    left join filtered f on f.question_id = qm.id
    group by qm.owneruserid
)
select
    r.question_id,
    r.title,
    r.tag,
    r.global_rank,
    r.rank_within_tag,
    r.decayed_quality,
    r.base_quality,
    r.viewcount,
    r.answers,
    r.pos_answers,
    r.best_answer_score,
    r.pct_highrep_answers,
    r.upvotes,
    r.downvotes,
    r.favorites,
    r.owner_rep_band,
    coalesce(u.displayname, '(unknown)') as owner_displayname,
    u.reputation as owner_reputation,
    oru.recent_qs as owner_recent_questions,
    coalesce(oru.avg_decayed_quality_in_filtered, 0) as owner_avg_filtered_quality,
    case when dg.representative is not null then dg.representative else r.question_id end as duplicate_cluster_rep,
    r.accepted_answerer_id
from ranked r
left join users u on u.id = (
    select owneruserid from question_metrics where id = r.question_id
)
left join owner_rollup oru on oru.owner_id = u.id
left join dup_groups dg on dg.member = r.question_id
where r.global_rank <= 500
order by r.global_rank, r.rank_within_tag, r.question_id;