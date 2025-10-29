-- {"query": "898.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2552} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as region,
        date_trunc('month', u.creationdate) as cohort_month,
        count(b.id) filter (where b.class = 1) as gold_badges,
        count(b.id) filter (where b.class = 2) as silver_badges,
        count(b.id) filter (where b.class = 3) as bronze_badges,
        count(*) over () as total_users_window
    from users u
    left join badges b
        on b.userid = u.id
        and b.date >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '10 years'
    group by u.id, u.displayname, u.reputation, region, cohort_month
),
question_activity as (
    select
        p.owneruserid as user_id,
        count(*) as question_count,
        sum(coalesce(p.viewcount, 0)) as total_views,
        sum(coalesce(p.score, 0)) as total_score,
        avg(nullif(p.answercount, 0)) as avg_answercount_nonzero,
        max(p.creationdate) as last_question_date,
        count(*) filter (where p.closeddate is not null) as closed_questions
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by p.owneruserid
),
answer_activity as (
    select
        p.owneruserid as user_id,
        count(*) as answer_count,
        sum(coalesce(p.score, 0)) as total_answer_score,
        max(p.creationdate) as last_answer_date
    from posts p
    where p.posttypeid = 2
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by p.owneruserid
),
vote_agg as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        sum(coalesce(v.bountyamount, 0)) as total_bounty_given
    from votes v
    where v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by v.userid
),
comment_agg as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        sum(greatest(length(c.text) - length(replace(c.text, ' ', '')) + 1, 1)) as comment_words,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by c.userid
),
dup_links as (
    select
        pl.postid as post_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
        count(*) filter (where pl.linktypeid = 1) as linked_refs
    from postlinks pl
    where pl.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by pl.postid
),
question_quality as (
    select
        q.id as post_id,
        q.owneruserid as user_id,
        q.score,
        q.viewcount,
        q.answercount,
        q.closeddate,
        coalesce(dl.duplicate_marks, 0) as duplicate_marks,
        coalesce(dl.linked_refs, 0) as linked_refs,
        case
            when q.closeddate is not null then 'Closed'
            when coalesce(dl.duplicate_marks, 0) > 0 then 'Duplicate'
            when q.score >= 5 and q.viewcount >= 1000 then 'Popular'
            when q.score < 0 then 'Controversial'
            else 'Normal'
        end as quality_bucket
    from posts q
    left join dup_links dl on dl.post_id = q.id
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
),
best_questions as (
    select
        user_id,
        post_id,
        score,
        viewcount,
        row_number() over (partition by user_id order by score desc nulls last, viewcount desc nulls last, post_id) as rn
    from question_quality
),
user_edits as (
    select
        ph.userid as user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20)) as mod_actions_count,
        max(ph.creationdate) as last_edit_date
    from posthistory ph
    where ph.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
    group by ph.userid
),
tag_extract as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        unnest(
            case
                when p.tags is null then array[]::varchar[]
                else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
            end
        ) as tagname
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '8 years'
),
top_tags as (
    select
        te.user_id,
        te.tagname,
        count(*) as tag_uses,
        row_number() over (partition by te.user_id order by count(*) desc, te.tagname) as tag_rn
    from tag_extract te
    group by te.user_id, te.tagname
),
user_last_activity as (
    select
        u.id as user_id,
        greatest(
            coalesce(qa.last_question_date, to_timestamp(0)),
            coalesce(aa.last_answer_date, to_timestamp(0)),
            coalesce(ca.last_comment_date, to_timestamp(0)),
            coalesce(ue.last_edit_date, to_timestamp(0)),
            u.lastaccessdate
        ) as last_touch
    from users u
    left join question_activity qa on qa.user_id = u.id
    left join answer_activity aa on aa.user_id = u.id
    left join comment_agg ca on ca.user_id = u.id
    left join user_edits ue on ue.user_id = u.id
),
cohort_perf as (
    select
        ru.cohort_month,
        count(*) as users_in_cohort,
        avg(coalesce(qa.question_count, 0)) as avg_questions,
        avg(coalesce(aa.answer_count, 0)) as avg_answers,
        percentile_cont(0.9) within group (order by coalesce(qa.total_score, 0) + coalesce(aa.total_answer_score, 0)) as p90_total_score
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join answer_activity aa on aa.user_id = ru.user_id
    group by ru.cohort_month
),
power_users as (
    select
        ru.user_id,
        (coalesce(qa.total_score,0) + coalesce(aa.total_answer_score,0)) as total_contrib_score,
        ntile(10) over (order by coalesce(qa.total_score,0) + coalesce(aa.total_answer_score,0) desc) as decile
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join answer_activity aa on aa.user_id = ru.user_id
),
null_sentinel as (
    select
        ru.user_id,
        case when qa.user_id is null and aa.user_id is null and ca.user_id is null then 1 else 0 end as has_no_activity
    from recent_users ru
    left join question_activity qa on qa.user_id = ru.user_id
    left join answer_activity aa on aa.user_id = ru.user_id
    left join comment_agg ca on ca.user_id = ru.user_id
)
select
    ru.user_id,
    coalesce(ru.displayname, concat('user#', ru.user_id::varchar)) as displayname,
    ru.reputation,
    ru.region,
    ru.cohort_month,
    ru.gold_badges,
    ru.silver_badges,
    ru.bronze_badges,
    coalesce(qa.question_count, 0) as question_count,
    coalesce(qa.total_views, 0) as total_question_views,
    coalesce(qa.total_score, 0) as total_question_score,
    coalesce(qa.closed_questions, 0) as closed_questions,
    coalesce(aa.answer_count, 0) as answer_count,
    coalesce(aa.total_answer_score, 0) as total_answer_score,
    coalesce(va.upvotes_cast, 0) as upvotes_cast,
    coalesce(va.downvotes_cast, 0) as downvotes_cast,
    coalesce(va.favorites_cast, 0) as favorites_cast,
    coalesce(va.total_bounty_given, 0) as bounty_given,
    coalesce(ca.comments_count, 0) as comments_count,
    coalesce(ca.comment_words, 0) as comment_words,
    coalesce(ue.edit_count, 0) as edit_count,
    coalesce(ue.mod_actions_count, 0) as mod_actions_count,
    qh.quality_bucket as best_question_quality_bucket,
    qh.score as best_question_score,
    qh.viewcount as best_question_views,
    tt1.tagname as top_tag_1,
    tt2.tagname as top_tag_2,
    tt3.tagname as top_tag_3,
    ul.last_touch,
    cp.users_in_cohort,
    cp.avg_questions,
    cp.avg_answers,
    cp.p90_total_score,
    pu.decile as contrib_decile,
    ns.has_no_activity,
    case
        when ru.reputation >= 20000 then 'Legend'
        when ru.reputation >= 10000 then 'Expert'
        when ru.reputation >= 1000 then 'Established'
        else 'Rookie'
    end as rep_tier
