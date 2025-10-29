-- {"query": "257.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2819} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(split_part(coalesce(u.location,''), ',', 1)), ''), 'Unknown') as region_hint,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '2 years' from users)
),
active_users as (
    select ru.*
    from recent_users ru
    where ru.rn <= 5000
),
q_posts as (
    select p.id, p.owneruserid as user_id, p.creationdate, p.score, p.viewcount, p.answercount,
           p.title, p.tags, p.posttypeid, p.acceptedanswerid
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select p.id, p.parentid as question_id, p.owneruserid as user_id, p.creationdate, p.score, p.posttypeid
    from posts p
    where p.posttypeid = 2
),
user_q as (
    select au.user_id,
           count(*) filter (where qp.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') as q_last_year,
           count(*) as q_total,
           avg(qp.score) as avg_q_score,
           percentile_cont(0.5) within group (order by qp.score) as med_q_score,
           avg(qp.viewcount) as avg_q_views,
           sum(qp.answercount) as sum_q_answers
    from active_users au
    left join q_posts qp on qp.user_id = au.user_id
    group by au.user_id
),
user_a as (
    select au.user_id,
           count(*) filter (where ap.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '365 days') as a_last_year,
           count(*) as a_total,
           avg(ap.score) as avg_a_score,
           percentile_cont(0.5) within group (order by ap.score) as med_a_score
    from active_users au
    left join a_posts ap on ap.user_id = au.user_id
    group by au.user_id
),
votes_agg as (
    select v.postid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded
    from votes v
    where v.creationdate >= (select coalesce(max(creationdate) - interval '3 years', cast('2024-10-01 12:34:56' as timestamp) - interval '3 years') from votes)
    group by v.postid
),
tag_expansion as (
    select qp.id as post_id,
           unnest(string_to_array(substring(qp.tags, 2, length(qp.tags)-2), '><')) as tagname
    from q_posts qp
    where qp.tags is not null and length(qp.tags) > 2
),
tag_focus as (
    select te.post_id,
           lower(te.tagname) as tagname
    from tag_expansion te
    where length(te.tagname) between 2 and 35
),
user_tag_stats as (
    select qp.user_id,
           tf.tagname,
           count(*) as q_count,
           avg(qp.score) as avg_score,
           sum(va.upvotes) as sum_up,
           sum(va.downvotes) as sum_down
    from q_posts qp
    join tag_focus tf on tf.post_id = qp.id
    left join votes_agg va on va.postid = qp.id
    group by qp.user_id, tf.tagname
),
top_tag_per_user as (
    select uts.user_id,
           uts.tagname,
           uts.q_count,
           uts.avg_score,
           uts.sum_up,
           uts.sum_down,
           row_number() over (partition by uts.user_id order by uts.q_count desc, uts.avg_score desc nulls last, uts.tagname) as rn
    from user_tag_stats uts
),
qa_latency as (
    select q.id as question_id,
           q.owneruserid as q_owner,
           min(a.creationdate) filter (where a.creationdate > q.creationdate) as first_answer_time,
           count(a.id) as answer_count_all,
           count(a.id) filter (where a.score > 0) as pos_answer_count
    from posts q
    left join posts a on a.parentid = q.id and a.posttypeid = 2
    where q.posttypeid = 1
      and q.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '2 years'
    group by q.id, q.owneruserid
),
close_events as (
    select ph.postid,
           min(ph.creationdate) filter (where ph.posthistorytypeid = 10) as first_close_date,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopen_date,
           sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_votes_events
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as original_post_id,
           min(pl.creationdate) as first_dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
badge_agg as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold,
           sum(case when b.class = 2 then 1 else 0 end) as silver,
           sum(case when b.class = 3 then 1 else 0 end) as bronze,
           count(*) as total_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
activity as (
    select au.user_id,
           coalesce(uq.q_last_year,0) as q_last_year,
           coalesce(ua.a_last_year,0) as a_last_year,
           coalesce(uq.q_total,0) as q_total,
           coalesce(ua.a_total,0) as a_total,
           coalesce(uq.avg_q_score,0) as avg_q_score,
           coalesce(ua.avg_a_score,0) as avg_a_score,
           coalesce(ba.total_badges,0) as total_badges,
           coalesce(ba.gold,0) as gold_badges,
           coalesce(ba.silver,0) as silver_badges,
           coalesce(ba.bronze,0) as bronze_badges,
           ba.last_badge_date
    from active_users au
    left join user_q uq on uq.user_id = au.user_id
    left join user_a ua on ua.user_id = au.user_id
    left join badge_agg ba on ba.userid = au.user_id
),
question_enriched as (
    select q.id,
           q.owneruserid as user_id,
           q.creationdate,
           q.score,
           q.viewcount,
           q.answercount,
           qa.first_answer_time,
           extract(epoch from (qa.first_answer_time - q.creationdate)) as seconds_to_first_answer,
           ce.first_close_date,
           ce.last_reopen_date,
           extract(epoch from (ce.first_close_date - q.creationdate)) as seconds_to_close,
           dl.original_post_id as marked_duplicate_of
    from posts q
    left join qa_latency qa on qa.question_id = q.id
    left join close_events ce on ce.postid = q.id
    left join dup_links dl on dl.dup_post_id = q.id
    where q.posttypeid = 1
),
user_quality as (
    select qe.user_id,
           count(*) as questions_considered,
           avg(qe.score) as avg_q_score,
           avg(case when qe.seconds_to_first_answer is not null then qe.seconds_to_first_answer end) as avg_time_to_first_answer_sec,
           sum(case when qe.first_close_date is not null then 1 else 0 end) as closed_q_count,
           sum(case when qe.marked_duplicate_of is not null then 1 else 0 end) as duplicate_q_count
    from question_enriched qe
    group by qe.user_id
),
ranked_users as (
    select au.user_id,
           au.displayname,
           au.reputation,
           au.region_hint,
           au.cohort_month,
           act.q_last_year,
           act.a_last_year,
           act.q_total,
           act.a_total,
           act.avg_q_score,
           act.avg_a_score,
           act.total_badges,
           act.gold_badges,
           act.silver_badges,
           act.bronze_badges,
           uqm.questions_considered,
           uqm.avg_q_score as avg_q_score_all_time,
           uqm.avg_time_to_first_answer_sec,
           uqm.closed_q_count,
           uqm.duplicate_q_count,
           ttp.tagname as top_tag,
           ttp.q_count as top_tag_q_count,
           ttp.avg_score as top_tag_avg_score,
           row_number() over (
               order by
                   coalesce(act.q_last_year,0)*2 + coalesce(act.a_last_year,0) desc,
                   coalesce(act.avg_q_score,0) + coalesce(act.avg_a_score,0) desc,
                   au.reputation desc,
                   au.user_id desc
           ) as activity_rank
    from active_users au
    left join activity act on act.user_id = au.user_id
    left join user_quality uqm on uqm.user_id = au.user_id
    left join top_tag_per_user ttp on ttp.user_id = au.user_id and ttp.rn = 1
),
comments_agg as (
    select c.userid as user_id,
           count(*) as comment_count,
           avg(c.score) as avg_comment_score,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
final_scores as (
    select ru.*,
           coalesce(ca.comment_count,0) as comment_count,
           coalesce(ca.avg_comment_score,0) as avg_comment_score,
           coalesce(ca.last_comment_date, timestamp 'epoch') as last_comment_date,
           case
             when coalesce(ru.top_tag_q_count,0) = 0 then null
             else round( (coalesce(ru.top_tag_avg_score,0) * 0.4)
                       + (coalesce(ru.avg_q_score,0) * 0.2)
                       + (coalesce(ru.avg_a_score,0) * 0.15)
                       + (least(coalesce(ru.q_last_year,0), 100) / 100.0) * 0.1
                       + (least(coalesce(ru.a_last_year,0), 200) / 200.0) * 0.05
                       + (least(coalesce(ru.total_badges,0), 50) / 50.0) * 0.05
                       + (case when coalesce(ru.duplicate_q_count,0) = 0 then 0.05 else 0 end)
                       , 4)
           end as quality_score
    from ranked_users ru
    left join comments_agg ca on ca.user_id = ru.user_id
),
savers as (
    select v.userid as user_id, count(*) as saves_last_year
    from votes v
    where v.votetypeid = 5
      and v.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '1 year'
    group by v.userid
),
final as (
    select fs.*,
           coalesce(sv.saves_last_year,0) as saves_last_year,
           dense_rank() over (order by coalesce(fs.quality_score,0) desc, fs.activity_rank) as quality_rank,
           count(*) over () as population_count
    from final_scores fs
    left join savers sv on sv.user_id = fs.user_id
)
select *
from final
where (
        -- complex predicate blending string, null, numeric logic
        (top_tag is not null and position('sql' in lower(top_tag)) > 0)
        or (top_tag is null and coalesce(region_hint, '') <> '' and length(region_hint) >= 3)
      )
  and coalesce(quality_score, 0) >= (
        select percentile_cont(0.6) within group (order by coalesce(quality_score,0))
        from final_scores
      )
  and (reputation > 1000 or (total_badges >= 5 and avg_comment_score >= 0))
order by quality_rank, activity_rank, user_id
limit 250;