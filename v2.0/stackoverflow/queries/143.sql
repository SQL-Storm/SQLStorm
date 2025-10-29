-- {"query": "143.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2648}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        count(case when b.class = 1 then 1 end) as gold_badges,
        count(case when b.class = 2 then 1 end) as silver_badges,
        count(case when b.class = 3 then 1 end) as bronze_badges,
        max(b.date) as last_badge_date
    from users u
    left join badges b
        on b.userid = u.id
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, coalesce(nullif(trim(u.websiteurl), ''), 'n/a')
),
question_activity as (
    select
        p.owneruserid as user_id,
        p.id as question_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount as q_views,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        count(a.id) as answers_count,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        max(c.creationdate) as last_comment_at
    from posts p
    left join posts a
        on a.parentid = p.id
        and a.posttypeid = 2
    left join votes v
        on v.postid = p.id
        and v.votetypeid in (2,3)
    left join comments c
        on c.postid = p.id
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 1)
    group by p.owneruserid, p.id, p.creationdate, p.score, p.viewcount, p.title, p.tags, p.acceptedanswerid, p.closeddate
),
answer_activity as (
    select
        a.owneruserid as user_id,
        a.id as answer_id,
        a.parentid as question_id,
        a.creationdate as a_created,
        a.score as a_score,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as a_net_votes
    from posts a
    left join votes v
        on v.postid = a.id
        and v.votetypeid in (2,3)
    where a.posttypeid = 2
      and a.creationdate >= (select max(creationdate) - interval '365 days' from posts where posttypeid = 2)
    group by a.owneruserid, a.id, a.parentid, a.creationdate, a.score
),
tag_explode as (
    select
        qa.user_id,
        qa.question_id,
        unnest(string_to_array(substring(qa.tags, 2, length(qa.tags)-2), '><')) as tag
    from question_activity qa
    where qa.tags is not null
),
tag_stats as (
    select
        user_id,
        count(*) as tagged_questions,
        count(distinct tag) as distinct_tags,
        bool_or(tag like '%sql%') as uses_sql_tag
    from tag_explode
    group by user_id
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        pl.creationdate as link_created
    from postlinks pl
    where pl.linktypeid = 3
),
closure_reasons as (
    select
        ph.postid,
        max(ph.creationdate) as last_closed_at,
        max(
            case
                when ph.posthistorytypeid = 10
                then nullif(regexp_replace(coalesce(ph.comment,''), '[^0-9]', '', 'g'), '')
                else null
            end
        ) as last_close_reason_text
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
closure_reasons_parsed as (
    select
        postid,
        last_closed_at,
        case when last_close_reason_text ~ '^[0-9]+$' then cast(last_close_reason_text as integer) else null end as last_close_reason_id
    from closure_reasons
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate,
        ru.location,
        ru.websiteurl,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.last_badge_date,
        coalesce(ts.tagged_questions, 0) as tagged_questions,
        coalesce(ts.distinct_tags, 0) as distinct_tags,
        coalesce(ts.uses_sql_tag, false) as uses_sql_tag,
        count(distinct qa.question_id) as questions_posted,
        sum(qa.answers_count) as answers_received_on_questions,
        sum(case when qa.acceptedanswerid is not null then 1 else 0 end) as questions_with_accepted_ans,
        sum(qa.net_votes) as question_net_votes,
        sum(coalesce(qa.q_views,0)) as question_views,
        max(qa.last_comment_at) as last_question_comment_at,
        count(distinct aa.answer_id) as answers_authored,
        sum(aa.a_net_votes) as answers_net_votes,
        avg(qa.q_score) filter (where qa.q_score is not null) as avg_q_score,
        avg(aa.a_score) filter (where aa.a_score is not null) as avg_a_score,
        max(qa.q_created) as last_question_at,
        max(aa.a_created) as last_answer_at
    from recent_users ru
    left join question_activity qa
        on qa.user_id = ru.user_id
    left join answer_activity aa
        on aa.user_id = ru.user_id
    left join tag_stats ts
        on ts.user_id = ru.user_id
    group by ru.user_id, ru.displayname, ru.reputation, ru.creationdate, ru.location, ru.websiteurl,
             ru.gold_badges, ru.silver_badges, ru.bronze_badges, ru.last_badge_date,
             ts.tagged_questions, ts.distinct_tags, ts.uses_sql_tag
),
question_rollup as (
    select
        qa.question_id,
        qa.user_id,
        coalesce(crp.last_closed_at, qa.closeddate) as effective_closed_at,
        crp.last_close_reason_id,
        dl.original_post_id as duplicate_of,
        count(distinct ca.id) as comments_count,
        min(ans.creationdate) filter (where ans.parentid = qa.question_id) as first_answer_at,
        max(ans.creationdate) filter (where ans.parentid = qa.question_id) as last_answer_at
    from question_activity qa
    left join dup_links dl
        on dl.dup_post_id = qa.question_id
    left join closure_reasons_parsed crp
        on crp.postid = qa.question_id
    left join comments ca
        on ca.postid = qa.question_id
    left join posts ans
        on ans.parentid = qa.question_id
        and ans.posttypeid = 2
    group by qa.question_id, qa.user_id, crp.last_closed_at, qa.closeddate, crp.last_close_reason_id, dl.original_post_id
),
user_quality as (
    select
        ur.user_id,
        percentile_cont(0.5) within group (order by qa.q_score) as median_q_score,
        percentile_cont(0.9) within group (order by aa.a_score) as p90_a_score,
        count(*) filter (where qr.duplicate_of is not null) as dup_questions,
        count(*) filter (where qr.last_close_reason_id = 101) as closed_as_duplicate,
        count(*) filter (where qr.effective_closed_at is not null) as total_closed,
        avg(extract(epoch from (qr.last_answer_at - qa.q_created))) filter (where qr.last_answer_at is not null) as avg_time_to_last_answer_sec
    from user_rollup ur
    left join question_activity qa
        on qa.user_id = ur.user_id
    left join answer_activity aa
        on aa.user_id = ur.user_id
    left join question_rollup qr
        on qr.user_id = ur.user_id
        and qr.question_id = qa.question_id
    group by ur.user_id
),
activity_flags as (
    select
        ur.user_id,
        case
            when coalesce(ur.answers_authored,0) = 0 and coalesce(ur.questions_posted,0) = 0 then 'inactive'
            when coalesce(ur.answers_authored,0) > coalesce(ur.questions_posted,0) * 5 then 'answer-heavy'
            when coalesce(ur.questions_posted,0) > coalesce(ur.answers_authored,0) * 5 then 'question-heavy'
            else 'balanced'
        end as activity_mix,
        case
            when ur.last_answer_at is null and ur.last_question_at is null then null
            when greatest(coalesce(ur.last_answer_at, timestamp '1970-01-01'), coalesce(ur.last_question_at, timestamp '1970-01-01')) >= (timestamp '2024-10-01 12:34:56' - interval '30 days') then 'active_30d'
            when greatest(coalesce(ur.last_answer_at, timestamp '1970-01-01'), coalesce(ur.last_question_at, timestamp '1970-01-01')) >= (timestamp '2024-10-01 12:34:56' - interval '90 days') then 'active_90d'
            else 'stale'
        end as recency_bucket
    from user_rollup ur
),
ranked_users as (
    select
        ur.user_id,
        ur.displayname,
        ur.reputation,
        ur.creationdate,
        ur.location,
        ur.websiteurl,
        ur.gold_badges,
        ur.silver_badges,
        ur.bronze_badges,
        ur.last_badge_date,
        ur.tagged_questions,
        ur.distinct_tags,
        ur.uses_sql_tag,
        ur.questions_posted,
        ur.answers_received_on_questions,
        ur.questions_with_accepted_ans,
        ur.question_net_votes,
        ur.question_views,
        ur.last_question_comment_at,
        ur.answers_authored,
        ur.answers_net_votes,
        ur.avg_q_score,
        ur.avg_a_score,
        ur.last_question_at,
        ur.last_answer_at,
        uq.median_q_score,
        uq.p90_a_score,
        uq.dup_questions,
        uq.closed_as_duplicate,
        uq.total_closed,
        uq.avg_time_to_last_answer_sec,
        af.activity_mix,
        af.recency_bucket,
        row_number() over (
            partition by af.activity_mix
            order by
                coalesce(ur.answers_net_votes,0) + coalesce(ur.question_net_votes,0) desc,
                ur.reputation desc,
                ur.questions_posted desc
        ) as rn_in_mix,
        dense_rank() over (
            order by
                coalesce(ur.answers_net_votes,0) + coalesce(ur.question_net_votes,0) desc
        ) as global_rank_by_net_votes
    from user_rollup ur
    left join user_quality uq on uq.user_id = ur.user_id
    left join activity_flags af on af.user_id = ur.user_id
),
mix_agg as (
    select
        activity_mix,
        count(*) as users_in_mix,
        avg(reputation) as avg_rep_in_mix,
        avg(coalesce(answers_net_votes,0) + coalesce(question_net_votes,0)) as avg_net_votes_in_mix
    from ranked_users
    group by activity_mix
),
final as (
    select
        ru.user_id,
        coalesce(ru.displayname, 'user_' || cast(ru.user_id as text)) as displayname,
        ru.reputation,
        ru.location,
        ru.websiteurl,
        (cast(ru.gold_badges as text) || '/' || cast(ru.silver_badges as text) || '/' || cast(ru.bronze_badges as text)) as badge_mix,
        ru.questions_posted,
        ru.answers_authored,
        ru.question_views,
        ru.question_net_votes,
        ru.answers_net_votes,
        ru.avg_q_score,
        ru.avg_a_score,
        ru.median_q_score,
        ru.p90_a_score,
        ru.tagged_questions,
        ru.distinct_tags,
        ru.uses_sql_tag,
        ru.dup_questions,
        ru.closed_as_duplicate,
        ru.total_closed,
        ru.avg_time_to_last_answer_sec,
        ru.activity_mix,
        ru.recency_bucket,
        ru.rn_in_mix,
        ru.global_rank_by_net_votes,
        ma.users_in_mix,
        ma.avg_rep_in_mix,
        ma.avg_net_votes_in_mix
    from ranked_users ru
    left join mix_agg ma
        on ma.activity_mix = ru.activity_mix
)
select *
from final
where
    (recency_bucket is distinct from 'stale' or reputation >= 1000)
    and coalesce(answers_authored,0) + coalesce(questions_posted,0) > 0
    and (uses_sql_tag = true or distinct_tags >= 5)
order by
    global_rank_by_net_votes asc,
    rn_in_mix asc,
    user_id asc
limit 250;