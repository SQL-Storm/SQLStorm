-- {"query": "920.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2854} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
           date_trunc('month', u.creationdate) as cohort_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
q_posts as (
    select p.id,
           p.owneruserid,
           p.creationdate,
           p.score,
           p.viewcount,
           p.title,
           p.tags,
           p.answercount
    from posts p
    where p.posttypeid = 1
),
a_posts as (
    select p.id,
           p.parentid,
           p.owneruserid,
           p.creationdate,
           p.score
    from posts p
    where p.posttypeid = 2
),
first_answer as (
    select parentid as question_id,
           min(creationdate) as first_answer_date
    from a_posts
    group by parentid
),
user_badges as (
    select b.userid,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           count(*) as total_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_vote_agg as (
    select v.userid,
           count(*) filter (where v.votetypeid = 2) as upvotes_cast,
           count(*) filter (where v.votetypeid = 3) as downvotes_cast,
           sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_total
    from votes v
    group by v.userid
),
question_stats as (
    select q.owneruserid as user_id,
           count(*) as q_count,
           sum(q.score) as q_score_sum,
           avg(q.score::numeric) as q_score_avg,
           sum(coalesce(q.viewcount,0)) as q_views_sum,
           avg(nullif(q.viewcount,0)) as q_views_avg_nonzero,
           count(*) filter (where q.answercount > 0) as q_with_answers,
           count(*) filter (where q.score <= 0) as q_nonpos,
           percentile_cont(0.5) within group (order by q.score) as q_score_p50
    from q_posts q
    group by q.owneruserid
),
answer_stats as (
    select a.owneruserid as user_id,
           count(*) as a_count,
           sum(a.score) as a_score_sum,
           avg(a.score::numeric) as a_score_avg,
           count(*) filter (where a.score > 0) as a_pos_answers,
           percentile_disc(0.9) within group (order by a.score) as a_score_p90
    from a_posts a
    group by a.owneruserid
),
question_time_to_first_answer as (
    select q.owneruserid as user_id,
           avg(extract(epoch from (fa.first_answer_date - q.creationdate)) / 3600.0) as avg_hours_to_first_answer,
           max(extract(epoch from (fa.first_answer_date - q.creationdate)) / 3600.0) as max_hours_to_first_answer,
           count(fa.first_answer_date) as answered_questions
    from q_posts q
    left join first_answer fa on fa.question_id = q.id
    group by q.owneruserid
),
tag_extraction as (
    select q.owneruserid as user_id,
           unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tagname
    from q_posts q
    where q.tags is not null and q.tags like '<%>'
),
top_tags as (
    select user_id,
           tagname,
           count(*) as tag_uses,
           row_number() over (partition by user_id order by count(*) desc, tagname) as rn
    from tag_extraction
    group by user_id, tagname
),
user_comments as (
    select c.userid as user_id,
           count(*) as comment_count,
           avg(c.score::numeric) as comment_score_avg,
           sum(case when c.text ilike '%thanks%' then 1 else 0 end) as thanks_mentions
    from comments c
    group by c.userid
),
postlink_dupes as (
    select p.owneruserid as user_id,
           count(*) as dupes_linked_to,
           count(*) filter (where pl.linktypeid = 3) as marked_duplicates
    from posts p
    join postlinks pl on pl.postid = p.id
    group by p.owneruserid
),
post_closures as (
    select ph.postid,
           ph.userid,
           ph.creationdate,
           ph.comment as closeraw,
           ph.text as closejson
    from posthistory ph
    where ph.posthistorytypeid = 10
),
user_closure_agg as (
    select coalesce(ph.userid, -1) as user_id,
           count(*) as close_events,
           count(*) filter (where nullif(ph.closeraw,'') ~ '^(101|102|103|104|105)$') as close_reason_known
    from post_closures ph
    group by coalesce(ph.userid, -1)
),
activity_window as (
    select u.id as user_id,
           p.id as post_id,
           p.posttypeid,
           p.creationdate,
           row_number() over (partition by u.id order by p.creationdate) as rn,
           lag(p.creationdate) over (partition by u.id order by p.creationdate) as prev_post_date,
           lead(p.creationdate) over (partition by u.id order by p.creationdate) as next_post_date
    from users u
    left join posts p on p.owneruserid = u.id
),
gaps_between_posts as (
    select user_id,
           avg(extract(epoch from (creationdate - prev_post_date)) / 86400.0) as avg_days_between_posts,
           max(extract(epoch from (creationdate - prev_post_date)) / 86400.0) as max_days_between_posts,
           count(*) filter (where prev_post_date is not null) as gaps_count
    from activity_window
    group by user_id
),
cohort_activity as (
    select ru.cohort_month,
           ru.user_id,
           count(q.id) as cohort_q_count,
           count(a.id) as cohort_a_count
    from recent_users ru
    left join q_posts q on q.owneruserid = ru.user_id
    left join a_posts a on a.owneruserid = ru.user_id
    group by ru.cohort_month, ru.user_id
),
cohort_summ as (
    select cohort_month,
           percentile_cont(0.5) within group (order by cohort_q_count) as p50_qs,
           percentile_cont(0.5) within group (order by cohort_a_count) as p50_as
    from cohort_activity
    group by cohort_month
),
ranked_users as (
    select u.id as user_id,
           dense_rank() over (order by u.reputation desc, u.id) as rep_rank_global
    from users u
),
accepted_answers as (
    select a.owneruserid as user_id,
           count(*) as accepted_given
    from posts q
    join posts a on a.id = q.acceptedanswerid
    group by a.owneruserid
),
user_quality_score as (
    select u.id as user_id,
           (coalesce(qs.q_score_sum,0) + coalesce(asx.a_score_sum,0))::numeric
             / nullif((coalesce(qs.q_count,0) + coalesce(asx.a_count,0)),0) as avg_post_score_overall,
           (coalesce(aa.accepted_given,0))::numeric / nullif(coalesce(asx.a_count,0),0) as answer_accept_rate
    from users u
    left join question_stats qs on qs.user_id = u.id
    left join answer_stats asx on asx.user_id = u.id
    left join accepted_answers aa on aa.user_id = u.id
),
final_users as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.cohort_month,
        coalesce(ub.total_badges,0) as total_badges,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        coalesce(qs.q_count,0) as q_count,
        coalesce(qs.q_score_sum,0) as q_score_sum,
        coalesce(qs.q_views_sum,0) as q_views_sum,
        coalesce(asx.a_count,0) as a_count,
        coalesce(asx.a_score_sum,0) as a_score_sum,
        coalesce(qa.avg_hours_to_first_answer, null) as avg_hours_to_first_answer,
        coalesce(dc.dupes_linked_to,0) as dupes_linked_to,
        coalesce(dc.marked_duplicates,0) as marked_duplicates,
        coalesce(uc.close_events,0) as close_events,
        coalesce(uv.upvotes_cast,0) as upvotes_cast,
        coalesce(uv.downvotes_cast,0) as downvotes_cast,
        coalesce(uv.bounty_total,0) as bounty_total,
        coalesce(uc.close_reason_known,0) as close_reason_known,
        coalesce(ucag.avg_days_between_posts, null) as avg_days_between_posts,
        coalesce(ucag.max_days_between_posts, null) as max_days_between_posts
    from recent_users ru
    left join user_badges ub on ub.userid = ru.user_id
    left join question_stats qs on qs.user_id = ru.user_id
    left join answer_stats asx on asx.user_id = ru.user_id
    left join question_time_to_first_answer qa on qa.user_id = ru.user_id
    left join postlink_dupes dc on dc.user_id = ru.user_id
    left join user_closure_agg uc on uc.user_id = ru.user_id
    left join user_vote_agg uv on uv.userid = ru.user_id
    left join gaps_between_posts ucag on ucag.user_id = ru.user_id
),
with_top_tag as (
    select fu.*,
           tt.tagname as top_tag,
           tt.tag_uses as top_tag_uses
    from final_users fu
    left join lateral (
        select tagname, tag_uses
        from top_tags tt
        where tt.user_id = fu.user_id and tt.rn = 1
    ) tt on true
)
select
    fu.user_id,
    fu.displayname,
    fu.reputation,
    fu.cohort_month,
    coalesce(fu.top_tag, '(none)') as top_tag,
    coalesce(fu.top_tag_uses, 0) as top_tag_uses,
    fu.q_count,
    fu.a_count,
    fu.q_score_sum,
    fu.a_score_sum,
    round(coalesce(uqs.avg_post_score_overall, 0), 3) as avg_post_score_overall,
    round(coalesce(uqs.answer_accept_rate, 0), 4) as answer_accept_rate,
    fu.q_views_sum,
    fu.avg_hours_to_first_answer,
    fu.dupes_linked_to,
    fu.marked_duplicates,
    fu.total_badges,
    fu.gold_badges,
    fu.silver_badges,
    fu.bronze_badges,
    fu.upvotes_cast,
    fu.downvotes_cast,
    fu.bounty_total,
    fu.close_events,
    fu.close_reason_known,
    fu.avg_days_between_posts,
    fu.max_days_between_posts,
    rg.rep_rank_global,
    case
        when fu.reputation >= 100000 then 'legend'
        when fu.reputation >= 50000 then 'guru'
        when fu.reputation >= 10000 then 'veteran'
        when fu.reputation >= 1000 then 'regular'
        else 'newcomer'
    end as reputation_band
from with_top_tag fu
left join user_quality_score uqs on uqs.user_id = fu.user_id
left join ranked_users rg on rg.user_id = fu.user_id
where (
    fu.q_count + fu.a_count >= 1
    or fu.total_badges >= 1
    or fu.upvotes_cast + fu.downvotes_cast >= 5
)
and (
    fu.reputation > 0
    or fu.bounty_total > 0
)
and (
    fu.top_tag is null
    or fu.top_tag not ilike any (array['meta%', 'discussion%', 'recommendation%'])
)
qualify
    row_number() over (
        partition by fu.cohort_month
        order by coalesce(uqs.avg_post_score_overall, -1) desc nulls last,
                 fu.q_count + fu.a_count desc,
                 fu.reputation desc,
                 fu.user_id
    ) <= 500
order by fu.cohort_month desc, reputation_band, rg.rep_rank_global, fu.user_id;