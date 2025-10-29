-- {"query": "647.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3657} 
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'n/a') as website_norm,
        date_trunc('month', u.creationdate) as signup_month
    from users u
    where u.creationdate >= (select max(creationdate) - interval '730 days' from users)
),
user_activity as (
    select
        p.owneruserid as user_id,
        count(*) filter (where p.posttypeid = 1) as q_count,
        count(*) filter (where p.posttypeid = 2) as a_count,
        sum(coalesce(p.score,0)) as post_score_sum,
        sum(coalesce(p.viewcount,0)) filter (where p.posttypeid = 1) as q_views_sum,
        max(p.lastactivitydate) as last_post_activity
    from posts p
    where p.owneruserid is not null
    group by p.owneruserid
),
comment_activity as (
    select
        c.userid as user_id,
        count(*) as comment_count,
        sum(coalesce(c.score,0)) as comment_score_sum,
        max(c.creationdate) as last_comment_date
    from comments c
    where c.userid is not null
    group by c.userid
),
badge_rollup as (
    select
        b.userid as user_id,
        count(*) as total_badges,
        count(*) filter (where b.class = 1) as gold_badges,
        count(*) filter (where b.class = 2) as silver_badges,
        count(*) filter (where b.class = 3) as bronze_badges,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
votes_rollup as (
    select
        v.userid as user_id,
        count(*) filter (where v.votetypeid = 2) as upvotes_cast,
        count(*) filter (where v.votetypeid = 3) as downvotes_cast,
        count(*) filter (where v.votetypeid = 5) as favorites_cast,
        max(v.creationdate) as last_vote_date
    from votes v
    where v.userid is not null
    group by v.userid
),
question_engagement as (
    select
        p.owneruserid as user_id,
        count(*) as questions_total,
        avg(p.score) as avg_q_score,
        percentile_disc(0.5) within group (order by p.viewcount) as median_q_views,
        count(*) filter (where p.acceptedanswerid is not null) as accepted_q,
        avg((select count(*) from posts a where a.parentid = p.id and a.posttypeid = 2)) as avg_answers_per_q
    from posts p
    where p.posttypeid = 1 and p.owneruserid is not null
    group by p.owneruserid
),
answer_engagement as (
    select
        p.owneruserid as user_id,
        count(*) as answers_total,
        avg(p.score) as avg_a_score,
        count(*) filter (where exists (
            select 1
            from posts q
            where q.id = p.parentid
              and q.acceptedanswerid = p.id
        )) as accepted_answers_by_user
    from posts p
    where p.posttypeid = 2 and p.owneruserid is not null
    group by p.owneruserid
),
tag_expertise as (
    select
        a.owneruserid as user_id,
        lower(trim(regexp_replace(t.tag, '\s+', ' ', 'g'))) as tag_norm,
        count(*) as answers_on_tag,
        sum(a.score) as score_on_tag,
        row_number() over (partition by a.owneruserid order by count(*) desc, sum(a.score) desc, lower(trim(regexp_replace(t.tag, '\s+', ' ', 'g'))) asc) as rn
    from posts a
    join posts q on q.id = a.parentid and a.posttypeid = 2 and q.posttypeid = 1
    cross join lateral unnest(string_to_array(substring(q.tags, 2, length(q.tags)-2), '><')) as t(tag)
    where a.owneruserid is not null and q.tags is not null
    group by a.owneruserid, lower(trim(regexp_replace(t.tag, '\s+', ' ', 'g')))
),
top_tag as (
    select
        user_id,
        tag_norm as top_tag,
        answers_on_tag,
        score_on_tag
    from tag_expertise
    where rn = 1
),
postlinks_stats as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 3) as duplicate_links,
        count(*) filter (where pl.linktypeid = 1) as related_links
    from posts p
    left join postlinks pl
      on pl.postid = p.id
    where p.owneruserid is not null
    group by p.owneruserid
),
closures as (
    select
        ph.userid as moderator_user_id,
        count(*) as closes_made,
        min(ph.creationdate) as first_close,
        max(ph.creationdate) as last_close
    from posthistory ph
    where ph.posthistorytypeid = 10
      and ph.userid is not null
    group by ph.userid
),
user_windows as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.signup_month,
        ua.q_count,
        ua.a_count,
        ua.post_score_sum,
        ca.comment_count,
        br.total_badges,
        br.gold_badges,
        br.silver_badges,
        br.bronze_badges,
        vr.upvotes_cast,
        vr.downvotes_cast,
        qe.questions_total,
        qe.avg_q_score,
        qe.median_q_views,
        qe.accepted_q,
        ae.answers_total,
        ae.avg_a_score,
        ae.accepted_answers_by_user,
        tt.top_tag,
        tt.answers_on_tag,
        tt.score_on_tag,
        pls.duplicate_links,
        pls.related_links,
        greatest(coalesce(ua.last_post_activity, timestamp 'epoch'),
                 coalesce(ca.last_comment_date, timestamp 'epoch'),
                 coalesce(br.last_badge_date, timestamp 'epoch'),
                 coalesce(vr.last_vote_date, timestamp 'epoch')) as last_activity_at
    from recent_users ru
    left join user_activity ua on ua.user_id = ru.user_id
    left join comment_activity ca on ca.user_id = ru.user_id
    left join badge_rollup br on br.user_id = ru.user_id
    left join votes_rollup vr on vr.user_id = ru.user_id
    left join question_engagement qe on qe.user_id = ru.user_id
    left join answer_engagement ae on ae.user_id = ru.user_id
    left join top_tag tt on tt.user_id = ru.user_id
    left join postlinks_stats pls on pls.user_id = ru.user_id
),
ranked_users as (
    select
        uw.*,
        coalesce(uw.a_count,0) + coalesce(uw.q_count,0) + coalesce(uw.comment_count,0) as total_contribs,
        coalesce(uw.post_score_sum,0) + coalesce(uw.upvotes_cast,0) - coalesce(uw.downvotes_cast,0) as net_karma,
        case
            when coalesce(uw.answers_total,0) > 0 then round(100.0 * coalesce(uw.accepted_answers_by_user,0)::numeric / nullif(uw.answers_total,0), 2)
            else null
        end as accept_rate_pct,
        dense_rank() over (order by coalesce(uw.reputation,0) desc, coalesce(uw.post_score_sum,0) desc, coalesce(uw.a_count,0) desc) as rep_rank,
        ntile(4) over (order by coalesce(uw.reputation,0) desc) as rep_quartile,
        row_number() over (partition by uw.signup_month order by coalesce(uw.post_score_sum,0) desc, coalesce(uw.a_count,0) desc, uw.user_id) as month_top_idx,
        lag(uw.reputation) over (order by uw.user_id) as prev_rep_by_id
    from user_windows uw
),
anomalies as (
    select
        ru.user_id,
        case
            when ru.total_contribs = 0 and ru.reputation > 1000 then 'high-rep-low-activity'
            when ru.total_contribs > 1000 and coalesce(ru.net_karma,0) < 0 then 'high-activity-negative-karma'
            when ru.accept_rate_pct is not null and ru.accept_rate_pct < 10 then 'low-accept-rate'
            when ru.rep_quartile = 1 and coalesce(ru.avg_q_score,0) < 0 then 'top-rep-negative-qscore'
            else null
        end as anomaly_type
    from ranked_users ru
),
activity_buckets as (
    select
        ru.user_id,
        case
            when coalesce(ru.total_contribs,0) >= 1000 then 'ultra'
            when coalesce(ru.total_contribs,0) >= 200 then 'high'
            when coalesce(ru.total_contribs,0) >= 50 then 'medium'
            when coalesce(ru.total_contribs,0) > 0 then 'low'
            else 'none'
        end as activity_band
    from ranked_users ru
),
combined as (
    select
        ru.user_id,
        ru.displayname,
        ru.reputation,
        ru.rep_rank,
        ru.rep_quartile,
        ru.signup_month,
        ru.total_contribs,
        ru.net_karma,
        ru.accept_rate_pct,
        ru.q_count,
        ru.a_count,
        ru.comment_count,
        ru.questions_total,
        ru.answers_total,
        ru.avg_q_score,
        ru.avg_a_score,
        ru.median_q_views,
        ru.accepted_q,
        ru.accepted_answers_by_user,
        coalesce(ru.top_tag, '(none)') as top_tag,
        ru.answers_on_tag,
        ru.score_on_tag,
        ru.duplicate_links,
        ru.related_links,
        ru.last_activity_at,
        ab.activity_band,
        an.anomaly_type
    from ranked_users ru
    left join activity_buckets ab on ab.user_id = ru.user_id
    left join anomalies an on an.user_id = ru.user_id
),
month_aggregates as (
    select
        signup_month,
        count(*) as users_in_month,
        avg(reputation) as avg_rep,
        percentile_disc(0.9) within group (order by reputation) as p90_rep,
        avg(total_contribs) as avg_contribs,
        count(*) filter (where anomaly_type is not null) as anomalies_in_month
    from combined
    group by signup_month
),
band_aggregates as (
    select
        activity_band,
        count(*) as users_in_band,
        avg(net_karma) as avg_net_karma,
        avg(coalesce(accept_rate_pct,0)) as avg_accept_rate_pct,
        count(*) filter (where anomaly_type is not null) as anomalies_in_band
    from combined
    group by activity_band
),
cross_mix as (
    select
        c.activity_band,
        date_trunc('quarter', c.signup_month) as signup_quarter,
        count(*) as users,
        avg(c.reputation) as avg_rep,
        sum(case when c.top_tag like '%sql%' then 1 else 0 end) as sql_top_tag_users
    from combined c
    group by c.activity_band, date_trunc('quarter', c.signup_month)
),
final_set as (
    select
        'USER_DETAIL' as section,
        c.user_id,
        c.displayname,
        c.reputation,
        c.rep_rank,
        c.rep_quartile,
        c.signup_month,
        c.total_contribs,
        c.net_karma,
        c.accept_rate_pct,
        c.q_count,
        c.a_count,
        c.comment_count,
        c.questions_total,
        c.answers_total,
        c.avg_q_score,
        c.avg_a_score,
        c.median_q_views,
        c.accepted_q,
        c.accepted_answers_by_user,
        c.top_tag,
        c.answers_on_tag,
        c.score_on_tag,
        c.duplicate_links,
        c.related_links,
        c.last_activity_at,
        c.activity_band,
        c.anomaly_type
    from combined c
    where (c.avg_a_score is not null or c.avg_q_score is not null)
  union all
    select
        'MONTH_AGG' as section,
        null::int as user_id,
        to_char(ma.signup_month, 'YYYY-MM') as displayname,
        ma.avg_rep::int as reputation,
        null::bigint as rep_rank,
        null::int as rep_quartile,
        ma.signup_month,
        ma.users_in_month as total_contribs,
        ma.p90_rep::int as net_karma,
        null::numeric as accept_rate_pct,
        null::bigint as q_count,
        null::bigint as a_count,
        ma.anomalies_in_month::bigint as comment_count,
        null::bigint as questions_total,
        null::bigint as answers_total,
        null::numeric as avg_q_score,
        null::numeric as avg_a_score,
        null::int as median_q_views,
        null::bigint as accepted_q,
        null::bigint as accepted_answers_by_user,
        null::varchar as top_tag,
        null::bigint as answers_on_tag,
        null::bigint as score_on_tag,
        null::bigint as duplicate_links,
        null::bigint as related_links,
        null::timestamp as last_activity_at,
        null::varchar as activity_band,
        null::varchar as anomaly_type
    from month_aggregates ma
  union all
    select
        'BAND_AGG' as section,
        null::int as user_id,
        ba.activity_band as displayname,
        ba.avg_net_karma::int as reputation,
        null::bigint as rep_rank,
        null::int as rep_quartile,
        null::timestamp as signup_month,
        ba.users_in_band as total_contribs,
        (ba.avg_accept_rate_pct)::int as net_karma,
        null::numeric as accept_rate_pct,
        null::bigint as q_count,
        null::bigint as a_count,
        ba.anomalies_in_band::bigint as comment_count,
        null::bigint as questions_total,
        null::bigint as answers_total,
        null::numeric as avg_q_score,
        null::numeric as avg_a_score,
        null::int as median_q_views,
        null::bigint as accepted_q,
        null::bigint as accepted_answers_by_user,
        null::varchar as top_tag,
        null::bigint as answers_on_tag,
        null::bigint as score_on_tag,
        null::bigint as duplicate_links,
        null::bigint as related_links,
        null::timestamp as last_activity_at,
        ba.activity_band,
        null::varchar as anomaly_type
    from band_aggregates ba
  union all
    select
        'CROSS_MIX' as section,
        null::int as user_id,
        cm.activity_band || ' / ' || to_char(cm.signup_quarter, '"Q"Q YYYY') as displayname,
        cm.avg_rep::int as reputation,
        null::bigint as rep_rank,
        null::int as rep_quartile,
        cm.signup_quarter as signup_month,
        cm.users as total_contribs,
        cm.sql_top_tag_users as net_karma,
        null::numeric as accept_rate_pct,
        null::bigint as q_count,
        null::bigint as a_count,
        null::bigint as comment_count,
        null::bigint as questions_total,
        null::bigint as answers_total,
        null::numeric as avg_q_score,
        null::numeric as avg_a_score,
        null::int as median_q_views,
        null::bigint as accepted_q,
        null::bigint as accepted_answers_by_user,
        null::varchar as top_tag,
        null::bigint as answers_on_tag,
        null::bigint as score_on_tag,
        null::bigint as duplicate_links,
        null::bigint as related_links,
        null::timestamp as last_activity_at,
        cm.activity_band,
        null::varchar as anomaly_type
    from cross_mix cm
)
select *
from final_set
where (
        section <> 'USER_DETAIL'
        or (
            net_karma is not null
            and (
                anomaly_type is not null
                or (rep_quartile = 1 and coalesce(accept_rate_pct,50) >= 25)
            )
        )
      )
order by section, coalesce(rep_rank, 999999), signup_month nulls last, displayname, user_id nulls last
limit 500;