-- {"query": "766.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3562} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown.host') as website_host,
        date_trunc('month', u.creationdate) as signup_month,
        row_number() over (order by u.reputation desc, u.id) as rn_global
    from users u
    where u.creationdate >= (select coalesce(max(creationdate), '2000-01-01'::timestamp) - interval '365 days' from users)
),
active_posts as (
    select
        p.id,
        p.posttypeid,
        p.owneruserid,
        p.creationdate,
        p.score,
        p.viewcount,
        p.title,
        p.tags,
        p.acceptedanswerid,
        p.parentid,
        p.closeddate,
        greatest(coalesce(p.lastactivitydate, p.creationdate), p.creationdate) as last_activity
    from posts p
    where p.creationdate >= (select min(creationdate) from recent_users) - interval '30 days'
),
tag_exploded as (
    select
        ap.id as post_id,
        lower(trim(tg)) as tag
    from active_posts ap
    left join lateral (
        select unnest(string_to_array(substring(coalesce(ap.tags,''), 2, greatest(length(coalesce(ap.tags,''))-2,0)), '><')) as tg
    ) s on true
),
user_activity as (
    select
        ru.user_id,
        count(distinct case when ap.posttypeid = 1 then ap.id end) as q_count,
        count(distinct case when ap.posttypeid = 2 then ap.id end) as a_count,
        sum(coalesce(ap.score,0)) as post_score_sum,
        sum(case when ap.viewcount is null then 0 else ap.viewcount end) as views_sum,
        count(*) filter (where ap.closeddate is not null) as closed_posts,
        max(ap.last_activity) as last_post_activity
    from recent_users ru
    left join active_posts ap
        on ap.owneruserid = ru.user_id
    group by ru.user_id
),
vote_stats as (
    select
        v.postid,
        sum(case when v.votetypeid = 2 then 1 else 0 end) as upvotes,
        sum(case when v.votetypeid = 3 then 1 else 0 end) as downvotes,
        sum(case when v.votetypeid = 8 then coalesce(v.bountyamount,0) else 0 end) as bounty_started,
        sum(case when v.votetypeid = 9 then coalesce(v.bountyamount,0) else 0 end) as bounty_awarded,
        count(*) filter (where v.votetypeid in (10,11)) as del_undel_events
    from votes v
    where v.creationdate >= (select min(creationdate) from recent_users) - interval '30 days'
    group by v.postid
),
comment_stats as (
    select
        c.postid,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_at
    from comments c
    where c.creationdate >= (select min(creationdate) from recent_users) - interval '30 days'
    group by c.postid
),
link_dupes as (
    select
        pl.postid,
        count(*) filter (where pl.linktypeid = 3) as duplicate_marks,
        count(*) filter (where pl.linktypeid = 1) as linked_refs,
        count(distinct case when pl.linktypeid = 3 then pl.relatedpostid end) as distinct_dupe_targets
    from postlinks pl
    where pl.creationdate >= (select min(creationdate) from recent_users) - interval '90 days'
    group by pl.postid
),
history_flags as (
    select
        ph.postid,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_events,
        max(ph.creationdate) filter (where ph.posthistorytypeid in (10,11)) as last_close_or_reopen,
        sum(case when ph.posthistorytypeid = 10 and (ph.comment ~ '^[0-9]+$') then 1 else 0 end) as close_votes_with_reason
    from posthistory ph
    where ph.creationdate >= (select min(creationdate) from recent_users) - interval '180 days'
    group by ph.postid
),
badge_tally as (
    select
        b.userid,
        sum(case when b.class = 1 then 1 else 0 end) as gold,
        sum(case when b.class = 2 then 1 else 0 end) as silver,
        sum(case when b.class = 3 then 1 else 0 end) as bronze,
        sum(case when b.tagbased = 1 then 1 else 0 end) as tag_badges,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    where b.date >= (select min(creationdate) from recent_users) - interval '365 days'
    group by b.userid
),
post_engagement as (
    select
        ap.id as post_id,
        ap.owneruserid as user_id,
        coalesce(vs.upvotes,0) as upvotes,
        coalesce(vs.downvotes,0) as downvotes,
        coalesce(cs.comment_count,0) as comments,
        coalesce(cs.comment_score_sum,0) as comment_score_sum,
        coalesce(ld.duplicate_marks,0) as duplicate_marks,
        coalesce(ld.linked_refs,0) as linked_refs,
        coalesce(ld.distinct_dupe_targets,0) as distinct_dupe_targets,
        coalesce(hf.mod_events,0) as mod_events,
        cs.last_comment_at,
        hf.last_close_or_reopen,
        case when ap.posttypeid = 1 then 1 else 0 end as is_question,
        case when ap.posttypeid = 2 then 1 else 0 end as is_answer
    from active_posts ap
    left join vote_stats vs on vs.postid = ap.id
    left join comment_stats cs on cs.postid = ap.id
    left join link_dupes ld on ld.postid = ap.id
    left join history_flags hf on hf.postid = ap.id
),
tag_hotness as (
    select
        te.tag,
        count(*) as tag_posts,
        sum(pe.upvotes - pe.downvotes) as tag_net_votes,
        sum(pe.comments) as tag_comments,
        max(pe.last_comment_at) as tag_last_comment,
        max(ap.creationdate) as tag_last_post,
        percentile_cont(0.5) within group (order by ap.score) as tag_score_median
    from tag_exploded te
    join active_posts ap on ap.id = te.post_id
    left join post_engagement pe on pe.post_id = te.post_id
    group by te.tag
),
user_tag_prefs as (
    select
        ap.owneruserid as user_id,
        te.tag,
        count(*) as tag_uses,
        sum(ap.score) as tag_score_sum,
        sum(pe.upvotes - pe.downvotes) as tag_net_votes,
        sum(pe.comments) as tag_comments
    from tag_exploded te
    join active_posts ap on ap.id = te.post_id
    left join post_engagement pe on pe.post_id = te.post_id
    group by ap.owneruserid, te.tag
),
user_tag_ranked as (
    select
        utp.user_id,
        utp.tag,
        utp.tag_uses,
        utp.tag_score_sum,
        utp.tag_net_votes,
        utp.tag_comments,
        row_number() over (partition by utp.user_id order by utp.tag_uses desc, utp.tag_score_sum desc, utp.tag) as tag_rank
    from user_tag_prefs utp
),
accepted_ratio as (
    select
        q.owneruserid as user_id,
        count(*) filter (where q.acceptedanswerid is not null) as accepted_questions,
        count(*) filter (where q.posttypeid = 1) as total_questions
    from active_posts q
    where q.posttypeid = 1
    group by q.owneruserid
),
answer_accepts as (
    select
        a.owneruserid as user_id,
        count(*) as answers_authored,
        count(*) filter (
            where exists (
                select 1
                from posts q
                where q.id = a.parentid
                  and q.acceptedanswerid = a.id
            )
        ) as answers_accepted
    from active_posts a
    where a.posttypeid = 2
    group by a.owneruserid
),
user_rollup as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.creationdate as user_created,
        ru.location,
        ru.website_host,
        ua.q_count,
        ua.a_count,
        ua.post_score_sum,
        ua.views_sum,
        ua.closed_posts,
        ua.last_post_activity,
        coalesce(ar.accepted_questions,0) as accepted_questions,
        coalesce(ar.total_questions,0) as total_questions,
        coalesce(aa.answers_authored,0) as answers_authored,
        coalesce(aa.answers_accepted,0) as answers_accepted,
        coalesce(bt.gold,0) as gold_badges,
        coalesce(bt.silver,0) as silver_badges,
        coalesce(bt.bronze,0) as bronze_badges,
        coalesce(bt.tag_badges,0) as tag_badges,
        bt.first_badge_date,
        bt.last_badge_date
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join accepted_ratio ar on ar.user_id = ru.user_id
    left join answer_accepts aa on aa.user_id = ru.user_id
    left join badge_tally bt on bt.userid = ru.user_id
),
scored_users as (
    select
        ur.*,
        case
            when coalesce(ur.a_count,0) + coalesce(ur.q_count,0) = 0 then null
            else round(100.0 * coalesce(ur.a_count,0) / nullif(coalesce(ur.a_count,0) + coalesce(ur.q_count,0),0), 2)
        end as pct_answers,
        case
            when ur.total_questions = 0 then null
            else round(100.0 * ur.accepted_questions::numeric / nullif(ur.total_questions,0), 2)
        end as question_accept_rate,
        case
            when ur.answers_authored = 0 then null
            else round(100.0 * ur.answers_accepted::numeric / nullif(ur.answers_authored,0), 2)
        end as answer_accept_rate,
        greatest(coalesce(ur.post_score_sum,0) + (coalesce(ur.views_sum,0) / 50.0) + (coalesce(ur.gold_badges,0) * 25) + (coalesce(ur.silver_badges,0) * 10) + (coalesce(ur.bronze_badges,0) * 3) - (coalesce(ur.closed_posts,0) * 5), 0) as engagement_score
    from user_rollup ur
),
user_top_tags as (
    select
        utr.user_id,
        string_agg(utr.tag || ':' || utr.tag_uses::text, ', ' order by utr.tag_uses desc, utr.tag) filter (where utr.tag_rank <= 5) as top5_tags
    from user_tag_ranked utr
    group by utr.user_id
),
post_quality as (
    select
        pe.post_id,
        pe.user_id,
        round(
            (coalesce(pe.upvotes,0) * 3)
          - (coalesce(pe.downvotes,0) * 2)
          + (coalesce(pe.comments,0) * 0.2)
          + (coalesce(pe.linked_refs,0) * 0.5)
          - (coalesce(pe.duplicate_marks,0) * 4)
          - (coalesce(pe.mod_events,0) * 1.5)
        , 2) as quality_score,
        pe.is_question,
        pe.is_answer
    from post_engagement pe
),
user_quality as (
    select
        pq.user_id,
        avg(pq.quality_score) as avg_quality,
        percentile_cont(0.9) within group (order by pq.quality_score) as p90_quality,
        sum(case when pq.is_question = 1 then pq.quality_score else 0 end) as q_quality_sum,
        sum(case when pq.is_answer = 1 then pq.quality_score else 0 end) as a_quality_sum
    from post_quality pq
    group by pq.user_id
),
ranked as (
    select
        su.user_id,
        su.displayname,
        su.reputation,
        su.location,
        su.website_host,
        su.q_count,
        su.a_count,
        su.post_score_sum,
        su.views_sum,
        su.closed_posts,
        su.last_post_activity,
        su.accepted_questions,
        su.total_questions,
        su.answers_authored,
        su.answers_accepted,
        su.gold_badges,
        su.silver_badges,
        su.bronze_badges,
        su.tag_badges,
        su.first_badge_date,
        su.last_badge_date,
        su.pct_answers,
        su.question_accept_rate,
        su.answer_accept_rate,
        su.engagement_score,
        ut.top5_tags,
        uq.avg_quality,
        uq.p90_quality,
        uq.q_quality_sum,
        uq.a_quality_sum,
        rank() over (order by su.engagement_score desc, coalesce(uq.avg_quality, -999) desc, su.reputation desc) as eng_rank,
        dense_rank() over (order by coalesce(uq.p90_quality, -999) desc) as p90_rank,
        row_number() over (order by su.reputation desc) as rep_rank
    from scored_users su
    left join user_top_tags ut on ut.user_id = su.user_id
    left join user_quality uq on uq.user_id = su.user_id
),
rep_quartiles as (
    select
        r.*,
        ntile(4) over (order by r.reputation desc) as rep_quartile
    from ranked r
)
select
    rq.user_id,
    rq.displayname,
    rq.reputation,
    rq.rep_quartile,
    rq.eng_rank,
    rq.p90_rank,
    rq.rep_rank,
    rq.location,
    rq.website_host,
    rq.q_count,
    rq.a_count,
    rq.post_score_sum,
    rq.views_sum,
    rq.closed_posts,
    rq.accepted_questions,
    rq.total_questions,
    rq.answers_authored,
    rq.answers_accepted,
    rq.pct_answers,
    rq.question_accept_rate,
    rq.answer_accept_rate,
    rq.engagement_score,
    coalesce(rq.avg_quality, 0) as avg_quality,
    coalesce(rq.p90_quality, 0) as p90_quality,
    rq.q_quality_sum,
    rq.a_quality_sum,
    coalesce(rq.top5_tags, '(none)') as top5_tags,
    case
        when rq.rep_quartile = 1 then 'Top 25%'
        when rq.rep_quartile = 2 then '25-50%'
        when rq.rep_quartile = 3 then '50-75%'
        else 'Bottom 25%'
    end as rep_band,
    case
        when rq.engagement_score >= (select avg(engagement_score) from scored_users) then 'above_avg_engagement'
        else 'below_avg_engagement'
    end as engagement_band
from rep_quartiles rq
where (
        rq.eng_rank <= 100
        or rq.p90_rank <= 100
        or (rq.rep_quartile = 1 and rq.engagement_score > 0)
     )
and coalesce(rq.top5_tags, '') not ilike '%discussion%'
and coalesce(rq.location, '') not ilike '%test%'
order by rq.eng_rank nulls last, rq.p90_rank nulls last, rq.reputation desc, rq.user_id
limit 250;