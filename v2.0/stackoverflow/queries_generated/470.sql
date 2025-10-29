-- {"query": "470.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3323} 
with recent_active_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(u.websiteurl, '') as websiteurl,
        date_trunc('month', greatest(u.creationdate, now() - interval '24 months')) as cohort_month,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date,
        sum(u.upvotes - u.downvotes) over (partition by u.id) as net_votes_snapshot
    from users u
    left join badges b
      on b.userid = u.id
    where u.lastaccessdate >= now() - interval '180 days'
    group by u.id, u.displayname, u.reputation, u.creationdate, u.location, u.websiteurl
),
user_post_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        avg(nullif(p.score, 0)) as avg_nonzero_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        max(p.lastactivitydate) as last_post_activity,
        sum(case when p.closeddate is not null then 1 else 0 end) as closed_posts,
        count(distinct p.parentid) filter (where p.posttypeid = 2 and p.parentid is not null) as distinct_answered_questions
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
recent_questions as (
    select
        q.id as question_id,
        q.owneruserid as asker_id,
        q.creationdate as asked_at,
        q.score as q_score,
        q.viewcount,
        q.answercount,
        q.tags,
        q.acceptedanswerid,
        regexp_split_to_table(coalesce(q.tags, ''), '><') as tag_piece_raw
    from posts q
    where q.posttypeid = 1
      and q.creationdate >= now() - interval '365 days'
),
normalized_tags as (
    select
        rq.question_id,
        rq.asker_id,
        lower(trim(both '<>' from tag_piece_raw)) as tagname
    from recent_questions rq
),
tag_stats as (
    select
        nt.tagname,
        count(*) as tag_q_count,
        avg(rq.q_score) as tag_avg_score,
        percentile_cont(0.9) within group (order by rq.q_score) as tag_p90_score
    from normalized_tags nt
    join recent_questions rq on rq.question_id = nt.question_id
    group by nt.tagname
),
answers_enriched as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answered_at,
        a.score as a_score,
        row_number() over (partition by a.parentid order by a.score desc nulls last, a.creationdate asc) as rn_by_score,
        dense_rank() over (partition by a.parentid order by a.creationdate asc) as dr_by_time
    from posts a
    where a.posttypeid = 2
      and a.creationdate >= now() - interval '365 days'
),
q_a_summary as (
    select
        rq.question_id,
        rq.asker_id,
        rq.q_score,
        rq.viewcount,
        rq.answercount,
        rq.acceptedanswerid,
        min(ae.answered_at) as first_answer_time,
        max(ae.a_score) as max_answer_score,
        count(*) filter (where ae.rn_by_score = 1) as has_top_answer,
        count(*) filter (where ae.dr_by_time = 1) as has_first_answer
    from recent_questions rq
    left join answers_enriched ae
      on ae.question_id = rq.question_id
    group by rq.question_id, rq.asker_id, rq.q_score, rq.viewcount, rq.answercount, rq.acceptedanswerid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (10,11,12)) as mod_actions
    from votes v
    where v.creationdate >= now() - interval '365 days'
    group by v.postid
),
close_reasons as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_at,
        mode() within group (order by cast(ph.comment as int)) as dominant_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid = 10
      and ph.creationdate >= now() - interval '365 days'
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_question_id,
        pl.relatedpostid as canonical_question_id,
        count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
      and pl.creationdate >= now() - interval '365 days'
    group by pl.postid, pl.relatedpostid
),
user_comment_activity as (
    select
        c.userid as user_id,
        count(*) as comments_last_year,
        sum(case when c.score > 0 then 1 else 0 end) as pos_scored_comments,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.creationdate >= now() - interval '365 days'
    group by c.userid
),
user_tag_focus as (
    select
        nt.asker_id as user_id,
        nt.tagname,
        count(*) as q_count_tag,
        row_number() over (partition by nt.asker_id order by count(*) desc, tagname asc) as rn_tag_pop
    from normalized_tags nt
    group by nt.asker_id, nt.tagname
),
heavy_users as (
    select
        rau.user_id,
        rau.displayname,
        rau.reputation,
        rau.cohort_month,
        upa.questions,
        upa.answers,
        upa.total_views,
        upa.avg_nonzero_score,
        upa.closed_posts,
        upa.distinct_answered_questions,
        uca.comments_last_year,
        coalesce(rau.gold_badges,0) as gold_badges,
        coalesce(rau.silver_badges,0) as silver_badges,
        coalesce(rau.bronze_badges,0) as bronze_badges,
        rau.last_badge_date,
        rau.net_votes_snapshot,
        uca.last_comment_date
    from recent_active_users rau
    left join user_post_activity upa on upa.user_id = rau.user_id
    left join user_comment_activity uca on uca.user_id = rau.user_id
),
per_question_metrics as (
    select
        rq.question_id,
        rq.asker_id,
        qas.q_score,
        qas.viewcount,
        qas.answercount,
        qas.acceptedanswerid,
        coalesce(va.upvotes,0) as upvotes,
        coalesce(va.downvotes,0) as downvotes,
        coalesce(va.bounty_started,0) as bounty_started,
        coalesce(va.bounty_awarded,0) as bounty_awarded,
        coalesce(va.mod_actions,0) as mod_actions,
        cr.first_close_at,
        cr.dominant_close_reason_id,
        case when rq.acceptedanswerid is not null then 1 else 0 end as has_accepted,
        qas.first_answer_time,
        qas.max_answer_score
    from recent_questions rq
    left join q_a_summary qas on qas.question_id = rq.question_id
    left join vote_agg va on va.postid = rq.question_id
    left join close_reasons cr on cr.postid = rq.question_id
),
tag_enriched as (
    select
        pqm.*,
        nt.tagname,
        ts.tag_q_count,
        ts.tag_avg_score,
        ts.tag_p90_score
    from per_question_metrics pqm
    join normalized_tags nt on nt.question_id = pqm.question_id
    left join tag_stats ts on ts.tagname = nt.tagname
),
user_top_tag as (
    select
        utf.user_id,
        utf.tagname as top_tag
    from user_tag_focus utf
    where utf.rn_tag_pop = 1
),
user_rollup as (
    select
        he.user_id,
        he.displayname,
        he.reputation,
        he.cohort_month,
        he.questions,
        he.answers,
        he.total_views,
        he.avg_nonzero_score,
        he.closed_posts,
        he.distinct_answered_questions,
        he.comments_last_year,
        he.gold_badges,
        he.silver_badges,
        he.bronze_badges,
        he.last_badge_date,
        he.net_votes_snapshot,
        he.last_comment_date,
        utt.top_tag,
        sum(case when te.has_accepted = 1 then 1 else 0 end) as accepted_qs,
        avg(te.q_score) as avg_q_score,
        avg(te.upvotes - te.downvotes) as avg_q_net_votes,
        avg(extract(epoch from (te.first_answer_time - rq.creationdate)) / 3600.0) as avg_hours_to_first_answer,
        count(*) as questions_last_year
    from heavy_users he
    left join user_top_tag utt on utt.user_id = he.user_id
    left join recent_questions rq on rq.asker_id = he.user_id
    left join per_question_metrics te on te.question_id = rq.question_id
    group by he.user_id, he.displayname, he.reputation, he.cohort_month, he.questions, he.answers, he.total_views,
             he.avg_nonzero_score, he.closed_posts, he.distinct_answered_questions, he.comments_last_year,
             he.gold_badges, he.silver_badges, he.bronze_badges, he.last_badge_date, he.net_votes_snapshot,
             he.last_comment_date, utt.top_tag
),
ranked_users as (
    select
        ur.*,
        row_number() over (
            order by
                coalesce(ur.answers,0) desc,
                coalesce(ur.questions,0) desc,
                coalesce(ur.reputation,0) desc
        ) as rn_activity
    from user_rollup ur
),
question_outliers as (
    select
        te.question_id,
        te.asker_id,
        te.q_score,
        te.viewcount,
        te.answercount,
        te.upvotes,
        te.downvotes,
        te.has_accepted,
        te.tagname,
        case
            when te.q_score > coalesce(ts.tag_p90_score, 0) then 1 else 0
        end as is_high_score_for_tag
    from tag_enriched te
    left join tag_stats ts on ts.tagname = te.tagname
),
final_set as (
    select
        'A' as src,
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.top_tag,
        ru.questions_last_year,
        ru.answers,
        ru.avg_q_score,
        ru.avg_q_net_votes,
        ru.accepted_qs,
        ru.avg_hours_to_first_answer,
        ru.gold_badges,
        ru.silver_badges,
        ru.bronze_badges,
        ru.net_votes_snapshot,
        ru.cohort_month::date as cohort_month,
        null::int as question_id,
        null::varchar as sample_tag,
        null::int as q_score,
        null::int as viewcount,
        null::int as answercount,
        null::int as upvotes,
        null::int as downvotes,
        null::int as has_accepted,
        null::int as is_high_score_for_tag
    from ranked_users ru
    where ru.rn_activity <= 200

    union all

    select
        'B' as src,
        qo.asker_id as user_id,
        u.displayname,
        u.reputation,
        ut.top_tag,
        null::bigint as questions_last_year,
        null::bigint as answers,
        null::numeric as avg_q_score,
        null::numeric as avg_q_net_votes,
        null::bigint as accepted_qs,
        null::numeric as avg_hours_to_first_answer,
        null::bigint as gold_badges,
        null::bigint as silver_badges,
        null::bigint as bronze_badges,
        null::bigint as net_votes_snapshot,
        null::date as cohort_month,
        qo.question_id,
        qo.tagname as sample_tag,
        qo.q_score,
        qo.viewcount,
        qo.answercount,
        qo.upvotes,
        qo.downvotes,
        qo.has_accepted,
        qo.is_high_score_for_tag
    from question_outliers qo
    left join users u on u.id = qo.asker_id
    left join user_top_tag ut on ut.user_id = qo.asker_id
    where qo.is_high_score_for_tag = 1
)
select
    fs.*,
    -- correlated subqueries for extra spice
    (
        select count(*) from postlinks pl
        where pl.postid = fs.question_id
          and pl.linktypeid = 1
    ) as linked_refs_count,
    (
        select count(*) from comments c
        where c.postid = fs.question_id
          and c.score > 0
    ) as pos_comments_on_question,
    -- elaborate predicate to categorize activity tier
    case
        when fs.src = 'A' and coalesce(fs.answers,0) >= 100 and coalesce(fs.reputation,0) >= 10000 then 'elite'
        when fs.src = 'A' and coalesce(fs.answers,0) >= 20 and coalesce(fs.reputation,0) >= 2000 then 'pro'
        when fs.src = 'A' and coalesce(fs.questions_last_year,0) >= 5 then 'engaged'
        when fs.src = 'B' and coalesce(fs.viewcount,0) >= 10000 and coalesce(fs.q_score,0) >= 10 then 'viral-question'
        when fs.src = 'B' and coalesce(fs.has_accepted,0) = 1 and coalesce(fs.answercount,0) >= 5 then 'well-answered'
        else 'other'
    end as activity_tier
from final_set fs
left join dup_links dl
  on dl.dup_question_id = fs.question_id
left join close_reasons cr
  on cr.postid = fs.question_id
order by
    src,
    coalesce(answers,0) desc nulls last,
    coalesce(questions_last_year,0) desc nulls last,
    coalesce(viewcount,0) desc nulls last,
    coalesce(q_score,0) desc nulls last;