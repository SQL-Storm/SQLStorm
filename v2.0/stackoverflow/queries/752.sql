-- {"query": "752.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2597}
with recent_users as (
    select
        u.id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (order by u.reputation desc, u.id) as rn_global
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(case when p.posttypeid = 1 then 1 end) as q_count,
        count(case when p.posttypeid = 2 then 1 end) as a_count,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as views,
        count(case when p.closeddate is not null then 1 end) as closed_q
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_stats as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        avg(coalesce(c.score,0)) as avg_comment_score,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_stats as (
    select
        b.userid as user_id,
        count(case when b.class = 1 then 1 end) as gold_badges,
        count(case when b.class = 2 then 1 end) as silver_badges,
        count(case when b.class = 3 then 1 end) as bronze_badges,
        count(case when coalesce(b.tagbased, false) = true then 1 end) as tag_badges,
        min(b.date) as first_badge_at,
        max(b.date) as last_badge_at
    from badges b
    group by b.userid
),
post_windows as (
    select
        p.owneruserid as user_id,
        p.id as post_id,
        p.posttypeid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        sum(coalesce(p.score,0)) over (partition by p.owneruserid order by p.creationdate rows between unbounded preceding and current row) as running_user_score,
        rank() over (partition by p.owneruserid order by coalesce(p.score, -2147483648) desc, p.id asc) as rnk_score_desc,
        dense_rank() over (partition by p.owneruserid order by coalesce(p.viewcount, -2147483648) desc) as drnk_views_desc,
        lag(p.creationdate) over (partition by p.owneruserid order by p.creationdate) as prev_post_at
    from posts p
    where p.owneruserid is not null
),
accepted_answers as (
    select
        a.owneruserid as user_id,
        count(*) as accepted_count
    from posts a
    where a.posttypeid = 2
      and exists (
          select 1
          from posts q
          where q.id = a.parentid
            and q.acceptedanswerid = a.id
      )
    group by a.owneruserid
),
vote_agg as (
    select
        v.userid as user_id,
        count(case when v.votetypeid = 2 then 1 end) as upvotes_cast,
        count(case when v.votetypeid = 3 then 1 end) as downvotes_cast,
        count(case when v.votetypeid = 5 then 1 end) as favorites_cast,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_flow
    from votes v
    where v.userid is not null
    group by v.userid
),
q_tag_explode as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')) as tagname
    from posts p
    where p.posttypeid = 1
      and p.tags is not null
),
top_user_tag as (
    select
        e.user_id,
        e.tagname,
        count(*) as tag_q_count,
        row_number() over (partition by e.user_id order by count(*) desc, e.tagname asc) as rn
    from q_tag_explode e
    group by e.user_id, e.tagname
),
postlinks_agg as (
    select
        p.owneruserid as user_id,
        count(case when pl.linktypeid = 1 then 1 end) as linked_count,
        count(case when pl.linktypeid = 3 then 1 end) as dup_count
    from posts p
    left join postlinks pl on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
edits_and_closures as (
    select
        ph.postid,
        count(case when ph.posthistorytypeid in (4,5,6,7,8,9,24) then 1 end) as edit_events,
        count(case when ph.posthistorytypeid = 10 then 1 end) as close_events,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as last_closed_at,
        max(case when ph.posthistorytypeid = 10 then cast(ph.comment as integer) end) as last_close_reason_id
    from posthistory ph
    group by ph.postid
),
user_latest_q as (
    select distinct on (p.owneruserid)
        p.owneruserid as user_id,
        p.id as last_q_id,
        p.title as last_q_title,
        p.creationdate as last_q_at,
        ea.edit_events as last_q_edit_events,
        ea.close_events as last_q_close_events,
        ea.last_close_reason_id
    from posts p
    left join edits_and_closures ea on ea.postid = p.id
    where p.posttypeid = 1 and p.owneruserid is not null
    order by p.owneruserid, p.creationdate desc, p.id desc
),
activity_density as (
    select
        pw.user_id,
        avg(extract(epoch from (pw.creationdate - pw.prev_post_at)) / 3600.0) as avg_hours_between_posts
    from post_windows pw
    where pw.prev_post_at is not null
    group by pw.user_id
),
rankings as (
    select
        ru.id as user_id,
        ntile(10) over (order by coalesce(ua.post_score,0) desc, ru.reputation desc) as decile_by_post_score,
        percent_rank() over (order by coalesce(ua.q_count,0) + coalesce(ua.a_count,0)) as pr_activity_volume
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.id
    group by ru.id, ru.reputation, ua.post_score, ua.q_count, ua.a_count
),
heavy_posts as (
    select
        pw.user_id,
        count(case when pw.rnk_score_desc <= 3 or pw.drnk_views_desc <= 3 then 1 end) as top_posts_count,
        sum(case when pw.rnk_score_desc = 1 then 1 else 0 end) as top1_score_posts,
        max(pw.running_user_score) as running_score_final
    from post_windows pw
    group by pw.user_id
)
select
    ru.id as user_id,
    ru.displayname,
    ru.reputation,
    ru.cohort_month,
    ru.websiteurl,
    coalesce(ua.q_count,0) as questions,
    coalesce(ua.a_count,0) as answers,
    coalesce(aa.accepted_count,0) as accepted_answers,
    coalesce(ua.post_score,0) as total_post_score,
    coalesce(vu.upvotes_cast,0) as upvotes_cast,
    coalesce(vu.downvotes_cast,0) as downvotes_cast,
    coalesce(vu.favorites_cast,0) as favorites_cast,
    coalesce(vu.bounty_flow,0) as bounty_flow,
    coalesce(cs.comment_count,0) as comments,
    round(cast(coalesce(cs.avg_comment_score,0) as numeric), 3) as avg_comment_score,
    cs.last_comment_at,
    coalesce(bs.gold_badges,0) as gold_badges,
    coalesce(bs.silver_badges,0) as silver_badges,
    coalesce(bs.bronze_badges,0) as bronze_badges,
    coalesce(bs.tag_badges,0) as tag_badges,
    bs.first_badge_at,
    bs.last_badge_at,
    coalesce(pa.linked_count,0) as links_from_posts,
    coalesce(pa.dup_count,0) as duplicates_marked,
    ulq.last_q_id,
    ulq.last_q_title,
    ulq.last_q_at,
    coalesce(ulq.last_q_edit_events,0) as last_q_edit_events,
    coalesce(ulq.last_q_close_events,0) as last_q_close_events,
    coalesce(ulq.last_close_reason_id, -1) as last_close_reason_id,
    t.tagname as top_tag_by_questions,
    coalesce(t.tag_q_count,0) as top_tag_q_count,
    round(cast(coalesce(ad.avg_hours_between_posts, 0) as numeric), 2) as avg_hours_between_posts,
    r.decile_by_post_score,
    round(cast(r.pr_activity_volume as numeric), 4) as pr_activity_volume,
    coalesce(hp.top_posts_count,0) as top_posts_count,
    coalesce(hp.top1_score_posts,0) as top1_score_posts,
    coalesce(hp.running_score_final,0) as running_score_final,
    case
        when coalesce(ua.a_count,0) > coalesce(ua.q_count,0) then 'Answer-heavy'
        when coalesce(ua.q_count,0) > coalesce(ua.a_count,0) then 'Question-heavy'
        when coalesce(ua.q_count,0) = 0 and coalesce(ua.a_count,0) = 0 then 'No posts'
        else 'Balanced'
    end as posting_style,
    case
        when ru.location is not null and (
             lower(ru.location) like '%us%' or lower(ru.location) like '%usa%' or lower(ru.location) like '%united states%'
        ) then 'US'
        when ru.location is not null and (
             lower(ru.location) like '%uk%' or lower(ru.location) like '%united kingdom%' or lower(ru.location) like '%england%' or lower(ru.location) like '%scotland%' or lower(ru.location) like '%wales%' or lower(ru.location) like '%northern ireland%'
        ) then 'UK'
        when ru.location is null or btrim(ru.location) = '' then 'Unknown'
        else 'Other'
    end as location_bucket
from recent_users ru
left join user_activity ua on ua.user_id = ru.id
left join comment_stats cs on cs.user_id = ru.id
left join badge_stats bs on bs.user_id = ru.id
left join accepted_answers aa on aa.user_id = ru.id
left join vote_agg vu on vu.user_id = ru.id
left join postlinks_agg pa on pa.user_id = ru.id
left join user_latest_q ulq on ulq.user_id = ru.id
left join lateral (
    select tagname, tag_q_count
    from top_user_tag tut
    where tut.user_id = ru.id and tut.rn = 1
) t on true
left join activity_density ad on ad.user_id = ru.id
left join rankings r on r.user_id = ru.id
left join heavy_posts hp on hp.user_id = ru.id
where (coalesce(ua.q_count,0) + coalesce(ua.a_count,0) + coalesce(cs.comment_count,0)) > 0
  and (
        ru.rn_global <= 1000
        or coalesce(ua.post_score,0) > (
            select percentile_disc(0.9) within group (order by coalesce(post_score,0))
            from user_activity
        )
      )
order by
    r.decile_by_post_score nulls last,
    coalesce(ua.post_score,0) desc,
    coalesce(aa.accepted_count,0) desc,
    ru.reputation desc,
    ru.id
limit 2000;