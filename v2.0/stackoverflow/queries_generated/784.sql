-- {"query": "784.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2874} 
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_normalized,
        date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(p.creationdate) from posts p where p.posttypeid in (1,2)) - interval '3 years'
),
tagged_questions as (
    select
        q.id as question_id,
        q.owneruserid as owner_id,
        q.creationdate as question_date,
        q.score as question_score,
        q.viewcount,
        q.title,
        q.tags,
        string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><') as tag_array
    from posts q
    where q.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_date,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
accepted as (
    select
        q.id as question_id,
        q.acceptedanswerid as accepted_answer_id
    from posts q
    where q.posttypeid = 1
      and q.acceptedanswerid is not null
),
user_badges as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_activity as (
    select
        q.question_id,
        count(distinct a.answer_id) as answers_count,
        count(distinct c.id) as comments_count,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        max(coalesce(a.answer_date, q.question_date)) as last_answer_or_question_time
    from tagged_questions q
    left join answers a on a.question_id = q.question_id
    left join comments c on c.postid = q.question_id
    left join votes v on v.postid = q.question_id and v.votetypeid in (2,3)
    group by q.question_id, q.question_date
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as canonical_post_id,
        min(pl.creationdate) as first_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
post_closures as (
    select
        ph.postid,
        min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed_at,
        max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_at,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max((ph.comment ~ '^[0-9]+$')::int * nullif(ph.comment, '')::int) filter (where ph.posthistorytypeid = 10) as last_close_reason_code
    from posthistory ph
    group by ph.postid
),
user_activity_rollup as (
    select
        ru.id as user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        count(distinct tq.question_id) as questions_asked,
        count(distinct a.answer_id) as answers_posted,
        sum(qa.answers_count) as total_answers_on_their_questions,
        sum(qa.comments_count) as total_comments_on_their_questions,
        sum(qa.net_votes) as net_votes_on_their_questions,
        max(qa.last_answer_or_question_time) as last_engagement_time,
        count(distinct case when ac.accepted_answer_id is not null then tq.question_id end) as questions_with_accepted,
        count(distinct case when dl.dup_post_id is not null then tq.question_id end) as questions_marked_duplicate,
        count(distinct case when pc.first_closed_at is not null then tq.question_id end) as questions_closed
    from recent_users ru
    left join tagged_questions tq on tq.owner_id = ru.id
    left join question_activity qa on qa.question_id = tq.question_id
    left join accepted ac on ac.question_id = tq.question_id
    left join dup_links dl on dl.dup_post_id = tq.question_id
    left join post_closures pc on pc.postid = tq.question_id
    left join answers a on a.answerer_id = ru.id
    group by ru.id, ru.displayname, ru.reputation, ru.cohort_month
),
question_quality as (
    select
        tq.question_id,
        tq.owner_id,
        tq.title,
        tq.question_date,
        tq.viewcount,
        tq.question_score,
        qa.answers_count,
        qa.comments_count,
        qa.net_votes,
        ac.accepted_answer_id,
        pc.first_closed_at,
        pc.last_reopened_at,
        pc.close_events,
        pc.reopen_events,
        pc.last_close_reason_code,
        case
            when pc.first_closed_at is not null and ac.accepted_answer_id is null then 'closed_unaccepted'
            when ac.accepted_answer_id is not null and coalesce(qa.answers_count,0) > 0 then 'accepted'
            when coalesce(qa.answers_count,0) = 0 and tq.viewcount > 1000 then 'unanswered_popular'
            when coalesce(qa.answers_count,0) = 0 then 'unanswered'
            else 'answered'
        end as quality_bucket
    from tagged_questions tq
    left join question_activity qa on qa.question_id = tq.question_id
    left join accepted ac on ac.question_id = tq.question_id
    left join post_closures pc on pc.postid = tq.question_id
),
top_tags as (
    select
        tq.owner_id,
        lower(trim(tn)) as tagname_norm,
        count(*) as cnt,
        row_number() over (partition by tq.owner_id order by count(*) desc, lower(trim(tn)) asc) as rn
    from tagged_questions tq
    cross join lateral unnest(tq.tag_array) as t(tn)
    group by tq.owner_id, lower(trim(tn))
),
user_vote_stats as (
    select
        u.id as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_given,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_given,
        count(*) filter (where v.votetypeid in (2,3)) as votes_cast
    from users u
    left join votes v on v.userid = u.id
    group by u.id
),
score_percentiles as (
    select
        qq.owner_id,
        percentile_cont(0.5) within group (order by coalesce(qq.question_score,0)) as median_q_score,
        percentile_cont(0.9) within group (order by coalesce(qq.question_score,0)) as p90_q_score
    from question_quality qq
    group by qq.owner_id
),
answer_response_time as (
    select
        tq.question_id,
        min(a.answer_date) as first_answer_time,
        tq.question_date,
        extract(epoch from (min(a.answer_date) - tq.question_date)) as seconds_to_first_answer
    from tagged_questions tq
    left join answers a on a.question_id = tq.question_id
    group by tq.question_id, tq.question_date
),
user_response_stats as (
    select
        tq.owner_id,
        avg(art.seconds_to_first_answer) filter (where art.seconds_to_first_answer is not null) as avg_secs_to_first_answer,
        percentile_cont(0.5) within group (order by art.seconds_to_first_answer) as p50_secs_to_first_answer
    from tagged_questions tq
    left join answer_response_time art on art.question_id = tq.question_id
    group by tq.owner_id
),
string_metrics as (
    select
        qq.owner_id,
        avg(length(coalesce(qq.title,''))) as avg_title_len,
        avg(o.word_count) as avg_title_words
    from question_quality qq
    cross join lateral (
        select
            case when coalesce(qq.title,'') = '' then 0
                 else cardinality(regexp_split_to_array(trim(qq.title), '\s+'))
            end as word_count
    ) o
    group by qq.owner_id
),
ranked_users as (
    select
        uar.*,
        coalesce(ub.total_badges, 0) as total_badges,
        coalesce(ubs.upvotes_given, 0) as upvotes_given,
        coalesce(ubs.downvotes_given, 0) as downvotes_given,
        coalesce(uts.tagname_norm, '(none)') as top_tag,
        coalesce(sp.median_q_score, 0) as median_q_score,
        coalesce(sp.p90_q_score, 0) as p90_q_score,
        coalesce(urs.avg_secs_to_first_answer, 0) as avg_secs_to_first_answer,
        coalesce(urs.p50_secs_to_first_answer, 0) as p50_secs_to_first_answer,
        coalesce(sm.avg_title_len, 0) as avg_title_len,
        coalesce(sm.avg_title_words, 0) as avg_title_words,
        row_number() over (
            order by
                (uar.questions_asked + uar.answers_posted) desc,
                uar.net_votes_on_their_questions desc,
                coalesce(ub.total_badges,0) desc,
                uar.reputation desc,
                uar.last_engagement_time desc nulls last
        ) as activity_rank
    from user_activity_rollup uar
    left join user_badges ub on ub.userid = uar.user_id
    left join user_vote_stats ubs on ubs.user_id = uar.user_id
    left join top_tags uts on uts.owner_id = uar.user_id and uts.rn = 1
    left join score_percentiles sp on sp.owner_id = uar.user_id
    left join user_response_stats urs on urs.owner_id = uar.user_id
    left join string_metrics sm on sm.owner_id = uar.user_id
),
cohort_stats as (
    select
        cohort_month,
        count(*) as users_in_cohort,
        avg(reputation) as avg_rep,
        avg(questions_asked) as avg_q,
        avg(answers_posted) as avg_a,
        avg(net_votes_on_their_questions) as avg_q_votes
    from user_activity_rollup
    group by cohort_month
),
final_users as (
    select
        ru.*,
        cs.users_in_cohort,
        cs.avg_rep as cohort_avg_rep
    from ranked_users ru
    left join cohort_stats cs on cs.cohort_month = ru.cohort_month
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.cohort_month,
    fu.users_in_cohort,
    fu.cohort_avg_rep,
    fu.questions_asked,
    fu.answers_posted,
    fu.total_answers_on_their_questions,
    fu.questions_with_accepted,
    fu.questions_closed,
    fu.questions_marked_duplicate,
    fu.net_votes_on_their_questions,
    fu.last_engagement_time,
    fu.total_badges,
    fu.upvotes_given,
    fu.downvotes_given,
    fu.top_tag,
    fu.median_q_score,
    fu.p90_q_score,
    fu.avg_secs_to_first_answer,
    fu.p50_secs_to_first_answer,
    fu.avg_title_len,
    fu.avg_title_words,
    fu.activity_rank,
    case
        when fu.questions_closed > 0 and fu.questions_with_accepted = 0 then 'needs_guidance'
        when fu.questions_with_accepted >= greatest(1, fu.questions_asked/2) then 'effective_asker'
        when fu.answers_posted > fu.questions_asked then 'more_answerer'
        when fu.answers_posted = 0 and fu.questions_asked = 0 then 'inactive'
        else 'balanced'
    end as engagement_profile
from final_users fu
where
    -- complex predicate to exercise planner
    (
        (fu.reputation >= coalesce(fu.cohort_avg_rep, 0) and fu.net_votes_on_their_questions >= 0)
        or
        (fu.reputation < coalesce(fu.cohort_avg_rep, 0) and fu.questions_asked > 0 and fu.answers_posted > 0)
    )
    and (fu.top_tag is null or fu.top_tag not like any (array['meta%', 'discussion%']))
    and coalesce(fu.avg_title_words, 0) >= 2
order by
    fu.activity_rank,
    fu.user_id
limit 200;