-- {"query": "20.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3948} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
        dense_rank() over (order by u.creationdate desc) as recency_rank
    from users u
),
user_badge_agg as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_core as (
    select
        p.id as question_id,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.answercount,
        p.favoritecount,
        p.closeddate,
        p.communityowneddate
    from posts p
    where p.posttypeid = 1
),
answer_core as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answerer_id,
        a.creationdate as answer_creation,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
q_activity as (
    select
        q.question_id,
        count(distinct c.id) as comment_count,
        count(distinct v.id) filter (where v.votetypeid = 2) as upvotes,
        count(distinct v.id) filter (where v.votetypeid = 3) as downvotes,
        count(distinct pl.id) filter (where pl.linktypeid = 3) as duplicate_links
    from question_core q
    left join comments c on c.postid = q.question_id
    left join votes v on v.postid = q.question_id
    left join postlinks pl on pl.postid = q.question_id
    group by q.question_id
),
first_answer as (
    select distinct on (a.question_id)
        a.question_id,
        a.answer_id,
        a.answerer_id,
        a.answer_creation,
        a.answer_score
    from answer_core a
    order by a.question_id, a.answer_creation asc, a.answer_id asc
),
accepted_answer as (
    select
        q.question_id,
        q.owneruserid as asker_id,
        q.creationdate as question_creation,
        q.score as question_score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.favoritecount,
        q.closeddate,
        q.communityowneddate,
        p2.id as accepted_answer_id,
        p2.owneruserid as accepted_answerer_id,
        p2.creationdate as accepted_creation,
        p2.score as accepted_score
    from question_core q
    left join posts p1 on p1.id = q.question_id
    left join posts p2 on p2.id = p1.acceptedanswerid
),
q_ph_events as (
    select
        ph.postid as question_id,
        sum(case when ph.posthistorytypeid in (10,35) then 1 else 0 end) as close_or_migrate_events,
        max(case when ph.posthistorytypeid = 10 then try_cast(nullif(ph.comment, '') as int) end) as last_close_reason_id,
        min(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as first_moderation_date,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36)) as last_moderation_date
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    group by ph.postid
),
answerer_stats as (
    select
        a.answerer_id as user_id,
        count(*) as answers_count,
        avg(a.answer_score)::numeric(18,4) as avg_answer_score,
        max(a.answer_score) as max_answer_score,
        min(a.answer_score) as min_answer_score,
        percentile_cont(0.5) within group (order by a.answer_score) as median_answer_score
    from answer_core a
    group by a.answerer_id
),
tag_expansion as (
    select
        q.question_id,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from question_core q
    where q.tags is not null and length(q.tags) > 2
),
tag_popularity as (
    select
        t.tagname,
        t.count as tag_global_count
    from tags t
),
q_tag_metrics as (
    select
        te.question_id,
        count(*) as tag_count,
        sum(tp.tag_global_count) as tag_popularity_sum,
        avg(tp.tag_global_count)::numeric(18,2) as tag_popularity_avg,
        max(tp.tag_global_count) as tag_popularity_max
    from tag_expansion te
    left join tag_popularity tp on lower(tp.tagname) = lower(te.tag)
    group by te.question_id
),
user_quality as (
    select
        u.id as user_id,
        u.reputation,
        coalesce(ub.total_badges, 0) as total_badges,
        coalesce(ub.gold_badges, 0) as gold_badges,
        coalesce(ub.silver_badges, 0) as silver_badges,
        coalesce(ub.bronze_badges, 0) as bronze_badges,
        coalesce(qa.answers_count, 0) as total_answers,
        coalesce(qa.avg_answer_score, 0)::numeric(18,4) as avg_answer_score,
        case
            when coalesce(ub.total_badges,0) = 0 then 0
            else (coalesce(ub.gold_badges,0) * 5 + coalesce(ub.silver_badges,0) * 3 + coalesce(ub.bronze_badges,0) * 1)
        end as badge_weighted_score
    from users u
    left join user_badge_agg ub on ub.userid = u.id
    left join answerer_stats qa on qa.user_id = u.id
),
question_enriched as (
    select
        q.question_id,
        q.owneruserid as asker_id,
        q.creationdate,
        q.score,
        q.viewcount,
        q.title,
        q.tags,
        q.answercount,
        q.favoritecount,
        q.closeddate,
        q.communityowneddate,
        qa.comment_count,
        qa.upvotes,
        qa.downvotes,
        qa.duplicate_links,
        coalesce(qtm.tag_count, 0) as tag_count,
        coalesce(qtm.tag_popularity_sum, 0) as tag_popularity_sum,
        qtm.tag_popularity_avg,
        qtm.tag_popularity_max,
        ph.close_or_migrate_events,
        ph.last_close_reason_id,
        ph.first_moderation_date,
        ph.last_moderation_date
    from question_core q
    left join q_activity qa on qa.question_id = q.question_id
    left join q_tag_metrics qtm on qtm.question_id = q.question_id
    left join q_ph_events ph on ph.question_id = q.question_id
),
time_buckets as (
    select
        qe.*,
        date_trunc('month', qe.creationdate) as month_bucket,
        case
            when qe.score >= 10 then 'very_high'
            when qe.score >= 5 then 'high'
            when qe.score >= 1 then 'medium'
            when qe.score >= -2 then 'low'
            else 'very_low'
        end as score_band
    from question_enriched qe
),
cross_user_question as (
    select
        tb.*,
        uqa.reputation as asker_reputation,
        uqa.total_badges as asker_total_badges,
        uqa.badge_weighted_score as asker_badge_weight,
        fa.answer_id as first_answer_id,
        fa.answerer_id as first_answerer_id,
        fa.answer_creation as first_answer_time,
        ex.accepted_answer_id,
        ex.accepted_answerer_id,
        ex.accepted_creation
    from time_buckets tb
    left join user_quality uqa on uqa.user_id = tb.asker_id
    left join first_answer fa on fa.question_id = tb.question_id
    left join accepted_answer ex on ex.question_id = tb.question_id
),
answerer_quality as (
    select
        cuq.question_id,
        uq.user_id,
        uq.reputation,
        uq.total_badges,
        uq.badge_weighted_score,
        uq.total_answers,
        uq.avg_answer_score
    from cross_user_question cuq
    left join user_quality uq on uq.user_id = coalesce(cuq.accepted_answerer_id, cuq.first_answerer_id)
),
bench_base as (
    select
        cuq.question_id,
        cuq.month_bucket,
        cuq.score_band,
        cuq.score,
        cuq.viewcount,
        cuq.answercount,
        cuq.favoritecount,
        cuq.comment_count,
        cuq.upvotes,
        cuq.downvotes,
        cuq.duplicate_links,
        cuq.tag_count,
        cuq.tag_popularity_sum,
        cuq.tag_popularity_avg,
        cuq.tag_popularity_max,
        cuq.close_or_migrate_events,
        cuq.last_close_reason_id,
        cuq.first_moderation_date,
        cuq.last_moderation_date,
        cuq.asker_id,
        cuq.asker_reputation,
        cuq.asker_total_badges,
        cuq.asker_badge_weight,
        cuq.first_answer_time,
        cuq.accepted_creation,
        aq.user_id as responder_id,
        aq.reputation as responder_reputation,
        aq.total_badges as responder_badges,
        aq.badge_weighted_score as responder_badge_weight,
        aq.total_answers as responder_total_answers,
        aq.avg_answer_score as responder_avg_answer_score,
        extract(epoch from (coalesce(cuq.accepted_creation, cuq.first_answer_time) - cuq.creationdate)) as seconds_to_first_or_accept,
        case when cuq.accepted_answer_id is not null then 1 else 0 end as has_accepted
    from cross_user_question cuq
    left join answerer_quality aq on aq.question_id = cuq.question_id
),
scored as (
    select
        bb.*,
        /* complex composite score mixing engagement, quality, and difficulty with null-safe logic */
        (
            coalesce(bb.score, 0) * 3
            + coalesce(bb.upvotes, 0) * 2
            - coalesce(bb.downvotes, 0) * 2
            + ln(1 + coalesce(bb.viewcount, 0))
            + coalesce(bb.favoritecount, 0) * 1.5
            + coalesce(bb.comment_count, 0) * 0.75
            + case when coalesce(bb.seconds_to_first_or_accept, 0) > 0 then greatest(0, 12 - least(12, bb.seconds_to_first_or_accept/3600.0)) else 0 end
            + coalesce(bb.tag_popularity_avg, 0) * 0.0005
            - coalesce(bb.duplicate_links, 0) * 5
            - case when bb.has_accepted = 0 and bb.answercount > 0 then 2 else 0 end
        )::numeric(18,4) as composite_engagement_score
    from bench_base bb
),
monthly_stats as (
    select
        month_bucket,
        count(*) as questions_in_month,
        avg(score)::numeric(18,4) as avg_score,
        percentile_cont(0.5) within group (order by score) as median_score,
        avg(viewcount)::numeric(18,2) as avg_views,
        avg(tag_count)::numeric(18,2) as avg_tag_count,
        avg(coalesce(seconds_to_first_or_accept,0))::numeric(18,2) as avg_secs_to_first_or_accept
    from bench_base
    group by month_bucket
),
ranked as (
    select
        s.*,
        ms.questions_in_month,
        ms.avg_score as month_avg_score,
        row_number() over (partition by s.month_bucket order by s.composite_engagement_score desc nulls last) as rn_month,
        dense_rank() over (order by s.composite_engagement_score desc nulls last) as rn_global,
        ntile(10) over (order by s.composite_engagement_score desc nulls last) as decile_global
    from scored s
    left join monthly_stats ms using (month_bucket)
),
dupe_clusters as (
    select
        q.question_id,
        array_agg(distinct pl.relatedpostid order by pl.relatedpostid) filter (where pl.linktypeid = 3) as duplicate_of_ids
    from question_core q
    left join postlinks pl on pl.postid = q.question_id
    group by q.question_id
),
final_set as (
    select
        r.question_id,
        r.month_bucket,
        r.score_band,
        r.composite_engagement_score,
        r.rn_month,
        r.rn_global,
        r.decile_global,
        r.score,
        r.viewcount,
        r.answercount,
        r.favoritecount,
        r.comment_count,
        r.upvotes,
        r.downvotes,
        r.duplicate_links,
        r.tag_count,
        r.tag_popularity_sum,
        r.tag_popularity_avg,
        r.tag_popularity_max,
        r.close_or_migrate_events,
        r.last_close_reason_id,
        r.first_moderation_date,
        r.last_moderation_date,
        r.asker_id,
        r.asker_reputation,
        r.asker_total_badges,
        r.asker_badge_weight,
        r.seconds_to_first_or_accept,
        r.has_accepted,
        r.responder_id,
        r.responder_reputation,
        r.responder_badges,
        r.responder_badge_weight,
        r.responder_total_answers,
        r.responder_avg_answer_score,
        dc.duplicate_of_ids
    from ranked r
    left join dupe_clusters dc on dc.question_id = r.question_id
),
-- introduce set operations to stress planner
blend as (
    select * from final_set where score_band in ('very_high','high')
    union all
    select * from final_set where composite_engagement_score > (select avg(composite_engagement_score) from final_set)
    except
    select * from final_set where duplicate_links > 0 and has_accepted = 0
)
select
    fs.question_id,
    coalesce(fs.month_bucket, date_trunc('month', now())) as month_bucket,
    fs.score_band,
    fs.composite_engagement_score,
    fs.rn_month,
    fs.rn_global,
    fs.decile_global,
    fs.score,
    fs.viewcount,
    fs.answercount,
    fs.favoritecount,
    fs.comment_count,
    fs.upvotes,
    fs.downvotes,
    fs.duplicate_links,
    fs.tag_count,
    fs.tag_popularity_sum,
    fs.tag_popularity_avg,
    fs.tag_popularity_max,
    fs.close_or_migrate_events,
    fs.last_close_reason_id,
    fs.first_moderation_date,
    fs.last_moderation_date,
    fs.asker_id,
    fs.asker_reputation,
    fs.asker_total_badges,
    fs.asker_badge_weight,
    fs.seconds_to_first_or_accept,
    fs.has_accepted,
    fs.responder_id,
    fs.responder_reputation,
    fs.responder_badges,
    fs.responder_badge_weight,
    fs.responder_total_answers,
    fs.responder_avg_answer_score,
    coalesce(array_length(fs.duplicate_of_ids,1),0) as duplicate_of_count,
    -- complicated predicate-driven label
    case
        when fs.has_accepted = 1 and fs.seconds_to_first_or_accept <= 3600 then 'fast_resolved'
        when fs.has_accepted = 1 then 'resolved'
        when fs.answercount > 0 and fs.has_accepted = 0 then 'answered_no_accept'
        when fs.answercount = 0 and fs.comment_count > 0 then 'discussed'
        else 'unanswered'
    end as resolution_label,
    -- string expression from title with null/length guards
    substring(coalesce(p.title, 'n/a') from 1 for least(80, greatest(0, length(coalesce(p.title, ''))))) as title_snippet,
    -- correlated subquery: top commenter count per question
    (
        select max(cnt) from (
            select count(*) as cnt
            from comments c2
            where c2.postid = fs.question_id
            group by c2.userid
        ) s
    ) as max_comments_by_single_user,
    -- outer join info: close reason name
    crt.name as last_close_reason_name,
    -- boolean-esque complex predicate
    (fs.upvotes - fs.downvotes >= 0 and fs.viewcount > 0) as net_positive_visible
from blend b
join final_set fs on fs.question_id = b.question_id
left join posts p on p.id = fs.question_id
left join closereasontypes crt on crt.id = fs.last_close_reason_id
where
    -- complex filter mixing null logic and expressions
    coalesce(fs.viewcount, 0) >= 0
    and (
        fs.composite_engagement_score is null
        or fs.composite_engagement_score >= (
            select avg(coalesce(composite_engagement_score, 0)) + stddev_pop(coalesce(composite_engagement_score, 0))
            from final_set
        )
        or (fs.tag_count >= 3 and fs.score_band in ('very_high','high','medium'))
    )
order by
    fs.month_bucket desc nulls last,
    fs.composite_engagement_score desc nulls last,
    fs.viewcount desc nulls last
limit 500;