-- {"query": "532.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 4244} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id) as rn_recent
    from users u
),
active_questions as (
    select
        p.id as question_id,
        p.title,
        p.creationdate,
        p.owneruserid,
        p.viewcount,
        p.score,
        p.answercount,
        p.tags,
        case when p.closeddate is not null then 1 else 0 end as is_closed,
        extract(epoch from (now() - coalesce(p.lastactivitydate, p.creationdate))) / 3600.0 as hours_since_activity
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= now() - interval '3 years'
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid,
        a.score,
        a.creationdate,
        a.lastactivitydate
    from posts a
    where a.posttypeid = 2
),
q_metrics as (
    select
        q.question_id,
        q.title,
        q.owneruserid,
        q.viewcount,
        q.score as q_score,
        q.answercount,
        q.is_closed,
        q.hours_since_activity,
        count(ans.answer_id) as total_answers,
        max(ans.score) as max_answer_score,
        min(ans.creationdate) as first_answer_time,
        avg(ans.score) filter (where ans.score is not null) as avg_answer_score
    from active_questions q
    left join answers ans on ans.question_id = q.question_id
    group by q.question_id, q.title, q.owneruserid, q.viewcount, q.score, q.answercount, q.is_closed, q.hours_since_activity
),
dup_links as (
    select
        pl.postid as question_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links
    from postlinks pl
    join posts p on p.id = pl.postid and p.posttypeid = 1
    group by pl.postid
),
tag_counts as (
    select
        p.id as question_id,
        t.tagname,
        t.count as global_tag_count
    from posts p
    cross join lateral unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag(tagname)
    left join tags t on t.tagname = tag.tagname
    where p.posttypeid = 1
),
tag_rollup as (
    select
        question_id,
        array_agg(tagname order by coalesce(global_tag_count, 0) desc nulls last) as tag_list,
        coalesce(sum(global_tag_count), 0) as sum_global_tag_popularity,
        count(*) as tag_count
    from tag_counts
    group by question_id
),
user_activity as (
    select
        u.id as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_authored,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_authored,
        sum(coalesce(p.score, 0)) as total_post_score,
        max(p.lastactivitydate) as last_post_activity,
        count(distinct date_trunc('day', p.creationdate)) as active_days_posting,
        sum(coalesce(c.score, 0)) as comment_score_sum
    from users u
    left join posts p on p.owneruserid = u.id
    left join comments c on c.userid = u.id
    group by u.id
),
edits_and_closures as (
    select
        ph.postid as question_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as last_edit_date,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_vote_time,
        count(*) filter (where ph.posthistorytypeid = 10) as close_vote_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        sum(
            case
                when ph.posthistorytypeid = 10
                then
                    case
                        when ph.comment ~ '^[0-9]+$' then 1
                        else 0
                    end
                else 0
            end
        ) as close_reasons_counted
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    group by ph.postid
),
votes_agg as (
    select
        v.postid as post_id,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        count(*) filter (where v.votetypeid = 9) as bounties_awarded,
        sum(v.bountyamount) filter (where v.votetypeid in (8,9)) as bounty_amount_total,
        count(distinct v.userid) filter (where v.votetypeid in (2,3)) as distinct_voters
    from votes v
    join posts p on p.id = v.postid and p.posttypeid in (1,2)
    group by v.postid
),
comment_stats as (
    select
        c.postid as post_id,
        count(*) as comment_count,
        max(c.score) as max_comment_score,
        avg(nullif(c.score, 0)) as avg_nonzero_comment_score,
        min(c.creationdate) as first_comment_time,
        max(c.creationdate) as last_comment_time
    from comments c
    group by c.postid
),
owner_enriched as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        ua.questions_authored,
        ua.answers_authored,
        ua.total_post_score,
        ua.last_post_activity,
        ua.active_days_posting,
        ua.comment_score_sum,
        dense_rank() over (order by u.reputation desc, u.id) as rep_rank
    from users u
    left join user_activity ua on ua.user_id = u.id
),
question_enriched as (
    select
        q.question_id,
        q.title,
        oe.user_id as owner_user_id,
        oe.displayname as owner_displayname,
        oe.reputation as owner_reputation,
        oe.rep_rank as owner_rep_rank,
        q.viewcount,
        q.q_score,
        q.answercount,
        q.is_closed,
        q.hours_since_activity,
        qm.total_answers,
        qm.max_answer_score,
        qm.first_answer_time,
        qm.avg_answer_score,
        coalesce(dl.duplicate_links, 0) as duplicate_links,
        coalesce(dl.linked_links, 0) as linked_links,
        coalesce(tr.tag_list, array[]::varchar[]) as tag_list,
        coalesce(tr.sum_global_tag_popularity, 0) as sum_global_tag_popularity,
        coalesce(tr.tag_count, 0) as tag_count,
        coalesce(ea.edit_events, 0) as edit_events,
        ea.last_edit_date,
        ea.first_close_vote_time,
        coalesce(ea.close_vote_events, 0) as close_vote_events,
        coalesce(ea.reopen_events, 0) as reopen_events,
        coalesce(va.upvotes, 0) as q_upvotes,
        coalesce(va.downvotes, 0) as q_downvotes,
        coalesce(va.bounties_started, 0) as bounties_started_on_q,
        coalesce(va.bounties_awarded, 0) as bounties_awarded_on_q,
        coalesce(va.bounty_amount_total, 0) as bounty_amount_on_q,
        coalesce(va.distinct_voters, 0) as distinct_voters_on_q,
        coalesce(cs.comment_count, 0) as q_comment_count,
        coalesce(cs.max_comment_score, 0) as q_max_comment_score,
        cs.avg_nonzero_comment_score as q_avg_nonzero_comment_score,
        cs.first_comment_time as q_first_comment_time,
        cs.last_comment_time as q_last_comment_time
    from q_metrics qm
    join active_questions q on q.question_id = qm.question_id
    left join owner_enriched oe on oe.user_id = q.owneruserid
    left join dup_links dl on dl.question_id = q.question_id
    left join tag_rollup tr on tr.question_id = q.question_id
    left join edits_and_closures ea on ea.question_id = q.question_id
    left join votes_agg va on va.post_id = q.question_id
    left join comment_stats cs on cs.post_id = q.question_id
),
answer_rollup as (
    select
        a.question_id,
        count(*) as answers_count,
        avg(a.score) as answers_avg_score,
        max(a.score) as answers_max_score,
        sum(case when a.owneruserid is null then 1 else 0 end) as answers_from_deleted_users,
        count(distinct a.owneruserid) filter (where a.owneruserid is not null) as distinct_answerers,
        count(*) filter (where a.lastactivitydate >= now() - interval '30 days') as answers_recent_30d
    from answers a
    group by a.question_id
),
badge_summary as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges
    from badges b
    group by b.userid
),
owner_badges as (
    select
        oe.user_id,
        coalesce(bs.gold_badges, 0) as gold_badges,
        coalesce(bs.silver_badges, 0) as silver_badges,
        coalesce(bs.bronze_badges, 0) as bronze_badges,
        coalesce(bs.tag_badges, 0) as tag_badges
    from owner_enriched oe
    left join badge_summary bs on bs.userid = oe.user_id
),
ranked_questions as (
    select
        qe.*,
        ar.answers_count,
        ar.answers_avg_score,
        ar.answers_max_score,
        ar.answers_from_deleted_users,
        ar.distinct_answerers,
        ar.answers_recent_30d,
        ob.gold_badges,
        ob.silver_badges,
        ob.bronze_badges,
        ob.tag_badges,
        dense_rank() over (
            order by
                (qe.q_upvotes - qe.q_downvotes) desc,
                qe.viewcount desc,
                qe.answercount desc,
                qe.q_score desc,
                qe.duplicate_links asc nulls last,
                qe.hours_since_activity asc nulls last
        ) as hotness_rank,
        percent_rank() over (
            order by
                coalesce(qe.sum_global_tag_popularity, 0) desc
        ) as tag_popularity_percentile,
        row_number() over (
            partition by (case when qe.is_closed = 1 then 'closed' else 'open' end)
            order by
                qe.viewcount desc nulls last,
                qe.q_score desc nulls last
        ) as rownum_by_closed_state
    from question_enriched qe
    left join answer_rollup ar on ar.question_id = qe.question_id
    left join owner_badges ob on ob.user_id = qe.owner_user_id
),
question_quality as (
    select
        rq.*,
        (
            0.35 * ln(1 + greatest(rq.viewcount, 0)) +
            0.25 * coalesce(rq.q_upvotes - rq.q_downvotes, 0) +
            0.20 * coalesce(rq.answers_count, 0) +
            0.10 * coalesce(rq.answers_avg_score, 0) +
            0.05 * coalesce(rq.q_comment_count, 0) +
            0.05 * case when rq.is_closed = 1 then -5 else 0 end
        ) as quality_score,
        case
            when rq.tag_count = 0 then 'untagged'
            when rq.tag_count between 1 and 2 then 'narrow'
            when rq.tag_count between 3 and 5 then 'balanced'
            else 'broad'
        end as tag_breadth_bucket,
        case
            when rq.hours_since_activity < 24 then 'active <24h'
            when rq.hours_since_activity < 168 then 'active <7d'
            when rq.hours_since_activity < 720 then 'active <30d'
            else 'stale'
        end as activity_bucket
    from ranked_questions rq
),
user_outliers as (
    select
        oe.user_id,
        oe.displayname,
        oe.reputation,
        oe.rep_rank,
        ua.questions_authored,
        ua.answers_authored,
        ua.total_post_score,
        ua.active_days_posting,
        case
            when ua.questions_authored > 0 then ua.total_post_score::numeric / ua.questions_authored
            else null
        end as avg_score_per_question,
        case
            when ua.answers_authored > 0 then ua.total_post_score::numeric / ua.answers_authored
            else null
        end as avg_score_per_answer
    from owner_enriched oe
    left join user_activity ua on ua.user_id = oe.user_id
    where oe.rep_rank <= 1000
),
final_union as (
    select
        'QUESTION'::varchar as row_type,
        qq.question_id::varchar as entity_id,
        qq.title,
        qq.owner_displayname,
        qq.owner_reputation,
        qq.owner_rep_rank,
        qq.viewcount,
        qq.q_score,
        qq.answercount,
        qq.total_answers,
        qq.max_answer_score,
        qq.first_answer_time,
        qq.avg_answer_score,
        qq.duplicate_links,
        qq.linked_links,
        qq.tag_list,
        qq.sum_global_tag_popularity,
        qq.tag_count,
        qq.edit_events,
        qq.last_edit_date,
        qq.first_close_vote_time,
        qq.close_vote_events,
        qq.reopen_events,
        qq.q_upvotes,
        qq.q_downvotes,
        qq.bounties_started_on_q,
        qq.bounties_awarded_on_q,
        qq.bounty_amount_on_q,
        qq.distinct_voters_on_q,
        qq.q_comment_count,
        qq.q_max_comment_score,
        qq.q_avg_nonzero_comment_score,
        qq.q_first_comment_time,
        qq.q_last_comment_time,
        qq.answers_count,
        qq.answers_avg_score,
        qq.answers_max_score,
        qq.answers_from_deleted_users,
        qq.distinct_answerers,
        qq.answers_recent_30d,
        qq.gold_badges,
        qq.silver_badges,
        qq.bronze_badges,
        qq.tag_badges,
        qq.hotness_rank,
        qq.tag_popularity_percentile,
        qq.rownum_by_closed_state,
        qq.quality_score,
        qq.tag_breadth_bucket,
        qq.activity_bucket
    from question_quality qq
    where qq.quality_score is not null
    union all
    select
        'USER'::varchar as row_type,
        uo.user_id::varchar as entity_id,
        null as title,
        uo.displayname as owner_displayname,
        uo.reputation as owner_reputation,
        uo.rep_rank as owner_rep_rank,
        null::int as viewcount,
        null::int as q_score,
        ua.questions_authored as answercount,
        null::bigint as total_answers,
        null::int as max_answer_score,
        null::timestamp as first_answer_time,
        null::numeric as avg_answer_score,
        null::bigint as duplicate_links,
        null::bigint as linked_links,
        null::varchar[] as tag_list,
        null::bigint as sum_global_tag_popularity,
        null::int as tag_count,
        null::bigint as edit_events,
        null::timestamp as last_edit_date,
        null::timestamp as first_close_vote_time,
        null::bigint as close_vote_events,
        null::bigint as reopen_events,
        null::bigint as q_upvotes,
        null::bigint as q_downvotes,
        null::bigint as bounties_started_on_q,
        null::bigint as bounties_awarded_on_q,
        null::bigint as bounty_amount_on_q,
        null::bigint as distinct_voters_on_q,
        null::bigint as q_comment_count,
        null::int as q_max_comment_score,
        null::numeric as q_avg_nonzero_comment_score,
        null::timestamp as q_first_comment_time,
        null::timestamp as q_last_comment_time,
        ua.answers_authored as answers_count,
        null::numeric as answers_avg_score,
        null::int as answers_max_score,
        null::bigint as answers_from_deleted_users,
        null::bigint as distinct_answerers,
        null::bigint as answers_recent_30d,
        null::bigint as gold_badges,
        null::bigint as silver_badges,
        null::bigint as bronze_badges,
        null::bigint as tag_badges,
        null::bigint as hotness_rank,
        null::double precision as tag_popularity_percentile,
        null::bigint as rownum_by_closed_state,
        uo.avg_score_per_question as quality_score,
        case
            when coalesce(uo.avg_score_per_question, 0) >= 10 then 'elite'
            when coalesce(uo.avg_score_per_question, 0) >= 2 then 'solid'
            when coalesce(uo.avg_score_per_question, 0) > 0 then 'newcomer'
            else 'inactive'
        end as tag_breadth_bucket,
        case
            when coalesce(uo.avg_score_per_answer, 0) >= 5 then 'helpful'
            when coalesce(uo.avg_score_per_answer, 0) > 0 then 'learning'
            else 'quiet'
        end as activity_bucket
    from user_outliers uo
    left join user_activity ua on ua.user_id = uo.user_id
),
ranked_final as (
    select
        f.*,
        row_number() over (
            partition by row_type
            order by
                coalesce(quality_score, 0) desc,
                coalesce(viewcount, 0) desc,
                coalesce(answercount, 0) desc,
                entity_id
        ) as final_rank
    from final_union f
)
select *
from ranked_final
where
    (
        row_type = 'QUESTION'
        and (
            quality_score > (
                select avg(quality_score) from question_quality where quality_score is not null
            )
            or hotness_rank <= 100
            or (tag_popularity_percentile >= 0.95 and q_upvotes - q_downvotes >= 5)
        )
    )
    or
    (
        row_type = 'USER'
        and final_rank <= 500
    )
order by row_type asc, final_rank asc, entity_id asc;