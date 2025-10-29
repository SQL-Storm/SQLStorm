with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.location,
        u.creationdate,
        date_trunc('month', u.creationdate) as cohort_month,
        row_number() over (partition by coalesce(nullif(trim(lower(u.location)), ''), 'unknown') order by u.reputation desc, u.id) as rn_loc_rep
    from users u
    where u.creationdate >= cast('2024-10-01 12:34:56' as timestamp) - interval '5 years'
),
questions as (
    select
        p.id as qid,
        p.owneruserid as asker_id,
        p.creationdate as q_created,
        p.score as q_score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.closeddate,
        p.communityowneddate,
        coalesce(p.answercount, 0) as answercount
    from posts p
    where p.posttypeid = 1
),
answers as (
    select
        a.id as aid,
        a.parentid as qid,
        a.owneruserid as answerer_id,
        a.creationdate as a_created,
        a.score as a_score
    from posts a
    where a.posttypeid = 2
),
first_answer as (
    select
        q.qid,
        min(a.a_created) as first_answer_time
    from questions q
    left join answers a on a.qid = q.qid
    group by q.qid
),
votes_agg as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        sum(case when v.votetypeid in (8,9) then coalesce(v.bountyamount,0) else 0 end) as bounty_total,
        min(case when v.votetypeid = 2 then v.creationdate end) as first_upvote_at
    from votes v
    group by v.postid
),
comment_agg as (
    select
        c.postid,
        count(*) as comments,
        avg(nullif(c.score,0)) as avg_nonzero_comment_score,
        max(c.creationdate) as last_comment_at,
        count(*) filter (where c.userid is null) as anon_comments
    from comments c
    group by c.postid
),
link_dupes as (
    select
        pl.postid as dupe_postid,
        count(*) filter (where pl.linktypeid = 3) as dup_links,
        count(*) filter (where pl.linktypeid = 1) as linked_links,
        max(pl.creationdate) as last_link_date
    from postlinks pl
    group by pl.postid
),
posthistory_flags as (
    select
        ph.postid,
        sum(case when ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35,36,37,38) then 1 else 0 end) as mod_events,
        max(case when ph.posthistorytypeid = 10 then ph.creationdate end) as closed_at,
        count(*) filter (where ph.posthistorytypeid = 50) as community_bumps,
        count(*) filter (where ph.posthistorytypeid in (52,53)) as hot_events
    from posthistory ph
    group by ph.postid
),
user_badges as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as golds,
        sum(case when b.class = 2 then 1 else 0 end) as silvers,
        sum(case when b.class = 3 then 1 else 0 end) as bronzes,
        count(*) filter (where b.tagbased = true) as tag_badges,
        min(b.date) as first_badge_date
    from badges b
    group by b.userid
),
tag_expand as (
    select
        q.qid,
        unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as tagname
    from questions q
    where q.tags is not null and length(q.tags) > 2
),
tag_stats as (
    select
        te.qid,
        count(*) as tag_count,
        min(t.count) as min_tag_popularity,
        max(t.count) as max_tag_popularity,
        cast(avg(t.count) as bigint) as avg_tag_popularity
    from tag_expand te
    left join tags t on lower(t.tagname) = lower(te.tagname)
    group by te.qid
),
accepted_answer_latency as (
    select
        q.qid,
        case
            when q.acceptedanswerid is not null then
                cast(extract(epoch from (
                    (select a2.a_created from answers a2 where a2.aid = q.acceptedanswerid) - q.q_created
                )) as bigint)
            else null
        end as accept_latency_seconds
    from questions q
),
activity_window as (
    select
        q.qid,
        q.asker_id,
        q.q_created,
        q.q_score,
        q.viewcount,
        q.title,
        q.answercount,
        v.upvotes,
        v.downvotes,
        v.favorites,
        v.bounty_total,
        ca.comments,
        ca.avg_nonzero_comment_score,
        ca.last_comment_at,
        ld.dup_links,
        ld.linked_links,
        ph.mod_events,
        ph.closed_at,
        ph.community_bumps,
        ph.hot_events,
        fa.first_answer_time,
        aal.accept_latency_seconds,
        ts.tag_count,
        ts.min_tag_popularity,
        ts.max_tag_popularity,
        ts.avg_tag_popularity,
        row_number() over (partition by q.asker_id order by q.q_created) as rn_by_user,
        lag(q.q_created) over (partition by q.asker_id order by q.q_created) as prev_q_time,
        lead(q.q_created) over (partition by q.asker_id order by q.q_created) as next_q_time,
        sum(coalesce(v.upvotes,0) - coalesce(v.downvotes,0)) over (partition by q.asker_id rows between unbounded preceding and current row) as cum_net_votes_by_user,
        avg(q.q_score) over (partition by date_trunc('month', q.q_created)) as avg_monthly_qscore
    from questions q
    left join votes_agg v on v.postid = q.qid
    left join comment_agg ca on ca.postid = q.qid
    left join link_dupes ld on ld.dupe_postid = q.qid
    left join posthistory_flags ph on ph.postid = q.qid
    left join first_answer fa on fa.qid = q.qid
    left join accepted_answer_latency aal on aal.qid = q.qid
    left join tag_stats ts on ts.qid = q.qid
),
user_enriched as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.location,
        ru.cohort_month,
        ru.rn_loc_rep,
        ub.golds,
        ub.silvers,
        ub.bronzes,
        ub.tag_badges,
        ub.first_badge_date,
        coalesce(ub.golds,0) + coalesce(ub.silvers,0) + coalesce(ub.bronzes,0) as total_badges
    from recent_users ru
    left join user_badges ub on ub.userid = ru.user_id
),
answerer_interactions as (
    select
        q.qid,
        count(distinct a.answerer_id) as distinct_answerers,
        max(a.a_score) as max_answer_score,
        sum(case when a.a_score > 0 then 1 else 0 end) as positive_answers,
        min(a.a_created) as first_answer_at,
        max(a.a_created) as last_answer_at
    from questions q
    left join answers a on a.qid = q.qid
    group by q.qid
),
quality_bucket as (
    select
        aw.qid,
        case
            when coalesce(aw.q_score,0) >= 10 and coalesce(aw.upvotes,0) - coalesce(aw.downvotes,0) >= 15 and coalesce(aw.viewcount,0) >= 1000 then 'excellent'
            when coalesce(aw.q_score,0) >= 3 and coalesce(aw.viewcount,0) >= 200 then 'good'
            when coalesce(aw.q_score,0) < 0 or aw.closed_at is not null then 'problematic'
            else 'average'
        end as quality_band
    from activity_window aw
),
cohort_activity as (
    select
        ue.user_id,
        date_trunc('month', aw.q_created) as activity_month,
        count(*) as questions_in_month,
        sum(coalesce(aw.upvotes,0)) as up_in_month,
        sum(coalesce(aw.downvotes,0)) as down_in_month
    from user_enriched ue
    left join activity_window aw on aw.asker_id = ue.user_id
    group by ue.user_id, date_trunc('month', aw.q_created)
),
ranked_questions as (
    select
        aw.qid,
        aw.asker_id,
        aw.q_created,
        aw.q_score,
        aw.viewcount,
        aw.title,
        aw.answercount,
        aw.upvotes,
        aw.downvotes,
        aw.favorites,
        aw.bounty_total,
        aw.comments,
        aw.avg_nonzero_comment_score,
        aw.last_comment_at,
        aw.dup_links,
        aw.linked_links,
        aw.mod_events,
        aw.closed_at,
        aw.community_bumps,
        aw.hot_events,
        aw.first_answer_time,
        aw.accept_latency_seconds,
        aw.tag_count,
        aw.min_tag_popularity,
        aw.max_tag_popularity,
        aw.avg_tag_popularity,
        aw.rn_by_user,
        aw.prev_q_time,
        aw.next_q_time,
        aw.cum_net_votes_by_user,
        aw.avg_monthly_qscore,
        ue.displayname,
        ue.reputation,
        ue.location,
        ue.cohort_month,
        ue.rn_loc_rep,
        ue.total_badges,
        ai.distinct_answerers,
        ai.max_answer_score,
        ai.positive_answers,
        qb.quality_band,
        sum(coalesce(aw.viewcount,0)) over (partition by ue.user_id order by aw.q_created rows between unbounded preceding and current row) as cum_views_by_user,
        dense_rank() over (order by coalesce(aw.bounty_total,0) desc, coalesce(aw.upvotes,0) desc, coalesce(aw.viewcount,0) desc, aw.q_created desc) as global_rank,
        v.first_upvote_at
    from activity_window aw
    left join user_enriched ue on ue.user_id = aw.asker_id
    left join answerer_interactions ai on ai.qid = aw.qid
    left join quality_bucket qb on qb.qid = aw.qid
    left join votes_agg v on v.postid = aw.qid
),
null_logic_demo as (
    select
        rq.qid,
        rq.asker_id,
        rq.q_created,
        rq.q_score,
        rq.viewcount,
        rq.title,
        rq.answercount,
        rq.upvotes,
        rq.downvotes,
        rq.favorites,
        rq.bounty_total,
        rq.comments,
        rq.avg_nonzero_comment_score,
        rq.last_comment_at,
        rq.dup_links,
        rq.linked_links,
        rq.mod_events,
        rq.closed_at,
        rq.community_bumps,
        rq.hot_events,
        rq.first_answer_time,
        rq.accept_latency_seconds,
        rq.tag_count,
        rq.min_tag_popularity,
        rq.max_tag_popularity,
        rq.avg_tag_popularity,
        rq.rn_by_user,
        rq.prev_q_time,
        rq.next_q_time,
        rq.cum_net_votes_by_user,
        rq.avg_monthly_qscore,
        rq.displayname,
        rq.reputation,
        rq.location,
        rq.cohort_month,
        rq.rn_loc_rep,
        rq.total_badges,
        rq.distinct_answerers,
        rq.max_answer_score,
        rq.positive_answers,
        rq.quality_band,
        rq.cum_views_by_user,
        rq.global_rank,
        rq.first_upvote_at,
        case
            when coalesce(nullif(trim(rq.title), ''), '(untitled)') ilike '%why%' then 1 else 0
        end as title_has_why,
        coalesce(rq.accept_latency_seconds, cast(extract(epoch from (rq.first_answer_time - rq.q_created)) as bigint)) as first_response_latency_seconds,
        coalesce(rq.favorites, 0) + case when rq.q_score > 0 then rq.q_score else 0 end as popularity_proxy,
        coalesce(rq.upvotes,0) - coalesce(rq.downvotes,0) as net_votes,
        case when rq.closed_at is not null or rq.mod_events > 0 then true else false end as had_moderation,
        greatest(
            coalesce(rq.max_answer_score, -2147483648),
            coalesce(rq.q_score, -2147483648)
        ) as best_score_any
    from ranked_questions rq
),
final_set as (
    select
        'top' as bucket,
        n.*
    from null_logic_demo n
    where n.global_rank <= 500

    union all

    select
        'recent_low' as bucket,
        n.*
    from null_logic_demo n
    where n.q_created >= cast('2024-10-01 12:34:56' as timestamp) - interval '90 days'
      and coalesce(n.net_votes,0) <= 0

    union all

    select
        'random_sample' as bucket,
        n.*
    from null_logic_demo n
    where (n.qid % 97) in (3,7,41)
)
select
    fs.bucket,
    fs.qid,
    fs.q_created,
    fs.title,
    substring(coalesce(fs.title, ''), 1, 80) as title_prefix,
    fs.asker_id,
    fs.displayname,
    fs.location,
    fs.reputation,
    fs.total_badges,
    fs.tag_count,
    fs.avg_tag_popularity,
    fs.viewcount,
    fs.q_score,
    fs.net_votes,
    fs.favorites,
    fs.bounty_total,
    fs.comments,
    -- anon_comments removed because it was not available in the final set
    fs.first_upvote_at,
    fs.first_answer_time,
    fs.first_response_latency_seconds,
    fs.accept_latency_seconds,
    fs.distinct_answerers,
    fs.max_answer_score,
    fs.positive_answers,
    fs.quality_band,
    fs.had_moderation,
    fs.community_bumps,
    fs.hot_events,
    fs.cum_net_votes_by_user,
    fs.cum_views_by_user,
    fs.global_rank,
    fs.avg_monthly_qscore,
    fs.prev_q_time,
    fs.next_q_time,
    fs.title_has_why,
    case when fs.closed_at is null then 'open' else 'closed' end as open_state,
    coalesce(nullif(trim(lower(fs.location)), ''), 'unknown') as norm_location,
    case
        when fs.viewcount is null then null
        when fs.viewcount <= 100 then 'low'
        when fs.viewcount <= 1000 then 'medium'
        when fs.viewcount <= 10000 then 'high'
        else 'viral'
    end as view_bucket
from final_set fs
where
    (
        fs.bucket = 'top'
        or (fs.bucket = 'recent_low' and fs.had_moderation = false)
        or (fs.bucket = 'random_sample' and fs.title_has_why = 0)
    )
    and coalesce(fs.tag_count,0) between 0 and 10
    and (fs.bounty_total is null or fs.bounty_total >= 0)
order by
    fs.bucket,
    fs.global_rank nulls last,
    fs.q_created desc
limit 2000;