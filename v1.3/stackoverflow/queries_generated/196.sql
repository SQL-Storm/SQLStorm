-- {"query": "196.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2752} 
with recent_activity as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.lastaccessdate,
        -- recency score: more recent activity -> higher
        greatest(0, extract(epoch from (now() - u.lastaccessdate))/86400) as days_since_last_access,
        -- weighted interactions
        coalesce((select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 1),0) as q_count,
        coalesce((select count(*) from posts p where p.owneruserid = u.id and p.posttypeid = 2),0) as a_count,
        coalesce((select count(*) from comments c where c.userid = u.id),0) as comment_count,
        coalesce((select count(*) from votes v where v.userid = u.id),0) as vote_actions
    from users u
    where u.id is not null
),
user_badge_agg as (
    select
        b.userid,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as most_recent_badge_date
    from badges b
    group by b.userid
),
user_post_stats as (
    select
        u.id as user_id,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as questions_posted,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as answers_posted,
        avg(nullif(p.score,0)) filter (where p.score is not null) as avg_post_score,
        sum(coalesce(p.viewcount,0)) as total_views_on_posts,
        max(p.lastactivitydate) as last_post_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
question_answer_details as (
    -- for each question compute aggregated answer metrics and top answer info
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.title,
        q.creationdate as asked_at,
        q.score as question_score,
        q.viewcount,
        q.tags,
        q.answercount,
        count(a.id) as existing_answers,
        avg(a.score) as avg_answer_score,
        max(a.score) as best_answer_score,
        -- id of the highest-scoring answer (ties broken by earliest creationdate)
        (select a2.id
         from posts a2
         where a2.parentid = q.id and a2.posttypeid = 2
         order by a2.score desc nulls last, a2.creationdate asc
         limit 1) as top_answer_id,
        -- correlated subquery: percent of answers from users with reputation > asker
        (select round(100.0 * sum(case when u.reputation > coalesce(q_owner.reputation,0) then 1 else 0 end) / nullif(count(a3.id),0),2)
         from posts a3
         left join users u on u.id = a3.owneruserid
         left join users q_owner on q_owner.id = q.owneruserid
         where a3.parentid = q.id and a3.posttypeid = 2
        ) as pct_answers_from_higher_rep
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.title, q.creationdate, q.score, q.viewcount, q.tags, q.answercount
),
tag_exploded as (
    -- explosion of tags for questions (PostTypeId = 1), handle NULL tags gracefully
    select
        q.id as question_id,
        trim(t) as tag
    from posts q
    cross join lateral (
        select unnest(string_to_array(substring(coalesce(q.tags,''), 2, char_length(coalesce(q.tags,'')) - 2), '><')) as t
    ) s
    where q.posttypeid = 1 and coalesce(q.tags,'') <> ''
),
tag_popularity as (
    select
        te.tag,
        count(distinct te.question_id) as questions_with_tag,
        sum(coalesce(q.viewcount,0)) as total_views_for_tag,
        avg(coalesce(q.score,0)) as avg_question_score_for_tag
    from tag_exploded te
    left join posts q on q.id = te.question_id
    group by te.tag
),
user_tag_skill as (
    -- per user, compute top tag by number of answers they posted in that tag and avg score
    select
        u.id as user_id,
        coalesce(t.tag,'<no-tag>') as tag,
        count(a.id) as answers_in_tag,
        avg(a.score) as avg_answer_score_in_tag,
        row_number() over (partition by u.id order by count(a.id) desc nulls last, avg(a.score) desc nulls last) as rn
    from users u
    left join posts a on a.owneruserid = u.id and a.posttypeid = 2
    left join posts q on q.id = a.parentid and q.posttypeid = 1
    left join lateral (
        select unnest(string_to_array(substring(coalesce(q.tags,''), 2, char_length(coalesce(q.tags,'')) - 2), '><')) as tag
    ) t on q.tags is not null and q.tags <> ''
    group by u.id, t.tag
),
best_user_tag as (
    select user_id, tag, answers_in_tag, avg_answer_score_in_tag
    from user_tag_skill
    where rn = 1
),
complex_user_score as (
    -- Combine many signals into a synthetic benchmark score
    select
        ra.user_id,
        ra.displayname,
        ra.reputation,
        ra.q_count,
        ra.a_count,
        ra.comment_count,
        ra.vote_actions,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ups.questions_posted,0) as questions_posted,
        coalesce(ups.answers_posted,0) as answers_posted,
        coalesce(ups.avg_post_score,0) as avg_post_score,
        -- time decay factor: newer accounts penalized (inverse log)
        (case when extract(epoch from (now() - ra.creationdate)) <= 0 then 1.0
              else 1.0 / (1 + ln(1 + extract(epoch from (now() - ra.creationdate))/86400))
         end) as age_decay,
        -- engagement index
        (ra.a_count * 2.5 + ra.q_count * 3 + ra.comment_count * 0.8 + ra.vote_actions * 0.5 + coalesce(ub.gold_badges,0) * 10 + coalesce(ub.silver_badges,0) * 3 + coalesce(ub.bronze_badges,0) * 1) as raw_engagement,
        -- normalized final score
        round(
            (
                (ra.reputation * 0.001)
                + (coalesce(ups.avg_post_score,0) * 0.2)
                + ((ra.a_count + ra.q_count) * 0.05)
                + (coalesce(ub.total_badges,0) * 0.02)
                + ((case when ra.days_since_last_access < 30 then 1 else 0 end) * 0.5)
            ) * (case when ra.days_since_last_access is null then 1 else greatest(0.1, 1 - ra.days_since_last_access/365.0) end)
            * (case when (case when extract(epoch from (now() - ra.creationdate)) <= 0 then 1.0 else 1.0 / (1 + ln(1 + extract(epoch from (now() - ra.creationdate))/86400)) end) is null then 1 else (case when extract(epoch from (now() - ra.creationdate)) <= 0 then 1.0 else 1.0 / (1 + ln(1 + extract(epoch from (now() - ra.creationdate))/86400)) end) end)
            ,4) as benchmark_score
    from recent_activity ra
    left join user_badge_agg ub on ub.userid = ra.user_id
    left join user_post_stats ups on ups.user_id = ra.user_id
),
ranked_users as (
    select
        *,
        rank() over (order by benchmark_score desc nulls last) as rank_by_score,
        dense_rank() over (order by coalesce(total_badges,0) desc) as rank_by_badges,
        ntile(10) over (order by benchmark_score desc nulls last) as decile
    from complex_user_score
),
top_questions_with_answer_stats as (
    select
        qad.*,
        tp.tag,
        tp.questions_with_tag,
        tp.total_views_for_tag,
        tp.avg_question_score_for_tag,
        best_user_tag.tag as asker_top_tag,
        best_user_tag.answers_in_tag as asker_top_tag_answers,
        -- string expression: concise question summary
        left(coalesce(qad.title, '') || ' [' || coalesce(tp.tag,'no-tag') || ']', 200) as short_summary
    from question_answer_details qad
    left join lateral (
        select tag, questions_with_tag, total_views_for_tag, avg_question_score_for_tag
        from tag_popularity tp where tp.tag = (select unnest(string_to_array(substring(coalesce(qad.tags,''),2,char_length(coalesce(qad.tags,''))-2),'><')) limit 1)
        limit 1
    ) tp on true
    left join best_user_tag on best_user_tag.user_id = qad.asker_id
),
combined_final AS (
    -- Combine top users and a sample of hot questions using UNION to exercise set operators and NULL handling
    select
        'user'::varchar as row_type,
        ru.user_id as id,
        ru.displayname as title_or_name,
        ru.benchmark_score as metric1,
        ru.rank_by_score as metric2,
        ru.decile as metric3,
        ru.total_badges as misc1,
        ru.avg_post_score as misc2,
        ru.age_decay as misc3,
        null::int as question_id,
        null::varchar as question_short_summary,
        now() as snapshot_at
    from ranked_users ru
    where ru.rank_by_score <= 100 -- top 100 users
    union all
    select
        'question'::varchar as row_type,
        qad.question_id as id,
        coalesce(qad.title, left(qad.tags,100)) as title_or_name,
        coalesce(qad.question_score,0) as metric1,
        coalesce(qad.existing_answers,0) as metric2,
        coalesce(qad.best_answer_score,0) as metric3,
        coalesce(tp.questions_with_tag,0) as misc1,
        coalesce(qad.pct_answers_from_higher_rep,0) as misc2,
        null::float as misc3,
        qad.question_id as question_id,
        qad.short_summary as question_short_summary,
        now() as snapshot_at
    from top_questions_with_answer_stats qad
    left join tag_popularity tp on tp.tag = (select unnest(string_to_array(substring(coalesce(qad.tags,''),2,char_length(coalesce(qad.tags,''))-2),'><')) limit 1)
    where coalesce(qad.answercount,0) >= 2 and coalesce(qad.viewcount,0) > 1000
    order by 1 desc, 3 desc
)
select *
from combined_final
order by snapshot_at desc, row_type desc, metric1 desc
limit 250;