-- {"query": "154.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3148} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           dense_rank() over (order by u.creationdate desc) as drnk
    from users u
),
top_recent_users as (
    select *
    from recent_users
    where drnk <= 500
),
user_badge_agg as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_post_activity as (
    select p.owneruserid as userid,
           sum(case when p.posttypeid = 1 then 1 else 0 end) as questions,
           sum(case when p.posttypeid = 2 then 1 else 0 end) as answers,
           sum(coalesce(p.viewcount, 0)) as total_views,
           sum(coalesce(p.score, 0)) as total_post_score,
           count(*) as total_posts,
           max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_stats as (
    select q.owneruserid as userid,
           avg(nullif(q.answercount, 0)) as avg_answercount_nonzero,
           avg(q.score) filter (where q.score is not null) as avg_question_score,
           percentile_disc(0.9) within group (order by coalesce(q.viewcount, 0)) as p90_question_views,
           sum(case when q.acceptedanswerid is not null then 1 else 0 end) as accepted_questions
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_stats as (
    select a.owneruserid as userid,
           avg(a.score) as avg_answer_score,
           sum(case when a.score > 0 then 1 else 0 end) as positive_answers,
           sum(case when a.score < 0 then 1 else 0 end) as negative_answers
    from posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
comment_agg as (
    select c.userid,
           count(*) as comments_count,
           sum(coalesce(c.score, 0)) as comments_score,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_agg as (
    select v.userid,
           sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
           sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
           sum(case when v.votetypeid = 8 then coalesce(v.bountyamount, 0) else 0 end) as bounty_started,
           sum(case when v.votetypeid = 9 then coalesce(v.bountyamount, 0) else 0 end) as bounty_awarded
    from votes v
    where v.userid is not null
    group by v.userid
),
dup_links as (
    select pl.postid,
           count(*) filter (where pl.linktypeid = 3) as duplicate_links,
           count(*) filter (where pl.linktypeid = 1) as regular_links
    from postlinks pl
    group by pl.postid
),
closed_reasons as (
    select ph.postid,
           max(ph.creationdate) as last_close_date,
           max(case
                 when ph.posthistorytypeid = 10 then
                   cast(nullif(regexp_replace(coalesce(ph.comment, ''), '[^0-9]', '', 'g'), '') as int)
                 else null
               end) as last_close_reason_id
    from posthistory ph
    where ph.posthistorytypeid in (10, 11)
    group by ph.postid
),
question_quality as (
    select q.id as postid,
           q.owneruserid as userid,
           q.score,
           coalesce(q.viewcount, 0) as views,
           q.answercount,
           coalesce(d.duplicate_links, 0) as duplicate_links,
           coalesce(d.regular_links, 0) as regular_links,
           cr.last_close_date,
           cr.last_close_reason_id,
           case
             when q.score is null then null
             when q.score >= 10 and coalesce(q.viewcount, 0) >= 10000 then 'Outstanding'
             when q.score >= 5 and coalesce(q.viewcount, 0) >= 2000 then 'Great'
             when q.score >= 0 and coalesce(q.viewcount, 0) >= 200 then 'Good'
             when q.score < 0 then 'Poor'
             else 'Average'
           end as quality_bucket
    from posts q
    left join dup_links d on d.postid = q.id
    left join closed_reasons cr on cr.postid = q.id
    where q.posttypeid = 1
),
tag_exploded as (
    select p.id as postid,
           trim(t) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as t
),
user_top_tag as (
    select q.owneruserid as userid,
           tag,
           count(*) as tag_q_count,
           row_number() over (partition by q.owneruserid order by count(*) desc, tag) as rn
    from posts q
    join tag_exploded te on te.postid = q.id
    where q.posttypeid = 1
    group by q.owneruserid, tag
),
best_user_top_tag as (
    select userid,
           tag as top_tag,
           tag_q_count as top_tag_questions
    from user_top_tag
    where rn = 1
),
recent_hot_questions as (
    select qq.userid,
           qq.postid,
           qq.quality_bucket,
           qq.views,
           qq.score,
           qq.answercount,
           row_number() over (partition by qq.userid order by qq.views desc, qq.score desc) as rn
    from question_quality qq
    where qq.quality_bucket in ('Outstanding', 'Great')
),
activity_timeline as (
    select u.id as userid,
           generate_series(
               date_trunc('month', u.creationdate)::timestamp,
               date_trunc('month', coalesce(upa.last_post_activity, now()))::timestamp,
               interval '1 month'
           ) as month_start
    from users u
    left join user_post_activity upa on upa.userid = u.id
),
monthly_post_counts as (
    select p.owneruserid as userid,
           date_trunc('month', p.creationdate)::date as month_start,
           count(*) as posts_in_month
    from posts p
    where p.creationdate is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)::date
),
user_activity_density as (
    select at.userid,
           avg(coalesce(mpc.posts_in_month, 0)) as avg_posts_per_month,
           max(coalesce(mpc.posts_in_month, 0)) as max_posts_in_a_month,
           sum(case when coalesce(mpc.posts_in_month, 0) = 0 then 1 else 0 end) as inactive_months
    from activity_timeline at
    left join monthly_post_counts mpc
      on mpc.userid = at.userid
     and mpc.month_start = at.month_start::date
    group by at.userid
),
user_quality_score as (
    select u.id as userid,
           coalesce(qs.avg_question_score, 0) * 0.4
         + coalesce(ans.avg_answer_score, 0) * 0.4
         + least(coalesce(upa.total_post_score, 0), 1000) * 0.001
         + coalesce(uba.gold_badges, 0) * 1.0
         + coalesce(uba.silver_badges, 0) * 0.3
         + coalesce(uba.bronze_badges, 0) * 0.1
         - greatest(coalesce(ans.negative_answers, 0) - coalesce(ans.positive_answers, 0), 0) * 0.2
         - case when coalesce(ua.avg_posts_per_month, 0) = 0 then 2 else 0 end as quality_score
    from users u
    left join question_stats qs on qs.userid = u.id
    left join answer_stats ans on ans.userid = u.id
    left join user_post_activity upa on upa.userid = u.id
    left join user_badge_agg uba on uba.userid = u.id
    left join user_activity_density ua on ua.userid = u.id
),
ranked_users as (
    select tru.userid,
           tru.displayname,
           tru.reputation,
           tru.creationdate,
           tru.location,
           coalesce(upa.total_posts, 0) as total_posts,
           coalesce(qa.avg_question_score, 0) as avg_q_score,
           coalesce(ans.avg_answer_score, 0) as avg_a_score,
           coalesce(uba.total_badges, 0) as total_badges,
           coalesce(uba.gold_badges, 0) as gold_badges,
           coalesce(uba.silver_badges, 0) as silver_badges,
           coalesce(uba.bronze_badges, 0) as bronze_badges,
           coalesce(v.upvotes_cast, 0) as upvotes_cast,
           coalesce(v.downvotes_cast, 0) as downvotes_cast,
           coalesce(v.bounty_started, 0) as bounty_started,
           coalesce(v.bounty_awarded, 0) as bounty_awarded,
           coalesce(uqs.quality_score, 0) as quality_score,
           coalesce(uad.avg_posts_per_month, 0) as avg_posts_per_month,
           coalesce(uad.max_posts_in_a_month, 0) as max_posts_in_a_month,
           coalesce(uad.inactive_months, 0) as inactive_months,
           coalesce(btt.top_tag, '(none)') as top_tag,
           coalesce(btt.top_tag_questions, 0) as top_tag_questions,
           row_number() over (
               order by
                   coalesce(uqs.quality_score, -1) desc,
                   tru.reputation desc,
                   coalesce(upa.total_posts, 0) desc,
                   tru.userid
           ) as global_rank
    from top_recent_users tru
    left join user_post_activity upa on upa.userid = tru.userid
    left join question_stats qa on qa.userid = tru.userid
    left join answer_stats ans on ans.userid = tru.userid
    left join user_badge_agg uba on uba.userid = tru.userid
    left join vote_agg v on v.userid = tru.userid
    left join user_activity_density uad on uad.userid = tru.userid
    left join best_user_top_tag btt on btt.userid = tru.userid
    left join user_quality_score uqs on uqs.userid = tru.userid
),
accepted_answer_time as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           a.id as answer_id,
           a.owneruserid as answerer_id,
           a.creationdate as answer_date,
           q.creationdate as question_date,
           extract(epoch from (a.creationdate - q.creationdate)) / 3600.0 as hours_to_accept
    from posts q
    join posts a on a.id = q.acceptedanswerid
),
user_accept_stats as (
    select aas.answerer_id as userid,
           avg(aas.hours_to_accept) as avg_hours_to_accept
    from accepted_answer_time aas
    group by aas.answerer_id
),
final as (
    select ru.*,
           coalesce(ua.avg_hours_to_accept, 9999) as avg_hours_for_accept_on_answers,
           case
             when ru.downvotes_cast is not null and ru.downvotes_cast > ru.upvotes_cast then 'Controversial'
             when ru.gold_badges >= 1 and ru.avg_a_score >= 2 then 'Expert'
             when ru.total_posts >= 50 then 'Prolific'
             else 'Active'
           end as user_archetype,
           rhq.postid as showcase_postid,
           rhq.quality_bucket as showcase_quality,
           rhq.views as showcase_views,
           rhq.score as showcase_score,
           rhq.answercount as showcase_answercount
    from ranked_users ru
    left join user_accept_stats ua on ua.userid = ru.userid
    left join recent_hot_questions rhq on rhq.userid = ru.userid and rhq.rn = 1
)
select f.userid,
       f.displayname,
       f.reputation,
       f.location,
       f.quality_score,
       f.global_rank,
       f.user_archetype,
       f.total_posts,
       f.avg_q_score,
       f.avg_a_score,
       f.total_badges,
       f.gold_badges,
       f.silver_badges,
       f.bronze_badges,
       f.upvotes_cast,
       f.downvotes_cast,
       f.bounty_started,
       f.bounty_awarded,
       f.avg_posts_per_month,
       f.max_posts_in_a_month,
       f.inactive_months,
       f.top_tag,
       f.top_tag_questions,
       f.avg_hours_for_accept_on_answers,
       f.showcase_postid,
       f.showcase_quality,
       f.showcase_views,
       f.showcase_score,
       f.showcase_answercount
from final f
where (
         f.quality_score > (
           select avg(coalesce(quality_score, 0))
           from ranked_users
         )
         or (f.top_tag is not null and f.top_tag <> '(none)' and f.top_tag_questions >= 3)
      )
  and (f.location is null or position(',' in coalesce(f.location, '')) = 0 or length(f.location) > 2)
  and not exists (
        select 1
        from posts p
        where p.owneruserid = f.userid
          and p.posttypeid = 1
          and p.score < -10
      )
order by f.global_rank
limit 100;