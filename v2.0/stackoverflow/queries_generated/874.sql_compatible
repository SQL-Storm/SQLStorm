with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(u.location), ''), 'Unknown') as location_norm,
           date_trunc('month', u.creationdate) as cohort_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_desc
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
user_badge_tally as (
    select b.userid,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           sum(case when b.tagbased = true then 1 else 0 end) as tag_badges,
           count(*) as total_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_posts as (
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
answer_posts as (
    select a.id,
           a.parentid as question_id,
           a.owneruserid as user_id,
           a.creationdate,
           a.score,
           a.commentcount
    from posts a
    where a.posttypeid = 2
),
q_activity as (
    select q.user_id,
           count(*) as questions_count,
           sum(coalesce(q.score,0)) as questions_score,
           sum(coalesce(q.viewcount,0)) as questions_views,
           sum(case when q.closeddate is not null then 1 else 0 end) as questions_closed,
           sum(case when q.acceptedanswerid is not null then 1 else 0 end) as questions_with_accept,
           avg(nullif(q.answercount,0)) filter (where q.answercount is not null) as avg_answers_per_q,
           max(q.creationdate) as last_question_date
    from question_posts q
    group by q.user_id
),
a_activity as (
    select a.user_id,
           count(*) as answers_count,
           sum(coalesce(a.score,0)) as answers_score,
           avg(nullif(a.score,0)) filter (where a.score is not null) as avg_answer_score,
           max(a.creationdate) as last_answer_date
    from answer_posts a
    group by a.user_id
),
post_interactions as (
    select p.owneruserid as user_id,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_rcvd,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_rcvd,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started_amt,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded_amt,
           count(distinct v.id) as vote_events
    from posts p
    left join votes v on v.postid = p.id
    group by p.owneruserid
),
comment_sentiment as (
    select c.userid as user_id,
           count(*) as comments_made,
           sum(case when c.score > 0 then 1 else 0 end) as comments_pos,
           sum(case when c.score < 0 then 1 else 0 end) as comments_neg,
           avg(c.score) as avg_comment_score,
           max(c.creationdate) as last_comment_date
    from comments c
    group by c.userid
),
dup_links as (
    select pl.postid as duplicate_id,
           pl.relatedpostid as original_id
    from postlinks pl
    where pl.linktypeid = 3
),
question_tag_expansion as (
    select q.id as question_id,
           unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tag_name
    from question_posts q
    where q.tags is not null and length(q.tags) > 2
),
user_tag_profile as (
    select q.user_id,
           t.tag_name,
           count(*) as tag_q_count,
           sum(coalesce(q.score,0)) as tag_q_score
    from question_posts q
    join question_tag_expansion t on t.question_id = q.id
    group by q.user_id, t.tag_name
),
top_tag_per_user as (
    select utp.user_id,
           utp.tag_name,
           utp.tag_q_count,
           utp.tag_q_score,
           row_number() over (partition by utp.user_id order by utp.tag_q_count desc, utp.tag_q_score desc, utp.tag_name) as rn
    from user_tag_profile utp
),
user_close_events as (
    select ph.postid,
           ph.userid as actor_id,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_dt,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_dt,
           sum(case when ph.posthistorytypeid = 10 then 1 else 0 end) as close_votes_cast,
           sum(case when ph.posthistorytypeid = 11 then 1 else 0 end) as reopen_votes_cast
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid, ph.userid
),
lhs as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.cohort_month,
           ru.location_norm,
           coalesce(q.questions_count,0) as questions_count,
           coalesce(q.questions_score,0) as questions_score,
           coalesce(q.questions_views,0) as questions_views,
           coalesce(q.questions_closed,0) as questions_closed,
           coalesce(q.questions_with_accept,0) as questions_with_accept,
           coalesce(a.answers_count,0) as answers_count,
           coalesce(a.answers_score,0) as answers_score,
           coalesce(pi.upvotes_rcvd,0) as upvotes_rcvd,
           coalesce(pi.downvotes_rcvd,0) as downvotes_rcvd,
           coalesce(pi.bounty_started_amt,0) as bounty_started_amt,
           coalesce(pi.bounty_awarded_amt,0) as bounty_awarded_amt,
           coalesce(cb.comments_made,0) as comments_made,
           coalesce(cb.comments_pos,0) as comments_pos,
           coalesce(cb.comments_neg,0) as comments_neg,
           ub.total_badges,
           ub.gold_count,
           ub.silver_count,
           ub.bronze_count,
           ub.tag_badges,
           greatest(coalesce(q.last_question_date, timestamp 'epoch'),
                    coalesce(a.last_answer_date, timestamp 'epoch'),
                    coalesce(cb.last_comment_date, timestamp 'epoch')) as last_activity_dt
    from recent_users ru
    left join q_activity q on q.user_id = ru.user_id
    left join a_activity a on a.user_id = ru.user_id
    left join post_interactions pi on pi.user_id = ru.user_id
    left join comment_sentiment cb on cb.user_id = ru.user_id
    left join user_badge_tally ub on ub.userid = ru.user_id
),
user_quality as (
    select l.*,
           (coalesce(answers_score,0) + coalesce(questions_score,0)) / nullif((answers_count + questions_count),0) as avg_post_score,
           (coalesce(upvotes_rcvd,0) - coalesce(downvotes_rcvd,0)) / nullif((answers_count + questions_count),0) as net_votes_per_post,
           case
               when coalesce(answers_count + questions_count,0) = 0 then null
               when coalesce(answers_score,0) + coalesce(questions_score,0) >= 100 then 'A'
               when coalesce(answers_score,0) + coalesce(questions_score,0) >= 25 then 'B'
               when coalesce(answers_score,0) + coalesce(questions_score,0) >= 5 then 'C'
               else 'D'
           end as perf_grade,
           case when ub.total_badges is null then 'No Badges'
                when ub.gold_count > 0 then 'Has Gold'
                when ub.silver_count > 2 then 'Silver+'
                when ub.bronze_count > 5 then 'Bronze+'
                else 'Some Badges'
           end as badge_band
    from lhs l
    left join user_badge_tally ub on ub.userid = l.user_id
),
activity_ranked as (
    select uq.*,
           row_number() over (partition by uq.cohort_month order by coalesce(uq.answers_score + uq.questions_score,0) desc, uq.reputation desc, uq.user_id) as cohort_rank,
           dense_rank() over (order by coalesce(uq.answers_count+uq.questions_count,0) desc) as global_post_vol_rank
    from user_quality uq
),
user_top_tag as (
    select t.user_id,
           t.tag_name as top_tag,
           t.tag_q_count as top_tag_qs,
           t.tag_q_score as top_tag_score
    from top_tag_per_user t
    where t.rn = 1
),
dup_impact as (
    select q.user_id,
           count(distinct d.duplicate_id) as dup_marked_questions,
           count(distinct d.original_id) as originals_referenced
    from question_posts q
    left join dup_links d on d.duplicate_id = q.id
    group by q.user_id
),
final_agg as (
    select ar.user_id,
           ar.displayname,
           ar.location_norm,
           ar.cohort_month,
           ar.reputation,
           ar.perf_grade,
           ar.badge_band,
           ar.questions_count,
           ar.answers_count,
           ar.questions_score,
           ar.answers_score,
           ar.net_votes_per_post,
           ar.avg_post_score,
           ar.cohort_rank,
           ar.global_post_vol_rank,
           ut.top_tag,
           ut.top_tag_qs,
           ut.top_tag_score,
           di.dup_marked_questions,
           di.originals_referenced,
           ar.last_activity_dt,
           case
             when ar.location_norm ilike '%remote%' then 'Remote'
             when position(',' in ar.location_norm) > 0 then split_part(ar.location_norm, ',', 2)
             when ar.location_norm = 'Unknown' then null
             else ar.location_norm
           end as region_hint,
           coalesce(nullif(trim(ut.top_tag), ''), 'un-tagged') || '|' ||
           coalesce(ar.perf_grade, 'U') || '|' ||
           coalesce(ar.badge_band, 'None') as compact_label,
           ar.comments_made,
           ar.upvotes_rcvd,
           ar.downvotes_rcvd,
           ar.bounty_awarded_amt,
           ar.total_badges
    from activity_ranked ar
    left join user_top_tag ut on ut.user_id = ar.user_id
    left join dup_impact di on di.user_id = ar.user_id
),
high_perf as (
    select * from final_agg where perf_grade in ('A','B') and (answers_count + questions_count) >= 10
),
emerging as (
    select * from final_agg where perf_grade in ('C') and reputation >= 1000
),
quiet as (
    select * from final_agg where (answers_count + questions_count) < 3 and last_activity_dt < cast('2024-10-01 12:34:56' as timestamp) - interval '180 days'
),
combined as (
    select 'high' as segment, f.* from high_perf f
    union all
    select 'emerging' as segment, f.* from emerging f
    union all
    select 'quiet' as segment, f.* from quiet f
),
with_percentiles as (
    select c.*,
           (
             select percentile_cont(0.9) within group (order by fa.answers_score + fa.questions_score)
             from final_agg fa
             where fa.cohort_month = c.cohort_month
           ) as cohort_p90_score
    from combined c
)
select wp.segment,
       wp.user_id,
       wp.displayname,
       wp.cohort_month,
       wp.reputation,
       wp.perf_grade,
       wp.badge_band,
       wp.questions_count,
       wp.answers_count,
       wp.questions_score,
       wp.answers_score,
       wp.avg_post_score,
       wp.net_votes_per_post,
       wp.cohort_rank,
       wp.global_post_vol_rank,
       wp.top_tag,
       wp.top_tag_qs,
       wp.top_tag_score,
       wp.dup_marked_questions,
       wp.originals_referenced,
       wp.region_hint,
       wp.compact_label,
       wp.cohort_p90_score,
       case when (wp.answers_score + wp.questions_score) >= wp.cohort_p90_score then 1 else 0 end as is_cohort_top10,
       round( greatest(0,
           (coalesce(wp.answers_count,0) * 1.5
          + (coalesce(wp.questions_count,0) * 1.0)
          + least(coalesce(wp.comments_made,0), 50) * 0.2
          + coalesce(wp.upvotes_rcvd,0) * 0.3
          - coalesce(wp.downvotes_rcvd,0) * 0.8
          + least(coalesce(wp.bounty_awarded_amt,0) / 50.0, 20)
          + coalesce(wp.total_badges,0) * 0.1)
       ), 2) as engagement_index
from with_percentiles wp
where (
        (wp.segment = 'high' and wp.net_votes_per_post is not null)
     or (wp.segment = 'emerging' and wp.avg_post_score is not null)
     or (wp.segment = 'quiet' and wp.last_activity_dt is not null)
)
order by wp.segment, wp.cohort_rank nulls last, wp.global_post_vol_rank, wp.user_id
limit 500;