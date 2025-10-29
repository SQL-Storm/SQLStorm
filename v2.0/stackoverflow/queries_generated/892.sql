-- {"query": "892.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2806} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id) as rn_desc
    from users u
),
active_questions as (
    select
        p.id as question_id,
        p.title,
        p.creationdate,
        p.score,
        p.viewcount,
        p.owneruserid,
        p.acceptedanswerid,
        p.tags,
        case when p.closeddate is not null then 1 else 0 end as is_closed
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id as answer_id,
        a.parentid as question_id,
        a.owneruserid as answer_owner_id,
        a.creationdate as answer_created,
        a.score as answer_score
    from posts a
    where a.posttypeid = 2
),
q_stats as (
    select
        q.question_id,
        count(a.answer_id) as total_answers,
        max(a.answer_score) as max_answer_score,
        avg(a.answer_score) filter (where a.answer_score is not null) as avg_answer_score,
        sum(case when a.answer_score > 0 then 1 else 0 end) as positive_answers
    from active_questions q
    left join answers a on a.question_id = q.question_id
    group by q.question_id
),
tag_expanded as (
    select
        q.question_id,
        lower(trim(both ' ' from t.tag)) as tag
    from active_questions q
    cross join lateral unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as t(tag)
),
tag_rank as (
    select
        te.tag,
        count(*) as tag_q_count,
        dense_rank() over (order by count(*) desc) as tag_pop_rank
    from tag_expanded te
    group by te.tag
),
user_badges as (
    select
        b.userid,
        count(*) as badge_count,
        sum(case when b.class = 1 then 1 else 0 end) as gold_badges,
        sum(case when b.class = 2 then 1 else 0 end) as silver_badges,
        sum(case when b.class = 3 then 1 else 0 end) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
vote_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        max(v.creationdate) as last_vote_date
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comments,
        avg(nullif(c.score,0)) as avg_nonzero_comment_score,
        max(c.creationdate) as last_comment_date,
        string_agg(distinct coalesce(nullif(trim(c.userdisplayname), ''), 'anon'), ', ' order by coalesce(c.userdisplayname, '')) as distinct_commenters
    from comments c
    group by c.postid
),
close_events as (
    select
        ph.postid,
        min(ph.creationdate) as first_close_date,
        max(ph.creationdate) as last_close_date,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events
    from posthistory ph
    where ph.posthistorytypeid in (10, 11) -- closed / reopened
    group by ph.postid
),
dup_links as (
    select
        pl.postid as dup_of_question_id,
        count(*) as duplicates_count,
        min(pl.creationdate) as first_dup_link_date
    from postlinks pl
    where pl.linktypeid = 3
    group by pl.postid
),
hot_bumps as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
        count(*) filter (where ph.posthistorytypeid = 52) as hot_selected,
        count(*) filter (where ph.posthistorytypeid = 53) as hot_removed
    from posthistory ph
    where ph.posthistorytypeid in (50,52,53)
    group by ph.postid
),
owner_activity as (
    select
        u.id as owner_id,
        count(*) filter (where p.posttypeid = 1) as owner_qs,
        count(*) filter (where p.posttypeid = 2) as owner_as,
        sum(coalesce(p.score,0)) as owner_total_post_score,
        max(p.lastactivitydate) as owner_last_activity
    from users u
    left join posts p on p.owneruserid = u.id
    group by u.id
),
recent_q as (
    select
        q.*,
        qa.total_answers,
        qa.max_answer_score,
        qa.avg_answer_score,
        te.tag,
        tr.tag_pop_rank,
        coalesce(v.upvotes,0) as upvotes,
        coalesce(v.downvotes,0) as downvotes,
        coalesce(v.bounty_started,0) as bounty_started,
        coalesce(v.bounty_awarded,0) as bounty_awarded,
        ca.comments,
        ca.avg_nonzero_comment_score,
        ca.last_comment_date,
        du.duplicates_count,
        ce.first_close_date,
        ce.last_close_date,
        hb.community_bumps,
        hb.hot_selected,
        hb.hot_removed
    from active_questions q
    left join q_stats qa on qa.question_id = q.question_id
    left join vote_agg v on v.postid = q.question_id
    left join comment_agg ca on ca.postid = q.question_id
    left join dup_links du on du.dup_of_question_id = q.question_id
    left join close_events ce on ce.postid = q.question_id
    left join hot_bumps hb on hb.postid = q.question_id
    left join tag_expanded te on te.question_id = q.question_id
    left join tag_rank tr on tr.tag = te.tag
),
accepted_answer_latency as (
    select
        q.question_id,
        case
            when q.acceptedanswerid is null then null
            else (
                select extract(epoch from (a.creationdate - q.creationdate))::bigint
                from posts a
                where a.id = q.acceptedanswerid
                and a.posttypeid = 2
            )
        end as accepted_latency_seconds
    from active_questions q
),
owner_enriched as (
    select
        u.id as owner_id,
        u.displayname as owner_name,
        u.reputation as owner_rep,
        coalesce(ub.badge_count,0) as badge_count,
        coalesce(ub.gold_badges,0) as gold_badges,
        coalesce(ub.silver_badges,0) as silver_badges,
        coalesce(ub.bronze_badges,0) as bronze_badges,
        ua.owner_qs,
        ua.owner_as,
        ua.owner_total_post_score,
        ua.owner_last_activity
    from users u
    left join user_badges ub on ub.userid = u.id
    left join owner_activity ua on ua.owner_id = u.id
),
ranked_questions as (
    select
        rq.*,
        aal.accepted_latency_seconds,
        oe.owner_name,
        oe.owner_rep,
        oe.badge_count,
        oe.gold_badges,
        oe.silver_badges,
        oe.bronze_badges,
        oe.owner_qs,
        oe.owner_as,
        oe.owner_total_post_score,
        oe.owner_last_activity,
        sum(coalesce(rq.viewcount,0)) over (partition by rq.owneruserid order by rq.creationdate rows between unbounded preceding and current row) as owner_cum_views,
        row_number() over (partition by rq.owneruserid order by rq.score desc nulls last, rq.viewcount desc nulls last, rq.creationdate desc) as owner_q_rank_by_score,
        percent_rank() over (order by coalesce(rq.score,0) desc, coalesce(rq.viewcount,0) desc) as global_percentile,
        case
            when rq.is_closed = 1 and coalesce(rq.viewcount,0) > 0 then rq.score::numeric / nullif(rq.viewcount,0)
            when rq.is_closed = 0 and coalesce(rq.viewcount,0) > 100 then (rq.score + coalesce(rq.upvotes,0) - coalesce(rq.downvotes,0))::numeric / nullif(rq.viewcount,0)
            else null
        end as engagement_ratio
    from recent_q rq
    left join accepted_answer_latency aal on aal.question_id = rq.question_id
    left join owner_enriched oe on oe.owner_id = rq.owneruserid
),
owner_top_tags as (
    select
        rq.owneruserid,
        rq.tag,
        count(*) as tag_count_for_owner,
        row_number() over (partition by rq.owneruserid order by count(*) desc, min(rq.creationdate)) as tag_rank_for_owner
    from recent_q rq
    group by rq.owneruserid, rq.tag
),
final_scored as (
    select
        rq.*,
        ot.tag as owner_top_tag,
        case
            when rq.owner_rep >= 100000 then 'legend'
            when rq.owner_rep >= 25000 then 'expert'
            when rq.owner_rep >= 5000 then 'seasoned'
            when rq.owner_rep >= 1000 then 'regular'
            else 'newbie'
        end as owner_segment,
        (
            coalesce(rq.score,0)*3
            + coalesce(rq.upvotes,0)*2
            - coalesce(rq.downvotes,0)
            + coalesce(rq.viewcount,0)/50
            + coalesce(rq.positive_answers,0)*5
            + least(coalesce(rq.tag_pop_rank,1000), 1000) * -0.1
            + case when rq.community_bumps > 0 then 10 else 0 end
            + case when rq.hot_selected > 0 then 25 else 0 end
            - case when rq.hot_removed > 0 then 5 else 0 end
            + case when rq.is_closed = 1 then -15 else 0 end
        )::numeric as composite_score
    from ranked_questions rq
    left join owner_top_tags ot
      on ot.owneruserid = rq.owneruserid
     and ot.tag_rank_for_owner = 1
),
dedup as (
    select
        fs.*,
        row_number() over (
            partition by question_id
            order by composite_score desc nulls last, creationdate desc
        ) as keep_one
    from final_scored fs
)
select
    d.question_id,
    d.title,
    d.creationdate,
    d.owneruserid,
    d.owner_name,
    d.owner_rep,
    d.owner_segment,
    d.badge_count,
    d.gold_badges,
    d.silver_badges,
    d.bronze_badges,
    d.owner_qs,
    d.owner_as,
    d.owner_total_post_score,
    d.owner_last_activity,
    d.tag as sample_tag,
    d.owner_top_tag,
    d.tag_pop_rank,
    d.total_answers,
    d.max_answer_score,
    round(d.avg_answer_score::numeric, 2) as avg_answer_score,
    d.accepted_latency_seconds,
    d.viewcount,
    d.upvotes,
    d.downvotes,
    d.bounty_started,
    d.bounty_awarded,
    coalesce(d.comments,0) as comments,
    d.avg_nonzero_comment_score,
    d.last_comment_date,
    d.duplicates_count,
    d.first_close_date,
    d.last_close_date,
    d.community_bumps,
    d.hot_selected,
    d.hot_removed,
    d.owner_cum_views,
    d.owner_q_rank_by_score,
    round(d.global_percentile::numeric, 4) as global_percentile,
    round(coalesce(d.engagement_ratio, 0)::numeric, 6) as engagement_ratio,
    round(d.composite_score, 2) as composite_score
from dedup d
where d.keep_one = 1
and (
    d.creationdate >= (select max(u.creationdate) - interval '365 days' from users u)
    or d.global_percentile >= 0.9
    or d.bounty_awarded > 0
)
order by d.composite_score desc nulls last, d.creationdate desc
limit 500;