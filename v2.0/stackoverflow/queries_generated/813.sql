-- {"query": "813.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3623} 
with
-- Generate monthly cohorts of users by creation month
user_cohorts as (
    select
        u.id as user_id,
        date_trunc('month', u.creationdate) as cohort_month,
        u.reputation,
        coalesce(nullif(trim(lower(u.location)), ''), 'unknown') as norm_location
    from users u
),
-- Identify top tags and map questions to tags
question_tags as (
    select
        p.id as question_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag_name,
        p.creationdate as q_created,
        p.owneruserid as asker_id,
        p.score as q_score,
        p.viewcount as q_views,
        p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
top_tags as (
    select t.tagname, t.count
    from tags t
    where t.count > (
        select percentile_cont(0.9) within group (order by t2.count)
        from tags t2
        where t2.count is not null
    )
),
qt_top as (
    select qt.*
    from question_tags qt
    inner join top_tags tt on tt.tagname = qt.tag_name
),
-- Answers joined with their parent questions (outer join to include orphan answers)
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
qa as (
    select
        q.question_id,
        q.tag_name,
        q.q_created,
        q.asker_id,
        q.q_score,
        q.q_views,
        q.acceptedanswerid,
        a.answer_id,
        a.answerer_id,
        a.a_created,
        a.a_score
    from qt_top q
    left join answers a on a.question_id = q.question_id
),
-- Compute first answer time per question and whether accepted answer was first
first_answers as (
    select
        question_id,
        min(a_created) filter (where answer_id is not null) as first_answer_time,
        min(case when answer_id = acceptedanswerid then a_created end) as accepted_time,
        bool_or(case when answer_id = acceptedanswerid and a_created = min(a_created) over (partition by question_id) then true end) as accepted_was_first
    from qa
    group by question_id
),
-- User activity windows
user_activity as (
    select
        u.id as user_id,
        u.reputation,
        u.upvotes,
        u.downvotes,
        u.views,
        row_number() over (order by u.reputation desc nulls last, u.id) as rep_rank_global,
        ntile(10) over (order by u.reputation desc nulls last) as rep_decile
    from users u
),
-- Votes aggregated by question and type with null-safe pivots
question_votes as (
    select
        v.postid as question_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
    from votes v
    group by v.postid
),
-- Post history signals (closures, protections, migrations)
question_history_flags as (
    select
        ph.postid as question_id,
        max(case when ph.posthistorytypeid = 10 then 1 else 0 end) as was_closed,
        max(case when ph.posthistorytypeid = 11 then 1 else 0 end) as was_reopened,
        max(case when ph.posthistorytypeid = 19 then 1 else 0 end) as was_protected,
        max(case when ph.posthistorytypeid in (35,36) then 1 else 0 end) as was_migrated
    from posthistory ph
    where ph.postid is not null
    group by ph.postid
),
-- Link graph: duplicates and linked counts
question_links as (
    select
        pl.postid as question_id,
        sum(case when pl.linktypeid = 1 then 1 else 0 end) as linked_out,
        sum(case when pl.linktypeid = 3 then 1 else 0 end) as marked_duplicate_of
    from postlinks pl
    group by pl.postid
),
-- Comment signal: max comment score and count
question_comments as (
    select
        c.postid as question_id,
        count(*) as comment_count,
        coalesce(max(c.score), 0) as max_comment_score
    from comments c
    group by c.postid
),
-- Badge effects: count of gold/silver/bronze before question creation for asker
asker_badges as (
    select
        q.question_id,
        count(*) filter (where b.class = 1) as asker_gold_badges,
        count(*) filter (where b.class = 2) as asker_silver_badges,
        count(*) filter (where b.class = 3) as asker_bronze_badges
    from qt_top q
    left join badges b
      on b.userid = q.asker_id
     and b.date <= q.q_created
    group by q.question_id
),
-- Derive time-to-first-answer and acceptance SLA buckets
sla as (
    select
        qa.question_id,
        qa.tag_name,
        qa.q_created,
        qa.asker_id,
        extract(epoch from (fa.first_answer_time - qa.q_created))::bigint as secs_to_first_answer,
        extract(epoch from (fa.accepted_time - qa.q_created))::bigint as secs_to_accept,
        case
            when fa.first_answer_time is null then 'no-answer'
            when fa.first_answer_time <= qa.q_created + interval '1 hour' then '1h'
            when fa.first_answer_time <= qa.q_created + interval '6 hour' then '6h'
            when fa.first_answer_time <= qa.q_created + interval '24 hour' then '24h'
            when fa.first_answer_time <= qa.q_created + interval '3 day' then '3d'
            else 'gt-3d'
        end as first_answer_sla_bucket,
        coalesce(fa.accepted_was_first, false) as accepted_was_first
    from (select distinct question_id, tag_name, q_created, asker_id from qa) qa
    left join first_answers fa on fa.question_id = qa.question_id
),
-- Consolidated question metrics
question_metrics as (
    select
        s.question_id,
        s.tag_name,
        s.q_created,
        s.asker_id,
        s.secs_to_first_answer,
        s.secs_to_accept,
        s.first_answer_sla_bucket,
        s.accepted_was_first,
        coalesce(qv.upvotes, 0) as upvotes,
        coalesce(qv.downvotes, 0) as downvotes,
        coalesce(qv.favorites, 0) as favorites,
        coalesce(qc.comment_count, 0) as comment_count,
        coalesce(qc.max_comment_score, 0) as max_comment_score,
        coalesce(ql.linked_out, 0) as linked_out,
        coalesce(ql.marked_duplicate_of, 0) as marked_duplicate_of,
        coalesce(qh.was_closed, 0) as was_closed,
        coalesce(qh.was_reopened, 0) as was_reopened,
        coalesce(qh.was_protected, 0) as was_protected,
        coalesce(qh.was_migrated, 0) as was_migrated
    from sla s
    left join question_votes qv on qv.question_id = s.question_id
    left join question_comments qc on qc.question_id = s.question_id
    left join question_links ql on ql.question_id = s.question_id
    left join question_history_flags qh on qh.question_id = s.question_id
),
-- Enrich asker with cohort and activity metrics
asker_enriched as (
    select
        qm.*,
        uc.cohort_month,
        ua.rep_rank_global,
        ua.rep_decile
    from question_metrics qm
    left join user_cohorts uc on uc.user_id = qm.asker_id
    left join user_activity ua on ua.user_id = qm.asker_id
),
-- Tag-level rolling stats by month for additional windowed complexity
tag_monthly as (
    select
        date_trunc('month', q_created) as ym,
        tag_name,
        count(*) as questions,
        avg(nullif(secs_to_first_answer, 0)) as avg_secs_first_answer,
        percentile_cont(0.5) within group (order by secs_to_first_answer) as p50_secs_first_answer,
        percentile_cont(0.9) within group (order by secs_to_first_answer) as p90_secs_first_answer
    from asker_enriched
    group by 1, 2
),
tag_monthly_with_windows as (
    select
        tm.*,
        avg(avg_secs_first_answer) over (partition by tag_name order by ym rows between 2 preceding and current row) as ma3_avg_secs_first_answer,
        sum(questions) over (partition by tag_name order by ym rows between 5 preceding and current row) as rolling6_questions
    from tag_monthly tm
),
-- Outlier detection for questions relative to tag-month distributions
question_outliers as (
    select
        ae.question_id,
        ae.tag_name,
        ae.q_created,
        ae.secs_to_first_answer,
        tmw.ym,
        tmw.p90_secs_first_answer,
        case when ae.secs_to_first_answer is not null and tmw.p90_secs_first_answer is not null
              and ae.secs_to_first_answer > tmw.p90_secs_first_answer then 1 else 0 end as is_slow_outlier
    from asker_enriched ae
    left join tag_monthly_with_windows tmw
      on tmw.tag_name = ae.tag_name
     and tmw.ym = date_trunc('month', ae.q_created)
),
-- Combine duplicate relationships to count inbound duplicates per question
inbound_duplicates as (
    select
        pl.relatedpostid as canonical_question_id,
        count(*) as inbound_dupe_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.relatedpostid
),
-- Final assembly with a variety of expressions, null logic, and set operators
final_aggregate as (
    select
        ae.tag_name,
        date_trunc('month', ae.q_created) as ym,
        count(*) as total_questions,
        count(*) filter (where ae.first_answer_sla_bucket = '1h') as q_1h,
        count(*) filter (where ae.first_answer_sla_bucket = '6h') as q_6h,
        count(*) filter (where ae.first_answer_sla_bucket = '24h') as q_24h,
        count(*) filter (where ae.first_answer_sla_bucket = '3d') as q_3d,
        count(*) filter (where ae.first_answer_sla_bucket = 'gt-3d') as q_gt3d,
        count(*) filter (where ae.first_answer_sla_bucket = 'no-answer') as q_no_answer,
        avg(ae.upvotes - ae.downvotes) as avg_net_votes,
        max(ae.favorites) as max_favorites,
        sum(ae.comment_count) as total_comments,
        sum(ae.linked_out) as total_links_out,
        sum(ae.marked_duplicate_of) as total_marked_duplicate_of,
        sum(ae.was_closed) as closed_questions,
        sum(ae.was_reopened) as reopened_questions,
        sum(ae.was_protected) as protected_questions,
        sum(ae.was_migrated) as migrated_questions,
        avg(case when ae.secs_to_first_answer is null then null else ae.secs_to_first_answer end) as avg_secs_to_first_answer,
        percentile_cont(0.5) within group (order by ae.secs_to_first_answer) as p50_secs_to_first_answer,
        percentile_cont(0.9) within group (order by ae.secs_to_first_answer) as p90_secs_to_first_answer,
        sum(qo.is_slow_outlier) as slow_outliers,
        avg(ae.rep_decile) as avg_asker_rep_decile,
        min(ae.rep_rank_global) as best_asker_rep_rank,
        sum(case when ae.accepted_was_first then 1 else 0 end) as accepted_first_count
    from asker_enriched ae
    left join question_outliers qo on qo.question_id = ae.question_id
    group by 1, 2
),
-- Derive synthetic "difficulty score" per tag-month
difficulty as (
    select
        fa.*,
        (coalesce(p90_secs_to_first_answer, 0)
         + 600 * (q_no_answer::numeric / nullif(total_questions,0))
         + 120 * (closed_questions::numeric / nullif(total_questions,0))
         + 60 * (slow_outliers::numeric / nullif(total_questions,0))
         + 10 * greatest(0, 1 - avg_net_votes))::numeric as difficulty_score
    from final_aggregate fa
),
-- Rank tag-months by difficulty within tag and globally
difficulty_ranked as (
    select
        d.*,
        row_number() over (partition by tag_name order by difficulty_score desc nulls last, ym desc) as tag_rank,
        dense_rank() over (order by difficulty_score desc nulls last) as global_rank
    from difficulty d
),
-- Build a label and incorporate inbound duplicate pressure
with_dupe_pressure as (
    select
        dr.*,
        coalesce(sum(idu.inbound_dupe_count), 0) as inbound_dupe_pressure
    from difficulty_ranked dr
    left join (
        select
            ae.tag_name,
            date_trunc('month', ae.q_created) as ym,
            sum(coalesce(idu.inbound_dupe_count,0)) as inbound_dupe_count
        from asker_enriched ae
        left join inbound_duplicates idu on idu.canonical_question_id = ae.question_id
        group by 1,2
    ) idu
      on idu.tag_name = dr.tag_name and idu.ym = dr.ym
),
-- Construct correlated subquery to compute share of top-asker deciles per tag-month
decile_distribution as (
    select
        ae.tag_name,
        date_trunc('month', ae.q_created) as ym,
        avg(case when ae.rep_decile <= 3 then 1.0 else 0.0 end) as share_top_deciles
    from asker_enriched ae
    group by 1,2
)
select
    wdp.tag_name,
    wdp.ym,
    wdp.global_rank,
    wdp.tag_rank,
    round(wdp.difficulty_score, 2) as difficulty_score,
    wdp.total_questions,
    wdp.q_no_answer,
    wdp.p90_secs_to_first_answer,
    wdp.closed_questions,
    wdp.slow_outliers,
    wdp.avg_net_votes,
    wdp.inbound_dupe_pressure,
    dd.share_top_deciles,
    -- string expressions and null logic
    ('[' || to_char(wdp.ym, 'YYYY-MM') || '] ' || wdp.tag_name ||
     ' q=' || coalesce(wdp.total_questions::text, '0') ||
     ' p90=' || coalesce(round(wdp.p90_secs_to_first_answer/3600.0,2)::text, 'n/a') || 'h' ||
     case when wdp.q_no_answer > 0 then ' noAns='||wdp.q_no_answer::text else '' end ||
     case when wdp.closed_questions > 0 then ' closed='||wdp.closed_questions::text else '' end
    ) as summary_label
from with_dupe_pressure wdp
left join decile_distribution dd
  on dd.tag_name = wdp.tag_name and dd.ym = wdp.ym
where wdp.total_questions > 0
  and (
      -- complicated predicates mixing nulls and ranges
      wdp.difficulty_score > (
          select avg(difficulty_score) from with_dupe_pressure where tag_name = wdp.tag_name
      )
      or (wdp.p90_secs_to_first_answer is not null and wdp.p90_secs_to_first_answer > 6*3600)
      or (dd.share_top_deciles is not null and dd.share_top_deciles < 0.2)
  )
order by wdp.global_rank, wdp.tag_name, wdp.ym
limit 200;