-- {"query": "926.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3680} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.creationdate,
           u.lastaccessdate,
           coalesce(u.websiteurl, '') as websiteurl,
           extract(year from u.creationdate) as create_year,
           row_number() over (partition by coalesce(nullif(trim(lower(u.location)), ''), 'unknown') order by u.reputation desc, u.id) as rn_loc
    from users u
    where u.creationdate >= (select min(creationdate) from users) + interval '365 days'
),
top_loc_users as (
    select *
    from recent_users
    where rn_loc <= 25
),
user_badge_stats as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
q_posts as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount,
           p.commentcount,
           p.favoritecount,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select p.id,
           p.parentid as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.commentcount
    from posts p
    where p.posttypeid = 2
),
question_activity AS (
    select q.id as question_id,
           q.user_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.answercount,
           q.commentcount,
           q.favoritecount,
           q.closeddate,
           coalesce(array_length(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><'), 1), 0) as tag_count,
           case when q.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer,
           sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
           count(case when v.votetypeid = 5 then 1 end) as favorites_legacy,
           count(distinct a.id) as answers_total,
           max(case when a.score is null then null else a.score end) as max_answer_score,
           min(a.creationdate) as first_answer_time
    from q_posts q
    left join votes v on v.postid = q.id
    left join a_posts a on a.question_id = q.id
    group by q.id, q.user_id, q.creationdate, q.score, q.viewcount, q.answercount, q.commentcount, q.favoritecount, q.closeddate, q.acceptedanswerid, q.tags
),
question_quality as (
    select qa.*,
           extract(epoch from (coalesce(qa.first_answer_time, qa.creationdate) - qa.creationdate)) as seconds_to_first_answer,
           case
             when qa.score >= 10 and qa.viewcount >= 10000 then 'viral'
             when qa.score >= 5 and qa.viewcount >= 3000 then 'popular'
             when qa.score >= 1 then 'ok'
             when qa.score is null then 'unknown'
             else 'unloved'
           end as popularity_bucket
    from question_activity qa
),
user_post_rollup as (
    select
        u.id as user_id,
        count(*) filter (where p.posttypeid = 1) as questions_count,
        count(*) filter (where p.posttypeid = 2) as answers_count,
        sum(p.score) as total_post_score,
        avg(nullif(p.score,0)) as avg_nonzero_post_score,
        max(p.score) as max_post_score,
        min(p.creationdate) as first_post_date,
        max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
dupe_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as orig_post_id,
           pl.creationdate as dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
),
close_reasons as (
    select ph.postid,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as closed_at,
           max(crt.name) filter (where ph.posthistorytypeid = 10) as close_reason_name,
           max(ph.comment) filter (where ph.posthistorytypeid = 10) as close_reason_code
    from posthistory ph
    left join closeresontypes crt
      on cast(nullif(ph.comment,'') as int) = crt.id
    group by ph.postid
),
user_comment_stats as (
    select c.userid as user_id,
           count(*) as comments_count,
           avg(c.score) as avg_comment_score,
           max(c.score) as max_comment_score,
           sum(case when c.text ilike '%thanks%' or c.text ilike '%thank you%' then 1 else 0 end) as thanked_comments
    from comments c
    where c.userid is not null
    group by c.userid
),
normalized_locations as (
    select u.id as user_id,
           coalesce(nullif(trim(lower(u.location)), ''), 'unknown') as norm_location,
           case when u.location ilike '%remote%' then 1 else 0 end as is_remote_flag
    from users u
),
tag_exploded as (
    select q.user_id,
           t.tag
    from q_posts q
    cross join lateral unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as t(tag)
),
user_top_tags as (
    select user_id,
           tag,
           count(*) as tag_q_count,
           row_number() over (partition by user_id order by count(*) desc, tag) as rn_tag
    from tag_exploded
    group by user_id, tag
),
accepted_answerers as (
    select a.user_id,
           count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1 and a.posttypeid = 2
    group by a.user_id
),
activity_by_year as (
    select p.owneruserid as user_id,
           extract(year from p.creationdate)::int as year,
           count(*) as posts_in_year,
           sum(p.score) as score_in_year
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, extract(year from p.creationdate)
),
activity_trend as (
    select user_id,
           year,
           posts_in_year,
           score_in_year,
           posts_in_year - lag(posts_in_year) over (partition by user_id order by year) as posts_delta,
           score_in_year - lag(score_in_year) over (partition by user_id order by year) as score_delta
    from activity_by_year
),
sparse_users as (
    select u.id as user_id
    from users u
    where not exists (
        select 1 from posts p where p.owneruserid = u.id
    ) and exists (
        select 1 from comments c where c.userid = u.id
    )
),
combined as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        nl.norm_location,
        nl.is_remote_flag,
        coalesce(ubs.total_badges,0) as total_badges,
        coalesce(ubs.gold_badges,0) as gold_badges,
        coalesce(ubs.silver_badges,0) as silver_badges,
        coalesce(ubs.bronze_badges,0) as bronze_badges,
        coalesce(ubr.questions_count,0) as questions_count,
        coalesce(ubr.answers_count,0) as answers_count,
        coalesce(ucc.comments_count,0) as comments_count,
        coalesce(aa.accepted_answers,0) as accepted_answers,
        coalesce(ubr.total_post_score,0) as total_post_score,
        coalesce(ubr.avg_nonzero_post_score,0) as avg_nonzero_post_score,
        coalesce(ubr.max_post_score,0) as max_post_score,
        coalesce(ucc.avg_comment_score,0) as avg_comment_score,
        coalesce(ucc.max_comment_score,0) as max_comment_score,
        coalesce(ucc.thanked_comments,0) as thanked_comments,
        case when su.user_id is not null then 1 else 0 end as is_sparse_user
    from users u
    left join normalized_locations nl on nl.user_id = u.id
    left join user_badge_stats ubs on ubs.userid = u.id
    left join user_post_rollup ubr on ubr.user_id = u.id
    left join user_comment_stats ucc on ucc.user_id = u.id
    left join accepted_answerers aa on aa.user_id = u.id
    left join sparse_users su on su.user_id = u.id
),
user_quality_score as (
    select
        c.*,
        (coalesce(c.reputation,0) / nullif(1 + c.questions_count + c.answers_count + c.comments_count,0)::numeric)
            + (c.gold_badges*5 + c.silver_badges*2 + c.bronze_badges) * 0.1
            + (c.accepted_answers * 0.3)
            + (case when c.is_sparse_user = 1 then -2 else 0 end)
            + (case when c.avg_nonzero_post_score is null then 0 else least(c.avg_nonzero_post_score, 50) * 0.2 end)
            + (case when c.avg_comment_score is null then 0 else c.avg_comment_score * 0.05 end)
            as quality_score
    from combined c
),
user_top_tag_final as (
    select user_id,
           tag as top_tag
    from user_top_tags
    where rn_tag = 1
),
question_flags as (
    select qq.question_id,
           qq.user_id,
           coalesce(cr.close_reason_name, 'Open') as close_reason_name,
           case when dl.dup_post_id is not null then 1 else 0 end as is_duplicate
    from question_quality qq
    left join close_reasons cr on cr.postid = qq.question_id
    left join dupe_links dl on dl.dup_post_id = qq.question_id
),
ranked_questions as (
    select
        qq.*,
        qf.close_reason_name,
        qf.is_duplicate,
        row_number() over (partition by qq.user_id order by qq.score desc nulls last, qq.viewcount desc nulls last, qq.question_id) as rn_best_q,
        row_number() over (partition by qq.user_id order by qq.score asc nulls last, qq.viewcount asc nulls last, qq.question_id) as rn_worst_q
    from question_quality qq
    left join question_flags qf on qf.question_id = qq.question_id
),
user_question_extremes as (
    select
        user_id,
        max(case when rn_best_q = 1 then question_id end) as best_question_id,
        max(case when rn_best_q = 1 then score end) as best_question_score,
        max(case when rn_best_q = 1 then viewcount end) as best_question_views,
        max(case when rn_worst_q = 1 then question_id end) as worst_question_id,
        max(case when rn_worst_q = 1 then score end) as worst_question_score,
        max(case when rn_worst_q = 1 then viewcount end) as worst_question_views
    from ranked_questions
    group by user_id
),
active_user_filter as (
    select user_id
    from user_quality_score
    where (questions_count + answers_count) >= 5
       or total_badges >= 3
),
final_users as (
    select
        uqs.user_id,
        uqs.displayname,
        uqs.reputation,
        uqs.norm_location,
        utl.top_tag,
        uqs.quality_score,
        uqs.questions_count,
        uqs.answers_count,
        uqs.comments_count,
        uqs.accepted_answers,
        uqs.total_badges,
        uqs.gold_badges,
        uqs.silver_badges,
        uqs.bronze_badges,
        uqs.total_post_score,
        uqs.avg_nonzero_post_score,
        uqs.max_post_score,
        uqs.avg_comment_score,
        uqs.max_comment_score,
        uqs.thanked_comments,
        uqe.best_question_id,
        uqe.best_question_score,
        uqe.best_question_views,
        uqe.worst_question_id,
        uqe.worst_question_score,
        uqe.worst_question_views
    from user_quality_score uqs
    left join user_top_tag_final utl on utl.user_id = uqs.user_id
    left join user_question_extremes uqe on uqe.user_id = uqs.user_id
    where uqs.user_id in (select user_id from active_user_filter)
),
top_vs_recent as (
    select
        fu.user_id,
        fu.displayname,
        fu.reputation,
        fu.norm_location,
        fu.top_tag,
        fu.quality_score,
        case when fu.quality_score >= percentile_disc(0.95) within group (order by fu.quality_score) over () then 'top5%'
             when fu.quality_score >= percentile_disc(0.75) within group (order by fu.quality_score) over () then 'top25%'
             when fu.quality_score >= percentile_disc(0.50) within group (order by fu.quality_score) over () then 'top50%'
             else 'bottom50%' end as quality_band,
        count(*) over () as cohort_size
    from final_users fu
),
recent_activity_intensity as (
    select p.owneruserid as user_id,
           sum(case when p.creationdate >= now() - interval '30 days' then 1 else 0 end) as posts_30d,
           sum(case when p.creationdate >= now() - interval '365 days' then 1 else 0 end) as posts_365d
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
scoreboard as (
    select
        fu.*,
        tvs.quality_band,
        rai.posts_30d,
        rai.posts_365d,
        case when coalesce(rai.posts_30d,0) >= 5 then 'hot' when coalesce(rai.posts_365d,0) >= 20 then 'warm' else 'cool' end as recency_heat
    from final_users fu
    left join top_vs_recent tvs on tvs.user_id = fu.user_id
    left join recent_activity_intensity rai on rai.user_id = fu.user_id
)
select
    s.user_id,
    s.displayname,
    s.reputation,
    s.norm_location,
    coalesce(s.top_tag, '(none)') as top_tag,
    s.quality_score,
    s.quality_band,
    s.recency_heat,
    s.questions_count,
    s.answers_count,
    s.comments_count,
    s.accepted_answers,
    s.total_badges,
    s.gold_badges,
    s.silver_badges,
    s.bronze_badges,
    s.total_post_score,
    s.avg_nonzero_post_score,
    s.max_post_score,
    s.avg_comment_score,
    s.max_comment_score,
    s.thanked_comments,
    s.best_question_id,
    s.best_question_score,
    s.best_question_views,
    s.worst_question_id,
    s.worst_question_score,
    s.worst_question_views,
    at.posts_in_year,
    at.score_in_year,
    at.posts_delta,
    at.score_delta
from scoreboard s
left join lateral (
    select at2.*
    from activity_trend at2
    where at2.user_id = s.user_id
    order by at2.year desc
    limit 1
) at on true
where (
        s.quality_band in ('top5%','top25%')
        or (s.recency_heat = 'hot' and s.answers_count >= 10)
      )
and not exists (
    select 1
    from ranked_questions rq
    where rq.user_id = s.user_id
      and rq.is_duplicate = 1
      and coalesce(rq.score,0) < 0
)
order by s.quality_band, s.recency_heat desc, s.quality_score desc, s.user_id
limit 500;