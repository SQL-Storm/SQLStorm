-- {"query": "276.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2723}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.websiteurl,
        u.upvotes,
        u.downvotes,
        coalesce(nullif(trim(u.location), ''), 'UNKNOWN') as norm_location
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
-- split tags into rows using standard SQL: remove leading/trailing angle brackets then split on '><'
user_tag_activity as (
    select
        p.owneruserid as user_id,
        lower(trim(both ' ' from t.tag_name)) as tag_name,
        sum(case when p.posttypeid = 1 then 1 else 0 end) as q_count,
        sum(case when p.posttypeid = 2 then 1 else 0 end) as a_count,
        sum(coalesce(p.score,0)) as score_sum,
        count(*) as post_count,
        max(p.lastactivitydate) as last_activity
    from posts p
    cross join lateral (
        select regexp_split_to_table(
                 case
                   when p.tags is null then ''
                   when left(p.tags,1) = '<' and right(p.tags,1) = '>' then substring(p.tags from 2 for char_length(p.tags)-2)
                   else p.tags
                 end,
                 '><'
               ) as tag_name
    ) t
    where p.owneruserid is not null
      and p.tags is not null
      and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
    group by p.owneruserid, lower(trim(both ' ' from t.tag_name))
),
user_vote_stats as (
    select
        v.userid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_cast,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_cast,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites_cast,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_cast
    from votes v
    where v.userid is not null
      and v.creationdate >= (select max(creationdate) - interval '730 days' from votes)
    group by v.userid
),
post_vote_agg as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total_received
    from posts p
    left join votes v on v.postid = p.id
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '730 days' from posts)
    group by p.owneruserid
),
badge_rank as (
    select
        b.userid as user_id,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) as total_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_close_events as (
    select
        ph.postid,
        sum(1) filter (where ph.posthistorytypeid = 10) as closes,
        sum(1) filter (where ph.posthistorytypeid = 11) as reopens,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_event
    from posthistory ph
    join posts p on p.id = ph.postid and p.posttypeid = 1
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_post_id,
        pl.relatedpostid as original_post_id,
        count(*) as dup_link_count,
        min(pl.creationdate) as first_dup_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid, pl.relatedpostid
),
user_activity_window as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        lead(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as next_post_time,
        lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_post_time,
        row_number() over (partition by p.owneruserid order by p.creationdate desc) as rn_desc,
        count(*) over (partition by p.owneruserid) as user_post_count
    from posts p
    where p.owneruserid is not null
),
user_quality as (
    select
        uaw.user_id,
        percentile_cont(0.5) within group (order by coalesce(uaw.score,0)) as median_post_score,
        avg(coalesce(uaw.score,0)) as avg_post_score,
        stddev_pop(coalesce(uaw.score,0)) as std_post_score,
        avg(extract(epoch from (uaw.next_post_time - uaw.creationdate))) as avg_time_to_next_sec,
        avg(extract(epoch from (uaw.creationdate - uaw.prev_post_time))) as avg_time_from_prev_sec,
        sum(case when uaw.posttypeid = 1 and uaw.score >= 5 then 1 else 0 end) as high_score_questions,
        sum(case when uaw.posttypeid = 2 and uaw.score >= 5 then 1 else 0 end) as high_score_answers
    from user_activity_window uaw
    group by uaw.user_id
),
top_tag_per_user as (
    select user_id, tag_name, post_count, score_sum,
           row_number() over (partition by user_id order by post_count desc, score_sum desc, tag_name) as rn
    from user_tag_activity
),
user_latest_question as (
    select
        p.owneruserid as user_id,
        p.id as question_id,
        p.title,
        p.creationdate as question_date,
        coalesce(qce.closes,0) as closes,
        coalesce(qce.reopens,0) as reopens,
        coalesce(qce.last_close_event, p.lastactivitydate) as last_close_or_activity
    from (
        select distinct on (owneruserid)
            owneruserid, id, title, creationdate, lastactivitydate
        from posts
        where posttypeid = 1 and owneruserid is not null
        order by owneruserid, creationdate desc
    ) p
    left join question_close_events qce on qce.postid = p.id
),
user_duplicate_impact as (
    select
        p.owneruserid as user_id,
        sum(dl.dup_link_count) as dup_links_sum,
        count(distinct dl.dup_post_id) as duplicated_posts,
        count(distinct dl.original_post_id) as original_targets
    from dup_links dl
    join posts p on p.id = dl.dup_post_id and p.owneruserid is not null
    group by p.owneruserid
),
cte_union_sample as (
    select user_id from user_quality
    union
    select user_id from user_vote_stats
    union
    select user_id from post_vote_agg
),
final_users as (
    select ru.user_id
    from recent_users ru
    join cte_union_sample cus on cus.user_id = ru.user_id
    where coalesce(ru.reputation,0) >= 1
)
select
    fu.user_id,
    ru.displayname,
    ru.norm_location as location_group,
    coalesce(br.total_badges,0) as total_badges,
    coalesce(br.gold_badges,0) as gold_badges,
    coalesce(br.silver_badges,0) as silver_badges,
    coalesce(br.bronze_badges,0) as bronze_badges,
    coalesce(pva.upvotes_received,0) as upvotes_received,
    coalesce(pva.downvotes_received,0) as downvotes_received,
    coalesce(uvs.upvotes_cast,0) as upvotes_cast,
    coalesce(uvs.downvotes_cast,0) as downvotes_cast,
    coalesce(uvs.bounty_total_cast,0) as bounty_cast,
    coalesce(pva.bounty_total_received,0) as bounty_received,
    uq.median_post_score,
    uq.avg_post_score,
    uq.std_post_score,
    uq.avg_time_to_next_sec,
    uq.avg_time_from_prev_sec,
    coalesce(uta.q_count,0) as q_count_top_tag,
    coalesce(uta.a_count,0) as a_count_top_tag,
    coalesce(uta.tag_name, '(none)') as top_tag,
    coalesce(uta.post_count,0) as top_tag_post_count,
    coalesce(uta.score_sum,0) as top_tag_score_sum,
    ulq.question_id as latest_question_id,
    left(coalesce(ulq.title,''), 120) as latest_question_title_trunc,
    coalesce(ulq.closes,0) as latest_question_closes,
    coalesce(ulq.reopens,0) as latest_question_reopens,
    ulq.last_close_or_activity,
    coalesce(udi.dup_links_sum,0) as dup_links_sum,
    coalesce(udi.duplicated_posts,0) as duplicated_posts,
    coalesce(udi.original_targets,0) as original_duplicate_targets,
    case
        when coalesce(pva.upvotes_received,0) + coalesce(pva.downvotes_received,0) = 0 then null
        else round(100.0 * coalesce(pva.upvotes_received,0) / nullif(coalesce(pva.upvotes_received,0) + coalesce(pva.downvotes_received,0),0), 2)
    end as upvote_ratio_received_pct,
    case
        when coalesce(uvs.upvotes_cast,0) + coalesce(uvs.downvotes_cast,0) = 0 then null
        else round(100.0 * coalesce(uvs.upvotes_cast,0) / nullif(coalesce(uvs.upvotes_cast,0) + coalesce(uvs.downvotes_cast,0),0), 2)
    end as upvote_ratio_cast_pct,
    case
        when coalesce(br.total_badges,0) = 0 then 'Newcomer'
        when coalesce(br.gold_badges,0) > 0 then 'Elite'
        when coalesce(br.silver_badges,0) > 3 then 'Advanced'
        when coalesce(br.bronze_badges,0) > 5 then 'Intermediate'
        else 'Beginner'
    end as badge_tier,
    case
        when uq.avg_post_score is null then 'NoPosts'
        when uq.avg_post_score >= 5 then 'High'
        when uq.avg_post_score between 1 and 4.999 then 'Medium'
        when uq.avg_post_score between -5 and 0.999 then 'Low'
        else 'VeryLow'
    end as quality_band
from final_users fu
left join recent_users ru on ru.user_id = fu.user_id
left join badge_rank br on br.user_id = fu.user_id
left join post_vote_agg pva on pva.user_id = fu.user_id
left join user_vote_stats uvs on uvs.user_id = fu.user_id
left join user_quality uq on uq.user_id = fu.user_id
left join top_tag_per_user ttp on ttp.user_id = fu.user_id and ttp.rn = 1
left join user_tag_activity uta on uta.user_id = ttp.user_id and uta.tag_name = ttp.tag_name
left join user_latest_question ulq on ulq.user_id = fu.user_id
left join user_duplicate_impact udi on udi.user_id = fu.user_id
where
    (
        coalesce(pva.upvotes_received,0) + coalesce(pva.downvotes_received,0) +
        coalesce(uvs.upvotes_cast,0) + coalesce(uvs.downvotes_cast,0)
    ) > 0
order by
    coalesce(br.gold_badges,0) desc,
    coalesce(pva.upvotes_received,0) desc,
    coalesce(uq.avg_post_score, -9999) desc,
    ru.displayname nulls last
limit 500;