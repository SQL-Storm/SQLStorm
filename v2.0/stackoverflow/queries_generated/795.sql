-- {"query": "795.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2673} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.creationdate,
           coalesce(nullif(trim(u.websiteurl), ''), 'unknown') as websiteurl_norm,
           date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= now() - interval '3 years'
),
user_badge_agg as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_count,
           sum(case when b.class = 2 then 1 else 0 end) as silver_count,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_count,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date,
           count(*) filter (where b.tagbased = true) as tag_badges,
           count(*) filter (where b.tagbased = false) as named_badges
    from badges b
    group by b.userid
),
user_post_activity as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           sum(coalesce(p.score,0)) as total_post_score,
           avg(nullif(p.score,0)) as avg_nonzero_post_score,
           max(p.viewcount) as max_views,
           count(*) filter (where p.closeddate is not null) as closed_count,
           count(*) filter (where p.communityowneddate is not null) as comm_owned_count
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_tag_expanded as (
    select p.id as question_id,
           p.owneruserid as owner_user_id,
           unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tag
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
user_top_tag as (
    select q.owner_user_id as user_id,
           t.tag,
           count(*) as tag_q_count,
           row_number() over (partition by q.owner_user_id order by count(*) desc, tag asc) as rn
    from question_tag_expanded q
    join tags t on t.tagname = q.tag
    group by q.owner_user_id, t.tag
),
answer_accept_stats as (
    select a.owneruserid as user_id,
           count(*) as answers_total,
           count(*) filter (where q.acceptedanswerid = a.id) as answers_accepted,
           1.0 * count(*) filter (where q.acceptedanswerid = a.id) / nullif(count(*),0) as accept_rate
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    where a.posttypeid = 2
    group by a.owneruserid
),
vote_agg as (
    select v.userid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           count(*) filter (where v.votetypeid = 5) as favorites_cast,
           max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
comment_agg as (
    select c.userid as user_id,
           count(*) as comment_count,
           sum(coalesce(c.score,0)) as comment_score_sum,
           avg(coalesce(c.score,0)) as comment_score_avg,
           max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
question_lifecycle as (
    select q.id as question_id,
           q.owneruserid as user_id,
           q.creationdate as q_created,
           q.closeddate as q_closed,
           lead(ph.creationdate) over (partition by q.id order by ph.creationdate) as next_event_dt,
           ph.posthistorytypeid,
           ph.creationdate as event_dt
    from posts q
    left join posthistory ph on ph.postid = q.id and q.posttypeid = 1
    where q.posttypeid = 1
),
question_durations as (
    select user_id,
           count(*) filter (where posthistorytypeid = 10) as close_events,
           avg(extract(epoch from (coalesce(q_closed, next_event_dt, now()) - q_created))) as avg_secs_to_next_event
    from question_lifecycle
    group by user_id
),
dup_links as (
    select pl.postid as duplicate_post_id,
           pl.relatedpostid as original_post_id,
           pl.creationdate as link_created
    from postlinks pl
    where pl.linktypeid = 3
),
user_dup_stats as (
    select q.owneruserid as user_id,
           count(distinct d.duplicate_post_id) as dup_marked_questions,
           min(d.link_created) as first_dup_date
    from dup_links d
    join posts q on q.id = d.postid
    group by q.owneruserid
),
recent_hot_candidates as (
    select ph.postid as question_id,
           min(ph.creationdate) as first_hot_dt
    from posthistory ph
    where ph.posthistorytypeid in (52)
    group by ph.postid
),
user_hot_stats as (
    select q.owneruserid as user_id,
           count(*) as hot_q_count,
           min(r.first_hot_dt) as first_hot_dt,
           max(r.first_hot_dt) as last_hot_dt
    from recent_hot_candidates r
    join posts q on q.id = r.question_id
    group by q.owneruserid
),
activity_calendar as (
    select u.user_id,
           date_trunc('month', p.creationdate) as month,
           count(*) filter (where p.posttypeid = 1) as q_in_month,
           count(*) filter (where p.posttypeid = 2) as a_in_month
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    group by u.user_id, date_trunc('month', p.creationdate)
),
activity_spark as (
    select ac.user_id,
           string_agg(lpad(coalesce(ac.q_in_month,0)::text, 2, '0') || '/' || lpad(coalesce(ac.a_in_month,0)::text, 2, '0'), ',' order by ac.month) as qa_sparkline
    from activity_calendar ac
    group by ac.user_id
),
user_quality_score as (
    select u.user_id,
           0.4 * coalesce(log(1 + upvotes_cast - downvotes_cast), 0) +
           0.3 * coalesce(accept_rate, 0) +
           0.2 * coalesce(nullif(avg_nonzero_post_score,0), 0) +
           0.1 * least(coalesce(hot_q_count,0), 10) as quality_score
    from recent_users u
    left join vote_agg v on v.user_id = u.user_id
    left join answer_accept_stats aas on aas.user_id = u.user_id
    left join user_post_activity upa on upa.user_id = u.user_id
    left join user_hot_stats hs on hs.user_id = u.user_id
),
ranked_users as (
    select u.user_id,
           u.displayname,
           u.location,
           u.reputation,
           u.creationdate,
           coalesce(ut.tag, '(none)') as top_tag,
           coalesce(ut.tag_q_count,0) as top_tag_qs,
           coalesce(ba.badge_count,0) as badge_count,
           coalesce(ba.gold_count,0) as gold_count,
           coalesce(ba.silver_count,0) as silver_count,
           coalesce(ba.bronze_count,0) as bronze_count,
           coalesce(upa.q_count,0) as q_count,
           coalesce(upa.a_count,0) as a_count,
           coalesce(upa.total_post_score,0) as total_post_score,
           coalesce(va.upvotes_cast,0) as upvotes_cast,
           coalesce(va.downvotes_cast,0) as downvotes_cast,
           coalesce(ca.comment_count,0) as comment_count,
           coalesce(aas.answers_total,0) as answers_total,
           coalesce(aas.answers_accepted,0) as answers_accepted,
           coalesce(aas.accept_rate,0) as accept_rate,
           coalesce(qd.close_events,0) as close_events,
           coalesce(qd.avg_secs_to_next_event,0) as avg_secs_to_next_event,
           coalesce(uds.dup_marked_questions,0) as dup_marked_questions,
           coalesce(hs.hot_q_count,0) as hot_q_count,
           coalesce(hs.first_hot_dt, null) as first_hot_dt,
           coalesce(hs.last_hot_dt, null) as last_hot_dt,
           coalesce(aspk.qa_sparkline, '') as qa_sparkline,
           coalesce(uqs.quality_score,0) as quality_score,
           row_number() over (
               order by coalesce(uqs.quality_score,0) desc,
                        coalesce(ba.gold_count,0) desc,
                        coalesce(upa.total_post_score,0) desc,
                        u.reputation desc,
                        u.user_id asc
           ) as overall_rank
    from recent_users u
    left join user_badge_agg ba on ba.userid = u.user_id
    left join user_post_activity upa on upa.user_id = u.user_id
    left join user_top_tag ut on ut.user_id = u.user_id and ut.rn = 1
    left join vote_agg va on va.user_id = u.user_id
    left join comment_agg ca on ca.user_id = u.user_id
    left join answer_accept_stats aas on aas.user_id = u.user_id
    left join question_durations qd on qd.user_id = u.user_id
    left join user_dup_stats uds on uds.user_id = u.user_id
    left join user_hot_stats hs on hs.user_id = u.user_id
    left join activity_spark aspk on aspk.user_id = u.user_id
    left join user_quality_score uqs on uqs.user_id = u.user_id
),
bench_union as (
    select * from ranked_users where overall_rank <= 50
    union all
    select * from ranked_users where overall_rank between 51 and 200
)
select ru.user_id,
       ru.displayname,
       ru.location,
       ru.reputation,
       ru.top_tag,
       ru.top_tag_qs,
       ru.badge_count,
       ru.gold_count,
       ru.silver_count,
       ru.bronze_count,
       ru.q_count,
       ru.a_count,
       ru.total_post_score,
       ru.upvotes_cast,
       ru.downvotes_cast,
       ru.comment_count,
       ru.answers_total,
       ru.answers_accepted,
       round(ru.accept_rate::numeric, 4) as accept_rate,
       ru.close_events,
       round(ru.avg_secs_to_next_event::numeric, 2) as avg_secs_to_next_event,
       ru.dup_marked_questions,
       ru.hot_q_count,
       ru.first_hot_dt,
       ru.last_hot_dt,
       ru.qa_sparkline,
       round(ru.quality_score::numeric, 4) as quality_score,
       ru.overall_rank,
       case
           when ru.reputation >= 100000 then 'legend'
           when ru.reputation >= 50000 then 'veteran'
           when ru.reputation >= 10000 then 'pro'
           when ru.reputation >= 1000 then 'regular'
           else 'newbie'
       end as rep_bucket,
       case when ru.downvotes_cast > ru.upvotes_cast then true else false end as net_negative_voter,
       coalesce(nullif(ru.location, ''), 'Unknown') as location_norm
from bench_union ru
where (ru.gold_count + ru.silver_count + ru.bronze_count) >= 0
  and (ru.a_count > 0 or ru.q_count > 0)
order by ru.overall_rank
limit 200;