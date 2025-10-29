-- {"query": "180.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3117} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as website_host
    from users u
    where u.creationdate >= (select date_trunc('month', max(creationdate)) - interval '12 months' from users)
),
badge_activity as (
    select b.userid,
           count(*) as badge_count,
           sum(case when b.class = 1 then 1 else 0 end) as gold_cnt,
           sum(case when b.class = 2 then 1 else 0 end) as silver_cnt,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_cnt,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           min(b.date) as first_badge_date,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
posts_aug as (
    select p.*,
           case when p.posttypeid = 1 then 'Question'
                when p.posttypeid = 2 then 'Answer'
                else 'Other' end as post_type_name,
           coalesce(p.ownerdiplayname, p.ownerdisplayname) as owner_name -- safeguard typo
    from posts p
),
qna as (
    select q.id as question_id,
           q.owneruserid as asker_id,
           q.creationdate as question_date,
           q.score as question_score,
           q.viewcount,
           q.title,
           q.tags,
           q.acceptedanswerid,
           count(a.id) as answer_count,
           avg(a.score) as avg_answer_score,
           max(a.creationdate) as last_answer_date
    from posts_aug q
    left join posts_aug a
      on a.parentid = q.id
     and a.posttypeid = 2
    where q.posttypeid = 1
    group by q.id, q.owneruserid, q.creationdate, q.score, q.viewcount, q.title, q.tags, q.acceptedanswerid
),
question_engagement as (
    select q.question_id,
           sum(case when vt.votetypeid = 2 then 1 else 0 end) as upvotes,
           sum(case when vt.votetypeid = 3 then 1 else 0 end) as downvotes,
           sum(case when vt.votetypeid = 5 then 1 else 0 end) as favorites,
           count(distinct c.id) as comment_count
    from qna q
    left join votes vt on vt.postid = q.question_id
    left join comments c on c.postid = q.question_id
    group by q.question_id
),
accepted_answerers as (
    select q.question_id,
           a.owneruserid as accepted_user_id,
           a.id as accepted_answer_id,
           a.score as accepted_answer_score,
           a.creationdate as accepted_answer_date
    from qna q
    left join posts_aug a
      on a.id = q.acceptedanswerid
),
tag_extracted as (
    select q.question_id,
           unnest(string_to_array(substring(coalesce(q.tags, ''), 2, greatest(length(coalesce(q.tags,''))-2,0)), '><')) as tag
    from qna q
),
tag_stats as (
    select te.tag,
           count(*) as tag_q_count,
           avg(q.question_score) as tag_avg_q_score,
           percentile_cont(0.5) within group (order by q.viewcount) as tag_median_views
    from tag_extracted te
    join qna q on q.question_id = te.question_id
    group by te.tag
),
post_close_events as (
    select ph.postid,
           count(*) filter (where ph.posthistorytypeid in (10,11)) as close_reopen_events,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 10) as last_closed_date,
           max(ph.creationdate) filter (where ph.posthistorytypeid = 11) as last_reopened_date,
           max(case when ph.posthistorytypeid = 10 then try_cast(ph.comment as int) end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
duplicate_links as (
    select pl.postid as dup_post_id,
           pl.relatedpostid as master_post_id,
           count(*) as dup_link_count
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_activity as (
    select u.id as user_id,
           count(*) filter (where p.posttypeid = 1) as questions_posted,
           count(*) filter (where p.posttypeid = 2) as answers_posted,
           sum(p.score) as total_post_score,
           avg(nullif(p.score,0)) as avg_nonzero_post_score,
           max(p.lastactivitydate) as last_post_activity,
           count(distinct case when p.posttypeid in (1,2) then p.id end) as total_contrib_posts
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
ranked_questions as (
    select q.*,
           qe.upvotes,
           qe.downvotes,
           qe.favorites,
           qe.comment_count,
           aa.accepted_user_id,
           aa.accepted_answer_id,
           aa.accepted_answer_score,
           aa.accepted_answer_date,
           pce.close_reopen_events,
           pce.last_closed_date,
           pce.last_reopened_date,
           pce.last_close_reason_id,
           dl.master_post_id,
           dl.dup_link_count,
           sum(q.viewcount) over () as total_views_all_q,
           rank() over (order by coalesce(q.viewcount,0) desc, coalesce(q.question_score,0) desc, q.creationdate desc) as pop_rank,
           row_number() over (partition by date_trunc('month', q.question_date) order by q.viewcount desc) as month_top_rank
    from qna q
    left join question_engagement qe on qe.question_id = q.question_id
    left join accepted_answerers aa on aa.question_id = q.question_id
    left join post_close_events pce on pce.postid = q.question_id
    left join duplicate_links dl on dl.dup_post_id = q.question_id
),
user_domains as (
    select ru.user_id,
           lower(regexp_replace(ru.website_host, '^www\.', '')) as root_host,
           count(*) as appearances
    from recent_users ru
    group by ru.user_id, lower(regexp_replace(ru.website_host, '^www\.', ''))
),
domain_popularity as (
    select root_host,
           sum(appearances) as total_users_on_host,
           dense_rank() over (order by sum(appearances) desc nulls last) as host_rank
    from user_domains
    group by root_host
),
heavy_users as (
    select ua.user_id,
           ua.questions_posted,
           ua.answers_posted,
           ua.total_contrib_posts,
           ua.total_post_score,
           ua.avg_nonzero_post_score,
           coalesce(ba.badge_count,0) as badge_count,
           coalesce(ba.gold_cnt,0) as gold_cnt,
           coalesce(ba.silver_cnt,0) as silver_cnt,
           coalesce(ba.bronze_cnt,0) as bronze_cnt,
           coalesce(ba.tag_badges,0) as tag_badges,
           ru.displayname,
           ru.reputation,
           ru.creationdate as user_created,
           ru.location,
           ud.root_host,
           dp.host_rank
    from user_activity ua
    left join badge_activity ba on ba.userid = ua.user_id
    left join recent_users ru on ru.user_id = ua.user_id
    left join user_domains ud on ud.user_id = ua.user_id
    left join domain_popularity dp on dp.root_host = ud.root_host
    where coalesce(ua.total_contrib_posts,0) >= 5
),
question_tag_rollup as (
    select rq.question_id,
           array_agg(te.tag order by te.tag) filter (where te.tag is not null) as tags_array,
           min(ts.tag_avg_q_score) as min_tag_avg_q_score,
           max(ts.tag_avg_q_score) as max_tag_avg_q_score
    from ranked_questions rq
    left join tag_extracted te on te.question_id = rq.question_id
    left join tag_stats ts on ts.tag = te.tag
    group by rq.question_id
),
final_scored as (
    select
        rq.question_id,
        rq.title,
        rq.tags,
        qtr.tags_array,
        rq.viewcount,
        rq.question_score,
        rq.answer_count,
        rq.avg_answer_score,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.comment_count,
        rq.accepted_answer_id,
        rq.accepted_user_id,
        rq.accepted_answer_score,
        rq.accepted_answer_date,
        rq.close_reopen_events,
        rq.last_closed_date,
        rq.last_reopened_date,
        rq.last_close_reason_id,
        rq.master_post_id,
        rq.dup_link_count,
        rq.total_views_all_q,
        rq.pop_rank,
        rq.month_top_rank,
        hu.displayname as asker_name,
        hu.reputation as asker_rep,
        hu.location as asker_location,
        hu.host_rank as asker_host_rank,
        hu.badge_count as asker_badges,
        hu.gold_cnt as asker_gold,
        hu.silver_cnt as asker_silver,
        hu.bronze_cnt as asker_bronze,
        hu.questions_posted,
        hu.answers_posted,
        hu.total_contrib_posts,
        hu.total_post_score,
        qtr.min_tag_avg_q_score,
        qtr.max_tag_avg_q_score,
        case
            when rq.accepted_answer_id is not null then 1
            when rq.answer_count > 0 and rq.avg_answer_score > 1 then 0.8
            when rq.answer_count > 0 then 0.6
            else 0.2
        end as answeriness_factor,
        case
            when rq.last_closed_date is not null and (rq.last_reopened_date is null or rq.last_closed_date > rq.last_reopened_date) then 0.5
            else 1.0
        end as open_state_factor,
        case
            when coalesce(rq.downvotes,0) = 0 then coalesce(rq.upvotes,0)
            else coalesce(rq.upvotes,0) - greatest(1, rq.downvotes) * 0.5
        end as net_vote_signal,
        least(5.0,
              coalesce(rq.question_score,0)/10.0
              + ln(greatest(1, rq.viewcount))
              + coalesce(rq.favorites,0)/5.0
              + coalesce(rq.comment_count,0)/20.0
             ) * case when rq.pop_rank <= 100 then 1.2 else 1.0 end as popularity_component
    from ranked_questions rq
    left join question_tag_rollup qtr on qtr.question_id = rq.question_id
    left join heavy_users hu on hu.user_id = rq.asker_id
),
scored_with_windows as (
    select fs.*,
           avg(popularity_component) over () as global_avg_pop,
           stddev_pop(popularity_component) over () as global_std_pop,
           avg(net_vote_signal) over () as global_avg_net_vote,
           percentile_cont(0.9) within group (order by coalesce(viewcount,0)) over () as p90_views,
           sum(case when accepted_answer_id is not null then 1 else 0 end) over () as total_with_accepted,
           count(*) over () as total_rows,
           row_number() over (order by
                (popularity_component * answeriness_factor * open_state_factor + coalesce(net_vote_signal,0)) desc,
                coalesce(viewcount,0) desc
           ) as overall_rank
    from final_scored fs
),
outliers as (
    select s.question_id,
           case when s.global_std_pop > 0 and s.popularity_component > s.global_avg_pop + 3*s.global_std_pop then 1 else 0 end as pop_outlier_hi,
           case when s.global_std_pop > 0 and s.popularity_component < s.global_avg_pop - 3*s.global_std_pop then 1 else 0 end as pop_outlier_lo
    from scored_with_windows s
),
dedup as (
    select s.*,
           o.pop_outlier_hi,
           o.pop_outlier_lo,
           dense_rank() over (partition by lower(coalesce(s.title,'')) order by s.viewcount desc nulls last, s.question_id) as title_rank
    from scored_with_windows s
    left join outliers o on o.question_id = s.question_id
)
select
    d.question_id,
    d.title,
    coalesce(array_to_string(d.tags_array, '|'), '') as tags_pipe,
    d.viewcount,
    d.question_score,
    d.answer_count,
    d.accepted_answer_id,
    d.accepted_user_id,
    d.popularity_component,
    d.net_vote_signal,
    round((d.popularity_component * d.answeriness_factor * d.open_state_factor + coalesce(d.net_vote_signal,0))::numeric, 3) as composite_score,
    d.pop_rank,
    d.month_top_rank,
    d.asker_name,
    d.asker_rep,
    d.asker_location,
    d.asker_host_rank,
    d.asker_badges,
    d.asker_gold,
    d.asker_silver,
    d.asker_bronze,
    d.questions_posted,
    d.answers_posted,
    d.total_contrib_posts,
    d.total_post_score,
    d.min_tag_avg_q_score,
    d.max_tag_avg_q_score,
    d.pop_outlier_hi,
    d.pop_outlier_lo,
    d.global_avg_pop,
    d.global_std_pop,
    d.global_avg_net_vote,
    d.p90_views,
    d.total_with_accepted,
    d.total_rows
from dedup d
where d.title_rank = 1
  and coalesce(d.viewcount,0) >= coalesce(d.p90_views,0) / 3
  and coalesce(d.asker_rep, 0) >= 1
order by composite_score desc, d.viewcount desc, d.question_id
limit 200;