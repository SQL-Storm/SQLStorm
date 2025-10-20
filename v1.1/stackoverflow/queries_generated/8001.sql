-- {"query": "8001.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2719} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location, ''), ',', 1)), ''), 'Unknown') as country_guess
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
question_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.acceptedanswerid,
           p.answercount
    from posts p
    where p.posttypeid = 1
),
answer_posts as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid,
           a.creationdate,
           a.score
    from posts a
    where a.posttypeid = 2
),
comment_stats as (
    select c.postid,
           count(*) as comment_count,
           sum(case when c.score > 0 then 1 else 0 end) as positive_comments,
           max(c.creationdate) as last_comment_at
    from comments c
    group by c.postid
),
tag_expansion as (
    select q.id as question_id,
           unnest(string_to_array(substring(coalesce(q.tags, ''), 2, greatest(length(coalesce(q.tags,'')) - 2, 0)), '><')) as tagname
    from question_posts q
),
top_tags as (
    select te.tagname,
           count(*) as q_cnt,
           dense_rank() over (order by count(*) desc, tagname) as rnk
    from tag_expansion te
    group by te.tagname
),
top10_tags as (
    select tagname from top_tags where rnk <= 10
),
user_badge_agg as (
    select b.userid,
           count(*) filter (where b.class = 1) as gold_cnt,
           count(*) filter (where b.class = 2) as silver_cnt,
           count(*) filter (where b.class = 3) as bronze_cnt,
           min(b.date) as first_badge_at,
           max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
q_vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites
    from votes v
    group by v.postid
),
dupe_links as (
    select pl.postid as dup_question_id,
           pl.relatedpostid as original_question_id,
           pl.creationdate as dupe_marked_at
    from postlinks pl
    where pl.linktypeid = 3
),
activity_window as (
    select q.id as question_id,
           q.owneruserid,
           q.creationdate,
           q.score,
           q.viewcount,
           q.acceptedanswerid,
           q.answercount,
           row_number() over (partition by q.owneruserid order by q.creationdate desc) as rn_user_recent,
           ntile(4) over (order by q.viewcount desc nulls last) as view_quartile,
           percentile_disc(0.5) within group (order by q.score) over () as global_median_score
    from question_posts q
),
accepted_answer_latency as (
    select q.id as question_id,
           a.id as answer_id,
           a.creationdate - q.creationdate as time_to_accept
    from question_posts q
    join posts a on a.id = q.acceptedanswerid
),
answerer_stats as (
    select ap.question_id,
           count(*) as answers_total,
           avg(ap.score) as avg_answer_score,
           max(ap.score) as max_answer_score,
           count(*) filter (where ap.score > 0) as positive_answers
    from answer_posts ap
    group by ap.question_id
),
edits_agg as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (4,5,6)) as edit_count,
           min(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as first_edit_at,
           max(ph.creationdate) filter (where ph.posthistorytypeid in (4,5,6)) as last_edit_at,
           count(*) filter (where ph.posthistorytypeid in (10,35)) as close_or_migrate_cnt,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
q_tag_focus as (
    select te.question_id,
           count(*) as tag_count,
           sum(case when te.tagname in (select tagname from top10_tags) then 1 else 0 end) as in_top10
    from tag_expansion te
    group by te.question_id
),
recent_hot_candidates as (
    select q.id as question_id,
           max(case when ph.posthistorytypeid = 52 then 1 else 0 end) as ever_hot,
           max(case when ph.posthistorytypeid = 53 then 1 else 0 end) as removed_hot
    from question_posts q
    left join posthistory ph on ph.postid = q.id
    group by q.id
),
owner_enriched as (
    select q.id as question_id,
           u.id as owner_id,
           u.displayname as owner_name,
           u.reputation as owner_rep,
           ru.country_guess,
           ub.gold_cnt,
           ub.silver_cnt,
           ub.bronze_cnt,
           coalesce(ub.last_badge_at, u.creationdate) as last_badge_at
    from question_posts q
    left join users u on u.id = q.owneruserid
    left join recent_users ru on ru.user_id = u.id
    left join user_badge_agg ub on ub.userid = u.id
),
rankings as (
    select q.id as question_id,
           q.viewcount,
           q.score,
           qa.upvotes,
           qa.downvotes,
           row_number() over (order by coalesce(qa.upvotes,0) - coalesce(qa.downvotes,0) desc, q.score desc, q.viewcount desc) as rn_net_votes,
           row_number() over (order by q.viewcount desc nulls last) as rn_views,
           dense_rank() over (order by q.score desc nulls last) as dr_score
    from question_posts q
    left join q_vote_agg qa on qa.postid = q.id
),
stringy as (
    select q.id as question_id,
           lower(regexp_replace(coalesce(q.title,''), '\s+', ' ', 'g')) as norm_title,
           length(coalesce(q.title,'')) as title_len,
           position(' how ' in lower(' ' || coalesce(q.title,'') || ' ')) as has_how_word,
           case when coalesce(q.tags,'') like '%<sql>%' then 1 else 0 end as is_sql_tagged
    from question_posts q
)
select
    q.id as question_id,
    oe.owner_id,
    coalesce(oe.owner_name, q.owneruserid::varchar) as owner_name,
    oe.owner_rep,
    oe.country_guess,
    q.creationdate as question_created_at,
    q.title,
    se.norm_title,
    se.title_len,
    se.has_how_word,
    se.is_sql_tagged,
    q.tags,
    qa.upvotes,
    qa.downvotes,
    qa.favorites,
    q.score,
    q.viewcount,
    cs.comment_count,
    cs.positive_comments,
    cs.last_comment_at,
    aa.answers_total,
    aa.avg_answer_score,
    aa.max_answer_score,
    aa.positive_answers,
    al.time_to_accept,
    ea.edit_count,
    ea.first_edit_at,
    ea.last_edit_at,
    ea.close_or_migrate_cnt,
    ea.last_close_reason_id,
    dl.original_question_id,
    dl.dupe_marked_at,
    rf.ever_hot,
    rf.removed_hot,
    qt.tag_count,
    qt.in_top10,
    aw.view_quartile,
    aw.global_median_score,
    r.rn_net_votes,
    r.rn_views,
    r.dr_score,
    -- complicated predicate-derived flags
    case
        when q.acceptedanswerid is not null and coalesce(aa.answers_total,0) > 0 then 1
        when q.acceptedanswerid is null and coalesce(aa.answers_total,0) = 0 then 0
        else null
    end as accepted_given_answers_flag,
    case
        when coalesce(qa.upvotes,0) >= 10 and coalesce(cs.comment_count,0) >= 5 then 'high engagement'
        when coalesce(qa.upvotes,0) - coalesce(qa.downvotes,0) < 0 then 'controversial'
        else 'normal'
    end as engagement_bucket,
    -- correlated subqueries
    (
        select count(*)
        from answer_posts ap2
        where ap2.question_id = q.id
          and ap2.creationdate <= q.creationdate + interval '1 day'
    ) as answers_in_24h,
    (
        select avg(a2.score)
        from posts a2
        where a2.posttypeid = 2
          and a2.parentid = q.id
          and a2.creationdate >= q.creationdate
    ) as avg_answer_score_after_post,
    -- set operator simulated via union all with distinct count in scalar subquery
    (
        select count(distinct x.uid)
        from (
            select v.userid as uid from votes v where v.postid = q.id and v.userid is not null
            union all
            select c.userid as uid from comments c where c.postid = q.id and c.userid is not null
        ) x
    ) as distinct_participants,
    -- null logic and expressions
    greatest(
        coalesce(q.viewcount, 0),
        coalesce(qa.upvotes, 0) * 50 + coalesce(qa.downvotes, 0) * 30 + coalesce(qa.favorites, 0) * 80
    ) as rough_popularity_score,
    coalesce(oe.gold_cnt,0) + coalesce(oe.silver_cnt,0) + coalesce(oe.bronze_cnt,0) as total_badges_owner,
    -- sample window over final result
    avg(q.score) over (partition by case when se.is_sql_tagged = 1 then 'sql' else 'other' end) as avg_score_by_sql_tag
from question_posts q
left join q_vote_agg qa on qa.postid = q.id
left join comment_stats cs on cs.postid = q.id
left join answerer_stats aa on aa.question_id = q.id
left join accepted_answer_latency al on al.question_id = q.id
left join edits_agg ea on ea.postid = q.id
left join dupe_links dl on dl.dup_question_id = q.id
left join recent_hot_candidates rf on rf.question_id = q.id
left join q_tag_focus qt on qt.question_id = q.id
left join activity_window aw on aw.question_id = q.id
left join owner_enriched oe on oe.question_id = q.id
left join rankings r on r.question_id = q.id
left join stringy se on se.question_id = q.id
where
    -- complicated filter combining multiple aspects
    (
        (coalesce(qa.upvotes,0) - coalesce(qa.downvotes,0)) >= -2
        or (ea.edit_count is not null and ea.edit_count >= 1)
        or rf.ever_hot = 1
    )
    and (qt.tag_count is null or qt.tag_count between 1 and 7)
    and (
        q.creationdate >= (select max(creationdate) - interval '180 days' from posts where posttypeid = 1)
        or oe.owner_rep >= (select percentile_disc(0.9) within group (order by reputation) from users)
    )
    and not exists (
        select 1
        from posthistory phx
        where phx.postid = q.id
          and phx.posthistorytypeid in (12) -- deleted
    )
order by
    rough_popularity_score desc,
    coalesce(qa.upvotes,0) - coalesce(qa.downvotes,0) desc,
    q.viewcount desc
limit 500;