-- {"query": "74.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2737} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.creationdate,
           u.location,
           coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl_norm,
           date_trunc('month', u.creationdate) as signup_month,
           row_number() over (order by u.creationdate desc, u.id desc) as rn_recent
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_summary as (
    select b.userid,
           count(*) as total_badges,
           sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
           sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
           sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
           sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
user_posts as (
    select p.owneruserid as user_id,
           count(*) filter (where p.posttypeid = 1) as q_count,
           count(*) filter (where p.posttypeid = 2) as a_count,
           count(*) filter (where p.posttypeid not in (1,2)) as other_count,
           sum(coalesce(p.score,0)) as total_post_score,
           sum(coalesce(p.viewcount,0)) as total_views,
           max(p.lastactivitydate) as last_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
qa_details as (
    select p.owneruserid as user_id,
           p.id as post_id,
           p.posttypeid,
           p.score,
           p.viewcount,
           p.creationdate,
           p.lastactivitydate,
           p.title,
           p.tags,
           row_number() over (partition by p.owneruserid, p.posttypeid order by p.score desc nulls last, p.viewcount desc nulls last, p.id) as rn_by_type
    from posts p
    where p.owneruserid is not null
      and p.posttypeid in (1,2)
),
best_question_answer as (
    select q.user_id,
           max(case when q.posttypeid = 1 and q.rn_by_type = 1 then q.post_id end) as best_question_id,
           max(case when q.posttypeid = 2 and q.rn_by_type = 1 then q.post_id end) as best_answer_id
    from qa_details q
    group by q.user_id
),
comment_stats as (
    select c.userid as user_id,
           count(*) as comments_count,
           sum(coalesce(c.score,0)) as comment_score,
           max(c.creationdate) as last_comment_date,
           avg(length(c.text))::numeric as avg_comment_len
    from comments c
    where c.userid is not null
    group by c.userid
),
votes_by_type as (
    select v.userid as user_id,
           v.votetypeid,
           count(*) as vote_count,
           sum(coalesce(v.bountyamount,0)) as bounty_total
    from votes v
    where v.userid is not null
    group by v.userid, v.votetypeid
),
votes_pivot as (
    select user_id,
           sum(case when votetypeid = 2 then vote_count else 0 end) as upvotes_cast,
           sum(case when votetypeid = 3 then vote_count else 0 end) as downvotes_cast,
           sum(case when votetypeid in (8,9) then bounty_total else 0 end) as bounty_amount_cast,
           sum(vote_count) as total_votes_cast
    from votes_by_type
    group by user_id
),
closed_question_events as (
    select ph.postid,
           min(ph.creationdate) as first_closed_date,
           count(*) filter (where ph.posthistorytypeid = 10) as close_events,
           sum(
               case
                   when ph.posthistorytypeid = 10
                        and (ph.comment similar to '%(101|1)%' or ph.text ilike '%duplicate%')
                   then 1 else 0 end
           ) as duplicate_close_events
    from posthistory ph
    where ph.posthistorytypeid in (10,11,35,37,38)
    group by ph.postid
),
dup_links as (
    select pl.postid,
           pl.relatedpostid,
           pl.creationdate,
           row_number() over (partition by pl.postid order by pl.creationdate asc, pl.id) as rn_dup
    from postlinks pl
    where pl.linktypeid = 3
),
top_tag_usage as (
    select p.owneruserid as user_id,
           unnest(string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')) as tagname
    from posts p
    where p.owneruserid is not null and p.posttypeid = 1 and p.tags is not null
),
top_tag_rank as (
    select t.user_id,
           t.tagname,
           count(*) as tag_count,
           dense_rank() over (partition by t.user_id order by count(*) desc, min(tagname)) as dr
    from top_tag_usage t
    group by t.user_id, t.tagname
),
user_top_tag as (
    select user_id,
           string_agg(tagname, ',' order by tagname) as top_tags
    from top_tag_rank
    where dr <= 3
    group by user_id
),
accepted_answers as (
    select a.owneruserid as user_id,
           count(*) as accepted_answers
    from posts q
    join posts a on a.id = q.acceptedanswerid
    group by a.owneruserid
),
answers_on_duplicates as (
    select a.owneruserid as user_id,
           count(distinct a.id) as answers_on_duplicate_questions
    from posts a
    join posts q on q.id = a.parentid and q.posttypeid = 1
    join closed_question_events cqe on cqe.postid = q.id and cqe.duplicate_close_events > 0
    group by a.owneruserid
),
activity_cadence as (
    select p.owneruserid as user_id,
           date_trunc('month', p.creationdate) as month,
           count(*) as posts_in_month
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_slope as (
    select ac.user_id,
           regr_slope(posts_in_month::numeric, extract(epoch from month)) as posts_time_slope
    from activity_cadence ac
    group by ac.user_id
),
recent_hot_candidates as (
    select p.id as question_id,
           p.owneruserid as user_id,
           p.creationdate,
           p.score,
           p.viewcount,
           coalesce(p.favoritecount,0) as favs,
           (coalesce(p.score,0) * 3 + coalesce(p.viewcount,0) / 50 + coalesce(p.favoritecount,0) * 5) as hot_score_est,
           row_number() over (partition by p.owneruserid order by coalesce(p.score,0) * 3 + coalesce(p.viewcount,0) / 50 + coalesce(p.favoritecount,0) * 5 desc, p.id) as rn_hot
    from posts p
    where p.posttypeid = 1
      and p.creationdate >= (select max(creationdate) - interval '180 days' from posts)
      and p.owneruserid is not null
),
first_dup_link as (
    select d.postid as question_id,
           d.relatedpostid as original_question_id
    from dup_links d
    where d.rn_dup = 1
),
user_null_sentinels as (
    select u.id as user_id,
           case when u.displayname is null or trim(u.displayname) = '' then 1 else 0 end as missing_displayname,
           case when u.location is null or trim(u.location) = '' then 1 else 0 end as missing_location
    from users u
),
ranked_users as (
    select ru.user_id,
           ru.displayname,
           ru.reputation,
           ru.signup_month,
           up.total_post_score,
           up.total_views,
           coalesce(bs.total_badges,0) as total_badges,
           coalesce(vp.total_votes_cast,0) as total_votes_cast,
           coalesce(cs.comments_count,0) as comments_count,
           row_number() over (
               order by
                   coalesce(up.total_post_score,0) desc,
                   coalesce(up.total_views,0) desc,
                   coalesce(bs.total_badges,0) desc,
                   ru.reputation desc,
                   ru.user_id
           ) as rn_overall
    from recent_users ru
    left join user_posts up on up.user_id = ru.user_id
    left join badge_summary bs on bs.userid = ru.user_id
    left join votes_pivot vp on vp.user_id = ru.user_id
    left join comment_stats cs on cs.user_id = ru.user_id
)
select
    ru.user_id,
    coalesce(nullif(ru.displayname, ''), concat('user-', ru.user_id::varchar)) as displayname_fallback,
    ru.reputation,
    ru.signup_month,
    up.q_count,
    up.a_count,
    up.other_count,
    up.total_post_score,
    up.total_views,
    up.last_activity,
    bs.total_badges,
    bs.gold_badges,
    bs.silver_badges,
    bs.bronze_badges,
    bs.tag_badges,
    bs.last_badge_date,
    cs.comments_count,
    cs.comment_score,
    cs.last_comment_date,
    round(cs.avg_comment_len, 2) as avg_comment_len,
    vp.upvotes_cast,
    vp.downvotes_cast,
    vp.bounty_amount_cast,
    vp.total_votes_cast,
    att.accepted_answers,
    aod.answers_on_duplicate_questions,
    att.accepted_answers::numeric / nullif(up.a_count,0) as accept_rate,
    at.posts_time_slope,
    utt.top_tags,
    bqa.best_question_id,
    bqa.best_answer_id,
    rhc.question_id as recent_hot_question_id,
    rhc.hot_score_est as recent_hot_score_est,
    fdl.original_question_id as first_duplicate_of,
    uns.missing_displayname,
    uns.missing_location,
    case
        when coalesce(up.total_post_score,0) >= 1000 and coalesce(bs.gold_badges,0) >= 5 then 'elite'
        when coalesce(up.total_post_score,0) >= 200 and coalesce(bs.silver_badges,0) >= 3 then 'power'
        when coalesce(up.total_post_score,0) >= 50 then 'active'
        when coalesce(up.total_post_score,0) is null then 'new'
        else 'casual'
    end as contributor_tier,
    case
        when ru.websiteurl_norm ilike '%github%' then 'github'
        when ru.websiteurl_norm ilike '%gitlab%' then 'gitlab'
        when ru.websiteurl_norm ilike '%stack%overflow%' then 'stackoverflow'
        when ru.websiteurl_norm = 'n/a' then null
        else 'other'
    end as website_class,
    ranku.rn_overall,
    count(*) over () as total_returned_users
from ranked_users ranku
join recent_users ru on ru.user_id = ranku.user_id
left join user_posts up on up.user_id = ru.user_id
left join badge_summary bs on bs.userid = ru.user_id
left join comment_stats cs on cs.user_id = ru.user_id
left join votes_pivot vp on vp.user_id = ru.user_id
left join accepted_answers att on att.user_id = ru.user_id
left join answers_on_duplicates aod on aod.user_id = ru.user_id
left join activity_slope at on at.user_id = ru.user_id
left join user_top_tag utt on utt.user_id = ru.user_id
left join best_question_answer bqa on bqa.user_id = ru.user_id
left join recent_hot_candidates rhc on rhc.user_id = ru.user_id and rhc.rn_hot = 1
left join posts q on q.id = rhc.question_id
left join first_dup_link fdl on fdl.question_id = q.id
left join user_null_sentinels uns on uns.user_id = ru.user_id
where ranku.rn_overall <= 500
order by
    contributor_tier desc,
    ranku.rn_overall,
    ru.user_id;