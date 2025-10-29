-- {"query": "661.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2847} 
with recent_users as (
    select u.id as user_id,
           u.displayname,
           u.reputation,
           u.location,
           u.creationdate,
           u.lastaccessdate,
           coalesce(nullif(trim(split_part(coalesce(u.websiteurl,''),'/',3)),''), 'unknown') as domain,
           date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as views,
        sum(coalesce(p.commentcount,0)) as comments,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
accepted_answers as (
    select a.owneruserid as user_id,
           count(*) as accepted_count,
           sum(coalesce(a.score,0)) as accepted_score_sum
    from posts q
    join posts a on a.id = q.acceptedanswerid
    where q.posttypeid = 1
      and a.posttypeid = 2
      and a.owneruserid is not null
    group by a.owneruserid
),
votes_by_user as (
    select p.owneruserid as user_id,
           count(*) filter (where v.votetypeid = 2) as upvotes_recv,
           count(*) filter (where v.votetypeid = 3) as downvotes_recv,
           count(*) filter (where v.votetypeid = 8) as bounties_started,
           sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from posts p
    left join votes v on v.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
badges_by_user as (
    select b.userid as user_id,
           count(*) as total_badges,
           count(*) filter (where b.class = 1) as gold_badges,
           count(*) filter (where b.class = 2) as silver_badges,
           count(*) filter (where b.class = 3) as bronze_badges,
           count(*) filter (where b.tagbased = 1) as tag_badges,
           max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_usage as (
    select
        p.owneruserid as user_id,
        lower(trim(regexp_replace(tag, '\s+', '','g'))) as tag,
        count(*) as tag_q_count
    from posts p
    cross join lateral unnest(
        case when p.posttypeid = 1 and p.tags is not null and length(p.tags) >= 2
             then string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
             else array[]::varchar[] end
    ) as tag
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid, lower(trim(regexp_replace(tag, '\s+', '','g')))
),
top_tag_per_user as (
    select user_id, tag, tag_q_count,
           row_number() over (partition by user_id order by tag_q_count desc, tag asc) as rn
    from tag_usage
),
edits_moderation as (
    select ph.userid as user_id,
           count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edit_events,
           count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,31,33,34,35,36)) as mod_events,
           count(*) filter (where ph.posthistorytypeid = 50) as community_bumps
    from posthistory ph
    where ph.userid is not null
    group by ph.userid
),
duplicates_closed as (
    select q.owneruserid as user_id,
           count(*) as dup_closed_by_votes
    from posts q
    join posthistory ph on ph.postid = q.id and ph.posthistorytypeid = 10
    left join closereasontypes crt on crt.id::text = nullif(ph.comment,'')::int
    where q.posttypeid = 1
      and (crt.id = 101 or crt.name ilike '%duplicate%')
    group by q.owneruserid
),
link_network as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as linked_refs,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links
    from postlinks pl
    join posts p on p.id = pl.postid
    where p.owneruserid is not null
    group by p.owneruserid
),
activity_by_month as (
    select
        p.owneruserid as user_id,
        date_trunc('month', p.creationdate) as month,
        count(*) filter (where p.posttypeid = 1) as questions_m,
        count(*) filter (where p.posttypeid = 2) as answers_m,
        sum(coalesce(p.score,0)) as score_m
    from posts p
    where p.owneruserid is not null
      and p.creationdate >= (select max(creationdate) - interval '365 days' from posts)
    group by p.owneruserid, date_trunc('month', p.creationdate)
),
activity_trends as (
    select user_id,
           sum(answers_m) as answers_12m,
           sum(questions_m) as questions_12m,
           sum(score_m) as score_12m,
           avg(answers_m) as avg_answers_pm,
           stddev_pop(answers_m) as std_answers_pm,
           percentile_cont(0.9) within group (order by score_m) as p90_score_m
    from activity_by_month
    group by user_id
),
user_baseline as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.domain,
        ua.q_count,
        ua.a_count,
        ua.post_score,
        ua.views,
        ua.comments,
        aa.accepted_count,
        vb.upvotes_recv,
        vb.downvotes_recv,
        coalesce(vb.bounty_amount_total,0) as bounty_amount_total,
        bb.total_badges,
        bb.gold_badges, bb.silver_badges, bb.bronze_badges, bb.tag_badges,
        em.edit_events, em.mod_events, em.community_bumps,
        dl.dup_closed_by_votes,
        ln.linked_refs, ln.duplicate_links,
        at.answers_12m, at.questions_12m, at.score_12m, at.avg_answers_pm, at.std_answers_pm, at.p90_score_m,
        ua.last_post_activity,
        bb.last_badge_date
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join accepted_answers aa on aa.user_id = ru.user_id
    left join votes_by_user vb on vb.user_id = ru.user_id
    left join badges_by_user bb on bb.user_id = ru.user_id
    left join edits_moderation em on em.user_id = ru.user_id
    left join duplicates_closed dl on dl.user_id = ru.user_id
    left join link_network ln on ln.user_id = ru.user_id
    left join activity_trends at on at.user_id = ru.user_id
),
normalized as (
    select
        ub.*,
        coalesce(ub.a_count,0) + coalesce(ub.q_count,0) as total_posts,
        case when coalesce(ub.a_count,0) > 0 then coalesce(ub.accepted_count,0)::numeric / nullif(ub.a_count,0) else null end as accept_rate,
        case when coalesce(ub.upvotes_recv,0) + coalesce(ub.downvotes_recv,0) > 0
             then ub.upvotes_recv::numeric / nullif(ub.upvotes_recv + ub.downvotes_recv,0)
             else null end as upvote_ratio,
        case when coalesce(ub.views,0) > 0 then ub.post_score::numeric / nullif(ub.views,0) else null end as score_per_view,
        case when coalesce(ub.total_badges,0) > 0 then ub.gold_badges::numeric / nullif(ub.total_badges,0) else 0 end as gold_badge_ratio,
        least(1.0, greatest(0.0, (coalesce(ub.reputation,0)::numeric - 1000) / 9000.0)) as rep_norm,
        extract(epoch from (now() - coalesce(ub.last_post_activity, ub.last_badge_date, ub.creationdate))) / 86400.0 as days_since_last_activity
    from user_baseline ub
),
ranked as (
    select
        n.*,
        coalesce(tt.tag, 'no-top-tag') as top_tag,
        coalesce(tt.tag_q_count, 0) as top_tag_q_count,
        row_number() over (order by
            coalesce(n.accept_rate,0) desc,
            coalesce(n.upvote_ratio,0) desc,
            coalesce(n.answers_12m,0) desc,
            coalesce(n.post_score,0) desc,
            coalesce(n.total_posts,0) desc,
            coalesce(n.total_badges,0) desc
        ) as global_rank,
        dense_rank() over (partition by n.domain order by coalesce(n.post_score,0) desc) as domain_rank,
        rank() over (partition by coalesce(n.location,'unknown') order by coalesce(n.reputation,0) desc) as location_rank,
        sum(coalesce(n.post_score,0)) over (order by n.user_id rows between unbounded preceding and current row) as running_score_sum
    from normalized n
    left join lateral (
        select tag, tag_q_count
        from top_tag_per_user t
        where t.user_id = n.user_id and t.rn = 1
        limit 1
    ) tt on true
),
anomalies as (
    select
        r.user_id,
        (coalesce(r.avg_answers_pm,0) > 3 and coalesce(r.std_answers_pm,0) > 4) as bursty_answerer,
        (coalesce(r.upvote_ratio,0) < 0.4 and coalesce(r.post_score,0) > 50) as controversial,
        (coalesce(r.accept_rate,0) > 0.8 and coalesce(r.a_count,0) >= 10) as highly_accepted
    from ranked r
),
final as (
    select
        r.user_id,
        r.displayname,
        r.reputation,
        r.location,
        r.domain,
        r.q_count,
        r.a_count,
        r.accepted_count,
        r.accept_rate,
        r.post_score,
        r.views,
        r.upvotes_recv,
        r.downvotes_recv,
        r.upvote_ratio,
        r.bounty_amount_total,
        r.total_badges,
        r.gold_badges,
        r.silver_badges,
        r.bronze_badges,
        r.tag_badges,
        r.edit_events,
        r.mod_events,
        r.community_bumps,
        r.dup_closed_by_votes,
        r.linked_refs,
        r.duplicate_links,
        r.answers_12m,
        r.questions_12m,
        r.score_12m,
        r.avg_answers_pm,
        r.std_answers_pm,
        r.p90_score_m,
        r.total_posts,
        r.score_per_view,
        r.gold_badge_ratio,
        r.rep_norm,
        r.days_since_last_activity,
        r.top_tag,
        r.top_tag_q_count,
        r.global_rank,
        r.domain_rank,
        r.location_rank,
        r.running_score_sum,
        a.bursty_answerer,
        a.controversial,
        a.highly_accepted
    from ranked r
    left join anomalies a on a.user_id = r.user_id
)
select *
from final
where
    -- Complex predicate mixing null logic and string ops
    (
        coalesce(accept_rate,0) >= 0.5
        or (post_score > 100 and upvote_ratio is not null and upvote_ratio > 0.6)
        or (top_tag ilike any (array['%sql%','%python%','%java%']) and coalesce(total_posts,0) >= 20)
    )
    and coalesce(domain,'unknown') not in ('localhost','unknown')
    and (location is null or location !~* '(north pole|atlantis)')
    and (
        days_since_last_activity < 365
        or (answers_12m > 12 and p90_score_m >= 2)
    )
order by
    global_rank,
    domain_rank,
    location_rank
limit 250;