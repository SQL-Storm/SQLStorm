-- {"query": "414.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2979} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl_clean
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
question_posts as (
    select p.*
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select p.*
    from posts p
    where p.posttypeid = 2
),
user_activity as (
    select
        ru.user_id,
        count(distinct qp.id) as questions_count,
        count(distinct ap.id) as answers_count,
        sum(coalesce(case when qp.owneruserid = ru.user_id then qp.score end, 0)) as q_score_sum,
        sum(coalesce(case when ap.owneruserid = ru.user_id then ap.score end, 0)) as a_score_sum,
        sum(coalesce(qp.viewcount, 0)) filter (where qp.owneruserid = ru.user_id) as q_views_sum,
        max(greatest(coalesce(qp.lastactivitydate, qp.creationdate), coalesce(ap.lastactivitydate, ap.creationdate))) as last_post_activity
    from recent_users ru
    left join question_posts qp on qp.owneruserid = ru.user_id
    left join answer_posts ap on ap.owneruserid = ru.user_id
    group by ru.user_id
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounties_awarded
    from votes v
    where v.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from votes)
    group by v.postid
),
post_enriched as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.parentid,
        p.acceptedanswerid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        va.upvotes,
        va.downvotes,
        va.bounties_awarded,
        coalesce(va.upvotes,0) - coalesce(va.downvotes,0) as net_votes
    from posts p
    left join votes_agg va on va.postid = p.id
),
comments_agg as (
    select
        c.postid,
        count(*) as comment_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
dup_links as (
    select pl.postid, count(*) filter (where pl.linktypeid = 3) as duplicate_count
    from postlinks pl
    group by pl.postid
),
close_events as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as closed_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopened_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen
    from posthistory ph
    group by ph.postid
),
accepted_answerers as (
    select
        q.owneruserid as question_owner_id,
        a.owneruserid as answer_owner_id,
        count(*) as accepted_answers_for_owner
    from posts q
    join posts a on a.id = q.acceptedanswerid and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.owneruserid, a.owneruserid
),
user_badges as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_exploded as (
    select
        p.id as post_id,
        unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tag
    from posts p
    where p.posttypeid = 1 and p.tags is not null and length(p.tags) > 2
),
tag_popularity as (
    select
        te.tag,
        count(*) as tag_question_count,
        approx_percentile(count(*)) over () as approx_global // placeholder for engines that support
    from tag_exploded te
    group by te.tag
),
user_tag_mix as (
    select
        q.owneruserid as user_id,
        te.tag,
        count(*) as tag_questions_by_user
    from tag_exploded te
    join posts q on q.id = te.post_id
    group by q.owneruserid, te.tag
),
post_quality as (
    select
        pe.id as post_id,
        pe.posttypeid,
        pe.owneruserid,
        pe.creationdate,
        pe.title,
        pe.score,
        coalesce(pe.net_votes,0) as net_votes,
        coalesce(ca.comment_count,0) as comment_count,
        coalesce(ca.avg_comment_score,0) as avg_comment_score,
        coalesce(du.duplicate_count,0) as duplicate_count,
        coalesce(ce.closed_events,0) as closed_events,
        coalesce(ce.reopened_events,0) as reopened_events,
        case
            when pe.posttypeid = 1 and pe.acceptedanswerid is not null then 1
            else 0
        end as has_accepted,
        case
            when pe.posttypeid = 2 and exists (
                select 1 from posts q
                where q.posttypeid = 1 and q.acceptedanswerid = pe.id
            ) then 1 else 0 end as is_accepted_answer
    from post_enriched pe
    left join comments_agg ca on ca.postid = pe.id
    left join dup_links du on du.postid = pe.id
    left join close_events ce on ce.postid = pe.id
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created,
        ru.location,
        ru.websiteurl_clean,
        ua.questions_count,
        ua.answers_count,
        ua.q_score_sum,
        ua.a_score_sum,
        ua.q_views_sum,
        ua.last_post_activity,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        ub.total_badges,
        ub.last_badge_date
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_badges ub on ub.userid = ru.user_id
),
user_post_metrics as (
    select
        pq.owneruserid as user_id,
        count(*) filter (where pq.posttypeid = 1) as total_questions,
        count(*) filter (where pq.posttypeid = 2) as total_answers,
        avg(nullif(pq.score,0)) as avg_nonzero_score,
        percentile_cont(0.5) within group (order by pq.score) as median_score,
        stddev_pop(coalesce(pq.score,0)) as score_stddev,
        sum(case when pq.is_accepted_answer = 1 then 1 else 0 end) as accepted_answers_made,
        sum(case when pq.has_accepted = 1 then 1 else 0 end) as questions_with_accepted,
        sum(pq.net_votes) as sum_net_votes,
        sum(pq.comment_count) as sum_comment_count,
        max(pq.creationdate) as last_post_created
    from post_quality pq
    group by pq.owneruserid
),
accepted_cross as (
    select
        aa.answer_owner_id as user_id,
        sum(aa.accepted_answers_for_owner) as accepted_by_others
    from accepted_answerers aa
    group by aa.answer_owner_id
),
user_tag_prefs as (
    select
        utm.user_id,
        jsonb_agg(jsonb_build_object(
            'tag', utm.tag,
            'questions', utm.tag_questions_by_user
        ) order by utm.tag_questions_by_user desc) filter (where utm.tag is not null) as tag_mix
    from user_tag_mix utm
    group by utm.user_id
),
final_scored as (
    select
        ur.user_id,
        ur.displayname,
        ur.reputation,
        ur.user_created,
        ur.location,
        ur.websiteurl_clean,
        coalesce(upm.total_questions,0) as total_questions,
        coalesce(upm.total_answers,0) as total_answers,
        coalesce(upm.avg_nonzero_score,0) as avg_nonzero_score,
        coalesce(upm.median_score,0) as median_score,
        coalesce(upm.score_stddev,0) as score_stddev,
        coalesce(upm.accepted_answers_made,0) as accepted_answers_made,
        coalesce(upm.questions_with_accepted,0) as questions_with_accepted,
        coalesce(ac.accepted_by_others,0) as accepted_by_others,
        coalesce(ur.q_score_sum,0) + coalesce(ur.a_score_sum,0) as total_post_score,
        coalesce(ur.q_views_sum,0) as total_question_views,
        ur.gold_badges, ur.silver_badges, ur.bronze_badges, ur.total_badges,
        ur.last_badge_date,
        ur.last_post_activity,
        coalesce(utp.tag_mix, '[]'::jsonb) as tag_mix,
        -- composite score with several weighted components and null-safe logic
        (
            0.30 * ln(1 + greatest(coalesce(upm.total_questions,0) + coalesce(upm.total_answers,0), 0)) +
            0.20 * ln(1 + greatest(coalesce(upm.accepted_answers_made,0) + coalesce(ac.accepted_by_others,0), 0)) +
            0.25 * ln(1 + greatest(coalesce(ur.q_score_sum,0) + coalesce(ur.a_score_sum,0), 0)) +
            0.10 * ln(1 + greatest(coalesce(ur.q_views_sum,0), 0)) +
            0.10 * ln(1 + greatest(coalesce(ur.total_badges,0)*2 + coalesce(ur.gold_badges,0)*3, 0)) +
            0.05 * greatest(0, coalesce(upm.avg_nonzero_score,0))
        ) as activity_score
    from user_rollup ur
    left join user_post_metrics upm on upm.owneruserid = ur.user_id
    left join accepted_cross ac on ac.user_id = ur.user_id
    left join user_tag_prefs utp on utp.user_id = ur.user_id
),
ranked as (
    select
        fs.*,
        row_number() over (order by fs.activity_score desc, fs.total_post_score desc, fs.reputation desc) as rn,
        rank() over (order by fs.activity_score desc) as rnk,
        dense_rank() over (partition by (case when fs.location is null or trim(fs.location) = '' then 'Unknown' else lower(fs.location) end) order by fs.activity_score desc) as location_rank,
        percentile_disc(0.9) within group (order by fs.activity_score) over () as p90_score
    from final_scored fs
),
top_and_neighbors as (
    select *
    from ranked r
    where r.rn <= 100
    union all
    select r.*
    from ranked r
    join (
        select rnk
        from ranked
        where rn in (101, 500, 1000)
    ) piv on r.rnk between piv.rnk - 1 and piv.rnk + 1
)
select
    t.user_id,
    t.displayname,
    t.reputation,
    t.user_created,
    coalesce(nullif(trim(t.location), ''), 'Unknown') as location,
    t.websiteurl_clean,
    t.total_questions,
    t.total_answers,
    t.accepted_answers_made,
    t.accepted_by_others,
    t.questions_with_accepted,
    t.total_post_score,
    t.total_question_views,
    t.gold_badges, t.silver_badges, t.bronze_badges, t.total_badges,
    t.last_badge_date,
    t.last_post_activity,
    t.activity_score,
    t.rn,
    t.rnk,
    t.location_rank,
    t.p90_score,
    case when t.activity_score >= t.p90_score then 'Top10%' else 'BelowTop10%' end as score_bucket,
    -- string expression: short handle
    lower(regexp_replace(coalesce(t.displayname, 'user_'||t.user_id::text), '[^a-zA-Z0-9]+', '_', 'g')) as handle_slug,
    -- show top 3 tags by questions as a comma list
    (
        select string_agg(elem->>'tag', ', ' order by (elem->>'questions')::int desc)
        from jsonb_array_elements(t.tag_mix) elem
        limit 3
    ) as top_tags
from top_and_neighbors t
order by t.rn, t.user_id;