from recent_users ru
left join question_activity qa on qa.user_id = ru.user_id
left join answer_activity aa on aa.user_id = ru.user_id
left join vote_agg va on va.user_id = ru.user_id
left join comment_agg ca on ca.user_id = ru.user_id
left join user_edits ue on ue.user_id = ru.user_id
left join best_questions bq
    on bq.user_id = ru.user_id and bq.rn = 1
left join question_quality qh
    on qh.post_id = bq.post_id
left join top_tags tt1
    on tt1.user_id = ru.user_id and tt1.tag_rn = 1
left join top_tags tt2
    on tt2.user_id = ru.user_id and tt2.tag_rn = 2
left join top_tags tt3
    on tt3.user_id = ru.user_id and tt3.tag_rn = 3
left join user_last_activity ul on ul.user_id = ru.user_id
left join cohort_perf cp on cp.cohort_month = ru.cohort_month
left join power_users pu on pu.user_id = ru.user_id
left join null_sentinel ns on ns.user_id = ru.user_id
where
    (
        coalesce(qa.total_score, 0)
        + coalesce(aa.total_answer_score, 0)
        + coalesce(va.upvotes_cast, 0)
        + coalesce(ue.edit_count, 0)
    ) >= 0
order by
    pu.decile nulls last,
    ru.reputation desc,
    ru.user_id
limit 500;