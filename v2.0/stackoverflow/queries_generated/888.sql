-- {"query": "888.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2951} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn_recent
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
badge_summaries as (
    select
        b.userid,
        count(*) as total_badges,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from badges b
    group by b.userid
),
user_posts as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as questions,
        count(*) filter (where p.posttypeid = 2) as answers,
        avg(nullif(p.score, 0)) as avg_nonzero_score,
        sum(coalesce(p.viewcount, 0)) as total_views,
        max(p.creationdate) as last_post_date
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
question_stats as (
    select
        q.owneruserid as user_id,
        count(*) as q_count,
        avg(q.viewcount) as avg_views,
        percentile_disc(0.9) within group (order by coalesce(q.viewcount,0)) as p90_views,
        count(*) filter (where q.acceptedanswerid is not null) as accepted_count,
        avg(q.answercount) as avg_answers_per_q,
        sum(case when q.closeddate is not null then 1 else 0 end) as closed_count
    from posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comments_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
vote_activity as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid in (8,9)) as bounties_interactions,
        sum(coalesce(v.bountyamount,0)) as bounty_amount_total
    from votes v
    where v.userid is not null
    group by v.userid
),
post_vote_agg as (
    select
        p.owneruserid as user_id,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes_received,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes_received
    from posts p
    left join votes v
      on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
hot_streaks as (
    select
        p.owneruserid as user_id,
        count(*) as edits_and_events_last_90d,
        min(ph.creationdate) as first_event_dt,
        max(ph.creationdate) as last_event_dt
    from posts p
    join posthistory ph
      on ph.postid = p.id
     and ph.posthistorytypeid in (4,5,6,10,11,12,19,20,24,31,33,34,50,52,53)
    where p.owneruserid is not null
      and ph.creationdate >= (select max(creationdate) - interval '90 days' from posthistory)
    group by p.owneruserid
),
dupe_network as (
    select
        pl.postid,
        pl.relatedpostid,
        pl.linktypeid,
        case when pl.linktypeid = 3 then 1 else 0 end as is_duplicate
    from postlinks pl
),
tag_exploded as (
    select
        p.id as post_id,
        p.owneruserid as user_id,
        lower(trim(t)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as t
    where p.posttypeid = 1
),
top_tags_per_user as (
    select user_id, tag, cnt, rank() over (partition by user_id order by cnt desc, tag) as rk
    from (
        select te.user_id, te.tag, count(*) as cnt
        from tag_exploded te
        group by te.user_id, te.tag
    ) s
),
user_quality_score as (
    select
        u.id as user_id,
        coalesce(bs.gold_badges,0)*5
        + coalesce(bs.silver_badges,0)*2
        + coalesce(bs.bronze_badges,0)*1
        + coalesce(pv.upvotes_received,0)*0.5
        - coalesce(pv.downvotes_received,0)*0.75
        + coalesce(qa.accepted_count,0)*3
        - coalesce(qa.closed_count,0)*2
        + coalesce(ua.answers,0)*0.25
        + least(coalesce(qa.avg_views,0)/100.0, 20) as quality_score
    from users u
    left join badge_summaries bs on bs.userid = u.id
    left join post_vote_agg pv on pv.user_id = u.id
    left join question_stats qa on qa.user_id = u.id
    left join user_posts ua on ua.user_id = u.id
),
activity_windows as (
    select
        u.id as user_id,
        count(*) filter (where p.creationdate >= now() - interval '30 days') as posts_30d,
        count(*) filter (where p.creationdate >= now() - interval '7 days') as posts_7d,
        max(p.creationdate) as last_post_date,
        min(p.creationdate) filter (where p.creationdate >= now() - interval '365 days') as first_post_in_year
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
ranked_users as (
    select
        u.id as user_id,
        row_number() over (order by uq.quality_score desc nulls last, u.reputation desc, u.id) as rank_quality,
        dense_rank() over (order by coalesce(bs.total_badges,0) desc, u.id) as rank_badges,
        ntile(10) over (order by coalesce(pv.upvotes_received,0) - coalesce(pv.downvotes_received,0) desc) as decile_net_votes
    from users u
    left join user_quality_score uq on uq.user_id = u.id
    left join badge_summaries bs on bs.userid = u.id
    left join post_vote_agg pv on pv.user_id = u.id
),
null_sentinels as (
    select
        u.id as user_id,
        case when u.displayname is null or trim(u.displayname) = '' then '(anonymous)' else u.displayname end as safe_displayname,
        case when u.location is null then '(unknown)' when trim(u.location) = '' then '(unknown)' else u.location end as safe_location
    from users u
),
recent_dupe_impacts as (
    select
        q.owneruserid as user_id,
        count(*) filter (where dn.is_duplicate = 1 and q.creationdate >= now() - interval '180 days') as dupes_180d,
        count(distinct dn.relatedpostid) filter (where dn.is_duplicate = 1) as distinct_dupe_targets
    from posts q
    left join dupe_network dn on dn.postid = q.id
    where q.posttypeid = 1 and q.owneruserid is not null
    group by q.owneruserid
),
string_fun as (
    select
        u.id as user_id,
        lower(coalesce(u.displayname, '')) as disp_lower,
        length(coalesce(u.aboutme, '')) as about_len,
        case
            when u.websiteurl ilike 'http%' then split_part(u.websiteurl, '/', 3)
            when u.websiteurl is null or trim(u.websiteurl) = '' then null
            else u.websiteurl
        end as site_host
    from users u
),
top_users as (
    select
        ru.user_id
    from recent_users ru
    join ranked_users rk on rk.user_id = ru.user_id
    where ru.rn_recent <= 500
      and rk.rank_quality <= 1000
)
select
    tu.user_id,
    ns.safe_displayname as displayname,
    ns.safe_location as location,
    ru.websiteurl,
    u.reputation,
    coalesce(bs.total_badges, 0) as total_badges,
    coalesce(bs.gold_badges, 0) as gold_badges,
    coalesce(bs.silver_badges, 0) as silver_badges,
    coalesce(bs.bronze_badges, 0) as bronze_badges,
    coalesce(bs.tag_badges, 0) as tag_badges,
    coalesce(ua.questions, 0) as questions,
    coalesce(ua.answers, 0) as answers,
    coalesce(ua.avg_nonzero_score, 0) as avg_nonzero_post_score,
    coalesce(ua.total_views, 0) as total_post_views,
    qa.q_count as total_questions,
    qa.avg_views as avg_q_views,
    qa.p90_views as p90_q_views,
    qa.accepted_count as accepted_answers_on_qs,
    qa.avg_answers_per_q,
    qa.closed_count as closed_qs,
    coalesce(ca.comments_count, 0) as comments_count,
    coalesce(ca.avg_comment_score, 0) as avg_comment_score,
    pv.upvotes_received - pv.downvotes_received as net_votes_received,
    va.upvotes_cast - va.downvotes_cast as net_votes_cast,
    va.bounties_interactions,
    va.bounty_amount_total,
    hs.edits_and_events_last_90d,
    hs.first_event_dt,
    hs.last_event_dt,
    rdi.dupes_180d,
    rdi.distinct_dupe_targets,
    sw.disp_lower,
    sw.about_len,
    sw.site_host,
    tt.tag as top_tag,
    uq.quality_score,
    rk.rank_quality,
    rk.rank_badges,
    rk.decile_net_votes,
    aw.posts_30d,
    aw.posts_7d,
    aw.last_post_date,
    aw.first_post_in_year,
    greatest(coalesce(u.lastaccessdate, u.creationdate), coalesce(ua.last_post_date, u.creationdate)) as last_seen_or_post,
    case
        when pv.upvotes_received is null and pv.downvotes_received is null then 'no posts'
        when pv.upvotes_received >= coalesce(pv.downvotes_received,0) then 'positive'
        else 'negative'
    end as vote_sentiment,
    case
        when tt.tag is null then 'untagged'
        when tt.tag like '%sql%' then 'db-inclined'
        when tt.tag like '%python%' then 'py-inclined'
        else 'other'
    end as tag_profile
from top_users tu
join users u on u.id = tu.user_id
left join recent_users ru on ru.user_id = tu.user_id
left join null_sentinels ns on ns.user_id = tu.user_id
left join badge_summaries bs on bs.userid = tu.user_id
left join user_posts ua on ua.user_id = tu.user_id
left join question_stats qa on qa.user_id = tu.user_id
left join comment_activity ca on ca.user_id = tu.user_id
left join vote_activity va on va.user_id = tu.user_id
left join post_vote_agg pv on pv.user_id = tu.user_id
left join hot_streaks hs on hs.user_id = tu.user_id
left join recent_dupe_impacts rdi on rdi.user_id = tu.user_id
left join string_fun sw on sw.user_id = tu.user_id
left join user_quality_score uq on uq.user_id = tu.user_id
left join ranked_users rk on rk.user_id = tu.user_id
left join activity_windows aw on aw.user_id = tu.user_id
left join lateral (
    select tag
    from top_tags_per_user ttp
    where ttp.user_id = tu.user_id and ttp.rk = 1
    order by tag
    limit 1
) tt on true
where coalesce(u.reputation, 0) >= 1
  and (
      qa.q_count is null
      or qa.closed_count::numeric / nullif(qa.q_count, 0)::numeric < 0.5
  )
  and (
      coalesce(va.upvotes_cast, 0) + coalesce(va.downvotes_cast, 0)
      >= coalesce(bs.gold_badges, 0)
  )
order by uq.quality_score desc nulls last, u.reputation desc, tu.user_id
limit 200;