-- {"query": "129.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3275} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(split_part(coalesce(u.websiteurl, ''), '/', 3)), ''), 'unknown') as domain_host,
        date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        ru.user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        count(distinct date_trunc('day', p.creationdate)) as active_days,
        sum(coalesce(p.score,0)) as post_score,
        sum(coalesce(p.viewcount,0)) as views,
        max(p.lastactivitydate) as last_post_activity
    from recent_users ru
    left join posts p
      on p.owneruserid = ru.user_id
     and p.creationdate >= ru.creationdate
    group by ru.user_id
),
user_votes as (
    select
        ru.user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 8) as bounties_started,
        sum(coalesce(v.bountyamount,0)) filter (where v.votetypeid in (8,9)) as bounty_amount_total
    from recent_users ru
    left join votes v
      on v.userid = ru.user_id
     and v.creationdate >= ru.creationdate
    group by ru.user_id
),
user_badges as (
    select
        ru.user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        count(*) filter (where b.tagbased = 1) as tag_badges
    from recent_users ru
    left join badges b
      on b.userid = ru.user_id
     and b.date >= ru.creationdate
    group by ru.user_id
),
question_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as questions,
        avg(p.score) as avg_q_score,
        percentile_cont(0.5) within group (order by p.score) as med_q_score,
        avg(p.viewcount) as avg_q_views,
        count(*) filter (where p.acceptedanswerid is not null) as accepted_count
    from posts p
    where p.posttypeid = 1
      and p.owneruserid is not null
    group by p.owneruserid
),
answer_metrics as (
    select
        p.owneruserid as user_id,
        count(*) as answers,
        avg(p.score) as avg_a_score,
        percentile_cont(0.5) within group (order by p.score) as med_a_score
    from posts p
    where p.posttypeid = 2
      and p.owneruserid is not null
    group by p.owneruserid
),
comment_activity as (
    select
        ru.user_id,
        count(c.id) as comment_count,
        avg(c.score) as avg_comment_score,
        max(c.creationdate) as last_comment
    from recent_users ru
    left join comments c
      on c.userid = ru.user_id
    group by ru.user_id
),
tag_expertise as (
    select
        p.owneruserid as user_id,
        lower(trim(both '<>' from unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><')))) as tagname,
        count(*) as tag_posts,
        avg(p.score) as tag_avg_score
    from posts p
    where p.posttypeid in (1,2)
      and p.owneruserid is not null
      and p.tags is not null
    group by p.owneruserid, lower(trim(both '<>' from unnest(string_to_array(substring(p.tags, 2, greatest(length(p.tags)-2,0)), '><'))))
),
top_tag_per_user as (
    select distinct on (te.user_id)
        te.user_id,
        te.tagname,
        te.tag_posts,
        te.tag_avg_score
    from tag_expertise te
    order by te.user_id, te.tag_posts desc, te.tag_avg_score desc, te.tagname asc
),
duplicate_interactions as (
    select
        ru.user_id,
        count(distinct pl.postid) filter (where pl.linktypeid = 3 and p.owneruserid = ru.user_id) as dup_marked_against_own_questions,
        count(distinct pl.relatedpostid) filter (where pl.linktypeid = 3 and pr.owneruserid = ru.user_id) as own_questions_as_originals
    from recent_users ru
    left join postlinks pl
      on pl.linktypeid = 3
     and (pl.postid in (select id from posts where owneruserid = ru.user_id)
          or pl.relatedpostid in (select id from posts where owneruserid = ru.user_id))
    left join posts p on p.id = pl.postid
    left join posts pr on pr.id = pl.relatedpostid
    group by ru.user_id
),
edits_and_closures as (
    select
        ru.user_id,
        count(*) filter (where ph.posthistorytypeid in (4,5,6,7,8,9,24)) as edits_count,
        count(*) filter (where ph.posthistorytypeid = 10) as close_votes_events,
        count(*) filter (where ph.posthistorytypeid = 11) as reopen_events,
        count(*) filter (where ph.posthistorytypeid in (12,13)) as delete_restore_events
    from recent_users ru
    left join posthistory ph
      on ph.userid = ru.user_id
    group by ru.user_id
),
user_rank as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.signup_month,
        ua.q_count,
        ua.a_count,
        ua.active_days,
        ua.post_score,
        ua.views,
        uv.upvotes_cast,
        uv.downvotes_cast,
        uv.bounties_started,
        uv.bounty_amount_total,
        ub.badge_count,
        ub.gold_badges,
        ub.silver_badges,
        ub.bronze_badges,
        coalesce(qm.questions,0) as questions,
        coalesce(qm.avg_q_score,0) as avg_q_score,
        coalesce(qm.med_q_score,0) as med_q_score,
        coalesce(am.answers,0) as answers,
        coalesce(am.avg_a_score,0) as avg_a_score,
        coalesce(am.med_a_score,0) as med_a_score,
        coalesce(ca.comment_count,0) as comment_count,
        ca.avg_comment_score,
        tt.tagname as top_tag,
        tt.tag_posts as top_tag_posts,
        tt.tag_avg_score as top_tag_avg_score,
        di.dup_marked_against_own_questions,
        di.own_questions_as_originals,
        ec.edits_count,
        ec.close_votes_events,
        ec.reopen_events,
        ec.delete_restore_events,
        -- complex score with null logic and caps
        greatest(0,
            0.30 * coalesce(ua.post_score,0) +
            0.20 * coalesce(ua.views,0)::numeric / nullif(ua.active_days,0) +
            5.00 * coalesce(ub.gold_badges,0) +
            2.50 * coalesce(ub.silver_badges,0) +
            1.00 * coalesce(ub.bronze_badges,0) +
            0.50 * coalesce(ua.q_count,0) +
            0.75 * coalesce(ua.a_count,0) +
            0.40 * coalesce(ca.comment_count,0) +
            0.10 * coalesce(uv.upvotes_cast,0) -
            0.30 * coalesce(uv.downvotes_cast,0) +
            0.02 * coalesce(uv.bounty_amount_total,0) -
            1.00 * coalesce(di.dup_marked_against_own_questions,0) +
            0.50 * coalesce(di.own_questions_as_originals,0) +
            0.20 * coalesce(ec.edits_count,0)
        ) as activity_score_raw
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join user_votes uv on uv.user_id = ru.user_id
    left join user_badges ub on ub.user_id = ru.user_id
    left join question_metrics qm on qm.user_id = ru.user_id
    left join answer_metrics am on am.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join top_tag_per_user tt on tt.user_id = ru.user_id
    left join duplicate_interactions di on di.user_id = ru.user_id
    left join edits_and_closures ec on ec.user_id = ru.user_id
),
scored as (
    select
        ur.*,
        -- normalized score per month cohort using window functions
        (ur.activity_score_raw - avg(ur.activity_score_raw) over (partition by ur.signup_month))
        / nullif(stddev_pop(ur.activity_score_raw) over (partition by ur.signup_month), 0) as zscore_month,
        row_number() over (order by ur.activity_score_raw desc) as rn_global,
        dense_rank() over (partition by coalesce(ur.top_tag, '_none_') order by ur.activity_score_raw desc) as rank_within_top_tag
    from user_rank ur
),
cohort_percentiles as (
    select
        signup_month,
        percentile_disc(0.90) within group (order by activity_score_raw) as p90,
        percentile_disc(0.75) within group (order by activity_score_raw) as p75,
        percentile_disc(0.50) within group (order by activity_score_raw) as p50,
        percentile_disc(0.25) within group (order by activity_score_raw) as p25
    from user_rank
    group by signup_month
),
finalized as (
    select
        s.user_id,
        s.displayname,
        s.reputation,
        s.signup_month,
        s.q_count,
        s.a_count,
        s.active_days,
        s.post_score,
        s.views,
        s.upvotes_cast,
        s.downvotes_cast,
        s.bounties_started,
        s.bounty_amount_total,
        s.badge_count,
        s.gold_badges,
        s.silver_badges,
        s.bronze_badges,
        s.questions,
        s.avg_q_score,
        s.med_q_score,
        s.answers,
        s.avg_a_score,
        s.med_a_score,
        s.comment_count,
        s.avg_comment_score,
        s.top_tag,
        s.top_tag_posts,
        s.top_tag_avg_score,
        s.dup_marked_against_own_questions,
        s.own_questions_as_originals,
        s.edits_count,
        s.close_votes_events,
        s.reopen_events,
        s.delete_restore_events,
        s.activity_score_raw,
        s.zscore_month,
        s.rn_global,
        s.rank_within_top_tag,
        cp.p90, cp.p75, cp.p50, cp.p25,
        case
            when s.activity_score_raw >= cp.p90 then 'top 10%'
            when s.activity_score_raw >= cp.p75 then 'top 25%'
            when s.activity_score_raw >= cp.p50 then 'top 50%'
            when s.activity_score_raw >= cp.p25 then 'top 75%'
            else 'bottom 25%'
        end as cohort_band
    from scored s
    left join cohort_percentiles cp
      on cp.signup_month = s.signup_month
),
domain_rollup as (
    select
        ru.domain_host,
        count(*) as users_in_domain,
        avg(fr.activity_score_raw) as avg_domain_score,
        sum(fr.views) as total_domain_views,
        sum(fr.q_count + fr.a_count) as total_domain_posts
    from recent_users ru
    join finalized fr on fr.user_id = ru.user_id
    group by ru.domain_host
),
leaderboard as (
    select
        fr.*,
        dr.domain_host,
        dr.users_in_domain,
        dr.avg_domain_score,
        dr.total_domain_views,
        dr.total_domain_posts,
        rank() over (partition by dr.domain_host order by fr.activity_score_raw desc) as rank_in_domain
    from finalized fr
    left join recent_users ru on ru.user_id = fr.user_id
    left join domain_rollup dr on dr.domain_host = ru.domain_host
),
outliers as (
    select
        l.*,
        case
            when l.zscore_month is null then false
            when abs(l.zscore_month) >= 3 then true
            else false
        end as is_outlier
    from leaderboard l
)
select
    o.user_id,
    o.displayname,
    o.reputation,
    o.signup_month,
    o.top_tag,
    o.activity_score_raw,
    round(o.zscore_month::numeric, 3) as zscore_month,
    o.cohort_band,
    o.rn_global,
    o.rank_within_top_tag,
    o.domain_host,
    o.rank_in_domain,
    o.users_in_domain,
    round(o.avg_domain_score::numeric, 2) as avg_domain_score,
    o.q_count, o.a_count, o.active_days, o.views, o.badge_count,
    o.upvotes_cast, o.downvotes_cast, o.bounties_started, o.bounty_amount_total,
    o.questions, o.answers, o.comment_count,
    o.dup_marked_against_own_questions, o.own_questions_as_originals,
    o.edits_count, o.close_votes_events, o.reopen_events, o.delete_restore_events,
    o.is_outlier,
    -- Demonstrate null logic: flag users with missing top_tag but high activity
    case when o.top_tag is null and o.activity_score_raw > coalesce(o.p75, o.p50, 0) then 'no-tag-high-activity' else 'ok' end as tag_status
from outliers o
where (
        o.activity_score_raw > coalesce(o.p50, 0)
        or (o.is_outlier and o.activity_score_raw is not null)
      )
  and coalesce(o.reputation, 0) >= 1
  and not exists (
        select 1
        from posts p
        where p.owneruserid = o.user_id
          and p.posttypeid = 1
          and p.closeddate is not null
          and p.creationdate >= o.signup_month
          and p.score < 0
    )
order by o.activity_score_raw desc, o.rn_global
limit 250;