-- {"query": "135.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2736}
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as website_norm,
           case when lower(u.location) like '%remote%' then 1 else 0 end as is_remote
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
q_posts as (
    select p.id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           p.answercount,
           p.favoritecount,
           p.commentcount,
           p.title,
           p.tags,
           p.closeddate,
           p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid as user_id,
           a.creationdate,
           a.score
    from posts a
    where a.posttypeid = 2
),
tag_expanded as (
    select q.id as question_id,
           unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag
    from q_posts q
    where q.tags is not null and length(q.tags) > 2
),
hotness as (
    select q.id as question_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.answercount,
           coalesce(q.favoritecount, 0) as favorites,
           coalesce(q.commentcount, 0) as comments,
           greatest(1, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.creationdate)) / 3600.0) as hours_since,
           (q.score * 3 + coalesce(q.viewcount,0) * 0.01 + coalesce(q.answercount,0) * 5 + coalesce(q.favoritecount,0) * 1.5 + coalesce(q.commentcount,0) * 1) /
           greatest(1, extract(epoch from (cast('2024-10-01 12:34:56' as timestamp) - q.creationdate)) / 3600.0) as hot_score
    from q_posts q
),
first_answer as (
    select a.question_id,
           min(a.creationdate) as first_answer_time,
           count(*) as answer_count_total
    from a_posts a
    group by a.question_id
),
accepted_answerer as (
    select q.id as question_id,
           pa.owneruserid as accepted_user_id,
           pa.score as accepted_answer_score
    from q_posts q
    left join posts pa on pa.id = q.acceptedanswerid
),
user_agg as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(p.score) as total_post_score,
           sum(case when p.posttypeid = 2 then p.score else 0 end) as total_answer_score,
           avg(nullif(p.score,0)) filter (where p.score is not null) as avg_nonzero_score,
           min(p.creationdate) as first_post_date,
           max(p.creationdate) as last_post_date
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
vote_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    group by v.postid
),
close_events as (
    select ph.postid,
           min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_closed,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened,
           max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) else null end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select pl.postid as dup_post_id,
           count(*) filter (where pl.linktypeid = 3) as dup_count,
           count(*) filter (where pl.linktypeid = 1) as link_count
    from postlinks pl
    group by pl.postid
),
tag_stats as (
    select te.tag,
           count(distinct te.question_id) as q_with_tag,
           sum(h.hot_score) as hotness_sum,
           avg(h.hot_score) as hotness_avg,
           stddev_pop(h.hot_score) as hotness_std
    from tag_expanded te
    join hotness h on h.question_id = te.question_id
    group by te.tag
),
user_recent_activity as (
    select ru.user_id,
           count(*) filter (where p.posttypeid = 1 and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as recent_q,
           count(*) filter (where p.posttypeid = 2 and p.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '30 days') as recent_a,
           sum(coalesce(va.upvotes,0) - coalesce(va.downvotes,0)) as recent_vote_delta
    from recent_users ru
    left join posts p on p.owneruserid = ru.user_id
    left join vote_agg va on va.postid = p.id
    group by ru.user_id
),
question_metrics as (
    select q.id as question_id,
           q.user_id,
           q.creationdate,
           q.title,
           q.tags,
           h.hot_score,
           fa.first_answer_time,
           extract(epoch from (fa.first_answer_time - q.creationdate))/60.0 as minutes_to_first_answer,
           coalesce(fa.answer_count_total, 0) as total_answers,
           coalesce(va.upvotes,0) as upvotes,
           coalesce(va.downvotes,0) as downvotes,
           coalesce(va.bounty_started,0) as bounty_started,
           coalesce(va.bounty_awarded,0) as bounty_awarded,
           ce.first_closed,
           ce.last_reopened,
           ce.last_close_reason_id,
           dl.dup_count,
           dl.link_count
    from q_posts q
    left join hotness h on h.question_id = q.id
    left join first_answer fa on fa.question_id = q.id
    left join vote_agg va on va.postid = q.id
    left join close_events ce on ce.postid = q.id
    left join dup_links dl on dl.dup_post_id = q.id
),
ranked_questions as (
    select qm.question_id,
           qm.user_id,
           qm.creationdate,
           qm.title,
           qm.tags,
           qm.hot_score,
           qm.first_answer_time,
           qm.minutes_to_first_answer,
           qm.total_answers,
           qm.upvotes,
           qm.downvotes,
           qm.bounty_started,
           qm.bounty_awarded,
           qm.first_closed,
           qm.last_reopened,
           qm.last_close_reason_id,
           qm.dup_count,
           qm.link_count,
           row_number() over (partition by qm.user_id order by qm.hot_score desc nulls last, qm.creationdate desc) as rn_hot,
           rank() over (order by qm.hot_score desc nulls last) as global_hot_rank,
           dense_rank() over (order by coalesce(qm.total_answers,0) desc, coalesce(qm.upvotes,0) desc) as engagement_rank
    from question_metrics qm
),
user_scores as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ua.q_count,
           ua.a_count,
           ua.total_post_score,
           ua.total_answer_score,
           ua.avg_nonzero_score,
           ua.first_post_date,
           ua.last_post_date,
           ura.recent_q,
           ura.recent_a,
           ura.recent_vote_delta,
           case
             when ua.a_count > 0 then cast(ua.total_answer_score as numeric) / ua.a_count
             when ua.q_count > 0 then cast(ua.total_post_score as numeric) / (ua.q_count + nullif(ua.a_count,0))
             else null
           end as avg_score_per_answer_fallback
    from recent_users ru
    left join user_agg ua on ua.user_id = ru.user_id
    left join user_recent_activity ura on ura.user_id = ru.user_id
),
best_question_per_user as (
    select rq.user_id,
           rq.question_id,
           rq.title,
           rq.hot_score,
           rq.total_answers,
           rq.upvotes,
           rq.downvotes,
           rq.minutes_to_first_answer,
           rq.dup_count,
           rq.global_hot_rank
    from ranked_questions rq
    where rq.rn_hot = 1
),
stringified_tags as (
    select te.question_id,
           string_agg(distinct lower(te.tag), ',' order by lower(te.tag)) as tag_list
    from tag_expanded te
    group by te.question_id
),
accepted_answerer_join as (
    select aa.question_id,
           aa.accepted_user_id,
           aa.accepted_answer_score,
           u.displayname as accepted_user_name
    from accepted_answerer aa
    left join posts p_question on p_question.id = aa.question_id
    left join users u on u.id = aa.accepted_user_id
),
outliers as (
    select rq.question_id,
           rq.user_id,
           case when rq.hot_score > (select avg(hot_score) + 3*stddev_pop(hot_score) from hotness) then 1 else 0 end as is_hot_outlier,
           case when rq.minutes_to_first_answer is not null and rq.minutes_to_first_answer >
                     (select avg(minutes_to_first_answer) + 3*stddev_pop(minutes_to_first_answer) from ranked_questions)
                then 1 else 0 end as is_slow_answer_outlier
    from ranked_questions rq
)
select
    us.user_id,
    us.displayname,
    us.reputation,
    us.q_count,
    us.a_count,
    coalesce(us.total_post_score,0) as total_post_score,
    round(coalesce(us.avg_nonzero_score,0),2) as avg_nonzero_score,
    coalesce(us.recent_q,0) as recent_q_30d,
    coalesce(us.recent_a,0) as recent_a_30d,
    coalesce(us.recent_vote_delta,0) as recent_vote_delta_agg,
    bq.question_id as best_question_id,
    substring(coalesce(bq.title,'[no title]') for 120) as best_question_title_prefix,
    round(coalesce(bq.hot_score,0),3) as best_question_hot_score,
    coalesce(bq.total_answers,0) as best_question_answers,
    coalesce(bq.upvotes,0) as best_question_upvotes,
    coalesce(bq.downvotes,0) as best_question_downvotes,
    round(coalesce(bq.minutes_to_first_answer,0),1) as minutes_to_first_answer,
    coalesce(bq.dup_count,0) as duplicate_links,
    st.tag_list as best_question_tags,
    trim(coalesce(ra.location, 'unknown')) as location_norm,
    case when aa.accepted_user_id is null then 'no accepted answer'
         when aa.accepted_user_id = us.user_id then 'self-accepted'
         else 'accepted by ' || coalesce(aa.accepted_user_name, 'unknown')
    end as accepted_answer_status,
    coalesce(o.is_hot_outlier,0) as is_hot_outlier,
    coalesce(o.is_slow_answer_outlier,0) as is_slow_answer_outlier
from user_scores us
left join best_question_per_user bq on bq.user_id = us.user_id
left join stringified_tags st on st.question_id = bq.question_id
left join recent_users ra on ra.user_id = us.user_id
left join accepted_answerer_join aa on aa.question_id = bq.question_id
left join outliers o on o.question_id = bq.question_id and o.user_id = us.user_id
where coalesce(us.q_count,0) + coalesce(us.a_count,0) > 0
  and (
        ra.is_remote = 1
        or (st.tag_list ilike '%sql%' and coalesce(us.total_answer_score,0) > 0)
      )
  and (
        bq.hot_score is null
        or bq.hot_score > (
            select percentile_cont(0.75) within group (order by hot_score) from hotness
        )
      )
order by
    is_hot_outlier desc,
    best_question_hot_score desc nulls last,
    us.total_post_score desc,
    us.reputation desc
limit 200;