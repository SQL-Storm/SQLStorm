-- {"query": "951.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2928} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        u.upvotes,
        u.downvotes,
        u.views,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as website_host
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
post_activity as (
    select
        p.id as post_id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.answercount,
        p.commentcount,
        p.favoritecount,
        p.closeddate,
        p.title,
        p.tags,
        case when p.posttypeid = 1 and p.acceptedanswerid is not null then 1 else 0 end as has_accepted_answer
    from posts p
),
user_posts as (
    select
        ru.user_id,
        count(*) filter (where pa.posttypeid = 1) as q_count,
        count(*) filter (where pa.posttypeid = 2) as a_count,
        sum(pa.score) as total_post_score,
        sum(pa.viewcount) as total_views,
        avg(nullif(pa.score, 0)) as avg_nonzero_score,
        max(pa.creationdate) as last_post_date,
        sum(case when pa.posttypeid = 1 and pa.has_accepted_answer = 1 then 1 else 0 end) as accepted_questions,
        sum(case when pa.posttypeid = 1 and pa.closeddate is not null then 1 else 0 end) as closed_questions
    from recent_users ru
    left join post_activity pa
      on pa.owneruserid = ru.user_id
    group by ru.user_id
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold,
        count(*) filter (where b.class = 2) as silver,
        count(*) filter (where b.class = 3) as bronze,
        count(*) filter (where b.tagbased = 1) as tag_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
tag_exploded as (
    select
        p.id as post_id,
        lower(trim(tg)) as tag
    from posts p
    cross join lateral unnest(
        case
            when p.tags is null then array[]::varchar[]
            when length(p.tags) <= 2 then array[]::varchar[]
            else string_to_array(substring(p.tags, 2, length(p.tags)-2), '><')
        end
    ) as tg
    where p.posttypeid = 1
),
user_top_tags as (
    select
        pa.owneruserid as user_id,
        te.tag,
        count(*) as uses,
        row_number() over (partition by pa.owneruserid order by count(*) desc, min(pa.creationdate)) as rn
    from post_activity pa
    join tag_exploded te on te.post_id = pa.id
    where pa.posttypeid = 1
    group by pa.owneruserid, te.tag
),
user_top_tag_pivot as (
    select
        user_id,
        max(case when rn = 1 then tag end) as top_tag_1,
        max(case when rn = 2 then tag end) as top_tag_2
    from user_top_tags
    where rn <= 2
    group by user_id
),
votes_agg as (
    select
        v.postid,
        count(*) filter (where v.votetypeid = 2) as upvotes,
        count(*) filter (where v.votetypeid = 3) as downvotes,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comment_count,
        max(c.creationdate) as last_comment_date
    from comments c
    group by c.postid
),
post_quality as (
    select
        pa.id as post_id,
        pa.owneruserid as user_id,
        pa.posttypeid,
        coalesce(v.upvotes,0) - coalesce(v.downvotes,0) as net_votes,
        coalesce(v.bounty_amount_total,0) as bounty_total,
        coalesce(c.comment_count,0) as comments,
        greatest(pa.score, coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) as score_or_votes,
        case
            when pa.posttypeid = 1 then
                (coalesce(pa.viewcount,0) * 0.0005)
                + (case when pa.has_accepted_answer = 1 then 5 else 0 end)
                + least(coalesce(pa.answercount,0), 10) * 0.7
            else
                least(coalesce(pa.score,0), 25) * 0.8
        end
        + least(coalesce(c.comment_count,0), 8) * 0.2
        + least(greatest(coalesce(v.upvotes,0) - coalesce(v.downvotes,0), 0), 50) * 0.3
        as quality_score
    from post_activity pa
    left join votes_agg v on v.postid = pa.id
    left join comment_agg c on c.postid = pa.id
),
user_quality as (
    select
        pq.user_id,
        avg(pq.quality_score) filter (where pq.posttypeid = 1) as avg_q_quality,
        avg(pq.quality_score) filter (where pq.posttypeid = 2) as avg_a_quality,
        percentile_cont(0.9) within group (order by pq.quality_score) as p90_quality,
        sum(pq.quality_score) as total_quality
    from post_quality pq
    group by pq.user_id
),
recent_closures as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 10) as close_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen
    from posthistory ph
    where ph.posthistorytypeid in (10,11)
    group by ph.postid
),
duplicates as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as dup_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links
    from postlinks pl
    group by pl.postid
),
question_summary as (
    select
        q.id as question_id,
        q.owneruserid as user_id,
        q.title,
        q.creationdate,
        coalesce(v.upvotes,0) as up,
        coalesce(v.downvotes,0) as down,
        coalesce(d.dup_links,0) as dup_links,
        coalesce(rc.close_events,0) as closes,
        coalesce(rc.reopen_events,0) as reopens,
        coalesce(rc.last_close_or_reopen, q.creationdate) as last_moderation_date,
        case
            when position('how' in lower(coalesce(q.title,''))) > 0 then 1 else 0
        end as is_how_question
    from posts q
    left join votes_agg v on v.postid = q.id
    left join recent_closures rc on rc.postid = q.id
    left join duplicates d on d.postid = q.id
    where q.posttypeid = 1
),
activity_rank as (
    select
        ru.user_id,
        dense_rank() over (order by coalesce(upvotes,0) - coalesce(downvotes,0) desc, ru.reputation desc) as karma_rank,
        dense_rank() over (order by ru.views desc) as views_rank,
        dense_rank() over (order by extract(epoch from (now() - ru.creationdate)) asc) as newest_rank
    from recent_users ru
),
thresholds as (
    select
        (select percentile_cont(0.75) within group (order by reputation) from recent_users) as rep_p75,
        (select percentile_cont(0.50) within group (order by coalesce(total_quality,0)) from user_quality) as qual_p50,
        (select percentile_cont(0.80) within group (order by coalesce(q_count + a_count,0)) from user_posts) as activity_p80
),
joined as (
    select
        ru.user_id,
        ru.displayname,
        ru.location,
        ru.website_host,
        ru.reputation,
        ru.upvotes,
        ru.downvotes,
        up.q_count,
        up.a_count,
        up.total_post_score,
        up.total_views,
        up.avg_nonzero_score,
        up.last_post_date,
        up.accepted_questions,
        up.closed_questions,
        ub.badge_count,
        ub.gold,
        ub.silver,
        ub.bronze,
        ub.tag_badges,
        ub.last_badge_date,
        coalesce(ut.top_tag_1, '(none)') as top_tag_1,
        coalesce(ut.top_tag_2, '(none)') as top_tag_2,
        uq.avg_q_quality,
        uq.avg_a_quality,
        uq.p90_quality,
        uq.total_quality,
        ar.karma_rank,
        ar.views_rank,
        ar.newest_rank,
        -- correlated subquery: most controversial recent question title snippet
        (
            select substring(qs.title from 1 for 80)
            from question_summary qs
            where qs.user_id = ru.user_id
            order by (qs.up + qs.down) desc nulls last, qs.closes desc, qs.dup_links desc, qs.creationdate desc
            limit 1
        ) as hottest_question_snippet,
        -- correlated aggregation: recent moderation footprint
        (
            select coalesce(sum(qs.closes) - sum(qs.reopens), 0)
            from question_summary qs
            where qs.user_id = ru.user_id
              and qs.creationdate >= now() - interval '180 days'
        ) as net_recent_closures,
        -- NULL logic and expression-heavy score
        (
            coalesce(uq.total_quality, 0)
            + coalesce(ub.gold,0) * 10 + coalesce(ub.silver,0) * 4 + coalesce(ub.bronze,0) * 1
            + coalesce(up.accepted_questions,0) * 3
            + case when coalesce(up.closed_questions,0) > 5 then -5 else 0 end
            + greatest(least(coalesce(up.total_views,0) / 1000.0, 50), 0)
            + (coalesce(ru.upvotes,0) - coalesce(ru.downvotes,0)) * 0.2
        ) as composite_score
    from recent_users ru
    left join user_posts up on up.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join user_top_tag_pivot ut on ut.user_id = ru.user_id
    left join user_quality uq on uq.user_id = ru.user_id
    left join activity_rank ar on ar.user_id = ru.user_id
),
filtered as (
    select
        j.*,
        t.rep_p75,
        t.qual_p50,
        t.activity_p80,
        case
            when j.reputation >= t.rep_p75
             and coalesce(j.total_quality,0) >= t.qual_p50
             and coalesce(j.q_count + j.a_count,0) >= t.activity_p80
            then 1 else 0
        end as is_power_user
    from joined j
    cross join thresholds t
),
ranked as (
    select
        f.*,
        row_number() over (
            partition by f.is_power_user
            order by f.composite_score desc, f.p90_quality desc nulls last, f.karma_rank asc, f.views_rank asc, f.newest_rank asc
        ) as rn
    from filtered f
)
select
    r.is_power_user,
    r.user_id,
    r.displayname,
    coalesce(nullif(r.location,''), 'unspecified') as location,
    r.website_host,
    r.reputation,
    r.q_count,
    r.a_count,
    r.badge_count,
    r.gold,
    r.silver,
    r.bronze,
    r.top_tag_1,
    r.top_tag_2,
    round(coalesce(r.avg_q_quality,0)::numeric, 2) as avg_q_quality,
    round(coalesce(r.avg_a_quality,0)::numeric, 2) as avg_a_quality,
    round(coalesce(r.p90_quality,0)::numeric, 2) as p90_quality,
    round(r.composite_score::numeric, 2) as composite_score,
    r.hottest_question_snippet,
    r.net_recent_closures,
    r.last_post_date,
    r.last_badge_date
from ranked r
where r.rn <= 50
order by r.is_power_user desc, r.composite_score desc, r.user_id asc;