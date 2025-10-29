-- {"query": "928.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2738}
with recent_users as (
    select
        u.id as user_id,
        u.displayname,
        u.reputation,
        u.creationdate,
        u.location,
        coalesce(nullif(trim(u.websiteurl), ''), 'N/A') as websiteurl,
        row_number() over (order by u.creationdate desc, u.id desc) as rn
    from users u
    where u.creationdate >= (select max(creationdate) - interval '365 days' from users)
),
user_activity as (
    select
        u.user_id,
        count(distinct p.id) filter (where p.posttypeid in (1,2)) as total_posts,
        count(*) filter (where ph.posthistorytypeid in (10,11,12,13,14,15,19,20,35)) as mod_events,
        sum(case when v.votetypeid = 2 then 1 when v.votetypeid = 3 then -1 else 0 end) as net_votes,
        sum(case when v.votetypeid = 5 then 1 else 0 end) as favorites,
        count(distinct c.id) as comments_made
    from recent_users u
    left join posts p on p.owneruserid = u.user_id
    left join votes v on v.postid = p.id
    left join posthistory ph on ph.postid = p.id
    left join comments c on c.userid = u.user_id
    group by u.user_id
),
user_badges as (
    select
        b.userid as user_id,
        count(*) as badge_count,
        count(*) filter (where b.class = 1) as gold_count,
        count(*) filter (where b.class = 2) as silver_count,
        count(*) filter (where b.class = 3) as bronze_count,
        min(b.date) as first_badge_date,
        max(b.date) as last_badge_date
    from badges b
    group by b.userid
),
question_stats as (
    select
        p.owneruserid as user_id,
        count(*) as questions,
        sum(coalesce(p.viewcount,0)) as total_views,
        avg(nullif(p.viewcount,0)) as avg_nonzero_views,
        sum(case when p.acceptedanswerid is not null then 1 else 0 end) as accepted_count,
        sum(coalesce(p.answercount,0)) as total_answers_rcvd,
        count(*) filter (where p.closeddate is not null) as closed_q
    from posts p
    where p.posttypeid = 1
    group by p.owneruserid
),
answer_stats as (
    select
        p.owneruserid as user_id,
        count(*) as answers,
        sum(coalesce(p.score,0)) as answer_score_sum,
        avg(p.score) as answer_score_avg,
        count(*) filter (
            where exists (
                select 1
                from posts q
                where q.id = p.parentid
                  and q.acceptedanswerid = p.id
            )
        ) as accepted_as_best
    from posts p
    where p.posttypeid = 2
    group by p.owneruserid
),
tag_exposure as (
    select
        q.owneruserid as user_id,
        unnest(string_to_array(substring(q.tags, 2, greatest(length(q.tags)-2,0)), '><')) as tag_name
    from posts q
    where q.posttypeid = 1
      and q.tags is not null
),
top_tags as (
    select
        te.user_id,
        t.tag_name,
        count(*) as tag_uses,
        row_number() over (partition by te.user_id order by count(*) desc, t.tag_name) as tag_rank
    from tag_exposure te
    join lateral (select te.tag_name) t on true
    group by te.user_id, t.tag_name
),
post_link_graph as (
    select
        p.owneruserid as user_id,
        count(*) filter (where pl.linktypeid = 1) as linked_out,
        count(*) filter (where pl.linktypeid = 3) as marked_duplicate,
        count(distinct pl.relatedpostid) as distinct_related
    from postlinks pl
    join posts p on p.id = pl.postid
    group by p.owneruserid
),
comment_sentiment as (
    select
        c.userid as user_id,
        avg(length(c.text)) as avg_comment_len,
        sum(case when position('thanks' in lower(c.text)) > 0 then 1 else 0 end) as thanks_mentions,
        sum(case when position('?' in c.text) > 0 then 1 else 0 end) as question_marks
    from comments c
    group by c.userid
),
user_windows as (
    select
        ru.*,
        lag(ru.creationdate) over (order by ru.creationdate) as prev_user_created,
        lead(ru.creationdate) over (order by ru.creationdate) as next_user_created
    from recent_users ru
),
reputation_momentum as (
    select
        u.user_id,
        u.reputation,
        coalesce(u.reputation - lag(u.reputation) over (order by u.creationdate), 0) as delta_from_prev_signup_order
    from user_windows u
),
activity_scores as (
    select
        ua.user_id,
        0.4*coalesce(ua.total_posts,0)
        + 0.3*coalesce(ua.net_votes,0)
        + 0.2*coalesce(us.badge_count,0)
        + 0.1*coalesce(qs.total_views,0)/greatest(coalesce(qs.questions,1),1)
        + 0.15*coalesce(ans.answers,0)
        - 0.25*coalesce(qs.closed_q,0)
        + 0.05*coalesce(plg.linked_out,0)
        - 0.1*coalesce(plg.marked_duplicate,0)
        + 0.02*coalesce(cs.thanks_mentions,0)
        as activity_score
    from user_activity ua
    left join user_badges us on us.user_id = ua.user_id
    left join question_stats qs on qs.user_id = ua.user_id
    left join answer_stats ans on ans.user_id = ua.user_id
    left join post_link_graph plg on plg.user_id = ua.user_id
    left join comment_sentiment cs on cs.user_id = ua.user_id
),
dupe_pairs as (
    select
        q.owneruserid as user_id,
        count(*) as dupe_closed_count
    from posthistory ph
    join posts q on q.id = ph.postid and q.posttypeid = 1
    where ph.posthistorytypeid = 10
      and ((ph.comment is not null and ph.comment ~ '^\s*(1|101)\s*$') or lower(coalesce(ph.text,'')) like '%duplicate%')
    group by q.owneruserid
),
recent_hotness as (
    select
        p.owneruserid as user_id,
        count(*) filter (where ph.posthistorytypeid = 52) as became_hot,
        count(*) filter (where ph.posthistorytypeid = 53) as removed_hot
    from posts p
    left join posthistory ph on ph.postid = p.id
    where p.creationdate >= (select max(creationdate) - interval '180 days' from posts)
    group by p.owneruserid
),
ranked_users as (
    select
        uw.user_id,
        uw.displayname,
        uw.location,
        uw.websiteurl,
        uw.creationdate,
        ua.total_posts,
        ua.mod_events,
        ua.net_votes,
        ua.favorites,
        ua.comments_made,
        us.badge_count,
        us.gold_count,
        us.silver_count,
        us.bronze_count,
        qs.questions,
        qs.total_views,
        qs.avg_nonzero_views,
        qs.accepted_count,
        qs.total_answers_rcvd,
        ans.answers,
        ans.answer_score_sum,
        ans.answer_score_avg,
        ans.accepted_as_best,
        plg.linked_out,
        plg.marked_duplicate,
        plg.distinct_related,
        cs.avg_comment_len,
        cs.thanks_mentions,
        cs.question_marks,
        rm.reputation,
        rm.delta_from_prev_signup_order,
        ap.activity_score,
        dp.dupe_closed_count,
        rh.became_hot,
        rh.removed_hot,
        coalesce(tt.tag_name, '(none)') as top_tag,
        coalesce(tt.tag_uses, 0) as top_tag_uses,
        row_number() over (
            order by ap.activity_score desc nulls last,
                     ua.net_votes desc nulls last,
                     us.badge_count desc nulls last,
                     uw.creationdate desc
        ) as activity_rank
    from user_windows uw
    left join user_activity ua on ua.user_id = uw.user_id
    left join user_badges us on us.user_id = uw.user_id
    left join question_stats qs on qs.user_id = uw.user_id
    left join answer_stats ans on ans.user_id = uw.user_id
    left join post_link_graph plg on plg.user_id = uw.user_id
    left join comment_sentiment cs on cs.user_id = uw.user_id
    left join reputation_momentum rm on rm.user_id = uw.user_id
    left join activity_scores ap on ap.user_id = uw.user_id
    left join dupe_pairs dp on dp.user_id = uw.user_id
    left join recent_hotness rh on rh.user_id = uw.user_id
    left join lateral (
        select tag_name, tag_uses
        from top_tags t
        where t.user_id = uw.user_id and t.tag_rank <= 1
        order by t.tag_rank
        limit 1
    ) tt on true
),
activity_percentiles as (
    select
        max(case when pct = 0.9 then val end) as p90,
        max(case when pct = 0.7 then val end) as p70,
        max(case when pct = 0.4 then val end) as p40
    from (
        select
            activity_score as val,
            percent_rank() over (order by activity_score) as pr
        from activity_scores
    ) ap
    cross join lateral (
        select
            (case when pr >= 0.9 then 0.9 when pr >= 0.7 then 0.7 when pr >= 0.4 then 0.4 else null end) as pct
    ) pctmap
    where pct is not null
),
banded as (
    select
        r.*,
        ntile(10) over (order by coalesce(r.activity_score,0) desc) as decile,
        case
            when coalesce(r.activity_score,0) >= ap.p90 then 'A'
            when coalesce(r.activity_score,0) >= ap.p70 then 'B'
            when coalesce(r.activity_score,0) >= ap.p40 then 'C'
            else 'D'
        end as grade
    from ranked_users r
    cross join activity_percentiles ap
),
null_logic_checks as (
    select
        b.*,
        case when b.top_tag is null or b.top_tag = '(none)' then 1 else 0 end as no_top_tag_flag,
        coalesce(b.questions,0) + coalesce(b.answers,0) as total_q_a,
        case when coalesce(b.avg_nonzero_views,0) = 0 and coalesce(b.total_views,0) > 0 then 1 else 0 end as has_zero_avg_nonzero_views
    from banded b
)
select
    nl.activity_rank,
    nl.user_id,
    coalesce(nl.displayname, ('user#' || cast(nl.user_id as varchar))) as displayname,
    nullif(trim(nl.location), '') as location,
    nl.websiteurl,
    nl.creationdate,
    nl.reputation,
    nl.delta_from_prev_signup_order,
    nl.grade,
    nl.decile,
    nl.activity_score,
    nl.total_posts,
    nl.net_votes,
    nl.badge_count,
    nl.gold_count,
    nl.silver_count,
    nl.bronze_count,
    nl.questions,
    nl.answers,
    nl.accepted_count,
    nl.accepted_as_best,
    nl.total_views,
    round(coalesce(nl.avg_nonzero_views,0)::double precision::numeric,2) as avg_nonzero_views,
    nl.total_answers_rcvd,
    nl.mod_events,
    nl.comments_made,
    nl.avg_comment_len,
    nl.thanks_mentions,
    nl.question_marks,
    nl.linked_out,
    nl.marked_duplicate,
    nl.distinct_related,
    nl.dupe_closed_count,
    nl.became_hot,
    nl.removed_hot,
    nl.top_tag,
    nl.top_tag_uses,
    nl.no_top_tag_flag,
    nl.total_q_a,
    nl.has_zero_avg_nonzero_views
from null_logic_checks nl
where (
    nl.activity_score > 0
    or (nl.net_votes > 0 and nl.badge_count is not null)
    or (nl.answers > 0 and nl.accepted_as_best > 0)
)
and (
    nl.location is not null
    or nl.websiteurl <> 'N/A'
    or nl.top_tag not in ('(none)')
)
order by nl.activity_rank
limit 200;